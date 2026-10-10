"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function setNewPassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirm_password") ?? "");
  if (password.length < 12 || password.length > 128 || password !== confirmation) {
    redirect("/auth/reset-password?error=invalid-password");
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?error=auth-callback");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect("/auth/reset-password?error=save-failed");
  redirect("/workspace");
}
