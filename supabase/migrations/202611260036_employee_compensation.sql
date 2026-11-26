-- Permission-gated compensation history. Bank and payment credentials are not
-- stored here; payroll payouts and statutory calculations are separate work.
create table public.employee_compensation (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null,
  effective_from date not null,
  effective_to date,
  monthly_base numeric(14, 2) not null check (monthly_base >= 0),
  monthly_allowance numeric(14, 2) not null default 0 check (monthly_allowance >= 0),
  monthly_bonus_target numeric(14, 2) not null default 0 check (monthly_bonus_target >= 0),
  currency text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  change_reason text not null check (char_length(trim(change_reason)) between 3 and 500),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  check (effective_to is null or effective_to >= effective_from),
  unique (organization_id, member_id, effective_from)
);

create index employee_compensation_member_history_idx
  on public.employee_compensation (organization_id, member_id, effective_from desc);
create unique index employee_compensation_one_current_per_member_idx
  on public.employee_compensation (organization_id, member_id) where effective_to is null;

revoke all on public.employee_compensation from anon, authenticated;
grant select on public.employee_compensation to authenticated;
alter table public.employee_compensation enable row level security;
create policy employee_compensation_read on public.employee_compensation for select to authenticated
  using ((member_id = (select auth.uid()) and public.is_org_member(organization_id))
    or public.has_org_permission(organization_id, 'hr.payroll.manage'));

-- Add a dedicated payroll capability to custom roles without coupling it to
-- attendance, leave, finance, or general workspace administration.
create or replace function public.save_custom_role(target_org uuid, role_name text, permission_doc jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare role_id uuid; actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to manage organization roles' using errcode = '42501';
  end if;
  if role_name is null or length(trim(role_name)) < 2 or length(trim(role_name)) > 80
    or permission_doc is null or jsonb_typeof(permission_doc) <> 'object'
    or (permission_doc - array['workspace.write', 'finance.manage', 'team.performance.manage', 'hr.leave.manage', 'hr.attendance.manage', 'hr.people.invite', 'tasks.self.update', 'hr.payroll.manage']) <> '{}'::jsonb
    or exists (select 1 from jsonb_each(permission_doc) p where jsonb_typeof(p.value) <> 'boolean') then
    raise exception 'Invalid custom role definition' using errcode = '22023';
  end if;
  select r.id into role_id from public.roles r where r.organization_id = target_org and lower(r.name) = lower(trim(role_name)) and not r.is_system;
  if role_id is null then
    insert into public.roles (organization_id, name, is_system, permissions)
      values (target_org, trim(role_name), false, permission_doc) returning id into role_id;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
      values (target_org, actor_id, 'create', 'roles', role_id::text, jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  else
    update public.roles set permissions = permission_doc where id = role_id and organization_id = target_org;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
      values (target_org, actor_id, 'update', 'roles', role_id::text, jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  end if;
  return role_id;
end;
$$;

create or replace function public.set_employee_compensation(
  target_org uuid,
  target_member uuid,
  target_effective_from date,
  target_monthly_base numeric,
  target_monthly_allowance numeric,
  target_monthly_bonus_target numeric,
  target_currency text,
  target_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); current_row public.employee_compensation%rowtype; compensation_id uuid;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.payroll.manage') then
    raise exception 'Not authorized to manage payroll compensation' using errcode = '42501';
  end if;
  if target_effective_from is null or target_monthly_base is null or target_monthly_base < 0
    or target_monthly_allowance is null or target_monthly_allowance < 0
    or target_monthly_bonus_target is null or target_monthly_bonus_target < 0
    or target_currency is null or target_currency !~ '^[A-Z]{3}$'
    or target_reason is null or char_length(trim(target_reason)) < 3 or char_length(target_reason) > 500 then
    raise exception 'Invalid employee compensation details' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.org_members m where m.organization_id = target_org and m.user_id = target_member
      and m.status = 'active' and m.role <> 'client'
  ) then
    raise exception 'Active employee not found in this organization' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_org::text || ':' || target_member::text, 0));
  select c.* into current_row from public.employee_compensation c
  where c.organization_id = target_org and c.member_id = target_member and c.effective_to is null
  for update;
  if found then
    if target_effective_from <= current_row.effective_from then
      raise exception 'A compensation change must start after the current effective date' using errcode = '22023';
    end if;
    update public.employee_compensation set effective_to = target_effective_from - 1
    where id = current_row.id and organization_id = target_org;
  end if;

  insert into public.employee_compensation (
    organization_id, member_id, effective_from, monthly_base, monthly_allowance,
    monthly_bonus_target, currency, change_reason, created_by
  ) values (
    target_org, target_member, target_effective_from, target_monthly_base,
    target_monthly_allowance, target_monthly_bonus_target, target_currency,
    trim(target_reason), actor_id
  ) returning id into compensation_id;

  -- Audit records identify the affected member and date without duplicating pay amounts.
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, case when current_row.id is null then 'create' else 'update' end,
    'employee_compensation', compensation_id::text,
    jsonb_build_object('member_id', target_member, 'effective_from', target_effective_from, 'currency', target_currency));
  return compensation_id;
end;
$$;
revoke all on function public.set_employee_compensation(uuid, uuid, date, numeric, numeric, numeric, text, text) from public, anon;
grant execute on function public.set_employee_compensation(uuid, uuid, date, numeric, numeric, numeric, text, text) to authenticated;
