# Let’s Go Central product workspace plan

## Access model

- One sign-in and one organization workspace shell; the user's work email is the login ID.
- No open registration. An owner or authorized organization administrator invites the email and assigns base access/department; an explicitly authorized HR/custom role may invite regular members only. The invitee sets a password through the verified invitation link.
- A role changes which screens and actions are available, but server authorization and database RLS remain the security boundary.
- Owner/founder: company overview, organization controls, finance and all team dashboards.
- Admin: organization membership and settings plus explicitly granted operational access.
- HR: employee profile, attendance, leave, HR documents, compensation approvals and payroll only through separately granted keys. Salary/bank details are private and never copied into audit logs.
- Sales: lead and deal pipeline, assigned accounts, quotations, proposals and follow-ups.
- Manager: assigned department workload, task blockers, delivery and team KPI review; no implicit payroll or private HR access.
- Production: task queue and project/content assignments, with editor and graphics designer subteams.
- Concept: brief, idea, strategy and approval work queues, separated from production where useful.
- Employee: own daily tasks, KPI goals, leave and attendance, with no access to another employee's private HR data.

## Department directory

Use configurable department names, initially Sales, HR, Management, Production (Editing, Graphics Design), Concept/Strategy, and Operations/Finance. A member may have a primary department and optional workgroups; permissions are independent of department labels.

## Product areas

1. Founder Overview: company and department KPIs, pipeline, delivery risk, finance and recent audit activity.
2. Sales & CRM: lead source, owner, stage, value, probability, next action/date, contact, account, loss reason, conversion and follow-up automation.
3. Invoices & Billing: quotations/estimates, proforma invoices, tax invoices, receipts, sales orders, delivery challans, credit notes, five reusable templates, recurring draft policy and reports. See `invoice-billing-spec.md`.
4. Attendance & Payroll: shifts and schedules, check-in/out, hours, corrections, leave/balances, payslips and compensation approvals. Attendance, leave requests/approval, annual balances, correction requests/approval, and effective-dated salary/allowance/bonus target history are implemented in code. Payroll runs, payslips, bank disbursement, and statutory calculations remain planned.
5. HR: employee directory, invitation/onboarding, department, role, contract and private employee documents; compensation, bonus, increment and approval records; private audit trail. Most HR file/pay features remain planned.
6. Team & KPI Reports: daily task updates, department/member scorecards, goal/actual/trend, workload, review notes with privacy boundaries, team and client reports.
7. Documents & Reports: company files, invoices, reviewed client reports, department reports, proposals, contracts and payroll documents.
8. Automations & Integrations: permission-checked task/CRM actions and provider adapters. External messages remain human-approved until provider setup and consent policy exist.

## Current implementation baseline

Existing: invitation-backed membership, email/password sign-in and recovery, verified invitation password setup, base owner/admin/manager/member roles, custom permissions including controlled HR invitations and payroll access, invite-time department assignment, role/department-aware dashboard heading, finance permission-gated overview, task-based workload, KPI goals for task completion/on-time delivery/won leads, private reviews, leave request/review/balances, attendance check-in/out/corrections, employee-private compensation history, invoices/payments/credits/refunds, private tenant files, reports, audit, task automations, integration registry and Slack foundation.

Next: department-specific navigation and content filtering, invite-time custom role assignment, department-filtered KPI reports; quotation lifecycle and invoice templates; shift schedules and work-hour corrections; holiday calendars and balance-aware leave approval; HR records and sensitive document access; compensation approval records and payslips; draft-to-approved payroll runs and restricted export; provider-backed email/WhatsApp and CRM connectors.

This is a multi-sprint plan, not a promise that a compliant payroll and integrations platform is production-ready in four days. Each feature ships with permissions, tenant isolation checks, browser walkthrough, and an explicit live-environment gate.
