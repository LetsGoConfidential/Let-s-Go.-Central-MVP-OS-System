-- Draft invoices are itemized. The database owns subtotal calculation and
-- creates the invoice and its first item atomically through an RPC.
create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null,
  description text not null check (length(btrim(description)) between 1 and 240),
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(16,2) generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, invoice_id)
    references public.invoices(organization_id, id) on delete cascade
);

create index invoice_items_invoice_idx on public.invoice_items (organization_id, invoice_id);
alter table public.invoice_items enable row level security;
revoke all on public.invoice_items from anon, authenticated;
grant select, insert, update, delete on public.invoice_items to authenticated;
create policy invoice_items_read on public.invoice_items for select to authenticated
  using (public.is_org_member(organization_id));
create policy invoice_items_write on public.invoice_items for all to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'))
  with check (public.has_org_permission(organization_id, 'finance.manage'));
create trigger set_updated_at before update on public.invoice_items
  for each row execute function public.set_updated_at();
create trigger audit_change after insert or update or delete on public.invoice_items
  for each row execute function public.write_audit_log();

create or replace function public.guard_invoice_item()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_invoice uuid; target_org uuid; current_status public.invoice_status;
begin
  if tg_op = 'DELETE' then target_invoice := old.invoice_id; target_org := old.organization_id;
  else target_invoice := new.invoice_id; target_org := new.organization_id; end if;
  if tg_op = 'UPDATE' and (new.invoice_id is distinct from old.invoice_id or new.organization_id is distinct from old.organization_id) then
    raise exception 'Invoice items cannot be moved between invoices';
  end if;
  if not public.has_org_permission(target_org, 'finance.manage') then raise exception 'Finance permission required'; end if;
  select i.status into current_status from public.invoices i
    where i.organization_id = target_org and i.id = target_invoice for update;
  if current_status is distinct from 'draft'::public.invoice_status then raise exception 'Only draft invoices can be edited'; end if;
  if tg_op = 'DELETE' then return old; end if;
  new.description := btrim(new.description);
  new.updated_at := now();
  return new;
end;
$$;
create trigger guard_invoice_item before insert or update or delete on public.invoice_items
  for each row execute function public.guard_invoice_item();

create or replace function public.recalculate_invoice_subtotal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_org uuid; target_invoice uuid;
begin
  if tg_op = 'DELETE' then target_org := old.organization_id; target_invoice := old.invoice_id;
  else target_org := new.organization_id; target_invoice := new.invoice_id; end if;
  update public.invoices i set subtotal = coalesce((
    select sum(it.line_total) from public.invoice_items it
    where it.organization_id = target_org and it.invoice_id = target_invoice
  ), 0)
  where i.organization_id = target_org and i.id = target_invoice and i.status = 'draft';
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger recalculate_invoice_subtotal after insert or update or delete on public.invoice_items
  for each row execute function public.recalculate_invoice_subtotal();

create or replace function public.require_invoice_item_before_issue()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'draft' and new.status = 'sent' and not exists (
    select 1 from public.invoice_items it where it.organization_id = new.organization_id and it.invoice_id = new.id
  ) then raise exception 'An invoice needs at least one line item before it can be issued'; end if;
  return new;
end;
$$;
create trigger require_invoice_item_before_issue before update of status on public.invoices
  for each row execute function public.require_invoice_item_before_issue();

create or replace function public.create_invoice_with_item(
  target_org uuid,
  target_client uuid,
  new_invoice_number text,
  invoice_currency char(3),
  invoice_tax numeric,
  new_issue_date date,
  new_due_date date,
  line_description text,
  line_quantity numeric,
  line_unit_price numeric
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required';
  end if;
  if length(btrim(new_invoice_number)) not between 2 and 40
    or invoice_currency !~ '^[A-Z]{3}$'
    or invoice_tax < 0 or line_quantity <= 0 or line_unit_price < 0
    or length(btrim(line_description)) not between 1 and 240
    or new_issue_date is null or new_due_date < new_issue_date then
    raise exception 'Invalid invoice details';
  end if;
  insert into public.invoices (organization_id, client_id, invoice_number, currency, subtotal, tax, issue_date, due_date)
  values (target_org, target_client, btrim(new_invoice_number), invoice_currency, 0, invoice_tax, new_issue_date, new_due_date)
  returning id into new_id;
  insert into public.invoice_items (organization_id, invoice_id, description, quantity, unit_price)
  values (target_org, new_id, btrim(line_description), line_quantity, line_unit_price);
  return new_id;
end;
$$;

-- Direct invoice creation would bypass the requirement for at least one line.
revoke insert (organization_id, client_id, invoice_number, currency, subtotal, tax, issue_date, due_date) on public.invoices from authenticated;
revoke all on function public.guard_invoice_item() from public, anon, authenticated;
revoke all on function public.recalculate_invoice_subtotal() from public, anon, authenticated;
revoke all on function public.require_invoice_item_before_issue() from public, anon, authenticated;
revoke all on function public.create_invoice_with_item(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric) from public, anon;
grant execute on function public.create_invoice_with_item(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric) to authenticated;
