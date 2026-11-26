"use server";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isOneOf } from "@/lib/validation";

function teamUrl(organizationId: string, result: string) {
  return `/workspace/team?organization=${encodeURIComponent(organizationId)}&${result}=1`;
}

async function authorized(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" });
  if (!allowed) redirect(teamUrl(organizationId, "forbidden"));
  return { supabase, user };
}

function adminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) return null;
  return createSupabaseClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
}

export async function inviteTeamMember(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const role = String(formData.get("role") ?? "member");
  const department = String(formData.get("department") ?? "").trim();
  const fullName = String(formData.get("full_name") ?? "").trim();
  const allowedDepartments = ["Sales", "HR", "Management", "Production", "Concept", "Operations"];
  if (!organizationId || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || fullName.length > 120 || !["admin", "manager", "member"].includes(role) || !allowedDepartments.includes(department)) {
    redirect(teamUrl(organizationId, "invalid"));
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: canManageMembers } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" });
  const { data: canInviteMembers } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "hr.people.invite" });
  if (!canManageMembers && (!canInviteMembers || role !== "member")) redirect(teamUrl(organizationId, "forbidden"));
  if (email === user.email?.toLowerCase()) redirect(teamUrl(organizationId, "self"));
  const admin = adminClient();
  if (!admin) redirect(teamUrl(organizationId, "config"));
  const { data: pending } = await supabase.from("org_invitations").select("id").eq("organization_id", organizationId).eq("email", email).eq("status", "pending").maybeSingle();
  if (pending) redirect(teamUrl(organizationId, "duplicate"));

  const { data: userPage, error: listError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (listError) redirect(teamUrl(organizationId, "invite-failed"));
  const existingUser = userPage.users.find((candidate) => candidate.email?.toLowerCase() === email);
  if (existingUser) {
    const { data: existingMembership } = await supabase.from("org_members").select("status").eq("organization_id", organizationId).eq("user_id", existingUser.id).maybeSingle();
    if (existingMembership) redirect(teamUrl(organizationId, "duplicate"));
    const { error: memberError } = await admin.from("org_members").insert({ organization_id: organizationId, user_id: existingUser.id, role, department, status: "active", joined_at: new Date().toISOString() });
    if (memberError) redirect(teamUrl(organizationId, "invite-failed"));
    await admin.from("audit_logs").insert({ organization_id: organizationId, actor_id: user.id, action: "add_existing_member", entity_type: "org_members", entity_id: existingUser.id, changes: { email, role, status: "active" } });
    revalidatePath("/workspace/team"); revalidatePath("/workspace/tasks");
    redirect(teamUrl(organizationId, "added"));
  }

  const appUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (!appUrl) redirect(teamUrl(organizationId, "config"));
  const callback = new URL("/auth/callback", appUrl);
  callback.searchParams.set("next", `/workspace?organization=${organizationId}&accept_invite=1`);
  const { data: invite, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: fullName ? { full_name: fullName } : undefined,
    redirectTo: callback.toString(),
  });
  if (inviteError || !invite.user) redirect(teamUrl(organizationId, "invite-failed"));
  const { error: storeError } = await admin.rpc("store_org_invitation", {
    target_org: organizationId,
    invite_email: email,
    invited_user: invite.user.id,
    assigned_role: role,
    actor_id: user.id,
  });
  if (storeError) redirect(teamUrl(organizationId, "store-failed"));
  const { error: departmentError } = await admin.from("org_members").update({ department }).eq("organization_id", organizationId).eq("user_id", invite.user.id).eq("status", "invited");
  if (departmentError) redirect(teamUrl(organizationId, "store-failed"));
  revalidatePath("/workspace/team");
  redirect(teamUrl(organizationId, "invited"));
}

export async function updateTeamMember(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const userId = String(formData.get("user_id") ?? "");
  const role = String(formData.get("role") ?? "");
  const status = String(formData.get("status") ?? "active");
  if (!organizationId || !userId || !isOneOf(["admin", "manager", "member"] as const, role) || !isOneOf(["active", "suspended"] as const, status)) redirect(teamUrl(organizationId, "invalid"));
  const { supabase } = await authorized(organizationId);
  const { data: updated, error } = await supabase.rpc("manage_org_member", { target_org: organizationId, target_user: userId, new_role: role, new_status: status });
  if (error || !updated) redirect(teamUrl(organizationId, "member-failed"));
  revalidatePath("/workspace/team"); revalidatePath("/workspace/tasks"); revalidatePath("/workspace");
  redirect(teamUrl(organizationId, "member-updated"));
}

export async function updateMemberDepartment(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const userId = String(formData.get("user_id") ?? "");
  const department = String(formData.get("department") ?? "").trim();
  if (!organizationId || !userId || department.length > 80 || (department.length > 0 && department.length < 2)) redirect(teamUrl(organizationId, "invalid"));
  const { supabase } = await authorized(organizationId);
  const { data: updated, error } = await supabase.rpc("set_member_department", { target_org: organizationId, target_user: userId, new_department: department || null });
  if (error || !updated) redirect(teamUrl(organizationId, "member-failed"));
  revalidatePath("/workspace/team"); revalidatePath(`/workspace/team/${userId}`);
  redirect(teamUrl(organizationId, "department-updated"));
}

