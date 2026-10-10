# Let’s Go Central — UI/UX direction

## Product promise

One calm home for running an agency: understand what needs attention, know who owns the next step, and move client work from lead to delivery to payment without losing context.

## Visual direction

- **Look:** modern, premium, clear, approachable B2B SaaS. Use a deep navy navigation rail, bright neutral canvas, white surfaces, restrained blue actions, mint success, and amber attention.
- **Type:** readable sans serif with strong distinction between page title, card heading, metric, labels, and supporting detail.
- **Density:** show useful operational information without dashboard clutter. Four primary KPIs maximum before the first action panel; tables and cards use concise labels and generous spacing.
- **Navigation:** fixed left rail groups daily work (Overview, Sales, Clients, Projects, Content, Tasks, Team, Finance, Reports) separately from tools (AI, Automations, Integrations). Current location and urgent counts stay visible.
- **Responsive:** keep a compact icon rail on smaller screens; allow dense boards and tables to scroll horizontally; preserve primary create actions.

## UX rules

1. **Prioritize the next action.** Lead with overdue work, approvals, project risks, and receivables that need follow-up. Each alert should open the relevant record or list.
2. **Keep relationships connected.** A lead can become a client; clients own contacts and delivery work; projects group tasks and content; invoices connect to clients. Show this context on list rows and detail pages.
3. **Make status understandable.** Use consistent named states and color chips. Color never carries meaning alone. Status changes should explain what happens next.
4. **Make ownership and timing visible.** Show one accountable owner and a clear deadline on leads, projects, tasks, content, and finance follow-ups.
5. **Use progressive disclosure.** Lists support scanning and common actions. Details pages hold notes, history, related records, and less frequent controls.
6. **Use safe defaults.** New automations start paused; AI can explain and summarize before it can write; integration credentials never appear in UI.
7. **Respect the tenant.** The organization switcher sets the workspace context. Every screen, search, count, and action stays inside that organization and follows the member’s role.
8. **Treat numbers as decisions.** Every dashboard metric has a useful period, currency, or count definition and links to the records behind it.

## Dashboard hierarchy

1. Greeting, current organization, quick-create action.
2. Four cards: revenue collected, open pipeline, delivery health, receivables.
3. Two-column block: revenue/pipeline trend and actionable attention queue.
4. Client portfolio with health and work summary beside recent activity.

## MVP design scope

The clickable [UI concept](../outputs/central-ui-ux-concept.html) explores the dashboard and the main operational modules using illustrative records. It is a visual and interaction prototype only. The production application remains the source of truth for authentication, permissions, tenant-scoped records, finance calculations, automation, and AI behavior.

The existing Figma file remains the visual reference. Figma edits are pending tool availability; do not share Figma passwords in chat. If another account is used later, connect it through the official Figma authorization flow.
