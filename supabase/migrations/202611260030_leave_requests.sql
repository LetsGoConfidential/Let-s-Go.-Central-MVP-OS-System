-- Leave access is deliberately separate from ordinary manager and payroll access.
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
    or (permission_doc - array['workspace.write', 'finance.manage', 'team.performance.manage', 'hr.leave.manage']) <> '{}'::jsonb
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

create table public.leave_requests (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null, leave_type text not null check (char_length(trim(leave_type)) between 2 and 40),
  start_date date not null, end_date date not null, reason text not null default '' check (char_length(reason) <= 2000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by uuid references auth.users(id) on delete set null, decided_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  check (end_date >= start_date),
  check ((status in ('approved','rejected') and decided_by is not null and decided_at is not null) or status in ('pending','cancelled'))
);
create index leave_requests_member_idx on public.leave_requests (organization_id, member_id, start_date desc);
create index leave_requests_queue_idx on public.leave_requests (organization_id, status, start_date);
revoke all on public.leave_requests from anon, authenticated;
grant select, insert, update on public.leave_requests to authenticated;
alter table public.leave_requests enable row level security;
create policy leave_requests_read on public.leave_requests for select to authenticated
  using ((member_id = auth.uid() and public.is_org_member(organization_id)) or public.has_org_permission(organization_id, 'hr.leave.manage'));
create policy leave_requests_employee_create on public.leave_requests for insert to authenticated
  with check (member_id = auth.uid() and status = 'pending' and decided_by is null and decided_at is null and public.is_org_member(organization_id));
create policy leave_requests_employee_cancel on public.leave_requests for update to authenticated
  using (member_id = auth.uid() and status = 'pending' and public.is_org_member(organization_id))
  with check (member_id = auth.uid() and status = 'cancelled' and decided_by is null and decided_at is null and public.is_org_member(organization_id));
create trigger leave_requests_updated_at before update on public.leave_requests for each row execute function public.set_updated_at();
create or replace function public.audit_leave_request_status()
returns trigger language plpgsql security definer set search_path = '' as $$
declare row_data jsonb; org_id uuid; record_id text; action_name text;
begin
  if tg_op = 'DELETE' then row_data = to_jsonb(old); else row_data = to_jsonb(new); end if;
  org_id = (row_data ->> 'organization_id')::uuid; record_id = row_data ->> 'id'; action_name = lower(tg_op);
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (org_id, auth.uid(), action_name, tg_table_name, record_id,
    jsonb_build_object('before', case when tg_op = 'INSERT' then null else jsonb_build_object('status', old.status, 'start_date', old.start_date, 'end_date', old.end_date, 'leave_type', old.leave_type) end,
      'after', case when tg_op = 'DELETE' then null else jsonb_build_object('status', new.status, 'start_date', new.start_date, 'end_date', new.end_date, 'leave_type', new.leave_type) end));
  if tg_op = 'DELETE' then return old; end if; return new;
end;
$$;
revoke all on function public.audit_leave_request_status() from public, anon, authenticated;
create trigger audit_leave_requests after insert or update or delete on public.leave_requests for each row execute function public.audit_leave_request_status();

create or replace function public.review_leave_request(target_org uuid, request_id uuid, decision text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); changed integer;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.leave.manage') then raise exception 'Not authorized to review leave requests' using errcode = '42501'; end if;
  if decision not in ('approved','rejected') then raise exception 'Invalid leave decision' using errcode = '22023'; end if;
  update public.leave_requests set status = decision, decided_by = actor_id, decided_at = now() where id = request_id and organization_id = target_org and status = 'pending';
  get diagnostics changed = row_count;
  return changed = 1;
end;
$$;
revoke all on function public.review_leave_request(uuid, uuid, text) from public, anon;
grant execute on function public.review_leave_request(uuid, uuid, text) to authenticated;
