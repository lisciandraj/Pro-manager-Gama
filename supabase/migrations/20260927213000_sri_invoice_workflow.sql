-- Fiscal documents are distinct from internal management invoices. Never expose
-- signing material or allow the browser to set an SRI authorization status.
create sequence private.sri_invoice_sequence;
revoke all on sequence private.sri_invoice_sequence from public, anon, authenticated;
alter table public.sri_settings add column provider_ruc text check(provider_ruc ~ '^[0-9]{13}$');

create table public.sri_invoice_issues (
 id uuid primary key default gen_random_uuid(),
 source_invoice_id uuid not null references public.external_invoices(id),
 customer_id uuid not null references public.customers(id),
 environment text not null check (environment in ('pruebas','produccion')),
 issuer_ruc text not null check (issuer_ruc ~ '^[0-9]{13}$'),
 establishment text not null check (establishment ~ '^[0-9]{3}$'),
 emission_point text not null check (emission_point ~ '^[0-9]{3}$'),
 sequential text not null check (sequential ~ '^[0-9]{9}$'),
 numeric_code text not null default lpad(floor(random()*100000000)::bigint::text,8,'0') check(numeric_code ~ '^[0-9]{8}$'),
 access_key text unique check (access_key ~ '^[0-9]{49}$'),
 status text not null default 'draft' check (status in ('draft','signed','received','processing','authorized','rejected','error')),
 snapshot jsonb not null,
 receipt jsonb,
 authorization_response jsonb,
 signed_xml_path text,
 authorized_xml_path text,
 ride_path text,
 sent_at timestamptz,
 authorized_at timestamptz,
 delivered_at timestamptz,
 last_error text,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (source_invoice_id),
 unique (environment, issuer_ruc, establishment, emission_point, sequential)
);
create index sri_invoice_issues_status_idx on public.sri_invoice_issues(status, created_at);
alter table public.sri_invoice_issues enable row level security;
revoke all on public.sri_invoice_issues from anon, authenticated;
grant select on public.sri_invoice_issues to authenticated;
create policy sri_invoice_issues_read on public.sri_invoice_issues for select to authenticated
 using (private.erp_module_allowed('accounting',array['administrador','comercial']));

-- The existing SRI scaffold allowed each user to replace signed XML and to
-- impersonate an invoice. Close its browser writes before enabling fiscal work.
drop policy if exists sri_docs_insert_own on public.sri_electronic_documents;
drop policy if exists sri_docs_update_own on public.sri_electronic_documents;
drop policy if exists sri_settings_insert_own on public.sri_settings;
drop policy if exists sri_settings_update_own on public.sri_settings;
drop policy if exists sri_settings_delete_own on public.sri_settings;
revoke insert,update,delete on public.sri_electronic_documents from authenticated;
revoke insert,update,delete on public.sri_settings from authenticated;

