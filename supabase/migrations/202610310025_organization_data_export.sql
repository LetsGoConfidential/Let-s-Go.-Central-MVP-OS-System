create or replace function public.log_organization_data_export(target_org uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Organization management permission required';
  end if;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
    values (target_org, auth.uid(), 'export', 'organization_data', target_org::text,
      jsonb_build_object('format', 'json', 'requested_at', now()));
  return true;
end;
$$;
revoke all on function public.log_organization_data_export(uuid) from public, anon;
grant execute on function public.log_organization_data_export(uuid) to authenticated;
