-- Load fulfillment-test-helpers.sql in the same rollback transaction first.
-- Run within BEGIN/ROLLBACK; scans and Auth fixtures are never kept.
do $$
#variable_conflict use_column
<<loading_test>>
declare
 admin_id uuid; operator_id uuid:=gen_random_uuid(); client_user uuid:=gen_random_uuid(); cid uuid; pid uuid; pid2 uuid; loc uuid; loc2 uuid; wh uuid;
 oid uuid; lid uuid; lid2 uuid; sid uuid; tid uuid; driver uuid; route_id uuid;
 veh uuid;
 code text:='SCAN-'||gen_random_uuid(); code2 text:='SCAN-'||gen_random_uuid();
 r jsonb; key_id uuid:=gen_random_uuid(); payload jsonb; rejected boolean; scan_id uuid; v integer; movement_count integer; qty_before numeric;
begin
 select id into admin_id from public.profiles where role='administrador' and active limit 1;
 select id,warehouse_id into loc,wh from public.warehouse_locations where active order by id limit 1;
 insert into public.warehouse_locations(warehouse_id,code,name) values(wh,'LOAD-'||gen_random_uuid(),'Loading test rollback') returning id into loc2;
 insert into auth.users(id,email,email_confirmed_at) values(operator_id,operator_id||'@gama-test.invalid',now()),(client_user,client_user||'@gama-test.invalid',now());
 insert into public.profiles(id,role,active,full_name) values(operator_id,'almacenero',true,'Test loader'),(client_user,'cliente',true,'Test client') on conflict(id) do update set role=excluded.role,active=true;
 insert into public.customers(name,address) values('Loading test rollback','Quito') returning id into cid;
 insert into public.products(name,barcode,reference,sale_price,stock) values('Loading A '||gen_random_uuid(),code,gen_random_uuid()::text,10,4) returning id into pid;
 insert into public.products(name,barcode,reference,sale_price,stock) values('Loading B '||gen_random_uuid(),code2,gen_random_uuid()::text,10,1) returning id into pid2;
 insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity) values(pid,loc,2,0),(pid,loc2,2,0),(pid2,loc,1,0);
 -- El conductor vive en Flota y su vehículo también; la salida exige que
 -- estén emparejados por una afectación vigente.
 insert into public.fleet_drivers(name,active) values('Loading test driver',true) returning id into driver;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,status)
  values('TEST-TRUCK','Test','Test','truck','diesel','in_service') returning id into veh;
 insert into public.fleet_assignments(vehicle_id,driver_id,started_on) values(veh,driver,current_date);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);execute 'set local role authenticated';
 r:=public.gama_sales_action('create',jsonb_build_object('request_key',gen_random_uuid(),'customer_id',cid,'delivery_address','Quito','lines',jsonb_build_array(jsonb_build_object('product_id',pid,'quantity',4,'unit_price',10,'tax_rate',0),jsonb_build_object('product_id',pid2,'quantity',1,'unit_price',10,'tax_rate',0))));oid:=(r->>'id')::uuid;
 perform public.gama_sales_action('confirm',jsonb_build_object('order_id',oid));
 select id into lid from public.sales_order_lines where order_id=oid and product_id=pid;
 select id into lid2 from public.sales_order_lines where order_id=oid and product_id=pid2;
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 r:=pg_temp.gama_test_prepared_ship('ship',jsonb_build_object('order_id',oid,'request_key',gen_random_uuid(),'delivery_date',current_date+1,'lines',jsonb_build_array(jsonb_build_object('line_id',lid,'location_id',loc,'quantity',2),jsonb_build_object('line_id',lid,'location_id',loc2,'quantity',2),jsonb_build_object('line_id',lid2,'location_id',loc,'quantity',1))));sid:=(r->>'id')::uuid;
 select tms_delivery_id into tid from public.sales_deliveries where id=sid;
 if tid is null then raise exception 'FAIL_AUTOMATIC_TMS'; end if;
 -- Simulate a legacy line missing its snapshot; saving the product code repairs only that line.
 execute 'reset role';
 update public.sales_delivery_lines set loading_barcode=null where delivery_id=sid and order_line_id=lid2;
 update public.products set barcode=code2 where id=pid2;
 if exists(select 1 from public.sales_delivery_lines where delivery_id=sid and loading_barcode is null) then raise exception 'FAIL_LEGACY_BARCODE_RECOVERY'; end if;
 update public.products set barcode='CHANGED-'||code where id=pid;
 if exists(select 1 from public.sales_delivery_lines where delivery_id=sid and order_line_id=lid and loading_barcode<>code) then raise exception 'FAIL_SNAPSHOT_OVERWRITTEN'; end if;
 execute 'set local role authenticated';
 r:=public.gama_loading_action('manifest',jsonb_build_object('delivery_id',tid));
 if not (r->>'complete')::boolean then raise exception 'FAIL_PREPARED_NOT_READY';end if;
 v:=(r#>>'{shipment,version}')::integer;
 select count(*) into movement_count from public.stock_movements where product_id in(pid,pid2);
 select sum(quantity) into qty_before from public.stock_quants where product_id in(pid,pid2);
 rejected:=false;begin perform public.gama_loading_action('scan',jsonb_build_object('delivery_id',tid));exception when others then if sqlerrm='INVALID_ACTION' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_TRANSPORT_SCAN';end if;
 rejected:=false;begin insert into public.tms_proofs(delivery_id,photo) values(tid,'data:image/png;base64,AAAA');exception when others then if sqlerrm='DEPARTURE_REQUIRED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_PROOF_BEFORE_DEPARTURE';end if;
 rejected:=false;begin perform public.gama_loading_action('depart',jsonb_build_object('delivery_id',tid,'driver_id',driver,'version',v-1));exception when others then if sqlerrm='LOADING_CHANGED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_STALE_DEPARTURE';end if;
 r:=public.gama_loading_action('depart',jsonb_build_object('delivery_id',tid,'driver_id',driver,'version',v));
 if r#>>'{shipment,departed_at}' is null then raise exception 'FAIL_DEPARTURE';end if;
 perform public.gama_loading_action('depart',jsonb_build_object('delivery_id',tid,'driver_id',driver,'version',v));
 if (select count(*) from public.tms_events where delivery_id=tid and type='SALIDA_VALIDADA')<>1 then raise exception 'FAIL_DOUBLE_DEPARTURE';end if;
 if (select sum(quantity) from public.stock_quants where product_id in(pid,pid2))<>qty_before or (select count(*) from public.stock_movements where product_id in(pid,pid2))<>movement_count then raise exception 'FAIL_TRANSPORT_MOVED_STOCK';end if;
 rejected:=false;begin perform public.gama_fulfillment_action('void_package',jsonb_build_object('order_id',oid,'preparation_id',(select id from public.fulfillment_preparations where shipment_id=sid),'package_id',(select pk.id from public.fulfillment_packages pk join public.fulfillment_preparations pp on pp.id=pk.preparation_id where pp.shipment_id=sid limit 1),'request_key',gen_random_uuid(),'reason','After departure'));exception when others then if sqlerrm='LOADING_CLOSED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_REOPEN_DEPARTED_CARTON';end if;
 insert into public.tms_proofs(delivery_id,photo) values(tid,'data:image/png;base64,AAAA');
 perform set_config('request.jwt.claim.sub',client_user::text,true);
 rejected:=false;begin perform public.gama_loading_action('list','{}');exception when others then if sqlerrm='ROLE_NOT_ALLOWED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'FAIL_CLIENT_TRANSPORT';end if;
 execute 'reset role';
end $$;
