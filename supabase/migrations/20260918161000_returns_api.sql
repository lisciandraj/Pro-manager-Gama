-- API de Devoluciones. Todo lo crítico se decide aquí, en el servidor: cuánto
-- se puede devolver, cuánto se puede abonar o reembolsar, y qué ya no se toca.
-- La pantalla sólo propone.
--
-- La cadena se parte en cuatro funciones porque PostgREST expone una sola y el
-- cuerpo entero no cabe cómodo: gama_returns_action encadena a action2, ésta a
-- action3 y ésta a action4. La API pública es una sola llamada.

create or replace function private.gama_returns_rights() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r text:=coalesce(private.current_user_role(),''); fin boolean;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if r not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 -- «Finanzas» no es un rol de GAMA: es quien puede validar en Contabilidad.
 fin:=r='administrador' or exists(select 1 from public.accounting_permissions
   where profile_id=auth.uid() and coalesce(can_validate,false));
 return jsonb_build_object(
  'role',r,
  'view',true,
  'create',r in ('administrador','comercial','almacenero'),
  'process',r in ('administrador','almacenero'),
  'refund',fin,
  'delete',r='administrador');
end $$;

-- El importe del retorno sale de sus líneas, que llevan el precio y el impuesto
-- del documento de origen: un abono emitido hace un año se recalcula igual
-- aunque la tarifa haya cambiado.
create or replace function private.gama_return_amount(p_return uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce(round(sum(l.quantity*l.unit_price*(1+l.tax_rate/100)),2),0)
 from public.return_lines l where l.return_id=p_return
$$;

create or replace function private.gama_returns_action(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 rights jsonb:=private.gama_returns_rights();
 today date:=(now() at time zone 'America/Guayaquil')::date;
 d1 date; d2 date; search text:=btrim(coalesce(p_data->>'search',''));
 p_kind text:=nullif(p_data->>'kind','');
 r record; j jsonb;
begin
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 d2:=coalesce(nullif(p_data->>'to','')::date,today);
 if d2<d1 then raise exception 'INVALID_PERIOD';end if;

 if p_action='overview' then
  return jsonb_build_object('rights',rights,'today',today,
   'kpis',jsonb_build_object(
    'open',(select count(*) from public.return_orders where status not in ('closed','cancelled')),
    'to_process',(select count(*) from public.return_orders where status='to_process'),
    'financial_pending',(select count(*) from public.return_orders o
      where o.status not in ('cancelled')
        and ((o.financial_action='credit' and not exists(select 1 from public.return_credits c where c.return_id=o.id))
          or (o.financial_action='refund' and coalesce((select sum(amount) from public.return_refunds f where f.return_id=o.id),0)
              < private.gama_return_amount(o.id)))),
    'closed_month',(select count(*) from public.return_orders
      where status='closed' and (closed_at at time zone 'America/Guayaquil')::date
        between date_trunc('month',today)::date and today)),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
     select o.id,o.number,o.kind,o.status,o.reason,o.financial_action,
      (o.created_at at time zone 'America/Guayaquil')::date created_on,o.created_at,
      coalesce(c.name,s.name) partner,
      private.gama_return_amount(o.id) amount,
      (select count(*) from public.return_lines l where l.return_id=o.id) lines,
      (select coalesce(sum(amount),0) from public.return_refunds f where f.return_id=o.id) refunded,
      exists(select 1 from public.return_credits k where k.return_id=o.id) credited
     from public.return_orders o
     left join public.customers c on c.id=o.customer_id
     left join public.suppliers s on s.id=o.supplier_id
     where (p_kind is null or o.kind=p_kind)
       and (nullif(p_data->>'status','') is null or o.status=p_data->>'status')
       and (nullif(p_data->>'customer_id','') is null or o.customer_id=(p_data->>'customer_id')::uuid)
       and (nullif(p_data->>'supplier_id','') is null or o.supplier_id=(p_data->>'supplier_id')::uuid)
       and (coalesce((p_data->>'all_dates')::boolean,false)
            or (o.created_at at time zone 'America/Guayaquil')::date between d1 and d2)
       and (search='' or concat_ws(' ',o.number,c.name,s.name,o.notes) ilike '%'||search||'%')
     order by o.created_at desc limit 200) z),'[]'::jsonb),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.customers where active and exists(select 1 from public.return_orders o where o.customer_id=customers.id)),'[]'::jsonb),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.suppliers where active and exists(select 1 from public.return_orders o where o.supplier_id=suppliers.id)),'[]'::jsonb));

 elsif p_action='detail' then
  select * into r from public.return_orders where id=(p_data->>'id')::uuid;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  return to_jsonb(r)||jsonb_build_object(
   'rights',rights,
   'amount',private.gama_return_amount(r.id),
   'partner',coalesce((select name from public.customers where id=r.customer_id),
                      (select name from public.suppliers where id=r.supplier_id)),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'product_id',l.product_id,
      'product',p.name,'reference',p.reference,'quantity',l.quantity,'unit_price',l.unit_price,
      'tax_rate',l.tax_rate,'disposition',l.disposition,'processed_at',l.processed_at,'notes',l.notes,
      'amount',round(l.quantity*l.unit_price*(1+l.tax_rate/100),2)) order by p.name)
     from public.return_lines l join public.products p on p.id=l.product_id
     where l.return_id=r.id),'[]'::jsonb),
   'credits',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'number',k.number,'amount',k.amount,
      'issued_on',k.issued_on,'supplier_reference',k.supplier_reference,'notes',k.notes,
      'has_file',k.data_url is not null) order by k.created_at)
     from public.return_credits k where k.return_id=r.id),'[]'::jsonb),
   'refunds',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'amount',f.amount,'paid_at',f.paid_at,
      'method',f.method,'reference',f.reference,'notes',f.notes) order by f.paid_at)
     from public.return_refunds f where f.return_id=r.id),'[]'::jsonb),
   'refunded',(select coalesce(sum(amount),0) from public.return_refunds where return_id=r.id),
   'files',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'filename',x.filename,
      'mime_type',x.mime_type) order by x.created_at) from public.return_files x where x.return_id=r.id),'[]'::jsonb),
   -- Documentos ligados: nunca se duplican, se enlazan.
   'documents',(select jsonb_build_object(
      'order',(select jsonb_build_object('id',o.id,'number',o.number) from public.sales_orders o where o.id=r.order_id),
      'delivery',(select jsonb_build_object('id',s.id,'number',s.number) from public.sales_deliveries s where s.id=r.delivery_id),
      'invoice',(select jsonb_build_object('id',i.id,'number',i.number) from public.external_invoices i where i.id=r.invoice_id),
      'purchase_order',(select jsonb_build_object('id',po.id,'number',po.order_number) from public.purchase_orders po where po.id=r.purchase_order_id),
      'supplier_invoice',(select jsonb_build_object('id',si.id,'number',si.number) from public.supplier_invoices si where si.id=r.supplier_invoice_id))));
 end if;
 return private.gama_returns_action2(p_action,p_data,rights,today);
