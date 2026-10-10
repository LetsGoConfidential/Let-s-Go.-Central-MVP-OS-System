"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function workspaceWriter(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  return { supabase, user };
}

export async function createProject(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const clientId = String(formData.get("client_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const dueDate = String(formData.get("due_date") ?? "");
  const priority = String(formData.get("priority") ?? "medium");
  const budget = Number(formData.get("budget") ?? 0);
  if (!organizationId || name.length < 2 || name.length > 180 || budget < 0 || !Number.isFinite(budget) || budget > 999999999999.99 || !["low", "medium", "high", "urgent"].includes(priority) || (dueDate && !/^\d{4}-\d{2}-\d{2}$/.test(dueDate))) {
    redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }
  const { supabase, user } = await workspaceWriter(organizationId);
  const { error } = await supabase.from("projects").insert({ organization_id: organizationId, client_id: clientId || null, name, due_date: dueDate || null, priority, budget, owner_id: user.id, created_by: user.id });
  if (error) redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/projects"); revalidatePath("/workspace/tasks");
  redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&created=1`);
}

export async function updateProjectStatus(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const projectId = String(formData.get("project_id") ?? "");
  const status = String(formData.get("status") ?? "");
  const allowedStatuses = ["planned", "in_progress", "internal_review", "client_review", "completed", "on_hold"];
  if (!organizationId || !projectId || !allowedStatuses.includes(status)) redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { supabase } = await workspaceWriter(organizationId);
  const { error } = await supabase.from("projects").update({ status }).eq("organization_id", organizationId).eq("id", projectId);
  if (error) redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/projects");
  redirect(`/workspace/projects?organization=${encodeURIComponent(organizationId)}&updated=1`);
}

export async function updateProjectDetails(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const projectId = String(formData.get("project_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const clientId = String(formData.get("client_id") ?? "");
  const status = String(formData.get("status") ?? "planned");
  const priority = String(formData.get("priority") ?? "medium");
  const startDate = String(formData.get("start_date") ?? "");
  const dueDate = String(formData.get("due_date") ?? "");
  const budget = Number(formData.get("budget") ?? 0);
  const target = `/workspace/projects/${encodeURIComponent(projectId)}?organization=${encodeURIComponent(organizationId)}`;
  const validDate = (value: string) => !value || (/^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value);
  const statusValues = ["planned", "in_progress", "internal_review", "client_review", "completed", "on_hold"];
  if (!organizationId || !projectId || name.length < 2 || name.length > 180 || description.length > 5000 || !statusValues.includes(status) || !["low", "medium", "high", "urgent"].includes(priority) || !validDate(startDate) || !validDate(dueDate) || (startDate && dueDate && dueDate < startDate) || !Number.isFinite(budget) || budget < 0 || budget > 999999999999.99) redirect(`${target}&error=invalid`);
  const { supabase } = await workspaceWriter(organizationId);
  const { error } = await supabase.from("projects").update({ name, description: description || null, client_id: clientId || null, status, priority, start_date: startDate || null, due_date: dueDate || null, budget }).eq("organization_id", organizationId).eq("id", projectId);
  if (error) redirect(`${target}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/projects"); revalidatePath(`/workspace/projects/${projectId}`); revalidatePath("/workspace/tasks"); revalidatePath("/workspace/clients");
  redirect(`${target}&updated=1`);
}
