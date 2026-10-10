"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function authorized(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/automations?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  return supabase;
}

function bounce(organizationId: string, code: string): never {
  redirect(`/workspace/automations?organization=${encodeURIComponent(organizationId)}&error=${code}`);
}

export async function saveTaskAutomation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const ruleId = String(formData.get("rule_id") ?? "") || null;
  const ruleName = String(formData.get("rule_name") ?? "").trim();
  const ruleDescription = String(formData.get("rule_description") ?? "").trim();
  const taskTitle = String(formData.get("task_title") ?? "").trim();
  const taskDescription = String(formData.get("task_description") ?? "").trim();
  const taskPriority = String(formData.get("task_priority") ?? "medium");
  const triggerMode = String(formData.get("trigger_mode") ?? "manual");
  const intervalMinutes = Number(formData.get("interval_minutes") ?? 1440);
  const enabled = formData.get("enabled") === "on";
  if (!organizationId || ruleName.length < 2 || ruleName.length > 80 || taskTitle.length < 2 || taskTitle.length > 120 || taskDescription.length > 500 || !["manual", "scheduled", "lead_created"].includes(triggerMode) || (triggerMode === "scheduled" && ![60, 1440, 10080].includes(intervalMinutes))) bounce(organizationId, "invalid");
  const supabase = await authorized(organizationId);
  const { error } = await supabase.rpc("save_task_automation", {
    target_org: organizationId,
    rule_id: ruleId,
    rule_name: ruleName,
    rule_description: ruleDescription,
    task_title: taskTitle,
    task_description: taskDescription,
    task_priority: taskPriority,
    enable_rule: enabled,
    trigger_mode: triggerMode,
    interval_minutes: intervalMinutes,
  });
  if (error) bounce(organizationId, "save");
  revalidatePath("/workspace/automations");
  redirect(`/workspace/automations?organization=${encodeURIComponent(organizationId)}&saved=1`);
}

export async function setAutomationEnabled(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const ruleId = String(formData.get("rule_id") ?? "");
  const enabled = formData.get("enabled") === "true";
  if (!organizationId || !ruleId) bounce(organizationId, "invalid");
  const supabase = await authorized(organizationId);
  const { data, error } = await supabase.rpc("set_automation_enabled", { target_org: organizationId, rule_id: ruleId, enable_rule: enabled });
  if (error || !data) bounce(organizationId, "save");
  revalidatePath("/workspace/automations");
  redirect(`/workspace/automations?organization=${encodeURIComponent(organizationId)}&saved=1`);
}

export async function runTaskAutomation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const ruleId = String(formData.get("rule_id") ?? "");
  const requestKey = String(formData.get("request_key") ?? "");
  if (!organizationId || !ruleId || requestKey.length < 16) bounce(organizationId, "invalid");
  const supabase = await authorized(organizationId);
  const { error } = await supabase.rpc("run_task_automation", { target_org: organizationId, rule_id: ruleId, request_key: requestKey });
  if (error) bounce(organizationId, "run");
  revalidatePath("/workspace/automations");
  revalidatePath("/workspace/tasks");
  revalidatePath("/workspace");
  redirect(`/workspace/automations?organization=${encodeURIComponent(organizationId)}&ran=1`);
}

export async function retryAutomationRun(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const runId = String(formData.get("run_id") ?? "");
  const requestKey = String(formData.get("request_key") ?? "");
  if (!organizationId || !runId || requestKey.length < 16) bounce(organizationId, "invalid");
  const supabase = await authorized(organizationId);
  const { error } = await supabase.rpc("retry_automation_run", { target_org: organizationId, run_id: runId, request_key: requestKey });
  if (error) bounce(organizationId, "retry");
  revalidatePath("/workspace/automations");
  revalidatePath("/workspace/tasks");
  revalidatePath("/workspace");
  redirect(`/workspace/automations?organization=${encodeURIComponent(organizationId)}&ran=1`);
}
