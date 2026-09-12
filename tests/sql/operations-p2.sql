-- Fixtures always run inside the caller's BEGIN / ROLLBACK.
do $$
declare a uuid;c uuid;p uuid;o uuid;l uuid;q uuid;v uuid;w uuid;po uuid;ic uuid;loc uuid;ei uuid;d uuid;sd uuid;
 out jsonb;base jsonb;al jsonb;deny boolean;cl uuid:=gen_random_uuid();wh uuid:=gen_random_uuid();
begin
 select id into a from public.profiles where role='administrador' and active limit 1;
 select id into w from public.warehouses where active limit 1;
 insert into public.warehouse_locations(warehouse_id,code,name,type) values(w,'P2-'||gen_random_uuid(),'P2 QA','bin') returning id into loc;
 insert into public.customers(name,address) values('P2 test','Quito') returning id into c;
 insert into public.suppliers(name) values('P2 supplier') returning id into v;
 insert into public.products(name,reference,barcode,stock) values('P2-'||gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),0) returning id into p;
 insert into public.sales_orders(request_key,customer_id,customer_name,status,created_by,created_at) values(gen_random_uuid(),c,'P2 test','confirmed',a,'2050-01-10T12:00:00Z') returning id into o;
 insert into public.sales_order_lines(order_id,product_id,product_name,quantity,unit_price,tax_rate) values(o,p,'P2',10,10,15) returning id into l;
 insert into public.invoices(customer_id,user_id,quote_state,quote_sent_at,quote_valid_until,quote_revision,quote_details) values(c,a,'sent',now()-interval '3 days',current_date-1,1,'{"client":"P2 test"}') returning id into q;
 insert into public.purchase_orders(supplier_id,order_number,status,expected_date) values(v,'P2-'||gen_random_uuid(),'partial',now()-interval '2 days') returning id into po;
 insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,received_quantity,unit_cost) values(po,p,10,3,5);
 insert into public.inventory_counts(warehouse_id,reference,status,created_by) values(w,'P2 test','in_progress',a) returning id into ic;
 insert into public.inventory_count_lines(count_id,product_id,location_id,expected_quantity,counted_quantity) values(ic,p,loc,10,8);
 insert into public.tms_deliveries(customer,address,delivery_date,status,created_by) values('P2 test','Quito',current_date-2,'Excepción',a) returning id into d;
 insert into public.sales_deliveries(order_id,request_key,tms_delivery_id,created_by,dispatched_at) values(o,gen_random_uuid(),d,a,'2050-01-11T12:00:00Z') returning id into sd;
 insert into public.sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values(sd,l,loc,4);
 insert into public.external_invoices(request_key,order_id,number,issuer_ruc,software,issue_date,subtotal,tax,fiscal_status,created_by)
 values(gen_random_uuid(),o,'P2-'||gen_random_uuid(),'1790012345001','Test','2050-01-12',20,3,'unverified',a) returning id into ei;
 insert into public.external_invoice_lines(invoice_id,order_line_id,quantity) values(ei,l,2);
 insert into public.external_invoice_payments(request_key,invoice_id,amount,paid_at,method,status,created_by) values(gen_random_uuid(),ei,5,'2050-01-13','transfer','confirmed',a);
 perform set_config('request.jwt.claim.sub',a::text,true);execute 'set local role authenticated';
 out:=public.gama_operations_action('snapshot','{"from":"2050-01-01","to":"2050-01-31","state":"all"}');
 if out#>>'{metrics,orders}'<>'1' or out#>>'{metrics,dispatches}'<>'1' or (out#>>'{metrics,invoiced}')::numeric<>23 or (out#>>'{metrics,collected}')::numeric<>5 then raise exception 'FAIL_PERIOD_METRICS %',out->'metrics';end if;
 execute 'reset role';
 if (select unbilled from private.gama_order_progress where id=o)<>92 or (select shipped_unbilled from private.gama_order_progress where id=o)<>23 or (select missing from private.gama_order_progress where id=o)<>6 then raise exception 'FAIL_LINE_ACCOUNTING';end if;
 execute 'set local role authenticated';
 select x into al from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='shortage:'||o;
 if al is null then raise exception 'FAIL_SHORTAGE_ALERT';end if;
 if not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='quote:'||q)
 or not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='receipt:'||po)
 or not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='delivery:'||d and x->>'kind'='failed_delivery')
 or not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='count:'||ic)
 or not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='backorder:'||o) then raise exception 'FAIL_MISSING_ALERT_KIND';end if;

 perform public.gama_operations_action('handle',jsonb_build_object('key',al->>'alert_key','fingerprint',al->>'fingerprint','status','snoozed','note','Waiting for supplier'));
 out:=public.gama_operations_action('snapshot','{"state":"snoozed"}');
 if not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='shortage:'||o and x->>'handling'='snoozed') then raise exception 'FAIL_SNOOZE';end if;
 perform public.gama_operations_action('handle',jsonb_build_object('key',al->>'alert_key','fingerprint',al->>'fingerprint','status','in_progress','note','Working'));
 out:=public.gama_operations_action('snapshot','{"state":"mine"}');
 if not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='shortage:'||o) then raise exception 'FAIL_ASSIGN';end if;
 execute 'reset role';update public.sales_order_lines set quantity=11 where id=l;execute 'set local role authenticated';
 out:=public.gama_operations_action('snapshot','{"kind":"shortage","state":"all"}');
 if not exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'alert_key'='shortage:'||o and x->>'handling'='open') then raise exception 'FAIL_CHANGED_CAUSE_REOPENS';end if;
 deny:=false;begin perform public.gama_operations_action('handle',jsonb_build_object('key',al->>'alert_key','fingerprint',al->>'fingerprint','status','in_progress'));exception when others then if sqlerrm like '%ALERT_CHANGED%' then deny:=true;else raise;end if;end;if not deny then raise exception 'FAIL_STALE_ALERT';end if;
 execute 'reset role';update public.sales_orders set status='cancelled' where id=o;execute 'set local role authenticated';
 deny:=false;begin perform public.gama_operations_action('handle',jsonb_build_object('key',al->>'alert_key','fingerprint',al->>'fingerprint','status','open'));exception when others then if sqlerrm like '%ALERT_RESOLVED%' then deny:=true;else raise;end if;end;
 if not deny then raise exception 'FAIL_RESOLVED';end if;
 deny:=false;begin update private.gama_alert_handling set note='BYPASS';exception when insufficient_privilege then deny:=true;end;if not deny then raise exception 'FAIL_DIRECT_WRITE';end if;
 execute 'reset role';
 insert into auth.users(id,email) values(cl,cl||'@test.invalid'),(wh,wh||'@test.invalid');
 insert into public.profiles(id,role,active) values(cl,'cliente',true),(wh,'almacenero',true) on conflict(id) do update set role=excluded.role,active=true;
 perform set_config('request.jwt.claim.sub',wh::text,true);execute 'set local role authenticated';out:=public.gama_operations_action('snapshot');
 if out->>'finance'<>'false' or out#>'{metrics,invoiced}'<>'null'::jsonb or exists(select 1 from jsonb_array_elements(out->'alerts') x where x->>'kind' in ('quote','unbilled')) then raise exception 'FAIL_WAREHOUSE_FINANCE';end if;
 perform set_config('request.jwt.claim.sub',cl::text,true);
 deny:=false;begin perform public.gama_operations_action('snapshot');exception when others then if sqlerrm like '%ROLE_NOT_ALLOWED%' then deny:=true;else raise;end if;end;if not deny then raise exception 'FAIL_CLIENT';end if;
 perform set_config('request.jwt.claim.sub','',true);
 deny:=false;begin perform public.gama_operations_action('snapshot');exception when others then if sqlerrm like '%AUTH_REQUIRED%' then deny:=true;else raise;end if;end;if not deny then raise exception 'FAIL_ANONYMOUS';end if;
 execute 'reset role';
end $$;
