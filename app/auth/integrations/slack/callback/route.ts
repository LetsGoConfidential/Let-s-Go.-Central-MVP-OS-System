import { createHmac, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { encryptIntegrationSecret } from "@/lib/integrations/crypto";

type OAuthState = { organizationId: string; userId: string; nonce: string; issuedAt: number };
type SlackTokenResponse = { ok: boolean; access_token?: string; refresh_token?: string; expires_in?: number; token_type?: string; scope?: string; team?: { id?: string; name?: string }; error?: string };
type SlackCredentials = { access_token: string; refresh_token?: string; token_type?: string };

function verifyState(state: string, secret: string): OAuthState | null {
  const [payload, signature] = state.split(".");
  if (!payload || !signature) return null;
  const expected = createHmac("sha256", secret).update(payload).digest();
  let supplied: Buffer;
  try { supplied = Buffer.from(signature, "base64url"); } catch { return null; }
  if (supplied.length !== expected.length || !timingSafeEqual(expected, supplied)) return null;
  try {
    const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as OAuthState;
    if (!decoded.organizationId || !decoded.userId || !decoded.nonce || !Number.isFinite(decoded.issuedAt) || Date.now() - decoded.issuedAt > 10 * 60 * 1000 || decoded.issuedAt > Date.now() + 30_000) return null;
    return decoded;
  } catch { return null; }
}

function returnToApp(request: Request, organizationId: string, outcome: string) {
  const base = process.env.NEXT_PUBLIC_SITE_URL || new URL(request.url).origin;
  const target = new URL("/workspace/integrations", base);
  target.searchParams.set("organization", organizationId);
  target.searchParams.set("oauth", outcome);
  return NextResponse.redirect(target);
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const cookiesStore = await cookies();
  const savedState = cookiesStore.get("lg_slack_oauth_state")?.value;
  cookiesStore.delete("lg_slack_oauth_state");
  const state = url.searchParams.get("state") ?? "";
  const stateSecret = process.env.OAUTH_STATE_SECRET;
  if (!stateSecret || !savedState || !state) return NextResponse.redirect(new URL("/login?error=oauth_state", request.url));
  const stateData = verifyState(state, stateSecret);
  if (!stateData || savedState.length !== state.length || !timingSafeEqual(Buffer.from(savedState), Buffer.from(state))) {
    return NextResponse.redirect(new URL("/login?error=oauth_state", request.url));
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || user.id !== stateData.userId) return NextResponse.redirect(new URL("/login?error=oauth_user", request.url));
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: stateData.organizationId, permission_key: "workspace.write" });
  if (!allowed) return returnToApp(request, stateData.organizationId, "forbidden");
  const oauthError = url.searchParams.get("error");
  const code = url.searchParams.get("code");
  if (oauthError || !code) return returnToApp(request, stateData.organizationId, "denied");

  const clientId = process.env.SLACK_CLIENT_ID;
  const clientSecret = process.env.SLACK_CLIENT_SECRET;
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (!clientId || !clientSecret || !siteUrl || !process.env.INTEGRATION_ENCRYPTION_KEY_BASE64) return returnToApp(request, stateData.organizationId, "config");
  let redirectUri: string;
  try {
    const appOrigin = new URL(siteUrl);
    if (!['http:', 'https:'].includes(appOrigin.protocol)) return returnToApp(request, stateData.organizationId, "config");
    redirectUri = new URL("/auth/integrations/slack/callback", appOrigin).toString();
  } catch { return returnToApp(request, stateData.organizationId, "config"); }
  const body = new URLSearchParams({ code, client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri });
  let tokenResponse: SlackTokenResponse;
  try {
    const response = await fetch("https://slack.com/api/oauth.v2.access", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body, cache: "no-store" });
    tokenResponse = await response.json() as SlackTokenResponse;
    if (!response.ok || !tokenResponse.ok || !tokenResponse.access_token || !tokenResponse.team?.id || !tokenResponse.team.name) return returnToApp(request, stateData.organizationId, "exchange");
  } catch { return returnToApp(request, stateData.organizationId, "exchange"); }

  try {
    const credentials: SlackCredentials = { access_token: tokenResponse.access_token, refresh_token: tokenResponse.refresh_token, token_type: tokenResponse.token_type };
    const expiry = Number.isFinite(tokenResponse.expires_in) ? new Date(Date.now() + Number(tokenResponse.expires_in) * 1000).toISOString() : null;
    const admin = createAdminClient();
    const { error } = await admin.rpc("store_slack_integration", {
      target_org: stateData.organizationId,
      slack_team_id: tokenResponse.team.id,
      slack_team_name: tokenResponse.team.name,
      encrypted_credentials: encryptIntegrationSecret(JSON.stringify(credentials)),
      token_expires_at: expiry,
      granted_scopes: (tokenResponse.scope ?? "").split(",").filter(Boolean),
    });
    if (error) return returnToApp(request, stateData.organizationId, "store");
  } catch { return returnToApp(request, stateData.organizationId, "config"); }
  return returnToApp(request, stateData.organizationId, "connected");
}
