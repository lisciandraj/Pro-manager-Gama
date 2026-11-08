do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>261
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261005165044_agent_coco_report_archive.sql; SHA256 3dbeadea989d27de23524aa15286097a04b6dc56aaf717e43f885b5688b5c9f8
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005165044','agent_coco_report_archive','3dbeadea989d27de23524aa15286097a04b6dc56aaf717e43f885b5688b5c9f8','3dbeadea989d27de23524aa15286097a04b6dc56aaf717e43f885b5688b5c9f8','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005190428_manual_mail_and_waze.sql; SHA256 101d027fcd93aee34e4ffaad678145f47464fbb707abbe9a725bc0f093df6744
-- User-requested handoff: mail drafts in Gmail/Outlook and Waze navigation.
-- Historical delivery evidence and verified schedules remain immutable.
select cron.unschedule('coco-message-dispatch');
select cron.unschedule('coco-road-matrix');
update private.message_provider set enabled=false;
update private.tms_road_provider set enabled=false;
alter table private.message_outbox drop constraint message_outbox_state_check;
alter table private.message_outbox add constraint message_outbox_state_check check(state in ('queued','draft','sent_manually','dispatching','accepted','delivered','bounced','complained','failed','cancelled','uncertain'));
alter table private.message_outbox alter column state set default 'draft';
alter table private.message_outbox add column manual_sent_at timestamptz;
alter table private.message_outbox add column manual_sent_by uuid references public.profiles(id);
create index message_manual_sender on private.message_outbox(manual_sent_by);
update private.message_outbox set state='draft',error_code=null where state in ('queued','failed') and attempts=0 and request_id is null and first_sent_at is null;
update private.message_outbox set state='uncertain',error_code='MANUAL_REVIEW_REQUIRED' where state='dispatching';
create or replace function private.message_dispatch() returns jsonb language sql security definer set search_path='' as $$select jsonb_build_object('mode','manual','dispatched',0)$$;
create or replace function private.tms_road_poll() returns jsonb language sql security definer set search_path='' as $$select jsonb_build_object('provider','waze','matrices_ready',0)$$;
create or replace function private.tms_road_prepare(p_day date) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_day is null or p_day<(now() at time zone private.erp_timezone())::date or p_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 return jsonb_build_object('provider','waze','navigation_only',true,'api_key_required',false);end $$;
create or replace function private.tms_road_metric(a double precision,b double precision,c double precision,d double precision) returns jsonb language sql stable security definer set search_path='' as $$select null::jsonb$$;
create or replace function private.automation_reminders(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row record;days integer:=greatest(1,least(coalesce((p_config->>'interval_days')::integer,7),90));n integer:=0;slot bigint:=floor(extract(epoch from now())/(86400*days));begin
 if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 for row in select r.*,c.email outbound_email from private.gama_receivables r join public.customers c on c.id=r.customer_id join private.customer_message_preferences p on p.customer_id=c.id and p.invoice_reminders where c.active and r.balance>0 and r.due_date<current_date and c.email~'^[^\s@]+@[^\s@]+\.[^\s@]+$' order by r.due_date,r.id limit 100 loop
  insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,source_amount,subject,body) values('invoice:'||row.id||':'||slot,'invoice_reminder',row.customer_id,row.id,p_job.id,auth.uid(),p_job.rule_version,row.outbound_email,row.balance,'GAMA · saldo pendiente '||row.number,'Hola '||row.customer_name||E',\nLa factura '||row.number||' tiene un saldo pendiente de USD '||row.balance||E'.\nSi ya has pagado, envíanos el comprobante para actualizar el registro.\nPuedes consultar tus documentos en https://gama-coco.pages.dev/b2b.html') on conflict(key) do nothing;n:=n+1;
 end loop;return jsonb_build_object('prepared',n);end $$;
