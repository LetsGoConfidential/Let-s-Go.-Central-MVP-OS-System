-- Members can update progress on tasks assigned to themselves without workspace-wide write access.
create or replace function public.save_custom_role(target_org uuid, role_name text, permission_doc jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare role_id uuid; actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then raise exception 'Not authorized to manage organization roles' using errcode = '42501'; end if;
  if role_name is null or length(trim(role_name)) < 2 or length(trim(role_name)) > 80
    or permission_doc is null or jsonb_typeof(permission_doc) <> 'object'
    or (permission_doc - array['workspace.write', 'finance.manage', 'team.performance.manage', 'hr.leave.manage', 'hr.attendance.manage', 'hr.people.invite', 'tasks.self.update']) <> '{}'::jsonb
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

create or replace function public.set_assigned_task_status(target_org uuid, target_task uuid, new_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'tasks.self.update') then
    raise exception 'Not authorized to update assigned tasks' using errcode = '42501';
  end if;
  if new_status is null or new_status not in ('todo', 'in_progress', 'blocked', 'done') then
    raise exception 'Invalid task status' using errcode = '22023';
  end if;
  update public.tasks
  set status = new_status::public.task_status,
      completed_at = case
        when new_status <> 'done' then null
        when status <> 'done' then now()
        else completed_at
      end
  where organization_id = target_org and id = target_task and assignee_id = actor_id;
  if not found then raise exception 'Assigned task not found' using errcode = '42501'; end if;
  return true;
end;
$$;
revoke all on function public.set_assigned_task_status(uuid, uuid, text) from public, anon;
grant execute on function public.set_assigned_task_status(uuid, uuid, text) to authenticated;

drop policy tenant_read on public.tasks;
create policy task_tenant_read on public.tasks for select to authenticated
  using (
    public.is_org_member(organization_id)
    and (
      public.has_org_permission(organization_id, 'workspace.write')
      or not public.has_org_permission(organization_id, 'tasks.self.update')
      or assignee_id = (select auth.uid())
    )
  );

drop policy task_comments_member_read on public.task_comments;
create policy task_comments_member_read on public.task_comments
  for select to authenticated using (
    public.is_org_member(organization_id)
    and (
      public.has_org_permission(organization_id, 'workspace.write')
      or not public.has_org_permission(organization_id, 'tasks.self.update')
      or exists (
        select 1 from public.tasks t
        where t.organization_id = task_comments.organization_id
          and t.id = task_comments.task_id and t.assignee_id = (select auth.uid())
      )
    )
  );

drop policy task_comments_writer_insert on public.task_comments;
create policy task_comments_writer_insert on public.task_comments
  for insert to authenticated with check (
    author_id = (select auth.uid()) and (
      public.has_org_permission(organization_id, 'workspace.write')
      or (public.has_org_permission(organization_id, 'tasks.self.update') and exists (
        select 1 from public.tasks t
        where t.organization_id = task_comments.organization_id
          and t.id = task_comments.task_id and t.assignee_id = (select auth.uid())
      ))
    )
  );
