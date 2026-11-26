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
- [x] Add repeatable pgTAP checks for cross-tenant reads/writes and member write restrictions, plus a GitHub Actions database verification job.
- [x] GitHub Actions applied all 32 migrations and seed fixtures, then passed 120 pgTAP checks for tenant isolation, owner/member/manager permissions, membership and role boundaries, private HR reviews and AI conversation/message/draft access, task-comment write/read permissions, content-review visibility, private file metadata and storage objects, integration and automation histories, credential-vault access denial, won-lead conversion, finance ledger rules, CRM record boundaries, tenant-safe project/task/content reads, links, and assignments, KPI goals, department assignment, leave authorization, attendance self-service, HR visibility, and cross-tenant attendance denial (run #65, commit `b424f78`).

## Phase 1 — secure product access

- [x] Sign-in, sign-out, session refresh, and protected workspace entry.
- [x] Password reset email, callback session exchange, and authenticated password update (12-character minimum).
- [x] Workspace switcher on the founder dashboard lists only active memberships; signed-in users without a workspace can onboard through the atomic `create_organization` RPC.
- [x] Invite new members by email, accept invitations against the authenticated email, revoke pending invitations, update roles, and suspend members.
- [x] HR-granted `hr.people.invite` can invite regular members; manager/admin invitations remain restricted to owner/admin.
- [x] Custom role editor and assignment with separate workspace, finance, KPI, HR, invitations, and assigned-task permissions.
- [x] Owner transfer flow: current owner confirms the transfer; former owner becomes an admin.
- [x] Owner/admin workspace settings for organization name, legal name, IANA timezone, and default currency with audited updates.
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
- [x] Assigned-task employee role can view only their own assigned tasks, update status, and add progress notes; database functions and row policies reject coworker and cross-tenant access.
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
- [x] Employee KPI goal table and scorecard for completed tasks, on-time delivery, and owned won leads; employee self-read, manager edit, tenant isolation, audit logging, and organization-timezone periods are implemented.
- [x] Tenant-scoped department assignment for employee records is implemented and shown in team workload and member detail. Department-filtered KPI targets and custom metrics remain in the [People operations and connected-workspace roadmap](people-operations-roadmap.md).
- [x] Replace authenticated dashboard fixture values with server-side tenant-scoped counts, monthly finance totals, receivables aging, and six-month cash-flow trends.
- [x] Add scoped reports for current sales outcomes and client health, trailing-period task timeliness, and exact assigned team workload; label snapshots and measurement limits clearly.
- Acceptance: money values use tenant currency, all aggregates respect tenant and date filters, and no metrics claim profit without expenses being included.

## Phase 4 — operational foundation

- [x] Organization-scoped audit history with action, entity, and date filters.
- [x] Private tenant file library with organization-prefixed storage paths, permission-checked upload/delete, and expiring signed links.
- [x] Tenant-scoped integration registry with credential-safe writes; connected state remains unavailable until provider OAuth is configured.
- [x] Manual task automation builder with paused-by-default rules, idempotency, per-attempt actor/result records, retry limits, and pause controls.
- [x] Hourly, daily, and weekly task schedules with a service-role-only Postgres worker, bounded batches, idempotent runs, bounded retry attempts, and a bearer-secret-protected endpoint.
- [x] New-lead event trigger queues one idempotent task run per enabled rule, with optional company-name task title tokens.
- [x] Slack OAuth callback with signed state, server-side AES-GCM encrypted credentials, and refresh-token rotation support.
- [x] Send a Slack message from the connected workspace to a channel where the bot is a member.
- External event/webhook integrations and general-purpose background jobs.
- [ ] Email, WhatsApp Business, and CRM connectors using provider adapters, consent, OAuth/API scopes, webhook validation, idempotency, and retries; avoid claiming universal software connectivity.
- [ ] Role-aware founder/admin/HR/sales/manager/employee home views within one account and shared navigation shell.
- [x] Employee leave requests and role-gated approval queue with custom `hr.leave.manage` grants and privacy-conscious audit payloads.
- [x] Employee daily check-in/check-out with organization-local work dates, self-only history, separately permissioned HR team visibility, and audited changes.
- [ ] Leave balances, attendance corrections, compensation approvals, and payroll remain separate, permissioned HR workflows.
- Acceptance: each integration/automation execution has a tenant, actor/source, result, and retry state.

## Phase 5 — AI and hardening

- [x] Read-only AI Command Center with a server-only OpenAI Responses adapter, tenant-scoped context, member-owned conversation history, token usage, and per-member rate limiting.
- [x] AI-generated task draft with editable fields, short expiry, explicit confirmation, permission-checked atomic task creation, and audit logging; AI cannot create records directly.
- [x] Optional per-response AI cost estimate from operator-configured input/output token prices for the selected model.
- [x] Organization owner/admin monthly USD cap with service-role-only serialized reservations, token-use settlement, permission-gated configuration, and audit trail.
- Automatic price catalog updates and invoice-grade provider reconciliation remain future work; maintain the configured model rates manually.
- [x] Organization-manager JSON export with RLS-scoped data, a recorded audit event, explicit sensitive-data exclusions, and bounded download size.
- Error monitoring, rate limiting beyond AI request claims, tenant deletion, backups, a complete accessibility review, and tenant isolation review.
- [x] Add global keyboard-focus visibility, a skip-to-main-content link, and reduced-motion support as accessibility foundations; a complete WCAG review remains a release gate.
- Acceptance: AI cannot retrieve cross-tenant records; tool writes require explicit user confirmation and are auditable.

## MVP release gates

1. GitHub Actions migration, seed, and pgTAP pass is green on run #65; local and target-project schema application plus deployed-policy review remain pending.
2. CI verifies two-tenant visibility/write boundaries and owner/member/manager checks across major operational areas, including HR and attendance; extend the role matrix across every tenant table before production rollout.
3. Exercise invitation, lead conversion, project/task/content flow, invoice/expense flow, and dashboard aggregate consistency in the configured app. CI does not replace a configured browser workflow review.
4. Configure production secrets and backups; deploy behind an invite-only pilot for Let’s Go Digitals.
5. Capture operational feedback, then prioritize the next slice from real use.

## Immediate next implementation slice

The CI runner applies all 32 migrations and passes 120 pgTAP assertions. Latest verified run: [#65](https://github.com/LetsGoConfidential/Let-s-Go.-Central-MVP-OS-System/actions/runs/45810507973), commit `b424f78`. This includes tenant isolation, finance ledger rules, CRM conversion, membership/role boundaries, KPI and department access, leave and attendance permissions, and cross-tenant attendance denial. Local and deployed environments remain unverified: this checkout has no `.env.local`, Supabase CLI, or Docker, and `pnpm preflight` reports those as blockers. Once available, configure Supabase, run `pnpm preflight`, apply migrations, provision the founder account as owner of `lets-go-digitals`, regenerate database types, and exercise the browser workflows. Configure Supabase Auth email delivery and allow `/auth/callback` on the deployed site before exercising invitations and password resets. Configure the Slack app and server-only credentials before connecting it; configure `OPENAI_API_KEY` and `OPENAI_MODEL` before using the AI Command Center. Set current model token prices before enabling an organization AI budget. Set `AUTOMATION_WORKER_SECRET` and schedule `POST /api/automation/worker` at least every 15 minutes to process schedules and queued lead events.
