create or replace function public.convert_won_lead_to_client(target_org uuid, target_lead uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare lead_row public.leads%rowtype; new_client_id uuid; actor uuid := auth.uid(); contact_parts text[];
begin
  if actor is null or not public.has_org_permission(target_org, 'workspace.write') then
    raise exception 'Workspace write permission required';
  end if;
  select * into lead_row from public.leads
    where id=target_lead and organization_id=target_org for update;
  if lead_row.id is null then raise exception 'Lead not found'; end if;
  if lead_row.converted_client_id is not null then return lead_row.converted_client_id; end if;
  if lead_row.stage <> 'won' then raise exception 'Only won leads can be converted'; end if;

  insert into public.clients (organization_id,name,monthly_value,owner_id)
    values (target_org,lead_row.company_name,0,coalesce(lead_row.owner_id,actor))
    returning id into new_client_id;

  if nullif(btrim(coalesce(lead_row.contact_name,'')),'') is not null
    or lead_row.email is not null or nullif(btrim(coalesce(lead_row.phone,'')),'') is not null then
    contact_parts := regexp_split_to_array(btrim(coalesce(lead_row.contact_name,'')), '\s+');
    insert into public.contacts (organization_id,client_id,first_name,last_name,email,phone,is_primary)
      values (target_org,new_client_id,coalesce(nullif(contact_parts[1],''),'Primary'),
        nullif(array_to_string(contact_parts[2:array_length(contact_parts,1)],' '),''),lead_row.email,
        nullif(btrim(coalesce(lead_row.phone,'')),''),true);
  end if;

  insert into public.deals (organization_id,lead_id,client_id,name,stage,value,owner_id)
    values (target_org,lead_row.id,new_client_id,lead_row.company_name || ' — New business','won',lead_row.estimated_value,
      coalesce(lead_row.owner_id,actor));
  update public.leads set converted_client_id=new_client_id,updated_at=now()
    where id=lead_row.id and organization_id=target_org;
  return new_client_id;
end;
$$;
revoke all on function public.convert_won_lead_to_client(uuid,uuid) from public, anon;
grant execute on function public.convert_won_lead_to_client(uuid,uuid) to authenticated;
