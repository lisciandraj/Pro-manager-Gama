-- El historial de stock ya tiene su vocabulario: return_in y return_out. Se
-- usa ése en vez de inventar tipos nuevos; el detalle humano va en «reason»,
-- que es donde el almacenero lo lee.
do $patch$
declare src text;
begin
 src:=pg_get_functiondef('private.gama_returns_action3(text,jsonb,jsonb,date)'::regprocedure);
 if position('return_restock' in src)=0 and position('supplier_return''' in src)=0 then return;end if;
 src:=replace(src,'''return_restock''','''return_in''');
 src:=replace(src,'case when p_data->>''disposition''=''scrapped'' then ''return_scrap'' else ''return_to_supplier'' end','''return_out''');
 src:=replace(src,'loc.id,''supplier_return'',''supplier_return''','loc.id,''return_out'',''supplier_return''');
 execute src;
end $patch$;
