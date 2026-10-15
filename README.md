# Let’s Go Central

Let’s Go Central is an agency operating system for sales, client management, project delivery, content, team capacity, and finance. Let’s Go Digitals is the first tenant and the product’s proving ground.

## Stack

- Next.js 16 App Router and TypeScript for the web application
- Supabase Auth and managed PostgreSQL for identity and data
- PostgreSQL row-level security (RLS) as the tenant isolation boundary
- Supabase Storage for client and project files
- Provider adapters for AI, automation, and external integrations

## Get started

1. Install Node.js 20.9 or newer and the Supabase CLI.
2. Run `pnpm install`.
3. Copy `.env.example` to `.env.local` and add the Supabase project URL and publishable key.
4. Run `pnpm dlx supabase start` for local services.
5. Run `pnpm dlx supabase db reset` to apply migrations 001-024 and insert the Let’s Go Digitals starter tenant.
6. Run `pnpm dev` and open `http://localhost:3000`.

After applying migrations, refresh the checked-in database type snapshot with `pnpm db:types`. This command uses the Supabase CLI and the local database schema; the committed snapshot is currently kept in sync with migrations 001-024 until a local database is available for CLI generation.

The root route (`/`) is a Figma-inspired illustrative preview. After configuring Supabase and linking the founder account to the seeded tenant (or creating a workspace through `/workspace` onboarding), the dashboard shows live organization-scoped counts and audit activity. The workspace picker only lists active memberships. Never expose a service-role key in the browser.

To send team invitations and password reset links, configure `SUPABASE_SERVICE_ROLE_KEY` as a server-only environment variable, set `NEXT_PUBLIC_SITE_URL` to the app's public origin, allow `/auth/callback` in Supabase Auth redirect URLs, and configure Auth email delivery. Existing Supabase accounts can be added directly to the organization by an authorized administrator. New accounts accept the emailed invitation before their membership becomes active. The login page sends password reset links with a non-enumerating response; the authenticated reset page requires at least 12 characters.

To connect Slack, create a Slack app, enable OAuth, and register `{NEXT_PUBLIC_SITE_URL}/auth/integrations/slack/callback` as its redirect URL. Add `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, `OAUTH_STATE_SECRET`, and `INTEGRATION_ENCRYPTION_KEY_BASE64` to the server environment; generate the latter two as independent secrets (for example, with Node's `crypto.randomBytes(32)`, base64-encoding the encryption key). Never put these values in a `NEXT_PUBLIC_` variable or commit real secrets. The app requests `chat:write`; invite its bot user to a channel, then use that channel's ID in the integration card to send a message. If Slack token rotation is enabled, rotated credentials are saved back to the encrypted server-side vault.

To use the AI Command Center, configure server-only `OPENAI_API_KEY` and `OPENAI_MODEL` values for a model available to your API project. The assistant receives a limited snapshot of the active organization and recent workflow records. Finance totals are added only for members with `finance.manage`. It can prepare an editable task proposal, but a workspace member must explicitly confirm the task before the database transaction creates it; the confirmed write is audited. Conversation replies and token counts are stored in the workspace, while OpenAI response storage is disabled for requests. Each member can make up to 10 AI requests per minute. Set `OPENAI_INPUT_USD_PER_1M_TOKENS` and `OPENAI_OUTPUT_USD_PER_1M_TOKENS` to current prices for the configured model to show estimated request costs and enable an organization budget cap. Organization owners/admins can set the monthly USD cap in the AI Command Center; each request reserves an estimated amount first and records token-based cost afterward. A cap starts when enabled and resets at the next UTC month boundary; earlier unpriced usage is not retroactively counted. This is a conservative estimate, not a billing reconciliation: keep model prices current, and reconcile against provider invoices before using it for billing decisions.

Scheduled automations and queued new-lead events use the shared worker endpoint `POST /api/automation/worker`. Set a server-only `AUTOMATION_WORKER_SECRET` with at least 32 characters, then configure your hosting scheduler to send `Authorization: Bearer <secret>` at least every 15 minutes. The worker processes up to 20 due jobs per call; schedule rules can run hourly, daily, or weekly. New-lead rules queue one task per enabled rule and lead, with `{{company_name}}` available in the task title and description. Manual task runs do not depend on the scheduler.

To link the first founder account to the seeded Let’s Go Digitals workspace, create the account through Supabase Auth, then run this once in the Supabase SQL editor with that account's UUID (from Authentication → Users):

```sql
insert into public.org_members (organization_id, user_id, role, status, joined_at)
select id, 'PASTE_AUTH_USER_UUID_HERE'::uuid, 'owner', 'active', now()
from public.organizations where slug = 'lets-go-digitals'
on conflict (organization_id, user_id) do update set role = 'owner', status = 'active', joined_at = now();
```

## Project map

- `app/` — app shell and founder dashboard
- `lib/` — Supabase clients and domain helpers
- `supabase/migrations/` — database schema, RLS, roles, and audit foundation
- `supabase/seed.sql` — first tenant and safe demo records
- `docs/architecture.md` — architecture decisions and system boundaries
- `docs/implementation-plan.md` — phased delivery plan and acceptance criteria
- `docs/product-walkthrough.md` — how to start the app and navigate the product screens step by step
- `docs/product-review-guide.md` — implemented route/status map and a structured way to review mismatches
- `docs/ui-ux-direction.md` — shared visual and interaction principles for the UI refresh

## Tenant rule

Every customer-owned record has an `organization_id`. Every exposed table has RLS enabled. Requests are authorized through the signed-in user's organization membership and database permissions; the UI is never the security boundary.
