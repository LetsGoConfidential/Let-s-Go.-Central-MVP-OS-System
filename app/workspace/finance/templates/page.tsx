import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createFinanceTemplateVersion } from "../actions";

type Membership = {
  organization_id: string;
  role: string;
  organizations: { name: string; slug: string } | { name: string; slug: string }[] | null;
};
type Template = {
  id: string;
  document_type: "invoice" | "quotation";
  template_key: string;
  name: string;
  version: number;
  is_default: boolean;
  is_active: boolean;
  configuration: Record<string, unknown>;
};
function orgInfo(membership: Membership) {
  return Array.isArray(membership.organizations) ? membership.organizations[0] : membership.organizations;
}

export default async function FinanceTemplatesPage({ searchParams }: {
  searchParams: Promise<{ organization?: string; created?: string; error?: string }>;
}) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: membershipRows } = await supabase.from("org_members")
    .select("organization_id,role,organizations(name,slug)").eq("user_id", user.id).eq("status", "active");
  const memberships = (membershipRows ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organization = orgInfo(membership);
  const organizationId = membership.organization_id;
  const [{ data: permission }, { data: rows }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "finance.manage" }),
    supabase.from("finance_document_templates").select("id,document_type,template_key,name,version,is_default,is_active,configuration")
      .eq("organization_id", organizationId).order("document_type").order("template_key").order("version", { ascending: false }),
  ]);
  const templates = (rows ?? []) as unknown as Template[];
  const activeTemplates = templates.filter((template) => template.is_active);
  const errorMessage = params.error === "forbidden" ? "Your role cannot manage finance templates."
    : params.error ? "The template could not be saved. Check its name and settings." : null;
  const colorOptions = ["#3474F5", "#7258D8", "#17A47B", "#E39A2E", "#192230"];

  return <main className="app-shell">
    <aside className="sidebar">
      <Link className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></Link>
      <div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{organization?.name ?? "Agency workspace"}</b><small>{membership.role}</small></span></div>
      <div className="nav-caption">WORKSPACE</div>
      <nav aria-label="Main navigation"><Link className="nav-link" href={`/workspace?organization=${organizationId}`}><span>Overview</span></Link><Link className="nav-link active" href={`/workspace/finance?organization=${organizationId}`}><span>Invoices & billing</span></Link></nav>
      <div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div></div></div>
    </aside>
    <section className="main-area">
      <header className="topbar"><div className="breadcrumbs"><span>{organization?.name ?? "Agency workspace"}</span><span className="slash">/</span><Link href={`/workspace/finance?organization=${organizationId}`}>Invoices & billing</Link><span className="slash">/</span><b>Templates</b></div><div className="top-actions"><span className="signed-in-as">{user.email}</span></div></header>
      <div id="main-content" tabIndex={-1} className="content-wrap">
        <section className="welcome-row"><div><div className="eyebrow">DOCUMENT SETTINGS</div><h1>Invoice & quotation templates</h1><p>Choose a saved format when creating a document. Each document keeps its own template version snapshot.</p></div><Link className="finance-action-button finance-template-link" href={`/workspace/finance?organization=${organizationId}`}>Back to billing</Link></section>
        {params.created && <div className="success-banner finance-message" role="status">New template version saved.</div>}
        {errorMessage && <div className="auth-error finance-message" role="alert">{errorMessage}</div>}
        <section className="card finance-list-card"><div className="leads-heading"><div><h2>Available formats</h2><p>{activeTemplates.length} active versions for this workspace · previous document snapshots remain unchanged</p></div></div>
          {templates.length ? <div className="table-scroll"><table className="lead-table finance-table"><thead><tr><th>Document</th><th>Template</th><th>Version</th><th>Style</th><th>Default</th><th>State</th></tr></thead><tbody>{templates.map((template) => <tr key={template.id}><td>{template.document_type === "invoice" ? "Invoice" : "Quotation"}</td><td><b>{template.name}</b></td><td>v{template.version}</td><td><span className="template-style-chip" style={{ borderColor: String(template.configuration.accent ?? "#dde4ef"), color: String(template.configuration.accent ?? "#526176") }}>{String(template.configuration.style ?? "clean")}</span></td><td>{template.is_active && template.is_default ? <span className="stage-pill invoice-paid">Default</span> : "—"}</td><td>{template.is_active ? "Active" : "Archived"}</td></tr>)}</tbody></table></div> : <div className="empty-state lead-empty"><b>No document templates</b><span>Default formats are created when the workspace is provisioned.</span></div>}
        </section>
        {permission && <section className="card new-lead-card template-editor-card"><div className="leads-heading"><div><h2>Create a new version</h2><p>Start from an existing format, then save a versioned visual configuration. Existing invoices and quotations keep their captured settings.</p></div></div>{activeTemplates.length ? <form action={createFinanceTemplateVersion} className="finance-form"><input type="hidden" name="organization_id" value={organizationId}/><label>Based on<select name="source_template_id" required defaultValue="">{activeTemplates.map((template) => <option key={template.id} value={template.id}>{template.document_type === "invoice" ? "Invoice" : "Quotation"} · {template.name} · v{template.version}</option>)}</select></label><label>Version name<input name="name" minLength={2} maxLength={100} required placeholder="Let’s Go. Premium Invoice"/></label><label>Accent color<select name="accent" defaultValue="#3474F5">{colorOptions.map((color) => <option key={color} value={color}>{color}</option>)}</select></label><label>Layout style<select name="style" defaultValue="clean"><option value="clean">Clean</option><option value="editorial">Editorial</option><option value="formal">Formal</option></select></label><div className="template-option-grid"><label><input type="checkbox" name="group_line_items" defaultChecked/> Group line items</label><label><input type="checkbox" name="show_tax" defaultChecked/> Show tax summary</label><label><input type="checkbox" name="show_signature" defaultChecked/> Show signature block</label><label><input type="checkbox" name="show_terms" defaultChecked/> Show terms</label><label><input type="checkbox" name="set_as_default"/> Make this the default for its document type</label></div><button className="primary-button" type="submit">Save new version</button></form> : <div className="finance-empty">No active template can be copied.</div>}</section>}
        {!permission && <div className="data-note">You can view template settings. Ask an organization admin or finance owner to create a new version.</div>}
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>GST, bank details, signatures, and legal terms still require organization review before client use.</span></footer>
      </div>
    </section>
  </main>;
}
