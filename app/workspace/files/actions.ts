"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const maximumSize = 20 * 1024 * 1024;
const allowedTypes = new Set([
  "application/pdf", "image/png", "image/jpeg", "image/webp", "text/plain",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
]);

function fail(organizationId: string, code: string): never {
  redirect(`/workspace/files?organization=${encodeURIComponent(organizationId)}&error=${code}`);
}

async function authorize(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "workspace.write" });
  if (!allowed) fail(organizationId, "forbidden");
  return { supabase, user };
}

export async function uploadOrganizationFile(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  if (!organizationId) fail(organizationId, "invalid");
  const { supabase, user } = await authorize(organizationId);
  const candidate = formData.get("file");
  if (!(candidate instanceof File) || candidate.size <= 0 || candidate.size > maximumSize || !allowedTypes.has(candidate.type)) fail(organizationId, "file");
  const originalFilename = candidate.name.trim().slice(0, 180);
  const safeName = originalFilename.normalize("NFKD").replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^\.+/, "").slice(-120) || "upload";
  const storagePath = `${organizationId}/${randomUUID()}-${safeName}`;
  const { error: storageError } = await supabase.storage.from("tenant-files").upload(storagePath, candidate, {
    contentType: candidate.type,
    cacheControl: "3600",
    upsert: false,
  });
  if (storageError) fail(organizationId, "upload");
  const { error: metadataError } = await supabase.from("organization_files").insert({
    organization_id: organizationId,
    storage_path: storagePath,
    original_filename: originalFilename,
    mime_type: candidate.type,
    size_bytes: candidate.size,
    uploaded_by: user.id,
  });
  if (metadataError) {
    await supabase.storage.from("tenant-files").remove([storagePath]);
    fail(organizationId, "save");
  }
  revalidatePath("/workspace/files");
  redirect(`/workspace/files?organization=${encodeURIComponent(organizationId)}&uploaded=1`);
}

export async function deleteOrganizationFile(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const fileId = String(formData.get("file_id") ?? "");
  if (!organizationId || !fileId) fail(organizationId, "invalid");
  const { supabase } = await authorize(organizationId);
  const { data: record } = await supabase.from("organization_files").select("id,storage_path").eq("organization_id", organizationId).eq("id", fileId).maybeSingle();
  if (!record) fail(organizationId, "missing");
  const { error: storageError } = await supabase.storage.from("tenant-files").remove([record.storage_path]);
  if (storageError) fail(organizationId, "delete");
  const { error: metadataError } = await supabase.from("organization_files").delete().eq("organization_id", organizationId).eq("id", fileId);
  if (metadataError) fail(organizationId, "delete");
  revalidatePath("/workspace/files");
  redirect(`/workspace/files?organization=${encodeURIComponent(organizationId)}&deleted=1`);
}
