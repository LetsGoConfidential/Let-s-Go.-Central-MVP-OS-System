-- Finance ledger: payments are immutable facts linked to one tenant invoice.
create table public.invoice_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  currency char(3) not null,
  paid_at timestamptz not null default now(),
  method text not null default 'other' check (method in ('bank_transfer', 'cash', 'card', 'cheque', 'other')),
  provider_reference text,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (organization_id, invoice_id) references public.invoices(organization_id, id) on delete cascade
);

create index invoice_payments_org_paid_idx on public.invoice_payments (organization_id, paid_at desc);
create index invoice_payments_invoice_idx on public.invoice_payments (organization_id, invoice_id, paid_at desc);

alter table public.invoice_payments enable row level security;
revoke all on public.invoice_payments from anon, authenticated;
grant select, insert on public.invoice_payments to authenticated;
create policy tenant_read on public.invoice_payments for select to authenticated
  using (public.is_org_member(organization_id));
create policy tenant_insert on public.invoice_payments for insert to authenticated
  with check (public.has_org_permission(organization_id, 'finance.manage'));

-- An issued invoice is retained as an auditable record; corrections use a future credit-note flow.
drop policy tenant_write on public.invoices;
create policy invoice_insert on public.invoices for insert to authenticated
  with check (public.has_org_permission(organization_id, 'finance.manage'));
create policy invoice_update on public.invoices for update to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'))
  with check (public.has_org_permission(organization_id, 'finance.manage'));
revoke insert, update, delete on public.invoices from authenticated;
grant insert (organization_id, client_id, invoice_number, currency, subtotal, tax, issue_date, due_date)
  on public.invoices to authenticated;
grant update (client_id, invoice_number, status, currency, subtotal, tax, issue_date, due_date)
  on public.invoices to authenticated;

create or replace function public.protect_invoice_payment_fields()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.amount_paid <> 0 or new.paid_at is not null or new.status <> 'draft' then
      raise exception 'New invoices must start as unpaid drafts';
    end if;
    return new;
  end if;
  if current_setting('letsgo.invoice_payment_sync', true) = 'on' then return new; end if;
  if new.amount_paid is distinct from old.amount_paid or new.paid_at is distinct from old.paid_at then
    raise exception 'Invoice payment totals are maintained by the payment ledger';
  end if;
  if old.status <> 'draft' and (
    new.client_id is distinct from old.client_id or new.invoice_number is distinct from old.invoice_number
    or new.currency is distinct from old.currency or new.subtotal is distinct from old.subtotal
    or new.tax is distinct from old.tax or new.issue_date is distinct from old.issue_date
    or new.due_date is distinct from old.due_date
  ) then
    raise exception 'Issued invoices are locked; use a credit note workflow for corrections';
  end if;
  if new.status is distinct from old.status and not (old.status = 'draft' and new.status = 'sent') then
    raise exception 'Invoice status must follow the issue and payment workflow';
  end if;
  return new;
end;
$$;
create trigger protect_invoice_payment_fields before insert or update on public.invoices
  for each row execute function public.protect_invoice_payment_fields();