export async function revokeTeamInvitation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const invitationId = String(formData.get("invitation_id") ?? "");
  if (!organizationId || !invitationId) redirect(teamUrl(organizationId, "invalid"));
  const { supabase } = await authorized(organizationId);
  const { data: revoked, error } = await supabase.rpc("revoke_org_invitation", { target_org: organizationId, invitation_id: invitationId });
  if (error || !revoked) redirect(teamUrl(organizationId, "member-failed"));
  revalidatePath("/workspace/team");
  redirect(teamUrl(organizationId, "revoked"));
}

export async function saveTeamPerformanceReview(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  const month = String(formData.get("review_month") ?? "");
  const target = `/workspace/team/${encodeURIComponent(memberId)}?organization=${encodeURIComponent(organizationId)}`;
  const period = /^\d{4}-\d{2}$/.test(month) ? `${month}-01` : "";
  const periodDate = period ? new Date(`${period}T00:00:00Z`) : null;
  const periodValid = Boolean(periodDate && Number.isFinite(periodDate.getTime()) && periodDate.toISOString().slice(0, 10) === period && Number(period.slice(5, 7)) >= 1 && Number(period.slice(5, 7)) <= 12);
  const scores = {
    delivery_score: Number(formData.get("delivery_score")),
    communication_score: Number(formData.get("communication_score")),
    ownership_score: Number(formData.get("ownership_score")),
    client_care_score: Number(formData.get("client_care_score")),
  };
  const highlights = String(formData.get("highlights") ?? "").trim();
  const growthFocus = String(formData.get("growth_focus") ?? "").trim();
  const managerNotes = String(formData.get("manager_notes") ?? "").trim();
  if (!organizationId || !memberId || !periodValid || Object.values(scores).some((score) => !Number.isInteger(score) || score < 1 || score > 5) || highlights.length > 3000 || growthFocus.length > 3000 || managerNotes.length > 3000) redirect(`${target}&error=review-invalid`);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "team.performance.manage" });
  if (!allowed) redirect(`${target}&error=review-forbidden`);
  const { data: member } = await supabase.from("org_members").select("user_id").eq("organization_id", organizationId).eq("user_id", memberId).in("status", ["active", "suspended"]).neq("role", "client").maybeSingle();
  if (!member) redirect(`${target}&error=review-invalid`);

  const { error } = await supabase.from("team_performance_reviews").upsert({
    organization_id: organizationId,
    member_id: memberId,
    updated_by: user.id,
    period_start: period,
    ...scores,
    highlights,
    growth_focus: growthFocus,
    manager_notes: managerNotes,
  }, { onConflict: "organization_id,member_id,period_start" });
  if (error) redirect(`${target}&error=review-save`);
  revalidatePath("/workspace/team"); revalidatePath(`/workspace/team/${memberId}`);
  redirect(`${target}&saved=1`);
}

export async function saveEmployeeKpiGoal(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  const metricKey = String(formData.get("metric_key") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const unit = metricKey === "tasks_on_time" ? "percent" : "count";
  const targetValue = Number(formData.get("target"));
  const periodStart = String(formData.get("period_start") ?? "");
  const periodEnd = String(formData.get("period_end") ?? "");
  const target = `/workspace/team/${encodeURIComponent(memberId)}?organization=${encodeURIComponent(organizationId)}`;
  const validDate = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
  if (!organizationId || !memberId || !["tasks_completed", "tasks_on_time", "leads_won"].includes(metricKey) || title.length < 2 || title.length > 120 || !Number.isFinite(targetValue) || targetValue <= 0 || (metricKey === "tasks_on_time" && targetValue > 100) || !validDate(periodStart) || !validDate(periodEnd) || periodEnd < periodStart) redirect(`${target}&error=kpi-invalid`);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "team.performance.manage" });
  if (!allowed) redirect(`${target}&error=kpi-forbidden`);
  const { data: member } = await supabase.from("org_members").select("user_id").eq("organization_id", organizationId).eq("user_id", memberId).in("status", ["active", "suspended"]).neq("role", "client").maybeSingle();
  if (!member) redirect(`${target}&error=kpi-invalid`);
  const { error } = await supabase.from("employee_kpi_goals").upsert({
    organization_id: organizationId, member_id: memberId,
    metric_key: metricKey as "tasks_completed" | "tasks_on_time" | "leads_won",
    title, target: targetValue, unit, period_start: periodStart, period_end: periodEnd,
    updated_by: user.id,
  }, { onConflict: "organization_id,member_id,metric_key,period_start" });
  if (error) redirect(`${target}&error=kpi-save`);
  revalidatePath("/workspace/team"); revalidatePath(`/workspace/team/${memberId}`);
  redirect(`${target}&kpi_saved=1`);
}
