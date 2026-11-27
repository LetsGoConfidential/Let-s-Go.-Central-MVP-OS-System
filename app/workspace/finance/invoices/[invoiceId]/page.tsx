import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PrintButton } from "./print-button";
import styles from "./invoice.module.css";

type Invoice = {
  id: string;
  organization_id: string;
  client_id: string;
  invoice_number: string;
  status: string;
  currency: string;
  subtotal: number;
  tax: number;
  total: number;
  credit_total: number;
  amount_paid: number;
  issue_date: string | null;
  due_date: string | null;
  purchase_order_number: string;
  document_notes: string;
  document_terms: string;
  signature_label: string;
};
type LineItem = { id: string; group_name: string; description: string; quantity: number; unit: string; unit_price: number; line_total: number };

function money(value: number, currency: string) {
  try { return new Intl.NumberFormat("en-IN", { style: "currency", currency: currency.trim(), maximumFractionDigits: 2 }).format(value); }
  catch { return `${currency.trim()} ${value.toLocaleString("en-IN")}`; }
}

function dateLabel(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-IN", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`));
}

export default async function InvoicePreviewPage({
  params,
  searchParams,
}: {
  params: Promise<{ invoiceId: string }>;
  searchParams: Promise<{ organization?: string }>;
}) {
  const [{ invoiceId }, query] = await Promise.all([params, searchParams]);
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: members } = await supabase.from("org_members").select("organization_id")
    .eq("user_id", user.id).eq("status", "active");
  const memberRows = members ?? [];
  const membership = memberRows.find((row) => row.organization_id === query.organization) ?? memberRows[0];
  if (!membership) redirect("/workspace");

  const { data: hasFinanceAccess } = await supabase.rpc("has_org_permission", {
    target_org: membership.organization_id,
    permission_key: "finance.manage",
  });
  if (!hasFinanceAccess) redirect(`/workspace/finance?organization=${encodeURIComponent(membership.organization_id)}&error=forbidden`);

  const { data: rawInvoice } = await supabase.from("invoices").select(
    "id,organization_id,client_id,invoice_number,status,currency,subtotal,tax,total,credit_total,amount_paid,issue_date,due_date,purchase_order_number,document_notes,document_terms,signature_label",
  ).eq("id", invoiceId).eq("organization_id", membership.organization_id).maybeSingle();
  if (!rawInvoice) notFound();
  const invoice = rawInvoice as Invoice;

  const [{ data: organization }, { data: client }, { data: rawItems }] = await Promise.all([
    supabase.from("organizations").select("name,legal_name").eq("id", invoice.organization_id).maybeSingle(),
    supabase.from("clients").select("name").eq("organization_id", invoice.organization_id).eq("id", invoice.client_id).maybeSingle(),
    supabase.from("invoice_items").select("id,group_name,description,quantity,unit,unit_price,line_total")
      .eq("organization_id", invoice.organization_id).eq("invoice_id", invoice.id).order("created_at"),
  ]);
  const lineItems = (rawItems ?? []) as LineItem[];
  const balance = Math.max(0, Number(invoice.total) - Number(invoice.credit_total) - Number(invoice.amount_paid));
  const isDraft = invoice.status === "draft";

  return <main className={styles.page}>
    <nav className={styles.actions} aria-label="Invoice actions">
      <a href={`/workspace/finance?organization=${invoice.organization_id}`}>← Invoices & billing</a>
      <PrintButton />
    </nav>
    <article className={styles.document}>
      <header className={styles.header}>
        <div className={styles.brandBlock}>
          <div className={styles.brand}>LET’S GO.<span>CENTRAL OS</span></div>
          <b>{organization?.legal_name || organization?.name || "Let’s Go Digitals"}</b>
          {organization?.legal_name && organization.name !== organization.legal_name && <small>{organization.name}</small>}
        </div>
        <div className={styles.documentHeading}>
          <span className={styles.eyebrow}>SALES DOCUMENT</span>
          <h1>Invoice</h1>
          <span className={`${styles.status} ${isDraft ? styles.draft : ""}`}>{invoice.status.replaceAll("_", " ")}</span>
        </div>
      </header>

      {isDraft && <div className={styles.draftNotice} role="note">Draft preview · This document has not been issued to the client.</div>}
      {Number(invoice.tax) > 0 && <div className={styles.taxNotice} role="note">Tax is manually entered and has not been checked against GST rules. Verify the amount before issuing.</div>}

      <section className={styles.metaGrid} aria-label="Invoice details">
        <div><span>Invoice number</span><b>{invoice.invoice_number}</b></div>
        <div><span>Invoice date</span><b>{dateLabel(invoice.issue_date)}</b></div>
        <div><span>Due date</span><b>{dateLabel(invoice.due_date)}</b></div>
        {invoice.purchase_order_number && <div><span>PO / reference</span><b>{invoice.purchase_order_number}</b></div>}
      </section>

      <section className={styles.parties}>
        <div><span>FROM</span><h2>{organization?.legal_name || organization?.name || "Let’s Go Digitals"}</h2><p>Let’s Go Digitals workspace</p></div>
        <div><span>BILL TO</span><h2>{client?.name ?? "Client"}</h2><p>Client billing details can be completed in the client profile.</p></div>
      </section>

      <section className={styles.items} aria-label="Invoice line items">
        <div className={styles.tableScroll}><table>
          <thead><tr><th>Description</th><th>Qty</th><th>Rate</th><th>Amount</th></tr></thead>
          <tbody>{lineItems.length ? lineItems.map((item) => <tr key={item.id}>
            <td><b>{item.description}</b>{item.group_name && <small>{item.group_name}</small>}</td>
            <td>{Number(item.quantity).toLocaleString("en-IN")} {item.unit}</td>
            <td>{money(Number(item.unit_price), invoice.currency)}</td>
            <td>{money(Number(item.line_total), invoice.currency)}</td>
          </tr>) : <tr><td colSpan={4}>No line items are available for this invoice.</td></tr>}</tbody>
        </table></div>
      </section>

      {(invoice.document_notes || invoice.document_terms) && <section className={styles.notes}>
        {invoice.document_notes && <div><h2>Notes</h2><p>{invoice.document_notes}</p></div>}
        {invoice.document_terms && <div><h2>Terms & conditions</h2><p>{invoice.document_terms}</p></div>}
      </section>}

      <section className={styles.bottom}>
        <div className={styles.paymentNote}>
          <span>PAYMENT SUMMARY</span>
          <p>Payment methods and bank instructions have not been configured for this workspace.</p>
          {invoice.status === "paid" && <b>Payment recorded as paid.</b>}
        </div>
        <dl className={styles.totals}>
          <div><dt>Subtotal</dt><dd>{money(Number(invoice.subtotal), invoice.currency)}</dd></div>
          <div><dt>Tax <small>(manual amount)</small></dt><dd>{money(Number(invoice.tax), invoice.currency)}</dd></div>
          {Number(invoice.credit_total) > 0 && <div><dt>Credits</dt><dd>− {money(Number(invoice.credit_total), invoice.currency)}</dd></div>}
          <div className={styles.grandTotal}><dt>Total</dt><dd>{money(Number(invoice.total), invoice.currency)}</dd></div>
          {Number(invoice.amount_paid) > 0 && <div><dt>Amount paid</dt><dd>{money(Number(invoice.amount_paid), invoice.currency)}</dd></div>}
          <div className={styles.balance}><dt>Balance due</dt><dd>{money(balance, invoice.currency)}</dd></div>
        </dl>
      </section>

      {invoice.signature_label && <section className={styles.signature}>
        <span className={styles.signatureLine} />
        <b>{invoice.signature_label}</b>
        <small>Signature image is not configured.</small>
      </section>}

      <footer className={styles.footer}>
        <span>Prepared in Let’s Go Central · {organization?.name ?? "Agency workspace"}</span>
        <small>This preview uses the financial records currently saved in the workspace. It is not a verified tax invoice.</small>
      </footer>
    </article>
  </main>;
}
