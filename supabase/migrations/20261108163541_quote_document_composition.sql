-- Private, immutable PDF files and reusable quote assembly settings. No existing
-- quote, sales document, invoice, payment or stored file is rewritten.
create table private.quote_pdf_assets(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 filename text not null check(length(filename) between 1 and 200),storage_path text not null unique,
 file_size bigint not null check(file_size between 8 and 10485760),pages integer not null check(pages between 1 and 100),
 field_names jsonb not null default '[]',field_map jsonb not null default '{}',version integer not null default 1,
 active boolean not null default true,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table private.quote_pdf_layouts(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 cover_id uuid references private.quote_pdf_assets(id),footer_id uuid references private.quote_pdf_assets(id),
 include_product_documents boolean not null default true,version integer not null default 1,active boolean not null default true,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table private.quote_product_documents(
 id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),document_id uuid not null references private.quote_pdf_assets(id),
 position integer not null check(position between 0 and 9),created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),unique(product_id,document_id));
create table private.quote_pdf_selections(
 quote_id uuid primary key references public.invoices(id),layout_id uuid references private.quote_pdf_layouts(id),
 include_product_documents boolean not null default true,extra_document_ids uuid[] not null default '{}',version integer not null default 1,
 manifest jsonb,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now());
create table private.quote_pdf_revisions(
 id uuid primary key default gen_random_uuid(),quote_id uuid not null references public.invoices(id),quote_revision integer not null,
 manifest jsonb not null,created_at timestamptz not null default now(),unique(quote_id,quote_revision));
