import { redirect } from "next/navigation";
import { Activity, CalendarClock, FileLock2, FileText, Gauge, Trash2, Users } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { deleteEmployeeDocument, uploadEmployeeDocument } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string; timezone: string } | { name: string; timezone: string }[] | null };
type Document = { id: string; organization_id: string; member_id: string; category: "contract" | "identity" | "tax" | "certificate" | "other"; original_filename: string; mime_type: string; size_bytes: number; employee_visible: boolean; uploaded_by: string | null; created_at: string };
type Employee = { user_id: string; role: string; department: string | null };
const categories = ["contract", "identity", "tax", "certificate", "other"] as const;
const categoryLabel: Record<Document["category"], string> = { contract: "Employment contract", identity: "Identity document", tax: "Tax document", certificate: "Certificate", other: "Other HR file" };
const sizeLabel = (bytes: number) => bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;

export default async function EmployeeDocumentsPage({ searchParams }: { searchParams: Promise<{ organization?: string; error?: string; uploaded?: string; deleted?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rows } = await supabase.from("org_members").select("organization_id,role,organizations(name,timezone)").eq("user_id", user.id).eq("status", "active");
  const memberships = (rows ?? []) as unknown as Membership[];
  const membership = memberships.find((item) => item.organization_id === params.organization) ?? memberships[0];
  if (!membership) redirect("/workspace");
  const organizationId = membership.organization_id;
  const organization = Array.isArray(membership.organizations) ? membership.organizations[0] : membership.organizations;
  const [{ data: canManage }, { data: documentRows }, { data: memberRows }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "hr.documents.manage" }),
    supabase.from("employee_documents").select("id,organization_id,member_id,category,original_filename,mime_type,size_bytes,employee_visible,uploaded_by,created_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(200),
    supabase.from("org_members").select("user_id,role,department").eq("organization_id", organizationId).eq("status", "active").neq("role", "client").order("created_at"),
  ]);
  const isHr = canManage === true;
  const employees = (memberRows ?? []) as Employee[];
  const employeeIds = employees.map((person) => person.user_id);
  const { data: profiles } = employeeIds.length ? await supabase.from("profiles").select("id,full_name").in("id", employeeIds) : { data: [] };
  const names = new Map((profiles ?? []).map((profile) => [profile.id, profile.full_name || "Team member"]));
  const documents = (documentRows ?? []) as unknown as Document[];
  const fileRows = await Promise.all(documents.map(async (doc) => {
    const { data } = await supabase.storage.from("employee-files").createSignedUrl(`${doc.organization_id}/${doc.member_id}/${doc.id}`, 300);
    return { ...doc, signedUrl: data?.signedUrl ?? null };
  }));
  const errors: Record<string, string> = {
    forbidden: "Your role cannot manage employee documents.",
    invalid: "Choose an active employee and a supported document type.",
    file: "Choose a PDF, image, text, or Word file under 20 MB.",
    save: "The document record could not be created. Check that the employee is active.",
    upload: "The file could not be uploaded. The incomplete document record was removed.",
    delete: "The document could not be deleted. Please refresh and try again.",
  };
  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{organization?.name ?? "Agency workspace"}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}><Activity size={17}/><span>Overview</span></a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}>My tasks</a><a className="nav-link" href={`/workspace/team?organization=${organizationId}`}><Users size={17}/><span>Team & KPIs</span></a><a className="nav-link active" href={`/workspace/people?organization=${organizationId}`}><CalendarClock size={17}/><span>Attendance & Payroll</span></a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><a href={`/workspace/people?organization=${organizationId}`}>Attendance & Payroll</a><span className="slash">/</span><b>Employee documents</b><span className="live-label">Private HR files</span></div><span className="signed-in-as">{user.email}</span></header><div id="main-content" tabIndex={-1} className="content-wrap">
      <section className="welcome-row"><div><div className="eyebrow">HR RECORDS</div><h1>Employee documents</h1><p>Contracts and HR files stay in a private bucket. Team access requires a separate HR document permission.</p></div><FileLock2 size={22}/></section>
      {params.error && <div className="auth-error finance-message" role="alert">{errors[params.error] ?? errors.invalid}</div>}
      {params.uploaded && <div className="success-banner finance-message" role="status">Employee document uploaded successfully.</div>}
      {params.deleted && <div className="success-banner finance-message" role="status">Employee document and stored file deleted.</div>}
      {isHr && <section className="card new-lead-card"><div className="leads-heading"><div><h2>Add an employee document</h2><p>PDF, image, text, or Word · up to 20 MB. Employee visibility can be enabled per document.</p></div><FileText size={18}/></div><form action={uploadEmployeeDocument} className="lead-form" encType="multipart/form-data"><input type="hidden" name="organization_id" value={organizationId}/><label>Employee<select name="member_id" required defaultValue=""><option value="" disabled>Select employee</option>{employees.map((person) => <option key={person.user_id} value={person.user_id}>{names.get(person.user_id) ?? "Team member"}{person.department ? ` · ${person.department}` : ""}</option>)}</select></label><label>Document type<select name="category" defaultValue="contract">{categories.map((category) => <option key={category} value={category}>{categoryLabel[category]}</option>)}</select></label><label>File<input name="file" type="file" accept=".pdf,.png,.jpg,.jpeg,.webp,.txt,.docx" required/></label><label className="role-check"><input name="employee_visible" type="checkbox"/> Let this employee view and download this file</label><button className="primary-button" type="submit">Upload private file</button></form></section>}
      <section className="card leads-card"><div className="leads-heading"><div><h2>{isHr ? "HR document register" : "My HR documents"}</h2><p>{fileRows.length} visible document{fileRows.length === 1 ? "" : "s"} · secure links expire after five minutes</p></div><FileLock2 size={18}/></div>{fileRows.length ? <div className="table-scroll"><table className="lead-table"><thead><tr>{isHr && <th>Employee</th>}<th>Document</th><th>Category</th><th>Employee access</th><th>Size</th><th>Added</th><th>Actions</th></tr></thead><tbody>{fileRows.map((doc) => <tr key={doc.id}>{isHr && <td><b>{names.get(doc.member_id) ?? "Team member"}</b><small>{employees.find((person) => person.user_id === doc.member_id)?.department ?? "Unassigned"}</small></td>}<td><b>{doc.original_filename}</b></td><td>{categoryLabel[doc.category]}</td><td><span className={`stage-pill ${doc.employee_visible ? "stage-completed" : "stage-review"}`}>{doc.employee_visible ? "Visible to employee" : "HR only"}</span></td><td>{sizeLabel(Number(doc.size_bytes))}</td><td>{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: organization?.timezone || "Asia/Kolkata" }).format(new Date(doc.created_at))}</td><td className="file-actions">{doc.signedUrl ? <a className="finance-action-button" href={doc.signedUrl} target="_blank" rel="noreferrer">Open file</a> : <span>Unavailable</span>}{isHr && <form action={deleteEmployeeDocument}><input type="hidden" name="organization_id" value={organizationId}/><input type="hidden" name="document_id" value={doc.id}/><button className="finance-action-button file-delete-button" type="submit" aria-label={`Delete ${doc.original_filename}`}><Trash2 size={14}/> Delete</button></form>}</td></tr>)}</tbody></table></div> : <div className="empty-state lead-empty"><b>No documents available</b><span>{isHr ? "Use the secure upload panel to add a contract or HR file." : "Your HR team has not shared any employee documents with you yet."}</span></div>}</section>
      <section className="card leads-card"><div className="leads-heading"><div><h2>Privacy and access</h2><p>Owners/admins can manage records. Other roles need an explicit “Private employee documents” grant. Employees only see files HR has marked visible; managers do not receive team document access by default.</p></div><Gauge size={18}/></div></section>
      <footer className="footer"><span>LET’S GO. CENTRAL OS</span><span>Private HR files are separate from shared company documents</span></footer>
    </div></section>
  </main>;
}
