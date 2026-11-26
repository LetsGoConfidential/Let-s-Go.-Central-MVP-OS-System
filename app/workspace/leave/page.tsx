import { redirect } from "next/navigation";
import { CalendarDays } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { requestLeave, reviewLeaveRequest, setLeaveBalance } from "./actions";

type OrganizationInfo = { name: string; timezone: string } | { name: string; timezone: string }[] | null;
type Membership = { organization_id: string; role: string; organizations: OrganizationInfo };
function organization(row: Membership) { return Array.isArray(row.organizations) ? row.organizations[0] : row.organizations; }
function orgName(row: Membership) { return organization(row)?.name ?? "Agency workspace"; }
function dateLabel(value: string) { return new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`)); }
function workingDays(from: string, to: string) {
  let count = 0;
  for (let day = new Date(`${from}T12:00:00Z`); day <= new Date(`${to}T12:00:00Z`); day.setUTCDate(day.getUTCDate() + 1)) {
    const weekday = day.getUTCDay();
    if (weekday !== 0 && weekday !== 6) count += 1;
  }
  return count;
}
function dayLabel(value: number) { return Number.isInteger(value) ? String(value) : value.toFixed(1); }

export default async function LeavePage({ searchParams }: { searchParams: Promise<{ organization?: string; requested?: string; approved?: string; rejected?: string; balanceSaved?: string; error?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: membershipsRaw } = await supabase.from("org_members").select("organization_id,role,organizations(name,timezone)").eq("user_id", user.id).eq("status", "active");
  const memberships = (membershipsRaw ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organizationId = membership.organization_id;
  const timezone = organization(membership)?.timezone ?? "UTC";
  const leaveYear = Number(new Intl.DateTimeFormat("en", { timeZone: timezone, year: "numeric" }).format(new Date()));
  const yearStart = `${leaveYear}-01-01`;
  const yearEnd = `${leaveYear}-12-31`;
  const [{ data: canReview }, { data: requests }, { data: balances }, { data: approvedRequests }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "hr.leave.manage" }),
    supabase.from("leave_requests").select("id,member_id,leave_type,start_date,end_date,reason,status,created_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(100),
    supabase.from("leave_balances").select("member_id,leave_year,leave_type,entitled_days,adjustment_days,updated_at").eq("organization_id", organizationId).eq("leave_year", leaveYear).order("leave_type"),
    supabase.from("leave_requests").select("member_id,leave_type,start_date,end_date").eq("organization_id", organizationId).eq("status", "approved").lte("start_date", yearEnd).gte("end_date", yearStart).limit(1000),
  ]);
  const activeMembers = canReview
    ? (await supabase.from("org_members").select("user_id").eq("organization_id", organizationId).eq("status", "active").neq("role", "client")).data ?? []
    : [];
  const ids = [...new Set([
    ...(requests ?? []).map((row) => row.member_id),
    ...(balances ?? []).map((row) => row.member_id),
    ...activeMembers.map((row) => row.user_id),
  ])];
  const { data: profiles } = ids.length ? await supabase.from("profiles").select("id,full_name").in("id", ids) : { data: [] };
  const names = new Map((profiles ?? []).map((profile) => [profile.id, profile.full_name || "Team member"]));
  const usedByMemberAndType = new Map<string, number>();
  for (const row of approvedRequests ?? []) {
    const from = row.start_date > yearStart ? row.start_date : yearStart;
    const to = row.end_date < yearEnd ? row.end_date : yearEnd;
    const key = `${row.member_id}:${row.leave_type}`;
    usedByMemberAndType.set(key, (usedByMemberAndType.get(key) ?? 0) + workingDays(from, to));
  }
  const message = params.requested ? "Your leave request was sent for review."
    : params.approved ? "Leave request approved."
      : params.rejected ? "Leave request declined."
        : params.balanceSaved ? "Leave balance saved."
          : params.error === "forbidden" ? "Your role cannot manage leave balances or review requests."
            : params.error ? "That update could not be saved. Check the dates, employee and balance values, then try again."
              : null;
  const success = Boolean(params.requested || params.approved || params.rejected || params.balanceSaved);

  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}>Overview</a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}>My tasks</a><a className="nav-link" href={`/workspace/team?organization=${organizationId}`}>Team &amp; KPIs</a><a className="nav-link active" href={`/workspace/people?organization=${organizationId}`}>Attendance &amp; Payroll</a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{orgName(membership)}</span><span className="slash">/</span><b>Leave &amp; time off</b><span className="live-label">People operations</span></div><span className="signed-in-as">{user.email}</span></header>
      <div id="main-content" tabIndex={-1} className="content-wrap"><section className="welcome-row"><div><div className="eyebrow">EMPLOYEE SELF-SERVICE</div><h1>Leave &amp; time off</h1><p>Request time off, track your current-year balance, and review team allocations when your role allows it.</p></div><CalendarDays size={20}/></section>
        {message && <div className={success ? "success-banner" : "auth-error"} role="status">{message}</div>}
        {canReview && <section className="card new-lead-card"><div className="leads-heading"><div><h2>Set a leave allocation</h2><p>Current organization year: {leaveYear}. Saving replaces the selected employee/type allocation. Half-day values are supported. Approved weekdays count as used; public holidays are not deducted automatically.</p></div></div>{activeMembers.length ? <form action={setLeaveBalance} className="lead-form"><input type="hidden" name="organization_id" value={organizationId}/><input type="hidden" name="leave_year" value={leaveYear}/><label>Employee<select name="member_id" required defaultValue=""><option value="" disabled>Select an employee</option>{activeMembers.map((member) => <option key={member.user_id} value={member.user_id}>{names.get(member.user_id) ?? "Team member"}</option>)}</select></label><label>Leave type<select name="leave_type" defaultValue="Annual"><option>Annual</option><option>Sick</option><option>Personal</option><option>Unpaid</option><option>Other</option></select></label><label>Entitled days<input type="number" name="entitled_days" min="0" max="366" step="0.5" required/></label><label>Adjustment days<input type="number" name="adjustment_days" min="-366" max="366" step="0.5" required/></label><button className="primary-button" type="submit">Save allocation</button></form> : <div className="empty-state">No active employee accounts are available to assign.</div>}</section>}
        <section className="card leads-card"><div className="leads-heading"><div><h2>{canReview ? `Team leave balances · ${leaveYear}` : `My leave balance · ${leaveYear}`}</h2><p>{canReview ? "Employee names and allocations are visible only to HR, owners, and admins." : "Only your personal leave balance and approved usage are shown."} Weekdays are counted Monday–Friday; holidays are not excluded.</p></div></div>{balances?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canReview && <th>Employee</th>}<th>Leave type</th><th>Entitled</th><th>Adjustment</th><th>Approved used</th><th>Remaining</th><th>Updated</th></tr></thead><tbody>{balances.map((row) => { const used = usedByMemberAndType.get(`${row.member_id}:${row.leave_type}`) ?? 0; const allocation = Number(row.entitled_days) + Number(row.adjustment_days); return <tr key={`${row.member_id}:${row.leave_type}`}>
          {canReview && <td>{names.get(row.member_id) ?? "Team member"}</td>}<td>{row.leave_type}</td><td>{dayLabel(Number(row.entitled_days))} days</td><td>{Number(row.adjustment_days) > 0 ? "+" : ""}{dayLabel(Number(row.adjustment_days))} days</td><td>{dayLabel(used)} days</td><td><b>{dayLabel(allocation - used)} days</b></td><td>{dateLabel(row.updated_at.slice(0, 10))}</td>
        </tr>; })}</tbody></table></div> : <div className="empty-state">{canReview ? "No leave allocations yet. Set one above to start tracking balances." : "HR has not assigned a leave balance for this year yet."}</div>}</section>
        <div className="team-detail-grid"><section className="card new-lead-card"><div className="leads-heading"><div><h2>Request leave</h2><p>Your manager or an authorized HR teammate will review this request.</p></div></div><form action={requestLeave} className="lead-form"><input type="hidden" name="organization_id" value={organizationId}/><label>Leave type<select name="leave_type" defaultValue="Annual"><option>Annual</option><option>Sick</option><option>Personal</option><option>Unpaid</option><option>Other</option></select></label><label>From<input type="date" name="start_date" required/></label><label>To<input type="date" name="end_date" required/></label><label>Note for reviewer<textarea name="reason" maxLength={2000} rows={4} placeholder="Optional context"/></label><button className="primary-button" type="submit">Send request</button></form></section>
          <section className="card leads-card"><div className="leads-heading"><div><h2>{canReview ? "Leave review queue" : "My requests"}</h2><p>{canReview ? "Employee details are visible only to HR, owners and admins." : "Only your own leave requests appear here."}</p></div></div>{requests?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canReview && <th>Employee</th>}<th>Leave</th><th>Dates</th><th>Note</th><th>Status</th>{canReview && <th>Review</th>}</tr></thead><tbody>{requests.map((row) => <tr key={row.id}>{canReview && <td>{names.get(row.member_id) ?? "Team member"}</td>}<td>{row.leave_type}</td><td>{dateLabel(row.start_date)} – {dateLabel(row.end_date)}</td><td>{row.reason || "—"}</td><td><span className={`stage-pill stage-${row.status === "approved" ? "completed" : row.status === "pending" ? "review" : "urgent"}`}>{row.status}</span></td>{canReview && <td>{row.status === "pending" ? <form action={reviewLeaveRequest} className="stage-form"><input type="hidden" name="organization_id" value={organizationId}/><input type="hidden" name="request_id" value={row.id}/><button name="decision" value="approved" type="submit">Approve</button><button name="decision" value="rejected" type="submit">Decline</button></form> : "—"}</td>}</tr>)}</tbody></table></div> : <div className="empty-state">No leave requests yet.</div>}</section></div>
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Leave decisions and allocations are permission-checked and audited</span></footer>
      </div>
    </section>
  </main>;
}
