begin;

select plan(153);

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

insert into public.leave_requests (organization_id, member_id, leave_type, start_date, end_date, reason)
values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'Annual', '2026-12-10', '2026-12-11', 'RLS private leave fixture');

insert into public.org_invitations (organization_id, email, user_id, role, status, invited_by)
values
  ('20000000-0000-4000-8000-000000000001', 'rls-invite-a@example.test', '10000000-0000-4000-8000-000000000004', 'member', 'pending', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', 'rls-invite-b@example.test', '10000000-0000-4000-8000-000000000002', 'member', 'pending', '10000000-0000-4000-8000-000000000004');

insert into public.employee_kpi_goals (organization_id, member_id, metric_key, title, target, unit, period_start, period_end, created_by, updated_by)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'tasks_completed', 'RLS Tenant A monthly tasks', 10, 'count', '2026-11-01', '2026-11-30', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004', 'tasks_completed', 'RLS Tenant B monthly tasks', 5, 'count', '2026-11-01', '2026-11-30', '10000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004');

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

insert into public.tasks (id, organization_id, project_id, title)
values ('51000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', 'RLS fixture task A');

update public.tasks set assignee_id = '10000000-0000-4000-8000-000000000002'
where id = '51000000-0000-4000-8000-000000000001';

insert into public.tasks (id, organization_id, project_id, assignee_id, title)
values ('51000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'RLS fixture owner task');

insert into public.task_comments (organization_id, task_id, author_id, body)
values ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'RLS owner task private note');

insert into public.content_items (organization_id, client_id, project_id, title)
values
  ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', 'RLS fixture content A'),
  ('20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000002', 'RLS fixture content B');

insert into public.tasks (id, organization_id, project_id, title)
values ('51000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000002', 'RLS fixture task B');

insert into public.task_comments (organization_id, task_id, author_id, body)
select '20000000-0000-4000-8000-000000000002', t.id, '10000000-0000-4000-8000-000000000004', 'RLS task comment tenant B'
from public.tasks t where t.organization_id = '20000000-0000-4000-8000-000000000002' and t.title = 'RLS fixture task B';

insert into public.leads (id, organization_id, company_name, contact_name, email, stage, estimated_value)
values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'RLS fixture converted lead', 'Meera Shah', 'meera@example.test', 'won', 25000),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'RLS fixture tenant B lead', 'Ravi Tenant', 'ravi@example.test', 'qualified', 10000);

insert into public.deals (organization_id, lead_id, client_id, name, stage, value)
values ('20000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002', 'RLS fixture tenant B deal', 'qualified', 10000);

insert into public.organization_files (organization_id, storage_path, original_filename, mime_type, size_bytes, uploaded_by)
values ('20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002/RLS-file.pdf', 'RLS-file.pdf', 'application/pdf', 10, '10000000-0000-4000-8000-000000000004');

insert into storage.objects (bucket_id, name)
values ('tenant-files', '20000000-0000-4000-8000-000000000002/RLS-storage-object.pdf');

