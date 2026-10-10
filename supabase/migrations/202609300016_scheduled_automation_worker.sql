-- Add opt-in recurring task rules and a service-role worker entry point.
alter table public.automation_rules add column next_run_at timestamptz;
alter table public.automation_runs drop constraint automation_runs_source_check;
alter table public.automation_runs add constraint automation_runs_source_check check (source in ('manual','scheduled'));
alter table public.automation_run_attempts drop constraint automation_run_attempts_source_check;
alter table public.automation_run_attempts add constraint automation_run_attempts_source_check check (source in ('manual','scheduled'));

drop function public.save_task_automation(uuid,uuid,text,text,text,text,text,boolean);

create function public.save_task_automation(
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
    or trigger_mode not in ('manual','scheduled') then raise exception 'Invalid automation details'; end if;
  if trigger_mode = 'scheduled' and interval_minutes not between 15 and 10080 then raise exception 'Invalid schedule interval'; end if;
  if trigger_mode = 'scheduled' then
    trigger_data := jsonb_build_object('source','schedule','interval_minutes',interval_minutes);
    if enable_rule then next_at := now() + make_interval(mins => interval_minutes); end if;
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
  return true;
end;
$$;

create or replace function public.process_scheduled_automations(batch_size integer default 20)
returns integer language plpgsql security definer set search_path = '' as $$
declare rule_row public.automation_rules%rowtype; run_id uuid; attempt_id uuid; task_id uuid;
  due_at timestamptz; interval_minutes integer; request_key text; processed integer := 0;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'Service role required'; end if;
  for rule_row in
    select r.* from public.automation_rules r
    where r.is_enabled and r.trigger_type='scheduled' and r.next_run_at <= now()
    order by r.next_run_at
    for update skip locked
    limit greatest(1,least(coalesce(batch_size,20),50))
  loop
    run_id := null;
    attempt_id := null;
    task_id := null;
    due_at := rule_row.next_run_at;
    interval_minutes := least(10080,greatest(15,coalesce((rule_row.trigger_config ->> 'interval_minutes')::integer,1440)));
    request_key := 'schedule:' || rule_row.id::text || ':' || floor(extract(epoch from due_at))::bigint::text;
    insert into public.automation_runs (organization_id,rule_id,status,trigger_payload,actor_id,source,idempotency_key,max_attempts)
      values (rule_row.organization_id,rule_row.id,'queued',jsonb_build_object('source','schedule','scheduled_at',due_at),null,'scheduled',request_key,3)
      on conflict (organization_id,idempotency_key) do nothing returning id into run_id;
    update public.automation_rules set next_run_at=now()+make_interval(mins => interval_minutes),updated_at=now()
      where id=rule_row.id and organization_id=rule_row.organization_id;
    if run_id is null then continue; end if;

    insert into public.automation_run_attempts (organization_id,run_id,attempt_number,idempotency_key,actor_id,source,status)
      values (rule_row.organization_id,run_id,1,request_key || ':attempt:1',null,'scheduled','running') returning id into attempt_id;
    update public.automation_runs set status='running',attempt_count=1,started_at=now(),actor_id=null
      where id=run_id and organization_id=rule_row.organization_id;
    begin
      if rule_row.action_config ->> 'type' <> 'create_task'
        or length(btrim(coalesce(rule_row.action_config ->> 'title',''))) not between 2 and 120
        or length(coalesce(rule_row.action_config ->> 'description','')) > 500
        or coalesce(rule_row.action_config ->> 'priority','medium') not in ('low','medium','high','urgent') then
        raise exception 'Unsupported or invalid scheduled action';
      end if;
      insert into public.tasks (organization_id,title,description,priority,status,created_by)
        values (rule_row.organization_id,rule_row.action_config ->> 'title',rule_row.action_config ->> 'description',
          coalesce(rule_row.action_config ->> 'priority','medium'),'todo',rule_row.created_by)
        returning id into task_id;
      update public.automation_run_attempts set status='succeeded',result=jsonb_build_object('task_id',task_id),finished_at=now()
        where id=attempt_id;
      update public.automation_runs set status='succeeded',result=jsonb_build_object('task_id',task_id),finished_at=now()
        where id=run_id and organization_id=rule_row.organization_id;
    exception when others then
      update public.automation_run_attempts set status='failed',error_message=left(sqlerrm,500),finished_at=now()
        where id=attempt_id;
      update public.automation_runs set status='failed',error_message=left(sqlerrm,500),finished_at=now()
        where id=run_id and organization_id=rule_row.organization_id;
    end;
    processed := processed + 1;
  end loop;
  return processed;
end;
$$;

revoke all on function public.save_task_automation(uuid,uuid,text,text,text,text,text,boolean,text,integer) from public, anon;
revoke all on function public.process_scheduled_automations(integer) from public, anon, authenticated;
grant execute on function public.save_task_automation(uuid,uuid,text,text,text,text,text,boolean,text,integer) to authenticated;
grant execute on function public.process_scheduled_automations(integer) to service_role;
