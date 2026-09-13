-- Rollback-only fixtures: no real customer records are changed.
do $$
declare a uuid;c uuid;p uuid;q uuid;o uuid;l uuid;td uuid;sd uuid;loc uuid;i jsonb;again jsonb;blocked boolean;
begin
 select id into a from public.profiles where role='administrador' and active limit 1;
 select id into loc from public.warehouse_locations limit 1;
 insert into public.customers(name,address) values('Invoice delivery QA','Quito') returning id into c;
 insert into public.products(name,reference,barcode,stock) values('DELIVERY-INVOICE-'||gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),0) returning id into p;
 insert into public.invoices(customer_id,user_id,quote_state,quote_revision,subtotal,tax,quote_details) values(c,a,'accepted',1,30,4.5,'{}') returning id into q;
 insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total) values(q,p,3,10,15,30);
 insert into public.sales_orders(request_key,customer_id,customer_name,source_quote_id,status,created_by) values(gen_random_uuid(),c,'QA',q,'confirmed',a) returning id into o;
 insert into public.sales_order_lines(order_id,product_id,product_name,quantity,unit_price,tax_rate) values(o,p,'QA',3,10,15) returning id into l;
 perform set_config('request.jwt.claim.sub',a::text,true);
 blocked:=false;begin perform public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q));exception when others then if sqlerrm='DELIVERY_VALIDATION_REQUIRED' then blocked:=true;else raise;end if;end;
 if not blocked then raise exception 'FAIL_UNDELIVERED';end if;
 -- Build a historical delivery fixture before linking it to the order.
 insert into public.tms_deliveries(customer,address,status) values('QA','Quito','Entregada') returning id into td;
 insert into public.sales_deliveries(order_id,request_key,tms_delivery_id,created_by) values(o,gen_random_uuid(),td,a) returning id into sd;
 insert into public.sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values(sd,l,loc,3);
 if private.gama_order_delivery_validated(o) then raise exception 'FAIL_UNSIGNED';end if;
 -- Fixture proof bypasses loading only by creating the proof before its sales linkage.
 delete from public.sales_delivery_lines where delivery_id=sd;
 delete from public.sales_deliveries where id=sd;
 insert into public.tms_proofs(delivery_id,signature) values(td,'data:image/png;base64,QA');
 insert into public.sales_deliveries(id,order_id,request_key,tms_delivery_id,created_by) values(sd,o,gen_random_uuid(),td,a);
 insert into public.sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values(sd,l,loc,2);
 if private.gama_order_delivery_validated(o) then raise exception 'FAIL_PARTIAL';end if;
 blocked:=false;begin perform public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q));exception when others then if sqlerrm='DELIVERY_VALIDATION_REQUIRED' then blocked:=true;else raise;end if;end;
 if not blocked then raise exception 'FAIL_PARTIAL_CREATE';end if;
 update public.sales_delivery_lines set quantity=3 where delivery_id=sd;
 if not private.gama_order_delivery_validated(o) then raise exception 'FAIL_COMPLETE';end if;
 execute 'set local role authenticated';
 i:=public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q));
 again:=public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q));
 if i->>'id'<>again->>'id' or (i->>'total')::numeric<>34.5 then raise exception 'FAIL_INVOICE';end if;
 again:=public.gama_internal_invoice_action('eligibility',jsonb_build_object('quote_ids',jsonb_build_array(q)));
 if not (again->0->>'ready')::boolean or again->0->>'invoice_id'<>i->>'id' then raise exception 'FAIL_ELIGIBILITY';end if;
 execute 'reset role';
 if (select stock from public.products where id=p)<>0 then raise exception 'FAIL_STOCK_CHANGED';end if;
end $$;
