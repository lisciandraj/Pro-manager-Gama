-- Purpose-bound quote signature links. No customer account or portal is restored.
-- Public capabilities are disabled until a database is explicitly assigned to
-- production. Development previews require a server-verified active admin.
create table private.sales_checkout_invitations(
 id uuid primary key,quote_id uuid references public.invoices(id) on delete restrict,
 invoice_id uuid references public.external_invoices(id) on delete restrict,
 customer_id uuid not null references public.customers(id) on delete restrict,
 revision integer not null,token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),request_fingerprint text not null,
 document jsonb not null,document_hash text not null check(document_hash ~ '^[a-f0-9]{64}$'),
 pdf_path text not null unique,pdf_sha256 text not null check(pdf_sha256 ~ '^[a-f0-9]{64}$'),
 issuer uuid not null references public.profiles(id),issuer_aal text not null,
 require_signature boolean not null default true,payment_percent numeric(5,2) not null default 0 check(payment_percent between 0 and 100),
 created_at timestamptz not null default now(),expires_at timestamptz not null,revoked_at timestamptz,
 signed_at timestamptz,signed_name text,signature_method text check(signature_method in('typed','drawn','uploaded')),
 signature_png text,signature_request_key uuid,signed_payload_hash text,result jsonb,
 check((quote_id is not null)::integer+(invoice_id is not null)::integer=1),
 check(not require_signature or quote_id is not null)
);
create index sales_checkout_quote on private.sales_checkout_invitations(quote_id);
create index sales_checkout_invoice on private.sales_checkout_invitations(invoice_id);
create index sales_checkout_customer on private.sales_checkout_invitations(customer_id);
create index sales_checkout_issuer on private.sales_checkout_invitations(issuer);
alter table private.sales_checkout_invitations enable row level security;
revoke all on private.sales_checkout_invitations from public,anon,authenticated,service_role;

