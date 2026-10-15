alter table public.organizations
  add column ai_monthly_budget_usd numeric(14, 8)
    check (ai_monthly_budget_usd is null or ai_monthly_budget_usd between 0.01 and 10000),
  add column ai_budget_started_at timestamptz;

create table public.ai_usage_events (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  request_type text not null check (request_type in ('assistant_reply', 'task_draft')),
  model text not null,
  status text not null default 'reserved' check (status in ('reserved', 'completed', 'failed')),
  input_tokens integer not null default 0 check (input_tokens >= 0),
  output_tokens integer not null default 0 check (output_tokens >= 0),
  reserved_usd numeric(14, 8) not null check (reserved_usd >= 0),
  actual_cost_usd numeric(14, 8) check (actual_cost_usd is null or actual_cost_usd >= 0),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  unique (organization_id, id)
);

create index ai_usage_events_org_month_idx on public.ai_usage_events (organization_id, created_at desc, status);
alter table public.ai_usage_events enable row level security;
revoke all on public.ai_usage_events from anon, authenticated;
grant all on public.ai_usage_events to service_role;

create or replace function public.has_org_permission_for_user(target_org uuid, target_user uuid, permission_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = target_user and m.status = 'active'
      and m.role <> 'client'
      and (
        m.role in ('owner', 'admin')
        or (m.role = 'manager' and permission_key not in ('organization.manage', 'finance.manage', 'members.manage'))
        or exists (
          select 1 from public.role_assignments ra join public.roles r on r.id = ra.role_id
          where ra.organization_id = m.organization_id and ra.user_id = m.user_id
            and coalesce((r.permissions ->> permission_key)::boolean, false)
        )
      )
  );
$$;
revoke all on function public.has_org_permission_for_user(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.has_org_permission_for_user(uuid, uuid, text) to service_role;

create or replace function public.reserve_ai_budget(
  target_org uuid,
  target_user uuid,
  request_id uuid,
  request_type text,
  request_model text,
  estimated_cost_usd numeric
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  org_budget numeric(14, 8);
  budget_started_at timestamptz;
  current_commitment numeric(14, 8);
begin
  if not public.has_org_permission_for_user(target_org, target_user, 'workspace.write') then
    raise exception 'Not authorized to use the AI assistant';
  end if;
  if request_type not in ('assistant_reply', 'task_draft') or char_length(request_model) not between 1 and 200
    or estimated_cost_usd is not null and estimated_cost_usd < 0 then
    raise exception 'Invalid AI budget reservation';
  end if;

  select o.ai_monthly_budget_usd, o.ai_budget_started_at into org_budget, budget_started_at
    from public.organizations o where o.id = target_org for update;
  if not found then raise exception 'Workspace not found'; end if;
  if org_budget is not null and estimated_cost_usd is null then
    raise exception 'Configure model token prices before enabling an AI spending limit';
  end if;

  select coalesce(sum(case when e.status = 'reserved' then e.reserved_usd else coalesce(e.actual_cost_usd, 0) end), 0)
    into current_commitment
    from public.ai_usage_events e
    where e.organization_id = target_org
      and e.created_at >= greatest(date_trunc('month', now() at time zone 'UTC') at time zone 'UTC', coalesce(budget_started_at, date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'))
      and (e.status <> 'reserved' or e.expires_at > now());
  if org_budget is not null and current_commitment + coalesce(estimated_cost_usd, 0) > org_budget then
    raise exception 'Monthly AI budget would be exceeded';
  end if;

  insert into public.ai_usage_events (id, organization_id, user_id, request_type, model, reserved_usd)
    values (request_id, target_org, target_user, request_type, request_model, coalesce(estimated_cost_usd, 0));
  return true;
end;
$$;
revoke all on function public.reserve_ai_budget(uuid, uuid, uuid, text, text, numeric) from public, anon, authenticated;
grant execute on function public.reserve_ai_budget(uuid, uuid, uuid, text, text, numeric) to service_role;

create or replace function public.settle_ai_budget(
  request_id uuid,
  target_user uuid,
  input_count integer,
  output_count integer,
  actual_cost numeric
)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if target_user is null or input_count < 0 or output_count < 0 or actual_cost is not null and actual_cost < 0 then
    raise exception 'Invalid AI usage settlement';
  end if;
  update public.ai_usage_events
    set status = 'completed', input_tokens = input_count, output_tokens = output_count,
        actual_cost_usd = actual_cost, completed_at = now()
    where id = request_id and user_id = target_user and status = 'reserved';
  return found;
end;
$$;
revoke all on function public.settle_ai_budget(uuid, uuid, integer, integer, numeric) from public, anon, authenticated;
grant execute on function public.settle_ai_budget(uuid, uuid, integer, integer, numeric) to service_role;

create or replace function public.release_ai_budget(request_id uuid, target_user uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.ai_usage_events set status = 'failed', reserved_usd = 0, completed_at = now()
    where id = request_id and user_id = target_user and status = 'reserved' and expires_at > now();
  return found;
end;
$$;
revoke all on function public.release_ai_budget(uuid, uuid) from public, anon, authenticated;
grant execute on function public.release_ai_budget(uuid, uuid) to service_role;

create or replace function public.set_org_ai_monthly_budget(target_org uuid, budget_usd numeric)
returns boolean language plpgsql security definer set search_path = '' as $$
declare old_budget numeric(14, 8);
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Organization management permission required';
  end if;
  if budget_usd is not null and (budget_usd < 0.01 or budget_usd > 10000) then
    raise exception 'Monthly AI budget must be between $0.01 and $10,000, or blank for no cap';
  end if;
  select ai_monthly_budget_usd into old_budget from public.organizations where id = target_org for update;
  if not found then raise exception 'Workspace not found'; end if;
  update public.organizations set ai_monthly_budget_usd = budget_usd,
    ai_budget_started_at = case when budget_usd is null then null when old_budget is null then now() else ai_budget_started_at end,
    updated_at = now()
    where id = target_org;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
    values (target_org, auth.uid(), 'update_ai_monthly_budget', 'organizations', target_org::text,
      jsonb_build_object('previous_usd', old_budget, 'new_usd', budget_usd));
  return found;
end;
$$;
revoke all on function public.set_org_ai_monthly_budget(uuid, numeric) from public, anon;
grant execute on function public.set_org_ai_monthly_budget(uuid, numeric) to authenticated;

create or replace function public.ai_budget_status(target_org uuid)
returns table (budget_usd numeric, spent_usd numeric, reserved_usd numeric)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Organization management permission required';
  end if;
  return query
    select o.ai_monthly_budget_usd,
      coalesce(sum(case when e.status = 'completed' then coalesce(e.actual_cost_usd, 0) else 0 end), 0)::numeric,
      coalesce(sum(case when e.status = 'reserved' then e.reserved_usd else 0 end), 0)::numeric
    from public.organizations o left join public.ai_usage_events e
      on e.organization_id = o.id and e.created_at >= greatest(date_trunc('month', now() at time zone 'UTC') at time zone 'UTC', coalesce(o.ai_budget_started_at, date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'))
        and (e.status <> 'reserved' or e.expires_at > now())
    where o.id = target_org group by o.id;
end;
$$;
revoke all on function public.ai_budget_status(uuid) from public, anon;
grant execute on function public.ai_budget_status(uuid) to authenticated;
