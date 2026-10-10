-- Prevent a task from being assigned to an identity outside its organization.
create or replace function public.validate_task_assignee_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assignee_id is not null and not exists (
    select 1 from public.org_members m
    where m.organization_id = new.organization_id
      and m.user_id = new.assignee_id
      and m.status = 'active'
      and m.role <> 'client'
  ) then
    raise exception 'Task assignee must be an active internal member of the same organization'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_task_assignee_membership() from public, anon, authenticated;
create trigger validate_task_assignee_membership
before insert or update of organization_id, assignee_id on public.tasks
for each row execute function public.validate_task_assignee_membership();

create or replace function public.clear_ineligible_task_assignees()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'active' or new.role = 'client' then
    update public.tasks
    set assignee_id = null
    where organization_id = new.organization_id and assignee_id = new.user_id;
  end if;
  return new;
end;
$$;

revoke all on function public.clear_ineligible_task_assignees() from public, anon, authenticated;
create trigger clear_ineligible_task_assignees
after update of status, role on public.org_members
for each row execute function public.clear_ineligible_task_assignees();

create index tasks_org_assignee_status_idx on public.tasks (organization_id, assignee_id, status, due_at);
