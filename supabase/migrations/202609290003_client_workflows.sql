create or replace function public.create_client_with_contact(
  target_org uuid,
  client_name text,
  client_industry text default null,
  client_website text default null,
  client_monthly_value numeric default 0,
  contact_first_name text default null,
  contact_last_name text default null,
  contact_email text default null,
  contact_phone text default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_client_id uuid;
begin
  if not public.has_org_permission(target_org, 'workspace.write') then raise exception 'Workspace write permission required'; end if;
  if length(trim(client_name)) < 2 or length(trim(client_name)) > 160 then raise exception 'Client name must be between 2 and 160 characters'; end if;
  if coalesce(client_monthly_value, 0) < 0 then raise exception 'Monthly value cannot be negative'; end if;

  insert into public.clients (organization_id, name, industry, website, monthly_value, owner_id)
  values (target_org, trim(client_name), nullif(trim(client_industry), ''), nullif(trim(client_website), ''), coalesce(client_monthly_value, 0), auth.uid())
  returning id into new_client_id;

  if nullif(trim(contact_first_name), '') is not null then
    insert into public.contacts (organization_id, client_id, first_name, last_name, email, phone, is_primary)
    values (target_org, new_client_id, trim(contact_first_name), nullif(trim(contact_last_name), ''), nullif(trim(contact_email), '')::extensions.citext, nullif(trim(contact_phone), ''), true);
  end if;
  return new_client_id;
end;
$$;
revoke all on function public.create_client_with_contact(uuid, text, text, text, numeric, text, text, text, text) from public, anon;
grant execute on function public.create_client_with_contact(uuid, text, text, text, numeric, text, text, text, text) to authenticated;

create index contacts_org_client_idx on public.contacts (organization_id, client_id, is_primary desc, created_at);

create or replace function public.audit_contact_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare row_data jsonb;
begin
  if tg_op = 'DELETE' then row_data = to_jsonb(old); else row_data = to_jsonb(new); end if;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values ((row_data ->> 'organization_id')::uuid, auth.uid(), lower(tg_op), 'contact', row_data ->> 'id', '{}'::jsonb);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger audit_contact_change after insert or update or delete on public.contacts
  for each row execute function public.audit_contact_change();
revoke all on function public.audit_contact_change() from public, anon, authenticated;
