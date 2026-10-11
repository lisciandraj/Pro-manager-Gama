-- The stock list is paged in SQL. Its KPIs cover the entire filtered, authorized
-- catalogue, never the visible page. Reads remain invoker and respect every RLS
-- boundary; no stock, reservation, snapshot or financial row is rewritten.
create function public.gama_inventory_page(
 p_warehouse uuid default null,p_until date default null,p_search text default '',
 p_category text default '',p_state text default '',p_query text default '',p_sort text default 'name',
 p_direction text default 'asc',p_page integer default 0,p_page_size integer default 20
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;can_incoming boolean;size integer:=least(50,greatest(1,coalesce(p_page_size,20)));
begin
 if auth.uid() is null or not private.erp_mfa_ok() or
  not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if coalesce(p_sort,'name') not in ('name','warehouse','physical','reserved','available','status')
  or coalesce(p_direction,'asc') not in ('asc','desc')
  or coalesce(p_state,'') not in ('','agotado','bajo','sobre','reservado','ok')
  or length(coalesce(p_search,''))>200 or length(coalesce(p_query,''))>200 or length(coalesce(p_category,''))>200 then raise exception 'INVALID_FILTER';end if;
 can_incoming:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
 with stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved,count(*) locations,
   string_agg(distinct w.name,', ' order by w.name) warehouse
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id
   join public.warehouses w on w.id=l.warehouse_id
  where p_warehouse is null or l.warehouse_id=p_warehouse group by q.product_id
 ), incoming as (
  select l.product_id,sum(greatest(0,l.quantity-l.received_quantity)) incoming
  from public.purchase_orders o join public.purchase_order_lines l on l.purchase_order_id=o.id
   left join public.warehouse_locations loc on loc.id=o.destination_location_id
  where can_incoming and o.status in ('sent','partial')
   and (p_warehouse is null or loc.warehouse_id=p_warehouse)
   and (p_until is null or o.expected_date::date<=p_until) group by l.product_id
 ), base as materialized (
  select p.id,p.name,p.reference,p.barcode,p.category,p.min_stock,p.max_stock,p.purchase_price,p.has_photo,p.active,
   coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,coalesce(s.locations,0) locations,
   coalesce(s.warehouse,'—') warehouse,
   case when can_incoming then coalesce(i.incoming,0) end incoming,
   case when can_incoming then coalesce(s.physical,0)-coalesce(s.reserved,0)+coalesce(i.incoming,0) end projected,
   coalesce(s.physical,0)*coalesce(p.purchase_price,0) current_cost_value,
   case when coalesce(s.physical,0)<=0 then 'agotado'
    when coalesce(p.min_stock,0)>0 and coalesce(s.physical,0)-coalesce(s.reserved,0)<=p.min_stock then 'bajo'
    when coalesce(p.max_stock,0)>0 and coalesce(s.physical,0)>p.max_stock then 'sobre'
    when coalesce(s.reserved,0)>0 then 'reservado' else 'ok' end status
  from public.products p left join stock s on s.product_id=p.id left join incoming i on i.product_id=p.id
  where p.active and p.product_kind='goods'
 ), matched as materialized (
  select * from base b where (p_warehouse is null or b.locations>0 or b.incoming>0)
   and (coalesce(p_search,'')='' or position(lower(trim(p_search)) in lower(concat_ws(' ',b.name,b.reference,b.barcode)))>0)
   and (coalesce(p_category,'')='' or b.category=p_category)
   and (coalesce(p_state,'')='' or b.status=p_state)
   and not exists(select 1 from regexp_split_to_table(translate(lower(trim(coalesce(p_query,''))),'áàäâéèëêíìïîóòöôúùüûñ','aaaaeeeeiiiioooouuuun'),E'\\s+') term
    where term<>'' and position(term in translate(lower(concat_ws(' ',b.name,b.warehouse,b.physical,b.reserved,b.available,
     case b.status when 'agotado' then 'Sin stock' when 'bajo' then 'Stock bajo' when 'sobre' then 'Sobre stock' when 'reservado' then 'Con reservas' else 'Disponible' end)),
     'áàäâéèëêíìïîóòöôúùüûñ','aaaaeeeeiiiioooouuuun'))=0)
 ), meta as (
  select count(*) total,count(*) filter(where status='bajo') low,count(*) filter(where physical<=0) out,
   coalesce(sum(current_cost_value),0) current_cost_value,
   least(greatest(0,coalesce(p_page,0)),greatest(0,(count(*)::integer-1)/size)) page from matched
 ), page_rows as materialized (
  select b.* from matched b order by
   case when p_direction='asc' and p_sort='name' then b.name end asc nulls last,
   case when p_direction='desc' and p_sort='name' then b.name end desc nulls last,
   case when p_direction='asc' and p_sort='warehouse' then b.warehouse end asc nulls last,
   case when p_direction='desc' and p_sort='warehouse' then b.warehouse end desc nulls last,
   case when p_direction='asc' and p_sort='status' then case b.status when 'agotado' then 'Sin stock' when 'bajo' then 'Stock bajo' when 'sobre' then 'Sobre stock' when 'reservado' then 'Con reservas' else 'Disponible' end end asc nulls last,
   case when p_direction='desc' and p_sort='status' then case b.status when 'agotado' then 'Sin stock' when 'bajo' then 'Stock bajo' when 'sobre' then 'Sobre stock' when 'reservado' then 'Con reservas' else 'Disponible' end end desc nulls last,
   case when p_direction='asc' then case p_sort when 'physical' then b.physical when 'reserved' then b.reserved when 'available' then b.available end end asc nulls last,
   case when p_direction='desc' then case p_sort when 'physical' then b.physical when 'reserved' then b.reserved when 'available' then b.available end end desc nulls last,
   b.id asc offset (select page*size from meta) limit size
 )
 select jsonb_build_object('generated_at',now(),'warehouse_id',p_warehouse,'until',p_until,'incoming_visible',can_incoming,
  'page',m.page,'page_size',size,'total',m.total,
  'totals',jsonb_build_object('products',m.total,'low',m.low,'out',m.out,'current_cost_value',m.current_cost_value),
  'categories',(select coalesce(jsonb_agg(category order by category),'[]') from (select distinct category from base where coalesce(category,'')<>'') c),
  'rows',(select coalesce(jsonb_agg(to_jsonb(b)-'locations'||jsonb_build_object('lines',
   (select coalesce(jsonb_agg(jsonb_build_object('product_id',q.product_id,'location_id',q.location_id,'quantity',q.quantity,'reserved_quantity',q.reserved_quantity) order by l.code,q.id),'[]')
    from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id
    where q.product_id=b.id and (p_warehouse is null or l.warehouse_id=p_warehouse)))),'[]') from page_rows b)) into result from meta m;
 return result;