create or replace function private.automation_surveys(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid:=nullif(p_config->>'survey_id','')::uuid;s private.surveys;row record;inv jsonb;n integer:=0;begin
 if not private.erp_action_allowed('surveys','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into s from private.surveys where id=sid and state='open' and (closes_at is null or closes_at>now());if not found then return jsonb_build_object('blocked',true,'reason','PUBLISHED_SURVEY_REQUIRED');end if;
 for row in select distinct c.id,c.email from public.customers c join private.customer_message_preferences pref on pref.customer_id=c.id and pref.surveys where c.active and c.email~'^[^\s@]+@[^\s@]+\.[^\s@]+$' and (exists(select 1 from public.tms_deliveries d where d.customer_id=c.id and d.status='Entregada' and d.delivery_date>=current_date-30) or exists(select 1 from public.service_tickets t where t.customer_id=c.id and t.status in ('resolved','closed') and t.resolved_at>=now()-interval '30 days')) order by c.id limit 100 loop
  inv:=private.gama_surveys('invite',jsonb_build_object('id',sid,'kind','customer','contact_id',row.id));
  if not exists(select 1 from private.survey_responses where invitation_id=(inv->>'id')::uuid) then
   insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,subject,body) values('survey:'||(inv->>'id'),'survey',row.id,(inv->>'id')::uuid,p_job.id,auth.uid(),p_job.rule_version,row.email,'GAMA · '||s.title,E'Gracias por confiar en GAMA. Puedes compartir tu experiencia aquí:\nhttps://gama-coco.pages.dev/surveys.html#'||(inv->>'token')) on conflict(key) do nothing;n:=n+1;
  end if;
 end loop;return jsonb_build_object('prepared',n);end $$;
create function private.message_draft_valid(m private.message_outbox) returns boolean language plpgsql stable security definer set search_path='' as $$
declare valid boolean;begin
 select exists(select 1 from public.customers c join private.customer_message_preferences p on p.customer_id=c.id where c.id=m.customer_id and c.active and c.email=m.recipient and case m.kind when 'invoice_reminder' then p.invoice_reminders else p.surveys end) and exists(select 1 from private.automation_jobs j join private.automation_rules r on r.kind=j.kind and r.version=j.rule_version join public.profiles a on a.id=m.actor join auth.users u on u.id=a.id where j.id=m.job_id and r.enabled and r.version=m.rule_version and r.version=(select max(version) from private.automation_rules where kind=r.kind) and r.executor=m.actor and r.approved_until>now() and a.active and a.role='administrador' and a.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) into valid;
 if m.kind='invoice_reminder' then return valid and exists(select 1 from private.gama_receivables r where r.id=m.source_id and r.customer_id=m.customer_id and r.balance=m.source_amount and r.balance>0 and r.due_date<current_date);end if;
 return valid and exists(select 1 from private.survey_invitations i join private.surveys s on s.id=i.survey_id where i.id=m.source_id and not i.revoked and s.state='open' and (s.closes_at is null or s.closes_at>now()) and not exists(select 1 from private.survey_responses r where r.invitation_id=i.id));end $$;
revoke all on function private.message_draft_valid(private.message_outbox) from public,anon,authenticated,service_role;
alter function private.gama_messages(text,jsonb) rename to gama_messages_before_manual;
revoke all on function private.gama_messages_before_manual(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_messages(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare m private.message_outbox;rows jsonb;module text;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='configure' then raise exception 'MANUAL_MAIL_ONLY';
 elsif p_action='context' then
  update private.message_outbox x set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where x.state='draft' and private.automation_visible(case x.kind when 'survey' then 'surveys' else 'payments' end) and not private.message_draft_valid(x);
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from(select id,kind,customer_id,source_id,state,recipient,subject,manual_sent_at,manual_sent_by,error_code,created_at,updated_at from private.message_outbox x where private.automation_visible(case x.kind when 'survey' then 'surveys' else 'payments' end) order by case when state='draft' then 0 else 1 end,created_at desc,id limit 100)z;
  return jsonb_build_object('mode','manual','outbox',rows);
 elsif p_action in ('draft','manual_sent') then
  select * into m from private.message_outbox where id=(p_data->>'id')::uuid for update;if not found then raise exception 'MESSAGE_NOT_FOUND';end if;
  module:=case m.kind when 'survey' then 'surveys' else 'payments' end;
  if not private.automation_visible(module) or not private.erp_action_allowed(module,case m.kind when 'survey' then 'edit' else 'create' end) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='manual_sent' and not coalesce((p_data->>'confirmed')::boolean,false) then raise exception 'MANUAL_SEND_CONFIRMATION_REQUIRED';end if;
  if m.state='sent_manually' then return jsonb_build_object('id',m.id,'state',m.state,'manual_sent_at',m.manual_sent_at,'manual_sent_by',m.manual_sent_by);end if;
  if m.state<>'draft' then raise exception 'MESSAGE_NOT_AVAILABLE';end if;
  if not private.message_draft_valid(m) then update private.message_outbox set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where id=m.id;return jsonb_build_object('id',m.id,'state','cancelled');end if;
  if m.recipient !~ '^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' then raise exception 'MESSAGE_RECIPIENT_INVALID';end if;
  if p_action='draft' then return jsonb_build_object('id',m.id,'state',m.state,'recipient',m.recipient,'subject',m.subject,'body',m.body);end if;
  update private.message_outbox set state='sent_manually',manual_sent_at=now(),manual_sent_by=auth.uid(),updated_at=now() where id=m.id returning * into m;
  return jsonb_build_object('id',m.id,'state',m.state,'manual_sent_at',m.manual_sent_at,'manual_sent_by',m.manual_sent_by);
 end if;return private.gama_messages_before_manual(p_action,p_data);end $$;
revoke all on function private.gama_messages(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_messages(text,jsonb) to authenticated;
create or replace function private.gama_tms_roads(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('context','configure','disable') then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='configure' then raise exception 'WAZE_NAVIGATION_ONLY';end if;
  return jsonb_build_object('provider',jsonb_build_object('name','waze','configured',true,'api_key_required',false,'navigation_only',true),'requests','[]'::jsonb);
 elsif p_action='prepare' then return private.tms_road_prepare((p_data->>'day')::date);
 elsif p_action='route' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
  return jsonb_build_object('navigation_provider','waze','source','manual','legs','[]'::jsonb,'missing',jsonb_array_length(r.stops));
 end if;raise exception 'INVALID_ACTION';end $$;
-- Renamed definer functions keep their original privilege revocations. The two
-- historical public invoker facades continue resolving the new implementations.

create or replace function public.gama_messages(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_messages(p_action,p_data)$$;
create or replace function public.gama_tms_roads(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_roads(p_action,p_data)$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005190428','manual_mail_and_waze','101d027fcd93aee34e4ffaad678145f47464fbb707abbe9a725bc0f093df6744','101d027fcd93aee34e4ffaad678145f47464fbb707abbe9a725bc0f093df6744','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005230102_tms_execution_phase1.sql; SHA256 fc9a02827e4ef243a441c7e00559768b7e6aa388853a6a430782b99a15e7cb4a
-- TMS execution: additive history, account-scoped access and explicit received quantities.
create table private.tms_user_scopes (
 profile_id uuid primary key references public.profiles(id),
 role text not null check(role in ('dispatcher','driver','manager')),
 active boolean not null default true,
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id)
);
alter table private.tms_user_scopes enable row level security;
revoke all on private.tms_user_scopes from public,anon,authenticated;

create function private.tms_scope() returns text language plpgsql stable security definer set search_path='' as $$
declare scope text;enabled boolean;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then return null;end if;
 if private.current_user_role()='administrador' then return 'manager';end if;
 select s.role,s.active into scope,enabled from private.tms_user_scopes s where s.profile_id=auth.uid();
 if found then return case when enabled then scope else null end;end if;
 if exists(select 1 from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.active and h.active and h.profile_id=auth.uid()) then return 'driver';end if;
 return 'dispatcher';
end $$;
create function private.tms_own_driver() returns uuid language sql stable security definer set search_path='' as $$
 select f.id from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where auth.uid() is not null and f.active and h.active and h.profile_id=auth.uid() order by f.id limit 1
$$;
create function private.tms_can_read(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.tms_scope() in ('dispatcher','manager') or (private.tms_scope()='driver' and exists(select 1 from public.tms_deliveries d where d.id=p_delivery and d.driver_id=private.tms_own_driver())),false)
$$;
create function private.tms_can_route(p_route uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.tms_scope() in ('dispatcher','manager') or (private.tms_scope()='driver' and exists(select 1 from public.tms_routes r where r.id=p_route and r.driver_id=private.tms_own_driver())),false)
$$;
create function private.tms_require(p_delivery uuid default null,p_dispatch boolean default false,p_action text default 'read') returns void language plpgsql stable security definer set search_path='' as $$
begin
 if private.tms_scope() is null then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_dispatch and private.tms_scope() not in ('dispatcher','manager') then raise exception 'TMS_DISPATCH_REQUIRED';end if;
 if p_delivery is not null and not private.tms_can_read(p_delivery) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action<>'read' and not private.erp_action_allowed('tms',p_action) then raise exception 'ACTION_NOT_ALLOWED:tms:%',p_action;end if;
end $$;
revoke all on function private.tms_scope(),private.tms_own_driver(),private.tms_can_read(uuid),private.tms_can_route(uuid),private.tms_require(uuid,boolean,text) from public,anon;
grant execute on function private.tms_scope(),private.tms_own_driver(),private.tms_can_read(uuid),private.tms_can_route(uuid),private.tms_require(uuid,boolean,text) to authenticated;

alter table public.tms_deliveries add column version integer not null default 1,
 add column promised_from timestamptz,add column promised_until timestamptz,
 add column initial_promised_from timestamptz,add column initial_promised_until timestamptz,
 add column settled_at timestamptz,add column settled_by uuid references public.profiles(id),add column settlement_note text,add column invoice_reviewed_at timestamptz,
 add column cargo_verified_at timestamptz,add column cargo_verified_by uuid references public.profiles(id),
 add constraint tms_promise_order check(promised_from is null or promised_until>promised_from),
 add constraint tms_promise_complete check((promised_from is null)=(promised_until is null));
alter table public.tms_routes add column closed_at timestamptz,add column closed_by uuid references public.profiles(id);
create table public.tms_delivery_attempts (
 id uuid primary key default gen_random_uuid(),delivery_id uuid not null references public.tms_deliveries(id),
 route_id uuid references public.tms_routes(id),driver_id uuid references public.fleet_drivers(id),
 attempt_no integer not null check(attempt_no>0),request_key uuid not null unique,
 result text not null check(result in ('complete','partial','failed')),
 receiver_name text not null default '' check(length(receiver_name)<=160),reason text check(length(reason)<=2000),
 occurred_at timestamptz not null,received_at timestamptz not null default now(),
 actor_id uuid not null references public.profiles(id),base_version integer not null,
 gps jsonb not null default '{}',return_id uuid references public.return_orders(id),
 unique(delivery_id,attempt_no)
);
create table public.tms_attempt_lines (
 attempt_id uuid not null references public.tms_delivery_attempts(id),delivery_line_id uuid not null references public.sales_delivery_lines(id),
 quantity numeric not null check(quantity>0),accepted numeric not null check(accepted>=0),refused numeric not null check(refused>=0),
 missing numeric not null check(missing>=0),deferred numeric not null check(deferred>=0),
 primary key(attempt_id,delivery_line_id),check(quantity=accepted+refused+missing+deferred)
);
create table public.tms_attempt_proofs (
 id uuid primary key default gen_random_uuid(),attempt_id uuid not null references public.tms_delivery_attempts(id),
 kind text not null check(kind in ('signature','photo')),object_path text,
 content_hash text not null,byte_size integer not null check(byte_size>0),
 created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id),
 unique(attempt_id,kind)
);
-- Compatibility proof data is retained, while each attempt keeps immutable evidence.
create table private.tms_attempt_media (
 proof_id uuid primary key references public.tms_attempt_proofs(id),data_url text not null
);
alter table private.tms_attempt_media enable row level security;
revoke all on private.tms_attempt_media from public,anon,authenticated;
alter table public.tms_events add column attempt_id uuid references public.tms_delivery_attempts(id),add column detail jsonb;
alter table public.tms_delivery_incidents add column attempt_id uuid references public.tms_delivery_attempts(id),add column resolved_at timestamptz,add column resolved_by uuid references public.profiles(id),add column resolution text;
create index tms_attempts_route on public.tms_delivery_attempts(route_id);
create index tms_attempts_driver on public.tms_delivery_attempts(driver_id,occurred_at);
create index tms_attempts_actor on public.tms_delivery_attempts(actor_id);
create index tms_attempt_lines_delivery on public.tms_attempt_lines(delivery_line_id);
create index tms_attempt_proofs_actor on public.tms_attempt_proofs(created_by);
create index tms_events_attempt on public.tms_events(attempt_id);
create index tms_incidents_attempt on public.tms_delivery_incidents(attempt_id);
create index tms_deliveries_promise on public.tms_deliveries(initial_promised_until) where initial_promised_until is not null;

alter table public.tms_delivery_attempts enable row level security;
alter table public.tms_attempt_lines enable row level security;
alter table public.tms_attempt_proofs enable row level security;
revoke all on public.tms_delivery_attempts,public.tms_attempt_lines,public.tms_attempt_proofs from public,anon,authenticated;
grant select on public.tms_delivery_attempts,public.tms_attempt_lines,public.tms_attempt_proofs to authenticated;
create policy tms_attempts_read on public.tms_delivery_attempts for select to authenticated using(private.tms_can_read(delivery_id));
create policy tms_attempt_lines_read on public.tms_attempt_lines for select to authenticated using(exists(select 1 from public.tms_delivery_attempts a where a.id=attempt_id));
create policy tms_attempt_proofs_read on public.tms_attempt_proofs for select to authenticated using(exists(select 1 from public.tms_delivery_attempts a where a.id=attempt_id));
create policy tms_delivery_scope on public.tms_deliveries as restrictive for all to authenticated using(private.tms_can_read(id)) with check(private.tms_scope() in ('dispatcher','manager'));
create policy tms_route_scope on public.tms_routes as restrictive for all to authenticated using(private.tms_can_route(id)) with check(private.tms_scope() in ('dispatcher','manager'));
create policy tms_delivery_delete_scope on public.tms_deliveries as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_route_delete_scope on public.tms_routes as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_schedule_delete_scope on public.tms_route_schedules as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_settings_delete_scope on public.tms_settings as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_proof_scope on public.tms_proofs as restrictive for all to authenticated using(private.tms_can_read(delivery_id)) with check(false);
create policy tms_event_scope on public.tms_events as restrictive for all to authenticated using(private.tms_can_read(delivery_id)) with check(false);
create policy tms_incident_scope on public.tms_delivery_incidents as restrictive for all to authenticated using(private.tms_can_read(delivery_id)) with check(false);
create policy tms_schedule_scope on public.tms_route_schedules as restrictive for all to authenticated using(private.tms_can_route(route_id)) with check(private.tms_scope() in ('dispatcher','manager'));
create policy tms_settings_scope on public.tms_settings as restrictive for all to authenticated using(private.tms_scope() is not null) with check(private.tms_scope() in ('dispatcher','manager'));
revoke insert,update,delete,truncate,references,trigger on public.tms_proofs,public.tms_events,public.tms_delivery_incidents from authenticated;
revoke all on public.tms_deliveries,public.tms_routes,public.tms_proofs,public.tms_events from anon;
alter view public.tms_proofs_read set(security_invoker=true);

create function private.tms_execution_version() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' then
  new.version:=old.version+1;
  new.initial_promised_from:=old.initial_promised_from;new.initial_promised_until:=old.initial_promised_until;
 else new.initial_promised_from:=null;new.initial_promised_until:=null;
 end if;
 if new.initial_promised_until is null and new.promised_until is not null then new.initial_promised_from:=new.promised_from;new.initial_promised_until:=new.promised_until;end if;
 return new;
end $$;
create trigger tms_execution_version before insert or update on public.tms_deliveries for each row execute function private.tms_execution_version();

create function private.tms_refused_quantity(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(rl.quantity),0) from public.return_lines rl join public.return_orders ro on ro.id=rl.return_id where rl.delivery_line_id=p_line and ro.status<>'cancelled'
$$;
create function private.tms_line_balance(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select greatest(0,l.quantity-private.tms_refused_quantity(l.id)-coalesce((select sum(al.accepted+al.missing) from public.tms_attempt_lines al where al.delivery_line_id=l.id),0)) from public.sales_delivery_lines l where l.id=p_line
$$;
create function private.tms_cargo_known(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select d.cargo_verified_at is not null or (d.weight>0 and d.volume>0 and not exists(
 select 1 from public.sales_deliveries s join public.sales_delivery_lines sl on sl.delivery_id=s.id join public.sales_order_lines ol on ol.id=sl.order_line_id join public.products p on p.id=ol.product_id
 where s.tms_delivery_id=d.id and (coalesce(p.weight_g,0)<=0 or coalesce(p.volume_cm3,0)<=0))) from public.tms_deliveries d where d.id=p_delivery
$$;

CREATE OR REPLACE FUNCTION private.gama_tms_resources(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare today date:=p_day;
begin perform private.tms_require(null,false,'read');
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','almacenero')
  then raise exception 'ROLE_NOT_ALLOWED';end if;
 return coalesce((select jsonb_agg(to_jsonb(z) order by z.name) from (
  select f.id driver_id,f.name,f.phone,f.employee_id,
   v.id vehicle_id,v.plate,v.brand,v.model,v.kind,v.status vehicle_status,
   coalesce(v.payload_kg,0) max_weight,coalesce(v.cargo_volume_m3,0) max_volume,
   (v.id is not null and v.status='in_service') available,
   exists(select 1 from public.hr_absences a
     where a.employee_id=f.employee_id and a.status='aprobada'
       and a.start_date<=today and a.end_date>=today) absent
  from public.fleet_drivers f
  left join public.fleet_assignments fa on fa.driver_id=f.id and fa.started_on<=today and (fa.ended_on is null or fa.ended_on>=today)
  left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active
  where f.active and (private.tms_scope()<>'driver' or f.id=private.tms_own_driver())) z),'[]'::jsonb);
end $function$
;
revoke all on function private.gama_tms_resources(date) from public,anon;grant execute on function private.gama_tms_resources(date) to authenticated;
create function public.gama_tms_resources(p_day date) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_resources(p_day)$$;revoke all on function public.gama_tms_resources(date) from public,anon;grant execute on function public.gama_tms_resources(date) to authenticated;

CREATE OR REPLACE FUNCTION private.gama_tms_plan_day(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 planning_day date:=p_day;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 route_clock timestamptz;arrival_at timestamptz;road_count integer;leg_count integer;road_metric jsonb;depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if planning_day is null or planning_day<(now() at time zone private.erp_timezone())::date or planning_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(planning_day-date '2000-01-01')::integer);
 -- Same row-lock order as departure: shipment, delivery, route.
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=planning_day order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.delivery_date=planning_day order by d.id for update;
 perform r.id from public.tms_routes r where r.route_date=planning_day order by r.id for update;
 update public.tms_deliveries d set lat=c.lat,lng=c.lng from public.customers c where d.customer_id=c.id and d.delivery_date=planning_day and d.lat is null and d.lng is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and c.lat is not null and lower(btrim(d.address))=lower(btrim(c.gps_address));
 select coalesce(array_agg(r.id),'{}') into locked from public.tms_routes r where
 r.manual_override or r.status in ('En ruta','En tránsito','Terminada','Cancelada')
 or exists(select 1 from public.tms_route_schedules ts where ts.route_id=r.id)
 or exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not exists(select 1 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id where d.id::text=sid and d.delivery_date=planning_day and o.status='confirmed' and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')))
 or exists(select 1 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id
  where (d.route_id=r.id or r.stops ? d.id::text) and (s.departed_at is not null or d.status in ('En carga','En tránsito','En ruta','Entregada')));
 select coalesce(jsonb_agg(d.id order by d.id),'[]') into origin_ids from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=planning_day;
 select coalesce(array_agg(d.id order by d.id),'{}') into eligible
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id
 where d.delivery_date=planning_day and o.status='confirmed' and s.departed_at is null
 and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and not(coalesce(d.route_id,'00000000-0000-0000-0000-000000000000')=any(locked));
 select * into settings from public.tms_settings limit 1;
 depot_ok:=coalesce(settings.depot_lat between -85 and 85 and settings.depot_lng between -180 and 180,false);
 resources:=private.gama_tms_resources(planning_day);
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window,d.promised_from,d.promised_until,private.tms_cargo_known(d.id)) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings),'roads',(select max(measured_at) from private.tms_road_pairs),'road_provider',(select jsonb_build_array(enabled,profile) from private.tms_road_provider where id))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180 and private.tms_cargo_known(d.id));
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or coalesce((dr->>'max_volume')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  route_clock:=(planning_day+time '08:00') at time zone private.erp_timezone();
  w:=0;v:=0;km:=0;road_count:=0;leg_count:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and v+d.volume<=(dr->>'max_volume')::numeric
    and (d.promised_until is null or greatest(route_clock+make_interval(mins=>ceil(coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0)*1.3/25*60)::int),d.promised_from)<=d.promised_until)
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     d.promised_until nulls last,coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);leg_count:=leg_count+1;road_metric:=private.tms_road_metric(cur_lat,cur_lng,stop.lat,stop.lng);if road_metric is not null then road_count:=road_count+1;end if;end if;
   route_clock:=greatest(route_clock+make_interval(mins=>ceil(coalesce(private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng),0)*1.3/25*60)::int),coalesce(stop.promised_from,route_clock))+make_interval(mins=>stop.service_minutes);
   cur_lat:=stop.lat;cur_lng:=stop.lng;w:=w+stop.weight;v:=v+stop.volume;
   stops:=stops||jsonb_build_array(stop.id);remaining:=array_remove(remaining,stop.id);
  end loop;
  if jsonb_array_length(stops)>(case when depot_ok then 1 else 0 end) then
   if depot_ok and settings.return_depot then km:=km+private.tms_distance(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng);leg_count:=leg_count+1;if private.tms_road_metric(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng) is not null then road_count:=road_count+1;end if;stops:=stops||jsonb_build_array('__depot');end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)
    values(planning_day,(dr->>'driver_id')::uuid,dr->>'name',dr->>'plate',(dr->>'vehicle_id')::uuid,stops,km,w,v,'Planificada',case when road_count=0 then 'air' when road_count=leg_count and depot_ok then 'road' else 'mixed' end) returning id into route_uuid;
   update public.tms_deliveries d set route_id=route_uuid,driver_id=(dr->>'driver_id')::uuid,status=case when d.status='Lista para envío' then d.status else 'Planificada' end
    where stops ? d.id::text;
   planned_count:=planned_count+jsonb_array_length(stops)-(case when depot_ok then 1 else 0 end)-(case when depot_ok and settings.return_depot then 1 else 0 end);
   route_count:=route_count+1;vehicle_ids:=array_append(vehicle_ids,(dr->>'vehicle_id')::uuid);
  end if;
 end loop;
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 summary:=jsonb_build_object('today',planning_day,'changed',true,'routes',route_count,'total',cardinality(eligible),'planned',planned_count,
  'unplanned',cardinality(eligible)-planned_count,'without_coordinates',jsonb_array_length(geocode_ids),'without_capacity',cardinality(remaining),
  'without_cargo', (select count(*) from public.tms_deliveries x where x.id=any(eligible) and not private.tms_cargo_known(x.id)), 'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_move_stop(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date);
 d public.tms_deliveries;source public.tms_routes;target public.tms_routes;r public.tms_routes;
 dest uuid:=(p_data->>'target_route_id')::uuid;before_id text:=nullif(p_data->>'before_stop_id','');
 ids text[];source_ids text[];new_stops jsonb;sid text;pos integer;resource jsonb;
 w numeric;v numeric;km double precision;last_lat double precision;last_lng double precision;a double precision;b double precision;
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if day<(now() at time zone private.erp_timezone())::date or day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(day-date '2000-01-01')::integer);
 -- Match automatic planning and departure lock order.
 perform s.id from public.sales_deliveries s join public.tms_deliveries x on x.id=s.tms_delivery_id where x.delivery_date=day order by s.id for update of s;
 perform x.id from public.tms_deliveries x where x.delivery_date=day order by x.id for update;
 perform x.id from public.tms_routes x where x.route_date=day order by x.id for update;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid;
 select * into source from public.tms_routes where id=d.route_id;
 select * into target from public.tms_routes where id=dest;
 if d.id is null or source.id is null or target.id is null or d.delivery_date<>day or source.route_date<>day or target.route_date<>day then raise exception 'ROUTE_NOT_FOUND';end if;
 if source.version is distinct from (p_data->>'source_version')::int or target.version is distinct from (p_data->>'target_version')::int then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from public.tms_routes x where x.id in(source.id,target.id) and
  (x.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.tms_route_schedules ts where ts.route_id=x.id)))
 or exists(select 1 from public.tms_deliveries x left join public.sales_deliveries s on s.tms_delivery_id=x.id
  where (x.route_id in(source.id,target.id) or source.stops ? x.id::text or target.stops ? x.id::text)
   and (s.departed_at is not null or x.status in ('En carga','En tránsito','En ruta','Entregada','Cancelada'))) then raise exception 'ROUTE_CLOSED';end if;
 if not(source.stops ? d.id::text) then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from jsonb_array_elements_text(source.stops||target.stops) e where e<>'__depot' and not exists(
  select 1 from public.tms_deliveries x join public.sales_deliveries s on s.tms_delivery_id=x.id join public.sales_orders o on o.id=s.order_id
  where x.id::text=e and x.delivery_date=day and o.status='confirmed')) then raise exception 'TMS_ORDER_REQUIRED';end if;
 select j into resource from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'driver_id')::uuid=target.driver_id and (j->>'vehicle_id')::uuid=target.vehicle_id and (j->>'available')::boolean and not(j->>'absent')::boolean;
 if resource is null then raise exception 'DRIVER_REQUIRED';end if;
 ids:=array(select e from jsonb_array_elements_text(target.stops)e where e<>'__depot' and e<>d.id::text);
 if before_id is not null and not(before_id=any(ids)) then raise exception 'ROUTE_STALE';end if;
 pos:=coalesce(array_position(ids,before_id),cardinality(ids)+1);
 ids:=coalesce(ids[1:pos-1],'{}')||array[d.id::text]||coalesce(ids[pos:cardinality(ids)],'{}');
 select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where x.id::text=any(ids);
 if exists(select 1 from public.tms_deliveries x where x.id::text=any(ids) and not private.tms_cargo_known(x.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
 if coalesce((resource->>'max_volume')::numeric,0)<=0 or w>coalesce((resource->>'max_weight')::numeric,0) or v>(resource->>'max_volume')::numeric then raise exception 'ROUTE_CAPACITY';end if;
 source_ids:=array(select e from jsonb_array_elements_text(source.stops)e where e<>'__depot' and e<>d.id::text);
 for r in select * from public.tms_routes where id in(source.id,target.id) order by id loop
  new_stops:=to_jsonb(case when r.id=target.id then ids else source_ids end);
  if r.stops->>0='__depot' then new_stops:=jsonb_build_array('__depot')||new_stops;end if;
  if jsonb_array_length(r.stops)>1 and r.stops->>(jsonb_array_length(r.stops)-1)='__depot' then new_stops:=new_stops||jsonb_build_array('__depot');end if;
  select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where new_stops ? x.id::text;
  km:=0;last_lat:=null;last_lng:=null;
  for sid in select e from jsonb_array_elements_text(new_stops)e loop
   if sid='__depot' then select depot_lat,depot_lng into a,b from public.tms_settings limit 1;
   else select lat,lng into a,b from public.tms_deliveries where id::text=sid;end if;
   if last_lat is not null and a is not null then km:=km+private.tms_distance(last_lat,last_lng,a,b);end if;
   last_lat:=a;last_lng:=b;
  end loop;
  update public.tms_routes set stops=new_stops,weight=w,volume=v,distance=km,manual_override=true where id=r.id;
 end loop;
 update public.tms_deliveries set route_id=target.id,driver_id=target.driver_id where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'RUTA_AJUSTADA',concat_ws(' · ',source.erp_reference,target.erp_reference,'Orden de paradas actualizado'),d.customer,auth.uid());
 return jsonb_build_object('delivery_id',d.id,'route_id',target.id);
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_save_gps(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.tms_deliveries;a double precision:=(p_data->>'lat')::double precision;b double precision:=(p_data->>'lng')::double precision;saved boolean:=false;
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if a is null or b is null or not(a between -85 and 85 and b between -180 and 180) then raise exception 'GPS_INVALID';end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
 if d.status in ('En carga','En tránsito','En ruta','Entregada','Cancelada') or exists(select 1 from public.sales_deliveries where tms_delivery_id=d.id and departed_at is not null) then raise exception 'ROUTE_CLOSED';end if;
 update public.tms_deliveries set lat=a,lng=b where id=d.id;
 if d.customer_id is not null then
  update public.customers set lat=a,lng=b where id=d.customer_id and lower(btrim(address))=lower(btrim(d.address));
  saved:=found;
 end if;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'COORDENADAS',case when saved then 'GPS guardado en la ficha del cliente' else 'GPS guardado para esta dirección de entrega' end,d.customer,auth.uid());
 return jsonb_build_object('delivery_id',d.id,'customer_saved',saved);
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_capture(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.tms_deliveries;pr public.tms_proofs;key uuid:=(p_data->>'request_key')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('hash',md5((p_data-'request_key')::text));stamp timestamptz:=nullif(p_data->>'captured_at','')::timestamptz;signature text:=p_data->>'signature';photo text:=p_data->>'photo';result jsonb;begin
 perform private.tms_require((p_data->>'delivery_id')::uuid,false,'validate'); if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended('tms-capture:'||key::text,0));
 select * into receipt from private.command_receipts where domain='tms-capture' and request_key=key;if found then if receipt.actor_id<>auth.uid() or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;if not found or d.status in ('Entregada','Cancelada') then raise exception 'DELIVERY_CLOSED';end if;
 if stamp is null or stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
 if signature is null and photo is null then raise exception 'PROOF_REQUIRED';end if;
 if (signature is not null and (signature!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(signature)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
 if p_data->>'complete'='true' and nullif(signature,'') is null then raise exception 'SIGNATURE_REQUIRED';end if;
 select * into pr from public.tms_proofs where delivery_id=d.id for update;
 if pr.signature is not null and signature is not null and pr.signature<>signature then raise exception 'PROOF_CONFLICT';end if;
 insert into public.tms_proofs(delivery_id,photo,signature,captured_at,captured_by) values(d.id,photo,signature,stamp,auth.uid()) on conflict(delivery_id) do update set photo=coalesce(excluded.photo,tms_proofs.photo),signature=coalesce(excluded.signature,tms_proofs.signature),captured_at=excluded.captured_at,captured_by=excluded.captured_by;
 if p_data->>'complete'='true' then
 if exists(select 1 from public.sales_deliveries s join public.sales_delivery_lines l on l.delivery_id=s.id where s.tms_delivery_id=d.id and private.tms_refused_quantity(l.id)>0) or exists(select 1 from public.tms_delivery_attempts a where a.delivery_id=d.id) then raise exception 'RECEIPT_QUANTITIES_REQUIRED';end if;
 update public.tms_deliveries set status='Entregada',actual_arrival=coalesce(actual_arrival,stamp),delivered_at=stamp where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'Entregada','Prueba de entrega registrada',d.customer,auth.uid());end if;

 if p_data ? 'gps' then
  if p_data->'gps'->>'status' not in ('captured','denied','unavailable','timeout') then raise exception 'GPS_INVALID';end if;
  if p_data->'gps'->>'status'='captured' and (nullif(p_data->'gps'->>'lat','')::double precision is null or nullif(p_data->'gps'->>'lng','')::double precision is null or not((p_data->'gps'->>'lat')::double precision between -90 and 90 and (p_data->'gps'->>'lng')::double precision between -180 and 180) or nullif(p_data->'gps'->>'accuracy','')::double precision is null or (p_data->'gps'->>'accuracy')::double precision<0) then raise exception 'GPS_INVALID';end if;
  update public.tms_proofs set latitude=coalesce(nullif(p_data->'gps'->>'lat','')::double precision,latitude),longitude=coalesce(nullif(p_data->'gps'->>'lng','')::double precision,longitude),gps_accuracy_m=coalesce(nullif(p_data->'gps'->>'accuracy','')::double precision,gps_accuracy_m),gps_recorded_at=coalesce(nullif(p_data->'gps'->>'at','')::timestamptz,gps_recorded_at),gps_status=p_data->'gps'->>'status',received_at=now() where delivery_id=d.id;
 end if;
 update public.tms_proofs set received_at=now() where delivery_id=d.id;
 result:=jsonb_build_object('delivery_id',d.id,'captured_at',stamp,'completed',p_data->>'complete'='true');insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-capture',key,auth.uid(),payload,result);return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_delivery_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.tms_deliveries;s public.sales_deliveries;invoice public.external_invoices;payment public.external_invoice_payments;
 u uuid:=auth.uid();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;eta timestamptz;next_day date;amount numeric;paid numeric;packages uuid[];lines jsonb;return_result jsonb;
begin
 perform private.tms_require((p_data->>'delivery_id')::uuid,false,case when p_action='context' then 'read' else 'edit' end);
 if u is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action not in ('context','message','incident','reschedule','partial_return','collect') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'context' then
  if not private.erp_action_allowed('tms','edit') then raise exception 'ACTION_NOT_ALLOWED:tms:edit';end if;
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('tms-delivery:'||key,0));
  select * into receipt from private.command_receipts where domain='tms-delivery' and request_key=key;
  if found then if receipt.actor_id<>u or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 end if;
 -- Commercial transaction first, then shipment and delivery (same order as departure).
 if p_action in ('collect','partial_return') then perform pg_advisory_xact_lock(775120);end if;
 select * into s from public.sales_deliveries where tms_delivery_id=(p_data->>'delivery_id')::uuid for update;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
 if p_action='context' then
  return jsonb_build_object('delivery',to_jsonb(d),'phone',(select c.phone from public.customers c where c.id=d.customer_id),
   'eta',coalesce(d.eta_at,(select (l->>'arrival_at')::timestamptz from public.tms_route_schedules ts cross join jsonb_array_elements(ts.legs) l where ts.route_id=d.route_id and l->>'id'=d.id::text limit 1)),
   'incidents',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.tms_delivery_incidents i where i.delivery_id=d.id),'[]'),
   'packages',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'barcode',p.barcode,'rejected',exists(select 1 from private.tms_rejected_packages x where x.delivery_id=d.id and x.package_id=p.id)) order by p.barcode) from public.fulfillment_packages p join public.fulfillment_preparations f on f.id=p.preparation_id where f.shipment_id=s.id and p.status='active'),'[]'),
   'invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'reference',coalesce(i.erp_reference,i.number),'balance',greatest(0,i.total-coalesce((select sum(x.amount) from public.external_invoice_payments x where x.invoice_id=i.id and x.status='confirmed'),0))) order by i.issue_date) from public.external_invoices i where i.order_id=s.order_id and i.fiscal_status not in ('cancelled','rejected')),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind)) from public.financial_accounts a join public.company_settings c on c.id where a.active and a.account_id is not null and a.currency=c.currency),'[]'),
   'returns',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'status',r.status)) from public.return_orders r where r.delivery_id=s.id and r.status<>'cancelled'),'[]'));
 end if;
 if d.status='Cancelada' or (d.status='Entregada' and p_action not in ('collect','partial_return')) then raise exception 'DELIVERY_CLOSED';end if;
 if p_action='message' then
  eta:=nullif(p_data->>'eta','')::timestamptz;
  if eta is null or eta<now()-interval '1 hour' or eta>now()+interval '366 days' then raise exception 'ETA_REQUIRED';end if;
  update public.tms_deliveries set eta_at=eta where id=d.id;
  insert into private.tms_tracking_links(delivery_id) values(d.id) on conflict(delivery_id) do update set expires_at=now()+interval '30 days',token=case when tms_tracking_links.expires_at<now() then gen_random_uuid() else tms_tracking_links.token end;
  result:=jsonb_build_object('token',(select token from private.tms_tracking_links where delivery_id=d.id),'eta',eta);
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'AVISO_PREPARADO','Aviso con hora estimada y seguimiento preparado',d.customer,u);
 elsif p_action='incident' then
  if s.departed_at is null then raise exception 'DEPARTURE_REQUIRED';end if;
  if p_data->>'reason' not in ('absent','refused','wrong_address') then raise exception 'INCIDENT_REASON_REQUIRED';end if;
  insert into public.tms_delivery_incidents(delivery_id,driver_id,reason,note,created_by) values(d.id,d.driver_id,p_data->>'reason',left(p_data->>'note',2000),u);
  update public.tms_deliveries set status='Excepción' where id=d.id;
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'INCIDENTE',case p_data->>'reason' when 'absent' then 'Cliente ausente' when 'refused' then 'Entrega rechazada' else 'Dirección incorrecta' end,d.customer,u);
  result:=jsonb_build_object('delivery_id',d.id,'status','Excepción');
 elsif p_action='reschedule' then
  next_day:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date+1);
  if next_day<=(now() at time zone private.erp_timezone())::date or next_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
  if d.status not in ('Excepción','Entrega parcial') then raise exception 'INCIDENT_REQUIRED';end if;
  -- Keep the original departure and its stock movements; the goods are still on the vehicle.
  update public.tms_deliveries set delivery_date=next_day,eta_at=null where id=d.id;
  update public.tms_delivery_incidents set rescheduled_for=next_day where delivery_id=d.id and rescheduled_for is null;
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'REPROGRAMADA','Entrega reprogramada para '||next_day,d.customer,u);
  result:=jsonb_build_object('delivery_id',d.id,'day',next_day);
 elsif p_action='partial_return' then
  if s.id is null or s.departed_at is null then raise exception 'DEPARTURE_REQUIRED';end if;
  if not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) or not private.erp_action_allowed('returns','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
  packages:=array(select distinct e::uuid from jsonb_array_elements_text(p_data->'package_ids')e);
  if cardinality(packages)=0 or exists(select 1 from unnest(packages) pk(package_id) where not exists(select 1 from public.fulfillment_packages p join public.fulfillment_preparations f on f.id=p.preparation_id where p.id=pk.package_id and f.shipment_id=s.id and p.status='active')) then raise exception 'PACKAGE_REQUIRED';end if;
  if exists(select 1 from private.tms_rejected_packages x where x.delivery_id=d.id and x.package_id=any(packages)) then raise exception 'PACKAGE_ALREADY_RETURNED';end if;
  select coalesce(jsonb_agg(jsonb_build_object('line_id',dl.id,'quantity',q.quantity)),'[]') into lines from
   (select pl.order_line_id,pl.source_location_id,sum(l.quantity) quantity from public.fulfillment_package_lines l join public.fulfillment_pick_lines pl on pl.id=l.pick_line_id where l.package_id=any(packages) group by pl.order_line_id,pl.source_location_id) q
   join public.sales_delivery_lines dl on dl.delivery_id=s.id and dl.order_line_id=q.order_line_id and dl.location_id=q.source_location_id;
  return_result:=private.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',s.id,'reason','other','notes','Cartones rechazados en entrega · '||coalesce(d.erp_reference,''),'lines',lines));
  insert into private.tms_rejected_packages(delivery_id,package_id,return_id) select d.id,pk.package_id,(return_result->>'id')::uuid from unnest(packages) pk(package_id);
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'ENTREGA_PARCIAL',cardinality(packages)||' cartones rechazados · '||(return_result->>'number'),d.customer,u);
  result:=return_result;
 elsif p_action='collect' then
  if not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') or not private.erp_action_allowed('tms','validate') then raise exception 'ACTION_NOT_ALLOWED:payments:create';end if;
  if private.current_user_role()<>'administrador' and not exists(select 1 from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.id=d.driver_id and f.active and h.active and h.profile_id=u) then raise exception 'DRIVER_ACCOUNT_REQUIRED';end if;
  if s.departed_at is null then raise exception 'DEPARTURE_REQUIRED';end if;
  select * into invoice from public.external_invoices where id=(p_data->>'invoice_id')::uuid and order_id=s.order_id for update;
  if invoice.id is null or invoice.fiscal_status in ('cancelled','rejected') then raise exception 'INVOICE_CLOSED';end if;
  amount:=(p_data->>'amount')::numeric;
  if amount is null or amount<=0 or amount<>round(amount,2) then raise exception 'INVALID_PAYMENT_AMOUNT';end if;
  if p_data->>'method' not in ('cash','transfer') then raise exception 'INVALID_PAYMENT_METHOD';end if;
  if not exists(select 1 from public.financial_accounts a join public.company_settings c on c.id where a.id=(p_data->>'financial_account_id')::uuid and a.active and a.account_id is not null and a.currency=c.currency and ((p_data->>'method'='cash' and a.kind='cash') or (p_data->>'method'='transfer' and a.kind='bank'))) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  select coalesce(sum(x.amount),0) into paid from public.external_invoice_payments x where x.invoice_id=invoice.id and x.status='confirmed';
  if paid+amount>invoice.total then raise exception 'PAYMENT_EXCEEDS_BALANCE';end if;
  insert into public.external_invoice_payments(request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by,financial_account_id)
  values(key,invoice.id,amount,(now() at time zone private.erp_timezone())::date,p_data->>'method',coalesce(p_data->>'reference',''),'','Cobro en entrega · '||coalesce(d.erp_reference,''),u,(p_data->>'financial_account_id')::uuid) returning * into payment;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(s.order_id,'payment',payment.id,u,jsonb_build_object('delivery_id',d.id,'amount',amount,'method',payment.method));
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'COBRO',amount||' · '||payment.method||' · '||payment.erp_reference,d.customer,u);
  result:=jsonb_build_object('id',payment.id,'reference',payment.erp_reference,'amount',amount);
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-delivery',key,u,payload,result);
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_loading_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 u uuid:=auth.uid(); role_name text:=coalesce(private.current_user_role(),'');
 d public.tms_deliveries; s public.sales_deliveries; sc public.tms_loading_scans; dr record;
 l record; code text; qty numeric; remaining numeric; take numeric; available numeric; key_id uuid; scan_id uuid; result jsonb; off integer;
