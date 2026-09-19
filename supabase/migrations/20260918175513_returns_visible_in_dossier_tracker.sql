-- El seguimiento de expediente decide lo que enseña preguntando a la tabla de
-- cada documento. Sin rama para return_orders caía en el ELSE false: la
-- devolución existía en el expediente pero nadie la veía.
do $$
declare q text:=pg_get_expr(polqual,polrelid)
 from pg_policy where polrelid='public.gama_document_references'::regclass and polname='dossier_reference_read';
begin
 if position('''customer_returns''::text' in q)=0 then raise exception 'ANCHOR_DOSSIER_POLICY';end if;
 q:=replace(q,'    WHEN ''customer_returns''::text THEN',
  '    WHEN ''return_orders''::text THEN (EXISTS ( SELECT 1'||E'\n'||
  '       FROM return_orders x'||E'\n'||
  '      WHERE (x.id = gama_document_references.document_id)))'||E'\n'||
  '    WHEN ''customer_returns''::text THEN');
 execute 'alter policy dossier_reference_read on public.gama_document_references using ('||q||')';
end $$;
