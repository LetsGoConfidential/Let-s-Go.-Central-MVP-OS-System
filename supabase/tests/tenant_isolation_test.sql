begin;

select plan(6);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rls-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rls-member@example.test', '', now(), '{}', '{}', now(), now());

insert into public.organizations (id, name, slug)
values
  ('20000000-0000-4000-8000-000000000001', 'RLS Test Tenant A', 'rls-test-tenant-a'),
  ('20000000-0000-4000-8000-000000000002', 'RLS Test Tenant B', 'rls-test-tenant-b');

insert into public.org_members (organization_id, user_id, role, status, joined_at)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'owner', 'active', now()),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'member', 'active', now());

insert into public.clients (organization_id, name)
values
  ('20000000-0000-4000-8000-000000000001', 'RLS fixture tenant A'),
  ('20000000-0000-4000-8000-000000000002', 'RLS fixture tenant B');

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select results_eq(
  $$select name::text from public.clients where name like 'RLS fixture%' order by name$$,
  $$values ('RLS fixture tenant A'::text)$$,
  'Tenant A owner can read only Tenant A clients'
);

select throws_ok(
  $$insert into public.clients (organization_id, name) values ('20000000-0000-4000-8000-000000000002', 'RLS fixture forged client') returning id$$,
  '42501', null,
  'Tenant A owner cannot insert a client into Tenant B'
);

select results_eq(
  $$update public.clients set name = 'RLS fixture changed across tenant' where organization_id = '20000000-0000-4000-8000-000000000002' and name = 'RLS fixture tenant B' returning id::text$$,
  $$select null::text where false$$,
  'Tenant A owner cannot update Tenant B clients'
);

select results_eq(
  $$insert into public.clients (organization_id, name) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture owner-created') returning name::text$$,
  $$values ('RLS fixture owner-created'::text)$$,
  'Tenant A owner can create a client in Tenant A'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select throws_ok(
  $$insert into public.clients (organization_id, name) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture member-write') returning id$$,
  '42501', null,
  'Read-only member cannot create a client'
);

select results_eq(
  $$select name::text from public.clients where name like 'RLS fixture%' order by name$$,
  $$values ('RLS fixture owner-created'::text), ('RLS fixture tenant A'::text)$$,
  'Read-only member can read their tenant and still cannot see Tenant B'
);

select * from finish();
rollback;
