-- First customer workspace. This seed is safe demo context, not production financial data.
insert into public.organizations (id, name, slug, legal_name, timezone, currency)
values ('a0000000-0000-4000-8000-000000000001', 'Let’s Go Digitals', 'lets-go-digitals', 'Let’s Go Digitals', 'Asia/Kolkata', 'INR')
on conflict (slug) do update set name = excluded.name, legal_name = excluded.legal_name;

insert into public.roles (organization_id, name, is_system, permissions)
select id, 'Administrator', true,
  '{"workspace.write":true,"finance.manage":true,"members.manage":true,"organization.manage":true}'::jsonb
from public.organizations where slug = 'lets-go-digitals'
on conflict (organization_id, name) do nothing;

insert into public.roles (organization_id, name, is_system, permissions)
select id, 'Agency teammate', true, '{"workspace.write":true}'::jsonb
from public.organizations where slug = 'lets-go-digitals'
on conflict (organization_id, name) do nothing;

insert into public.clients (organization_id, name, industry, health, monthly_value)
select id, sample.name, sample.industry, sample.health, sample.monthly_value
from public.organizations
cross join (values
  ('Samprati Studio', 'Lifestyle', 'healthy', 85000::numeric),
  ('Vasishtha Wellness', 'Wellness', 'needs_attention', 62000::numeric),
  ('Urban Brew Co.', 'Food & beverage', 'healthy', 94000::numeric)
) as sample(name, industry, health, monthly_value)
where organizations.slug = 'lets-go-digitals'
and not exists (select 1 from public.clients c where c.organization_id = organizations.id and c.name = sample.name);

insert into public.leads (organization_id, company_name, contact_name, source, stage, estimated_value, probability, next_action, next_action_at)
select id, sample.company_name, sample.contact_name, sample.source, sample.stage::public.lead_stage,
       sample.estimated_value, sample.probability, sample.next_action, sample.next_action_at
from public.organizations
cross join (values
  ('Northstar Fitness', 'Maya Shah', 'Referral', 'proposal', 240000::numeric, 60::smallint, 'Follow up on proposal', now() + interval '1 day'),
  ('Pixel & Pour', 'Dev Rao', 'Website', 'qualified', 180000::numeric, 40::smallint, 'Book discovery call', now() + interval '2 days')
) as sample(company_name, contact_name, source, stage, estimated_value, probability, next_action, next_action_at)
where organizations.slug = 'lets-go-digitals'
and not exists (select 1 from public.leads l where l.organization_id = organizations.id and l.company_name = sample.company_name);

insert into public.projects (organization_id, client_id, name, status, priority, due_date)
select organizations.id, clients.id, 'Brand Launch Campaign', 'client_review', 'high', current_date + 2
from public.organizations join public.clients on clients.organization_id = organizations.id and clients.name = 'Samprati Studio'
where organizations.slug = 'lets-go-digitals'
and not exists (select 1 from public.projects p where p.organization_id = organizations.id and p.name = 'Brand Launch Campaign');

insert into public.content_items (organization_id, client_id, title, format, channel, status, scheduled_at)
select organizations.id, clients.id, sample.title, sample.format, 'Instagram', sample.status::public.content_status, current_date + sample.day_offset
from public.organizations join public.clients on clients.organization_id = organizations.id
cross join (values
  ('September Content Calendar', 'reel', 'approved', 1),
  ('Behind the scenes', 'story', 'review', 2),
  ('Product spotlight', 'static', 'draft', 4)
) as sample(title, format, status, day_offset)
where organizations.slug = 'lets-go-digitals' and clients.name = 'Samprati Studio'
and not exists (select 1 from public.content_items ci where ci.organization_id = organizations.id and ci.title = sample.title);
