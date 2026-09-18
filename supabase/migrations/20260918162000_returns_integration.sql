-- Integración de Devoluciones con lo que ya existía, y retirada de lo que
-- sustituye. GAMA tenía customer_returns, customer_return_credits y
-- customer_return_photos, con la mecánica de almacén resuelta dentro de
-- gama_fulfillment_action pero sin cabecera de documento, sin varias líneas por
-- devolución, sin lado proveedor, sin reembolsos y sin pantalla propia: vivía
-- enterrado en el dossier del pedido. Estaban vacías, así que en vez de dejar
-- dos sistemas conviviendo se reordenan en uno solo.

-- ------------------------------------------- el expediente enseña la devolución
-- El seguimiento decide lo que muestra preguntando a la tabla de cada
-- documento. Sin rama para return_orders caía en el ELSE false: la devolución
-- estaba en el expediente pero nadie la veía.
do $mig$
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
end $mig$;

-- ------------------------------------------- se retiran las acciones antiguas
do $mig$
declare
 src text:=pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure);
 lines text[]; ln text; out text:=''; i int; state text:='';
 seen_actions boolean:=false; seen_photo boolean:=false; seen_reads int:=0;
begin
 select array_agg(line order by n) into lines
  from regexp_split_to_table(src,E'\n') with ordinality as t(line,n);

 for i in 1..array_length(lines,1) loop
  ln:=lines[i];

  if state='' and ln=' elsif p_action=''request_return'' then' then
   state:='actions';seen_actions:=true;
  end if;
  if state='actions' then
   if ln='  end if;eid:=rt.id;' then state:='';end if;
   continue;
  end if;

  if state='' and ln=' if p_action=''photo'' then' then state:='photo';seen_photo:=true;end if;
  if state='photo' then
   if ln=' end if;' then state:='';end if;
   continue;
  end if;

  if ln like '   ''returns'',coalesce(%' or ln like '   ''photos'',coalesce(%'
   or ln like '   ''credits'',case when role_name%customer_return_credits%' then
   seen_reads:=seen_reads+1;continue;
  end if;

  ln:=replace(ln,'rt public.customer_returns;','');
  ln:=replace(ln,'p_action not in (''dossier'',''photo'')','p_action<>''dossier''');
  ln:=replace(ln,',''receive_return'',''inspect_return''','');

  out:=out||ln||E'\n';
 end loop;

 if not seen_actions then raise exception 'ANCHOR_RETURN_ACTIONS';end if;
 if not seen_photo then raise exception 'ANCHOR_RETURN_PHOTO';end if;
 if seen_reads<>3 then raise exception 'ANCHOR_RETURN_READS_%',seen_reads;end if;
 if position('customer_return' in out)>0 then raise exception 'LEGACY_RETURN_LEFTOVER';end if;
 execute out;
end $mig$;

-- ------------------------------------------------- catálogo del Asistente IA
-- El Asistente lee el catálogo, no tablas nuevas. Las columnas con adjuntos
-- (data_url) se quedan fuera, como en el resto del catálogo.
do $mig$
declare src text:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure); before int;
begin
 before:=length(src);
 src:=replace(src,'{"table":"customer_return_credits","columns":["id","return_id","invoice_id","number","amount","notes","created_by","created_at"],"pk":["id"],"module":"sales-orders"},','');
 src:=replace(src,'{"table":"customer_return_photos","columns":["id","return_id","filename","created_at"],"pk":["id"],"module":"sales-orders"},','');
 src:=replace(src,'{"table":"customer_returns","columns":["id","number","order_id","delivery_line_id","quantity","reason","status","quarantine_location_id","hold_reservation_id","replacement_order_id","inspection_notes","received_at","closed_at","created_by","created_at"],"pk":["id"],"module":"sales-orders"},','');
 if length(src)>=before then raise exception 'ANCHOR_AI_LEGACY_RETURNS';end if;

 before:=length(src);
 src:=replace(src,'{"table":"sales_deliveries","columns":["id","number","order_id"',
  '{"table":"return_orders","columns":["id","number","kind","status","customer_id","order_id","delivery_id","invoice_id","supplier_id","purchase_order_id","supplier_invoice_id","reason","notes","financial_action","carrier","tracking","shipped_on","received_at","processed_at","closed_at","created_by","created_at","updated_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"return_lines","columns":["id","return_id","product_id","quantity","unit_price","tax_rate","delivery_line_id","purchase_order_line_id","disposition","processed_at","notes","created_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"return_credits","columns":["id","number","return_id","invoice_id","supplier_invoice_id","supplier_reference","amount","issued_on","notes","created_by","created_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"return_refunds","columns":["id","return_id","amount","paid_at","method","reference","notes","created_by","created_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"sales_deliveries","columns":["id","number","order_id"');
 if length(src)<=before then raise exception 'ANCHOR_AI_INSERT';end if;
 execute src;
end $mig$;

-- ------------------------------------------------- y se retiran las tablas
do $guard$
begin
 if (select count(*) from public.customer_returns)>0
  or (select count(*) from public.customer_return_credits)>0
  or (select count(*) from public.customer_return_photos)>0 then
  raise exception 'RETURNS_LEGACY_NOT_EMPTY: hay devoluciones antiguas, hay que migrarlas antes';
 end if;
end $guard$;

do $mig$
declare q text:=pg_get_expr(polqual,polrelid)
 from pg_policy where polrelid='public.gama_document_references'::regclass and polname='dossier_reference_read';
 src text:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
begin
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

alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
alter table public.gama_document_references add constraint gama_document_references_table_name_check
 check(table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations',
  'fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices',
  'external_invoice_payments','return_orders'));
