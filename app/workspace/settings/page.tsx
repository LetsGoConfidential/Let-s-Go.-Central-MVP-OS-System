import { redirect } from "next/navigation";
import { Activity, CalendarClock, CircleDollarSign, FileText, ListTodo, Settings2, Users, WalletCards } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { supportedCurrencies } from "@/lib/organization/currencies";
import { saveOrganizationSettings } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string } | { name: string }[] | null };
type Organization = { id: string; name: string; legal_name: string | null; timezone: string; currency: string };

export default async function OrganizationSettingsPage({ searchParams }: { searchParams: Promise<{ organization?: string; error?: string; saved?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rows } = await supabase.from("org_members").select("organization_id,role,organizations(name)").eq("user_id", user.id).eq("status", "active");
  const memberships = (rows ?? []) as unknown as Membership[];
  const membership = memberships.find((row) => row.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organizationId = membership.organization_id;
  const [{ data: organizationRow }, { data: canManage }] = await Promise.all([
    supabase.from("organizations").select("id,name,legal_name,timezone,currency").eq("id", organizationId).maybeSingle(),
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" }),
  ]);
  if (!organizationRow) redirect("/workspace");
  const organization = organizationRow as Organization;
  const errorMessages: Record<string, string> = {
    invalid: "Check the workspace name, timezone, and supported currency.",
    forbidden: "Your role cannot manage workspace settings.",
    save: "The settings could not be saved. Confirm your timezone is a valid IANA timezone, such as Asia/Kolkata.",
  };
  const message = params.error ? errorMessages[params.error] : undefined;
  const currencyIsSupported = supportedCurrencies.includes(organization.currency as typeof supportedCurrencies[number]);
  const currencyOptions = currencyIsSupported ? [...supportedCurrencies] : [organization.currency, ...supportedCurrencies];
  const membershipOrg = Array.isArray(membership.organizations) ? membership.organizations[0] : membership.organizations;

  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{organization.name}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}><Activity size={17}/><span>Overview</span></a><a className="nav-link" href={`/workspace/sales?organization=${organizationId}`}><Activity size={17}/><span>Sales & CRM</span></a><a className="nav-link" href={`/workspace/clients?organization=${organizationId}`}><Users size={17}/><span>Clients</span></a><a className="nav-link" href={`/workspace/projects?organization=${organizationId}`}><FileText size={17}/><span>Projects</span></a><a className="nav-link" href={`/workspace/content?organization=${organizationId}`}><CalendarClock size={17}/><span>Content</span></a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}><ListTodo size={17}/><span>Tasks</span></a><a className="nav-link" href={`/workspace/team?organization=${organizationId}`}><Users size={17}/><span>Team</span></a><a className="nav-link" href={`/workspace/finance?organization=${organizationId}`}><WalletCards size={17}/><span>Finance</span></a><a className="nav-link" href={`/workspace/audit?organization=${organizationId}`}><Activity size={17}/><span>Audit history</span></a><a className="nav-link active" aria-current="page" href={`/workspace/settings?organization=${organizationId}`}><Settings2 size={17}/><span>Workspace settings</span></a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{membershipOrg?.name ?? organization.name}</span><span className="slash">/</span><b>Workspace settings</b><span className="live-label">Organization</span></div><span className="signed-in-as">{user.email}</span></header><div id="main-content" tabIndex={-1} className="content-wrap settings-content-wrap">
      <section className="welcome-row"><div><div className="eyebrow">ORGANIZATION</div><h1>Workspace settings</h1><p>Manage your organization identity and the defaults used across workspace dates and finances.</p></div><a className="back-link" href={`/workspace/team?organization=${organizationId}`}>← Back to team</a></section>
      {params.saved && <div className="success-banner" role="status">Workspace settings updated and recorded in audit history.</div>}
      {message && <div className="auth-error" role="alert">{message}</div>}
      <section className="card organization-settings-card"><div className="leads-heading"><div><h2>Organization profile</h2><p>Timezone controls date-based workflows. Currency labels financial values; it does not convert them.</p></div><Settings2 size={17}/></div>
        {canManage ? <form action={saveOrganizationSettings} className="organization-settings-form"><input type="hidden" name="organization_id" value={organizationId}/><label>Workspace name<input name="name" required minLength={2} maxLength={100} defaultValue={organization.name}/></label><label>Legal name <small>Optional; for official organization identity</small><input name="legal_name" maxLength={160} defaultValue={organization.legal_name ?? ""}/></label><label>Timezone <small>Use an IANA timezone such as Asia/Kolkata</small><input name="timezone" required maxLength={100} defaultValue={organization.timezone}/></label><label>Default currency <small>Choose the currency used by the organization; values are never converted</small><select name="currency" defaultValue={organization.currency}>{currencyOptions.map((currency) => <option key={currency} value={currency}>{currency}{currency === organization.currency && !currencyIsSupported ? " (current, unsupported)" : ""}</option>)}</select></label><div className="organization-settings-footer"><span>Changes apply to every member of this workspace.</span><button className="primary-button" type="submit">Save settings</button></div></form> : <div className="performance-restricted"><Settings2 size={18}/><b>Workspace settings are restricted</b><span>Ask an organization owner or admin to update this information.</span></div>}
      </section>
      <div className="integration-note"><CircleDollarSign size={18}/><span><b>Review before changing the currency.</b> Leads, deals, and project budgets store numeric amounts without their own currency code, so a change also updates how those existing amounts are labeled. No amounts are converted. Invoices and expenses keep their recorded currency.</span></div>
      <footer className="footer"><span>LET’S GO. CENTRAL OS</span><span>Organization changes appear in audit history.</span></footer>
    </div></section>
  </main>;
}
