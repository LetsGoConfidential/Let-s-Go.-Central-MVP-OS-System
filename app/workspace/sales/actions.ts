"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { dateAtNineInZoneToIso } from "@/lib/dates";

export async function createLead(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const organizationId = String(formData.get("organization_id") ?? "");
  const companyName = String(formData.get("company_name") ?? "").trim();
  const contactName = String(formData.get("contact_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const source = String(formData.get("source") ?? "").trim();
  const estimatedValue = Number(formData.get("estimated_value") ?? 0);

  const emailIsValid = !email || (email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email));
  if (!organizationId || companyName.length < 2 || companyName.length > 140 || contactName.length > 140 || source.length > 100 || !emailIsValid || !Number.isFinite(estimatedValue) || estimatedValue < 0 || estimatedValue > 999999999999.99) {
    redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }

  const { data: canWrite } = await supabase.rpc("has_org_permission", {
    target_org: organizationId,
    permission_key: "workspace.write",
  });
  if (!canWrite) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=forbidden`);

  const { error } = await supabase.from("leads").insert({
    organization_id: organizationId,
    company_name: companyName,
    contact_name: contactName || null,
    email: email || null,
    source: source || null,
    stage: "new",
    estimated_value: estimatedValue,
    owner_id: user.id,
    probability: 10,
  });
  if (error) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=save`);

  revalidatePath("/workspace");
  revalidatePath("/workspace/sales");
  redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&created=1`);
}

export async function updateLeadStage(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const organizationId = String(formData.get("organization_id") ?? "");
  const leadId = String(formData.get("lead_id") ?? "");
  const stage = String(formData.get("stage") ?? "");
  const allowedStages = ["new", "qualified", "proposal", "negotiation", "won", "lost"];
  if (!organizationId || !leadId || !allowedStages.includes(stage)) {
    redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }

  const { data: canWrite } = await supabase.rpc("has_org_permission", {
    target_org: organizationId,
    permission_key: "workspace.write",
  });
  if (!canWrite) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=forbidden`);

  const { data, error } = await supabase.from("leads").update({ stage }).eq("id", leadId).eq("organization_id", organizationId).is("converted_client_id", null).select("id").maybeSingle();
  if (error || !data) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=save`);

  revalidatePath("/workspace");
  revalidatePath("/workspace/sales");
  redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&updated=1`);
}

export async function convertWonLead(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const organizationId = String(formData.get("organization_id") ?? "");
  const leadId = String(formData.get("lead_id") ?? "");
  if (!organizationId || !leadId) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { data: canWrite } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!canWrite) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  const { data: clientId, error } = await supabase.rpc("convert_won_lead_to_client", { target_org: organizationId, target_lead: leadId });
  if (error || !clientId) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=convert`);
  revalidatePath("/workspace");
  revalidatePath("/workspace/sales");
  revalidatePath("/workspace/clients");
  redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&converted=${clientId}`);
}

export async function updateLeadNextAction(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const organizationId = String(formData.get("organization_id") ?? "");
  const leadId = String(formData.get("lead_id") ?? "");
  const nextAction = String(formData.get("next_action") ?? "").trim();
  const dueDate = String(formData.get("due_date") ?? "").trim();
  if (!organizationId || !leadId || nextAction.length > 180) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const { data: canWrite } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!canWrite) redirect(`/workspace/sales?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  let dueAt: string | null = null;
  if (dueDate) {
    try {
      const { data: organization } = await supabase.from("organizations").select("timezone").eq("id", organizationId).single();
      dueAt = dateAtNineInZoneToIso(dueDate, organization?.timezone ?? "UTC");
    } catch {
      redirect(`/workspace/sales/${leadId}?organization=${encodeURIComponent(organizationId)}&error=invalid-date`);
    }
  }
  const { data, error } = await supabase.from("leads").update({ next_action: nextAction || null, next_action_at: dueAt })
    .eq("id", leadId).eq("organization_id", organizationId).is("converted_client_id", null).select("id").maybeSingle();
  if (error || !data) redirect(`/workspace/sales/${leadId}?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace");
  revalidatePath("/workspace/sales");
  revalidatePath(`/workspace/sales/${leadId}`);
  redirect(`/workspace/sales/${leadId}?organization=${encodeURIComponent(organizationId)}&saved=1`);
}
