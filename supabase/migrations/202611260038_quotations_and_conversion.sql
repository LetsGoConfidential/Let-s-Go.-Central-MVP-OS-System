create type public.quotation_status as enum ('draft', 'sent', 'accepted', 'declined', 'expired', 'converted');

create table public.quotations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  quotation_number text not null check (length(btrim(quotation_number)) between 2 and 40),
  status public.quotation_status not null default 'draft',
  currency char(3) not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  tax numeric(14,2) not null default 0 check (tax >= 0),
  total numeric(14,2) generated always as (subtotal + tax) stored,
  issue_date date not null default current_date,
  valid_until date not null,
  source_lead_id uuid,
  converted_invoice_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, quotation_number),
  unique (organization_id, converted_invoice_id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id),
  foreign key (organization_id, source_lead_id) references public.leads(organization_id, id),
  check (valid_until >= issue_date)
);
create index quotations_org_status_date_idx on public.quotations (organization_id, status, created_at desc);

create table public.quotation_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quotation_id uuid not null,
  description text not null check (length(btrim(description)) between 1 and 240),
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(16,2) generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, quotation_id) references public.quotations(organization_id, id) on delete cascade
);
create index quotation_items_quote_idx on public.quotation_items (organization_id, quotation_id);

alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;
revoke all on public.quotations, public.quotation_items from anon;
grant select, insert, update, delete on public.quotations, public.quotation_items to authenticated;
create policy quotations_read on public.quotations for select to authenticated
  using (public.is_org_member(organization_id));
create policy quotations_write on public.quotations for all to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'))
  with check (public.has_org_permission(organization_id, 'finance.manage'));
create policy quotation_items_read on public.quotation_items for select to authenticated
  using (public.is_org_member(organization_id));
create policy quotation_items_write on public.quotation_items for all to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'))
  with check (public.has_org_permission(organization_id, 'finance.manage'));
create trigger quotations_updated_at before update on public.quotations
  for each row execute function public.set_updated_at();
create trigger quotation_items_updated_at before update on public.quotation_items
  for each row execute function public.set_updated_at();
create trigger quotations_audit after insert or update or delete on public.quotations
  for each row execute function public.write_audit_log();
create trigger quotation_items_audit after insert or update or delete on public.quotation_items
  for each row execute function public.write_audit_log();

create or replace function public.guard_quotation_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'draft' and (
    new.client_id is distinct from old.client_id or new.quotation_number is distinct from old.quotation_number
    or new.currency is distinct from old.currency or new.subtotal is distinct from old.subtotal
    or new.tax is distinct from old.tax or new.issue_date is distinct from old.issue_date
    or new.valid_until is distinct from old.valid_until or new.source_lead_id is distinct from old.source_lead_id
  ) then raise exception 'Only draft quotations can be edited'; end if;
  if new.status is distinct from old.status and not (
    (old.status = 'draft' and new.status = 'sent')
    or (old.status = 'sent' and new.status in ('accepted', 'declined', 'expired'))
    or (old.status = 'accepted' and new.status = 'converted')
  ) then raise exception 'Invalid quotation transition' using errcode = '22023'; end if;
  if new.status = 'converted' and new.converted_invoice_id is null then
    raise exception 'Converted quotation must link an invoice';
  end if;
  if new.status <> 'converted' and new.converted_invoice_id is not null then
    raise exception 'Only converted quotations can link an invoice';
  end if;
  return new;
end;
$$;
create trigger guard_quotation_update before update on public.quotations
  for each row execute function public.guard_quotation_update();

