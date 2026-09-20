-- One document index, original binaries retained in their owning module.
create or replace function private.service_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active and (p.role in ('administrador','comercial') or (module_id='documents' and p.role='almacenero'))
 and not coalesce(module_id=any(a.disabled_modules),false)
 and not exists(select 1 from public.app_modules m where m.id=module_id and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false) and module_id in ('sav','documents')
$$;
create table public.document_categories(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 80),
 created_by uuid default auth.uid() references auth.users(id),created_at timestamptz not null default now()
);
create unique index document_category_name on public.document_categories(lower(btrim(name)));
create index document_category_creator on public.document_categories(created_by);
alter table public.document_categories enable row level security;
revoke all on public.document_categories from anon,authenticated;
grant select,insert on public.document_categories to authenticated;
create policy document_categories_read on public.document_categories for select to authenticated using(private.service_access('documents') or private.service_access('sav'));
create policy document_categories_create on public.document_categories for insert to authenticated with check((private.service_access('documents') or private.service_access('sav')) and created_by=auth.uid());
insert into public.document_categories(name) select distinct on(lower(btrim(folder))) btrim(folder) from public.business_documents order by lower(btrim(folder));
insert into public.document_categories(name) select x from unnest(array['General','RH','Fleet','Proyectos','Facturas','Justificantes','Devoluciones','Entregas','SAV']) x on conflict do nothing;
alter table public.business_documents drop constraint business_documents_visibility_check;
alter table public.business_documents add constraint business_documents_visibility_check check(visibility in ('team','hr','management','source'));
alter table public.business_documents
 add column category_id uuid references public.document_categories(id),
 add column employee_id uuid references public.hr_employees(id) on delete set null,
 add column source_table text,
 add column source_id uuid,
 add column source_module text,
 add column source_record_id uuid,
 add column source_filename text,
 add column source_bucket text,
 add column source_path text,
 add column source_created_by uuid,
 add column source_deleted boolean not null default false,
 add constraint business_document_source_pair check((source_table is null)=(source_id is null)),
 add constraint business_document_source_known check(source_table is null or source_table in ('hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs'));
create unique index business_documents_source on public.business_documents(source_table,source_id);
create index business_documents_category on public.business_documents(category_id);
create index business_documents_employee on public.business_documents(employee_id);
create index business_documents_source_storage on public.business_documents(source_bucket,source_path);
update public.business_documents d set category_id=c.id from public.document_categories c where lower(btrim(d.folder))=lower(btrim(c.name));

create function private.document_audience(v text) returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and private.is_staff() and
 (v='team' or (v='management' and private.current_user_role()='administrador') or (v='hr' and private.hr_admin()))
$$;
-- This additional gate never replaces the owning module's authorization.
create function private.document_source_visible(t text,k uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.business_documents d
 where d.source_table=t and d.source_id=k and (d.source_deleted or (d.visibility<>'source' and not private.document_audience(d.visibility))))
$$;
create function private.document_original_access(d public.business_documents) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_staff() then return false;end if;
 case d.source_table
 when 'hr_documents' then return private.hr_admin() or private.hr_own(d.source_record_id);
 when 'fleet_documents' then return private.gama_fleet_may();
 when 'pm_files' then return private.pm_access(d.source_record_id);
 when 'expense_receipts' then return private.gama_accounting_may('view');
 when 'external_invoice_files' then return private.current_user_role() in ('administrador','comercial');
 when 'return_files','return_credits' then return private.current_user_role() in ('administrador','comercial','almacenero');
 when 'tms_proofs' then return private.current_user_role() in ('administrador','almacenero');
 else return false;end case;
end $$;
create function private.document_read(d public.business_documents) returns boolean language sql stable security invoker set search_path='' as $$
 select not d.source_deleted and (private.service_access('documents') or (d.ticket_id is not null and private.service_access('sav')))
 and (private.document_audience(d.visibility) or (d.visibility='source' and private.document_original_access(d)))
