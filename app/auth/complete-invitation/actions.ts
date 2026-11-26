"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function completeInvitation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirm_password") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(organizationId) || password.length < 12 || password.length > 128 || password !== confirmation) {
    redirect(`/auth/complete-invitation?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user?.email) redirect("/login");
  const { data: membership } = await supabase.from("org_members").select("user_id").eq("organization_id", organizationId).eq("user_id", user.id).eq("status", "active").maybeSingle();
  if (!membership) redirect("/auth/invitation-error");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect(`/auth/complete-invitation?organization=${encodeURIComponent(organizationId)}&error=save`);
  redirect(`/workspace?organization=${encodeURIComponent(organizationId)}&welcome=1`);
}
