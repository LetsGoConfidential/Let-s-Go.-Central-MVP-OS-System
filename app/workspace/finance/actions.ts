"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isOneOf } from "@/lib/validation";

const paymentMethods = ["bank_transfer", "cash", "card", "cheque", "other"] as const;

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
  const templateId = String(formData.get("document_template_id") ?? "");
  const currency = String(formData.get("currency") ?? "INR").toUpperCase();
  const description = String(formData.get("line_description") ?? "").trim();
  const quantity = Number(formData.get("quantity") ?? 0);
  const unitPrice = Number(formData.get("unit_price") ?? -1);
  const tax = Number(formData.get("tax") ?? 0);
  const issueDate = String(formData.get("issue_date") ?? "");
  const dueDate = String(formData.get("due_date") ?? "");
  if (!organizationId || !clientId || invoiceNumber.length < 2 || invoiceNumber.length > 40 || !/^[A-Z]{3}$/.test(currency) || description.length < 1 || description.length > 240 || !Number.isFinite(quantity) || quantity <= 0 || quantity > 9999999999 || !Number.isFinite(unitPrice) || unitPrice < 0 || unitPrice > 999999999999.99 || !Number.isFinite(tax) || tax < 0 || tax > 999999999999.99 || quantity * unitPrice + tax > 999999999999.99 || !issueDate || !dueDate || dueDate < issueDate) fail(organizationId);

  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.rpc("create_invoice_from_template", {
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
    selected_template: templateId || null,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=invoice`);
}

export async function createQuotation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const clientId = String(formData.get("client_id") ?? "");
  const quotationNumber = String(formData.get("quotation_number") ?? "").trim();
  const templateId = String(formData.get("document_template_id") ?? "");
  const currency = String(formData.get("currency") ?? "INR").toUpperCase();
  const description = String(formData.get("line_description") ?? "").trim();
  const quantity = Number(formData.get("quantity") ?? 0);
  const unitPrice = Number(formData.get("unit_price") ?? -1);
  const tax = Number(formData.get("tax") ?? 0);
  const issueDate = String(formData.get("issue_date") ?? "");
  const validUntil = String(formData.get("valid_until") ?? "");
  const datePattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!organizationId || !clientId || quotationNumber.length < 2 || quotationNumber.length > 40
    || !/^[A-Z]{3}$/.test(currency) || description.length < 1 || description.length > 240
    || !Number.isFinite(quantity) || quantity <= 0 || quantity > 9999999999
    || !Number.isFinite(unitPrice) || unitPrice < 0 || unitPrice > 999999999999.99
    || quantity * unitPrice > 999999999999.99 || !Number.isFinite(tax) || tax < 0 || tax > 999999999999.99
    || quantity * unitPrice + tax > 999999999999.99 || !datePattern.test(issueDate)
    || !datePattern.test(validUntil) || validUntil < issueDate) fail(organizationId);

  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.rpc("create_quotation_from_template", {
    target_org: organizationId,
    target_client: clientId,
    new_quotation_number: quotationNumber,
    quote_currency: currency,
    quote_tax: tax,
    quote_issue_date: issueDate,
    quote_valid_until: validUntil,
    line_description: description,
    line_quantity: quantity,
    line_unit_price: unitPrice,
    selected_template: templateId || null,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&created=quotation`);
}

export async function createFinanceTemplateVersion(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const sourceTemplate = String(formData.get("source_template_id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const accent = String(formData.get("accent") ?? "");
  const style = String(formData.get("style") ?? "clean");
  const validIds = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const validColors = ["#3474F5", "#7258D8", "#17A47B", "#E39A2E", "#192230"];
  if (!organizationId || !validIds.test(sourceTemplate) || name.length < 2 || name.length > 100
    || !validColors.includes(accent) || !["clean", "editorial", "formal"].includes(style)) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.rpc("create_finance_template_version", {
    target_org: organizationId,
    source_template: sourceTemplate,
    template_name: name,
    accent_color: accent,
    template_style: style,
    group_line_items: formData.get("group_line_items") === "on",
    show_tax: formData.get("show_tax") === "on",
    show_signature: formData.get("show_signature") === "on",
    show_terms: formData.get("show_terms") === "on",
    set_as_default: formData.get("set_as_default") === "on",
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace/finance");
  revalidatePath("/workspace/finance/templates");
  redirect(`/workspace/finance/templates?organization=${encodeURIComponent(organizationId)}&created=template`);
}

export async function transitionQuotation(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const quotationId = String(formData.get("quotation_id") ?? "");
  const decision = String(formData.get("decision") ?? "");
  if (!organizationId || !quotationId || !["send", "accept", "decline"].includes(decision)) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.rpc("transition_quotation", {
    target_org: organizationId,
    target_quote: quotationId,
    decision,
  });
  if (error) fail(organizationId, "save");
  revalidatePath("/workspace/finance");
  redirect(`/workspace/finance?organization=${encodeURIComponent(organizationId)}&updated=quotation`);
}

export async function convertQuotationToInvoice(formData: FormData) {
  const organizationId = String(formData.get("organization_id") ?? "");
  const quotationId = String(formData.get("quotation_id") ?? "");
  const invoiceNumber = String(formData.get("invoice_number") ?? "").trim();
  const issueDate = String(formData.get("issue_date") ?? "");
  const dueDate = String(formData.get("due_date") ?? "");
  const datePattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!organizationId || !quotationId || invoiceNumber.length < 2 || invoiceNumber.length > 40
    || !datePattern.test(issueDate) || !datePattern.test(dueDate) || dueDate < issueDate) fail(organizationId);
  const supabase = await authorizedFinanceClient(organizationId);
  const { error } = await supabase.rpc("convert_quotation_to_invoice", {
    target_org: organizationId,
    target_quote: quotationId,
    new_invoice_number: invoiceNumber,
    new_issue_date: issueDate,
    new_due_date: dueDate,
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
  if (!organizationId || !invoiceId || !Number.isFinite(amount) || amount <= 0 || amount > 999999999999.99 || !isOneOf(paymentMethods, method)) fail(organizationId);
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
