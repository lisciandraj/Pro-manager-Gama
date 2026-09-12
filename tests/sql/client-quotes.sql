-- Execute inside BEGIN/ROLLBACK. No persistent business or Auth fixtures.
do $$
#variable_conflict use_column
<<quote_test>>
declare
 admin_id uuid; client_id uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid();
 cid uuid; other_cid uuid; pid uuid; pid2 uuid; loc uuid; qid uuid; oid uuid; did uuid; other_did uuid;
 result jsonb; payload jsonb; rev integer; key_id uuid:=gen_random_uuid(); denied boolean;
begin
 select id into admin_id from public.profiles where role='administrador' and active limit 1;
 select id into loc from public.warehouse_locations where active order by id limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(client_id,client_id||'@gama-test.invalid',now()),(other_id,other_id||'@gama-test.invalid',now());
 insert into public.profiles(id,role,active,email) values(client_id,'cliente',true,client_id||'@gama-test.invalid'),(other_id,'cliente',true,other_id||'@gama-test.invalid') on conflict(id) do update set role='cliente',active=true;
 insert into public.customers(name,email,address) values('QUOTE TEST rollback',client_id||'@gama-test.invalid','Quito') returning id into cid;
 insert into public.customers(name,email,address) values('OTHER TEST rollback',other_id||'@gama-test.invalid','Cuenca') returning id into other_cid;
 insert into public.products(name,barcode,reference,sale_price,stock) values('QUOTE PRODUCT '||gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,10,5) returning id into pid;
 insert into public.products(name,barcode,reference,sale_price,stock) values('QUOTE SUBSTITUTE '||gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,20,2) returning id into pid2;
 insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity) values(pid,loc,5,0),(pid2,loc,2,0);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 execute 'set local role authenticated';
 payload:=jsonb_build_object('request_key',key_id,'customer_id',cid,'issue_date',current_date,'valid_until',current_date+30,
  'details',jsonb_build_object('seller','GAMA','client','TEST customer','delivery_address','Quito','clientId','TEST','terms','Oferta especial'),
  'lines',jsonb_build_array(jsonb_build_object('product_id',pid,'description','Producto inicial','quantity',4,'list_price',10,'discount',10,'tax_rate',15)));
 result:=public.gama_quote_action('save',payload);qid:=(result->>'id')::uuid;rev:=(result->>'revision')::int;
 if (select total from public.invoices where id=qid)<>41.40 then raise exception 'FAIL_TOTAL'; end if;
 if (public.gama_quote_action('save',payload)->>'id')::uuid<>qid then raise exception 'FAIL_SAVE_IDEMPOTENCY'; end if;
 -- Replace unavailable product; retain promotional price and editable description.
 payload:=payload||jsonb_build_object('id',qid,'revision',rev,'lines',jsonb_build_array(jsonb_build_object('product_id',pid2,'description','Producto sustituto oferta','quantity',3,'list_price',20,'discount',25,'tax_rate',15)));
 result:=public.gama_quote_action('save',payload);rev:=(result->>'revision')::int;
 if exists(select 1 from public.invoice_lines where invoice_id=qid and product_id=pid) then raise exception 'FAIL_REPLACE'; end if;
 if (select total from public.invoices where id=qid)<>51.75 then raise exception 'FAIL_DISCOUNT'; end if;
 -- Managed rows cannot be changed through the old direct-write API.
 denied:=false;begin update public.invoices set total=1 where id=qid;exception when others then denied:=true;end;
 if not denied then raise exception 'FAIL_DIRECT_HEADER_WRITE'; end if;
 denied:=false;begin update public.invoice_lines set unit_price=1 where invoice_id=qid;exception when others then denied:=true;end;
 if not denied then raise exception 'FAIL_DIRECT_LINE_WRITE'; end if;
 -- Client cannot see a draft or accept it.
 perform set_config('request.jwt.claim.sub',client_id::text,true);
 if exists(select 1 from public.invoices where id=qid) then raise exception 'FAIL_DRAFT_VISIBLE'; end if;
 denied:=false;begin perform public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev));exception when others then denied:=true;end;
 if not denied then raise exception 'FAIL_ACCEPT_DRAFT'; end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 result:=public.gama_quote_action('send',jsonb_build_object('id',qid,'revision',rev));rev:=(result->>'revision')::int;
 denied:=false;begin perform public.gama_sales_action('create',jsonb_build_object('request_key',gen_random_uuid(),'source','quote','source_id',qid));exception when others then if sqlerrm='QUOTE_ACCEPT_FIRST' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_LEGACY_BYPASS'; end if;
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 if exists(select 1 from public.invoices where id=qid) or exists(select 1 from public.invoice_lines where invoice_id=qid) then raise exception 'FAIL_CROSS_CLIENT_READ'; end if;
 denied:=false;begin perform public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev));exception when others then denied:=true;end;
 if not denied then raise exception 'FAIL_CROSS_CLIENT_ACCEPT'; end if;
 perform set_config('request.jwt.claim.sub',client_id::text,true);
 if not exists(select 1 from public.invoices where id=qid) then raise exception 'FAIL_CLIENT_READ'; end if;
 denied:=false;begin perform public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev-1));exception when others then if sqlerrm='QUOTE_CHANGED' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_STALE_ACCEPT'; end if;
 result:=public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev));oid:=(result->>'order_id')::uuid;
 if oid is null then raise exception 'FAIL_ORDER_MISSING'; end if;
 if (public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev))->>'order_id')::uuid<>oid then raise exception 'FAIL_ACCEPT_IDEMPOTENCY'; end if;
 result:=public.gama_quote_reservations(qid);
 if (result->0->>'reserved')::numeric<>2 or (result->0->>'quantity')::numeric<>3 then raise exception 'FAIL_PARTIAL_RESERVATION'; end if;
 execute 'reset role';
 if (select quantity from public.stock_quants where product_id=pid2)<>2 or (select reserved_quantity from public.stock_quants where product_id=pid2)<>2 then raise exception 'FAIL_PHYSICAL_OR_DOUBLE_RESERVATION'; end if;
 if (select unit_price from public.sales_order_lines where order_id=oid)<>15 then raise exception 'FAIL_NEGOTIATED_ORDER_PRICE'; end if;
 -- Reopen invalidates an earlier client view, and expired quotes cannot send.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);execute 'set local role authenticated';
 payload:=payload-'id'-'revision';payload:=payload||jsonb_build_object('request_key',gen_random_uuid(),'issue_date',current_date-2,'valid_until',current_date-1);
 result:=public.gama_quote_action('save',payload);qid:=(result->>'id')::uuid;rev:=(result->>'revision')::int;
 denied:=false;begin perform public.gama_quote_action('send',jsonb_build_object('id',qid,'revision',rev));exception when others then if sqlerrm='QUOTE_EXPIRED' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_EXPIRED_SEND'; end if;
 payload:=payload||jsonb_build_object('id',qid,'revision',rev,'valid_until',current_date+30);
 result:=public.gama_quote_action('save',payload);rev:=(result->>'revision')::int;
 result:=public.gama_quote_action('send',jsonb_build_object('id',qid,'revision',rev));rev:=(result->>'revision')::int;
 perform public.gama_quote_action('reopen',jsonb_build_object('id',qid,'revision',rev));
 perform set_config('request.jwt.claim.sub',client_id::text,true);
 if exists(select 1 from public.invoices where id=qid) then raise exception 'FAIL_REOPEN_STILL_VISIBLE'; end if;
 denied:=false;begin perform public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev));exception when others then denied:=true;end;
 if not denied then raise exception 'FAIL_REOPEN_ACCEPTED'; end if;
 execute 'reset role';
 -- An external acceptance needs a traceable agreement reference.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);execute 'set local role authenticated';
 payload:=payload-'id'-'revision';payload:=payload||jsonb_build_object('request_key',gen_random_uuid());
 result:=public.gama_quote_action('save',payload);qid:=(result->>'id')::uuid;rev:=(result->>'revision')::int;
 result:=public.gama_quote_action('send',jsonb_build_object('id',qid,'revision',rev));rev:=(result->>'revision')::int;
 denied:=false;begin perform public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev,'channel','email'));exception when others then if sqlerrm='ACCEPTANCE_REFERENCE_REQUIRED' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_MISSING_REFERENCE'; end if;
 result:=public.gama_quote_action('accept',jsonb_build_object('id',qid,'revision',rev,'channel','email','reference','Email client du 12/09 — TEST'));
 if (select quote_acceptance_channel from public.invoices where id=qid)<>'email' then raise exception 'FAIL_EXTERNAL_CHANNEL'; end if;
 execute 'reset role';
 insert into public.tms_deliveries(customer,customer_id,address) values('TEST',cid,'Quito') returning id into did;
 insert into public.tms_deliveries(customer,customer_id,address) values('OTHER',other_cid,'Cuenca') returning id into other_did;
 insert into public.tms_proofs(delivery_id,photo,signature) values(did,'data:image/png;base64,AAAA','data:image/png;base64,BBBB'),(other_did,'private-other','private-other');
 perform set_config('request.jwt.claim.sub',client_id::text,true);execute 'set local role authenticated';
 result:=public.gama_client_deliveries(did,0);
 if jsonb_array_length(result)<>1 or result->0->'proof'->>'photo'<>'data:image/png;base64,AAAA' then raise exception 'FAIL_OWN_PROOF'; end if;
 if jsonb_array_length(public.gama_client_deliveries(other_did,0))<>0 then raise exception 'FAIL_CROSS_CLIENT_PROOF'; end if;
 result:=public.gama_client_deliveries(null,0);
 if exists(select 1 from jsonb_array_elements(result) a where a->'proof'<>'null'::jsonb) then raise exception 'FAIL_LIST_TRANSFERS_PROOFS'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;begin perform public.gama_client_deliveries(did,0);exception when others then denied:=true;end;
 if not denied then raise exception 'FAIL_ANONYMOUS'; end if;
 execute 'reset role';
end $$;