end $$;

create or replace function private.gama_returns_action2(p_action text,p_data jsonb,rights jsonb,today date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare eid uuid; r record; n integer; ln jsonb; qty numeric; src uuid;
begin
 -- Documentos de origen elegibles. El usuario elige uno y GAMA trae lo demás:
 -- cliente, productos, precios, impuestos y los documentos ligados.
 if p_action='sources' then
  if p_data->>'kind'='supplier' then
   return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.order_date desc) from (
     select po.id,po.order_number number,po.order_date,s.name partner,po.supplier_id,
      (select count(*) from public.purchase_order_lines pl
        where pl.purchase_order_id=po.id and coalesce(pl.received_quantity,0)>0) lines
     from public.purchase_orders po join public.suppliers s on s.id=po.supplier_id
     where exists(select 1 from public.purchase_order_lines pl
       where pl.purchase_order_id=po.id and coalesce(pl.received_quantity,0)>0)
     order by po.order_date desc limit 100) z),'[]'::jsonb));
  end if;
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.dispatched_at desc nulls last) from (
    select sd.id,sd.number,sd.dispatched_at,c.name partner,o.customer_id,
     o.id order_id,o.number order_number,
     (select i.id from public.external_invoices i
       where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected') order by i.issue_date desc limit 1) invoice_id,
     (select i.number from public.external_invoices i
       where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected') order by i.issue_date desc limit 1) invoice_number,
     (select count(*) from public.sales_delivery_lines dl where dl.delivery_id=sd.id) lines
    from public.sales_deliveries sd
    join public.sales_orders o on o.id=sd.order_id
    join public.customers c on c.id=o.customer_id
    order by sd.dispatched_at desc nulls last limit 100) z),'[]'::jsonb));

 -- Lo que se puede devolver de ese documento, con lo ya devuelto descontado.
 elsif p_action='source_lines' then
  src:=(p_data->>'source_id')::uuid;
  if p_data->>'kind'='supplier' then
   select po.id,po.order_number,po.supplier_id,s.name partner into r
    from public.purchase_orders po join public.suppliers s on s.id=po.supplier_id where po.id=src;
   if not found then raise exception 'SOURCE_NOT_FOUND';end if;
   return jsonb_build_object('kind','supplier','source_id',r.id,'number',r.order_number,
    'partner',r.partner,'supplier_id',r.supplier_id,
    'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.product) from (
      select pl.id line_id,pl.product_id,p.name product,p.reference,
       coalesce(pl.received_quantity,0) moved,
       coalesce((select sum(rl.quantity) from public.return_lines rl
         join public.return_orders ro on ro.id=rl.return_id
         where rl.purchase_order_line_id=pl.id and ro.status<>'cancelled'),0) returned,
       greatest(0,coalesce(pl.received_quantity,0)-coalesce((select sum(rl.quantity) from public.return_lines rl
         join public.return_orders ro on ro.id=rl.return_id
         where rl.purchase_order_line_id=pl.id and ro.status<>'cancelled'),0)) max_return,
       pl.unit_cost unit_price,pl.tax_rate
      from public.purchase_order_lines pl join public.products p on p.id=pl.product_id
      where pl.purchase_order_id=r.id and coalesce(pl.received_quantity,0)>0) z),'[]'::jsonb));
  end if;
  select sd.id,sd.number,o.id order_id,o.number order_number,o.customer_id,c.name partner into r
   from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
   join public.customers c on c.id=o.customer_id where sd.id=src;
  if not found then raise exception 'SOURCE_NOT_FOUND';end if;
  return jsonb_build_object('kind','customer','source_id',r.id,'number',r.number,
   'partner',r.partner,'customer_id',r.customer_id,'order_id',r.order_id,'order_number',r.order_number,
   'invoice_id',(select i.id from public.external_invoices i where i.order_id=r.order_id
     and i.fiscal_status not in ('cancelled','rejected') order by i.issue_date desc limit 1),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.product) from (
     select dl.id line_id,ol.product_id,p.name product,p.reference,
      dl.quantity moved,
      coalesce((select sum(rl.quantity) from public.return_lines rl
        join public.return_orders ro on ro.id=rl.return_id
        where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0) returned,
      greatest(0,dl.quantity-coalesce((select sum(rl.quantity) from public.return_lines rl
        join public.return_orders ro on ro.id=rl.return_id
        where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0)) max_return,
      ol.unit_price,ol.tax_rate
     from public.sales_delivery_lines dl
     join public.sales_order_lines ol on ol.id=dl.order_line_id
     join public.products p on p.id=ol.product_id
     where dl.delivery_id=r.id) z),'[]'::jsonb));

 elsif p_action='create' then
  if not (rights->>'create')::boolean then raise exception 'NOT_ALLOWED';end if;
  if jsonb_typeof(p_data->'lines')<>'array' or jsonb_array_length(p_data->'lines')=0
   then raise exception 'NO_LINES';end if;
  perform pg_advisory_xact_lock(884412);

  if p_data->>'kind'='supplier' then
   select po.id,po.supplier_id into r from public.purchase_orders po where po.id=(p_data->>'source_id')::uuid;
   if not found then raise exception 'SOURCE_NOT_FOUND';end if;
   insert into public.return_orders(kind,supplier_id,purchase_order_id,reason,notes,created_by)
    values('supplier',r.supplier_id,r.id,coalesce(nullif(p_data->>'reason',''),'other'),
      p_data->>'notes',auth.uid()) returning id into eid;
  else
   select sd.id,o.customer_id,o.id order_id into r
    from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
    where sd.id=(p_data->>'source_id')::uuid;
   if not found then raise exception 'SOURCE_NOT_FOUND';end if;
   insert into public.return_orders(kind,customer_id,order_id,delivery_id,invoice_id,reason,notes,created_by)
    values('customer',r.customer_id,r.order_id,r.id,
      nullif(p_data->>'invoice_id','')::uuid,
      coalesce(nullif(p_data->>'reason',''),'other'),p_data->>'notes',auth.uid()) returning id into eid;
  end if;

  for ln in select value from jsonb_array_elements(p_data->'lines') loop
   qty:=(ln->>'quantity')::numeric;
   if qty is null or qty<=0 then continue;end if;
   if p_data->>'kind'='supplier' then
    -- Nunca más de lo recibido menos lo ya devuelto. La regla vive aquí, en el
    -- servidor: la pantalla puede equivocarse, esto no.
    select pl.id,pl.product_id,pl.unit_cost,pl.tax_rate,
     greatest(0,coalesce(pl.received_quantity,0)-coalesce((select sum(rl.quantity) from public.return_lines rl
       join public.return_orders ro on ro.id=rl.return_id
       where rl.purchase_order_line_id=pl.id and ro.status<>'cancelled'),0)) allowed
     into r from public.purchase_order_lines pl
     where pl.id=(ln->>'line_id')::uuid and pl.purchase_order_id=(p_data->>'source_id')::uuid;
    if not found then raise exception 'INVALID_LINE';end if;
    if qty>r.allowed then raise exception 'RETURN_EXCEEDS_RECEIVED';end if;
    insert into public.return_lines(return_id,product_id,quantity,unit_price,tax_rate,purchase_order_line_id,notes)
     values(eid,r.product_id,qty,r.unit_cost,r.tax_rate,r.id,ln->>'notes');
   else
    select dl.id,ol.product_id,ol.unit_price,ol.tax_rate,
     greatest(0,dl.quantity-coalesce((select sum(rl.quantity) from public.return_lines rl
       join public.return_orders ro on ro.id=rl.return_id
       where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0)) allowed
     into r from public.sales_delivery_lines dl
     join public.sales_order_lines ol on ol.id=dl.order_line_id
     where dl.id=(ln->>'line_id')::uuid and dl.delivery_id=(p_data->>'source_id')::uuid;
    if not found then raise exception 'INVALID_LINE';end if;
    if qty>r.allowed then raise exception 'RETURN_EXCEEDS_DELIVERED';end if;
    insert into public.return_lines(return_id,product_id,quantity,unit_price,tax_rate,delivery_line_id,notes)
     values(eid,r.product_id,qty,r.unit_price,r.tax_rate,r.id,ln->>'notes');
   end if;
  end loop;

  select count(*) into n from public.return_lines where return_id=eid;
  if n=0 then raise exception 'NO_LINES';end if;
  return jsonb_build_object('id',eid,
   'number',(select number from public.return_orders where id=eid));
 end if;
 return private.gama_returns_action3(p_action,p_data,rights,today);
end $$;

create or replace function private.gama_returns_action3(p_action text,p_data jsonb,rights jsonb,today date)
returns jsonb language plpgsql security definer set search_path='' as $$
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
  -- La mercancía devuelta entra retenida, no en el stock disponible: todavía no
  -- se sabe si vale. Para el usuario no hay paso extra —recibir y decidir— pero
  -- el stock disponible no se mueve hasta que alguien decide.
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
  select * into l from public.return_lines where id=(p_data->>'line_id')::uuid and return_id=o.id for update;
  if not found then raise exception 'INVALID_LINE';end if;
  -- Una línea no se procesa dos veces: ni se repone dos veces, ni se desguaza
  -- lo ya repuesto. Se mira la línea antes que el documento para que el motivo
  -- del rechazo sea el de verdad.
  if l.processed_at is not null then raise exception 'LINE_ALREADY_PROCESSED';end if;
  if o.status<>'received' then raise exception 'NOT_RECEIVED';end if;
  if p_data->>'disposition' not in ('restocked','scrapped','to_supplier')
   then raise exception 'INVALID_DISPOSITION';end if;

  perform 1 from public.stock_reservations where id=l.hold_reservation_id for update;
  if l.hold_reservation_id is null or (select status from public.stock_reservations where id=l.hold_reservation_id)<>'active'
   then raise exception 'RETURN_HOLD_MISSING';end if;

  perform 1 from public.products where id=l.product_id for update;
  perform private.gama_lock_quant(l.product_id,l.quarantine_location_id);
  select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
  -- Sale de la retención en todos los casos: lo que cambia es adónde va.
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
     before_qty,before_qty,l.quarantine_location_id,loc.id,'return_in','customer_return',o.id);
  else
   -- Rebut o devolución al proveedor: la cantidad sale definitivamente del
   -- stock disponible.
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'out',l.quantity,
     case when p_data->>'disposition'='scrapped' then 'Devolución al rebut' else 'Devolución hacia el proveedor' end,
     o.number,u,before_qty,before_qty-l.quantity,l.quarantine_location_id,
     'return_out',
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
     before_qty,before_qty-l.quantity,loc.id,'return_out','supplier_return',o.id);
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
end $$;

