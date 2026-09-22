-- Proceso de compra (PDC): un solo número para todos sus documentos.
--
-- En la venta, solicitud, presupuesto, pedido, preparación, envío, factura y
-- cobro comparten el número de su expediente (SOL-, COT-, PED-…-00001246).
-- En la compra cada documento llevaba su propio contador: el pedido OCO-7, su
-- factura FPR-45 y su pago PPR-12 hablaban del mismo proceso con tres números.
-- Desde aquí el pedido de compra abre un expediente, su factura de proveedor
-- entra en él y el pago entra en el de su factura: OCO-, FPR- y PPR-00001330.
--
-- Además, el pedido guarda de dónde nace la necesidad —el paso 1 del proceso—:
--   manual       creado en el módulo Compras
--   low_stock    preparado desde la alerta de stock bajo el mínimo
--   sales_order  preparado desde un pedido de cliente que supera el stock
--
-- Las referencias ya emitidas no cambian. Los pedidos existentes entran cada
-- uno en un expediente nuevo, conservando su OCO; el número único vale para
-- los procesos que se abran a partir de ahora.

alter table public.purchase_orders
  add column if not exists source_kind text not null default 'manual',
  add column if not exists source_order_id uuid references public.sales_orders(id) on delete set null;
alter table public.purchase_orders drop constraint if exists purchase_orders_source_kind_check;
alter table public.purchase_orders add constraint purchase_orders_source_kind_check
  check (source_kind in ('manual','low_stock','sales_order') and (source_kind = 'sales_order' or source_order_id is null));

-- La creación acepta el origen; lo demás, idéntico.
create or replace function private.gama_purchase_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare actor uuid:=auth.uid();request uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;payload jsonb:=p_data-'request_key';po public.purchase_orders;
 supplier public.suppliers;product public.products;line jsonb;qty numeric;cost numeric;rate numeric;
 net numeric;vat numeric;v_sub numeric:=0;v_tax numeric:=0;result jsonb;location uuid:=nullif(p_data->>'destination_location_id','')::uuid;
 origin text:=coalesce(nullif(p_data->>'source_kind',''),'manual');origin_order uuid:=nullif(p_data->>'source_order_id','')::uuid;
begin if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if actor is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase:'||request::text,0));
 select * into receipt from private.command_receipts where domain='purchase' and request_key=request;
 if found then
  if receipt.actor_id<>actor or receipt.payload<>payload then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 if origin not in ('manual','low_stock','sales_order') then raise exception 'INVALID_SOURCE';end if;
 if origin='sales_order' and not exists(select 1 from public.sales_orders o where o.id=origin_order) then raise exception 'INVALID_SOURCE';end if;
 if origin<>'sales_order' then origin_order:=null;end if;
 select * into supplier from public.suppliers where id=(p_data->>'supplier_id')::uuid and active;
 if not found then raise exception 'SUPPLIER_REQUIRED';end if;
 if location is not null and not exists(select 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id=location and l.active and w.active) then raise exception 'INVALID_LOCATION';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 insert into public.purchase_orders(supplier_id,status,expected_date,notes,created_by,destination_location_id,source_kind,source_order_id)
 values(supplier.id,'draft',nullif(p_data->>'expected_date','')::timestamptz,nullif(p_data->>'notes',''),actor,location,origin,origin_order) returning * into po;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  select * into product from public.products where id=(line->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  qty:=(line->>'quantity')::numeric;cost:=(line->>'unit_cost')::numeric;rate:=coalesce(nullif(line->>'tax_rate','')::numeric,product.tax_rate,0);
  if qty is null or qty<=0 or qty>999999999 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
  if cost is null or cost<0 or cost>999999999 or cost<>round(cost,2) then raise exception 'INVALID_PRICE';end if;
  if rate<0 or rate>100 or rate<>round(rate,3) then raise exception 'INVALID_TAX';end if;
  net:=round(qty*cost,2);vat:=round(net*rate/100,2);
  insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,unit_cost,tax_rate,line_total)
   values(po.id,product.id,qty,cost,rate,net+vat);
  v_sub:=v_sub+net;v_tax:=v_tax+vat;
 end loop;
 update public.purchase_orders set subtotal=v_sub,tax=v_tax,total=v_sub+v_tax where id=po.id returning * into po;
 result:=to_jsonb(po);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('purchase',request,actor,payload,result);
 return result;
end $function$;

-- Registro de documentos: la cadena de compra se suma a la de venta.
-- El 0 no es un expediente sino «todavía sin expediente»: no se busca en él,
-- y un documento que lo tenga entra en el expediente que le corresponda
-- conservando su referencia.
create or replace function private.gama_register_document(t text, j jsonb) returns void
language plpgsql security definer set search_path to '' as $function$
declare id uuid:=coalesce((j->>'id')::uuid,(j->>'delivery_id')::uuid); edges jsonb:='[]'; e jsonb;
 cases bigint[]:='{}'; target bigint; p uuid;