begin
 perform private.tms_require(null,true,case when p_action='depart' then 'validate' else 'read' end); if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('list','manifest','depart') then raise exception 'INVALID_ACTION'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 if p_action='list' then
  off:=coalesce((p_data->>'offset')::integer,0);if off<0 or off>1000000 then raise exception 'INVALID_OFFSET'; end if;
  select coalesce(jsonb_agg(j),'[]'::jsonb) into result from (
   select jsonb_build_object('id',td.id,'number',sd.number,'customer',td.customer,'date',td.delivery_date,'status',td.status,'departed_at',sd.departed_at,'complete',private.gama_loading_complete(sd.id)) j
   from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id
   where sd.loading_required and (coalesce((p_data->>'history')::boolean,false) or (sd.departed_at is null and td.status not in ('Cancelada','Entregada')))
   order by td.delivery_date,td.id limit 21 offset off
  ) a;
  return result;
 end if;
 if p_action='manifest' then
  result:=private.gama_loading_manifest((p_data->>'delivery_id')::uuid);
  if result is null then raise exception 'DELIVERY_NOT_FOUND'; end if;
  return result;
 end if;
 -- Serialize with stock issue/receipt and concurrent scanners. Nothing here
 -- updates stock, reservations or movements.
 perform pg_advisory_xact_lock(741932,1);
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if not found then raise exception 'DELIVERY_NOT_FOUND'; end if;
 select * into s from public.sales_deliveries where tms_delivery_id=d.id for update;
 if not found or not s.loading_required then raise exception 'NO_LOADING_REQUIRED'; end if;
 if p_action='depart' and s.departed_at is not null then return private.gama_loading_manifest(d.id); end if;
 if p_action='scan' then
  key_id:=(p_data->>'request_key')::uuid;code:=btrim(p_data->>'barcode');qty:=(p_data->>'quantity')::numeric;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where request_key=key_id;
  if found then
   if sc.delivery_id<>s.id or sc.barcode is distinct from code or sc.quantity is distinct from qty then raise exception 'REQUEST_KEY_CONFLICT'; end if;
   return private.gama_loading_manifest(d.id);
  end if;
 end if;
 if s.departed_at is not null or d.status in ('Cancelada','Entregada') then raise exception 'LOADING_CLOSED'; end if;
 if p_action='scan' then
  if code is null or length(code) not between 1 and 256 then raise exception 'BARCODE_REQUIRED'; end if;
  if qty is null or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY'; end if;
  if not exists(select 1 from public.sales_delivery_lines where delivery_id=s.id and loading_barcode=code) then raise exception 'WRONG_PRODUCT'; end if;
  select sum(dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0)) into available from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code;
  if qty>available then raise exception 'EXCEEDS_CARGO_QUANTITY'; end if;
  insert into public.tms_loading_scans(request_key,delivery_id,barcode,quantity,scanned_by) values(key_id,s.id,code,qty,u) returning id into scan_id;
  remaining:=qty;
  for l in select dl.id,dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0) needed
   from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code order by dl.id for update of dl loop
   exit when remaining<=0;take:=least(remaining,l.needed);if take<=0 then continue;end if;
   insert into public.tms_loading_allocations(scan_id,delivery_line_id,quantity) values(scan_id,l.id,take);remaining:=remaining-take;
  end loop;
  if remaining<>0 then raise exception 'LOADING_CHANGED'; end if;
 elsif p_action='void_scan' then
  if length(btrim(coalesce(p_data->>'reason','')))<3 or length(p_data->>'reason')>1000 then raise exception 'REASON_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where id=(p_data->>'scan_id')::uuid and delivery_id=s.id for update;
  if not found then raise exception 'SCAN_NOT_FOUND'; end if;
  if sc.voided_at is not null then return private.gama_loading_manifest(d.id); end if;
  update public.tms_loading_scans set voided_at=now(),voided_by=u,void_reason=btrim(p_data->>'reason') where id=sc.id;
 elsif p_action='depart' then
  if not private.gama_loading_complete(s.id) then raise exception 'LOADING_INCOMPLETE'; end if;
  if s.loading_version is distinct from (p_data->>'version')::integer then raise exception 'LOADING_CHANGED'; end if;
  select f.id,f.name,f.employee_id,v.plate into dr
   from public.fleet_drivers f
   left join public.fleet_assignments fa on fa.driver_id=f.id and fa.ended_on is null
   left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active and v.status='in_service'
   where f.id=coalesce(nullif(p_data->>'driver_id','')::uuid,d.driver_id) and f.active;
  if not found or dr.plate is null then raise exception 'DRIVER_REQUIRED'; end if;
  if not exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (j->>'available')::boolean and not(j->>'absent')::boolean and (j->>'max_weight')::numeric>0 and (j->>'max_volume')::numeric>0) then raise exception 'DRIVER_UNAVAILABLE';end if;
  if not private.tms_cargo_known(d.id) or exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and not private.tms_cargo_known(dd.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
  if exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (coalesce((select sum(dd.weight) from public.tms_deliveries dd where dd.route_id=d.route_id),d.weight)>(j->>'max_weight')::numeric or coalesce((select sum(dd.volume) from public.tms_deliveries dd where dd.route_id=d.route_id),d.volume)>(j->>'max_volume')::numeric)) then raise exception 'ROUTE_CAPACITY';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and dd.promised_until is not null) and not exists(select 1 from public.tms_route_schedules ts where ts.route_id=d.route_id) then raise exception 'ROUTE_SCHEDULE_REQUIRED';end if;
  update public.sales_deliveries set departed_at=now(),departed_by=u,departure_driver_id=dr.id,departure_vehicle=dr.plate where id=s.id;
  update public.tms_deliveries set status='En tránsito',driver_id=dr.id where id=d.id;
 end if;
 update public.sales_deliveries set loading_version=loading_version+1 where id=s.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id)
 values(d.id,case p_action when 'scan' then 'CARGA_ESCANEADA' when 'void_scan' then 'ESCANEO_ANULADO' else 'SALIDA_VALIDADA' end,
 case p_action when 'scan' then code||' × '||qty when 'void_scan' then p_data->>'reason' else s.number||' · '||dr.name||' · '||dr.plate end,d.customer,u);
 return private.gama_loading_manifest(d.id);
end $function$
;

create or replace function private.gama_line_performed(p_line uuid,p_signed boolean default false) returns numeric language sql stable security definer set search_path='' as $$
 select case when l.product_kind='service' then coalesce((select sum(c.quantity) from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null),0)
 else coalesce((select sum(case when not p_signed then dl.quantity
 when exists(select 1 from public.tms_delivery_attempts a where a.delivery_id=td.id) then coalesce((select sum(al.accepted) from public.tms_attempt_lines al where al.delivery_line_id=dl.id),0)
 when td.status='Entregada' and exists(select 1 from public.tms_proofs p where p.delivery_id=td.id and nullif(btrim(p.signature),'') is not null) then greatest(0,dl.quantity-private.tms_refused_quantity(dl.id)) else 0 end)
 from public.sales_delivery_lines dl join public.sales_deliveries sd on sd.id=dl.delivery_id left join public.tms_deliveries td on td.id=sd.tms_delivery_id where dl.order_line_id=l.id),0) end from public.sales_order_lines l where l.id=p_line
$$;

create function private.gama_tms_execution(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();tid uuid:=nullif(p_data->>'delivery_id','')::uuid;key_id uuid:=nullif(p_data->>'request_key','')::uuid;
 d public.tms_deliveries;s public.sales_deliveries;r public.tms_routes;a public.tms_delivery_attempts;
 receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;entry jsonb;line record;remaining numeric;ac numeric;rf numeric;mi numeric;de numeric;accepted_total numeric:=0;total numeric;
 lines jsonb:='[]';return_lines jsonb:='[]';ret jsonb;stamp timestamptz:=coalesce(nullif(p_data->>'occurred_at','')::timestamptz,now());
 sig text:=nullif(p_data->>'signature','');photo text:=nullif(p_data->>'photo','');proof_id uuid;media text;kind text;from_at timestamptz;until_at timestamptz;
begin
 perform private.tms_require(tid,p_action in ('configure','close','settle','access','set_access','day'),case when p_action in ('context','bundle','proof','manifest','access','day') then 'read' when p_action='receive' then 'validate' else 'edit' end);
 if jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_DATA';end if;
 if p_action='bundle' then
  result:=private.gama_tms_my_route();
  select coalesce(jsonb_agg(x.value||jsonb_build_object('execution',private.gama_tms_execution('context',jsonb_build_object('delivery_id',x.value->>'id')))),'[]') into lines from jsonb_array_elements(result->'deliveries') x;
  return result||jsonb_build_object('deliveries',lines,'scope',private.tms_scope(),'actor_id',uid,'downloaded_at',now());
 elsif p_action='access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('profile_id',p.id,'name',coalesce(h.full_name,p.full_name,p.email),'role',case when p.role='administrador' then 'manager' else sc.role end,'admin',p.role='administrador','active',sc.active,'driver_id',f.id) order by p.email) from public.profiles p left join public.hr_employees h on h.profile_id=p.id left join public.fleet_drivers f on f.employee_id=h.id left join private.tms_user_scopes sc on sc.profile_id=p.id where p.active and p.role in ('administrador','almacenero')),'[]');
 elsif p_action='proof' then
  select aa.* into a from public.tms_delivery_attempts aa join public.tms_attempt_proofs pr on pr.attempt_id=aa.id where pr.id=(p_data->>'proof_id')::uuid;
  if a.id is null or not private.tms_can_read(a.delivery_id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return (select jsonb_build_object('data_url',m.data_url,'kind',pr.kind) from public.tms_attempt_proofs pr join private.tms_attempt_media m on m.proof_id=pr.id where pr.id=(p_data->>'proof_id')::uuid);
 elsif p_action='manifest' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return jsonb_build_object('route',to_jsonb(r),'deliveries',coalesce((select jsonb_agg(private.gama_tms_execution('context',jsonb_build_object('delivery_id',dd.id)) order by x.ordinality) from jsonb_array_elements_text(r.stops) with ordinality x(id,ordinality) join public.tms_deliveries dd on dd.id::text=x.id),'[]'),'guide',(select jsonb_build_object('status',status,'number',establishment||'-'||emission_point||'-'||sequential) from public.sri_document_issues where route_id=r.id));
 elsif p_action='day' then
  return jsonb_build_object('deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',dd.id,'reference',dd.erp_reference,'customer',dd.customer,'status',dd.status,'date',dd.delivery_date,'version',dd.version,'pending_quantity',(select coalesce(sum(private.tms_line_balance(dl.id)),0) from public.sales_deliveries ss join public.sales_delivery_lines dl on dl.delivery_id=ss.id where ss.tms_delivery_id=dd.id),'invoice_review',(dd.invoice_reviewed_at is null and exists(select 1 from public.tms_delivery_attempts aa where aa.delivery_id=dd.id and aa.result<>'complete')),'settled_at',dd.settled_at,'open_returns',(select count(*) from public.return_orders ro join public.sales_deliveries ss on ss.id=ro.delivery_id where ss.tms_delivery_id=dd.id and ro.status not in ('closed','cancelled'))) order by dd.delivery_date,dd.customer) from public.tms_deliveries dd where dd.settled_at is null and dd.delivery_date<=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date) and (dd.status not in ('Entregada','Cancelada') or dd.delivery_date=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date))),'[]'));
 elsif p_action='context' then
  select * into d from public.tms_deliveries where id=tid;
  select * into s from public.sales_deliveries where tms_delivery_id=tid;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  return jsonb_build_object('delivery',to_jsonb(d),'shipment',jsonb_build_object('id',s.id,'number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at),
   'scope',private.tms_scope(),'cargo_known',private.tms_cargo_known(d.id),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',ol.product_name,'quantity',l.quantity,'remaining',private.tms_line_balance(l.id),'accepted',coalesce((select sum(al.accepted) from public.tms_attempt_lines al where al.delivery_line_id=l.id),0),'refused',private.tms_refused_quantity(l.id)) order by l.id) from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id where l.delivery_id=s.id),'[]'),
   'attempts',coalesce((select jsonb_agg(to_jsonb(aa)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(al)) from public.tms_attempt_lines al where al.attempt_id=aa.id),'proofs',(select jsonb_agg(to_jsonb(pr)) from public.tms_attempt_proofs pr where pr.attempt_id=aa.id)) order by aa.attempt_no desc) from public.tms_delivery_attempts aa where aa.delivery_id=tid),'[]'));
 end if;
 if p_action not in ('receive','arrive','notes','configure','close','settle','set_access') then raise exception 'INVALID_ACTION';end if;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 -- One commercial lock order with receipt/return operations, then shipment/delivery.
 perform pg_advisory_xact_lock(775120);
 perform pg_advisory_xact_lock(hashtextextended('tms-execution:'||key_id,0));
 select * into receipt from private.command_receipts where domain='tms-execution' and request_key=key_id;
 if found then if receipt.actor_id<>uid or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='set_access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  insert into private.tms_user_scopes(profile_id,role,active,updated_by) values((p_data->>'profile_id')::uuid,p_data->>'role',coalesce((p_data->>'active')::boolean,true),uid) on conflict(profile_id) do update set role=excluded.role,active=excluded.active,updated_at=now(),updated_by=uid;
  result:=jsonb_build_object('saved',true);
 elsif p_action='close' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;
  if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  if r.version is distinct from (p_data->>'version')::integer then raise exception 'ROUTE_STALE';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=r.id and dd.status not in ('Entregada','Cancelada') and dd.settled_at is null) then raise exception 'ROUTE_DELIVERIES_PENDING';end if;
  update public.tms_routes set closed_at=now(),closed_by=uid,status='Terminada' where id=r.id;
  result:=jsonb_build_object('closed',true);
 else
  select * into s from public.sales_deliveries where tms_delivery_id=tid for update;
  select * into d from public.tms_deliveries where id=tid for update;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  if d.version is distinct from (p_data->>'version')::integer then raise exception 'DELIVERY_STALE';end if;
  if d.status in ('Entregada','Cancelada') or d.settled_at is not null then raise exception 'DELIVERY_CLOSED';end if;
  if p_action='settle' then
   if private.tms_scope() not in ('dispatcher','manager') then raise exception 'TMS_DISPATCH_REQUIRED';end if;
   if length(btrim(coalesce(p_data->>'reason','')))<5 or not coalesce((p_data->>'invoice_reviewed')::boolean,false) then raise exception 'SETTLEMENT_REVIEW_REQUIRED';end if;
   if exists(select 1 from public.sales_delivery_lines dl where dl.delivery_id=s.id and private.tms_line_balance(dl.id)>0) or exists(select 1 from public.return_orders ro where ro.delivery_id=s.id and ro.status not in ('closed','cancelled')) then raise exception 'DELIVERY_QUANTITIES_PENDING';end if;
   update public.tms_deliveries set settled_at=now(),settled_by=uid,settlement_note=left(p_data->>'reason',2000),invoice_reviewed_at=now() where id=d.id;
   update public.tms_delivery_incidents set resolved_at=now(),resolved_by=uid,resolution=left(p_data->>'reason',2000) where delivery_id=d.id and resolved_at is null;
   insert into public.tms_events(delivery_id,type,note,user_id) values(d.id,'CIERRE_REVISADO',left(p_data->>'reason',2000),uid);
  elsif p_action='configure' then
   if s.departed_at is not null then raise exception 'ROUTE_CLOSED';end if;
   from_at:=nullif(p_data->>'promised_from','')::timestamptz;until_at:=nullif(p_data->>'promised_until','')::timestamptz;
   if (from_at is null)<>(until_at is null) or until_at<=from_at or (from_at at time zone private.erp_timezone())::date<>d.delivery_date or until_at>from_at+interval '2 days' then raise exception 'DELIVERY_WINDOW_INVALID';end if;
   update public.tms_deliveries set promised_from=from_at,promised_until=until_at,service_minutes=coalesce((p_data->>'service_minutes')::integer,service_minutes),
    time_window=case when from_at is null then '' else to_char(from_at at time zone private.erp_timezone(),'HH24:MI')||'–'||to_char(until_at at time zone private.erp_timezone(),'HH24:MI') end where id=d.id;
   if p_data ? 'weight' or p_data ? 'volume' then
    if coalesce((p_data->>'weight')::numeric,0)<=0 or coalesce((p_data->>'volume')::numeric,0)<=0 or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
    update public.tms_deliveries set weight=(p_data->>'weight')::numeric,volume=(p_data->>'volume')::numeric,cargo_verified_at=now(),cargo_verified_by=uid where id=d.id;
   end if;
   delete from public.tms_route_schedules where route_id=d.route_id;
   insert into public.tms_events(delivery_id,type,note,user_id,detail) values(d.id,'PLANIFICACION_VALIDADA',left(p_data->>'reason',2000),uid,p_data-'request_key');
  elsif p_action='notes' then
   update public.tms_deliveries set notes=left(p_data->>'notes',2000) where id=d.id;
  else
   if s.id is null or (s.loading_required and s.departed_at is null) then raise exception 'DEPARTURE_REQUIRED';end if;
   if stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
   if p_action='arrive' then
    update public.tms_deliveries set actual_arrival=coalesce(actual_arrival,stamp) where id=d.id;
    insert into public.tms_events(delivery_id,type,at,user_id) values(d.id,'LLEGADA',stamp,uid);
   elsif p_action='receive' then
    if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')=0 or jsonb_array_length(p_data->'lines')>500 then raise exception 'RECEIPT_LINES_REQUIRED';end if;
    if (select count(*) from jsonb_array_elements(p_data->'lines'))<>(select count(distinct x->>'id') from jsonb_array_elements(p_data->'lines') x) then raise exception 'RECEIPT_LINES_INVALID';end if;
    if (sig is not null and (sig!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(sig)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
    if p_data ? 'gps' and (coalesce(p_data#>>'{gps,status}','') not in ('captured','denied','unavailable','timeout') or (p_data#>>'{gps,status}'='captured' and (not coalesce((p_data#>>'{gps,lat}')::numeric between -90 and 90,false) or not coalesce((p_data#>>'{gps,lng}')::numeric between -180 and 180,false) or not coalesce((p_data#>>'{gps,accuracy}')::numeric>=0,false)))) then raise exception 'GPS_INVALID';end if;
    if (select count(*) from public.sales_delivery_lines l where l.delivery_id=s.id and private.tms_line_balance(l.id)>0)<>jsonb_array_length(p_data->'lines') then raise exception 'RECEIPT_LINES_CHANGED';end if;
    for entry in select value from jsonb_array_elements(p_data->'lines') loop
     select * into line from public.sales_delivery_lines l where l.id=(entry->>'id')::uuid and l.delivery_id=s.id for update;
     if not found then raise exception 'RECEIPT_LINES_INVALID';end if;
     remaining:=private.tms_line_balance(line.id);ac:=coalesce((entry->>'accepted')::numeric,0);rf:=coalesce((entry->>'refused')::numeric,0);mi:=coalesce((entry->>'missing')::numeric,0);de:=coalesce((entry->>'deferred')::numeric,0);
     if remaining<=0 or least(ac,rf,mi,de)<0 or ac+rf+mi+de<>remaining or ac<>round(ac,3) or rf<>round(rf,3) or mi<>round(mi,3) or de<>round(de,3) then raise exception 'RECEIPT_QUANTITY_INVALID';end if;
     accepted_total:=accepted_total+ac;
     lines:=lines||jsonb_build_array(jsonb_build_object('id',line.id,'quantity',remaining,'accepted',ac,'refused',rf,'missing',mi,'deferred',de));
     if rf>0 then return_lines:=return_lines||jsonb_build_array(jsonb_build_object('line_id',line.id,'quantity',rf));end if;
    end loop;
    if accepted_total>0 and (sig is null or length(btrim(coalesce(p_data->>'receiver_name','')))<2) then raise exception 'RECEIVER_SIGNATURE_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'accepted')::numeric<(x->>'quantity')::numeric) and length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'RECEIPT_REASON_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'missing')::numeric>0) and photo is null then raise exception 'INCIDENT_PHOTO_REQUIRED';end if;
    select sum(l.quantity) into total from public.sales_delivery_lines l where l.delivery_id=s.id;
    select accepted_total+coalesce(sum(al.accepted),0) into accepted_total from public.tms_attempt_lines al join public.sales_delivery_lines l on l.id=al.delivery_line_id where l.delivery_id=s.id;
    insert into public.tms_delivery_attempts(delivery_id,route_id,driver_id,attempt_no,request_key,result,receiver_name,reason,occurred_at,actor_id,base_version,gps)
    values(d.id,d.route_id,d.driver_id,coalesce((select max(aa.attempt_no) from public.tms_delivery_attempts aa where aa.delivery_id=d.id),0)+1,key_id,case when accepted_total=total then 'complete' when accepted_total>0 then 'partial' else 'failed' end,btrim(coalesce(p_data->>'receiver_name','')),left(p_data->>'reason',2000),stamp,uid,d.version,coalesce(p_data->'gps','{}')) returning * into a;
    insert into public.tms_attempt_lines(attempt_id,delivery_line_id,quantity,accepted,refused,missing,deferred) select a.id,(x->>'id')::uuid,(x->>'quantity')::numeric,(x->>'accepted')::numeric,(x->>'refused')::numeric,(x->>'missing')::numeric,(x->>'deferred')::numeric from jsonb_array_elements(lines) x;
    if jsonb_array_length(return_lines)>0 then
     ret:=private.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',s.id,'reason','other','notes','Rechazo en entrega · '||coalesce(d.erp_reference,'')||' · '||coalesce(p_data->>'reason',''),'lines',return_lines));
     update public.tms_delivery_attempts set return_id=(ret->>'id')::uuid where id=a.id;
    end if;
    foreach kind in array array['signature','photo'] loop
     media:=case when kind='signature' then sig else photo end;
     if media is not null then
      insert into public.tms_attempt_proofs(attempt_id,kind,content_hash,byte_size,created_by) values(a.id,kind,md5(media),length(media),uid) returning id into proof_id;
      insert into private.tms_attempt_media(proof_id,data_url) values(proof_id,media);
     end if;
    end loop;
    if sig is not null or photo is not null then
     insert into public.tms_proofs(delivery_id,signature,photo,captured_at,captured_by,received_at,gps_status,latitude,longitude,gps_accuracy_m,gps_recorded_at)
     values(d.id,sig,photo,stamp,uid,now(),coalesce(p_data#>>'{gps,status}','unavailable'),case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lat}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lng}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,accuracy}')::float8 end,nullif(p_data#>>'{gps,at}','')::timestamptz)
     on conflict(delivery_id) do update set signature=excluded.signature,photo=excluded.photo,captured_at=excluded.captured_at,captured_by=excluded.captured_by,received_at=excluded.received_at,gps_status=excluded.gps_status,latitude=excluded.latitude,longitude=excluded.longitude,gps_accuracy_m=excluded.gps_accuracy_m,gps_recorded_at=excluded.gps_recorded_at;
    end if;
    update public.tms_deliveries set status=case a.result when 'complete' then 'Entregada' when 'partial' then 'Entrega parcial' else 'Excepción' end,actual_arrival=coalesce(actual_arrival,stamp),delivered_at=case when a.result='complete' then stamp end where id=d.id;
    if a.result<>'complete' then insert into public.tms_delivery_incidents(delivery_id,driver_id,reason,note,created_by,attempt_id) values(d.id,d.driver_id,'refused',left(p_data->>'reason',2000),uid,a.id);end if;
    insert into public.tms_events(delivery_id,type,note,customer,user_id,attempt_id,detail) values(d.id,case when a.result='complete' then 'Entregada' else 'ENTREGA_PARCIAL' end,coalesce(p_data->>'reason','Recepción registrada'),d.customer,uid,a.id,jsonb_build_object('lines',lines,'result',a.result));
   end if;
  end if;
  result:=private.gama_tms_execution('context',jsonb_build_object('delivery_id',d.id));
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-execution',key_id,uid,payload,result);
 return result;
end $$;
revoke all on function private.gama_tms_execution(text,jsonb) from public,anon;
grant execute on function private.gama_tms_execution(text,jsonb) to authenticated;
create function public.gama_tms_execution(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_execution(p_action,p_data)$$;
revoke all on function public.gama_tms_execution(text,jsonb) from public,anon;grant execute on function public.gama_tms_execution(text,jsonb) to authenticated;

revoke all on function private.tms_refused_quantity(uuid),private.tms_line_balance(uuid),private.tms_cargo_known(uuid) from public,anon,authenticated;
create or replace function private.gama_tms_resources() returns jsonb language sql stable security definer set search_path='' as $$select private.gama_tms_resources((now() at time zone private.erp_timezone())::date)$$;
create or replace function private.gama_tms_plan_day() returns jsonb language sql security definer set search_path='' as $$select private.gama_tms_plan_day((now() at time zone private.erp_timezone())::date)$$;

CREATE OR REPLACE FUNCTION private.gama_tms_customer_costs(p_from date, p_to date, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; q text; lim integer; off integer;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>8192 then raise exception 'INVALID_REQUEST';end if;
 q:=btrim(coalesce(p_data->>'search',''));
 if length(q)>100 or coalesce(p_data->>'limit','30') !~ '^[0-9]{1,3}$' or coalesce(p_data->>'offset','0') !~ '^[0-9]{1,9}$' then raise exception 'INVALID_REQUEST';end if;
 lim:=greatest(1,least(100,coalesce(p_data->>'limit','30')::integer));
 off:=coalesce(p_data->>'offset','0')::integer;
 with routes as materialized (
  select r.id,coalesce(s.road_km,r.distance) km,s.road_km is null estimated,r.cost_per_km,
   round(coalesce(s.road_km,r.distance)*r.cost_per_km*100) cents,
   case when jsonb_typeof(r.stops)='array' then r.stops else '[]'::jsonb end stops
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id
  where r.route_date between p_from and p_to
 ), stops as materialized (
  select r.id,stop.id stop_id,r.km,r.estimated,r.cost_per_km,r.cents,
   count(*) over(partition by r.id) n,row_number() over(partition by r.id order by stop.id collate "C") pos
  from routes r cross join lateral (select distinct value id from jsonb_array_elements_text(r.stops) where value<>'__depot') stop
 ), allocated as (
  select x.id route_id,c.id customer_id,case when c.id is null then 'Cliente no identificado' else c.name end customer,
   x.km/x.n km,x.estimated,x.cost_per_km is null missing_cost,c.id is null unknown_customer,
   case when x.cents is null then null else floor(x.cents/x.n)+case when x.pos<=mod(x.cents,x.n) then 1 else 0 end end cents
  from stops x left join public.tms_deliveries d on d.id=case when x.stop_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then x.stop_id::uuid end
  left join public.customers c on c.id=d.customer_id
 ), grouped as materialized (
  select customer_id,customer,count(*) deliveries,count(distinct route_id) routes,sum(km) km,sum(cents)/100 cost,
   count(*) filter(where missing_cost) missing_cost,count(*) filter(where estimated) estimated_stops,count(*) filter(where unknown_customer) unknown_stops
  from allocated group by customer_id,customer
 ), matching as materialized (
  select * from grouped where q='' or position(lower(q) in lower(customer))>0
 ), page as (
  select * from matching order by customer collate "C",customer_id nulls last limit lim offset off
 )
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.customer collate "C",p.customer_id nulls last) from page p),'[]'::jsonb),
  'total',(select count(*) from matching),'offset',off,'limit',lim,
  'unassigned_routes',(select count(*) from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_cost',(select sum(r.cents)/100 from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_missing_cost',(select count(*) from routes r where r.cost_per_km is null and not exists(select 1 from stops x where x.id=r.id))) into result;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_metrics(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 select jsonb_build_object('delivered',count(*) filter(where d.status='Entregada'),'total',count(*),'promised',count(*) filter(where d.initial_promised_until is not null),'otif',count(*) filter(where d.status='Entregada' and d.initial_promised_until is not null and d.delivered_at<=d.initial_promised_until),'partial',count(*) filter(where d.status='Entrega parcial'),'with_eta',count(*) filter(where d.status='Entregada' and d.eta_at is not null),
 'on_time',count(*) filter(where d.status='Entregada' and d.eta_at is not null and d.delivered_at<=d.eta_at),
 'days',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from (select r.route_date as "day",sum(coalesce(s.road_km,r.distance)) km,
  sum(coalesce(s.road_km,r.distance)*r.cost_per_km) cost,count(*) filter(where r.cost_per_km is null) missing_cost
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id where r.route_date between p_from and p_to group by r.route_date)x),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.incidents desc,x.name) from (select coalesce(f.name,'Sin conductor') name,count(*) incidents
  from public.tms_delivery_incidents i left join public.fleet_drivers f on f.id=i.driver_id where (i.created_at at time zone private.erp_timezone())::date between p_from and p_to group by f.id,f.name)x),'[]')) into result
 from public.tms_deliveries d where coalesce((d.initial_promised_until at time zone private.erp_timezone())::date,d.delivery_date) between p_from and p_to and d.status<>'Cancelada';
 return result;