create or replace function private.gama_returns_action4(p_action text,p_data jsonb,rights jsonb,today date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 o public.return_orders; u uuid:=auth.uid(); eid uuid;
 total numeric; already numeric; amount numeric; cap numeric; j jsonb;
begin
 if p_data ? 'id' then
  select * into o from public.return_orders where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  if o.status in ('closed','cancelled') and p_action<>'file_get' then raise exception 'RETURN_CLOSED';end if;
 end if;
 total:=private.gama_return_amount(o.id);

 -- Qué se hace con el dinero. Nada obliga a una acción: se puede desguazar y
 -- reembolsar, o reponer en stock y no devolver un céntimo.
 if p_action='financial_action' then
  if p_data->>'financial_action' not in ('none','credit','refund','store_credit')
   then raise exception 'INVALID_ACTION';end if;
  if (p_data->>'financial_action') in ('credit','refund','store_credit')
     and not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  update public.return_orders set financial_action=p_data->>'financial_action',updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'financial_action',p_data->>'financial_action');

 -- El importe lo calcula GAMA a partir de las líneas, que llevan el precio y
 -- el impuesto del documento original. El usuario autorizado puede ajustarlo,
 -- pero nunca por encima de lo que queda por abonar de esa factura.
 elsif p_action='credit_preview' then
  return jsonb_build_object('amount',total,
   'invoice_total',coalesce((select i.total from public.external_invoices i where i.id=o.invoice_id),0),
   'already',coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id),0));

 elsif p_action='credit' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  if o.invoice_id is null then raise exception 'INVOICE_REQUIRED';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  select i.total into cap from public.external_invoices i where i.id=o.invoice_id;
  already:=coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id),0);
  if amount+already>cap then raise exception 'CREDIT_EXCEEDS_INVOICE';end if;
  insert into public.return_credits(return_id,invoice_id,amount,issued_on,notes,created_by)
   values(o.id,o.invoice_id,amount,coalesce(nullif(p_data->>'issued_on','')::date,today),
     p_data->>'notes',u) returning id into eid;
  update public.return_orders set financial_action='credit',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,
   'number',(select number from public.return_credits where id=eid),'amount',amount);

 -- El abono que manda el proveedor: se registra, no se emite.
 elsif p_action='supplier_credit' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'supplier' then raise exception 'INVALID_ACTION';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  insert into public.return_credits(return_id,supplier_invoice_id,supplier_reference,amount,issued_on,
    notes,filename,mime_type,data_url,created_by)
   values(o.id,o.supplier_invoice_id,nullif(p_data->>'supplier_reference',''),amount,
     coalesce(nullif(p_data->>'issued_on','')::date,today),p_data->>'notes',
     nullif(p_data->>'filename',''),nullif(p_data->>'mime_type',''),nullif(p_data->>'data_url',''),u)
   returning id into eid;
  update public.return_orders set status='credited',financial_action='credit',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,'amount',amount);

 -- Reembolso al cliente. Nunca por encima del importe devuelto, y varios
 -- reembolsos sumados tampoco pueden pasarse.
 elsif p_action='refund' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  already:=coalesce((select sum(f.amount) from public.return_refunds f where f.return_id=o.id),0);
  if amount+already>total then raise exception 'REFUND_EXCEEDS_RETURN';end if;
  if length(coalesce(p_data->>'method',''))<2 then raise exception 'METHOD_REQUIRED';end if;
  insert into public.return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by)
   values(o.id,amount,coalesce(nullif(p_data->>'paid_at','')::date,today),p_data->>'method',
     nullif(p_data->>'reference',''),p_data->>'notes',
     nullif(p_data->>'request_key','')::uuid,u)
   on conflict(request_key) do nothing returning id into eid;
  if eid is null then
   select id into eid from public.return_refunds where request_key=(p_data->>'request_key')::uuid;
  end if;
  update public.return_orders set financial_action='refund',updated_at=now() where id=o.id;
  -- Las subconsultas van con alias: «amount» también es columna aquí.
  return jsonb_build_object('id',eid,'amount',amount,
   'refunded',(select coalesce(sum(f2.amount),0) from public.return_refunds f2 where f2.return_id=o.id),
   'outstanding',total-(select coalesce(sum(f3.amount),0) from public.return_refunds f3 where f3.return_id=o.id));

 elsif p_action='close' then
  if not (rights->>'process')::boolean and not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind='customer' and o.status not in ('processed') then raise exception 'NOT_PROCESSED';end if;
  if o.kind='supplier' and o.status not in ('shipped','credited') then raise exception 'NOT_SHIPPED';end if;
  update public.return_orders set status='closed',closed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','closed');

 elsif p_action='cancel' then
  if not (rights->>'create')::boolean then raise exception 'NOT_ALLOWED';end if;
  -- Sólo mientras no se haya tocado la mercancía: después hay movimientos de
  -- stock detrás y anular en silencio los dejaría huérfanos.
  if o.status<>'to_process' then raise exception 'RETURN_ALREADY_STARTED';end if;
  update public.return_orders set status='cancelled',closed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','cancelled');

 elsif p_action='file_add' then
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  if (select count(*) from public.return_files where return_id=o.id)>=6 then raise exception 'TOO_MANY_FILES';end if;
  insert into public.return_files(return_id,filename,mime_type,data_url,created_by)
   values(o.id,left(coalesce(p_data->>'filename','archivo'),180),nullif(p_data->>'mime_type',''),
     p_data->>'data_url',u) returning id into eid;
  return jsonb_build_object('id',eid);

 elsif p_action='file_get' then
  select jsonb_build_object('filename',filename,'mime_type',mime_type,'data_url',data_url) into j
   from public.return_files where id=(p_data->>'file_id')::uuid;
  if j is null then raise exception 'FILE_NOT_FOUND';end if;
  return j;

 elsif p_action='file_delete' then
  delete from public.return_files where id=(p_data->>'file_id')::uuid and return_id=o.id returning id into eid;
  if eid is null then raise exception 'FILE_NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);

 elsif p_action='delete' then
  if not (rights->>'delete')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.status<>'to_process' then raise exception 'RETURN_ALREADY_STARTED';end if;
  delete from public.return_orders where id=o.id;
  return jsonb_build_object('id',o.id,'deleted',true);
 end if;
 raise exception 'INVALID_ACTION';
end $$;

-- La única puerta: SECURITY INVOKER, y sólo para quien ha iniciado sesión.
create or replace function public.gama_returns_action(p_action text,p_data jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin return private.gama_returns_action(p_action,p_data);end $$;

revoke all on function public.gama_returns_action(text,jsonb) from public,anon;
grant execute on function public.gama_returns_action(text,jsonb) to authenticated;
