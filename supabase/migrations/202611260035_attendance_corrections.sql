-- Attendance time corrections are requested by the employee and applied only
-- after an HR-authorized reviewer approves them.
create unique index attendance_days_org_id_unique on public.attendance_days (organization_id, id);

create table public.attendance_corrections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  attendance_id uuid not null,
  member_id uuid not null,
  proposed_check_in timestamptz not null,
  proposed_check_out timestamptz,
  reason text not null check (char_length(trim(reason)) between 3 and 1000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, attendance_id) references public.attendance_days(organization_id, id) on delete cascade,
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade,
  check (proposed_check_out is null or proposed_check_out >= proposed_check_in),
  check ((status = 'pending' and decided_by is null and decided_at is null) or (status in ('approved', 'rejected') and decided_by is not null and decided_at is not null))
);
create index attendance_corrections_member_idx on public.attendance_corrections (organization_id, member_id, created_at desc);
create index attendance_corrections_queue_idx on public.attendance_corrections (organization_id, status, created_at);
create unique index attendance_corrections_one_pending_per_day
  on public.attendance_corrections (organization_id, attendance_id) where status = 'pending';
revoke all on public.attendance_corrections from anon, authenticated;
grant select on public.attendance_corrections to authenticated;
alter table public.attendance_corrections enable row level security;
create policy attendance_corrections_read on public.attendance_corrections for select to authenticated
  using ((member_id = (select auth.uid()) and public.is_org_member(organization_id))
    or public.has_org_permission(organization_id, 'hr.attendance.manage'));
create trigger attendance_corrections_updated_at before update on public.attendance_corrections
  for each row execute function public.set_updated_at();

create or replace function public.audit_attendance_correction()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); row_data jsonb; org_id uuid; record_id text;
begin
  if tg_op = 'DELETE' then row_data = to_jsonb(old); else row_data = to_jsonb(new); end if;
  org_id = (row_data ->> 'organization_id')::uuid;
  record_id = row_data ->> 'id';
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (org_id, actor_id, lower(tg_op), tg_table_name, record_id,
    jsonb_build_object(
      'attendance_id', row_data ->> 'attendance_id',
      'member_id', row_data ->> 'member_id',
      'status', case when tg_op = 'INSERT' then null else old.status end,
      'result', case when tg_op = 'DELETE' then null else new.status end
    ));
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.audit_attendance_correction() from public, anon, authenticated;
create trigger audit_attendance_corrections after insert or update or delete on public.attendance_corrections
  for each row execute function public.audit_attendance_correction();

create or replace function public.submit_attendance_correction(
  target_org uuid,
  target_attendance uuid,
  target_check_in timestamp without time zone,
  target_check_out timestamp without time zone,
  target_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); attendance_row public.attendance_days%rowtype; org_timezone text; correction_value uuid;
begin
  if actor_id is null or not public.is_org_member(target_org) then
    raise exception 'Not authorized to request attendance correction' using errcode = '42501';
  end if;
  if target_check_in is null or target_reason is null or char_length(trim(target_reason)) < 3 or char_length(target_reason) > 1000
    or (target_check_out is not null and target_check_out < target_check_in) then
    raise exception 'Invalid attendance correction' using errcode = '22023';
  end if;
  select d.* into attendance_row
  from public.attendance_days d
  where d.organization_id = target_org and d.id = target_attendance and d.member_id = actor_id;
  if not found then raise exception 'Attendance record not found' using errcode = '42501'; end if;
  select o.timezone into org_timezone from public.organizations o where o.id = target_org;
  if attendance_row.work_date > (now() at time zone org_timezone)::date
    or attendance_row.work_date < (now() at time zone org_timezone)::date - 90 then
    raise exception 'Attendance correction is outside the 90-day request window' using errcode = '22023';
  end if;
  insert into public.attendance_corrections (
    organization_id, attendance_id, member_id, proposed_check_in, proposed_check_out, reason
  ) values (
    target_org, target_attendance, actor_id, target_check_in at time zone org_timezone,
    case when target_check_out is null then null else target_check_out at time zone org_timezone end,
    trim(target_reason)
  ) returning id into correction_value;
  return correction_value;
exception when unique_violation then
  raise exception 'A correction is already pending for this workday' using errcode = '23505';
end;
$$;
revoke all on function public.submit_attendance_correction(uuid, uuid, timestamp without time zone, timestamp without time zone, text) from public, anon;
grant execute on function public.submit_attendance_correction(uuid, uuid, timestamp without time zone, timestamp without time zone, text) to authenticated;

create or replace function public.review_attendance_correction(target_org uuid, correction_id uuid, decision text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); correction_row public.attendance_corrections%rowtype; org_timezone text;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.attendance.manage') then
    raise exception 'Not authorized to review attendance corrections' using errcode = '42501';
  end if;
  if decision is null or decision not in ('approved', 'rejected') then raise exception 'Invalid attendance correction decision' using errcode = '22023'; end if;
  select c.* into correction_row from public.attendance_corrections c
  where c.organization_id = target_org and c.id = correction_id and c.status = 'pending'
  for update;
  if not found then return false; end if;
  select o.timezone into org_timezone from public.organizations o where o.id = target_org;
  if decision = 'approved' then
    update public.attendance_days set
      checked_in_at = correction_row.proposed_check_in,
      checked_out_at = correction_row.proposed_check_out
    where organization_id = target_org and id = correction_row.attendance_id and member_id = correction_row.member_id;
  end if;
  update public.attendance_corrections set status = decision, decided_by = actor_id, decided_at = now()
  where id = correction_row.id and organization_id = target_org;
  return true;
end;
$$;
revoke all on function public.review_attendance_correction(uuid, uuid, text) from public, anon;
grant execute on function public.review_attendance_correction(uuid, uuid, text) to authenticated;
