-- Preserve failed attempt records and retry queued automation runs until their
-- configured attempt limit is reached. Each retry is picked up by the next
-- worker invocation, so one failing integration/action cannot monopolize a batch.
create or replace function public.execute_automation_run(target_run uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  run_row public.automation_runs%rowtype;
  rule_row public.automation_rules%rowtype;
  attempt_id uuid;
  attempt_no integer;
  task_id uuid;
  task_title text;
  task_description text;
  failure_message text;
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
    failure_message := left(sqlerrm,500);
    update public.automation_run_attempts set status='failed',error_message=failure_message,finished_at=now() where id=attempt_id;
    update public.automation_runs set
      status=case when attempt_no < run_row.max_attempts then 'queued' else 'failed' end,
      error_message=failure_message,
      finished_at=case when attempt_no < run_row.max_attempts then null else now() end
      where id=target_run;
  end;
end;
$$;

revoke all on function public.execute_automation_run(uuid) from public, anon, authenticated;
grant execute on function public.execute_automation_run(uuid) to service_role;
