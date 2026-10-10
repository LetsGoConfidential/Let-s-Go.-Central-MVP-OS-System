import { createClient } from "@/lib/supabase/server";

function csvCell(value: string | number | null) {
  let text = value === null ? "" : String(value);
  if (typeof value === "string" && /^[\s]*[=+@-]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export async function GET(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401 });
  const organizationId = new URL(request.url).searchParams.get("organization") ?? "";
  if (!organizationId) return new Response("Organization required", { status: 400 });
  const { data: allowed } = await supabase.rpc("has_org_permission", {
    target_org: organizationId,
    permission_key: "finance.manage",
  });
  if (!allowed) return new Response("Forbidden", { status: 403 });

  const { data: invoices, error } = await supabase.from("invoices")
    .select("id,invoice_number,status,currency,subtotal,tax,total,credit_total,amount_paid,issue_date,due_date,created_at,clients(name)")
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });
  if (error) return new Response("Export unavailable", { status: 500 });
  const ids = (invoices ?? []).map(({ id }) => id);
  const { data: items, error: itemError } = ids.length
    ? await supabase.from("invoice_items").select("invoice_id,description,quantity,unit_price,line_total").eq("organization_id", organizationId).in("invoice_id", ids).order("created_at")
    : { data: [], error: null };
  if (itemError) return new Response("Export unavailable", { status: 500 });
  const { data: credits, error: creditError } = ids.length
    ? await supabase.from("invoice_credits").select("invoice_id,credit_number,amount,reason").eq("organization_id", organizationId).in("invoice_id", ids).order("issued_at")
    : { data: [], error: null };
  if (creditError) return new Response("Export unavailable", { status: 500 });
  const { data: refunds, error: refundError } = ids.length
    ? await supabase.from("invoice_refunds").select("invoice_id,amount,reason").eq("organization_id", organizationId).in("invoice_id", ids)
    : { data: [], error: null };
  if (refundError) return new Response("Export unavailable", { status: 500 });

  const headings = ["Invoice number", "Client", "Status", "Currency", "Description", "Quantity", "Unit price", "Line total", "Subtotal", "Tax", "Invoice total", "Credit total", "Credit notes", "Refund total", "Refunds", "Net paid", "Balance due", "Issue date", "Due date"];
  const rows = (invoices ?? []).flatMap((invoice) => {
    const client = Array.isArray(invoice.clients) ? invoice.clients[0]?.name ?? "" : invoice.clients?.name ?? "";
    const invoiceItems = (items ?? []).filter((item) => item.invoice_id === invoice.id);
    const invoiceCredits = (credits ?? []).filter((credit) => credit.invoice_id === invoice.id);
    const creditNotes = invoiceCredits.map((credit) => `${credit.credit_number}: ${credit.reason} (${credit.amount})`).join("; ");
    const invoiceRefunds = (refunds ?? []).filter((refund) => refund.invoice_id === invoice.id);
    const refundTotal = invoiceRefunds.reduce((sum, refund) => sum + Number(refund.amount), 0);
    const refundDetails = invoiceRefunds.map((refund) => `${refund.reason} (${refund.amount})`).join("; ");
    const lines = invoiceItems.length ? invoiceItems : [null];
    return lines.map((item) => [invoice.invoice_number, client, invoice.status, invoice.currency.trim(), item?.description ?? "", item?.quantity ?? "", item?.unit_price ?? "", item?.line_total ?? "", invoice.subtotal, invoice.tax, invoice.total, invoice.credit_total, creditNotes, refundTotal, refundDetails, invoice.amount_paid, Math.max(0, Number(invoice.total) - Number(invoice.credit_total) - Number(invoice.amount_paid)), invoice.issue_date, invoice.due_date].map(csvCell).join(","));
  });
  const body = [headings.map(csvCell).join(","), ...rows].join("\r\n");
  return new Response(`\uFEFF${body}`, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="lets-go-finance-${new Date().toISOString().slice(0, 10)}.csv"`,
      "Cache-Control": "private, no-store",
    },
  });
}
