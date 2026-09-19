create or replace function private.gama_returns_action2(p_action text,p_data jsonb,rights jsonb,today date)
returns jsonb language plpgsql security definer set search_path='' as $fn$
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
end $fn$;
revoke all on function private.gama_returns_action2(text,jsonb,jsonb,date) from public,anon,authenticated;
