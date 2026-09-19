-- La capacidad de carga es del vehículo, no del conductor, así que vive en
-- Flota. El TMS reparte por peso y por volumen: el peso ya estaba en
-- payload_kg, el volumen no existía en ninguna parte.
alter table public.fleet_vehicles
 add column cargo_volume_m3 numeric(8,2) check(cargo_volume_m3>0 and cargo_volume_m3<1000);

-- La carga útil se pedía sólo para camiones porque el PTAC es una noción de
-- camión. Pero una furgoneta que reparte también carga kilos, y el TMS necesita
-- saber cuántos. El PTAC sigue siendo cosa de camiones.
alter table public.fleet_vehicles drop constraint fleet_vehicles_check;
alter table public.fleet_vehicles add constraint fleet_vehicles_gvwr_truck_only
 check(kind='truck' or gvwr_kg is null);

comment on column public.fleet_vehicles.cargo_volume_m3 is
 'Volumen útil de carga en m³. Lo usa el TMS para repartir las entregas.';
comment on column public.fleet_vehicles.payload_kg is
 'Carga útil en kg. Lo usa el TMS para repartir las entregas.';

-- La RPC del módulo tiene que aceptarlos y devolverlos.
do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_fleet_action(text,jsonb)'::regprocedure);
 if position('cargo_volume_m3' in src)>0 then return;end if;

 old:='    gvwr_kg,payload_kg,notes,created_by)';
 if position(old in src)=0 then raise exception 'ANCHOR_INSERT_COLUMNS';end if;
 src:=replace(src,old,'    gvwr_kg,payload_kg,cargo_volume_m3,notes,created_by)');

 old:='    case when p_data->>''kind''=''truck'' then nullif(p_data->>''payload_kg'','''')::numeric end,'||E'\n'||
      '    p_data->>''notes'',u) returning id into eid;';
 if position(old in src)=0 then raise exception 'ANCHOR_INSERT_VALUES';end if;
 src:=replace(src,old,
   '    nullif(p_data->>''payload_kg'','''')::numeric,'||E'\n'||
   '    nullif(p_data->>''cargo_volume_m3'','''')::numeric,'||E'\n'||
   '    p_data->>''notes'',u) returning id into eid;');

 old:='    payload_kg=case when p_data->>''kind''=''truck'' then nullif(p_data->>''payload_kg'','''')::numeric end,';
 if position(old in src)=0 then raise exception 'ANCHOR_UPDATE';end if;
 src:=replace(src,old,
   '    payload_kg=nullif(p_data->>''payload_kg'','''')::numeric,'||E'\n'||
   '    cargo_volume_m3=nullif(p_data->>''cargo_volume_m3'','''')::numeric,');

 old:='     v.odometer,v.status,v.gvwr_kg,v.payload_kg,v.notes,v.active,v.photo is not null as has_photo,';
 if position(old in src)=0 then raise exception 'ANCHOR_LIST';end if;
 src:=replace(src,old,
   '     v.odometer,v.status,v.gvwr_kg,v.payload_kg,v.cargo_volume_m3,v.notes,v.active,v.photo is not null as has_photo,');

 execute src;
end $patch$;

do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_fleet_action2(text,jsonb,date,date,date,uuid,text)'::regprocedure);
 if position('cargo_volume_m3' in src)>0 then return;end if;
 old:='     ''gvwr_kg'',v.gvwr_kg,''payload_kg'',v.payload_kg,''driver'',dr.name,';
 if position(old in src)=0 then raise exception 'ANCHOR_EXPORT';end if;
 execute replace(src,old,
   '     ''gvwr_kg'',v.gvwr_kg,''payload_kg'',v.payload_kg,''cargo_volume_m3'',v.cargo_volume_m3,''driver'',dr.name,');
end $patch$;
