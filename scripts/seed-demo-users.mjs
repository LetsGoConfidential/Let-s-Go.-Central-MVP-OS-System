import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createClient } from "@supabase/supabase-js";

const envPath = resolve(process.cwd(), ".env.local");
const envFile = await readFile(envPath, "utf8").catch(() => "");
for (const line of envFile.split(/\r?\n/)) {
  const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
  if (!match || process.env[match[1]]) continue;
  const value = match[2].replace(/^(['"])(.*)\1$/, "$2");
  process.env[match[1]] = value;
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  throw new Error("Set NEXT_PUBLIC_SUPABASE_URL and the local SUPABASE_SERVICE_ROLE_KEY in .env.local first.");
}

const parsedUrl = new URL(url);
const localHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
if (!localHosts.has(parsedUrl.hostname)) {
  throw new Error("Demo users can only be created against localhost, 127.0.0.1, or ::1. Refusing this Supabase URL.");
}

const demoPassword = "CentralDemo!2026";
const demoAccounts = [
  { email: "founder@letsgo-demo.test", name: "Demo Founder", role: "owner", department: "Leadership" },
  { email: "hr@letsgo-demo.test", name: "Demo HR", role: "member", department: "HR", permissions: { "workspace.write": true, "team.performance.manage": true, "hr.leave.manage": true, "hr.attendance.manage": true, "hr.people.invite": true } },
  { email: "sales@letsgo-demo.test", name: "Demo Sales", role: "member", department: "Sales", permissions: { "workspace.write": true } },
  { email: "manager@letsgo-demo.test", name: "Demo Manager", role: "manager", department: "Management" },
  { email: "production@letsgo-demo.test", name: "Demo Production", role: "member", department: "Production", permissions: { "workspace.write": true } },
  { email: "employee@letsgo-demo.test", name: "Demo Employee", role: "member", department: "Production" },
];

const supabase = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
const { data: organization, error: organizationError } = await supabase
  .from("organizations")
  .select("id")
  .eq("slug", "lets-go-digitals")
  .single();
if (organizationError) throw organizationError;

const rolesByName = new Map();
for (const account of demoAccounts.filter((candidate) => candidate.permissions)) {
  const name = `${account.department} demo`;
  const { error } = await supabase.from("roles").upsert({
    organization_id: organization.id,
    name,
    is_system: false,
    permissions: account.permissions,
  }, { onConflict: "organization_id,name" });
  if (error) throw error;
  const { data: role, error: roleError } = await supabase.from("roles")
    .select("id")
    .eq("organization_id", organization.id)
    .eq("name", name)
    .single();
  if (roleError) throw roleError;
  rolesByName.set(name, role.id);
}

const { data: usersPage, error: usersError } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
if (usersError) throw usersError;
const existingUsers = new Map((usersPage.users ?? []).map((user) => [user.email?.toLowerCase(), user]));

for (const account of demoAccounts) {
  let user = existingUsers.get(account.email);
  if (!user) {
    const { data, error } = await supabase.auth.admin.createUser({
      email: account.email,
      password: demoPassword,
      email_confirm: true,
      user_metadata: { full_name: account.name, demo_account: true },
    });
    if (error) throw error;
    user = data.user;
    existingUsers.set(account.email, user);
  } else {
    const { data, error } = await supabase.auth.admin.updateUserById(user.id, {
      password: demoPassword,
      email_confirm: true,
      user_metadata: { ...user.user_metadata, full_name: account.name, demo_account: true },
    });
    if (error) throw error;
    user = data.user;
  }

  const { error: profileError } = await supabase.from("profiles").upsert({ id: user.id, full_name: account.name }, { onConflict: "id" });
  if (profileError) throw profileError;
  const { error: memberError } = await supabase.from("org_members").upsert({
    organization_id: organization.id,
    user_id: user.id,
    role: account.role,
    title: account.name.replace("Demo ", ""),
    department: account.department,
    status: "active",
    joined_at: new Date().toISOString(),
  }, { onConflict: "organization_id,user_id" });
  if (memberError) throw memberError;

  const { error: clearRolesError } = await supabase.from("role_assignments").delete()
    .eq("organization_id", organization.id).eq("user_id", user.id);
  if (clearRolesError) throw clearRolesError;
  const roleId = account.permissions && rolesByName.get(`${account.department} demo`);
  if (roleId) {
    const { error: assignmentError } = await supabase.from("role_assignments").insert({
      organization_id: organization.id,
      user_id: user.id,
      role_id: roleId,
    });
    if (assignmentError) throw assignmentError;
  }
}

console.log("Local demo accounts are ready for Let’s Go Digitals.");
console.log(`Password for all accounts: ${demoPassword}`);
for (const account of demoAccounts) console.log(`${account.name} (${account.department}): ${account.email}`);
console.log("Local development only. Do not use these credentials on a deployed environment.");
