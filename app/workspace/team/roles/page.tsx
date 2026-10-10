import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { assignCustomRole, saveCustomRole } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string } | { name: string }[] | null };
function orgName(row: Membership) { return (Array.isArray(row.organizations) ? row.organizations[0] : row.organizations)?.name ?? "Agency workspace"; }
const messages: Record<string, string> = {
  saved: "Custom role saved. It can now be assigned to active team members.",
  assigned: "Team role assignment saved.",
  forbidden: "Only organization owners and admins can manage roles.",
  invalid: "Enter a role name between 2 and 80 characters.",
  "save-failed": "The role could not be saved. Use a unique name and try again.",
  "assignment-failed": "This role could not be assigned. Owners and your own membership are protected.",
};

export default async function RolesPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined> & { organization?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rows } = await supabase.from("org_members").select("organization_id,role,organizations(name)").eq("user_id", user.id).eq("status", "active");
  const memberships = (rows ?? []) as unknown as Membership[];
  const membership = memberships.find((item) => item.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organizationId = membership.organization_id;
  const [{ data: canManage }, { data: roleRows }, { data: members }, { data: assignmentRows }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" }),
    supabase.from("roles").select("id,name,is_system,permissions").eq("organization_id", organizationId).order("name"),
    supabase.from("org_members").select("user_id,role,status").eq("organization_id", organizationId).eq("status", "active").neq("role", "client").order("created_at"),
    supabase.from("role_assignments").select("user_id,role_id").eq("organization_id", organizationId),
  ]);
  if (!canManage) redirect(`/workspace/team?organization=${organizationId}&forbidden=1`);
  const customRoles = (roleRows ?? []).filter((role) => !role.is_system);
  const userIds = (members ?? []).map((member) => member.user_id);
  const { data: profiles } = userIds.length ? await supabase.from("profiles").select("id,full_name").in("id", userIds) : { data: [] };
  const profileMap = new Map((profiles ?? []).map((profile) => [profile.id, profile.full_name]));
  const assignmentMap = new Map((assignmentRows ?? []).map((assignment) => [assignment.user_id, assignment.role_id]));
  const message = Object.entries(messages).find(([key]) => params[key])?.[1];
  return <main className="app-shell"><aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}>Overview</a><a className="nav-link" href={`/workspace/sales?organization=${organizationId}`}>Sales & CRM</a><a className="nav-link" href={`/workspace/clients?organization=${organizationId}`}>Clients</a><a className="nav-link" href={`/workspace/projects?organization=${organizationId}`}>Projects</a><a className="nav-link" href={`/workspace/content?organization=${organizationId}`}>Content</a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}>Tasks</a><a className="nav-link active" href={`/workspace/team?organization=${organizationId}`}>Team</a><a className="nav-link" href={`/workspace/finance?organization=${organizationId}`}>Finance</a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
  <section className="main-area"><header className="topbar"><div className="breadcrumbs"><a href={`/workspace/team?organization=${organizationId}`}>Team</a><span className="slash">/</span><b>Roles & permissions</b><span className="live-label">Admin settings</span></div><span className="signed-in-as">{user.email}</span></header><div className="content-wrap"><section className="welcome-row"><div><div className="eyebrow">ACCESS CONTROL</div><h1>Roles & permissions</h1><p>Create custom roles for workspace and finance access, then assign one to a teammate.</p></div><a className="back-link" href={`/workspace/team?organization=${organizationId}`}>← Back to team</a></section>
  {message && <div className={params.saved || params.assigned ? "success-banner" : "auth-error"} role="status">{message}</div>}
  <section className="card new-lead-card"><div className="leads-heading"><div><h2>Create or update a custom role</h2><p>Saving an existing name updates its permissions.</p></div></div><form action={saveCustomRole} className="role-form"><input type="hidden" name="organization_id" value={organizationId}/><label>Role name<input name="name" required minLength={2} maxLength={80} placeholder="Delivery editor"/></label><label className="role-check"><input type="checkbox" name="workspace_write"/> Can create and update workspace records</label><label className="role-check"><input type="checkbox" name="finance_manage"/> Can manage invoices and expenses</label><p className="data-note role-note">Organization administration and member invitations stay restricted to owner and admin accounts.</p><button className="primary-button" type="submit">Save role</button></form></section>
  <section className="card leads-card"><div className="leads-heading"><div><h2>Custom roles</h2><p>{customRoles.length} roles in this organization</p></div></div>{customRoles.length ? <div className="table-scroll"><table className="lead-table"><thead><tr><th>Role</th><th>Workspace edits</th><th>Finance management</th></tr></thead><tbody>{customRoles.map((role) => <tr key={role.id}><td><b>{role.name}</b></td><td>{role.permissions?.["workspace.write"] ? "Allowed" : "Read only"}</td><td>{role.permissions?.["finance.manage"] ? "Allowed" : "No access"}</td></tr>)}</tbody></table></div> : <div className="empty-state">No custom roles yet. Save one above to get started.</div>}</section>
  <section className="card leads-card"><div className="leads-heading"><div><h2>Assign a custom role</h2><p>Each member can have one custom role here. Selecting no custom role restores base-role permissions.</p></div></div>{members?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr><th>Member</th><th>Base role</th><th>Custom role</th><th></th></tr></thead><tbody>{members.map((member) => <tr key={member.user_id}><td><b>{profileMap.get(member.user_id) || "Team member"}</b>{member.user_id === user.id && <small>You</small>}</td><td>{member.role}</td><td>{member.role === "owner" || member.user_id === user.id ? <span className="live-metric-detail">Protected</span> : <form action={assignCustomRole} className="stage-form role-assign-form"><input type="hidden" name="organization_id" value={organizationId}/><input type="hidden" name="user_id" value={member.user_id}/><select name="role_id" aria-label={`Custom role for ${profileMap.get(member.user_id) || "team member"}`} defaultValue={assignmentMap.get(member.user_id) ?? ""}><option value="">No custom role</option>{customRoles.map((role) => <option key={role.id} value={role.id}>{role.name}</option>)}</select><button type="submit">Save</button></form>}</td><td></td></tr>)}</tbody></table></div> : <div className="empty-state">No active internal members to assign.</div>}</section>
  <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Custom permissions are constrained to the selected access keys</span></footer></div></section></main>;
}
