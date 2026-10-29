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
notify pgrst,'reload schema';
