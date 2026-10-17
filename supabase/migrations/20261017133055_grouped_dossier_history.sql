-- Enrich only events already admitted by the dossier's existing access checks.
-- This internal projection never returns raw audit/detail payloads or prices.
create function private.coco_history_event_details(p_event text,p_key text,p_action text,p_step integer,p_reference text) returns jsonb
language plpgsql stable set search_path='' as $$
declare
 source uuid:=split_part(p_key,':',2)::uuid;prefix text:=split_part(p_event,':',1);token text:=split_part(p_event,':',2);
 eid uuid;entity uuid;pid uuid;line_id uuid;delivery_id uuid;quote_id uuid;invoice_id uuid;
 detail jsonb:='{}';before_data jsonb:='{}';after_data jsonb:='{}';tbl text;at_time timestamptz;qty numeric;
 refs jsonb:='[]';links jsonb:='[]';doc_reference text;product_name text;product_reference text;unit text;
begin
 if split_part(p_key,':',1)='q' then quote_id:=source;select o.id into source from public.sales_orders o where o.source_quote_id=quote_id;end if;
 if token ~ '^[0-9a-fA-F-]{36}$' then eid:=token::uuid;end if;
 if prefix='sale' then
  select e.detail,e.entity_id,e.created_at into detail,entity,at_time from public.sales_events e where e.id=eid and e.order_id=source;
  if detail->>'product_id' ~ '^[0-9a-fA-F-]{36}$' then pid:=(detail->>'product_id')::uuid;end if;
  if detail->>'line_id' ~ '^[0-9a-fA-F-]{36}$' then line_id:=(detail->>'line_id')::uuid;end if;
  if jsonb_typeof(detail->'quantity')='number' then qty:=(detail->>'quantity')::numeric;end if;
  if p_action='fulfillment_pick' then select l.order_line_id into line_id from public.fulfillment_pick_lines l where l.id=entity;end if;
  if line_id is not null then select l.product_id,l.product_name,l.reference into pid,product_name,product_reference from public.sales_order_lines l where l.id=line_id and l.order_id=source;end if;
  if p_action in ('confirm','reserve') then
   select coalesce(jsonb_agg(jsonb_build_object('kind','product','id',x.product_id,'reference',x.reference,'name',x.product_name,'quantity',x.quantity,'unit',x.base_unit)),'[]') into refs from (
    select l.product_id,l.reference,l.product_name,p.base_unit,sum(r.quantity) quantity from public.stock_reservations r
    join public.sales_reservation_links sl on sl.reservation_id=r.id join public.sales_order_lines l on l.id=sl.line_id join public.products p on p.id=l.product_id
    where l.order_id=source and r.created_at=at_time group by l.product_id,l.reference,l.product_name,p.base_unit
   ) x;
  elsif p_action='fulfillment_package' then
   select coalesce(jsonb_agg(jsonb_build_object('kind','product','id',l.product_id,'reference',l.reference,'name',l.product_name,'quantity',pl.quantity,'unit',p.base_unit)),'[]') into refs
    from public.fulfillment_package_lines pl join public.fulfillment_pick_lines pick on pick.id=pl.pick_line_id
    join public.sales_order_lines l on l.id=pick.order_line_id join public.products p on p.id=l.product_id where pl.package_id=entity and l.order_id=source;
  end if;
  if p_action like 'internal_%' or p_action like 'invoice_%' or p_action in ('invoice','deposit_created') then
   select i.id,i.number into invoice_id,doc_reference from public.external_invoices i where i.id=entity and i.order_id=source;
   if invoice_id is not null then
    refs:=refs||jsonb_build_array(jsonb_build_object('kind','invoice','id',invoice_id,'reference',doc_reference));
    if private.erp_module_allowed('payments',array['administrador','comercial']) then links:=links||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',invoice_id,'reference',doc_reference));end if;
   end if;
  end if;
  select d.tms_delivery_id into delivery_id from public.sales_deliveries d where d.id=entity and d.order_id=source;
 elsif prefix='stock' then
  select m.product_id,m.quantity into pid,qty from public.stock_movements m where m.id=eid and m.reference_type='purchase_order' and m.reference_id=source;
 elsif prefix='audit' and token ~ '^[0-9]+$' then
  select a.table_name,a.before_data,a.after_data into tbl,before_data,after_data from public.erp_audit_events a where a.id=token::bigint;
  if tbl='purchase_order_lines' and after_data->>'purchase_order_id'=source::text then
   pid:=(after_data->>'product_id')::uuid;qty:=coalesce((after_data->>'received_quantity')::numeric,0)-coalesce((before_data->>'received_quantity')::numeric,0);
  elsif tbl='supplier_invoices' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   invoice_id:=(after_data->>'id')::uuid;doc_reference:=coalesce(after_data->>'number',p_reference);
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',invoice_id,'reference',doc_reference));
  elsif tbl='supplier_invoice_payments' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',after_data->>'supplier_invoice_id','reference',p_reference));
  elsif tbl='supplier_invoice_matches' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',after_data->>'invoice_id','reference',p_reference));
  elsif tbl in ('external_invoices','external_invoice_payments') and private.erp_module_allowed('payments',array['administrador','comercial']) then
   invoice_id:=case when tbl='external_invoices' then (after_data->>'id')::uuid else (after_data->>'invoice_id')::uuid end;
   links:=links||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',invoice_id,'reference',p_reference));
  elsif tbl='customer_requests' and private.erp_module_allowed('customer-requests',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','customer-requests','action','request','id',after_data->>'id','reference',p_reference));
  elsif tbl='crm_opportunities' and private.erp_module_allowed('crm',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','crm','action','opportunity','id',after_data->>'id','reference',p_reference));
  end if;
 elsif prefix='request-created' and private.erp_module_allowed('customer-requests',array['administrador','comercial']) then
  links:=links||jsonb_build_array(jsonb_build_object('module','customer-requests','action','request','id',eid,'reference',p_reference));
 elsif prefix='opportunity-created' and private.erp_module_allowed('crm',array['administrador','comercial']) then
  links:=links||jsonb_build_array(jsonb_build_object('module','crm','action','opportunity','id',eid,'reference',p_reference));
 elsif prefix in ('credit-created','refund-created') and private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) then
  if prefix='credit-created' then select c.return_id into entity from public.return_credits c where c.id=eid;else select f.return_id into entity from public.return_refunds f where f.id=eid;end if;
  if entity is not null then links:=links||jsonb_build_array(jsonb_build_object('module','returns','action','return','id',entity,'reference',p_reference));end if;
 elsif prefix in ('delivery','proof') then
  if prefix='delivery' then select e.delivery_id into delivery_id from public.tms_events e where e.id=eid;else delivery_id:=eid;end if;
 elsif prefix in ('payment-created','supplier-payment-created') then
  if prefix='payment-created' and private.erp_module_allowed('payments',array['administrador','comercial']) then
   select p.invoice_id into invoice_id from public.external_invoice_payments p where p.id=eid;
   links:=links||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',invoice_id,'reference',p_reference));
  elsif prefix='supplier-payment-created' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   select p.supplier_invoice_id into invoice_id from public.supplier_invoice_payments p where p.id=eid;
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',invoice_id,'reference',p_reference));
  end if;
 end if;
 if pid is not null then
  select coalesce(product_name,p.name),coalesce(nullif(product_reference,''),p.reference),p.base_unit into product_name,product_reference,unit from public.products p where p.id=pid;
  refs:=refs||jsonb_build_array(jsonb_build_object('kind','product','id',pid,'reference',product_reference,'name',product_name,'quantity',qty,'unit',unit));
 end if;
 if nullif(p_reference,'') is not null then refs:=refs||jsonb_build_array(jsonb_build_object('kind','document','reference',p_reference));end if;
 if delivery_id is not null and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista']) then
  select coalesce(d.erp_reference,d.customer) into doc_reference from public.tms_deliveries d where d.id=delivery_id;
  links:=links||jsonb_build_array(jsonb_build_object('module','tms','action','delivery','id',delivery_id,'reference',doc_reference));
 end if;
 if split_part(p_key,':',1) in ('o','q') then
  if split_part(p_key,':',1)='o' then select o.source_quote_id into quote_id from public.sales_orders o where o.id=source;end if;
  if source is not null and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then
   select o.number into doc_reference from public.sales_orders o where o.id=source;
   links:=links||jsonb_build_array(jsonb_build_object('module','sales-orders','action','order','id',source,'reference',doc_reference));
  end if;
  if p_step<=3 and quote_id is not null and private.erp_module_allowed('quotes',array['administrador','comercial']) then
   select q.invoice_number into doc_reference from public.invoices q where q.id=quote_id;
   links:=links||jsonb_build_array(jsonb_build_object('module','quotes','action','quote','id',quote_id,'reference',doc_reference));
  end if;
  if p_step=4 and source is not null and private.erp_module_allowed('tms',array['administrador','comercial','almacenero']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','tms','action','preparation','id',source));
  end if;
 elsif split_part(p_key,':',1)='p' and private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial','almacenero']) then
  select o.order_number into doc_reference from public.purchase_orders o where o.id=source;
  links:=links||jsonb_build_array(jsonb_build_object('module','gamaPurchasesV14','action','purchase','id',source,'reference',doc_reference));
 end if;
 if p_step in (3,4) and (pid is not null or jsonb_array_length(refs)>0) and private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then
  links:=links||jsonb_build_array(jsonb_build_object('module','warehouses','action','module'));
 end if;
 return jsonb_build_object('references',refs,'links',links);
end $$;
revoke all on function private.coco_history_event_details(text,text,text,integer,text) from public,anon,authenticated;

-- Group transaction siblings before paging. An action by another author, on
-- another dossier, at another exact server timestamp or stage stays separate.
-- The canonical process history remains unchanged for milestone consumers.
do $$declare source text;needle text;replacement text;begin
 source:=pg_get_functiondef('private.coco_dossier_process_history(text,integer,integer)'::regprocedure);
 needle:=$old$ ), numbered as (
  select *,row_number() over(partition by stage order by at desc,id desc) rn,count(*) over(partition by stage) total from permitted
 ) select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'step',stage,'at',at,'actor_name',actor_name,'actor_id',actor_id,'action',action,'status',status,'reference',reference,'total',total) order by stage,at desc,id desc),'[]')) into result from numbered where rn>p_offset and rn<=p_offset+50;$old$;
 replacement:=$new$ ), grouped as (
  select min(id) id,stage,at,actor_id,actor_name,action,status,count(*) action_count,
   array_agg(id order by id) event_ids,array_agg(reference order by id) event_references
  from permitted group by stage,at,actor_id,actor_name,action,status
 ), numbered as (
  select *,row_number() over(partition by stage order by at desc,id desc) rn,count(*) over(partition by stage) total from grouped
 ), page as (
  select n.*,(select jsonb_agg(private.coco_history_event_details(x.id,p_key,n.action,n.stage,x.reference)) from unnest(n.event_ids,n.event_references) x(id,reference)) details
  from numbered n where rn>p_offset and rn<=p_offset+50
 ) select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'step',stage,'at',at,'actor_name',actor_name,'actor_id',actor_id,'action',action,'status',status,'action_count',action_count,'total',total,
  'references',coalesce((select jsonb_agg(r) from jsonb_array_elements(details) d cross join lateral jsonb_array_elements(d->'references') r),'[]'),
  'links',coalesce((select jsonb_agg(distinct l) from jsonb_array_elements(details) d cross join lateral jsonb_array_elements(d->'links') l),'[]')) order by stage,at desc,id desc),'[]')) into result from page;$new$;
 if position(needle in source)=0 then raise exception 'DOSSIER_HISTORY_GROUPING_PATCH_MISMATCH';end if;
 execute replace(source,needle,replacement);
end $$;
notify pgrst,'reload schema';
