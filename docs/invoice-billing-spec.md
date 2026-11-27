# Invoice & billing product slice

## Reference review

Reviewed the user's existing Refrens invoice dashboard and new-invoice flow in Chrome. The observed workflow supports reusable document formats, invoice numbering and dates, PO numbers, client selection, GST/currency, grouped line items, payment details, discount/additional charges, signatures, notes/attachments, terms, recurring invoices, and invoice/payment/GST/client/project reports. No customer records or bank/payment identifiers are included in this specification.

## Product structure

Keep this as one **Invoices & Billing** area, with inner sections:

- Overview: draft/sent/overdue/paid totals, outstanding balances, collection trend, and next actions.
- Invoices: search, status/date/client filters, duplicate, draft, issue, record partial payment, credit/refund, and reminders.
- Quotations: create, send, accept/decline, expire, convert accepted quote to invoice while preserving line items.
- Templates: choose from service retainer, project milestone, one-time service, GST tax invoice, and quotation formats; organization admins can edit and save versions.
- Recurring: interval, start/end, next-run visibility, and draft generation; do not auto-send without explicit organization setup.
- Reports: client aging, invoice/payment, project margin, tax/GST, and line-item views.

### Sales document types from the supplied reference

Expose a document-type switcher for **Quotation & Estimate**, **Proforma Invoice**, **Tax Invoice**, **Payment Receipt**, **Sales Order**, **Delivery Challan**, and **Credit Note**. These types have different lifecycle and accounting effects; a quotation is not an invoice, a receipt records payment, a challan records delivery, and a credit note adjusts an issued invoice. The current app already has invoice, payment, and credit-note records; other document types need their own states and permissions before they can be issued.

The invoice editor should support grouped service sections, multi-line deliverables, per-row quantity/unit/rate, optional descriptions/images, and a clear subtotal → discount/charges → GST split → total → amount paid → balance. Payment presentation may include configured bank/UPI methods and a QR, but those details must come from approved organization settings and be absent from the preview's fictional data. A signature block, notes, attachments, tax summary, and ordered terms can be enabled per template.

Recurring invoices need a cadence, first issue date, end condition, next-run preview, and an after-generation policy: create draft (default), create/save draft for review, or send via configured email/WhatsApp only after an explicit organization-level opt-in and recipient consent. Failed deliveries need visible retry/error status; do not silently mark a document sent.

## Common document fields

Client/contact, organization issuer details, document number series, issue/due/valid-until date, PO/reference number, currency, service/item description, SKU/HSN/SAC and unit, quantity, rate, discount, tax configuration, extra charge, subtotal/total, payment instructions, notes, attachments, terms, signature, and status history. Tax rates and numbering formats are organization-configured; the UI must not imply tax/legal compliance without correct configuration.

## Access and lifecycle

Finance permission controls create/edit/issue/payment/export actions. Clients only receive a deliberately published document through an approved share/send action. Edits after issue create an auditable revision or credit/debit workflow; paid balance is reconciled from immutable payment records. A quotation conversion is idempotent and preserves source linkage. Template changes are versioned and do not rewrite prior documents.

## Build order

1. UI shell, five templates, common document editor, invoice/quotation lists.
2. Quote lifecycle and conversion; improve validation and line-item editing.
3. PDF render/preview and reviewed email delivery with explicit confirmation.
4. Payment reconciliation, recurring draft scheduler, client/project reports, and CSV/PDF export.
5. Tenant/role tests for every action, GST calculation review, accessibility, and browser walkthrough.

## Current implementation

The app supports tenant-scoped invoices, grouped multi-line items, PO/reference numbers, up to 20 document custom fields, payments, credit notes, refunds, expense records, finance summaries, reports, and permission-gated export. Invoice and quotation drafts accept up to 50 service/deliverable lines with optional group labels, quantity, unit, and rate; totals recalculate from all lines. Quotations have their own draft/sent/accepted/declined/expired/converted lifecycle, line-item totals, audit history, tenant RLS, and an idempotent conversion into a draft invoice that preserves every line, group, unit, PO/reference, custom field, tax amount, source link, and selected template snapshot. Issued document references are immutable. Finance permission is required for changes, and non-members cannot read another tenant's quotes.

Each workspace is provisioned with four invoice formats and one quotation format. Finance owners can publish a new version with layout, accent, grouping, tax summary, signature, and terms settings; each new draft captures a settings snapshot so template updates do not rewrite older records. The document forms remain a first usable slice: tax is entered as an amount and advanced document settings are not all implemented. The supplied Refrens flow still guides the next work: attachment handling, full signature and terms editor, verified GST rules, rendered PDF preview, explicit email/WhatsApp send, recurring draft generation, and detailed reports. No email/WhatsApp delivery or public client acceptance link is claimed by the current status buttons; they only record internal workflow state. Tax is not calculated automatically and the screen tells operators to configure verified rules before issuing documents. Concept previews remain sample-only and do not create financial records.
