-- Refunds are immutable cash movements linked to their original payment.
alter table public.invoice_payments
  add constraint invoice_payments_org_invoice_id_unique unique (organization_id, invoice_id, id);

create table public.invoice_refunds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  payment_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  reason text not null check (length(btrim(reason)) between 2 and 240),
  refunded_at timestamptz not null default now(),
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (organization_id, invoice_id) references public.invoices(organization_id, id) on delete cascade,
  foreign key (organization_id, invoice_id, payment_id)
    references public.invoice_payments(organization_id, invoice_id, id) on delete cascade
);
create index invoice_refunds_invoice_idx on public.invoice_refunds (organization_id, invoice_id, refunded_at desc);
alter table public.invoice_refunds enable row level security;
revoke all on public.invoice_refunds from anon, authenticated;
grant select on public.invoice_refunds to authenticated;
create policy invoice_refunds_read on public.invoice_refunds for select to authenticated
  using (public.is_org_member(organization_id));
create trigger audit_change after insert on public.invoice_refunds
  for each row execute function public.write_audit_log();

create or replace function public.create_invoice_refund(
  target_org uuid, target_invoice uuid, target_payment uuid, refund_amount numeric, refund_reason text, actor_id uuid
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare payment_row public.invoice_payments%rowtype; already_refunded numeric(14,2); new_refund_id uuid;
begin
  if auth.uid() is null or actor_id is distinct from auth.uid()
    or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required';
  end if;
  if length(btrim(refund_reason)) not between 2 and 240 or refund_amount <= 0 then
    raise exception 'Invalid refund details';
  end if;
  -- Serialize against concurrent refunds for the same original payment.
  select * into payment_row from public.invoice_payments p
    where p.organization_id = target_org and p.invoice_id = target_invoice and p.id = target_payment for update;
  if payment_row.id is null then raise exception 'Payment not found in this organization'; end if;
  select coalesce(sum(r.amount), 0) into already_refunded from public.invoice_refunds r
    where r.organization_id = target_org and r.payment_id = target_payment;
  if refund_amount > payment_row.amount - already_refunded then raise exception 'Refund exceeds the unrefunded payment'; end if;
  insert into public.invoice_refunds (organization_id, invoice_id, payment_id, amount, reason, recorded_by)
  values (target_org, target_invoice, target_payment, refund_amount, btrim(refund_reason), actor_id)
  returning id into new_refund_id;
  return new_refund_id;
end;
$$;

create or replace function public.refresh_invoice_payment_state(target_org uuid, target_invoice uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare paid_total numeric(14,2); credited_total numeric(14,2); last_paid_at timestamptz;
begin
  select coalesce((select sum(p.amount) from public.invoice_payments p where p.organization_id = target_org and p.invoice_id = target_invoice), 0)
    - coalesce((select sum(r.amount) from public.invoice_refunds r where r.organization_id = target_org and r.invoice_id = target_invoice), 0),
    (select max(p.paid_at) from public.invoice_payments p where p.organization_id = target_org and p.invoice_id = target_invoice)
    into paid_total, last_paid_at;
  select coalesce(sum(c.amount), 0) into credited_total from public.invoice_credits c
    where c.organization_id = target_org and c.invoice_id = target_invoice;
  perform set_config('letsgo.invoice_payment_sync', 'on', true);
  update public.invoices i set amount_paid = paid_total,
      credit_total = credited_total,
      paid_at = case when paid_total >= i.total - credited_total then last_paid_at else null end,
      status = case when i.status = 'void' then 'void'::public.invoice_status
        when paid_total >= i.total - credited_total then 'paid'::public.invoice_status
        when paid_total > 0 then 'partially_paid'::public.invoice_status
        when i.status = 'draft' then 'draft'::public.invoice_status
        when i.due_date < current_date then 'overdue'::public.invoice_status
        else 'sent'::public.invoice_status end
    where i.organization_id = target_org and i.id = target_invoice;
  perform set_config('letsgo.invoice_payment_sync', 'off', true);
end;
$$;

create or replace function public.sync_invoice_refund_state()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_invoice_payment_state(new.organization_id, new.invoice_id);
  return new;
end;
$$;
create trigger sync_invoice_refund_state after insert on public.invoice_refunds
  for each row execute function public.sync_invoice_refund_state();

create or replace function public.validate_new_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare collectible numeric(14,2); invoice_currency char(3); invoice_current_status public.invoice_status; net_paid numeric(14,2);
begin
  if not public.has_org_permission(new.organization_id, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.total - i.credit_total, i.currency, i.status into collectible, invoice_currency, invoice_current_status
    from public.invoices i where i.organization_id = new.organization_id and i.id = new.invoice_id for update;
  if collectible is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_current_status in ('draft', 'void') then raise exception 'Payments require an issued invoice'; end if;
  select coalesce((select sum(p.amount) from public.invoice_payments p where p.organization_id = new.organization_id and p.invoice_id = new.invoice_id), 0)
    - coalesce((select sum(r.amount) from public.invoice_refunds r where r.organization_id = new.organization_id and r.invoice_id = new.invoice_id), 0)
    into net_paid;
  if invoice_currency <> new.currency then raise exception 'Payment currency must match invoice currency'; end if;
  if new.amount + net_paid > collectible then raise exception 'Payment exceeds remaining invoice balance'; end if;
  return new;
end;
$$;

create or replace function public.validate_updated_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare collectible numeric(14,2); invoice_currency char(3); invoice_current_status public.invoice_status; net_paid numeric(14,2);
begin
  if not public.has_org_permission(new.organization_id, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.total - i.credit_total, i.currency, i.status into collectible, invoice_currency, invoice_current_status
    from public.invoices i where i.organization_id = new.organization_id and i.id = new.invoice_id for update;
  if collectible is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_current_status in ('draft', 'void') then raise exception 'Payments require an issued invoice'; end if;
  select coalesce((select sum(p.amount) from public.invoice_payments p where p.organization_id = new.organization_id and p.invoice_id = new.invoice_id and p.id <> old.id), 0)
    - coalesce((select sum(r.amount) from public.invoice_refunds r where r.organization_id = new.organization_id and r.invoice_id = new.invoice_id), 0)
    into net_paid;
  if invoice_currency <> new.currency then raise exception 'Payment currency must match invoice currency'; end if;
  if new.amount + net_paid > collectible then raise exception 'Payment exceeds remaining invoice balance'; end if;
  return new;
end;
$$;

create or replace function public.finance_summary(target_org uuid)
returns table (currency char(3), monthly_revenue numeric, receivables numeric, monthly_expenses numeric, estimated_profit numeric)
language sql stable security definer set search_path = '' as $$
  with settings as (select o.timezone from public.organizations o where o.id = target_org and public.is_org_member(target_org)),
  currencies as (
    select o.currency as code from public.organizations o where o.id = target_org
    union select i.currency as code from public.invoices i where i.organization_id = target_org
    union select e.currency as code from public.expenses e where e.organization_id = target_org
  ), totals as (
    select c.code,
      coalesce((select sum(p.amount) from public.invoice_payments p join public.invoices i on i.organization_id = p.organization_id and i.id = p.invoice_id
        where p.organization_id = target_org and i.currency = c.code and p.paid_at >= (date_trunc('month', now() at time zone s.timezone) at time zone s.timezone) and p.paid_at < now()), 0)
      - coalesce((select sum(r.amount) from public.invoice_refunds r join public.invoices i on i.organization_id = r.organization_id and i.id = r.invoice_id
        where r.organization_id = target_org and i.currency = c.code and r.refunded_at >= (date_trunc('month', now() at time zone s.timezone) at time zone s.timezone) and r.refunded_at < now()), 0) as revenue,
      coalesce((select sum(i.total - i.credit_total - i.amount_paid) from public.invoices i where i.organization_id = target_org and i.currency = c.code
        and i.status not in ('draft', 'void') and i.total - i.credit_total > i.amount_paid), 0) as outstanding,
      coalesce((select sum(e.amount) from public.expenses e where e.organization_id = target_org and e.currency = c.code
        and e.spent_on >= date_trunc('month', now() at time zone s.timezone)::date and e.spent_on <= (now() at time zone s.timezone)::date), 0) as expenses
    from currencies c cross join settings s
  ) select code, revenue, outstanding, expenses, revenue - expenses from totals;
$$;

create or replace function public.finance_monthly_trend(target_org uuid, month_count integer default 6)
returns table (currency char(3), month_start date, revenue numeric, expenses numeric, net_cash numeric)
language sql stable security definer set search_path = '' as $$
  with settings as (select o.timezone, date_trunc('month', now() at time zone o.timezone)::date as current_month from public.organizations o where o.id = target_org and public.is_org_member(target_org)),
  months as (select (s.current_month - (g.month_offset || ' months')::interval)::date as month_start, s.timezone from settings s cross join generate_series(0, greatest(least(coalesce(month_count, 6), 24), 1) - 1) as g(month_offset)),
  currencies as (select o.currency as code from public.organizations o where o.id = target_org union select i.currency as code from public.invoices i where i.organization_id = target_org union select e.currency as code from public.expenses e where e.organization_id = target_org),
  values_by_month as (
    select c.code, m.month_start,
      coalesce((select sum(p.amount) from public.invoice_payments p join public.invoices i on i.organization_id = p.organization_id and i.id = p.invoice_id
        where p.organization_id = target_org and i.currency = c.code and (p.paid_at at time zone m.timezone)::date >= m.month_start and (p.paid_at at time zone m.timezone)::date < (m.month_start + interval '1 month')::date), 0)
      - coalesce((select sum(r.amount) from public.invoice_refunds r join public.invoices i on i.organization_id = r.organization_id and i.id = r.invoice_id
        where r.organization_id = target_org and i.currency = c.code and (r.refunded_at at time zone m.timezone)::date >= m.month_start and (r.refunded_at at time zone m.timezone)::date < (m.month_start + interval '1 month')::date), 0) as cash_in,
      coalesce((select sum(e.amount) from public.expenses e where e.organization_id = target_org and e.currency = c.code and e.spent_on >= m.month_start and e.spent_on < (m.month_start + interval '1 month')::date), 0) as cash_out
    from currencies c cross join months m
  ) select code, month_start, cash_in, cash_out, cash_in - cash_out from values_by_month order by code, month_start;
$$;

revoke all on function public.create_invoice_refund(uuid, uuid, uuid, numeric, text, uuid) from public, anon;
grant execute on function public.create_invoice_refund(uuid, uuid, uuid, numeric, text, uuid) to authenticated;
revoke all on function public.sync_invoice_refund_state() from public, anon, authenticated;
revoke all on function public.finance_summary(uuid) from public, anon;
revoke all on function public.finance_monthly_trend(uuid, integer) from public, anon;
grant execute on function public.finance_summary(uuid) to authenticated;
grant execute on function public.finance_monthly_trend(uuid, integer) to authenticated;