create function private.coco_checkout_staff(p_write boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('quotes',array['administrador','comercial'])
 and (not p_write or private.erp_action_allowed('quotes','edit'))
$$;
revoke all on function private.coco_checkout_staff(boolean) from public,anon,service_role;
grant execute on function private.coco_checkout_staff(boolean) to authenticated;

create function private.coco_checkout_hash(p_text text) returns text
language sql immutable set search_path='' as $$select encode(sha256(convert_to(p_text,'UTF8')),'hex')$$;
revoke all on function private.coco_checkout_hash(text) from public,anon,authenticated,service_role;

create function private.coco_sales_checkout(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare q public.invoices;i private.sales_checkout_invitations;doc jsonb;key uuid:=nullif(p_data->>'id','')::uuid;
 qid uuid:=nullif(p_data->>'quote_id','')::uuid;token text:=p_data->>'token';path text;expires timestamptz;result jsonb;
begin
 if not private.coco_checkout_staff(p_action not in('context','evidence')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='evidence' then
  select * into i from private.sales_checkout_invitations where id=key and signed_at is not null;
  if not found then raise exception 'CHECKOUT_SIGNATURE_NOT_FOUND';end if;
  return jsonb_build_object('id',i.id,'quote_id',i.quote_id,'document',i.document,'document_hash',i.document_hash,'pdf_sha256',i.pdf_sha256,
   'pdf_path',i.pdf_path,'signed_at',i.signed_at,'signed_name',i.signed_name,'signature_method',i.signature_method,'signature_png',i.signature_png,
   'issuer',i.issuer,'result',i.result);
 end if;
 if p_action='context' then
  if qid is null then raise exception 'QUOTE_NOT_FOUND';end if;
  select * into q from public.invoices where id=qid and quote_state is not null;
  if not found then raise exception 'QUOTE_NOT_FOUND';end if;
  return jsonb_build_object('invitations',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'quote_id',x.quote_id,'revision',x.revision,
   'created_at',x.created_at,'expires_at',x.expires_at,'revoked_at',x.revoked_at,'signed_at',x.signed_at,'signed_name',x.signed_name,
   'signature_method',x.signature_method,'pdf_sha256',x.pdf_sha256,'document_hash',x.document_hash,'result',x.result,
   'require_signature',x.require_signature,'payment_percent',x.payment_percent) order by x.created_at desc)
   from private.sales_checkout_invitations x where x.quote_id=qid),'[]'));
 end if;
 perform pg_advisory_xact_lock(741932,1);
 if p_action='revoke' then
  update private.sales_checkout_invitations set revoked_at=coalesce(revoked_at,now()) where id=key returning * into i;
  if not found then raise exception 'CHECKOUT_LINK_NOT_FOUND';end if;
  return jsonb_build_object('id',i.id,'revoked',true);
 end if;
 if p_action<>'create' then raise exception 'INVALID_ACTION';end if;
 if key is null or token is null or token !~ '^[a-f0-9]{64}$' then raise exception 'CHECKOUT_TOKEN_REQUIRED';end if;
 select * into i from private.sales_checkout_invitations where id=key;
 if found then
  if i.issuer<>auth.uid() or i.quote_id is distinct from qid or i.token_hash<>private.coco_checkout_hash(token)
   or i.request_fingerprint<>private.coco_checkout_hash((p_data-'token')::text) then raise exception 'REQUEST_KEY_CONFLICT';end if;
  return jsonb_build_object('id',i.id,'expires_at',i.expires_at,'document_hash',i.document_hash);
 end if;
 select * into q from public.invoices where id=qid for update;
 if not found or q.quote_state<>'sent' then raise exception 'CHECKOUT_SENT_QUOTE_REQUIRED';end if;
 if q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
 if q.quote_valid_until<current_date then raise exception 'QUOTE_EXPIRED';end if;
 if p_data->>'pdf_sha256' is null or p_data->>'pdf_sha256' !~ '^[a-f0-9]{64}$' then raise exception 'CHECKOUT_PDF_REQUIRED';end if;
 path:=auth.uid()::text||'/'||key::text||'.pdf';
 if not exists(select 1 from storage.objects where bucket_id='sales-checkout-documents' and name=path
   and (metadata->>'size')::bigint between 5 and 52428800 and metadata->>'mimetype'='application/pdf') then raise exception 'CHECKOUT_PDF_REQUIRED';end if;
 expires:=least(coalesce(nullif(p_data->>'expires_at','')::timestamptz,now()+interval '7 days'),
  (q.quote_valid_until+1)::timestamp at time zone private.erp_timezone());
 if expires<=now() or expires>now()+interval '30 days' then raise exception 'CHECKOUT_EXPIRY_INVALID';end if;
 -- Only commercial content is projected; internal notes, margin, price rules,
 -- credit limits, storage paths, users and document library metadata stay private.
 doc:=jsonb_build_object('quote_id',q.id,'revision',q.quote_revision,'number',q.invoice_number,'issue_date',q.issue_date,
  'valid_until',q.quote_valid_until,'currency',coalesce(q.quote_details->>'currency',(select currency from public.company_settings where id)),
  'seller',q.quote_details->>'seller','customer',q.quote_details->>'client','subtotal',q.subtotal,'tax',q.tax,'total',q.total,
  'lines',coalesce((select jsonb_agg(jsonb_build_object('description',l.quote_description,'quantity',l.quantity,'unit_price',l.unit_price,
   'discount',l.quote_discount,'tax_rate',l.tax_rate,'subtotal',l.line_total) order by l.id) from public.invoice_lines l where l.invoice_id=q.id),'[]'),
  'commercial_lines',coalesce(private.coco_sales_quote_commercial_lines(q.id),'[]'));
 insert into private.sales_checkout_invitations(id,quote_id,customer_id,revision,token_hash,request_fingerprint,document,document_hash,pdf_path,pdf_sha256,issuer,issuer_aal,expires_at,require_signature,payment_percent)
 values(key,q.id,q.customer_id,q.quote_revision,private.coco_checkout_hash(token),private.coco_checkout_hash((p_data-'token')::text),doc,private.coco_checkout_hash(doc::text),path,p_data->>'pdf_sha256',auth.uid(),
  coalesce(auth.jwt()->>'aal','aal1'),expires,coalesce((p_data->>'require_signature')::boolean,true),coalesce((p_data->>'payment_percent')::numeric,0));
 return jsonb_build_object('id',key,'expires_at',expires,'document_hash',private.coco_checkout_hash(doc::text));