begin
 if id is null then return;end if;
 perform pg_advisory_xact_lock(724613092);
 case t
  when 'customer_requests' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'invoice_id'));
  when 'sales_orders' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'source_quote_id'),jsonb_build_array('customer_requests',j->>'source_request_id'));
  when 'fulfillment_preparations' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('sales_deliveries',j->>'shipment_id'));
  when 'fulfillment_packages' then edges:=jsonb_build_array(jsonb_build_array('fulfillment_preparations',j->>'preparation_id'));
  when 'sales_deliveries' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('tms_deliveries',j->>'tms_delivery_id'));
  when 'tms_proofs' then edges:=jsonb_build_array(jsonb_build_array('tms_deliveries',j->>'delivery_id'));
  when 'external_invoices' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('invoices',j->>'source_quote_id'));
  when 'external_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('external_invoices',j->>'invoice_id'));
  when 'return_orders' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('external_invoices',j->>'invoice_id'));
  -- Proceso de compra: la factura del proveedor, con su pedido; el pago, con su factura.
  when 'supplier_invoices' then edges:=jsonb_build_array(jsonb_build_array('purchase_orders',j->>'purchase_order_id'));
  when 'supplier_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('supplier_invoices',j->>'supplier_invoice_id'));
  else null;end case;

 -- Mirar antes de pedir: el documento y sus enlaces, por si ya tienen casa.
 cases:=coalesce((select array_agg(dossier_number) from public.gama_document_references
   where table_name=t and document_id=id and dossier_number>0),'{}');
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   cases:=cases||coalesce((select array_agg(dossier_number) from public.gama_document_references
     where table_name=e->>0 and document_id=p and dossier_number>0),'{}');
  end if;
 end loop;
 select min(x) into target from unnest(cases) x;
 -- Y sólo aquí, cuando de verdad nace un expediente, se gasta un número.
 if target is null then target:=nextval('private.gama_dossier_sequence');end if;

 insert into public.gama_document_references(table_name,document_id,dossier_number)
  values(t,id,target) on conflict do nothing;
 update public.gama_document_references set dossier_number=target
  where table_name=t and document_id=id and dossier_number=0;
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   insert into public.gama_document_references(table_name,document_id,dossier_number)
    values(e->>0,p,target) on conflict do nothing;
   update public.gama_document_references set dossier_number=target
    where table_name=e->>0 and document_id=p and dossier_number=0;
  end if;
 end loop;

 update public.gama_document_references set dossier_number=target
  where dossier_number=any(cases) and dossier_number<>target;

 update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;
end $function$;

-- El sello de referencias envía la cadena de compra al registro. Una factura
-- de proveedor sin pedido, o el pago de una factura así, no es un proceso de
-- compra: sigue con su contador propio, como hasta ahora.
create or replace function private.erp_stamp_reference() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare j jsonb:=to_jsonb(new);f public.erp_reference_formats;key text:=coalesce(j->>'id',j->>'delivery_id');ref text;begin
 select * into f from public.erp_reference_formats where source_table=tg_table_name and (kind_value is null or kind_value=j->>'kind');
 if not found then raise exception 'REFERENCE_KIND_INVALID';end if;
 if tg_table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders','purchase_orders')
    or (tg_table_name='supplier_invoices' and j->>'purchase_order_id' is not null)
    or (tg_table_name='supplier_invoice_payments' and exists(select 1 from public.gama_document_references d where d.table_name='supplier_invoices' and d.document_id=(j->>'supplier_invoice_id')::uuid and d.dossier_number>0)) then
 perform private.gama_register_document(tg_table_name,j);
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 else
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 if ref is null then ref:=private.erp_issue_reference(f.kind,tg_table_name||'/'||key,null,j->>f.number_column);end if;
 insert into public.gama_document_references(table_name,document_id,dossier_number,document_reference) values(tg_table_name,key::uuid,0,ref) on conflict(table_name,document_id) do nothing;
 end if;
 j:=jsonb_build_object('erp_reference',ref);
 if f.number_column is not null then j:=j||jsonb_build_object(f.number_column,ref);end if;
 if tg_table_name='external_invoices' and to_jsonb(new)->>'document_kind'='internal' then j:=j||jsonb_build_object('number',ref);end if;
 new:=jsonb_populate_record(new,j);return new;
end $function$;

-- Los pedidos de compra existentes entran cada uno en su expediente, con sus
-- facturas y pagos; las referencias ya emitidas se conservan.
do $$declare r record;begin
 for r in select to_jsonb(p) j from public.purchase_orders p order by p.created_at,p.id loop
  perform private.gama_register_document('purchase_orders',r.j);
 end loop;
 for r in select to_jsonb(s) j from public.supplier_invoices s where s.purchase_order_id is not null order by s.created_at,s.id loop
  perform private.gama_register_document('supplier_invoices',r.j);
 end loop;
 for r in select to_jsonb(x) j from public.supplier_invoice_payments x
   where exists(select 1 from public.gama_document_references d where d.table_name='supplier_invoices' and d.document_id=x.supplier_invoice_id and d.dossier_number>0)
   order by x.created_at,x.id loop
  perform private.gama_register_document('supplier_invoice_payments',r.j);
 end loop;
end $$;
