# MVP implementation plan

## MVP outcome

Let’s Go Digitals can use one secure workspace to manage a lead from first contact through a client engagement, plan delivery work, coordinate content and tasks, track invoices and expenses, and see the business state on a founder dashboard. A second organization can be created without changing code, and cross-tenant access is blocked in PostgreSQL.

## Phase 0 — foundation (started)

- [x] Choose the stack and document tenant/security boundaries.
- [x] Scaffold the Next.js + TypeScript application and Supabase local project.
- [x] Build a responsive founder dashboard shell following the Figma visual language.
- [x] Add initial tenant-scoped schemas, RLS helpers, role model, and audit triggers.
- [x] Seed the Let’s Go Digitals workspace with clearly illustrative sample records.
- [x] Add Supabase SSR clients, sign-in/sign-out, and a protected workspace entry point.
- [x] Add setup notes for attaching the first authenticated founder account to the seeded tenant.
- [x] Add the authenticated founder workspace with tenant-scoped client, lead, project, task, review, and audit counts.
- [ ] Apply the migration locally and inspect Supabase policy behavior.
- [ ] Create local auth account and attach it as owner of the seeded tenant.

## Phase 1 — secure product access

- [x] Sign-in, sign-out, session refresh, and protected workspace entry.
- [x] Password reset email, callback session exchange, and authenticated password update (12-character minimum).
- [x] Workspace switcher on the founder dashboard lists only active memberships; signed-in users without a workspace can onboard through the atomic `create_organization` RPC.
- [x] Invite new members by email, accept invitations against the authenticated email, revoke pending invitations, update roles, and suspend members.
- [x] Custom role editor and assignment with workspace-write/finance permission keys.
- [x] Owner transfer flow: current owner confirms the transfer; former owner becomes an admin.
- [x] Add a migration-backed TypeScript schema snapshot for all public tables, enums, and RPCs.
- Regenerate the snapshot from local Supabase and wire typed clients/accessors after migrations are applied.
- Acceptance: unauthenticated requests cannot read tenant data; a user in tenant A cannot list or mutate tenant B data, even by changing request parameters.

## Phase 2 — core agency workflow

- [x] CRM lead list: source, stage, estimated value, owner, company search, create, and stage update (audited mutations).
- [x] Tenant-checked pipeline summary query for all active leads (not just the visible 100-row list).
- [x] Convert a won lead atomically into a client, optional primary contact, and won deal; repeat requests return the existing client.
- [x] Lead detail view with organization-timezone follow-up dates and won-deal/client links.
- CRM lead detail, deal tracking, next-action workflow, and won conversion.
- [x] Client directory, create-client-with-primary-contact, currency-aware service value, and client detail contacts/projects/invoice balance view.
- [x] Client health/notes editing, active task timeline, and contact editing.
- [x] Project delivery: tenant-scoped list/create/detail/edit, client link, scope, dates, priority, budget, linked task roll-up, permission-gated expenses, and audit history.
- [x] Task workflow: tenant-scoped board/create/assignment, project link, due date, priority, blockers, editable task details, and append-only comment activity.
- [x] Assign tasks to active same-tenant internal members; database trigger rejects cross-tenant or client assignments.
- [x] Content workflow foundation: tenant-scoped content list/create and draft/review/approved/scheduled/published state changes.
- [x] Content calendar weekly/monthly views, client association, scheduling dates, and publish-status updates.
- [x] Content item detail, client/project association, editable caption, and append-only review comments/approval/change requests.
- Acceptance: a lead can be qualified and converted once; a project/task/content record always remains in its tenant; the dashboard can explain every shown count.

## Phase 3 — finance, team, and founder dashboard

