create or replace function public.finance_custom_fields_valid(target_fields jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  field jsonb;
  field_label text;
  field_value text;
  labels text[] := array[]::text[];
begin
  if target_fields is null or jsonb_typeof(target_fields) is distinct from 'array' then
    return false;
  end if;
  if jsonb_array_length(target_fields) > 20 then
    return false;
  end if;
  for field in select value from jsonb_array_elements(target_fields) as entries(value) loop
    if jsonb_typeof(field) is distinct from 'object' then return false; end if;
    if field - 'label' - 'value' <> '{}'::jsonb or not (field ? 'label') or not (field ? 'value') then return false; end if;
    field_label := btrim(coalesce(field ->> 'label', ''));
    field_value := btrim(coalesce(field ->> 'value', ''));
    if char_length(field_label) not between 1 and 60 or char_length(field_value) not between 1 and 240
      or lower(field_label) = any(labels) then
      return false;
    end if;
    labels := array_append(labels, lower(field_label));
  end loop;
  return true;
end;
$$;

alter table public.invoices
  add column purchase_order_number text not null default '' check (char_length(btrim(purchase_order_number)) <= 60),
  add column custom_fields jsonb not null default '[]'::jsonb check (public.finance_custom_fields_valid(custom_fields));
alter table public.quotations
  add column purchase_order_number text not null default '' check (char_length(btrim(purchase_order_number)) <= 60),
  add column custom_fields jsonb not null default '[]'::jsonb check (public.finance_custom_fields_valid(custom_fields));

create or replace function public.create_invoice_document_from_template(
  target_org uuid, target_client uuid, new_invoice_number text, invoice_currency char,
  invoice_tax numeric, new_issue_date date, new_due_date date, target_items jsonb,
  document_purchase_order text, document_custom_fields jsonb, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_invoice_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if document_purchase_order is null or char_length(btrim(document_purchase_order)) > 60
    or not public.finance_custom_fields_valid(document_custom_fields) then
    raise exception 'Invalid document references or custom fields' using errcode = '22023';
  end if;
  new_invoice_id := public.create_invoice_with_items_from_template(
    target_org, target_client, new_invoice_number, invoice_currency, invoice_tax, new_issue_date, new_due_date,
    target_items, selected_template
  );
  update public.invoices set purchase_order_number = btrim(document_purchase_order), custom_fields = document_custom_fields
    where organization_id = target_org and id = new_invoice_id;
  return new_invoice_id;
end;
$$;

create or replace function public.create_quotation_document_from_template(
  target_org uuid, target_client uuid, new_quotation_number text, quote_currency char,
  quote_tax numeric, quote_issue_date date, quote_valid_until date, target_items jsonb,
  document_purchase_order text, document_custom_fields jsonb, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_quote_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if document_purchase_order is null or char_length(btrim(document_purchase_order)) > 60
    or not public.finance_custom_fields_valid(document_custom_fields) then
    raise exception 'Invalid document references or custom fields' using errcode = '22023';
  end if;
  new_quote_id := public.create_quotation_with_items_from_template(
    target_org, target_client, new_quotation_number, quote_currency, quote_tax, quote_issue_date, quote_valid_until,
    target_items, selected_template, null
  );
  update public.quotations set purchase_order_number = btrim(document_purchase_order), custom_fields = document_custom_fields
    where organization_id = target_org and id = new_quote_id;
  return new_quote_id;
end;
$$;

create or replace function public.copy_quotation_template_to_invoice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source_quotation_id is not null then
    select q.document_template_id, q.document_template_version, q.document_template_snapshot,
      q.purchase_order_number, q.custom_fields
      into new.document_template_id, new.document_template_version, new.document_template_snapshot,
        new.purchase_order_number, new.custom_fields
    from public.quotations q where q.organization_id = new.organization_id and q.id = new.source_quotation_id;
    if not found then raise exception 'Source quotation not found'; end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_document_references()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status::text <> 'draft' and (
    new.purchase_order_number is distinct from old.purchase_order_number
    or new.custom_fields is distinct from old.custom_fields
  ) then
    raise exception 'Document references cannot be changed after issue' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_document_references() from public, anon, authenticated;
create trigger invoices_guard_document_references before update on public.invoices
  for each row execute function public.guard_document_references();
create trigger quotations_guard_document_references before update on public.quotations
  for each row execute function public.guard_document_references();

revoke all on function public.create_invoice_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, uuid) from public, anon;
grant execute on function public.create_invoice_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, uuid) to authenticated;
revoke all on function public.create_quotation_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, uuid) from public, anon;
grant execute on function public.create_quotation_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, uuid) to authenticated;
