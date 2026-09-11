-- Run inside BEGIN ... ROLLBACK. Fixtures and all mutations must be rolled back.
-- Requires the migration and at least one active admin profile.
do $$
declare
 admin_id uuid; other_id uuid; client_id uuid; v_product_id uuid; loc_id uuid;
 o jsonb; o2 jsonb; inv jsonb; line_id uuid; ship_key uuid:=gen_random_uuid();
 create_key uuid:=gen_random_uuid(); invoice_key uuid:=gen_random_uuid(); before_count int;
 quote_id uuid; payload jsonb; denied boolean;
begin
 select id into admin_id from public.profiles where role='administrador' and active limit 1;
 if admin_id is null then raise exception 'TEST_ADMIN_REQUIRED'; end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
 insert into public.customers(name,identification,address) values('GAMA SQL TEST — rolled back','TEST-'||gen_random_uuid(),'Test address') returning id into client_id;
 insert into public.products(name,barcode,reference,sale_price,tax_rate) values('GAMA SQL TEST — rolled back',gen_random_uuid()::text,gen_random_uuid()::text,10,15) returning id into v_product_id;
 select id into loc_id from public.warehouse_locations where active order by id limit 1;
 insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity) values(v_product_id,loc_id,100,0);
 perform private.gama_sync_product_stock(v_product_id);
 payload:=jsonb_build_object('request_key',create_key,'customer_id',client_id,'delivery_address','Test address','lines',jsonb_build_array(jsonb_build_object('product_id',v_product_id,'quantity',100,'unit_price',10,'tax_rate',15)));
 execute 'set local role authenticated';
 o:=public.gama_sales_action('create',payload);
 o2:=public.gama_sales_action('create',payload);
 if o->>'id'<>o2->>'id' then raise exception 'FAIL_CREATE_IDEMPOTENCE'; end if;
 select id into line_id from public.sales_order_lines where order_id=(o->>'id')::uuid;
 perform public.gama_sales_action('confirm',jsonb_build_object('order_id',o->>'id'));
 perform public.gama_sales_action('reserve',jsonb_build_object('order_id',o->>'id'));
 if (select sum(sq.reserved_quantity) from public.stock_quants sq where sq.product_id=v_product_id)<>100 then raise exception 'FAIL_CONFIRM_RESERVATION'; end if;
 -- API clients cannot mutate checked records directly.
 denied:=false;begin update public.sales_order_lines set quantity=999 where id=line_id;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL_DIRECT_WRITE_ALLOWED'; end if;
 payload:=jsonb_build_object('order_id',o->>'id','request_key',ship_key,'lines',jsonb_build_array(jsonb_build_object('line_id',line_id,'location_id',loc_id,'quantity',60)));
 o2:=public.gama_sales_action('ship',payload);
 perform public.gama_sales_action('ship',payload);
 if (select count(*) from public.sales_deliveries where order_id=(o->>'id')::uuid)<>1 then raise exception 'FAIL_SHIP_IDEMPOTENCE'; end if;
 if (select stock from public.products where id=v_product_id)<>40 then raise exception 'FAIL_STOCK_AFTER_SHIPMENT'; end if;
 if (select sum(sq.reserved_quantity) from public.stock_quants sq where sq.product_id=v_product_id)<>40 then raise exception 'FAIL_RESERVATION_AFTER_SHIPMENT'; end if;
 -- A second line failure must roll back first-line changes, dispatch and TMS.
 denied:=false;begin
  perform public.gama_sales_action('ship',jsonb_build_object('order_id',o->>'id','request_key',gen_random_uuid(),'lines',jsonb_build_array(jsonb_build_object('line_id',line_id,'location_id',loc_id,'quantity',10),jsonb_build_object('line_id',line_id,'location_id',loc_id,'quantity',50))));
 exception when others then if SQLERRM in ('EXCEEDS_ORDERED','INSUFFICIENT_RESERVED') then denied:=true;else raise;end if;end;
 if not denied or (select stock from public.products where id=v_product_id)<>40 then raise exception 'FAIL_ATOMIC_SHIPMENT'; end if;
 payload:=jsonb_build_object('order_id',o->>'id','request_key',invoice_key,'number','TEST-'||gen_random_uuid(),'issuer_ruc','1234567890001','customer_identification',(select identification from public.customers where id=client_id),'issue_date',current_date,'subtotal',600,'tax',90,'fiscal_status','authorized','lines',jsonb_build_array(jsonb_build_object('line_id',line_id,'quantity',60)));
 inv:=public.gama_sales_action('invoice',payload);
 perform public.gama_sales_action('invoice',payload);
 if (select count(*) from public.external_invoices where order_id=(o->>'id')::uuid)<>1 then raise exception 'FAIL_INVOICE_IDEMPOTENCE'; end if;
 if (select stock from public.products where id=v_product_id)<>40 then raise exception 'FAIL_INVOICE_MOVED_STOCK'; end if;
 denied:=false;begin perform public.gama_sales_action('invoice',payload||jsonb_build_object('request_key',gen_random_uuid(),'number','OTHER','subtotal',500,'tax',75,'lines',jsonb_build_array(jsonb_build_object('line_id',line_id,'quantity',50))));exception when others then if SQLERRM='EXCEEDS_UNBILLED' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_OVERBILLING'; end if;
 denied:=false;begin perform public.gama_sales_action('invoice',payload||jsonb_build_object('request_key',gen_random_uuid(),'number','OTHER','subtotal',100,'tax',0,'lines',jsonb_build_array(jsonb_build_object('line_id',line_id,'quantity',10))));exception when others then if SQLERRM='AMOUNT_MISMATCH' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_AMOUNT_MISMATCH'; end if;
 denied:=false;begin perform public.gama_sales_action('invoice',payload||jsonb_build_object('request_key',gen_random_uuid(),'customer_identification','WRONG'));exception when others then if SQLERRM='CUSTOMER_MISMATCH' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_CUSTOMER_MISMATCH'; end if;
 -- Files are saved and recoverable separately from register rows.
 perform public.gama_sales_action('attach',jsonb_build_object('order_id',o->>'id','invoice_id',inv->>'id','files',jsonb_build_array(jsonb_build_object('filename','test.xml','mime_type','application/xml','content_base64',encode(convert_to('<test/>','utf8'),'base64')))));
 if not exists(select 1 from public.external_invoice_files where invoice_id=(inv->>'id')::uuid) then raise exception 'FAIL_ATTACHMENT'; end if;
 perform public.gama_sales_action('invoice_status',jsonb_build_object('order_id',o->>'id','invoice_id',inv->>'id','fiscal_status','cancelled','reason','External cancellation confirmed — test'));
 if (select stock from public.products where id=v_product_id)<>40 then raise exception 'FAIL_CANCELLATION_MOVED_STOCK'; end if;
 -- Confirming a backorder reserves only what is available; cancellation releases it.
 o2:=public.gama_sales_action('create',jsonb_build_object('request_key',gen_random_uuid(),'customer_id',client_id,'lines',jsonb_build_array(jsonb_build_object('product_id',v_product_id,'quantity',50,'unit_price',10,'tax_rate',15))));
 perform public.gama_sales_action('confirm',jsonb_build_object('order_id',o2->>'id'));
 perform public.gama_sales_action('cancel',jsonb_build_object('order_id',o2->>'id'));
 if (select sum(sq.reserved_quantity) from public.stock_quants sq where sq.product_id=v_product_id)<>40 then raise exception 'FAIL_BACKORDER_RESERVE'; end if;
 execute 'reset role';
 -- Quote conversion uses server-owned prices and an immutable customer snapshot.
 insert into public.invoices(customer_id,status,invoice_number) values(client_id,'draft','TEST-QUOTE') returning id into quote_id;
 insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate) values(quote_id,v_product_id,2,7,15);
 execute 'set local role authenticated';
 payload:=jsonb_build_object('source','quote','source_id',quote_id,'request_key',gen_random_uuid());
 o2:=public.gama_sales_action('create',payload);
 payload:=payload||jsonb_build_object('request_key',gen_random_uuid());
 if public.gama_sales_action('create',payload)->>'id'<>o2->>'id' then raise exception 'FAIL_SOURCE_DEDUPLICATION'; end if;
 if (select unit_price from public.sales_order_lines where order_id=(o2->>'id')::uuid)<>7 then raise exception 'FAIL_QUOTE_PRICE'; end if;
 execute 'reset role';
 select id into other_id from public.profiles where role='comercial' and active limit 1;
 if other_id is not null then
  perform set_config('request.jwt.claim.sub',other_id::text,true);
  execute 'set local role authenticated';
  denied:=false;begin perform public.gama_sales_action('ship',jsonb_build_object('order_id',o->>'id'));exception when others then if SQLERRM='ROLE_NOT_ALLOWED' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'FAIL_COMMERCIAL_DISPATCH'; end if;
  execute 'reset role';
 end if;
 select id into other_id from public.profiles where role='almacenero' and active limit 1;
 if other_id is not null then
  perform set_config('request.jwt.claim.sub',other_id::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.external_invoices where order_id=(o->>'id')::uuid) then raise exception 'FAIL_WAREHOUSE_FISCAL_READ'; end if;
  denied:=false;begin perform public.gama_sales_action('invoice',jsonb_build_object('order_id',o->>'id'));exception when others then if SQLERRM='ROLE_NOT_ALLOWED' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'FAIL_WAREHOUSE_INVOICE'; end if;
  execute 'reset role';
 end if;
 select id into other_id from public.profiles where role='cliente' and active limit 1;
 if other_id is not null then
  perform set_config('request.jwt.claim.sub',other_id::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.sales_orders) or exists(select 1 from public.external_invoice_files) then raise exception 'FAIL_CLIENT_READ'; end if;
  denied:=false;begin perform public.gama_sales_action('confirm',jsonb_build_object('order_id',o->>'id'));exception when others then if SQLERRM='ROLE_NOT_ALLOWED' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'FAIL_CLIENT_WRITE'; end if;
  execute 'reset role';
 end if;
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);
 denied:=false;begin perform public.gama_sales_action('create',payload);exception when others then if SQLERRM='AUTH_REQUIRED' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_NO_AUTH'; end if;
 if has_function_privilege('anon','public.gama_sales_action(text,jsonb)','EXECUTE') then raise exception 'FAIL_ANON_GRANT'; end if;
end $$;
select 'sales transaction, stock, documents, attachments and permissions checks passed' as result;
