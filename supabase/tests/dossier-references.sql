begin;
do $$
declare req uuid:=gen_random_uuid();q uuid:=gen_random_uuid();o uuid:=gen_random_uuid();s1 uuid:=gen_random_uuid();s2 uuid:=gen_random_uuid();i uuid:=gen_random_uuid();p uuid:=gen_random_uuid();num bigint;before_ref text;u uuid;fresh uuid;
begin
 select id into u from public.profiles where active limit 1;
 if u is not null then
  insert into public.customer_requests(created_by,requester_name,status,total) values(u,'Reference trigger test','pending',0) returning id into fresh;
  if not exists(select 1 from public.gama_document_references where table_name='customer_requests' and document_id=fresh and document_reference like 'SOL-%') then raise exception 'New request trigger failed';end if;
 end if;
 perform private.gama_register_document('customer_requests',jsonb_build_object('id',req));
 perform private.gama_register_document('invoices',jsonb_build_object('id',q));
 perform private.gama_register_document('customer_requests',jsonb_build_object('id',req,'invoice_id',q));
 perform private.gama_register_document('sales_orders',jsonb_build_object('id',o,'source_quote_id',q,'source_request_id',req));
 perform private.gama_register_document('sales_deliveries',jsonb_build_object('id',s1,'order_id',o));
 perform private.gama_register_document('sales_deliveries',jsonb_build_object('id',s2,'order_id',o));
 perform private.gama_register_document('external_invoices',jsonb_build_object('id',i,'order_id',o));
 perform private.gama_register_document('external_invoice_payments',jsonb_build_object('id',p,'invoice_id',i));
 if (select count(distinct dossier_number) from public.gama_document_references where document_id=any(array[req,q,o,s1,s2,i,p]))<>1 then raise exception 'Dossier chain split';end if;
 select dossier_number,document_reference into num,before_ref from public.gama_document_references where document_id=s1;
 if (select document_reference from public.gama_document_references where document_id=s2)<>'ENV-B-'||lpad(num::text,8,'0') then raise exception 'Partial shipment reference mismatch';end if;
 perform private.gama_register_document('sales_deliveries',jsonb_build_object('id',s1,'order_id',o));
 if (select document_reference from public.gama_document_references where document_id=s1)<>before_ref then raise exception 'Reference not idempotent';end if;
 if has_table_privilege('authenticated','public.gama_document_references','INSERT') or has_table_privilege('anon','public.gama_document_references','SELECT') or has_function_privilege('authenticated','private.gama_register_document(text,jsonb)','EXECUTE') then raise exception 'Registry permits direct writes or anonymous reads';end if;
end $$;
rollback;
