-- AI history is private to the creating member. Server actions write through
-- the service role only after validating the signed-in user and organization.
drop policy if exists tenant_read on public.ai_conversations;
drop policy if exists tenant_write on public.ai_conversations;
drop policy if exists tenant_read on public.ai_messages;
drop policy if exists tenant_write on public.ai_messages;

create policy ai_conversations_read_own on public.ai_conversations
  for select to authenticated
  using (user_id = (select auth.uid()) and public.is_org_member(organization_id));

create policy ai_messages_read_own on public.ai_messages
  for select to authenticated
  using (exists (
    select 1 from public.ai_conversations c
    where c.id = ai_messages.conversation_id
      and c.organization_id = ai_messages.organization_id
      and c.user_id = (select auth.uid())
      and public.is_org_member(c.organization_id)
  ));

revoke insert, update, delete on public.ai_conversations, public.ai_messages from authenticated;

create index ai_conversations_owner_recent_idx on public.ai_conversations (organization_id, user_id, updated_at desc);
create index ai_messages_conversation_created_idx on public.ai_messages (organization_id, conversation_id, created_at);

create table public.ai_request_limits (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null check (request_count > 0),
  primary key (organization_id, user_id)
);
alter table public.ai_request_limits enable row level security;
revoke all on public.ai_request_limits from anon, authenticated;
grant all on public.ai_request_limits to service_role;

create or replace function public.claim_ai_request(target_org uuid, target_user uuid, request_limit integer default 10)
returns boolean language plpgsql security definer set search_path = '' as $$
declare current_count integer;
begin
  if auth.uid() is distinct from target_user
    or not public.has_org_permission(target_org, 'workspace.write') then
    raise exception 'Not authorized to use the AI assistant';
  end if;
  insert into public.ai_request_limits (organization_id, user_id, window_start, request_count)
    values (target_org, target_user, date_trunc('minute', now()), 1)
  on conflict (organization_id, user_id)
    do update set
      window_start = case when public.ai_request_limits.window_start < date_trunc('minute', now()) then date_trunc('minute', now()) else public.ai_request_limits.window_start end,
      request_count = case when public.ai_request_limits.window_start < date_trunc('minute', now()) then 1 else public.ai_request_limits.request_count + 1 end
  returning request_count into current_count;
  return current_count <= greatest(1, least(request_limit, 20));
end;
$$;
revoke all on function public.claim_ai_request(uuid,uuid,integer) from public, anon;
grant execute on function public.claim_ai_request(uuid,uuid,integer) to authenticated;
