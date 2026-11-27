import { redirect } from "next/navigation";
import { FileText, FolderOpen, ReceiptText, ChartNoAxesCombined } from "lucide-react";
import { createClient } from "@/lib/supabase/server";

type Membership = { organization_id: string; role: string; organizations: { name: string } | { name: string }[] | null };
const orgName = (row: Membership) => (Array.isArray(row.organizations) ? row.organizations[0] : row.organizations)?.name ?? "Agency workspace";

export default async function DocumentsHub({ searchParams }: { searchParams: Promise<{ organization?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: raw } = await supabase.from("org_members").select("organization_id,role,organizations(name)").eq("user_id", user.id).eq("status", "active");
  const memberships = (raw ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const orgId = membership.organization_id;
  const areas = [
    { title: "Invoices & payments", description: "Create invoices, record payments, credits and refunds.", href: `/workspace/finance?organization=${orgId}`, status: "Available", icon: ReceiptText },
    { title: "Company documents", description: "Secure organization files with tenant-scoped access.", href: `/workspace/files?organization=${orgId}`, status: "Available", icon: FolderOpen },
    { title: "Client reports", description: "Review account health and delivery reporting before sharing with clients.", href: `/workspace/reports?organization=${orgId}`, status: "Available · Review before sharing", icon: ChartNoAxesCombined },
    { title: "Quotations", description: "Quote creation, approval and conversion to invoice are planned.", href: `/workspace/finance?organization=${orgId}`, status: "Planned", icon: FileText },
    { title: "Employee contracts & HR files", description: "Private employee files with a separate HR permission and optional employee self-view.", href: `/workspace/people/documents?organization=${orgId}`, status: "Available", icon: FileText },
    { title: "Department reports", description: "Team KPI scorecards live under Team; exportable department reports are planned.", href: `/workspace/team?organization=${orgId}`, status: "Available · KPI view", icon: ChartNoAxesCombined },
  ];
  return <main className="app-shell"><aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{orgName(membership)}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${orgId}`}>Overview</a><a className="nav-link" href={`/workspace/people?organization=${orgId}`}>Attendance & Payroll</a><a className="nav-link active" href={`/workspace/documents?organization=${orgId}`}>Documents & Reports</a><a className="nav-link" href={`/workspace/team?organization=${orgId}`}>Team & KPIs</a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside><section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{orgName(membership)}</span><span className="slash">/</span><b>Documents & Reports</b><span className="live-label">Company workspace</span></div><span className="signed-in-as">{user.email}</span></header><div id="main-content" tabIndex={-1} className="content-wrap"><section className="welcome-row"><div><div className="eyebrow">COMPANY RECORDS</div><h1>Documents & Reports</h1><p>One home for finance documents, team and client reporting, and company files.</p></div><FileText size={20}/></section><section className="integration-grid">{areas.map(({ title, description, href, status, icon: Icon }) => <a className="card integration-card" href={href} key={title}><span className="metric-icon"><Icon size={18}/></span><span><b>{title}</b><small>{description}</small></span><span className={`stage-pill ${status.startsWith("Available") ? "stage-completed" : "stage-review"}`}>{status}</span></a>)}</section><div className="data-note role-note">Employee contracts and HR files use private storage, a separate “Private employee documents” role permission, and five-minute signed links. Payroll statements remain under Payroll & compensation.</div><footer className="footer"><span>© 2026 Let’s Go Central</span><span>Client-facing documents require human review before sharing</span></footer></div></section></main>;
}
