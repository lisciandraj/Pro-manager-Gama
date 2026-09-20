-- La variable local «amount» chocaba con la columna del mismo nombre en las
-- subconsultas del retorno. Se califican por alias.
do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_returns_action4(text,jsonb,jsonb,date)'::regprocedure);
 old:='  return jsonb_build_object(''id'',eid,''amount'',amount,'||E'\n'||
      '   ''refunded'',(select coalesce(sum(amount),0) from public.return_refunds where return_id=o.id),'||E'\n'||
      '   ''outstanding'',total-(select coalesce(sum(amount),0) from public.return_refunds where return_id=o.id));';
 if position(old in src)=0 then raise exception 'ANCHOR_REFUND_RETURN';end if;
 execute replace(src,old,
  '  return jsonb_build_object(''id'',eid,''amount'',amount,'||E'\n'||
  '   ''refunded'',(select coalesce(sum(f2.amount),0) from public.return_refunds f2 where f2.return_id=o.id),'||E'\n'||
  '   ''outstanding'',total-(select coalesce(sum(f3.amount),0) from public.return_refunds f3 where f3.return_id=o.id));');
end $patch$;
