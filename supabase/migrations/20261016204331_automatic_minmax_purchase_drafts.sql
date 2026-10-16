-- Fixed product thresholds are a separate, explicit mode of the existing
-- delegated automation. The minute scheduler works even with every client closed.
-- Installing this migration alone does not enable or renew a delegation.
create function private.stock_minmax_replenishment_rows()
returns table(product_id uuid,data jsonb)
language sql stable security invoker set search_path='' as $$
 with pending as (
  select l.product_id,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status='draft'),0) drafts,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status in ('sent','partial')),0) incoming
  from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
  where o.status in ('draft','sent','partial') group by l.product_id
 )
 select p.id,jsonb_build_object(
  'id',p.id,'name',p.name,'reference',p.reference,'supplier_id',s.id,
  'on_hand',p.stock,'min_stock',p.min_stock,'max_stock',p.max_stock,
  'draft_quantity',coalesce(b.drafts,0),'incoming',coalesce(b.incoming,0),
  'quantity',round(greatest(p.max_stock-p.stock-coalesce(b.drafts,0)-coalesce(b.incoming,0),0),3),
  'thresholds_valid',p.min_stock>=0 and p.max_stock>0 and p.max_stock>=p.min_stock,
  'unit_cost',round(coalesce(p.purchase_price,0),2),'tax_rate',coalesce(p.tax_rate,0),
  'lead_time_days',r.lead
 )
 from public.products p left join pending b on b.product_id=p.id
 left join public.suppliers s on s.id=p.supplier_id and s.active
 left join lateral (
  select max(z.lead_time_days) lead from public.reorder_rules z
  where z.product_id=p.id and z.active
   and (z.warehouse_id is null or not exists(
    select 1 from public.reorder_rules g where g.product_id=p.id and g.active and g.warehouse_id is null))
 ) r on true
 where p.active and p.product_kind='goods' and not p.replenishment_excluded and p.stock<p.min_stock
$$;
revoke all on function private.stock_minmax_replenishment_rows() from public,anon,authenticated,service_role;

