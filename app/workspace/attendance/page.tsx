import { redirect } from "next/navigation";
import { Clock3 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { recordAttendance, requestAttendanceCorrection, reviewAttendanceCorrection } from "./actions";

type OrganizationInfo = { name: string; timezone: string } | { name: string; timezone: string }[] | null;
type Membership = { organization_id: string; role: string; organizations: OrganizationInfo };
function organization(row: Membership) { return Array.isArray(row.organizations) ? row.organizations[0] : row.organizations; }
const orgName = (row: Membership) => organization(row)?.name ?? "Agency workspace";
const dateTime = (value: string | null, timezone: string) => value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short", timeZone: timezone }).format(new Date(value)) : "—";
const dateLabel = (value: string) => new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`));

export default async function AttendancePage({ searchParams }: { searchParams: Promise<{ organization?: string; recorded?: string; correctionSubmitted?: string; correctionReviewed?: string; error?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: raw } = await supabase.from("org_members").select("organization_id,role,organizations(name,timezone)").eq("user_id", user.id).eq("status", "active");
  const memberships = (raw ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const orgId = membership.organization_id;
  const timezone = organization(membership)?.timezone ?? "UTC";
  const orgToday = new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const oldestCorrectionDay = new Date(`${orgToday}T12:00:00Z`);
  oldestCorrectionDay.setUTCDate(oldestCorrectionDay.getUTCDate() - 90);
  const oldestCorrectionDate = oldestCorrectionDay.toISOString().slice(0, 10);
  const [{ data: canManage }, { data: records }, { data: corrections }, { data: mineRecords }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: orgId, permission_key: "hr.attendance.manage" }),
    supabase.from("attendance_days").select("id,member_id,work_date,checked_in_at,checked_out_at").eq("organization_id", orgId).order("work_date", { ascending: false }).limit(60),
    supabase.from("attendance_corrections").select("id,attendance_id,member_id,proposed_check_in,proposed_check_out,reason,status,created_at").eq("organization_id", orgId).order("created_at", { ascending: false }).limit(100),
    supabase.from("attendance_days").select("id,work_date,checked_in_at,checked_out_at").eq("organization_id", orgId).eq("member_id", user.id).gte("work_date", oldestCorrectionDate).lte("work_date", orgToday).order("work_date", { ascending: false }).limit(100),
  ]);
  const attendanceIds = [...new Set((corrections ?? []).map((row) => row.attendance_id))];
  const { data: correctionDays } = attendanceIds.length
    ? await supabase.from("attendance_days").select("id,work_date,checked_in_at,checked_out_at").eq("organization_id", orgId).in("id", attendanceIds)
    : { data: [] };
  const currentByAttendance = new Map((correctionDays ?? []).map((row) => [row.id, row]));
  const ids = canManage ? [...new Set([...(records ?? []).map((row) => row.member_id), ...(corrections ?? []).map((row) => row.member_id)])] : [];
  const { data: profiles } = ids.length ? await supabase.from("profiles").select("id,full_name").in("id", ids) : { data: [] };
  const names = new Map((profiles ?? []).map((profile) => [profile.id, profile.full_name || "Team member"]));
  const mine = (records ?? []).find((row) => row.member_id === user.id);
  const pendingDayIds = new Set((corrections ?? []).filter((row) => row.status === "pending").map((row) => row.attendance_id));
  const correctionCandidates = (mineRecords ?? []).filter((row) => !pendingDayIds.has(row.id));
  const message = params.recorded ? params.recorded === "check_in" ? "You are checked in for today." : "Your check-out time was recorded."
    : params.correctionSubmitted ? "Your attendance correction was sent to HR for review."
      : params.correctionReviewed ? `Attendance correction ${params.correctionReviewed}.`
        : params.error === "forbidden" ? "Your role cannot review attendance corrections."
          : params.error ? "That attendance update could not be saved. Check the workday, times, and request status."
            : null;
  const success = Boolean(params.recorded || params.correctionSubmitted || params.correctionReviewed);

  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${orgId}`}>Overview</a><a className="nav-link" href={`/workspace/tasks?organization=${orgId}`}>My tasks</a><a className="nav-link" href={`/workspace/team?organization=${orgId}`}>Team &amp; KPIs</a><a className="nav-link active" href={`/workspace/people?organization=${orgId}`}>Attendance &amp; Payroll</a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{orgName(membership)}</span><span className="slash">/</span><b>Attendance</b><span className="live-label">People operations</span></div><span className="signed-in-as">{user.email}</span></header>
      <div id="main-content" tabIndex={-1} className="content-wrap"><section className="welcome-row"><div><div className="eyebrow">EMPLOYEE SELF-SERVICE</div><h1>Attendance</h1><p>Record your workday and request a correction when a recorded time needs review. Dates and times use {timezone}.</p></div><Clock3 size={20}/></section>
        {message && <div className={success ? "success-banner" : "auth-error"} role="status">{message}</div>}
        <section className="team-detail-grid"><article className="card new-lead-card"><div className="leads-heading"><div><h2>Today</h2><p>One check-in and one check-out per organization workday.</p></div></div><div className="employee-kpi-list"><div className="employee-kpi-row"><span>Checked in</span><b>{dateTime(mine?.checked_in_at ?? null, timezone)}</b></div><div className="employee-kpi-row"><span>Checked out</span><b>{dateTime(mine?.checked_out_at ?? null, timezone)}</b></div></div><div className="stage-form">{!mine ? <form action={recordAttendance}><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="action_name" value="check_in"/><button className="primary-button" type="submit">Check in</button></form> : !mine.checked_out_at ? <form action={recordAttendance}><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="action_name" value="check_out"/><button className="primary-button" type="submit">Check out</button></form> : <span className="live-metric-detail">Day complete</span>}</div></article>
          <article className="card leads-card"><div className="leads-heading"><div><h2>{canManage ? "Team attendance" : "My recent attendance"}</h2><p>{canManage ? "Visible to HR, owners and admins, or teammates explicitly granted attendance access." : "Only your personal attendance records are shown."}</p></div></div>{records?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canManage && <th>Employee</th>}<th>Work date</th><th>Check in</th><th>Check out</th></tr></thead><tbody>{records.map((row) => <tr key={row.id}>{canManage && <td>{names.get(row.member_id) ?? "Team member"}</td>}<td>{dateLabel(row.work_date)}</td><td>{dateTime(row.checked_in_at, timezone)}</td><td>{dateTime(row.checked_out_at, timezone)}</td></tr>)}</tbody></table></div> : <div className="empty-state">No attendance has been recorded yet.</div>}</article>
        </section>
        <section className="card new-lead-card"><div className="leads-heading"><div><h2>Request a time correction</h2><p>Choose one of your recorded days from the last 90 days. HR reviews every request; a pending request prevents duplicates for that day.</p></div></div>{correctionCandidates.length ? <form action={requestAttendanceCorrection} className="lead-form"><input type="hidden" name="organization_id" value={orgId}/><label>Workday<select name="attendance_id" required defaultValue=""><option value="" disabled>Select a recorded workday</option>{correctionCandidates.map((row) => <option value={row.id} key={row.id}>{dateLabel(row.work_date)} · {dateTime(row.checked_in_at, timezone)}–{dateTime(row.checked_out_at, timezone)}</option>)}</select></label><label>Correct check-in · {timezone}<input type="datetime-local" name="proposed_check_in" required/></label><label>Correct check-out · {timezone}<input type="datetime-local" name="proposed_check_out"/></label><label>Why does this time need correction?<textarea name="reason" rows={3} maxLength={1000} minLength={3} required placeholder="Add a short explanation for HR"/></label><button className="primary-button" type="submit">Send correction request</button></form> : <div className="empty-state">No recorded workday is available for a correction request. A day can have one pending request at a time.</div>}</section>
        <section className="card leads-card"><div className="leads-heading"><div><h2>{canManage ? "Attendance correction review" : "My correction requests"}</h2><p>{canManage ? "Approving applies the requested times and writes an attendance audit event." : "Your requests and decisions are visible here."}</p></div></div>{corrections?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canManage && <th>Employee</th>}<th>Work date</th><th>Recorded</th><th>Requested</th><th>Reason</th><th>Status</th>{canManage && <th>Review</th>}</tr></thead><tbody>{corrections.map((row) => { const day = currentByAttendance.get(row.attendance_id); return <tr key={row.id}>{canManage && <td>{names.get(row.member_id) ?? "Team member"}</td>}<td>{day ? dateLabel(day.work_date) : "—"}</td><td>{day ? `${dateTime(day.checked_in_at, timezone)} – ${dateTime(day.checked_out_at, timezone)}` : "—"}</td><td>{dateTime(row.proposed_check_in, timezone)} – {dateTime(row.proposed_check_out, timezone)}</td><td>{row.reason}</td><td><span className={`stage-pill stage-${row.status === "approved" ? "completed" : row.status === "pending" ? "review" : "urgent"}`}>{row.status}</span></td>{canManage && <td>{row.status === "pending" ? <form action={reviewAttendanceCorrection} className="stage-form"><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="correction_id" value={row.id}/><button name="decision" value="approved" type="submit">Approve</button><button name="decision" value="rejected" type="submit">Decline</button></form> : "—"}</td>}</tr>; })}</tbody></table></div> : <div className="empty-state">No correction requests yet.</div>}</section>
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Attendance corrections require HR review and are audited</span></footer>
      </div>
    </section>
  </main>;
}
