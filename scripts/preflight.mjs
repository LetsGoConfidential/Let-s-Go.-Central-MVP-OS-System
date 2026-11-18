import { existsSync, readFileSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const root = process.cwd();
const envPath = resolve(root, ".env.local");
const required = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "NEXT_PUBLIC_SITE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "AUTOMATION_WORKER_SECRET",
];
const placeholderPattern = /^(your-|replace-with-|changeme|example$)/i;
const values = new Map();

function parseEnv(source) {
  for (const line of source.split(/\r?\n/)) {
    const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!match) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/, "").trim();
    }
    values.set(match[1], value);
  }
}

function report(label, ok, detail) {
  console.log(`${ok ? "PASS" : "BLOCK"}  ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
}

function usable(name) {
  const value = values.get(name)?.trim();
  return Boolean(value && !placeholderPattern.test(value));
}

function validUrl(name) {
  if (!usable(name)) return false;
  try {
    const url = new URL(values.get(name));
    return ["http:", "https:"].includes(url.protocol) && Boolean(url.hostname);
  } catch {
    return false;
  }
}

function commandAvailable(command, args) {
  const executable = process.platform === "win32" ? `${command}.exe` : command;
  const result = spawnSync(executable, args, { cwd: root, stdio: "ignore" });
  return !result.error && result.status === 0;
}

let failures = 0;
if (existsSync(envPath)) parseEnv(readFileSync(envPath, "utf8"));
console.log("Let’s Go Central setup preflight (secret values are never printed)");
report(".env.local exists", existsSync(envPath), existsSync(envPath) ? "loaded locally" : "copy .env.example to .env.local");

for (const name of required) {
  const valid = name.endsWith("_URL") ? validUrl(name) : usable(name);
  const note = valid ? "configured" : "missing, blank, or still a placeholder";
  report(`${name}`, valid, note);
}

const workerSecret = values.get("AUTOMATION_WORKER_SECRET") ?? "";
report("automation worker secret length", workerSecret.length >= 32, workerSecret.length >= 32 ? "at least 32 characters" : "use an independently generated secret of at least 32 characters");

const slackNames = ["SLACK_CLIENT_ID", "SLACK_CLIENT_SECRET", "OAUTH_STATE_SECRET", "INTEGRATION_ENCRYPTION_KEY_BASE64"];
const slackConfigured = slackNames.every(usable);
const slackStarted = slackNames.some(usable);
report("Slack OAuth configuration", slackConfigured || !slackStarted, slackConfigured ? "configured" : slackStarted ? "partial configuration; set all four server-only values" : "optional until Slack is enabled");
if (usable("OAUTH_STATE_SECRET")) report("OAuth state secret length", values.get("OAUTH_STATE_SECRET").length >= 32, "at least 32 characters");
if (usable("INTEGRATION_ENCRYPTION_KEY_BASE64")) {
  const key = Buffer.from(values.get("INTEGRATION_ENCRYPTION_KEY_BASE64"), "base64");
  const valid = key.length === 32 && key.toString("base64") === values.get("INTEGRATION_ENCRYPTION_KEY_BASE64");
  report("integration encryption key", valid, valid ? "valid base64 for 32 bytes" : "must be base64 encoding of exactly 32 random bytes");
}

const aiNames = ["OPENAI_API_KEY", "OPENAI_MODEL"];
const aiConfigured = aiNames.every(usable);
const aiStarted = aiNames.some(usable);
report("AI provider configuration", aiConfigured || !aiStarted, aiConfigured ? "configured" : aiStarted ? "partial configuration; set both server-only values" : "optional until AI is enabled");

const migrationDir = resolve(root, "supabase", "migrations");
const migrations = existsSync(migrationDir)
  ? readdirSync(migrationDir).filter((name) => /^\d{12}_.+\.sql$/.test(name)).sort()
  : [];
const migrationNumbers = migrations.map((name) => Number(name.slice(8, 12)));
const expectedCount = 27;
const sequential = migrationNumbers.length === expectedCount && migrationNumbers.every((value, index) => value === migrationNumbers[0] + index);
report("database migrations", sequential, sequential ? `${migrations.length} ordered files found` : `expected ${expectedCount} sequential files, found ${migrations.length}`);

const nodeMajor = Number(process.versions.node.split(".")[0]);
report("Node.js version", nodeMajor >= 20, `${process.versions.node} (20 or newer required)`);
report("Supabase CLI", commandAvailable("supabase", ["--version"]), "install the CLI to apply and regenerate the local schema snapshot");
report("Docker", commandAvailable("docker", ["info"]), "required for local Supabase services");

console.log(failures ? `\n${failures} setup blocker(s) found.` : "\nPreflight passed. Continue with local Supabase reset and auth setup.");
process.exitCode = failures ? 1 : 0;