end $$;
revoke all on function public.gama_inventory_page(uuid,date,text,text,text,text,text,text,integer,integer) from public,anon,service_role;
grant execute on function public.gama_inventory_page(uuid,date,text,text,text,text,text,text,integer,integer) to authenticated;

-- Keep the old complete Dashboard API and its access/date/currency rules.
-- Context follows the accounting API's existing MFA, role and scope checks,
-- and omits the expensive overview aggregates when opening SRI.
do $$declare src text;anchor text:='if p_action=''overview'' then';begin
 src:=pg_get_functiondef('private.gama_accounting_action_before_ec(text,jsonb)'::regprocedure);
 if position('if p_action=''context'' then' in src)>0 then return;end if;
 if position(anchor in src)=0 then raise exception 'ACCOUNTING_CONTEXT_ANCHOR_MISSING';end if;
 execute replace(src,anchor,'if p_action=''context'' then return jsonb_build_object(''currency'',cfg.currency,''country'',cfg.country,''scope'',scope,''rights'',rights,''today'',today);end if; '||anchor);
end $$;

-- One implementation accepts an explicit subset for the first visible panels;
-- remaining sections are requested only when their details are expanded.
do $$declare src text;anchor text:='if not private.dashboard_access(module_id) then continue;end if;';begin
 if to_regprocedure('public.gama_company_dashboard_sections(date,date,text[])') is not null then return;end if;
 src:=pg_get_functiondef('public.gama_company_dashboard(date,date)'::regprocedure);
 if position(anchor in src)=0 then raise exception 'DASHBOARD_SECTION_ANCHOR_MISSING';end if;
 src:=replace(src,'public.gama_company_dashboard(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)',
  'public.gama_company_dashboard_sections(p_from date, p_to date, p_modules text[])');
 if position('gama_company_dashboard_sections(' in src)=0 then raise exception 'DASHBOARD_SIGNATURE_ANCHOR_MISSING';end if;
 execute replace(src,anchor,'if p_modules is not null and not module_id=any(p_modules) then continue;end if; '||anchor);
