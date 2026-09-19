-- Private automation entry point. It cannot be invoked by API roles.
-- Reuse the current invoice calculation, snapshot, locks and duplicate checks.
do $migration$
declare src text;
begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'private.gama_internal_invoice_action(', 'private.gama_delivery_invoice_create(');
 src:=replace(src,'begin'||chr(10),'begin'||chr(10)||' if p_action<>''create'' then raise exception ''INVALID_ACTION'';end if;'||chr(10));
 src:=replace(src,'''administrador'',''comercial''','''administrador'',''comercial'',''almacenero''');
 execute src;
end $migration$;
revoke all on function private.gama_delivery_invoice_create(text,jsonb) from public,anon,authenticated;

create function private.gama_invoice_on_signed_delivery() returns trigger
language plpgsql security definer set search_path='' as $$
declare tid uuid;oid uuid;qid uuid;inv jsonb;
begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial','almacenero') then return new;end if;
 if tg_table_name='tms_proofs' then tid:=new.delivery_id;else tid:=new.id;end if;
 select sd.order_id into oid from public.sales_deliveries sd where sd.tms_delivery_id=tid;
 if oid is null then return new;end if;
 -- Quote then order is the lock order used by manual invoice creation.
 select so.source_quote_id into qid from public.sales_orders so where so.id=oid;
 if qid is null then return new;end if;
 perform 1 from public.invoices where id=qid for update;
 perform 1 from public.sales_orders where id=oid for update;
 if not private.gama_order_delivery_validated(oid) then return new;end if;
 -- Editing a proof must never duplicate or recreate an invoice, even cancelled.
 if exists(select 1 from public.external_invoices where order_id=oid) then return new;end if;
 inv:=private.gama_delivery_invoice_create('create',jsonb_build_object('quote_id',qid));
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
 values(oid,'invoice_auto_delivery',(inv->>'id')::uuid,auth.uid(),jsonb_build_object('delivery_id',tid,'source','signed_delivery'));
 return new;
end $$;
revoke all on function private.gama_invoice_on_signed_delivery() from public,anon,authenticated;
create trigger invoice_on_delivered_status after insert or update of status,delivered_at on public.tms_deliveries
 for each row when(new.status='Entregada') execute function private.gama_invoice_on_signed_delivery();
create trigger invoice_on_signed_proof after insert or update of signature on public.tms_proofs
 for each row when(nullif(btrim(new.signature),'') is not null) execute function private.gama_invoice_on_signed_delivery();
