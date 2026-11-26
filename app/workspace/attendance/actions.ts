"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function recordAttendance(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const actionName = String(formData.get("action_name") ?? "");
  const url = `/workspace/attendance?organization=${encodeURIComponent(organizationId)}`;
  if (!organizationId || !["check_in", "check_out"].includes(actionName)) redirect(`${url}&error=invalid`);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("record_attendance", { target_org: organizationId, action_name: actionName });
  if (error) redirect(`${url}&error=attendance`);
  revalidatePath("/workspace/attendance");
  redirect(`${url}&recorded=${actionName}`);
}
