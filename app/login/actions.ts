"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { headers } from "next/headers";

export async function signIn(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) redirect("/login?error=missing-fields");
  if (!isSupabaseConfigured()) redirect("/login?error=configuration");

  let error: unknown;
  try {
    const supabase = await createClient();
    ({ error } = await supabase.auth.signInWithPassword({ email, password }));
  } catch {
    redirect("/login?error=auth-unavailable");
  }
  if (error) redirect("/login?error=invalid-credentials");
  redirect("/workspace");
}

export async function requestPasswordReset(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  if (!email || email.length > 254) redirect("/login?reset=sent");
  if (!isSupabaseConfigured()) redirect("/login?error=configuration");
  try {
    const supabase = await createClient();
    const headerStore = await headers();
    const origin = process.env.NEXT_PUBLIC_SITE_URL || headerStore.get("origin") || "http://localhost:3000";
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${origin}/auth/callback?next=${encodeURIComponent("/auth/reset-password")}`,
    });
    if (error) redirect("/login?error=auth-unavailable");
  } catch {
    redirect("/login?error=auth-unavailable");
  }
  // Keep the response identical whether or not the email belongs to an account.
  redirect("/login?reset=sent");
}
