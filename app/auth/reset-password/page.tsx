import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { setNewPassword } from "./actions";

export default async function ResetPasswordPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?error=auth-callback");
  return <main id="main-content" tabIndex={-1} className="auth-page"><div className="auth-card"><a className="brand auth-brand" href="/"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a><h1>Set a new password</h1><p>Choose a strong password with at least 12 characters.</p>{error && <div className="auth-error" role="alert">{error === "invalid-password" ? "Use at least 12 characters and make both entries match." : "We couldn’t update your password. Please try again."}</div>}<form action={setNewPassword}><label htmlFor="password">New password</label><input id="password" name="password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required/><label htmlFor="confirm_password">Confirm new password</label><input id="confirm_password" name="confirm_password" type="password" autoComplete="new-password" minLength={12} maxLength={128} required/><button className="primary-button auth-submit" type="submit">Update password</button></form></div></main>;
}