create function public.gama_sri_configure(p_environment text,p_establishment text,p_emission_point text,
 p_provider_ruc text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings; result public.sri_settings;
begin
 if auth.uid() is null or private.current_user_role()<>'administrador' or
    not private.erp_module_allowed('accounting',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED'; end if;
 select * into cfg from public.company_settings where id=true;
 if cfg.country<>'EC' or cfg.tax_id !~ '^[0-9]{13}$' or length(btrim(cfg.legal_name))=0
    or length(btrim(cfg.address))=0 then raise exception 'COMPANY_IDENTITY_INCOMPLETE'; end if;
 if p_environment not in ('pruebas','produccion') or p_establishment !~ '^[0-9]{3}$'
    or p_emission_point !~ '^[0-9]{3}$' or p_provider_ruc is null or p_provider_ruc !~ '^[0-9]{13}$'
 then raise exception 'SRI_CONFIGURATION_INVALID'; end if;
 insert into public.sri_settings(user_id,environment,ruc,razon_social,estab,pto_emi,dir_matriz,email,provider_ruc)
 values(auth.uid(),p_environment,cfg.tax_id,cfg.legal_name,p_establishment,p_emission_point,cfg.address,cfg.email,p_provider_ruc)
 on conflict(user_id) do update set environment=excluded.environment,ruc=excluded.ruc,
 razon_social=excluded.razon_social,estab=excluded.estab,pto_emi=excluded.pto_emi,
 dir_matriz=excluded.dir_matriz,email=excluded.email,provider_ruc=excluded.provider_ruc
 returning * into result;
 return jsonb_build_object('environment',result.environment,'establishment',result.estab,'emission_point',result.pto_emi);
end $$;
revoke all on function public.gama_sri_configure(text,text,text,text) from public,anon;
grant execute on function public.gama_sri_configure(text,text,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('sri-documents','sri-documents',false,1048576,array['application/xml','application/pdf'])
 on conflict(id) do nothing;

create function public.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare v public.external_invoices; o public.sales_orders; c public.customers;
 cfg public.company_settings; old_issue public.sri_invoice_issues; s public.sri_settings;
 lines jsonb; seq text; result public.sri_invoice_issues;
begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador'])
   or private.current_user_role() <> 'administrador' then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_payment_code is null or p_payment_code not in ('01','16','19','20') then raise exception 'SRI_PAYMENT_CODE_REQUIRED'; end if;
 select * into v from public.external_invoices where id=p_invoice_id for update;
 if not found or v.document_kind<>'internal' or v.fiscal_status<>'unverified'
    or v.external_number is not null then raise exception 'SRI_SOURCE_INVOICE_INVALID'; end if;
 select * into old_issue from public.sri_invoice_issues where source_invoice_id=p_invoice_id;
 if found then return jsonb_build_object('id',old_issue.id,'status',old_issue.status); end if;
 select * into o from public.sales_orders where id=v.order_id;
 select * into c from public.customers where id=o.customer_id;
 select * into cfg from public.company_settings where id=true;
 select * into s from public.sri_settings where user_id=auth.uid();
 if cfg.country<>'EC' or not cfg.configured or cfg.tax_id !~ '^[0-9]{13}$'
    or s.id is null or s.ruc<>cfg.tax_id or s.estab !~ '^[0-9]{3}$' or s.pto_emi !~ '^[0-9]{3}$'
    or length(btrim(coalesce(s.razon_social,'')))=0 or length(btrim(coalesce(s.dir_matriz,'')))=0
    or s.provider_ruc is null
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE'; end if;
 if c.identification is null or c.identification !~ '^[0-9]{10,13}$'
   or length(btrim(c.name))=0 or length(btrim(coalesce(c.address,'')))=0
 then raise exception 'SRI_CUSTOMER_INCOMPLETE'; end if;
 select jsonb_agg(jsonb_build_object('code',ol.reference,'description',ol.product_name,
   'quantity',il.quantity,'unit_price',ol.unit_price,'tax_rate',ol.tax_rate,
   'subtotal',round(il.quantity*ol.unit_price,2)) order by il.id) into lines
 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
 where il.invoice_id=v.id;
 if lines is null then raise exception 'SRI_LINES_MISSING'; end if;
 if exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
   where il.invoice_id=v.id and ol.tax_rate not in (0,5,12,13,14,15)) then raise exception 'SRI_UNSUPPORTED_TAX_RATE'; end if;
 -- The legal 9-digit sequence is independent of Coco's internal FAC number.
 seq:=lpad(nextval('private.sri_invoice_sequence')::text,9,'0');
 insert into public.sri_invoice_issues(source_invoice_id,customer_id,environment,issuer_ruc,
   establishment,emission_point,sequential,created_by,snapshot)
 values(v.id,c.id,s.environment,s.ruc,s.estab,s.pto_emi,seq,auth.uid(),
  jsonb_build_object('issue_date',v.issue_date,'source_number',v.number,'issuer',s.razon_social,
    'provider_ruc',s.provider_ruc,'payment_code',p_payment_code,
    'address',s.dir_matriz,'customer',c.name,'identification',c.identification,
    'customer_address',c.address,'customer_email',c.email,'subtotal',v.subtotal,
    'tax',v.tax,'total',v.total,'lines',lines)) returning * into result;
 return jsonb_build_object('id',result.id,'status',result.status);
end $$;
revoke all on function public.gama_sri_prepare(uuid,text) from public,anon;
grant execute on function public.gama_sri_prepare(uuid,text) to authenticated;

create function private.gama_sri_protect_internal_invoice() returns trigger
 language plpgsql set search_path='' as $$
begin
 if old.document_kind='internal' and exists(select 1 from public.sri_invoice_issues
    where source_invoice_id=old.id and status<>'rejected') then
  if new.fiscal_status='cancelled' and old.fiscal_status<>'cancelled' then
   raise exception 'SRI_INVOICE_CANNOT_CANCEL_LOCALLY'; end if;
  if new.external_number is distinct from old.external_number and current_user<>'service_role' then
   raise exception 'SRI_EXTERNAL_REFERENCE_LOCKED'; end if;
 end if;
 return new;
end $$;
revoke all on function private.gama_sri_protect_internal_invoice() from public,anon,authenticated;
create trigger sri_protect_internal_invoice before update on public.external_invoices
 for each row execute function private.gama_sri_protect_internal_invoice();