create or replace function public.guard_quotation_item()
returns trigger language plpgsql security definer set search_path = '' as $$
declare quote_status public.quotation_status; target_org uuid; target_quote uuid;
begin
  if tg_op = 'DELETE' then target_org := old.organization_id; target_quote := old.quotation_id;
  else target_org := new.organization_id; target_quote := new.quotation_id; end if;
  if tg_op = 'UPDATE' and (new.organization_id is distinct from old.organization_id or new.quotation_id is distinct from old.quotation_id) then
    raise exception 'Quotation items cannot be moved between quotations';
  end if;
  if not public.has_org_permission(target_org, 'finance.manage') then raise exception 'Finance permission required' using errcode = '42501'; end if;
  select q.status into quote_status from public.quotations q
    where q.organization_id = target_org and q.id = target_quote for update;
  if quote_status is distinct from 'draft'::public.quotation_status then raise exception 'Only draft quotations can be edited'; end if;
  if tg_op = 'DELETE' then return old; end if;
  new.description := btrim(new.description);
  new.updated_at := now();
  return new;
end;
$$;
create trigger guard_quotation_item before insert or update or delete on public.quotation_items
  for each row execute function public.guard_quotation_item();

create or replace function public.recalculate_quotation_subtotal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_org uuid; target_quote uuid;
begin
  if tg_op = 'DELETE' then target_org := old.organization_id; target_quote := old.quotation_id;
  else target_org := new.organization_id; target_quote := new.quotation_id; end if;
  update public.quotations q set subtotal = coalesce((
    select sum(i.line_total) from public.quotation_items i
    where i.organization_id = target_org and i.quotation_id = target_quote
  ), 0)
  where q.organization_id = target_org and q.id = target_quote and q.status = 'draft';
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger recalculate_quotation_subtotal after insert or update or delete on public.quotation_items
  for each row execute function public.recalculate_quotation_subtotal();

create or replace function public.require_quotation_item_before_send()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'draft' and new.status = 'sent' and not exists (
    select 1 from public.quotation_items i where i.organization_id = new.organization_id and i.quotation_id = new.id
  ) then raise exception 'A quotation needs at least one line item before it can be sent'; end if;
  return new;
end;
$$;
create trigger require_quotation_item_before_send before update of status on public.quotations
  for each row execute function public.require_quotation_item_before_send();

