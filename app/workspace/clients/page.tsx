import { redirect } from "next/navigation";
import { Plus, Search, Users } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { createClientRecord } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string; currency: string } | { name: string; currency: string }[] | null };
function orgInfo(membership: Membership) { return Array.isArray(membership.organizations) ? membership.organizations[0] : membership.organizations; }
function orgName(membership: Membership) { return orgInfo(membership)?.name ?? "Agency workspace"; }

export default async function ClientsPage({ searchParams }: { searchParams: Promise<{ organization?: string; error?: string; q?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rows } = await supabase.from("org_members").select("organization_id, role, organizations(name,currency)").eq("user_id", user.id).eq("status", "active");
  const memberships = (rows ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organizationId = membership.organization_id;
  const currency = orgInfo(membership)?.currency?.trim() ?? "INR";
  const money = new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 0 });
  const search = (params.q ?? "").trim().slice(0, 100);
  let clientsQuery = supabase.from("clients").select("id,name,industry,website,health,monthly_value,created_at").eq("organization_id", organizationId).order("name").limit(200);
  if (search) clientsQuery = clientsQuery.ilike("name", `%${search}%`);
  const [{ data: clients }, { data: canWrite }] = await Promise.all([
    clientsQuery,
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" }),
  ]);
  const healthLabel: Record<string, string> = { healthy: "Healthy", needs_attention: "Needs attention", at_risk: "At risk", churned: "Churned" };
  const activeValue = (clients ?? []).reduce((sum, client) => sum + Number(client.monthly_value ?? 0), 0);

  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}>Overview</a><a className="nav-link" href={`/workspace/sales?organization=${organizationId}`}>Sales & CRM</a><a className="nav-link active" href={`/workspace/clients?organization=${organizationId}`}><Users size={17}/><span>Clients</span></a><a className="nav-link" href={`/workspace/projects?organization=${organizationId}`}>Projects</a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}>Tasks</a><a className="nav-link" href={`/workspace/finance?organization=${organizationId}`}>Finance</a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{orgName(membership)}</span><span className="slash">/</span><b>Clients</b><span className="live-label">Live workspace</span></div><div className="top-actions"><span className="signed-in-as">{user.email}</span></div></header><div className="content-wrap">
      <section className="welcome-row"><div><div className="eyebrow">CLIENT RELATIONSHIPS</div><h1>Clients</h1><p>Keep account health, monthly value, and key contacts in one place.</p></div>{canWrite && <a className="primary-button sales-create-link" href="#new-client"><Plus size={16}/> New client</a>}</section>
        <section className="sales-summary-grid"><article className="metric card"><div className="metric-top"><span>Active clients</span></div><div className="metric-value">{clients?.length ?? 0}</div><div className="live-metric-detail">{search ? "Matching your search" : "Customer accounts in this view"}</div></article><article className="metric card"><div className="metric-top"><span>Monthly service value</span></div><div className="metric-value">{money.format(activeValue)}</div><div className="live-metric-detail">Sum of listed client monthly values · {currency}</div></article><article className="metric card"><div className="metric-top"><span>At risk</span></div><div className="metric-value">{(clients ?? []).filter((client) => client.health === "at_risk").length}</div><div className="live-metric-detail">Clients marked at risk</div></article></section>
      {params.error && <div className="auth-error" role="alert">{params.error === "forbidden" ? "Your role does not have permission to add clients." : params.error === "invalid" ? "Check the client name, monthly value, and contact details." : "The client could not be saved. Please try again."}</div>}
      <section className="card leads-card"><div className="leads-heading"><div><h2>Client directory</h2><p>{clients?.length ?? 0} accounts shown</p></div><form action="/workspace/clients" method="get" className="lead-search"><input type="hidden" name="organization" value={organizationId}/><Search size={15}/><input name="q" aria-label="Search client names" placeholder="Search clients" defaultValue={search}/><button type="submit">Search</button></form></div>
        {clients?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr><th>Client</th><th>Industry</th><th>Health</th><th>Monthly value</th><th>Website</th></tr></thead><tbody>{clients.map((client) => <tr key={client.id}><td><a className="table-primary-link" href={`/workspace/clients/${client.id}?organization=${organizationId}`}>{client.name}</a></td><td>{client.industry || "—"}</td><td><span className={`stage-pill health-${client.health}`}>{healthLabel[client.health] ?? client.health}</span></td><td>{money.format(Number(client.monthly_value ?? 0))}</td><td>{client.website ? <a href={client.website} target="_blank" rel="noreferrer">Open site ↗</a> : "—"}</td></tr>)}</tbody></table></div> : <div className="empty-state lead-empty"><b>{search ? "No matching clients" : "No client accounts yet"}</b><span>{search ? "Try another name." : "Add your first client to start a 360° account view."}</span></div>}
      </section>
      {canWrite && <section className="card new-lead-card" id="new-client"><div className="leads-heading"><div><h2>Add a client</h2><p>Optionally add a primary contact in the same save.</p></div></div><form action={createClientRecord} className="lead-form"><input type="hidden" name="organization_id" value={organizationId}/><label>Client name<input name="name" minLength={2} maxLength={160} required placeholder="Company or brand"/></label><label>Industry<input name="industry" maxLength={100} placeholder="Industry"/></label><label>Website<input name="website" placeholder="company.com"/></label><label>Monthly service value<input name="monthly_value" type="number" min="0" step="0.01" defaultValue="0"/></label><label>Primary contact first name<input name="contact_first_name" maxLength={100} placeholder="Optional"/></label><label>Primary contact last name<input name="contact_last_name" maxLength={100} placeholder="Optional"/></label><label>Contact email<input name="contact_email" type="email" placeholder="Optional"/></label><label>Contact phone<input name="contact_phone" maxLength={40} placeholder="Optional"/></label><button className="primary-button" type="submit">Save client</button></form></section>}
      <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Client records are scoped to this organization</span></footer>
    </div></section>
  </main>;
}