- [x] Draft invoices, issue status, immutable partial/full payment entries, and expense capture.
- [x] Derive invoice balances and payment state in PostgreSQL; reject cross-currency and over-balance payments.
- [x] Show monthly revenue received, receivables, expenses, and estimated cash profit by currency on the founder dashboard.
- [x] Receivables aging grouped by currency and overdue interval; six-month cash-flow trend for payments and expenses.
- [x] Itemized draft invoices with database-calculated subtotals and atomic invoice-plus-first-line creation.
- [x] Tenant- and finance-permission-checked invoice and line-item CSV export.
- [x] Immutable credit notes reduce outstanding balances without altering issued invoice history.
- [x] Immutable refunds linked to original payments, capped at remaining payment value, and reconciled into invoice balances and net cash reporting.
- [x] Basic team workload view from live assigned open, overdue, and completed task counts.
- [x] Team detail page with assigned work counts and a private, audited monthly performance check-in.
- [x] Replace authenticated dashboard fixture values with server-side tenant-scoped counts, monthly finance totals, receivables aging, and six-month cash-flow trends.
- [x] Add scoped reports for current sales outcomes and client health, trailing-period task timeliness, and exact assigned team workload; label snapshots and measurement limits clearly.
- Acceptance: money values use tenant currency, all aggregates respect tenant and date filters, and no metrics claim profit without expenses being included.

## Phase 4 — operational foundation

- [x] Organization-scoped audit history with action, entity, and date filters.
- [x] Private tenant file library with organization-prefixed storage paths, permission-checked upload/delete, and expiring signed links.
- [x] Tenant-scoped integration registry with credential-safe writes; connected state remains unavailable until provider OAuth is configured.
- [x] Manual task automation builder with paused-by-default rules, idempotency, per-attempt actor/result records, retry limits, and pause controls.
- [x] Hourly, daily, and weekly task schedules with a service-role-only Postgres worker, bounded batches, idempotent runs, and a bearer-secret-protected endpoint.
- [x] New-lead event trigger queues one idempotent task run per enabled rule, with optional company-name task title tokens.
- [x] Slack OAuth callback with signed state, server-side AES-GCM encrypted credentials, and refresh-token rotation support.
- [x] Send a Slack message from the connected workspace to a channel where the bot is a member.
- External event/webhook integrations and general-purpose background jobs.
- Acceptance: each integration/automation execution has a tenant, actor/source, result, and retry state.

## Phase 5 — AI and hardening

- [x] Read-only AI Command Center with a server-only OpenAI Responses adapter, tenant-scoped context, member-owned conversation history, token usage, and per-member rate limiting.
- [x] AI-generated task draft with editable fields, short expiry, explicit confirmation, permission-checked atomic task creation, and audit logging; AI cannot create records directly.
- [x] Optional per-response AI cost estimate from operator-configured input/output token prices for the selected model.
- [x] Organization owner/admin monthly USD cap with service-role-only serialized reservations, token-use settlement, permission-gated configuration, and audit trail.
- Automatic price catalog updates and invoice-grade provider reconciliation remain future work; maintain the configured model rates manually.
- Error monitoring, rate limiting beyond AI request claims, export/delete, backups, accessibility review, and tenant isolation review.
- Acceptance: AI cannot retrieve cross-tenant records; tool writes require explicit user confirmation and are auditable.

## MVP release gates

1. Apply schema and run database policy checks in local Supabase.
2. Verify two-tenant read/write isolation and role matrix.
3. Exercise invite, lead conversion, project/task/content flow, invoice/expense flow, and dashboard aggregate consistency.
4. Configure production secrets and backups; deploy behind an invite-only pilot for Let’s Go Digitals.
5. Capture operational feedback, then prioritize the next slice from real use.

## Immediate next implementation slice

Apply migrations 001-024 and provision the founder account as owner of `lets-go-digitals`, then verify the tenant and role policies. Regenerate database types from local Supabase. Configure Supabase Auth email delivery and allow `/auth/callback` on the deployed site before exercising invitations and password resets. Configure the Slack app and server-only credentials before connecting it; configure `OPENAI_API_KEY` and `OPENAI_MODEL` before using the AI Command Center. Set current model token prices before enabling an organization AI budget. Set `AUTOMATION_WORKER_SECRET` and schedule `POST /api/automation/worker` at least every 15 minutes to process schedules and queued lead events.