insert into public.integrations (id, organization_id, provider, display_name, status)
values ('73000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'slack', 'RLS Tenant B Slack', 'disconnected');

insert into public.automation_rules (id, organization_id, name, trigger_type, created_by)
values ('74000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'RLS Tenant B rule', 'manual', '10000000-0000-4000-8000-000000000004');

insert into public.automation_runs (id, organization_id, rule_id, status, trigger_payload)
values ('75000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', '74000000-0000-4000-8000-000000000002', 'succeeded', '{"fixture":true}');

insert into public.automation_run_attempts (organization_id, run_id, attempt_number, idempotency_key, actor_id, status, result)
values ('20000000-0000-4000-8000-000000000002', '75000000-0000-4000-8000-000000000002', 1, 'RLS-AUTO-ATTEMPT-TENANT-B', '10000000-0000-4000-8000-000000000004', 'succeeded', '{"fixture":true}');

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

insert into public.attendance_days (organization_id, member_id, work_date, checked_in_at, checked_out_at)
select '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003',
  (now() at time zone o.timezone)::date, now() - interval '8 hours', now() - interval '1 hour'
from public.organizations o where o.id = '20000000-0000-4000-8000-000000000001';

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
  $$select email::text from public.org_invitations where email = 'rls-invite-b@example.test'$$,
  $$values ('rls-invite-b@example.test'::text)$$,
  'Tenant B owner can read their pending invitation'
);

select results_eq(
  $$select title::text from public.employee_kpi_goals where member_id = '10000000-0000-4000-8000-000000000004'$$,
  $$values ('RLS Tenant B monthly tasks'::text)$$,
  'Tenant B owner can read their employee KPI goal'
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

select results_eq(
  $$select name::text from storage.objects where bucket_id = 'tenant-files' and name = '20000000-0000-4000-8000-000000000002/RLS-storage-object.pdf'$$,
  $$values ('20000000-0000-4000-8000-000000000002/RLS-storage-object.pdf'::text)$$,
  'Tenant B owner can read their private storage object'
);

select results_eq(
  $$select
      (select count(*)::bigint from public.organization_files where original_filename = 'RLS-file.pdf'),
      (select count(*)::bigint from public.integrations where id = '73000000-0000-4000-8000-000000000002'),
      (select count(*)::bigint from public.automation_runs where id = '75000000-0000-4000-8000-000000000002'),
      (select count(*)::bigint from public.automation_run_attempts where idempotency_key = 'RLS-AUTO-ATTEMPT-TENANT-B')$$,
  $$values (1::bigint, 1::bigint, 1::bigint, 1::bigint)$$,
  'Tenant B owner can read their file, integration, and automation run history'
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
  $$select email::text from public.org_invitations where email = 'rls-invite-a@example.test'$$,
  $$values ('rls-invite-a@example.test'::text)$$,
  'Tenant A owner can read their pending invitation'
);

select results_eq(
  $$select email::text from public.org_invitations where email = 'rls-invite-b@example.test'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read a Tenant B invitation'
);

select results_eq(
  $$select title::text from public.employee_kpi_goals where title like 'RLS Tenant % monthly tasks' order by title$$,
  $$values ('RLS Tenant A monthly tasks'::text)$$,
  'Tenant A owner cannot read Tenant B employee KPI goals'
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
  $$select original_filename::text from public.organization_files where original_filename = 'RLS-file.pdf'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B file metadata'
);

select results_eq(
  $$select name::text from storage.objects where bucket_id = 'tenant-files' and name = '20000000-0000-4000-8000-000000000002/RLS-storage-object.pdf'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read a Tenant B storage object'
);

select results_eq(
  $$insert into storage.objects (bucket_id, name) values ('tenant-files', '20000000-0000-4000-8000-000000000001/RLS-owner-upload.pdf') returning name::text$$,
  $$values ('20000000-0000-4000-8000-000000000001/RLS-owner-upload.pdf'::text)$$,
  'Tenant A owner can upload into their own private storage folder'
);

select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('tenant-files', '20000000-0000-4000-8000-000000000002/RLS-forged-object.pdf') returning name$$,
  '42501', null,
  'Tenant A owner cannot upload a file into Tenant B storage'
);

select results_eq(
  $$select display_name::text from public.integrations where id = '73000000-0000-4000-8000-000000000002'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B integrations'
);

select results_eq(
  $$select name::text from public.automation_rules where id = '74000000-0000-4000-8000-000000000002'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B automation rules'
);

select results_eq(
  $$select status::text from public.automation_runs where id = '75000000-0000-4000-8000-000000000002'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B automation runs'
);

select results_eq(
  $$select idempotency_key::text from public.automation_run_attempts where idempotency_key = 'RLS-AUTO-ATTEMPT-TENANT-B'$$,
  $$select null::text where false$$,
  'Tenant A owner cannot read Tenant B automation attempts'
);

select throws_ok(
  $$select encrypted_credentials from public.integration_secrets$$,
  '42501', null,
  'Authenticated users cannot read the service-role credential vault'
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
  $$select title::text from public.employee_kpi_goals where member_id = '10000000-0000-4000-8000-000000000002'$$,
  $$values ('RLS Tenant A monthly tasks'::text)$$,
  'Employee can read their own KPI goal'
);

select throws_ok(
  $$insert into public.employee_kpi_goals (organization_id, member_id, metric_key, title, target, unit, period_start, period_end) values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'tasks_completed', 'RLS member-created goal', 20, 'count', '2026-12-01', '2026-12-31') returning id$$,
  '42501', null,
  'Employee cannot set their own KPI target'
);

