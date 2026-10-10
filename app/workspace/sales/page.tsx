import { redirect } from "next/navigation";
import { Plus, Search } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { convertWonLead, createLead, updateLeadStage } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string; slug: string } | { name: string; slug: string }[] | null };

function orgName(membership: Membership) {
  const relation = membership.organizations;
  return Array.isArray(relation) ? relation[0]?.name ?? "Agency workspace" : relation?.name ?? "Agency workspace";
}

const money = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 });

export default async function SalesPage({ searchParams }: { searchParams: Promise<{ organization?: string; error?: string; created?: string; updated?: string; converted?: string; q?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: membershipRows } = await supabase.from("org_members").select("organization_id, role, organizations(name, slug)").eq("user_id", user.id).eq("status", "active");
  const memberships = (membershipRows ?? []) as unknown as Membership[];
  const membership = memberships.find((item) => item.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");

  let leadsQuery = supabase.from("leads").select("id, company_name, contact_name, source, stage, estimated_value, probability, next_action, converted_client_id, created_at").eq("organization_id", membership.organization_id).order("created_at", { ascending: false }).limit(100);
  const search = (params.q ?? "").trim().slice(0, 100);
  if (search) leadsQuery = leadsQuery.ilike("company_name", `%${search}%`);
  const [{ data: leads }, { data: canWrite }, { data: summaryRows }] = await Promise.all([
    leadsQuery,
    supabase.rpc("has_org_permission", { target_org: membership.organization_id, permission_key: "workspace.write" }),
    supabase.rpc("sales_summary", { target_org: membership.organization_id }),
  ]);

  const summary = summaryRows?.[0];
  const stageLabels: Record<string, string> = { new: "New", qualified: "Qualified", proposal: "Proposal", negotiation: "Negotiation", won: "Won", lost: "Lost" };

  return <main className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a>
      <div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div>
      <div className="nav-caption">WORKSPACE</div>
      <nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${membership.organization_id}`}><span>Overview</span></a><a className="nav-link active" href={`/workspace/sales?organization=${membership.organization_id}`}><span>Sales & CRM</span></a><a className="nav-link" href={`/workspace/clients?organization=${membership.organization_id}`}><span>Clients</span></a><a className="nav-link" href={`/workspace/projects?organization=${membership.organization_id}`}><span>Projects</span></a><a className="nav-link" href={`/workspace/tasks?organization=${membership.organization_id}`}><span>Tasks</span></a><a className="nav-link" href={`/workspace/finance?organization=${membership.organization_id}`}><span>Finance</span></a></nav>
      <div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div>
    </aside>
    <section className="main-area">
      <header className="topbar"><div className="breadcrumbs"><span>{orgName(membership)}</span><span className="slash">/</span><b>Sales & CRM</b><span className="live-label">Live workspace</span></div><div className="top-actions"><span className="signed-in-as">{user.email}</span></div></header>
      <div className="content-wrap">
        <section className="welcome-row"><div><div className="eyebrow">SALES WORKSPACE</div><h1>Sales & CRM</h1><p>Track leads, move deals forward, and keep next steps visible.</p></div>{canWrite && <a className="primary-button sales-create-link" href="#new-lead"><Plus size={17}/> New lead</a>}</section>
        <section className="sales-summary-grid"><article className="metric card"><div className="metric-top"><span>Open pipeline value</span></div><div className="metric-value">{money.format(Number(summary?.pipeline_value ?? 0))}</div><div className="live-metric-detail">Sum of active lead estimates</div></article><article className="metric card"><div className="metric-top"><span>Active leads</span></div><div className="metric-value">{summary?.open_lead_count ?? 0}</div><div className="live-metric-detail">Not yet won or closed</div></article><article className="metric card"><div className="metric-top"><span>In proposal</span></div><div className="metric-value">{summary?.proposal_count ?? 0}</div><div className="live-metric-detail">Waiting on a prospect decision</div></article></section>
        <section className="card leads-card"><div className="leads-heading"><div><h2>Lead pipeline</h2><p>{leads?.length ?? 0} recent leads</p></div></div>
          {params.created && <div className="success-banner">Lead created and added to this organization’s pipeline.</div>}{params.updated && <div className="success-banner">Lead stage updated.</div>}{params.converted && <div className="success-banner">Lead converted to a client and won deal. <a href={`/workspace/clients/${params.converted}?organization=${membership.organization_id}`}>Open client</a></div>}
          {params.error && <div className="auth-error">{params.error === "forbidden" ? "Your role does not have permission to create leads." : params.error === "invalid" ? "Enter a company name and a valid estimated value." : params.error === "convert" ? "Only an unconverted won lead can be converted. Check its stage and try again." : "The lead could not be saved. Please check the details and try again."}</div>}
          <form action="/workspace/sales" method="get" className="lead-search"><input type="hidden" name="organization" value={membership.organization_id}/><Search size={15}/><input name="q" aria-label="Search leads by company" placeholder="Search companies" defaultValue={search}/><button type="submit">Search</button></form>
          {leads?.length ? <div className="table-scroll"><table className="lead-table"><thead><tr><th>Company / contact</th><th>Stage</th><th>Est. value</th><th>Source</th><th>Next action</th>{canWrite && <th>Actions</th>}</tr></thead><tbody>{leads.map((lead) => <tr key={lead.id}><td><a className="sales-lead-link" href={`/workspace/sales/${lead.id}?organization=${membership.organization_id}`}><b>{lead.company_name}</b></a><small>{lead.contact_name || "Contact not added"}</small></td><td><span className={`stage-pill stage-${lead.stage}`}>{stageLabels[lead.stage] ?? lead.stage}</span></td><td>{money.format(Number(lead.estimated_value ?? 0))}</td><td>{lead.source || "—"}</td><td>{lead.next_action || "Add next step"}</td>{canWrite && <td>{lead.converted_client_id ? <a className="finance-action-button" href={`/workspace/clients/${lead.converted_client_id}?organization=${membership.organization_id}`}>Open client</a> : <div className="sales-row-actions"><form action={updateLeadStage} className="stage-form"><input type="hidden" name="organization_id" value={membership.organization_id}/><input type="hidden" name="lead_id" value={lead.id}/><select name="stage" defaultValue={lead.stage} aria-label={`Stage for ${lead.company_name}`}>{Object.entries(stageLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><button type="submit">Save</button></form>{lead.stage === "won" && <form action={convertWonLead}><input type="hidden" name="organization_id" value={membership.organization_id}/><input type="hidden" name="lead_id" value={lead.id}/><button className="finance-action-button" type="submit">Convert to client</button></form>}</div>}</td>}</tr>)}</tbody></table></div> : <div className="empty-state lead-empty"><b>{search ? "No matching leads" : "Your pipeline is clear"}</b><span>{search ? "Try a different company name." : "Add a lead to start tracking the next opportunity."}</span></div>}
        </section>
        {canWrite && <section className="card new-lead-card" id="new-lead"><div className="leads-heading"><div><h2>Create a lead</h2><p>This record will be saved inside {orgName(membership)}.</p></div></div><form action={createLead} className="lead-form"><input type="hidden" name="organization_id" value={membership.organization_id}/><label>Company name<input name="company_name" minLength={2} maxLength={140} required placeholder="Example: Northstar Fitness"/></label><label>Contact name<input name="contact_name" maxLength={140} placeholder="Primary contact"/></label><label>Email<input name="email" type="email" placeholder="contact@company.com"/></label><label>Lead source<input name="source" maxLength={100} placeholder="Referral, website, event…"/></label><label>Estimated deal value<input name="estimated_value" type="number" min="0" step="0.01" defaultValue="0"/></label><button className="primary-button" type="submit">Create lead</button></form></section>}
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Sales data is scoped to this organization</span></footer>
      </div>
    </section>
  </main>;
}
