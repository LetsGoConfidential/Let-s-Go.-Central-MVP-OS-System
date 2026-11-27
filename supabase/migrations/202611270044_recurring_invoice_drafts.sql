create table public.recurring_invoice_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_invoice_id uuid not null,
  client_id uuid not null,
  document_template_id uuid,
  invoice_prefix text not null check (invoice_prefix ~ '^[A-Za-z0-9-]{2,20}$'),
  currency char(3) not null check (currency ~ '^[A-Z]{3}$'),
  tax numeric(14,2) not null check (tax >= 0),
  due_after_days smallint not null default 7 check (due_after_days between 0 and 365),
  purchase_order_number text not null default '' check (char_length(btrim(purchase_order_number)) <= 60),
  custom_fields jsonb not null default '[]'::jsonb check (public.finance_custom_fields_valid(custom_fields)),
  document_notes text not null default '' check (char_length(document_notes) <= 2000),
  document_terms text not null default '' check (char_length(document_terms) <= 5000),
  signature_label text not null default '' check (char_length(signature_label) <= 80),
  line_items jsonb not null check (case when jsonb_typeof(line_items) = 'array' then jsonb_array_length(line_items) between 1 and 50 else false end),
  cadence text not null check (cadence in ('monthly', 'quarterly', 'yearly')),
  first_invoice_on date not null,
  next_invoice_on date not null,
  ends_on date,
  generated_count integer not null default 0 check (generated_count >= 0),
  status text not null default 'active' check (status in ('active', 'paused', 'completed')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, source_invoice_id) references public.invoices(organization_id, id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id),
  foreign key (organization_id, document_template_id) references public.finance_document_templates(organization_id, id),
  check (ends_on is null or ends_on >= first_invoice_on)
);
create index recurring_invoice_schedules_due_idx
  on public.recurring_invoice_schedules (organization_id, next_invoice_on, id) where status = 'active';
alter table public.recurring_invoice_schedules enable row level security;
revoke all on public.recurring_invoice_schedules from anon, authenticated;
grant select on public.recurring_invoice_schedules to authenticated;
create policy recurring_invoice_schedules_finance_read on public.recurring_invoice_schedules for select to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'));
create trigger recurring_invoice_schedules_updated_at before update on public.recurring_invoice_schedules
  for each row execute function public.set_updated_at();
create trigger recurring_invoice_schedules_audit after insert or update on public.recurring_invoice_schedules
  for each row execute function public.write_audit_log();

create table public.recurring_invoice_occurrences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  schedule_id uuid not null,
  invoice_id uuid not null,
  issue_date date not null,
  invoice_number text not null,
  created_at timestamptz not null default now(),
  unique (organization_id, schedule_id, issue_date),
  unique (organization_id, invoice_id),
  foreign key (organization_id, schedule_id) references public.recurring_invoice_schedules(organization_id, id) on delete cascade,
  foreign key (organization_id, invoice_id) references public.invoices(organization_id, id) on delete cascade
);
create index recurring_invoice_occurrences_schedule_idx
  on public.recurring_invoice_occurrences (organization_id, schedule_id, issue_date desc);
alter table public.recurring_invoice_occurrences enable row level security;
revoke all on public.recurring_invoice_occurrences from anon, authenticated;
grant select on public.recurring_invoice_occurrences to authenticated;
create policy recurring_invoice_occurrences_finance_read on public.recurring_invoice_occurrences for select to authenticated
  using (public.has_org_permission(organization_id, 'finance.manage'));
create trigger recurring_invoice_occurrences_audit after insert on public.recurring_invoice_occurrences
  for each row execute function public.write_audit_log();

create function public.create_recurring_invoice_schedule(
  target_org uuid, source_invoice uuid, invoice_cadence text, first_run date, end_on date, number_prefix text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare source_row public.invoices%rowtype; source_items jsonb; active_template uuid; new_schedule_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if invoice_cadence not in ('monthly', 'quarterly', 'yearly') or first_run is null
    or (end_on is not null and end_on < first_run)
    or number_prefix is null or number_prefix !~ '^[A-Za-z0-9-]{2,20}$' then
    raise exception 'Invalid recurring invoice schedule' using errcode = '22023';
  end if;
  select i.* into source_row from public.invoices i
    where i.organization_id = target_org and i.id = source_invoice and i.status <> 'void';
  if not found then raise exception 'Source invoice not found' using errcode = '42501'; end if;
  select jsonb_agg(jsonb_build_object(
    'group_name', it.group_name, 'description', it.description, 'quantity', it.quantity,
    'unit', it.unit, 'unit_price', it.unit_price
  ) order by it.created_at, it.id) into source_items
  from public.invoice_items it where it.organization_id = target_org and it.invoice_id = source_invoice;
  if source_items is null or jsonb_array_length(source_items) not between 1 and 50 then
    raise exception 'Source invoice must contain between one and fifty lines' using errcode = '22023';
  end if;
  select t.id into active_template from public.finance_document_templates t
    where t.organization_id = target_org and t.document_type = 'invoice' and t.is_active
      and t.id = source_row.document_template_id;
  if active_template is null then
    select t.id into active_template from public.finance_document_templates t
      where t.organization_id = target_org and t.document_type = 'invoice' and t.is_active and t.is_default;
  end if;
  if active_template is null then raise exception 'Choose an active invoice template first' using errcode = '22023'; end if;

  insert into public.recurring_invoice_schedules (
    organization_id, source_invoice_id, client_id, document_template_id, invoice_prefix, currency, tax,
    due_after_days, purchase_order_number, custom_fields, document_notes, document_terms,
    signature_label, line_items, cadence, first_invoice_on, next_invoice_on, ends_on, created_by
  ) values (
    target_org, source_invoice, source_row.client_id, active_template, btrim(number_prefix), source_row.currency,
    source_row.tax, greatest(0, coalesce(source_row.due_date - source_row.issue_date, 7)), source_row.purchase_order_number,
    source_row.custom_fields, source_row.document_notes, source_row.document_terms, source_row.signature_label,
    source_items, invoice_cadence, first_run, first_run, end_on, auth.uid()
  ) returning id into new_schedule_id;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, auth.uid(), 'create', 'recurring_invoice_schedules', new_schedule_id::text,
    jsonb_build_object('source_invoice_id', source_invoice, 'cadence', invoice_cadence, 'first_invoice_on', first_run, 'ends_on', end_on));
  return new_schedule_id;
