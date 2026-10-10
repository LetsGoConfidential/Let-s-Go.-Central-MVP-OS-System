create table public.team_performance_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null,
  author_id uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  period_start date not null check (extract(day from period_start) = 1),
  delivery_score smallint not null check (delivery_score between 1 and 5),
  communication_score smallint not null check (communication_score between 1 and 5),
  ownership_score smallint not null check (ownership_score between 1 and 5),
  client_care_score smallint not null check (client_care_score between 1 and 5),
  highlights text not null default '',
  growth_focus text not null default '',
  manager_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, member_id)
    references public.org_members(organization_id, user_id) on delete cascade,
  unique (organization_id, member_id, period_start),
  check (char_length(highlights) <= 3000),
  check (char_length(growth_focus) <= 3000),
  check (char_length(manager_notes) <= 3000)
);

create index team_performance_member_period_idx
  on public.team_performance_reviews (organization_id, member_id, period_start desc);

revoke all on public.team_performance_reviews from anon, authenticated;
grant select, insert, update on public.team_performance_reviews to authenticated;
alter table public.team_performance_reviews enable row level security;

create policy team_performance_manager_read on public.team_performance_reviews
  for select to authenticated
  using (public.has_org_permission(organization_id, 'team.performance.manage'));
create policy team_performance_manager_insert on public.team_performance_reviews
  for insert to authenticated
  with check (
    public.has_org_permission(organization_id, 'team.performance.manage')
    and author_id = auth.uid()
    and updated_by = auth.uid()
  );
create policy team_performance_manager_update on public.team_performance_reviews
  for update to authenticated
  using (public.has_org_permission(organization_id, 'team.performance.manage'))
  with check (
    public.has_org_permission(organization_id, 'team.performance.manage')
    and updated_by = auth.uid()
  );

create trigger set_team_performance_updated_at
  before update on public.team_performance_reviews
  for each row execute function public.set_updated_at();

-- Keep private manager notes out of the tenant-wide audit feed.
create or replace function public.audit_team_performance_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (
    new.organization_id,
    auth.uid(),
    lower(tg_op),
    'team_performance_review',
    new.id::text,
    jsonb_build_object(
      'member_id', new.member_id,
      'period_start', new.period_start,
      'delivery_score', new.delivery_score,
      'communication_score', new.communication_score,
      'ownership_score', new.ownership_score,
      'client_care_score', new.client_care_score,
      'written_feedback_updated', tg_op = 'INSERT' or
        (old.highlights, old.growth_focus, old.manager_notes) is distinct from
        (new.highlights, new.growth_focus, new.manager_notes)
    )
  );
  return new;
end;
$$;
revoke all on function public.audit_team_performance_review() from public, anon, authenticated;

create trigger audit_team_performance_review
  after insert or update on public.team_performance_reviews
  for each row execute function public.audit_team_performance_review();
