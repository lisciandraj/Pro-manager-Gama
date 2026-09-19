create or replace function public.gama_ai_overview(p_from date default null,p_to date default null) returns jsonb
language plpgsql stable security invoker set search_path='' set statement_timeout='12s' as $$
declare catalog jsonb:=public.gama_ai_catalog(); counts jsonb:='[]';spec jsonb;n bigint;stock_summary jsonb;finance jsonb;
 today date:=(now() at time zone 'America/Guayaquil')::date;date_from date:=coalesce(p_from,date_trunc('month',now() at time zone 'America/Guayaquil')::date);date_to date:=coalesce(p_to,today);
begin
 if date_from>date_to then raise exception 'INVALID_PERIOD';end if;
 for spec in select value from jsonb_array_elements(catalog) loop
  execute format('select count(*) from public.%I',spec->>'table') into n;
  counts:=counts||jsonb_build_array(jsonb_build_object('table',spec->>'table','module',spec->>'module','rows',n));
 end loop;
 with reserved as(select product_id,sum(quantity) qty from public.stock_reservations where status='active' group by product_id),
 s as(select p.id,p.name,p.reference,p.stock,p.min_stock,p.purchase_price,p.stock-coalesce(r.qty,0) available,
 greatest(0,p.min_stock-(p.stock-coalesce(r.qty,0))) shortage from public.products p left join reserved r on r.product_id=p.id where p.active)
 select jsonb_build_object('active_products',count(*),'low_products',count(*) filter(where available<=min_stock),
 'stock_cost',coalesce(sum(stock*purchase_price),0),'missing_costs',count(*) filter(where purchase_price is null),
 'low_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,stock,min_stock,available,shortage from s where available<=min_stock order by shortage desc,name limit 20)x),'[]'::jsonb)) into stock_summary from s;
 finance:=public.gama_payment_action('list','{"status":"all"}'::jsonb);
 return jsonb_build_object('as_of',clock_timestamp(),'today',today,'currency','USD','timezone','America/Guayaquil',
 'period',jsonb_build_object('from',date_from,'to',date_to),'coverage',counts,'stock',stock_summary,
 'receivables',finance,
 'sales',jsonb_build_object('registered_subtotal',coalesce((select sum(subtotal) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'registered_total',coalesce((select sum(total) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'invoice_count',(select count(*) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),
 'receipts',coalesce((select sum(amount) from public.external_invoice_payments where status='confirmed' and paid_at between date_from and date_to),0),
 'orders',(select count(*) from public.sales_orders where status<>'cancelled' and (created_at at time zone 'America/Guayaquil')::date between date_from and date_to),
 'quotes_to_follow',(select count(*) from public.invoices where quote_state='sent' and quote_sent_at<now()-interval '7 days')),
 'purchases',jsonb_build_object('late_count',(select count(*) from public.purchase_orders where status not in ('received','cancelled') and expected_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,order_number,supplier_id,expected_date,status,total from public.purchase_orders where status not in ('received','cancelled') and expected_date<today order by expected_date,id limit 20)x),'[]'::jsonb)),
 'logistics',jsonb_build_object('late_count',(select count(*) from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,customer,delivery_date,status from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today order by delivery_date,id limit 20)x),'[]'::jsonb)),
 'crm',jsonb_build_object('open_opportunities',(select count(*) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),
 'weighted_pipeline',coalesce((select sum(o.weighted_amount) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),0),
 'late_activities',(select count(*) from public.crm_activities where status not in ('done','cancelled') and due_at<now())),
 'hr',jsonb_build_object('active_employees',(select count(*) from public.hr_employees where active),'pending_absences',(select count(*) from public.hr_absences where status='pending')),
 'knowledge',jsonb_build_object('articles',(select count(*) from public.knowledge_articles)));
end $$;
revoke all on function public.gama_ai_overview(date,date) from public,anon;
grant execute on function public.gama_ai_overview(date,date) to authenticated;
