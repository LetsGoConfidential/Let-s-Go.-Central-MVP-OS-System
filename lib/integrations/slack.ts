import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { decryptIntegrationSecret, encryptIntegrationSecret } from "./crypto";

type SlackCredentials = { access_token: string; refresh_token?: string; token_type?: string };
type SlackTokenResponse = { ok: boolean; access_token?: string; refresh_token?: string; expires_in?: number; token_type?: string; error?: string };

async function readCredentials(organizationId: string, integrationId: string) {
  const admin = createAdminClient();
  const [{ data: secret, error: secretError }, { data: integration, error: integrationError }] = await Promise.all([
    admin.from("integration_secrets").select("encrypted_credentials,expires_at").eq("organization_id", organizationId).eq("integration_id", integrationId).maybeSingle(),
    admin.from("integrations").select("external_account_id,display_name,scopes").eq("organization_id", organizationId).eq("id", integrationId).eq("provider", "slack").maybeSingle(),
  ]);
  if (secretError || integrationError || !secret || !integration) throw new Error("Slack integration is unavailable.");
  let credentials: SlackCredentials;
  try { credentials = JSON.parse(decryptIntegrationSecret(secret.encrypted_credentials)) as SlackCredentials; }
  catch { throw new Error("Slack credentials could not be decrypted."); }
  return { admin, secret, integration, credentials };
}

export async function getSlackAccessToken(organizationId: string, integrationId: string) {
  const stored = await readCredentials(organizationId, integrationId);
  const expiresAt = stored.secret.expires_at ? new Date(stored.secret.expires_at).getTime() : null;
  if (!expiresAt || expiresAt - Date.now() > 5 * 60 * 1000) return stored.credentials.access_token;
  if (!stored.credentials.refresh_token) throw new Error("Slack authorization has expired. Reconnect the workspace.");
  const clientId = process.env.SLACK_CLIENT_ID;
  const clientSecret = process.env.SLACK_CLIENT_SECRET;
  if (!clientId || !clientSecret) throw new Error("Slack OAuth is not configured.");
  const body = new URLSearchParams({ client_id: clientId, client_secret: clientSecret, grant_type: "refresh_token", refresh_token: stored.credentials.refresh_token });
  const response = await fetch("https://slack.com/api/oauth.v2.access", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body, cache: "no-store" });
  const token = await response.json() as SlackTokenResponse;
  if (!response.ok || !token.ok || !token.access_token || !token.refresh_token) {
    await stored.admin.from("integrations").update({ status: "reauthorization_required" }).eq("organization_id", organizationId).eq("id", integrationId);
    throw new Error("Slack authorization needs to be renewed.");
  }
  const expiresAtNext = new Date(Date.now() + Math.max(0, Number(token.expires_in ?? 0)) * 1000).toISOString();
  const nextCredentials: SlackCredentials = { access_token: token.access_token, refresh_token: token.refresh_token, token_type: token.token_type };
  const { error } = await stored.admin.rpc("store_slack_integration", {
    target_org: organizationId,
    slack_team_id: stored.integration.external_account_id ?? "",
    slack_team_name: stored.integration.display_name,
    encrypted_credentials: encryptIntegrationSecret(JSON.stringify(nextCredentials)),
    token_expires_at: expiresAtNext,
    granted_scopes: stored.integration.scopes,
  });
  if (error) throw new Error("Rotated Slack credentials could not be stored.");
  return token.access_token;
}

export async function postSlackMessage(organizationId: string, integrationId: string, channelId: string, text: string) {
  if (!channelId || channelId.length > 80 || !text.trim() || text.length > 4000) throw new Error("Invalid Slack message.");
  const token = await getSlackAccessToken(organizationId, integrationId);
  const response = await fetch("https://slack.com/api/chat.postMessage", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ channel: channelId, text }),
    cache: "no-store",
  });
  const result = await response.json() as { ok?: boolean };
  if (!response.ok || !result.ok) throw new Error("Slack could not deliver the message.");
}
