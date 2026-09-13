-- Picking records quantities only. Package/product controls happen after handoff to TMS.
do $$ declare src text;old text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 old:=$s$select * into p from public.fulfillment_preparations where order_id=oid and status in ('queued','picking','packed') for update;$s$;
 if position(old in src)=0 then raise exception 'Unexpected preparation selection';end if;
 src:=replace(src,old,$s$if p_action in ('package','void_package') then
   select * into p from public.fulfillment_preparations where order_id=oid and id=(p_data->>'preparation_id')::uuid and status='shipped' for update;
   if not found then raise exception 'PACKAGE_CONTROL_IN_TMS';end if;
   if not exists(select 1 from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id where sd.id=p.shipment_id and sd.departed_at is null and td.status not in ('Entregada','Cancelada')) then raise exception 'LOADING_CLOSED';end if;
  else
   select * into p from public.fulfillment_preparations where order_id=oid and status in ('queued','picking','packed') for update;
  end if;$s$);
 src:=replace(src,$s$p_action not in ('start','cancel_preparation')$s$,$s$p_action not in ('start','cancel_preparation','package','void_package')$s$);
 old:=$s$if loc.id is null or btrim(coalesce(p_data->>'location_code','')) not in (loc.code,coalesce(nullif(loc.barcode,''),loc.code)) then raise exception 'LOCATION_SCAN_MISMATCH';end if;$s$;
 if position(old in src)=0 then raise exception 'Unexpected picking location';end if;
 src:=replace(src,old,$s$if loc.id is null then raise exception 'LOCATION_SCAN_MISMATCH';end if;$s$);
 old:=$s$if nullif(btrim(pr.barcode),'') is null or btrim(coalesce(p_data->>'product_code',''))<>btrim(pr.barcode) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;$s$;
 if position(old in src)=0 then raise exception 'Unexpected picking scan';end if;
 src:=replace(src,old,'');
 src:=replace(src,$s$elsif p_action='package' then
  if p.status<>'picking'$s$,$s$elsif p_action='package' then
  if p.status<>'shipped'$s$);
 src:=replace(src,$s$elsif p_action='void_package' then
  if p.status<>'picking'$s$,$s$elsif p_action='void_package' then
  if p.status<>'shipped'$s$);
 old:=substring(src from position('  if not exists(select 1 from public.fulfillment_packages where preparation_id=p.id' in src) for position('  if exists(select 1 from public.sales_order_lines ol where ol.order_id=oid and ol.quantity>' in src)-position('  if not exists(select 1 from public.fulfillment_packages where preparation_id=p.id' in src));
 if position('PACKING_INCOMPLETE' in old)=0 then raise exception 'Unexpected finish packing gate';end if;
 src:=replace(src,old,$s$  if not exists(select 1 from public.fulfillment_pick_lines where preparation_id=p.id and picked>0) then raise exception 'PACKING_REQUIRED';end if;
$s$);
 -- Package changes invalidate stale departure manifests. The global logistics lock is already held.
 -- Add version update immediately before the common persisted result.
 src:=replace(src,$s$result:=jsonb_build_object('id',eid,'order_id',oid);$s$,$s$if p_action in ('package','void_package') then update public.sales_deliveries set loading_version=loading_version+1 where id=p.shipment_id;end if;
 result:=jsonb_build_object('id',eid,'order_id',oid);$s$);
 execute src;
end $$;
-- Completion requires both verified cargo scans and every prepared unit assigned to an active parcel.
create or replace function private.gama_loading_complete(p_delivery_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.sales_delivery_lines where delivery_id=p_delivery_id)
 and not exists(select 1 from public.sales_delivery_lines l where l.delivery_id=p_delivery_id
 and l.quantity<>coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans s on s.id=a.scan_id where a.delivery_line_id=l.id and s.voided_at is null),0))
 and not exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id where p.shipment_id=p_delivery_id
 and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0));
$$;
