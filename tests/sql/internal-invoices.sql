-- All fixtures inside caller BEGIN / ROLLBACK.
do $$
declare a uuid;c uuid;p uuid;q uuid;o uuid;l uuid;i jsonb;again jsonb;b jsonb;after_metrics jsonb;n numeric;blocked boolean;wh uuid:=gen_random_uuid();loc uuid;
begin
 select id into a from public.profiles where role='administrador' and active limit 1;
 insert into public.customers(name,address) values('INTERNAL invoice QA','Quito') returning id into c;
 insert into public.products(name,reference,barcode,stock) values('INTERNAL-'||gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),0) returning id into p;
 insert into public.invoices(customer_id,user_id,quote_state,quote_revision,subtotal,tax,quote_details) values(c,a,'accepted',2,30,4.5,'{"client":"Internal client","clientId":"0991","seller":"GAMA","payment":"Transferencia"}') returning id into q;
 insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total) values(q,p,3,10,15,30);
 insert into public.sales_orders(request_key,customer_id,customer_name,customer_identification,source_quote_id,status,created_by) values(gen_random_uuid(),c,'Internal client','0991',q,'confirmed',a) returning id into o;
 insert into public.sales_order_lines(order_id,product_id,product_name,quantity,unit_price,tax_rate) values(o,p,'Product snapshot',3,10,15) returning id into l;
 perform set_config('request.jwt.claim.sub',a::text,true);execute 'set local role authenticated';
 b:=public.gama_operations_action('snapshot','{"from":"2051-01-01","to":"2051-01-31"}');
 i:=public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q,'issue_date','2051-01-10','due_date','2051-01-20'));
 again:=public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q));
 if i->>'id'<>again->>'id' or (i->>'total')::numeric<>34.5 or i->>'document_kind'<>'internal' then raise exception 'FAIL_CREATION_RETRY';end if;
 after_metrics:=public.gama_operations_action('snapshot','{"from":"2051-01-01","to":"2051-01-31"}');
 if (after_metrics#>>'{metrics,invoiced}')::numeric-(b#>>'{metrics,invoiced}')::numeric<>34.5 then raise exception 'FAIL_KPI';end if;
 blocked:=false;begin perform public.gama_internal_invoice_action('link_external',jsonb_build_object('invoice_id',i->>'id','number','EXT-QA','issuer_ruc','1790012345001','customer_identification','0991','software','Other','issue_date','2051-01-11','subtotal',31,'tax',4.5));exception when others then if sqlerrm='AMOUNT_MISMATCH' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'FAIL_MISMATCH';end if;
 perform public.gama_commercial_action('payment',jsonb_build_object('invoice_id',i->>'id','request_key',gen_random_uuid(),'amount',10,'paid_at','2051-01-12','method','transfer'));
 again:=public.gama_internal_invoice_action('link_external',jsonb_build_object('invoice_id',i->>'id','number','EXT-'||gen_random_uuid(),'issuer_ruc','1790012345001','customer_identification','0991','software','Other','issue_date','2051-01-11','subtotal',30,'tax',4.5,'status','authorized'));
 if again->>'id'<>i->>'id' or again->>'number'<>i->>'number' or again->>'issue_date'<>i->>'issue_date' then raise exception 'FAIL_IDENTITY_PRESERVED';end if;
 after_metrics:=public.gama_operations_action('snapshot','{"from":"2051-01-01","to":"2051-01-31"}');
 if (after_metrics#>>'{metrics,invoiced}')::numeric-(b#>>'{metrics,invoiced}')::numeric<>34.5 or (after_metrics#>>'{metrics,collected}')::numeric-(b#>>'{metrics,collected}')::numeric<>10 then raise exception 'FAIL_DOUBLE_COUNT';end if;
 if not exists(select 1 from jsonb_array_elements(public.gama_internal_invoice_action('report')) x where x->>'id'=i->>'id' and x#>>'{items,0,name}'='Product snapshot') then raise exception 'FAIL_REPORT';end if;
 blocked:=false;begin perform public.gama_sales_action('invoice_status',jsonb_build_object('order_id',o,'invoice_id',i->>'id','fiscal_status','cancelled','reason','QA cancel'));exception when others then if sqlerrm='CANCEL_PAYMENTS_FIRST' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'FAIL_CANCEL_PAID';end if;
 execute 'reset role';
 if (select count(*) from public.external_invoice_lines where invoice_id=(i->>'id')::uuid)<>1 then raise exception 'FAIL_DUPLICATE_LINES';end if;
 if (select unbilled from private.gama_order_progress where id=o)<>0 then raise exception 'FAIL_UNBILLED';end if;
 if exists(select 1 from public.sales_deliveries where order_id=o) then raise exception 'FAIL_STOCK_SIDE_EFFECT';end if;
 update public.invoices set quote_state='sent' where id=q;
 blocked:=false;begin perform public.gama_internal_invoice_action('create',jsonb_build_object('quote_id',q));exception when others then if sqlerrm='QUOTE_NOT_ACCEPTED' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'FAIL_UNVALIDATED';end if;
 insert into auth.users(id,email) values(wh,wh||'@test.invalid');insert into public.profiles(id,role,active) values(wh,'almacenero',true) on conflict(id) do update set role='almacenero',active=true;
 perform set_config('request.jwt.claim.sub',wh::text,true);execute 'set local role authenticated';
 blocked:=false;begin perform public.gama_internal_invoice_action('report');exception when others then if sqlerrm='ROLE_NOT_ALLOWED' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'FAIL_ROLE';end if;
 execute 'reset role';
end $$;
