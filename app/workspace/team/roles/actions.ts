"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function rolesUrl(organizationId: string, result: string) { return `/workspace/team/roles?organization=${encodeURIComponent(organizationId)}&${result}=1`; }
async function authorize(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" });
  if (!allowed) redirect(rolesUrl(organizationId, "forbidden"));
  return supabase;
}

export async function saveCustomRole(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const permissions = {
    "workspace.write": formData.get("workspace_write") === "on",
    "finance.manage": formData.get("finance_manage") === "on",
  };
  if (!organizationId || name.length < 2 || name.length > 80) redirect(rolesUrl(organizationId, "invalid"));
  const supabase = await authorize(organizationId);
  const { error } = await supabase.rpc("save_custom_role", { target_org: organizationId, role_name: name, permission_doc: permissions });
  if (error) redirect(rolesUrl(organizationId, "save-failed"));
  revalidatePath("/workspace/team/roles"); revalidatePath("/workspace/team");
  redirect(rolesUrl(organizationId, "saved"));
}

export async function assignCustomRole(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const userId = String(formData.get("user_id") ?? "");
  const roleId = String(formData.get("role_id") ?? "");
  if (!organizationId || !userId) redirect(rolesUrl(organizationId, "invalid"));
  const supabase = await authorize(organizationId);
  const { error } = await supabase.rpc("assign_custom_role", { target_org: organizationId, target_user: userId, target_role: roleId || null });
  if (error) redirect(rolesUrl(organizationId, "assignment-failed"));
  revalidatePath("/workspace/team/roles"); revalidatePath("/workspace/team"); revalidatePath("/workspace/tasks");
  redirect(rolesUrl(organizationId, "assigned"));
}
