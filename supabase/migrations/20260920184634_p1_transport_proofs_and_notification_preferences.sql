create function private.gama_tms_capture(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;pr public.tms_proofs;key uuid:=(p_data->>'request_key')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('hash',md5((p_data-'request_key')::text));stamp timestamptz:=nullif(p_data->>'captured_at','')::timestamptz;signature text:=p_data->>'signature';photo text:=p_data->>'photo';result jsonb;begin
 if not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended('tms-capture:'||key::text,0));
 select * into receipt from private.command_receipts where domain='tms-capture' and request_key=key;if found then if receipt.actor_id<>auth.uid() or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;if not found or d.status in ('Entregada','Cancelada') then raise exception 'DELIVERY_CLOSED';end if;
 if stamp is null or stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
 if signature is null and photo is null then raise exception 'PROOF_REQUIRED';end if;
 if (signature is not null and (signature!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(signature)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
 if p_data->>'complete'='true' and nullif(signature,'') is null then raise exception 'SIGNATURE_REQUIRED';end if;
 select * into pr from public.tms_proofs where delivery_id=d.id for update;
 if pr.signature is not null and signature is not null and pr.signature<>signature then raise exception 'PROOF_CONFLICT';end if;
 insert into public.tms_proofs(delivery_id,photo,signature,captured_at,captured_by) values(d.id,photo,signature,stamp,auth.uid()) on conflict(delivery_id) do update set photo=coalesce(excluded.photo,tms_proofs.photo),signature=coalesce(excluded.signature,tms_proofs.signature),captured_at=excluded.captured_at,captured_by=excluded.captured_by;
 if p_data->>'complete'='true' then
 update public.tms_deliveries set status='Entregada',actual_arrival=coalesce(actual_arrival,stamp),delivered_at=stamp where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'Entregada','Prueba de entrega registrada',d.customer,auth.uid());end if;
 result:=jsonb_build_object('delivery_id',d.id,'captured_at',stamp,'completed',p_data->>'complete'='true');insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-capture',key,auth.uid(),payload,result);return result;
end $$;
revoke all on function private.gama_tms_capture(jsonb) from public,anon;grant execute on function private.gama_tms_capture(jsonb) to authenticated;
create function public.gama_tms_capture(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_capture(p_data)$$;
revoke all on function public.gama_tms_capture(jsonb) from public,anon;grant execute on function public.gama_tms_capture(jsonb) to authenticated;

alter table public.tms_deliveries add column service_minutes integer not null default 10 check(service_minutes between 0 and 480);
create table public.tms_route_schedules(id uuid primary key default gen_random_uuid(),route_id uuid not null unique references public.tms_routes(id),starts_at timestamptz not null,legs jsonb not null,road_source text not null check(length(btrim(road_source))>=3),road_km numeric not null check(road_km>=0),duration_minutes integer not null check(duration_minutes>=0),updated_by uuid not null default auth.uid() references public.profiles(id),updated_at timestamptz not null default now());
alter table public.tms_route_schedules enable row level security;revoke all on public.tms_route_schedules from public,anon,authenticated;grant select on public.tms_route_schedules to authenticated;
create policy route_schedule_read on public.tms_route_schedules for select to authenticated using(private.erp_module_allowed('tms',array['administrador','almacenero']));create index route_schedule_actor on public.tms_route_schedules(updated_by);
create trigger erp_audit_capture after insert or update or delete on public.tms_route_schedules for each row execute function private.erp_audit_capture();
create function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes int:=0;km numeric:=0;n int:=0;travel int;service int;row public.tms_route_schedules;begin
 if not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 if stamp is null or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
 if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
 travel:=(x->>'drive_minutes')::int;service:=(x->>'service_minutes')::int;
 if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric<0 then raise exception 'ROUTE_TIME_REQUIRED';end if;
 minutes:=minutes+travel;km:=km+(x->>'road_km')::numeric;legs:=legs||jsonb_build_array(x||jsonb_build_object('arrival_at',stamp+make_interval(mins=>minutes),'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;
 end loop;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes) values(r.id,stamp,legs,p_data->>'road_source',km,minutes) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,updated_by=auth.uid(),updated_at=now() returning * into row;return to_jsonb(row);
end $$;
revoke all on function private.gama_route_schedule(jsonb) from public,anon;grant execute on function private.gama_route_schedule(jsonb) to authenticated;
create function public.gama_route_schedule(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_route_schedule(p_data)$$;
revoke all on function public.gama_route_schedule(jsonb) from public,anon;grant execute on function public.gama_route_schedule(jsonb) to authenticated;

-- Preferences filter the notification list and its count, never the operations KPIs.
do $$declare src text;begin select pg_get_functiondef('private.gama_operations_core(text,jsonb)'::regprocedure) into src;
 if position('), filtered as (' in src)=0 then raise exception 'NOTIFICATION_FILTER_ANCHOR';end if;
 src:=replace(src,'), filtered as (',$patch$), preferred as (
 select h.* from handled h where not coalesce((p_data->>'respect_preferences')::boolean,false) or (
 not exists(select 1 from public.erp_notification_preferences pref where pref.user_id=auth.uid() and (h.kind=any(pref.hidden_kinds) or (pref.only_mine and h.assigned_to is distinct from auth.uid())))
 and (coalesce(p_data->>'notification_class','all')='all' or (p_data->>'notification_class'='action' and h.priority>=2) or (p_data->>'notification_class'='information' and h.priority<2)))) , filtered as ($patch$);
 src:=replace(src,'select * from handled where','select * from preferred where');src:=replace(src,$p$from handled where handling<>'snoozed'$p$,$p$from preferred where handling<>'snoozed'$p$);src:=replace(src,'from handled group by kind','from preferred group by kind');execute src;
end $$;
