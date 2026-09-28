-- Resolve a request-derived quote's parent BEFORE issuing its immutable number.
-- The conversion RPC uses the request UUID as its idempotency key. Verify the
-- actual customer and existing link instead of trusting a client process number.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 anchor:=' case t';
 if strpos(src,anchor)=0 then raise exception 'PROCESS_REGISTER_ANCHOR';end if;
 src:=replace(src,anchor,anchor||$patch$
  when 'invoices' then edges:=coalesce((select jsonb_build_array(jsonb_build_array('customer_requests',r.id)) from public.customer_requests r where r.id=nullif(j->>'quote_request_key','')::uuid and r.customer_id=nullif(j->>'customer_id','')::uuid and (r.invoice_id is null or r.invoice_id=nullif(j->>'id','')::uuid)),'[]'::jsonb);
  when 'stock_reservations' then
   if j->>'reference_type'='sales_order' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'reference_id'));end if;
  when 'stock_movements' then
   if j->>'reference_type'='purchase_order' then edges:=jsonb_build_array(jsonb_build_array('purchase_orders',j->>'reference_id'));end if;
$patch$);
 -- Repeated documents must not consume the number of a future process root.
 anchor:=$old$if target is null then target:=nextval('private.gama_dossier_sequence');end if;$old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_SEQUENCE_ANCHOR';end if;
 src:=replace(src,anchor,$new$if target is null then
  loop
   target:=nextval('private.gama_dossier_sequence');
   exit when not exists(select 1 from private.erp_issued_references where serial_number=target and kind in ('request','quote','order','preparation','package','shipment','delivery','proof','invoice','collection','purchase','supplier_invoice','supplier_payment','return','credit','refund','reservation','movement'));
  end loop;
 end if;$new$);
 execute src;
 src:=pg_get_functiondef('private.erp_stamp_reference()'::regprocedure);
 anchor:=$old$or (tg_table_name='supplier_invoices'$old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_STAMP_ANCHOR';end if;
 src:=replace(src,anchor,$new$or (tg_table_name='stock_reservations' and j->>'reference_type'='sales_order' and j->>'reference_id' is not null)
    or (tg_table_name='stock_movements' and j->>'reference_type'='purchase_order' and j->>'reference_id' is not null)
    or (tg_table_name='supplier_invoices'$new$);
 execute src;
end $$;

-- Stage identity is separate from immutable issued-document identity. Several
-- reservations/packages/payments can belong to one stage without renumbering
-- fiscal documents, signed PDFs or printed package barcodes.
alter table public.gama_document_references add column process_reference text generated always as
 (case when dossier_number>0 and document_reference ~ '^[A-Z]{3}-[0-9]{8}$' then left(document_reference,3)||'-'||lpad(dossier_number::text,8,'0') else null end) stored;

-- Repair missing membership only; no stock/financial workflow is replayed.
do $$declare r record;begin
 for r in select to_jsonb(s) j from public.stock_reservations s where s.reference_type='sales_order' and exists(select 1 from public.sales_orders o where o.id=s.reference_id) loop
  perform private.gama_register_document('stock_reservations',r.j);
 end loop;
 for r in select to_jsonb(s) j from public.stock_movements s where s.reference_type='purchase_order' and exists(select 1 from public.purchase_orders o where o.id=s.reference_id) loop
  perform private.gama_register_document('stock_movements',r.j);
 end loop;
end $$;

-- The editable conversion form can correct the customer. Make that association
-- visible to the reference trigger inside the same transaction; failed saves
-- roll it back together with the quote and its references.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_quote_from_request(uuid,jsonb)'::regprocedure);
 anchor:=$old$ result:=private.gama_quote_action('save',$old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_QUOTE_ANCHOR';end if;
 execute replace(src,anchor,$new$ update public.customer_requests set customer_id=(p_data->>'customer_id')::uuid where id=req.id;
 result:=private.gama_quote_action('save',$new$);
end $$;

-- Return stages use the registry's process identity, including partial refunds.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
 anchor:=$old$ return to_jsonb(r)||jsonb_build_object($old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_RETURN_DETAIL_ANCHOR';end if;
 execute replace(src,anchor,anchor||$new$
   'dossier_number',(select dossier_number from public.gama_document_references where table_name='return_orders' and document_id=r.id),$new$);
end $$;

-- Correct unambiguous historical request/quote offsets (including the reported
-- COT/PED discrepancy). Retain old aliases and complete before-images. Fiscal
-- documents, already stored snapshots and signed files are never rewritten.
create table private.quote_process_reference_repairs(
 quote_id uuid primary key,old_reference text not null,new_reference text not null,
 old_row jsonb not null,old_registry jsonb not null,old_issued jsonb not null,
 repaired_at timestamptz not null default clock_timestamp()
);
alter table private.quote_process_reference_repairs enable row level security;
revoke all on private.quote_process_reference_repairs from public,anon,authenticated;
do $$declare r record;corrected text;triggers jsonb;tr jsonb;begin
 perform pg_advisory_xact_lock(724613092);
 select jsonb_agg(jsonb_build_object('name',tgname,'mode',tgenabled)) into triggers from pg_trigger where tgrelid='public.invoices'::regclass and not tgisinternal and tgenabled<>'D';
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.invoices disable trigger %I',tr->>'name');end loop;
 for r in
  select d.*,to_jsonb(d) registry,to_jsonb(i) issued,to_jsonb(q) original,i.document_key
  from public.gama_document_references d
  join private.erp_issued_references i on i.kind='quote' and i.document_key='invoices/'||d.document_id
  join public.invoices q on q.id=d.document_id
  where d.table_name='invoices' and d.dossier_number>0 and i.serial_number<>d.dossier_number
   and (select count(*) from public.gama_document_references x where x.table_name='invoices' and x.dossier_number=d.dossier_number)=1
   and not exists(select 1 from private.erp_issued_references x where x.kind='quote' and x.serial_number=d.dossier_number)
   and not exists(select 1 from public.sri_electronic_documents x where x.invoice_id=q.id)
  order by d.dossier_number
 loop
  corrected:=left(r.document_reference,3)||'-'||lpad(r.dossier_number::text,8,'0');
  insert into private.quote_process_reference_repairs(quote_id,old_reference,new_reference,old_row,old_registry,old_issued) values(r.document_id,r.document_reference,corrected,r.original,r.registry,r.issued);
  update private.erp_issued_references set serial_number=r.dossier_number,reference=corrected,legacy_reference=r.document_reference where kind='quote' and document_key=r.document_key;
  update public.gama_document_references set document_reference=corrected,legacy_reference=r.document_reference where table_name='invoices' and document_id=r.document_id;
  update public.invoices set invoice_number=corrected,erp_reference=corrected where id=r.document_id;
 end loop;
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.invoices enable %s trigger %I',case tr->>'mode' when 'A' then 'always' when 'R' then 'replica' else '' end,tr->>'name');end loop;
end $$;
notify pgrst,'reload schema';
