do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_fleet_action(text,jsonb)'::regprocedure);
 if position('cargo_volume_m3' in src)>0 then return;end if;

 -- alta: la carga útil deja de ser sólo de camión y entra el volumen
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

 -- modificación
 old:='    payload_kg=case when p_data->>''kind''=''truck'' then nullif(p_data->>''payload_kg'','''')::numeric end,';
 if position(old in src)=0 then raise exception 'ANCHOR_UPDATE';end if;
 src:=replace(src,old,
   '    payload_kg=nullif(p_data->>''payload_kg'','''')::numeric,'||E'\n'||
   '    cargo_volume_m3=nullif(p_data->>''cargo_volume_m3'','''')::numeric,');

 -- la lista tiene columnas explícitas para no arrastrar la foto
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
