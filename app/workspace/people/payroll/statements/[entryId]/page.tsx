import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PrintButton } from "./print-button";
import styles from "./statement.module.css";

type Entry = { id: string; organization_id: string; payroll_run_id: string; member_id: string; currency: string; base_salary: number; monthly_allowance: number; bonus_paid: number; other_additions: number; deductions: number; net_pay: number; adjustment_note: string };
type Run = { period_start: string; period_end: string; status: "draft" | "approved" | "paid" };
const money = (value: number, currency: string) => {
  try { return new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 2 }).format(value); }
  catch { return `${currency} ${value.toLocaleString("en-IN")}`; }
};

export default async function PayrollStatementPage({ params }: { params: Promise<{ entryId: string }> }) {
  const { entryId } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: rawEntry } = await supabase.from("payroll_entries")
    .select("id,organization_id,payroll_run_id,member_id,currency,base_salary,monthly_allowance,bonus_paid,other_additions,deductions,net_pay,adjustment_note")
    .eq("id", entryId).maybeSingle();
  if (!rawEntry) redirect("/workspace/people/payroll?statement=unavailable");
  const entry = rawEntry as Entry;
  const { data: run } = await supabase.from("payroll_runs").select("period_start,period_end,status")
    .eq("organization_id", entry.organization_id).eq("id", entry.payroll_run_id).maybeSingle();
  if (!run || run.status === "draft") redirect(`/workspace/people/payroll?organization=${entry.organization_id}&statement=unavailable`);
  const payrollRun = run as Run;
  const [{ data: canManage }, { data: organization }, { data: profile }] = await Promise.all([
    supabase.rpc("has_org_permission", { target_org: entry.organization_id, permission_key: "hr.payroll.manage" }),
    supabase.from("organizations").select("name").eq("id", entry.organization_id).maybeSingle(),
    supabase.from("profiles").select("full_name").eq("id", entry.member_id).maybeSingle(),
  ]);
  const month = new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(`${payrollRun.period_start}T12:00:00Z`));
  const staffName = profile?.full_name ?? (canManage ? "Team member" : "You");
  const lines = [
    ["Base salary", entry.base_salary],
    ["Monthly allowance", entry.monthly_allowance],
    ["Bonus paid", entry.bonus_paid],
    ["Other additions", entry.other_additions],
  ] as const;

  return <main className={styles.page}>
    <nav className={styles.actions} aria-label="Statement actions"><a href={`/workspace/people/payroll?organization=${entry.organization_id}`}>← Payroll & compensation</a><PrintButton/></nav>
    <article className={styles.statement}>
      <header className={styles.header}><div><div className={styles.brand}>LET’S GO. <span>CENTRAL OS</span></div><p>{organization?.name ?? "Agency workspace"}</p></div><div className={styles.status}>{payrollRun.status === "paid" ? "PAID" : "APPROVED"}<small>Salary statement</small></div></header>
      <section className={styles.summary}><div><small>Employee</small><b>{staffName}</b></div><div><small>Pay period</small><b>{month}</b></div><div><small>Payment status</small><b>{payrollRun.status === "paid" ? "Paid" : "Approved"}</b></div></section>
      <section className={styles.tableSection}><h1>Pay statement</h1><p>Compensation details for the selected pay period.</p><table><thead><tr><th>Earnings</th><th>Amount</th></tr></thead><tbody>{lines.map(([label, amount]) => <tr key={label}><td>{label}</td><td>{money(amount, entry.currency)}</td></tr>)}<tr className={styles.deduction}><td>Deductions</td><td>− {money(entry.deductions, entry.currency)}</td></tr><tr className={styles.total}><td>Net pay</td><td>{money(entry.net_pay, entry.currency)}</td></tr></tbody></table></section>
      {entry.adjustment_note && <section className={styles.note}><b>Payroll note</b><p>{entry.adjustment_note}</p></section>}
      <footer className={styles.footer}><b>This statement is generated from the organization payroll record.</b><span>For questions, contact your payroll administrator.</span></footer>
      <p className={styles.disclaimer}>This internal salary statement is not a statutory tax certificate. Tax and local employment requirements must be reviewed separately.</p>
    </article>
  </main>;
}
