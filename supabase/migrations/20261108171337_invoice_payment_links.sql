-- Invoice payment links share the existing capability and immutable PDF store.
-- They cannot accept a quote, create an order or alter the invoice itself.
create function private.coco_invoice_checkout_staff(p_write boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('accounting',array['administrador','comercial'])
 and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false)
 and (not p_write or coalesce((private.gama_accounting_rights()->>'create')::boolean,false)
  and coalesce((private.gama_accounting_rights()->>'pay')::boolean,false) and private.erp_action_allowed('accounting','create'))
$$;
revoke all on function private.coco_invoice_checkout_staff(boolean) from public,anon,service_role;
grant execute on function private.coco_invoice_checkout_staff(boolean) to authenticated;

alter function private.coco_sales_checkout(text,jsonb) rename to coco_sales_checkout_before_invoices;
revoke all on function private.coco_sales_checkout_before_invoices(text,jsonb) from public,anon,authenticated,service_role;
create function private.coco_sales_checkout(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare iid uuid:=nullif(p_data->>'invoice_id','')::uuid;key uuid:=nullif(p_data->>'id','')::uuid;i private.sales_checkout_invitations;
 inv public.external_invoices;r private.gama_receivables;doc jsonb;tok text:=p_data->>'token';expires timestamptz;path text;revision integer;
begin
 if p_action not in('context','create','revoke','evidence') then return private.coco_sales_checkout_before_invoices(p_action,p_data);end if;
 if key is not null then select * into i from private.sales_checkout_invitations where id=key;end if;
 iid:=coalesce(iid,i.invoice_id);
 if iid is null then
  -- The storage policy below also supports accountants. Quote commands retain
  -- the original quote-specific authorization and cannot inherit that access.
  if not private.coco_checkout_staff(p_action not in('context','evidence')) then raise exception 'ROLE_NOT_ALLOWED';end if;
  return private.coco_sales_checkout_before_invoices(p_action,p_data);
 end if;
 if not private.coco_invoice_checkout_staff(p_action not in('context','evidence')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='evidence' then raise exception 'CHECKOUT_SIGNATURE_NOT_FOUND';end if;
 select * into inv from public.external_invoices where id=iid;
 if not found then raise exception 'INVOICE_NOT_FOUND';end if;
 if p_action='context' then
  return jsonb_build_object('invoice_id',iid,'can_create',private.coco_invoice_checkout_staff(true),'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'invoice_id',x.invoice_id,'revision',x.revision,
   'created_at',x.created_at,'expires_at',x.expires_at,'revoked_at',x.revoked_at,'pdf_sha256',x.pdf_sha256,'document_hash',x.document_hash,
   'require_signature',false,'payment_percent',x.payment_percent) order by x.created_at desc) from private.sales_checkout_invitations x where x.invoice_id=iid),'[]'));
 end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-checkout:'||iid::text,0));
 if p_action='revoke' then
  if i.id is null or i.invoice_id<>iid then raise exception 'CHECKOUT_LINK_NOT_FOUND';end if;
  update private.sales_checkout_invitations set revoked_at=coalesce(revoked_at,now()) where id=key;
  return jsonb_build_object('id',key,'revoked',true);
 end if;
 if key is null or tok is null or tok !~ '^[a-f0-9]{64}$' then raise exception 'CHECKOUT_TOKEN_REQUIRED';end if;
 if p_data->>'quote_id' is not null or coalesce((p_data->>'require_signature')::boolean,false) or coalesce((p_data->>'payment_percent')::numeric,100)<>100 then raise exception 'CHECKOUT_INVOICE_OPTIONS_INVALID';end if;
 if i.id is not null then
  if i.issuer<>auth.uid() or i.invoice_id is distinct from iid or i.token_hash<>private.coco_checkout_hash(tok)
   or i.request_fingerprint<>private.coco_checkout_hash((p_data-'token')::text) then raise exception 'REQUEST_KEY_CONFLICT';end if;
  return jsonb_build_object('id',i.id,'expires_at',i.expires_at,'document_hash',i.document_hash);
 end if;
 select * into inv from public.external_invoices where id=iid for update;
 select * into r from private.gama_receivables where id=iid;
 if r.id is null or inv.fiscal_status in('cancelled','rejected') or inv.direct_status<>'posted' or r.balance-coalesce(r.unposted_payment,0)<=0
  or not exists(select 1 from public.accounting_entries where source_type='sales_invoice' and source_id=iid and status='posted') then raise exception 'CHECKOUT_POSTED_INVOICE_REQUIRED';end if;
 revision:=inv.direct_revision;
 if (p_data->>'revision')::integer is distinct from revision then raise exception 'DIRECT_INVOICE_CHANGED';end if;
 if p_data->>'pdf_sha256' is null or p_data->>'pdf_sha256' !~ '^[a-f0-9]{64}$' then raise exception 'CHECKOUT_PDF_REQUIRED';end if;
 path:=auth.uid()::text||'/'||key::text||'.pdf';
 if not exists(select 1 from storage.objects where bucket_id='sales-checkout-documents' and name=path
  and (metadata->>'size')::bigint between 5 and 52428800 and metadata->>'mimetype'='application/pdf') then raise exception 'CHECKOUT_PDF_REQUIRED';end if;
 expires:=coalesce(nullif(p_data->>'expires_at','')::timestamptz,now()+interval '7 days');
 if expires<=now() or expires>now()+interval '30 days' then raise exception 'CHECKOUT_EXPIRY_INVALID';end if;
 doc:=jsonb_build_object('kind','invoice','invoice_id',inv.id,'revision',revision,'number',inv.number,'issue_date',inv.issue_date,'due_date',inv.due_date,
  'currency',coalesce(inv.document_snapshot->>'currency',inv.document_snapshot#>>'{company,currency}',(select currency from public.company_settings where id)),
  'seller',inv.document_snapshot#>>'{company,legal_name}','customer',coalesce(inv.document_snapshot->>'customer',r.customer_name),
  'subtotal',inv.subtotal,'tax',inv.tax,'total',inv.total,'balance',r.balance-coalesce(r.unposted_payment,0),
  'lines',coalesce((select jsonb_agg(jsonb_build_object('description',l->>'name','reference',l->>'reference','quantity',l->'qty','unit_price',l->'price',
   'discount',l->'discount','tax_rate',l->'taxRate','subtotal',l->'subtotal','tax',l->'tax') order by ordinality)
    from jsonb_array_elements(inv.document_snapshot->'lines') with ordinality x(l,ordinality)),'[]'));
 insert into private.sales_checkout_invitations(id,invoice_id,customer_id,revision,token_hash,request_fingerprint,document,document_hash,pdf_path,pdf_sha256,issuer,issuer_aal,expires_at,require_signature,payment_percent)
 values(key,iid,inv.customer_id,revision,private.coco_checkout_hash(tok),private.coco_checkout_hash((p_data-'token')::text),doc,private.coco_checkout_hash(doc::text),path,p_data->>'pdf_sha256',
  auth.uid(),coalesce(auth.jwt()->>'aal','aal1'),expires,false,100);
 return jsonb_build_object('id',key,'expires_at',expires,'document_hash',private.coco_checkout_hash(doc::text));
end $$;
revoke all on function private.coco_sales_checkout(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_sales_checkout(text,jsonb) to authenticated;

-- Uploading an unregistered PDF grants no quote command. Registered objects
-- retain the permissions of their actual source and remain immutable.
create or replace function private.coco_checkout_file_owned(p_path text,p_unregistered boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select split_part(p_path,'/',1)=auth.uid()::text and
 case when p_unregistered then (private.coco_checkout_staff(true) or private.coco_invoice_checkout_staff(true))
  and not exists(select 1 from private.sales_checkout_invitations where pdf_path=p_path)
 else exists(select 1 from private.sales_checkout_invitations i where i.pdf_path=p_path and
  ((i.quote_id is not null and private.coco_checkout_staff(false)) or(i.invoice_id is not null and private.coco_invoice_checkout_staff(false))))
  or (private.coco_checkout_staff(true) or private.coco_invoice_checkout_staff(true)) and not exists(select 1 from private.sales_checkout_invitations where pdf_path=p_path) end
$$;

create function private.coco_invoice_checkout_history(p_id text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare i private.sales_checkout_invitations;begin
 select * into i from private.sales_checkout_invitations where id::text=p_id;
 if i.invoice_id is not null then return private.coco_invoice_checkout_staff(false);end if;
 return private.coco_checkout_staff(false);
end $$;
revoke all on function private.coco_invoice_checkout_history(text) from public,anon,service_role;
grant execute on function private.coco_invoice_checkout_history(text) to authenticated;
alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_invoice_links;
revoke all on function private.coco_history_record_visible_before_invoice_links(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_invoice_links(text,text,uuid) to authenticated;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_checkout_invitations' then return private.coco_invoice_checkout_history(p_id);end if;
 return private.coco_history_record_visible_before_invoice_links(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
create function private.coco_invoice_checkout_event_route() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.record_table='sales_checkout_invitations' and exists(select 1 from private.sales_checkout_invitations where id::text=new.record_id and invoice_id is not null) then new.module_id:='accounting';end if;return new;
end $$;
revoke all on function private.coco_invoice_checkout_event_route() from public,anon,authenticated,service_role;
create trigger coco_invoice_checkout_route before insert on private.coco_module_events for each row execute function private.coco_invoice_checkout_event_route();
