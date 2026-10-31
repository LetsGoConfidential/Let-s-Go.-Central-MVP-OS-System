import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const exportTables = [
  "org_members", "roles", "role_assignments", "org_invitations", "clients", "contacts", "leads", "deals",
  "projects", "tasks", "task_comments", "content_items", "content_reviews", "team_performance_reviews",
  "invoices", "invoice_items", "invoice_payments", "invoice_credits", "invoice_refunds", "expenses",
  "organization_files", "automation_rules", "automation_runs", "automation_run_attempts", "integrations",
  "audit_logs",
] as const;

type ExportReader = {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        order(column: string, options: { ascending: boolean }): ExportQuery;
      };
    };
  };
};
type ExportQuery = {
  order(column: string, options: { ascending: boolean }): ExportQuery;
  range(from: number, to: number): Promise<{ data: unknown[] | null; error: unknown }>;
};

export async function GET(request: Request) {
  const organizationId = new URL(request.url).searchParams.get("organization") ?? "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(organizationId)) {
    return Response.json({ error: "A valid workspace is required." }, { status: 400, headers: { "Cache-Control": "no-store" } });
  }

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Sign in to export workspace data." }, { status: 401, headers: { "Cache-Control": "no-store" } });
  const { data: allowed, error: permissionError } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "organization.manage" });
  if (permissionError || !allowed) return Response.json({ error: "Organization management permission is required." }, { status: 403, headers: { "Cache-Control": "no-store" } });
  const { error: auditError } = await supabase.rpc("log_organization_data_export", { target_org: organizationId });
  if (auditError) return Response.json({ error: "The export could not be recorded. Please try again." }, { status: 503, headers: { "Cache-Control": "no-store" } });

  const { data: organization, error: organizationError } = await supabase.from("organizations")
    .select("id,name,slug,legal_name,timezone,currency,status,ai_monthly_budget_usd,ai_budget_started_at,created_at,updated_at")
    .eq("id", organizationId).maybeSingle();
  if (organizationError || !organization) return Response.json({ error: "Workspace data is unavailable." }, { status: 404, headers: { "Cache-Control": "no-store" } });

  const reader = supabase as unknown as ExportReader;
  const tables: Record<string, unknown[]> = {};
  let totalRows = 0;
  let estimatedDataBytes = 0;
  let downloadLimitExceeded = false;
  try {
    for (let batchStart = 0; batchStart < exportTables.length; batchStart += 5) {
      const batch = await Promise.all(exportTables.slice(batchStart, batchStart + 5).map(async (table) => {
        const rows: unknown[] = [];
        for (let offset = 0; ; offset += 500) {
          if (downloadLimitExceeded) return { table, rows, failed: false, tooLarge: true };
          const columns = table === "integrations"
            ? "id,organization_id,provider,display_name,status,external_account_id,scopes,last_synced_at,created_at,updated_at"
            : "*";
          const sortColumn = table === "org_members" || table === "role_assignments" ? "user_id" : "id";
          let query = reader.from(table).select(columns).eq("organization_id", organizationId).order(sortColumn, { ascending: true });
          if (table === "role_assignments") query = query.order("role_id", { ascending: true });
          const { data, error } = await query.range(offset, offset + 499);
          if (error || !data) return { table, rows, failed: true, tooLarge: false };
          estimatedDataBytes += Buffer.byteLength(JSON.stringify(data), "utf8");
          totalRows += data.length;
          if (estimatedDataBytes > 22_000_000 || totalRows > 25_000) {
            downloadLimitExceeded = true;
            return { table, rows, failed: false, tooLarge: true };
          }
          rows.push(...data);
          if (data.length < 500) return { table, rows, failed: false, tooLarge: false };
        }
      }));
      for (const result of batch) {
        if (result.failed) return Response.json({ error: "A workspace data set could not be exported. Check database migrations and access policies." }, { status: 503, headers: { "Cache-Control": "no-store" } });
        if (result.tooLarge) {
          const message = totalRows > 25_000 ? "This workspace is larger than the current 25,000-row download limit." : "This workspace export exceeds the current 25 MB download limit.";
          return Response.json({ error: message }, { status: 413, headers: { "Cache-Control": "no-store" } });
        }
        tables[result.table] = result.rows;
      }
    }

    const membershipRows = tables.org_members as Array<{ user_id?: string }>;
    const memberIds = [...new Set(membershipRows.map((row) => row.user_id).filter((id): id is string => Boolean(id)))];
    const profiles: unknown[] = [];
    for (let offset = 0; offset < memberIds.length; offset += 200) {
      const { data, error } = await supabase.from("profiles").select("id,full_name,avatar_url,phone,created_at,updated_at").in("id", memberIds.slice(offset, offset + 200));
      if (error) return Response.json({ error: "Workspace member profiles could not be exported." }, { status: 503, headers: { "Cache-Control": "no-store" } });
      estimatedDataBytes += Buffer.byteLength(JSON.stringify(data ?? []), "utf8");
      totalRows += data?.length ?? 0;
      if (estimatedDataBytes > 22_000_000) return Response.json({ error: "This workspace export exceeds the current 25 MB download limit." }, { status: 413, headers: { "Cache-Control": "no-store" } });
      if (totalRows > 25_000) return Response.json({ error: "This workspace is larger than the current 25,000-row download limit." }, { status: 413, headers: { "Cache-Control": "no-store" } });
      profiles.push(...(data ?? []));
    }

    const body = JSON.stringify({
      export_version: 1,
      exported_at: new Date().toISOString(),
      organization,
      tables: { ...tables, profiles },
      excluded: ["integration_secrets (provider credentials)", "AI conversations and drafts (private to each member)", "ai_usage_events (internal AI cost ledger)", "Supabase Auth credentials", "file contents in private storage"],
    }, null, 2);
    if (Buffer.byteLength(body, "utf8") > 25_000_000) return Response.json({ error: "This workspace export exceeds the current 25 MB download limit." }, { status: 413, headers: { "Cache-Control": "no-store" } });
    const filename = `${organization.slug.replace(/[^a-z0-9-]/gi, "-")}-workspace-export-${new Date().toISOString().slice(0, 10)}.json`;
    return new Response(body, { headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    } });
  } catch {
    return Response.json({ error: "The workspace export could not be completed." }, { status: 500, headers: { "Cache-Control": "no-store" } });
  }
}
