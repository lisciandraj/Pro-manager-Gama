-- Immutable, private analysis editions. PDF bytes are read separately from the
-- paginated list; neither public visitors nor cloud customers can access them.
insert into public.erp_reference_formats(kind,module_id,label_es,prefix,source_table,number_column,default_prefix) values('agent_report','assistant-ia','Informe de análisis Agent Coco','RCO',null,null,'RCO');
insert into private.erp_reference_counters(kind) values('agent_report');
insert into private.erp_reference_prefixes(prefix,kind) values('RCO','agent_report');
create table private.agent_reports(id uuid primary key default gen_random_uuid(),report_key text not null unique check(length(report_key) between 1 and 150),reference text not null unique,title text not null check(length(title) between 3 and 250),report_date date not null,period_from date,period_to date,languages text[] not null default array['fr','es'],source_filename text not null check(length(source_filename) between 1 and 255),sha256 text not null unique check(sha256~'^[0-9a-f]{64}$'),file_size integer not null check(file_size between 100 and 5242880),created_at timestamptz not null default now(),imported_by uuid references public.profiles(id),check(period_to is null or period_from is not null and period_from<=period_to),check(languages<@array['fr','es','en'] and cardinality(languages)>0));
create index agent_reports_by_date on private.agent_reports(report_date desc,created_at desc,id);
create index agent_reports_imported_by on private.agent_reports(imported_by);
create table private.agent_report_files(report_id uuid primary key references private.agent_reports(id),content bytea not null check(octet_length(content) between 100 and 5242880));
alter table private.agent_reports enable row level security;
alter table private.agent_report_files enable row level security;
revoke all on private.agent_reports,private.agent_report_files from public,anon,authenticated,service_role;
create function private.agent_report_import_data(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare bytes bytea;hash text;r private.agent_reports;report_id uuid;begin
 if length(coalesce(p_data->>'content_base64',''))>6990600 then raise exception 'REPORT_FILE_TOO_LARGE';end if;
 bytes:=decode(p_data->>'content_base64','base64');if bytes is null or octet_length(bytes) not between 100 and 5242880 or substring(bytes from 1 for 5)<>decode('255044462d','hex') or position(convert_to('%%EOF','UTF8') in bytes)=0 then raise exception 'REPORT_PDF_REQUIRED';end if;
 hash:=encode(sha256(bytes),'hex');if p_data->>'sha256' is not null and p_data->>'sha256'<>hash then raise exception 'REPORT_HASH_MISMATCH';end if;
 if length(btrim(coalesce(p_data->>'report_key','')))<1 or length(btrim(coalesce(p_data->>'title','')))<3 or nullif(p_data->>'report_date','') is null then raise exception 'REPORT_METADATA_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('agent-report-import',0));
 select * into r from private.agent_reports where report_key=p_data->>'report_key' or sha256=hash;
 if found then
  if r.sha256<>hash or r.report_date<>(p_data->>'report_date')::date or r.title<>btrim(p_data->>'title') then raise exception 'REPORT_EDITION_CONFLICT';end if;
  return jsonb_build_object('id',r.id,'reference',r.reference,'sha256',r.sha256,'existing',true);
 end if;
 report_id:=gen_random_uuid();
 insert into private.agent_reports(id,report_key,reference,title,report_date,period_from,period_to,languages,source_filename,sha256,file_size,imported_by) values(report_id,p_data->>'report_key',private.erp_issue_reference('agent_report',report_id::text),btrim(p_data->>'title'),(p_data->>'report_date')::date,nullif(p_data->>'period_from','')::date,nullif(p_data->>'period_to','')::date,case when jsonb_typeof(p_data->'languages')='array' then array(select jsonb_array_elements_text(p_data->'languages')) else array['fr','es'] end,coalesce(nullif(p_data->>'filename',''),'report.pdf'),hash,octet_length(bytes),auth.uid()) returning * into r;
 insert into private.agent_report_files(report_id,content) values(r.id,bytes);
 return jsonb_build_object('id',r.id,'reference',r.reference,'sha256',r.sha256,'existing',false);end $$;
create function private.gama_agent_reports(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.agent_reports;rows jsonb;total integer;offset_n integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));ascending boolean:=coalesce(p_data->>'order'='asc',false);begin
 -- Viewing is governed by role_module_access/app_modules. The action matrix
 -- governs create/edit/delete/validate/export and has no 'view' action.
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('assistant-ia',array['administrador']) then raise exception 'ADMIN_REQUIRED';end if;
 if p_action='list' then
  select count(*) into total from private.agent_reports;
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from(select id,reference,title,report_date,period_from,period_to,languages,file_size,created_at from private.agent_reports order by case when ascending then report_date end asc,case when not ascending then report_date end desc,created_at desc,id limit 25 offset offset_n) z;
  return jsonb_build_object('rows',rows,'total',total,'offset',offset_n,'page_size',25);
 elsif p_action='download' then
  if not private.erp_action_allowed('assistant-ia','export') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into r from private.agent_reports where id=(p_data->>'id')::uuid;if not found then raise exception 'REPORT_NOT_FOUND';end if;
  return jsonb_build_object('filename',r.reference||'.pdf','mime_type','application/pdf','sha256',r.sha256,'content_base64',(select encode(content,'base64') from private.agent_report_files where report_id=r.id));
 elsif p_action='import' then
  if not private.erp_action_allowed('assistant-ia','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
  return private.agent_report_import_data(p_data);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_agent_reports(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_agent_reports(p_action,p_data)$$;
revoke all on function private.agent_report_import_data(jsonb) from public,anon,authenticated,service_role;
revoke all on function private.gama_agent_reports(text,jsonb),public.gama_agent_reports(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_agent_reports(text,jsonb),public.gama_agent_reports(text,jsonb) to authenticated;
