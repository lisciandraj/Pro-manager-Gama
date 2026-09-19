-- Group by the key, not by the built object: an aggregate cannot sit in GROUP BY,
-- and ordering by the object ordered by its JSON text rather than by the amount.
do $patch$
declare src text;old text;
begin
 select pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure) into src;
 old:=$q$   'by_month',coalesce((select jsonb_agg(t order by t->>'key') from (
     select jsonb_build_object('key',to_char(i.issue_date,'YYYY-MM'),'amount',sum(i.total-coalesce(i.tax,0))) t
     from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
     and i.issue_date between d1 and d2 group by 1) z),'[]'::jsonb),
   'by_customer',coalesce((select jsonb_agg(t) from (
     select jsonb_build_object('key',o.customer_name,'amount',sum(i.total-coalesce(i.tax,0))) t
     from public.external_invoices i join public.sales_orders o on o.id=i.order_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by o.customer_name order by 1 desc limit 20) z),'[]'::jsonb),
   'by_product',coalesce((select jsonb_agg(t) from (
     select jsonb_build_object('key',l.product_name,'amount',sum(il.quantity*l.unit_price)) t
     from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
     join public.sales_order_lines l on l.id=il.order_line_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by l.product_name order by 1 desc limit 20) z),'[]'::jsonb));$q$;
 if position(old in src)=0 then raise exception 'Unexpected revenue report';end if;
 src:=replace(src,old,$q$   'by_month',coalesce((select jsonb_agg(jsonb_build_object('key',z.k,'amount',z.amount) order by z.k) from (
     select to_char(i.issue_date,'YYYY-MM') k,sum(i.total-coalesce(i.tax,0)) amount
     from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
     and i.issue_date between d1 and d2 group by 1) z),'[]'::jsonb),
   'by_customer',coalesce((select jsonb_agg(jsonb_build_object('key',z.k,'amount',z.amount) order by z.amount desc) from (
     select o.customer_name k,sum(i.total-coalesce(i.tax,0)) amount
     from public.external_invoices i join public.sales_orders o on o.id=i.order_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by o.customer_name order by 2 desc limit 20) z),'[]'::jsonb),
   'by_product',coalesce((select jsonb_agg(jsonb_build_object('key',z.k,'amount',z.amount) order by z.amount desc) from (
     select l.product_name k,sum(il.quantity*l.unit_price) amount
     from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
     join public.sales_order_lines l on l.id=il.order_line_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by l.product_name order by 2 desc limit 20) z),'[]'::jsonb));$q$);
 execute src;
end $patch$;

-- The same shape appeared in the dashboard's expense breakdown and the cash-flow report.
do $patch$
declare src text;old text;
begin
 select pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure) into src;
 old:=$q$   'rows',coalesce((select jsonb_agg(t order by t->>'month') from (
    select jsonb_build_object('month',m,'in',coalesce(sum(cin),0),'out',coalesce(sum(cout),0),
     'net',coalesce(sum(cin),0)-coalesce(sum(cout),0)) t from ($q$;
 if position(old in src)=0 then raise exception 'Unexpected cash-flow report';end if;
 src:=replace(src,old,$q$   'rows',coalesce((select jsonb_agg(jsonb_build_object('month',z.m,'in',z.cin,'out',z.cout,
     'net',z.cin-z.cout) order by z.m) from (
    select m,coalesce(sum(cin),0) cin,coalesce(sum(cout),0) cout from ($q$);
 old:=$q$      where e.status='posted' and e.expense_date between d1 and d2) s group by m) z),'[]'::jsonb),$q$;
 if position(old in src)=0 then raise exception 'Unexpected cash-flow grouping';end if;
 src:=replace(src,old,$q$      where e.status='posted' and e.expense_date between d1 and d2) s group by m) z),'[]'::jsonb),$q$);
 execute src;
end $patch$;
select 'revenue-report-fix' as status;
