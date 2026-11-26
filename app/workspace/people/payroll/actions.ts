"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function payrollUrl(organizationId: string, result: string) {
  return `/workspace/people/payroll?organization=${encodeURIComponent(organizationId)}&${result}=1`;
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
