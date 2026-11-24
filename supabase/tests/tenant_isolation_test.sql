begin;

select plan(20);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rls-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rls-member@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'rls-manager@example.test', '', now(), '{}', '{}', now(), now());

insert into public.organizations (id, name, slug)
values
  ('20000000-0000-4000-8000-000000000001', 'RLS Test Tenant A', 'rls-test-tenant-a'),
  ('20000000-0000-4000-8000-000000000002', 'RLS Test Tenant B', 'rls-test-tenant-b');

insert into public.org_members (organization_id, user_id, role, status, joined_at)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'owner', 'active', now()),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'member', 'active', now()),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', 'manager', 'active', now());

insert into public.clients (organization_id, name)
values
  ('20000000-0000-4000-8000-000000000001', 'RLS fixture tenant A'),
  ('20000000-0000-4000-8000-000000000002', 'RLS fixture tenant B');

insert into public.leads (id, organization_id, company_name, contact_name, email, stage, estimated_value)
values (
  '30000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'RLS fixture converted lead', 'Meera Shah', 'meera@example.test', 'won', 25000
);

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

select results_eq(
  $$select name::text from public.organizations where name like 'RLS Test Tenant%' order by name$$,
  $$values ('RLS Test Tenant A'::text)$$,
  'Tenant A owner can read only Tenant A organization settings'
);

select results_eq(
  $$update public.organizations set name = 'RLS fixture changed across tenant' where slug = 'rls-test-tenant-b' returning id::text$$,
  $$select null::text where false$$,
  'Tenant A owner cannot update Tenant B organization settings'
);

select public.convert_won_lead_to_client(
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001'
);

select results_eq(
  $$select
      (select count(*)::bigint from public.clients c where c.id = l.converted_client_id),
      (select count(*)::bigint from public.contacts c where c.organization_id = l.organization_id and c.client_id = l.converted_client_id and c.first_name = 'Meera' and c.last_name = 'Shah' and c.is_primary),
      (select count(*)::bigint from public.deals d where d.organization_id = l.organization_id and d.lead_id = l.id and d.client_id = l.converted_client_id and d.stage = 'won' and d.value = 25000)
    from public.leads l where l.id = '30000000-0000-4000-8000-000000000001'$$,
  $$values (1::bigint, 1::bigint, 1::bigint)$$,
  'Won lead conversion creates its client, primary contact, and won deal together'
);

select is(
  public.convert_won_lead_to_client(
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001'
  )::text,
  (select converted_client_id::text from public.leads where id = '30000000-0000-4000-8000-000000000001'),
  'Repeated won lead conversion returns the existing client'
);

select results_eq(
  $$select
      (select count(*)::bigint from public.clients where organization_id = l.organization_id and name = l.company_name),
      (select count(*)::bigint from public.deals where organization_id = l.organization_id and lead_id = l.id)
    from public.leads l where l.id = '30000000-0000-4000-8000-000000000001'$$,
  $$values (1::bigint, 1::bigint)$$,
  'Repeated conversion does not duplicate client or deal records'
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

select results_eq(
  $$update public.organizations set name = 'RLS fixture member update' where id = '20000000-0000-4000-8000-000000000001' returning id::text$$,
  $$select null::text where false$$,
  'Read-only member cannot update organization settings'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

select results_eq(
  $$select name::text from public.organizations where name like 'RLS Test Tenant%' order by name$$,
  $$values ('RLS Test Tenant A'::text)$$,
  'Manager can read only their own organization settings'
);

select results_eq(
  $$insert into public.clients (organization_id, name) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture manager-created') returning name::text$$,
  $$values ('RLS fixture manager-created'::text)$$,
  'Manager can create workspace records in their organization'
);

select throws_ok(
  $$insert into public.expenses (organization_id, description, category, amount) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture restricted expense', 'test', 1) returning id$$,
  '42501', null,
  'Manager without finance.manage cannot create expenses'
);

select results_eq(
  $$update public.organizations set name = 'RLS fixture manager update' where id = '20000000-0000-4000-8000-000000000001' returning id::text$$,
  $$select null::text where false$$,
  'Manager without organization.manage cannot update organization settings'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select public.create_invoice_with_item(
  '20000000-0000-4000-8000-000000000001',
  (select id from public.clients where organization_id = '20000000-0000-4000-8000-000000000001' and name = 'RLS fixture tenant A'),
  'RLS-INVOICE-001', 'INR', 0, current_date, current_date + 30, 'Test service', 1, 100
);

update public.invoices set status = 'sent'
where organization_id = '20000000-0000-4000-8000-000000000001' and invoice_number = 'RLS-INVOICE-001';

insert into public.invoice_payments (organization_id, invoice_id, amount, currency, method, recorded_by)
select '20000000-0000-4000-8000-000000000001', id, 40, 'INR', 'bank_transfer', '10000000-0000-4000-8000-000000000001'
from public.invoices where organization_id = '20000000-0000-4000-8000-000000000001' and invoice_number = 'RLS-INVOICE-001';

select results_eq(
  $$select i.status::text, i.subtotal::numeric, i.amount_paid::numeric,
      (select count(*)::bigint from public.invoice_items it where it.organization_id = i.organization_id and it.invoice_id = i.id)
    from public.invoices i where i.organization_id = '20000000-0000-4000-8000-000000000001' and i.invoice_number = 'RLS-INVOICE-001'$$,
  $$values ('partially_paid'::text, 100::numeric, 40::numeric, 1::bigint)$$,
  'Itemized invoice calculates its subtotal and partial payment updates its balance'
);

select throws_ok(
  $$insert into public.invoice_payments (organization_id, invoice_id, amount, currency, method) select '20000000-0000-4000-8000-000000000001', id, 61, 'INR', 'bank_transfer' from public.invoices where organization_id = '20000000-0000-4000-8000-000000000001' and invoice_number = 'RLS-INVOICE-001' returning id$$,
  'P0001', 'Payment exceeds remaining invoice balance',
  'Invoice payment ledger rejects an overpayment'
);

select throws_ok(
  $$insert into public.invoice_payments (organization_id, invoice_id, amount, currency, method) select '20000000-0000-4000-8000-000000000001', id, 1, 'USD', 'bank_transfer' from public.invoices where organization_id = '20000000-0000-4000-8000-000000000001' and invoice_number = 'RLS-INVOICE-001' returning id$$,
  'P0001', 'Payment currency must match invoice currency',
  'Invoice payment ledger rejects a currency mismatch'
);

insert into public.invoice_payments (organization_id, invoice_id, amount, currency, method, recorded_by)
select '20000000-0000-4000-8000-000000000001', id, 60, 'INR', 'bank_transfer', '10000000-0000-4000-8000-000000000001'
from public.invoices where organization_id = '20000000-0000-4000-8000-000000000001' and invoice_number = 'RLS-INVOICE-001';

select results_eq(
  $$select status::text, amount_paid::numeric from public.invoices where organization_id = '20000000-0000-4000-8000-000000000001' and invoice_number = 'RLS-INVOICE-001'$$,
  $$values ('paid'::text, 100::numeric)$$,
  'Final invoice payment settles the recorded balance'
);

select * from finish();
rollback;
