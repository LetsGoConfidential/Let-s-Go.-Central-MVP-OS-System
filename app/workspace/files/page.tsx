import { redirect } from "next/navigation";
import { Activity, CalendarClock, FileText, FolderOpen, ListTodo, Users, WalletCards } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { deleteOrganizationFile, uploadOrganizationFile } from "./actions";

type Membership = { organization_id: string; role: string; organizations: { name: string } | { name: string }[] | null };
function fileSize(bytes: number) { return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`; }

export default async function FilesPage({ searchParams }: { searchParams: Promise<{ organization?: string; error?: string; uploaded?: string; deleted?: string }> }) {
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
  const [{ data: records }, { data: canManage }] = await Promise.all([
    supabase.from("organization_files").select("id,storage_path,original_filename,mime_type,size_bytes,uploaded_by,created_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(100),
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" }),
  ]);
  const files = await Promise.all((records ?? []).map(async (record) => {
    const { data } = await supabase.storage.from("tenant-files").createSignedUrl(record.storage_path, 300);
    return { ...record, signedUrl: data?.signedUrl ?? null };
  }));
  const errors: Record<string, string> = {
    forbidden: "Your role cannot add or remove organization files.",
    file: "Choose a supported file under 20 MB.",
    upload: "The file could not be uploaded. Check the file type and try again.",
    save: "The file was uploaded but its workspace record could not be saved. Try again.",
    missing: "That file is no longer available in this workspace.",
    delete: "The file could not be removed. Please try again.",
    invalid: "Choose a file and try again.",
  };

  return <main className="app-shell">
    <aside className="sidebar"><a className="brand" href="/workspace"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>{organization?.name ?? "Agency workspace"}</b><small>{membership.role}</small></span></div><div className="nav-caption">WORKSPACE</div><nav aria-label="Main navigation"><a className="nav-link" href={`/workspace?organization=${organizationId}`}><Activity size={17}/><span>Overview</span></a><a className="nav-link" href={`/workspace/sales?organization=${organizationId}`}><Activity size={17}/><span>Sales & CRM</span></a><a className="nav-link" href={`/workspace/clients?organization=${organizationId}`}><Users size={17}/><span>Clients</span></a><a className="nav-link" href={`/workspace/projects?organization=${organizationId}`}><FileText size={17}/><span>Projects</span></a><a className="nav-link" href={`/workspace/content?organization=${organizationId}`}><CalendarClock size={17}/><span>Content</span></a><a className="nav-link" href={`/workspace/tasks?organization=${organizationId}`}><ListTodo size={17}/><span>Tasks</span></a><a className="nav-link" href={`/workspace/team?organization=${organizationId}`}><Users size={17}/><span>Team</span></a><a className="nav-link" href={`/workspace/finance?organization=${organizationId}`}><WalletCards size={17}/><span>Finance</span></a><a className="nav-link" href={`/workspace/audit?organization=${organizationId}`}><Activity size={17}/><span>Audit history</span></a><a className="nav-link active" href={`/workspace/files?organization=${organizationId}`}><FolderOpen size={17}/><span>Files</span></a></nav><div className="sidebar-bottom"><div className="profile"><div className="avatar avatar-dark">{(user.email ?? "LG").slice(0, 2).toUpperCase()}</div><div><b>{user.email}</b><small>{membership.role}</small></div><form action="/auth/signout" method="post"><button className="signout-inline" aria-label="Sign out">↗</button></form></div></div></aside>
    <section className="main-area"><header className="topbar"><div className="breadcrumbs"><span>{organization?.name ?? "Agency workspace"}</span><span className="slash">/</span><b>Files</b><span className="live-label">Private workspace files</span></div><div className="top-actions"><span className="signed-in-as">{user.email}</span></div></header><div className="content-wrap">
      <section className="welcome-row"><div><div className="eyebrow">ORGANIZATION LIBRARY</div><h1>Files</h1><p>Keep shared project documents and references in this private workspace library.</p></div></section>
      {params.error && <div className="auth-error finance-message" role="alert">{errors[params.error] ?? errors.upload}</div>}
      {params.uploaded && <div className="success-banner finance-message">File added to this workspace.</div>}
      {params.deleted && <div className="success-banner finance-message">File removed from this workspace.</div>}
      {canManage && <section className="card file-upload-card"><div className="leads-heading"><div><h2>Add a file</h2><p>PDF, image, text, Word, Excel, or PowerPoint · up to 20 MB</p></div></div><form action={uploadOrganizationFile} className="file-upload-form" encType="multipart/form-data"><input type="hidden" name="organization_id" value={organizationId}/><input name="file" type="file" accept=".pdf,.png,.jpg,.jpeg,.webp,.txt,.docx,.xlsx,.pptx" required/><button className="primary-button" type="submit">Upload file</button></form></section>}
      <section className="card file-list-card"><div className="leads-heading"><div><h2>Workspace files</h2><p>{files.length} recent files · links expire after five minutes</p></div></div>{files.length ? <div className="table-scroll"><table className="lead-table"><thead><tr><th>File</th><th>Type</th><th>Size</th><th>Added</th><th>Actions</th></tr></thead><tbody>{files.map((file) => <tr key={file.id}><td><b>{file.original_filename}</b></td><td>{file.mime_type}</td><td>{fileSize(Number(file.size_bytes))}</td><td>{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(file.created_at))}</td><td className="file-actions">{file.signedUrl ? <a className="finance-action-button" href={file.signedUrl} target="_blank" rel="noreferrer">Open file</a> : <span>Unavailable</span>}{canManage && <form action={deleteOrganizationFile}><input type="hidden" name="organization_id" value={organizationId}/><input type="hidden" name="file_id" value={file.id}/><button className="finance-action-button file-delete-button" type="submit">Remove</button></form>}</td></tr>)}</tbody></table></div> : <div className="empty-state lead-empty"><b>No files yet</b><span>Upload a workspace document to make it available to your organization.</span></div>}</section>
      <footer className="footer"><span>LET’S GO. CENTRAL OS</span><span>Files are private and accessible only to members of this organization.</span></footer>
    </div></section>
  </main>;
}
