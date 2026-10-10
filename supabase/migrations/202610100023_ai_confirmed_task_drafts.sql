create table public.ai_action_drafts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  action_type text not null default 'create_task' check (action_type = 'create_task'),
  title text not null check (char_length(trim(title)) between 2 and 200),
  description text not null default '' check (char_length(description) <= 5000),
  priority text not null check (priority in ('low', 'medium', 'high', 'urgent')),
  suggested_due_date date,
  model text,
  usage jsonb,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'cancelled')),
  task_id uuid references public.tasks(id) on delete set null,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create index ai_action_drafts_owner_idx on public.ai_action_drafts (organization_id, user_id, status, created_at desc);
revoke all on public.ai_action_drafts from anon, authenticated;
grant select on public.ai_action_drafts to authenticated;
alter table public.ai_action_drafts enable row level security;
create policy ai_action_drafts_owner_read on public.ai_action_drafts
  for select to authenticated using (public.is_org_member(organization_id) and user_id = auth.uid());

create or replace function public.confirm_ai_task_draft(
  target_org uuid,
  draft_id uuid,
  final_title text,
  final_description text default null,
  final_priority text default null,
  final_due_date date default null,
  selected_project uuid default null,
  selected_assignee uuid default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  draft_row public.ai_action_drafts%rowtype;
  new_task_id uuid;
  org_timezone text;
  linked_client_id uuid;
  task_title text;
  task_description text;
  task_priority text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace write permission required'; end if;
  select * into draft_row from public.ai_action_drafts d
    where d.id = draft_id and d.organization_id = target_org and d.user_id = auth.uid()
      and d.status = 'pending' and d.expires_at > now()
    for update;
  if not found then raise exception 'Draft is missing, expired, or already handled'; end if;
  task_title := coalesce(nullif(trim(final_title), ''), draft_row.title);
  task_description := coalesce(final_description, draft_row.description);
  task_priority := coalesce(final_priority, draft_row.priority);
  if char_length(task_title) < 2 or char_length(task_title) > 200 then raise exception 'Task title must be between 2 and 200 characters'; end if;
  if char_length(task_description) > 5000 then raise exception 'Task description is too long'; end if;
  if task_priority not in ('low', 'medium', 'high', 'urgent') then raise exception 'Invalid task priority'; end if;
  select o.timezone into org_timezone from public.organizations o where o.id = target_org;
  if selected_project is not null then
    select p.client_id into linked_client_id from public.projects p
      where p.id = selected_project and p.organization_id = target_org;
    if not found then raise exception 'Project must belong to this workspace'; end if;
  end if;
  if selected_assignee is not null and not exists (
    select 1 from public.org_members m where m.organization_id = target_org
      and m.user_id = selected_assignee and m.status = 'active' and m.role <> 'client'
  ) then raise exception 'Assignee must be an active internal workspace member'; end if;
  insert into public.tasks (organization_id, project_id, client_id, assignee_id, title, description, priority, due_at, created_by)
  values (
    target_org, selected_project, linked_client_id, selected_assignee, task_title,
    nullif(trim(task_description), ''), task_priority,
    case when final_due_date is null then null else (final_due_date::timestamp + time '23:59') at time zone coalesce(org_timezone, 'UTC') end,
    auth.uid()
  ) returning id into new_task_id;
  update public.ai_action_drafts set status = 'confirmed', task_id = new_task_id, confirmed_at = now()
    where id = draft_id and organization_id = target_org;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, auth.uid(), 'ai_task_confirmed', 'tasks', new_task_id::text,
    jsonb_build_object('draft_id', draft_id, 'project_id', selected_project, 'assignee_id', selected_assignee, 'priority', task_priority));
  return new_task_id;
end;
$$;
revoke all on function public.confirm_ai_task_draft(uuid, uuid, text, text, text, date, uuid, uuid) from public, anon;
grant execute on function public.confirm_ai_task_draft(uuid, uuid, text, text, text, date, uuid, uuid) to authenticated;

create or replace function public.cancel_ai_task_draft(target_org uuid, draft_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.ai_action_drafts set status = 'cancelled'
  where id = draft_id and organization_id = target_org and user_id = auth.uid()
    and status = 'pending' and expires_at > now() and public.has_org_permission(target_org, 'workspace.write');
  return found;
end;
$$;
revoke all on function public.cancel_ai_task_draft(uuid, uuid) from public, anon;
grant execute on function public.cancel_ai_task_draft(uuid, uuid) to authenticated;
