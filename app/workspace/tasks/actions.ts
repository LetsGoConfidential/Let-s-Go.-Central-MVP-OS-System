"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function writer(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  return { supabase, user };
}

export async function createTask(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const projectId = String(formData.get("project_id") ?? "");
  const assigneeId = String(formData.get("assignee_id") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const priority = String(formData.get("priority") ?? "medium");
  const dueDate = String(formData.get("due_date") ?? "");
  if (!organizationId || title.length < 2 || title.length > 200 || !["low", "medium", "high", "urgent"].includes(priority) || (dueDate && !/^\d{4}-\d{2}-\d{2}$/.test(dueDate))) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { supabase, user } = await writer(organizationId);
  const { data: project } = projectId ? await supabase.from("projects").select("client_id").eq("organization_id", organizationId).eq("id", projectId).maybeSingle() : { data: null };
  const { error } = await supabase.from("tasks").insert({ organization_id: organizationId, project_id: projectId || null, client_id: project?.client_id ?? null, assignee_id: assigneeId || null, title, priority, due_at: dueDate ? `${dueDate}T23:59:00` : null, created_by: user.id });
  if (error) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/tasks"); revalidatePath("/workspace/projects");
  redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&created=1`);
}

export async function updateTaskStatus(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const taskId = String(formData.get("task_id") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!organizationId || !taskId || !["todo", "in_progress", "blocked", "done"].includes(status)) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { supabase } = await writer(organizationId);
  const { error } = await supabase.from("tasks").update({ status, completed_at: status === "done" ? new Date().toISOString() : null }).eq("organization_id", organizationId).eq("id", taskId);
  if (error) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/tasks");
  redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&updated=1`);
}

export async function assignTask(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const taskId = String(formData.get("task_id") ?? "");
  const assigneeId = String(formData.get("assignee_id") ?? "");
  if (!organizationId || !taskId) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { supabase } = await writer(organizationId);
  const { error } = await supabase.from("tasks").update({ assignee_id: assigneeId || null }).eq("organization_id", organizationId).eq("id", taskId);
  if (error) redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&error=assignee`);
  revalidatePath("/workspace"); revalidatePath("/workspace/tasks"); revalidatePath("/workspace/team");
  redirect(`/workspace/tasks?organization=${encodeURIComponent(organizationId)}&assigned=1`);
}

export async function updateTaskDetails(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const taskId = String(formData.get("task_id") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const status = String(formData.get("status") ?? "todo");
  const priority = String(formData.get("priority") ?? "medium");
  const dueDate = String(formData.get("due_date") ?? "");
  const target = `/workspace/tasks/${encodeURIComponent(taskId)}?organization=${encodeURIComponent(organizationId)}`;
  const dateValid = !dueDate || (/^\d{4}-\d{2}-\d{2}$/.test(dueDate) && Number.isFinite(Date.parse(`${dueDate}T00:00:00Z`)) && new Date(`${dueDate}T00:00:00Z`).toISOString().slice(0, 10) === dueDate);
  if (!organizationId || !taskId || title.length < 2 || title.length > 200 || description.length > 5000 || !["todo", "in_progress", "blocked", "done"].includes(status) || !["low", "medium", "high", "urgent"].includes(priority) || !dateValid) redirect(`${target}&error=invalid`);
  const { supabase } = await writer(organizationId);
  const { data: existing } = await supabase.from("tasks").select("status,completed_at").eq("organization_id", organizationId).eq("id", taskId).maybeSingle();
  if (!existing) redirect(`${target}&error=save`);
  const completedAt = status !== "done" ? null : existing.status === "done" ? existing.completed_at : new Date().toISOString();
  const { error } = await supabase.from("tasks").update({ title, description: description || null, status, priority, due_at: dueDate ? `${dueDate}T23:59:00` : null, completed_at: completedAt }).eq("organization_id", organizationId).eq("id", taskId);
  if (error) redirect(`${target}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/tasks"); revalidatePath(`/workspace/tasks/${taskId}`);
  redirect(`${target}&updated=1`);
}

export async function addTaskComment(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const taskId = String(formData.get("task_id") ?? "");
  const body = String(formData.get("body") ?? "").trim();
  const target = `/workspace/tasks/${encodeURIComponent(taskId)}?organization=${encodeURIComponent(organizationId)}`;
  if (!organizationId || !taskId || body.length < 1 || body.length > 4000) redirect(`${target}&error=comment-invalid`);
  const { supabase, user } = await writer(organizationId);
  const { error } = await supabase.from("task_comments").insert({ organization_id: organizationId, task_id: taskId, author_id: user.id, body });
  if (error) redirect(`${target}&error=comment-save`);
  revalidatePath(`/workspace/tasks/${taskId}`); revalidatePath("/workspace/audit");
  redirect(`${target}&commented=1`);
}
