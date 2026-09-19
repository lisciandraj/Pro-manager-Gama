-- SME service desk and private, versioned business documents.
create function private.service_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active and p.role in ('administrador','comercial')
 and not coalesce(module_id=any(a.disabled_modules),false)
 and not exists(select 1 from public.app_modules m where m.id=module_id and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false) and module_id in ('sav','documents')
$$;
revoke all on function private.service_access(text) from public,anon;
grant execute on function private.service_access(text) to authenticated;

create table public.service_tickets(
 id uuid primary key default gen_random_uuid(),
 number bigint generated always as identity unique,
 subject text not null check(length(btrim(subject)) between 1 and 200),
 description text not null check(length(btrim(description)) between 1 and 12000),
 customer_id uuid not null references public.customers(id),
 sales_order_id uuid references public.sales_orders(id),
 assigned_to uuid references public.profiles(id),
 status text not null default 'new' check(status in ('new','progress','waiting','resolved','closed')),
 priority text not null default 'normal' check(priority in ('normal','high','urgent')),
 category text not null default 'other' check(category in ('delivery','product','warranty','other')),
 warranty_until date,
 due_date date,
 resolution text not null default '' check(length(resolution)<=12000),
 archived boolean not null default false,
 version integer not null default 1,
 created_by uuid default auth.uid() references auth.users(id),
 updated_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 resolved_at timestamptz,
 check(status not in ('resolved','closed') or length(btrim(resolution))>0)
);
create table public.service_messages(
 id uuid primary key default gen_random_uuid(), ticket_id uuid not null references public.service_tickets(id),
 body text not null check(length(btrim(body)) between 1 and 12000),
 created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now()
);
create table public.service_events(
 id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.service_tickets(id),
 actor_id uuid references auth.users(id),created_at timestamptz not null default now(),changes jsonb not null
);
create table public.business_documents(
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(btrim(title)) between 1 and 200),
 folder text not null default 'General' check(length(btrim(folder)) between 1 and 80),
 notes text not null default '' check(length(notes)<=12000),
 visibility text not null default 'team' check(visibility in ('team','management')),
 customer_id uuid references public.customers(id),supplier_id uuid references public.suppliers(id),
 sales_order_id uuid references public.sales_orders(id),ticket_id uuid references public.service_tickets(id),
 expires_on date, archived boolean not null default false,version integer not null default 1,
 created_by uuid default auth.uid() references auth.users(id),updated_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.business_document_files(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references public.business_documents(id),
 revision integer not null,storage_path text not null unique,
 filename text not null check(length(btrim(filename)) between 1 and 240),
 mime_type text not null,file_size bigint not null check(file_size between 1 and 20971520),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),
 unique(document_id,revision)
);
-- Index foreign keys and the main work queues.
create index service_tickets_queue on public.service_tickets(archived,status,due_date);
create index business_documents_folder on public.business_documents(archived,folder);
do $$declare t text;c text;begin
 foreach t in array array['service_tickets','service_messages','service_events','business_documents','business_document_files'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  for c in select column_name from information_schema.columns where table_schema='public' and table_name=t and (column_name like '%\_id' escape '\' or column_name in ('created_by','updated_by','assigned_to')) and column_name<>'id' loop
   execute format('create index on public.%I(%I)',t,c);
  end loop;
 end loop;
end $$;
revoke all on sequence public.service_tickets_number_seq from anon,authenticated;
grant usage on sequence public.service_tickets_number_seq to authenticated;
grant select,insert,update on public.service_tickets,public.business_documents to authenticated;
grant select,insert on public.service_messages,public.business_document_files to authenticated;
grant select on public.service_events to authenticated;
create policy service_tickets_read on public.service_tickets for select to authenticated using((select private.service_access('sav')));
create policy service_tickets_create on public.service_tickets for insert to authenticated with check((select private.service_access('sav')));
create policy service_tickets_update on public.service_tickets for update to authenticated using((select private.service_access('sav'))) with check((select private.service_access('sav')));
create policy service_messages_read on public.service_messages for select to authenticated using((select private.service_access('sav')));
create policy service_messages_create on public.service_messages for insert to authenticated with check((select private.service_access('sav')) and created_by=auth.uid());
create policy service_events_read on public.service_events for select to authenticated using((select private.service_access('sav')));
create policy business_documents_read on public.business_documents for select to authenticated using(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador'));
create policy business_documents_create on public.business_documents for insert to authenticated with check(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador'));
create policy business_documents_update on public.business_documents for update to authenticated using(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador')) with check(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador'));
create policy business_files_read on public.business_document_files for select to authenticated using(exists(select 1 from public.business_documents d where d.id=document_id));
create policy business_files_create on public.business_document_files for insert to authenticated with check(exists(select 1 from public.business_documents d where d.id=document_id and not d.archived));

create function private.service_stamp() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='INSERT' then new.version:=1;new.created_by:=auth.uid();new.created_at:=now();
 else
  if new.id<>old.id then raise exception 'IMMUTABLE_ID';end if;
  new.version:=old.version+1;new.created_by:=old.created_by;new.created_at:=old.created_at;
 end if;
 new.updated_by:=auth.uid();new.updated_at:=clock_timestamp();
 if new.sales_order_id is not null and not exists(select 1 from public.sales_orders o where o.id=new.sales_order_id and o.customer_id=new.customer_id) then raise exception 'SERVICE_ORDER_CUSTOMER';end if;
 if tg_table_name='service_tickets' then
  if tg_op='UPDATE' then new.number:=old.number;end if;
  if new.assigned_to is not null and not exists(select 1 from public.gama_service_assignees() a where a.id=new.assigned_to) then raise exception 'SERVICE_ASSIGNEE';end if;
  if new.status in ('resolved','closed') then
   if tg_op='UPDATE' then new.resolved_at:=coalesce(old.resolved_at,now());else new.resolved_at:=now();end if;
  else new.resolved_at:=null;end if;
 else
  if new.ticket_id is not null and not exists(select 1 from public.service_tickets t where t.id=new.ticket_id and t.customer_id=new.customer_id and (new.sales_order_id is null or t.sales_order_id=new.sales_order_id)) then raise exception 'SERVICE_TICKET_CUSTOMER';end if;
 end if;
 return new;
end $$;
-- Only a minimal staff directory is exposed; profiles themselves retain existing RLS.
create function private.gama_service_assignees() returns table(id uuid,full_name text)
language sql stable security definer set search_path='' as $$
 select p.id,p.full_name from public.profiles p where auth.uid() is not null
 and private.service_access('sav') and p.active and p.role in ('administrador','comercial')
 order by p.full_name,p.id
$$;
-- The exposed wrapper remains invoker.
create function public.gama_service_assignees() returns table(id uuid,full_name text)
language sql stable security invoker set search_path='' as $$select * from private.gama_service_assignees()$$;
revoke all on function private.gama_service_assignees(),public.gama_service_assignees() from public,anon;
grant execute on function private.gama_service_assignees(),public.gama_service_assignees() to authenticated;
create trigger service_tickets_stamp before insert or update on public.service_tickets for each row execute function private.service_stamp();
create trigger business_documents_stamp before insert or update on public.business_documents for each row execute function private.service_stamp();
-- Append-only audit: operators cannot forge, edit or remove server events.
create function private.service_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 insert into public.service_events(ticket_id,actor_id,changes) values(new.id,auth.uid(),
 jsonb_build_object('event',lower(tg_op),'status',new.status,'priority',new.priority,'assigned_to',new.assigned_to,'archived',new.archived,'version',new.version));
 return new;
end $$;
revoke all on function private.service_audit() from public,anon,authenticated;
create trigger service_tickets_audit after insert or update on public.service_tickets for each row execute function private.service_audit();
create function private.service_message_stamp() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.service_tickets where id=new.ticket_id and not archived) then raise exception 'SERVICE_TICKET_UNAVAILABLE';end if;
 new.created_by:=auth.uid();new.created_at:=now();return new;
end $$;
create trigger service_messages_stamp before insert on public.service_messages for each row execute function private.service_message_stamp();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('business-documents','business-documents',false,20971520,
 array['application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy business_storage_upload on storage.objects for insert to authenticated with check(bucket_id='business-documents'
 and (private.service_access('documents') or private.service_access('sav')) and (storage.foldername(name))[1]=auth.uid()::text);
-- Cleanup must also see files hidden by document RLS: otherwise a restricted file could be deleted as an 'orphan'.
create function private.business_file_registered(path text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.business_document_files where storage_path=path)
$$;
revoke all on function private.business_file_registered(text) from public,anon;
grant execute on function private.business_file_registered(text) to authenticated;
create policy business_storage_read on storage.objects for select to authenticated using(bucket_id='business-documents' and (
 exists(select 1 from public.business_document_files f where f.storage_path=name)
 or ((storage.foldername(name))[1]=auth.uid()::text and (private.service_access('documents') or private.service_access('sav')) and not private.business_file_registered(name))));
create policy business_storage_cleanup on storage.objects for delete to authenticated using(bucket_id='business-documents'
 and (storage.foldername(name))[1]=auth.uid()::text and (private.service_access('documents') or private.service_access('sav')) and not private.business_file_registered(name));
create function private.business_file_validate() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.business_documents where id=new.document_id and not archived for update;
 if not found then raise exception 'DOCUMENT_UNAVAILABLE';end if;
 if split_part(new.storage_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='business-documents' and name=new.storage_path) then raise exception 'DOCUMENT_FILE_MISSING';end if;
 select coalesce(max(revision),0)+1 into new.revision from public.business_document_files where document_id=new.document_id;
 new.created_by:=auth.uid();new.created_at:=now();return new;
end $$;
create trigger business_files_validate before insert on public.business_document_files for each row execute function private.business_file_validate();
create function public.gama_save_business_document(p_document jsonb,p_version integer,p_file jsonb default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare d public.business_documents;doc_id uuid:=(p_document->>'id')::uuid;
begin
 if p_version=0 then
  if p_file is null then raise exception 'DOCUMENT_FILE_REQUIRED';end if;
  insert into public.business_documents(id,title,folder,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on)
  values(doc_id,p_document->>'title',p_document->>'folder',coalesce(p_document->>'notes',''),coalesce(p_document->>'visibility','team'),
  nullif(p_document->>'customer_id','')::uuid,nullif(p_document->>'supplier_id','')::uuid,nullif(p_document->>'sales_order_id','')::uuid,nullif(p_document->>'ticket_id','')::uuid,nullif(p_document->>'expires_on','')::date) returning * into d;
 else
  update public.business_documents set title=p_document->>'title',folder=p_document->>'folder',notes=coalesce(p_document->>'notes',''),
  visibility=coalesce(p_document->>'visibility','team'),customer_id=nullif(p_document->>'customer_id','')::uuid,supplier_id=nullif(p_document->>'supplier_id','')::uuid,
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
revoke all on function public.gama_save_business_document(jsonb,integer,jsonb) from public,anon;
grant execute on function public.gama_save_business_document(jsonb,integer,jsonb) to authenticated;
revoke all on function private.service_stamp(),private.service_message_stamp(),private.business_file_validate() from public,anon,authenticated;

alter table public.role_module_access drop constraint role_module_access_known;
alter table public.role_module_access add constraint role_module_access_known check(disabled_modules <@ array['sav','documents','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing']::text[] and array_position(disabled_modules,null) is null);

-- Preserve ticket/document relationships even when a restricted attachment is invisible to the editor.
alter table public.service_tickets add unique(id,customer_id),add unique(id,sales_order_id);
alter table public.business_documents add foreign key(ticket_id,customer_id) references public.service_tickets(id,customer_id),
 add foreign key(ticket_id,sales_order_id) references public.service_tickets(id,sales_order_id);