end $$;
create function public.coco_sales_checkout(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_sales_checkout(p_action,p_data)$$;
revoke all on function public.coco_sales_checkout(text,jsonb),private.coco_sales_checkout(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_sales_checkout(text,jsonb),private.coco_sales_checkout(text,jsonb) to authenticated;

-- This is the only identity delegation used by a capability. It grants exactly
-- one frozen quote acceptance, using the issuer's still-current permissions.
-- The caller never supplies an actor, claims, target or revision. Public code
-- cannot invoke this helper. All request context is restored even on failure.
create function private.coco_checkout_confirm(p_invitation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.sales_checkout_invitations;result jsonb;old_sub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');
 old_claims text:=coalesce(current_setting('request.jwt.claims',true),'');old_source text:=coalesce(current_setting('coco.activity_source_type',true),'');
 old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');old_source_id text:=coalesce(current_setting('coco.activity_source_id',true),'');
begin
 select * into i from private.sales_checkout_invitations where id=p_invitation;
 if i.quote_id is null or (i.require_signature and i.signed_at is null) then raise exception 'CHECKOUT_SIGNATURE_REQUIRED';end if;
 if not exists(select 1 from public.profiles where id=i.issuer and active and deleted_at is null and role in('administrador','comercial')) then raise exception 'CHECKOUT_ISSUER_UNAVAILABLE';end if;
 perform set_config('request.jwt.claim.sub',i.issuer::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',i.issuer,'role','authenticated','aal',i.issuer_aal)::text,true);
 perform set_config('coco.activity_source_type','erp',true);perform set_config('coco.activity_source_id',i.id::text,true);
 perform set_config('coco.activity_source_label','Firma del cliente · '||coalesce(i.signed_name,''),true);
 if not private.coco_checkout_staff(true) or not private.erp_action_allowed('quotes','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 result:=private.gama_quote_action('accept',jsonb_build_object('id',i.quote_id,'revision',i.revision,'channel','other',
  'reference','Firma electrónica · '||coalesce(i.signed_name,'Pago verificado')||' · enlace '||i.id::text||' · PDF SHA-256 '||i.pdf_sha256));
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('request.jwt.claims',old_claims,true);
 perform set_config('coco.activity_source_type',old_source,true);perform set_config('coco.activity_source_id',old_source_id,true);perform set_config('coco.activity_source_label',old_label,true);
 return result;
exception when others then
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('request.jwt.claims',old_claims,true);
 perform set_config('coco.activity_source_type',old_source,true);perform set_config('coco.activity_source_id',old_source_id,true);perform set_config('coco.activity_source_label',old_label,true);raise;
end $$;
revoke all on function private.coco_checkout_confirm(uuid) from public,anon,authenticated,service_role;

create function private.coco_checkout_public(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare i private.sales_checkout_invitations;q public.invoices;tok text:=p_data->>'token';key uuid:=nullif(p_data->>'request_key','')::uuid;
 signature text:=p_data->>'signature_png';name text:=btrim(p_data->>'signed_name');mode text:=p_data->>'signature_method';payload text;result jsonb;failure text;
begin
 if not coalesce((select environment='production' from private.coco_environment where id),false)
  and not private.coco_environment_admin() then raise exception 'CHECKOUT_PUBLIC_DISABLED';end if;
 if tok is null or tok !~ '^[a-f0-9]{64}$' then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 -- Reads never take the global sales mutation lock. Signing uses the same
 -- lock order as revocation and native quote acceptance to avoid deadlocks.
 if p_action='sign' then perform pg_advisory_xact_lock(741932,1);end if;
 select * into i from private.sales_checkout_invitations where token_hash=private.coco_checkout_hash(tok);
 if not found or i.revoked_at is not null then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 select * into q from public.invoices where id=i.quote_id;
 if p_action='view' then
  if i.expires_at<=now() and i.signed_at is null then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
  if i.signed_at is null and (q.quote_revision<>i.revision or q.quote_state<>'sent') then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
  return jsonb_build_object('id',i.id,'document',i.document,'document_hash',i.document_hash,'pdf_sha256',i.pdf_sha256,'expires_at',i.expires_at,
   'require_signature',i.require_signature,'payment_percent',i.payment_percent,'signed_at',i.signed_at,'signed_name',i.signed_name,
   'confirmation_pending',i.signed_at is not null and not(coalesce(i.result->>'state'='accepted',false) or(q.quote_state='accepted' and q.quote_revision=i.revision+1)),
   'confirmed',coalesce(i.result->>'state'='accepted',false) or(q.quote_state='accepted' and q.quote_revision=i.revision+1));
 end if;
 if p_action<>'sign' then raise exception 'INVALID_ACTION';end if;
 if not i.require_signature or key is null or name is null or length(name) not between 2 and 160 or mode is null or mode not in('typed','drawn','uploaded')
  or (p_data->>'agree') is distinct from 'true' or p_data->>'pdf_sha256' is distinct from i.pdf_sha256 then raise exception 'CHECKOUT_SIGNATURE_INVALID';end if;
 if mode='typed' and signature is not null then raise exception 'CHECKOUT_SIGNATURE_INVALID';end if;
 if mode in('drawn','uploaded') and (signature is null or length(signature) not between 40 and 200000 or signature !~ '^data:image/png;base64,[A-Za-z0-9+/]+=*$') then raise exception 'CHECKOUT_SIGNATURE_INVALID';end if;
 if signature is not null and (left(encode(decode(split_part(signature,',',2),'base64'),'hex'),16)<>'89504e470d0a1a0a' or length(signature)>200000) then raise exception 'CHECKOUT_SIGNATURE_INVALID';end if;
 payload:=private.coco_checkout_hash(jsonb_build_object('signed_name',name,'signature_method',mode,'signature_png',signature,'pdf_sha256',i.pdf_sha256)::text);
 if i.signed_at is not null then
  if i.signature_request_key<>key or i.signed_payload_hash<>payload then raise exception 'CHECKOUT_ALREADY_SIGNED';end if;
  return i.result;
 end if;
 if i.expires_at<=now() or q.quote_valid_until<current_date then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 if q.quote_revision<>i.revision or q.quote_state<>'sent' then raise exception 'QUOTE_CHANGED';end if;
 update private.sales_checkout_invitations set signed_at=now(),signed_name=name,signature_method=mode,signature_png=signature,
  signature_request_key=key,signed_payload_hash=payload where id=i.id;
 -- Evidence survives a credit/stock/approval failure; staff can review and use
 -- the normal acceptance workflow. No bypass of the native commercial checks.
 begin result:=private.coco_checkout_confirm(i.id);
 exception when others then failure:=sqlstate;result:=jsonb_build_object('state','signed_pending','confirmation_pending',true);end;
 result:=result||jsonb_build_object('signature_recorded',true,'signed_at',now(),'invitation_id',i.id);
 update private.sales_checkout_invitations set result=result where id=i.id;
 return result;
end $$;
-- Anonymous callers do not receive USAGE on the application's private schema.
-- This dedicated schema exposes only the purpose-bound capability adapter.
create schema checkout_api;
grant usage on schema checkout_api to anon,authenticated,service_role;
create function checkout_api.coco_checkout_public(p_action text,p_data jsonb) returns jsonb
language sql security definer set search_path='' as $$select private.coco_checkout_public(p_action,p_data)$$;
create function public.coco_checkout_public(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select checkout_api.coco_checkout_public(p_action,p_data)$$;
revoke all on function private.coco_checkout_public(text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.coco_checkout_public(text,jsonb),checkout_api.coco_checkout_public(text,jsonb) from public,service_role;
grant execute on function public.coco_checkout_public(text,jsonb),checkout_api.coco_checkout_public(text,jsonb) to anon,authenticated;

-- PDFs are private and immutable once an invitation references them. A service
-- adapter streams only the exact bytes whose SHA-256 the signer confirms.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('sales-checkout-documents','sales-checkout-documents',false,52428800,array['application/pdf']);
create function private.coco_checkout_file_owned(p_path text,p_unregistered boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_checkout_staff(true) and split_part(p_path,'/',1)=auth.uid()::text
 and (not p_unregistered or not exists(select 1 from private.sales_checkout_invitations where pdf_path=p_path))
$$;
revoke all on function private.coco_checkout_file_owned(text,boolean) from public,anon,service_role;grant execute on function private.coco_checkout_file_owned(text,boolean) to authenticated;
create policy checkout_pdf_upload on storage.objects for insert to authenticated with check(bucket_id='sales-checkout-documents' and private.coco_checkout_file_owned(name,true));
create policy checkout_pdf_read on storage.objects for select to authenticated using(bucket_id='sales-checkout-documents' and private.coco_checkout_file_owned(name,false));
create policy checkout_pdf_cleanup on storage.objects for delete to authenticated using(bucket_id='sales-checkout-documents' and private.coco_checkout_file_owned(name,true));

-- The only machine endpoint resolves a capability after a caller-bound check.
-- It never delegates public development access to the service role.
create function checkout_api.coco_checkout_document(p_id uuid,p_pdf_sha256 text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.sales_checkout_invitations;begin
 if current_setting('role',true)<>'service_role' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into i from private.sales_checkout_invitations where id=p_id and pdf_sha256=p_pdf_sha256 and revoked_at is null;
 if not found then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 return jsonb_build_object('path',i.pdf_path,'sha256',i.pdf_sha256);
end $$;
create function public.coco_checkout_document(p_id uuid,p_pdf_sha256 text) returns jsonb
language sql security invoker set search_path='' as $$select checkout_api.coco_checkout_document(p_id,p_pdf_sha256)$$;
revoke all on function public.coco_checkout_document(uuid,text),checkout_api.coco_checkout_document(uuid,text) from public,anon,authenticated;
grant execute on function public.coco_checkout_document(uuid,text),checkout_api.coco_checkout_document(uuid,text) to service_role;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('sales_checkout_invitations','quotes','Firma y pago a distancia','private','id');
create trigger coco_module_history after insert or update or delete on private.sales_checkout_invitations for each row execute function private.coco_capture_module_event();
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
 'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_checkout(');end $$;
revoke all on function private.coco_history_record_visible_before_checkout(text,text,uuid) from public,anon,service_role;grant execute on function private.coco_history_record_visible_before_checkout(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_checkout_invitations' then return private.coco_checkout_staff(false);end if;
 return private.coco_history_record_visible_before_checkout(p_table,p_id,p_owner);end $$;
select private.coco_install_environment_policies();
