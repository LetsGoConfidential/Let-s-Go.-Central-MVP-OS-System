import { redirect } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { completeInvitation } from "./actions";

export default async function CompleteInvitationPage({ searchParams }: { searchParams: Promise<{ organization?: string; error?: string }> }) {
  const params = await searchParams;
  if (!params.organization || !/^[0-9a-f-]{36}$/i.test(params.organization)) redirect("/login");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user?.email) redirect("/login");
  const { data: member } = await supabase.from("org_members").select("user_id,organizations(name)").eq("organization_id", params.organization).eq("user_id", user.id).eq("status", "active").maybeSingle();
  if (!member) redirect("/auth/invitation-error");
  return <main id="main-content" tabIndex={-1} className="auth-page"><div className="auth-card"><Link className="brand auth-brand" href="/"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></Link><div className="eyebrow">INVITED WORKSPACE ACCESS</div><h1>Set up your password</h1><p>Your account has been approved for this workspace. Sign in ID: <b>{user.email}</b>.</p>{params.error && <div className="auth-error" role="alert">{params.error === "invalid" ? "Use a matching password with at least 12 characters." : "We couldn’t save your password. Try again or use password recovery."}</div>}<form action={completeInvitation} className="onboarding-form"><input type="hidden" name="organization_id" value={params.organization}/><label htmlFor="password">Create password<input id="password" name="password" type="password" minLength={12} maxLength={128} autoComplete="new-password" required/></label><label htmlFor="confirm_password">Confirm password<input id="confirm_password" name="confirm_password" type="password" minLength={12} maxLength={128} autoComplete="new-password" required/></label><button className="primary-button" type="submit">Finish setup and open workspace</button></form><p className="onboarding-footnote">Ask your workspace owner or admin if you need access to another department.</p></div></main>;
}
