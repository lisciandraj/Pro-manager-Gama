
create function public.gama_tms_routing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_routing(p_action,p_data)$$;
revoke all on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) to authenticated;

-- Only the authenticated Edge adapter may store a matrix. No client-supplied
-- matrix can become a trusted distance/time source.
create function private.tms_routing_commit(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m private.tms_routing_matrices;n integer;i integer;j integer;km jsonb;seconds jsonb;begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into m from private.tms_routing_matrices where day=(p_data->>'day')::date and lease=(p_data->>'lease')::uuid and actor_id=(p_data->>'actor_id')::uuid for update;
 if not found or m.state<>'pending' or m.requested_at<now()-interval '2 minutes' then raise exception 'ROAD_MATRIX_STALE';end if;
 if p_data->>'error'='ROAD_PROVIDER_UNAVAILABLE' then
  update private.tms_routing_matrices set state='failed',error_code='ROAD_PROVIDER_UNAVAILABLE' where day=m.day;return jsonb_build_object('stored',false);
 end if;
 if m.points<>private.tms_routing_points(m.day) then raise exception 'ROAD_MATRIX_STALE';end if;
 n:=jsonb_array_length(m.points);
 if jsonb_typeof(p_data->'distances') is distinct from 'array' or jsonb_typeof(p_data->'durations') is distinct from 'array' or jsonb_array_length(p_data->'distances')<>n or jsonb_array_length(p_data->'durations')<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
 for i in 0..n-1 loop
  if jsonb_typeof(p_data->'distances'->i) is distinct from 'array' or jsonb_typeof(p_data->'durations'->i) is distinct from 'array' or jsonb_array_length(p_data->'distances'->i)<>n or jsonb_array_length(p_data->'durations'->i)<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
  for j in 0..n-1 loop
   km:=p_data->'distances'->i->j;seconds:=p_data->'durations'->i->j;
   if not ((km='null'::jsonb and seconds='null'::jsonb and i<>j) or (jsonb_typeof(km)='number' and jsonb_typeof(seconds)='number' and km::text::numeric between 0 and 20000 and seconds::text::numeric between 0 and 604800 and (i<>j or (km='0'::jsonb and seconds='0'::jsonb)))) then raise exception 'ROAD_RESPONSE_INVALID';end if;
   insert into private.tms_routing_pairs(day,a_lat,a_lng,b_lat,b_lng,km,seconds) values(m.day,(m.points->i->>1)::numeric,(m.points->i->>0)::numeric,(m.points->j->>1)::numeric,(m.points->j->>0)::numeric,(km#>>'{}')::double precision,(seconds#>>'{}')::double precision);
  end loop;
 end loop;
 update private.tms_routing_matrices set state='ready',measured_at=now(),expires_at=now()+interval '24 hours',error_code=null where day=m.day;
 delete from private.tms_day_plans where day=m.day;
 return jsonb_build_object('stored',true,'locations',n,'expires_at',now()+interval '24 hours');
end $$;
create function public.gama_tms_routing_commit(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.tms_routing_commit(p_data)$$;
revoke all on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) from public,anon,authenticated;
grant execute on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) to service_role;
-- Private cache expiry is enforced on reads even if cleanup is delayed.
select cron.schedule('coco-tms-routing-retention','17 3 * * *',$cron$delete from private.tms_routing_matrices where requested_at<now()-interval '48 hours'$cron$);
do $$declare p record;begin for p in select oid::regprocedure sig from pg_proc where pronamespace='private'::regnamespace and proname in ('tms_routing_points','tms_routing_covers','tms_routing_begin','tms_routing_evaluate','tms_routing_improve') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',p.sig);end loop;end $$;

-- The 100-stop isolated benchmark exceeds the default API role's 8 s on WASM.
-- Bound only these authorized operations; retain all global/role timeouts.
alter function public.gama_tms_plan_day(date) set statement_timeout='30s';
alter function public.gama_tms_plan_day() set statement_timeout='30s';
alter function public.gama_tms_routing_commit(jsonb) set statement_timeout='30s';
notify pgrst, 'reload schema';