end;
$$;

create function public.generate_due_recurring_invoice_drafts(
  target_org uuid, through_date date, batch_limit integer default 10
)
returns integer language plpgsql security definer set search_path = '' as $$
declare schedule_row public.recurring_invoice_schedules%rowtype; existing_invoice uuid;
  issue_on date; due_on date; next_on date; cadence_months integer; created_count integer := 0; schedule_count integer := 0;
  next_count integer; invoice_number text; new_invoice_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if through_date is null or batch_limit not between 1 and 50 then
    raise exception 'Invalid recurring invoice generation window' using errcode = '22023';
  end if;
  for schedule_row in
    select s.* from public.recurring_invoice_schedules s
    where s.organization_id = target_org and s.status = 'active' and s.next_invoice_on <= through_date
    order by s.next_invoice_on, s.id for update skip locked limit batch_limit
  loop
    cadence_months := case schedule_row.cadence when 'monthly' then 1 when 'quarterly' then 3 else 12 end;
    issue_on := schedule_row.next_invoice_on;
    while issue_on <= through_date and created_count < batch_limit loop
      if schedule_row.ends_on is not null and issue_on > schedule_row.ends_on then
        update public.recurring_invoice_schedules set status = 'completed'
          where organization_id = target_org and id = schedule_row.id;
        exit;
      end if;
      select o.invoice_id into existing_invoice from public.recurring_invoice_occurrences o
        where o.organization_id = target_org and o.schedule_id = schedule_row.id and o.issue_date = issue_on;
      next_count := schedule_row.generated_count + 1;
      next_on := (schedule_row.first_invoice_on + make_interval(months => next_count * cadence_months))::date;
      if existing_invoice is null then
        due_on := issue_on + schedule_row.due_after_days;
        invoice_number := schedule_row.invoice_prefix || '-' || upper(substr(replace(schedule_row.id::text, '-', ''), 1, 6)) || '-' || to_char(issue_on, 'YYYYMMDD');
        new_invoice_id := public.create_invoice_document_from_template(
          target_org, schedule_row.client_id, invoice_number, schedule_row.currency, schedule_row.tax,
          issue_on, due_on, schedule_row.line_items, schedule_row.purchase_order_number,
          schedule_row.custom_fields, schedule_row.document_notes, schedule_row.document_terms,
          schedule_row.signature_label, schedule_row.document_template_id
        );
        insert into public.recurring_invoice_occurrences (organization_id, schedule_id, invoice_id, issue_date, invoice_number)
        values (target_org, schedule_row.id, new_invoice_id, issue_on, invoice_number);
        created_count := created_count + 1;
      end if;
      update public.recurring_invoice_schedules set generated_count = next_count, next_invoice_on = next_on,
        status = case when ends_on is not null and next_on > ends_on then 'completed' else status end
        where organization_id = target_org and id = schedule_row.id;
      schedule_row.generated_count := next_count;
      schedule_row.next_invoice_on := next_on;
      if schedule_row.status = 'completed' then exit; end if;
      issue_on := next_on;
      existing_invoice := null;
    end loop;
    schedule_count := schedule_count + 1;
    if created_count >= batch_limit then exit; end if;
    if schedule_count >= batch_limit then exit; end if;
  end loop;
  return created_count;
end;
$$;

create function public.set_recurring_invoice_schedule_status(target_org uuid, target_schedule uuid, new_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare old_status text;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'finance.manage') then
    raise exception 'Finance permission required' using errcode = '42501';
  end if;
  if new_status not in ('active', 'paused') then raise exception 'Invalid schedule status' using errcode = '22023'; end if;
  select s.status into old_status from public.recurring_invoice_schedules s
    where s.organization_id = target_org and s.id = target_schedule for update;
  if not found or old_status = 'completed' then return false; end if;
  update public.recurring_invoice_schedules set status = new_status
    where organization_id = target_org and id = target_schedule;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, auth.uid(), 'status_change', 'recurring_invoice_schedules', target_schedule::text,
    jsonb_build_object('before', old_status, 'after', new_status));
  return true;
end;
$$;

revoke all on function public.create_recurring_invoice_schedule(uuid, uuid, text, date, date, text) from public, anon;
grant execute on function public.create_recurring_invoice_schedule(uuid, uuid, text, date, date, text) to authenticated;
revoke all on function public.generate_due_recurring_invoice_drafts(uuid, date, integer) from public, anon;
grant execute on function public.generate_due_recurring_invoice_drafts(uuid, date, integer) to authenticated;
revoke all on function public.set_recurring_invoice_schedule_status(uuid, uuid, text) from public, anon;
grant execute on function public.set_recurring_invoice_schedule_status(uuid, uuid, text) to authenticated;
