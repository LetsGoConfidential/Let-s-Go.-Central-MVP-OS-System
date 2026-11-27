-- Keep the quotation's public edit guard aligned with the document-reference
-- guard so issued reference fields receive the intended, stable error.
create or replace function public.guard_quotation_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'draft' and (
    new.client_id is distinct from old.client_id
    or new.quotation_number is distinct from old.quotation_number
    or new.currency is distinct from old.currency
    or new.subtotal is distinct from old.subtotal
    or new.tax is distinct from old.tax
    or new.issue_date is distinct from old.issue_date
    or new.valid_until is distinct from old.valid_until
    or new.source_lead_id is distinct from old.source_lead_id
    or new.purchase_order_number is distinct from old.purchase_order_number
    or new.custom_fields is distinct from old.custom_fields
    or new.document_notes is distinct from old.document_notes
    or new.document_terms is distinct from old.document_terms
    or new.signature_label is distinct from old.signature_label
  ) then
    raise exception 'Document references cannot be changed after issue' using errcode = '22023';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'draft' and new.status = 'sent')
    or (old.status = 'sent' and new.status in ('accepted', 'declined', 'expired'))
    or (old.status = 'accepted' and new.status = 'converted')
  ) then
    raise exception 'Invalid quotation transition' using errcode = '22023';
  end if;
  if new.status = 'converted' and new.converted_invoice_id is null then
    raise exception 'Converted quotation must link an invoice';
  end if;
  if new.status <> 'converted' and new.converted_invoice_id is not null then
    raise exception 'Only converted quotations can link an invoice';
  end if;
  return new;
end;
$$;
