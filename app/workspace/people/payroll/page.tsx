import { redirect } from "next/navigation";
import { BadgeIndianRupee, CalendarDays, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { createPayrollRun, saveCompensation, transitionPayrollRun, updatePayrollEntry } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string; currency: string; timezone: string } | { name: string; currency: string; timezone: string }[] | null };
type Compensation = { id: string; member_id: string; effective_from: string; effective_to: string | null; monthly_base: number; monthly_allowance: number; monthly_bonus_target: number; currency: string; change_reason: string; created_at: string };
type PayrollRun = { id: string; organization_id: string; period_start: string; period_end: string; status: "draft" | "approved" | "paid"; created_at: string };
type PayrollEntry = { id: string; organization_id: string; payroll_run_id: string; member_id: string; currency: string; base_salary: number; monthly_allowance: number; bonus_paid: number; other_additions: number; deductions: number; net_pay: number; adjustment_note: string };
const orgName = (row: Membership) => (Array.isArray(row.organizations) ? row.organizations[0] : row.organizations)?.name ?? "Agency workspace";
const orgCurrency = (row: Membership) => (Array.isArray(row.organizations) ? row.organizations[0] : row.organizations)?.currency ?? "INR";
const orgTimezone = (row: Membership) => (Array.isArray(row.organizations) ? row.organizations[0] : row.organizations)?.timezone ?? "UTC";
const dateLabel = (value: string) => new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`));
const money = (value: number, currency: string) => {
  try { return new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 2 }).format(value); }
  catch { return `${currency} ${value.toLocaleString("en-IN")}`; }
};

const messages: Record<string, string> = {
  saved: "Compensation history saved and audit logged.",
  invalid: "Check the employee, effective date, amounts, currency, and reason.",
  forbidden: "Your role cannot manage employee compensation.",
  "save-failed": "This compensation change could not be saved. The effective date must come after the current record.",
  "run-created": "Draft payroll run created from compensation effective on the first day of the selected month.",
  duplicate: "A payroll run already exists for that month.",
  "invalid-period": "Choose a valid payroll month.",
  "run-failed": "The payroll run could not be created. Ensure compensation records exist for the selected month.",
  "invalid-adjustment": "Check the bonus, additions, deductions, and adjustment note.",
  "adjustment-saved": "Draft payroll adjustment saved and audited.",
  "adjustment-failed": "The adjustment could not be saved. Check that deductions do not exceed gross pay and the run is still draft.",
  approved: "Payroll run approved. Employee pay statements are now available.",
  paid: "Payroll run marked paid. The system records this status but does not move money.",
  "invalid-transition": "This payroll status change is not valid.",
  "transition-failed": "Payroll status could not be changed. Check the run is in the required state.",
};

export default async function PayrollPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined> & { organization?: string; run?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rows } = await supabase.from("org_members").select("organization_id,role,organizations(name,currency,timezone)").eq("user_id", user.id).eq("status", "active");
  const memberships = (rows ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const orgId = membership.organization_id;
  const [{ data: canManage }, { data: rawCompensation }, { data: memberRows }, { data: rawRuns }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: orgId, permission_key: "hr.payroll.manage" }),
    supabase.from("employee_compensation").select("id,member_id,effective_from,effective_to,monthly_base,monthly_allowance,monthly_bonus_target,currency,change_reason,created_at").eq("organization_id", orgId).order("effective_from", { ascending: false }),
    supabase.from("org_members").select("user_id,department,role").eq("organization_id", orgId).eq("status", "active").neq("role", "client").order("created_at"),
    supabase.from("payroll_runs").select("id,organization_id,period_start,period_end,status,created_at").eq("organization_id", orgId).order("period_start", { ascending: false }).limit(24),
  ]);
  const compensation = (rawCompensation ?? []) as Compensation[];
  const members = memberRows ?? [];
  const runs = (rawRuns ?? []) as PayrollRun[];
  const visibleRuns = canManage ? runs : runs.filter((run) => run.status !== "draft");
  const selectedRun = visibleRuns.find((run) => run.id === params.run) ?? visibleRuns[0];
  const { data: rawEntries } = selectedRun
    ? await supabase.from("payroll_entries").select("id,organization_id,payroll_run_id,member_id,currency,base_salary,monthly_allowance,bonus_paid,other_additions,deductions,net_pay,adjustment_note").eq("organization_id", orgId).eq("payroll_run_id", selectedRun.id).order("member_id")
    : { data: [] };
  const entries = (rawEntries ?? []) as PayrollEntry[];
  const ids = [...new Set([...compensation.map((row) => row.member_id), ...entries.map((row) => row.member_id), ...(canManage ? members.map((row) => row.user_id) : [user.id])])];
  const { data: profileRows } = ids.length ? await supabase.from("profiles").select("id,full_name").in("id", ids) : { data: [] };
  const names = new Map((profileRows ?? []).map((row) => [row.id, row.full_name]));
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: orgTimezone(membership), year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const currentRows = compensation.filter((row) => row.effective_to === null && row.effective_from <= today);
  const current = compensation.find((row) => row.member_id === user.id && row.effective_to === null && row.effective_from <= today);
  const message = Object.entries(messages).find(([key]) => params[key])?.[1];
  const success = ["saved", "run-created", "adjustment-saved", "approved", "paid"].some((key) => params[key]);
  const currency = orgCurrency(membership);
  const defaultPayrollMonth = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)), 1)).toISOString().slice(0, 7);
  const periodLabel = (value: string) => new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`));

  return <main className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a>
      <div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div>
      <div className="nav-caption">WORKSPACE</div>
      <nav aria-label="Main navigation">
        <a className="nav-link" href={`/workspace?organization=${orgId}`}>Overview</a>
        <a className="nav-link" href={`/workspace/tasks?organization=${orgId}`}>My tasks</a>
        <a className="nav-link" href={`/workspace/team?organization=${orgId}`}>Team & KPIs</a>
        <a className="nav-link active" href={`/workspace/people?organization=${orgId}`}>Attendance & Payroll</a>
        <a className="nav-link" href={`/workspace/attendance?organization=${orgId}`}>Attendance</a>
        <a className="nav-link" href={`/workspace/leave?organization=${orgId}`}>Leave & time off</a>
        <a className="nav-link active" href={`/workspace/people/payroll?organization=${orgId}`}>Payroll & compensation</a>
      </nav>
      <div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div>
    </aside>
    <section className="main-area">
      <header className="topbar"><div className="breadcrumbs"><a href={`/workspace/people?organization=${orgId}`}>Attendance & Payroll</a><span className="slash">/</span><b>Payroll & compensation</b><span className="live-label">{canManage ? "HR and founder" : "Employee self-service"}</span></div><span className="signed-in-as">{user.email}</span></header>
      <div id="main-content" tabIndex={-1} className="content-wrap">
        <section className="welcome-row"><div><div className="eyebrow">PRIVATE PEOPLE DATA</div><h1>Payroll & compensation</h1><p>{canManage ? "Manage employee pay changes with effective dates and a clear history." : "View your own compensation history and effective dates."}</p></div><BadgeIndianRupee size={21}/></section>
        {message && <div className={success ? "success-banner" : "auth-error"} role="status">{message}</div>}
        {current && <section className="metrics-grid" aria-label="My current compensation"><article className="metric card"><div className="metric-top"><span>Monthly base</span><span className="metric-icon"><BadgeIndianRupee size={17}/></span></div><div className="metric-value">{money(current.monthly_base, current.currency)}</div><div className="live-metric-detail">Effective {dateLabel(current.effective_from)}</div></article><article className="metric card"><div className="metric-top"><span>Monthly allowance</span></div><div className="metric-value">{money(current.monthly_allowance, current.currency)}</div><div className="live-metric-detail">Current compensation record</div></article><article className="metric card"><div className="metric-top"><span>Monthly bonus target</span></div><div className="metric-value">{money(current.monthly_bonus_target, current.currency)}</div><div className="live-metric-detail">Target only; actual bonus is human-approved</div></article><article className="metric card"><div className="metric-top"><span>Payroll record privacy</span><span className="metric-icon"><ShieldCheck size={17}/></span></div><div className="metric-value">Restricted</div><div className="live-metric-detail">Only you and payroll-authorized roles can view this</div></article></section>}
        {canManage && <section className="card new-lead-card"><div className="leads-heading"><div><h2>Record a salary or bonus change</h2><p>Add an effective-dated record. The system closes the previous active record the day before this one begins.</p></div></div><form action={saveCompensation} className="lead-form"><input type="hidden" name="organization_id" value={orgId}/><label>Employee<select name="member_id" required defaultValue=""><option value="" disabled>Select an active employee</option>{members.map((member) => <option key={member.user_id} value={member.user_id}>{names.get(member.user_id) ?? "Team member"}{member.department ? ` · ${member.department}` : ""}</option>)}</select></label><label>Effective from<input name="effective_from" type="date" required/></label><label>Monthly base salary<input name="monthly_base" type="number" min="0" step="0.01" required placeholder="0.00"/></label><label>Monthly allowance<input name="monthly_allowance" type="number" min="0" step="0.01" defaultValue="0"/></label><label>Monthly bonus target<input name="monthly_bonus_target" type="number" min="0" step="0.01" defaultValue="0"/></label><label>Currency<input name="currency" defaultValue={currency} maxLength={3} pattern="[A-Za-z]{3}" required/></label><label>Change reason<input name="change_reason" required minLength={3} maxLength={500} placeholder="Annual increment, role change, bonus adjustment"/></label><p className="data-note role-note">This records agreed compensation terms only. It does not calculate taxes or create a payment instruction.</p><button className="primary-button" type="submit">Save compensation change</button></form></section>}
        <section className="card leads-card"><div className="leads-heading"><div><h2>{canManage ? "Team compensation history" : "My compensation history"}</h2><p>{canManage ? `${currentRows.length} active compensation records · amounts are only visible to payroll-authorized roles and each employee.` : "Your changes are listed newest first."}</p></div></div>{compensation.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canManage && <th>Employee</th>}<th>Effective period</th><th>Monthly base</th><th>Allowance</th><th>Bonus target</th><th>Change reason</th><th>Status</th></tr></thead><tbody>{compensation.map((row) => { const scheduled = !row.effective_to && row.effective_from > today; const status = row.effective_to ? "Historical" : scheduled ? "Scheduled" : "Current"; return <tr key={row.id}>{canManage && <td><b>{names.get(row.member_id) ?? "Team member"}</b></td>}<td>{dateLabel(row.effective_from)} – {row.effective_to ? dateLabel(row.effective_to) : "Open"}</td><td>{money(row.monthly_base, row.currency)}</td><td>{money(row.monthly_allowance, row.currency)}</td><td>{money(row.monthly_bonus_target, row.currency)}</td><td>{row.change_reason}</td><td><span className={`stage-pill ${status === "Current" ? "stage-completed" : "stage-review"}`}>{status}</span></td></tr>; })}</tbody></table></div> : <div className="empty-state">{canManage ? "No compensation records yet. Add the first approved salary record above." : "No compensation record has been shared with your account yet."}</div>}</section>
        {canManage && <section className="card new-lead-card"><div className="leads-heading"><div><h2>Create a monthly payroll draft</h2><p>The run snapshots active compensation effective on the month’s first day. Review all amounts before approving.</p></div><CalendarDays size={19}/></div><form action={createPayrollRun} className="lead-form"><input type="hidden" name="organization_id" value={orgId}/><label>Payroll month<input type="month" name="period" defaultValue={defaultPayrollMonth} required/></label><button className="primary-button" type="submit">Create draft run</button></form><p className="data-note role-note">This records payroll calculations for human review. It does not calculate tax, create statutory filings, or initiate a bank transfer.</p></section>}
        <section className="card leads-card"><div className="leads-heading"><div><h2>{canManage ? "Payroll runs" : "My salary statements"}</h2><p>{canManage ? "Drafts are private to payroll-authorized roles. Approved runs publish employee statements." : "Only approved or paid statements are shown here."}</p></div></div>{visibleRuns.length ? <div className="table-scroll"><table className="lead-table"><thead><tr><th>Month</th><th>Status</th>{canManage && <th>Created</th>}<th></th></tr></thead><tbody>{visibleRuns.map((run) => <tr key={run.id}><td><a href={`/workspace/people/payroll?organization=${orgId}&run=${run.id}`}><b>{periodLabel(run.period_start)}</b></a></td><td><span className={`stage-pill ${run.status === "paid" ? "stage-completed" : run.status === "approved" ? "stage-review" : "stage-review"}`}>{run.status}</span></td>{canManage && <td>{dateLabel(run.created_at.slice(0, 10))}</td>}<td>{selectedRun?.id === run.id ? "Selected" : <a href={`/workspace/people/payroll?organization=${orgId}&run=${run.id}`}>Open →</a>}</td></tr>)}</tbody></table></div> : <div className="empty-state">{canManage ? "No payroll runs yet. Create a draft after entering employee compensation." : "No approved pay statements are available yet."}</div>}</section>
        {selectedRun && <section className="card leads-card"><div className="leads-heading"><div><h2>{periodLabel(selectedRun.period_start)} payroll · {selectedRun.status}</h2><p>{canManage ? `${entries.length} employee record${entries.length === 1 ? "" : "s"} in this tenant-scoped run.` : "Your private payroll statement for this month."}</p></div>{canManage && selectedRun.status !== "paid" && <form action={transitionPayrollRun} className="stage-form"><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="run_id" value={selectedRun.id}/>{selectedRun.status === "draft" ? <button name="decision" value="approve" type="submit" disabled={!entries.length}>Approve & publish statements</button> : <button name="decision" value="mark_paid" type="submit">Mark paid</button>}</form>}</div>{entries.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canManage && <th>Employee</th>}<th>Base</th><th>Allowance</th><th>Bonus</th><th>Additions</th><th>Deductions</th><th>Net pay</th><th>Status / action</th></tr></thead><tbody>{entries.map((entry) => <tr key={entry.id}>{canManage && <td><b>{names.get(entry.member_id) ?? "Team member"}</b></td>}<td>{money(entry.base_salary, entry.currency)}</td><td>{money(entry.monthly_allowance, entry.currency)}</td><td>{money(entry.bonus_paid, entry.currency)}</td><td>{money(entry.other_additions, entry.currency)}</td><td>{money(entry.deductions, entry.currency)}</td><td><b>{money(entry.net_pay, entry.currency)}</b></td><td>{selectedRun.status === "draft" && canManage ? <details><summary>Edit draft</summary><form action={updatePayrollEntry} className="lead-form payroll-adjustment-form"><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="run_id" value={selectedRun.id}/><input type="hidden" name="entry_id" value={entry.id}/><label>Bonus paid<input name="bonus_paid" type="number" min="0" step="0.01" defaultValue={entry.bonus_paid}/></label><label>Other additions<input name="other_additions" type="number" min="0" step="0.01" defaultValue={entry.other_additions}/></label><label>Deductions<input name="deductions" type="number" min="0" step="0.01" defaultValue={entry.deductions}/></label><label>Adjustment note<input name="adjustment_note" maxLength={500} defaultValue={entry.adjustment_note}/></label><button className="primary-button" type="submit">Save adjustment</button></form></details> : selectedRun.status === "draft" ? <span className="live-metric-detail">Draft · not published</span> : <a href={`/workspace/people/payroll/statements/${entry.id}`}>View statement →</a>}</td></tr>)}</tbody></table></div> : <div className="empty-state">No employee had compensation effective on {dateLabel(selectedRun.period_start)}. Add compensation dated on or before the period start, then create a new run.</div>}</section>}
        <section className="card leads-card"><div className="leads-heading"><div><h2>Payroll boundaries</h2><p>“Mark paid” records that an authorized operator completed payment outside this app. No bank details or payment credentials are stored, and tax or statutory deductions must be reviewed using your configured local process.</p></div></div></section>
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Compensation updates are permission-gated and audited</span></footer>
      </div>
    </section>
  </main>;
}