end $$;
revoke all on function public.gama_company_dashboard_sections(date,date,text[]) from public,anon,service_role;
grant execute on function public.gama_company_dashboard_sections(date,date,text[]) to authenticated;
create or replace function public.gama_company_dashboard(p_from date default null,p_to date default null)
returns jsonb language sql stable security invoker set search_path='' as $$select public.gama_company_dashboard_sections(p_from,p_to,null)$$;

-- Aggregate reorder rules once and reuse one stock analysis for management.
CREATE OR REPLACE FUNCTION private.stock_insight_rows(p_purchases boolean)
 RETURNS TABLE(product_id uuid, data jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with demand as (
  select m.product_id,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '30 days'),0) d30,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '60 days'),0) d60,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '90 days'),0) d90,
   max(m.created_at) last_out
  from public.stock_movements m where m.type='out' and m.quantity>0
   and (m.movement_type is null or m.movement_type in ('delivery','manual_out','production_out')) group by m.product_id
 ), stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved from public.stock_quants q group by q.product_id
 ), purchases as (
  select l.product_id,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status in ('sent','partial')),0) incoming,
   coalesce(sum(l.quantity) filter(where o.status='draft'),0) drafts
  from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
  where p_purchases and o.status in ('draft','sent','partial') group by l.product_id
 ), discrepancies as (
  select l.product_id,count(distinct l.count_id) repeats from public.inventory_count_lines l
   join public.inventory_counts c on c.id=l.count_id
  where c.status='validated' and l.validated and l.variance<>0 and c.completed_at>=now()-interval '180 days' group by l.product_id
 ), rules as (
  select z.product_id,sum(z.min_quantity) minimum,sum(z.max_quantity) maximum,max(z.lead_time_days) lead,
   (array_agg(z.supplier_id order by z.created_at desc) filter(where z.supplier_id is not null))[1] supplier
  from public.reorder_rules z where z.active and (z.warehouse_id is null or not exists
   (select 1 from public.reorder_rules g where g.product_id=z.product_id and g.active and g.warehouse_id is null))
  group by z.product_id
 ), base as (
  select p.id,p.name,p.reference,p.category,p.purchase_price,p.replenishment_excluded,p.order_minimum,p.order_multiple,
   coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,
   coalesce(b.incoming,0) incoming,coalesce(b.drafts,0) drafts,
   coalesce(d.d30,0) d30,coalesce(d.d60,0) d60,coalesce(d.d90,0) d90,d.last_out,
   coalesce(d.d30,0)/30*.5+coalesce(d.d60,0)/60*.3+coalesce(d.d90,0)/90*.2 daily,
   greatest(0,current_date-coalesce(d.last_out::date,p.created_at::date)) days_without_out,
   coalesce(r.minimum,p.min_stock,0) minimum,coalesce(r.maximum,p.max_stock,0) maximum,
   coalesce(r.supplier,p.supplier_id) supplier,
   greatest(1,coalesce(r.lead,7)) lead,r.lead is not null lead_configured,
   coalesce(x.repeats,0) repeats,coalesce(s.physical,0)*coalesce(p.purchase_price,0) stock_value
  from public.products p left join stock s on s.product_id=p.id left join demand d on d.product_id=p.id
   left join purchases b on b.product_id=p.id left join discrepancies x on x.product_id=p.id
   left join rules r on r.product_id=p.id
  where p.active and p.product_kind='goods'
 ), targets as (
  select b.*,case when daily>0 then greatest(minimum,ceil(daily*lead*1.5)) else minimum end target_min,
   case when daily>0 then greatest(maximum,minimum,ceil(daily*(lead+14)+daily*lead*.5)) else greatest(maximum,minimum) end target_max,
   available+incoming+drafts net,
   sum(greatest(stock_value,0)) over() total_value,
   coalesce(sum(greatest(stock_value,0)) over(order by stock_value desc,id rows between unbounded preceding and 1 preceding),0) prior_value
  from base b
 ), proposal as (
  select t.*,case when not replenishment_excluded and net<target_min then greatest(target_max-net,coalesce(order_minimum,0)) else 0 end need
  from targets t
 )
 select p.id,jsonb_build_object(
  'id',p.id,'name',p.name,'reference',p.reference,'category',p.category,
  'on_hand',p.physical,'reserved',p.reserved,'available',p.available,
  'incoming',case when p_purchases then p.incoming end,'draft_quantity',case when p_purchases then p.drafts end,
  'projected',case when p_purchases then p.net end,
  'min_quantity',p.minimum,'max_quantity',p.maximum,'target_min',p.target_min,'target_max',p.target_max,
  'lead_time_days',p.lead,'lead_configured',p.lead_configured,
  'demand30',p.d30,'demand60',p.d60,'demand90',p.d90,'avg_daily',round(p.daily,3),
  'last_out',p.last_out,'days_without_out',p.days_without_out,
  'unit_cost',p.purchase_price,'value',p.stock_value,'excluded',p.replenishment_excluded,
  'supplier_id',case when p_purchases and s.active then s.id end,
  'supplier_name',case when p_purchases and s.active then s.name end,
  'suggested_quantity',case when p_purchases then case when p.need>0 and coalesce(p.order_multiple,0)>0 then round(ceil(p.need/p.order_multiple)*p.order_multiple,3) else round(p.need,3) end end,
  'basis',case when p.daily>0 then 'recent_demand' else 'thresholds' end,
  'repeated_discrepancies',p.repeats,
  'importance',case when p.total_value>0 and p.prior_value/p.total_value<.8 then 'A' when p.total_value>0 and p.prior_value/p.total_value<.95 then 'B' else 'C' end
 ) from proposal p left join public.suppliers s on s.id=p.supplier