end $function$
;

create or replace function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes integer:=0;km numeric:=0;n integer:=0;travel integer;service integer;waiting integer;arrival timestamptz;start_window timestamptz;end_window timestamptz;delivery public.tms_deliveries;match text[];warnings jsonb:='[]';row public.tms_route_schedules;reason text:=btrim(coalesce(p_data->>'window_exception_reason',''));begin
 perform private.tms_require(null,true,'edit');
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.route_id=r.id order by d.id for update;
 select * into r from public.tms_routes where id=r.id for update;
 if r.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id and s.departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
 if stamp is null or (stamp at time zone private.erp_timezone())::date<>r.route_date or jsonb_typeof(p_data->'legs') is distinct from 'array' or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 if length(btrim(coalesce(p_data->>'road_source','')))<3 then raise exception 'ROAD_SOURCE_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
  if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
  travel:=(x->>'drive_minutes')::integer;service:=(x->>'service_minutes')::integer;
  if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric not between 0 and 20000 then raise exception 'ROUTE_TIME_REQUIRED';end if;
  minutes:=minutes+travel;km:=km+(x->>'road_km')::numeric;arrival:=stamp+make_interval(mins=>minutes);waiting:=0;
  if x->>'id'<>'__depot' then
   select * into delivery from public.tms_deliveries where id::text=x->>'id' and route_id=r.id;if not found then raise exception 'ROUTE_LEGS_CHANGED';end if;
   if delivery.promised_until is not null then
    start_window:=delivery.promised_from;end_window:=delivery.promised_until;
    if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::int;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
    if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
   elsif nullif(btrim(delivery.time_window),'') is not null then
    match:=regexp_match(delivery.time_window,'^\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*[-–]\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*$');
    if match is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_REVIEW_REQUIRED','window',delivery.time_window));
    else
     start_window:=(r.route_date+match[1]::time) at time zone private.erp_timezone();end_window:=(r.route_date+match[2]::time) at time zone private.erp_timezone();if end_window<start_window then end_window:=end_window+interval '1 day';end if;
     if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::integer;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
     if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
    end if;
   end if;
   update public.tms_deliveries set eta_at=arrival,service_minutes=service where id=delivery.id;
  end if;
  legs:=legs||jsonb_build_array(x||jsonb_build_object('waiting_minutes',waiting,'arrival_at',arrival,'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;
 end loop;
 if warnings<>'[]' and length(reason)<3 then raise exception 'TIME_WINDOW_EXCEPTION_REASON_REQUIRED';end if;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes,window_exceptions) values(r.id,stamp,legs,p_data->>'road_source',km,minutes,jsonb_build_object('warnings',warnings,'review_reason',reason)) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,window_exceptions=excluded.window_exceptions,updated_by=auth.uid(),updated_at=now() returning * into row;
 update public.tms_routes set distance=km,distance_basis='road_verified' where id=r.id;
 return to_jsonb(row);end $$;

CREATE OR REPLACE FUNCTION private.gama_tms_today_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=(now() at time zone private.erp_timezone())::date;result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select jsonb_build_object('preparation',(select count(*) from public.sales_orders o where o.status='confirmed' and exists(
   select 1 from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=o.id and p.product_kind='goods'
   and l.quantity>coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))),
  'planning',count(*) filter(where s.departed_at is null and d.route_id is null),
  'loading',count(*) filter(where s.departed_at is null and d.route_id is not null),
  'proof',count(*) filter(where s.departed_at is not null),
  'incidents',count(*) filter(where d.status='Excepción')) into result
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.status not in ('Entregada','Cancelada') and d.settled_at is null;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_my_route()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare driver public.fleet_drivers;day date:=(now() at time zone private.erp_timezone())::date;routes jsonb;deliveries jsonb;
begin
 perform private.tms_require(null,false,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select f.* into driver from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.active and h.active and h.profile_id=auth.uid();
 if driver.id is null then return jsonb_build_object('driver',null,'routes','[]'::jsonb,'deliveries','[]'::jsonb);end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.route_date,r.created_at),'[]') into routes from public.tms_routes r where r.driver_id=driver.id and (r.route_date=day or r.status in ('En ruta','En tránsito')) and r.status<>'Cancelada';
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('phone',c.phone,'shipment_number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at) order by d.delivery_date,d.id),'[]') into deliveries
 from public.tms_deliveries d left join public.customers c on c.id=d.customer_id left join public.sales_deliveries s on s.tms_delivery_id=d.id
 where d.driver_id=driver.id and exists(select 1 from jsonb_array_elements(routes) r where (r->>'id')::uuid=d.route_id) and d.status<>'Cancelada' and d.delivery_date<=day;
 return jsonb_build_object('driver',jsonb_build_object('id',driver.id,'name',driver.name),'routes',routes,'deliveries',deliveries);
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_today_counts(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=p_day;result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select jsonb_build_object('preparation',(select count(*) from public.sales_orders o where o.status='confirmed' and exists(
   select 1 from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=o.id and p.product_kind='goods'
   and l.quantity>coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))),
  'planning',count(*) filter(where s.departed_at is null and d.route_id is null),
  'loading',count(*) filter(where s.departed_at is null and d.route_id is not null),
  'proof',count(*) filter(where s.departed_at is not null),
  'incidents',count(*) filter(where d.status='Excepción')) into result
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.status not in ('Entregada','Cancelada') and d.settled_at is null;
 return result;
end $function$
;

-- Index foreign-key review and closure lookups used by the new commands.
create index tms_attempts_return on public.tms_delivery_attempts(return_id) where return_id is not null;
create index tms_deliveries_cargo_actor on public.tms_deliveries(cargo_verified_by) where cargo_verified_by is not null;
create index tms_deliveries_settled_actor on public.tms_deliveries(settled_by) where settled_by is not null;
create index tms_routes_closed_actor on public.tms_routes(closed_by) where closed_by is not null;
create index tms_incidents_resolved_actor on public.tms_delivery_incidents(resolved_by) where resolved_by is not null;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005230102','tms_execution_phase1','fc9a02827e4ef243a441c7e00559768b7e6aa388853a6a430782b99a15e7cb4a','fc9a02827e4ef243a441c7e00559768b7e6aa388853a6a430782b99a15e7cb4a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261006124000_marketing_campaigns.sql; SHA256 6feff479689ba68ea2a68acc83282c00e91f09196e58b6f0b4ae3f420a00dd87
-- Persisted manual campaigns. Composer opening is recorded; delivery is never claimed.
create table private.marketing_campaigns (
 id uuid primary key default gen_random_uuid(), title text not null check(length(btrim(title)) between 1 and 180),
 channel text not null default 'email' check(channel in ('email','whatsapp')),
 subject text not null default '' check(length(subject)<=150), message text not null default '' check(length(message)<=1800),
 dialing_code text not null default '593' check(dialing_code ~ '^[1-9][0-9]{0,2}$'),
 state text not null default 'draft' check(state in ('draft','prepared','archived')), version integer not null default 1,
 prepared_payload jsonb, created_by uuid not null, updated_by uuid not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index marketing_campaigns_updated on private.marketing_campaigns(updated_at desc,id);
create table private.marketing_recipients (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references private.marketing_campaigns(id) on delete cascade,
 kind text not null check(kind in ('customer','contact','lead')), contact_id uuid not null,
 recipient_group text not null check(recipient_group in ('customer','lead')), label text not null,
 address text, subject text not null, message text not null,
 status text not null check(status in ('prepared','opened','missing_email','duplicate_email','missing_phone','duplicate_phone')),
 opened_at timestamptz, opened_by uuid, unique(campaign_id,kind,contact_id)
);
alter table private.marketing_campaigns enable row level security;
alter table private.marketing_recipients enable row level security;
revoke all on private.marketing_campaigns,private.marketing_recipients from public,anon,authenticated;

create function private.marketing_phone(p_phone text,p_code text) returns text
language plpgsql immutable set search_path='' as $$
declare raw text:=btrim(coalesce(p_phone,''));digits text;
begin
 if raw='' or raw !~ '^\+?[0-9 ().-]+$' or p_code !~ '^[1-9][0-9]{0,2}$' then return null;end if;
 digits:=regexp_replace(raw,'[^0-9]','','g');
 if raw like '+%' then null;
 elsif digits like '00%' then digits:=substr(digits,3);
 elsif digits like p_code||'%' and length(digits)>=11 then null;
 else digits:=p_code||regexp_replace(digits,'^0+','');end if;
 if digits !~ '^[1-9][0-9]{7,14}$' then return null;end if;return digits;
end $$;

-- CRM classification is stored independently of contact foreign keys, preserving access restrictions after deletion.
create function private.marketing_contacts() returns table(id uuid,kind text,recipient_group text,label text,email text,phone text)
language sql stable set search_path='' as $$
 select c.id,'customer','customer',c.name,coalesce(c.email,''),coalesce(c.phone,'') from public.customers c where c.active
 union all select c.id,'contact',case when c.customer_id is not null then 'customer' else 'lead' end,
 coalesce(nullif(btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),nullif(c.email,''),'—'),coalesce(c.email,''),coalesce(c.phone,'')
 from public.crm_contacts c where c.active and private.erp_module_allowed('crm',array['administrador','comercial'])
 and (exists(select 1 from public.customers a where a.id=c.customer_id and a.active) or c.customer_id is null and exists(select 1 from public.crm_leads l where l.id=c.lead_id and l.active and l.converted_customer_id is null))
 union all select l.id,'lead','lead',coalesce(nullif(l.company,''),nullif(btrim(coalesce(l.first_name,'')||' '||coalesce(l.last_name,'')),''),nullif(l.email,''),'—'),coalesce(l.email,''),coalesce(l.phone,'')
 from public.crm_leads l where l.active and l.converted_customer_id is null and private.erp_module_allowed('crm',array['administrador','comercial'])
$$;

create function private.gama_marketing(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();s private.marketing_campaigns;v_rec private.marketing_recipients;c record;
 sid uuid;items jsonb;total bigint;entry jsonb;payload jsonb;seen text[]:='{}';address text;status text;
 off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));term text:=left(coalesce(p_data->>'search',''),100);
 channel text:=coalesce(p_data->>'channel','email');code text:=coalesce(p_data->>'dialing_code','593');
begin
 if actor is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>30000 then raise exception 'MARKETING_INVALID_DATA';end if;
 if p_action='list' then
  select count(*) into total from private.marketing_campaigns where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state');
  select coalesce(jsonb_agg(x),'[]') into items from (select m.id,m.title,m.channel,m.state,m.version,m.updated_at,
   (select count(*) from private.marketing_recipients r where r.campaign_id=m.id and r.status in ('prepared','opened')) prepared,
   (select count(*) from private.marketing_recipients r where r.campaign_id=m.id and r.status='opened') opened
   from private.marketing_campaigns m where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state') order by updated_at desc,id limit 30 offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='search' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'MARKETING_ACCESS_DENIED';end if;
  if channel not in ('email','whatsapp') or code !~ '^[1-9][0-9]{0,2}$' or coalesce(p_data->>'kind','customer') not in ('customer','lead') then raise exception 'MARKETING_INVALID_DATA';end if;
  with filtered as (select * from private.marketing_contacts() where recipient_group=coalesce(p_data->>'kind','customer') and (label ilike '%'||term||'%' or email ilike '%'||term||'%' or phone ilike '%'||term||'%'))
  select (select count(*) from filtered),(select coalesce(jsonb_agg(x),'[]') from (select id,kind,recipient_group as "group",label,email,phone,
   case when channel='whatsapp' then private.marketing_phone(phone,code) is not null else btrim(email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and length(btrim(email))<=254 end selectable
   from filtered order by label,id,kind limit 30 offset off) x) into total,items;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='save' and nullif(p_data->>'id','') is null then
  if not private.erp_action_allowed('surveys','create') then raise exception 'MARKETING_ACCESS_DENIED';end if;
  insert into private.marketing_campaigns(title,channel,subject,message,dialing_code,created_by,updated_by)
   values(btrim(p_data->>'title'),channel,coalesce(p_data->>'subject',''),coalesce(p_data->>'message',''),code,actor,actor) returning * into s;
  return jsonb_build_object('campaign',to_jsonb(s)-'prepared_payload','items','[]'::jsonb);
 end if;
 sid:=(p_data->>'id')::uuid;select * into s from private.marketing_campaigns where id=sid for update;
 if not found then raise exception 'MARKETING_NOT_FOUND';end if;
 if p_action='get' then
  select coalesce(jsonb_agg(x order by x.label,x.id),'[]') into items from (
   select r.id,r.kind,r.contact_id,r.recipient_group as "group",r.label,r.address,r.subject,r.message,r.status,r.opened_at,
    s.state='prepared' and r.status in ('prepared','opened') and exists(select 1 from private.marketing_contacts() mc where mc.id=r.contact_id and mc.kind=r.kind and r.address=case when s.channel='whatsapp' then private.marketing_phone(mc.phone,s.dialing_code) else lower(btrim(mc.email)) end) available
   from private.marketing_recipients r where r.campaign_id=sid and private.erp_module_allowed('contacts',array['administrador','comercial']) and (r.kind='customer' or private.erp_module_allowed('crm',array['administrador','comercial']))
  ) x;
  return jsonb_build_object('campaign',to_jsonb(s)-'prepared_payload','items',items);
 elsif p_action='duplicate' then
  if not private.erp_action_allowed('surveys','create') then raise exception 'MARKETING_ACCESS_DENIED';end if;
  insert into private.marketing_campaigns(title,channel,subject,message,dialing_code,created_by,updated_by)
   values(left(s.title,170)||' (copy)',s.channel,s.subject,s.message,s.dialing_code,actor,actor) returning * into s;
  return jsonb_build_object('campaign',to_jsonb(s)-'prepared_payload','items','[]'::jsonb);
 end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if p_action in ('draft','opened','prepare') and not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if p_action in ('draft','opened') then
  select * into v_rec from private.marketing_recipients where id=(p_data->>'recipient_id')::uuid and campaign_id=sid;
  if not found or v_rec.kind<>'customer' and not private.erp_module_allowed('crm',array['administrador','comercial']) then raise exception 'MARKETING_ACCESS_DENIED';end if;
  if s.state<>'prepared' or v_rec.status not in ('prepared','opened') then raise exception 'MARKETING_LOCKED';end if;
  select * into c from private.marketing_contacts() mc where mc.id=v_rec.contact_id and mc.kind=v_rec.kind;
  if not found or v_rec.address is distinct from (case when s.channel='whatsapp' then private.marketing_phone(c.phone,s.dialing_code) else lower(btrim(c.email)) end) then raise exception 'MARKETING_CONTACT_CHANGED';end if;
  if p_action='opened' then update private.marketing_recipients set status='opened',opened_at=coalesce(opened_at,now()),opened_by=coalesce(opened_by,actor) where id=v_rec.id returning * into v_rec;end if;
  return jsonb_build_object('id',v_rec.id,'address',v_rec.address,'subject',v_rec.subject,'message',v_rec.message,'status',v_rec.status,'channel',s.channel);
 elsif p_action='prepare' then
  if jsonb_typeof(p_data->'recipients') is distinct from 'array' or jsonb_array_length(p_data->'recipients') not between 1 and 50 then raise exception 'MARKETING_INVALID_DATA';end if;
  select jsonb_agg(x order by x->>'kind',x->>'id') into payload from (select distinct jsonb_build_object('kind',value->>'kind','id',value->>'id') x from jsonb_array_elements(p_data->'recipients')) a;
  if s.state='prepared' and s.prepared_payload=payload then return private.gama_marketing('get',jsonb_build_object('id',sid));end if;
  if s.state<>'draft' then raise exception 'MARKETING_LOCKED';end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
  if btrim(s.message)='' or s.channel='email' and btrim(s.subject)='' then raise exception 'MARKETING_INVALID_DATA';end if;
  for entry in select value from jsonb_array_elements(payload) loop
   if coalesce(entry->>'kind','') not in ('customer','lead','contact') then raise exception 'MARKETING_INVALID_CONTACT';end if;
   select * into c from private.marketing_contacts() mc where mc.id=(entry->>'id')::uuid and mc.kind=entry->>'kind';
   if not found then raise exception 'MARKETING_INVALID_CONTACT';end if;
   address:=case when s.channel='whatsapp' then private.marketing_phone(c.phone,s.dialing_code) else lower(btrim(c.email)) end;
   if address is null or s.channel='email' and (address !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(address)>254) then status:=case when s.channel='whatsapp' then 'missing_phone' else 'missing_email' end;
   elsif address=any(seen) then status:=case when s.channel='whatsapp' then 'duplicate_phone' else 'duplicate_email' end;
   else status:='prepared';seen:=array_append(seen,address);end if;
   insert into private.marketing_recipients(campaign_id,kind,contact_id,recipient_group,label,address,subject,message,status)
    values(sid,c.kind,c.id,c.recipient_group,c.label,address,replace(replace(s.subject,'{campaign}',s.title),'{name}',c.label),replace(replace(s.message,'{campaign}',s.title),'{name}',c.label),status);
  end loop;
  update private.marketing_campaigns set state='prepared',prepared_payload=payload,version=version+1,updated_by=actor,updated_at=now() where id=sid;
  return private.gama_marketing('get',jsonb_build_object('id',sid));
 end if;
 if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
 if p_action='save' then
  if s.state<>'draft' then raise exception 'MARKETING_LOCKED';end if;
  update private.marketing_campaigns set title=btrim(p_data->>'title'),channel=coalesce(p_data->>'channel','email'),subject=coalesce(p_data->>'subject',''),message=coalesce(p_data->>'message',''),dialing_code=code,version=version+1,updated_by=actor,updated_at=now() where id=sid returning * into s;
 elsif p_action='archive' then
  if s.state='archived' then raise exception 'MARKETING_LOCKED';end if;
  update private.marketing_campaigns set state='archived',version=version+1,updated_by=actor,updated_at=now() where id=sid returning * into s;
 else raise exception 'MARKETING_INVALID_ACTION';end if;
 return private.gama_marketing('get',jsonb_build_object('id',sid));
end $$;
create function public.gama_marketing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_marketing(p_action,p_data)$$;
revoke all on function private.marketing_phone(text,text),private.marketing_contacts(),private.gama_marketing(text,jsonb),public.gama_marketing(text,jsonb) from public,anon,authenticated;
grant execute on function private.gama_marketing(text,jsonb),public.gama_marketing(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261006124000','marketing_campaigns','6feff479689ba68ea2a68acc83282c00e91f09196e58b6f0b4ae3f420a00dd87','6feff479689ba68ea2a68acc83282c00e91f09196e58b6f0b4ae3f420a00dd87','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261006130042_marketing_attachments.sql; SHA256 1a8bb975275dd56648ed0e243b2cd012c4883c6b291dbaffa4751508f5db125a
-- Files are private binary payloads, loaded separately from campaign lists.
-- Duplicated campaigns share immutable bytes rather than copying large files.
create table private.marketing_attachment_files (
 id uuid primary key, filename text not null check(length(filename) between 1 and 200 and filename !~ '[[:cntrl:]/\\]'),
 mime_type text not null, content bytea not null check(octet_length(content) between 1 and 5242880),
 created_at timestamptz not null default now(), created_by uuid not null
);
create table private.marketing_campaign_attachments (
 campaign_id uuid not null references private.marketing_campaigns(id) on delete cascade,
 attachment_id uuid not null references private.marketing_attachment_files(id),
 primary key(campaign_id,attachment_id)
);
create index marketing_campaign_attachments_file on private.marketing_campaign_attachments(attachment_id);
alter table private.marketing_attachment_files enable row level security;
alter table private.marketing_campaign_attachments enable row level security;
revoke all on private.marketing_attachment_files,private.marketing_campaign_attachments from public,anon,authenticated;

create function private.marketing_attachment_list(p_campaign uuid) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'filename',f.filename,'mime_type',f.mime_type,'size',octet_length(f.content)) order by f.created_at,f.id),'[]')
 from private.marketing_campaign_attachments a join private.marketing_attachment_files f on f.id=a.attachment_id where a.campaign_id=p_campaign
$$;
revoke all on function private.marketing_attachment_list(uuid) from public,anon,authenticated;

create function private.gama_marketing_attachments(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();s private.marketing_campaigns;f private.marketing_attachment_files;
 sid uuid;fid uuid;bytes bytea;mime text;ext text;filename text;linked boolean;amount bigint;count_files bigint;
begin
 if actor is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>7050000 then raise exception 'MARKETING_FILE_LIMIT';end if;
 sid:=(p_data->>'id')::uuid;select * into s from private.marketing_campaigns where id=sid for update;
 if not found then raise exception 'MARKETING_NOT_FOUND';end if;
 if p_action='list' then return jsonb_build_object('attachments',private.marketing_attachment_list(sid));end if;
 fid:=(p_data->>'attachment_id')::uuid;
 select * into f from private.marketing_attachment_files af where af.id=fid;
 select exists(select 1 from private.marketing_campaign_attachments a where a.campaign_id=sid and a.attachment_id=fid) into linked;
 if p_action='file' then
  if not linked then raise exception 'MARKETING_FILE_UNAVAILABLE';end if;
  return jsonb_build_object('id',f.id,'filename',f.filename,'mime_type',f.mime_type,'size',octet_length(f.content),'content_base64',encode(f.content,'base64'));
 end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if s.state<>'draft' then raise exception 'MARKETING_LOCKED';end if;
 if s.channel<>'email' then raise exception 'MARKETING_ATTACHMENTS_EMAIL_ONLY';end if;
 if p_action='add' then
  filename:=p_data->>'filename';ext:=lower(substring(filename from '\.([^.]+)$'));
  mime:=case ext when 'pdf' then 'application/pdf' when 'jpg' then 'image/jpeg' when 'jpeg' then 'image/jpeg' when 'png' then 'image/png' when 'webp' then 'image/webp'
   when 'txt' then 'text/plain' when 'csv' then 'text/csv' when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
   when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' when 'pptx' then 'application/vnd.openxmlformats-officedocument.presentationml.presentation' end;
  if fid is null or coalesce(length(filename),0) not between 1 and 200 or filename ~ '[[:cntrl:]/\\]' or mime is null or coalesce(p_data->>'content_base64','') !~ '^[A-Za-z0-9+/]+={0,2}$' then raise exception 'MARKETING_FILE_FORMAT';end if;
  begin bytes:=decode(p_data->>'content_base64','base64');exception when others then raise exception 'MARKETING_FILE_FORMAT';end;
  if octet_length(bytes) not between 1 and 5242880 then raise exception 'MARKETING_FILE_LIMIT';end if;
  if f.id is not null then
   if not linked or f.filename<>filename or f.mime_type<>mime or f.content<>bytes then raise exception 'MARKETING_FILE_CHANGED';end if;
   -- Same upload identity may safely retry after the original response was lost.
   return private.gama_marketing('get',jsonb_build_object('id',sid))||jsonb_build_object('attachments',private.marketing_attachment_list(sid));
  end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
  select count(*),coalesce(sum(octet_length(af.content)),0) into count_files,amount from private.marketing_campaign_attachments a join private.marketing_attachment_files af on af.id=a.attachment_id where a.campaign_id=sid;
  if count_files>=5 or amount+octet_length(bytes)>15728640 then raise exception 'MARKETING_FILE_LIMIT';end if;
  insert into private.marketing_attachment_files(id,filename,mime_type,content,created_by) values(fid,filename,mime,bytes,actor);
  insert into private.marketing_campaign_attachments(campaign_id,attachment_id) values(sid,fid);
 elsif p_action='remove' then
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
  if not linked then raise exception 'MARKETING_FILE_UNAVAILABLE';end if;
  delete from private.marketing_campaign_attachments where campaign_id=sid and attachment_id=fid;
  delete from private.marketing_attachment_files af where af.id=fid and not exists(select 1 from private.marketing_campaign_attachments a where a.attachment_id=fid);
 else raise exception 'MARKETING_INVALID_ACTION';end if;
 update private.marketing_campaigns set version=version+1,updated_at=now(),updated_by=actor where id=sid;
 return private.gama_marketing('get',jsonb_build_object('id',sid))||jsonb_build_object('attachments',private.marketing_attachment_list(sid));
end $$;

-- Extend the existing contract without replacing its recipient and authorization logic.
create function private.gama_marketing_with_attachments(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;sid uuid;source_id uuid;
begin
 if auth.uid() is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>30000 then raise exception 'MARKETING_INVALID_DATA';end if;
 if p_action='save' and p_data->>'channel'='whatsapp' and nullif(p_data->>'id','') is not null then
  -- Serialize channel changes with attachment writes and preparation.
  source_id:=(p_data->>'id')::uuid;perform 1 from private.marketing_campaigns where id=source_id for update;
  if exists(select 1 from private.marketing_campaign_attachments a where a.campaign_id=source_id) then raise exception 'MARKETING_ATTACHMENTS_EMAIL_ONLY';end if;
 end if;
 result:=private.gama_marketing(p_action,p_data);
 if p_action='duplicate' then
  source_id:=(p_data->>'id')::uuid;sid:=(result->'campaign'->>'id')::uuid;
  insert into private.marketing_campaign_attachments(campaign_id,attachment_id) select sid,a.attachment_id from private.marketing_campaign_attachments a where a.campaign_id=source_id;
 end if;
 if result ? 'campaign' then
  sid:=(result->'campaign'->>'id')::uuid;return result||jsonb_build_object('attachments',private.marketing_attachment_list(sid));
 elsif p_action='draft' then
  return result||jsonb_build_object('attachments',private.marketing_attachment_list((p_data->>'id')::uuid));
 end if;
 return result;
end $$;
create or replace function public.gama_marketing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_marketing_with_attachments(p_action,p_data)$$;
create function public.gama_marketing_attachments(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_marketing_attachments(p_action,p_data)$$;
revoke all on function private.gama_marketing_with_attachments(text,jsonb),private.gama_marketing_attachments(text,jsonb),public.gama_marketing_attachments(text,jsonb) from public,anon,authenticated;
grant execute on function private.gama_marketing_with_attachments(text,jsonb),private.gama_marketing_attachments(text,jsonb),public.gama_marketing_attachments(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261006130042','marketing_attachments','1a8bb975275dd56648ed0e243b2cd012c4883c6b291dbaffa4751508f5db125a','1a8bb975275dd56648ed0e243b2cd012c4883c6b291dbaffa4751508f5db125a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261006214828_performance_security_audit.sql; SHA256 e44849e182939e95d1d9e6442aecc82bae67db4fd7ce09fe6fe8723555fbd166
-- No business rows are edited by this audit migration.
set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- Existing JWTs must also respect a ban or deletion of their live Auth session.
-- Legacy trusted JWTs without session_id retain their historical compatibility.
create or replace function private.erp_mfa_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select (
  auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (
   nullif(auth.jwt()->>'session_id','') is null
   or exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id'
    and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()))
  )
  and (coalesce(auth.jwt()->>'aal'='aal2',false)
   or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
 ) or private.automation_delegation_ok()
$$;

-- Only stable/immutable, scalar, zero-argument helpers are request constants.
-- Row-dependent ownership/module checks stay correlated with their original row.
do $$
declare p record; f record; expression text; checked text; pattern text;
begin
 for p in select * from pg_policies where schemaname in ('public','storage') loop
  expression:=p.qual;checked:=p.with_check;
  for f in
   select n.nspname,fn.proname from pg_proc fn join pg_namespace n on n.oid=fn.pronamespace
   where n.nspname in ('auth','private') and fn.pronargs=0 and fn.provolatile in ('s','i')
    and not fn.proretset and fn.prorettype<>'trigger'::regtype
  loop
   pattern:='(?<!SELECT )'||f.nspname||'[.]'||f.proname||'\(\)';
   expression:=regexp_replace(expression,pattern,'(SELECT '||f.nspname||'.'||f.proname||'())','g');
   checked:=regexp_replace(checked,pattern,'(SELECT '||f.nspname||'.'||f.proname||'())','g');
  end loop;
  if expression is distinct from p.qual or checked is distinct from p.with_check then
   execute format('alter policy %I on %I.%I%s%s',p.policyname,p.schemaname,p.tablename,
    case when expression is null then '' else ' using ('||expression||')' end,
    case when checked is null then '' else ' with check ('||checked||')' end);
  end if;
 end loop;
end $$;

-- Combine permissive OR predicates by command and exact role group.
-- Restrictive MFA/customer policies are never merged, removed or broadened.
do $$
declare t record; original jsonb; scope record; command text; roles_sql text;
 predicate text; checked text; policy text; old_policy text; retained text[];
begin
 for t in select distinct schemaname,tablename from pg_policies where schemaname='public' and permissive='PERMISSIVE' loop
  select jsonb_agg(to_jsonb(p)) into original from pg_policies p
   where p.schemaname=t.schemaname and p.tablename=t.tablename and p.permissive='PERMISSIVE';
  retained:=array[]::text[];
  for scope in select distinct value->'roles' roles from jsonb_array_elements(original) loop
   select string_agg(quote_ident(value #>> '{}'),',') into roles_sql from jsonb_array_elements(scope.roles);
   foreach command in array array['SELECT','INSERT','UPDATE','DELETE'] loop
    if not exists(select 1 from jsonb_array_elements(original) p
     where p->'roles'=scope.roles and p->>'cmd' in ('ALL',command)) then continue;end if;
    select string_agg('('||coalesce(p->>'qual','true')||')',' OR ' order by p->>'policyname'),
     string_agg('('||coalesce(p->>'with_check',p->>'qual','true')||')',' OR ' order by p->>'policyname')
    into predicate,checked from jsonb_array_elements(original) p
    where p->'roles'=scope.roles and p->>'cmd' in ('ALL',command);
    policy:='coco_perf_'||lower(command)||'_'||substr(md5(scope.roles::text),1,8);
    execute format('drop policy if exists %I on %I.%I',policy,t.schemaname,t.tablename);
    execute format('create policy %I on %I.%I for %s to %s%s%s',policy,t.schemaname,t.tablename,command,roles_sql,
     case when command='INSERT' then '' else ' using ('||predicate||')' end,
     case when command in ('INSERT','UPDATE') then ' with check ('||checked||')' else '' end);
    retained:=array_append(retained,policy);
   end loop;
  end loop;
  for old_policy in select p->>'policyname' from jsonb_array_elements(original) p loop
   if not old_policy=any(retained) then
    execute format('drop policy %I on %I.%I',old_policy,t.schemaname,t.tablename);
   end if;
  end loop;
 end loop;
end $$;

-- A FK needs the referencing columns at the front of a valid full B-tree.
-- Existing indexes with additional trailing columns already cover it.
do $$
declare f record; columns_sql text; index_name text;
begin
 for f in
  select con.*,n.nspname,c.relname from pg_constraint con
  join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where con.contype='f' and n.nspname in ('public','private')
   and not exists(select 1 from pg_index i join pg_class ic on ic.oid=i.indexrelid
    join pg_am am on am.oid=ic.relam where i.indrelid=con.conrelid and i.indisvalid
    and i.indpred is null and am.amname='btree'
    and (i.indkey::smallint[])[0:array_length(con.conkey,1)-1] @> con.conkey)
  order by n.nspname,c.relname,con.conname
 loop
  select string_agg(quote_ident(a.attname),',' order by keys.ordinality) into columns_sql
   from unnest(f.conkey) with ordinality keys(attnum,ordinality)
   join pg_attribute a on a.attrelid=f.conrelid and a.attnum=keys.attnum;
  index_name:='coco_fk_'||substr(f.relname,1,24)||'_'||substr(md5(f.conname),1,12);
  execute format('create index if not exists %I on %I.%I (%s)',index_name,f.nspname,f.relname,columns_sql);
 end loop;
end $$;

-- Drop only the audited duplicate, never a constraint-backed or unequal index.
do $$
declare pair record;
begin
 for pair in select * from (values
  ('hr_employees_unique_profile','hr_employees_profile_uniq'),
  ('purchase_orders_order_number_uidx','purchase_orders_order_number_key'),
  ('process_credit_invoice','return_credits_invoice'),
  ('stock_movements_created_idx','stock_movements_created_at_idx'),
  ('tms_deliveries_customer_id_idx','tms_deliveries_customer_idx')
 ) duplicates(remove_name,keep_name) loop
  if exists(
   select 1 from pg_index a join pg_index b on a.indrelid=b.indrelid
    join pg_class ac on ac.oid=a.indexrelid join pg_class bc on bc.oid=b.indexrelid
   where ac.oid=to_regclass('public.'||pair.remove_name) and bc.oid=to_regclass('public.'||pair.keep_name)
    and a.indkey=b.indkey and a.indclass=b.indclass and a.indcollation=b.indcollation
    and a.indoption=b.indoption and a.indisunique=b.indisunique and ac.relam=bc.relam
    and coalesce(pg_get_expr(a.indpred,a.indrelid),'')=coalesce(pg_get_expr(b.indpred,b.indrelid),'')
    and coalesce(pg_get_expr(a.indexprs,a.indrelid),'')=coalesce(pg_get_expr(b.indexprs,b.indrelid),'')
    and b.indisvalid and not exists(select 1 from pg_constraint c where c.conindid=a.indexrelid)
  ) then execute format('drop index public.%I',pair.remove_name);end if;
 end loop;
end $$;

revoke all on function private.gama_lock_quant(uuid,uuid),private.gama_sync_product_stock(uuid),
 private.gama_return_split(uuid,numeric),private.gama_audit_row(),private.touch_updated_at(),
 private.tms_execution_version() from public,anon,authenticated;
revoke all on function private.my_employee_id() from public,anon;
grant execute on function private.my_employee_id() to authenticated;
alter default privileges in schema public revoke execute on functions from public,anon,authenticated;
alter default privileges in schema private revoke execute on functions from public,anon,authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261006214828','performance_security_audit','e44849e182939e95d1d9e6442aecc82bae67db4fd7ce09fe6fe8723555fbd166','e44849e182939e95d1d9e6442aecc82bae67db4fd7ce09fe6fe8723555fbd166','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261006225816_storefront_legal_identity.sql; SHA256 c0806e06e0357dccbf28d97b297edfc2a046f45bbf65fe39c6cf5136aede3356
-- Additional editable legal information. No business identity is invented.
begin;
create or replace function private.gama_storefront_schema() returns jsonb language sql immutable set search_path='' as $schema$ select '{"version":2,"groups":[{"id":"identity","label":["Identidad y diseño","Identité et apparence","Identity and design"],"fields":[{"key":"brand_name","label":["Nombre comercial","Nom commercial","Brand name"],"type":"text","max":100,"default":"Distribuidora GAMA"},{"key":"tagline","label":["Firma de marca","Signature de marque","Tagline"],"type":"text","max":120,"default":"Lo pides, lo tienes."},{"key":"logo_url","label":["Logotipo","Logo","Logo"],"type":"image","max":400000,"default":""},{"key":"primary_color","label":["Color principal","Couleur principale","Primary color"],"type":"color","default":"#176072"},{"key":"accent_color","label":["Color de acento","Couleur d’accent","Accent color"],"type":"color","default":"#e4884f"},{"key":"background_color","label":["Fondo","Fond","Background"],"type":"color","default":"#f7f6f2"},{"key":"corner_style","label":["Esquinas","Angles","Corners"],"type":"enum","options":["soft","square"],"option_labels":[["Redondeadas","Arrondis","Rounded"],["Rectas","Droits","Square"]],"default":"soft"},{"key":"navigation","label":["Menú","Menu","Navigation"],"type":"list","max":6,"default":[{"label":"Catálogo","href":"#catalogo"},{"label":"Sobre GAMA","href":"#nosotros"},{"label":"Contacto","href":"#contacto"}],"fields":[{"key":"label","label":["Texto","Texte","Text"],"type":"text","max":40},{"key":"href","label":["Destino","Destination","Destination"],"type":"link","max":500}]}]},{"id":"home","label":["Página de inicio","Page d’accueil","Homepage"],"fields":[{"key":"announcement","label":["Banda superior","Bandeau supérieur","Announcement"],"type":"text","max":180,"default":"Abastecemos el día a día de tu empresa · Quito, Ecuador"},{"key":"hero_label","label":["Etiqueta de inicio","Accroche","Hero label"],"type":"text","max":80,"default":"Tu empresa, bien abastecida"},{"key":"hero_title","label":["Título principal","Titre principal","Hero title"],"type":"text","max":120,"default":"Todo lo que necesitas."},{"key":"hero_accent","label":["Segunda línea del título","Deuxième ligne du titre","Title second line"],"type":"text","max":120,"default":"En un solo lugar."},{"key":"hero_intro","label":["Presentación","Présentation","Introduction"],"type":"textarea","max":600,"default":"Productos para tu equipo, tu oficina y cada pausa del día. Encuentra lo que buscas y recibe una atención cercana, de principio a fin."},{"key":"hero_image","label":["Imagen principal (opcional)","Image principale (facultative)","Hero image (optional)"],"type":"image","max":700000,"default":""},{"key":"hero_button","label":["Texto del botón","Texte du bouton","Button label"],"type":"text","max":45,"default":"Explorar el catálogo"},{"key":"hero_button_target","label":["Destino del botón","Destination du bouton","Button destination"],"type":"enum","options":["catalogo","contacto"],"option_labels":[["Catálogo","Catalogue","Catalogue"],["Contacto","Contact","Contact"]],"default":"catalogo"},{"key":"catalog_title","label":["Título del catálogo","Titre du catalogue","Catalogue title"],"type":"text","max":100,"default":"Encuentra tu próximo imprescindible."},{"key":"catalog_intro","label":["Texto del catálogo","Texte du catalogue","Catalogue introduction"],"type":"textarea","max":350,"default":"Una selección para acompañar el día a día de tu negocio."},{"key":"featured_title","label":["Título de destacados","Titre de la sélection","Featured title"],"type":"text","max":100,"default":"La selección GAMA"},{"key":"categories_title","label":["Título de categorías","Titre des catégories","Categories title"],"type":"text","max":100,"default":"Cada necesidad, su solución."},{"key":"show_featured","label":["Mostrar destacados","Afficher la sélection","Show featured products"],"type":"boolean","default":true},{"key":"show_categories","label":["Mostrar categorías","Afficher les catégories","Show categories"],"type":"boolean","default":true},{"key":"show_benefits","label":["Mostrar ventajas","Afficher les avantages","Show benefits"],"type":"boolean","default":true},{"key":"benefits","label":["Ventajas","Avantages","Benefits"],"type":"list","max":4,"default":[{"icon":"box","title":"Un solo proveedor","text":"Haz más sencilla la compra de los productos de tu empresa."},{"icon":"headset","title":"Atención cercana","text":"Te acompañamos para encontrar lo que necesitas."},{"icon":"truck","title":"Entrega coordinada","text":"Confirmamos contigo disponibilidad, condiciones y entrega."}],"fields":[{"key":"icon","label":["Icono","Icône","Icon"],"type":"enum","options":["box","headset","truck","shield"],"option_labels":[["Caja","Colis","Box"],["Atención","Assistance","Support"],["Entrega","Livraison","Delivery"],["Confianza","Confiance","Trust"]]},{"key":"title","label":["Título","Titre","Title"],"type":"text","max":70},{"key":"text","label":["Descripción","Description","Description"],"type":"textarea","max":200}]}]},{"id":"content","label":["Contenido y páginas","Contenu et pages","Content and pages"],"fields":[{"key":"show_about","label":["Mostrar presentación","Afficher la présentation","Show about section"],"type":"boolean","default":true},{"key":"about_title","label":["Título de presentación","Titre de présentation","About title"],"type":"text","max":120,"default":"Tu negocio avanza. Nosotros lo acompañamos."},{"key":"about_text","label":["Sobre la empresa","À propos de l’entreprise","About the business"],"type":"textarea","max":2000,"default":"En GAMA hacemos más sencilla la búsqueda de productos para tu empresa. Nuestro catálogo reúne una selección práctica y un equipo dispuesto a ayudarte. Cuéntanos qué necesitas: prepararemos una propuesta para ti."},{"key":"about_image","label":["Imagen de presentación","Image de présentation","About image"],"type":"image","max":700000,"default":""},{"key":"show_faq","label":["Mostrar preguntas frecuentes","Afficher les questions fréquentes","Show FAQ"],"type":"boolean","default":true},{"key":"faq","label":["Preguntas frecuentes","Questions fréquentes","Frequently asked questions"],"type":"list","max":10,"default":[{"question":"¿Cómo solicito una cotización?","answer":"Añade productos a tu selección y envía la solicitud con tus datos de contacto. Nuestro equipo confirmará precios, disponibilidad y condiciones."},{"question":"¿Puedo consultar por otros productos?","answer":"Sí. Contacta con nuestro equipo y cuéntanos qué necesita tu empresa."}],"fields":[{"key":"question","label":["Pregunta","Question","Question"],"type":"text","max":180},{"key":"answer","label":["Respuesta","Réponse","Answer"],"type":"textarea","max":1000}]},{"key":"brands","label":["Marcas (opcional)","Marques (facultatif)","Brands (optional)"],"type":"list","max":12,"default":[],"fields":[{"key":"name","label":["Nombre","Nom","Name"],"type":"text","max":70},{"key":"image","label":["Imagen","Image","Image"],"type":"url","max":500}]},{"key":"terms_title","label":["Título de condiciones","Titre des conditions","Terms title"],"type":"text","max":100,"default":"Condiciones de la solicitud"},{"key":"terms_text","label":["Condiciones","Conditions","Terms"],"type":"textarea","max":6000,"default":"Enviar una solicitud no confirma una compra ni reserva productos. Nuestro equipo confirmará la disponibilidad, los precios finales y las condiciones de pago y entrega antes de acordar un pedido."},{"key":"privacy_title","label":["Título de privacidad","Titre de confidentialité","Privacy title"],"type":"text","max":100,"default":"Privacidad"},{"key":"privacy_text","label":["Información de privacidad","Informations de confidentialité","Privacy information"],"type":"textarea","max":6000,"default":"Utilizamos los datos de contacto que nos envías para atender tu solicitud. Puedes contactar con nosotros para consultar el uso de tus datos. No envíes datos bancarios ni información sensible a través de este formulario."},{"key":"footer_note","label":["Texto del pie de página","Texte du pied de page","Footer text"],"type":"textarea","max":350,"default":"Productos y atención para el día a día de tu empresa."}]},{"id":"legal","label":["Información legal","Informations légales","Legal information"],"fields":[{"key":"legal_name","label":["Razón social","Raison sociale","Legal entity name"],"type":"text","max":160,"default":""},{"key":"legal_tax_id","label":["RUC (13 dígitos)","RUC (13 chiffres)","Tax ID (13 digits)"],"type":"text","max":13,"default":""},{"key":"privacy_email","label":["Contacto de privacidad","Contact confidentialité","Privacy contact"],"type":"email","max":254,"default":""},{"key":"notice_title","label":["Título de información legal","Titre des mentions légales","Legal information title"],"type":"text","max":100,"default":"Información legal"},{"key":"notice_text","label":["Información legal adicional","Mentions légales complémentaires","Additional legal information"],"type":"textarea","max":6000,"default":""},{"key":"delivery_title","label":["Título de entregas y devoluciones","Titre livraison et retours","Delivery and returns title"],"type":"text","max":100,"default":"Entregas, cambios y garantías"},{"key":"delivery_text","label":["Entregas, cambios y garantías","Livraison, retours et garanties","Delivery, returns and warranties"],"type":"textarea","max":6000,"default":"Antes de aceptar un pedido, confirmaremos por escrito la disponibilidad, la zona de entrega, el plazo, el costo del envío y las condiciones de pago. El envío no está incluido en el importe indicativo del catálogo.\n\nPara consultar por una entrega, un producto defectuoso, una garantía o una devolución, contacta con GAMA e indica la referencia del pedido y del producto. Revisaremos la solicitud según las condiciones acordadas y los derechos que reconoce la legislación ecuatoriana. Las garantías y los derechos legales del consumidor no se limitan por estas condiciones."},{"key":"storage_title","label":["Título de almacenamiento","Titre du stockage","Storage information title"],"type":"text","max":100,"default":"Cookies y almacenamiento"},{"key":"storage_text","label":["Cookies y almacenamiento","Cookies et stockage","Cookies and storage"],"type":"textarea","max":6000,"default":"El catálogo utiliza el almacenamiento de sesión del navegador para conservar los identificadores y cantidades de tu selección en esta pestaña. No guarda en ese espacio tu nombre, correo electrónico ni el contenido del formulario.\n\nEl portal Mi empresa utiliza una sesión de autenticación para mostrar los datos de la empresa autorizada. Puedes cerrarla con Cerrar sesión.\n\nEste catálogo no incorpora herramientas publicitarias, píxeles de seguimiento ni analítica de comportamiento. La infraestructura puede procesar datos técnicos de conexión para servir y proteger el sitio. Los enlaces externos se rigen por las políticas de sus respectivos sitios. Puedes borrar los datos de navegación en los ajustes de tu navegador; la selección o la sesión podrían perderse."}]},{"id":"contact","label":["Contacto","Contact","Contact"],"fields":[{"key":"show_contact","label":["Mostrar contacto","Afficher les coordonnées","Show contact section"],"type":"boolean","default":true},{"key":"contact_title","label":["Título de contacto","Titre de contact","Contact title"],"type":"text","max":120,"default":"Hablemos de lo que necesitas."},{"key":"contact_intro","label":["Texto de contacto","Texte de contact","Contact introduction"],"type":"textarea","max":500,"default":"Una consulta, una lista de productos o tu próximo pedido. Estamos para ayudarte."},{"key":"phone","label":["Teléfono","Téléphone","Phone"],"type":"text","max":60,"default":"(593-2) 250-1350"},{"key":"email","label":["Correo electrónico","Adresse e-mail","Email"],"type":"email","max":254,"default":""},{"key":"address","label":["Dirección","Adresse","Address"],"type":"textarea","max":300,"default":"Puerto Rico N27-108 y Selva Alegre, Quito"},{"key":"whatsapp","label":["WhatsApp (con código de país)","WhatsApp (avec indicatif du pays)","WhatsApp (with country code)"],"type":"text","max":30,"default":""},{"key":"opening_hours","label":["Horario de atención","Horaires d’ouverture","Opening hours"],"type":"textarea","max":300,"default":""},{"key":"map_url","label":["Enlace al mapa","Lien vers la carte","Map link"],"type":"url","max":500,"default":""},{"key":"facebook_url","label":["Facebook","Facebook","Facebook"],"type":"url","max":500,"default":""},{"key":"instagram_url","label":["Instagram","Instagram","Instagram"],"type":"url","max":500,"default":""},{"key":"linkedin_url","label":["LinkedIn","LinkedIn","LinkedIn"],"type":"url","max":500,"default":""}]},{"id":"publication","label":["Publicación y catálogo","Publication et catalogue","Publication and catalogue"],"fields":[{"key":"site_enabled","label":["Publicar el sitio","Publier le site","Publish website"],"type":"boolean","default":true},{"key":"website_url","label":["Dirección del sitio Cloudflare","Adresse du site Cloudflare","Cloudflare website address"],"type":"url","max":500,"default":""},{"key":"show_prices","label":["Mostrar precios","Afficher les prix","Show prices"],"type":"boolean","default":true},{"key":"price_display","label":["Presentación de precios","Affichage des prix","Price display"],"type":"enum","options":["with_tax","without_tax"],"option_labels":[["Con impuestos","Taxes comprises","Including tax"],["Sin impuestos","Hors taxes","Excluding tax"]],"default":"with_tax"},{"key":"enable_quotes","label":["Recibir solicitudes de cotización","Recevoir des demandes de devis","Accept quote requests"],"type":"boolean","default":true},{"key":"quote_label","label":["Nombre de la selección","Nom de la sélection","Selection label"],"type":"text","max":50,"default":"Mi cotización"},{"key":"default_sort","label":["Orden del catálogo","Tri du catalogue","Catalogue sorting"],"type":"enum","options":["featured","name","price_asc","price_desc"],"option_labels":[["Destacados primero","Sélection en premier","Featured first"],["Nombre","Nom","Name"],["Precio creciente","Prix croissant","Price ascending"],["Precio decreciente","Prix décroissant","Price descending"]],"default":"featured"},{"key":"page_size","label":["Productos por página","Produits par page","Products per page"],"type":"enum","options":["12","24","36"],"option_labels":[["12","12","12"],["24","24","24"],["36","36","36"]],"default":"12"},{"key":"seo_title","label":["Título para buscadores","Titre pour les moteurs de recherche","Search engine title"],"type":"text","max":100,"default":"Distribuidora GAMA | Productos para tu empresa en Quito"},{"key":"seo_description","label":["Descripción para buscadores","Description pour les moteurs de recherche","Search engine description"],"type":"textarea","max":320,"default":"Descubre el catálogo de Distribuidora GAMA. Productos para tu empresa, atención personalizada y solicitudes de cotización en Quito, Ecuador."}]}]}'::jsonb $schema$;
revoke all on function private.gama_storefront_schema() from public,anon,authenticated;
update private.website_public_settings set config=private.gama_storefront_defaults()||config,version=version+1,updated_at=now() where id;
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261006225816','storefront_legal_identity','c0806e06e0357dccbf28d97b297edfc2a046f45bbf65fe39c6cf5136aede3356','c0806e06e0357dccbf28d97b297edfc2a046f45bbf65fe39c6cf5136aede3356','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261007015617_storefront_category_photos.sql; SHA256 29fc1f36e9e7d3c6819cc66b12223412c8f7195c43847470dfb477a55d7867cc
-- Categories use an actual published product photo, or a neutral icon when absent.
-- Keep the existing public API, authorization and private-data projection intact.
begin;
do $$
declare definition text; before_text text := 'min(id::text) photo_id';
begin
 definition := pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure);
 if strpos(definition,before_text)=0 then raise exception 'STOREFRONT_CATEGORY_PROJECTION_CHANGED'; end if;
 execute replace(definition,before_text,'min(id::text) filter (where has_photo) photo_id');
end $$;
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261007015617','storefront_category_photos','29fc1f36e9e7d3c6819cc66b12223412c8f7195c43847470dfb477a55d7867cc','29fc1f36e9e7d3c6819cc66b12223412c8f7195c43847470dfb477a55d7867cc','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261007073708_product_illustrative_photos.sql; SHA256 036f28d67676d00ed69c57e53980dc5c26354981432403a63f3327eda029059f
-- Real illustrative photos are explicitly distinguished from reference-specific photos.
-- Existing images and publication/access rules are preserved.
alter table public.products add column photo_is_illustrative boolean not null default false;
comment on column public.products.photo_is_illustrative is 'True for a representative photograph that does not guarantee brand, model, color, dosage, dimensions or packaging.';
create function private.clear_replaced_illustrative_photo() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.photo_data is distinct from old.photo_data
    and (old.photo_is_illustrative or coalesce(new.photo_data,'')='') then
  new.photo_is_illustrative:=false;
 end if;
 return new;
end $$;
revoke all on function private.clear_replaced_illustrative_photo() from public,anon,authenticated;
create trigger clear_replaced_illustrative_photo before update of photo_data on public.products
for each row execute function private.clear_replaced_illustrative_photo();

CREATE OR REPLACE FUNCTION storefront_api.gama_storefront(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb;curr text;term text;cat text;brand_filter text;sortby text;off integer;lim integer;count_items integer;rows jsonb;req uuid;prior private.website_public_inquiries;payload jsonb;visitor text;secret text;
 line jsonb;prod public.products;pid uuid;qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';rid uuid;seq bigint;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if not coalesce((cfg->>'site_enabled')::boolean,false) then
  if p_action='bootstrap' then return jsonb_build_object('paused',true,'settings',jsonb_build_object('brand_name',cfg->>'brand_name','phone',cfg->>'phone','email',cfg->>'email'));end if;
  raise exception 'WEBSITE_PUBLIC_PAUSED';
 end if;
 if p_action='bootstrap' then
  return jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from private.gama_storefront_items()),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) filter (where has_photo) photo_id from private.gama_storefront_items() group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from private.gama_storefront_items() where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from private.gama_storefront_items() where featured order by name,id limit 8) z),'[]'));
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  select count(*) into count_items from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter);
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from(select * from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
   order by case when sortby='featured' then featured end desc nulls last,case when sortby='price_asc' then unit_price end asc nulls last,case when sortby='price_desc' then unit_price end desc nulls last,name,id limit lim offset off) z;
  return jsonb_build_object('items',rows,'total',count_items,'offset',off,'limit',lim,'currency',curr);
 elsif p_action='product' then
  select to_jsonb(i) into rows from private.gama_storefront_items() i where id=(p_data->>'id')::uuid;
  if rows is null then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;return jsonb_build_object('item',rows,'currency',curr);
 elsif p_action='photos' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data,'photo_is_illustrative',p.photo_is_illustrative)) from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'),'[]');
 elsif p_action='submit' then
  if not (cfg->>'enable_quotes')::boolean then raise exception 'WEBSITE_QUOTES_DISABLED';end if;
  select token into secret from private.website_public_connection where id;
  if coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
  if coalesce(p_data->>'website','')<>'' then raise exception 'WEBSITE_INVALID_DATA';end if;
  visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'WEBSITE_VISITOR_REQUIRED';end if;visitor:=md5(secret||visitor);
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||req,0));payload:=p_data-'request_key'-'visitor'-'website';select * into prior from private.website_public_inquiries where request_key=req;
  if found then if prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;return jsonb_build_object('reference','WEB-'||lpad(prior.number::text,8,'0'));end if;
  if (p_data->>'consent') is distinct from 'true' or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web-visitor:'||visitor,0));
  if (select count(*) from private.website_public_inquiries where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8 or (select count(*) from private.website_public_inquiries where email=lower(btrim(p_data->>'email')) and created_at>now()-interval '1 hour')>=5 or (select count(*) from private.website_public_inquiries where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 30 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p.* into prod from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.id=pid and p.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax,'price_to_confirm',coalesce(prod.sale_price,0)<=0));
  end loop;
  insert into private.website_public_inquiries(request_key,payload,contact_name,email,phone,company,notes,lines,currency,total,visitor_hash,consent_at)
   values(req,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total,visitor,now()) returning id,number into rid,seq;
  return jsonb_build_object('reference','WEB-'||lpad(seq::text,8,'0'));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $function$

