-- Stock reads on demand, accountable replenishment drafts and cycle count scheduling.
-- All commands preserve the existing stock and purchase transaction boundaries.
alter table public.inventory_counts
 add column assigned_to uuid references public.profiles(id),
 add column due_date date,
 add column priority text not null default 'normal' check(priority in ('normal','high')),
 add column scope_product_id uuid references public.products(id),
 add column repeat_of uuid references public.inventory_counts(id);
create index inventory_counts_assigned on public.inventory_counts(assigned_to) where assigned_to is not null;
create index inventory_counts_scope_product on public.inventory_counts(scope_product_id) where scope_product_id is not null;
create unique index inventory_counts_repeat on public.inventory_counts(repeat_of) where repeat_of is not null and status<>'cancelled';
create index inventory_counts_due on public.inventory_counts(due_date) where status in ('draft','in_progress');
create index stock_movements_demand on public.stock_movements(product_id,created_at desc)
 where type='out' and quantity>0 and (movement_type is null or movement_type in ('delivery','manual_out','production_out'));
create index inventory_count_lines_discrepancy on public.inventory_count_lines(product_id,count_id) where validated and variance<>0;

-- Internal aggregation is not callable by clients. No Intelligence cache permissions change.
create function private.stock_insight_rows(p_purchases boolean)
returns table(product_id uuid,data jsonb) language sql stable security invoker set search_path='' as $$
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
 ), base as (
  select p.*,coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
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
   left join lateral (
    select sum(z.min_quantity) minimum,sum(z.max_quantity) maximum,max(z.lead_time_days) lead,
     (array_agg(z.supplier_id order by z.created_at desc) filter(where z.supplier_id is not null))[1] supplier
    from public.reorder_rules z where z.product_id=p.id and z.active
     and (z.warehouse_id is null or not exists(select 1 from public.reorder_rules g where g.product_id=p.id and g.active and g.warehouse_id is null))
   ) r on true
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
$$;
revoke all on function private.stock_insight_rows(boolean) from public,anon,authenticated;

create function private.gama_stock_insights(p_view text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare can_buy boolean;can_count boolean;rows jsonb;late jsonb:='[]';adjustments jsonb:='[]';counts jsonb:='[]';people jsonb:='[]';begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_view not in ('acciones','rotacion','reabastecimiento','conteos') then raise exception 'INVALID_VIEW';end if;
 can_buy:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
 can_count:=private.erp_module_allowed('warehouses',array['administrador','almacenero']);
 select coalesce(jsonb_agg(case when can_count then x.data else x.data-'repeated_discrepancies' end order by x.data->>'name'),'[]') into rows from private.stock_insight_rows(can_buy) x;
 if p_view='acciones' and can_buy then
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'supplier',s.name,'expected_date',o.expected_date,'days_late',current_date-o.expected_date::date) order by o.expected_date),'[]') into late
   from public.purchase_orders o join public.suppliers s on s.id=o.supplier_id
   where o.status in ('sent','partial') and o.expected_date::date<current_date
    and exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id and l.quantity>l.received_quantity);
 end if;
 if p_view='acciones' and can_count then
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'product_id',r.product_id,'reason',r.reason,'requested_at',r.requested_at) order by r.requested_at desc,r.id desc),'[]') into adjustments from public.stock_adjustment_requests r where r.status='pending';
 end if;
 if p_view in ('acciones','conteos') and can_count then
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('assigned_name',p.full_name,'repeat_started',exists(select 1 from public.inventory_counts n where n.repeat_of=c.id and n.status<>'cancelled')) order by case when c.priority='high' then 0 else 1 end,coalesce(c.due_date,c.next_due),c.created_at desc),'[]') into counts
   from public.inventory_counts c left join public.profiles p on p.id=c.assigned_to
   where c.status in ('draft','in_progress') or (c.status='validated' and c.next_due is not null);
  if p_view='conteos' then select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name),'[]') into people from public.profiles p where p.active and p.role in ('administrador','almacenero');end if;
 end if;
 return jsonb_build_object('as_of',now(),'today',current_date,'can_buy',can_buy,'can_count',can_count,'rows',rows,'late_orders',late,'adjustments',adjustments,'counts',counts,'people',people);
