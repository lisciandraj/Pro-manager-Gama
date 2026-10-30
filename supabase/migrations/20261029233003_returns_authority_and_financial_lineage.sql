-- Keep native Returns and the SAV bridge on the same module boundary.
do $audit$
declare src text;before_text text;t text;
begin
 src:=pg_get_functiondef('private.gama_returns_rights()'::regprocedure);
 before_text:='if r not in';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:returns_rights';end if;
 execute replace(src,before_text,$gate$
 if not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 $gate$||before_text);
 foreach t in array array['return_orders','return_lines','return_files','return_credits','return_refunds'] loop
  execute format('create policy security_returns_module on public.%I as restrictive for select to authenticated using (private.erp_module_allowed(''returns'',array[''administrador'',''comercial'',''almacenero'']))',t);
 end loop;
end $audit$;

create function private.return_invoice_matches(p_invoice uuid,p_order uuid,p_customer uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.external_invoices i
  join public.sales_orders source_order on source_order.id=p_order and source_order.customer_id=p_customer
  join public.sales_orders invoice_order on invoice_order.id=i.order_id and invoice_order.customer_id=p_customer
  where i.id=p_invoice and i.fiscal_status not in ('cancelled','rejected') and
   (exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=p_order)
    or (i.order_id=p_order and not exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id))))
$$;
revoke all on function private.return_invoice_matches(uuid,uuid,uuid) from public,anon,authenticated;

-- Enforce lineage at the row boundary as well as when posting an older return.
create function private.return_source_and_cancel_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.kind='customer' and new.invoice_id is not null and
   (tg_op='INSERT' or (new.invoice_id,new.order_id,new.customer_id) is distinct from (old.invoice_id,old.order_id,old.customer_id)) and
   not private.return_invoice_matches(new.invoice_id,new.order_id,new.customer_id)
 then raise exception 'RETURN_INVOICE_SOURCE_MISMATCH';end if;
 if tg_op='UPDATE' and new.status='cancelled' and old.status is distinct from new.status and
   (exists(select 1 from public.return_credits where return_id=new.id) or exists(select 1 from public.return_refunds where return_id=new.id))
 then raise exception 'RETURN_HAS_FINANCIAL_EFFECTS';end if;
 return new;
end $$;
revoke all on function private.return_source_and_cancel_guard() from public,anon,authenticated;
create trigger return_source_and_cancel_guard before insert or update on public.return_orders
 for each row execute function private.return_source_and_cancel_guard();

do $audit$
declare src text;before_text text;
begin
 src:=pg_get_functiondef('private.gama_returns_settlement(text,jsonb,jsonb,date)'::regprocedure);
 before_text:='if o.invoice_id is null then raise exception ''INVOICE_REQUIRED'';end if;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:return_credit_binding';end if;
 execute replace(src,before_text,before_text||$gate$
 -- Serialize the shared invoice headroom before reading cap or prior credits.
 perform 1 from public.external_invoices where id=o.invoice_id for update;
 if not private.return_invoice_matches(o.invoice_id,o.order_id,o.customer_id) then raise exception 'RETURN_INVOICE_SOURCE_MISMATCH';end if;
 $gate$);

 -- A legacy cancelled record with retained financial children still consumes
 -- its original quantity. No historical business data is rewritten here.
 src:=pg_get_functiondef('private.gama_returns_sources(text,jsonb,jsonb,date)'::regprocedure);
 before_text:='ro.status<>''cancelled''';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:return_source_capacity';end if;
 execute replace(src,before_text,$gate$(ro.status<>'cancelled'
  or exists(select 1 from public.return_credits rc where rc.return_id=ro.id)
  or exists(select 1 from public.return_refunds rf where rf.return_id=ro.id))$gate$);
end $audit$;
notify pgrst,'reload schema';
