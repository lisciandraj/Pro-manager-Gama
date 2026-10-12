-- Complete preparation handoff is one transaction. Existing pick, packing,
-- partial-delivery, stock, audit and transport APIs remain authoritative.
-- No historical preparation is changed by installing this endpoint.
create function private.gama_preparation_dispatch(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid();key_id uuid;oid uuid;pid uuid;
 prep public.fulfillment_preparations;receipt private.fulfillment_requests;
 items jsonb;result jsonb;reason text;delivery_day date;
begin
 if actor is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('tms',array['administrador','almacenero'])
  or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then
  raise exception 'TMS_ACCESS_DENIED';
 end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 key_id:=nullif(p_data->>'request_key','')::uuid;
 oid:=nullif(p_data->>'order_id','')::uuid;pid:=nullif(p_data->>'preparation_id','')::uuid;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 if oid is null or pid is null then raise exception 'PREPARATION_NOT_FOUND';end if;
 reason:=btrim(coalesce(p_data->>'reason',''));
 if length(reason)>2000 then raise exception 'TEXT_TOO_LONG';end if;

 -- Match the existing logistics lock order before locking the document.
 perform pg_advisory_xact_lock(741932,1);
 perform 1 from public.sales_orders where id=oid and status='confirmed' for update;
 if not found then raise exception 'CONFIRM_ORDER_FIRST';end if;
 select * into prep from public.fulfillment_preparations where id=pid and order_id=oid for update;
 if not found then raise exception 'PREPARATION_NOT_FOUND';end if;
 if prep.assigned_to is distinct from actor and private.current_user_role()<>'administrador' then
  raise exception 'ASSIGNED_TO_OTHER';
 end if;
 select * into receipt from private.fulfillment_requests where request_key=key_id;
 if found then
  if receipt.actor_id<>actor or receipt.action<>'auto_dispatch'
   or receipt.payload_hash<>encode(sha256(convert_to(p_data::text,'UTF8')),'hex') then
   raise exception 'REQUEST_KEY_REUSED';
  end if;
  return receipt.result;
 end if;

 -- A refreshed tab or another retry key can only return the same shipment.
 if prep.status='shipped' and prep.shipment_id is not null then
  result:=jsonb_build_object('id',prep.shipment_id,'order_id',oid,'preparation_id',pid);
 else
  if prep.status not in ('picking','packed') then raise exception 'PREPARATION_CLOSED';end if;
  if not exists(select 1 from public.fulfillment_pick_lines where preparation_id=pid and picked>0)
   or (prep.status='picking' and exists(select 1 from public.fulfillment_pick_lines
    where preparation_id=pid and picked<>planned)) then
   raise exception 'PREPARATION_INCOMPLETE';
  end if;

  -- Keep manually made parcels; pack only quantities not yet in an active one.
  -- The existing package API accepts at most 200 lines per parcel.
  loop
   select jsonb_agg(jsonb_build_object('pick_line_id',a.id,'quantity',a.quantity) order by a.id)
    into items from (
     select pl.id,pl.picked-coalesce(sum(pk.quantity),0) quantity
     from public.fulfillment_pick_lines pl left join (
      select l.pick_line_id,l.quantity from public.fulfillment_package_lines l
       join public.fulfillment_packages p on p.id=l.package_id and p.status='active'
     ) pk on pk.pick_line_id=pl.id
     where pl.preparation_id=pid group by pl.id,pl.picked
     having pl.picked>coalesce(sum(pk.quantity),0) order by pl.id limit 200
    ) a;
   exit when items is null;
   perform public.gama_fulfillment_action('package',jsonb_build_object(
    'order_id',oid,'preparation_id',pid,'request_key',gen_random_uuid(),'lines',items));
  end loop;
  if prep.status='picking' then
   perform public.gama_fulfillment_action('finish',jsonb_build_object(
    'order_id',oid,'preparation_id',pid,'request_key',gen_random_uuid(),'reason',reason));
  end if;
  -- Use the agreed date for the prepared goods, never a past planning date.
  select greatest((now() at time zone private.erp_timezone())::date,max(ol.promised_date))
   into delivery_day from public.sales_order_lines ol join public.fulfillment_pick_lines pl
    on pl.order_line_id=ol.id where pl.preparation_id=pid and pl.picked>0;
  result:=public.gama_sales_action('ship',jsonb_build_object(
   'order_id',oid,'preparation_id',pid,'request_key',gen_random_uuid(),'delivery_date',delivery_day))
    ||jsonb_build_object('preparation_id',pid);
 end if;
 result:=result||jsonb_build_object('tms_delivery_id',(
  select tms_delivery_id from public.sales_deliveries where id=(result->>'id')::uuid));
 insert into private.fulfillment_requests(request_key,actor_id,action,payload_hash,result)
  values(key_id,actor,'auto_dispatch',encode(sha256(convert_to(p_data::text,'UTF8')),'hex'),result);
 return result;
end $$;

create function public.gama_preparation_dispatch(p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_preparation_dispatch(p_data)$$;
revoke all on function private.gama_preparation_dispatch(jsonb),public.gama_preparation_dispatch(jsonb) from public,anon;
grant execute on function private.gama_preparation_dispatch(jsonb),public.gama_preparation_dispatch(jsonb) to authenticated;
comment on function public.gama_preparation_dispatch(jsonb) is
 'Empaqueta las cantidades validadas, cierra la preparación completa y crea una única entrega TMS de forma atómica.';
