# People operations and connected-workspace roadmap

## Product decision

Keep one account and one workspace shell. Give founders, admins, HR, sales, managers, and employees role-aware home pages and navigation inside that shell. A person with more than one role gets the union of the permissions they have; every page and server action checks the permission on the server and every tenant-owned record stays protected by database RLS. Hiding a menu item is never the access control.

## KPI and performance

Build employee work tracking from task and CRM events, with configurable department scorecards and date periods. Each KPI needs a plain-language definition, source, numerator/denominator where applicable, target, actual, trend, and last-updated time. Start with task completion, on-time delivery, overdue workload, and sales outcomes; allow an organization manager to define additional goals. Show an employee their own assigned work and goals. Keep manager-only feedback private and auditable. Do not turn a score into an automatic employment decision.

Compensation changes, increments, and bonuses need a separate restricted approval record with proposal, reason, effective date, approver, and immutable audit history. A KPI can inform a human review but cannot trigger a pay change by itself. Track leave requests and approvals, attendance events and corrections, and payroll runs as separate HR records with narrow permissions and access logs. Employees see only their own personal HR records; managers see only records required for their team; HR and payroll access stays separately grantable. Payroll exports must be permission-gated and generated only for an authorized payroll operator.

## Sequence

1. **KPI foundations:** initial manager goals and task/CRM scorecards are implemented. Next add departments, role-aware home navigation, and organization-configured metrics before compensation or payroll.
2. **HR basics:** configurable leave types, balances, requests, approvals, and auditable attendance events/corrections. Add employee self-service and manager/HR queues.
3. **Compensation controls:** proposed increments/bonuses, approval states, effective dates, and access restrictions; keep a full audit trail.
4. **Payroll readiness:** employee pay profiles and payroll periods, a draft-to-approved calculation workflow, and restricted export. Start with explicit organization-configured pay rules; do not claim statutory payroll compliance until local rules and a payroll provider are configured and reviewed.
5. **Rollout checks:** test every HR table against two tenants and owner, HR, manager, and employee roles; verify the workflow in a configured target environment before launch.

## Integrations foundation

Use provider adapters behind the existing tenant-scoped integration registry. Each connector needs OAuth or securely stored API credentials, minimum scopes, webhook signature validation, idempotency, rate-limit handling, bounded retries, sync cursors, error visibility, disconnect/revocation, and audit events. Never put provider secrets in browser code or general workspace exports.

Prioritize email notifications, Slack, WhatsApp Business Platform, and CRM import/export after the KPI and leave slices. Email requires a configured sender and verified domain. WhatsApp automation requires an approved business API provider, templates where required by the provider, and recipient consent. CRM connectors should be added one provider at a time from a documented object/property mapping; “connect to any software” is not a safe or testable promise. AI may summarize and draft updates, but a person confirms external messages and changes before sending.

## Release status

Current code has task-based team workload, private monthly performance reviews, KPI goals for completed tasks/on-time delivery/owned won leads, a tenant-scoped integration registry, Slack OAuth/send foundations, and task automation. Departments, leave, attendance, compensation, payroll, WhatsApp, and general-purpose CRM connectors remain unimplemented. These are planned implementation slices, not completed or target-environment verified features.
