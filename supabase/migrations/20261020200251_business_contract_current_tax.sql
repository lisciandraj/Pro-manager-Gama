-- Contract prices may be fixed; product tax belongs to the newly prepared order.
-- Preserve the checked sales gateway and historical orders.
do $patch$ declare body text;needle text:='jsonb_build_object(''price_mode'',case when s.price_mode=';begin
 select pg_get_functiondef('private.contract_generate(uuid,date,boolean)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'CONTRACT_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,'jsonb_build_object(''tax_rate'',(select p.tax_rate from public.products p where p.id=(x->>''product_id'')::uuid),''price_mode'',case when s.price_mode=');
 execute body;
end $patch$;
