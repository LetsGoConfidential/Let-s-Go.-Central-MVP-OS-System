create or replace function public.update_organization_settings(
  target_org uuid,
  org_name text,
  org_legal_name text,
  org_timezone text,
  org_currency text
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  previous public.organizations%rowtype;
  normalized_name text := btrim(coalesce(org_name, ''));
  normalized_legal_name text := nullif(btrim(coalesce(org_legal_name, '')), '');
  normalized_timezone text := btrim(coalesce(org_timezone, ''));
  normalized_currency text := upper(btrim(coalesce(org_currency, '')));
begin
  if actor is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Organization management permission required' using errcode = '42501';
  end if;
  if char_length(normalized_name) not between 2 and 100
    or char_length(coalesce(normalized_legal_name, '')) > 160
    or char_length(normalized_timezone) not between 1 and 100
    or normalized_currency not in ('AED', 'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'INR', 'JPY', 'NZD', 'SGD', 'USD') then
    raise exception 'Invalid workspace settings' using errcode = '22023';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = normalized_timezone) then
    raise exception 'Choose a valid IANA timezone' using errcode = '22023';
  end if;

  select * into previous from public.organizations where id = target_org for update;
  if not found then return false; end if;

  update public.organizations set
    name = normalized_name,
    legal_name = normalized_legal_name,
    timezone = normalized_timezone,
    currency = normalized_currency,
    updated_at = now()
  where id = target_org;

  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
    values (target_org, actor, 'update_settings', 'organizations', target_org::text,
      jsonb_build_object(
        'previous', jsonb_build_object('name', previous.name, 'legal_name', previous.legal_name, 'timezone', previous.timezone, 'currency', previous.currency),
        'new', jsonb_build_object('name', normalized_name, 'legal_name', normalized_legal_name, 'timezone', normalized_timezone, 'currency', normalized_currency)
      ));
  return true;
end;
$$;
revoke all on function public.update_organization_settings(uuid, text, text, text, text) from public, anon;
grant execute on function public.update_organization_settings(uuid, text, text, text, text) to authenticated;
