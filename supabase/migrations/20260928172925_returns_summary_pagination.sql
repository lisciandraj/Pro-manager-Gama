-- Preserve the existing authorization/MFA checks and return actions. Extend
-- only the overview: exact filtered count, stable pagination and credit total.
do $migration$
declare
 src text:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
 row_pos integer; from_pos integer; order_pos integer; matching text;
begin
 row_pos:=strpos(src,'''rows'',coalesce');
 from_pos:=row_pos+strpos(substr(src,row_pos),'from public.return_orders o')-1;
 order_pos:=strpos(src,'order by o.created_at desc limit 200) z)');
 if row_pos=0 or from_pos<row_pos or order_pos<=from_pos then raise exception 'RETURN_SUMMARY_ANCHOR';end if;
 matching:=substr(src,from_pos,order_pos-from_pos);
 src:=replace(src,'''rows'',coalesce','''total'',(select count(*) '||matching||'),'||E'\n   '||'''rows'',coalesce');
 src:=replace(src,'order by o.created_at desc limit 200) z)',
  'order by o.created_at desc,o.id desc limit greatest(1,least(200,coalesce((p_data->>''limit'')::integer,200))) offset greatest(0,coalesce((p_data->>''offset'')::integer,0))) z)');
 src:=replace(src,'to_jsonb(z) order by z.created_at desc','to_jsonb(z) order by z.created_at desc,z.id desc');
 if strpos(src,'exists(select 1 from public.return_credits k where k.return_id=o.id) credited')=0 then raise exception 'RETURN_CREDIT_ANCHOR';end if;
 src:=replace(src,'exists(select 1 from public.return_credits k where k.return_id=o.id) credited',
  '(select coalesce(sum(k.amount),0) from public.return_credits k where k.return_id=o.id) credited_amount, exists(select 1 from public.return_credits k where k.return_id=o.id) credited');
 execute src;
end $migration$;
notify pgrst,'reload schema';
