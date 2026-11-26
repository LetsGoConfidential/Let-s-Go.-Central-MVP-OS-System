# People operations and connected-workspace roadmap

## Product decision

Keep one account and one workspace shell. Give founders, admins, HR, sales, managers, and employees role-aware home pages and navigation inside that shell. A person with more than one role gets the union of the permissions they have; every page and server action checks the permission on the server and every tenant-owned record stays protected by database RLS. Hiding a menu item is never the access control.

## KPI and performance

Build employee work tracking from task and CRM events, with configurable department scorecards and date periods. Each KPI needs a plain-language definition, source, numerator/denominator where applicable, target, actual, trend, and last-updated time. Start with task completion, on-time delivery, overdue workload, and sales outcomes; allow an organization manager to define additional goals. Show an employee their own assigned work and goals. Keep manager-only feedback private and auditable. Do not turn a score into an automatic employment decision.

Compensation changes, increments, and bonuses need a separate restricted approval record with proposal, reason, effective date, approver, and immutable audit history. A KPI can inform a human review but cannot trigger a pay change by itself. Track leave requests and approvals, attendance events and corrections, and payroll runs as separate HR records with narrow permissions and access logs. Employees see only their own personal HR records; managers see only records required for their team; HR and payroll access stays separately grantable. Payroll exports must be permission-gated and generated only for an authorized payroll operator.

## Sequence

1. **KPI foundations:** initial manager goals and task/CRM scorecards are implemented. Department assignment is now available on team records and visible beside workload and KPI detail. Department-filtered scorecards and organization-configured metrics remain next.
2. **HR basics:** employee leave request and approval workflow with a role-gated HR queue is implemented. Daily check-in/check-out attendance is available with organization-local work dates, self-only employee views, separately granted HR team visibility, and audit events. Annual leave allocations with employee self-view and HR management are verified in CI run #70. Attendance correction requests and HR approval are verified with the newer RLS suite in CI run #76. Holiday calendars and balance-aware leave approval rules remain next.
3. **Compensation controls:** effective-dated salary history, monthly allowances, and bonus targets are implemented with an independent `hr.payroll.manage` permission. Employees can read only their own records; payroll-authorized roles can update the team's records. Audit entries record the employee and effective date without copying pay amounts. Migration and RLS checks passed in CI run #76. Approval proposals, realized bonus payments, and payslips remain next.
4. **Payroll readiness:** a first manual monthly workflow is implemented: snapshot compensation effective on period start, edit bonus/additions/deductions in draft, approve, record external payment completion, and show employees a private printable statement. Migration and isolation checks passed in CI run #79. Next: configurable proration/pay rules, payroll export, verified payout-provider integration, and statutory/local compliance review. The current “paid” transition is bookkeeping only and does not transfer money.
5. **Rollout checks:** test every HR table against two tenants and owner, HR, manager, and employee roles; verify the workflow in a configured target environment before launch.

## Integrations foundation

Use provider adapters behind the existing tenant-scoped integration registry. Each connector needs OAuth or securely stored API credentials, minimum scopes, webhook signature validation, idempotency, rate-limit handling, bounded retries, sync cursors, error visibility, disconnect/revocation, and audit events. Never put provider secrets in browser code or general workspace exports.

Prioritize email notifications, Slack, WhatsApp Business Platform, and CRM import/export after the KPI and leave slices. Email requires a configured sender and verified domain. WhatsApp automation requires an approved business API provider, templates where required by the provider, and recipient consent. CRM connectors should be added one provider at a time from a documented object/property mapping; “connect to any software” is not a safe or testable promise. AI may summarize and draft updates, but a person confirms external messages and changes before sending.

## Release status

Current code has task-based team workload, private monthly performance reviews, KPI goals for completed tasks/on-time delivery/owned won leads, tenant-scoped employee department assignments, employee leave requests with a role-gated approval queue, annual leave allocation and weekday usage display (verified in CI run #70), daily attendance check-in/check-out, employee attendance correction requests with HR approval, effective-dated compensation history with payroll-scoped access, monthly draft-to-approved runs and private printable statements (migrations 035–037; 186 pgTAP assertions passed in CI run #79), an assigned-task employee role with self-only task/status/progress-note permissions, a tenant-scoped integration registry, Slack OAuth/send foundations, and task automation. Department scorecard filtering, holiday calendars, balance-aware approvals, statutory payroll rules, payout integration, WhatsApp, and general-purpose CRM connectors remain unimplemented. CI verification does not replace validation in the configured customer environment.