end $$;
create function public.gama_stock_insights(p_view text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_stock_insights(p_view)$$;
revoke all on function private.gama_stock_insights(text),public.gama_stock_insights(text) from public,anon;
grant execute on function private.gama_stock_insights(text),public.gama_stock_insights(text) to authenticated;

-- One transaction for all suppliers; stable receipt makes a network retry safe.
create function private.gama_stock_replenish(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;
 payload jsonb:=p_data-'request_key';selected jsonb:=p_data->'items';fresh jsonb;item jsonb;grouped record;result jsonb;orders jsonb:='[]';po jsonb;begin
 if actor is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial']) or not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-replenish:'||key::text,0));
 select * into receipt from private.command_receipts where domain='stock-replenish' and request_key=key;
 if found then if receipt.actor_id<>actor or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if jsonb_typeof(selected) is distinct from 'array' or jsonb_array_length(selected) not between 1 and 3000 then raise exception 'INVALID_LINES';end if;
 if (select count(distinct v->>'product_id') from jsonb_array_elements(selected) v)<>jsonb_array_length(selected) then raise exception 'DUPLICATE_PRODUCT';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 select coalesce(jsonb_agg(x.data),'[]') into fresh from private.stock_insight_rows(true) x where x.product_id in (select (v->>'product_id')::uuid from jsonb_array_elements(selected) v);
 for item in select value from jsonb_array_elements(selected) loop
  if not exists(select 1 from jsonb_array_elements(fresh) x where x->>'id'=item->>'product_id' and nullif(x->>'supplier_id','') is not null and (x->>'suggested_quantity')::numeric>0 and (x->>'suggested_quantity')::numeric=(item->>'quantity')::numeric and x->>'supplier_id'=item->>'supplier_id') then raise exception 'REPLENISHMENT_CHANGED';end if;
 end loop;
 for grouped in select x->>'supplier_id' supplier,max((x->>'lead_time_days')::integer) lead,
  jsonb_agg(jsonb_build_object('product_id',p.id,'quantity',(x->>'suggested_quantity')::numeric,'unit_cost',round(coalesce(p.purchase_price,0),2),'tax_rate',p.tax_rate) order by p.id) lines
  from jsonb_array_elements(fresh) x join public.products p on p.id=(x->>'id')::uuid group by x->>'supplier_id' order by x->>'supplier_id'
 loop
  if jsonb_array_length(grouped.lines)>500 then raise exception 'SUPPLIER_LINE_LIMIT_500';end if;
  po:=private.gama_purchase_save(jsonb_build_object('request_key',gen_random_uuid(),'supplier_id',grouped.supplier,'destination_location_id',p_data->>'destination_location_id','expected_date',current_date+grouped.lead,'source_kind','low_stock','notes','Reposición desde Stock: salidas recientes, plazo de suministro y mínimos configurados. Revisar antes de enviar.','lines',grouped.lines));
  orders:=orders||jsonb_build_array(jsonb_build_object('id',po->>'id','number',po->>'order_number','supplier_id',grouped.supplier,'lines',jsonb_array_length(grouped.lines)));
 end loop;
 result:=jsonb_build_object('orders',orders,'products',jsonb_array_length(selected));
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('stock-replenish',key,actor,payload,result);
 return result;
end $$;
create function public.gama_stock_replenish(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_stock_replenish(p_data)$$;
revoke all on function private.gama_stock_replenish(jsonb),public.gama_stock_replenish(jsonb) from public,anon;
grant execute on function private.gama_stock_replenish(jsonb),public.gama_stock_replenish(jsonb) to authenticated;

-- Extend the existing idempotent count command. Quantities still change only on validation.
create or replace function private.gama_count_create_core(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.inventory_counts;key uuid:=(p_data->>'request_key')::uuid;parent public.inventory_counts;assignee uuid:=nullif(p_data->>'assigned_to','')::uuid;repeat_id uuid:=nullif(p_data->>'repeat_of','')::uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('count:'||key::text,0));
 select * into c from public.inventory_counts where request_key=key;if found then if c.created_by<>auth.uid() then raise exception 'ROLE_NOT_ALLOWED';end if;return to_jsonb(c);end if;
 if not exists(select 1 from public.warehouses w where w.id=(p_data->>'warehouse_id')::uuid and w.active) then raise exception 'WAREHOUSE_NOT_FOUND';end if;
 if nullif(p_data->>'location_id','') is not null and not exists(select 1 from public.warehouse_locations where id=(p_data->>'location_id')::uuid and warehouse_id=(p_data->>'warehouse_id')::uuid and active) then raise exception 'LOCATION_NOT_FOUND';end if;
 if assignee is not null and not exists(select 1 from public.profiles p where p.id=assignee and p.active and p.role in ('administrador','almacenero')) then raise exception 'COUNT_ASSIGNEE_INVALID';end if;
 if repeat_id is not null then
  select * into parent from public.inventory_counts where id=repeat_id for update;
  if not found or parent.status<>'validated' or parent.next_due is null or parent.warehouse_id<>(p_data->>'warehouse_id')::uuid then raise exception 'COUNT_REPEAT_INVALID';end if;
  if exists(select 1 from public.inventory_counts n where n.repeat_of=repeat_id and n.status<>'cancelled') then raise exception 'COUNT_REPEAT_STARTED';end if;
 end if;
 insert into public.inventory_counts(warehouse_id,reference,status,created_by,started_at,blind,cycle_days,scope_location_id,scope_category,request_key,assigned_to,due_date,priority,scope_product_id,repeat_of)
 values((p_data->>'warehouse_id')::uuid,p_data->>'reference','in_progress',auth.uid(),now(),coalesce((p_data->>'blind')::boolean,true),nullif(p_data->>'cycle_days','')::integer,nullif(p_data->>'location_id','')::uuid,nullif(p_data->>'category',''),key,assignee,nullif(p_data->>'due_date','')::date,coalesce(nullif(p_data->>'priority',''),'normal'),nullif(p_data->>'product_id','')::uuid,repeat_id) returning * into c;
 insert into public.inventory_count_lines(count_id,product_id,location_id,expected_quantity)
 select c.id,q.product_id,q.location_id,q.quantity from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.products p on p.id=q.product_id
 where p.active and p.product_kind='goods' and l.active and l.warehouse_id=c.warehouse_id
  and (c.scope_location_id is null or q.location_id=c.scope_location_id) and (c.scope_category is null or p.category=c.scope_category) and (c.scope_product_id is null or p.id=c.scope_product_id);
 if not found then raise exception 'COUNT_SCOPE_EMPTY';end if;return to_jsonb(c);
end $$;
revoke all on function private.gama_count_create_core(jsonb) from public,anon,authenticated;
