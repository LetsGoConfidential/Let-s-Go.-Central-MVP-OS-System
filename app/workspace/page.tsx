import { redirect } from "next/navigation";
import { Activity, BadgeIndianRupee, BarChart3, Bot, CalendarClock, CircleAlert, FileText, ListTodo, Users, WalletCards } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { createWorkspace } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string; slug: string } | { name: string; slug: string }[] | null };

function organizationName(membership: Membership) {
  const relation = membership.organizations;
  return Array.isArray(relation) ? relation[0]?.name ?? "Agency workspace" : relation?.name ?? "Agency workspace";
}

function Metric({ label, value, detail, icon: Icon }: { label: string; value: number; detail: string; icon: typeof Users }) {
  return <article className="metric card"><div className="metric-top"><span>{label}</span><span className="metric-icon"><Icon size={17} /></span></div><div className="metric-value">{value}</div><div className="live-metric-detail">{detail}</div></article>;
}

export default async function WorkspacePage({ searchParams }: { searchParams: Promise<{ organization?: string; onboarding?: string; welcome?: string }> }) {
  const { organization: requestedOrg, onboarding, welcome } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: membershipRows } = await supabase
    .from("org_members")
    .select("organization_id, role, organizations(name, slug)")
    .eq("user_id", user.id)
    .eq("status", "active");
  const memberships = (membershipRows ?? []) as unknown as Membership[];
  const activeMembership = memberships.find((membership) => membership.organization_id === requestedOrg) ?? memberships[0];

  if (!activeMembership) {
    const onboardingError = onboarding === "slug-taken" ? "That workspace address is already in use. Choose another one." : onboarding === "invalid" ? "Enter a workspace name and a valid address (lowercase letters, numbers, and hyphens)." : onboarding ? "We couldn’t create the workspace. Please retry." : null;
    return <main className="workspace-gate"><div className="workspace-panel onboarding-panel"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span><div className="eyebrow onboarding-eyebrow">YOUR AGENCY WORKSPACE</div><h1>Create your workspace</h1><p>You’re signed in as <b>{user.email}</b>. Set up an organization to start managing your clients, delivery, team, and finances.</p>{onboardingError && <div className="auth-error onboarding-error" role="alert">{onboardingError}</div>}<form action={createWorkspace} className="onboarding-form"><label htmlFor="organization_name">Workspace name<input id="organization_name" name="organization_name" required minLength={2} maxLength={100} placeholder="Let’s Go Digitals"/></label><label htmlFor="organization_slug">Workspace address <small>Lowercase letters, numbers, and hyphens. Leave blank to create one from the name.</small><input id="organization_slug" name="organization_slug" minLength={3} maxLength={60} pattern="[a-z0-9]+(-[a-z0-9]+)*" placeholder="lets-go-digitals"/></label><button className="primary-button" type="submit">Create workspace</button></form><p className="onboarding-footnote">You’ll become the owner. You can invite your team from workspace settings.</p><form action="/auth/signout" method="post"><button className="signout-button">Sign out</button></form></div></main>;
  }

  const orgId = activeMembership.organization_id;
  const [clients, openLeads, projects, openTasks, overdueTasks, reviewContent, riskProjects, audit, finance, financeTrend, receivablesAging] = await Promise.all([
    supabase.from("clients").select("id", { count: "exact", head: true }).eq("organization_id", orgId).eq("status", "active"),
    supabase.from("leads").select("id", { count: "exact", head: true }).eq("organization_id", orgId).not("stage", "in", "(won,lost)"),
    supabase.from("projects").select("id", { count: "exact", head: true }).eq("organization_id", orgId).in("status", ["planned", "in_progress", "internal_review", "client_review"]),
    supabase.from("tasks").select("id", { count: "exact", head: true }).eq("organization_id", orgId).neq("status", "done"),
    supabase.from("tasks").select("id", { count: "exact", head: true }).eq("organization_id", orgId).neq("status", "done").lt("due_at", new Date().toISOString()),
    supabase.from("content_items").select("id", { count: "exact", head: true }).eq("organization_id", orgId).eq("status", "review"),
    supabase.from("projects").select("id", { count: "exact", head: true }).eq("organization_id", orgId).in("status", ["in_progress", "internal_review", "client_review"]).lte("due_date", new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10)),
    supabase.from("audit_logs").select("id, action, entity_type, entity_id, created_at").eq("organization_id", orgId).order("created_at", { ascending: false }).limit(5),
    supabase.rpc("finance_summary", { target_org: orgId }),
    supabase.rpc("finance_monthly_trend", { target_org: orgId, month_count: 6 }),
    supabase.rpc("receivables_aging", { target_org: orgId }),
  ]);

  const orgName = organizationName(activeMembership);
  const metrics = [
    { label: "Active clients", value: clients.count ?? 0, detail: "Current customer accounts", icon: Users },
    { label: "Open sales leads", value: openLeads.count ?? 0, detail: "Not yet won or closed", icon: Activity },
    { label: "Active projects", value: projects.count ?? 0, detail: "Across your client work", icon: FileText },
    { label: "Open tasks", value: openTasks.count ?? 0, detail: "Work still in progress", icon: ListTodo },
  ];

  return <main className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="/"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a>
      {memberships.length > 1 ? <form action="/workspace" className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName}</b><small>{activeMembership.role}</small></span><select className="org-picker" aria-label="Switch workspace" name="organization" defaultValue={orgId}>{memberships.map((membership) => <option value={membership.organization_id} key={membership.organization_id}>{organizationName(membership)}</option>)}</select><button className="org-switch-button" aria-label="Open selected workspace">↗</button></form> : <div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName}</b><small>{activeMembership.role}</small></span></div>}
      <div className="nav-caption">WORKSPACE</div>
      <nav aria-label="Main navigation"><a className="nav-link active" href={`/workspace?organization=${orgId}`}><Activity size={17}/><span>Overview</span></a><a className="nav-link" href={`/workspace/sales?organization=${orgId}`}><Activity size={17}/><span>Sales & CRM</span></a><a className="nav-link" href={`/workspace/clients?organization=${orgId}`}><Users size={17}/><span>Clients</span></a><a className="nav-link" href={`/workspace/projects?organization=${orgId}`}><FileText size={17}/><span>Projects</span></a><a className="nav-link" href={`/workspace/content?organization=${orgId}`}><CalendarClock size={17}/><span>Content</span></a><a className="nav-link" href={`/workspace/tasks?organization=${orgId}`}><ListTodo size={17}/><span>Tasks</span></a><a className="nav-link" href={`/workspace/team?organization=${orgId}`}><Users size={17}/><span>Team</span></a><a className="nav-link" href={`/workspace/finance?organization=${orgId}`}><WalletCards size={17}/><span>Finance</span></a><a className="nav-link" href={`/workspace/reports?organization=${orgId}`}><BarChart3 size={17}/><span>Reports</span></a><a className="nav-link" href={`/workspace/audit?organization=${orgId}`}><Activity size={17}/><span>Audit history</span></a><a className="nav-link" href={`/workspace/files?organization=${orgId}`}><FileText size={17}/><span>Files</span></a><a className="nav-link" href={`/workspace/integrations?organization=${orgId}`}><Users size={17}/><span>Integrations</span></a><a className="nav-link" href={`/workspace/automations?organization=${orgId}`}><Activity size={17}/><span>Automations</span></a><a className="nav-link" href={`/workspace/ai?organization=${orgId}`}><Bot size={17}/><span>AI Command Center</span></a></nav>
      <div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{activeMembership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline">↗</button></form></div></div>
    </aside>
    <section className="main-area">
      <header className="topbar"><div className="breadcrumbs"><span>{orgName}</span><span className="slash">/</span><b>Overview</b><span className="live-label">Live workspace</span></div><div className="top-actions"><span className="signed-in-as">{user.email}</span></div></header>
      <div className="content-wrap">
        <section className="welcome-row"><div><div className="eyebrow">FOUNDER DASHBOARD</div><h1>{orgName}</h1><p>{welcome ? "Your workspace is ready. Start by adding a client, lead, or team member." : "Here’s a live view of the work in your agency workspace."}</p></div></section>
        <section className="metrics-grid" aria-label="Live workspace overview">{metrics.map((metric) => <Metric key={metric.label} {...metric}/>)}</section>
        <section className="finance-live-section"><div className="live-section-heading"><h2>Finance this month</h2><a href={`/workspace/finance?organization=${orgId}`}>Open finance →</a></div>{finance.data?.length ? <div className="finance-live-grid">{finance.data.map((row) => {const format = new Intl.NumberFormat("en-IN", { style: "currency", currency: row.currency.trim(), maximumFractionDigits: 0 }); return <article className="card finance-live-card" key={row.currency}><div className="finance-currency">{row.currency.trim()}</div><div className="finance-live-values"><div><span>Revenue</span><b>{format.format(Number(row.monthly_revenue))}</b></div><div><span>Receivables</span><b>{format.format(Number(row.receivables))}</b></div><div><span>Expenses</span><b>{format.format(Number(row.monthly_expenses))}</b></div><div><span>Est. profit</span><b>{format.format(Number(row.estimated_profit))}</b></div></div></article>;})}</div> : <div className="finance-empty">Finance totals will appear when invoices and expenses are recorded. No preview amounts are shown in this signed-in workspace.</div>}</section>
        <section className="founder-finance-reports"><article className="card finance-list-card"><div className="leads-heading"><div><h2>Six-month cash flow</h2><p>Monthly payments received less recorded expenses</p></div><a href={`/workspace/finance?organization=${orgId}`}>View detail →</a></div>{financeTrend.data?.length ? <div className="founder-trend">{Array.from(new Set(financeTrend.data.map((row) => row.currency.trim()))).map((currency) => { const rows = financeTrend.data.filter((row) => row.currency.trim() === currency); const max = Math.max(1, ...rows.flatMap((row) => [Number(row.revenue), Number(row.expenses)])); return <div className="founder-trend-currency" key={currency}><span className="finance-currency">{currency}</span><div className="founder-trend-bars">{rows.map((row) => <div className="founder-month" key={row.month_start} title={`${new Date(`${row.month_start}T12:00:00`).toLocaleDateString("en-IN", { month: "long", year: "numeric" })}: received ${Number(row.revenue)}, expenses ${Number(row.expenses)}`}><div className="founder-bar-pair"><i className="revenue-bar" style={{ height: `${Math.max(Number(row.revenue) > 0 ? 3 : 0, Number(row.revenue) / max * 100)}%` }}/><i className="expense-bar" style={{ height: `${Math.max(Number(row.expenses) > 0 ? 3 : 0, Number(row.expenses) / max * 100)}%` }}/></div><small>{new Date(`${row.month_start}T12:00:00`).toLocaleDateString("en-IN", { month: "short" })}</small></div>)}</div></div>; })}<div className="trend-legend"><span><i className="revenue-key"/> Received</span><span><i className="expense-key"/> Expenses</span></div></div> : <p className="finance-empty">Apply the finance reporting migration to show cash-flow trends.</p>}</article><article className="card finance-list-card"><div className="leads-heading"><div><h2>Receivables aging</h2><p>Outstanding balances grouped by currency</p></div><a href={`/workspace/finance?organization=${orgId}`}>View detail →</a></div>{receivablesAging.data?.length ? <div className="aging-groups">{Array.from(new Set(receivablesAging.data.map((row) => row.currency.trim()))).map((currency) => { const format = new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 0 }); const total = receivablesAging.data.filter((row) => row.currency.trim() === currency).reduce((sum, row) => sum + Number(row.amount), 0); return <div className="aging-row founder-aging-row" key={currency}><span><b>{currency}</b><small>{receivablesAging.data.filter((row) => row.currency.trim() === currency).reduce((sum, row) => sum + Number(row.invoice_count), 0)} open invoices</small></span><strong>{format.format(total)}</strong></div>; })}</div> : <p className="finance-empty">No outstanding issued invoices.</p>}</article></section>
        <section className="attention card"><div className="section-heading"><div className="heading-icon warning"><CircleAlert size={18}/></div><div><h2>Needs your attention</h2><p>Items that may need a follow-up.</p></div></div><div className="attention-list live-attention">
          <div className="attention-item"><span className="status-dot amber"/><div><b>{overdueTasks.count ?? 0} overdue tasks</b><small>Open tasks past their due date</small></div></div>
          <div className="attention-item"><span className="status-dot blue"/><div><b>{reviewContent.count ?? 0} content items in review</b><small>Waiting for an approval decision</small></div></div>
          <div className="attention-item"><span className="status-dot rose"/><div><b>{riskProjects.count ?? 0} projects due within 48 hours</b><small>Active delivery work close to its due date</small></div></div>
        </div></section>
        <section className="lower-grid live-lower-grid">
          <article className="card activity-card live-card"><div className="card-heading"><div><h2>Recent activity</h2><p>Latest changes recorded in this workspace</p></div><a className="finance-action-button" href={`/workspace/audit?organization=${orgId}`}>View audit history</a></div>
            {audit.data?.length ? <div className="activity-list">{audit.data.map((event) => <div className="activity-item" key={event.id}><div className="avatar avatar-blue">LG</div><div className="activity-copy"><p><b>{event.action}</b> · {event.entity_type.replaceAll("_", " ")}{event.entity_id ? ` #${event.entity_id.slice(0, 8)}` : ""}</p><small>{new Date(event.created_at).toLocaleString()}</small></div></div>)}</div> : <p className="empty-state">No recent activity yet. Changes to clients, leads, projects, tasks, content, and invoices will appear here.</p>}
          </article>
          <article className="card activity-card live-card"><div className="card-heading"><div><h2>Workspace status</h2><p>Live records, protected by organization membership</p></div></div><div className="workspace-status"><div><span>Organization</span><b>{orgName}</b></div><div><span>Your role</span><b>{activeMembership.role}</b></div><div><span>Data source</span><b>Supabase · PostgreSQL</b></div></div><p className="data-note">Financial totals and reports will appear once invoice payment records and expense entries are connected to the dashboard.</p></article>
        </section>
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Live organization-scoped workspace</span></footer>
      </div>
    </section>
  </main>;
}
