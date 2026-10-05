-- Commercial dispatches only: internal moves, consumption and draft orders are not sales.
create function private.gama_stock_sales_threshold_rows() returns table(product_id uuid,data jsonb)
language sql stable security invoker set search_path='' as $$
 with demand as (
  select l.product_id,sum(d.quantity) quantity from public.sales_delivery_lines d
  join public.sales_deliveries h on h.id=d.delivery_id join public.sales_order_lines l on l.id=d.order_line_id
  where h.dispatched_at>=now()-interval '90 days' and h.dispatched_at<=now() group by l.product_id
 ), base as (
  select p.*,coalesce(d.quantity,0) sales90,r.rules,r.rule_id,r.minimum,r.maximum,
   greatest(1,coalesce(r.lead,7)) lead,r.lead is not null lead_configured,
   exists(select 1 from public.reorder_rules w where w.product_id=p.id and w.active and w.warehouse_id is not null) local_rules
  from public.products p join demand d on d.product_id=p.id
  left join lateral (select count(*) rules,(array_agg(g.id order by g.id))[1] rule_id,
   max(g.min_quantity) minimum,max(g.max_quantity) maximum,max(g.lead_time_days) lead
   from public.reorder_rules g where g.product_id=p.id and g.active and g.warehouse_id is null) r on true
  where p.active and p.product_kind='goods' and not p.replenishment_excluded
 ), proposals as (
  select b.*,ceil(sales90/90*lead*1.5) proposed_min,ceil(sales90/90*(lead*1.5+14)) proposed_max,
   coalesce(minimum,min_stock,0) current_min,coalesce(maximum,max_stock,0) current_max,
   rules<=1 and (rules=1 or not local_rules) can_apply
  from base b
 )
 select id,jsonb_build_object('id',id,'name',name,'reference',reference,'sales90',sales90,
  'daily',round(sales90/90,3),'lead_time_days',lead,'lead_configured',lead_configured,
  'current_min',current_min,'current_max',current_max,'proposed_min',proposed_min,'proposed_max',proposed_max,
  'can_apply',can_apply,'changed',current_min<>proposed_min or current_max<>proposed_max,
  'fingerprint',md5(jsonb_build_object('sales',sales90,'min',current_min,'max',current_max,'lead',lead,
   'rule',rule_id,'rules',rules,'local',local_rules,'product_min',min_stock,'product_max',max_stock)::text))
 from proposals
