import "server-only";
import type { createClient } from "@/lib/supabase/server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

export async function loadWorkspaceContext(supabase: Supabase, organizationId: string) {
  const [organizationResult, clientResult, leadResult, projectResult, taskResult, contentResult, canSeeFinance] = await Promise.all([
    supabase.from("organizations").select("name,currency,timezone").eq("id", organizationId).single(),
    supabase.from("clients").select("name,industry,health,monthly_value").eq("organization_id", organizationId).eq("status", "active").order("monthly_value", { ascending: false }).limit(15),
    supabase.from("leads").select("company_name,stage,estimated_value,probability,next_action,next_action_at").eq("organization_id", organizationId).order("updated_at", { ascending: false }).limit(20),
    supabase.from("projects").select("name,status,priority,due_date").eq("organization_id", organizationId).neq("status", "completed").order("due_date", { ascending: true }).limit(15),
    supabase.from("tasks").select("title,status,priority,due_at").eq("organization_id", organizationId).neq("status", "done").order("due_at", { ascending: true }).limit(20),
    supabase.from("content_items").select("title,format,channel,status,scheduled_at").eq("organization_id", organizationId).order("scheduled_at", { ascending: true }).limit(15),
    supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "finance.manage" }),
  ]);
  if (organizationResult.error || !organizationResult.data) throw new Error("Workspace context is unavailable.");

  let finance: unknown = "Not available to this user.";
  if (canSeeFinance.data) {
    const { data } = await supabase.rpc("finance_summary", { target_org: organizationId });
    finance = data ?? [];
  }
  return {
    workspace: organizationResult.data,
    clients: clientResult.data ?? [],
    leads: leadResult.data ?? [],
    active_projects: projectResult.data ?? [],
    open_tasks: taskResult.data ?? [],
    content_schedule: contentResult.data ?? [],
    finance_summary: finance,
  };
}
