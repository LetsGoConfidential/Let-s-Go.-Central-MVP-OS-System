-- Let’s Go Central MVP: organization-scoped agency operations.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;

create type public.member_role as enum ('owner', 'admin', 'manager', 'member', 'client');
create type public.record_status as enum ('active', 'archived');
create type public.lead_stage as enum ('new', 'qualified', 'proposal', 'negotiation', 'won', 'lost');
create type public.project_status as enum ('planned', 'in_progress', 'internal_review', 'client_review', 'completed', 'on_hold');
create type public.task_status as enum ('todo', 'in_progress', 'blocked', 'done');
create type public.content_status as enum ('draft', 'review', 'approved', 'scheduled', 'published');
create type public.invoice_status as enum ('draft', 'sent', 'partially_paid', 'paid', 'overdue', 'void');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  legal_name text,
  timezone text not null default 'Asia/Kolkata',
  currency char(3) not null default 'INR',
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  avatar_url text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.org_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.member_role not null default 'member',
  title text,
  status text not null default 'active' check (status in ('invited', 'active', 'suspended')),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  is_system boolean not null default false,
  permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table public.role_assignments (
  organization_id uuid not null,
  user_id uuid not null,
  role_id uuid not null references public.roles(id) on delete cascade,
  primary key (organization_id, user_id, role_id),
  foreign key (organization_id, user_id) references public.org_members(organization_id, user_id) on delete cascade
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  industry text,
  website text,
  health text not null default 'healthy' check (health in ('healthy', 'needs_attention', 'at_risk', 'churned')),
  monthly_value numeric(14,2) not null default 0 check (monthly_value >= 0),
  owner_id uuid references auth.users(id) on delete set null,
  notes text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id)
);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  first_name text not null,
  last_name text,
  email extensions.citext,
  phone text,
  job_title text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id)
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  company_name text not null,
  contact_name text,
  email extensions.citext,
  phone text,
  source text,
  stage public.lead_stage not null default 'new',
  estimated_value numeric(14,2) not null default 0 check (estimated_value >= 0),
  probability smallint not null default 10 check (probability between 0 and 100),
  owner_id uuid references auth.users(id) on delete set null,
  next_action text,
  next_action_at timestamptz,
  converted_client_id uuid references public.clients(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, converted_client_id) references public.clients(organization_id, id)
);

create table public.deals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  name text not null,
  stage public.lead_stage not null default 'new',
  value numeric(14,2) not null default 0 check (value >= 0),
  expected_close_date date,
  owner_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, lead_id) references public.leads(organization_id, id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  name text not null,
  description text,
  status public.project_status not null default 'planned',
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  start_date date,
  due_date date,
  budget numeric(14,2) not null default 0,
  owner_id uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  title text not null,
  description text,
  status public.task_status not null default 'todo',
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  assignee_id uuid references auth.users(id) on delete set null,
  due_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, project_id) references public.projects(organization_id, id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id)
);

create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  title text not null,
  format text not null default 'post',
  channel text,
  status public.content_status not null default 'draft',
  caption text,
  scheduled_at timestamptz,
  published_at timestamptz,
  owner_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  foreign key (organization_id, client_id) references public.clients(organization_id, id),
  foreign key (organization_id, project_id) references public.projects(organization_id, id)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  client_id uuid not null,
  invoice_number text not null,
  status public.invoice_status not null default 'draft',
  currency char(3) not null default 'INR',
  subtotal numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) generated always as (subtotal + tax) stored,
  amount_paid numeric(14,2) not null default 0,
  issue_date date,
  due_date date,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, invoice_number),
  foreign key (organization_id, client_id) references public.clients(organization_id, id),
  check (subtotal >= 0 and tax >= 0 and amount_paid >= 0 and amount_paid <= subtotal + tax)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  description text not null,
  category text not null,
  amount numeric(14,2) not null check (amount >= 0),
  currency char(3) not null default 'INR',
  spent_on date not null default current_date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (organization_id, project_id) references public.projects(organization_id, id)
);

create table public.automation_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  trigger_type text not null,
  trigger_config jsonb not null default '{}'::jsonb,
  action_config jsonb not null default '[]'::jsonb,
  is_enabled boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.automation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  rule_id uuid references public.automation_rules(id) on delete set null,
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed', 'skipped')),
  trigger_payload jsonb not null default '{}'::jsonb,
  result jsonb,
  error_message text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (organization_id, rule_id) references public.automation_rules(organization_id, id)
);

create table public.integrations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null,
  display_name text not null,
  status text not null default 'disconnected' check (status in ('disconnected', 'connected', 'error', 'reauthorization_required')),
  external_account_id text,
  secret_reference text,
  scopes text[] not null default '{}',
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, provider, external_account_id)
);

create table public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New conversation',
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid not null,
  role text not null check (role in ('user', 'assistant', 'tool')),
  content text not null,
  model text,
  usage jsonb,
  created_at timestamptz not null default now(),
  foreign key (organization_id, conversation_id) references public.ai_conversations(organization_id, id) on delete cascade
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  changes jsonb not null default '{}'::jsonb,
  request_id text,
  created_at timestamptz not null default now()
);

