# Let’s Go Central — Product Walkthrough

Yeh guide abhi tak bane product ko screen par dekhne aur main workflow ko samajhne ke liye hai. Screens ka visual direction Let’s Go Central Figma design follow karta hai.

## Figma visual reference

[Let’s Go Central OS — Figma](https://www.figma.com/design/VHeqOS2Rbe3Rx6xQhE8qF4/Lets-Go-Central-OS?node-id=3-169)

Content screen mein left sidebar, content calendar, client labels, aur Draft / Review / Approved / Scheduled states dikhte hain. App implementation ab isi workflow ko week/month navigation, tenant-scoped client assignment, aur timezone-aware scheduling ke saath aage badhati hai.

## Quick visual review

Open the [clickable UI concept](../outputs/central-ui-ux-concept.html) in your browser. Left sidebar se Overview, Sales, Clients, Projects, Tasks, Content, Finance, Team, Reports, AI, Automations, aur Integrations screens dekh sakte hain. **Build status** screen specifically batata hai kya code mein ready hai, kya setup chahiye, aur kya abhi planned hai. Concept ka data sample hai; actual app routes ke exact screenshots/live records nahi.

For the accurate screen-by-screen code status and review-notes template, open the [product review guide](./product-review-guide.md).

## Local app ko open karne ke steps

Yeh repo ek Next.js app hai. Pehli baar local preview chalane ke liye:

1. Project folder terminal mein kholen: `C:\Users\jankhan patel\Documents\Codex\2026-09-30\build-let-s-go-central-mvp`.
2. Dependencies install karein: `pnpm install`.
3. `.env.example` ko `.env.local` mein copy karein aur Supabase URL + publishable key set karein.
4. Local Supabase start aur seed karein: `pnpm dlx supabase start`, phir `pnpm dlx supabase db reset`.
5. Founder account create karke usko `lets-go-digitals` tenant ka owner banayein. SQL snippet ke liye [README setup](../README.md#to-link-the-first-founder-account-to-the-seeded-lets-go-digitals-workspace) dekhein.
6. App start karein: `pnpm dev`.
7. Browser mein `http://localhost:3000` kholen.

Is workspace mein abhi `.env.local` aur installed `node_modules` maujood nahi the, isliye is turn mein live local server nahi dikhaya ja saka. Root page Figma-inspired illustrative preview hai; real tenant data ke liye Supabase setup aur sign-in zaroori hain.

Sign in ke baad agar account ka koi active organization nahi hai, `/workspace` par apni company ka workspace name set karke create karein. Aap owner banenge. Dashboard ke left workspace picker mein sirf aapki active memberships wale organizations dikhte hain. Seeded Let’s Go Digitals organization ko use karne ke liye pehle [README ke founder setup steps](../README.md#to-link-the-first-founder-account-to-the-seeded-lets-go-digitals-workspace) follow karein.

## Screen-by-screen tour

Organization id har URL mein `?organization=<org-id>` se select hoti hai. Signed-in owner ke liye app ke workspace sidebar aur ye direct routes use karein:

| Step | Screen | Route | Kya dekhen / karein |
|---|---|---|---|
| 1 | Overview | `/workspace` | Agency counts, revenue/receivables, attention items, recent activity. |
| 2 | Sales & CRM | `/workspace/sales` | Leads, pipeline stages aur estimated deal value; lead kholkar detail aur next action dekhen. |
| 3 | Lead detail | `/workspace/sales/<lead-id>` | Contact, stage, next follow-up; Won lead ko client mein convert karein. |
| 4 | Clients | `/workspace/clients` | Client directory; kisi client ko kholkar contacts, projects aur invoice balance dekhen. |
| 5 | Projects | `/workspace/projects` | Client-linked delivery projects aur status/priority/due date. |
| 5a | Project detail | `/workspace/projects/<project-id>` | Scope, client, budget, delivery dates, linked tasks, finance-restricted expenses aur project audit history. |
| 6 | Tasks | `/workspace/tasks` | Owners, priorities, due dates, blockers aur completion status. Kisi task ke title par click karke details edit karein aur progress/blocker update post karein. |
| 6a | Task detail | `/workspace/tasks/<task-id>` | Brief, status, priority, due date, project/client context aur append-only activity comments. |
| 7 | Content calendar | `/workspace/content?view=week` | Week/month switch karein, client select karke publish date dein; planned post calendar par dikhega. |
| 8 | Content detail | `/workspace/content/<item-id>` | Calendar/pipeline item kholkar project, caption/copy, publish date aur review feedback manage karein. |
| 9 | Finance | `/workspace/finance` | Invoices, payments, receivables aur expenses. |
| 9a | Reports | `/workspace/reports?days=90` | Current lead outcomes/client health aur trailing-period task timeliness/team workload. Period tabs 30, 90, 365 din switch karte hain. |
| 10 | Team | `/workspace/team` | Members, access, invites, and task workload. Open a member for assigned-task detail and permission-gated monthly performance check-ins. Role/permission editor: `/workspace/team/roles`. |
| 11 | Automations | `/workspace/automations` | Task automation rules, schedule aur run history. |
| 12 | Integrations | `/workspace/integrations` | Connected provider status aur integration setup. |
| 13 | AI Command Center | `/workspace/ai` | Organization context ke read-only Q&A ke alawa task ka editable draft banayein; review karke **Confirm and create task** dabane ke baad hi task save hota hai. |
| 14 | Files | `/workspace/files` | Organization-scoped private file library. |
| 15 | Audit history | `/workspace/audit` | Kisne kya action kiya, entity aur time ke saath. |

Password bhool gaye hon to `/login` par work email daal kar **Send reset link** chunein. Email link session establish karega aur `/auth/reset-password` par naya password set karne dega. Is flow ke liye Supabase Auth email delivery aur deployed callback URL allowlist configured honi chahiye.

## 5-minute sample walkthrough

1. Overview se Sales & CRM kholen.
2. Existing lead select karein ya test lead banayein.
3. Lead detail par next action/date set karein; sample lead Won ho to conversion flow dekhein.
4. Naye bane client ko Clients page par kholen; uske liye project aur task banayein.
5. Content page par `New content` select karein, client assign karein aur publish date dein. Calendar mein Week aur Month switch karke item locate karein.
6. Finance, Team, Automations, Integrations aur AI screens dekh kar flow ko end-to-end samjhein.

## Preview data aur real data

Home page par “Illustrative preview” label ke saath jo numbers/names dikhte hain woh sample UI content hain. Signed-in `/workspace` screens tenant database se data load karte hain. Let’s Go Digitals first tenant hai; har real record organization ke saath scoped hai. External provider actions ke liye credentials (jaise Slack/OpenAI) alag se configure karne padte hain.
