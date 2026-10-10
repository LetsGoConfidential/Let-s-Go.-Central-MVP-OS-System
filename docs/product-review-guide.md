# Product review guide — Let’s Go Central

## Open the visual review

Open [`central-ui-ux-concept.html`](../outputs/central-ui-ux-concept.html) in a browser. Use the left navigation to move across the proposed screens. Open **Build status** to see what has been implemented, what is sample UI, and what still needs setup or development.

The screens are **visual examples with illustrative data**. They help review information hierarchy, navigation, and workflow language. They are not connected to Supabase and are not screenshots of the current protected app routes.

## What is implemented in the application code

| Module | Current route | Implemented behavior | Not complete / needs setup |
|---|---|---|---|
| Authentication & workspace | `/login`, `/auth/reset-password`, `/workspace` | Sign-in, sign-out, password reset, protected routes, atomic organization onboarding, membership-only workspace switcher, and founder dashboard queries. | Local Supabase, migrations, Let’s Go Digitals founder membership, and configured Supabase Auth email delivery/redirect allowlist. |
| Sales & CRM | `/workspace/sales`, `/workspace/sales/<lead-id>` | Search, pipeline stage and value, lead details, timezone-aware next action, audit mutation, won conversion. | More complete deal management UX. |
| Clients | `/workspace/clients`, `/workspace/clients/<client-id>` | Directory, create client with primary contact, account health/notes, contact create/edit, client task timeline, projects and invoice balance. | Richer project/client collaboration. |
| Projects | `/workspace/projects`, `/workspace/projects/<project-id>` | Tenant-scoped list and detail, editable project brief/client/status/priority/dates/budget, linked delivery tasks, finance-permission-gated expense totals, and recent audited project history. | Project collaboration beyond linked task activity; local RLS verification. |
| Tasks | `/workspace/tasks`, `/workspace/tasks/<task-id>` | Tenant-scoped board, project/client context, same-tenant assignment, detail editing, due dates, priority, blockers, append-only comments and audited activity. | Migration 021 must be applied; local policy/isolation verification remains. |
| Content | `/workspace/content`, `/workspace/content/<item-id>` | Create, client/project link, week/month calendar, schedule date, caption, review history, comment/approve/request-changes workflow. | Live database migration must be applied; formal client-facing approvals are not included. |
| Finance | `/workspace/finance` | Invoices and lines, payments, credit notes, refunds, expenses, aging, cash trend, CSV export. | Local policy/financial workflow verification. |
| Reports | `/workspace/reports` | Exact tenant-scoped sales stage counts, current client health snapshot, trailing-period on-time task rate, and assigned open/blocked/overdue task workload. | Migration 022 and local policy/isolation verification; no historical client retention or hours-based utilization until lifecycle dates and time/capacity tracking exist. |
| Team & access | `/workspace/team`, `/workspace/team/<member-id>`, `/workspace/team/roles` | Member detail, assigned-task history and exact workload counts, private audited monthly performance reviews, member access, custom permissions, owner transfer, invites. | Invitation email delivery, password reset email delivery, and complete onboarding require Auth configuration. |
| Automations | `/workspace/automations` | Paused task rules, schedules, idempotent run records, retries, lead-created task events. | Worker secret and external scheduler configuration. |
| Integrations | `/workspace/integrations` | Tenant-scoped integration registry, Slack OAuth/token vault, send message action. | Provider credentials; generic webhooks and general background jobs. |
| AI | `/workspace/ai` | Read-only tenant context and member-owned history plus editable task proposals that require explicit confirmation; confirmed writes use an atomic permission-checked RPC and audit events. Optional per-response estimates appear when operator-configured token prices are set. | OpenAI configuration; organization-level budget controls. Migration 023 must be applied. |
| Files | `/workspace/files` | Private tenant library, permission checks, signed links, upload/delete actions. | Storage setup and live-environment verification. |
| Audit | `/workspace/audit` | Organization-scoped activity with action/entity/date filters. | Tenant isolation and production behavior still need verification. |

The code is present for the “implemented” behaviors above, but the local database migrations and security acceptance checks have not been completed in this environment. New team performance reviews are restricted by `team.performance.manage`; manager notes are excluded from the tenant-wide audit feed. Treat **implemented in code** and **verified for production** as separate states.

## To review real application routes

1. Follow the local setup in [the walkthrough](./product-walkthrough.md) and sign in as a member of Let’s Go Digitals.
2. Open `/workspace` and select the organization from the membership switcher if more than one is available.
3. Use the live workspace sidebar, or append `?organization=<organization-id>` to module URLs.
4. Review the **coded route** for actual page behavior. Use the HTML concept to compare a proposed visual direction, not as evidence that a feature is live.

Current local checkout has no `.env.local` or installed `node_modules`; a live authenticated preview needs those setup steps first.

## Review notes template

For each change you want, capture:

- **Screen / location:**
- **What you see now:**
- **What you expected:**
- **Why it matters to the user:**
- **Priority:** must-have / should-have / later

Review the visual concept first, then compare the corresponding coded route. That will help separate a design change from a missing product behavior and fix both together.
