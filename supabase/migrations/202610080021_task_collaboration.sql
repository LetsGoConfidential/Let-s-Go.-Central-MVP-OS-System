create table public.task_comments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  task_id uuid not null,
  author_id uuid references auth.users(id) on delete set null default auth.uid(),
  body text not null check (char_length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now(),
  foreign key (organization_id, task_id)
    references public.tasks(organization_id, id) on delete cascade
);

create index task_comments_recent_idx on public.task_comments (organization_id, task_id, created_at desc);
revoke all on public.task_comments from anon, authenticated;
grant select, insert on public.task_comments to authenticated;
alter table public.task_comments enable row level security;
create policy task_comments_member_read on public.task_comments
  for select to authenticated using (public.is_org_member(organization_id));
create policy task_comments_writer_insert on public.task_comments
  for insert to authenticated with check (
    public.has_org_permission(organization_id, 'workspace.write') and author_id = auth.uid()
  );

create or replace function public.audit_task_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (new.organization_id, auth.uid(), 'commented', 'task', new.task_id::text,
    jsonb_build_object('comment_id', new.id, 'body_length', char_length(new.body)));
  return new;
end;
$$;
revoke all on function public.audit_task_comment() from public, anon, authenticated;
create trigger audit_task_comment after insert on public.task_comments
  for each row execute function public.audit_task_comment();
