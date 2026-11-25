begin;

select plan(75);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rls-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rls-member@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'rls-manager@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'rls-tenant-b-member@example.test', '', now(), '{}', '{}', now(), now());

insert into public.organizations (id, name, slug)
values
  ('20000000-0000-4000-8000-000000000001', 'RLS Test Tenant A', 'rls-test-tenant-a'),
  ('20000000-0000-4000-8000-000000000002', 'RLS Test Tenant B', 'rls-test-tenant-b');

insert into public.org_members (organization_id, user_id, role, status, joined_at)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'owner', 'active', now()),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'member', 'active', now()),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', 'manager', 'active', now()),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004', 'owner', 'active', now());

insert into public.clients (id, organization_id, name)
values
  ('40000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'RLS fixture tenant A'),
  ('40000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'RLS fixture tenant B');

insert into public.contacts (organization_id, client_id, first_name, last_name)
values
  ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'Asha', 'Tenant A'),
  ('20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'Bina', 'Tenant B');

insert into public.invoices (organization_id, client_id, invoice_number, currency, subtotal)
values ('20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'RLS-INVOICE-TENANT-B', 'INR', 1000);

insert into public.expenses (organization_id, description, category, amount, currency)
values ('20000000-0000-4000-8000-000000000002', 'RLS expense tenant B', 'test', 25, 'INR');

insert into public.projects (id, organization_id, client_id, name)
values
  ('50000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'RLS fixture project A'),
  ('50000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'RLS fixture project B');

insert into public.tasks (organization_id, project_id, title)
values ('20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', 'RLS fixture task A');

insert into public.content_items (organization_id, client_id, project_id, title)
values
  ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', 'RLS fixture content A'),
  ('20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000002', 'RLS fixture content B');

insert into public.tasks (organization_id, project_id, title)
values ('20000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000002', 'RLS fixture task B');

insert into public.task_comments (organization_id, task_id, author_id, body)
select '20000000-0000-4000-8000-000000000002', t.id, '10000000-0000-4000-8000-000000000004', 'RLS task comment tenant B'
from public.tasks t where t.organization_id = '20000000-0000-4000-8000-000000000002' and t.title = 'RLS fixture task B';

insert into public.leads (id, organization_id, company_name, contact_name, email, stage, estimated_value)
values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'RLS fixture converted lead', 'Meera Shah', 'meera@example.test', 'won', 25000),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'RLS fixture tenant B lead', 'Ravi Tenant', 'ravi@example.test', 'qualified', 10000);

insert into public.deals (organization_id, lead_id, client_id, name, stage, value)
values ('20000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'RLS fixture tenant B deal', 'qualified', 10000);

insert into public.ai_conversations (id, organization_id, user_id, title)
values
  ('61000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'RLS AI owner private'),
  ('61000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'RLS AI member private'),
  ('61000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004', 'RLS AI tenant B private');

insert into public.ai_messages (organization_id, conversation_id, role, content)
values
  ('20000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', 'user', 'RLS AI owner message'),
  ('20000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002', 'user', 'RLS AI member message'),
  ('20000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000003', 'user', 'RLS AI tenant B message');

insert into public.ai_action_drafts (id, organization_id, user_id, title, priority)
values ('62000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004', 'RLS AI tenant B draft', 'medium');

insert into public.team_performance_reviews (
  organization_id, member_id, author_id, updated_by, period_start,
  delivery_score, communication_score, ownership_score, client_care_score, manager_notes
)
values (
  '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', '2026-11-01',
  4, 4, 5, 4, 'RLS private manager note'
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000004';

select public.submit_content_review(
  '20000000-0000-4000-8000-000000000002',
  (select id from public.content_items where organization_id = '20000000-0000-4000-8000-000000000002' and title = 'RLS fixture content B'),
  'comment', 'RLS content review tenant B'
);

insert into public.invoice_items (organization_id, invoice_id, description, quantity, unit_price)
select i.organization_id, i.id, 'RLS item tenant B', 1, 1000
from public.invoices i where i.organization_id = '20000000-0000-4000-8000-000000000002'
  and i.invoice_number = 'RLS-INVOICE-TENANT-B';

update public.invoices set status = 'sent'
where organization_id = '20000000-0000-4000-8000-000000000002'
  and invoice_number = 'RLS-INVOICE-TENANT-B';

insert into public.invoice_payments (organization_id, invoice_id, amount, currency, method, recorded_by)
select i.organization_id, i.id, 300, 'INR', 'bank_transfer', '10000000-0000-4000-8000-000000000004'
from public.invoices i where i.organization_id = '20000000-0000-4000-8000-000000000002'
  and i.invoice_number = 'RLS-INVOICE-TENANT-B';

select public.create_invoice_credit(
  '20000000-0000-4000-8000-000000000002',
  (select id from public.invoices where organization_id = '20000000-0000-4000-8000-000000000002' and invoice_number = 'RLS-INVOICE-TENANT-B'),
  'RLS-CREDIT-TENANT-B', 100, 'Tenant B isolation fixture', '10000000-0000-4000-8000-000000000004'
);

select public.create_invoice_refund(
  '20000000-0000-4000-8000-000000000002',
  (select id from public.invoices where organization_id = '20000000-0000-4000-8000-000000000002' and invoice_number = 'RLS-INVOICE-TENANT-B'),
  (select id from public.invoice_payments where organization_id = '20000000-0000-4000-8000-000000000002'
    and invoice_id = (select id from public.invoices where organization_id = '20000000-0000-4000-8000-000000000002' and invoice_number = 'RLS-INVOICE-TENANT-B')),
  50, 'Tenant B isolation fixture', '10000000-0000-4000-8000-000000000004'
);

select results_eq(
  $$select manager_notes::text from public.team_performance_reviews where member_id = '10000000-0000-4000-8000-000000000002'$$,
  $$select null::text where false$$,
  'Tenant B owner cannot read a Tenant A performance review'
);

select results_eq(
  $$select body::text from public.task_comments where body = 'RLS task comment tenant B'$$,
  $$values ('RLS task comment tenant B'::text)$$,
  'Tenant B owner can read their own task comment'
);

select results_eq(
  $$select feedback::text from public.content_reviews where feedback = 'RLS content review tenant B'$$,
  $$values ('RLS content review tenant B'::text)$$,
  'Tenant B owner can read their content review'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select results_eq(
  $$select manager_notes::text from public.team_performance_reviews where member_id = '10000000-0000-4000-8000-000000000002'$$,
  $$values ('RLS private manager note'::text)$$,
  'Tenant A owner can read the private performance review'
);

select results_eq(
  $$select name::text from public.clients where name like 'RLS fixture%' order by name$$,
  $$values ('RLS fixture tenant A'::text)$$,
  'Tenant A owner can read only Tenant A clients'
);

select results_eq(
  $$select first_name::text from public.contacts where last_name like 'Tenant %' order by first_name$$,
  $$values ('Asha'::text)$$,
  'Tenant A owner can read only Tenant A contacts'
);

select results_eq(
  $$select company_name::text from public.leads where company_name like 'RLS fixture%' order by company_name$$,
  $$values ('RLS fixture converted lead'::text)$$,
  'Tenant A owner can read only Tenant A leads'
);

select results_eq(
  $$select name::text from public.deals where name like 'RLS fixture%' order by name$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B deals'
);

select results_eq(
  $$select invoice_number::text from public.invoices where invoice_number = 'RLS-INVOICE-TENANT-B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B invoices'
);

select results_eq(
  $$select description::text from public.expenses where description = 'RLS expense tenant B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B expenses'
);

select results_eq(
  $$select description::text from public.invoice_items where description = 'RLS item tenant B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B invoice items'
);

select results_eq(
  $$select amount::numeric from public.invoice_payments where organization_id = '20000000-0000-4000-8000-000000000002'$$,
  $$select null::numeric where false$$,
  'Tenant A owner cannot read Tenant B invoice payments'
);

select results_eq(
  $$select credit_number::text from public.invoice_credits where credit_number = 'RLS-CREDIT-TENANT-B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B invoice credits'
);

select results_eq(
  $$select amount::numeric from public.invoice_refunds where organization_id = '20000000-0000-4000-8000-000000000002'$$,
  $$select null::numeric where false$$,
  'Tenant A owner cannot read Tenant B invoice refunds'
);

select results_eq(
  $$select name::text from public.projects where name = 'RLS fixture project B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B projects'
);

select results_eq(
  $$select title::text from public.tasks where title = 'RLS fixture task B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B tasks'
);

select results_eq(
  $$select title::text from public.content_items where title = 'RLS fixture content B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B content items'
);

select results_eq(
  $$select body::text from public.task_comments where body = 'RLS task comment tenant B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B task comments'
);

select results_eq(
  $$select feedback::text from public.content_reviews where feedback = 'RLS content review tenant B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B content reviews'
);

select results_eq(
  $$select title::text from public.ai_conversations where id = '61000000-0000-4000-8000-000000000001'$$,
  $$values ('RLS AI owner private'::text)$$,
  'AI conversation owner can read their own history'
);

select results_eq(
  $$select title::text from public.ai_conversations where id = '61000000-0000-4000-8000-000000000002'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read a member private AI conversation'
);

select results_eq(
  $$select title::text from public.ai_conversations where id = '61000000-0000-4000-8000-000000000003'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read a Tenant B AI conversation'
);

select results_eq(
  $$select content::text from public.ai_messages where content = 'RLS AI tenant B message'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read a Tenant B AI message'
);

select results_eq(
  $$select title::text from public.ai_action_drafts where id = '62000000-0000-4000-8000-000000000001'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read a Tenant B AI action draft'
);

select throws_ok(
  $$insert into public.invoices (organization_id, client_id, invoice_number) values ('20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'RLS-INVOICE-FORGED') returning id$$,
  '42501', null,
  'Tenant A owner cannot create an invoice in Tenant B'
);

select throws_ok(
  $$insert into public.expenses (organization_id, description, category, amount) values ('20000000-0000-4000-8000-000000000002', 'RLS forged tenant B expense', 'test', 1) returning id$$,
  '42501', null,
  'Tenant A owner cannot create an expense in Tenant B'
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
  $$select id::text from public.profiles where id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') order by id$$,
  $$values ('10000000-0000-4000-8000-000000000001'::text)$$,
  'Tenant A owner cannot read a Tenant B user profile'
);

select results_eq(
  $$select user_id::text from public.org_members where user_id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') order by user_id$$,
  $$values ('10000000-0000-4000-8000-000000000001'::text)$$,
  'Tenant A owner cannot read Tenant B membership records'
);

select results_eq(
  $$select entity_id::text from public.audit_logs where entity_type = 'clients' and entity_id in ('40000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002') order by entity_id$$,
  $$values ('40000000-0000-4000-8000-000000000001'::text)$$,
  'Tenant A owner can read audit history only for Tenant A clients'
);

select throws_ok(
  $$insert into public.audit_logs (organization_id, action, entity_type) values ('20000000-0000-4000-8000-000000000001', 'forged', 'clients') returning id$$,
  '42501', null,
  'Authenticated users cannot write audit records directly'
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

select results_eq(
  $$select manager_notes::text from public.team_performance_reviews where member_id = '10000000-0000-4000-8000-000000000002'$$,
  $$select null::text where false$$,
  'Read-only member cannot read private performance review notes'
);

select results_eq(
  $$select body::text from public.task_comments where body = 'RLS task comment tenant B'$$,
  $$select null::text where false$$,
  'Tenant A member cannot read a Tenant B task comment'
);

select results_eq(
  $$select feedback::text from public.content_reviews where feedback = 'RLS content review tenant B'$$,
  $$select null::text where false$$,
  'Tenant A member cannot read a Tenant B content review'
);

select results_eq(
  $$select title::text from public.ai_conversations where id = '61000000-0000-4000-8000-000000000002'$$,
  $$values ('RLS AI member private'::text)$$,
  'AI member can read their own private conversation'
);

select results_eq(
  $$select content::text from public.ai_messages where conversation_id = '61000000-0000-4000-8000-000000000002'$$,
  $$values ('RLS AI member message'::text)$$,
  'AI member can read messages in their private conversation'
);

select results_eq(
  $$select title::text from public.ai_conversations where id = '61000000-0000-4000-8000-000000000001'$$,
  $$select null::text where false$$,
  'AI member cannot read the owner private conversation'
);

select results_eq(
  $$select content::text from public.ai_messages where content = 'RLS AI tenant B message'$$,
  $$select null::text where false$$,
  'AI member cannot read a Tenant B message'
);

select throws_ok(
  $$insert into public.clients (organization_id, name) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture member-write') returning id$$,
  '42501', null,
  'Read-only member cannot create a client'
);

select results_eq(
  $$select name::text from public.clients where name like 'RLS fixture%' order by name$$,
  $$values ('RLS fixture converted lead'::text), ('RLS fixture owner-created'::text), ('RLS fixture tenant A'::text)$$,
  'Read-only member can read their tenant and still cannot see Tenant B'
);

select results_eq(
  $$select company_name::text from public.leads where company_name like 'RLS fixture%' order by company_name$$,
  $$values ('RLS fixture converted lead'::text)$$,
  'Read-only member can read Tenant A leads but not Tenant B leads'
);

select results_eq(
  $$select id::text from public.profiles where id in ('10000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004') order by id$$,
  $$values ('10000000-0000-4000-8000-000000000002'::text)$$,
  'Read-only member cannot read a Tenant B user profile'
);

select results_eq(
  $$select name::text from public.deals where name like 'RLS fixture%' order by name$$,
  $$values ('RLS fixture converted lead — New business'::text)$$,
  'Read-only member can read Tenant A deals but not Tenant B deals'
);

select throws_ok(
  $$insert into public.leads (organization_id, company_name) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture member lead') returning id$$,
  '42501', null,
  'Read-only member cannot create a lead'
);

select throws_ok(
  $$insert into public.contacts (organization_id, client_id, first_name) values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'Member') returning id$$,
  '42501', null,
  'Read-only member cannot create a contact'
);

select throws_ok(
  $$insert into public.invoices (organization_id, client_id, invoice_number) values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'RLS-INVOICE-MEMBER') returning id$$,
  '42501', null,
  'Read-only member cannot create an invoice in their tenant'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select results_eq(
  $$select
      (select count(*)::bigint from public.projects p where p.organization_id = '20000000-0000-4000-8000-000000000001' and p.name = 'RLS fixture project A' and p.client_id = '40000000-0000-4000-8000-000000000001'),
      (select count(*)::bigint from public.tasks t where t.organization_id = '20000000-0000-4000-8000-000000000001' and t.title = 'RLS fixture task A' and t.project_id = '50000000-0000-4000-8000-000000000001'),
      (select count(*)::bigint from public.content_items c where c.organization_id = '20000000-0000-4000-8000-000000000001' and c.title = 'RLS fixture content A' and c.client_id = '40000000-0000-4000-8000-000000000001' and c.project_id = '50000000-0000-4000-8000-000000000001')$$,
  $$values (1::bigint, 1::bigint, 1::bigint)$$,
  'Tenant A project, task, and content remain linked to Tenant A records'
);

select throws_ok(
  $$insert into public.projects (organization_id, client_id, name) values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', 'RLS fixture cross-tenant project') returning id$$,
  '23503', null,
  'Project cannot link a client from another tenant'
);

select throws_ok(
  $$insert into public.tasks (organization_id, project_id, title) values ('20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000002', 'RLS fixture cross-tenant task') returning id$$,
  '23503', null,
  'Task cannot link a project from another tenant'
);

select throws_ok(
  $$insert into public.tasks (organization_id, project_id, client_id, title) values ('20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', 'RLS fixture cross-tenant task client') returning id$$,
  '23503', null,
  'Task cannot link a client from another tenant'
);

select throws_ok(
  $$insert into public.tasks (organization_id, project_id, assignee_id, title) values ('20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004', 'RLS fixture cross-tenant assignee') returning id$$,
  '23514', 'Task assignee must be an active internal member of the same organization',
  'Tenant A task cannot be assigned to an active member of Tenant B'
);

select throws_ok(
  $$insert into public.content_items (organization_id, client_id, project_id, title) values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000001', 'RLS fixture cross-tenant content') returning id$$,
  '23503', null,
  'Content cannot link a client from another tenant'
);

select throws_ok(
  $$insert into public.content_items (organization_id, client_id, project_id, title) values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000002', 'RLS fixture cross-tenant content project') returning id$$,
  '23503', null,
  'Content cannot link a project from another tenant'
);

select throws_ok(
  $$insert into public.deals (organization_id, lead_id, client_id, name) values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001', 'RLS fixture cross-tenant deal') returning id$$,
  '23503', null,
  'Deal cannot link a lead from another tenant'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select results_eq(
  $$update public.organizations set name = 'RLS fixture member update' where id = '20000000-0000-4000-8000-000000000001' returning id::text$$,
  $$select null::text where false$$,
  'Read-only member cannot update organization settings'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

select results_eq(
  $$select manager_notes::text from public.team_performance_reviews where member_id = '10000000-0000-4000-8000-000000000002'$$,
  $$values ('RLS private manager note'::text)$$,
  'Authorized manager can read the private performance review'
);

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

select throws_ok(
  $$insert into public.roles (organization_id, name) values ('20000000-0000-4000-8000-000000000001', 'RLS fixture manager role') returning id$$,
  '42501', null,
  'Manager without organization.manage cannot create a role'
);

select results_eq(
  $$select invoice_number::text from public.invoices where invoice_number = 'RLS-INVOICE-TENANT-B'$$,
  $$select null::text where false$$,
  'Manager cannot read Tenant B financial records'
);

select throws_ok(
  $$insert into public.invoices (organization_id, client_id, invoice_number) values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'RLS-INVOICE-MANAGER') returning id$$,
  '42501', null,
  'Manager without finance.manage cannot create an invoice'
);

select results_eq(
  $$update public.organizations set name = 'RLS fixture manager update' where id = '20000000-0000-4000-8000-000000000001' returning id::text$$,
  $$select null::text where false$$,
  'Manager without organization.manage cannot update organization settings'
);

select results_eq(
  $$update public.org_members set status = 'suspended' where organization_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000002' returning user_id::text$$,
  $$select null::text where false$$,
  'Manager without organization.manage cannot suspend a workspace member'
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
