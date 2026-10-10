"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function authorizedFinanceClient(organizationId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: allowed } = await supabase.rpc("has_org_permission", {
    target_org: organizationId,
    permission_key: "finance.manage",
  });
  if (!allowed) redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&error=forbidden`);
  return supabase;
}

function fail(organizationId: string, reason = "invalid"): never {
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&error=${reason}`);
}

export async function createInvoice(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const clientId = String(formData.get("client_id") ?? "");
  const invoiceNumber = String(formData.get("invoice_number") ?? "").trim();
  const currency = String(formData.get("currency") ?? "INR").toUpperCase();
  const description = String(formData.get("line_description") ?? "").trim();
  const quantity = Number(formData.get("quantity") ?? 0);
  const unitPrice = Number(formData.get("unit_price") ?? -1);
  const tax = Number(formData.get("tax") ?? 0);
  const issueDate = String(formData.get("issue_date") ?? "");
  const dueDate = String(formData.get("due_date") ?? "");
  if (!organizationId || !clientId || invoiceNumber.length < 2 || invoiceNumber.length > 40 || !/^[A-Z]{3}$/.test(currency) || description.length < 1 || description.length > 240 || !Number.isFinite(quantity) || quantity <= 0 || quantity > 9999999999 || !Number.isFinite(unitPrice) || unitPrice < 0 || unitPrice > 999999999999.99 || !Number.isFinite(tax) || tax < 0 || tax > 999999999999.99 || quantity * unitPrice + tax > 999999999999.99 || !issueDate || !dueDate || dueDate < issueDate) fail(organizationId);

  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.rpc("create_invoice_with_item", {
    target_org: organizationId,
    target_client: clientId,
    new_invoice_number: invoiceNumber,
    invoice_currency: currency,
    invoice_tax: tax,
    new_issue_date: issueDate,
    new_due_date: dueDate,
    line_description: description,
    line_quantity: quantity,
    line_unit_price: unitPrice,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=invoice`);
}

export async function markInvoiceSent(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const invoiceId = String(formData.get("invoice_id") ?? "");
  if (!organizationId || !invoiceId) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.from("invoices").update({ status: "sent" }).eq("id", invoiceId).eq("organization_id", organizationId).eq("status", "draft");
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&updated=invoice`);
}

export async function recordPayment(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const invoiceId = String(formData.get("invoice_id") ?? "");
  const amount = Number(formData.get("amount") ?? 0);
  const method = String(formData.get("method") ?? "other");
  const allowedMethods = ["bank_transfer", "cash", "card", "cheque", "other"];
  if (!organizationId || !invoiceId || !Number.isFinite(amount) || amount <= 0 || amount > 999999999999.99 || !allowedMethods.includes(method)) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { data: { user } } = await supabase.auth.getUser();
  const { data: invoice, error: invoiceError } = await supabase.from("invoices").select("id,total,credit_total,amount_paid,currency,status").eq("id", invoiceId).eq("organization_id", organizationId).maybeSingle();
  if (invoiceError || !invoice || ["draft", "void"].includes(invoice.status) || amount > Number(invoice.total) - Number(invoice.credit_total) - Number(invoice.amount_paid)) fail(organizationId);
  const { error } = await supabase.from("invoice_payments").insert({
    organization_id: organizationId,
    invoice_id: invoiceId,
    amount,
    currency: invoice.currency,
    method,
    recorded_by: user?.id,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=payment`);
}

export async function createCreditNote(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const invoiceId = String(formData.get("invoice_id") ?? "");
  const creditNumber = String(formData.get("credit_number") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const amount = Number(formData.get("amount") ?? 0);
  if (!organizationId || !invoiceId || creditNumber.length < 2 || creditNumber.length > 40 || reason.length < 2 || reason.length > 240 || !Number.isFinite(amount) || amount <= 0 || amount > 999999999999.99) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("create_invoice_credit", {
    target_org: organizationId,
    target_invoice: invoiceId,
    new_credit_number: creditNumber,
    credit_amount: amount,
    credit_reason: reason,
    actor_id: user.id,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=credit`);
}

export async function createInvoiceRefund(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const invoiceId = String(formData.get("invoice_id") ?? "");
  const paymentId = String(formData.get("payment_id") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  const amount = Number(formData.get("amount") ?? 0);
  if (!organizationId || !invoiceId || !paymentId || reason.length < 2 || reason.length > 240 || !Number.isFinite(amount) || amount <= 0 || amount > 999999999999.99) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("create_invoice_refund", {
    target_org: organizationId,
    target_invoice: invoiceId,
    target_payment: paymentId,
    refund_amount: amount,
    refund_reason: reason,
    actor_id: user.id,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=refund`);
}

export async function createExpense(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const description = String(formData.get("description") ?? "").trim();
  const category = String(formData.get("category") ?? "").trim();
  const amount = Number(formData.get("amount") ?? 0);
  const spentOn = String(formData.get("spent_on") ?? "");
  const currency = String(formData.get("currency") ?? "INR").toUpperCase();
  if (!organizationId || description.length < 2 || description.length > 180 || category.length < 2 || category.length > 60 || !Number.isFinite(amount) || amount <= 0 || amount > 999999999999.99 || !/^[A-Z]{3}$/.test(currency) || (spentOn && !/^\d{4}-\d{2}-\d{2}$/.test(spentOn))) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from("expenses").insert({
    organization_id: organizationId,
    description,
    category,
    amount,
    currency,
    ...(spentOn ? { spent_on: spentOn } : {}),
    ...(user ? { created_by: user.id } : {}),
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=expense`);
}
