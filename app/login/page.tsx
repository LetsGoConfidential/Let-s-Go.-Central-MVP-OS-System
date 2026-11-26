import Link from "next/link";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import styles from "./login.module.css";
import { requestPasswordReset, signIn } from "./actions";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; reset?: string }> }) {
  const { error, reset } = await searchParams;
  const supabaseConfigured = isSupabaseConfigured();
  const errorMessage = error === "missing-fields" ? "Enter your email and password."
    : error === "auth-callback" ? "That sign-in link is invalid or expired. Request a fresh email and try again."
      : error === "configuration" ? "Sign-in is unavailable because Supabase is not configured for this app yet."
        : error === "auth-unavailable" ? "The sign-in service is temporarily unavailable. Try again after setup is complete."
          : "We couldn’t sign you in. Check your details and try again.";
  const disabledClass = supabaseConfigured ? "" : styles.disabledButton;
  return <main id="main-content" tabIndex={-1} className="auth-page"><div className="auth-card"><Link className="brand auth-brand" href="/"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></Link><h1>Welcome back</h1><p>Sign in with your invited work email. New accounts are created by an authorized workspace owner or admin.</p>{!supabaseConfigured && <div className="auth-error" role="status"><b>Preview mode · Sign-in is not connected</b><br/>Configure the Supabase URL and publishable key in <code>.env.local</code> to enable sign-in and password reset. Both actions are disabled until setup is complete.</div>}{reset && <div className="auth-success" role="status">If an account matches that email, we’ve sent a password reset link.</div>}{error && <div className="auth-error" role="alert">{errorMessage}</div>}<form action={signIn}><label htmlFor="email">Work email · Login ID</label><input id="email" name="email" type="email" autoComplete="email" required placeholder="you@company.com"/><label htmlFor="password">Password</label><input id="password" name="password" type="password" autoComplete="current-password" required placeholder="Your password"/><button className={`primary-button auth-submit ${disabledClass}`} type="submit" disabled={!supabaseConfigured}>Sign in</button></form><form action={requestPasswordReset} className="reset-request-form"><label htmlFor="reset-email">Forgot your password?</label><div><input id="reset-email" name="email" type="email" autoComplete="email" required placeholder="Enter your work email"/><button className={disabledClass} type="submit" disabled={!supabaseConfigured}>Send reset link</button></div></form><Link className="back-link" href="/">Back to preview</Link></div></main>;
}
