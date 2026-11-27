-- Private employee documents are isolated from the shared workspace library.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'employee-files', 'employee-files', false, 20971520,
  array['application/pdf','image/png','image/jpeg','image/webp','text/plain',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Managers do not receive private HR-document access by virtue of their base role.
create or replace function public.has_org_permission(target_org uuid, permission_key text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    where m.organization_id = target_org and m.user_id = (select auth.uid()) and m.status = 'active'
      and (
        m.role in ('owner', 'admin')
        or (m.role = 'manager' and permission_key not in ('organization.manage', 'finance.manage', 'members.manage', 'hr.documents.manage'))
        or exists (
          select 1 from public.role_assignments ra join public.roles r on r.id = ra.role_id
          where ra.organization_id = m.organization_id and ra.user_id = m.user_id
            and coalesce((r.permissions ->> permission_key)::boolean, false)
        )
      )
  );
$$;
revoke all on function public.has_org_permission(uuid, text) from public, anon;
grant execute on function public.has_org_permission(uuid, text) to authenticated;

create or replace function public.save_custom_role(target_org uuid, role_name text, permission_doc jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare role_id uuid; actor_id uuid := auth.uid();
begin
  if actor_id is null or not public.has_org_permission(target_org, 'organization.manage') then
    raise exception 'Not authorized to manage organization roles' using errcode = '42501';
  end if;
  if role_name is null or length(trim(role_name)) < 2 or length(trim(role_name)) > 80
    or permission_doc is null or jsonb_typeof(permission_doc) <> 'object'
    or (permission_doc - array['workspace.write', 'finance.manage', 'team.performance.manage', 'hr.leave.manage', 'hr.attendance.manage', 'hr.people.invite', 'tasks.self.update', 'hr.payroll.manage', 'hr.documents.manage']) <> '{}'::jsonb
    or exists (select 1 from jsonb_each(permission_doc) p where jsonb_typeof(p.value) <> 'boolean') then
    raise exception 'Invalid custom role definition' using errcode = '22023';
  end if;
  select r.id into role_id from public.roles r where r.organization_id = target_org and lower(r.name) = lower(trim(role_name)) and not r.is_system;
  if role_id is null then
    insert into public.roles (organization_id, name, is_system, permissions)
      values (target_org, trim(role_name), false, permission_doc) returning id into role_id;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
      values (target_org, actor_id, 'create', 'roles', role_id::text, jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  else
    update public.roles set permissions = permission_doc where id = role_id and organization_id = target_org;
    insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
      values (target_org, actor_id, 'update', 'roles', role_id::text, jsonb_build_object('name', trim(role_name), 'permissions', permission_doc));
  end if;
  return role_id;
end;
$$;

create table public.employee_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  member_id uuid not null,
  category text not null check (category in ('contract', 'identity', 'tax', 'certificate', 'other')),
  original_filename text not null check (length(btrim(original_filename)) between 1 and 180),
  mime_type text not null check (mime_type in ('application/pdf','image/png','image/jpeg','image/webp','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 20971520),
  employee_visible boolean not null default false,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, member_id, id),
  foreign key (organization_id, member_id) references public.org_members(organization_id, user_id) on delete cascade
);
create index employee_documents_member_recent_idx on public.employee_documents (organization_id, member_id, created_at desc);
alter table public.employee_documents enable row level security;
revoke all on public.employee_documents from anon, authenticated;
grant select on public.employee_documents to authenticated;
create policy employee_documents_read on public.employee_documents for select to authenticated
  using (
    public.has_org_permission(organization_id, 'hr.documents.manage')
    or (member_id = (select auth.uid()) and employee_visible and public.is_org_member(organization_id))
  );

create function public.create_employee_document(
  target_org uuid, target_member uuid, target_category text, target_filename text,
  target_mime text, target_size bigint, target_employee_visible boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); document_id uuid := gen_random_uuid(); safe_filename text;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.documents.manage') then
    raise exception 'HR document permission required' using errcode = '42501';
  end if;
  if target_category is null or target_category not in ('contract','identity','tax','certificate','other')
    or target_filename is null or length(btrim(target_filename)) not between 1 and 180
    or target_mime is null or target_mime not in ('application/pdf','image/png','image/jpeg','image/webp','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document')
    or target_size is null or target_size <= 0 or target_size > 20971520
    or target_employee_visible is null then
    raise exception 'Invalid employee document details' using errcode = '22023';
  end if;
  if not exists (select 1 from public.org_members m where m.organization_id = target_org and m.user_id = target_member and m.status = 'active' and m.role <> 'client') then
    raise exception 'Active employee not found in this organization' using errcode = '22023';
  end if;
  safe_filename := left(regexp_replace(btrim(target_filename), '[[:cntrl:]]', '', 'g'), 180);
  if safe_filename = '' then raise exception 'Invalid employee document details' using errcode = '22023'; end if;
  insert into public.employee_documents (id, organization_id, member_id, category, original_filename, mime_type, size_bytes, employee_visible, uploaded_by)
  values (document_id, target_org, target_member, target_category, safe_filename, target_mime, target_size, target_employee_visible, actor_id);
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'upload', 'employee_documents', document_id::text,
    jsonb_build_object('member_id', target_member, 'category', target_category, 'size_bytes', target_size, 'employee_visible', target_employee_visible));
  return document_id;
end;
$$;

create function public.delete_employee_document(target_org uuid, target_document uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); doc public.employee_documents%rowtype;
begin
  if actor_id is null or not public.has_org_permission(target_org, 'hr.documents.manage') then
    raise exception 'HR document permission required' using errcode = '42501';
  end if;
  select * into doc from public.employee_documents d where d.organization_id = target_org and d.id = target_document for update;
  if not found then return false; end if;
  delete from public.employee_documents where organization_id = target_org and id = target_document;
  insert into public.audit_logs (organization_id, actor_id, action, entity_type, entity_id, changes)
  values (target_org, actor_id, 'delete', 'employee_documents', target_document::text,
    jsonb_build_object('member_id', doc.member_id, 'category', doc.category, 'size_bytes', doc.size_bytes));
  return true;
end;
$$;
revoke all on function public.create_employee_document(uuid,uuid,text,text,text,bigint,boolean) from public, anon;
revoke all on function public.delete_employee_document(uuid,uuid) from public, anon;
grant execute on function public.create_employee_document(uuid,uuid,text,text,text,bigint,boolean) to authenticated;
grant execute on function public.delete_employee_document(uuid,uuid) to authenticated;

create policy employee_files_read on storage.objects for select to authenticated
  using (bucket_id = 'employee-files' and array_length(storage.foldername(name), 1) = 2 and exists (
    select 1 from public.employee_documents d
    where d.organization_id::text = (storage.foldername(name))[1]
      and d.member_id::text = (storage.foldername(name))[2]
      and d.id::text = storage.filename(name)
      and (public.has_org_permission(d.organization_id, 'hr.documents.manage')
        or (d.member_id = (select auth.uid()) and d.employee_visible))
  ));
create policy employee_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'employee-files' and array_length(storage.foldername(name), 1) = 2
    and exists (
      select 1 from public.employee_documents d
      where d.organization_id::text = (storage.foldername(name))[1]
        and d.member_id::text = (storage.foldername(name))[2]
        and d.id::text = storage.filename(name)
        and public.has_org_permission(d.organization_id, 'hr.documents.manage')
    ));
create policy employee_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'employee-files' and array_length(storage.foldername(name), 1) = 2 and exists (
    select 1 from public.employee_documents d
    where d.organization_id::text = (storage.foldername(name))[1]
      and d.member_id::text = (storage.foldername(name))[2]
      and d.id::text = storage.filename(name)
      and public.has_org_permission(d.organization_id, 'hr.documents.manage')
  ));
