create or replace function private.gama_returns_action3(p_action text,p_data jsonb,rights jsonb,today date)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 o public.return_orders; l public.return_lines; loc public.warehouse_locations;
 u uuid:=auth.uid(); stage uuid; resv uuid; before_qty numeric; eid uuid;
 total numeric; already numeric; amount numeric; n integer;
begin
 o.id:=null;
 if p_data ? 'id' then
  select * into o from public.return_orders where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  -- Un documento cerrado o anulado no se toca en silencio.
  if o.status in ('closed','cancelled') and p_action not in ('file_get') then
   raise exception 'RETURN_CLOSED';end if;
 end if;

 -- ---------------------------------------------------- recepción física
 if p_action='receive' then
  if not (rights->>'process')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  if o.status<>'to_process' then raise exception 'ALREADY_RECEIVED';end if;
  select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
  -- La mercancía devuelta entra en cuarentena, no en el stock disponible:
  -- todavía no se sabe si vale. La zona se crea la primera vez y se reutiliza.
  insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)
   values(loc.warehouse_id,'RET-QUARANTINE','Devoluciones — cuarentena','zone','RET-QUARANTINE')
   on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;
  for l in select * from public.return_lines where return_id=o.id loop
   perform 1 from public.products where id=l.product_id for update;
   perform private.gama_lock_quant(l.product_id,stage);
   select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
   insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity)
    values(l.product_id,stage,l.quantity,l.quantity)
    on conflict(product_id,location_id) do update
      set quantity=public.stock_quants.quantity+l.quantity,
          reserved_quantity=public.stock_quants.reserved_quantity+l.quantity,updated_at=now();
   insert into public.stock_reservations(product_id,location_id,quantity,reference_type,reference_id,created_by)
    values(l.product_id,stage,l.quantity,'customer_return',o.id,u) returning id into resv;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,destination_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'in',l.quantity,'Devolución en cuarentena',o.number,u,
     before_qty,before_qty+l.quantity,stage,'return_in','customer_return',o.id);
   perform private.gama_sync_product_stock(l.product_id);
   update public.return_lines set quarantine_location_id=stage,hold_reservation_id=resv where id=l.id;
  end loop;
  update public.return_orders set status='received',received_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','received');

 -- ------------------------------------------- qué se hace con el producto
 elsif p_action='process_line' then
  if not (rights->>'process')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.status<>'received' then raise exception 'NOT_RECEIVED';end if;
  select * into l from public.return_lines where id=(p_data->>'line_id')::uuid and return_id=o.id for update;
  if not found then raise exception 'INVALID_LINE';end if;
  -- Una línea no se procesa dos veces: ni se repone dos veces, ni se
  -- desguaza lo ya repuesto.
  if l.processed_at is not null then raise exception 'LINE_ALREADY_PROCESSED';end if;
  if p_data->>'disposition' not in ('restocked','scrapped','to_supplier')
   then raise exception 'INVALID_DISPOSITION';end if;

  select * into resv from public.stock_reservations where id=l.hold_reservation_id for update;
  if l.hold_reservation_id is null or (select status from public.stock_reservations where id=l.hold_reservation_id)<>'active'
   then raise exception 'RETURN_HOLD_MISSING';end if;

  perform 1 from public.products where id=l.product_id for update;
  perform private.gama_lock_quant(l.product_id,l.quarantine_location_id);
  select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
  -- Sale de cuarentena en todos los casos: lo que cambia es adónde va.
  update public.stock_reservations set status='released',released_at=now() where id=l.hold_reservation_id;
  update public.stock_quants set reserved_quantity=reserved_quantity-l.quantity,
    quantity=quantity-l.quantity,updated_at=now()
   where product_id=l.product_id and location_id=l.quarantine_location_id;

  if p_data->>'disposition'='restocked' then
   select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
   if not found or loc.id=l.quarantine_location_id then raise exception 'LOCATION_NOT_FOUND';end if;
   perform private.gama_lock_quant(l.product_id,loc.id);
   insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity)
    values(l.product_id,loc.id,l.quantity,0)
    on conflict(product_id,location_id) do update
      set quantity=public.stock_quants.quantity+l.quantity,updated_at=now();
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,destination_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'in',l.quantity,'Devolución repuesta en stock',o.number,u,
     before_qty,before_qty,l.quarantine_location_id,loc.id,'return_restock','customer_return',o.id);
  else
   -- Rebut o devolución al proveedor: la cantidad sale definitivamente del
   -- stock disponible.
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'out',l.quantity,
     case when p_data->>'disposition'='scrapped' then 'Devolución al rebut' else 'Devolución hacia el proveedor' end,
     o.number,u,before_qty,before_qty-l.quantity,l.quarantine_location_id,
     case when p_data->>'disposition'='scrapped' then 'return_scrap' else 'return_to_supplier' end,
     'customer_return',o.id);
  end if;
  perform private.gama_sync_product_stock(l.product_id);
  update public.return_lines set disposition=p_data->>'disposition',processed_at=now(),
    notes=coalesce(nullif(p_data->>'notes',''),notes) where id=l.id;

  select count(*) into n from public.return_lines where return_id=o.id and processed_at is null;
  if n=0 then update public.return_orders set status='processed',processed_at=now(),updated_at=now() where id=o.id;end if;
  return jsonb_build_object('id',o.id,'line_id',l.id,'pending',n);

 -- --------------------------------------------- expedición al proveedor
 elsif p_action='ship' then
  if not (rights->>'process')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'supplier' then raise exception 'INVALID_ACTION';end if;
  if o.status<>'to_process' then raise exception 'ALREADY_SHIPPED';end if;
  select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
  for l in select * from public.return_lines where return_id=o.id loop
   perform 1 from public.products where id=l.product_id for update;
   perform private.gama_lock_quant(l.product_id,loc.id);
   select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
   if coalesce((select quantity-reserved_quantity from public.stock_quants
     where product_id=l.product_id and location_id=loc.id),0)<l.quantity
    then raise exception 'INSUFFICIENT_STOCK';end if;
   update public.stock_quants set quantity=quantity-l.quantity,updated_at=now()
    where product_id=l.product_id and location_id=loc.id;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'out',l.quantity,'Devolución al proveedor',o.number,u,
     before_qty,before_qty-l.quantity,loc.id,'supplier_return','supplier_return',o.id);
   perform private.gama_sync_product_stock(l.product_id);
   update public.return_lines set disposition='to_supplier',processed_at=now() where id=l.id;
  end loop;
  update public.return_orders set status='shipped',
    carrier=nullif(p_data->>'carrier',''),tracking=nullif(p_data->>'tracking',''),
    shipped_on=coalesce(nullif(p_data->>'shipped_on','')::date,today),
    processed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','shipped');
 end if;
 return private.gama_returns_action4(p_action,p_data,rights,today);
end $fn$;
revoke all on function private.gama_returns_action3(text,jsonb,jsonb,date) from public,anon,authenticated;
