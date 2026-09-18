-- Load fulfillment-test-helpers.sql in the same rollback transaction first.
-- Run within BEGIN/ROLLBACK; fixtures and Auth rows are never kept.
-- Cubre los diez casos exigidos por el pliego de Devoluciones.
do $$
#variable_conflict use_column
declare
 admin_id uuid; sales_id uuid:=gen_random_uuid(); ware_id uuid:=gen_random_uuid();
 fin_id uuid:=gen_random_uuid(); client_id uuid:=gen_random_uuid();
 cid uuid; sup uuid; wh uuid; loc uuid;
 pa uuid; pb uuid; pc uuid; pd uuid;
 oid uuid; la uuid; lb uuid; lc uuid; sid uuid; inv uuid; invoice_total numeric;
 dla uuid; dlb uuid; dlc uuid;
 po uuid; pol uuid;
 r jsonb; j jsonb; row_json jsonb; rid uuid; rid2 uuid; rid3 uuid; rid4 uuid;
 credit_id uuid; dossier bigint; quote_id uuid;
 rejected boolean; n numeric; avail numeric; phys numeric;
begin
 select id into admin_id from public.profiles where role='administrador' and active limit 1;
 select id,warehouse_id into loc,wh from public.warehouse_locations where active order by id limit 1;
 insert into auth.users(id,email,email_confirmed_at) values
  (sales_id,sales_id||'@gama-test.invalid',now()),(ware_id,ware_id||'@gama-test.invalid',now()),
  (fin_id,fin_id||'@gama-test.invalid',now()),(client_id,client_id||'@gama-test.invalid',now());
 insert into public.profiles(id,role,active,full_name) values
  (sales_id,'comercial',true,'Test comercial'),(ware_id,'almacenero',true,'Test almacen'),
  (fin_id,'comercial',true,'Test finanzas'),(client_id,'cliente',true,'Test cliente')
  on conflict(id) do update set role=excluded.role,active=true,full_name=excluded.full_name;
 -- «Finanzas» no es un rol de GAMA: es quien puede validar en Contabilidad.
 insert into public.accounting_permissions(profile_id,can_validate) values(fin_id,true)
  on conflict(profile_id) do update set can_validate=true;

 insert into public.customers(name,identification,address) values('Returns test rollback','0999999999001','Quito') returning id into cid;
 insert into public.suppliers(name) values('Returns supplier rollback') returning id into sup;
 insert into public.products(name,barcode,reference,sale_price,stock) values
  ('Return A '||gen_random_uuid(),'RET-A-'||gen_random_uuid(),gen_random_uuid()::text,10,10) returning id into pa;
 insert into public.products(name,barcode,reference,sale_price,stock) values
  ('Return B '||gen_random_uuid(),'RET-B-'||gen_random_uuid(),gen_random_uuid()::text,10,3) returning id into pb;
 insert into public.products(name,barcode,reference,sale_price,stock) values
  ('Return C '||gen_random_uuid(),'RET-C-'||gen_random_uuid(),gen_random_uuid()::text,25,10) returning id into pc;
 insert into public.products(name,barcode,reference,sale_price,stock) values
  ('Return D '||gen_random_uuid(),'RET-D-'||gen_random_uuid(),gen_random_uuid()::text,5,20) returning id into pd;
 insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity)
  values(pa,loc,10,0),(pb,loc,3,0),(pc,loc,10,0),(pd,loc,20,0);

 perform set_config('request.jwt.claim.sub',admin_id::text,true);execute 'set local role authenticated';
 r:=public.gama_sales_action('create',jsonb_build_object('request_key',gen_random_uuid(),'customer_id',cid,
   'delivery_address','Quito','lines',jsonb_build_array(
     jsonb_build_object('product_id',pa,'quantity',10,'unit_price',10,'tax_rate',0),
     jsonb_build_object('product_id',pb,'quantity',3,'unit_price',10,'tax_rate',0),
     jsonb_build_object('product_id',pc,'quantity',10,'unit_price',25,'tax_rate',0))));
 oid:=(r->>'id')::uuid;
 perform public.gama_sales_action('confirm',jsonb_build_object('order_id',oid));
 select id into la from public.sales_order_lines where order_id=oid and product_id=pa;
 select id into lb from public.sales_order_lines where order_id=oid and product_id=pb;
 select id into lc from public.sales_order_lines where order_id=oid and product_id=pc;
 r:=pg_temp.gama_test_prepared_ship('ship',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),
   'delivery_date',current_date,'lines',jsonb_build_array(
     jsonb_build_object('line_id',la,'location_id',loc,'quantity',10),
     jsonb_build_object('line_id',lb,'location_id',loc,'quantity',3),
     jsonb_build_object('line_id',lc,'location_id',loc,'quantity',10))));
 sid:=(r->>'id')::uuid;
 select id into dla from public.sales_delivery_lines where delivery_id=sid and order_line_id=la;
 select id into dlb from public.sales_delivery_lines where delivery_id=sid and order_line_id=lb;
 select id into dlc from public.sales_delivery_lines where delivery_id=sid and order_line_id=lc;
 -- La factura nace de un presupuesto: aquí se monta el fixture equivalente
 -- en lugar de forzar la API comercial, que exige toda la cadena firmada.
 execute 'reset role';
 insert into public.invoices(customer_id,user_id,quote_state,subtotal,tax,quote_details)
  values(cid,admin_id,'accepted',380,0,'{}') returning id into quote_id;
 insert into public.external_invoices(request_key,order_id,number,issuer_ruc,software,issue_date,
   subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot)
  values(gen_random_uuid(),oid,'RET-TEST-'||gen_random_uuid(),'1234567890001','QA',current_date,
   380,0,'unverified',admin_id,'internal',quote_id,'{}') returning id into inv;
 execute 'set local role authenticated';
 select total into invoice_total from public.external_invoices where id=inv;
 if invoice_total is null or invoice_total<=0 then raise exception 'FAIL_INVOICE_FIXTURE';end if;

 -- ------------------------------------------------------------------ origen
 -- La pantalla nunca pide lo que GAMA ya sabe: elige una salida y recibe el
 -- cliente, la factura y las líneas con su precio.
 r:=public.gama_returns_action('sources',jsonb_build_object('kind','customer'));
 if not exists(select 1 from jsonb_array_elements(r->'rows') x where (x->>'id')::uuid=sid)
  then raise exception 'FAIL_SOURCE_LIST';end if;
 r:=public.gama_returns_action('source_lines',jsonb_build_object('kind','customer','source_id',sid));
 if (r->>'customer_id')::uuid<>cid or (r->>'invoice_id')::uuid<>inv
  then raise exception 'FAIL_SOURCE_PREFILL';end if;
 select value into row_json from jsonb_array_elements(r->'rows') where (value->>'line_id')::uuid=dla;
 if (row_json->>'moved')::numeric<>10 or (row_json->>'returned')::numeric<>0
  or (row_json->>'max_return')::numeric<>10 or (row_json->>'unit_price')::numeric<>10
  then raise exception 'FAIL_SOURCE_LINE';end if;

 -- --------------------------------------------- Caso 1 — devolución simple
 -- 10 entregados, 2 devueltos, 2 repuestos: stock +2.
 r:=public.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',sid,
   'invoice_id',inv,'reason','defective','lines',jsonb_build_array(
     jsonb_build_object('line_id',dla,'quantity',2))));
 rid:=(r->>'id')::uuid;
 if (r->>'number') !~ '^RET-[0-9]{6}$' then raise exception 'FAIL_RETURN_NUMBER';end if;
 select coalesce(sum(quantity-reserved_quantity),0) into avail from public.stock_quants where product_id=pa;
 perform set_config('request.jwt.claim.sub',ware_id::text,true);
 perform public.gama_returns_action('receive',jsonb_build_object('id',rid,'location_id',loc));
 if (select status from public.return_orders where id=rid)<>'received' then raise exception 'FAIL_RECEIVE';end if;
 if (select coalesce(sum(quantity-reserved_quantity),0) from public.stock_quants where product_id=pa)<>avail
  then raise exception 'FAIL_QUARANTINE_AVAILABLE';end if;
 -- La retención de cuarentena no se suelta a mano: sólo la procesa el módulo.
 rejected:=false;
 begin perform public.gama_stock_unreserve(
   (select hold_reservation_id from public.return_lines where return_id=rid));
 exception when others then if sqlerrm='FULFILLMENT_RESERVATION_LOCKED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_QUARANTINE_RELEASE';end if;
 perform public.gama_returns_action('process_line',jsonb_build_object('id',rid,
   'line_id',(select id from public.return_lines where return_id=rid),
   'disposition','restocked','location_id',loc));
 if (select coalesce(sum(quantity-reserved_quantity),0) from public.stock_quants where product_id=pa)<>avail+2
  then raise exception 'FAIL_CASE1_RESTOCK';end if;
 if (select stock from public.products where id=pa)<>avail+2 then raise exception 'FAIL_CASE1_PRODUCT_STOCK';end if;
 if (select status from public.return_orders where id=rid)<>'processed' then raise exception 'FAIL_CASE1_STATUS';end if;
 if not exists(select 1 from public.stock_movements where reference_id=rid and reference_type='customer_return'
   and movement_type='return_in' and product_id=pa) then raise exception 'FAIL_CASE1_MOVEMENT';end if;

 -- ------------------------------------------- Caso 7 — doble tratamiento
 -- La misma línea no se repone dos veces.
 rejected:=false;
 begin perform public.gama_returns_action('process_line',jsonb_build_object('id',rid,
   'line_id',(select id from public.return_lines where return_id=rid),
   'disposition','restocked','location_id',loc));
 exception when others then if sqlerrm='LINE_ALREADY_PROCESSED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CASE7_DOUBLE_PROCESS';end if;

 -- ------------------------------------------------------ Caso 2 — rebut
 -- 3 devueltos, 3 al rebut: el stock disponible no se mueve al recibir.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 r:=public.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',sid,
   'invoice_id',inv,'reason','damaged','lines',jsonb_build_array(
     jsonb_build_object('line_id',dlb,'quantity',3))));
 rid2:=(r->>'id')::uuid;
 select coalesce(sum(quantity-reserved_quantity),0) into avail from public.stock_quants where product_id=pb;
 select coalesce(sum(quantity),0) into phys from public.stock_quants where product_id=pb;
 perform public.gama_returns_action('receive',jsonb_build_object('id',rid2,'location_id',loc));
 if (select coalesce(sum(quantity-reserved_quantity),0) from public.stock_quants where product_id=pb)<>avail
  then raise exception 'FAIL_CASE2_AVAILABLE_MOVED';end if;
 perform public.gama_returns_action('process_line',jsonb_build_object('id',rid2,
   'line_id',(select id from public.return_lines where return_id=rid2),'disposition','scrapped'));
 if (select coalesce(sum(quantity-reserved_quantity),0) from public.stock_quants where product_id=pb)<>avail
  or (select coalesce(sum(quantity),0) from public.stock_quants where product_id=pb)<>phys
  then raise exception 'FAIL_CASE2_SCRAP';end if;
 if not exists(select 1 from public.stock_movements where reference_id=rid2 and movement_type='return_out'
   and product_id=pb) then raise exception 'FAIL_CASE2_MOVEMENT';end if;

 -- ----------------------------------------------- Caso 3 — retorno parcial
 -- 10 entregados, 4 ya devueltos: como mucho quedan 6.
 r:=public.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',sid,
   'invoice_id',inv,'reason','wrong_product','lines',jsonb_build_array(
     jsonb_build_object('line_id',dlc,'quantity',4))));
 rid3:=(r->>'id')::uuid;
 r:=public.gama_returns_action('source_lines',jsonb_build_object('kind','customer','source_id',sid));
 select value into row_json from jsonb_array_elements(r->'rows') where (value->>'line_id')::uuid=dlc;
 if (row_json->>'returned')::numeric<>4 or (row_json->>'max_return')::numeric<>6
  then raise exception 'FAIL_CASE3_MAX_RETURN';end if;
 rejected:=false;
 begin perform public.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',sid,
   'reason','other','lines',jsonb_build_array(jsonb_build_object('line_id',dlc,'quantity',7))));
 exception when others then if sqlerrm='RETURN_EXCEEDS_DELIVERED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CASE3_CAP';end if;

 -- ------------------------------------------------------- Caso 6 — abono
 -- El importe sale de las líneas del retorno y queda atado a la factura.
 if private.gama_return_amount(rid3)<>100 then raise exception 'FAIL_RETURN_AMOUNT';end if;
 perform set_config('request.jwt.claim.sub',fin_id::text,true);
 r:=public.gama_returns_action('credit_preview',jsonb_build_object('id',rid3));
 if (r->>'amount')::numeric<>100 or (r->>'invoice_total')::numeric<>invoice_total
  then raise exception 'FAIL_CREDIT_PREVIEW';end if;
 r:=public.gama_returns_action('credit',jsonb_build_object('id',rid3));
 credit_id:=(r->>'id')::uuid;
 if (r->>'number') !~ '^AV-[0-9]{6}$' then raise exception 'FAIL_CREDIT_NUMBER';end if;
 if not exists(select 1 from public.return_credits where id=credit_id and return_id=rid3 and invoice_id=inv and amount=100)
  then raise exception 'FAIL_CASE6_LINK';end if;
 rejected:=false;
 begin perform public.gama_returns_action('credit',jsonb_build_object('id',rid3,'amount',invoice_total));
 exception when others then if sqlerrm='CREDIT_EXCEEDS_INVOICE' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CREDIT_CAP';end if;

 -- ------------------------------------------------ Caso 4 — reembolso
 -- Nunca por encima del importe devuelto, ni sumando varios reembolsos.
 rejected:=false;
 begin perform public.gama_returns_action('refund',jsonb_build_object('id',rid3,'amount',100.01,'method','transferencia'));
 exception when others then if sqlerrm='REFUND_EXCEEDS_RETURN' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CASE4_CAP';end if;
 r:=public.gama_returns_action('refund',jsonb_build_object('id',rid3,'method','transferencia','request_key',gen_random_uuid()));
 if (r->>'amount')::numeric<>100 or (r->>'outstanding')::numeric<>0
  then raise exception 'FAIL_CASE4_REFUND';end if;
 rejected:=false;
 begin perform public.gama_returns_action('refund',jsonb_build_object('id',rid3,'amount',0.01,'method','efectivo'));
 exception when others then if sqlerrm='REFUND_EXCEEDS_RETURN' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CASE4_SECOND_REFUND';end if;

 -- --------------------------------------------- Caso 5 — retorno proveedor
 -- 20 recibidos, 5 devueltos: el stock baja 5 al expedir.
 execute 'reset role';
 insert into public.purchase_orders(supplier_id,order_number,status)
  values(sup,'OC-TEST-'||gen_random_uuid(),'received') returning id into po;
 insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,received_quantity,unit_cost,tax_rate,line_total)
  values(po,pd,20,20,5,0,100) returning id into pol;
 execute 'set local role authenticated';
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 r:=public.gama_returns_action('source_lines',jsonb_build_object('kind','supplier','source_id',po));
 select value into row_json from jsonb_array_elements(r->'rows') where (value->>'line_id')::uuid=pol;
 if (row_json->>'moved')::numeric<>20 or (row_json->>'max_return')::numeric<>20
  then raise exception 'FAIL_CASE5_SOURCE';end if;
 rejected:=false;
 begin perform public.gama_returns_action('create',jsonb_build_object('kind','supplier','source_id',po,
   'reason','defective','lines',jsonb_build_array(jsonb_build_object('line_id',pol,'quantity',21))));
 exception when others then if sqlerrm='RETURN_EXCEEDS_RECEIVED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CASE5_CAP';end if;
 r:=public.gama_returns_action('create',jsonb_build_object('kind','supplier','source_id',po,
   'reason','defective','lines',jsonb_build_array(jsonb_build_object('line_id',pol,'quantity',5))));
 rid4:=(r->>'id')::uuid;
 select coalesce(sum(quantity),0) into phys from public.stock_quants where product_id=pd;
 perform public.gama_returns_action('ship',jsonb_build_object('id',rid4,'location_id',loc,
   'carrier','Servientrega','tracking','TR-1','shipped_on',current_date));
 if (select coalesce(sum(quantity),0) from public.stock_quants where product_id=pd)<>phys-5
  then raise exception 'FAIL_CASE5_STOCK';end if;
 if (select status from public.return_orders where id=rid4)<>'shipped' then raise exception 'FAIL_CASE5_STATUS';end if;
 perform set_config('request.jwt.claim.sub',fin_id::text,true);
 r:=public.gama_returns_action('supplier_credit',jsonb_build_object('id',rid4,
   'supplier_reference','NC-778','amount',25,'issued_on',current_date));
 if (select status from public.return_orders where id=rid4)<>'credited' then raise exception 'FAIL_SUPPLIER_CREDIT';end if;
 perform public.gama_returns_action('close',jsonb_build_object('id',rid4));
 if (select status from public.return_orders where id=rid4)<>'closed' then raise exception 'FAIL_SUPPLIER_CLOSE';end if;
 -- Un documento cerrado no se modifica en silencio.
 rejected:=false;
 begin perform public.gama_returns_action('supplier_credit',jsonb_build_object('id',rid4,'amount',10));
 exception when others then if sqlerrm='RETURN_CLOSED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CLOSED_WRITE';end if;

 -- ----------------------------------------------------- Caso 8 — permisos
 perform set_config('request.jwt.claim.sub',sales_id::text,true);
 r:=public.gama_returns_action('overview','{}');
 if not (r#>>'{rights,create}')::boolean or (r#>>'{rights,process}')::boolean
  or (r#>>'{rights,refund}')::boolean or (r#>>'{rights,delete}')::boolean
  then raise exception 'FAIL_RIGHTS_COMMERCIAL';end if;
 rejected:=false;
 begin perform public.gama_returns_action('receive',jsonb_build_object('id',rid3,'location_id',loc));
 exception when others then if sqlerrm='NOT_ALLOWED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_COMMERCIAL_PROCESS';end if;
 rejected:=false;
 begin perform public.gama_returns_action('refund',jsonb_build_object('id',rid3,'amount',1,'method','efectivo'));
 exception when others then if sqlerrm='NOT_ALLOWED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_COMMERCIAL_REFUND';end if;

 perform set_config('request.jwt.claim.sub',ware_id::text,true);
 r:=public.gama_returns_action('overview',jsonb_build_object('kind','customer','all_dates',true));
 if not (r#>>'{rights,process}')::boolean or (r#>>'{rights,refund}')::boolean
  then raise exception 'FAIL_RIGHTS_WAREHOUSE';end if;
 -- El filtro por tipo separa las dos pestañas.
 if not exists(select 1 from jsonb_array_elements(r->'rows') x where (x->>'id')::uuid=rid)
  or exists(select 1 from jsonb_array_elements(r->'rows') x where (x->>'id')::uuid=rid4)
  then raise exception 'FAIL_KIND_FILTER';end if;
 if (r#>>'{kpis,open}')::int<1 then raise exception 'FAIL_KPI_OPEN';end if;
 -- La pantalla necesita las ubicaciones para recibir, reponer y expedir.
 if jsonb_array_length(r->'locations')<1 then raise exception 'FAIL_LOCATIONS';end if;

 perform set_config('request.jwt.claim.sub',fin_id::text,true);
 r:=public.gama_returns_action('overview','{}');
 if not (r#>>'{rights,refund}')::boolean or (r#>>'{rights,process}')::boolean
  or (r#>>'{rights,delete}')::boolean then raise exception 'FAIL_RIGHTS_FINANCE';end if;

 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 r:=public.gama_returns_action('overview','{}');
 if not ((r#>>'{rights,process}')::boolean and (r#>>'{rights,refund}')::boolean
   and (r#>>'{rights,delete}')::boolean) then raise exception 'FAIL_RIGHTS_ADMIN';end if;
 -- Documentos ligados: el retorno apunta al pedido, la salida y la factura
 -- existentes, sin copiar ninguno.
 r:=public.gama_returns_action('detail',jsonb_build_object('id',rid3));
 if (r->>'amount')::numeric<>100 or (r->>'refunded')::numeric<>100
  or jsonb_array_length(r->'credits')<>1 or jsonb_array_length(r->'refunds')<>1
  or (r#>>'{documents,invoice,id}')::uuid<>inv or (r#>>'{documents,order,id}')::uuid<>oid
  or (r#>>'{documents,delivery,id}')::uuid<>sid
  then raise exception 'FAIL_DETAIL_DOCUMENTS';end if;
 -- El abono y el reembolso llegan a Contabilidad por la misma vía que los
 -- demás documentos, y repetir la sincronización no duplica el asiento.
 execute 'reset role';
 update public.accounting_periods set status='open'
  where period_start=date_trunc('month',current_date)::date;
 perform private.gama_accounting_sync(400);
 if (select count(*) from public.accounting_entries where source_type='return_credit'
      and source_id=credit_id)<>1 then raise exception 'FAIL_ACCOUNTING_CREDIT';end if;
 if (select count(*) from public.accounting_entries e
      join public.return_refunds f on f.id=e.source_id
      where e.source_type='return_refund' and f.return_id=rid3)<>1
  then raise exception 'FAIL_ACCOUNTING_REFUND';end if;
 if exists(select 1 from public.accounting_entries e
      where e.source_type in ('return_credit','supplier_credit','return_refund')
        and coalesce((select sum(l.debit) from public.accounting_entry_lines l where l.entry_id=e.id),0)
         <> coalesce((select sum(l.credit) from public.accounting_entry_lines l where l.entry_id=e.id),0))
  then raise exception 'FAIL_ACCOUNTING_UNBALANCED';end if;
 perform private.gama_accounting_sync(400);
 if (select count(*) from public.accounting_entries where source_type='return_credit'
      and source_id=credit_id)<>1 then raise exception 'FAIL_ACCOUNTING_DUPLICATED';end if;
 execute 'set local role authenticated';
 perform set_config('request.jwt.claim.sub',admin_id::text,true);

 -- Las cifras del §18 se calculan donde están los datos.
 r:=public.gama_returns_action('stats','{}');
 if (r->>'month_count')::int<1 or (r->>'month_value')::numeric<=0
  or jsonb_array_length(r->'reasons')<1 then raise exception 'FAIL_STATS';end if;

 perform set_config('request.jwt.claim.sub',client_id::text,true);
 rejected:=false;
 begin perform public.gama_returns_action('overview','{}');
 exception when others then if sqlerrm='ROLE_NOT_ALLOWED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CLIENT_READS_RETURNS';end if;

 -- ------------------------------------------- expediente y pista de auditoría
 -- El retorno entra en el expediente de su pedido, no abre uno nuevo.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 select dossier_number into dossier from public.gama_document_references
  where table_name='sales_orders' and document_id=oid;
 if dossier is null then raise exception 'FAIL_ORDER_DOSSIER';end if;
 if not exists(select 1 from public.gama_document_references
   where table_name='return_orders' and document_id=rid and dossier_number=dossier
     and document_reference like 'DEV%') then raise exception 'FAIL_RETURN_DOSSIER';end if;
 if not exists(select 1 from public.gama_audit where table_name='return_orders' and row_id=rid::text and action='INSERT')
  then raise exception 'FAIL_AUDIT_CREATE';end if;
 if not exists(select 1 from public.gama_audit where table_name='return_orders' and row_id=rid::text and action='UPDATE')
  then raise exception 'FAIL_AUDIT_UPDATE';end if;
 if not exists(select 1 from public.gama_audit where table_name='return_refunds' and action='INSERT')
  then raise exception 'FAIL_AUDIT_REFUND';end if;

 -- ------------------------------------------------ borrado y cancelación
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 r:=public.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',sid,
   'reason','other','notes','Para anular','lines',jsonb_build_array(
     jsonb_build_object('line_id',dlc,'quantity',1))));
 perform public.gama_returns_action('cancel',jsonb_build_object('id',(r->>'id')::uuid));
 if (select status from public.return_orders where id=(r->>'id')::uuid)<>'cancelled' then raise exception 'FAIL_CANCEL';end if;
 -- Lo cancelado libera de nuevo la cantidad devolvible.
 j:=public.gama_returns_action('source_lines',jsonb_build_object('kind','customer','source_id',sid));
 select value into row_json from jsonb_array_elements(j->'rows') where (value->>'line_id')::uuid=dlc;
 if (row_json->>'max_return')::numeric<>6 then raise exception 'FAIL_CANCEL_FREES_QUANTITY';end if;
 -- Ya recibido, no se borra: detrás hay movimientos de stock.
 rejected:=false;
 begin perform public.gama_returns_action('delete',jsonb_build_object('id',rid));
 exception when others then if sqlerrm='RETURN_ALREADY_STARTED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_DELETE_STARTED';end if;

 execute 'reset role';
end $$;
