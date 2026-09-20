-- La variable local «kind» chocaba con la columna del mismo nombre en la
-- consulta de la lista: el filtro por tipo tumbaba la pantalla principal.
do $$
declare src text:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
begin
 if position(' kind text:=nullif(p_data->>''kind'','''');' in src)=0 then raise exception 'ANCHOR_KIND_DECL';end if;
 if position('where (kind is null or o.kind=kind)' in src)=0 then raise exception 'ANCHOR_KIND_FILTER';end if;
 src:=replace(src,' kind text:=nullif(p_data->>''kind'','''');',' p_kind text:=nullif(p_data->>''kind'','''');');
 src:=replace(src,'where (kind is null or o.kind=kind)','where (p_kind is null or o.kind=p_kind)');
 execute src;
end $$;
