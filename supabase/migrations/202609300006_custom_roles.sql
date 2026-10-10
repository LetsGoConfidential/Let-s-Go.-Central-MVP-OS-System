-- Membership and invitation administration stays reserved for organization owners/admins.
drop policy org_invitation_manager_read on public.org_invitations;
create policy org_invitation_admin_read on public.org_invitations for select to authenticated
  using (public.has_org_permission(organization_id, 'organization.manage'));

-- Remove any legacy custom grant that could otherwise confer admin control.
update public.roles
set permissions = permissions - array['organization.manage', 'members.manage']
where not is_system and permissions ?| array['organization.manage', 'members.manage'];

create or replace function public.manage_org_member(
  target_org uuid,
  target_user uuid,
  new_role public.member_role,
  new_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_row public.org_members%rowtype;
  actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to manage organization members' using errcode = '42501';
  end if;
  if target_user = actor_id then raise exception 'You cannot change your own membership here' using errcode = '42501'; end if;
  if new_role not in ('admin', 'manager', 'member') or new_status not in ('active', 'suspended') then
    raise exception 'Invalid member role or status' using errcode = '22023';
  end if;
  select * into member_row from public.org_members
    where organization_id = target_org and user_id = target_user for update;
  if not found or member_row.status = 'invited' then return false; end if;
  if member_row.role = 'owner' then
    raise exception 'Owner membership must be transferred through a separate workflow' using errcode = '42501';
  end if;
  update public.org_members set role = new_role, status = new_status
    where organization_id = target_org and user_id = target_user;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'update', 'org_members', target_user::text,
    jsonb_build_object('before', jsonb_build_object('role', member_row.role, 'status', member_row.status),
      'after', jsonb_build_object('role', new_role, 'status', new_status)));
  return true;
end;
$$;

create or replace function public.revoke_org_invitation(target_org uuid, invitation_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  invitation_row public.org_invitations%rowtype;
  actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to manage organization invitations' using errcode = '42501';
  end if;
  update public.org_invitations set status = 'revoked'
  where id = invitation_id and organization_id = target_org and status = 'pending'
  returning * into invitation_row;
  if not found then return false; end if;
  update public.org_members set status = 'suspended'
  where organization_id = target_org and user_id = invitation_row.user_id and status = 'invited';
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'revoke_invitation', 'org_members', invitation_row.user_id::text,
    jsonb_build_object('email', invitation_row.email::text, 'role', invitation_row.role));
  return true;
end;
$$;

create or replace function public.save_custom_role(target_org uuid, role_name text, permission_doc jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  role_id uuid;
  actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to manage organization roles' using errcode = '42501';
  end if;
  if role_name is null or length(trim(role_name)) < 2 or length(trim(role_name)) > 80
    or permission_doc is null or jsonb_typeof(permission_doc) <> 'object'
    or (permission_doc - array['workspace.write', 'finance.manage']) <> '{}'::jsonb
    or exists (select 1 from jsonb_each(permission_doc) p where jsonb_typeof(p.value) <> 'boolean') then
    raise exception 'Invalid custom role definition' using errcode = '22023';
  end if;
  select r.id into role_id from public.roles r
  where r.organization_id = target_org and lower(r.name) = lower(trim(role_name)) and not r.is_system;
  if role_id is null then
    insert into public.roles (organization_id, name, is_system, permissions)
    values (target_org, trim(role_name), false, permission_doc)
    returning id into role_id;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
    values (target_org, actor_id, 'create', 'roles', role_id::text,
      jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  else
    update public.roles set permissions = permission_doc where id = role_id and organization_id = target_org;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
    values (target_org, actor_id, 'update', 'roles', role_id::text,
      jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  end if;
  return role_id;
end;
$$;

create or replace function public.assign_custom_role(target_org uuid, target_user uuid, target_role uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  old_role_ids uuid[];
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to assign organization roles' using errcode = '42501';
  end if;
  if target_user = actor_id then raise exception 'You cannot change your own role assignment here' using errcode = '42501'; end if;
  if not exists (select 1 from public.org_members m where m.organization_id = target_org and m.user_id = target_user and m.status = 'active' and m.role <> 'owner') then
    raise exception 'Target must be an active non-owner member' using errcode = '22023';
  end if;
  if target_role is not null and not exists (select 1 from public.roles r where r.id = target_role and r.organization_id = target_org and not r.is_system) then
    raise exception 'Role must be a custom role in this organization' using errcode = '22023';
  end if;
  select coalesce(array_agg(ra.role_id), array[]::uuid[]) into old_role_ids
  from public.role_assignments ra join public.roles r on r.id = ra.role_id
  where ra.organization_id = target_org and ra.user_id = target_user and not r.is_system;
  delete from public.role_assignments ra using public.roles r
  where ra.organization_id = target_org and ra.user_id = target_user and r.id = ra.role_id and not r.is_system;
  if target_role is not null then
    insert into public.role_assignments (organization_id, user_id, role_id) values (target_org, target_user, target_role);
  end if;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'assign_role', 'role_assignments', target_user::text,
    jsonb_build_object('before_role_ids', to_jsonb(old_role_ids), 'role_id', target_role));
  return true;
end;
$$;

revoke all on function public.save_custom_role(uuid, text, jsonb) from public, anon;
revoke all on function public.assign_custom_role(uuid, uuid, uuid) from public, anon;
grant execute on function public.save_custom_role(uuid, text, jsonb) to authenticated;
grant execute on function public.assign_custom_role(uuid, uuid, uuid) to authenticated;
