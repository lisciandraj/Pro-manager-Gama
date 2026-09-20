alter table private.gama_alert_handling add column next_action text not null default '' check(length(next_action)<=500),add column due_at timestamptz,add column root_cause text not null default '' check(length(root_cause)<=1000);
create table public.erp_notification_preferences(user_id uuid primary key default auth.uid() references auth.users(id),hidden_kinds text[] not null default '{}',only_mine boolean not null default false,updated_at timestamptz not null default now());
alter table public.erp_notification_preferences enable row level security;
revoke all on public.erp_notification_preferences from public,anon,authenticated;
grant select,insert,update on public.erp_notification_preferences to authenticated;
create policy own_preferences on public.erp_notification_preferences for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create table private.erp_alert_state(alert_key text primary key,fingerprint text not null,finance_only boolean not null,warehouse_only boolean not null,active boolean not null default true,changed_at timestamptz not null default now());
alter table private.erp_alert_state enable row level security;
revoke all on private.erp_alert_state from public,anon,authenticated;
-- Business exceptions keep one stable identity across both screens.
do $$declare src text:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');begin
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'crm_stale:'||o.id,'crm_stale',o.id,'opportunity',o.reference,coalesce(c.name,o.title),'Oportunidad sin próxima acción',
  'Responsable: '||coalesce(p.full_name,'Sin asignar')||' · Última actividad: '||o.updated_at::date,
  o.updated_at,2,true,false from public.crm_opportunities o left join public.customers c on c.id=o.customer_id left join public.profiles p on p.id=o.owner_id
 where o.active and o.won_at is null and o.lost_at is null and
 (o.updated_at<now()-make_interval(days=>(select stale_opportunity_days from public.erp_policies where id)) or not exists(select 1 from public.crm_activities a where a.opportunity_id=o.id and a.status in ('pendiente','en_curso') and a.due_at>=now()))
 union all
 select 'service_late:'||s.id,'service_late',s.id,'service',coalesce(s.erp_reference,'SAV-'||s.number),coalesce(c.name,''),'SAV fuera de plazo',s.subject,s.due_date::timestamptz,3,true,false
 from public.service_tickets s left join public.customers c on c.id=s.customer_id where not s.archived and s.status not in ('resolved','closed') and s.due_date<current_date
 $extra$;end $$;
-- Preserve the established metrics and alert computation; extend handling atomically.
alter function private.gama_operations_action(text,jsonb) rename to gama_operations_core;
revoke all on function private.gama_operations_core(text,jsonb) from public,anon,authenticated;
create function private.gama_operations_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r text:=private.current_user_role();result jsonb;x record;live record;fin boolean;wh boolean;owner uuid;prefs jsonb;begin
 if auth.uid() is null or r not in ('administrador','comercial','almacenero') or not(private.erp_module_allowed('operations',array['administrador','comercial','almacenero']) or private.erp_module_allowed('notifications',array['administrador','comercial','almacenero'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 fin:=r in ('administrador','comercial');wh:=r in ('administrador','almacenero');
 if p_action='history' then
  if not exists(select 1 from private.erp_alert_state where alert_key=p_data->>'key' and (not finance_only or fin) and (not warehouse_only or wh)) then raise exception 'ALERT_NOT_FOUND';end if;
  return(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from(select e.id,e.action,e.note,e.created_at,p.full_name actor from private.gama_alert_events e left join public.profiles p on p.id=e.actor where e.alert_key=p_data->>'key' order by e.id desc limit 100)e);
 elsif p_action='handle' then
  result:=private.gama_operations_core(p_action,p_data);
  owner:=coalesce(nullif(p_data->>'assigned_to','')::uuid,auth.uid());
  if not exists(select 1 from public.profiles p where p.id=owner and p.active and p.role in ('administrador','comercial','almacenero')) then raise exception 'ASSIGNEE_REQUIRED';end if;
  update private.gama_alert_handling set next_action=coalesce(p_data->>'next_action',next_action),root_cause=coalesce(p_data->>'root_cause',root_cause),due_at=nullif(p_data->>'due_at','')::timestamptz,assigned_to=case when p_data->>'status'='open' then null else owner end where alert_key=p_data->>'key';
  update private.gama_alert_events set note=concat_ws(E'\n',note,p_data->>'next_action',p_data->>'root_cause',p_data->>'due_at') where id=(select max(id) from private.gama_alert_events where alert_key=p_data->>'key' and actor=auth.uid());
  return result;
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 if coalesce((p_data->>'track')::boolean,false) then
 -- Resolution/reopening is observed from the underlying record, never by dismissing a card.
 for x in select * from private.erp_alert_state where (not finance_only or fin) and (not warehouse_only or wh) and active and not exists(select 1 from private.gama_live_alerts a where a.alert_key=erp_alert_state.alert_key) for update loop
  update private.erp_alert_state set active=false,changed_at=now() where alert_key=x.alert_key;
  insert into private.gama_alert_events(alert_key,fingerprint,action,note,actor) values(x.alert_key,x.fingerprint,'resolved','Causa resuelta en el documento de origen',auth.uid());
 end loop;
 for live in select a.*,md5(a.kind||coalesce(a.detail,'')||coalesce(a.since::text,'')) fingerprint from private.gama_live_alerts a where (not a.finance_only or fin) and (not a.warehouse_only or wh) loop
  select * into x from private.erp_alert_state where alert_key=live.alert_key for update;
  if found and not x.active then insert into private.gama_alert_events(alert_key,fingerprint,action,note,actor) values(live.alert_key,live.fingerprint,'reopened','La causa vuelve a estar activa',auth.uid());end if;
  insert into private.erp_alert_state(alert_key,fingerprint,finance_only,warehouse_only) values(live.alert_key,live.fingerprint,live.finance_only,live.warehouse_only)
   on conflict(alert_key) do update set fingerprint=excluded.fingerprint,active=true;
 end loop;
 end if;
 result:=private.gama_operations_core('snapshot',p_data);
 select coalesce(jsonb_agg(a.value||jsonb_build_object('next_action',h.next_action,'root_cause',h.root_cause,'due_at',h.due_at,'escalated',coalesce(h.due_at<now() or (h.assigned_to is null and (a.value->>'since')::timestamptz<now()-make_interval(days=>(select escalation_days from public.erp_policies where id))),false)) order by a.n),'[]') into prefs
 from jsonb_array_elements(result->'alerts') with ordinality a(value,n) left join private.gama_alert_handling h on h.alert_key=a.value->>'alert_key';
 result:=jsonb_set(result,'{alerts}',prefs);
 return result;
end $$;
revoke all on function private.gama_operations_action(text,jsonb) from public,anon;
grant execute on function private.gama_operations_action(text,jsonb) to authenticated;
create or replace function public.gama_operations_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_operations_action(p_action,p_data)$$;