create function private.automation_replenish_minmax(p_job private.automation_jobs,p_config jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 row record;item jsonb;items jsonb:='[]';grouped record;orders jsonb:='[]';po jsonb;result jsonb;
 cap numeric:=coalesce((p_config->>'max_order_total')::numeric,1000);
 receipt private.command_receipts;products_count integer:=0;skipped integer:=0;reason text;
begin
 if auth.uid() is null or not private.automation_delegation_ok() then raise exception 'DELEGATION_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial'])
  or not private.erp_action_allowed('gamaPurchasesV14','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if cap::text in ('NaN','Infinity','-Infinity') or cap<=0 or cap>1000000 then
  return jsonb_build_object('blocked',true,'reason','PURCHASE_LIMIT_REQUIRED');
 end if;
 -- Shared with manual Stock replenishment, and protected by the durable job
 -- receipt as well as the canonical purchase command's own receipts.
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 select * into receipt from private.command_receipts where domain='automatic-minmax-replenish' and request_key=p_job.id;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.payload is distinct from p_config then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 -- Resolve old product exceptions when stock/thresholds/following purchases
 -- have changed. Still-invalid rows are reopened below with the current reason.
 update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now()
  where kind='replenishment' and key like 'minmax:%' and active;
 for row in select x.product_id,x.data from private.stock_minmax_replenishment_rows() x order by x.product_id limit 3000 loop
  item:=row.data;reason:=null;
  if not (item->>'thresholds_valid')::boolean then reason:='MIN_MAX_REQUIRED';
  elsif (item->>'quantity')::numeric<=0 then continue;
  elsif nullif(item->>'supplier_id','') is null then reason:='ACTIVE_SUPPLIER_REQUIRED';
  elsif (item->>'quantity')::numeric>999999999 then reason:='INVALID_QUANTITY';
  elsif (item->>'unit_cost')::numeric<0 or (item->>'unit_cost')::numeric>999999999 then reason:='INVALID_PRICE';
  end if;
  if reason is not null then
   perform private.automation_exception('minmax:'||row.product_id,'replenishment','gamaPurchasesV14','product',row.product_id,reason,p_job.id,item->>'reference');
   skipped:=skipped+1;
  else items:=items||jsonb_build_array(item);
  end if;
 end loop;
 for grouped in
  select x->>'supplier_id' supplier,max((x->>'lead_time_days')::integer) lead,
   sum(round((x->>'quantity')::numeric*(x->>'unit_cost')::numeric,2)
    +round(round((x->>'quantity')::numeric*(x->>'unit_cost')::numeric,2)*(x->>'tax_rate')::numeric/100,2)) total,
   jsonb_agg(jsonb_build_object('product_id',x->>'id','quantity',(x->>'quantity')::numeric,
    'unit_cost',(x->>'unit_cost')::numeric,'tax_rate',(x->>'tax_rate')::numeric) order by x->>'id') lines
  from jsonb_array_elements(items) x group by x->>'supplier_id' order by x->>'supplier_id'
 loop
  if grouped.total>cap or jsonb_array_length(grouped.lines)>500 then
   perform private.automation_exception('minmax:limit:'||grouped.supplier,'replenishment','gamaPurchasesV14','supplier',grouped.supplier::uuid,
    case when grouped.total>cap then 'PURCHASE_LIMIT_EXCEEDED' else 'SUPPLIER_LINE_LIMIT_500' end,p_job.id);
   skipped:=skipped+jsonb_array_length(grouped.lines);continue;
  end if;
  po:=private.gama_purchase_save(jsonb_build_object(
   'request_key',private.automation_key('minmax:'||p_job.id||':'||grouped.supplier),
   'supplier_id',grouped.supplier,'source_kind','low_stock',
   'destination_location_id',p_config->>'destination_location_id',
   'expected_date',case when grouped.lead is not null then current_date+grouped.lead end,
   'notes','Reposición automática mín./máx.: máximo de la ficha menos stock físico y compras pendientes (incluidos borradores). Revisar antes de enviar.',
   'lines',grouped.lines));
  orders:=orders||jsonb_build_array(jsonb_build_object('id',po->>'id','number',po->>'order_number',
   'supplier_id',grouped.supplier,'lines',jsonb_array_length(grouped.lines)));
  products_count:=products_count+jsonb_array_length(grouped.lines);
 end loop;
 result:=jsonb_build_object('orders',orders,'products',products_count,'skipped',skipped,'basis','min_max','as_of',now());
 insert into private.command_receipts(domain,request_key,actor_id,payload,result)
  values('automatic-minmax-replenish',p_job.id,auth.uid(),p_config,result);
 return result;
end $$;
revoke all on function private.automation_replenish_minmax(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;

-- Preserve the demand-based mode and every existing rule's behaviour.
alter function private.automation_replenish(private.automation_jobs,jsonb) rename to automation_replenish_forecast;
create function private.automation_replenish(p_job private.automation_jobs,p_config jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_config->>'basis'='min_max' then return private.automation_replenish_minmax(p_job,p_config);
 elsif coalesce(p_config->>'basis','demand')='demand' then return private.automation_replenish_forecast(p_job,p_config);
 else raise exception 'INVALID_REPLENISHMENT_BASIS';end if;
end $$;
revoke all on function private.automation_replenish(private.automation_jobs,jsonb),
 private.automation_replenish_forecast(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;

-- The Purchases suggestions must also deduct drafts; otherwise the manual
-- button continues proposing the quantities the background job just created.
-- Preserve the view's existing column order, access checks and demand semantics.
do $$declare source text;columns_sql text;begin
 source:=rtrim(pg_get_viewdef('public.replenishment_needs'::regclass,true),';');
 select string_agg(case
  when attname='projected_available' then '(b.projected_available+coalesce(d.quantity,0))::numeric as projected_available'
  when attname='suggested_purchase' then $column$case when p.replenishment_excluded then 0::numeric
   when b.projected_available+coalesce(d.quantity,0)<b.min_stock or b.projected_available+coalesce(d.quantity,0)<0
   then greatest(b.max_stock,b.min_stock,0)-b.projected_available-coalesce(d.quantity,0) else 0::numeric end as suggested_purchase$column$
  else format('b.%I',attname) end,',' order by attnum) into columns_sql
 from pg_attribute where attrelid='public.replenishment_needs'::regclass and attnum>0 and not attisdropped;
 execute 'create or replace view public.replenishment_needs with(security_invoker=true) as select '||columns_sql||
  ' from ('||source||') b join public.products p on p.id=b.product_id left join ('||
  'select l.product_id,sum(greatest(l.quantity-l.received_quantity,0)) quantity from public.purchase_order_lines l '||
  'join public.purchase_orders o on o.id=l.purchase_order_id where o.status=''draft'' group by l.product_id) d on d.product_id=b.product_id';
end $$;
