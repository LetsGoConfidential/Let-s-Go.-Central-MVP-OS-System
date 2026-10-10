-- Keep connection records visible to the tenant, but require RPC-backed writes
-- so client input cannot mark a provider connected or store credential values.
drop policy tenant_write on public.integrations;
revoke insert, update, delete on public.integrations from authenticated;
grant select on public.integrations to authenticated;
create trigger audit_change after insert or update or delete on public.integrations
  for each row execute function public.write_audit_log();

create or replace function public.register_integration(target_org uuid, provider_key text, display_label text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  if provider_key not in ('google_drive','slack','hubspot','stripe','notion','figma')
    or length(btrim(display_label)) not between 2 and 80 then raise exception 'Invalid integration details'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_org::text || ':' || provider_key, 0));
  select id into new_id from public.integrations where organization_id=target_org and provider=provider_key and external_account_id is null for update;
  if new_id is not null then
    update public.integrations set display_name=btrim(display_label),updated_at=now() where id=new_id and organization_id=target_org;
    return new_id;
  end if;
  insert into public.integrations (organization_id, provider, display_name, status, external_account_id, secret_reference, scopes)
  values (target_org, provider_key, btrim(display_label), 'disconnected', null, null, '{}')
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.remove_integration(target_org uuid, integration_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  delete from public.integrations where id = integration_id and organization_id = target_org and status = 'disconnected';
  return found;
end;
$$;
revoke all on function public.register_integration(uuid, text, text) from public, anon;
revoke all on function public.remove_integration(uuid, uuid) from public, anon;
grant execute on function public.register_integration(uuid, text, text) to authenticated;
grant execute on function public.remove_integration(uuid, uuid) to authenticated;

-- Rules support a deliberately small, low-risk synchronous action set first.
alter table public.automation_runs add constraint automation_runs_org_id_unique unique (organization_id, id);
alter table public.automation_runs add column actor_id uuid references auth.users(id) on delete set null;
alter table public.automation_runs add column source text not null default 'manual' check (source in ('manual'));
alter table public.automation_runs add column idempotency_key text not null default gen_random_uuid()::text;
alter table public.automation_runs add column attempt_count integer not null default 0 check (attempt_count >= 0);
alter table public.automation_runs add column max_attempts integer not null default 3 check (max_attempts between 1 and 5);
alter table public.automation_runs add constraint automation_runs_idempotency_unique unique (organization_id, idempotency_key);

drop policy tenant_write on public.automation_rules;
drop policy tenant_write on public.automation_runs;
revoke insert, update, delete on public.automation_rules, public.automation_runs from authenticated;
grant select on public.automation_rules, public.automation_runs to authenticated;
create trigger audit_change after insert or update or delete on public.automation_rules
  for each row execute function public.write_audit_log();
create trigger audit_change after insert or update on public.automation_runs
  for each row execute function public.write_audit_log();

create table public.automation_run_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  run_id uuid not null,
  attempt_number integer not null check (attempt_number between 1 and 5),
  idempotency_key text not null,
  actor_id uuid references auth.users(id) on delete set null,
  source text not null default 'manual' check (source in ('manual')),
  status text not null default 'running' check (status in ('running','succeeded','failed')),
  result jsonb,
  error_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  foreign key (organization_id, run_id) references public.automation_runs(organization_id, id) on delete cascade,
  unique (organization_id, idempotency_key),
  unique (organization_id, run_id, attempt_number)
);
alter table public.automation_run_attempts enable row level security;
revoke all on public.automation_run_attempts from anon, authenticated;
grant select on public.automation_run_attempts to authenticated;
create policy automation_attempts_read on public.automation_run_attempts for select to authenticated
  using (public.is_org_member(organization_id));
create trigger audit_change after insert or update on public.automation_run_attempts
  for each row execute function public.write_audit_log();

