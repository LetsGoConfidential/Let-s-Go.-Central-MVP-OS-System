create table public.employee_kpi_goals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null,
  metric_key text not null check (metric_key in ('tasks_completed', 'tasks_on_time', 'leads_won')),
  title text not null check (char_length(trim(title)) between 2 and 120),
  target numeric(12,2) not null check (target > 0),
  unit text not null default 'count' check (unit in ('count', 'percent')),
  period_start date not null,
  period_end date not null,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  check (period_end >= period_start),
  check ((metric_key = 'tasks_on_time' and unit = 'percent' and target <= 100) or (metric_key <> 'tasks_on_time' and unit = 'count')),
  unique (organization_id, member_id, metric_key, period_start)
);

create index employee_kpi_goals_member_period_idx
  on public.employee_kpi_goals (organization_id, member_id, period_start desc);

revoke all on public.employee_kpi_goals from anon, authenticated;
grant select, insert, update on public.employee_kpi_goals to authenticated;
alter table public.employee_kpi_goals enable row level security;

create policy employee_kpi_read on public.employee_kpi_goals
  for select to authenticated using (
    member_id = auth.uid() and public.is_org_member(organization_id)
    or public.has_org_permission(organization_id, 'team.performance.manage')
  );
create policy employee_kpi_manager_insert on public.employee_kpi_goals
  for insert to authenticated with check (
    public.has_org_permission(organization_id, 'team.performance.manage')
    and created_by = auth.uid() and updated_by = auth.uid()
  );
create policy employee_kpi_manager_update on public.employee_kpi_goals
  for update to authenticated using (
    public.has_org_permission(organization_id, 'team.performance.manage')
  ) with check (
    public.has_org_permission(organization_id, 'team.performance.manage')
    and updated_by = auth.uid()
  );

create trigger employee_kpi_goals_updated_at
  before update on public.employee_kpi_goals
  for each row execute function public.set_updated_at();

create trigger audit_employee_kpi_goals
  after insert or update or delete on public.employee_kpi_goals
  for each row execute function public.write_audit_log();
