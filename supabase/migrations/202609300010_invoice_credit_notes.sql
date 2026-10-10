-- Immutable credit notes reduce an issued invoice's receivable without
-- rewriting its original line items or invoice total.
alter table public.invoices add column credit_total numeric(14,2) not null default 0
  check (credit_total >= 0 and credit_total <= total);

create table public.invoice_credits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  credit_number text not null check (length(btrim(credit_number)) between 2 and 40),
  amount numeric(14,2) not null check (amount > 0),
  reason text not null check (length(btrim(reason)) between 2 and 240),
  issued_at timestamptz not null default now(),
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (organization_id, invoice_id)
    references public.invoices(organization_id, id) on delete cascade,
  unique (organization_id, credit_number)
);

create index invoice_credits_invoice_idx on public.invoice_credits (organization_id, invoice_id, issued_at desc);
alter table public.invoice_credits enable row level security;
revoke all on public.invoice_credits from anon, authenticated;
grant select on public.invoice_credits to authenticated;
create policy invoice_credits_read on public.invoice_credits for select to authenticated
  using (public.is_org_member(organization_id));
create trigger audit_change after insert on public.invoice_credits
  for each row execute function public.write_audit_log();

create or replace function public.refresh_invoice_payment_state(target_org uuid, target_invoice uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare paid_total numeric(14,2); credited_total numeric(14,2); last_paid_at timestamptz;
begin
  select coalesce(sum(p.amount), 0), max(p.paid_at)
    into paid_total, last_paid_at from public.invoice_payments p
    where p.organization_id = target_org and p.invoice_id = target_invoice;
  select coalesce(sum(c.amount), 0) into credited_total from public.invoice_credits c
    where c.organization_id = target_org and c.invoice_id = target_invoice;
  perform set_config('letsgo.invoice_payment_sync', 'on', true);
  update public.invoices i set amount_paid = paid_total,
      credit_total = credited_total,
      paid_at = case when paid_total >= i.total - credited_total then last_paid_at else null end,
      status = case
        when i.status = 'void' then 'void'::public.invoice_status
        when paid_total >= i.total - credited_total then 'paid'::public.invoice_status
        when paid_total > 0 then 'partially_paid'::public.invoice_status
        when i.status = 'draft' then 'draft'::public.invoice_status
        when i.due_date < current_date then 'overdue'::public.invoice_status
        else 'sent'::public.invoice_status end
    where i.organization_id = target_org and i.id = target_invoice;
  perform set_config('letsgo.invoice_payment_sync', 'off', true);
end;
$$;

create or replace function public.sync_invoice_credit_state()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_invoice_payment_state(new.organization_id, new.invoice_id);
  return new;
end;
$$;
create trigger sync_invoice_credit_state after insert on public.invoice_credits
  for each row execute function public.sync_invoice_credit_state();

create or replace function public.validate_new_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare collectible numeric(14,2); invoice_currency char(3); invoice_current_status public.invoice_status; existing_amount numeric(14,2);
begin
  if not public.has_org_permission(new.organization_id, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.total - i.credit_total, i.currency, i.status into collectible, invoice_currency, invoice_current_status
    from public.invoices i where i.organization_id = new.organization_id and i.id = new.invoice_id for update;
  if collectible is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_current_status in ('draft', 'void') then raise exception 'Payments require an issued invoice'; end if;
  select coalesce(sum(p.amount), 0) into existing_amount from public.invoice_payments p
    where p.organization_id = new.organization_id and p.invoice_id = new.invoice_id;
  if invoice_currency <> new.currency then raise exception 'Payment currency must match invoice currency'; end if;
  if new.amount + existing_amount > collectible then raise exception 'Payment exceeds remaining invoice balance'; end if;
  return new;
end;
$$;

create or replace function public.validate_updated_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare collectible numeric(14,2); invoice_currency char(3); invoice_current_status public.invoice_status; existing_amount numeric(14,2);
begin
  if not public.has_org_permission(new.organization_id, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.total - i.credit_total, i.currency, i.status into collectible, invoice_currency, invoice_current_status
    from public.invoices i where i.organization_id = new.organization_id and i.id = new.invoice_id for update;
  if collectible is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_current_status in ('draft', 'void') then raise exception 'Payments require an issued invoice'; end if;
  select coalesce(sum(p.amount), 0) into existing_amount from public.invoice_payments p
    where p.organization_id = new.organization_id and p.invoice_id = new.invoice_id and p.id <> old.id;
  if invoice_currency <> new.currency then raise exception 'Payment currency must match invoice currency'; end if;
  if new.amount + existing_amount > collectible then raise exception 'Payment exceeds remaining invoice balance'; end if;
  return new;
end;
$$;

create or replace function public.create_invoice_credit(
  target_org uuid, target_invoice uuid, new_credit_number text, credit_amount numeric, credit_reason text, actor_id uuid
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare invoice_row public.invoices%rowtype; new_credit_id uuid;
begin
  if auth.uid() is null or actor_id is distinct from auth.uid()
    or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required';
  end if;
  if length(btrim(new_credit_number)) not between 2 and 40
    or length(btrim(credit_reason)) not between 2 and 240 or credit_amount <= 0 then
    raise exception 'Invalid credit note details';
  end if;
  select * into invoice_row from public.invoices i
    where i.organization_id = target_org and i.id = target_invoice for update;
  if invoice_row.id is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_row.status in ('draft', 'void') then raise exception 'Credit notes require an issued invoice'; end if;
  if credit_amount > invoice_row.total - invoice_row.amount_paid - invoice_row.credit_total then
    raise exception 'Credit note exceeds the outstanding balance';
  end if;
  insert into public.invoice_credits (organization_id, invoice_id, credit_number, amount, reason, recorded_by)
  values (target_org, target_invoice, btrim(new_credit_number), credit_amount, btrim(credit_reason), actor_id)
  returning id into new_credit_id;
  return new_credit_id;
end;
$$;

-- Credit balance is reflected in founder receivables and aging reports.
create or replace function public.finance_summary(target_org uuid)
returns table (currency char(3), monthly_revenue numeric, receivables numeric, monthly_expenses numeric, estimated_profit numeric)
language sql stable security definer set search_path = '' as $$
  with settings as (
    select o.timezone from public.organizations o where o.id = target_org and public.is_org_member(target_org)
  ), currencies as (
    select o.currency as code from public.organizations o where o.id = target_org
    union select i.currency as code from public.invoices i where i.organization_id = target_org
    union select e.currency as code from public.expenses e where e.organization_id = target_org
  ), totals as (
    select c.code,
      coalesce((select sum(p.amount) from public.invoice_payments p join public.invoices i
        on i.organization_id = p.organization_id and i.id = p.invoice_id
        where p.organization_id = target_org and i.currency = c.code
          and p.paid_at >= (date_trunc('month', now() at time zone s.timezone) at time zone s.timezone) and p.paid_at < now()), 0) as revenue,
      coalesce((select sum(i.total - i.credit_total - i.amount_paid) from public.invoices i
        where i.organization_id = target_org and i.currency = c.code
          and i.status not in ('draft', 'void') and i.total - i.credit_total > i.amount_paid), 0) as outstanding,
      coalesce((select sum(e.amount) from public.expenses e where e.organization_id = target_org and e.currency = c.code
        and e.spent_on >= date_trunc('month', now() at time zone s.timezone)::date
        and e.spent_on <= (now() at time zone s.timezone)::date), 0) as expenses
    from currencies c cross join settings s
  ) select code, revenue, outstanding, expenses, revenue - expenses from totals;
$$;

create or replace function public.receivables_aging(target_org uuid)
returns table (currency char(3), bucket text, invoice_count bigint, amount numeric)
language sql stable security definer set search_path = '' as $$
  with settings as (
    select (now() at time zone o.timezone)::date as local_today from public.organizations o
    where o.id = target_org and public.is_org_member(target_org)
  ), open_invoices as (
    select i.currency, i.due_date, (i.total - i.credit_total - i.amount_paid) as balance, s.local_today
    from public.invoices i cross join settings s where i.organization_id = target_org
      and i.status not in ('draft', 'void') and i.total - i.credit_total > i.amount_paid
  ), aged as (
    select currency, case when due_date is null then 'no_due_date' when due_date >= local_today then 'not_due'
      when local_today - due_date <= 30 then '1_30' when local_today - due_date <= 60 then '31_60' else '61_plus' end as bucket, balance
    from open_invoices
  ) select currency, bucket, count(*)::bigint, sum(balance) from aged group by currency, bucket
    order by currency, case bucket when 'not_due' then 1 when '1_30' then 2 when '31_60' then 3 when '61_plus' then 4 else 5 end;
$$;

revoke all on function public.sync_invoice_credit_state() from public, anon, authenticated;
revoke all on function public.create_invoice_credit(uuid, uuid, text, numeric, text, uuid) from public, anon;
grant execute on function public.create_invoice_credit(uuid, uuid, text, numeric, text, uuid) to authenticated;
revoke all on function public.finance_summary(uuid) from public, anon;
revoke all on function public.receivables_aging(uuid) from public, anon;
grant execute on function public.finance_summary(uuid) to authenticated;
grant execute on function public.receivables_aging(uuid) to authenticated;
