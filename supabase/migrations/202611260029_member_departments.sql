alter table public.org_members
  add column department text check (department is null or char_length(trim(department)) between 2 and 80);

create index org_members_department_idx
  on public.org_members (organization_id, lower(department)) where department is not null;

create or replace function public.set_member_department(target_org uuid, target_user uuid, new_department text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  member_row public.org_members%rowtype;
  cleaned text := nullif(trim(new_department), '');
  actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to manage organization departments' using errcode = '42501';
  end if;
  if cleaned is not null and char_length(cleaned) > 80 then
    raise exception 'Department must be 80 characters or fewer' using errcode = '22023';
  end if;
  select * into member_row from public.org_members
    where organization_id = target_org and user_id = target_user and status <> 'invited' for update;
  if not found then return false; end if;
  update public.org_members set department = cleaned
    where organization_id = target_org and user_id = target_user;
  -- org_members already has the shared audit trigger; it captures this change once.
  return true;
end;
$$;
revoke all on function public.set_member_department(uuid, uuid, text) from public, anon;
grant execute on function public.set_member_department(uuid, uuid, text) to authenticated;
