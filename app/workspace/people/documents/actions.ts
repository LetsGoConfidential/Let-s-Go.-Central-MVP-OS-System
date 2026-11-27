"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const maxSize = 20 * 1024 * 1024;
const mimeTypes = new Set([
  "application/pdf", "image/png", "image/jpeg", "image/webp", "text/plain",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const categories = new Set(["contract", "identity", "tax", "certificate", "other"]);

function go(organizationId: string, result: string): never {
  redirect(`/workspace/people/documents?organization=${encodeURIComponent(organizationId)}&${result}=1`);
}

async function authorize(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_org: organizationId, permission_key: "hr.documents.manage" });
  return { supabase, user, allowed: allowed === true };
}

export async function uploadEmployeeDocument(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  const category = String(formData.get("category") ?? "");
  const employeeVisible = formData.get("employee_visible") === "on";
  const candidate = formData.get("file");
  if (!uuidPattern.test(organizationId) || !uuidPattern.test(memberId) || !categories.has(category)) go(organizationId, "invalid");
  const { supabase, allowed } = await authorize(organizationId);
  if (!allowed) go(organizationId, "forbidden");
  if (!(candidate instanceof File) || candidate.size <= 0 || candidate.size > maxSize || !mimeTypes.has(candidate.type)) go(organizationId, "file");
  const { data: documentId, error: createError } = await supabase.rpc("create_employee_document", {
    target_org: organizationId,
    target_member: memberId,
    target_category: category,
    target_filename: candidate.name.trim().slice(0, 180),
    target_mime: candidate.type,
    target_size: candidate.size,
    target_employee_visible: employeeVisible,
  });
  if (createError || !documentId) go(organizationId, "save");
  const storagePath = `${organizationId}/${memberId}/${documentId}`;
  const { error: storageError } = await supabase.storage.from("employee-files").upload(storagePath, candidate, {
    contentType: candidate.type,
    cacheControl: "3600",
    upsert: false,
  });
  if (storageError) {
    await supabase.storage.from("employee-files").remove([storagePath]);
    await supabase.rpc("delete_employee_document", { target_org: organizationId, target_document: documentId });
    go(organizationId, "upload");
  }
  revalidatePath("/workspace/people/documents");
  go(organizationId, "uploaded");
}

export async function deleteEmployeeDocument(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const documentId = String(formData.get("document_id") ?? "");
  if (!uuidPattern.test(organizationId) || !uuidPattern.test(documentId)) go(organizationId, "invalid");
  const { supabase, allowed } = await authorize(organizationId);
  if (!allowed) go(organizationId, "forbidden");
  const { data: record } = await supabase.from("employee_documents").select("member_id").eq("organization_id", organizationId).eq("id", documentId).maybeSingle();
  if (!record) go(organizationId, "delete");
  const storagePath = `${organizationId}/${record.member_id}/${documentId}`;
  const { error: storageError } = await supabase.storage.from("employee-files").remove([storagePath]);
  if (storageError) go(organizationId, "delete");
  const { data: deleted, error } = await supabase.rpc("delete_employee_document", { target_org: organizationId, target_document: documentId });
  if (error || !deleted) go(organizationId, "delete");
  revalidatePath("/workspace/people/documents");
  go(organizationId, "deleted");
}
