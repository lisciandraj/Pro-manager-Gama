-- A zero-price sale has no computable percentage margin. Require an explicit
-- approval when a margin floor is configured, just as for a missing cost.
do $$declare name text;src text;old text:='(s.minimum_margin is not null and missing>0)';begin
 foreach name in array array['sales_quote_review','sales_order_review'] loop
  select pg_get_functiondef(to_regprocedure('private.'||name||'(uuid)')) into src;
  if src is null or strpos(src,old)=0 then raise exception 'SALES_ZERO_MARGIN_ANCHOR: %',name;end if;
  execute replace(src,old,'(s.minimum_margin is not null and (missing>0 or revenue<=0))');
 end loop;
end $$;
notify pgrst,'reload schema';