create or replace function public.save_task_automation(
  target_org uuid, rule_id uuid, rule_name text, rule_description text,
  task_title text, task_description text, task_priority text, enable_rule boolean
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare saved_id uuid; actor uuid := auth.uid();
begin
  if actor is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  if length(btrim(rule_name)) not between 2 and 80 or length(btrim(task_title)) not between 2 and 120
    or length(coalesce(task_description,'')) > 500 or task_priority not in ('low','medium','high','urgent') then
    raise exception 'Invalid automation details';
  end if;
  if rule_id is null then
    insert into public.automation_rules (organization_id,name,description,trigger_type,trigger_config,action_config,is_enabled,created_by)
    values (target_org,btrim(rule_name),nullif(btrim(rule_description),''),'manual','{"source":"manual"}'::jsonb,
      jsonb_build_object('type','create_task','title',btrim(task_title),'description',nullif(btrim(task_description),''),'priority',task_priority),enable_rule,actor)
    returning id into saved_id;
  else
    update public.automation_rules set name=btrim(rule_name),description=nullif(btrim(rule_description),''),
      trigger_config='{"source":"manual"}'::jsonb,
      action_config=jsonb_build_object('type','create_task','title',btrim(task_title),'description',nullif(btrim(task_description),''),'priority',task_priority),
      is_enabled=enable_rule,updated_at=now()
    where id=rule_id and organization_id=target_org returning id into saved_id;
    if saved_id is null then raise exception 'Automation not found'; end if;
  end if;
  return saved_id;
end;
$$;

create or replace function public.set_automation_enabled(target_org uuid, rule_id uuid, enable_rule boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  update public.automation_rules set is_enabled=enable_rule,updated_at=now()
    where id=rule_id and organization_id=target_org;
  return found;
end;
$$;

create or replace function public.create_automation_run(target_org uuid, target_rule uuid, request_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); new_run uuid;
begin
  if actor is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  if length(request_key) not between 16 and 100 then raise exception 'Invalid idempotency key'; end if;
  insert into public.automation_runs (organization_id,rule_id,status,trigger_payload,actor_id,source,idempotency_key,max_attempts)
  select target_org,r.id,'queued',jsonb_build_object('source','manual'),actor,'manual',request_key,3
  from public.automation_rules r where r.organization_id=target_org and r.id=target_rule and r.is_enabled
  on conflict (organization_id,idempotency_key) do nothing returning id into new_run;
  if new_run is null then
    select id into new_run from public.automation_runs where organization_id=target_org and idempotency_key=request_key and rule_id=target_rule;
    if new_run is not null then return new_run; end if;
    raise exception 'Automation is disabled or unavailable';
  end if;
  return new_run;
end;
$$;

create or replace function public.perform_automation_attempt(target_org uuid, run_id uuid, request_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare run_row public.automation_runs%rowtype; rule_row public.automation_rules%rowtype;
  attempt_id uuid; attempt_no integer; task_id uuid; existing_attempt public.automation_run_attempts%rowtype;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  if length(request_key) not between 16 and 100 then raise exception 'Invalid idempotency key'; end if;
  select * into run_row from public.automation_runs where id=run_id and organization_id=target_org for update;
  if run_row.id is null then raise exception 'Run not found'; end if;
  select * into existing_attempt from public.automation_run_attempts where organization_id=target_org and idempotency_key=request_key;
  if existing_attempt.id is not null then
    if existing_attempt.run_id <> run_id then raise exception 'Idempotency key already used for another run'; end if;
    return existing_attempt.id;
  end if;
  if run_row.status not in ('queued','failed') or run_row.attempt_count >= run_row.max_attempts then raise exception 'Run is not retryable'; end if;
  select * into rule_row from public.automation_rules where id=run_row.rule_id and organization_id=target_org and is_enabled for update;
  if rule_row.id is null then raise exception 'Automation is disabled or unavailable'; end if;
  attempt_no := run_row.attempt_count + 1;
  insert into public.automation_run_attempts (organization_id,run_id,attempt_number,idempotency_key,actor_id,source)
    values (target_org,run_id,attempt_no,request_key,auth.uid(),'manual') returning id into attempt_id;
  update public.automation_runs set status='running',attempt_count=attempt_no,started_at=now(),finished_at=null,error_message=null,actor_id=auth.uid()
    where id=run_id and organization_id=target_org;
  begin
    if rule_row.action_config ->> 'type' <> 'create_task' then raise exception 'Unsupported automation action'; end if;
    insert into public.tasks (organization_id,title,description,priority,status,created_by)
    values (target_org,rule_row.action_config ->> 'title',rule_row.action_config ->> 'description',
      rule_row.action_config ->> 'priority','todo',auth.uid())
    returning id into task_id;
    update public.automation_run_attempts set status='succeeded',result=jsonb_build_object('task_id',task_id),finished_at=now()
      where id=attempt_id;
    update public.automation_runs set status='succeeded',result=jsonb_build_object('task_id',task_id),finished_at=now()
      where id=run_id and organization_id=target_org;
  exception when others then
    update public.automation_run_attempts set status='failed',error_message=left(sqlerrm,500),finished_at=now()
      where id=attempt_id;
    update public.automation_runs set status='failed',error_message=left(sqlerrm,500),finished_at=now()
      where id=run_id and organization_id=target_org;
  end;
  return attempt_id;
end;
$$;

create or replace function public.run_task_automation(target_org uuid, rule_id uuid, request_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare run_id uuid;
begin
  run_id := public.create_automation_run(target_org,rule_id,request_key);
  perform public.perform_automation_attempt(target_org,run_id,request_key);
  return run_id;
end;
$$;

create or replace function public.retry_automation_run(target_org uuid, run_id uuid, request_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  return public.perform_automation_attempt(target_org,run_id,request_key);
end;
$$;

revoke all on function public.save_task_automation(uuid,uuid,text,text,text,text,text,boolean) from public, anon;
revoke all on function public.set_automation_enabled(uuid,uuid,boolean) from public, anon;
revoke all on function public.create_automation_run(uuid,uuid,text) from public, anon;
revoke all on function public.perform_automation_attempt(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.run_task_automation(uuid,uuid,text) from public, anon;
revoke all on function public.retry_automation_run(uuid,uuid,text) from public, anon;
grant execute on function public.save_task_automation(uuid,uuid,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.set_automation_enabled(uuid,uuid,boolean) to authenticated;
grant execute on function public.run_task_automation(uuid,uuid,text) to authenticated;
grant execute on function public.retry_automation_run(uuid,uuid,text) to authenticated;