$function$
;
CREATE OR REPLACE FUNCTION private.gama_management_overview(p_context text DEFAULT 'dashboard'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare today date:=(now() at time zone private.erp_timezone())::date;month_start date;metrics jsonb:='{}';clients jsonb:='[]';purchase jsonb:='[]';client_count integer:=0;purchase_count integer:=0;value jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(p_context,array['administrador']) or p_context not in ('dashboard','assistant-ia') then raise exception 'ROLE_NOT_ALLOWED';end if;
 month_start:=date_trunc('month',today)::date;
 if private.erp_module_allowed('payments',array['administrador']) then
  with valid as(select i.* from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')),
  reductions as(select coalesce(sum(c.amount*i.subtotal/nullif(i.total,0)),0) net from public.return_credits c join valid i on i.id=c.invoice_id where c.issued_on between month_start and today),
  movement_cost as(select m.reference_id delivery_id,m.product_id,sum(m.quantity*m.unit_cost_at_movement)/nullif(sum(m.quantity),0) cost,bool_and(m.unit_cost_at_movement is not null) complete
   from public.stock_movements m where m.type='out' and m.movement_type='delivery' and m.reference_type='sales_delivery' group by m.reference_id,m.product_id),
  cost_by_line as(select l.id,sum(d.quantity*c.cost)/nullif(sum(d.quantity),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.sales_order_lines l join public.sales_delivery_lines d on d.order_line_id=l.id left join movement_cost c on c.delivery_id=d.delivery_id and c.product_id=l.product_id group by l.id),
  invoice_cost as(select x.invoice_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x left join cost_by_line c on c.id=x.order_line_id group by x.invoice_id),
  restored as(select coalesce(sum(l.quantity*c.cost),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.return_lines l join public.return_orders r on r.id=l.return_id join public.sales_delivery_lines d on d.id=l.delivery_line_id left join cost_by_line c on c.id=d.order_line_id
   where l.disposition='restocked' and l.processed_at is not null and exists(select 1 from public.return_credits n where n.return_id=r.id and n.invoice_id is not null and n.issued_on between month_start and today)),
  totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost,count(*) missing
   from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today and not coalesce(c.complete,false)),
  full_totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today)
  select jsonb_build_object('sales_month',round(f.net-r.net,2),'margin_month',case when t.missing=0 and coalesce(s.complete,true) then round(f.net-r.net-f.cost+s.cost,2) end,'margin_missing_invoices',t.missing,'margin_basis','historical_dispatch_cost',
   'overdue',coalesce((select sum(balance) from private.gama_customer_dues() where coalesce(due_date,issue_date)<today),0)) into value from full_totals f cross join reductions r cross join totals t cross join restored s;
  if not private.erp_module_allowed('accounting',array['administrador']) then value:=value-'margin_month'-'margin_missing_invoices'-'margin_basis';end if;
  metrics:=metrics||value;
  with grouped as(select customer_id id,customer_name name,sum(balance) balance,min(coalesce(due_date,issue_date)) oldest_due from private.gama_customer_dues() where coalesce(due_date,issue_date)<today group by customer_id,customer_name),
  limited as(select * from grouped order by balance desc,oldest_due,id limit 10)
  select (select count(*) from grouped),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('days_late',today-l.oldest_due) order by l.balance desc,l.oldest_due,l.id),'[]') into client_count,clients from limited l;
 end if;
 if private.erp_module_allowed('warehouses',array['administrador']) then
  with all_rows as materialized (
   select data from private.stock_insight_rows(private.erp_module_allowed('gamaPurchasesV14',array['administrador']))
  ), limited as (
   select data from all_rows where (data->>'suggested_quantity')::numeric>0
   order by (data->>'available')::numeric,data->>'name' limit 20
  )
  select jsonb_build_object('stockouts',count(*) filter(where (data->>'available')::numeric<=0),
   'dormant_stock_value',coalesce(sum((data->>'value')::numeric) filter(where (data->>'on_hand')::numeric>0 and (data->>'days_without_out')::integer>=90),0)),
   (select count(*) from all_rows where (data->>'suggested_quantity')::numeric>0),
   (select coalesce(jsonb_agg(data),'[]') from limited) into value,purchase_count,purchase from all_rows;
  metrics:=metrics||value;
 end if;
 if private.erp_module_allowed('tms',array['administrador']) then
  select jsonb_build_object('late_deliveries',count(*) filter(where status not in ('Entregada','Cancelada') and (delivery_date<today or (delivery_date=today and eta_at<now())))) into value from public.tms_deliveries;metrics:=metrics||value;
 end if;
 return jsonb_build_object('today',today,'month_start',month_start,'generated_at',now(),'metrics',metrics,'clients',clients,'client_count',client_count,'purchases',purchase,'purchase_count',purchase_count);
end $function$
;

