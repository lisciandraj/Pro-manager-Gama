-- Optional traceability starts with zero stock. Received lots must be identified
-- before removal; every removal/transfer keeps a movement-to-lot ledger.
alter table public.products add column lot_tracking boolean not null default false,add column lot_tracking_since timestamptz;
create table public.product_lots(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),code text not null check(length(btrim(code)) between 1 and 100),expires_on date,created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id),unique(product_id,code));
create table public.stock_lot_balances(lot_id uuid not null references public.product_lots(id),location_id uuid not null references public.warehouse_locations(id),quantity numeric(14,3) not null check(quantity>=0),primary key(lot_id,location_id));
create table public.stock_lot_movements(id uuid primary key default gen_random_uuid(),movement_id uuid not null references public.stock_movements(id),lot_id uuid not null references public.product_lots(id),source_location_id uuid references public.warehouse_locations(id),destination_location_id uuid references public.warehouse_locations(id),quantity numeric(14,3) not null check(quantity>0),created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id));
do $$declare tbl text;begin foreach tbl in array array['product_lots','stock_lot_balances','stock_lot_movements'] loop
 execute format('alter table public.%I enable row level security',tbl);execute format('revoke all on public.%I from public,anon,authenticated;grant select on public.%I to authenticated',tbl,tbl);
 execute format('create policy lot_read on public.%I for select to authenticated using(private.erp_module_allowed(''warehouses'',array[''administrador'',''almacenero'']) or private.erp_module_allowed(''products'',array[''administrador'',''comercial'']))',tbl);
 end loop;end $$;
