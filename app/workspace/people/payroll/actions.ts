"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function payrollUrl(organizationId: string, result: string) {
  return `/workspace/people/payroll?organization=${encodeURIComponent(organizationId)}&${result}=1`;
}

function payrollRunUrl(organizationId: string, result: string, runId?: string) {
  const query = new URLSearchParams({ organization: organizationId, [result]: "1" });
  if (runId) query.set("run", runId);
  return `/workspace/people/payroll?${query.toString()}`;
}

export async function saveCompensation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  const effectiveFrom = String(formData.get("effective_from") ?? "");
  const monthlyBase = Number(formData.get("monthly_base"));
  const monthlyAllowance = Number(formData.get("monthly_allowance") || 0);
  const monthlyBonusTarget = Number(formData.get("monthly_bonus_target") || 0);
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const reason = String(formData.get("change_reason") ?? "").trim();
  if (!organizationId || !memberId || !/^\d{4}-\d{2}-\d{2}$/.test(effectiveFrom)
    || ![monthlyBase, monthlyAllowance, monthlyBonusTarget].every((value) => Number.isFinite(value) && value >= 0)
    || !/^[A-Z]{3}$/.test(currency) || reason.length < 3 || reason.length > 500) {
    redirect(payrollUrl(organizationId, "invalid"));
  }

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("set_employee_compensation", {
    target_org: organizationId,
    target_member: memberId,
    target_effective_from: effectiveFrom,
    target_monthly_base: monthlyBase,
    target_monthly_allowance: monthlyAllowance,
    target_monthly_bonus_target: monthlyBonusTarget,
    target_currency: currency,
    target_reason: reason,
  });
  if (error) redirect(payrollUrl(organizationId, error.code === "42501" ? "forbidden" : "save-failed"));
  revalidatePath("/workspace/people/payroll");
  revalidatePath("/workspace/people");
  redirect(payrollUrl(organizationId, "saved"));
}

export async function createPayrollRun(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const period = String(formData.get("period") ?? "");
  if (!organizationId || !/^\d{4}-(0[1-9]|1[0-2])$/.test(period)) redirect(payrollUrl(organizationId, "invalid-period"));
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: runId, error } = await supabase.rpc("create_payroll_run", {
    target_org: organizationId,
    target_period_start: `${period}-01`,
  });
  if (error) redirect(payrollRunUrl(organizationId, error.code === "42501" ? "forbidden" : error.code === "23505" ? "duplicate" : "run-failed"));
  if (!runId) redirect(payrollUrl(organizationId, "run-failed"));
  revalidatePath("/workspace/people/payroll");
  redirect(payrollRunUrl(organizationId, "run-created", runId));
}

export async function updatePayrollEntry(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const runId = String(formData.get("run_id") ?? "");
  const entryId = String(formData.get("entry_id") ?? "");
  const bonusPaid = Number(formData.get("bonus_paid") || 0);
  const additions = Number(formData.get("other_additions") || 0);
  const deductions = Number(formData.get("deductions") || 0);
  const note = String(formData.get("adjustment_note") ?? "").trim();
  if (!organizationId || !runId || !entryId || ![bonusPaid, additions, deductions].every((value) => Number.isFinite(value) && value >= 0) || note.length > 500) {
    redirect(payrollRunUrl(organizationId, "invalid-adjustment", runId));
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("update_payroll_entry", {
    target_org: organizationId,
    target_entry: entryId,
    target_bonus_paid: bonusPaid,
    target_other_additions: additions,
    target_deductions: deductions,
    target_adjustment_note: note,
  });
  if (error) redirect(payrollRunUrl(organizationId, error.code === "42501" ? "forbidden" : "adjustment-failed", runId));
  revalidatePath("/workspace/people/payroll");
  redirect(payrollRunUrl(organizationId, "adjustment-saved", runId));
}

export async function transitionPayrollRun(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const runId = String(formData.get("run_id") ?? "");
  const decision = String(formData.get("decision") ?? "");
  if (!organizationId || !runId || !["approve", "mark_paid"].includes(decision)) redirect(payrollRunUrl(organizationId, "invalid-transition", runId));
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: changed, error } = await supabase.rpc("transition_payroll_run", {
    target_org: organizationId,
    target_run: runId,
    decision,
  });
  if (error || !changed) redirect(payrollRunUrl(organizationId, error?.code === "42501" ? "forbidden" : "transition-failed", runId));
  revalidatePath("/workspace/people/payroll");
  revalidatePath("/workspace/people/payroll/statements");
  redirect(payrollRunUrl(organizationId, decision === "approve" ? "approved" : "paid", runId));
}