create table private.quote_pdf_commands(request_key uuid primary key,actor_id uuid not null references auth.users(id),action text not null,payload jsonb not null,result jsonb not null);
create index quote_pdf_selections_layout on private.quote_pdf_selections(layout_id);
create index quote_product_documents_asset on private.quote_product_documents(document_id);
do $$declare t text;begin foreach t in array array['quote_pdf_assets','quote_pdf_layouts','quote_product_documents','quote_pdf_selections','quote_pdf_revisions','quote_pdf_commands'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.quote_pdf_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and private.current_user_role() in('administrador','comercial')
  and private.erp_module_allowed('quotes',array['administrador','comercial'])
$$;
revoke all on function private.quote_pdf_allowed() from public,anon,service_role;grant execute on function private.quote_pdf_allowed() to authenticated;
create function private.quote_pdf_mapping_valid(names jsonb,mappings jsonb) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(names) is distinct from 'array' or jsonb_typeof(mappings) is distinct from 'object' then return false;end if;
 if jsonb_array_length(names)>100 or exists(select 1 from jsonb_array_elements(names)x where jsonb_typeof(x)<>'string' or length(x#>>'{}') not between 1 and 160) then return false;end if;
 return not exists(select 1 from jsonb_each_text(mappings) m where length(m.key) not between 1 and 160 or not names ? m.key or m.value not in(
  'quote.reference','quote.date','quote.valid_until','quote.client_name','quote.client_id','quote.client_address','quote.client_email','quote.currency','quote.subtotal','quote.tax','quote.total','item.name','item.reference','item.quantity'));
end $$;
revoke all on function private.quote_pdf_mapping_valid(jsonb,jsonb) from public,anon,authenticated,service_role;

-- A manifest copies each document's mapping/version, so editing a library entry
-- cannot silently change a finalized document's form fields or attachments.
create function private.quote_pdf_manifest(p_quote uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s private.quote_pdf_selections;l private.quote_pdf_layouts;docs jsonb;begin
 select * into s from private.quote_pdf_selections where quote_id=p_quote;if not found then return null;end if;
 if s.manifest is not null then return s.manifest;end if;
 if s.layout_id is not null then select * into l from private.quote_pdf_layouts where id=s.layout_id and active;if not found then raise exception 'PDF_LAYOUT_UNAVAILABLE';end if;end if;
 with requested as(
  select l.cover_id id,'cover'::text placement,null::uuid product_id,0 rank where l.cover_id is not null
  union all select d.document_id,'product',d.product_id,10+d.position from private.quote_product_documents d
   where s.include_product_documents and d.product_id in(select product_id from public.invoice_lines where invoice_id=p_quote)
  union all select e.id,'product',null::uuid,100+e.n::integer from unnest(s.extra_document_ids) with ordinality e(id,n)
  union all select l.footer_id,'footer',null::uuid,1000 where l.footer_id is not null)
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'storage_path',a.storage_path,'file_size',a.file_size,
  'pages',a.pages,'field_map',a.field_map,'version',a.version,'position',r.placement,'product_id',r.product_id) order by r.rank,r.product_id,a.id),'[]') into docs
 from requested r join private.quote_pdf_assets a on a.id=r.id and a.active;
 if jsonb_array_length(docs)>20 or (select coalesce(sum((x->>'pages')::integer),0) from jsonb_array_elements(docs)x)>250
  or (select coalesce(sum((x->>'file_size')::bigint),0) from jsonb_array_elements(docs)x)>40000000 then raise exception 'PDF_ATTACHMENT_LIMIT';end if;
 if l.cover_id is not null and not exists(select 1 from private.quote_pdf_assets where id=l.cover_id and active)
  or l.footer_id is not null and not exists(select 1 from private.quote_pdf_assets where id=l.footer_id and active)
  or exists(select 1 from unnest(s.extra_document_ids)d where not exists(select 1 from private.quote_pdf_assets a where a.id=d and active)) then raise exception 'PDF_DOCUMENT_UNAVAILABLE';end if;
 return jsonb_build_object('quote_id',p_quote,'selection_version',s.version,'documents',docs);
end $$;
create function private.quote_pdf_safe_manifest(p_quote uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin return private.quote_pdf_manifest(p_quote);exception when sqlstate 'P0001' then if sqlerrm like 'PDF\_%' escape '\' then return jsonb_build_object('quote_id',p_quote,'error',sqlerrm,'documents','[]'::jsonb);end if;raise;end $$;
revoke all on function private.quote_pdf_safe_manifest(uuid) from public,anon,authenticated,service_role;
revoke all on function private.quote_pdf_manifest(uuid) from public,anon,authenticated,service_role;
create function private.quote_pdf_quote_state() returns trigger language plpgsql security definer set search_path='' as $$
declare lid uuid;data jsonb;begin
 if new.quote_state='draft' and (tg_op='INSERT' or old.quote_state is distinct from 'draft') then
  update private.quote_pdf_selections set manifest=null,version=version+1,updated_at=now() where quote_id=new.id and manifest is not null;
 end if;
 if new.quote_state='draft' and nullif(new.quote_details->>'pdf_layout_id','') is not null
  and (tg_op='INSERT' or new.quote_details->>'pdf_layout_id' is distinct from old.quote_details->>'pdf_layout_id' or not exists(select 1 from private.quote_pdf_selections where quote_id=new.id)) then
  lid:=(new.quote_details->>'pdf_layout_id')::uuid;
  if not exists(select 1 from private.quote_pdf_layouts where id=lid and active and (created_by=auth.uid() or private.current_user_role()='administrador')) then raise exception 'PDF_LAYOUT_UNAVAILABLE';end if;
  insert into private.quote_pdf_selections(quote_id,layout_id,include_product_documents,updated_by)
   select new.id,l.id,l.include_product_documents,auth.uid() from private.quote_pdf_layouts l where id=lid
   on conflict(quote_id) do update set layout_id=excluded.layout_id,include_product_documents=excluded.include_product_documents,manifest=null,version=private.quote_pdf_selections.version+1,updated_by=auth.uid(),updated_at=now();
 end if;
 if new.quote_state in('sent','accepted') then
  data:=private.quote_pdf_manifest(new.id);
  if data is not null then
   update private.quote_pdf_selections set manifest=data where quote_id=new.id and manifest is null;
   insert into private.quote_pdf_revisions(quote_id,quote_revision,manifest) values(new.id,new.quote_revision,data) on conflict do nothing;
  end if;
 end if;return new;
end $$;
revoke all on function private.quote_pdf_quote_state() from public,anon,authenticated,service_role;
create trigger zz_quote_pdf_state after insert or update of quote_state,quote_details on public.invoices for each row execute function private.quote_pdf_quote_state();

create function private.gama_quote_documents(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare q public.invoices;a private.quote_pdf_assets;l private.quote_pdf_layouts;s private.quote_pdf_selections;tpl private.sales_templates;
 target_id uuid;key uuid;receipt private.quote_pdf_commands;result jsonb;meta jsonb;names jsonb;mapping jsonb;ids uuid[];product uuid;lid uuid;
 search text:=left(coalesce(p_data->>'search',''),120);off integer:=greatest(0,least(100000,coalesce((p_data->>'offset')::integer,0)));begin
 if not private.quote_pdf_allowed() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in('context','quote_context') then
  if p_action='quote_context' then
   select * into q from public.invoices where id=(p_data->>'quote_id')::uuid;if not found then raise exception 'QUOTE_NOT_FOUND';end if;
   select * into s from private.quote_pdf_selections where quote_id=q.id;
  end if;
  return jsonb_build_object('assets',coalesce((select jsonb_agg(to_jsonb(x)-'storage_path' order by x.name,x.id) from(select * from private.quote_pdf_assets a
   where (a.active or a.created_by=auth.uid() or private.current_user_role()='administrador') and (search='' or strpos(lower(a.name),lower(search))>0) order by name,id limit 50 offset off)x),'[]'),
   'total',(select count(*) from private.quote_pdf_assets a where (a.active or a.created_by=auth.uid() or private.current_user_role()='administrador') and (search='' or strpos(lower(a.name),lower(search))>0)),
   'layouts',coalesce((select jsonb_agg(to_jsonb(l) order by name,id) from private.quote_pdf_layouts l where (created_by=auth.uid() or private.current_user_role()='administrador')),'[]'),
   'selection',case when s.quote_id is not null then to_jsonb(s)-'manifest' else null end,
   'composition',case when q.id is not null then private.quote_pdf_safe_manifest(q.id) end,'quote_state',q.quote_state,
   'rights',jsonb_build_object('create',private.erp_action_allowed('quotes','create'),'edit',private.erp_action_allowed('quotes','edit'),'delete',private.erp_action_allowed('quotes','delete')));
 elsif p_action='assets_lookup' then
  select coalesce(array_agg(x::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(p_data->'ids','[]'))x;
  if cardinality(ids)>20 then raise exception 'PDF_ATTACHMENT_LIMIT';end if;
  return coalesce((select jsonb_agg(to_jsonb(a)-'storage_path' order by name,id) from private.quote_pdf_assets a where a.id=any(ids) and (active or created_by=auth.uid() or private.current_user_role()='administrador')),'[]');
 elsif p_action='templates' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,version,details->>'pdf_layout_id' layout_id from private.sales_templates where active and (created_by=auth.uid() or private.current_user_role()='administrador') and (search='' or strpos(lower(name),lower(search))>0) order by updated_at desc,id limit 100 offset off)x),'[]');
 elsif p_action='products' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.name,p.reference,coalesce((select jsonb_agg(document_id order by position) from private.quote_product_documents where product_id=p.id),'[]') documents
   from public.products p where p.active and (search='' or strpos(lower(concat_ws(' ',p.name,p.reference)),lower(search))>0) order by p.name,p.id limit 30)x),'[]');
 end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('quote-pdf-command:'||key,0));select * into receipt from private.quote_pdf_commands where request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.action<>p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if not private.erp_action_allowed('quotes',case when p_action='asset_register' or p_action='layout_save' and nullif(p_data->>'id','') is null then 'create' when p_action='asset_archive' then 'delete' else 'edit' end) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='asset_register' then
  if nullif(btrim(p_data->>'name'),'') is null or length(p_data->>'name')>120 then raise exception 'PDF_NAME_REQUIRED';end if;
  if p_data->>'storage_path' !~ ('^'||auth.uid()::text||'/[a-f0-9-]{36}$') then raise exception 'PDF_FILE_INVALID';end if;
  select to_jsonb(o)->'metadata' into meta from storage.objects o where bucket_id='quote-pdf-documents' and name=p_data->>'storage_path';
  if meta is null or coalesce(meta->>'mimetype','')<>'application/pdf' or coalesce(nullif(meta->>'size','')::bigint,0) not between 8 and 10485760 then raise exception 'PDF_FILE_INVALID';end if;
  names:=coalesce(p_data->'field_names','[]');mapping:=coalesce(p_data->'field_map','{}');
  if not private.quote_pdf_mapping_valid(names,mapping) then raise exception 'PDF_FIELD_MAPPING_INVALID';end if;
  insert into private.quote_pdf_assets(name,filename,storage_path,file_size,pages,field_names,field_map,created_by)
   values(btrim(p_data->>'name'),p_data->>'filename',p_data->>'storage_path',(meta->>'size')::bigint,(p_data->>'pages')::integer,names,mapping,auth.uid()) returning * into a;
  result:=to_jsonb(a)-'storage_path';
 elsif p_action in('asset_update','asset_archive') then
  select * into a from private.quote_pdf_assets where id=(p_data->>'id')::uuid for update;
  if not found or a.created_by<>auth.uid() and private.current_user_role()<>'administrador' then raise exception 'PDF_DOCUMENT_UNAVAILABLE';end if;
  if a.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  mapping:=coalesce(p_data->'field_map',a.field_map);if not private.quote_pdf_mapping_valid(a.field_names,mapping) then raise exception 'PDF_FIELD_MAPPING_INVALID';end if;
  update private.quote_pdf_assets set name=coalesce(nullif(btrim(p_data->>'name'),''),a.name),field_map=mapping,
   active=case when p_action='asset_archive' then false else coalesce((p_data->>'active')::boolean,a.active) end,version=version+1,updated_at=now() where id=a.id returning * into a;
  result:=to_jsonb(a)-'storage_path';
 elsif p_action='layout_save' then
  if nullif(btrim(p_data->>'name'),'') is null or length(p_data->>'name')>120 then raise exception 'PDF_NAME_REQUIRED';end if;
  target_id:=nullif(p_data->>'id','')::uuid;
  if target_id is not null then select * into l from private.quote_pdf_layouts where quote_pdf_layouts.id=target_id for update;if not found or l.created_by<>auth.uid() and private.current_user_role()<>'administrador' then raise exception 'PDF_LAYOUT_UNAVAILABLE';end if;if l.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;end if;
  if exists(select 1 from unnest(array[nullif(p_data->>'cover_id','')::uuid,nullif(p_data->>'footer_id','')::uuid]) x where x is not null and not exists(select 1 from private.quote_pdf_assets a where a.id=x and active)) then raise exception 'PDF_DOCUMENT_UNAVAILABLE';end if;
  if target_id is null then insert into private.quote_pdf_layouts(name,cover_id,footer_id,include_product_documents,active,created_by) values(btrim(p_data->>'name'),nullif(p_data->>'cover_id','')::uuid,nullif(p_data->>'footer_id','')::uuid,coalesce((p_data->>'include_product_documents')::boolean,true),coalesce((p_data->>'active')::boolean,true),auth.uid()) returning * into l;
  else update private.quote_pdf_layouts set name=btrim(p_data->>'name'),cover_id=nullif(p_data->>'cover_id','')::uuid,footer_id=nullif(p_data->>'footer_id','')::uuid,include_product_documents=coalesce((p_data->>'include_product_documents')::boolean,true),active=coalesce((p_data->>'active')::boolean,true),version=version+1,updated_at=now() where quote_pdf_layouts.id=target_id returning * into l;end if;
  result:=to_jsonb(l);
 elsif p_action='product_save' then
  if not private.erp_module_allowed('products',array['administrador','comercial']) or not private.erp_action_allowed('products','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  product:=(p_data->>'product_id')::uuid;perform 1 from public.products where products.id=product and active for update;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if jsonb_typeof(p_data->'expected_document_ids') is distinct from 'array' then raise exception 'RECORD_CHANGED';end if;
  if coalesce((select jsonb_agg(document_id order by position) from private.quote_product_documents where product_id=product),'[]'::jsonb) is distinct from p_data->'expected_document_ids' then raise exception 'RECORD_CHANGED';end if;
  select coalesce(array_agg(x::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(p_data->'document_ids','[]'))x;
  if cardinality(ids)>10 or cardinality(ids)<>(select count(distinct x) from unnest(ids)x) or exists(select 1 from unnest(ids)x where not exists(select 1 from private.quote_pdf_assets where quote_pdf_assets.id=x and active)) then raise exception 'PDF_DOCUMENT_UNAVAILABLE';end if;
  delete from private.quote_product_documents where product_id=product;
  insert into private.quote_product_documents(product_id,document_id,position,created_by) select product,x,(n-1)::integer,auth.uid() from unnest(ids) with ordinality d(x,n);
  result:=jsonb_build_object('ok',true);
 elsif p_action='selection_save' then
  select * into q from public.invoices where invoices.id=(p_data->>'quote_id')::uuid for update;if not found then raise exception 'QUOTE_NOT_FOUND';end if;
  if q.quote_state is distinct from 'draft' then raise exception 'QUOTE_LOCKED';end if;
  select * into s from private.quote_pdf_selections where quote_id=q.id for update;
  if coalesce(s.version,0) is distinct from coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  lid:=nullif(p_data->>'layout_id','')::uuid;
  if lid is not null and not exists(select 1 from private.quote_pdf_layouts where quote_pdf_layouts.id=lid and active and (created_by=auth.uid() or private.current_user_role()='administrador')) then raise exception 'PDF_LAYOUT_UNAVAILABLE';end if;
  select coalesce(array_agg(x::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(p_data->'extra_document_ids','[]'))x;
  if cardinality(ids)>10 or cardinality(ids)<>(select count(distinct x) from unnest(ids)x) then raise exception 'PDF_ATTACHMENT_LIMIT';end if;
  insert into private.quote_pdf_selections(quote_id,layout_id,include_product_documents,extra_document_ids,updated_by) values(q.id,lid,coalesce((p_data->>'include_product_documents')::boolean,true),ids,auth.uid())
   on conflict(quote_id) do update set layout_id=excluded.layout_id,include_product_documents=excluded.include_product_documents,extra_document_ids=excluded.extra_document_ids,manifest=null,version=private.quote_pdf_selections.version+1,updated_by=auth.uid(),updated_at=now();
  result:=private.quote_pdf_manifest(q.id);
 elsif p_action='template_save' then
  select * into tpl from private.sales_templates where sales_templates.id=(p_data->>'template_id')::uuid for update;
  if not found or tpl.created_by<>auth.uid() and private.current_user_role()<>'administrador' then raise exception 'NOT_FOUND';end if;if tpl.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  lid:=nullif(p_data->>'layout_id','')::uuid;
  if lid is not null and not exists(select 1 from private.quote_pdf_layouts where quote_pdf_layouts.id=lid and active and (created_by=auth.uid() or private.current_user_role()='administrador')) then raise exception 'PDF_LAYOUT_UNAVAILABLE';end if;
  update private.sales_templates set details=case when lid is null then details-'pdf_layout_id' else details||jsonb_build_object('pdf_layout_id',lid) end,version=version+1,updated_at=now() where sales_templates.id=tpl.id;
  result:=jsonb_build_object('ok',true);
 else raise exception 'UNKNOWN_ACTION';end if;
 insert into private.quote_pdf_commands values(key,auth.uid(),p_action,p_data,result);return result;
end $$;
create function public.gama_quote_documents(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_quote_documents(p_action,p_data)$$;
revoke all on function private.gama_quote_documents(text,jsonb),public.gama_quote_documents(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_quote_documents(text,jsonb),public.gama_quote_documents(text,jsonb) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('quote-pdf-documents','quote-pdf-documents',false,10485760,array['application/pdf']);
create function private.quote_pdf_file_readable(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select private.quote_pdf_allowed() and (
  split_part(p_path,'/',1)=auth.uid()::text and not exists(select 1 from private.quote_pdf_assets where storage_path=p_path)
  or exists(select 1 from private.quote_pdf_assets a where a.storage_path=p_path and (a.active or a.created_by=auth.uid() or private.current_user_role()='administrador'
   or exists(select 1 from private.quote_pdf_revisions r where r.manifest->'documents' @> jsonb_build_array(jsonb_build_object('id',a.id))))))
$$;
revoke all on function private.quote_pdf_file_readable(text) from public,anon,service_role;grant execute on function private.quote_pdf_file_readable(text) to authenticated;
create policy quote_pdf_upload on storage.objects for insert to authenticated with check(bucket_id='quote-pdf-documents' and private.quote_pdf_allowed() and private.erp_action_allowed('quotes','create') and split_part(name,'/',1)=auth.uid()::text);
create policy quote_pdf_read on storage.objects for select to authenticated using(bucket_id='quote-pdf-documents' and private.quote_pdf_file_readable(name));
create function private.quote_pdf_file_registered(p_path text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.quote_pdf_assets where storage_path=p_path)$$;
revoke all on function private.quote_pdf_file_registered(text) from public,anon,service_role;grant execute on function private.quote_pdf_file_registered(text) to authenticated;
create policy quote_pdf_cleanup on storage.objects for delete to authenticated using(bucket_id='quote-pdf-documents' and private.quote_pdf_allowed() and split_part(name,'/',1)=auth.uid()::text and not private.quote_pdf_file_registered(name));

-- Existing dossier guards run first; only authorized staff receive private PDF metadata.
do $$begin execute replace(pg_get_functiondef('private.gama_sales_dossier(text,jsonb)'::regprocedure),'FUNCTION private.gama_sales_dossier(', 'FUNCTION private.gama_sales_dossier_before_quote_documents(');end $$;
revoke all on function private.gama_sales_dossier_before_quote_documents(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_sales_dossier_before_quote_documents(text,jsonb) to authenticated;
create or replace function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;qid uuid;begin r:=private.gama_sales_dossier_before_quote_documents(p_action,p_data);
 if p_action='dossier' and private.quote_pdf_allowed() then qid:=coalesce(nullif(p_data->>'quote_id','')::uuid,nullif(r->>'quote_id','')::uuid);if qid is not null then r:=r||jsonb_build_object('document_composition',private.quote_pdf_safe_manifest(qid));end if;end if;return r;
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('quote_pdf_assets','quotes','Documento PDF comercial','private','id'),('quote_pdf_layouts','quotes','Diseño PDF comercial','private','id'),
 ('quote_product_documents','quotes','Ficha PDF del producto','private','id'),('quote_pdf_selections','quotes','Documentos PDF del presupuesto','private','quote_id');
do $$declare t text;begin foreach t in array array['quote_pdf_assets','quote_pdf_layouts','quote_product_documents','quote_pdf_selections'] loop execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);end loop;end $$;
create function private.quote_pdf_history_visible(p_table text,p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select private.quote_pdf_allowed() and case when p_table='quote_pdf_layouts' then exists(select 1 from private.quote_pdf_layouts where id::text=p_id and (created_by=auth.uid() or private.current_user_role()='administrador'))
 when p_table='quote_pdf_assets' then exists(select 1 from private.quote_pdf_assets where id::text=p_id and (active or created_by=auth.uid() or private.current_user_role()='administrador')) else true end
$$;
revoke all on function private.quote_pdf_history_visible(text,text) from public,anon,service_role;grant execute on function private.quote_pdf_history_visible(text,text) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_quote_documents(');end $$;
revoke all on function private.coco_history_record_visible_before_quote_documents(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_quote_documents(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in('quote_pdf_assets','quote_pdf_layouts','quote_product_documents','quote_pdf_selections') then return private.quote_pdf_history_visible(p_table,p_id);end if;
 return private.coco_history_record_visible_before_quote_documents(p_table,p_id,p_owner);
end $$;

do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_quote_documents(');end $$;
revoke all on function private.coco_history_typed_link_before_quote_documents(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_quote_documents(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language sql immutable security invoker set search_path='' as $$
 select case when p_table='quote_pdf_selections' then jsonb_build_object('module','quotes','action','quote','id',p_id,'reference',p_reference)
 when p_table in('quote_pdf_assets','quote_pdf_layouts','quote_product_documents') then jsonb_build_object('module','quotes','action','module')
 else private.coco_history_typed_link_before_quote_documents(p_module,p_table,p_id,p_reference) end
$$;
