"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createClientRecord(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const industry = String(formData.get("industry") ?? "").trim();
  const websiteInput = String(formData.get("website") ?? "").trim();
  const monthlyValue = Number(formData.get("monthly_value") ?? 0);
  const firstName = String(formData.get("contact_first_name") ?? "").trim();
  const lastName = String(formData.get("contact_last_name") ?? "").trim();
  const email = String(formData.get("contact_email") ?? "").trim();
  const phone = String(formData.get("contact_phone") ?? "").trim();
  let website = "";
  try {
    if (websiteInput) {
      const parsed = new URL(websiteInput.startsWith("http") ? websiteInput : `https://${websiteInput}`);
      if (!(["http:", "https:"].includes(parsed.protocol)) || !parsed.hostname) throw new Error("Invalid website");
      website = parsed.origin;
    }
  } catch { redirect(`/workspace/clients?organization=${encodeURIComponent(organizationId)}&error=invalid`); }
  const validEmail = !email || (email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email));
  if (!organizationId || name.length < 2 || name.length > 160 || industry.length > 100 || !Number.isFinite(monthlyValue) || monthlyValue < 0 || monthlyValue > 999999999999.99 || firstName.length > 100 || lastName.length > 100 || phone.length > 40 || !validEmail || (email && !firstName)) {
    redirect(`/workspace/clients?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/clients?organization=${encodeURIComponent(organizationId)}&error=forbidden`);

  const { data: clientId, error } = await supabase.rpc("create_client_with_contact", {
    target_org: organizationId,
    client_name: name,
    client_industry: industry || null,
    client_website: website || null,
    client_monthly_value: monthlyValue,
    contact_first_name: firstName || null,
    contact_last_name: lastName || null,
    contact_email: email || null,
    contact_phone: phone || null,
  });
  if (error || !clientId) redirect(`/workspace/clients?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace");
  revalidatePath("/workspace/clients");
  redirect(`/workspace/clients/${clientId}?organization=${encodeURIComponent(organizationId)}&created=1`);
}

export async function createContact(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const clientId = String(formData.get("client_id") ?? "");
  const firstName = String(formData.get("first_name") ?? "").trim();
  const lastName = String(formData.get("last_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const title = String(formData.get("job_title") ?? "").trim();
  const validEmail = !email || (email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email));
  if (!organizationId || !clientId || firstName.length < 1 || firstName.length > 100 || lastName.length > 100 || phone.length > 40 || title.length > 100 || !validEmail) {
    redirect(`/workspace/clients/${clientId}?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/clients/${clientId}?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  const { error } = await supabase.from("contacts").insert({ organization_id: organizationId, client_id: clientId, first_name: firstName, last_name: lastName || null, email: email || null, phone: phone || null, job_title: title || null });
  if (error) redirect(`/workspace/clients/${clientId}?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath(`/workspace/clients/${clientId}`);
  redirect(`/workspace/clients/${clientId}?organization=${encodeURIComponent(organizationId)}&created=contact`);
}

export async function updateClientDetails(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const clientId = String(formData.get("client_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const industry = String(formData.get("industry") ?? "").trim();
  const websiteInput = String(formData.get("website") ?? "").trim();
  const health = String(formData.get("health") ?? "");
  const notes = String(formData.get("notes") ?? "").trim();
  const target = `/workspace/clients/${encodeURIComponent(clientId)}?organization=${encodeURIComponent(organizationId)}`;
  let website: string | null = null;
  try {
    if (websiteInput) {
      const parsed = new URL(websiteInput.startsWith("http") ? websiteInput : `https://${websiteInput}`);
      if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) throw new Error("Invalid website");
      website = parsed.origin;
    }
  } catch { redirect(`${target}&error=invalid`); }
  if (!organizationId || !clientId || name.length < 2 || name.length > 160 || industry.length > 100 || notes.length > 5000 || !["healthy", "needs_attention", "at_risk", "churned"].includes(health)) redirect(`${target}&error=invalid`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`${target}&error=forbidden`);
  const { data, error } = await supabase.from("clients").update({ name, industry: industry || null, website, health, notes: notes || null }).eq("organization_id", organizationId).eq("id", clientId).select("id").maybeSingle();
  if (error || !data) redirect(`${target}&error=save`);
  revalidatePath("/workspace"); revalidatePath("/workspace/clients"); revalidatePath(target);
  redirect(`${target}&updated=client`);
}

export async function updateContact(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const clientId = String(formData.get("client_id") ?? "");
  const contactId = String(formData.get("contact_id") ?? "");
  const firstName = String(formData.get("first_name") ?? "").trim();
  const lastName = String(formData.get("last_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const title = String(formData.get("job_title") ?? "").trim();
  const target = `/workspace/clients/${encodeURIComponent(clientId)}?organization=${encodeURIComponent(organizationId)}`;
  const validEmail = !email || (email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email));
  if (!organizationId || !clientId || !contactId || firstName.length < 1 || firstName.length > 100 || lastName.length > 100 || phone.length > 40 || title.length > 100 || !validEmail) redirect(`${target}&error=invalid`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`${target}&error=forbidden`);
  const { data, error } = await supabase.from("contacts").update({ first_name: firstName, last_name: lastName || null, email: email || null, phone: phone || null, job_title: title || null }).eq("organization_id", organizationId).eq("client_id", clientId).eq("id", contactId).select("id").maybeSingle();
  if (error || !data) redirect(`${target}&error=save`);
  revalidatePath(target);
  redirect(`${target}&updated=contact`);
}
