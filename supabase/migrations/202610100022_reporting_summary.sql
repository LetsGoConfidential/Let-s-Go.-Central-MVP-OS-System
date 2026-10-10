create or replace function public.report_summary(target_org uuid, days_back integer default 90)
returns table (
  period_start date,
  open_leads bigint,
  won_leads bigint,
  lost_leads bigint,
  active_clients bigint,
  healthy_clients bigint,
  needs_attention_clients bigint,
  at_risk_clients bigint,
  churned_clients bigint,
  completed_tasks_in_period bigint,
  completed_tasks_with_due_date bigint,
  on_time_tasks_in_period bigint,
  open_tasks bigint,
  blocked_tasks bigint,
  active_internal_members bigint
)
language plpgsql stable security definer set search_path = '' as $$
declare selected_period_start date;
begin
  if not public.is_org_member(target_org) then raise exception 'Organization membership required'; end if;
  selected_period_start := current_date - greatest(7, least(365, coalesce(days_back, 90)));
  return query
  select selected_period_start,
    (select count(*) from public.leads l where l.organization_id = target_org and l.stage not in ('won','lost')),
    (select count(*) from public.leads l where l.organization_id = target_org and l.stage = 'won'),
    (select count(*) from public.leads l where l.organization_id = target_org and l.stage = 'lost'),
    (select count(*) from public.clients c where c.organization_id = target_org and c.status = 'active'),
    (select count(*) from public.clients c where c.organization_id = target_org and c.status = 'active' and c.health = 'healthy'),
    (select count(*) from public.clients c where c.organization_id = target_org and c.status = 'active' and c.health = 'needs_attention'),
    (select count(*) from public.clients c where c.organization_id = target_org and c.status = 'active' and c.health = 'at_risk'),
    (select count(*) from public.clients c where c.organization_id = target_org and c.status = 'active' and c.health = 'churned'),
    (select count(*) from public.tasks t where t.organization_id = target_org and t.status = 'done' and t.completed_at >= selected_period_start::timestamptz and t.completed_at < now()),
    (select count(*) from public.tasks t where t.organization_id = target_org and t.status = 'done' and t.due_at is not null and t.completed_at >= selected_period_start::timestamptz and t.completed_at < now()),
    (select count(*) from public.tasks t where t.organization_id = target_org and t.status = 'done' and t.due_at is not null and t.due_at <= t.completed_at and t.completed_at >= selected_period_start::timestamptz and t.completed_at < now()),
    (select count(*) from public.tasks t where t.organization_id = target_org and t.status <> 'done'),
    (select count(*) from public.tasks t where t.organization_id = target_org and t.status = 'blocked'),
    (select count(*) from public.org_members m where m.organization_id = target_org and m.status = 'active' and m.role <> 'client');
end;
$$;
revoke all on function public.report_summary(uuid, integer) from public, anon;
grant execute on function public.report_summary(uuid, integer) to authenticated;

create or replace function public.report_team_workload(target_org uuid)
returns table (member_id uuid, full_name text, open_tasks bigint, blocked_tasks bigint, overdue_tasks bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_org_member(target_org) then raise exception 'Organization membership required'; end if;
  return query
  select m.user_id, coalesce(p.full_name, ''),
    count(t.id) filter (where t.status <> 'done'),
    count(t.id) filter (where t.status = 'blocked'),
    count(t.id) filter (where t.status <> 'done' and t.due_at < now())
  from public.org_members m
  left join public.profiles p on p.id = m.user_id
  left join public.tasks t on t.organization_id = m.organization_id and t.assignee_id = m.user_id
  where m.organization_id = target_org and m.status = 'active' and m.role <> 'client'
  group by m.user_id, p.full_name
  order by count(t.id) filter (where t.status <> 'done') desc, coalesce(p.full_name, '');
end;
$$;
revoke all on function public.report_team_workload(uuid) from public, anon;
grant execute on function public.report_team_workload(uuid) to authenticated;