;
CREATE OR REPLACE FUNCTION private.gama_b2b_action_before_documents(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.gama_b2b_customer();off integer:=coalesce((p_data->>'offset')::integer,0);v_id uuid:=nullif(p_data->>'id','')::uuid;
 today date:=(now() at time zone private.erp_timezone())::date;customer public.customers;invoice public.external_invoices;f public.external_invoice_files;sri public.sri_invoice_issues;adr public.customer_addresses;key uuid;receipt private.command_receipts;payload jsonb:=p_data-'request_key';cart jsonb;line jsonb;rid uuid;reference text;rows jsonb;cnt integer;result jsonb;balance numeric;overdue numeric;begin
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 select * into customer from public.customers where customers.id=cid;
 if p_action='bootstrap' then
 select coalesce(sum(d.balance),0),coalesce(sum(d.balance) filter(where coalesce(d.due_date,d.issue_date)<today),0) into balance,overdue from private.gama_customer_dues(cid) d;
 return jsonb_build_object('customer',jsonb_build_object('name',customer.name,'identification',customer.identification,'category',customer.category),'today',today,'currency',(select currency from public.company_settings where company_settings.id),
 'total',balance,'overdue',overdue,'addresses',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'label',a.label,'address',a.address,'city',a.city) order by a.label) from public.customer_addresses a where a.customer_id=cid and a.active and a.purpose in ('delivery','order')),'[]'));
 end if;
 if p_action='catalog' then
 with filtered as(select p.id,p.name,p.reference,p.category,p.description,p.has_photo,p.photo_is_illustrative,p.order_minimum,p.order_multiple,p.tax_rate
  from public.products p where p.active and p.product_kind='goods' and (p.name ilike '%'||left(coalesce(p_data->>'search',''),100)||'%' or p.reference ilike '%'||left(coalesce(p_data->>'search',''),100)||'%')),
 limited as(select * from filtered order by name,id limit 30 offset off)
 select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('unit_price',private.erp_price_calculate(cid,l.id,greatest(1,l.order_minimum),null)->'unit_price') order by name,id),'[]') into cnt,rows from limited l;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='photo' then
 if not exists(select 1 from public.products p where p.id=v_id and p.active and p.product_kind='goods') then raise exception 'PRODUCT_NOT_FOUND';end if;
 return jsonb_build_object('photo',(select ph.photo from public.product_photos ph where ph.product_id=v_id));
 end if;
 if p_action='preview' then return private.gama_b2b_cart(cid,p_data->'lines');end if;
 if p_action='favorites' then return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'lines',coalesce((select jsonb_agg(jsonb_build_object('product_id',l.product_id,'quantity',l.quantity,'name',p.name,'active',p.active) order by p.name) from public.favorite_order_lines l join public.products p on p.id=l.product_id where l.favorite_order_id=o.id),'[]')) order by o.created_at desc,o.id) from public.favorite_orders o where o.created_by=auth.uid()),'[]');end if;
 if p_action='favorite_delete' then delete from public.favorite_orders where favorite_orders.id=v_id and created_by=auth.uid();if not found then raise exception 'NOT_FOUND';end if;return jsonb_build_object('deleted',true);end if;
 if p_action in ('submit','favorite_save') then
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('b2b-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='b2b-'||p_action and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if (select count(*) from private.command_receipts where actor_id=auth.uid() and domain='b2b-'||p_action and created_at>now()-interval '1 hour')>=60 then raise exception 'B2B_RATE_LIMIT';end if;
 cart:=private.gama_b2b_cart(cid,p_data->'lines');
 if p_action='favorite_save' then
 if length(btrim(coalesce(p_data->>'name',''))) not between 1 and 80 or (select count(*) from public.favorite_orders where created_by=auth.uid())>=30 then raise exception 'B2B_FAVORITE_LIMIT';end if;
 insert into public.favorite_orders(created_by,name) values(auth.uid(),btrim(p_data->>'name')) returning favorite_orders.id into rid;
 for line in select value from jsonb_array_elements(cart->'lines') loop insert into public.favorite_order_lines(favorite_order_id,product_id,quantity) values(rid,(line->>'product_id')::uuid,(line->>'quantity')::numeric);end loop;result:=jsonb_build_object('id',rid);
 else
 if cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
 if length(coalesce(p_data->>'notes',''))>2000 or (nullif(p_data->>'requested_delivery_date','')::date is not null and nullif(p_data->>'requested_delivery_date','')::date<today) then raise exception 'INVALID_DATA';end if;
 if nullif(p_data->>'address_id','') is not null then select * into adr from public.customer_addresses where customer_addresses.id=(p_data->>'address_id')::uuid and customer_id=cid and active and purpose in ('delivery','order');if not found then raise exception 'B2B_ADDRESS_NOT_FOUND';end if;end if;
 insert into public.customer_requests(customer_id,created_by,status,requester_name,requester_email,notes,total,requested_delivery_date,delivery_address_id,delivery_address_snapshot)
 values(cid,auth.uid(),'pending',customer.name,customer.email,coalesce(p_data->>'notes',''),(cart->>'total')::numeric,nullif(p_data->>'requested_delivery_date','')::date,adr.id,case when adr.id is not null then concat_ws(', ',adr.address,adr.city) else customer.address end) returning customer_requests.id,erp_reference into rid,reference;
 for line in select value from jsonb_array_elements(cart->'lines') loop insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total) values(rid,(line->>'product_id')::uuid,(line->>'quantity')::numeric,(line->>'unit_price')::numeric,(line->>'tax_rate')::numeric,(line->>'net')::numeric);end loop;
 result:=jsonb_build_object('id',rid,'reference',reference,'total',cart->'total');
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('b2b-'||p_action,key,auth.uid(),payload,result);return result;
 end if;
 if p_action='requests' then return coalesce((select jsonb_agg(to_jsonb(z)) from(select r.erp_reference reference,r.status,r.total,r.created_at,r.requested_delivery_date,r.delivery_address_snapshot from public.customer_requests r where r.customer_id=cid order by r.created_at desc,r.id limit 30 offset off) z),'[]');end if;
 if p_action='invoices' then
 with owned as(select i.* from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected')),
 limited as(select * from owned order by issue_date desc,id limit 30 offset off)
 select (select count(*) from owned),coalesce(jsonb_agg(jsonb_build_object('id',i.id,'reference',coalesce(i.erp_reference,i.number),'fiscal_number',coalesce(i.external_number,i.number),'issue_date',i.issue_date,'due_date',i.due_date,'total',i.total,'status',case when i.document_kind='internal' then coalesce(i.external_status,i.fiscal_status) else i.fiscal_status end,
 'balance',coalesce((select sum(d.balance) from private.gama_customer_dues(cid,array[i.id]) d),0),
 'sri_id',(select s.id from public.sri_invoice_issues s where s.source_invoice_id=i.id and s.status='authorized'),
 'files',coalesce((select jsonb_agg(jsonb_build_object('id',fl.id,'mime_type',fl.mime_type)) from public.external_invoice_files fl where fl.invoice_id=i.id),'[]')) order by i.issue_date desc,i.id),'[]') into cnt,rows from limited i;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='invoice_file' then
 select x.* into f from public.external_invoice_files x join public.external_invoices i on i.id=x.invoice_id join public.sales_orders o on o.id=i.order_id where x.id=v_id and o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected');if not found then raise exception 'NOT_FOUND';end if;
 select coalesce(i.erp_reference,i.number) into reference from public.external_invoices i where i.id=f.invoice_id;
 return jsonb_build_object('content_base64',f.content_base64,'mime_type',f.mime_type,'filename',reference||case when f.mime_type='application/pdf' then '.pdf' else '.xml' end);
 end if;
 if p_action='sri_document' then
 select x.* into sri from public.sri_invoice_issues x join public.external_invoices i on i.id=x.source_invoice_id join public.sales_orders o on o.id=i.order_id where x.id=v_id and x.customer_id=cid and o.customer_id=cid and x.status='authorized' and i.fiscal_status not in ('cancelled','rejected');if not found then raise exception 'NOT_FOUND';end if;
 if p_data->>'kind' not in ('xml','ride') then raise exception 'INVALID_DATA';end if;
 select coalesce(i.erp_reference,i.number) into reference from public.external_invoices i where i.id=sri.source_invoice_id;
 return jsonb_build_object('path',case when p_data->>'kind'='xml' then sri.authorized_xml_path else sri.ride_path end,'filename',reference||case when p_data->>'kind'='xml' then '.xml' else '.pdf' end);
 end if;
 if p_action='deliveries' then
 with owned as(select d.* from public.tms_deliveries d where d.customer_id=cid and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid)),limited as(select * from owned order by delivery_date desc,id limit 30 offset off)
 select (select count(*) from owned),coalesce(jsonb_agg(jsonb_build_object('id',d.id,'reference',d.erp_reference,'date',d.delivery_date,'address',d.address,'status',d.status,'delivered_at',d.delivered_at,'has_proof',exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)) order by d.delivery_date desc,d.id),'[]') into cnt,rows from limited d;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='proof' then
 select jsonb_build_object('reference',d.erp_reference,'customer',customer.name,'address',d.address,'date',d.delivery_date,'delivered_at',d.delivered_at,'photo',p.photo,'signature',p.signature,'captured_at',p.captured_at,'latitude',p.latitude,'longitude',p.longitude,'accuracy',p.gps_accuracy_m)
 into result from public.tms_deliveries d join public.tms_proofs p on p.delivery_id=d.id where d.id=v_id and d.customer_id=cid and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid);if result is null then raise exception 'NOT_FOUND';end if;return result;
 end if;
 if p_action='statement' then
 select count(*),coalesce(sum(d.balance),0),coalesce(sum(d.balance) filter(where coalesce(d.due_date,d.issue_date)<today),0) into cnt,balance,overdue from private.gama_customer_dues(cid) d;
 if coalesce((p_data->>'export')::boolean,false) and cnt>10000 then raise exception 'B2B_STATEMENT_EXPORT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(d) order by coalesce(d.due_date,d.issue_date),d.number,d.position),'[]') into rows from(select d.number,d.issue_date,d.due_date,d.amount,d.balance,d.position from private.gama_customer_dues(cid) d order by coalesce(d.due_date,d.issue_date),d.number,d.position limit case when coalesce((p_data->>'export')::boolean,false) then 10000 else 30 end offset off) d;
 return jsonb_build_object('customer',jsonb_build_object('name',customer.name,'identification',customer.identification),'today',today,'total',balance,'overdue',overdue,'count',cnt,'rows',rows,
 'company',(select jsonb_build_object('legal_name',c.legal_name,'tax_id',c.tax_id,'address',c.address,'phone',c.phone,'email',c.email,'currency',c.currency,'country',c.country,'logo_data',c.logo_data,'website',c.website,'document_primary',c.document_primary,'document_secondary',c.document_secondary) from public.company_settings c where c.id));
 end if;raise exception 'INVALID_ACTION';
