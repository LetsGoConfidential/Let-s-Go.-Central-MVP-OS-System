-- Daily self-service attendance. HR access is separately grantable; managers do not inherit it.
create or replace function public.has_org_permission(target_org uuid, permission_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
      and m.role <> 'client'
      and (m.role in ('owner', 'admin')
        or (m.role = 'manager' and permission_key not in ('organization.manage', 'finance.manage', 'members.manage', 'hr.leave.manage', 'hr.attendance.manage', 'hr.payroll.manage'))
        or exists (select 1 from public.role_assignments ra join public.roles r on r.id = ra.role_id
          where ra.organization_id = m.organization_id and ra.user_id = m.user_id
            and coalesce((r.permissions ->> permission_key)::boolean, false)))
  );
$$;

create or replace function public.save_custom_role(target_org uuid, role_name text, permission_doc jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare role_id uuid; actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then raise exception 'Not authorized to manage organization roles' using errcode = '42501'; end if;
  if role_name is null or length(trim(role_name)) < 2 or length(trim(role_name)) > 80
    or permission_doc is null or jsonb_typeof(permission_doc) <> 'object'
    or (permission_doc - array['workspace.write', 'finance.manage', 'team.performance.manage', 'hr.leave.manage', 'hr.attendance.manage']) <> '{}'::jsonb
    or exists (select 1 from jsonb_each(permission_doc) p where jsonb_typeof(p.value) <> 'boolean') then
    raise exception 'Invalid custom role definition' using errcode = '22023';
  end if;
  select r.id into role_id from public.roles r where r.organization_id = target_org and lower(r.name) = lower(trim(role_name)) and not r.is_system;
  if role_id is null then
    insert into public.roles (organization_id, name, is_system, permissions) values (target_org, trim(role_name), false, permission_doc) returning id into role_id;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes) values (target_org, actor_id, 'create', 'roles', role_id::text, jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  else
    update public.roles set permissions = permission_doc where id = role_id and organization_id = target_org;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes) values (target_org, actor_id, 'update', 'roles', role_id::text, jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  end if;
  return role_id;
end;
$$;

create table public.attendance_days (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null, work_date date not null, checked_in_at timestamptz not null, checked_out_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  unique (organization_id, member_id, work_date), check (checked_out_at is null or checked_out_at >= checked_in_at)
);
create index attendance_days_org_date_idx on public.attendance_days(organization_id, work_date desc);
revoke all on public.attendance_days from anon, authenticated;
grant select on public.attendance_days to authenticated;
alter table public.attendance_days enable row level security;
create policy attendance_days_read on public.attendance_days for select to authenticated
  using ((member_id = auth.uid() and public.is_org_member(organization_id)) or public.has_org_permission(organization_id, 'hr.attendance.manage'));
create trigger attendance_days_updated_at before update on public.attendance_days for each row execute function public.set_updated_at();
create trigger audit_attendance_days after insert or update or delete on public.attendance_days for each row execute function public.write_audit_log();

create or replace function public.record_attendance(target_org uuid, action_name text)
returns public.attendance_days language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); day_value date; row_value public.attendance_days%rowtype;
begin
  if actor_id is null or not public.is_org_member(target_org) then raise exception 'Not authorized to record attendance' using errcode = '42501'; end if;
  if action_name not in ('check_in', 'check_out') then raise exception 'Invalid attendance action' using errcode = '22023'; end if;
  select (now() at time zone o.timezone)::date into day_value from public.organizations o where o.id = target_org;
  if action_name = 'check_in' then
    insert into public.attendance_days(organization_id, member_id, work_date, checked_in_at)
      values (target_org, actor_id, day_value, now()) on conflict (organization_id, member_id, work_date) do nothing;
  else
    update public.attendance_days set checked_out_at = now() where organization_id = target_org and member_id = actor_id and work_date = day_value and checked_out_at is null;
    if not found then raise exception 'No open attendance record for today' using errcode = '22023'; end if;
  end if;
  select * into row_value from public.attendance_days where organization_id = target_org and member_id = actor_id and work_date = day_value;
  return row_value;
end;
$$;
revoke all on function public.record_attendance(uuid, text) from public, anon;
grant execute on function public.record_attendance(uuid, text) to authenticated;
