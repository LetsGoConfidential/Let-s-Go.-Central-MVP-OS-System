-- OAuth credentials are encrypted by the application before insertion. This
-- table has no authenticated grants or RLS policies; only service_role reads it.
alter table public.integrations add constraint integrations_org_id_unique unique (organization_id, id);

create table public.integration_secrets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  integration_id uuid not null unique,
  encrypted_credentials text not null,
  key_version smallint not null default 1 check (key_version = 1),
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  foreign key (organization_id, integration_id) references public.integrations(organization_id, id) on delete cascade
);
alter table public.integration_secrets enable row level security;
revoke all on public.integration_secrets from anon, authenticated;
grant all on public.integration_secrets to service_role;

create or replace function public.store_slack_integration(
  target_org uuid, slack_team_id text, slack_team_name text,
  encrypted_credentials text, token_expires_at timestamptz, granted_scopes text[]
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare connection_id uuid; secret_id uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'Service role required'; end if;
  if length(slack_team_id) not between 1 and 80 or length(btrim(slack_team_name)) not between 1 and 120
    or length(encrypted_credentials) not between 40 and 20000 then raise exception 'Invalid Slack connection data'; end if;
  select i.id into connection_id from public.integrations i
    where i.organization_id=target_org and i.provider='slack'
      and (i.external_account_id=slack_team_id or (i.external_account_id is null and i.status='disconnected'))
    order by case when i.external_account_id=slack_team_id then 0 else 1 end, i.created_at desc
    limit 1 for update;
  if connection_id is null then
    insert into public.integrations (organization_id,provider,display_name,status,external_account_id,scopes)
      values (target_org,'slack',btrim(slack_team_name),'disconnected',null,'{}') returning id into connection_id;
  end if;
  select s.id into secret_id from public.integration_secrets s where s.integration_id=connection_id;
  if secret_id is null then secret_id := gen_random_uuid(); end if;
  update public.integrations set display_name=btrim(slack_team_name),status='connected',external_account_id=slack_team_id,
    secret_reference='vault://integration_secrets/' || secret_id::text,scopes=coalesce(granted_scopes,'{}'),updated_at=now()
    where id=connection_id and organization_id=target_org;
  insert into public.integration_secrets (id,organization_id,integration_id,encrypted_credentials,key_version,expires_at,updated_at)
    values (secret_id,target_org,connection_id,encrypted_credentials,1,token_expires_at,now())
    on conflict (integration_id) do update set encrypted_credentials=excluded.encrypted_credentials,
      key_version=excluded.key_version,expires_at=excluded.expires_at,updated_at=now();
  return connection_id;
end;
$$;
revoke all on function public.store_slack_integration(uuid,text,text,text,timestamptz,text[]) from public, anon, authenticated;
grant execute on function public.store_slack_integration(uuid,text,text,text,timestamptz,text[]) to service_role;