select throws_ok(
  $$select public.revoke_org_invitation('20000000-0000-4000-8000-000000000001', (select id from public.org_invitations where email = 'rls-invite-a@example.test'))$$,
  '42501', 'Not authorized to manage organization invitations',
  'Read-only member cannot revoke a pending invitation'
);

select results_eq(
  $$select email::text from public.org_invitations where email = 'rls-invite-a@example.test'$$,
  $$select null::text where false$$,
  'Read-only member cannot read pending invitations'
);

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
  $$select name::text from storage.objects where bucket_id = 'tenant-files' and name = '20000000-0000-4000-8000-000000000002/RLS-storage-object.pdf'$$,
  $$select null::text where false$$,
  'Tenant A member cannot read a Tenant B storage object'
);

select results_eq(
  $$select
      (select count(*)::bigint from public.organization_files where original_filename = 'RLS-file.pdf'),
      (select count(*)::bigint from public.integrations where id = '73000000-0000-4000-8000-000000000002'),
      (select count(*)::bigint from public.automation_rules where id = '74000000-0000-4000-8000-000000000002'),
      (select count(*)::bigint from public.automation_runs where id = '75000000-0000-4000-8000-000000000002'),
      (select count(*)::bigint from public.automation_run_attempts where idempotency_key = 'RLS-AUTO-ATTEMPT-TENANT-B')$$,
  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
  'Tenant A member cannot read Tenant B files, integrations, or automation history'
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

select throws_ok(
  $$insert into public.task_comments (organization_id, task_id, author_id, body) values ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'RLS unauthorized member comment') returning id$$,
  '42501', null,
  'Read-only member cannot add a task comment'
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

select results_eq(
  $$insert into public.leave_requests (organization_id, member_id, leave_type, start_date, end_date, reason) values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'Sick', '2026-12-12', '2026-12-12', 'Private reason') returning status::text$$,
  $$values ('pending'::text)$$,
  'Employee can create a pending leave request for themselves'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

select results_eq(
  $$select count(*)::bigint from public.leave_requests where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (0::bigint)$$,
  'Manager without hr.leave.manage cannot read an employee leave request'
);

select throws_ok(
  $$select public.review_leave_request('20000000-0000-4000-8000-000000000001', (select id from public.leave_requests limit 1), 'approved')$$,
  '42501', 'Not authorized to review leave requests',
  'Manager without hr.leave.manage cannot approve a leave request'
);

select results_eq(
  $$select public.has_org_permission('20000000-0000-4000-8000-000000000001', 'hr.payroll.manage')$$,
  $$values (false)$$,
  'Manager role does not implicitly receive restricted payroll permission'
);

select results_eq(
  $$select title::text from public.employee_kpi_goals where member_id = '10000000-0000-4000-8000-000000000002'$$,
  $$values ('RLS Tenant A monthly tasks'::text)$$,
  'Authorized manager can read the employee KPI goal'
);

select throws_ok(
  $$select public.revoke_org_invitation('20000000-0000-4000-8000-000000000001', (select id from public.org_invitations where email = 'rls-invite-a@example.test'))$$,
  '42501', 'Not authorized to manage organization invitations',
  'Manager without organization.manage cannot revoke a pending invitation'
);

select results_eq(
  $$select email::text from public.org_invitations where email = 'rls-invite-a@example.test'$$,
  $$select null::text where false$$,
  'Manager without organization.manage cannot read pending invitations'
);

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

select throws_ok(
  $$select public.set_member_department('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'Sales')$$,
  '42501', 'Not authorized to manage organization departments',
  'Manager without organization.manage cannot assign employee departments'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select results_eq(
  $$select public.assign_custom_role('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', public.save_custom_role('20000000-0000-4000-8000-000000000001', 'RLS HR Specialist', '{"hr.leave.manage":true,"hr.people.invite":true,"hr.attendance.manage":true,"tasks.self.update":true}'::jsonb))$$,
  $$values (true)$$,
  'Owner can create and assign an HR leave-review permission to a custom role'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select is(
  public.has_org_permission('20000000-0000-4000-8000-000000000001', 'hr.people.invite'),
  true,
  'Explicit HR invite permission can invite regular members'
);

select results_eq(
  $$select count(*)::bigint from public.leave_requests where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (2::bigint)$$,
  'HR role can read its organization leave queue'
);

select results_eq(
  $$select public.review_leave_request('20000000-0000-4000-8000-000000000001', (select id from public.leave_requests where reason = 'RLS private leave fixture'), 'approved')$$,
  $$values (true)$$,
  'HR role can approve a pending leave request'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select results_eq(
  $$select public.set_leave_balance('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', extract(year from now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001'))::integer, 'Annual', 12, 1)$$,
  $$values (true)$$,
  'Owner can allocate annual leave to an employee'
);

select results_eq(
  $$select public.set_leave_balance('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', extract(year from now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001'))::integer, 'Annual', 20, 0)$$,
  $$values (true)$$,
  'Owner can allocate a separate leave balance for themselves'
);

select results_eq(
  $$select public.set_leave_balance('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', extract(year from now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001'))::integer, 'Annual', 15, 0)$$,
  $$values (true)$$,
  'Owner can allocate leave to a manager'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

select results_eq(
  $$select count(*)::bigint from public.leave_balances where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (1::bigint)$$,
  'Employee without HR permission can read only their own leave balance'
);

select results_eq(
  $$select count(*)::bigint from public.leave_balances where member_id = '10000000-0000-4000-8000-000000000001'$$,
  $$values (0::bigint)$$,
  'Employee without HR permission cannot read an owner leave balance'
);

select throws_ok(
  $$select public.set_leave_balance('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', 2026, 'Annual', 30, 0)$$,
  '42501', 'Not authorized to manage leave balances',
  'Manager without HR leave permission cannot change a balance'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select results_eq(
  $$select count(*)::bigint from public.leave_balances where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (3::bigint)$$,
  'HR role can review all employee leave balances in its organization'
);

select results_eq(
  $$select entitled_days::numeric, adjustment_days::numeric from public.leave_balances where member_id = '10000000-0000-4000-8000-000000000002' and leave_type = 'Annual'$$,
  $$values (12::numeric, 1::numeric)$$,
  'HR sees the employee allocation and adjustment values'
);

select results_eq(
  $$select public.set_leave_balance('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', extract(year from now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001'))::integer, 'Annual', 14, -1)$$,
  $$values (true)$$,
  'HR can update an employee leave allocation'
);

select results_eq(
  $$select entitled_days::numeric, adjustment_days::numeric from public.leave_balances where member_id = '10000000-0000-4000-8000-000000000002' and leave_type = 'Annual'$$,
  $$values (14::numeric, -1::numeric)$$,
  'Updated leave allocation is recorded'
);

select throws_ok(
  $$select public.set_leave_balance('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000004', 2026, 'Annual', 10, 0)$$,
  '42501', 'Not authorized to manage leave balances',
  'HR member cannot allocate leave in another tenant'
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

select results_eq(
  $$select public.revoke_org_invitation('20000000-0000-4000-8000-000000000001', (select id from public.org_invitations where email = 'rls-invite-a@example.test'))$$,
  $$values (true)$$,
  'Owner can revoke a pending invitation'
);

select results_eq(
  $$insert into public.employee_kpi_goals (organization_id, member_id, metric_key, title, target, unit, period_start, period_end) values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'tasks_completed', 'RLS owner-created KPI goal', 12, 'count', '2026-12-01', '2026-12-31') returning title::text$$,
  $$values ('RLS owner-created KPI goal'::text)$$,
  'Organization owner can create an employee KPI goal'
);

select results_eq(
  $$select public.set_member_department('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'Sales')$$,
  $$values (true)$$,
  'Organization owner can assign a department to an employee'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select is(
  public.has_org_permission('20000000-0000-4000-8000-000000000001', 'tasks.self.update'),
  true,
  'Assigned employee receives the narrow task progress permission'
);

select is(
  public.set_assigned_task_status('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', 'in_progress'),
  true,
  'Employee can update status for an assigned task'
);

select results_eq(
  $$select title::text, status::text from public.tasks where id = '51000000-0000-4000-8000-000000000001'$$,
  $$values ('RLS fixture task A'::text, 'in_progress'::text)$$,
  'Self-service status update leaves task details intact'
);

select throws_ok(
  $$select public.set_assigned_task_status('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000003', 'done')$$,
  '42501', 'Assigned task not found',
  'Employee cannot update a task assigned to another teammate'
);

select results_eq(
  $$update public.tasks set title = 'RLS forged task edit' where id = '51000000-0000-4000-8000-000000000001' returning title::text$$,
  $$select null::text where false$$,
  'Self-service task permission cannot edit task details directly'
);

select results_eq(
  $$select title::text from public.tasks where id = '51000000-0000-4000-8000-000000000001'$$,
  $$values ('RLS fixture task A'::text)$$,
  'Rejected direct task edit leaves the task unchanged'
);

select results_eq(
  $$insert into public.task_comments (organization_id, task_id, body) values ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', 'RLS assigned employee progress update') returning body::text$$,
  $$values ('RLS assigned employee progress update'::text)$$,
  'Employee can add a progress note to their assigned task'
);

select throws_ok(
  $$insert into public.task_comments (organization_id, task_id, body) values ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000003', 'RLS unauthorized coworker update') returning body::text$$,
  '42501', null,
  'Employee cannot add an update to another teammate task'
);

select results_eq(
  $$select title::text from public.tasks where organization_id = '20000000-0000-4000-8000-000000000001' order by title$$,
  $$values ('RLS fixture task A'::text)$$,
  'Employee task view shows only their assigned work'
);

select results_eq(
  $$select body::text from public.task_comments where body = 'RLS owner task private note'$$,
  $$select null::text where false$$,
  'Employee cannot read updates from another teammate task'
);

select throws_ok(
  $$select public.set_assigned_task_status('20000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000002', 'done')$$,
  '42501', 'Not authorized to update assigned tasks',
  'Employee cannot update a task across tenant boundaries'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000004';

select throws_ok(
  $$select public.record_attendance('20000000-0000-4000-8000-000000000001', 'check_in')$$,
  '42501', 'Not authorized to record attendance',
  'Tenant B employee cannot record attendance in Tenant A'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select is(
  (public.record_attendance('20000000-0000-4000-8000-000000000001', 'check_in')).member_id,
  '10000000-0000-4000-8000-000000000002'::uuid,
  'Employee can check in for their own attendance'
);

select is(
  (public.record_attendance('20000000-0000-4000-8000-000000000001', 'check_in')).member_id,
  '10000000-0000-4000-8000-000000000002'::uuid,
  'Repeated check-in is idempotent for the same organization day'
);

select is(
  (select count(*)::integer from public.attendance_days where organization_id = '20000000-0000-4000-8000-000000000001' and member_id = '10000000-0000-4000-8000-000000000002'),
  1,
  'Attendance has only one row per member and work date'
);

select ok(
  (public.record_attendance('20000000-0000-4000-8000-000000000001', 'check_out')).checked_out_at is not null,
  'Employee check-out records its timestamp'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

select is(
  public.has_org_permission('20000000-0000-4000-8000-000000000001', 'hr.attendance.manage'),
  false,
  'Manager without the HR attendance permission cannot review team attendance'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::integer from public.attendance_days where organization_id = '20000000-0000-4000-8000-000000000001'),
  2,
  'Organization owner can review team attendance'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select results_eq(
  $$
    with attendance as (
      select id from public.attendance_days
      where member_id = '10000000-0000-4000-8000-000000000002'
      order by created_at desc limit 1
    ), submitted as (
      select public.submit_attendance_correction(
        '20000000-0000-4000-8000-000000000001', (select id from attendance),
        (now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001')) - interval '8 hours',
        (now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001')) - interval '1 hour',
        'Clock was recorded late'
      ) as correction_id
    )
    select c.status::text from submitted s
    join public.attendance_corrections c on c.id = s.correction_id
  $$,
  $$values ('pending'::text)$$,
  'Employee can submit a correction for their own attendance record'
);

select results_eq(
  $$select count(*)::bigint from public.attendance_corrections where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (1::bigint)$$,
  'Employee can read their own correction request'
);

select throws_ok(
  $$select public.submit_attendance_correction('20000000-0000-4000-8000-000000000001', (select id from public.attendance_days where member_id = '10000000-0000-4000-8000-000000000003' order by created_at desc limit 1), (now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001')) - interval '8 hours', (now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001')) - interval '1 hour', 'Attempt to edit coworker')$$,
  '42501', 'Attendance record not found',
  'Employee cannot request a correction for a coworker attendance record'
);

select throws_ok(
  $$select public.submit_attendance_correction('20000000-0000-4000-8000-000000000001', (select id from public.attendance_days where member_id = '10000000-0000-4000-8000-000000000002' order by created_at desc limit 1), (now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001')) - interval '8 hours', (now() at time zone (select timezone from public.organizations where id = '20000000-0000-4000-8000-000000000001')) - interval '1 hour', 'Duplicate request')$$,
  '23505', 'A correction is already pending for this workday',
  'Employee cannot create a second pending correction for a workday'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000003';

select results_eq(
  $$select count(*)::bigint from public.attendance_corrections where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (0::bigint)$$,
  'Manager without HR attendance permission cannot read correction requests'
);

select throws_ok(
  $$select public.review_attendance_correction('20000000-0000-4000-8000-000000000001', (select id from public.attendance_corrections limit 1), 'approved')$$,
  '42501', 'Not authorized to review attendance corrections',
  'Manager without HR attendance permission cannot approve a correction'
);

set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

select results_eq(
  $$select count(*)::bigint from public.attendance_corrections where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values (1::bigint)$$,
  'HR role can read attendance correction requests for its organization'
);

select results_eq(
  $$select public.review_attendance_correction('20000000-0000-4000-8000-000000000001', (select id from public.attendance_corrections limit 1), 'approved')$$,
  $$values (true)$$,
  'HR role can approve an attendance correction'
);

select results_eq(
  $$select status::text, decided_by::text from public.attendance_corrections where organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$values ('approved'::text, '10000000-0000-4000-8000-000000000002'::text)$$,
  'Approved correction records its status and HR reviewer'
);

select results_eq(
  $$select d.checked_in_at, d.checked_out_at from public.attendance_days d join public.attendance_corrections c on c.organization_id = d.organization_id and c.attendance_id = d.id where c.organization_id = '20000000-0000-4000-8000-000000000001'$$,
  $$select ((now() at time zone o.timezone) - interval '8 hours') at time zone o.timezone, ((now() at time zone o.timezone) - interval '1 hour') at time zone o.timezone from public.organizations o where o.id = '20000000-0000-4000-8000-000000000001'$$,
  'Approval applies corrected organization-local times to the attendance record'
);

select throws_ok(
  $$select public.submit_attendance_correction('20000000-0000-4000-8000-000000000002', (select id from public.attendance_days where member_id = '10000000-0000-4000-8000-000000000002' limit 1), now()::timestamp, null::timestamp, 'Cross tenant attempt')$$,
  '42501', 'Not authorized to request attendance correction',
  'Employee cannot create attendance corrections across tenant boundaries'
);

select * from finish();
rollback;