$$;
revoke all on function private.gama_stock_sales_threshold_rows() from public,anon,authenticated;
create function private.gama_stock_sales_thresholds(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid;item jsonb;fresh jsonb;rows jsonb;key uuid;payload jsonb:=p_data-'request_key';receipt private.command_receipts;rule uuid;result jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then
 select coalesce(jsonb_agg(r.data order by r.data->>'name'),'[]') into rows from private.gama_stock_sales_threshold_rows() r;
 return jsonb_build_object('rows',rows,'as_of',now(),'can_apply',private.erp_module_allowed('products',array['administrador','comercial']) and private.erp_action_allowed('products','edit') and private.erp_action_allowed('warehouses','validate'));
 end if;
 if p_action<>'apply' then raise exception 'INVALID_ACTION';end if;
 if not private.erp_module_allowed('products',array['administrador','comercial']) or not private.erp_action_allowed('products','edit') or not private.erp_action_allowed('warehouses','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('sales-threshold-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='sales-thresholds' and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items') not between 1 and 3000 or (select count(distinct v->>'id') from jsonb_array_elements(p_data->'items') v)<>jsonb_array_length(p_data->'items') then raise exception 'INVALID_LINES';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-sales-thresholds',0));
 for v_id in select (v->>'id')::uuid from jsonb_array_elements(p_data->'items') v order by v->>'id' loop
  perform 1 from public.products p where p.id=v_id for update;
  perform 1 from public.reorder_rules r where r.product_id=v_id order by r.id for update;
 end loop;
 for item in select value from jsonb_array_elements(p_data->'items') loop
  select r.data into fresh from private.gama_stock_sales_threshold_rows() r where r.product_id=(item->>'id')::uuid;
  if fresh is null or not (fresh->>'can_apply')::boolean or fresh->>'fingerprint' is distinct from item->>'fingerprint' then raise exception 'STOCK_THRESHOLDS_CHANGED';end if;
  update public.products p set min_stock=(fresh->>'proposed_min')::numeric,max_stock=(fresh->>'proposed_max')::numeric where p.id=(item->>'id')::uuid;
  select r.id into rule from public.reorder_rules r where r.product_id=(item->>'id')::uuid and r.active and r.warehouse_id is null;
  if rule is null then insert into public.reorder_rules(product_id,min_quantity,max_quantity,lead_time_days,supplier_id)
   select p.id,(fresh->>'proposed_min')::numeric,(fresh->>'proposed_max')::numeric,(fresh->>'lead_time_days')::integer,p.supplier_id from public.products p where p.id=(item->>'id')::uuid;
  else update public.reorder_rules set min_quantity=(fresh->>'proposed_min')::numeric,max_quantity=(fresh->>'proposed_max')::numeric where reorder_rules.id=rule;end if;
 end loop;
 result:=jsonb_build_object('updated',jsonb_array_length(p_data->'items'),'as_of',now());
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('sales-thresholds',key,auth.uid(),payload,result);return result;
end $$;
create function public.gama_stock_sales_thresholds(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_stock_sales_thresholds(p_action,p_data)$$;
revoke all on function private.gama_stock_sales_thresholds(text,jsonb),public.gama_stock_sales_thresholds(text,jsonb) from public,anon;
grant execute on function private.gama_stock_sales_thresholds(text,jsonb),public.gama_stock_sales_thresholds(text,jsonb) to authenticated;

-- A split first receipt is an incomplete delivery even if the order is later completed.
create or replace function public.gama_supplier_performance(p_id uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;begin
 if not private.erp_module_allowed('suppliers',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 with receipts as (
  select m.reference_id order_id,min(m.created_at) first_receipt,max(m.created_at) last_receipt
  from public.stock_movements m where m.reference_type='purchase_order' and m.movement_type='receipt' and m.type='in' group by m.reference_id
 ), orders as (
  select o.*,r.first_receipt,r.last_receipt,
   case when r.first_receipt is not null then exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id group by l.product_id
    having sum(l.quantity)>coalesce((select sum(m.quantity) from public.stock_movements m where m.reference_id=o.id and m.reference_type='purchase_order' and m.movement_type='receipt' and m.type='in' and m.product_id=l.product_id and m.created_at=r.first_receipt),0)) end first_incomplete,
   case when o.status='received' and o.expected_date is not null and r.last_receipt is not null then (r.last_receipt at time zone private.erp_timezone())::date<=(o.expected_date at time zone private.erp_timezone())::date end on_time
  from public.purchase_orders o left join receipts r on r.order_id=o.id where o.supplier_id=p_id and o.status<>'cancelled'
 ) select jsonb_build_object('orders',count(*),'received',count(*) filter(where status='received'),'measured',count(on_time),'on_time',count(*) filter(where on_time),
  'on_time_percent',round(100.0*count(*) filter(where on_time)/nullif(count(on_time),0),1),
  'average_lead_days',round(avg((last_receipt at time zone private.erp_timezone())::date-(order_date at time zone private.erp_timezone())::date) filter(where status='received' and last_receipt is not null),1),
  'promised_lead_days',round(avg((expected_date at time zone private.erp_timezone())::date-(order_date at time zone private.erp_timezone())::date) filter(where status='received' and last_receipt is not null and expected_date is not null),1),
  'average_delay_days',round(avg((last_receipt at time zone private.erp_timezone())::date-(expected_date at time zone private.erp_timezone())::date) filter(where status='received' and last_receipt is not null and expected_date is not null),1),
  'receipts_measured',count(first_incomplete),'first_incomplete',count(*) filter(where first_incomplete),'incomplete_percent',round(100.0*count(*) filter(where first_incomplete)/nullif(count(first_incomplete),0),1),
  'late_open',count(*) filter(where status in ('sent','partial') and (expected_date at time zone private.erp_timezone())::date<(now() at time zone private.erp_timezone())::date),
  'returns',(select count(*) from public.return_orders where supplier_id=p_id and status<>'cancelled'),'generated_at',now()) into result from orders;return result;
end $$;
