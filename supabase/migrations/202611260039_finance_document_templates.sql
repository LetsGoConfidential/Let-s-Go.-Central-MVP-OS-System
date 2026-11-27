create table public.finance_document_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_type text not null check (document_type in ('invoice', 'quotation')),
  template_key text not null check (template_key ~ '^[a-z0-9-]{2,60}$'),
  name text not null check (length(btrim(name)) between 2 and 100),
  version integer not null check (version > 0),
  is_default boolean not null default false,
  is_active boolean not null default true,
  configuration jsonb not null default '{}'::jsonb check (jsonb_typeof(configuration) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, document_type, template_key, version)
);
create unique index finance_document_templates_one_default
  on public.finance_document_templates (organization_id, document_type)
  where is_default and is_active;
create index finance_document_templates_list_idx
  on public.finance_document_templates (organization_id, document_type, is_active, name);
alter table public.finance_document_templates enable row level security;
revoke all on public.finance_document_templates from anon;
grant select, insert, update on public.finance_document_templates to authenticated;
create policy finance_document_templates_read on public.finance_document_templates for select to authenticated
  using (public.is_org_member(organization_id));
create policy finance_document_templates_write on public.finance_document_templates for all to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'))
  with check (public.has_org_permission(organization_id, 'finance.manage'));
create trigger finance_document_templates_updated_at before update on public.finance_document_templates
  for each row execute function public.set_updated_at();
create trigger finance_document_templates_audit after insert or update or delete on public.finance_document_templates
  for each row execute function public.write_audit_log();

alter table public.invoices
  add column document_template_id uuid,
  add column document_template_version integer,
  add column document_template_snapshot jsonb not null default '{}'::jsonb;
alter table public.invoices add constraint invoices_document_template_fkey
  foreign key (organization_id, document_template_id) references public.finance_document_templates(organization_id, id);
alter table public.quotations
  add column document_template_id uuid,
  add column document_template_version integer,
  add column document_template_snapshot jsonb not null default '{}'::jsonb;
alter table public.quotations add constraint quotations_document_template_fkey
  foreign key (organization_id, document_template_id) references public.finance_document_templates(organization_id, id);

create or replace function public.guard_document_template_snapshot()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.document_template_id is not distinct from old.document_template_id
    and new.document_template_version is not distinct from old.document_template_version
    and new.document_template_snapshot is not distinct from old.document_template_snapshot then
    return new;
  end if;
  if old.status <> 'draft' or old.document_template_snapshot <> '{}'::jsonb
    or new.document_template_id is null or new.document_template_version is null
    or jsonb_typeof(new.document_template_snapshot) <> 'object'
    or new.document_template_snapshot ->> 'id' is distinct from new.document_template_id::text
    or new.document_template_snapshot ->> 'version' is distinct from new.document_template_version::text
    or new.document_template_snapshot ->> 'name' is null then
    raise exception 'Document template snapshot can only be attached once to a draft';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_document_template_snapshot() from public, anon, authenticated;
create trigger invoices_guard_template_snapshot before update on public.invoices
  for each row execute function public.guard_document_template_snapshot();
create trigger quotations_guard_template_snapshot before update on public.quotations
  for each row execute function public.guard_document_template_snapshot();

