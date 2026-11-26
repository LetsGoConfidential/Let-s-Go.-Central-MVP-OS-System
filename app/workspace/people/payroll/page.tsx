import { redirect } from "next/navigation";
import { BadgeIndianRupee, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { saveCompensation } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string; currency: string; timezone: string } | { name: string; currency: string; timezone: string }[] | null };
type Compensation = { id: string; member_id: string; effective_from: string; effective_to: string | null; monthly_base: number; monthly_allowance: number; monthly_bonus_target: number; currency: string; change_reason: string; created_at: string };
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
};

export default async function PayrollPage({ searchParams }: { searchParams: Promise<{ organization?: string; saved?: string; invalid?: string; forbidden?: string; "save-failed"?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rows } = await supabase.from("org_members").select("organization_id,role,organizations(name,currency,timezone)").eq("user_id", user.id).eq("status", "active");
  const memberships = (rows ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const orgId = membership.organization_id;
  const [{ data: canManage }, { data: rawCompensation }, { data: memberRows }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: orgId, permission_key: "hr.payroll.manage" }),
    supabase.from("employee_compensation").select("id,member_id,effective_from,effective_to,monthly_base,monthly_allowance,monthly_bonus_target,currency,change_reason,created_at").eq("organization_id", orgId).order("effective_from", { ascending: false }),
    supabase.from("org_members").select("user_id,department,role").eq("organization_id", orgId).eq("status", "active").neq("role", "client").order("created_at"),
  ]);
  const compensation = (rawCompensation ?? []) as Compensation[];
  const members = memberRows ?? [];
  const ids = [...new Set([...compensation.map((row) => row.member_id), ...(canManage ? members.map((row) => row.user_id) : [user.id])])];
  const { data: profileRows } = ids.length ? await supabase.from("profiles").select("id,full_name").in("id", ids) : { data: [] };
  const names = new Map((profileRows ?? []).map((row) => [row.id, row.full_name]));
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: orgTimezone(membership), year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const currentRows = compensation.filter((row) => row.effective_to === null && row.effective_from <= today);
  const current = compensation.find((row) => row.member_id === user.id && row.effective_to === null && row.effective_from <= today);
  const message = Object.entries(messages).find(([key]) => params[key as keyof typeof params])?.[1];
  const currency = orgCurrency(membership);

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
        {message && <div className={params.saved ? "success-banner" : "auth-error"} role="status">{message}</div>}
        {current && <section className="metrics-grid" aria-label="My current compensation"><article className="metric card"><div className="metric-top"><span>Monthly base</span><span className="metric-icon"><BadgeIndianRupee size={17}/></span></div><div className="metric-value">{money(current.monthly_base, current.currency)}</div><div className="live-metric-detail">Effective {dateLabel(current.effective_from)}</div></article><article className="metric card"><div className="metric-top"><span>Monthly allowance</span></div><div className="metric-value">{money(current.monthly_allowance, current.currency)}</div><div className="live-metric-detail">Current compensation record</div></article><article className="metric card"><div className="metric-top"><span>Monthly bonus target</span></div><div className="metric-value">{money(current.monthly_bonus_target, current.currency)}</div><div className="live-metric-detail">Target only; actual bonus is human-approved</div></article><article className="metric card"><div className="metric-top"><span>Payroll record privacy</span><span className="metric-icon"><ShieldCheck size={17}/></span></div><div className="metric-value">Restricted</div><div className="live-metric-detail">Only you and payroll-authorized roles can view this</div></article></section>}
        {canManage && <section className="card new-lead-card"><div className="leads-heading"><div><h2>Record a salary or bonus change</h2><p>Add an effective-dated record. The system closes the previous active record the day before this one begins.</p></div></div><form action={saveCompensation} className="lead-form"><input type="hidden" name="organization_id" value={orgId}/><label>Employee<select name="member_id" required defaultValue=""><option value="" disabled>Select an active employee</option>{members.map((member) => <option key={member.user_id} value={member.user_id}>{names.get(member.user_id) ?? "Team member"}{member.department ? ` · ${member.department}` : ""}</option>)}</select></label><label>Effective from<input name="effective_from" type="date" required/></label><label>Monthly base salary<input name="monthly_base" type="number" min="0" step="0.01" required placeholder="0.00"/></label><label>Monthly allowance<input name="monthly_allowance" type="number" min="0" step="0.01" defaultValue="0"/></label><label>Monthly bonus target<input name="monthly_bonus_target" type="number" min="0" step="0.01" defaultValue="0"/></label><label>Currency<input name="currency" defaultValue={currency} maxLength={3} pattern="[A-Za-z]{3}" required/></label><label>Change reason<input name="change_reason" required minLength={3} maxLength={500} placeholder="Annual increment, role change, bonus adjustment"/></label><p className="data-note role-note">This records agreed compensation terms only. It does not calculate taxes or create a payment instruction.</p><button className="primary-button" type="submit">Save compensation change</button></form></section>}
        <section className="card leads-card"><div className="leads-heading"><div><h2>{canManage ? "Team compensation history" : "My compensation history"}</h2><p>{canManage ? `${currentRows.length} active compensation records · amounts are only visible to payroll-authorized roles and each employee.` : "Your changes are listed newest first."}</p></div></div>{compensation.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canManage && <th>Employee</th>}<th>Effective period</th><th>Monthly base</th><th>Allowance</th><th>Bonus target</th><th>Change reason</th><th>Status</th></tr></thead><tbody>{compensation.map((row) => { const scheduled = !row.effective_to && row.effective_from > today; const status = row.effective_to ? "Historical" : scheduled ? "Scheduled" : "Current"; return <tr key={row.id}>{canManage && <td><b>{names.get(row.member_id) ?? "Team member"}</b></td>}<td>{dateLabel(row.effective_from)} – {row.effective_to ? dateLabel(row.effective_to) : "Open"}</td><td>{money(row.monthly_base, row.currency)}</td><td>{money(row.monthly_allowance, row.currency)}</td><td>{money(row.monthly_bonus_target, row.currency)}</td><td>{row.change_reason}</td><td><span className={`stage-pill ${status === "Current" ? "stage-completed" : "stage-review"}`}>{status}</span></td></tr>; })}</tbody></table></div> : <div className="empty-state">{canManage ? "No compensation records yet. Add the first approved salary record above." : "No compensation record has been shared with your account yet."}</div>}</section>
        <section className="card leads-card"><div className="leads-heading"><div><h2>Next payroll steps</h2><p>Salary slips, approved monthly payroll runs, bonus payouts, bank details, and statutory deductions still need their own protected workflows. This foundation avoids collecting bank data before those controls are ready.</p></div></div></section>
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Compensation updates are permission-gated and audited</span></footer>
      </div>
    </section>
  </main>;
}
