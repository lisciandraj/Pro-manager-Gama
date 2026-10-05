-- Bounded first-party operational measurements; never store form data, document
-- identifiers, tokens, URL queries, error text or network payloads.
create table private.operational_metrics(id bigint generated always as identity primary key,actor uuid not null references public.profiles(id),recorded_at timestamptz not null default now(),metric text not null check(metric in ('rpc','navigation','action')),module text not null,operation text not null,duration_ms integer not null check(duration_ms between 0 and 300000),success boolean not null,device text not null check(device in ('mobile','desktop')),network text not null check(network in ('slow','normal','unknown')));
alter table private.operational_metrics enable row level security;
revoke all on private.operational_metrics from public,anon,authenticated,service_role;
create index operational_metrics_actor_time on private.operational_metrics(actor,recorded_at);
create index operational_metrics_time on private.operational_metrics(recorded_at,module,metric);
create function private.gama_operational_metrics(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;n integer;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.deleted_at is null and p.role in ('administrador','comercial','almacenero')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='record' then
  if jsonb_typeof(p_data->'samples') is distinct from 'array' or jsonb_array_length(p_data->'samples') not between 1 and 50 then raise exception 'INVALID_DATA';end if;
  perform pg_advisory_xact_lock(hashtextextended('metrics:'||auth.uid(),0));
  select count(*) into n from private.operational_metrics where actor=auth.uid() and recorded_at>=now()-interval '1 minute';if n>=1000 then return jsonb_build_object('accepted',0,'limited',true);end if;
  for item in select value from jsonb_array_elements(p_data->'samples') loop
   if item->>'module' !~ '^[a-zA-Z0-9_-]{1,64}$' or item->>'operation' !~ '^[a-zA-Z0-9_-]{0,64}$' then raise exception 'INVALID_DATA';end if;
   insert into private.operational_metrics(actor,metric,module,operation,duration_ms,success,device,network) values(auth.uid(),item->>'metric',item->>'module',item->>'operation',(item->>'duration_ms')::integer,(item->>'success')::boolean,item->>'device',item->>'network');
  end loop;return jsonb_build_object('accepted',jsonb_array_length(p_data->'samples'));
 elsif p_action='report' then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  return jsonb_build_object('as_of',now(),'window_days',7,'rows',(select coalesce(jsonb_agg(to_jsonb(z) order by z.p95_ms desc),'[]') from(select metric,module,operation,device,network,count(*) samples,round((percentile_cont(.95) within group(order by duration_ms))::numeric) p95_ms,round(avg(duration_ms)) average_ms,count(*) filter(where not success) errors from private.operational_metrics where recorded_at>=now()-interval '7 days' group by metric,module,operation,device,network order by count(*) desc limit 200)z));
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_operational_metrics(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_operational_metrics(p_action,p_data)$$;
revoke all on function public.gama_operational_metrics(text,jsonb),private.gama_operational_metrics(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_operational_metrics(text,jsonb),private.gama_operational_metrics(text,jsonb) to authenticated;
create function private.operational_metrics_cleanup() returns void language sql security definer set search_path='' as $$delete from private.operational_metrics where recorded_at<now()-interval '14 days'$$;
revoke all on function private.operational_metrics_cleanup() from public,anon,authenticated,service_role;
select cron.schedule('coco-metrics-retention','25 3 * * *','select private.operational_metrics_cleanup()');
