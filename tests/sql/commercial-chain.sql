-- Run after 20260912125649_commercial_transaction_chain.sql.
-- The caller must wrap this file in BEGIN/ROLLBACK; no fixture is persistent.
do $$
#variable_conflict use_column
<<commercial_chain>>
declare
  admin_id uuid;
  customer_id uuid;
  product_id uuid;
  supplier_id uuid;
  location_id uuid;
  order_id uuid;
  order_line_id uuid;
  po_id uuid;
  po_line_id uuid;
  delivery_id uuid;
  invoice_id uuid;
  quote_id uuid;
  opportunity_id uuid;
  crm_order_id uuid;
  stage_id uuid;
  result jsonb;
  denied boolean;
  payment_key uuid := gen_random_uuid();
  payment_id uuid;
  second_order_id uuid;
  second_line_id uuid;
begin
  select id into admin_id from public.profiles where role='administrador' and active limit 1;
  if admin_id is null then raise exception 'TEST_ADMIN_REQUIRED'; end if;
  select id into location_id from public.warehouse_locations where active order by id limit 1;
  select id into stage_id from public.crm_pipeline_stages where active order by sort_order limit 1;
  if location_id is null or stage_id is null then raise exception 'TEST_REFERENCE_DATA_REQUIRED'; end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);

  insert into public.customers(name,identification,address)
  values('GAMA CHAIN TEST — rolled back','CHAIN-'||gen_random_uuid(),'Quito') returning id into customer_id;
  insert into public.products(name,barcode,reference,sale_price,tax_rate,min_stock,max_stock,stock)
  values('GAMA CHAIN PRODUCT — rolled back',gen_random_uuid()::text,gen_random_uuid()::text,10,0,10,0,0)
  returning id into product_id;
  insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity)
  values(product_id,location_id,0,0);

  execute 'set local role authenticated';
  result:=public.gama_sales_action('create',jsonb_build_object(
    'request_key',gen_random_uuid(),'customer_id',customer_id,'delivery_address','Quito',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product_id,'quantity',10,'unit_price',10,'tax_rate',0))));
  order_id:=(result->>'id')::uuid;
  select id into order_line_id from public.sales_order_lines where order_id=commercial_chain.order_id;
  perform public.gama_sales_action('confirm',jsonb_build_object('order_id',order_id));
  if (select reserved_quantity from public.stock_quants where product_id=commercial_chain.product_id)<>0 then
    raise exception 'FAIL_EMPTY_STOCK_RESERVED';
  end if;
  execute 'reset role';

  -- With no stock and a demand of ten, buy ten for demand plus ten to restore
  -- the configured safety minimum.
  if (select suggested_purchase from public.replenishment_needs where product_id=commercial_chain.product_id)<>20 then
    raise exception 'FAIL_REPLENISHMENT_DEMAND';
  end if;

  insert into public.suppliers(name,tax_id,active)
  values('GAMA CHAIN SUPPLIER — rolled back','CHAIN-'||gen_random_uuid(),true) returning id into supplier_id;
  insert into public.purchase_orders(supplier_id,order_number,order_date,status,subtotal,tax,total,created_by)
  values(supplier_id,'CHAIN-'||gen_random_uuid(),now(),'sent',200,0,200,admin_id) returning id into po_id;
  insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,received_quantity,unit_cost,tax_rate,line_total)
  values(po_id,product_id,20,0,10,0,200) returning id into po_line_id;
  if (select suggested_purchase from public.replenishment_needs where product_id=commercial_chain.product_id)<>0 then
    raise exception 'FAIL_INCOMING_NOT_COUNTED';
  end if;

  execute 'set local role authenticated';
  result:=public.gama_sales_action('create',jsonb_build_object(
    'request_key',gen_random_uuid(),'customer_id',customer_id,'delivery_address','Quito',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product_id,'quantity',3,'unit_price',10,'tax_rate',0))));
  second_order_id:=(result->>'id')::uuid;
  perform public.gama_sales_action('confirm',jsonb_build_object('order_id',second_order_id));
  select sl.id into second_line_id from public.sales_order_lines sl where sl.order_id=second_order_id;
  -- Give the first order an earlier timestamp: now() is transaction-stable.
  execute 'reset role';
  update public.sales_orders so set created_at=now()-interval '1 minute' where so.id=order_id;
  execute 'set local role authenticated';
  perform public.gama_receive_purchase(po_id,jsonb_build_array(jsonb_build_object(
    'line_id',po_line_id,'quantity',10,'location_id',location_id)),'Commercial chain test');
  if (select reserved_quantity from public.stock_quants where product_id=commercial_chain.product_id)<>10 then
    raise exception 'FAIL_RECEIPT_AUTO_ALLOCATION';
  end if;
  if (select coalesce(sum(sr.quantity),0)
        from public.stock_reservations sr
        join public.sales_reservation_links sl on sl.reservation_id=sr.id
       where sl.line_id=order_line_id and sr.status='active')<>10 then
    raise exception 'FAIL_SALES_LINK_ALLOCATION';
  end if;
  if exists(select 1 from public.sales_reservation_links sl where sl.line_id=second_line_id) then
    raise exception 'FAIL_FIFO_PRIORITY';
  end if;
  perform public.gama_receive_purchase(po_id,jsonb_build_array(jsonb_build_object(
    'line_id',po_line_id,'quantity',3,'location_id',location_id)),'Second partial receipt');
  if (select sum(sr.quantity) from public.stock_reservations sr
      join public.sales_reservation_links sl on sl.reservation_id=sr.id
      where sl.line_id=second_line_id and sr.status='active')<>3 then
    raise exception 'FAIL_SECOND_FIFO_ALLOCATION';
  end if;
  perform public.gama_sales_action('cancel',jsonb_build_object('order_id',second_order_id,'reason','SQL cancellation test'));
  if (select reserved_quantity from public.stock_quants where product_id=commercial_chain.product_id)<>10 then
    raise exception 'FAIL_CANCEL_RELEASE';
  end if;
  -- Independent warehouse reservations must not disappear from purchasing.
  perform public.gama_stock_reserve(product_id,location_id,2,'manual',null);
  if (select suggested_purchase from public.replenishment_needs where product_id=commercial_chain.product_id)<>2 then
    raise exception 'FAIL_NON_SALES_RESERVATION_DEMAND';
  end if;

  result:=public.gama_sales_action('ship',jsonb_build_object(
    'order_id',order_id,'request_key',gen_random_uuid(),'delivery_date',current_date,
    'lines',jsonb_build_array(jsonb_build_object('line_id',order_line_id,'location_id',location_id,'quantity',6))));
  select id into delivery_id from public.sales_deliveries where order_id=commercial_chain.order_id order by dispatched_at desc limit 1;
  result:=public.gama_sales_action('invoice',jsonb_build_object(
    'order_id',order_id,'request_key',gen_random_uuid(),'number','CHAIN-'||gen_random_uuid(),
    'issuer_ruc','1234567890001','customer_identification',(select identification from public.customers where id=customer_id),
    'issue_date',current_date,'due_date',current_date+30,'subtotal',60,'tax',0,'fiscal_status','authorized',
    'delivery_ids',jsonb_build_array(delivery_id),
    'lines',jsonb_build_array(jsonb_build_object('line_id',order_line_id,'quantity',6))));
  invoice_id:=(result->>'id')::uuid;
  if not exists(select 1 from public.external_invoice_deliveries where invoice_id=commercial_chain.invoice_id and delivery_id=commercial_chain.delivery_id) then
    raise exception 'FAIL_ATOMIC_INVOICE_DELIVERY_LINK';
  end if;
  perform public.gama_commercial_action('link_invoice_delivery',jsonb_build_object(
    'invoice_id',invoice_id,'delivery_ids',jsonb_build_array(delivery_id)));
  if not exists(select 1 from public.external_invoice_deliveries where invoice_id=commercial_chain.invoice_id and delivery_id=commercial_chain.delivery_id) then
    raise exception 'FAIL_INVOICE_DELIVERY_LINK';
  end if;
  result:=public.gama_commercial_action('payment',jsonb_build_object(
    'invoice_id',invoice_id,'request_key',payment_key,'amount',20,'paid_at',current_date,
    'method','transfer','reference','CHAIN-PART-1'));
  payment_id:=(result->>'id')::uuid;
  perform public.gama_commercial_action('payment',jsonb_build_object(
    'invoice_id',invoice_id,'request_key',payment_key,'amount',20,'method','transfer'));
  if (select sum(amount) from public.external_invoice_payments where invoice_id=commercial_chain.invoice_id and status='confirmed')<>20 then
    raise exception 'FAIL_PARTIAL_PAYMENT';
  end if;
  perform public.gama_commercial_action('payment',jsonb_build_object(
    'invoice_id',invoice_id,'request_key',gen_random_uuid(),'amount',40,'paid_at',current_date,
    'method','cash'));
  if (select sum(amount) from public.external_invoice_payments where invoice_id=commercial_chain.invoice_id and status='confirmed')<>60 then
    raise exception 'FAIL_PAYMENT_BALANCE';
  end if;
  denied:=false;
  begin
    perform public.gama_commercial_action('payment',jsonb_build_object(
      'invoice_id',invoice_id,'request_key',gen_random_uuid(),'amount',1,'method','cash'));
  exception when others then
    if sqlerrm='PAYMENT_EXCEEDS_BALANCE' then denied:=true; else raise; end if;
  end;
  if not denied then raise exception 'FAIL_OVERPAYMENT_ALLOWED'; end if;
  perform public.gama_commercial_action('cancel_payment',jsonb_build_object(
    'invoice_id',invoice_id,'payment_id',payment_id,'reason','Correction test'));
  if (select sum(amount) from public.external_invoice_payments where invoice_id=commercial_chain.invoice_id and status='confirmed')<>40 then
    raise exception 'FAIL_PAYMENT_CANCELLATION_BALANCE';
  end if;
  denied:=false;
  begin
    update public.external_invoice_payments set amount=1 where id=payment_id;
  exception when insufficient_privilege then denied:=true;
  end;
  if not denied then raise exception 'FAIL_PAYMENT_DIRECT_WRITE'; end if;
  execute 'reset role';

  -- CRM -> quote -> order keeps both foreign keys.
  insert into public.invoices(customer_id,status,invoice_number,subtotal,tax,total)
  values(customer_id,'draft','CHAIN-QUOTE-'||gen_random_uuid(),10,0,10) returning id into quote_id;
  insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total)
  values(quote_id,product_id,1,10,0,10);
  insert into public.crm_opportunities(title,customer_id,stage_id,amount,probability,priority,quote_invoice_id,created_by)
  values('GAMA CHAIN OPPORTUNITY',customer_id,stage_id,10,50,'media',quote_id,admin_id)
  returning id into opportunity_id;
  execute 'set local role authenticated';
  result:=public.gama_sales_action('create',jsonb_build_object(
    'source','quote','source_id',quote_id,'request_key',gen_random_uuid()));
  crm_order_id:=(result->>'id')::uuid;
  if (select source_opportunity_id from public.sales_orders where id=crm_order_id)<>opportunity_id then
    raise exception 'FAIL_CRM_QUOTE_ORDER_LINK';
  end if;
  execute 'reset role';

  if has_function_privilege('anon','public.gama_commercial_action(text,jsonb)','EXECUTE') then
    raise exception 'FAIL_ANON_COMMERCIAL_GRANT';
  end if;
end $$;

select 'all eight critical commercial-chain checks passed' as result;
