-- Monthly payroll drafts snapshot approved compensation. This is a human-
-- reviewed ledger, not a tax calculator or a bank-payment integration.
create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'paid')),
  created_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  paid_by uuid references auth.users(id),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_start = date_trunc('month', period_start)::date
    and period_end = (period_start + interval '1 month' - interval '1 day')::date),
  check (
    (status = 'draft' and approved_by is null and approved_at is null and paid_by is null and paid_at is null)
    or (status = 'approved' and approved_by is not null and approved_at is not null and paid_by is null and paid_at is null)
    or (status = 'paid' and approved_by is not null and approved_at is not null and paid_by is not null and paid_at is not null)
  ),
  unique (organization_id, period_start),
  unique (organization_id, id)
);
create index payroll_runs_org_period_idx on public.payroll_runs (organization_id, period_start desc);

create table public.payroll_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  payroll_run_id uuid not null,
  member_id uuid not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  base_salary numeric(14, 2) not null check (base_salary >= 0),
  monthly_allowance numeric(14, 2) not null default 0 check (monthly_allowance >= 0),
  bonus_paid numeric(14, 2) not null default 0 check (bonus_paid >= 0),
  other_additions numeric(14, 2) not null default 0 check (other_additions >= 0),
  deductions numeric(14, 2) not null default 0 check (deductions >= 0),
  net_pay numeric(14, 2) generated always as (base_salary + monthly_allowance + bonus_paid + other_additions - deductions) stored,
  adjustment_note text not null default '' check (char_length(adjustment_note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, payroll_run_id) references public.payroll_runs(organization_id, id) on delete cascade,
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  check (deductions <= base_salary + monthly_allowance + bonus_paid + other_additions),
  unique (organization_id, payroll_run_id, member_id),
  unique (organization_id, id)
);
create index payroll_entries_member_period_idx on public.payroll_entries (organization_id, member_id, payroll_run_id);

revoke all on public.payroll_runs, public.payroll_entries from anon, authenticated;
grant select on public.payroll_runs, public.payroll_entries to authenticated;
alter table public.payroll_runs enable row level security;
alter table public.payroll_entries enable row level security;
create policy payroll_entries_read on public.payroll_entries for select to authenticated
  using ((member_id = (select auth.uid()) and public.is_org_member(organization_id))
    or public.has_org_permission(organization_id, 'hr.payroll.manage'));
create policy payroll_runs_read on public.payroll_runs for select to authenticated
  using (public.has_org_permission(organization_id, 'hr.payroll.manage')
    or (public.is_org_member(organization_id) and exists (
      select 1 from public.payroll_entries e
      where e.organization_id = payroll_runs.organization_id and e.payroll_run_id = payroll_runs.id
        and e.member_id = (select auth.uid())
    )));
create trigger payroll_runs_updated_at before update on public.payroll_runs
  for each row execute function public.set_updated_at();
create trigger payroll_entries_updated_at before update on public.payroll_entries
  for each row execute function public.set_updated_at();

create or replace function public.create_payroll_run(target_org uuid, target_period_start date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); run_id uuid; entry_count integer;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.payroll.manage') then
    raise exception 'Not authorized to manage payroll' using errcode = '42501';
  end if;
  if target_period_start is null or target_period_start <> date_trunc('month', target_period_start)::date then
    raise exception 'Payroll period must start on the first of a month' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_org::text || ':' || target_period_start::text, 0));
  insert into public.payroll_runs (organization_id, period_start, period_end, created_by)
  values (target_org, target_period_start, (target_period_start + interval '1 month' - interval '1 day')::date, actor_id)
  returning id into run_id;

  insert into public.payroll_entries (
    organization_id, payroll_run_id, member_id, currency, base_salary, monthly_allowance
  )
  select target_org, run_id, selected.member_id, selected.currency, selected.monthly_base, selected.monthly_allowance
  from (
    select distinct on (c.member_id) c.member_id, c.currency, c.monthly_base, c.monthly_allowance
    from public.employee_compensation c
    join public.org_members m on m.organization_id = c.organization_id and m.user_id = c.member_id
    where c.organization_id = target_org and m.status = 'active' and m.role <> 'client'
      and c.effective_from <= target_period_start
      and (c.effective_to is null or c.effective_to >= target_period_start)
    order by c.member_id, c.effective_from desc
  ) selected;

  get diagnostics entry_count = row_count;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'create', 'payroll_runs', run_id::text,
    jsonb_build_object('period_start', target_period_start, 'entry_count', entry_count));
  return run_id;
