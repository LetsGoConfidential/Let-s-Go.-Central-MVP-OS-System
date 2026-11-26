import { redirect } from "next/navigation";
import { Clock3 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { recordAttendance } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string } | { name: string }[] | null };
const orgName = (row: Membership) => (Array.isArray(row.organizations) ? row.organizations[0] : row.organizations)?.name ?? "Agency workspace";
const dateTime = (value: string | null) => value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "—";

export default async function AttendancePage({ searchParams }: { searchParams: Promise<{ organization?: string; recorded?: string; error?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: raw } = await supabase.from("org_members").select("organization_id,role,organizations(name)").eq("user_id", user.id).eq("status", "active");
  const memberships = (raw ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const orgId = membership.organization_id;
  const [{ data: canManage }, { data: records }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: orgId, permission_key: "hr.attendance.manage" }),
    supabase.from("attendance_days").select("id,member_id,work_date,checked_in_at,checked_out_at").eq("organization_id", orgId).order("work_date", { ascending: false }).limit(60),
  ]);
  const ids = canManage ? [...new Set((records ?? []).map((row) => row.member_id))] : [];
  const { data: profiles } = ids.length ? await supabase.from("profiles").select("id,full_name").in("id", ids) : { data: [] };
  const names = new Map((profiles ?? []).map((profile) => [profile.id, profile.full_name || "Team member"]));
  const mine = (records ?? []).find((row) => row.member_id === user.id);
  const message = params.recorded ? params.recorded === "check_in" ? "You are checked in for today." : "Your check-out time was recorded." : params.error ? "Attendance could not be recorded. Check whether you already checked in or out today." : null;
  return <main className="app-shell"><aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${orgId}`}>Overview</a><a className="nav-link" href={`/workspace/tasks?organization=${orgId}`}>My tasks</a><a className="nav-link" href={`/workspace/team?organization=${orgId}`}>Team</a><a className="nav-link" href={`/workspace/leave?organization=${orgId}`}>Leave & time off</a><a className="nav-link active" href={`/workspace/attendance?organization=${orgId}`}>Attendance</a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
  <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{orgName(membership)}</span><span className="slash">/</span><b>Attendance</b><span className="live-label">People operations</span></div><span className="signed-in-as">{user.email}</span></header><div id="main-content" tabIndex={-1} className="content-wrap"><section className="welcome-row"><div><div className="eyebrow">EMPLOYEE SELF-SERVICE</div><h1>Attendance</h1><p>Record your daily start and finish. Work dates follow the organization timezone.</p></div><Clock3 size={20}/></section>{message && <div className={params.recorded ? "success-banner" : "auth-error"} role="status">{message}</div>}
  <section className="team-detail-grid"><article className="card new-lead-card"><div className="leads-heading"><div><h2>Today</h2><p>One check-in and one check-out per organization workday.</p></div></div><div className="employee-kpi-list"><div className="employee-kpi-row"><span>Checked in</span><b>{dateTime(mine?.checked_in_at ?? null)}</b></div><div className="employee-kpi-row"><span>Checked out</span><b>{dateTime(mine?.checked_out_at ?? null)}</b></div></div><div className="stage-form">{!mine ? <form action={recordAttendance}><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="action_name" value="check_in"/><button className="primary-button" type="submit">Check in</button></form> : !mine.checked_out_at ? <form action={recordAttendance}><input type="hidden" name="organization_id" value={orgId}/><input type="hidden" name="action_name" value="check_out"/><button className="primary-button" type="submit">Check out</button></form> : <span className="live-metric-detail">Day complete</span>}</div></article>
  <article className="card leads-card"><div className="leads-heading"><div><h2>{canManage ? "Team attendance" : "My recent attendance"}</h2><p>{canManage ? "Visible to HR, owners and admins, or teammates explicitly granted attendance access." : "Only your personal attendance records are shown."}</p></div></div>{records?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{canManage && <th>Employee</th>}<th>Work date</th><th>Check in</th><th>Check out</th></tr></thead><tbody>{records.map((row) => <tr key={row.id}>{canManage && <td>{names.get(row.member_id) ?? "Team member"}</td>}<td>{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(`${row.work_date}T12:00:00Z`))}</td><td>{dateTime(row.checked_in_at)}</td><td>{dateTime(row.checked_out_at)}</td></tr>)}</tbody></table></div> : <div className="empty-state">No attendance has been recorded yet.</div>}</article></section><footer className="footer"><span>© 2026 Let’s Go Central</span><span>Attendance events are permission-checked and audited</span></footer></div></section></main>;
}