end $function$

;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261007073708','product_illustrative_photos','036f28d67676d00ed69c57e53980dc5c26354981432403a63f3327eda029059f','036f28d67676d00ed69c57e53980dc5c26354981432403a63f3327eda029059f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261007190055_b2b_product_favorites.sql; SHA256 df04125c90bb3b864fd64191c21e648058871bd34acdc956c2004f31d1febf67
-- Product favorites belong to the customer account, not the browser or email.
-- Existing named favorite selections remain unchanged.
create table private.b2b_product_favorites (
 customer_id uuid not null references public.customers(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(customer_id,product_id)
);
create index b2b_product_favorites_product on private.b2b_product_favorites(product_id);
alter table private.b2b_product_favorites enable row level security;
revoke all on private.b2b_product_favorites from public,anon,authenticated;
create policy b2b_product_favorites_no_direct_access on private.b2b_product_favorites
 for all to anon,authenticated using(false) with check(false);

create function private.gama_b2b_product_favorites(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 cid uuid:=private.gama_b2b_customer();
 pid uuid;
 off integer:=coalesce((p_data->>'offset')::integer,0);
 term text:=left(btrim(coalesce(p_data->>'search','')),100);
 wanted boolean;
 cnt integer;
 rows jsonb;
begin
 -- The resolver checks auth.uid(), MFA, verified account, current membership,
 -- active customer and the website module on EVERY read and write.
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 if p_action='ids' then
  return coalesce((select jsonb_agg(f.product_id order by f.product_id)
   from private.b2b_product_favorites f where f.customer_id=cid),'[]'::jsonb);
 end if;
 if p_action='list' then
  with filtered as (
   select p.id,p.name,p.reference,p.category,p.tax_rate,p.order_minimum,p.order_multiple,
    (p.active and p.product_kind='goods') active,
    (p.has_photo and p.active and p.product_kind='goods') has_photo,
    p.photo_is_illustrative,f.created_at
   from private.b2b_product_favorites f join public.products p on p.id=f.product_id
   where f.customer_id=cid and (term='' or p.name ilike '%'||term||'%'
    or p.reference ilike '%'||term||'%' or p.barcode ilike '%'||term||'%')
  ), limited as (select * from filtered order by created_at desc,id limit 30 offset off)
  select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
   'unit_price',case when l.active then private.erp_price_calculate(cid,l.id,
    ceil(greatest(1,l.order_minimum)/l.order_multiple)*l.order_multiple,null)->'unit_price' else null end
   ) order by l.created_at desc,l.id),'[]'::jsonb) into cnt,rows from limited l;
  return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='set' then
  pid:=nullif(p_data->>'product_id','')::uuid;
  if pid is null or jsonb_typeof(p_data->'favorite') is distinct from 'boolean' then raise exception 'INVALID_DATA';end if;
  wanted:=(p_data->>'favorite')::boolean;
  -- Serialize updates for one customer, including the bounded-list check.
  perform pg_advisory_xact_lock(hashtextextended('b2b-product-favorites:'||cid::text,0));
  if wanted then
   if not exists(select 1 from public.products p where p.id=pid and p.active and p.product_kind='goods') then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not exists(select 1 from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid)
    and (select count(*) from private.b2b_product_favorites f where f.customer_id=cid)>=500 then raise exception 'B2B_PRODUCT_FAVORITE_LIMIT';end if;
   insert into private.b2b_product_favorites(customer_id,product_id) values(cid,pid) on conflict do nothing;
  else
   -- Unavailable products can still be removed. Retrying either state is safe.
   delete from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid;
  end if;
  return jsonb_build_object('product_id',pid,'favorite',wanted);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create function public.gama_b2b_product_favorites(p_action text,p_data jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_b2b_product_favorites(p_action,p_data)
$$;
revoke all on function private.gama_b2b_product_favorites(text,jsonb),public.gama_b2b_product_favorites(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_product_favorites(text,jsonb),public.gama_b2b_product_favorites(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261007190055','b2b_product_favorites','df04125c90bb3b864fd64191c21e648058871bd34acdc956c2004f31d1febf67','df04125c90bb3b864fd64191c21e648058871bd34acdc956c2004f31d1febf67','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261007194241_b2b_unified_storefront.sql; SHA256 e9ef9c5b488de5d1d2c98d84ae3803647057e59d29721b1404d43cfc86138ccd
-- Reuse the public product projection, with prices derived from the verified customer.
-- No customer identifier, price or permission claim is accepted from the browser.
begin;
create function private.gama_b2b_storefront_price(cid uuid,item jsonb) returns jsonb
language sql stable set search_path='' as $$
 select item || jsonb_build_object(
  'unit_price',private.erp_price_calculate(cid,p.id,
   case when coalesce(p.order_multiple,0)>0 then ceil(greatest(1,coalesce(p.order_minimum,0))/p.order_multiple)*p.order_multiple
        else greatest(1,coalesce(p.order_minimum,0)) end,null)->'unit_price',
  'tax_rate',p.tax_rate,'orderable',p.product_kind='goods')
 from public.products p where p.id=(item->>'id')::uuid and p.active
$$;
revoke all on function private.gama_b2b_storefront_price(uuid,jsonb) from public,anon,authenticated;

create function private.gama_b2b_storefront(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid;cfg jsonb;result jsonb;rows jsonb;sortby text;term text;cat text;brand_filter text;off integer;lim integer;cnt integer;
begin
 if auth.uid() is null then raise exception 'B2B_ACCESS_REQUIRED';end if;
 cid:=private.gama_b2b_customer();
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 if not coalesce((cfg->>'site_enabled')::boolean,false) then raise exception 'WEBSITE_PUBLIC_PAUSED';end if;
 if p_action='bootstrap' then
  result:=storefront_api.gama_storefront('bootstrap','{}');
  select coalesce(jsonb_agg(private.gama_b2b_storefront_price(cid,item) order by n),'[]') into rows from jsonb_array_elements(result->'featured') with ordinality f(item,n);
  return jsonb_set(result,'{featured}',rows);
 elsif p_action='product' then
  result:=storefront_api.gama_storefront('product',p_data);
  return jsonb_set(result,'{item}',private.gama_b2b_storefront_price(cid,result->'item'));
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  with filtered as materialized (
   select * from private.gama_storefront_items() i
   where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0)
    and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
  ), candidates as (
   select * from filtered order by case when sortby='featured' then featured end desc nulls last,name,id
   limit case when sortby in ('price_asc','price_desc') then null else lim end
   offset case when sortby in ('price_asc','price_desc') then 0 else off end
  ), priced as materialized (
   select private.gama_b2b_storefront_price(cid,to_jsonb(i)) item from candidates i
  ), ranked as (
   select item,
    (item->>'unit_price')::numeric * case when cfg->>'price_display'='without_tax' then 1 else 1+coalesce((item->>'tax_rate')::numeric,0)/100 end amount
   from priced
  ), selected as (
   select item from ranked order by
    case when sortby='price_asc' then amount end asc nulls last,
    case when sortby='price_desc' then amount end desc nulls last,
    case when sortby='featured' then (item->>'featured')::boolean end desc nulls last,item->>'name',item->>'id'
   limit lim offset case when sortby in ('price_asc','price_desc') then off else 0 end
  ) select (select count(*) from filtered),coalesce(jsonb_agg(item),'[]') into cnt,rows from selected;
  return jsonb_build_object('items',rows,'total',cnt,'offset',off,'limit',lim,'currency',(select currency from public.company_settings where id));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_b2b_storefront(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_storefront(text,jsonb) to authenticated;
create function public.gama_b2b_storefront(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.gama_b2b_storefront(p_action,p_data) $$;
revoke all on function public.gama_b2b_storefront(text,jsonb) from public,anon;
grant execute on function public.gama_b2b_storefront(text,jsonb) to authenticated;
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261007194241','b2b_unified_storefront','e9ef9c5b488de5d1d2c98d84ae3803647057e59d29721b1404d43cfc86138ccd','e9ef9c5b488de5d1d2c98d84ae3803647057e59d29721b1404d43cfc86138ccd','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261008131512_performance_notification_badge.sql; SHA256 b9eee5f77cae504a2b1bcba9832bfb2bbd986f772d694583c3016f30dcae5355
-- The bell needs only the authorized active count, not dashboard KPIs or 50 dossiers.
-- Keep the existing authentication, MFA, module and role gates in the wrapper.
do $migration$
declare src text;anchor text:=$anchor$ if p_action='history' then$anchor$;
begin
 select pg_get_functiondef('private.gama_operations_action(text,jsonb)'::regprocedure) into src;
 if position($guard$'badge'$guard$ in src)>0 then return;end if;
 if position(anchor in src)=0 then raise exception 'NOTIFICATION_BADGE_ANCHOR';end if;
 src:=replace(src,anchor,$patch$ if p_action='badge' then
  return (
   select jsonb_build_object('active_count',count(*),'generated_at',now())
   from private.gama_live_alerts l
   left join private.gama_alert_handling h on h.alert_key=l.alert_key
    and h.fingerprint=md5(l.kind||coalesce(l.detail,'')||coalesce(l.since::text,''))
   where (not l.finance_only or fin) and (not l.warehouse_only or wh)
    and (case when h.status='snoozed' and h.snoozed_until<=now() then 'open' else coalesce(h.status,'open') end)<>'snoozed'
    and (not coalesce((p_data->>'respect_preferences')::boolean,false) or (
     not exists(select 1 from public.erp_notification_preferences pref where pref.user_id=auth.uid()
      and (l.kind=any(pref.hidden_kinds) or (pref.only_mine and h.assigned_to is distinct from auth.uid())))
     and (coalesce(p_data->>'notification_class','all')='all'
      or (p_data->>'notification_class'='action' and l.priority>=2)
      or (p_data->>'notification_class'='information' and l.priority<2)))));
 elsif p_action='history' then$patch$);
 execute src;
end $migration$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261008131512','performance_notification_badge','b9eee5f77cae504a2b1bcba9832bfb2bbd986f772d694583c3016f30dcae5355','b9eee5f77cae504a2b1bcba9832bfb2bbd986f772d694583c3016f30dcae5355','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261009164509_agent_coco_gateway.sql; SHA256 cfed40755daef306cdd565e06f998bab51b83f479c469f80b684c3f746e3cc6b
-- Agent Coco: additive schema. No stock fixture, user account or business mutation.
-- Generate the versioned migration with `supabase migration new agent_coco_gateway`.
create table if not exists private.coco_agent_access (
 actor_id uuid primary key references public.profiles(id),
 enabled boolean not null default false, can_write boolean not null default false,
 client_ids text[] not null default '{}', write_client_ids text[] not null default '{}',
 check(write_client_ids <@ client_ids), revision bigint not null default 1,
 updated_at timestamptz not null default now()
);
create table if not exists private.coco_agent_commands (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 client_id text, request_key uuid not null, payload jsonb not null, snapshot jsonb not null,
 digest text not null, access_revision bigint not null,
 state text not null default 'prepared' check(state in ('prepared','submitted','failed')),
 result jsonb, created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '10 minutes',
 unique(actor_id,request_key)
);
create table if not exists private.coco_agent_events (
 id bigint generated always as identity primary key, actor_id uuid not null,
 command_id uuid, client_id text, event text not null, detail jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index if not exists coco_agent_commands_actor_date on private.coco_agent_commands(actor_id,created_at desc);
create index if not exists coco_agent_events_actor_date on private.coco_agent_events(actor_id,created_at desc);
alter table private.coco_agent_access enable row level security;
alter table private.coco_agent_commands enable row level security;
alter table private.coco_agent_events enable row level security;
revoke all on private.coco_agent_access,private.coco_agent_commands,private.coco_agent_events from public,anon,authenticated;

-- A delegated OAuth token can only enter the audited gateway through PostgREST.
-- This does NOT change ordinary ERP sessions, MFA, roles or existing approval rules.
create or replace function public.coco_agent_request_guard() returns void
language plpgsql security invoker set search_path='' as $$
begin
 if nullif(auth.jwt()->>'client_id','') is not null
 and coalesce(current_setting('request.path',true),'')<>'/rpc/coco_agent' then
  raise exception 'AGENT_ENDPOINT_NOT_ALLOWED' using errcode='42501';
 end if;
end $$;
revoke all on function public.coco_agent_request_guard() from public;
grant execute on function public.coco_agent_request_guard() to anon,authenticated,service_role;

-- Fail rather than replacing an unrelated pre-request hook.
do $$ declare hook text;r record;begin
 if exists(select 1 from pg_roles where rolname='authenticator') then
  select substring(v from length('pgrst.db_pre_request=')+1) into hook
  from pg_roles cross join lateral unnest(rolconfig) v
  where rolname='authenticator' and v like 'pgrst.db_pre_request=%';
  if hook is not null and hook<>'' and hook<>'public.coco_agent_request_guard' then
   raise exception 'AGENT_EXISTING_PRE_REQUEST_HOOK_REQUIRES_REVIEW';
  end if;
  execute 'alter role authenticator set pgrst.db_pre_request=''public.coco_agent_request_guard''';
 end if;
 -- Restrictive policies prevent bypass through Realtime or Storage. The gateway
 -- uses guarded private functions; ordinary authenticated users keep their policies.
 for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p') and c.relrowsecurity and
  (n.nspname='public' or (n.nspname='storage' and c.relname='objects') or (n.nspname='realtime' and c.relname='messages')) loop
  execute format('drop policy if exists coco_agent_no_direct_oauth on %I.%I',r.nspname,r.relname);
  execute format('create policy coco_agent_no_direct_oauth on %I.%I as restrictive for all to authenticated using ((select nullif(auth.jwt()->>''client_id'','''')) is null) with check ((select nullif(auth.jwt()->>''client_id'','''')) is null)',r.nspname,r.relname);
 end loop;
end $$;

create or replace function private.coco_agent(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();cid text:=nullif(auth.jwt()->>'client_id','');cfg private.coco_agent_access;
 cmd private.coco_agent_commands;prod public.products;quant public.stock_quants;
 lines jsonb;line jsonb;payload jsonb;snap jsonb;answer jsonb;receipts jsonb:='[]';
 key uuid;lid uuid;target numeric;qty numeric;total_delta numeric;reason text;kind text;op text;
 all_stock boolean;hash text;err text;off integer;lot_id uuid;lot_qty numeric;cfg_ids text[];cfg_write_ids text[];
begin
 if uid is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_INPUT';end if;
 if p_action in ('settings','configure') then
  if cid is not null or not private.erp_module_allowed('assistant-ia',array['administrador'])
   or not private.erp_action_allowed('settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='configure' then
   if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'can_write') is distinct from 'boolean'
    or jsonb_typeof(p_data->'client_ids') is distinct from 'array' or jsonb_array_length(p_data->'client_ids')>10 then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_ids from jsonb_array_elements_text(p_data->'client_ids');
   if jsonb_typeof(coalesce(p_data->'write_client_ids','[]')) is distinct from 'array' then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_write_ids from jsonb_array_elements_text(coalesce(p_data->'write_client_ids','[]'));
   if not (cfg_write_ids <@ cfg_ids) or array_position(cfg_write_ids,null) is not null then raise exception 'INVALID_CLIENT_ID';end if;
   if exists(select 1 from unnest(cfg_ids) x where x is null or x!~'^[A-Za-z0-9_-]{3,200}$') then raise exception 'INVALID_CLIENT_ID';end if;
   insert into private.coco_agent_access(actor_id,enabled,can_write,client_ids,write_client_ids)
    values(uid,(p_data->>'enabled')::boolean,(p_data->>'can_write')::boolean,cfg_ids,cfg_write_ids)
    on conflict(actor_id) do update set enabled=excluded.enabled,can_write=excluded.can_write,
     client_ids=excluded.client_ids,write_client_ids=excluded.write_client_ids,revision=coco_agent_access.revision+1,updated_at=now();
   insert into private.coco_agent_events(actor_id,event,detail) values(uid,'access_changed',p_data);
  end if;
  select * into cfg from private.coco_agent_access where actor_id=uid;
  return jsonb_build_object('enabled',coalesce(cfg.enabled,false),'can_write',coalesce(cfg.can_write,false),
   'client_ids',coalesce(cfg.client_ids,'{}'),'write_client_ids',coalesce(cfg.write_client_ids,'{}'),'revision',cfg.revision,'actor_id',uid);
 end if;
 select * into cfg from private.coco_agent_access where actor_id=uid for share;
 if not found or not cfg.enabled then raise exception 'AGENT_ACCESS_DISABLED';end if;
 if cid is not null and not (cid=any(cfg.client_ids)) then raise exception 'AGENT_CLIENT_NOT_ALLOWED';end if;
 if p_action='search' then
  reason:=btrim(coalesce(p_data->>'query',''));
  if length(reason)<2 or length(reason)>200 then raise exception 'SEARCH_QUERY_REQUIRED';end if;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into answer from (
   select p.id,p.name,p.reference,p.base_unit,p.stock,p.lot_tracking
   from public.products p where p.active and p.product_kind='goods' and
    (strpos(lower(p.name),lower(reason))>0 or lower(p.reference)=lower(reason) or p.barcode=reason)
   order by case when lower(p.reference)=lower(reason) then 0 else 1 end,p.name,p.id limit 25) r;
  return jsonb_build_object('items',answer,'limit',25,'as_of',now());
 elsif p_action='stock' then
  select * into prod from public.products where id=(p_data->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('location_id',q.location_id,'location',l.code,'warehouse',w.name,
   'quantity',q.quantity,'reserved',q.reserved_quantity,'available',q.quantity-q.reserved_quantity) order by l.code),'[]') into answer
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id where q.product_id=prod.id;
  return jsonb_build_object('product_id',prod.id,'name',prod.name,'reference',prod.reference,'unit',prod.base_unit,
   'lot_tracking',prod.lot_tracking,'locations',answer,'as_of',now());
 elsif p_action='history' then
  off:=greatest(0,least(100000,coalesce((p_data->>'offset')::integer,0)));
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into answer from (
   select c.id,c.created_at,c.expires_at,c.state,c.payload,c.result,
    case when c.client_id is null then 'Coco ERP' else 'ChatGPT / OAuth' end as channel,
    p.full_name as actor_name
   from private.coco_agent_commands c join public.profiles p on p.id=c.actor_id where c.actor_id=uid
   order by c.created_at desc,c.id desc limit 25 offset off) r;
  return jsonb_build_object('items',answer,'offset',off);
 elsif p_action='status' then
  select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid and client_id is not distinct from cid;
  if not found then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'reference',a.erp_reference,'status',a.status,'reason',a.reason,'movement_id',a.movement_id)),'[]') into receipts
   from public.stock_adjustment_requests a where a.id in (select (x->>'id')::uuid from jsonb_array_elements(coalesce(cmd.result->'adjustments','[]')) x);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'reference',m.erp_reference,'quantity',m.quantity,'reason',m.reason,'stock_before',m.stock_before,'stock_after',m.stock_after,'user_id',m.user_id,'created_at',m.created_at)),'[]') into lines
   from public.stock_movements m where m.id in (select (x->>'movement_id')::uuid from jsonb_array_elements(receipts) x);
  return jsonb_build_object('command_id',cmd.id,'original_receipt',cmd.result,'adjustments',receipts,'movements',lines,'as_of',now(),
   'status',case when cmd.state='prepared' then case when cmd.expires_at<=now() then 'expired' else 'prepared' end
    when cmd.state='failed' then 'rejected' when exists(select 1 from jsonb_array_elements(receipts) x where x->>'status'='pending') then 'pending_approval'
    when jsonb_array_length(receipts)>0 and jsonb_array_length(lines)=jsonb_array_length(receipts) then 'executed' else 'rejected' end,
   'stock_now',(select coalesce(sum(quantity),0) from public.stock_quants where product_id=(cmd.payload->>'product_id')::uuid));
 elsif p_action not in ('prepare','execute','plan_claim') then raise exception 'INVALID_ACTION';end if;
 if not cfg.can_write or (cid is not null and not(cid=any(cfg.write_client_ids))) or not private.erp_action_allowed('warehouses','create')
  or not private.erp_action_allowed('movement','create') then raise exception 'AGENT_WRITE_NOT_ALLOWED';end if;
 if p_action='plan_claim' then
  if cid is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-agent-planning:'||uid::text,0));
  if (select count(*) from private.coco_agent_events where actor_id=uid and event='planning' and created_at>now()-interval '1 minute')>=10 then raise exception 'AGENT_RATE_LIMIT';end if;
  insert into private.coco_agent_events(actor_id,event,detail) values(uid,'planning',jsonb_build_object('request_key',key));
  return jsonb_build_object('allowed',true);
 end if;
 if p_action='prepare' then
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-agent:'||uid::text||key::text,0));
  select * into cmd from private.coco_agent_commands where actor_id=uid and request_key=key;
  if found then
   if cmd.payload<>p_data or cmd.client_id is distinct from cid then raise exception 'REQUEST_KEY_REUSED';end if;
   return to_jsonb(cmd)-'actor_id'-'client_id'-'access_revision';
  end if;
  if (select count(*) from private.coco_agent_commands where actor_id=uid and created_at>now()-interval '1 minute')>=30 then raise exception 'AGENT_RATE_LIMIT';end if;
  reason:=btrim(coalesce(p_data->>'reason',''));op:=p_data->>'operation';kind:=coalesce(p_data->>'kind','inventory_difference');
  if length(reason)<3 or length(reason)>2000 or op not in ('out','in','adjust') or op is null then raise exception 'INVALID_INPUT';end if;
  if kind not in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening') then raise exception 'INVALID_ADJUSTMENT_KIND';end if;
  if op<>'out' and kind not in ('inventory_difference','opening') then raise exception 'EXCEPTION_OUT_ONLY';end if;
  all_stock:=coalesce((p_data->>'all_stock')::boolean,false);lid:=nullif(p_data->>'location_id','')::uuid;lot_id:=nullif(p_data->>'lot_id','')::uuid;
  if all_stock and (op<>'out' or lid is not null or p_data ? 'quantity' or p_data ? 'target_quantity') then raise exception 'INVALID_INPUT';end if;
  select * into prod from public.products where id=(p_data->>'product_id')::uuid and active for share;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if prod.product_kind<>'goods' then raise exception 'STOCK_GOODS_ONLY';end if;
  if prod.lot_tracking and (all_stock or lot_id is null) then raise exception 'AGENT_EXPLICIT_LOT_REQUIRED';end if;
  if not prod.lot_tracking and lot_id is not null then raise exception 'INVALID_LOT';end if;
  if not all_stock and lid is null then raise exception 'LOCATION_REQUIRED';end if;
  if all_stock then
   select coalesce(jsonb_agg(jsonb_build_object('location_id',q.location_id,'location',l.code,'expected_quantity',q.quantity,
    'reserved',q.reserved_quantity,'target_quantity',0) order by q.location_id),'[]') into lines
   from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id
   where q.product_id=prod.id and q.quantity>0;
  else
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   qty:=(p_data->>'quantity')::numeric;
   if op in ('out','in') and (qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty<>round(qty,3)) then raise exception 'INVALID_QUANTITY';end if;
   if (op='adjust' and p_data ? 'quantity') or (op<>'adjust' and p_data ? 'target_quantity') then raise exception 'INVALID_INPUT';end if;
   target:=case op when 'out' then coalesce(quant.quantity,0)-qty when 'in' then coalesce(quant.quantity,0)+qty else (p_data->>'target_quantity')::numeric end;
   lines:=jsonb_build_array(jsonb_build_object('location_id',lid,'expected_quantity',coalesce(quant.quantity,0),'reserved',coalesce(quant.reserved_quantity,0),'target_quantity',target));
  end if;
  if jsonb_array_length(lines)=0 then raise exception 'NO_CHANGE';end if;
  if jsonb_array_length(lines)>25 then raise exception 'AGENT_TOO_MANY_LOCATIONS';end if;
  total_delta:=0;
  for line in select value from jsonb_array_elements(lines) loop
   target:=(line->>'target_quantity')::numeric;
   if target is null or target::text in ('NaN','Infinity','-Infinity') or target<0 or target>999999999 or target<>round(target,3) then raise exception 'INVALID_QUANTITY';end if;
   if target<(line->>'reserved')::numeric then raise exception 'RESERVED_EXCEEDS_QUANTITY';end if;
   if target=(line->>'expected_quantity')::numeric then raise exception 'NO_CHANGE';end if;
   perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
    where l.id=(line->>'location_id')::uuid and l.active and w.active;
   if not found then raise exception 'LOCATION_NOT_FOUND';end if;
   total_delta:=total_delta+abs(target-(line->>'expected_quantity')::numeric);
  end loop;
  -- Never split a large operation across locations to avoid an approval threshold.
  if jsonb_array_length(lines)>1 and exists(select 1 from public.erp_policies where id and
   ((stock_adjustment_limit is not null and total_delta>stock_adjustment_limit) or
    (stock_adjustment_value_limit is not null and (prod.purchase_price<=0 or total_delta*prod.purchase_price>stock_adjustment_value_limit)))) then
   raise exception 'AGENT_GROUP_APPROVAL_USE_ERP';
  end if;
  if lot_id is not null then
   perform 1 from public.product_lots where id=lot_id and product_id=prod.id;
   if not found then raise exception 'INVALID_LOT';end if;
   select coalesce(sum(quantity),0) into lot_qty from public.stock_lot_balances b where b.lot_id=(p_data->>'lot_id')::uuid and b.location_id=lid;
   if op='out' and lot_qty<qty then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  end if;
  snap:=jsonb_build_object('product_id',prod.id,'name',prod.name,'reference',prod.reference,'unit',prod.base_unit,'purchase_price',prod.purchase_price,
   'lot_tracking',prod.lot_tracking,'lot_quantity',lot_qty,'lines',lines,'quantity_changed',total_delta,
   'reason',reason,'kind',kind,'operation',op,'all_stock',all_stock,'policies',(select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r));
  hash:=encode(sha256(convert_to(jsonb_build_object('payload',p_data,'snapshot',snap,'actor',uid,'client',cid,'revision',cfg.revision)::text,'UTF8')),'hex');
  insert into private.coco_agent_commands(actor_id,client_id,request_key,payload,snapshot,digest,access_revision)
   values(uid,cid,key,p_data,snap,hash,cfg.revision) returning * into cmd;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event) values(uid,cmd.id,cid,'prepared');
  return to_jsonb(cmd)-'actor_id'-'client_id'-'access_revision';
 end if;
 select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid for update;
 if not found or cmd.client_id is distinct from cid then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb or p_data->>'digest' is distinct from cmd.digest then raise exception 'AGENT_CONFIRMATION_REQUIRED';end if;
 if cmd.state='submitted' then return cmd.result;end if;
 if cmd.state<>'prepared' then raise exception 'AGENT_COMMAND_CLOSED';end if;
 begin
  if cmd.expires_at<=now() then raise exception 'AGENT_PROPOSAL_EXPIRED';end if;
  if cfg.revision<>cmd.access_revision then raise exception 'AGENT_ACCESS_CHANGED';end if;
  select * into prod from public.products where id=(cmd.payload->>'product_id')::uuid for update;
  if not found or not prod.active or prod.product_kind<>'goods' or prod.lot_tracking is distinct from (cmd.snapshot->>'lot_tracking')::boolean
   or prod.purchase_price is distinct from (cmd.snapshot->>'purchase_price')::numeric
   or prod.name is distinct from cmd.snapshot->>'name' or prod.reference is distinct from cmd.snapshot->>'reference'
   or prod.base_unit is distinct from cmd.snapshot->>'unit' then raise exception 'AGENT_PRODUCT_CHANGED';end if;
  if cmd.snapshot->'policies' is distinct from (select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r) then raise exception 'AGENT_POLICY_CHANGED';end if;
  perform 1 from public.stock_quants where product_id=prod.id order by location_id for update;
  if (cmd.snapshot->>'all_stock')::boolean and exists(select 1 from public.stock_quants q where q.product_id=prod.id and q.quantity>0 and
   not exists(select 1 from jsonb_array_elements(cmd.snapshot->'lines') x where (x->>'location_id')::uuid=q.location_id)) then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   lid:=(line->>'location_id')::uuid;
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   if coalesce(quant.quantity,0) is distinct from (line->>'expected_quantity')::numeric or coalesce(quant.reserved_quantity,0) is distinct from (line->>'reserved')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end loop;
  if nullif(cmd.payload->>'lot_id','') is not null then
   select coalesce(sum(b.quantity),0) into lot_qty from public.stock_lot_balances b where b.lot_id=(cmd.payload->>'lot_id')::uuid and b.location_id=(cmd.payload->>'location_id')::uuid;
   if lot_qty is distinct from (cmd.snapshot->>'lot_quantity')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end if;
  -- The existing ERP API checks lots, locations, reservations, approvals and MFA.
  -- All lines and the receipt commit in one transaction, including retries.
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   payload:=jsonb_build_object('request_key',gen_random_uuid(),'product_id',prod.id,'location_id',line->'location_id',
    'expected_quantity',line->'expected_quantity','target_quantity',line->'target_quantity',
    'reason',cmd.snapshot->>'reason','kind',cmd.snapshot->>'kind');
   if nullif(cmd.payload->>'lot_id','') is not null then payload:=payload||jsonb_build_object('lot_id',cmd.payload->>'lot_id');end if;
   answer:=public.gama_adjustment_request('submit',payload);
   receipts:=receipts||jsonb_build_array(answer);
  end loop;
  answer:=jsonb_build_object('command_id',cmd.id,'status',case when exists(select 1 from jsonb_array_elements(receipts) x where x->>'status'='pending') then 'pending_approval' else 'executed' end,
   'adjustments',receipts,'stock_after',(select coalesce(sum(quantity),0) from public.stock_quants where product_id=prod.id),
   'actor_id',uid,'agent','Agent Coco','completed_at',now());
  update private.coco_agent_commands set state='submitted',result=answer where id=cmd.id;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event,detail) values(uid,cmd.id,cid,'submitted',answer);
  return answer;
 exception when others then
  get stacked diagnostics err=message_text;
  if err !~ '^[A-Z][A-Z0-9_]{2,100}$' then err:='AGENT_EXECUTION_FAILED';end if;
  answer:=jsonb_build_object('command_id',cmd.id,'status','rejected','error',err);
  update private.coco_agent_commands set state='failed',result=answer where id=cmd.id;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event,detail) values(uid,cmd.id,cid,'rejected',answer);
  return answer;
 end;