create or replace function public.create_quotation_with_item(
  target_org uuid, target_client uuid, new_quotation_number text, quote_currency char,
  quote_tax numeric, quote_issue_date date, quote_valid_until date,
  line_description text, line_quantity numeric, line_unit_price numeric, target_lead uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if length(btrim(new_quotation_number)) not between 2 and 40 or quote_currency !~ '^[A-Z]{3}$'
    or quote_tax < 0 or quote_tax > 999999999999.99 or line_quantity <= 0 or line_quantity > 9999999999
    or line_unit_price < 0 or line_quantity * line_unit_price > 999999999999.99
    or length(btrim(line_description)) not between 1 and 240
    or quote_issue_date is null or quote_valid_until < quote_issue_date then
    raise exception 'Invalid quotation details' using errcode = '22023';
  end if;
  insert into public.quotations (organization_id, client_id, quotation_number, currency, tax, issue_date, valid_until, source_lead_id, created_by)
  values (target_org, target_client, btrim(new_quotation_number), quote_currency, quote_tax, quote_issue_date, quote_valid_until, target_lead, auth.uid())
  returning id into new_id;
  insert into public.quotation_items (organization_id, quotation_id, description, quantity, unit_price)
  values (target_org, new_id, btrim(line_description), line_quantity, line_unit_price);
  return new_id;
end;
$$;

create or replace function public.transition_quotation(target_org uuid, target_quote uuid, decision text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare quote_row public.quotations%rowtype; next_status public.quotation_status;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  select q.* into quote_row from public.quotations q
    where q.organization_id = target_org and q.id = target_quote for update;
  if not found then raise exception 'Quotation not found' using errcode = '42501'; end if;
  if decision = 'send' and quote_row.status = 'draft' then next_status := 'sent';
  elsif decision = 'accept' and quote_row.status = 'sent' and quote_row.valid_until >= current_date then next_status := 'accepted';
  elsif decision = 'decline' and quote_row.status = 'sent' then next_status := 'declined';
  elsif decision = 'expire' and quote_row.status = 'sent' and quote_row.valid_until < current_date then next_status := 'expired';
  else raise exception 'Invalid quotation transition' using errcode = '22023';
  end if;
  update public.quotations set status = next_status where organization_id = target_org and id = target_quote;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, auth.uid(), decision, 'quotations', target_quote::text,
    jsonb_build_object('quotation_number', quote_row.quotation_number, 'status', next_status));
  return true;
end;
$$;

alter table public.invoices add column source_quotation_id uuid;
alter table public.invoices add constraint invoices_source_quotation_fkey
  foreign key (organization_id, source_quotation_id) references public.quotations(organization_id, id);
alter table public.quotations add constraint quotations_converted_invoice_fkey
  foreign key (organization_id, converted_invoice_id) references public.invoices(organization_id, id);
create unique index invoices_source_quotation_unique on public.invoices (organization_id, source_quotation_id)
  where source_quotation_id is not null;

create or replace function public.convert_quotation_to_invoice(
  target_org uuid, target_quote uuid, new_invoice_number text, new_issue_date date, new_due_date date
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare quote_row public.quotations%rowtype; new_invoice_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  select q.* into quote_row from public.quotations q
    where q.organization_id = target_org and q.id = target_quote for update;
  if not found then raise exception 'Quotation not found' using errcode = '42501'; end if;
  if quote_row.status = 'converted' then
    select i.id into new_invoice_id from public.invoices i
      where i.organization_id = target_org and i.source_quotation_id = target_quote;
    if new_invoice_id is not null then return new_invoice_id; end if;
    raise exception 'Converted quotation has no linked invoice';
  end if;
  if quote_row.status <> 'accepted' or quote_row.valid_until < current_date then
    raise exception 'Only an accepted, valid quotation can become an invoice' using errcode = '22023';
  end if;
  if length(btrim(new_invoice_number)) not between 2 and 40 or new_issue_date is null or new_due_date < new_issue_date then
    raise exception 'Invalid invoice details' using errcode = '22023';
  end if;
  insert into public.invoices (organization_id, client_id, invoice_number, currency, subtotal, tax, issue_date, due_date, source_quotation_id)
  values (target_org, quote_row.client_id, btrim(new_invoice_number), quote_row.currency, 0, quote_row.tax, new_issue_date, new_due_date, target_quote)
  returning id into new_invoice_id;
  insert into public.invoice_items (organization_id, invoice_id, description, quantity, unit_price)
  select target_org, new_invoice_id, i.description, i.quantity, i.unit_price
  from public.quotation_items i where i.organization_id = target_org and i.quotation_id = target_quote;
  update public.quotations set status = 'converted', converted_invoice_id = new_invoice_id
  where organization_id = target_org and id = target_quote;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, auth.uid(), 'convert_to_invoice', 'quotations', target_quote::text,
    jsonb_build_object('quotation_number', quote_row.quotation_number, 'invoice_id', new_invoice_id));
  return new_invoice_id;
end;
$$;

revoke all on function public.guard_quotation_item() from public, anon, authenticated;
revoke all on function public.recalculate_quotation_subtotal() from public, anon, authenticated;
revoke all on function public.require_quotation_item_before_send() from public, anon, authenticated;
revoke all on function public.guard_quotation_update() from public, anon, authenticated;
revoke all on function public.create_quotation_with_item(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric, uuid) from public, anon;
revoke all on function public.transition_quotation(uuid, uuid, text) from public, anon;
revoke all on function public.convert_quotation_to_invoice(uuid, uuid, text, date, date) from public, anon;
grant execute on function public.create_quotation_with_item(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric, uuid) to authenticated;
grant execute on function public.transition_quotation(uuid, uuid, text) to authenticated;
grant execute on function public.convert_quotation_to_invoice(uuid, uuid, text, date, date) to authenticated;
