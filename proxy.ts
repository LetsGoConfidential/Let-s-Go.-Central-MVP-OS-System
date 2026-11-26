import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  if (!isSupabaseConfigured()) {
    if (request.nextUrl.pathname.startsWith("/workspace")) {
      const destination = request.nextUrl.clone();
      destination.pathname = "/login";
      destination.searchParams.set("error", "configuration");
      return NextResponse.redirect(destination);
    }
    return response;
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  let user;
  try {
    ({ data: { user } } = await supabase.auth.getUser());
  } catch {
    if (request.nextUrl.pathname.startsWith("/workspace")) {
      const destination = request.nextUrl.clone();
      destination.pathname = "/login";
      destination.searchParams.set("error", "auth-unavailable");
      return NextResponse.redirect(destination);
    }
    return response;
  }
  if (request.nextUrl.pathname.startsWith("/workspace") && !user) {
    const destination = request.nextUrl.clone();
    destination.pathname = "/login";
    return NextResponse.redirect(destination);
  }
  if (request.nextUrl.pathname === "/login" && user) {
    const destination = request.nextUrl.clone();
    destination.pathname = "/workspace";
    return NextResponse.redirect(destination);
  }
  return response;
}

export const config = { matcher: ["/workspace/:path*", "/login"] };
