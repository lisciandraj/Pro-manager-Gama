do $patch$
declare src text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 if position('fleet_deadline' in src)>0 then return;end if;
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'fleet_deadline:'||d.alert_key,'fleet_deadline',coalesce(d.vehicle_id,d.driver_id),
  case when d.vehicle_id is not null then 'fleet_vehicle' else 'fleet_driver' end,
  d.subject,coalesce(d.reference,'—'),
  case d.kind when 'licence' then 'Permiso de conducir por caducar'
   when 'document_insurance' then 'Seguro por caducar'
   when 'document_technical_inspection' then 'Inspección técnica por caducar'
   when 'document_registration' then 'Permiso de circulación por caducar'
   when 'service_date' then 'Revisión prevista por fecha'
   when 'service_km' then 'Revisión prevista por kilometraje'
   else 'Vencimiento de flota' end,
  case when d.due_on is not null then 'Vence: '||d.due_on
       else 'Faltan '||d.km_remaining||' km' end,
  coalesce(d.due_on::timestamp at time zone 'America/Guayaquil',now()),
  case when coalesce(d.days_remaining,999)<=7 or coalesce(d.km_remaining,999999)<=200 then 3 else 2 end,
  false,false
 from private.gama_fleet_deadlines d
 where private.gama_fleet_may()
   and ((d.days_remaining is not null and d.days_remaining<=30)
     or (d.km_remaining is not null and d.km_remaining<=1000))
 $extra$;
end $patch$;
