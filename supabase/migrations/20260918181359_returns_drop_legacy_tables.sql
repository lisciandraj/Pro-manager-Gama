-- Las tres tablas antiguas ya no tienen ni escritura ni lectura. Estaban
-- vacías; se comprueba una última vez antes de retirarlas.
do $guard$
begin
 if (select count(*) from public.customer_returns)>0
  or (select count(*) from public.customer_return_credits)>0
  or (select count(*) from public.customer_return_photos)>0 then
  raise exception 'RETURNS_LEGACY_NOT_EMPTY: hay devoluciones antiguas, hay que migrarlas antes';
 end if;
end $guard$;

-- El seguimiento de expediente y el registro de documentos dejan de conocerlas.
do $mig$
declare q text:=pg_get_expr(polqual,polrelid)
 from pg_policy where polrelid='public.gama_document_references'::regclass and polname='dossier_reference_read';
 src text:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
begin
 if position('''customer_returns''::text' in q)=0 then raise exception 'ANCHOR_DOSSIER_POLICY';end if;
 q:=regexp_replace(q,'\s*WHEN ''customer_returns''::text THEN \(EXISTS \( SELECT 1\s+FROM customer_returns x\s+WHERE \(x\.id = gama_document_references\.document_id\)\)\)','');
 if position('customer_returns' in q)>0 then raise exception 'DOSSIER_POLICY_LEFTOVER';end if;
 execute 'alter policy dossier_reference_read on public.gama_document_references using ('||q||')';

 if position('when ''customer_returns'' then edges' in src)=0 then raise exception 'ANCHOR_REGISTER_EDGES';end if;
 src:=replace(src,'  when ''customer_returns'' then edges:=jsonb_build_array(jsonb_build_array(''sales_orders'',j->>''order_id''));'||E'\n','');
 src:=replace(src,'when ''customer_returns'' then ''DEV'' ','');
 if position('customer_returns' in src)>0 then raise exception 'REGISTER_LEFTOVER';end if;
 execute src;
end $mig$;

delete from public.gama_document_references where table_name='customer_returns';
drop table public.customer_return_photos;
drop table public.customer_return_credits;
drop table public.customer_returns;
