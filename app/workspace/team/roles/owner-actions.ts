"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function transferOwnership(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const newOwnerId = String(formData.get("new_owner_id") ?? "");
  const confirmation = String(formData.get("confirmation") ?? "");
  if (!organizationId || !newOwnerId || confirmation !== "TRANSFER") redirect(`/workspace/team?organization=${encodeURIComponent(organizationId)}&owner-error=invalid`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: transferred, error } = await supabase.rpc("transfer_organization_owner", { target_org: organizationId, new_owner: newOwnerId });
  if (error || !transferred) redirect(`/workspace/team?organization=${encodeURIComponent(organizationId)}&owner-error=failed`);
  revalidatePath("/workspace"); revalidatePath("/workspace/team"); revalidatePath("/workspace/team/roles");
  redirect(`/workspace/team?organization=${encodeURIComponent(organizationId)}&owner-transferred=1`);
}
