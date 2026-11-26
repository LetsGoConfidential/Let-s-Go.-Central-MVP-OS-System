"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function attendanceUrl(org: string, key: string, value = "1") {
  return `/workspace/attendance?organization=${encodeURIComponent(org)}&${key}=${encodeURIComponent(value)}`;
}

export async function recordAttendance(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const actionName = String(formData.get("action_name") ?? "");
  const url = `/workspace/attendance?organization=${encodeURIComponent(organizationId)}`;
  if (!organizationId || !["check_in", "check_out"].includes(actionName)) redirect(`${url}&error=invalid`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("record_attendance", { target_org: organizationId, action_name: actionName });
  if (error) redirect(`${url}&error=attendance`);
  revalidatePath("/workspace/attendance");
  redirect(`${url}&recorded=${actionName}`);
}

export async function requestAttendanceCorrection(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const attendanceId = String(formData.get("attendance_id") ?? "");
  const checkIn = String(formData.get("proposed_check_in") ?? "");
  const checkOut = String(formData.get("proposed_check_out") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  const validLocalDateTime = (value: string) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)
    && Number.isFinite(Date.parse(`${value}:00Z`));
  if (!organizationId || !attendanceId || !validLocalDateTime(checkIn)
    || (checkOut && !validLocalDateTime(checkOut)) || reason.length < 3 || reason.length > 1000
    || (checkOut && checkOut < checkIn)) {
    redirect(attendanceUrl(organizationId, "error", "invalid-correction"));
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("submit_attendance_correction", {
    target_org: organizationId,
    target_attendance: attendanceId,
    target_check_in: checkIn,
    target_check_out: checkOut || null,
    target_reason: reason,
  });
  if (error) redirect(attendanceUrl(organizationId, "error", "correction"));
  revalidatePath("/workspace/attendance");
  redirect(attendanceUrl(organizationId, "correctionSubmitted"));
}

export async function reviewAttendanceCorrection(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const correctionId = String(formData.get("correction_id") ?? "");
  const decision = String(formData.get("decision") ?? "");
  if (!organizationId || !correctionId || !["approved", "rejected"].includes(decision)) {
    redirect(attendanceUrl(organizationId, "error", "invalid-correction"));
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: permitted } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "hr.attendance.manage" });
  if (!permitted) redirect(attendanceUrl(organizationId, "error", "forbidden"));
  const { data: changed, error } = await supabase.rpc("review_attendance_correction", {
    target_org: organizationId,
    correction_id: correctionId,
    decision,
  });
  if (error || !changed) redirect(attendanceUrl(organizationId, "error", "correction-review"));
  revalidatePath("/workspace/attendance");
  redirect(attendanceUrl(organizationId, "correctionReviewed", decision));
}
