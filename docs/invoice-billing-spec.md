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

The app already supports tenant-scoped invoices, line items, payments, credit notes, refunds, expense records, reports, and permission-gated finance export. Dedicated quotation lifecycle, reusable invoice templates, PDF/email delivery, recurring invoices, and GST configuration are not yet implemented. Concept previews use sample data and do not create financial records.
