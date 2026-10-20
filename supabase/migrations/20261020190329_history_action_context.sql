-- Preserve a small, typed account of the actual change, never a row snapshot.
-- This helper is callable only by the existing capture trigger.
create function private.coco_history_change_context(p_module text,p_table text,p_op text,p_before jsonb,p_after jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb:='{}';changes jsonb:='[]';k text;v jsonb;old_value jsonb;loc text;location_key text;currency_code text;
begin
 if p_module in ('hr','users','access-settings','settings','sri') then return result;end if;
 foreach k in array array['name','title','reference','code','barcode','quantity','reserved_quantity','received_quantity','min_stock','max_stock','sale_price','purchase_price','unit_price','unit_cost','amount','total','subtotal','litres','odometer','active','status','movement_type','type','photo_data','data_url'] loop
  if not (p_after ? k) and not (p_before ? k) then continue;end if;
  v:=p_after->k;old_value:=p_before->k;
  if p_op='UPDATE' and v is not distinct from old_value then continue;end if;
  if k in ('photo_data','data_url') then
   changes:=changes||jsonb_build_array(jsonb_build_object('field','photo','changed',true));
  elsif k in ('name','title','reference','code','barcode') and jsonb_typeof(v)='string' then
   changes:=changes||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('field',k,'before',case when p_op='UPDATE' then left(old_value #>> '{}',180) end,'after',left(v #>> '{}',180))));
  elsif k in ('status','movement_type','type') then
   -- Only bounded status/type codes, never free text or arbitrary detail.
   if (v #>> '{}') !~ '^[[:alnum:]_ -]{1,60}$' then continue;end if;
   changes:=changes||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('field',k,'before',case when p_op='UPDATE' and (old_value #>> '{}') ~ '^[[:alnum:]_ -]{1,60}$' then old_value end,'after',v)));
  elsif jsonb_typeof(v) in ('number','boolean','null') then
   changes:=changes||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('field',k,'before',case when p_op='UPDATE' and jsonb_typeof(old_value) in ('number','boolean') then old_value end,'after',v)));
  end if;
 end loop;
 result:=jsonb_build_object('changes',changes);
 if exists(select 1 from jsonb_array_elements(changes) c where c->>'field' in ('sale_price','purchase_price','unit_price','unit_cost','amount','total','subtotal')) then
  select coalesce(nullif(p_after->>'currency',''),s.currency) into currency_code from public.company_settings s limit 1;
  if currency_code ~ '^[A-Z]{3}$' then result:=result||jsonb_build_object('currency',currency_code);end if;
 end if;
 if p_module='warehouses' then
  foreach location_key in array array['location_id','source_location_id','destination_location_id'] loop
   if p_after->>location_key is null then continue;end if;
   select concat_ws(' · ',w.name,l.code,l.name) into loc from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id::text=p_after->>location_key;
   if loc is not null then result:=result||jsonb_build_object(replace(location_key,'_id',''),left(loc,220));end if;
  end loop;
 end if;
 return result;
end $$;
revoke all on function private.coco_history_change_context(text,text,text,jsonb,jsonb) from public,anon,authenticated,service_role;

-- Upgrade known document routes. A generic module route remains a module route;
-- its record UUID must never be presented as a supposedly opened document.
create function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select jsonb_strip_nulls(jsonb_build_object('module',p_module,'id',p_id,'reference',p_reference,'action',
  case p_table when 'sales_orders' then 'order' when 'purchase_orders' then 'purchase' when 'invoices' then 'quote'
   when 'tms_deliveries' then 'delivery' when 'external_invoices' then 'invoice' when 'supplier_invoices' then 'supplier_invoice'
   when 'business_documents' then 'document' when 'crm_opportunities' then 'opportunity' when 'return_requests' then 'return' else 'module' end))
$$;
revoke all on function private.coco_history_typed_link(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link(text,text,text,text) to authenticated;

do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_capture_module_event()'::regprocedure);
 src:=replace(src,$s$'reference',p.reference,'name',p.name,$s$,$s$'reference',p.reference,'name',p.name,'unit',p.base_unit,$s$);
 needle:=' insert into private.coco_module_events(';
 if strpos(src,needle)=0 then raise exception 'HISTORY_CONTEXT_CAPTURE_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$
 -- One context per affected record: quantities are snapshots, not additive events.
 refs:=(select jsonb_agg(r||jsonb_build_object('record_id',rid,'record_table',tg_table_name,'quantity_mode','snapshot',
  'context',private.coco_history_change_context(cfg.module_id,tg_table_name,tg_op,coalesce(before_row,'{}'),n))) from jsonb_array_elements(refs) r);
 ln:=jsonb_build_array(private.coco_history_typed_link(cfg.module_id,tg_table_name,rid,ref))||(ln-0);
 if cfg.parent_column is not null and parent is not null then
  ln:=ln||jsonb_build_array(private.coco_history_typed_link(cfg.module_id,cfg.parent_table,n->>cfg.parent_column,ref));
 end if;
 if cfg.module_id='warehouses' and n->>'product_id' is not null then
  ln:=ln||jsonb_build_array(jsonb_build_object('module','warehouses','action','stock_product','id',n->>'product_id',
   'reference',refs->0->>'reference'));
 end if;
 if n->>'document_id' is not null then ln:=ln||jsonb_build_array(private.coco_history_typed_link('documents','business_documents',n->>'document_id',null));end if;
 if n->>'sales_order_id' is not null then ln:=ln||jsonb_build_array(private.coco_history_typed_link('sales-orders','sales_orders',n->>'sales_order_id',null));end if;
 if n->>'purchase_order_id' is not null then ln:=ln||jsonb_build_array(private.coco_history_typed_link('gamaPurchasesV14','purchase_orders',n->>'purchase_order_id',null));end if;
 if tg_op='DELETE' then ln:=jsonb_build_array(jsonb_build_object('module',cfg.module_id,'action','module'));end if;
 insert into private.coco_module_events($s$);
 execute src;

 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:='select module_id,min(id::text) id,max(created_at) at,actor_id,max(actor_name) actor_name,type,action,subject,body,';
 if strpos(src,needle)=0 then raise exception 'HISTORY_CONTEXT_GROUP_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$select module_id,record_table,min(id::text) id,max(created_at) at,actor_id,max(actor_name) actor_name,type,action,subject,string_agg(distinct nullif(body,''),E'\n') body,$s$);
 src:=replace(src,'record_table,actor_id,type,action,subject,body,','record_table,actor_id,actor_name,type,action,subject,');
 src:=replace(src,$s$'action_count',p.action_count,$s$,$s$'record_table',p.record_table,'action_count',p.action_count,$s$);
 execute src;
end $$;
notify pgrst,'reload schema';
