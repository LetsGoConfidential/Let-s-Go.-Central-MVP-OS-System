"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { dateAtNineInZoneToIso } from "@/lib/dates";

async function writer(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  return { supabase, user };
}

export async function createContentItem(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const channel = String(formData.get("channel") ?? "").trim();
  const format = String(formData.get("format") ?? "post");
  const clientId = String(formData.get("client_id") ?? "").trim();
  const scheduledDate = String(formData.get("scheduled_date") ?? "").trim();
  if (!organizationId || title.length < 2 || title.length > 200 || channel.length > 80 || !["post", "story", "video", "email", "article", "other"].includes(format)) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { supabase, user } = await writer(organizationId);
  let scheduleIso: string | null = null;
  if (scheduledDate) {
    const { data: org } = await supabase.from("organizations").select("timezone").eq("id", organizationId).single();
    try { scheduleIso = dateAtNineInZoneToIso(scheduledDate, org?.timezone ?? "Asia/Kolkata"); } catch { redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=invalid`); }
  }
  if (clientId) {
    const { data: client } = await supabase.from("clients").select("id").eq("organization_id", organizationId).eq("id", clientId).maybeSingle();
    if (!client) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }
  const { error } = await supabase.from("content_items").insert({ organization_id: organizationId, title, channel: channel || null, format, client_id: clientId || null, scheduled_at: scheduleIso, status: scheduleIso ? "scheduled" : "draft", owner_id: user.id });
  if (error) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/content");
  redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&created=1`);
}

export async function updateContentStatus(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const itemId = String(formData.get("item_id") ?? "");
  const status = String(formData.get("status") ?? "");
  const scheduledDate = String(formData.get("scheduled_date") ?? "").trim();
  if (!organizationId || !itemId || !["draft", "review", "approved", "scheduled", "published"].includes(status)) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { supabase } = await writer(organizationId);
  let scheduleIso: string | null = null;
  if (scheduledDate) {
    const { data: org } = await supabase.from("organizations").select("timezone").eq("id", organizationId).single();
    try { scheduleIso = dateAtNineInZoneToIso(scheduledDate, org?.timezone ?? "Asia/Kolkata"); } catch { redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=invalid`); }
  }
  if (status === "scheduled" && !scheduleIso) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const update = { status, published_at: status === "published" ? new Date().toISOString() : null, ...(scheduledDate ? { scheduled_at: scheduleIso } : {}) };
  const { error } = await supabase.from("content_items").update(update).eq("organization_id", organizationId).eq("id", itemId);
  if (error) redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/content");
  redirect(`/workspace/content?organization=${encodeURIComponent(organizationId)}&updated=1`);
}

export async function updateContentItem(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const itemId = String(formData.get("item_id") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const format = String(formData.get("format") ?? "");
  const channel = String(formData.get("channel") ?? "").trim();
  const caption = String(formData.get("caption") ?? "").trim();
  let clientId = String(formData.get("client_id") ?? "").trim();
  const projectId = String(formData.get("project_id") ?? "").trim();
  const status = String(formData.get("status") ?? "");
  const scheduledDate = String(formData.get("scheduled_date") ?? "").trim();
  const target = `/workspace/content/${encodeURIComponent(itemId)}?organization=${encodeURIComponent(organizationId)}`;
  if (!organizationId || !itemId || title.length < 2 || title.length > 200 || channel.length > 80 || caption.length > 5000 || !["post", "story", "video", "email", "article", "other"].includes(format) || !["draft", "review", "approved", "scheduled", "published"].includes(status)) redirect(`${target}&error=invalid`);
  const { supabase } = await writer(organizationId);
  if (clientId) {
    const { data: client } = await supabase.from("clients").select("id").eq("organization_id", organizationId).eq("id", clientId).maybeSingle();
    if (!client) redirect(`${target}&error=invalid`);
  }
  if (projectId) {
    const { data: project } = await supabase.from("projects").select("id,client_id").eq("organization_id", organizationId).eq("id", projectId).maybeSingle();
    if (!project || (clientId && project.client_id && project.client_id !== clientId)) redirect(`${target}&error=invalid`);
    if (!clientId) clientId = project.client_id ?? "";
  }
  let scheduleIso: string | null = null;
  if (scheduledDate) {
    const { data: org } = await supabase.from("organizations").select("timezone").eq("id", organizationId).single();
    try { scheduleIso = dateAtNineInZoneToIso(scheduledDate, org?.timezone ?? "Asia/Kolkata"); } catch { redirect(`${target}&error=invalid`); }
  }
  if (status === "scheduled" && !scheduleIso) redirect(`${target}&error=invalid`);
  const update = {
    title, format, channel: channel || null, caption: caption || null,
    client_id: clientId || null, project_id: projectId || null, status,
    published_at: status === "published" ? new Date().toISOString() : null,
    ...(scheduledDate ? { scheduled_at: scheduleIso } : {}),
  };
  const { error } = await supabase.from("content_items").update(update).eq("organization_id", organizationId).eq("id", itemId);
  if (error) redirect(`${target}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/content"); revalidatePath(`/workspace/content/${itemId}`);
  redirect(`${target}&updated=1`);
}

export async function submitContentReview(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const itemId = String(formData.get("item_id") ?? "");
  const decision = String(formData.get("decision") ?? "");
  const feedback = String(formData.get("feedback") ?? "").trim();
  const target = `/workspace/content/${encodeURIComponent(itemId)}?organization=${encodeURIComponent(organizationId)}`;
  if (!organizationId || !itemId || !["comment", "approved", "changes_requested"].includes(decision) || feedback.length > 3000 || (decision !== "approved" && feedback.length < 2)) redirect(`${target}&error=review_invalid`);
  const { supabase } = await writer(organizationId);
  const { error } = await supabase.rpc("submit_content_review", { target_org: organizationId, target_item: itemId, review_decision: decision, review_feedback: feedback });
  if (error) redirect(`${target}&error=review_save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/content"); revalidatePath(`/workspace/content/${itemId}`);
  redirect(`${target}&reviewed=1`);
}
