-- Files stay in a private Supabase Storage bucket with tenant ID as the first
-- path segment. The metadata table is the tenant-scoped application index.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tenant-files', 'tenant-files', false, 20971520,
  array['application/pdf','image/png','image/jpeg','image/webp','text/plain',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation']
)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table public.organization_files (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  storage_path text not null,
  original_filename text not null check (length(original_filename) between 1 and 180),
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 20971520),
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id, storage_path),
  check (storage_path like organization_id::text || '/%')
);
create index organization_files_recent_idx on public.organization_files (organization_id, created_at desc);
alter table public.organization_files enable row level security;
revoke all on public.organization_files from anon, authenticated;
grant select, insert, delete on public.organization_files to authenticated;
create policy organization_files_read on public.organization_files for select to authenticated
  using (public.is_org_member(organization_id));
create policy organization_files_write on public.organization_files for insert to authenticated
  with check (public.has_org_permission(organization_id, 'workspace.write') and uploaded_by = auth.uid());
create policy organization_files_delete on public.organization_files for delete to authenticated
  using (public.has_org_permission(organization_id, 'workspace.write'));
create trigger audit_change after insert or delete on public.organization_files
  for each row execute function public.write_audit_log();

create policy tenant_files_read on storage.objects for select to authenticated
  using (bucket_id = 'tenant-files' and public.is_org_member(((storage.foldername(name))[1])::uuid));
create policy tenant_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'tenant-files' and public.has_org_permission(((storage.foldername(name))[1])::uuid, 'workspace.write'));
create policy tenant_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'tenant-files' and public.has_org_permission(((storage.foldername(name))[1])::uuid, 'workspace.write'));
