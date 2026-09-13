begin;
do $$ declare u uuid;oid uuid;q uuid;fid uuid;r jsonb;
begin
 select id into u from public.profiles where active and role='administrador' limit 1;
 select id into oid from public.sales_orders limit 1;
 if u is null or oid is null then raise exception 'TEST_FIXTURE_MISSING';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 insert into public.invoices default values returning id into q;
 insert into public.external_invoices(request_key,order_id,number,issue_date,subtotal,tax,created_by,document_kind,source_quote_id,document_snapshot,fiscal_status)
 values(gen_random_uuid(),oid,'QA-'||gen_random_uuid(),current_date,100,15,u,'internal',q,'{}','unverified') returning id into fid;
 r:=public.gama_internal_invoice_action('link_external',jsonb_build_object('invoice_id',fid,'number','  OFFICIAL-123  '));
 if r->>'external_number'<>'OFFICIAL-123' or (r->>'total')::numeric<>115 then raise exception 'ADD_FAILED';end if;
 r:=public.gama_internal_invoice_action('link_external',jsonb_build_object('invoice_id',fid,'number','CORRECTED-456'));
 if r->>'external_number'<>'CORRECTED-456' then raise exception 'EDIT_FAILED';end if;
 r:=public.gama_internal_invoice_action('link_external',jsonb_build_object('invoice_id',fid,'number',''));
 if r->>'external_number' is not null or (r->>'total')::numeric<>115 then raise exception 'CLEAR_FAILED';end if;
 begin
  insert into public.external_invoices(request_key,order_id,number,issuer_ruc,issue_date,subtotal,tax,created_by,fiscal_status)
  values(gen_random_uuid(),oid,'QA-EXTERNAL','1234567890001',current_date,100,15,u,'unverified');
  raise exception 'EXTERNAL_CREATION_ALLOWED';
 exception when raise_exception then if sqlerrm<>'CREATE_INVOICE_FROM_QUOTE' then raise;end if;end;
end $$;
rollback;

