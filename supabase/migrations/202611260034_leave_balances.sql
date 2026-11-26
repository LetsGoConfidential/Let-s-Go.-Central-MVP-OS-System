-- Annual leave allocations are visible to the employee and to explicitly
-- authorized HR roles. Approved weekday usage is derived from leave requests.
create table public.leave_balances (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null,
  leave_year integer not null check (leave_year between 2000 and 2200),
  leave_type text not null check (leave_type in ('Annual', 'Sick', 'Personal', 'Unpaid', 'Other')),
  entitled_days numeric(5,2) not null default 0 check (entitled_days between 0 and 366),
  adjustment_days numeric(5,2) not null default 0 check (adjustment_days between -366 and 366),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (organization_id, member_id, leave_year, leave_type),
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  check (entitled_days + adjustment_days >= 0)
);

create index leave_balances_member_year_idx
  on public.leave_balances (organization_id, member_id, leave_year);
revoke all on public.leave_balances from anon, authenticated;
grant select on public.leave_balances to authenticated;
alter table public.leave_balances enable row level security;
create policy leave_balances_read on public.leave_balances for select to authenticated
  using ((member_id = (select auth.uid()) and public.is_org_member(organization_id))
    or public.has_org_permission(organization_id, 'hr.leave.manage'));
create trigger audit_leave_balances after insert or update or delete on public.leave_balances
  for each row execute function public.write_audit_log();

create or replace function public.set_leave_balance(
  target_org uuid,
  target_member uuid,
  target_year integer,
  target_leave_type text,
  target_entitled_days numeric,
  target_adjustment_days numeric default 0
) returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.leave.manage') then
    raise exception 'Not authorized to manage leave balances' using errcode = '42501';
  end if;
  if target_year is null
    or target_year < extract(year from now() at time zone coalesce((select o.timezone from public.organizations o where o.id = target_org), 'UTC'))::integer
    or target_year > extract(year from now() at time zone coalesce((select o.timezone from public.organizations o where o.id = target_org), 'UTC'))::integer + 2
    or target_leave_type not in ('Annual', 'Sick', 'Personal', 'Unpaid', 'Other')
    or target_entitled_days is null or target_entitled_days < 0 or target_entitled_days > 366
    or target_adjustment_days is null or target_adjustment_days < -366 or target_adjustment_days > 366
    or target_entitled_days + target_adjustment_days < 0 then
    raise exception 'Invalid leave balance allocation' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = target_member
      and m.status = 'active' and m.role <> 'client'
  ) then
    raise exception 'Active employee not found' using errcode = '22023';
  end if;
  insert into public.leave_balances (
    organization_id, member_id, leave_year, leave_type,
    entitled_days, adjustment_days, updated_by
  ) values (
    target_org, target_member, target_year, target_leave_type,
    target_entitled_days, target_adjustment_days, actor_id
  ) on conflict (organization_id, member_id, leave_year, leave_type) do update set
    entitled_days = excluded.entitled_days,
    adjustment_days = excluded.adjustment_days,
    updated_by = actor_id,
    updated_at = now();
  return true;
end;
$$;
revoke all on function public.set_leave_balance(uuid, uuid, integer, text, numeric, numeric) from public, anon;
grant execute on function public.set_leave_balance(uuid, uuid, integer, text, numeric, numeric) to authenticated;
