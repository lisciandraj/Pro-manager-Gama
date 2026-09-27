-- Register the shipment and its transport delivery together, BEFORE issuing
-- either reference. Previously ENT opened an unrelated dossier; merging it
-- afterwards could not change its already issued (immutable) reference.
-- No client-supplied process number or mutable session setting is trusted.
do $migration$
declare source text;old_insert text;new_insert text;
begin
 source:=pg_get_functiondef('private.gama_sales_action_before_fulfillment(text,jsonb)'::regprocedure);
 old_insert:=$old$  insert into public.tms_deliveries(customer,customer_id,address,delivery_date,notes,created_by)
  values(o.customer_name,o.customer_id,o.delivery_address,coalesce((p_data->>'delivery_date')::date,current_date),o.number||' · '||coalesce(p_data->>'notes',''),u) returning id into tid;
  insert into public.sales_deliveries(order_id,request_key,tms_delivery_id,notes,created_by)
   values(oid,key_id,tid,coalesce(p_data->>'notes',''),u) returning id into eid;$old$;
 new_insert:=$new$  eid:=gen_random_uuid();tid:=gen_random_uuid();
  perform private.gama_register_document('sales_deliveries',jsonb_build_object('id',eid,'order_id',oid,'tms_delivery_id',tid));
  insert into public.tms_deliveries(id,customer,customer_id,address,delivery_date,notes,created_by)
  values(tid,o.customer_name,o.customer_id,o.delivery_address,coalesce((p_data->>'delivery_date')::date,current_date),o.number||' · '||coalesce(p_data->>'notes',''),u);
  insert into public.sales_deliveries(id,order_id,request_key,tms_delivery_id,notes,created_by)
   values(eid,oid,key_id,tid,coalesce(p_data->>'notes',''),u);$new$;
 if position(old_insert in source)=0 then raise exception 'DELIVERY_REFERENCE_INSERT_ANCHOR';end if;
 execute replace(source,old_insert,new_insert);
end $migration$;

-- Repair only the unambiguous historical case: one ENT in a sales process,
-- with its correct number still unused. Archive the original values, retain
-- the former ENT as a legacy reference and leave all UUID links,
-- signed proofs, fiscal numbers, statuses, amounts and quantities intact.
create table private.delivery_reference_repairs(
 delivery_id uuid primary key,
 old_reference text not null,
 new_reference text not null,
 old_registry jsonb not null,
 old_issued jsonb not null,
 repaired_at timestamptz not null default clock_timestamp()
);
alter table private.delivery_reference_repairs enable row level security;
revoke all on private.delivery_reference_repairs from public,anon,authenticated;

do $repair$
declare r record;corrected text;
begin
 perform pg_advisory_xact_lock(724613092);
 for r in
  select d.*,to_jsonb(d) registry,to_jsonb(i) issued,i.kind,i.document_key
  from public.gama_document_references d
  join private.erp_issued_references i on i.kind='delivery' and i.document_key='tms_deliveries/'||d.document_id
  where d.table_name='tms_deliveries' and d.dossier_number>0
   and i.serial_number<>d.dossier_number
   and exists(select 1 from public.sales_deliveries s where s.tms_delivery_id=d.document_id)
   and (select count(*) from public.gama_document_references x where x.table_name=d.table_name and x.dossier_number=d.dossier_number)=1
  order by d.dossier_number
 loop
  -- Never silently steal another document's number.
  if exists(select 1 from private.erp_issued_references i where i.kind=r.kind and i.serial_number=r.dossier_number and i.document_key<>r.document_key) then
   raise exception 'DELIVERY_REFERENCE_REPAIR_COLLISION';
  end if;
  corrected:=left(r.document_reference,3)||'-'||lpad(r.dossier_number::text,8,'0');
  insert into private.delivery_reference_repairs(delivery_id,old_reference,new_reference,old_registry,old_issued)
   values(r.document_id,r.document_reference,corrected,r.registry,r.issued);
  update private.erp_issued_references set serial_number=r.dossier_number,reference=corrected,legacy_reference=r.document_reference
   where kind=r.kind and document_key=r.document_key;
  update public.gama_document_references set document_reference=corrected,legacy_reference=r.document_reference
   where table_name='tms_deliveries' and document_id=r.document_id;
  update public.tms_deliveries set erp_reference=corrected where id=r.document_id;
 end loop;
end $repair$;
