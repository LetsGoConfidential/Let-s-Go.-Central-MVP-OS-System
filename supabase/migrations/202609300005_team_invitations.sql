create table public.org_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  email extensions.citext not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.member_role not null check (role in ('admin', 'manager', 'member')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked')),
  invited_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (organization_id, email)
);

alter table public.org_invitations enable row level security;
revoke all on public.org_invitations from anon, authenticated;
grant select on public.org_invitations to authenticated;
create policy org_invitation_manager_read on public.org_invitations for select to authenticated
  using (public.has_org_permission(organization_id, 'members.manage'));

create or replace function public.store_org_invitation(
  target_org uuid,
  invite_email extensions.citext,
  invited_user uuid,
  assigned_role public.member_role,
  actor_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare invitation_id uuid;
begin
  if assigned_role not in ('admin', 'manager', 'member') then
    raise exception 'Invalid invite role' using errcode = '22023';
  end if;
  if not exists (select 1 from public.organizations o where o.id = target_org) then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;
  insert into public.org_members as current_member (organization_id, user_id, role, status, joined_at)
  values (target_org, invited_user, assigned_role, 'invited', null)
  on conflict (organization_id, user_id) do update
    set role = excluded.role, status = 'invited', joined_at = null
    where current_member.status <> 'active';
  if not found then
    raise exception 'User is already an active organization member' using errcode = '23505';
  end if;
  insert into public.org_invitations (organization_id, email, user_id, role, invited_by)
  values (target_org, invite_email, invited_user, assigned_role, actor_id)
  on conflict (organization_id, email) do update
    set user_id = excluded.user_id, role = excluded.role, status = 'pending', invited_by = excluded.invited_by,
        created_at = now(), accepted_at = null
  returning id into invitation_id;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'invite', 'org_members', invited_user::text,
    jsonb_build_object('email', invite_email::text, 'role', assigned_role, 'status', 'pending'));
  return invitation_id;
end;
$$;
revoke all on function public.store_org_invitation(uuid, extensions.citext, uuid, public.member_role, uuid) from public, anon, authenticated;
grant execute on function public.store_org_invitation(uuid, extensions.citext, uuid, public.member_role, uuid) to service_role;

create or replace function public.accept_org_invitation(target_org uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare accepted_user uuid := auth.uid();
begin
  if accepted_user is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  update public.org_members m
  set status = 'active', joined_at = now()
  from public.org_invitations i
  where i.organization_id = target_org and i.user_id = accepted_user and i.status = 'pending'
    and lower(i.email::text) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and m.organization_id = i.organization_id and m.user_id = i.user_id and m.status = 'invited';
  if not found then return false; end if;
  update public.org_invitations set status = 'accepted', accepted_at = now()
  where organization_id = target_org and user_id = accepted_user and status = 'pending';
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, accepted_user, 'accept_invitation', 'org_members', accepted_user::text,
    jsonb_build_object('status', 'active'));
  return true;
end;
$$;
revoke all on function public.accept_org_invitation(uuid) from public, anon;
grant execute on function public.accept_org_invitation(uuid) to authenticated;

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
  if actor_id is null or not public.has_org_permission(target_org, 'members.manage') then
    raise exception 'Not authorized to manage organization members' using errcode = '42501';
  end if;
  if target_user = actor_id then
    raise exception 'You cannot change your own membership here' using errcode = '42501';
  end if;
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
revoke all on function public.manage_org_member(uuid, uuid, public.member_role, text) from public, anon;
grant execute on function public.manage_org_member(uuid, uuid, public.member_role, text) to authenticated;

create or replace function public.revoke_org_invitation(target_org uuid, invitation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_row public.org_invitations%rowtype;
  actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'members.manage') then
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
revoke all on function public.revoke_org_invitation(uuid, uuid) from public, anon;
grant execute on function public.revoke_org_invitation(uuid, uuid) to authenticated;
