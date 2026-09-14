-- Run inside BEGIN / ROLLBACK. No fixtures persist.
do $$
declare admin_id uuid; other_id uuid:=gen_random_uuid(); cid uuid; pid uuid; rid uuid; rid2 uuid; qid uuid; p jsonb; res jsonb; blocked boolean; before_count bigint;
begin
 select id into admin_id from public.profiles where role='administrador' and active limit 1;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 insert into public.customers(name,address) values('REQUEST QA '||gen_random_uuid(),'Quito') returning id into cid;
 insert into public.products(name,barcode,reference,sale_price,stock) values('REQUEST QA '||gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,10,0) returning id into pid;
 insert into public.customer_requests(customer_id,created_by,status,notes,total) values(cid,admin_id,'pending','Original request comment',20) returning id into rid;
 insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total) values(rid,pid,2,10,15,20);
 insert into public.customer_requests(customer_id,created_by,status,total) values(cid,admin_id,'pending',20) returning id into rid2;
 p:=jsonb_build_object('customer_id',cid,'issue_date',current_date,'valid_until',current_date+30,'details',jsonb_build_object('seller','GAMA','client','QA','delivery_address','Quito','customer_comment','tampered'),'lines',jsonb_build_array(jsonb_build_object('product_id',pid,'description','Offer','quantity',2,'list_price',10,'discount',10,'tax_rate',15)));
 execute 'set local role authenticated';
 res:=public.gama_quote_from_request(rid,p);qid:=(res->>'id')::uuid;
 assert (select invoice_id=qid and status='invoiced' and total=20 from public.customer_requests where id=rid),'LINK_AND_ORIGINAL_TOTAL';
 assert (select quote_state='draft' and total=20.70 and quote_details->>'customer_comment'='Original request comment' from public.invoices where id=qid),'DRAFT_TOTAL_AND_SOURCE_COMMENT';
 assert (select count(*) from public.invoice_lines where invoice_id=qid)=1,'LINES_CREATED';
 assert (public.gama_quote_from_request(rid,p)->>'id')::uuid=qid,'RETRY_RETURNS_SAME_QUOTE';
 assert not exists(select 1 from public.sales_orders where source_quote_id=qid),'NO_PREMATURE_ORDER_OR_RESERVATION';
 select count(*) into before_count from public.invoices;
 blocked:=false;begin perform public.gama_quote_from_request(rid2,p||'{"lines":[]}'::jsonb);exception when others then blocked:=true;end;
 assert blocked,'INVALID_LINES_REJECTED';
 assert (select count(*) from public.invoices)=before_count and (select invoice_id is null from public.customer_requests where id=rid2),'FAILED_SAVE_IS_ATOMIC';
 execute 'reset role';
 update public.customer_requests set status='cancelled' where id=rid2;
 blocked:=false;begin perform public.gama_quote_from_request(rid2,p);exception when others then blocked:=sqlerrm like '%REQUEST_CLOSED%';end;assert blocked,'CANCELLED_REJECTED';
 insert into auth.users(id,email,email_confirmed_at) values(other_id,other_id||'@request-test.invalid',now());
 insert into public.profiles(id,role,active,email) values(other_id,'cliente',true,other_id||'@request-test.invalid') on conflict(id) do update set role='cliente',active=true;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 execute 'set local role authenticated';
 blocked:=false;begin perform public.gama_quote_from_request(rid,p);exception when others then blocked:=sqlerrm like '%ROLE_NOT_ALLOWED%';end;assert blocked,'CLIENT_DENIED_EVEN_ON_EXISTING_LINK';
 execute 'reset role';
 update public.profiles set role='almacenero' where id=other_id;
 blocked:=false;begin perform public.gama_quote_from_request(rid,p);exception when others then blocked:=sqlerrm like '%ROLE_NOT_ALLOWED%';end;assert blocked,'WAREHOUSE_DENIED';
 perform set_config('request.jwt.claim.sub','',true);
 blocked:=false;begin perform private.gama_quote_from_request(rid,p);exception when others then blocked:=sqlerrm like '%AUTH_REQUIRED%';end;assert blocked,'ANONYMOUS_DENIED';
end $$;
