-- Parcel verification belongs to preparation; TMS never rescans product contents.
do $$ declare src text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 if position('PACKAGE_CONTROL_IN_TMS' in src)=0 then raise exception 'Unexpected preparation function';end if;
 src:=replace(src,$s$id=(p_data->>'preparation_id')::uuid and status='shipped' for update;$s$,$s$id=(p_data->>'preparation_id')::uuid and status in ('picking','packed','shipped') for update;$s$);
 src:=replace(src,'PACKAGE_CONTROL_IN_TMS','PREPARATION_NOT_FOUND');
 src:=replace(src,$s$if not exists(select 1 from public.sales_deliveries sd join public.tms_deliveries td$s$,$s$if p.shipment_id is not null and not exists(select 1 from public.sales_deliveries sd join public.tms_deliveries td$s$);
 src:=replace(src,$s$if p.status<>'shipped' then raise exception 'PREPARATION_CLOSED';end if;$s$,$s$if p.status not in ('picking','packed','shipped') then raise exception 'PREPARATION_CLOSED';end if;$s$);
 src:=replace(src,$s$if p.status<>'shipped' or length(reason)<3$s$,$s$if p.status not in ('picking','packed','shipped') or length(reason)<3$s$);
 src:=replace(src,$s$elsif p_action='finish' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;$s$,$s$elsif p_action='finish' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;
  if exists(select 1 from public.fulfillment_pick_lines pl where pl.preparation_id=p.id and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0)) then raise exception 'PACKING_INCOMPLETE';end if;$s$);
 execute src;
 select pg_get_functiondef('private.gama_sales_action(text,jsonb)'::regprocedure) into src;
 if position($s$if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;$s$ in src)=0 then raise exception 'Unexpected shipment function';end if;
 src:=replace(src,$s$if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;$s$,$s$if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;
  if exists(select 1 from public.fulfillment_pick_lines pl where pl.preparation_id=p.id and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0)) then raise exception 'PACKING_INCOMPLETE';end if;$s$);
 execute src;
 -- Old scans stay in history but new scans are no longer a transport action.
 select pg_get_functiondef('private.gama_loading_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,$s$p_action not in ('list','manifest','scan','void_scan','depart')$s$,$s$p_action not in ('list','manifest','depart')$s$);
 execute src;
end $$;
create or replace function private.gama_loading_complete(p_delivery_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.sales_delivery_lines where delivery_id=p_delivery_id)
 and not exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id where p.shipment_id=p_delivery_id
 and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0));
$$;
