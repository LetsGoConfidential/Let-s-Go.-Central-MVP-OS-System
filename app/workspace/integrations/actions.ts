"use server";

import { createHmac, randomBytes } from "node:crypto";
import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { postSlackMessage } from "@/lib/integrations/slack";

async function authorized(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  return supabase;
}

export async function startSlackOAuth(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const { user } = await authorized(organizationId);
  const clientId = process.env.SLACK_CLIENT_ID;
  const stateSecret = process.env.OAUTH_STATE_SECRET;
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (!clientId || !stateSecret || stateSecret.length < 32 || !siteUrl) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=oauth-config`);
  let appOrigin: URL;
  try { appOrigin = new URL(siteUrl); } catch { redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=oauth-config`); }
  if (!['http:', 'https:'].includes(appOrigin.protocol)) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=oauth-config`);
  const redirectUri = new URL("/auth/integrations/slack/callback", appOrigin).toString();
  const stateData = Buffer.from(JSON.stringify({ organizationId, userId: user.id, nonce: randomBytes(24).toString("base64url"), issuedAt: Date.now() })).toString("base64url");
  const signature = createHmac("sha256", stateSecret).update(stateData).digest("base64url");
  const state = `${stateData}.${signature}`;
  const cookieStore = await cookies();
  cookieStore.set("lg_slack_oauth_state", state, { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax", path: "/auth/integrations/slack/callback", maxAge: 600 });
  const authorizeUrl = new URL("https://slack.com/oauth/v2/authorize");
  authorizeUrl.searchParams.set("client_id", clientId);
  authorizeUrl.searchParams.set("scope", "chat:write");
  authorizeUrl.searchParams.set("redirect_uri", redirectUri);
  authorizeUrl.searchParams.set("state", state);
  redirect(authorizeUrl.toString());
}

export async function sendSlackMessage(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const integrationId = String(formData.get("integration_id") ?? "");
  const channelId = String(formData.get("channel_id") ?? "").trim();
  const message = String(formData.get("message") ?? "").trim();
  if (!organizationId || !integrationId || !channelId || channelId.length > 80 || !message || message.length > 4000) {
    redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=message-invalid`);
  }
  const supabase = await authorized(organizationId);
  const { data: connection } = await supabase.from("integrations").select("id").eq("organization_id", organizationId).eq("id", integrationId).eq("provider", "slack").eq("status", "connected").maybeSingle();
  if (!connection) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=message-unavailable`);
  try {
    await postSlackMessage(organizationId, connection.id, channelId, message);
  } catch {
    redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=message-failed`);
  }
  revalidatePath("/workspace/integrations");
  redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&sent=1`);
}

export async function registerIntegration(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const provider = String(formData.get("provider") ?? "");
  const displayName = String(formData.get("display_name") ?? "").trim();
  if (!organizationId || displayName.length < 2 || displayName.length > 80) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const supabase = await authorized(organizationId);
  const { error } = await supabase.rpc("register_integration", { target_org: organizationId, provider_key: provider, display_label: displayName });
  if (error) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=save`);
  revalidatePath("/workspace/integrations");
  redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&created=1`);
}

export async function removeIntegration(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const integrationId = String(formData.get("integration_id") ?? "");
  if (!organizationId || !integrationId) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=invalid`);
  const supabase = await authorized(organizationId);
  const { data, error } = await supabase.rpc("remove_integration", { target_org: organizationId, integration_id: integrationId });
  if (error || !data) redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&error=remove`);
  revalidatePath("/workspace/integrations");
  redirect(`/workspace/integrations?organization=${encodeURIComponent(organizationId)}&removed=1`);
}
