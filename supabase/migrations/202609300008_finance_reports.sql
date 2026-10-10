create or replace function public.finance_monthly_trend(target_org uuid, month_count integer default 6)
returns table (currency char(3), month_start date, revenue numeric, expenses numeric, net_cash numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with settings as (
    select o.timezone, date_trunc('month', now() at time zone o.timezone)::date as current_month
    from public.organizations o where o.id = target_org and public.is_org_member(target_org)
  ), months as (
    select (s.current_month - (g.month_offset || ' months')::interval)::date as month_start, s.timezone
    from settings s
    cross join generate_series(0, greatest(least(coalesce(month_count, 6), 24), 1) - 1) as g(month_offset)
  ), currencies as (
    select o.currency as code from public.organizations o where o.id = target_org
    union select i.currency as code from public.invoices i where i.organization_id = target_org
    union select e.currency as code from public.expenses e where e.organization_id = target_org
  ), values_by_month as (
    select c.code, m.month_start,
      coalesce((select sum(p.amount)
        from public.invoice_payments p join public.invoices i
          on i.organization_id = p.organization_id and i.id = p.invoice_id
        where p.organization_id = target_org and i.currency = c.code
          and (p.paid_at at time zone m.timezone)::date >= m.month_start
          and (p.paid_at at time zone m.timezone)::date < (m.month_start + interval '1 month')::date), 0) as cash_in,
      coalesce((select sum(e.amount) from public.expenses e
        where e.organization_id = target_org and e.currency = c.code
          and e.spent_on >= m.month_start and e.spent_on < (m.month_start + interval '1 month')::date), 0) as cash_out
    from currencies c cross join months m
  )
  select code, month_start, cash_in, cash_out, cash_in - cash_out
  from values_by_month order by code, month_start;
$$;

create or replace function public.receivables_aging(target_org uuid)
returns table (currency char(3), bucket text, invoice_count bigint, amount numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with settings as (
    select (now() at time zone o.timezone)::date as local_today
    from public.organizations o where o.id = target_org and public.is_org_member(target_org)
  ), open_invoices as (
    select i.currency, i.due_date, (i.total - i.amount_paid) as balance, s.local_today
    from public.invoices i cross join settings s
    where i.organization_id = target_org and i.status not in ('draft', 'void') and i.amount_paid < i.total
  ), aged as (
    select currency,
      case when due_date is null then 'no_due_date'
        when due_date >= local_today then 'not_due'
        when local_today - due_date <= 30 then '1_30'
        when local_today - due_date <= 60 then '31_60'
        else '61_plus' end as bucket,
      balance
    from open_invoices
  )
  select currency, bucket, count(*)::bigint, sum(balance)
  from aged group by currency, bucket
  order by currency, case bucket when 'not_due' then 1 when '1_30' then 2 when '31_60' then 3 when '61_plus' then 4 else 5 end;
$$;

revoke all on function public.finance_monthly_trend(uuid, integer) from public, anon;
revoke all on function public.receivables_aging(uuid) from public, anon;
grant execute on function public.finance_monthly_trend(uuid, integer) to authenticated;
grant execute on function public.receivables_aging(uuid) to authenticated;