$$;
create function private.document_write(d public.business_documents) returns boolean language sql stable security invoker set search_path='' as $$
 select private.document_read(d) and (private.current_user_role()='administrador' or private.hr_admin()
 or (d.visibility='team' and coalesce(d.source_created_by,d.created_by)=auth.uid()))
$$;
do $$declare f regprocedure;begin
 for f in select oid::regprocedure from pg_proc where pronamespace='private'::regnamespace and proname in ('document_audience','document_source_visible','document_original_access','document_read','document_write') loop
 execute format('revoke all on function %s from public,anon',f);execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
drop policy business_documents_read on public.business_documents;
drop policy business_documents_create on public.business_documents;
drop policy business_documents_update on public.business_documents;
create policy business_documents_read on public.business_documents for select to authenticated using(private.document_read(business_documents));
create policy business_documents_create on public.business_documents for insert to authenticated with check(source_table is null and visibility<>'source' and private.document_write(business_documents));
create policy business_documents_update on public.business_documents for update to authenticated using(private.document_write(business_documents)) with check(private.document_write(business_documents));
-- Source identity is writable only by trusted synchronization triggers, never by an API client.
revoke insert,update on public.business_documents from authenticated;
grant insert(id,title,folder,category_id,employee_id,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on) on public.business_documents to authenticated;
grant update(title,folder,category_id,employee_id,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on,archived) on public.business_documents to authenticated;
drop policy business_files_create on public.business_document_files;
create policy business_files_create on public.business_document_files for insert to authenticated with check(exists(select 1 from public.business_documents d where d.id=document_id and not d.archived and d.source_table is null and private.document_write(d)));

create function private.document_category_stamp() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.category_id is null then
 select id into new.category_id from public.document_categories where lower(btrim(name))=lower(btrim(new.folder));
 if new.category_id is null then
 insert into public.document_categories(name) values(btrim(new.folder)) on conflict do nothing;
 select id into new.category_id from public.document_categories where lower(btrim(name))=lower(btrim(new.folder));
 end if;
 end if;
 select name into new.folder from public.document_categories where id=new.category_id;
 if new.folder is null then raise exception 'DOCUMENT_CATEGORY_REQUIRED';end if;
 return new;
end $$;
create trigger business_document_category before insert or update on public.business_documents for each row execute function private.document_category_stamp();
revoke all on function private.document_category_stamp() from public,anon,authenticated;

create or replace function public.gama_save_business_document(p_document jsonb,p_version integer,p_file jsonb default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare d public.business_documents;doc_id uuid:=(p_document->>'id')::uuid;
begin
 if p_version=0 then
 if p_file is null then raise exception 'DOCUMENT_FILE_REQUIRED';end if;
 insert into public.business_documents(id,title,folder,category_id,employee_id,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on)
 values(doc_id,p_document->>'title',coalesce(p_document->>'folder','General'),nullif(p_document->>'category_id','')::uuid,nullif(p_document->>'employee_id','')::uuid,coalesce(p_document->>'notes',''),coalesce(p_document->>'visibility','team'),nullif(p_document->>'customer_id','')::uuid,nullif(p_document->>'supplier_id','')::uuid,nullif(p_document->>'sales_order_id','')::uuid,nullif(p_document->>'ticket_id','')::uuid,nullif(p_document->>'expires_on','')::date) returning * into d;
 else
 update public.business_documents set title=p_document->>'title',folder=coalesce(p_document->>'folder','General'),
 category_id=nullif(p_document->>'category_id','')::uuid,employee_id=nullif(p_document->>'employee_id','')::uuid,
 notes=coalesce(p_document->>'notes',''),visibility=coalesce(p_document->>'visibility','team'),
 customer_id=nullif(p_document->>'customer_id','')::uuid,supplier_id=nullif(p_document->>'supplier_id','')::uuid,
 sales_order_id=nullif(p_document->>'sales_order_id','')::uuid,ticket_id=nullif(p_document->>'ticket_id','')::uuid,expires_on=nullif(p_document->>'expires_on','')::date,
 archived=coalesce((p_document->>'archived')::boolean,false) where id=doc_id and version=p_version returning * into d;
 if not found then raise exception 'SERVICE_CONFLICT';end if;
 end if;
 if p_file is not null then
 insert into public.business_document_files(document_id,storage_path,filename,mime_type,file_size,revision)
 values(doc_id,p_file->>'storage_path',p_file->>'filename',p_file->>'mime_type',(p_file->>'file_size')::bigint,1);
 end if;
 return to_jsonb(d);
end $$;

-- Minimal employee directory and trusted capabilities. No personal HR details exposed.
create function private.document_context() returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is not null and (private.service_access('documents') or private.service_access('sav')) then jsonb_build_object(
 'user_id',auth.uid(),'admin',private.current_user_role()='administrador','hr',private.hr_admin(),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'active',active) order by full_name) from public.hr_employees),'[]'::jsonb)) else null end
