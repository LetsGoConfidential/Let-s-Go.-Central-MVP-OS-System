create unique index org_members_one_active_owner_per_org
  on public.org_members (organization_id)
  where role = 'owner' and status = 'active';

create or replace function public.transfer_organization_owner(target_org uuid, new_owner uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_role public.member_role;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if new_owner = actor_id then raise exception 'Select another active team member' using errcode = '22023'; end if;

  -- Serialize transfers so concurrent requests cannot leave two competing owners.
  perform 1 from public.organizations where id = target_org for update;
  if not found then return false; end if;
  if not exists (
    select 1 from public.org_members
    where organization_id = target_org and user_id = actor_id and role = 'owner' and status = 'active'
  ) then
    raise exception 'Only the current organization owner can transfer ownership' using errcode = '42501';
  end if;
  select role into target_role from public.org_members
  where organization_id = target_org and user_id = new_owner and status = 'active' for update;
  if not found or target_role = 'client' then
    raise exception 'The new owner must be an active internal member of this organization' using errcode = '22023';
  end if;

  update public.org_members set role = 'admin'
  where organization_id = target_org and user_id = actor_id;
  update public.org_members set role = 'owner'
  where organization_id = target_org and user_id = new_owner;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'transfer_owner_out', 'org_members', actor_id::text,
    jsonb_build_object('new_owner_id', new_owner, 'new_role', 'admin'));
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'transfer_owner_in', 'org_members', new_owner::text,
    jsonb_build_object('previous_owner_id', actor_id, 'new_role', 'owner'));
  return true;
end;
$$;

revoke all on function public.transfer_organization_owner(uuid, uuid) from public, anon;
grant execute on function public.transfer_organization_owner(uuid, uuid) to authenticated;
