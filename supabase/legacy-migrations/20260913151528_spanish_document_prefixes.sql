-- Translate canonical ERP prefixes without changing dossier numbers or ordinals.
do $$
declare src text;old_prefix text;new_prefix text;
begin
 perform pg_advisory_xact_lock(724613092);
 select pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure) into src;
 for old_prefix,new_prefix in select * from (values('DEM','SOL'),('DEV','COT'),('CMD','PED'),('COL','PAQ'),('EXP','ENV'),('LIV','ENT'),('POD','PDE'),('PAY','COB'),('RET','DEV')) x(a,b) loop
  if position('then '||quote_literal(old_prefix) in src)=0 then raise exception 'Unexpected reference prefix: %',old_prefix;end if;
  src:=replace(src,'then '||quote_literal(old_prefix),'then '||quote_literal(new_prefix));
 end loop;
 execute src;
 update public.gama_document_references set document_reference=
  (case table_name when 'customer_requests' then 'SOL' when 'invoices' then 'COT' when 'sales_orders' then 'PED' when 'fulfillment_preparations' then 'PREP' when 'fulfillment_packages' then 'PAQ' when 'sales_deliveries' then 'ENV' when 'tms_deliveries' then 'ENT' when 'tms_proofs' then 'PDE' when 'external_invoices' then 'FAC' when 'external_invoice_payments' then 'COB' when 'customer_returns' then 'DEV' end)
  ||case when ordinal>1 then '-'||private.gama_reference_letters(ordinal) else '' end||'-'||lpad(dossier_number::text,8,'0');
end $$;
