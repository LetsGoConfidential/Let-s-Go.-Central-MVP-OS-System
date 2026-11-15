"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supportedCurrencies } from "@/lib/organization/currencies";
import { createClient } from "@/lib/supabase/server";

export async function saveOrganizationSettings(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const legalName = String(formData.get("legal_name") ?? "").trim();
  const timezone = String(formData.get("timezone") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const target = `/workspace/settings?organization=${encodeURIComponent(organizationId)}`;
  if (!organizationId || name.length < 2 || name.length > 100 || legalName.length > 160 || timezone.length < 1 || timezone.length > 100 || !supportedCurrencies.includes(currency as typeof supportedCurrencies[number])) {
    redirect(`${target}&error=invalid`);
  }

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" });
  if (!allowed) redirect(`${target}&error=forbidden`);
  const { error } = await supabase.rpc("update_organization_settings", {
    target_org: organizationId,
    org_name: name,
    org_legal_name: legalName || null,
    org_timezone: timezone,
    org_currency: currency,
  });
  if (error) redirect(`${target}&error=save`);

  revalidatePath("/workspace");
  revalidatePath("/workspace/settings");
  revalidatePath("/workspace/team");
  revalidatePath("/workspace/sales");
  revalidatePath("/workspace/projects");
  revalidatePath("/workspace/clients");
  revalidatePath("/workspace/tasks");
  revalidatePath("/workspace/content");
  revalidatePath("/workspace/finance");
  revalidatePath("/workspace/reports");
  revalidatePath("/workspace/files");
  revalidatePath("/workspace/audit");
  redirect(`${target}&saved=1`);
}
