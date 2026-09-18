-- Run with the migration inside BEGIN/ROLLBACK. All identities and goods are fixtures.
do $$
declare
 a uuid;c uuid;prod uuid;subprod uuid;emptyprod uuid;loc uuid;wid uuid;oid uuid;lid uuid;prep uuid;pickid uuid;pkg uuid;shipid uuid;tid uuid;opt uuid;oid2 uuid;lid2 uuid;
 client_id uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();keyid uuid;data jsonb;res jsonb;denied boolean;bc text;sid uuid;
begin
 select id into a from public.profiles where role='administrador' and active limit 1;
 select id into wid from public.warehouses where active limit 1;
 insert into public.warehouse_locations(warehouse_id,code,name,type) values(wid,'P1-'||gen_random_uuid(),'P1 test','bin') returning id into loc;
 insert into auth.users(id,email,email_confirmed_at) values(client_id,client_id||'@gama-test.invalid',now()),(outsider,outsider||'@gama-test.invalid',now());
 insert into public.profiles(id,role,active,email) values(client_id,'cliente',true,client_id||'@gama-test.invalid'),(outsider,'cliente',true,outsider||'@gama-test.invalid') on conflict(id) do update set role='cliente',active=true;
 insert into public.customers(name,address,email) values('P1 rollback','Quito',client_id||'@gama-test.invalid') returning id into c;
 bc:=gen_random_uuid()::text;
 insert into public.products(name,reference,barcode,sale_price,stock,weight_g,volume_cm3) values('P1-A-'||bc,bc,bc,10,10,250,2000) returning id into prod;
 insert into public.products(name,reference,barcode,sale_price,stock) values('P1-B-'||bc,gen_random_uuid(),gen_random_uuid(),20,4) returning id into subprod;
 insert into public.products(name,reference,barcode,sale_price,stock) values('P1-C-'||bc,gen_random_uuid(),gen_random_uuid(),20,0) returning id into emptyprod;
 insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity) values(prod,loc,10,0),(subprod,loc,4,0),(emptyprod,loc,0,0);
 perform set_config('request.jwt.claim.sub',a::text,true);execute 'set local role authenticated';
 res:=public.gama_sales_action('create',jsonb_build_object('request_key',gen_random_uuid(),'customer_id',c,'delivery_address','Quito','lines',jsonb_build_array(jsonb_build_object('product_id',prod,'quantity',12,'unit_price',10,'tax_rate',0))));oid:=(res->>'id')::uuid;
 perform public.gama_sales_action('confirm',jsonb_build_object('order_id',oid));
 select id into lid from public.sales_order_lines where order_id=oid;
 select id into prep from public.fulfillment_preparations where order_id=oid;
 if prep is null then raise exception 'FAIL_AUTO_QUEUE';end if;
 denied:=false;begin perform public.gama_sales_action('ship',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'lines',jsonb_build_array(jsonb_build_object('line_id',lid,'location_id',loc,'quantity',4))));exception when others then if sqlerrm like '%PACKING_REQUIRED%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_DIRECT_SHIP_GATE';end if;
 perform public.gama_fulfillment_action('start',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid()));
 select id into pickid from public.fulfillment_pick_lines where preparation_id=prep;
 keyid:=gen_random_uuid();data:=jsonb_build_object('order_id',oid,'request_key',keyid,'pick_line_id',pickid,'product_code',bc,'location_code',(select code from public.warehouse_locations where id=loc),'quantity',4);
 -- A scanned code must match the product sheet; picking without one is still allowed.
 denied:=false;begin perform public.gama_fulfillment_action('pick',data||jsonb_build_object('request_key',gen_random_uuid(),'product_code','NO-'||bc));exception when others then if sqlerrm like '%PRODUCT_SCAN_MISMATCH%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_PICK_SCAN_GUARD';end if;
 data:=data-'location_code'-'product_code';
 perform public.gama_fulfillment_action('pick',data);perform public.gama_fulfillment_action('pick',data);
 if (select picked from public.fulfillment_pick_lines where id=pickid)<>4 then raise exception 'FAIL_PICK_RETRY';end if;
 if (select sum(quantity) from public.stock_quants where product_id=prod)<>10 then raise exception 'FAIL_PICK_STOCK_TOTAL';end if;
 denied:=false;begin perform public.gama_fulfillment_action('pick',data||jsonb_build_object('quantity',1));exception when others then if sqlerrm like '%REQUEST_KEY_REUSED%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_IDEMPOTENCY_CONFLICT';end if;
 select sr.id into sid from public.stock_reservations sr where product_id=prod and location_id<>(loc) and status='active';
 denied:=false;begin perform public.gama_stock_unreserve(sid);exception when others then if sqlerrm like '%FULFILLMENT_RESERVATION_LOCKED%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_PICKED_RELEASE';end if;

 denied:=false;begin perform public.gama_fulfillment_action('finish',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid()));exception when others then if sqlerrm='PACKING_INCOMPLETE' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_UNCHECKED_CARTONS';end if;
 res:=public.gama_fulfillment_action('package',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'preparation_id',prep,'lines',jsonb_build_array(jsonb_build_object('pick_line_id',pickid,'quantity',4))));pkg:=(res->>'id')::uuid;
 -- Weight comes from the product sheet; the operator never types it and dimensions stay empty.
 if (select weight_kg from public.fulfillment_packages where id=pkg)<>1 then raise exception 'FAIL_PACKAGE_WEIGHT_SHEET';end if;
 if (select coalesce(length_cm,width_cm,height_cm) from public.fulfillment_packages where id=pkg) is not null then raise exception 'FAIL_PACKAGE_DIMENSIONS';end if;
 denied:=false;begin perform public.gama_fulfillment_action('finish',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid()));exception when others then if sqlerrm like '%PARTIAL_REASON_REQUIRED%' then denied:=true;else raise;end if;
 if not denied then raise exception 'FAIL_PARTIAL_REASON';end if;
 res:=public.gama_fulfillment_action('propose_option',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'line_id',lid,'kind','wait','quantity',12,'promised_date',current_date+5));opt:=(res->>'id')::uuid;
 perform public.gama_fulfillment_action('respond_option',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'option_id',opt,'decision','accepted','agreement_reference','Email test'));
 denied:=false;begin perform public.gama_fulfillment_action('finish',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'reason','Partial test'));exception when others then if sqlerrm like '%WAIT_FOR_COMPLETE%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_WAIT_AGREEMENT';end if;
 res:=public.gama_fulfillment_action('propose_option',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'line_id',lid,'kind','partial','quantity',4));opt:=(res->>'id')::uuid;
 perform public.gama_fulfillment_action('respond_option',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'option_id',opt,'decision','accepted','agreement_reference','Email partial'));
 perform public.gama_fulfillment_action('finish',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'reason','Entrega parcial acordada'));
 keyid:=gen_random_uuid();data:=jsonb_build_object('order_id',oid,'preparation_id',prep,'request_key',keyid);
 res:=public.gama_sales_action('ship',data);shipid:=(res->>'id')::uuid;perform public.gama_sales_action('ship',data);
 if (select sum(quantity) from public.stock_quants where product_id=prod)<>6 then raise exception 'FAIL_SHIP_STOCK';end if;
 -- TMS keeps reading the load from the product sheet, not from what an operator typed.
 select tms_delivery_id into tid from public.sales_deliveries where id=shipid;
 if round((select weight from public.tms_deliveries where id=tid)::numeric,3)<>1
 or round((select volume from public.tms_deliveries where id=tid)::numeric,6)<>0.008 then raise exception 'FAIL_TMS_LOAD_FROM_SHEET';end if;
 if (select shipment_id from public.fulfillment_preparations where id=prep)<>shipid then raise exception 'FAIL_PREP_LINK';end if;
 denied:=false;begin perform public.gama_loading_action('scan',jsonb_build_object('delivery_id',(select tms_delivery_id from public.sales_deliveries where id=shipid)));exception when others then if sqlerrm='INVALID_ACTION' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_TMS_STILL_SCANS';end if;
 update public.products set weight_g=null where id=prod;
 perform public.gama_fulfillment_action('void_package',jsonb_build_object('order_id',oid,'preparation_id',prep,'package_id',pkg,'reason','Corregir bulto','request_key',gen_random_uuid()));
 if (public.gama_loading_action('manifest',jsonb_build_object('delivery_id',(select tms_delivery_id from public.sales_deliveries where id=shipid)))->>'complete')::boolean then raise exception 'FAIL_VOID_PACKAGE_GATE';end if;
 res:=public.gama_fulfillment_action('package',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'preparation_id',prep,'lines',jsonb_build_array(jsonb_build_object('pick_line_id',pickid,'quantity',4))));pkg:=(res->>'id')::uuid;
 -- A product sheet without a weight leaves the parcel empty instead of blocking the operator.
 if (select weight_kg from public.fulfillment_packages where id=pkg) is not null then raise exception 'FAIL_PACKAGE_WEIGHT_EMPTY';end if;
 if not (public.gama_loading_action('manifest',jsonb_build_object('delivery_id',(select tms_delivery_id from public.sales_deliveries where id=shipid)))->>'complete')::boolean then raise exception 'FAIL_READY_AFTER_PACKING';end if;
 if (select sum(quantity) from public.stock_quants where product_id=prod)<>6 then raise exception 'FAIL_PACKING_MOVED_STOCK';end if;
 -- Full replacement retains the original line at zero and requires customer ownership.
 res:=public.gama_sales_action('create',jsonb_build_object('request_key',gen_random_uuid(),'customer_id',c,'delivery_address','Quito','lines',jsonb_build_array(jsonb_build_object('product_id',emptyprod,'quantity',2,'unit_price',20,'tax_rate',0))));oid2:=(res->>'id')::uuid;
 perform public.gama_sales_action('confirm',jsonb_build_object('order_id',oid2));select id into lid2 from public.sales_order_lines where order_id=oid2;
 res:=public.gama_fulfillment_action('propose_option',jsonb_build_object('order_id',oid2,'request_key',gen_random_uuid(),'line_id',lid2,'kind','substitute','quantity',2,'replacement_product_id',subprod,'unit_price',18,'tax_rate',0,'promised_date',current_date+3));opt:=(res->>'id')::uuid;
 execute 'reset role';perform set_config('request.jwt.claim.sub',outsider::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.gama_fulfillment_action('respond_option',jsonb_build_object('request_key',gen_random_uuid(),'option_id',opt,'decision','accepted'));exception when others then if sqlerrm like '%ORDER_NOT_FOUND%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_CUSTOMER_OWNERSHIP';end if;
 if jsonb_array_length(public.gama_fulfillment_action('options','{}'))<>0 then raise exception 'FAIL_OPTIONS_LEAK';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',client_id::text,true);execute 'set local role authenticated';
 perform public.gama_fulfillment_action('respond_option',jsonb_build_object('request_key',gen_random_uuid(),'option_id',opt,'decision','accepted'));
 denied:=false;begin perform public.gama_fulfillment_action('dossier',jsonb_build_object('order_id',oid2));exception when others then if sqlerrm like '%ROLE_NOT_ALLOWED%' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'FAIL_CLIENT_LOGISTICS';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',a::text,true);execute 'set local role authenticated';
 if (select quantity from public.sales_order_lines where id=lid2)<>0 then raise exception 'FAIL_REPLACEMENT_ORIGINAL';end if;
 if (select reserved_quantity from public.stock_quants where product_id=subprod)<>2 then raise exception 'FAIL_REPLACEMENT_RESERVATION';end if;
 -- Cancellation physically returns picked goods, without freeing the order reservation.
 perform public.gama_fulfillment_action('start',jsonb_build_object('order_id',oid2,'request_key',gen_random_uuid()));
 select p.id,pl.id into prep,pickid from public.fulfillment_preparations p join public.fulfillment_pick_lines pl on pl.preparation_id=p.id where p.order_id=oid2 and p.status='picking';
 perform public.gama_fulfillment_action('pick',jsonb_build_object('order_id',oid2,'request_key',gen_random_uuid(),'pick_line_id',pickid,'quantity',1,'location_code',(select code from public.warehouse_locations where id=loc),'product_code',(select barcode from public.products where id=subprod)));
 perform public.gama_fulfillment_action('cancel_preparation',jsonb_build_object('order_id',oid2,'request_key',gen_random_uuid(),'reason','Reorganización'));
 if (select quantity from public.stock_quants where product_id=subprod and location_id=loc)<>4 then raise exception 'FAIL_CANCEL_RESTORE_LOCATION';end if;
 if (select sum(reserved_quantity) from public.stock_quants where product_id=subprod)<>2 then raise exception 'FAIL_CANCEL_LOST_RESERVATION';end if;
 -- Direct Data API writes are denied, even for staff.
 denied:=false;begin update public.fulfillment_preparations set status='packed' where id=prep;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'FAIL_DIRECT_WRITE';end if;
 execute 'reset role';
 if exists(select 1 from public.products p where p.id in(prod,subprod,emptyprod) and p.stock<>coalesce((select sum(quantity) from public.stock_quants where product_id=p.id),0)) then raise exception 'FAIL_QUANT_INVARIANT';end if;
 if exists(select 1 from public.stock_quants q where q.product_id in(prod,subprod,emptyprod) and q.reserved_quantity<>coalesce((select sum(quantity) from public.stock_reservations r where r.product_id=q.product_id and r.location_id=q.location_id and r.status='active'),0)) then raise exception 'FAIL_RESERVATION_INVARIANT';end if;
end $$;