create index clients_org_health_idx on public.clients (organization_id, health);
create index leads_org_stage_idx on public.leads (organization_id, stage, updated_at desc);
create index projects_org_status_idx on public.projects (organization_id, status, due_date);
create index tasks_org_due_idx on public.tasks (organization_id, status, due_at);
create index content_org_schedule_idx on public.content_items (organization_id, scheduled_at);
create index invoices_org_status_idx on public.invoices (organization_id, status, due_date);
create index audit_org_created_idx on public.audit_logs (organization_id, created_at desc);

create or replace function public.is_org_member(target_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
      and m.role <> 'client'
  );
$$;

create or replace function public.has_org_permission(target_org uuid, permission_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
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
revoke all on function public.is_org_member(uuid) from public, anon;
revoke all on function public.has_org_permission(uuid, text) from public, anon;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_permission(uuid, text) to authenticated;

create or replace function public.sales_summary(target_org uuid)
returns table (open_lead_count bigint, pipeline_value numeric, proposal_count bigint)
language sql stable security definer set search_path = '' as $$
  select count(*) filter (where l.stage not in ('won', 'lost')),
         coalesce(sum(l.estimated_value) filter (where l.stage not in ('won', 'lost')), 0),
         count(*) filter (where l.stage = 'proposal')
  from public.leads l
  where l.organization_id = target_org and public.is_org_member(target_org);
$$;
revoke all on function public.sales_summary(uuid) from public, anon;
grant execute on function public.sales_summary(uuid) to authenticated;

-- Atomic tenant bootstrap; the caller becomes owner and receives an org admin role.
create or replace function public.create_organization(org_name text, org_slug text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_org_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.organizations (name, slug) values (trim(org_name), lower(trim(org_slug))) returning id into new_org_id;
  insert into public.org_members (organization_id, user_id, role, status, joined_at)
    values (new_org_id, auth.uid(), 'owner', 'active', now());
  insert into public.roles (organization_id, name, is_system, permissions)
    values (new_org_id, 'Administrator', true, '{"workspace.write":true,"finance.manage":true,"members.manage":true,"organization.manage":true}'::jsonb);
  return new_org_id;
end;
$$;
revoke all on function public.create_organization(text, text) from public, anon;
grant execute on function public.create_organization(text, text) to authenticated;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;

create or replace function public.write_audit_log()
returns trigger language plpgsql security definer set search_path = '' as $$
declare row_data jsonb; org_id uuid; record_id text; action_name text;
begin
  if (tg_op = 'DELETE') then row_data = to_jsonb(old); else row_data = to_jsonb(new); end if;
  org_id = (row_data ->> 'organization_id')::uuid;
  record_id = row_data ->> 'id';
  action_name = lower(tg_op);
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (org_id, auth.uid(), action_name, tg_table_name, record_id,
    case when tg_op = 'UPDATE' then jsonb_build_object('before', to_jsonb(old), 'after', to_jsonb(new))
         when tg_op = 'DELETE' then jsonb_build_object('before', to_jsonb(old))
         else jsonb_build_object('after', to_jsonb(new)) end);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- Public API tables are closed by default; RLS remains the row boundary.
revoke all on all tables in schema public from anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array['organizations','org_members','roles','role_assignments','clients','contacts','leads','deals','projects','tasks','content_items','invoices','expenses','automation_rules','automation_runs','integrations','ai_conversations','ai_messages','audit_logs'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('create policy tenant_read on public.%I for select to authenticated using (public.is_org_member(organization_id))', table_name);
    if table_name in ('organizations','org_members','roles','role_assignments') then
      execute format('create policy tenant_write on public.%I for all to authenticated using (public.has_org_permission(organization_id, ''organization.manage'')) with check (public.has_org_permission(organization_id, ''organization.manage''))', table_name);
    elsif table_name in ('invoices','expenses') then
      execute format('create policy tenant_write on public.%I for all to authenticated using (public.has_org_permission(organization_id, ''finance.manage'')) with check (public.has_org_permission(organization_id, ''finance.manage''))', table_name);
    else
      execute format('create policy tenant_write on public.%I for all to authenticated using (public.has_org_permission(organization_id, ''workspace.write'')) with check (public.has_org_permission(organization_id, ''workspace.write''))', table_name);
    end if;
  end loop;
end $$;

-- Audit records are append-only through the application. No client-side writes.
drop policy tenant_write on public.audit_logs;
revoke insert, update, delete on public.audit_logs from authenticated;

-- Keep profile reads scoped to organization colleagues and allow self-edit only.
alter table public.profiles enable row level security;
grant select, insert, update on public.profiles to authenticated;
create policy profile_read on public.profiles for select to authenticated using (
  id = (select auth.uid()) or exists (
    select 1 from public.org_members mine join public.org_members colleague
    on mine.organization_id = colleague.organization_id
    where mine.user_id = (select auth.uid()) and mine.status = 'active' and colleague.user_id = profiles.id
  )
);
create policy profile_insert_self on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profile_update_self on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- updated_at maintenance and audit trail on mutable business records.
do $$
declare table_name text;
begin
  foreach table_name in array array['organizations','profiles','clients','contacts','leads','deals','projects','tasks','content_items','invoices','automation_rules','integrations','ai_conversations'] loop
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name);
  end loop;
  foreach table_name in array array['clients','leads','deals','projects','tasks','content_items','invoices','expenses'] loop
    execute format('create trigger audit_change after insert or update or delete on public.%I for each row execute function public.write_audit_log()', table_name);
  end loop;
end $$;

-- New auth users receive a minimal profile. Organization membership is invitation-driven.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name) values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();

alter default privileges in schema public revoke all on tables from anon, authenticated;
