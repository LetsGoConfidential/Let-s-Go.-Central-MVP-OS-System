import Link from "next/link";

export default function InvitationErrorPage() {
  return <main id="main-content" tabIndex={-1} className="auth-page"><section className="auth-card"><Link className="brand auth-brand" href="/"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></Link><h1>Invitation not available</h1><p>This invitation may have expired, been revoked, or belong to another email address. Ask your organization admin for a fresh invitation.</p><Link className="primary-button auth-submit" href="/login">Continue to sign in</Link></section></main>;
}
