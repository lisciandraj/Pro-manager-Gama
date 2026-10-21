-- Log future automatic min/max purchase drafts in the purchase module inbox.
-- Keep the existing locks, permissions, quantity calculation and durable receipts.
-- No historical backfill: a replayed receipt returns before any new history write.
create or replace function private.automation_replenish_minmax(p_job private.automation_jobs,p_config jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 row record;item jsonb;items jsonb:='[]';grouped record;orders jsonb:='[]';po jsonb;result jsonb;
 cap numeric:=coalesce((p_config->>'max_order_total')::numeric,1000);
 receipt private.command_receipts;products_count integer:=0;skipped integer:=0;reason text;author text;supplier_name text;snapshot jsonb;
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
  -- This module event commits with the actual draft, never with a stock check.
  -- The delegated account remains the recorded actor; the title marks automation.
  select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
  select name into supplier_name from public.suppliers where id=grouped.supplier::uuid;
  select jsonb_agg(jsonb_build_object('product_id',x->>'id','name',x->>'name','reference',x->>'reference',
   'quantity',x->'quantity','on_hand',x->'on_hand','min_stock',x->'min_stock','max_stock',x->'max_stock') order by x->>'id')
   into snapshot from jsonb_array_elements(items) x where x->>'supplier_id'=grouped.supplier;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,request_key,detail)
   values('purchase',null,'action',auth.uid(),coalesce(author,'USER_UNAVAILABLE'),'automatic_minmax_purchase',
    concat_ws(' · ',po->>'order_number',supplier_name),private.automation_key('minmax-history:'||(po->>'id')),
    jsonb_build_object('purchase_order_id',po->>'id','job_id',p_job.id,'basis','min_max','replenishment',snapshot))
   on conflict(actor_id,request_key) do nothing;
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

-- Expose only the navigation target and stock snapshot on the already-scoped
-- history projection. Keep every module, financial and proposal permission intact.
do $$declare source text;needle text:='e.detail->>''source_subject'' source_subject';begin
 source:=pg_get_functiondef('private.coco_dossier(text,jsonb)'::regprocedure);
 if (length(source)-length(replace(source,needle,'')))/length(needle)<>1 then
  raise exception 'UNEXPECTED_DOSSIER_HISTORY_PROJECTION';
 end if;
 source:=replace(source,needle,needle||',e.detail->>''purchase_order_id'' purchase_order_id,e.detail->''replenishment'' replenishment');
 execute source;
end $$;
notify pgrst,'reload schema';
