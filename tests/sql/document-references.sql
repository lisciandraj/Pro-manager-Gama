-- Ejecutar dentro de BEGIN/ROLLBACK. Comprueba que la numeración de
-- expedientes avanza de uno en uno.
--
-- La regresión que cubre: nextval() se evaluaba dentro de un
-- «insert ... on conflict do nothing», y como se evalúa ANTES de comprobar el
-- conflicto, gastaba un número aunque no se insertara nada. Con el disparador
-- en AFTER INSERT OR UPDATE, cada edición de cualquier documento de la cadena
-- quemaba números: de SOL-00001196 se pasó a SOL-00001244.
do $$
#variable_conflict use_column
<<reference_test>>
declare
 admin_id uuid; cid uuid; r uuid; o uuid;
 seq0 bigint; n bigint; prev bigint; i integer; j integer; gastado bigint;
begin
 select id into admin_id from public.profiles where role='administrador' and active limit 1;
 if admin_id is null then raise exception 'FAIL_SIN_ADMINISTRADOR'; end if;
 insert into public.customers(name,address) values('Referencias test','Quito') returning id into cid;

 seq0:=(select last_value from private.gama_dossier_sequence);
 prev:=seq0;

 -- Cinco solicitudes seguidas. Cada una se edita cuatro veces y arrastra un
 -- pedido que a su vez se edita tres: el caso que disparaba la numeración.
 for i in 1..5 loop
  insert into public.customer_requests(customer_id,status,total)
   values(cid,'pending',0) returning id into r;
  select dossier_number into n from public.gama_document_references
   where table_name='customer_requests' and document_id=r;
  if n is null then raise exception 'FAIL_SIN_EXPEDIENTE en la %',i; end if;
  if n<>prev+1 then raise exception 'FAIL_SALTO en la %: % -> % (se esperaba +1)',i,prev,n; end if;

  for j in 1..4 loop update public.customer_requests set notes='e'||j where id=r; end loop;
  if (select last_value from private.gama_dossier_sequence)<>n then
   raise exception 'FAIL_EDITAR_GASTA_NUMERO en la %',i; end if;

  insert into public.sales_orders(number,request_key,customer_id,customer_name,delivery_address,status,source_request_id,created_by)
   values('REF-'||i,gen_random_uuid(),cid,'Referencias test','Quito','draft',r,admin_id) returning id into o;
  -- El pedido nace de la solicitud: entra en SU expediente, no abre otro.
  if (select dossier_number from public.gama_document_references
      where table_name='sales_orders' and document_id=o)<>n then
   raise exception 'FAIL_EL_PEDIDO_ABRIO_OTRO_EXPEDIENTE en la %',i; end if;
  if (select last_value from private.gama_dossier_sequence)<>n then
   raise exception 'FAIL_EL_PEDIDO_GASTA_NUMERO en la %',i; end if;

  for j in 1..3 loop update public.sales_orders set notes='f'||j where id=o; end loop;
  if (select last_value from private.gama_dossier_sequence)<>n then
   raise exception 'FAIL_EDITAR_EL_PEDIDO_GASTA en la %',i; end if;

  -- Y la referencia del pedido comparte el número de la solicitud.
  if (select document_reference from public.gama_document_references
      where table_name='sales_orders' and document_id=o)<>'PED-'||lpad(n::text,8,'0') then
   raise exception 'FAIL_REFERENCIA_DEL_PEDIDO en la %',i; end if;
  if (select document_reference from public.gama_document_references
      where table_name='customer_requests' and document_id=r)<>'SOL-'||lpad(n::text,8,'0') then
   raise exception 'FAIL_REFERENCIA_DE_LA_SOLICITUD en la %',i; end if;

  prev:=n;
 end loop;

 gastado:=(select last_value from private.gama_dossier_sequence)-seq0;
 if gastado<>5 then raise exception 'FAIL_TOTAL: cinco solicitudes gastaron % números',gastado; end if;
 raise notice 'OK: % -> %, exactamente +5 en cinco solicitudes',seq0,prev;
end $$;