end $$;
revoke all on function private.coco_agent(text,jsonb) from public,anon;
grant execute on function private.coco_agent(text,jsonb) to authenticated;
create or replace function public.coco_agent(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_agent(p_action,p_data)$$;
revoke all on function public.coco_agent(text,jsonb) from public,anon;
grant execute on function public.coco_agent(text,jsonb) to authenticated;
notify pgrst,'reload config';
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261009164509','agent_coco_gateway','cfed40755daef306cdd565e06f998bab51b83f479c469f80b684c3f746e3cc6b','cfed40755daef306cdd565e06f998bab51b83f479c469f80b684c3f746e3cc6b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261010170822_sri_invoice_api_snapshot.sql; SHA256 45ef1237d13fec3815f8a96652d678701cfeb09dfc40336d8a762436e7136c92
-- Provider-neutral invoice preparation. No historical invoice or SRI record is rewritten.
-- Existing private helper authorization, atomic claim and public RPC remain compatible.
create or replace function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare v public.external_invoices; o public.sales_orders; c public.customers;
 cfg public.company_settings; old_issue public.sri_invoice_issues; s public.sri_settings;
 lines jsonb; seq text; result public.sri_invoice_issues; saved jsonb; item jsonb;
 qty numeric; price numeric; rate numeric; base numeric; vat numeric; net numeric:=0; taxes numeric:=0;
begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador'])
   or private.current_user_role() is distinct from 'administrador'
   or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED'; end if;
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
 if cfg.country is distinct from 'EC' or cfg.currency is distinct from 'USD' or not coalesce(cfg.configured,false) or coalesce(cfg.tax_id,'') !~ '^[0-9]{13}$'
    or s.id is null or s.ruc<>cfg.tax_id or s.estab !~ '^[0-9]{3}$' or s.pto_emi !~ '^[0-9]{3}$'
    or length(btrim(coalesce(s.razon_social,'')))=0 or length(btrim(coalesce(s.dir_matriz,'')))=0
    or s.provider_ruc is null or s.accounting_obligation is null or s.accounting_obligation not in ('SI','NO')
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE'; end if;
 -- Commercial identity and prices come exclusively from the immutable invoice.
 -- Missing historical data requires an explicit audited correction, never a live fallback.
 saved:=v.document_snapshot;
 if coalesce(saved->>'customer_identification','') !~ '^([0-9]{10}|[0-9]{13})$'
   or saved->>'customer_identification'='9999999999999'
   or nullif(btrim(saved->>'customer'),'') is null
   or nullif(btrim(saved#>>'{details,clientAddress}'),'') is null
 then raise exception 'SRI_CUSTOMER_INCOMPLETE'; end if;
 if jsonb_typeof(saved->'lines') is distinct from 'array' then raise exception 'SRI_LINES_MISSING'; end if;
 if jsonb_array_length(saved->'lines') not between 1 and 1000 then raise exception 'SRI_LINES_MISSING'; end if;
 lines:='[]'::jsonb;
 for item in select value from jsonb_array_elements(saved->'lines') loop
  if coalesce(item->>'qty','') !~ '^[0-9]+([.][0-9]{1,6})?$'
    or coalesce(item->>'price','') !~ '^[0-9]+([.][0-9]{1,6})?$'
    or coalesce(item->>'taxRate','') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or coalesce(item->>'subtotal','') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or coalesce(item->>'tax','') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or nullif(btrim(item->>'reference'),'') is null or length(item->>'reference')>25
    or nullif(btrim(item->>'name'),'') is null or length(item->>'name')>300
  then raise exception 'SRI_LINES_INVALID'; end if;
  qty:=(item->>'qty')::numeric;price:=(item->>'price')::numeric;rate:=(item->>'taxRate')::numeric;
  if qty<=0 or price<0 then raise exception 'SRI_LINES_INVALID'; end if;
  if rate not in (0,5,12,13,14,15) then raise exception 'SRI_UNSUPPORTED_TAX_RATE'; end if;
  base:=round(qty*price,2);vat:=round(base*rate/100,2);
  if base<>(item->>'subtotal')::numeric or vat<>(item->>'tax')::numeric then raise exception 'SRI_TOTAL_MISMATCH'; end if;
  net:=net+base;taxes:=taxes+vat;
  lines:=lines||jsonb_build_array(jsonb_build_object('source_line_id',item->>'line_id','product_id',item->>'product_id',
   'code',item->>'reference','description',item->>'name','quantity',qty,'unit_price',price,
   'list_price',item->'listPrice','discount_percent',item->'discount','tax_rate',rate,'subtotal',base,'tax',vat));
 end loop;
 if net is distinct from v.subtotal or taxes is distinct from v.tax or net+taxes is distinct from v.total then raise exception 'SRI_TOTAL_MISMATCH'; end if;
 -- The legal 9-digit sequence is independent of Coco's internal FAC number.
 seq:=lpad(nextval('private.sri_invoice_sequence')::text,9,'0');
 insert into public.sri_invoice_issues(source_invoice_id,customer_id,environment,issuer_ruc,
   establishment,emission_point,sequential,created_by,snapshot)
 values(v.id,c.id,s.environment,s.ruc,s.estab,s.pto_emi,seq,auth.uid(),
  jsonb_build_object('schema_version','coco.sri.invoice.v1','currency','USD','pricing_basis','net_unit_price',
    'source_order_id',v.order_id,'source_quote_id',v.source_quote_id,'due_date',v.due_date,
    'issue_date',v.issue_date,'source_number',v.number,'issuer',s.razon_social,
    'accounting_obligation',s.accounting_obligation,'trade_name',s.trade_name,
    'establishment_address',s.establishment_address,
    'provider_ruc',s.provider_ruc,'payment_code',p_payment_code,
    'address',s.dir_matriz,'customer',saved->>'customer','identification',saved->>'customer_identification',
    'customer_address',saved#>>'{details,clientAddress}','customer_email',saved#>>'{details,clientEmail}','subtotal',v.subtotal,
    'tax',v.tax,'total',v.total,'lines',lines)) returning * into result;
 return jsonb_build_object('id',result.id,'status',result.status);
end $$;

create function private.sri_invoice_snapshot_immutable() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if (new.source_invoice_id,new.customer_id,new.environment,new.issuer_ruc,new.establishment,new.emission_point,new.sequential,new.snapshot)
    is distinct from
    (old.source_invoice_id,old.customer_id,old.environment,old.issuer_ruc,old.establishment,old.emission_point,old.sequential,old.snapshot)
 then raise exception 'SRI_SNAPSHOT_IMMUTABLE'; end if;
 return new;
end $$;
revoke all on function private.sri_invoice_snapshot_immutable() from public,anon,authenticated;
create trigger sri_invoice_snapshot_immutable before update on public.sri_invoice_issues
for each row execute function private.sri_invoice_snapshot_immutable();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261010170822','sri_invoice_api_snapshot','45ef1237d13fec3815f8a96652d678701cfeb09dfc40336d8a762436e7136c92','45ef1237d13fec3815f8a96652d678701cfeb09dfc40336d8a762436e7136c92','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
