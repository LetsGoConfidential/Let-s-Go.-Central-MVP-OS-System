import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const requestedNext = url.searchParams.get("next") ?? "/workspace";
  const safeNext = requestedNext === "/auth/reset-password" || requestedNext.startsWith("/workspace/") || requestedNext.startsWith("/workspace?") ? requestedNext : "/workspace";
  if (!code) return NextResponse.redirect(new URL("/login?error=auth-callback", request.url));
  const supabase = await createClient();
  const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
  if (exchangeError) return NextResponse.redirect(new URL("/login?error=auth-callback", request.url));
  const destination = new URL(safeNext, request.url);
  if (destination.searchParams.get("accept_invite") === "1") {
    const organizationId = destination.searchParams.get("organization");
    if (!organizationId) return NextResponse.redirect(new URL("/auth/invitation-error", request.url));
    const { data: accepted, error } = await supabase.rpc("accept_org_invitation", { target_org: organizationId });
    if (error || !accepted) return NextResponse.redirect(new URL("/auth/invitation-error", request.url));
    destination.searchParams.delete("accept_invite");
  }
  return NextResponse.redirect(destination);
}