create or replace function public.seed_finance_document_templates(target_org uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.finance_document_templates (organization_id, document_type, template_key, name, version, is_default, configuration)
  values
    (target_org, 'invoice', 'service-retainer', 'Service Retainer', 1, true,
      '{"style":"clean","accent":"#3474F5","line_groups":true,"show_tax_summary":true,"show_signature":true,"show_terms":true,"show_bank_details":false,"terms":[]}'::jsonb),
    (target_org, 'invoice', 'project-milestone', 'Project Milestone', 1, false,
      '{"style":"editorial","accent":"#7258D8","line_groups":true,"show_tax_summary":true,"show_signature":true,"show_terms":true,"show_bank_details":false,"terms":[]}'::jsonb),
    (target_org, 'invoice', 'one-time-service', 'One-time Service', 1, false,
      '{"style":"clean","accent":"#17A47B","line_groups":false,"show_tax_summary":true,"show_signature":true,"show_terms":true,"show_bank_details":false,"terms":[]}'::jsonb),
    (target_org, 'invoice', 'gst-tax-invoice', 'GST Invoice · tax setup required', 1, false,
      '{"style":"formal","accent":"#3474F5","line_groups":false,"show_tax_summary":true,"show_signature":true,"show_terms":true,"show_bank_details":false,"terms":[]}'::jsonb),
    (target_org, 'quotation', 'client-quotation', 'Client Quotation', 1, true,
      '{"style":"editorial","accent":"#7258D8","line_groups":true,"show_tax_summary":true,"show_signature":true,"show_terms":true,"show_bank_details":false,"terms":["This estimate is valid until the date shown on the quotation."]}'::jsonb)
  on conflict (organization_id, document_type, template_key, version) do nothing;
end;
$$;
revoke all on function public.seed_finance_document_templates(uuid) from public, anon, authenticated;
create or replace function public.seed_finance_document_templates_after_org_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.seed_finance_document_templates(new.id);
  return new;
end;
$$;
revoke all on function public.seed_finance_document_templates_after_org_insert() from public, anon, authenticated;
create trigger seed_finance_templates_on_org_insert after insert on public.organizations
  for each row execute function public.seed_finance_document_templates_after_org_insert();
select public.seed_finance_document_templates(o.id) from public.organizations o;

create or replace function public.create_finance_template_version(
  target_org uuid, source_template uuid, template_name text, accent_color text,
  template_style text, group_line_items boolean, show_tax boolean,
  show_signature boolean, show_terms boolean, set_as_default boolean
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare source_row public.finance_document_templates%rowtype; new_template_id uuid; next_version integer;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if length(btrim(template_name)) not between 2 and 100
    or accent_color !~ '^#[0-9A-Fa-f]{6}$'
    or template_style not in ('clean', 'editorial', 'formal') then
    raise exception 'Invalid template settings' using errcode = '22023';
  end if;
  select t.* into source_row from public.finance_document_templates t
    where t.organization_id = target_org and t.id = source_template and t.is_active for update;
  if not found then raise exception 'Template not found' using errcode = '42501'; end if;
  select coalesce(max(t.version), 0) + 1 into next_version from public.finance_document_templates t
    where t.organization_id = target_org and t.document_type = source_row.document_type and t.template_key = source_row.template_key;
  if set_as_default then
    update public.finance_document_templates set is_default = false
      where organization_id = target_org and document_type = source_row.document_type and is_default;
  end if;
  insert into public.finance_document_templates (organization_id, document_type, template_key, name, version, is_default, configuration, created_by)
  values (target_org, source_row.document_type, source_row.template_key, btrim(template_name), next_version, set_as_default,
    jsonb_build_object(
      'style', template_style, 'accent', accent_color, 'line_groups', group_line_items,
      'show_tax_summary', show_tax, 'show_signature', show_signature, 'show_terms', show_terms,
      'show_bank_details', false,
      'terms', coalesce(source_row.configuration -> 'terms', '[]'::jsonb)
    ), auth.uid())
  returning id into new_template_id;
  return new_template_id;
end;
$$;
revoke all on function public.create_finance_template_version(uuid, uuid, text, text, text, boolean, boolean, boolean, boolean, boolean) from public, anon;
grant execute on function public.create_finance_template_version(uuid, uuid, text, text, text, boolean, boolean, boolean, boolean, boolean) to authenticated;

create or replace function public.create_invoice_from_template(
  target_org uuid, target_client uuid, new_invoice_number text, invoice_currency char,
  invoice_tax numeric, new_issue_date date, new_due_date date,
  line_description text, line_quantity numeric, line_unit_price numeric, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare template_row public.finance_document_templates%rowtype; new_invoice_id uuid; snapshot jsonb;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if selected_template is null then
    select t.* into template_row from public.finance_document_templates t
      where t.organization_id = target_org and t.document_type = 'invoice' and t.is_default and t.is_active;
  else
    select t.* into template_row from public.finance_document_templates t
      where t.organization_id = target_org and t.id = selected_template and t.document_type = 'invoice' and t.is_active;
  end if;
  if not found then raise exception 'Select an active invoice template' using errcode = '22023'; end if;
  snapshot := jsonb_build_object('id', template_row.id, 'key', template_row.template_key, 'name', template_row.name,
    'type', template_row.document_type, 'version', template_row.version, 'configuration', template_row.configuration);
  new_invoice_id := public.create_invoice_with_item(target_org, target_client, new_invoice_number, invoice_currency,
    invoice_tax, new_issue_date, new_due_date, line_description, line_quantity, line_unit_price);
  update public.invoices set document_template_id = template_row.id, document_template_version = template_row.version,
    document_template_snapshot = snapshot where organization_id = target_org and id = new_invoice_id;
  return new_invoice_id;
end;
$$;

create or replace function public.create_quotation_from_template(
  target_org uuid, target_client uuid, new_quotation_number text, quote_currency char,
  quote_tax numeric, quote_issue_date date, quote_valid_until date,
  line_description text, line_quantity numeric, line_unit_price numeric, selected_template uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare template_row public.finance_document_templates%rowtype; new_quote_id uuid; snapshot jsonb;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if selected_template is null then
    select t.* into template_row from public.finance_document_templates t
      where t.organization_id = target_org and t.document_type = 'quotation' and t.is_default and t.is_active;
  else
    select t.* into template_row from public.finance_document_templates t
      where t.organization_id = target_org and t.id = selected_template and t.document_type = 'quotation' and t.is_active;
  end if;
  if not found then raise exception 'Select an active quotation template' using errcode = '22023'; end if;
  snapshot := jsonb_build_object('id', template_row.id, 'key', template_row.template_key, 'name', template_row.name,
    'type', template_row.document_type, 'version', template_row.version, 'configuration', template_row.configuration);
  new_quote_id := public.create_quotation_with_item(target_org, target_client, new_quotation_number, quote_currency,
    quote_tax, quote_issue_date, quote_valid_until, line_description, line_quantity, line_unit_price);
  update public.quotations set document_template_id = template_row.id, document_template_version = template_row.version,
    document_template_snapshot = snapshot where organization_id = target_org and id = new_quote_id;
  return new_quote_id;
end;
$$;

create or replace function public.copy_quotation_template_to_invoice()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source_quotation_id is not null then
    select q.document_template_id, q.document_template_version, q.document_template_snapshot
      into new.document_template_id, new.document_template_version, new.document_template_snapshot
    from public.quotations q where q.organization_id = new.organization_id and q.id = new.source_quotation_id;
    if not found then raise exception 'Source quotation not found'; end if;
  end if;
  return new;
end;
$$;
revoke all on function public.copy_quotation_template_to_invoice() from public, anon, authenticated;
create trigger copy_quotation_template_to_invoice before insert on public.invoices
  for each row execute function public.copy_quotation_template_to_invoice();

revoke all on function public.create_invoice_from_template(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric, uuid) from public, anon;
grant execute on function public.create_invoice_from_template(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric, uuid) to authenticated;
revoke all on function public.create_quotation_from_template(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric, uuid) from public, anon;
grant execute on function public.create_quotation_from_template(uuid, uuid, text, char, numeric, date, date, text, numeric, numeric, uuid) to authenticated;