create index lot_balance_location on public.stock_lot_balances(location_id);
create index lot_movement_source on public.stock_lot_movements(source_location_id);create index lot_movement_destination on public.stock_lot_movements(destination_location_id);
create index lot_movement_stock on public.stock_lot_movements(movement_id);create index lot_movement_lot on public.stock_lot_movements(lot_id,created_at);
create index lot_movement_actor on public.stock_lot_movements(created_by);create index product_lot_actor on public.product_lots(created_by);
create trigger erp_audit_capture after insert on public.product_lots for each row execute function private.erp_audit_capture();
create trigger erp_audit_capture after insert on public.stock_lot_movements for each row execute function private.erp_audit_capture();
create function private.erp_lot_mode_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.lot_tracking and new.product_kind<>'goods' then raise exception 'LOT_GOODS_ONLY';end if;
 if tg_op='INSERT' then if new.lot_tracking and not private.erp_module_allowed('products',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;new.lot_tracking_since:=case when new.lot_tracking then now() end;
 elsif new.lot_tracking is distinct from old.lot_tracking then
 if not private.erp_module_allowed('products',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if exists(select 1 from public.stock_quants where product_id=new.id and (quantity<>0 or reserved_quantity<>0)) or coalesce(new.stock,0)<>0 then raise exception 'LOT_MODE_REQUIRES_ZERO_STOCK';end if;
 if exists(select 1 from public.product_lots where product_id=new.id) then raise exception 'LOT_MODE_ALREADY_USED';end if;
 new.lot_tracking_since:=case when new.lot_tracking then now() end;
 else new.lot_tracking_since:=old.lot_tracking_since;end if;return new;end $$;
revoke all on function private.erp_lot_mode_guard() from public,anon,authenticated;
create trigger erp_lot_mode_guard before insert or update on public.products for each row execute function private.erp_lot_mode_guard();
create function private.erp_lot_plan(p_product uuid,p_location uuid,p_quantity numeric,p_expiry boolean default true) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare x record;remaining numeric:=p_quantity;take numeric;result jsonb:='[]';begin
 if not exists(select 1 from public.products where id=p_product and lot_tracking) then return null;end if;
 if p_quantity is null or p_quantity<=0 or p_quantity<>round(p_quantity,3) then raise exception 'INVALID_QUANTITY';end if;
 for x in select l.id,l.code,l.expires_on,b.quantity from public.product_lots l join public.stock_lot_balances b on b.lot_id=l.id where l.product_id=p_product and b.location_id=p_location and b.quantity>0 and (not p_expiry or l.expires_on is null or l.expires_on>=current_date) order by l.expires_on nulls last,l.created_at,l.id loop
 exit when remaining<=0;take:=least(remaining,x.quantity);result:=result||jsonb_build_array(jsonb_build_object('lot_id',x.id,'code',x.code,'expires_on',x.expires_on,'quantity',take));remaining:=remaining-take;
 end loop;
 if remaining>0 then raise exception 'IDENTIFY_RECEIVED_LOTS_OR_CHECK_EXPIRY';end if;return result;
end $$;
revoke all on function private.erp_lot_plan(uuid,uuid,numeric,boolean) from public,anon,authenticated;
create function private.gama_lot_pick_plan(p_product uuid,p_location uuid,p_quantity numeric) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.erp_module_allowed('order-preparation',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;return private.erp_lot_plan(p_product,p_location,p_quantity,true);end $$;
revoke all on function private.gama_lot_pick_plan(uuid,uuid,numeric) from public,anon;grant execute on function private.gama_lot_pick_plan(uuid,uuid,numeric) to authenticated;
create function public.gama_lot_pick_plan(p_product uuid,p_location uuid,p_quantity numeric) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_lot_pick_plan(p_product,p_location,p_quantity)$$;
revoke all on function public.gama_lot_pick_plan(uuid,uuid,numeric) from public,anon;grant execute on function public.gama_lot_pick_plan(uuid,uuid,numeric) to authenticated;
create function private.erp_lot_movement() returns trigger language plpgsql security definer set search_path='' as $$
declare plan jsonb;x jsonb;strict_expiry boolean;begin
 if not exists(select 1 from public.products where id=new.product_id and lot_tracking) then return new;end if;
 if new.source_location_id is null then
 if new.destination_location_id is null then raise exception 'LOT_LOCATION_REQUIRED';end if;return new;-- Identify inbound lot codes in the receiving register.
 end if;
 perform 1 from public.products where id=new.product_id for update;
 strict_expiry:=(new.reference_type='sales_order' or new.movement_type in ('issue','shipment','manual_out')) and coalesce(current_setting('erp.lot_reset',true),'')<>'yes';
 plan:=private.erp_lot_plan(new.product_id,new.source_location_id,abs(new.quantity),coalesce(strict_expiry,false));
 for x in select value from jsonb_array_elements(plan) loop
 update public.stock_lot_balances set quantity=quantity-(x->>'quantity')::numeric where lot_id=(x->>'lot_id')::uuid and location_id=new.source_location_id;
 if new.destination_location_id is not null then insert into public.stock_lot_balances(lot_id,location_id,quantity) values((x->>'lot_id')::uuid,new.destination_location_id,(x->>'quantity')::numeric) on conflict(lot_id,location_id) do update set quantity=public.stock_lot_balances.quantity+excluded.quantity;end if;
 insert into public.stock_lot_movements(movement_id,lot_id,source_location_id,destination_location_id,quantity,created_by) values(new.id,(x->>'lot_id')::uuid,new.source_location_id,new.destination_location_id,(x->>'quantity')::numeric,auth.uid());
 end loop;return new;
end $$;
revoke all on function private.erp_lot_movement() from public,anon,authenticated;
create trigger erp_lot_movement after insert on public.stock_movements for each row execute function private.erp_lot_movement();
create function private.gama_lots(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare pid uuid:=(p_data->>'product_id')::uuid;m public.stock_movements;l public.product_lots;p public.products;k uuid;prior private.command_receipts;result jsonb;qty numeric;begin
 if not(private.erp_module_allowed('warehouses',array['administrador','almacenero']) or private.erp_module_allowed('products',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into p from public.products where id=pid;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_action='identify' then
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) or not private.erp_action_allowed('warehouses','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.products where id=pid for update;k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('identify-lot:'||k::text,0));select * into prior from private.command_receipts where domain='identify-lot' and request_key=k;
 if found then if prior.actor_id<>auth.uid() or prior.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 select * into m from public.stock_movements where id=(p_data->>'movement_id')::uuid and product_id=pid for update;
 if m.id is null or not p.lot_tracking or m.created_at<p.lot_tracking_since or m.source_location_id is not null or m.destination_location_id is null then raise exception 'INBOUND_LOT_MOVEMENT_REQUIRED';end if;
 qty:=(p_data->>'quantity')::numeric;
 if qty is null or qty<=0 or qty<>round(qty,3) or qty+coalesce((select sum(quantity) from public.stock_lot_movements where movement_id=m.id),0)>abs(m.quantity) then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
 select * into l from public.product_lots where product_id=pid and code=btrim(p_data->>'code');
 if found then if l.expires_on is distinct from nullif(p_data->>'expires_on','')::date then raise exception 'LOT_EXPIRY_MISMATCH';end if;
 else insert into public.product_lots(product_id,code,expires_on,created_by) values(pid,btrim(p_data->>'code'),nullif(p_data->>'expires_on','')::date,auth.uid()) returning * into l;end if;
 insert into public.stock_lot_balances(lot_id,location_id,quantity) values(l.id,m.destination_location_id,qty) on conflict(lot_id,location_id) do update set quantity=public.stock_lot_balances.quantity+excluded.quantity;
 insert into public.stock_lot_movements(movement_id,lot_id,destination_location_id,quantity,created_by) values(m.id,l.id,m.destination_location_id,qty,auth.uid());
 result:=to_jsonb(l);insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('identify-lot',k,auth.uid(),p_data,result);return result;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('product',to_jsonb(p)-'photo_data','pending',(select coalesce(jsonb_agg(to_jsonb(movement_row)||jsonb_build_object('remaining',abs(movement_row.quantity)-coalesce((select sum(lm.quantity) from public.stock_lot_movements lm where lm.movement_id=movement_row.id),0)) order by movement_row.created_at),'[]') from public.stock_movements movement_row where movement_row.product_id=pid and movement_row.source_location_id is null and movement_row.destination_location_id is not null and p.lot_tracking and movement_row.created_at>=p.lot_tracking_since and abs(movement_row.quantity)>coalesce((select sum(lm.quantity) from public.stock_lot_movements lm where lm.movement_id=movement_row.id),0)),
 'balances',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('code',lot_row.code,'expires_on',lot_row.expires_on,'location',(select code from public.warehouse_locations where id=b.location_id)) order by lot_row.expires_on nulls last,lot_row.code),'[]') from public.stock_lot_balances b join public.product_lots lot_row on lot_row.id=b.lot_id where lot_row.product_id=pid),
 'history',(select coalesce(jsonb_agg(to_jsonb(lm)||jsonb_build_object('code',lot_row.code,'reference_type',movement_row.reference_type,'reference_id',movement_row.reference_id,'reason',movement_row.reason,'comment',movement_row.comment) order by lm.created_at desc,lm.id),'[]') from public.stock_lot_movements lm join public.product_lots lot_row on lot_row.id=lm.lot_id join public.stock_movements movement_row on movement_row.id=lm.movement_id where lot_row.product_id=pid));
end $$;
revoke all on function private.gama_lots(text,jsonb) from public,anon;grant execute on function private.gama_lots(text,jsonb) to authenticated;
create function public.gama_lots(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_lots(p_action,p_data)$$;
revoke all on function public.gama_lots(text,jsonb) from public,anon;grant execute on function public.gama_lots(text,jsonb) to authenticated;
-- Pickers explicitly check lot codes. Recompute under the stock transaction lock
-- so a concurrent pick cannot silently change the displayed FEFO allocation.
do $$declare src text;anchor text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 anchor:='select * into loc from public.warehouse_locations where id=pl.source_location_id and active;';
 if strpos(src,anchor)=0 then raise exception 'LOT_PICK_ANCHOR';end if;
 src:=replace(src,anchor,$patch$if exists(select 1 from public.products where id=l.product_id and lot_tracking) then
 if p_data->'lot_plan' is distinct from private.erp_lot_plan(l.product_id,pl.source_location_id,qty,true) then raise exception 'LOT_PLAN_CHANGED';end if;end if;
 $patch$||anchor);execute src;
end $$;
-- Returning a cancelled preparation to storage is allowed even after expiry.
-- The expiry gate still applies to its next pick and shipment.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_reset_preparation(uuid,text)'::regprocedure) into src;
 src:=replace(src,'perform private.gama_fulfillment_move(l.order_line_id,l.stage_location_id,l.source_location_id,l.picked);',$patch$perform set_config('erp.lot_reset','yes',true);perform private.gama_fulfillment_move(l.order_line_id,l.stage_location_id,l.source_location_id,l.picked);perform set_config('erp.lot_reset','',true);$patch$);execute src;
end $$;
