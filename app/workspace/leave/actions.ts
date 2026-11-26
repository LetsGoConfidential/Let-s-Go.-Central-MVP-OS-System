"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function leaveUrl(org: string, state: string) { return `/workspace/leave?organization=${encodeURIComponent(org)}&${state}=1`; }

export async function requestLeave(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const leaveType = String(formData.get("leave_type") ?? "");
  const start = String(formData.get("start_date") ?? "");
  const end = String(formData.get("end_date") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  const validDate = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
  if (!organizationId || !["Annual", "Sick", "Personal", "Unpaid", "Other"].includes(leaveType) || !validDate(start) || !validDate(end) || end < start || reason.length > 2000) redirect(leaveUrl(organizationId, "invalid"));
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.from("leave_requests").insert({ organization_id: organizationId, member_id: user.id, leave_type: leaveType, start_date: start, end_date: end, reason });
  if (error) redirect(leaveUrl(organizationId, "save-failed"));
  revalidatePath("/workspace/leave");
  redirect(leaveUrl(organizationId, "requested"));
}

export async function reviewLeaveRequest(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const requestId = String(formData.get("request_id") ?? "");
  const decision = String(formData.get("decision") ?? "");
  if (!organizationId || !requestId || !["approved", "rejected"].includes(decision)) redirect(leaveUrl(organizationId, "invalid"));
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: permitted } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "hr.leave.manage" });
  if (!permitted) redirect(leaveUrl(organizationId, "forbidden"));
  const { data: changed, error } = await supabase.rpc("review_leave_request", { target_org: organizationId, request_id: requestId, decision });
  if (error || !changed) redirect(leaveUrl(organizationId, "review-failed"));
  revalidatePath("/workspace/leave");
  redirect(leaveUrl(organizationId, decision));
}