-- OLD is not defined for INSERT triggers, so use separate trigger functions for each event.
create or replace function public.validate_new_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare invoice_total numeric(14,2); invoice_currency char(3); invoice_current_status public.invoice_status; existing_amount numeric(14,2);
begin
  if not public.has_org_permission(new.organization_id, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.total, i.currency, i.status into invoice_total, invoice_currency, invoice_current_status
  from public.invoices i where i.organization_id = new.organization_id and i.id = new.invoice_id for update;
  if invoice_total is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_current_status in ('draft', 'void') then raise exception 'Payments require an issued invoice'; end if;
  select coalesce(sum(p.amount), 0) into existing_amount from public.invoice_payments p
    where p.organization_id = new.organization_id and p.invoice_id = new.invoice_id;
  if invoice_currency <> new.currency then raise exception 'Payment currency must match invoice currency'; end if;
  if new.amount + existing_amount > invoice_total then raise exception 'Payment exceeds remaining invoice balance'; end if;
  return new;
end;
$$;

create or replace function public.validate_updated_invoice_payment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare invoice_total numeric(14,2); invoice_currency char(3); invoice_current_status public.invoice_status; existing_amount numeric(14,2);
begin
  if not public.has_org_permission(new.organization_id, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.total, i.currency, i.status into invoice_total, invoice_currency, invoice_current_status
  from public.invoices i where i.organization_id = new.organization_id and i.id = new.invoice_id for update;
  if invoice_total is null then raise exception 'Invoice not found in this organization'; end if;
  if invoice_current_status in ('draft', 'void') then raise exception 'Payments require an issued invoice'; end if;
  select coalesce(sum(p.amount), 0) into existing_amount from public.invoice_payments p
    where p.organization_id = new.organization_id and p.invoice_id = new.invoice_id and p.id <> old.id;
  if invoice_currency <> new.currency then raise exception 'Payment currency must match invoice currency'; end if;
  if new.amount + existing_amount > invoice_total then raise exception 'Payment exceeds remaining invoice balance'; end if;
  return new;
end;
$$;

create trigger validate_invoice_payment_insert before insert on public.invoice_payments
  for each row execute function public.validate_new_invoice_payment();
create trigger validate_invoice_payment_update before update on public.invoice_payments
  for each row execute function public.validate_updated_invoice_payment();

create or replace function public.refresh_invoice_payment_state(target_org uuid, target_invoice uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare paid_total numeric(14,2); last_paid_at timestamptz;
begin
  select coalesce(sum(p.amount), 0), max(p.paid_at)
    into paid_total, last_paid_at
  from public.invoice_payments p
  where p.organization_id = target_org and p.invoice_id = target_invoice;

  perform set_config('letsgo.invoice_payment_sync', 'on', true);
  update public.invoices i
  set amount_paid = paid_total,
      paid_at = case when paid_total >= i.total then last_paid_at else null end,
      status = case
        when i.status = 'void' then 'void'::public.invoice_status
        when paid_total >= i.total then 'paid'::public.invoice_status
        when paid_total > 0 then 'partially_paid'::public.invoice_status
        when i.status = 'draft' then 'draft'::public.invoice_status
        when i.due_date < current_date then 'overdue'::public.invoice_status
        else 'sent'::public.invoice_status
      end
  where i.organization_id = target_org and i.id = target_invoice;
  perform set_config('letsgo.invoice_payment_sync', 'off', true);
end;
$$;

create or replace function public.sync_invoice_payment_state()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.refresh_invoice_payment_state(old.organization_id, old.invoice_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public.refresh_invoice_payment_state(new.organization_id, new.invoice_id);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger sync_invoice_payment_state after insert or update or delete on public.invoice_payments
  for each row execute function public.sync_invoice_payment_state();

-- A single row per currency prevents combining incomparable amounts in reports.
create or replace function public.finance_summary(target_org uuid)
returns table (currency char(3), monthly_revenue numeric, receivables numeric, monthly_expenses numeric, estimated_profit numeric)
language sql stable security definer set search_path = '' as $$
  with settings as (
    select o.timezone from public.organizations o
    where o.id = target_org and public.is_org_member(target_org)
  ), currencies as (
    select o.currency as code from public.organizations o where o.id = target_org
    union
    select i.currency as code from public.invoices i where i.organization_id = target_org
    union
    select e.currency as code from public.expenses e where e.organization_id = target_org
  ), totals as (
    select c.code,
      coalesce((select sum(p.amount) from public.invoice_payments p
        join public.invoices i on i.organization_id = p.organization_id and i.id = p.invoice_id
        where p.organization_id = target_org and i.currency = c.code
          and p.paid_at >= (date_trunc('month', now() at time zone s.timezone) at time zone s.timezone)
          and p.paid_at < now()), 0) as revenue,
      coalesce((select sum(i.total - i.amount_paid) from public.invoices i
        where i.organization_id = target_org and i.currency = c.code
          and i.status not in ('draft', 'void') and i.amount_paid < i.total), 0) as outstanding,
      coalesce((select sum(e.amount) from public.expenses e
        where e.organization_id = target_org and e.currency = c.code
          and e.spent_on >= date_trunc('month', now() at time zone s.timezone)::date
          and e.spent_on <= (now() at time zone s.timezone)::date), 0) as expenses
    from currencies c cross join settings s
  )
  select code, revenue, outstanding, expenses, revenue - expenses from totals;
$$;
revoke all on function public.finance_summary(uuid) from public, anon;
grant execute on function public.finance_summary(uuid) to authenticated;

-- Avoid exposing payment references or identity fields in generic change snapshots.
create or replace function public.write_payment_audit_log()
returns trigger language plpgsql security definer set search_path = '' as $$
declare row_data jsonb; org_id uuid; record_id text; action_name text;
begin
  if tg_op = 'DELETE' then row_data = to_jsonb(old); else row_data = to_jsonb(new); end if;
  org_id = (row_data ->> 'organization_id')::uuid;
  record_id = row_data ->> 'id';
  action_name = lower(tg_op);
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (org_id, auth.uid(), action_name, 'invoice_payment', record_id,
    jsonb_build_object('amount', row_data -> 'amount', 'currency', row_data -> 'currency', 'paid_at', row_data -> 'paid_at', 'method', row_data -> 'method'));
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger audit_invoice_payment after insert or update or delete on public.invoice_payments
  for each row execute function public.write_payment_audit_log();

revoke all on function public.validate_new_invoice_payment() from public, anon, authenticated;
revoke all on function public.validate_updated_invoice_payment() from public, anon, authenticated;
revoke all on function public.refresh_invoice_payment_state(uuid, uuid) from public, anon, authenticated;
revoke all on function public.sync_invoice_payment_state() from public, anon, authenticated;
revoke all on function public.write_payment_audit_log() from public, anon, authenticated;
revoke all on function public.protect_invoice_payment_fields() from public, anon, authenticated;
