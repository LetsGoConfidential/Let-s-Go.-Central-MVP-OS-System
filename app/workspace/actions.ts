"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createWorkspace(formData: FormData) {
  const name = String(formData.get("organization_name") ?? "").trim().replace(/\s+/g, " ");
  const enteredSlug = String(formData.get("organization_slug") ?? "").trim();
  const generatedSlug = name.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60).replace(/-+$/g, "");
  const slug = (enteredSlug || generatedSlug).toLowerCase();
  if (name.length < 2 || name.length > 100 || slug.length < 3 || slug.length > 60 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) redirect("/workspace?onboarding=invalid");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: organizationId, error } = await supabase.rpc("create_organization", { org_name: name, org_slug: slug });
  if (error || !organizationId) redirect(`/workspace?onboarding=${encodeURIComponent(error?.code === "23505" ? "slug-taken" : "failed")}`);
  redirect(`/workspace?organization=${encodeURIComponent(organizationId)}&welcome=1`);
}
