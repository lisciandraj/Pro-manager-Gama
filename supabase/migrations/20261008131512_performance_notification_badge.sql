-- The bell needs only the authorized active count, not dashboard KPIs or 50 dossiers.
-- Keep the existing authentication, MFA, module and role gates in the wrapper.
do $migration$
declare src text;anchor text:=$anchor$ if p_action='history' then$anchor$;
begin
 select pg_get_functiondef('private.gama_operations_action(text,jsonb)'::regprocedure) into src;
 if position($guard$'badge'$guard$ in src)>0 then return;end if;
 if position(anchor in src)=0 then raise exception 'NOTIFICATION_BADGE_ANCHOR';end if;
 src:=replace(src,anchor,$patch$ if p_action='badge' then
  return (
   select jsonb_build_object('active_count',count(*),'generated_at',now())
   from private.gama_live_alerts l
   left join private.gama_alert_handling h on h.alert_key=l.alert_key
    and h.fingerprint=md5(l.kind||coalesce(l.detail,'')||coalesce(l.since::text,''))
   where (not l.finance_only or fin) and (not l.warehouse_only or wh)
    and (case when h.status='snoozed' and h.snoozed_until<=now() then 'open' else coalesce(h.status,'open') end)<>'snoozed'
    and (not coalesce((p_data->>'respect_preferences')::boolean,false) or (
     not exists(select 1 from public.erp_notification_preferences pref where pref.user_id=auth.uid()
      and (l.kind=any(pref.hidden_kinds) or (pref.only_mine and h.assigned_to is distinct from auth.uid())))
     and (coalesce(p_data->>'notification_class','all')='all'
      or (p_data->>'notification_class'='action' and l.priority>=2)
      or (p_data->>'notification_class'='information' and l.priority<2)))));
 elsif p_action='history' then$patch$);
 execute src;
end $migration$;
