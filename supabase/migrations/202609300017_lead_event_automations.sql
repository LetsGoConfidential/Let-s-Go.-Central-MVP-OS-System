-- Let enabled rules react to a newly created lead. The trigger only enqueues;
-- the worker performs the task action and records its attempt.
alter table public.automation_runs drop constraint automation_runs_source_check;
alter table public.automation_runs add constraint automation_runs_source_check check (source in ('manual','scheduled','event'));
alter table public.automation_run_attempts drop constraint automation_run_attempts_source_check;
alter table public.automation_run_attempts add constraint automation_run_attempts_source_check check (source in ('manual','scheduled','event'));

create or replace function public.save_task_automation(
  target_org uuid, rule_id uuid, rule_name text, rule_description text,
  task_title text, task_description text, task_priority text, enable_rule boolean,
  trigger_mode text default 'manual', interval_minutes integer default 1440
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare saved_id uuid; actor uuid := auth.uid(); next_at timestamptz; trigger_data jsonb;
begin
  if actor is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  if length(btrim(rule_name)) not between 2 and 80 or length(btrim(task_title)) not between 2 and 120
    or length(coalesce(task_description,'')) > 500 or task_priority not in ('low','medium','high','urgent')
    or trigger_mode not in ('manual','scheduled','lead_created') then raise exception 'Invalid automation details'; end if;
  if trigger_mode = 'scheduled' and interval_minutes not between 15 and 10080 then raise exception 'Invalid schedule interval'; end if;
  if trigger_mode = 'scheduled' then
    trigger_data := jsonb_build_object('source','schedule','interval_minutes',interval_minutes);
    if enable_rule then next_at := now() + make_interval(mins => interval_minutes); end if;
  elsif trigger_mode = 'lead_created' then
    trigger_data := '{"event":"lead.created"}'::jsonb;
  else
    trigger_data := '{"source":"manual"}'::jsonb;
  end if;

  if rule_id is null then
    insert into public.automation_rules (organization_id,name,description,trigger_type,trigger_config,action_config,is_enabled,created_by,next_run_at)
    values (target_org,btrim(rule_name),nullif(btrim(rule_description),''),trigger_mode,trigger_data,
      jsonb_build_object('type','create_task','title',btrim(task_title),'description',nullif(btrim(task_description),''),'priority',task_priority),enable_rule,actor,next_at)
    returning id into saved_id;
  else
    update public.automation_rules set name=btrim(rule_name),description=nullif(btrim(rule_description),''),
      trigger_type=trigger_mode,trigger_config=trigger_data,
      action_config=jsonb_build_object('type','create_task','title',btrim(task_title),'description',nullif(btrim(task_description),''),'priority',task_priority),
      is_enabled=enable_rule,next_run_at=next_at,updated_at=now()
    where id=rule_id and organization_id=target_org returning id into saved_id;
    if saved_id is null then raise exception 'Automation not found'; end if;
    update public.automation_runs set status='skipped',error_message='Rule configuration changed before event execution',finished_at=now()
      where organization_id=target_org and rule_id=rule_id and source='event' and status='queued';
  end if;
  return saved_id;
end;
$$;

create or replace function public.set_automation_enabled(target_org uuid, rule_id uuid, enable_rule boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare rule_row public.automation_rules%rowtype; interval_minutes integer;
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace permission required'; end if;
  select * into rule_row from public.automation_rules where id=rule_id and organization_id=target_org for update;
  if rule_row.id is null then return false; end if;
  interval_minutes := least(10080,greatest(15,coalesce((rule_row.trigger_config ->> 'interval_minutes')::integer,1440)));
  update public.automation_rules set is_enabled=enable_rule,
    next_run_at=case when enable_rule and rule_row.trigger_type='scheduled' then now()+make_interval(mins => interval_minutes) else null end,
    updated_at=now()
  where id=rule_id and organization_id=target_org;
  if not enable_rule then
    update public.automation_runs set status='skipped',error_message='Rule paused before event execution',finished_at=now()
      where organization_id=target_org and rule_id=rule_id and source='event' and status='queued';
  end if;
  return true;
end;
$$;

create or replace function public.enqueue_lead_created_automations()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.automation_runs (organization_id,rule_id,status,trigger_payload,actor_id,source,idempotency_key,max_attempts)
  select new.organization_id,r.id,'queued',
    jsonb_build_object('event','lead.created','lead_id',new.id,'company_name',new.company_name),
    auth.uid(),'event','lead.created:' || r.id::text || ':' || new.id::text,3
  from public.automation_rules r
  where r.organization_id=new.organization_id and r.trigger_type='lead_created' and r.is_enabled
  on conflict (organization_id,idempotency_key) do nothing;
  return new;
end;
$$;
create trigger enqueue_lead_created_automations after insert on public.leads
  for each row execute function public.enqueue_lead_created_automations();
revoke all on function public.enqueue_lead_created_automations() from public, anon, authenticated;

create or replace function public.execute_automation_run(target_run uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare run_row public.automation_runs%rowtype; rule_row public.automation_rules%rowtype;
  attempt_id uuid; attempt_no integer; task_id uuid; task_title text; task_description text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'Service role required'; end if;
  select * into run_row from public.automation_runs where id=target_run for update;
  if run_row.id is null or run_row.status <> 'queued' or run_row.attempt_count >= run_row.max_attempts then return; end if;
  select * into rule_row from public.automation_rules where id=run_row.rule_id and organization_id=run_row.organization_id for update;
  if rule_row.id is null then
    update public.automation_runs set status='skipped',error_message='Rule unavailable at execution time',finished_at=now() where id=target_run;
    return;
  end if;
  if not rule_row.is_enabled then
    update public.automation_runs set status='skipped',error_message='Rule paused before execution',finished_at=now() where id=target_run;
    return;
  end if;

  attempt_no := run_row.attempt_count + 1;
  insert into public.automation_run_attempts (organization_id,run_id,attempt_number,idempotency_key,actor_id,source,status)
    values (run_row.organization_id,target_run,attempt_no,target_run::text || ':attempt:' || attempt_no::text,run_row.actor_id,run_row.source,'running')
    returning id into attempt_id;
  update public.automation_runs set status='running',attempt_count=attempt_no,started_at=now(),finished_at=null,error_message=null
    where id=target_run;
  begin
    if rule_row.action_config ->> 'type' <> 'create_task'
      or length(btrim(coalesce(rule_row.action_config ->> 'title',''))) not between 2 and 120
      or length(coalesce(rule_row.action_config ->> 'description','')) > 500
      or coalesce(rule_row.action_config ->> 'priority','medium') not in ('low','medium','high','urgent') then
      raise exception 'Unsupported or invalid automation action';
    end if;
    task_title := left(replace(rule_row.action_config ->> 'title','{{company_name}}',coalesce(run_row.trigger_payload ->> 'company_name','')),120);
    task_description := left(replace(coalesce(rule_row.action_config ->> 'description',''),'{{company_name}}',coalesce(run_row.trigger_payload ->> 'company_name','')),500);
    insert into public.tasks (organization_id,title,description,priority,status,created_by)
      values (run_row.organization_id,task_title,nullif(task_description,''),coalesce(rule_row.action_config ->> 'priority','medium'),'todo',rule_row.created_by)
      returning id into task_id;
    update public.automation_run_attempts set status='succeeded',result=jsonb_build_object('task_id',task_id),finished_at=now() where id=attempt_id;
    update public.automation_runs set status='succeeded',result=jsonb_build_object('task_id',task_id),finished_at=now() where id=target_run;
  exception when others then
    update public.automation_run_attempts set status='failed',error_message=left(sqlerrm,500),finished_at=now() where id=attempt_id;
    update public.automation_runs set status='failed',error_message=left(sqlerrm,500),finished_at=now() where id=target_run;
  end;
end;
$$;

drop function public.process_scheduled_automations(integer);

create function public.process_automation_jobs(batch_size integer default 20)
returns integer language plpgsql security definer set search_path = '' as $$
declare rule_row public.automation_rules%rowtype; run_row public.automation_runs%rowtype;
  run_id uuid; due_at timestamptz; interval_minutes integer; request_key text;
  processed integer := 0; job_limit integer := greatest(1,least(coalesce(batch_size,20),50));
begin
  if auth.role() is distinct from 'service_role' then raise exception 'Service role required'; end if;

  for rule_row in
    select r.* from public.automation_rules r
    where r.is_enabled and r.trigger_type='scheduled' and r.next_run_at <= now()
    order by r.next_run_at for update skip locked limit job_limit
  loop
    run_id := null;
    due_at := rule_row.next_run_at;
    interval_minutes := least(10080,greatest(15,coalesce((rule_row.trigger_config ->> 'interval_minutes')::integer,1440)));
    request_key := 'schedule:' || rule_row.id::text || ':' || floor(extract(epoch from due_at))::bigint::text;
    insert into public.automation_runs (organization_id,rule_id,status,trigger_payload,actor_id,source,idempotency_key,max_attempts)
      values (rule_row.organization_id,rule_row.id,'queued',jsonb_build_object('source','schedule','scheduled_at',due_at),null,'scheduled',request_key,3)
      on conflict (organization_id,idempotency_key) do nothing returning id into run_id;
    update public.automation_rules set next_run_at=now()+make_interval(mins => interval_minutes),updated_at=now()
      where id=rule_row.id and organization_id=rule_row.organization_id;
    if run_id is not null then
      perform public.execute_automation_run(run_id);
      processed := processed + 1;
    end if;
  end loop;

  for run_row in
    select a.* from public.automation_runs a
    join public.automation_rules r on r.id=a.rule_id and r.organization_id=a.organization_id
    where a.source='event' and a.status='queued' and r.is_enabled
    order by a.created_at for update of a skip locked limit greatest(0,job_limit-processed)
  loop
    perform public.execute_automation_run(run_row.id);
    processed := processed + 1;
  end loop;
  return processed;
end;
$$;

revoke all on function public.execute_automation_run(uuid) from public, anon, authenticated;
grant execute on function public.save_task_automation(uuid,uuid,text,text,text,text,text,boolean,text,integer) to authenticated;
grant execute on function public.process_automation_jobs(integer) to service_role;
