alter table public.invoices
  add column document_notes text not null default '' check (char_length(document_notes) <= 2000),
  add column document_terms text not null default '' check (char_length(document_terms) <= 5000),
  add column signature_label text not null default '' check (char_length(signature_label) <= 80);

alter table public.quotations
  add column document_notes text not null default '' check (char_length(document_notes) <= 2000),
  add column document_terms text not null default '' check (char_length(document_terms) <= 5000),
  add column signature_label text not null default '' check (char_length(signature_label) <= 80);

drop function public.create_invoice_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, uuid);
drop function public.create_quotation_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, uuid);

create function public.create_invoice_document_from_template(
  target_org uuid, target_client uuid, new_invoice_number text, invoice_currency char,
  invoice_tax numeric, new_issue_date date, new_due_date date, target_items jsonb,
  document_purchase_order text, document_custom_fields jsonb, document_notes text,
  document_terms text, document_signature_label text, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_invoice_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if document_purchase_order is null or char_length(btrim(document_purchase_order)) > 60
    or not public.finance_custom_fields_valid(document_custom_fields)
    or document_notes is null or char_length(document_notes) > 2000
    or document_terms is null or char_length(document_terms) > 5000
    or document_signature_label is null or char_length(document_signature_label) > 80 then
    raise exception 'Invalid document references, fields, or terms' using errcode = '22023';
  end if;
  new_invoice_id := public.create_invoice_with_items_from_template(
    target_org, target_client, new_invoice_number, invoice_currency, invoice_tax, new_issue_date, new_due_date,
    target_items, selected_template
  );
  update public.invoices set purchase_order_number = btrim(document_purchase_order), custom_fields = document_custom_fields,
    document_notes = btrim(document_notes), document_terms = btrim(document_terms), signature_label = btrim(document_signature_label)
    where organization_id = target_org and id = new_invoice_id;
  return new_invoice_id;
end;
$$;

create function public.create_quotation_document_from_template(
  target_org uuid, target_client uuid, new_quotation_number text, quote_currency char,
  quote_tax numeric, quote_issue_date date, quote_valid_until date, target_items jsonb,
  document_purchase_order text, document_custom_fields jsonb, document_notes text,
  document_terms text, document_signature_label text, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_quote_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if document_purchase_order is null or char_length(btrim(document_purchase_order)) > 60
    or not public.finance_custom_fields_valid(document_custom_fields)
    or document_notes is null or char_length(document_notes) > 2000
    or document_terms is null or char_length(document_terms) > 5000
    or document_signature_label is null or char_length(document_signature_label) > 80 then
    raise exception 'Invalid document references, fields, or terms' using errcode = '22023';
  end if;
  new_quote_id := public.create_quotation_with_items_from_template(
    target_org, target_client, new_quotation_number, quote_currency, quote_tax, quote_issue_date, quote_valid_until,
    target_items, selected_template, null
  );
  update public.quotations set purchase_order_number = btrim(document_purchase_order), custom_fields = document_custom_fields,
    document_notes = btrim(document_notes), document_terms = btrim(document_terms), signature_label = btrim(document_signature_label)
    where organization_id = target_org and id = new_quote_id;
  return new_quote_id;
end;
$$;

create or replace function public.copy_quotation_template_to_invoice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source_quotation_id is not null then
    select q.document_template_id, q.document_template_version, q.document_template_snapshot,
      q.purchase_order_number, q.custom_fields, q.document_notes, q.document_terms, q.signature_label
      into new.document_template_id, new.document_template_version, new.document_template_snapshot,
        new.purchase_order_number, new.custom_fields, new.document_notes, new.document_terms, new.signature_label
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
    or new.document_notes is distinct from old.document_notes
    or new.document_terms is distinct from old.document_terms
    or new.signature_label is distinct from old.signature_label
  ) then
    raise exception 'Document references cannot be changed after issue' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.create_invoice_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, text, text, text, uuid) from public, anon;
grant execute on function public.create_invoice_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, text, text, text, uuid) to authenticated;
revoke all on function public.create_quotation_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, text, text, text, uuid) from public, anon;
grant execute on function public.create_quotation_document_from_template(uuid, uuid, text, char, numeric, date, date, jsonb, text, jsonb, text, text, text, uuid) to authenticated;
