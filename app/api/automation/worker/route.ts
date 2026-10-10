import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

function validSecret(request: Request, secret: string) {
  const authorization = request.headers.get("authorization") ?? "";
  const supplied = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const expectedBytes = Buffer.from(secret);
  const suppliedBytes = Buffer.from(supplied);
  return suppliedBytes.length === expectedBytes.length && timingSafeEqual(suppliedBytes, expectedBytes);
}

export async function POST(request: Request) {
  const secret = process.env.AUTOMATION_WORKER_SECRET;
  if (!secret || secret.length < 32 || !validSecret(request, secret)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401, headers: { "Cache-Control": "no-store" } });
  }

  try {
    const admin = createAdminClient();
    const { data, error } = await admin.rpc("process_automation_jobs", { batch_size: 20 });
    if (error) return NextResponse.json({ error: "Worker failed" }, { status: 500, headers: { "Cache-Control": "no-store" } });
    return NextResponse.json({ processed: data ?? 0 }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Worker is not configured" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
