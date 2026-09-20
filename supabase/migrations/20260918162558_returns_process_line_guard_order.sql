-- Procesar dos veces la misma línea ya estaba bloqueado, pero saltaba primero
-- el guardián de estado y el usuario leía «no recibido» cuando lo cierto es
-- que esa línea ya estaba tratada. Se mira la línea antes que el documento.
do $patch$
declare src text;old text;new text;
begin
 src:=pg_get_functiondef('private.gama_returns_action3(text,jsonb,jsonb,date)'::regprocedure);
 old:='  if o.status<>''received'' then raise exception ''NOT_RECEIVED'';end if;'||E'\n'||
      '  select * into l from public.return_lines where id=(p_data->>''line_id'')::uuid and return_id=o.id for update;'||E'\n'||
      '  if not found then raise exception ''INVALID_LINE'';end if;';
 if position(old in src)=0 then raise exception 'ANCHOR_GUARDS';end if;
 new:='  select * into l from public.return_lines where id=(p_data->>''line_id'')::uuid and return_id=o.id for update;'||E'\n'||
      '  if not found then raise exception ''INVALID_LINE'';end if;'||E'\n'||
      '  if l.processed_at is not null then raise exception ''LINE_ALREADY_PROCESSED'';end if;'||E'\n'||
      '  if o.status<>''received'' then raise exception ''NOT_RECEIVED'';end if;';
 src:=replace(src,old,new);
 -- y se retira la comprobación duplicada que quedaba más abajo
 old:='  if l.processed_at is not null then raise exception ''LINE_ALREADY_PROCESSED'';end if;'||E'\n'||
      '  if p_data->>''disposition'' not in';
 if position(old in src)=0 then raise exception 'ANCHOR_DUP';end if;
 execute replace(src,old,'  if p_data->>''disposition'' not in');
end $patch$;
