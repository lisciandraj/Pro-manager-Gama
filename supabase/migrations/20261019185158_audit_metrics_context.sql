begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
do $$begin if md5(pg_get_functiondef('private.gama_operational_metrics(text,jsonb)'::regprocedure))<>'bdcd67ccd3f722146e0c355d3879bf34' then raise exception 'AUDIT_METRICS_DEFINITION_CHANGED';end if;end $$;
alter table private.operational_metrics
 add column build_id text not null default 'unknown',
 add column display_mode text not null default 'unknown',
 add column browser_family text not null default 'unknown',
 add column cache_state text not null default 'unknown',
 add column device_source text not null default 'viewport',
 add column visit_id uuid,
 add column metric_id text,
 add column value numeric;
alter table private.operational_metrics drop constraint operational_metrics_metric_check;
alter table private.operational_metrics add constraint operational_metrics_metric_check check(metric in ('rpc','navigation','action','vital'));
-- Web Vitals can report again on pagehide. Replace that visit's measurement.
create unique index operational_metrics_vital_once on private.operational_metrics(actor,visit_id,metric_id,operation) where metric='vital';
create or replace function private.gama_operational_metrics(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb;n integer;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.deleted_at is null and p.role in ('administrador','comercial','almacenero')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='record' then
  if jsonb_typeof(p_data->'samples') is distinct from 'array' or jsonb_array_length(p_data->'samples') not between 1 and 50 or octet_length(p_data::text)>64000 then raise exception 'INVALID_DATA';end if;
  perform pg_advisory_xact_lock(hashtextextended('metrics:'||auth.uid(),0));
  select count(*) into n from private.operational_metrics where actor=auth.uid() and recorded_at>=now()-interval '1 minute';if n+jsonb_array_length(p_data->'samples')>1000 then return jsonb_build_object('accepted',0,'limited',true);end if;
  for item in select value from jsonb_array_elements(p_data->'samples') loop
   if coalesce(item->>'module','')!~'^[a-zA-Z0-9_-]{1,64}$' or coalesce(item->>'operation','')!~'^[a-zA-Z0-9_-]{0,64}$'
    or coalesce(item->>'build_id','unknown')!~'^(unknown|[a-f0-9]{40})$'
    or coalesce(item->>'display_mode','unknown') not in ('unknown','browser','pwa')
    or coalesce(item->>'browser_family','unknown') not in ('unknown','chromium','safari','firefox','edge')
    or coalesce(item->>'cache_state','unknown') not in ('unknown','first_visit','return_visit')
    or coalesce(item->>'device_source','viewport')<>'viewport' then raise exception 'INVALID_DATA';end if;
   if item->>'metric'='vital' and (item->>'operation' not in ('LCP','INP','CLS') or item->>'visit_id' is null or coalesce(item->>'metric_id','')!~'^[a-zA-Z0-9_-]{1,100}$' or coalesce((item->>'value')::numeric,-1) not between 0 and 300000) then raise exception 'INVALID_DATA';end if;
   insert into private.operational_metrics(actor,metric,module,operation,duration_ms,success,device,network,build_id,display_mode,browser_family,cache_state,device_source,visit_id,metric_id,value)
    values(auth.uid(),item->>'metric',item->>'module',item->>'operation',(item->>'duration_ms')::integer,(item->>'success')::boolean,item->>'device',item->>'network',coalesce(item->>'build_id','unknown'),coalesce(item->>'display_mode','unknown'),coalesce(item->>'browser_family','unknown'),coalesce(item->>'cache_state','unknown'),'viewport',(item->>'visit_id')::uuid,item->>'metric_id',case when item->>'metric'='vital' then (item->>'value')::numeric end)
    on conflict(actor,visit_id,metric_id,operation) where metric='vital' do update set value=excluded.value,duration_ms=excluded.duration_ms,recorded_at=now();
  end loop;return jsonb_build_object('accepted',jsonb_array_length(p_data->'samples'));
 elsif p_action='report' then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  return jsonb_build_object('as_of',now(),'window_days',7,'rows',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(
   select metric,module,operation,device,network,build_id,display_mode,browser_family,cache_state,count(*) samples,
    case when metric<>'vital' then round((percentile_cont(.5) within group(order by duration_ms))::numeric) end median_ms,
    case when metric<>'vital' and count(*)>=100 then round((percentile_cont(.95) within group(order by duration_ms))::numeric) end p95_ms,
    case when metric='vital' and count(*)>=20 then (percentile_cont(.75) within group(order by value)) end p75_value,
    case when operation='CLS' and metric='vital' then 'score' else 'ms' end unit,
    round(avg(duration_ms)) average_ms,count(*) filter(where not success) errors
   from private.operational_metrics where recorded_at>=now()-interval '7 days'
   group by metric,module,operation,device,network,build_id,display_mode,browser_family,cache_state order by count(*) desc limit 200)z));
 end if;raise exception 'INVALID_ACTION';
end $$;
notify pgrst,'reload schema';
commit;
