alter table public.invoice_items
  add column group_name text not null default '' check (char_length(group_name) <= 80),
  add column unit text not null default 'unit' check (char_length(btrim(unit)) between 1 and 30);
alter table public.quotation_items
  add column group_name text not null default '' check (char_length(group_name) <= 80),
  add column unit text not null default 'unit' check (char_length(btrim(unit)) between 1 and 30);

create or replace function public.apply_document_line_items(target_org uuid, target_document uuid, target_type text, target_items jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  doc_status text;
  first_item_id uuid;
  current_line record;
  line_description text;
  line_group text;
  line_unit text;
  line_quantity numeric;
  line_rate numeric;
  line_amount numeric;
  subtotal_amount numeric := 0;
  item_number integer := 0;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if target_type not in ('invoice', 'quotation') or target_items is null or jsonb_typeof(target_items) is distinct from 'array' then
    raise exception 'Provide between one and fifty document lines' using errcode = '22023';
  end if;
  if jsonb_array_length(target_items) not between 1 and 50 then
    raise exception 'Provide between one and fifty document lines' using errcode = '22023';
  end if;
  if target_type = 'invoice' then
    select i.status::text into doc_status from public.invoices i
      where i.organization_id = target_org and i.id = target_document for update;
    select i.id into first_item_id from public.invoice_items i
      where i.organization_id = target_org and i.invoice_id = target_document order by i.created_at, i.id limit 1 for update;
  else
    select q.status::text into doc_status from public.quotations q
      where q.organization_id = target_org and q.id = target_document for update;
    select i.id into first_item_id from public.quotation_items i
      where i.organization_id = target_org and i.quotation_id = target_document order by i.created_at, i.id limit 1 for update;
  end if;
  if doc_status is distinct from 'draft' then raise exception 'Only draft documents can be edited' using errcode = '22023'; end if;
  if first_item_id is null then raise exception 'The draft must start with an item' using errcode = '22023'; end if;

  for current_line in
    select line_element.value, line_element.ordinality from jsonb_array_elements(target_items) with ordinality as line_element(value, ordinality)
    order by line_element.ordinality
  loop
    if jsonb_typeof(current_line.value) <> 'object' then raise exception 'Each document line must be an object' using errcode = '22023'; end if;
    line_description := btrim(coalesce(current_line.value ->> 'description', ''));
    line_group := btrim(coalesce(current_line.value ->> 'group_name', ''));
    line_unit := btrim(coalesce(current_line.value ->> 'unit', 'unit'));
    begin
      line_quantity := nullif(current_line.value ->> 'quantity', '')::numeric;
      line_rate := nullif(current_line.value ->> 'unit_price', '')::numeric;
    exception when others then
      raise exception 'Line quantity and price must be numbers' using errcode = '22023';
    end;
    if char_length(line_description) not between 1 and 240 or char_length(line_group) > 80
      or char_length(line_unit) not between 1 and 30 or line_quantity is null or line_quantity <= 0
      or line_quantity > 9999999999 or line_rate is null or line_rate < 0 or line_rate > 999999999999.99 then
      raise exception 'Invalid document line' using errcode = '22023';
    end if;
    line_amount := line_quantity * line_rate;
    subtotal_amount := subtotal_amount + line_amount;
    if line_amount > 999999999999.99 or subtotal_amount > 999999999999.99 then
      raise exception 'Document subtotal is too large' using errcode = '22023';
    end if;

    if target_type = 'invoice' then
      if item_number = 0 then
        update public.invoice_items set description = line_description, group_name = line_group,
          unit = line_unit, quantity = line_quantity, unit_price = line_rate where id = first_item_id;
      else
        insert into public.invoice_items (organization_id, invoice_id, group_name, description, quantity, unit, unit_price)
        values (target_org, target_document, line_group, line_description, line_quantity, line_unit, line_rate);
      end if;
    else
      if item_number = 0 then
        update public.quotation_items set description = line_description, group_name = line_group,
          unit = line_unit, quantity = line_quantity, unit_price = line_rate where id = first_item_id;
      else
        insert into public.quotation_items (organization_id, quotation_id, group_name, description, quantity, unit, unit_price)
        values (target_org, target_document, line_group, line_description, line_quantity, line_unit, line_rate);
      end if;
    end if;
    item_number := item_number + 1;
  end loop;
  return true;
end;
$$;

create or replace function public.create_invoice_with_items_from_template(
  target_org uuid, target_client uuid, new_invoice_number text, invoice_currency char,
  invoice_tax numeric, new_issue_date date, new_due_date date, target_items jsonb, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare first_line jsonb; new_invoice_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if target_items is null or jsonb_typeof(target_items) is distinct from 'array' then
    raise exception 'Provide between one and fifty document lines' using errcode = '22023';
  end if;
  if jsonb_array_length(target_items) not between 1 and 50 then
    raise exception 'Provide between one and fifty document lines' using errcode = '22023';
  end if;
  first_line := target_items -> 0;
  new_invoice_id := public.create_invoice_from_template(target_org, target_client, new_invoice_number, invoice_currency,
    invoice_tax, new_issue_date, new_due_date, coalesce(first_line ->> 'description', ''),
    (first_line ->> 'quantity')::numeric, (first_line ->> 'unit_price')::numeric, selected_template);
  perform public.apply_document_line_items(target_org, new_invoice_id, 'invoice', target_items);
  return new_invoice_id;
end;
$$;

create or replace function public.create_quotation_with_items_from_template(
  target_org uuid, target_client uuid, new_quotation_number text, quote_currency char,
  quote_tax numeric, quote_issue_date date, quote_valid_until date, target_items jsonb,
  selected_template uuid default null, target_lead uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare first_line jsonb; new_quote_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if target_items is null or jsonb_typeof(target_items) is distinct from 'array' then
    raise exception 'Provide between one and fifty document lines' using errcode = '22023';
  end if;
  if jsonb_array_length(target_items) not between 1 and 50 then
    raise exception 'Provide between one and fifty document lines' using errcode = '22023';
  end if;
  first_line := target_items -> 0;
  new_quote_id := public.create_quotation_from_template(target_org, target_client, new_quotation_number, quote_currency,
    quote_tax, quote_issue_date, quote_valid_until, coalesce(first_line ->> 'description', ''),
    (first_line ->> 'quantity')::numeric, (first_line ->> 'unit_price')::numeric, selected_template);
  if target_lead is not null then
    update public.quotations set source_lead_id = target_lead
      where organization_id = target_org and id = new_quote_id;
  end if;
  perform public.apply_document_line_items(target_org, new_quote_id, 'quotation', target_items);
  return new_quote_id;
end;
$$;

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
  insert into public.invoice_items (organization_id, invoice_id, group_name, description, quantity, unit, unit_price)
  select target_org, new_invoice_id, i.group_name, i.description, i.quantity, i.unit, i.unit_price
  from public.quotation_items i where i.organization_id = target_org and i.quotation_id = target_quote order by i.created_at, i.id;
  update public.quotations set status = 'converted', converted_invoice_id = new_invoice_id
  where organization_id = target_org and id = target_quote;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, auth.uid(), 'convert_to_invoice', 'quotations', target_quote::text,
    jsonb_build_object('quotation_number', quote_row.quotation_number, 'invoice_id', new_invoice_id));
  return new_invoice_id;
end;
$$;

revoke all on function public.apply_document_line_items(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.create_invoice_with_items_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, uuid) from public, anon;
revoke all on function public.create_quotation_with_items_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, uuid, uuid) from public, anon;
grant execute on function public.create_invoice_with_items_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, uuid) to authenticated;
grant execute on function public.create_quotation_with_items_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, uuid, uuid) to authenticated;
