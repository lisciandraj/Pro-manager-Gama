-- Receipt quantities and line identity are written by canonical purchase RPCs.
-- Direct table clients retain reads; definer workflows retain their checks.
revoke insert,update,delete,truncate,references,trigger on public.purchase_order_lines from authenticated;

-- Cancellation and payment must inspect the same locked supplier invoice.
do $audit$
declare src text;before_text text:='select * into r from public.supplier_invoices where id=(p_data->>''id'')::uuid;';
begin
 src:=pg_get_functiondef('private.gama_accounting_banking(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:supplier_cancel_lock';end if;
 execute replace(src,before_text,'select * into r from public.supplier_invoices where id=(p_data->>''id'')::uuid for update;');
end $audit$;

-- Legacy methods have no accounting_payment_methods row, so their earlier
-- payment-mode trigger returns before locking. Every confirmed payment must
-- lock and re-read the invoice, including direct writes and status changes.
create or replace function private.automation_supplier_payment_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare invoice public.supplier_invoices;
begin
 if new.status='confirmed' then
  select * into invoice from public.supplier_invoices where id=new.supplier_invoice_id for update;
  if not found or invoice.status<>'posted' or not coalesce(invoice.source_reviewed,false) then
   raise exception 'POSTED_SUPPLIER_INVOICE_REQUIRED';
  end if;
 end if;
 return new;
end $$;
notify pgrst,'reload schema';