exception when unique_violation then
  raise exception 'A payroll run already exists for this month' using errcode = '23505';
end;
$$;
revoke all on function public.create_payroll_run(uuid, date) from public, anon;
grant execute on function public.create_payroll_run(uuid, date) to authenticated;

create or replace function public.update_payroll_entry(
  target_org uuid,
  target_entry uuid,
  target_bonus_paid numeric,
  target_other_additions numeric,
  target_deductions numeric,
  target_adjustment_note text
) returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); entry_row public.payroll_entries%rowtype; period_value date;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.payroll.manage') then
    raise exception 'Not authorized to manage payroll' using errcode = '42501';
  end if;
  if target_bonus_paid is null or target_bonus_paid < 0 or target_other_additions is null or target_other_additions < 0
    or target_deductions is null or target_deductions < 0 or target_adjustment_note is null
    or char_length(target_adjustment_note) > 500 then
    raise exception 'Invalid payroll adjustments' using errcode = '22023';
  end if;
  select e.* into entry_row
  from public.payroll_entries e join public.payroll_runs r
    on r.organization_id = e.organization_id and r.id = e.payroll_run_id
  where e.organization_id = target_org and e.id = target_entry and r.status = 'draft'
  for update of e, r;
  if not found then raise exception 'Draft payroll entry not found' using errcode = '42501'; end if;
  select r.period_start into period_value from public.payroll_runs r
  where r.organization_id = target_org and r.id = entry_row.payroll_run_id;
  if target_deductions > entry_row.base_salary + entry_row.monthly_allowance + target_bonus_paid + target_other_additions then
    raise exception 'Deductions cannot exceed gross pay' using errcode = '22023';
  end if;

  update public.payroll_entries set bonus_paid = target_bonus_paid,
    other_additions = target_other_additions, deductions = target_deductions,
    adjustment_note = trim(target_adjustment_note)
  where organization_id = target_org and id = target_entry;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'update', 'payroll_entries', target_entry::text,
    jsonb_build_object('member_id', entry_row.member_id, 'period_start', period_value,
      'fields', jsonb_build_array('bonus_paid', 'other_additions', 'deductions', 'adjustment_note')));
  return true;
end;
$$;
revoke all on function public.update_payroll_entry(uuid, uuid, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.update_payroll_entry(uuid, uuid, numeric, numeric, numeric, text) to authenticated;

create or replace function public.transition_payroll_run(target_org uuid, target_run uuid, decision text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); run_row public.payroll_runs%rowtype; entry_count integer;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.payroll.manage') then
    raise exception 'Not authorized to manage payroll' using errcode = '42501';
  end if;
  if decision is null or decision not in ('approve', 'mark_paid') then
    raise exception 'Invalid payroll decision' using errcode = '22023';
  end if;
  select r.* into run_row from public.payroll_runs r
  where r.organization_id = target_org and r.id = target_run for update;
  if not found then raise exception 'Payroll run not found' using errcode = '42501'; end if;
  select count(*)::integer into entry_count from public.payroll_entries e
  where e.organization_id = target_org and e.payroll_run_id = target_run;

  if decision = 'approve' then
    if run_row.status <> 'draft' or entry_count = 0 then
      raise exception 'Only a non-empty draft payroll run can be approved' using errcode = '22023';
    end if;
    update public.payroll_runs set status = 'approved', approved_by = actor_id, approved_at = now()
    where organization_id = target_org and id = target_run;
  else
    if run_row.status <> 'approved' then
      raise exception 'Only an approved payroll run can be marked paid' using errcode = '22023';
    end if;
    update public.payroll_runs set status = 'paid', paid_by = actor_id, paid_at = now()
    where organization_id = target_org and id = target_run;
  end if;

  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, decision, 'payroll_runs', target_run::text,
    jsonb_build_object('period_start', run_row.period_start, 'entry_count', entry_count));
  return true;
end;
$$;
revoke all on function public.transition_payroll_run(uuid, uuid, text) from public, anon;
grant execute on function public.transition_payroll_run(uuid, uuid, text) to authenticated;
