-- Recibir, reponer y expedir piden una ubicación. La pantalla la trae con el
-- resto de la vista en lugar de consultar la tabla por su cuenta, y se dejan
-- fuera la zona de cuarentena y las de preparación: no son destinos.
do $$
declare src text:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
begin
 if position('   ''suppliers'',coalesce((select jsonb_agg' in src)=0 then raise exception 'ANCHOR_OVERVIEW_TAIL';end if;
 src:=replace(src,'   ''suppliers'',coalesce((select jsonb_agg',
  '   ''locations'',coalesce((select jsonb_agg(jsonb_build_object(''id'',id,''code'',code,''name'',name) order by code)'||E'\n'||
  '     from public.warehouse_locations where active and code<>''RET-QUARANTINE'' and code not like ''PR-%''),''[]''::jsonb),'||E'\n'||
  '   ''suppliers'',coalesce((select jsonb_agg');
 execute src;
end $$;
