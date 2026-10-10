import { redirect } from "next/navigation";
import { Activity, BadgeIndianRupee, CalendarClock, FileText, FolderOpen, ListTodo, Users, WalletCards } from "lucide-react";
import { createClient } from "@/lib/supabase/server";

type Membership = { organization_id: string; role: string; organizations: { name: string } | { name: string }[] | null };
type AuditEntry = { id: number; actor_id: string | null; action: string; entity_type: string; entity_id: string | null; changes: unknown; created_at: string };
const pretty = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());

export default async function AuditPage({ searchParams }: { searchParams: Promise<{ organization?: string; action?: string; entity?: string; from?: string; to?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: membershipRows } = await supabase.from("org_members").select("organization_id,role,organizations(name)").eq("user_id", user.id).eq("status", "active");
  const memberships = (membershipRows ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organizationId = membership.organization_id;
  const organization = Array.isArray(membership.organizations) ? membership.organizations[0] : membership.organizations;

  let query = supabase.from("audit_logs").select("id,actor_id,action,entity_type,entity_id,changes,created_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(100);
  if (params.action) query = query.eq("action", params.action);
  if (params.entity) query = query.eq("entity_type", params.entity);
  if (params.from && /^\d{4}-\d{2}-\d{2}$/.test(params.from)) query = query.gte("created_at", `${params.from}T00:00:00`);
  if (params.to && /^\d{4}-\d{2}-\d{2}$/.test(params.to)) query = query.lt("created_at", `${params.to}T23:59:59.999`);
  const { data: entries } = await query;
  const events = (entries ?? []) as AuditEntry[];
  const actorIds = [...new Set(events.flatMap((entry) => entry.actor_id ? [entry.actor_id] : []))];
  const { data: profiles } = actorIds.length ? await supabase.from("profiles").select("id,full_name").in("id", actorIds) : { data: [] };
  const names = new Map((profiles ?? []).map((profile) => [profile.id, profile.full_name]));

  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{organization?.name ?? "Agency workspace"}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}><Activity size={17}/><span>Overview</span></a><a className="nav-link" href={`/workspace/sales?organization=${organizationId}`}><Activity size={17}/><span>Sales & CRM</span></a><a className="nav-link" href={`/workspace/clients?organization=${organizationId}`}><Users size={17}/><span>Clients</span></a><a className="nav-link" href={`/workspace/projects?organization=${organizationId}`}><FileText size={17}/><span>Projects</span></a><a className="nav-link" href={`/workspace/content?organization=${organizationId}`}><CalendarClock size={17}/><span>Content</span></a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}><ListTodo size={17}/><span>Tasks</span></a><a className="nav-link" href={`/workspace/team?organization=${organizationId}`}><Users size={17}/><span>Team</span></a><a className="nav-link" href={`/workspace/finance?organization=${organizationId}`}><WalletCards size={17}/><span>Finance</span></a><a className="nav-link active" href={`/workspace/audit?organization=${organizationId}`}><Activity size={17}/><span>Audit history</span></a><a className="nav-link" href={`/workspace/files?organization=${organizationId}`}><FolderOpen size={17}/><span>Files</span></a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{organization?.name ?? "Agency workspace"}</span><span className="slash">/</span><b>Audit history</b><span className="live-label">Organization activity</span></div><div className="top-actions"><span className="signed-in-as">{user.email}</span></div></header><div className="content-wrap">
      <section className="welcome-row"><div><div className="eyebrow">SECURITY & ACCOUNTABILITY</div><h1>Audit history</h1><p>Review recent changes made across this organization.</p></div></section>
      <section className="card audit-filter-card"><form className="audit-filters" method="get"><input type="hidden" name="organization" value={organizationId}/><label>Action<select name="action" defaultValue={params.action ?? ""}><option value="">All actions</option><option value="insert">Created</option><option value="update">Updated</option><option value="delete">Deleted</option></select></label><label>Record type<input name="entity" defaultValue={params.entity ?? ""} placeholder="e.g. invoice"/></label><label>From<input name="from" type="date" defaultValue={params.from}/></label><label>To<input name="to" type="date" defaultValue={params.to}/></label><button className="primary-button" type="submit">Filter activity</button></form></section>
      <section className="card audit-list-card"><div className="leads-heading"><div><h2>Recent activity</h2><p>Showing up to 100 matching events</p></div></div>{events.length ? <div className="audit-event-list">{events.map((entry) => <article className="audit-event" key={entry.id}><span className="audit-event-icon"><Activity size={15}/></span><div className="audit-event-main"><b>{pretty(entry.action)} {pretty(entry.entity_type)}</b><p>{names.get(entry.actor_id ?? "") || (entry.actor_id ? "Organization member" : "System")} · {entry.entity_id ? `Record ${entry.entity_id.slice(0, 8)}` : "Organization event"}</p><details><summary>View change details</summary><pre>{JSON.stringify(entry.changes, null, 2)}</pre></details></div><time dateTime={entry.created_at}>{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Kolkata" }).format(new Date(entry.created_at))}</time></article>)}</div> : <div className="empty-state lead-empty"><b>No matching activity</b><span>Try a wider date range or clear the filters.</span></div>}</section>
      <footer className="footer"><span>LET’S GO. CENTRAL OS</span><span>Activity is visible only to members of this organization.</span></footer>
    </div></section>
  </main>;
}
