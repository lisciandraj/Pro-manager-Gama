create table private.supplier_ocr_intakes(id uuid primary key default gen_random_uuid(),hash text not null unique,filename text not null,mime_type text not null,content bytea not null check(octet_length(content) between 10 and 5242880),state text not null default 'processing' check(state in ('processing','review','draft','failed')),extracted jsonb,reviewed jsonb,bill_id uuid references public.supplier_invoices(id),lease uuid,lease_until timestamptz,error_code text,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index supplier_ocr_creator on private.supplier_ocr_intakes(created_by,created_at);
alter table private.supplier_ocr_intakes enable row level security;revoke all on private.supplier_ocr_intakes from public,anon,authenticated;
create table private.supplier_ocr_attempts(actor uuid not null references public.profiles(id),created_at timestamptz not null default now());
create index supplier_ocr_attempts_actor on private.supplier_ocr_attempts(actor,created_at);
alter table private.supplier_ocr_attempts enable row level security;revoke all on private.supplier_ocr_attempts from public,anon,authenticated;
create function private.gama_supplier_ocr(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare r private.supplier_ocr_intakes;raw bytea;hash text;result jsonb;vendor uuid;purchase uuid;bill public.supplier_invoices;net numeric;tax numeric;total numeric;number text;issued date;currency text;begin
 perform private.commercial_require(case when p_action in ('list','context','file') then 'view' else 'create' end);
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>7200000 then raise exception 'INVALID_REQUEST';end if;
 if p_action='list' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select id,filename,state,bill_id,error_code,created_at from private.supplier_ocr_intakes order by created_at desc limit 100)x),'[]');end if;
 if p_action='begin' then
  if coalesce(p_data->>'mime_type','') not in ('application/pdf','image/jpeg','image/png','image/webp') or coalesce(p_data->>'content_base64','')!~'^[A-Za-z0-9+/]+={0,2}$' then raise exception 'OCR_FILE_INVALID';end if;
  raw:=decode(p_data->>'content_base64','base64');if octet_length(raw) not between 10 and 5242880 then raise exception 'OCR_FILE_INVALID';end if;
  if (p_data->>'mime_type'='application/pdf' and substring(raw from 1 for 5)<>decode('255044462d','hex')) or (p_data->>'mime_type'='image/png' and substring(raw from 1 for 8)<>decode('89504e470d0a1a0a','hex')) or (p_data->>'mime_type'='image/jpeg' and substring(raw from 1 for 3)<>decode('ffd8ff','hex')) or (p_data->>'mime_type'='image/webp' and (substring(raw from 1 for 4)<>decode('52494646','hex') or substring(raw from 9 for 4)<>decode('57454250','hex'))) then raise exception 'OCR_FILE_INVALID';end if;
  hash:=encode(sha256(raw),'hex');perform pg_advisory_xact_lock(hashtextextended('supplier-ocr:'||hash,0));select * into r from private.supplier_ocr_intakes where supplier_ocr_intakes.hash=hash for update;
  if r.id is not null then
   if r.state in ('review','draft') then return jsonb_build_object('id',r.id,'state',r.state,'existing',true);end if;
   if r.lease_until>now() then raise exception 'OCR_PROCESSING';end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('supplier-ocr-actor:'||auth.uid(),0));
  if (select count(*) from private.supplier_ocr_attempts where actor=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'RATE_LIMIT';end if;
  insert into private.supplier_ocr_attempts(actor) values(auth.uid());
  delete from private.supplier_ocr_attempts where created_at<now()-interval '7 days';
  if r.id is null then insert into private.supplier_ocr_intakes(hash,filename,mime_type,content,created_by,lease,lease_until) values(hash,left(coalesce(nullif(p_data->>'filename',''),'invoice'),180),p_data->>'mime_type',raw,auth.uid(),gen_random_uuid(),now()+interval '3 minutes') returning * into r;
  else update private.supplier_ocr_intakes set state='processing',error_code=null,lease=gen_random_uuid(),lease_until=now()+interval '3 minutes',updated_at=now() where id=r.id returning * into r;end if;
  return jsonb_build_object('id',r.id,'state',r.state,'lease',r.lease);
 end if;
 select * into r from private.supplier_ocr_intakes where id=(p_data->>'id')::uuid for update;if not found then raise exception 'NOT_FOUND';end if;
 if p_action='complete' or p_action='fail' then
  if r.state<>'processing' or r.lease is distinct from (p_data->>'lease')::uuid or r.lease_until<now() then raise exception 'OCR_LEASE_EXPIRED';end if;
  if p_action='complete' then
   result:=p_data->'extracted';if jsonb_typeof(result) is distinct from 'object' or octet_length(result::text)>64000 or jsonb_typeof(result->'lines') is distinct from 'array' or jsonb_array_length(result->'lines')>200 then raise exception 'OCR_RESPONSE_INVALID';end if;
   update private.supplier_ocr_intakes set extracted=result,state='review',lease=null,lease_until=null,error_code=null,updated_at=now() where id=r.id;
  else update private.supplier_ocr_intakes set state='failed',error_code=left(regexp_replace(coalesce(p_data->>'error','OCR_FAILED'),'[^A-Z0-9_]','','g'),80),lease=null,lease_until=null,updated_at=now() where id=r.id;end if;
  return jsonb_build_object('id',r.id,'state',case p_action when 'complete' then 'review' else 'failed' end);
 elsif p_action='file' then return jsonb_build_object('filename',r.filename,'mime_type',r.mime_type,'content_base64',encode(r.content,'base64'));
 elsif p_action='context' then
  return (to_jsonb(r)-'content'-'lease'-'lease_until'-'created_by')||jsonb_build_object('suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'tax_id',tax_id)) from public.suppliers where active),'[]'),'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.supplier_id,p.order_number,p.total,p.status,coalesce((select sum(round(l.received_quantity*l.unit_cost,2)+round(round(l.received_quantity*l.unit_cost,2)*l.tax_rate/100,2)) from public.purchase_order_lines l where l.purchase_order_id=p.id),0) received_total from public.purchase_orders p where p.status in ('sent','partial','received') order by p.order_date desc limit 300)x),'[]'),'buyer_tax_id',(select tax_id from public.company_settings where id),'currency',(select c.currency from public.company_settings c where id));
 elsif p_action='draft' then
  if r.state='draft' then if r.reviewed is distinct from (p_data-'id') then raise exception 'REQUEST_KEY_REUSED';end if;return jsonb_build_object('id',r.bill_id,'existing',true);end if;
  if r.state<>'review' or not coalesce((p_data->>'reviewed')::boolean,false) then raise exception 'SOURCE_REVIEW_REQUIRED';end if;
  vendor:=(p_data->>'supplier_id')::uuid;purchase:=nullif(p_data->>'purchase_order_id','')::uuid;number:=btrim(p_data->>'number');issued:=(p_data->>'issue_date')::date;net:=(p_data->>'subtotal')::numeric;tax:=(p_data->>'tax')::numeric;total:=(p_data->>'total')::numeric;
  select c.currency into currency from public.company_settings c where id;
  if p_data->>'currency' is distinct from currency or net is null or tax is null or total is null or net<0 or tax<0 or total<=0 or total>=1000000000 or net<>round(net,2) or tax<>round(tax,2) or total<>net+tax then raise exception 'OCR_TOTAL_OR_CURRENCY_INVALID';end if;
  if number is null or length(number) not between 1 and 100 or issued is null then raise exception 'NUMBER_REQUIRED';end if;
  if not exists(select 1 from public.suppliers where id=vendor and active) then raise exception 'SUPPLIER_MATCH_REQUIRED';end if;
  if purchase is not null and not exists(select 1 from public.purchase_orders where id=purchase and supplier_id=vendor and status<>'cancelled') then raise exception 'SUPPLIER_MISMATCH';end if;
  perform pg_advisory_xact_lock(hashtextextended('supplier-invoice:'||vendor||':'||number,0));
  if exists(select 1 from public.supplier_invoices b where b.supplier_id=vendor and b.number=number and b.status<>'cancelled') then raise exception 'SUPPLIER_INVOICE_DUPLICATE';end if;
  insert into public.supplier_invoices(supplier_id,purchase_order_id,number,issue_date,payment_terms_days,due_date,subtotal,tax,total,status,source_reviewed,request_key,created_by,notes) values(vendor,purchase,number,issued,coalesce((p_data->>'payment_terms_days')::integer,0),issued+coalesce((p_data->>'payment_terms_days')::integer,0),net,tax,total,'draft',false,r.id,auth.uid(),'OCR · '||r.filename||E'\n'||coalesce(p_data->>'notes','')) returning * into bill;
  update private.supplier_ocr_intakes set bill_id=bill.id,reviewed=p_data-'id',state='draft',updated_at=now() where id=r.id;
  perform private.automation_exception('supplier-draft:'||bill.id,'receipt_bill','accounting','supplier_invoice',bill.id,'OCR_RECEIPT_REVIEW_REQUIRED',null,bill.erp_reference);
  return jsonb_build_object('id',bill.id,'status','draft');
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_supplier_ocr(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_supplier_ocr(p_action,p_data)$$;
revoke all on function private.gama_supplier_ocr(text,jsonb),public.gama_supplier_ocr(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_supplier_ocr(text,jsonb),public.gama_supplier_ocr(text,jsonb) to authenticated;