$$;
create function public.gama_document_context() returns jsonb language sql stable security invoker set search_path='' as $$select private.document_context()$$;
revoke all on function private.document_context(),public.gama_document_context() from public,anon;
grant execute on function private.document_context(),public.gama_document_context() to authenticated;

create function private.document_index(t text,j jsonb,deleted boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare k uuid:=coalesce(j->>'id',j->>'delivery_id')::uuid;cat text;mod text;parent uuid;emp uuid;bucket text;path text;fname text;present boolean;prev public.business_documents;
begin
 case t
 when 'hr_documents' then cat:='RH';mod:='hr';emp:=(j->>'employee_id')::uuid;parent:=emp;bucket:='hr-documents';path:=j->>'storage_path';present:=path is not null;
 when 'fleet_documents' then cat:='Fleet';mod:='fleet';parent:=(j->>'vehicle_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 when 'pm_files' then cat:='Proyectos';mod:='projects';parent:=(j->>'project_id')::uuid;bucket:='pm-documents';path:=j->>'storage_path';present:=path is not null or nullif(j->>'url','') is not null;
 when 'external_invoice_files' then cat:='Facturas';mod:='payments';parent:=(j->>'invoice_id')::uuid;present:=nullif(j->>'content_base64','') is not null;
 when 'expense_receipts' then cat:='Justificantes';mod:='accounting';parent:=(j->>'expense_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 when 'return_files','return_credits' then cat:='Devoluciones';mod:='returns';parent:=(j->>'return_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 when 'tms_proofs' then cat:='Entregas';mod:='tms';parent:=k;present:=nullif(j->>'photo','') is not null;
 else raise exception 'DOCUMENT_SOURCE_INVALID';end case;
 if deleted or not coalesce(present,false) then
 update public.business_documents set source_deleted=true,archived=true where source_table=t and source_id=k and not source_deleted;return;
 end if;
 fname:=coalesce(nullif(j->>'filename',''),case when t='tms_proofs' then 'Entrega-'||k::text||'.jpg' else cat end);
 if nullif(j->>'supersedes_id','') is not null then select * into prev from public.business_documents where source_table=t and source_id=(j->>'supersedes_id')::uuid;end if;
 insert into public.business_documents(title,folder,category_id,employee_id,visibility,expires_on,source_table,source_id,source_module,source_record_id,source_filename,source_bucket,source_path,source_created_by)
 values(left(coalesce(nullif(j->>'title',''),fname),200),cat,coalesce(prev.category_id,(select id from public.document_categories where name=cat)),emp,coalesce(prev.visibility,'source'),nullif(j->>'expires_on','')::date,t,k,mod,parent,fname,bucket,path,coalesce(nullif(j->>'created_by',''),nullif(j->>'captured_by',''))::uuid)
 on conflict(source_table,source_id) do update set source_record_id=excluded.source_record_id,source_filename=excluded.source_filename,source_bucket=excluded.source_bucket,source_path=excluded.source_path,source_deleted=false,
 expires_on=excluded.expires_on;
end $$;
create function private.document_index_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.document_index(tg_table_name,case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end,tg_op='DELETE');return null;end $$;
revoke all on function private.document_index(text,jsonb,boolean),private.document_index_trigger() from public,anon,authenticated;
-- Existing files are indexed with their original access rules, never made public by a migration.
do $$declare t text;r record;begin
 foreach t in array array['hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs'] loop
 for r in execute format('select to_jsonb(x) j from public.%I x',t) loop perform private.document_index(t,r.j);end loop;
 execute format('create trigger document_index after insert or update or delete on public.%I for each row execute function private.document_index_trigger()',t);
 end loop;
end $$;

-- Direct source-table reads must obey document confidentiality too.
do $$declare t text;begin
 foreach t in array array['hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files'] loop
 execute format('create policy document_confidentiality on public.%I as restrictive for select to authenticated using(private.document_source_visible(%L,id))',t,t);
 end loop;
end $$;
create function private.document_source_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb;oldj jsonb;k uuid;begin
 if auth.uid() is null then return case when tg_op='DELETE' then old else new end;end if;
 j:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_op<>'INSERT' then
 oldj:=to_jsonb(old);k:=coalesce(oldj->>'id',oldj->>'delivery_id')::uuid;
 if tg_op='DELETE' or (j->'data_url' is distinct from oldj->'data_url') or (j->'photo' is distinct from oldj->'photo') or (j->'storage_path' is distinct from oldj->'storage_path') or (j->'url' is distinct from oldj->'url') or (j->'content_base64' is distinct from oldj->'content_base64') then
 if not private.document_source_visible(tg_table_name,k) then raise exception 'DOCUMENT_UNAVAILABLE' using errcode='42501';end if;
 end if;
 end if;
 if nullif(j->>'supersedes_id','') is not null and not private.document_source_visible(tg_table_name,(j->>'supersedes_id')::uuid) then raise exception 'DOCUMENT_UNAVAILABLE' using errcode='42501';end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function private.document_source_guard() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs'] loop
 execute format('create trigger document_source_guard before insert or update or delete on public.%I for each row execute function private.document_source_guard()',t);
 end loop;
end $$;

-- Shared storage: extra read authorization only for a registered, visible document.
create function private.document_storage_allowed(b text,p text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.business_documents d where d.source_bucket=b and d.source_path=p and (d.source_deleted or (d.visibility<>'source' and not private.document_audience(d.visibility))))
$$;
create function private.document_storage_registered(b text,p text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.business_documents d where d.source_bucket=b and d.source_path=p and not d.source_deleted)
$$;
revoke all on function private.document_storage_allowed(text,text),private.document_storage_registered(text,text) from public,anon;
grant execute on function private.document_storage_allowed(text,text),private.document_storage_registered(text,text) to authenticated;
create policy document_storage_confidentiality on storage.objects as restrictive for select to authenticated using(private.document_storage_allowed(bucket_id,name));
create policy document_storage_shared on storage.objects for select to authenticated using(exists(select 1 from public.business_documents d where d.source_bucket=bucket_id and d.source_path=name and not d.source_deleted));
create policy document_storage_registered_cleanup on storage.objects as restrictive for delete to authenticated using(not private.document_storage_registered(bucket_id,name));

-- Delivery status/signatures and financial amounts remain available to their business workflows.
-- Only the attachment bytes are withdrawn from direct API column access.
revoke select on public.tms_proofs,public.return_credits from authenticated;
do $$declare t text;cols text;begin
 foreach t in array array['tms_proofs','return_credits'] loop
 select string_agg(quote_ident(column_name),',') into cols from information_schema.columns where table_schema='public' and table_name=t and column_name<>case when t='tms_proofs' then 'photo' else 'data_url' end;
 execute format('grant select(%s) on public.%I to authenticated',cols,t);
 end loop;
end $$;
create function private.document_proof_photo(k uuid) returns text language sql stable security definer set search_path='' as $$
 select p.photo from public.tms_proofs p where p.delivery_id=k and auth.uid() is not null
 and private.current_user_role() in ('administrador','almacenero') and private.document_source_visible('tms_proofs',k)
$$;
revoke all on function private.document_proof_photo(uuid) from public,anon;
grant execute on function private.document_proof_photo(uuid) to authenticated;
create view public.tms_proofs_read with(security_invoker=true) as select p.delivery_id,private.document_proof_photo(p.delivery_id) photo,p.signature,p.captured_at,p.captured_by from public.tms_proofs p;
revoke all on public.tms_proofs_read from anon,authenticated;
grant select on public.tms_proofs_read to authenticated;

create function private.document_download(k uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.business_documents;j jsonb;begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 select * into d from public.business_documents where id=k;
 if not found or not private.document_read(d) then raise exception 'DOCUMENT_UNAVAILABLE' using errcode='42501';end if;
 case d.source_table
 when 'hr_documents' then select jsonb_build_object('bucket','hr-documents','path',storage_path,'filename',filename) into j from public.hr_documents where id=d.source_id;
 when 'pm_files' then select jsonb_build_object('bucket','pm-documents','path',storage_path,'url',url,'filename',filename) into j from public.pm_files where id=d.source_id;
 when 'fleet_documents' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.fleet_documents where id=d.source_id;
 when 'external_invoice_files' then select jsonb_build_object('data_url','data:'||mime_type||';base64,'||content_base64,'filename',filename) into j from public.external_invoice_files where id=d.source_id;
 when 'expense_receipts' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.expense_receipts where id=d.source_id;
 when 'return_files' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.return_files where id=d.source_id;
 when 'return_credits' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.return_credits where id=d.source_id;
 when 'tms_proofs' then select jsonb_build_object('data_url',photo,'filename',d.source_filename) into j from public.tms_proofs where delivery_id=d.source_id;
 else raise exception 'DOCUMENT_SOURCE_INVALID';end case;
 if j is null then raise exception 'DOCUMENT_UNAVAILABLE';end if;return j;
end $$;
create function public.gama_document_download(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.document_download(p_id)$$;
revoke all on function private.document_download(uuid),public.gama_document_download(uuid) from public,anon;
grant execute on function private.document_download(uuid),public.gama_document_download(uuid) to authenticated;

-- Patch the existing SECURITY DEFINER readers, which intentionally bypass table RLS.
-- Assert each anchor: fail the migration instead of silently leaving an unprotected endpoint.
do $$declare f regprocedure;s text;old text;replacement text;r record;begin
 for r in select * from (values
 ('pm_action','from public.pm_files z where project_id=pid','from public.pm_files z where project_id=pid and private.document_source_visible(''pm_files'',z.id)'),
 ('gama_fleet_operations','from public.fleet_documents where id=(p_data->>''id'')::uuid;','from public.fleet_documents where id=(p_data->>''id'')::uuid and private.document_source_visible(''fleet_documents'',id);'),
 ('gama_accounting_expenses','from public.expense_receipts x where x.id=(p_data->>''id'')::uuid','from public.expense_receipts x where x.id=(p_data->>''id'')::uuid and private.document_source_visible(''expense_receipts'',x.id)'),
 ('gama_returns_settlement','from public.return_files where id=(p_data->>''file_id'')::uuid;','from public.return_files where id=(p_data->>''file_id'')::uuid and private.document_source_visible(''return_files'',id);'),
 ('gama_client_deliveries','''photo'',p.photo','''photo'',case when private.document_source_visible(''tms_proofs'',p.delivery_id) then p.photo else null end'),
 ('dashboard_access','''accounting'',''sav'',''documents'') or','''accounting'',''sav'') or')
 ) x(fn,anchor,replacement) loop
 select oid::regprocedure,pg_get_functiondef(oid) into f,s from pg_proc where pronamespace='private'::regnamespace and proname=r.fn;
 if position(r.anchor in s)=0 then raise exception 'DOCUMENT_PATCH_ANCHOR: %',r.fn;end if;
 execute replace(s,r.anchor,r.replacement);
 end loop;
end $$;
