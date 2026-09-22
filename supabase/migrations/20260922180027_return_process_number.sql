-- Procesos de devolución: PRC (cliente) y PRP (proveedor), un número cada uno.
--
-- Como la venta (PDV) y la compra (PDC), cada devolución es ahora un proceso
-- con un número que llevan todos sus documentos: la devolución DEV-00001340,
-- su abono NCR-00001340 y su reembolso REE-00001340.
--
-- Hasta aquí la devolución de un cliente entraba en el expediente de su venta:
-- dos devoluciones de la misma venta habrían compartido número, y el abono y el
-- reembolso llevaban contadores propios. Ahora la devolución abre su propio
-- expediente —el pedido, la entrega y la factura de origen siguen enlazados en
-- sus columnas y se enseñan en el paso 1—, y el abono y el reembolso entran en
-- él. Las referencias ya emitidas no cambian.

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
  -- Una devolución es su propio proceso (PRC o PRP): abre su expediente en vez
  -- de entrar en el de la venta. El enlace con el pedido sigue en sus columnas.
  when 'return_orders' then edges:='[]'::jsonb;
  -- Su abono y su reembolso llevan su número.
  when 'return_credits' then edges:=jsonb_build_array(jsonb_build_array('return_orders',j->>'return_id'));
  when 'return_refunds' then edges:=jsonb_build_array(jsonb_build_array('return_orders',j->>'return_id'));
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

create or replace function private.erp_stamp_reference() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare j jsonb:=to_jsonb(new);f public.erp_reference_formats;key text:=coalesce(j->>'id',j->>'delivery_id');ref text;begin
 select * into f from public.erp_reference_formats where source_table=tg_table_name and (kind_value is null or kind_value=j->>'kind');
 if not found then raise exception 'REFERENCE_KIND_INVALID';end if;
 if tg_table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders','purchase_orders','return_credits','return_refunds')
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

-- Abonos y reembolsos existentes: entran en el expediente de su devolución,
-- conservando su referencia.
do $$declare r record;begin
 for r in select to_jsonb(c) j from public.return_credits c order by c.created_at,c.id loop
  perform private.gama_register_document('return_credits',r.j);
 end loop;
 for r in select to_jsonb(f) j from public.return_refunds f order by f.created_at,f.id loop
  perform private.gama_register_document('return_refunds',r.j);
 end loop;
end $$;
