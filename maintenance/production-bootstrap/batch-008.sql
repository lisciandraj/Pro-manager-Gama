do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>227
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261003212647_survey_publication_groups.sql; SHA256 77b16e64a91f098dbd6f250ca2c4dfa6137c6e82968a571155a96877ab1b1ec1
-- Explicit publication diagnostics and real CRM prospects, with no mail sending.
alter table private.survey_invitations add column lead_id uuid references public.crm_leads(id) on delete set null;
create index survey_invitations_lead on private.survey_invitations(lead_id);
create or replace function private.gama_surveys(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.surveys;i private.survey_invitations;actor uuid:=auth.uid();sid uuid;target uuid;label text;items jsonb;total bigint;
 off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));lim integer:=greatest(1,least(coalesce((p_data->>'limit')::integer,30),200));term text:=left(coalesce(p_data->>'search',''),100);
begin
 if actor is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>70000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if p_action='list' then
  select count(*) into total from private.surveys where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state');
  select coalesce(jsonb_agg(x),'[]') into items from (select id,title,state,language,quiz,version,updated_at,closes_at,(select count(*) from private.survey_responses r where r.survey_id=ss.id) responses from private.surveys ss where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state') order by updated_at desc,id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='contacts' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select coalesce(jsonb_agg(x),'[]') into items from (
   select id,'customer' kind,name label from public.customers where active and name ilike '%'||term||'%'
   union all select id,'supplier',name from public.suppliers where active and name ilike '%'||term||'%'
   union all select id,'contact',btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')) from public.crm_contacts where active and private.erp_module_allowed('crm',array['administrador','comercial']) and (coalesce(first_name,'')||' '||coalesce(last_name,'')) ilike '%'||term||'%'
   order by label,id limit 30) x;return items;
 elsif p_action='save' and nullif(p_data->>'id','') is null then
  if not private.erp_action_allowed('surveys','create') then raise exception 'SURVEY_ACCESS_DENIED';end if;
  perform private.survey_validate_questions(p_data->'questions');
  insert into private.surveys(title,introduction,thanks,language,questions,quiz,pass_percent,invitation_only,closes_at,created_by,updated_by)
  values(btrim(p_data->>'title'),coalesce(p_data->>'introduction',''),coalesce(p_data->>'thanks',''),coalesce(p_data->>'language','es'),p_data->'questions',coalesce((p_data->>'quiz')::boolean,false),coalesce((p_data->>'pass_percent')::integer,70),coalesce((p_data->>'invitation_only')::boolean,false),nullif(p_data->>'closes_at','')::timestamptz,actor,actor) returning * into s;
  return to_jsonb(s);
 end if;
 sid:=(p_data->>'id')::uuid;select * into s from private.surveys where id=sid for update;
 if not found then raise exception 'SURVEY_NOT_FOUND';end if;
 if p_action='get' then return to_jsonb(s);
 elsif p_action in ('results','export') then
  if p_action='export' and not private.erp_action_allowed('surveys','export') then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select count(*) into total from private.survey_responses where survey_id=sid;
  select coalesce(jsonb_agg(x),'[]') into items from (select r.id,r.answers,r.score,r.maximum,r.created_at,
   case when private.erp_module_allowed('contacts',array['administrador','comercial']) and (inv.contact_id is null and inv.lead_id is null or private.erp_module_allowed('crm',array['administrador','comercial'])) then inv.label else null end contact_label
   from private.survey_responses r left join private.survey_invitations inv on inv.id=r.invitation_id where r.survey_id=sid order by r.created_at,r.id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='invitations' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select coalesce(jsonb_agg(x),'[]') into items from (select inv.id,inv.token,inv.label,inv.revoked,exists(select 1 from private.survey_responses r where r.invitation_id=inv.id) answered from private.survey_invitations inv where survey_id=sid and (contact_id is null and lead_id is null or private.erp_module_allowed('crm',array['administrador','comercial'])) order by created_at desc,id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',(select count(*) from private.survey_invitations where survey_id=sid and (contact_id is null and lead_id is null or private.erp_module_allowed('crm',array['administrador','comercial']))));
 elsif p_action='duplicate' then
  if not private.erp_action_allowed('surveys','create') then raise exception 'SURVEY_ACCESS_DENIED';end if;
  insert into private.surveys(title,introduction,thanks,language,questions,quiz,pass_percent,invitation_only,created_by,updated_by)
  values(left(s.title,170)||' (copy)',s.introduction,s.thanks,s.language,s.questions,s.quiz,s.pass_percent,s.invitation_only,actor,actor) returning * into s;return to_jsonb(s);
 end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if p_action='invite' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) or s.state<>'open' then raise exception 'SURVEY_ACCESS_DENIED';end if;
  target:=(p_data->>'contact_id')::uuid;
  if p_data->>'kind'='customer' then select name into label from public.customers where id=target and active;
  elsif p_data->>'kind'='supplier' then select name into label from public.suppliers where id=target and active;
  elsif p_data->>'kind'='contact' and private.erp_module_allowed('crm',array['administrador','comercial']) then select btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')) into label from public.crm_contacts where id=target and active;
  elsif p_data->>'kind'='lead' and private.erp_module_allowed('crm',array['administrador','comercial']) then select coalesce(nullif(company,''),nullif(btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')),''),email,'—') into label from public.crm_leads where id=target and active and converted_customer_id is null;
  end if;
  if label is null then raise exception 'SURVEY_INVALID_CONTACT';end if;
  select * into i from private.survey_invitations where survey_id=sid and not revoked and (case p_data->>'kind' when 'customer' then customer_id when 'supplier' then supplier_id when 'lead' then lead_id else contact_id end)=target;
  if not found then insert into private.survey_invitations(survey_id,customer_id,supplier_id,contact_id,lead_id,label,created_by) values(sid,case when p_data->>'kind'='customer' then target end,case when p_data->>'kind'='supplier' then target end,case when p_data->>'kind'='contact' then target end,case when p_data->>'kind'='lead' then target end,label,actor) returning * into i;end if;return to_jsonb(i);
 elsif p_action='revoke' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  update private.survey_invitations set revoked=true where id=(p_data->>'invitation_id')::uuid and survey_id=sid;return jsonb_build_object('ok',true);
 end if;
 if s.version is distinct from (p_data->>'version')::integer then raise exception 'SURVEY_CHANGED';end if;
 if p_action='save' then
  if s.state<>'draft' then raise exception 'SURVEY_LOCKED';end if;
  perform private.survey_validate_questions(p_data->'questions');
  update private.surveys set title=btrim(p_data->>'title'),introduction=coalesce(p_data->>'introduction',''),thanks=coalesce(p_data->>'thanks',''),language=coalesce(p_data->>'language','es'),questions=p_data->'questions',quiz=coalesce((p_data->>'quiz')::boolean,false),pass_percent=coalesce((p_data->>'pass_percent')::integer,70),invitation_only=coalesce((p_data->>'invitation_only')::boolean,false),closes_at=nullif(p_data->>'closes_at','')::timestamptz,version=version+1,updated_at=now(),updated_by=actor where id=sid returning * into s;
 elsif p_action='state' then
  if p_data->>'state'='open' and s.state in ('draft','closed') then
   if not exists(select 1 from jsonb_array_elements(s.questions) q where q->>'type'<>'section') then raise exception 'SURVEY_QUESTIONS_REQUIRED';end if;
   if s.closes_at is not null and s.closes_at<=now() then raise exception 'SURVEY_DEADLINE_EXPIRED';end if;
   if s.quiz and not exists(select 1 from jsonb_array_elements(s.questions) q where jsonb_array_length(coalesce(q->'correct','[]'))>0) then raise exception 'SURVEY_QUIZ_ANSWERS_REQUIRED';end if;
  elsif not (p_data->>'state'='closed' and s.state='open' or p_data->>'state'='archived' and s.state in ('draft','closed')) then raise exception 'SURVEY_INVALID_STATE';end if;
  update private.surveys set state=p_data->>'state',version=version+1,updated_at=now(),updated_by=actor where id=sid returning * into s;
 else raise exception 'SURVEY_INVALID_ACTION';end if;
 return to_jsonb(s);
end $$;
-- Recipient selection prepares personal invitations; opening a mail composer is not delivery.
create or replace function private.gama_survey_recipients(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_items jsonb;v_total bigint;v_row jsonb;v_inv jsonb;v_out jsonb:='[]';v_seen text[]:='{}';v_email text;v_label text;v_sid uuid;
 v_off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));v_term text:=left(coalesce(p_data->>'search',''),100);v_kind text:=coalesce(p_data->>'kind','');
begin
 if auth.uid() is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_module_allowed('contacts',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>18000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if p_action='search' then
  with recipients as (
   select c.id,'customer' kind,'customer' recipient_group,c.name label,coalesce(c.email,'') email from public.customers c where c.active
   union all select s.id,'supplier','supplier',s.name,coalesce(s.email,'') from public.suppliers s where s.active
   union all select c.id,'contact',case when c.customer_id is not null then 'customer' else 'lead' end,coalesce(nullif(btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),c.email,'—'),coalesce(c.email,'') from public.crm_contacts c where c.active and (c.customer_id is not null or exists(select 1 from public.crm_leads l where l.id=c.lead_id and l.active and l.converted_customer_id is null)) and private.erp_module_allowed('crm',array['administrador','comercial'])
   union all select l.id,'lead','lead',coalesce(nullif(l.company,''),nullif(btrim(coalesce(l.first_name,'')||' '||coalesce(l.last_name,'')),''),l.email,'—'),coalesce(l.email,'') from public.crm_leads l where l.active and l.converted_customer_id is null and private.erp_module_allowed('crm',array['administrador','comercial'])
  ), filtered as (select * from recipients where (v_kind='' or recipient_group=v_kind or v_kind='contact' and kind='contact') and (label ilike '%'||v_term||'%' or email ilike '%'||v_term||'%'))
  select (select count(*) from filtered),(select coalesce(jsonb_agg(x),'[]') from (select id,kind,recipient_group as "group",label,email,email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and length(email)<=254 selectable from filtered order by label,id,kind limit 30 offset v_off) x) into v_total,v_items;
  return jsonb_build_object('items',v_items,'total',v_total);
 elsif p_action<>'prepare' then raise exception 'SURVEY_INVALID_ACTION';end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'SURVEY_ACCESS_DENIED';end if;
 v_sid:=(p_data->>'id')::uuid;
 perform 1 from private.surveys where id=v_sid and state='open' and (closes_at is null or closes_at>now()) for update;
 if not found then raise exception 'SURVEY_UNAVAILABLE';end if;
 if jsonb_typeof(p_data->'recipients') is distinct from 'array' or jsonb_array_length(p_data->'recipients') not between 1 and 50 then raise exception 'SURVEY_INVALID_DATA';end if;
 for v_row in select value from jsonb_array_elements(p_data->'recipients') loop
  v_email:=null;v_label:=null;
  if v_row->>'kind'='customer' then select name,lower(btrim(email)) into v_label,v_email from public.customers where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='supplier' then select name,lower(btrim(email)) into v_label,v_email from public.suppliers where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='contact' and private.erp_module_allowed('crm',array['administrador','comercial']) then select btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')),lower(btrim(email)) into v_label,v_email from public.crm_contacts where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='lead' and private.erp_module_allowed('crm',array['administrador','comercial']) then select coalesce(nullif(company,''),nullif(btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')),''),email,'—'),lower(btrim(email)) into v_label,v_email from public.crm_leads where id=(v_row->>'id')::uuid and active and converted_customer_id is null;
  else raise exception 'SURVEY_ACCESS_DENIED';end if;
  if v_label is null then raise exception 'SURVEY_INVALID_CONTACT';end if;
  if coalesce(v_email,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(v_email)>254 then
   v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','missing_email'));continue;
  elsif v_email=any(v_seen) then v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','duplicate_email'));continue;end if;
  v_seen:=array_append(v_seen,v_email);
  v_inv:=private.gama_surveys('invite',jsonb_build_object('id',v_sid,'kind',v_row->>'kind','contact_id',v_row->>'id'));
  if exists(select 1 from private.survey_responses where invitation_id=(v_inv->>'id')::uuid) then
   v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','answered'));continue;
  end if;
  v_out:=v_out||jsonb_build_array(jsonb_build_object('id',v_inv->>'id','label',v_label,'email',v_email,'token',v_inv->>'token','status','prepared'));
 end loop;
 return jsonb_build_object('items',v_out);
end $$;

notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003212647','survey_publication_groups','77b16e64a91f098dbd6f250ca2c4dfa6137c6e82968a571155a96877ab1b1ec1','77b16e64a91f098dbd6f250ca2c4dfa6137c6e82968a571155a96877ab1b1ec1','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003212648_process_step_history.sql; SHA256 ce7721e625bfe8c81a49cffedea4446febdc7b667ddcfc10877fffd68d35fc93
-- Scope audit metadata to one process. Raw audit payloads remain administrator-only.
create trigger process_return_audit after insert or update or delete on public.return_orders for each row execute function private.erp_audit_capture();
create trigger process_return_line_audit after insert or update or delete on public.return_lines for each row execute function private.erp_audit_capture();
create trigger process_return_credit_audit after insert or update or delete on public.return_credits for each row execute function private.erp_audit_capture();
create trigger process_request_audit after insert or update or delete on public.customer_requests for each row execute function private.erp_audit_capture();
create function private.gama_process_history(p_key text,p_step integer default 0,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare k text:=split_part(p_key,':',1);source uuid;oid uuid;qid uuid;rid uuid;poid uuid;ret public.return_orders;
 model jsonb;result jsonb;fin boolean:=false;is_return boolean:=false;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_key !~ '^(o|q|r|p|return):[0-9a-fA-F-]{36}$' or p_step not between 0 and 8 or p_offset not between 0 and 1000000 then raise exception 'INVALID_PROCESS_KEY';end if;
 source:=split_part(p_key,':',2)::uuid;is_return:=k='return';
 if is_return then
  if not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) or not coalesce((private.gama_returns_rights()->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into ret from public.return_orders where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  fin:=coalesce((private.gama_returns_rights()->>'refund')::boolean,false);
 else
  model:=private.gama_processes('state',jsonb_build_object('key',p_key));
  if k='o' then select id,source_quote_id,source_request_id into oid,qid,rid from public.sales_orders where id=source;
  elsif k='q' then qid:=source;
  elsif k='r' then rid:=source;select invoice_id into qid from public.customer_requests where id=source;
  elsif k='p' then poid:=source;end if;
  fin:=coalesce(model->'steps'->(case when k='p' then 4 else 5 end)->>'state','restricted')<>'restricted';
 end if;
 with related as (
  select 'customer_requests'::text tbl,rid::text id,1 stage,'request'::text action where rid is not null and private.erp_module_allowed('customer-requests',array['administrador','comercial'])
  union all select 'crm_opportunities',x.id::text,1,'opportunity' from public.crm_opportunities x where private.erp_module_allowed('crm',array['administrador','comercial']) and (x.id=(select source_opportunity_id from public.sales_orders where id=oid) or x.quote_invoice_id=qid)
  union all select 'purchase_orders',poid::text,2,'purchase' where poid is not null
  union all select 'purchase_order_lines',l.id::text,3,'receipt' from public.purchase_order_lines l where l.purchase_order_id=poid
  union all select 'supplier_invoices',i.id::text,5,'supplier_invoice' from public.supplier_invoices i where fin and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))
  union all select 'supplier_invoice_matches',m.id::text,5,'invoice_match' from public.supplier_invoice_matches m where m.purchase_order_id=poid and fin
  union all select 'supplier_invoice_payments',p.id::text,6,'supplier_payment' from public.supplier_invoice_payments p join public.supplier_invoices i on i.id=p.supplier_invoice_id where fin and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))
  union all select 'external_invoices',i.id::text,6,'invoice' from public.external_invoices i where i.order_id=oid and fin
  union all select 'external_invoice_payments',p.id::text,7,'payment' from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where i.order_id=oid and fin
  union all select 'dossier_followups',f.id::text,case when k='p' then 7 else 8 end,'closure' from public.dossier_followups f where f.dossier_key=p_key and fin
  union all select 'return_orders',ret.id::text,2,'return_request' where is_return
  union all select 'return_lines',l.id::text,4,'return_treatment' from public.return_lines l where is_return and ret.kind='customer' and l.return_id=ret.id
  union all select 'return_credits',c.id::text,case when ret.kind='customer' then 5 else 4 end,'credit' from public.return_credits c where is_return and fin and c.return_id=ret.id
  union all select 'return_refunds',f.id::text,5,'refund' from public.return_refunds f where is_return and fin and f.return_id=ret.id
 ), audited as (
  select 'audit:'||a.id id,a.created_at at,a.actor_id,
   case when x.tbl='return_orders' then case
    when a.after_data->>'closed_at' is distinct from a.before_data->>'closed_at' and a.after_data->>'closed_at' is not null then case when ret.kind='customer' then 6 else 5 end
    when a.after_data->>'status'='cancelled' then 2
    when a.after_data->>'received_at' is distinct from a.before_data->>'received_at' and a.after_data->>'received_at' is not null then 3
    when a.after_data->>'shipped_on' is distinct from a.before_data->>'shipped_on' and a.after_data->>'shipped_on' is not null then 3
    when a.after_data->>'financial_action' is distinct from a.before_data->>'financial_action' then case when ret.kind='customer' then 5 else 4 end
    else 2 end else x.stage end stage,
   case when x.tbl='return_orders' then case
    when a.after_data->>'closed_at' is distinct from a.before_data->>'closed_at' and a.after_data->>'closed_at' is not null then 'closure'
    when a.after_data->>'status'='cancelled' then 'cancel'
    when a.after_data->>'received_at' is distinct from a.before_data->>'received_at' and a.after_data->>'received_at' is not null then 'receipt'
    when a.after_data->>'shipped_on' is distinct from a.before_data->>'shipped_on' and a.after_data->>'shipped_on' is not null then 'dispatch'
    when a.after_data->>'financial_action' is distinct from a.before_data->>'financial_action' then 'financial_decision'
    else x.action end else x.action end action,
   coalesce(a.after_data->>'status',a.after_data->>'fiscal_status',a.after_data->>'quote_state') status,
   coalesce(a.after_data->>'erp_reference',a.after_data->>'number',a.after_data->>'order_number') reference
  from related x join public.erp_audit_events a on a.table_name=x.tbl and a.record_id=x.id
  where (a.operation='INSERT' and x.tbl not in ('purchase_orders','customer_requests','return_orders','return_credits','return_refunds','external_invoice_payments','supplier_invoice_payments')) or
   (a.operation='UPDATE' and exists(select 1 from unnest(array['status','fiscal_status','received_quantity','processed_at','closed_at','received_at','shipped_on','financial_action','approved_at','cancelled_at','external_status']) f where a.before_data->f is distinct from a.after_data->f))
 ), native as (
  select 'sale:'||e.id id,e.created_at at,e.actor_id,
   case when e.action='created' or e.action in ('confirm','cancel','update') then 3
    when e.action='quote_accepted' then 2
    when e.action like 'internal_%' or e.action like 'invoice_%' then 6
    when e.action like 'service_%' or e.action in ('dispatch','shipment','ship') or e.action='fulfillment_dispatch' then 5 else 4 end stage,
   e.action action,null::text status,null::text reference
  from public.sales_events e where e.order_id=oid and e.action<>'invoice_auto_failed' and e.action not in ('payment','payment_cancelled') and
   (private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) or e.action like 'fulfillment_%' and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista'])) and (fin or e.action not like 'internal_%' and e.action not like 'invoice_%') and (e.action<>'quote_accepted' or private.erp_module_allowed('quotes',array['administrador','comercial']))
  union all select 'quote:'||e.id,e.at,e.actor_id,2,'quote_'||e.action,null,null from public.quote_events e where e.quote_id=qid and private.erp_module_allowed('quotes',array['administrador','comercial'])
  union all select 'delivery:'||e.id,e.at,e.user_id,5,'delivery_'||e.type,null,null from public.tms_events e join public.sales_deliveries s on s.tms_delivery_id=e.delivery_id where s.order_id=oid and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista'])
  union all select 'stock:'||m.id,m.created_at,m.user_id,4,'stock',null,m.erp_reference from public.stock_movements m where m.reference_type='purchase_order' and m.reference_id=poid
  union all select 'opportunity-created:'||x.id,x.created_at,x.created_by,1,'opportunity_created',null,x.erp_reference from public.crm_opportunities x where private.erp_module_allowed('crm',array['administrador','comercial']) and (x.id=(select source_opportunity_id from public.sales_orders where id=oid) or x.quote_invoice_id=qid)
  union all select 'order-created:'||o.id,o.created_at,o.created_by,3,'created',null,o.erp_reference from public.sales_orders o where o.id=oid and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) and not exists(select 1 from public.sales_events e where e.order_id=o.id and e.action='created')
  union all select 'proof:'||p.delivery_id,p.captured_at,p.captured_by,5,'proof',null,p.erp_reference from public.tms_proofs p join public.sales_deliveries s on s.tms_delivery_id=p.delivery_id where s.order_id=oid and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista'])
  union all select 'request-created:'||r.id,r.created_at,r.created_by,1,'request_created',null,r.erp_reference from public.customer_requests r where r.id=rid and private.erp_module_allowed('customer-requests',array['administrador','comercial'])
  union all select 'purchase-created:'||p.id,p.created_at,p.created_by,1,'purchase_created',null,p.erp_reference from public.purchase_orders p where p.id=poid
  union all select 'return-created:'||ret.id,ret.created_at,ret.created_by,2,'return_created',null,ret.erp_reference where is_return
  union all select 'payment-created:'||p.id,p.created_at,p.created_by,7,'payment',null,p.erp_reference from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where i.order_id=oid and fin
  union all select 'supplier-payment-created:'||p.id,p.created_at,p.created_by,6,'supplier_payment',null,p.erp_reference from public.supplier_invoice_payments p join public.supplier_invoices i on i.id=p.supplier_invoice_id where fin and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))
  union all select 'credit-created:'||c.id,c.created_at,c.created_by,case when is_return then case when ret.kind='customer' then 5 else 4 end when poid is not null then 6 else 7 end,'credit',null,c.erp_reference from public.return_credits c where fin and (is_return and c.return_id=ret.id or exists(select 1 from public.external_invoices i where i.id=c.invoice_id and i.order_id=oid) or exists(select 1 from public.supplier_invoices i where i.id=c.supplier_invoice_id and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))))
  union all select 'refund-created:'||f.id,f.created_at,f.created_by,5,'refund',null,f.erp_reference from public.return_refunds f where is_return and fin and f.return_id=ret.id
 ), events as (
  select * from audited union all select * from native
 ), permitted as (
  select e.*,coalesce(nullif(p.full_name,''),case when e.actor_id is not null then 'USER_UNAVAILABLE' else 'AUTHOR_NOT_RECORDED' end) actor_name
  from events e left join public.profiles p on p.id=e.actor_id
  where (p_step=0 or e.stage=p_step) and e.stage between 1 and 8 and
   (is_return and (fin or e.stage<>case when ret.kind='customer' then 5 else 4 end) or not is_return and model->'steps'->(e.stage-1)->>'state' is distinct from 'restricted')
 ), numbered as (
  select *,row_number() over(partition by stage order by at desc,id desc) rn,count(*) over(partition by stage) total from permitted
 ) select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'step',stage,'at',at,'actor_name',actor_name,'action',action,'status',status,'reference',reference,'total',total) order by stage,at desc,id desc),'[]')) into result from numbered where rn>p_offset and rn<=p_offset+50;
 return result;
end $$;
revoke all on function private.gama_process_history(text,integer,integer) from public,anon;
grant execute on function private.gama_process_history(text,integer,integer) to authenticated;
create function public.gama_process_history(p_key text,p_step integer default 0,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_process_history(p_key,p_step,p_offset)$$;
revoke all on function public.gama_process_history(text,integer,integer) from public,anon;
grant execute on function public.gama_process_history(text,integer,integer) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003212648','process_step_history','ce7721e625bfe8c81a49cffedea4446febdc7b667ddcfc10877fffd68d35fc93','ce7721e625bfe8c81a49cffedea4446febdc7b667ddcfc10877fffd68d35fc93','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003213121_survey_recipient_privacy.sql; SHA256 7bb1822c2f6bd3edfb77b971b15d4e73dee75b152050b5d490c5c4528d41de2a
-- Preserve CRM visibility after the foreign key is cleared by a deleted prospect/person.
alter table private.survey_invitations add column crm_recipient boolean not null default false;
update private.survey_invitations set crm_recipient=true where contact_id is not null or lead_id is not null;
create function private.survey_recipient_privacy() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 new.crm_recipient:=new.crm_recipient or new.contact_id is not null or new.lead_id is not null;
 if tg_op='UPDATE' then new.crm_recipient:=new.crm_recipient or old.crm_recipient;end if;
 return new;
end $$;
revoke all on function private.survey_recipient_privacy() from public,anon,authenticated;
create trigger survey_recipient_privacy before insert or update on private.survey_invitations for each row execute function private.survey_recipient_privacy();
do $$declare definition text;begin
 definition:=pg_get_functiondef('private.gama_surveys(text,jsonb)'::regprocedure);
 if strpos(definition,'inv.contact_id is null and inv.lead_id is null or')=0 or strpos(definition,'contact_id is null and lead_id is null or')=0 then raise exception 'SURVEY_PRIVACY_ANCHOR_MISSING';end if;
 definition:=replace(definition,'inv.contact_id is null and inv.lead_id is null or','not inv.crm_recipient or');
 definition:=replace(definition,'contact_id is null and lead_id is null or','not crm_recipient or');
 execute definition;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003213121','survey_recipient_privacy','7bb1822c2f6bd3edfb77b971b15d4e73dee75b152050b5d490c5c4528d41de2a','7bb1822c2f6bd3edfb77b971b15d4e73dee75b152050b5d490c5c4528d41de2a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004095113_tms_order_only_auto_planning.sql; SHA256 781b74c7040154c63b8614574bd28d950c07ff80283a732fb455b45b2e63e855
-- Order creation inserts TMS before the shipment link in the same transaction.
-- Validate at commit; existing historical deliveries remain intact.
create function private.tms_order_origin() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.tms_deliveries where id=new.id)
 and not exists(select 1 from public.sales_deliveries where tms_delivery_id=new.id) then
  raise exception 'TMS_ORDER_REQUIRED';
 end if;
 return null;
end $$;
revoke all on function private.tms_order_origin() from public,anon,authenticated;
create constraint trigger tms_order_origin after insert on public.tms_deliveries
 deferrable initially deferred for each row execute function private.tms_order_origin();

create table private.tms_day_plans(day date primary key,fingerprint text not null,output_hash text not null,summary jsonb not null,planned_at timestamptz not null default now());
alter table private.tms_day_plans enable row level security;
revoke all on private.tms_day_plans from public,anon,authenticated;

create function private.tms_distance(a double precision,b double precision,c double precision,d double precision) returns double precision
language sql immutable set search_path='' as $$select 6371*2*asin(least(1.0,sqrt(power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))$$;
revoke all on function private.tms_distance(double precision,double precision,double precision,double precision) from public,anon,authenticated;

create function private.gama_tms_plan_day() returns jsonb language plpgsql security definer set search_path='' as $$
declare
 planning_day date:=(now() at time zone private.erp_timezone())::date;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 perform pg_advisory_xact_lock(193406,(planning_day-date '2000-01-01')::integer);
 -- Same row-lock order as departure: shipment, delivery, route.
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=planning_day order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.delivery_date=planning_day order by d.id for update;
 perform r.id from public.tms_routes r where r.route_date=planning_day order by r.id for update;
 select coalesce(array_agg(r.id),'{}') into locked from public.tms_routes r where
 r.status in ('En ruta','En tránsito','Terminada','Cancelada')
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
 resources:=private.gama_tms_resources();
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180);
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  w:=0;v:=0;km:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and (coalesce((dr->>'max_volume')::numeric,0)<=0 or v+d.volume<=(dr->>'max_volume')::numeric)
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);end if;
   cur_lat:=stop.lat;cur_lng:=stop.lng;w:=w+stop.weight;v:=v+stop.volume;
   stops:=stops||jsonb_build_array(stop.id);remaining:=array_remove(remaining,stop.id);
  end loop;
  if jsonb_array_length(stops)>(case when depot_ok then 1 else 0 end) then
   if depot_ok and settings.return_depot then km:=km+private.tms_distance(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng);stops:=stops||jsonb_build_array('__depot');end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status)
    values(planning_day,(dr->>'driver_id')::uuid,dr->>'name',dr->>'plate',(dr->>'vehicle_id')::uuid,stops,km,w,v,'Planificada') returning id into route_uuid;
   update public.tms_deliveries d set route_id=route_uuid,driver_id=(dr->>'driver_id')::uuid,status=case when d.status='Lista para envío' then d.status else 'Planificada' end
    where stops ? d.id::text;
   planned_count:=planned_count+jsonb_array_length(stops)-(case when depot_ok then 1 else 0 end)-(case when depot_ok and settings.return_depot then 1 else 0 end);
   route_count:=route_count+1;vehicle_ids:=array_append(vehicle_ids,(dr->>'vehicle_id')::uuid);
  end if;
 end loop;
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 summary:=jsonb_build_object('today',planning_day,'changed',true,'routes',route_count,'total',cardinality(eligible),'planned',planned_count,
  'unplanned',cardinality(eligible)-planned_count,'without_coordinates',jsonb_array_length(geocode_ids),'without_capacity',cardinality(remaining),
  'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $$;
revoke all on function private.gama_tms_plan_day() from public,anon;
grant execute on function private.gama_tms_plan_day() to authenticated;
create function public.gama_tms_plan_day() returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_plan_day()$$;
revoke all on function public.gama_tms_plan_day() from public,anon;
grant execute on function public.gama_tms_plan_day() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004095113','tms_order_only_auto_planning','781b74c7040154c63b8614574bd28d950c07ff80283a732fb455b45b2e63e855','781b74c7040154c63b8614574bd28d950c07ff80283a732fb455b45b2e63e855','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004145757_product_import_3000_rows.sql; SHA256 236af497c2bc8c4e7b04f976e7d8a21a6893b3cae801ec5cbeeb94b92792e880
-- Raise only product imports to 3000 rows. Preserve the deployed function's
-- MFA/module guards, request keys, per-row validation, audit and retry logic.
do $migration$
declare
 definition text := pg_get_functiondef('private.gama_import_batch(text,jsonb)'::regprocedure);
 old_guard text := $guard$if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 2000 then raise exception 'IMPORT_LIMIT_2000_ROWS';end if;$guard$;
 new_guard text := $guard$if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and (case when p_data->>'kind'='products' then 3000 else 2000 end) then
    if p_data->>'kind'='products' then raise exception 'IMPORT_LIMIT_3000_ROWS';
    else raise exception 'IMPORT_LIMIT_2000_ROWS';end if;
   end if;$guard$;
begin
 if position(old_guard in definition)=0 then raise exception 'IMPORT_ROW_LIMIT_GUARD_NOT_FOUND';end if;
 execute replace(definition,old_guard,new_guard);
end
$migration$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004145757','product_import_3000_rows','236af497c2bc8c4e7b04f976e7d8a21a6893b3cae801ec5cbeeb94b92792e880','236af497c2bc8c4e7b04f976e7d8a21a6893b3cae801ec5cbeeb94b92792e880','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004155043_import_product_timeout_and_indexes.sql; SHA256 d9f5fa357e56d4305665a338311c9441b0cc339e11bbd8f427fe9d7401e86c99
-- PostgREST hoists the public RPC's statement_timeout before starting its query.
-- Keep the usual role deadlines; only import preparation/application gets 60s.
alter function public.gama_import_batch(text,jsonb) set statement_timeout = '60s';

-- Match the import's case/space-insensitive identity checks, including archived
-- products. These are deliberately non-unique: ambiguous identities still fail.
create index products_import_barcode_normalized_idx on public.products (lower(btrim(barcode)));
create index products_import_reference_normalized_idx on public.products (lower(btrim(reference)));
create index products_import_name_normalized_idx on public.products (lower(btrim(name)));
analyze public.products;

-- Refresh the RPC settings cached by the REST API.
notify pgrst, 'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004155043','import_product_timeout_and_indexes','d9f5fa357e56d4305665a338311c9441b0cc339e11bbd8f427fe9d7401e86c99','d9f5fa357e56d4305665a338311c9441b0cc339e11bbd8f427fe9d7401e86c99','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004191646_stock_workspace_improvements.sql; SHA256 275b855803218f26b402336be67f745f0e779afa9491441d2424adbbcfa1e1fd
-- Stock reads on demand, accountable replenishment drafts and cycle count scheduling.
-- All commands preserve the existing stock and purchase transaction boundaries.
alter table public.inventory_counts
 add column assigned_to uuid references public.profiles(id),
 add column due_date date,
 add column priority text not null default 'normal' check(priority in ('normal','high')),
 add column scope_product_id uuid references public.products(id),
 add column repeat_of uuid references public.inventory_counts(id);
create index inventory_counts_assigned on public.inventory_counts(assigned_to) where assigned_to is not null;
create index inventory_counts_scope_product on public.inventory_counts(scope_product_id) where scope_product_id is not null;
create unique index inventory_counts_repeat on public.inventory_counts(repeat_of) where repeat_of is not null and status<>'cancelled';
create index inventory_counts_due on public.inventory_counts(due_date) where status in ('draft','in_progress');
create index stock_movements_demand on public.stock_movements(product_id,created_at desc)
 where type='out' and quantity>0 and (movement_type is null or movement_type in ('delivery','manual_out','production_out'));
create index inventory_count_lines_discrepancy on public.inventory_count_lines(product_id,count_id) where validated and variance<>0;

-- Internal aggregation is not callable by clients. No Intelligence cache permissions change.
create function private.stock_insight_rows(p_purchases boolean)
returns table(product_id uuid,data jsonb) language sql stable security invoker set search_path='' as $$
 with demand as (
  select m.product_id,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '30 days'),0) d30,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '60 days'),0) d60,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '90 days'),0) d90,
   max(m.created_at) last_out
  from public.stock_movements m where m.type='out' and m.quantity>0
   and (m.movement_type is null or m.movement_type in ('delivery','manual_out','production_out')) group by m.product_id
 ), stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved from public.stock_quants q group by q.product_id
 ), purchases as (
  select l.product_id,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status in ('sent','partial')),0) incoming,
   coalesce(sum(l.quantity) filter(where o.status='draft'),0) drafts
  from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
  where p_purchases and o.status in ('draft','sent','partial') group by l.product_id
 ), discrepancies as (
  select l.product_id,count(distinct l.count_id) repeats from public.inventory_count_lines l
   join public.inventory_counts c on c.id=l.count_id
  where c.status='validated' and l.validated and l.variance<>0 and c.completed_at>=now()-interval '180 days' group by l.product_id
 ), base as (
  select p.*,coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,
   coalesce(b.incoming,0) incoming,coalesce(b.drafts,0) drafts,
   coalesce(d.d30,0) d30,coalesce(d.d60,0) d60,coalesce(d.d90,0) d90,d.last_out,
   coalesce(d.d30,0)/30*.5+coalesce(d.d60,0)/60*.3+coalesce(d.d90,0)/90*.2 daily,
   greatest(0,current_date-coalesce(d.last_out::date,p.created_at::date)) days_without_out,
   coalesce(r.minimum,p.min_stock,0) minimum,coalesce(r.maximum,p.max_stock,0) maximum,
   coalesce(r.supplier,p.supplier_id) supplier,
   greatest(1,coalesce(r.lead,7)) lead,r.lead is not null lead_configured,
   coalesce(x.repeats,0) repeats,coalesce(s.physical,0)*coalesce(p.purchase_price,0) stock_value
  from public.products p left join stock s on s.product_id=p.id left join demand d on d.product_id=p.id
   left join purchases b on b.product_id=p.id left join discrepancies x on x.product_id=p.id
   left join lateral (
    select sum(z.min_quantity) minimum,sum(z.max_quantity) maximum,max(z.lead_time_days) lead,
     (array_agg(z.supplier_id order by z.created_at desc) filter(where z.supplier_id is not null))[1] supplier
    from public.reorder_rules z where z.product_id=p.id and z.active
     and (z.warehouse_id is null or not exists(select 1 from public.reorder_rules g where g.product_id=p.id and g.active and g.warehouse_id is null))
   ) r on true
  where p.active and p.product_kind='goods'
 ), targets as (
  select b.*,case when daily>0 then greatest(minimum,ceil(daily*lead*1.5)) else minimum end target_min,
   case when daily>0 then greatest(maximum,minimum,ceil(daily*(lead+14)+daily*lead*.5)) else greatest(maximum,minimum) end target_max,
   available+incoming+drafts net,
   sum(greatest(stock_value,0)) over() total_value,
   coalesce(sum(greatest(stock_value,0)) over(order by stock_value desc,id rows between unbounded preceding and 1 preceding),0) prior_value
  from base b
 ), proposal as (
  select t.*,case when not replenishment_excluded and net<target_min then greatest(target_max-net,coalesce(order_minimum,0)) else 0 end need
  from targets t
 )
 select p.id,jsonb_build_object(
  'id',p.id,'name',p.name,'reference',p.reference,'category',p.category,
  'on_hand',p.physical,'reserved',p.reserved,'available',p.available,
  'incoming',case when p_purchases then p.incoming end,'draft_quantity',case when p_purchases then p.drafts end,
  'projected',case when p_purchases then p.net end,
  'min_quantity',p.minimum,'max_quantity',p.maximum,'target_min',p.target_min,'target_max',p.target_max,
  'lead_time_days',p.lead,'lead_configured',p.lead_configured,
  'demand30',p.d30,'demand60',p.d60,'demand90',p.d90,'avg_daily',round(p.daily,3),
  'last_out',p.last_out,'days_without_out',p.days_without_out,
  'unit_cost',p.purchase_price,'value',p.stock_value,'excluded',p.replenishment_excluded,
  'supplier_id',case when p_purchases and s.active then s.id end,
  'supplier_name',case when p_purchases and s.active then s.name end,
  'suggested_quantity',case when p_purchases then case when p.need>0 and coalesce(p.order_multiple,0)>0 then round(ceil(p.need/p.order_multiple)*p.order_multiple,3) else round(p.need,3) end end,
  'basis',case when p.daily>0 then 'recent_demand' else 'thresholds' end,
  'repeated_discrepancies',p.repeats,
  'importance',case when p.total_value>0 and p.prior_value/p.total_value<.8 then 'A' when p.total_value>0 and p.prior_value/p.total_value<.95 then 'B' else 'C' end
 ) from proposal p left join public.suppliers s on s.id=p.supplier
$$;
revoke all on function private.stock_insight_rows(boolean) from public,anon,authenticated;

create function private.gama_stock_insights(p_view text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare can_buy boolean;can_count boolean;rows jsonb;late jsonb:='[]';adjustments jsonb:='[]';counts jsonb:='[]';people jsonb:='[]';begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_view not in ('acciones','rotacion','reabastecimiento','conteos') then raise exception 'INVALID_VIEW';end if;
 can_buy:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
 can_count:=private.erp_module_allowed('warehouses',array['administrador','almacenero']);
 select coalesce(jsonb_agg(case when can_count then x.data else x.data-'repeated_discrepancies' end order by x.data->>'name'),'[]') into rows from private.stock_insight_rows(can_buy) x;
 if p_view='acciones' and can_buy then
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'supplier',s.name,'expected_date',o.expected_date,'days_late',current_date-o.expected_date::date) order by o.expected_date),'[]') into late
   from public.purchase_orders o join public.suppliers s on s.id=o.supplier_id
   where o.status in ('sent','partial') and o.expected_date::date<current_date
    and exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id and l.quantity>l.received_quantity);
 end if;
 if p_view='acciones' and can_count then
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'product_id',r.product_id,'reason',r.reason,'requested_at',r.requested_at) order by r.requested_at desc,r.id desc),'[]') into adjustments from public.stock_adjustment_requests r where r.status='pending';
 end if;
 if p_view in ('acciones','conteos') and can_count then
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('assigned_name',p.full_name,'repeat_started',exists(select 1 from public.inventory_counts n where n.repeat_of=c.id and n.status<>'cancelled')) order by case when c.priority='high' then 0 else 1 end,coalesce(c.due_date,c.next_due),c.created_at desc),'[]') into counts
   from public.inventory_counts c left join public.profiles p on p.id=c.assigned_to
   where c.status in ('draft','in_progress') or (c.status='validated' and c.next_due is not null);
  if p_view='conteos' then select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name),'[]') into people from public.profiles p where p.active and p.role in ('administrador','almacenero');end if;
 end if;
 return jsonb_build_object('as_of',now(),'today',current_date,'can_buy',can_buy,'can_count',can_count,'rows',rows,'late_orders',late,'adjustments',adjustments,'counts',counts,'people',people);
end $$;
create function public.gama_stock_insights(p_view text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_stock_insights(p_view)$$;
revoke all on function private.gama_stock_insights(text),public.gama_stock_insights(text) from public,anon;
grant execute on function private.gama_stock_insights(text),public.gama_stock_insights(text) to authenticated;

-- One transaction for all suppliers; stable receipt makes a network retry safe.
create function private.gama_stock_replenish(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;
 payload jsonb:=p_data-'request_key';selected jsonb:=p_data->'items';fresh jsonb;item jsonb;grouped record;result jsonb;orders jsonb:='[]';po jsonb;begin
 if actor is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial']) or not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-replenish:'||key::text,0));
 select * into receipt from private.command_receipts where domain='stock-replenish' and request_key=key;
 if found then if receipt.actor_id<>actor or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if jsonb_typeof(selected) is distinct from 'array' or jsonb_array_length(selected) not between 1 and 3000 then raise exception 'INVALID_LINES';end if;
 if (select count(distinct v->>'product_id') from jsonb_array_elements(selected) v)<>jsonb_array_length(selected) then raise exception 'DUPLICATE_PRODUCT';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 select coalesce(jsonb_agg(x.data),'[]') into fresh from private.stock_insight_rows(true) x where x.product_id in (select (v->>'product_id')::uuid from jsonb_array_elements(selected) v);
 for item in select value from jsonb_array_elements(selected) loop
  if not exists(select 1 from jsonb_array_elements(fresh) x where x->>'id'=item->>'product_id' and nullif(x->>'supplier_id','') is not null and (x->>'suggested_quantity')::numeric>0 and (x->>'suggested_quantity')::numeric=(item->>'quantity')::numeric and x->>'supplier_id'=item->>'supplier_id') then raise exception 'REPLENISHMENT_CHANGED';end if;
 end loop;
 for grouped in select x->>'supplier_id' supplier,max((x->>'lead_time_days')::integer) lead,
  jsonb_agg(jsonb_build_object('product_id',p.id,'quantity',(x->>'suggested_quantity')::numeric,'unit_cost',round(coalesce(p.purchase_price,0),2),'tax_rate',p.tax_rate) order by p.id) lines
  from jsonb_array_elements(fresh) x join public.products p on p.id=(x->>'id')::uuid group by x->>'supplier_id' order by x->>'supplier_id'
 loop
  if jsonb_array_length(grouped.lines)>500 then raise exception 'SUPPLIER_LINE_LIMIT_500';end if;
  po:=private.gama_purchase_save(jsonb_build_object('request_key',gen_random_uuid(),'supplier_id',grouped.supplier,'destination_location_id',p_data->>'destination_location_id','expected_date',current_date+grouped.lead,'source_kind','low_stock','notes','Reposición desde Stock: salidas recientes, plazo de suministro y mínimos configurados. Revisar antes de enviar.','lines',grouped.lines));
  orders:=orders||jsonb_build_array(jsonb_build_object('id',po->>'id','number',po->>'order_number','supplier_id',grouped.supplier,'lines',jsonb_array_length(grouped.lines)));
 end loop;
 result:=jsonb_build_object('orders',orders,'products',jsonb_array_length(selected));
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('stock-replenish',key,actor,payload,result);
 return result;
end $$;
create function public.gama_stock_replenish(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_stock_replenish(p_data)$$;
revoke all on function private.gama_stock_replenish(jsonb),public.gama_stock_replenish(jsonb) from public,anon;
grant execute on function private.gama_stock_replenish(jsonb),public.gama_stock_replenish(jsonb) to authenticated;

-- Extend the existing idempotent count command. Quantities still change only on validation.
create or replace function private.gama_count_create_core(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.inventory_counts;key uuid:=(p_data->>'request_key')::uuid;parent public.inventory_counts;assignee uuid:=nullif(p_data->>'assigned_to','')::uuid;repeat_id uuid:=nullif(p_data->>'repeat_of','')::uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('count:'||key::text,0));
 select * into c from public.inventory_counts where request_key=key;if found then if c.created_by<>auth.uid() then raise exception 'ROLE_NOT_ALLOWED';end if;return to_jsonb(c);end if;
 if not exists(select 1 from public.warehouses w where w.id=(p_data->>'warehouse_id')::uuid and w.active) then raise exception 'WAREHOUSE_NOT_FOUND';end if;
 if nullif(p_data->>'location_id','') is not null and not exists(select 1 from public.warehouse_locations where id=(p_data->>'location_id')::uuid and warehouse_id=(p_data->>'warehouse_id')::uuid and active) then raise exception 'LOCATION_NOT_FOUND';end if;
 if assignee is not null and not exists(select 1 from public.profiles p where p.id=assignee and p.active and p.role in ('administrador','almacenero')) then raise exception 'COUNT_ASSIGNEE_INVALID';end if;
 if repeat_id is not null then
  select * into parent from public.inventory_counts where id=repeat_id for update;
  if not found or parent.status<>'validated' or parent.next_due is null or parent.warehouse_id<>(p_data->>'warehouse_id')::uuid then raise exception 'COUNT_REPEAT_INVALID';end if;
  if exists(select 1 from public.inventory_counts n where n.repeat_of=repeat_id and n.status<>'cancelled') then raise exception 'COUNT_REPEAT_STARTED';end if;
 end if;
 insert into public.inventory_counts(warehouse_id,reference,status,created_by,started_at,blind,cycle_days,scope_location_id,scope_category,request_key,assigned_to,due_date,priority,scope_product_id,repeat_of)
 values((p_data->>'warehouse_id')::uuid,p_data->>'reference','in_progress',auth.uid(),now(),coalesce((p_data->>'blind')::boolean,true),nullif(p_data->>'cycle_days','')::integer,nullif(p_data->>'location_id','')::uuid,nullif(p_data->>'category',''),key,assignee,nullif(p_data->>'due_date','')::date,coalesce(nullif(p_data->>'priority',''),'normal'),nullif(p_data->>'product_id','')::uuid,repeat_id) returning * into c;
 insert into public.inventory_count_lines(count_id,product_id,location_id,expected_quantity)
 select c.id,q.product_id,q.location_id,q.quantity from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.products p on p.id=q.product_id
 where p.active and p.product_kind='goods' and l.active and l.warehouse_id=c.warehouse_id
  and (c.scope_location_id is null or q.location_id=c.scope_location_id) and (c.scope_category is null or p.category=c.scope_category) and (c.scope_product_id is null or p.id=c.scope_product_id);
 if not found then raise exception 'COUNT_SCOPE_EMPTY';end if;return to_jsonb(c);
end $$;
revoke all on function private.gama_count_create_core(jsonb) from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004191646','stock_workspace_improvements','275b855803218f26b402336be67f745f0e779afa9491441d2424adbbcfa1e1fd','275b855803218f26b402336be67f745f0e779afa9491441d2424adbbcfa1e1fd','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004213801_delivery_transfer_audit.sql; SHA256 69e7ff114465c66b02cdc61875ed6d211d17c151f9440f74e31565ed5adde576
-- Pista de auditoría: sólo lo que importa, dicho con palabras de negocio.
-- Movimientos de stock, cobros y pagos, facturas emitidas, validaciones y
-- cambios de acceso, leídos de sus propias tablas —que son la fuente de verdad—
-- y no del registro técnico fila a fila, que sigue existiendo para quien lo
-- necesite (erp_audit_events, gama_audit).
create or replace function private.gama_audit_trail(p_filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
 f jsonb:=coalesce(p_filters,'{}');
 f_kind text:=nullif(f->>'kind','');
 f_from timestamptz:=nullif(f->>'from','')::date;
 f_to timestamptz:=nullif(f->>'to','')::date+1;
 f_actor uuid:=nullif(f->>'actor','')::uuid;
 f_q text:=lower(nullif(btrim(coalesce(f->>'search','')),''));
 f_offset int:=greatest(coalesce(nullif(f->>'offset','')::int,0),0);
 f_limit int:=least(greatest(coalesce(nullif(f->>'limit','')::int,50),1),200);
 page jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('audit',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if f_kind is not null and f_kind not in ('stock','transfer','payment','invoice','validation','access') then raise exception 'INVALID_KIND';end if;
 with ev(kind,at,actor,action,label,detail,reference,amount,quantity,target_table,target_id) as (
  select 'stock',m.created_at,m.user_id,coalesce(nullif(m.movement_type,''),m.type),
   case m.movement_type when 'receipt' then 'Recepción de compra' when 'delivery' then 'Salida por entrega'
    when 'internal_transfer' then 'Transferencia entre ubicaciones' when 'inventory_adjustment' then 'Ajuste de inventario'
    when 'return_in' then 'Devolución recibida' when 'return_out' then 'Devolución a proveedor'
    else case when m.type='in' then 'Entrada de stock' else 'Salida de stock' end end,
   concat_ws(' · ',p.name,nullif(btrim(coalesce(m.reason,'')),''),nullif(btrim(coalesce(m.comment,'')),'')),
   m.erp_reference,null::numeric,case when m.type='in' then m.quantity else -m.quantity end,'stock_movements',m.id::text
  from public.stock_movements m left join public.products p on p.id=m.product_id
  union all
  select 'transfer',e.at,e.user_id,'delivery_'||e.type,
   case e.type when 'Creada' then 'Entrega creada' when 'Entregada' then 'Entrega completada'
    when 'SALIDA_VALIDADA' then 'Salida de entrega validada' when 'CARGA_ESCANEADA' then 'Carga de entrega escaneada'
    when 'COORDENADAS' then 'Coordenadas de entrega corregidas' when 'RUTA_AJUSTADA' then 'Ruta de entrega ajustada'
    when 'INCIDENTE' then 'Incidencia de entrega registrada' when 'REPROGRAMADA' then 'Entrega reprogramada'
    when 'ENTREGA_PARCIAL' then 'Entrega parcial y retorno' when 'COBRO' then 'Cobro en la entrega'
    when 'AVISO_PREPARADO' then 'Aviso de llegada preparado'
    else 'Entrega · '||e.type end,
   concat_ws(' · ',coalesce(nullif(e.customer,''),d.customer),nullif(e.note,'')),
   d.erp_reference,null,null,'tms_events',e.id::text
  from public.tms_events e left join public.tms_deliveries d on d.id=e.delivery_id
  union all
  select 'payment',x.created_at,x.created_by,'customer_payment','Cobro de cliente',
   concat_ws(' · ',i.number,o.customer_name,x.method),x.erp_reference,x.amount,null,'external_invoice_payments',x.id::text
  from public.external_invoice_payments x left join public.external_invoices i on i.id=x.invoice_id left join public.sales_orders o on o.id=i.order_id
  union all
  select 'payment',x.cancelled_at,x.cancelled_by,'customer_payment_cancelled','Cobro anulado',
   concat_ws(' · ',i.number,o.customer_name,x.cancellation_reason),x.erp_reference,-x.amount,null,'external_invoice_payments',x.id::text
  from public.external_invoice_payments x left join public.external_invoices i on i.id=x.invoice_id left join public.sales_orders o on o.id=i.order_id
  where x.status='cancelled' and x.cancelled_at is not null
  union all
  select 'payment',x.created_at,x.created_by,'supplier_payment',
   case when x.status='cancelled' then 'Pago a proveedor anulado' else 'Pago a proveedor' end,
   concat_ws(' · ',si.number,s.name,x.method),x.erp_reference,-x.amount,null,'supplier_invoice_payments',x.id::text
  from public.supplier_invoice_payments x left join public.supplier_invoices si on si.id=x.supplier_invoice_id left join public.suppliers s on s.id=si.supplier_id
  union all
  select 'payment',x.created_at,x.created_by,'refund','Reembolso a cliente',
   concat_ws(' · ',r.number,c.name,x.method),x.erp_reference,-x.amount,null,'return_refunds',x.id::text
  from public.return_refunds x left join public.return_orders r on r.id=x.return_id left join public.customers c on c.id=r.customer_id
  union all
  select 'invoice',i.created_at,i.created_by,'invoice_issued','Factura emitida',
   concat_ws(' · ',o.customer_name,nullif(i.external_number,'')),coalesce(i.erp_reference,i.number),i.total,null,'external_invoices',i.id::text
  from public.external_invoices i left join public.sales_orders o on o.id=i.order_id
  union all
  select 'invoice',si.created_at,si.created_by,'supplier_invoice','Factura de proveedor registrada',
   concat_ws(' · ',s.name,si.number),coalesce(si.erp_reference,si.number),si.total,null,'supplier_invoices',si.id::text
  from public.supplier_invoices si left join public.suppliers s on s.id=si.supplier_id
  union all
  select 'validation',a.reviewed_at,a.reviewed_by,'approval_'||a.status,
   case when a.status='approved' then 'Validación aprobada' else 'Validación rechazada' end,
   concat_ws(' · ',a.module,a.reason,a.decision_reason),null,null,null,'erp_approvals',a.id::text
  from public.erp_approvals a where a.reviewed_at is not null and a.status in ('approved','rejected')
  union all
  select 'validation',q.reviewed_at,q.reviewed_by,'adjustment_'||q.status,
   case when q.status='approved' then 'Ajuste de stock aprobado' else 'Ajuste de stock rechazado' end,
   concat_ws(' · ',p.name,q.reason,q.decision_reason),null,null,q.target_quantity-q.expected_quantity,'stock_adjustment_requests',q.id::text
  from public.stock_adjustment_requests q left join public.products p on p.id=q.product_id
  where q.reviewed_at is not null and q.status in ('approved','rejected')
  union all
  select 'validation',e.posted_at,e.posted_by,'entry_posted','Asiento contabilizado',
   concat_ws(' · ',e.memo,e.reference),coalesce(e.erp_reference,e.number),null,null,'accounting_entries',e.id::text
  from public.accounting_entries e where e.posted_at is not null
  union all
  select 'access',a.created_at,a.actor_id,lower(a.table_name||'_'||a.operation),
   case a.table_name when 'profiles' then case a.operation when 'INSERT' then 'Usuario creado' when 'DELETE' then 'Usuario eliminado' else 'Usuario modificado' end
    when 'role_module_access' then 'Módulos de un perfil modificados' else 'Permisos de acción modificados' end,
   concat_ws(' · ',coalesce(a.after_data->>'full_name',a.before_data->>'full_name',a.after_data->>'display_name',a.after_data->>'role',a.before_data->>'role'),
    coalesce(a.after_data->>'email',a.before_data->>'email'),a.after_data->>'module',a.reason),
   null,null,null,a.table_name,a.record_id
  from public.erp_audit_events a where a.table_name in ('profiles','role_module_access','erp_action_permissions')
 ), hits as (
  select * from ev where at is not null and (f_kind is null or kind=f_kind) and (f_from is null or at>=f_from)
   and (f_to is null or at<f_to) and (f_actor is null or actor=f_actor)
   and (f_q is null or strpos(lower(concat_ws(' ',label,detail,reference)),f_q)>0)
  order by at desc,target_id limit f_limit+1 offset f_offset
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'at',h.at,'actor_id',h.actor,'actor',coalesce(nullif(pr.full_name,''),pr.email),
   'action',h.action,'label',h.label,'detail',nullif(h.detail,''),'reference',h.reference,'amount',h.amount,'quantity',h.quantity,
   'target_table',h.target_table,'target_id',h.target_id) order by h.at desc,h.target_id),'[]')
  into page from hits h left join public.profiles pr on pr.id=h.actor;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(e order by n),'[]') from jsonb_array_elements(page) with ordinality t(e,n) where n<=f_limit),
  'has_more',jsonb_array_length(page)>f_limit,'offset',f_offset,'limit',f_limit);
end $$;
revoke all on function private.gama_audit_trail(jsonb) from public,anon;
grant execute on function private.gama_audit_trail(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004213801','delivery_transfer_audit','69e7ff114465c66b02cdc61875ed6d211d17c151f9440f74e31565ed5adde576','69e7ff114465c66b02cdc61875ed6d211d17c151f9440f74e31565ed5adde576','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004213802_tms_today_driver_routes_gps.sql; SHA256 74753189efa991e21eaad0ce4e4b5cb802606086c99324d950e2640efb7692da
-- Saved GPS belongs to an address, never to an unrelated one-off destination.
alter table public.customers add column lat double precision, add column lng double precision, add column gps_address text;
alter table public.customers add constraint customer_gps_pair check
 ((lat is null and lng is null) or (lat is not null and lng is not null and lat between -85 and 85 and lng between -180 and 180));
create function private.customer_gps_address() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and new.address is distinct from old.address and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then
  new.lat:=null;new.lng:=null;
 end if;
 new.gps_address:=case when new.lat is not null then new.address end;
 return new;
end $$;
revoke all on function private.customer_gps_address() from public,anon,authenticated;
create trigger customer_gps_address before insert or update of address,lat,lng on public.customers for each row execute function private.customer_gps_address();

create function private.tms_customer_gps() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.customers;
begin
 if tg_op='UPDATE' and new.address is distinct from old.address and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then new.lat:=null;new.lng:=null;end if;
 if new.customer_id is not null and new.lat is null and new.lng is null then
  select * into c from public.customers where id=new.customer_id;
  if c.lat is not null and lower(btrim(new.address))=lower(btrim(c.gps_address)) then new.lat:=c.lat;new.lng:=c.lng;end if;
 end if;
 return new;
end $$;
revoke all on function private.tms_customer_gps() from public,anon,authenticated;
create trigger tms_customer_gps before insert or update of customer_id,address on public.tms_deliveries for each row execute function private.tms_customer_gps();

create function private.gama_tms_save_gps(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;a double precision:=(p_data->>'lat')::double precision;b double precision:=(p_data->>'lng')::double precision;saved boolean:=false;
begin
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
end $$;
revoke all on function private.gama_tms_save_gps(jsonb) from public,anon;
grant execute on function private.gama_tms_save_gps(jsonb) to authenticated;
create function public.gama_tms_save_gps(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_save_gps(p_data)$$;
revoke all on function public.gama_tms_save_gps(jsonb) from public,anon;
grant execute on function public.gama_tms_save_gps(jsonb) to authenticated;

alter table public.tms_routes add column manual_override boolean not null default false,add column version integer not null default 1;
create function private.tms_route_version() returns trigger language plpgsql set search_path='' as $$begin new.version:=old.version+1;return new;end $$;
revoke all on function private.tms_route_version() from public,anon,authenticated;
create trigger tms_route_version before update on public.tms_routes for each row execute function private.tms_route_version();

-- Keep approved manual routes when the daily automatic proposal is refreshed.
do $patch$
declare src text;anchor text:='r.status in (''En ruta'',''En tránsito'',''Terminada'',''Cancelada'')';
begin
 src:=pg_get_functiondef('private.gama_tms_plan_day()'::regprocedure);
 if position(anchor in src)=0 then raise exception 'TMS_PLAN_LOCK_ANCHOR';end if;
 execute replace(src,anchor,'r.manual_override or '||anchor);
end $patch$;

create function private.gama_tms_move_stop(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare day date:=(now() at time zone private.erp_timezone())::date;
 d public.tms_deliveries;source public.tms_routes;target public.tms_routes;r public.tms_routes;
 dest uuid:=(p_data->>'target_route_id')::uuid;before_id text:=nullif(p_data->>'before_stop_id','');
 ids text[];source_ids text[];new_stops jsonb;sid text;pos integer;resource jsonb;
 w numeric;v numeric;km double precision;last_lat double precision;last_lng double precision;a double precision;b double precision;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
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
 select j into resource from jsonb_array_elements(private.gama_tms_resources()) j where (j->>'driver_id')::uuid=target.driver_id and (j->>'vehicle_id')::uuid=target.vehicle_id and (j->>'available')::boolean and not(j->>'absent')::boolean;
 if resource is null then raise exception 'DRIVER_REQUIRED';end if;
 ids:=array(select e from jsonb_array_elements_text(target.stops)e where e<>'__depot' and e<>d.id::text);
 if before_id is not null and not(before_id=any(ids)) then raise exception 'ROUTE_STALE';end if;
 pos:=coalesce(array_position(ids,before_id),cardinality(ids)+1);
 ids:=coalesce(ids[1:pos-1],'{}')||array[d.id::text]||coalesce(ids[pos:cardinality(ids)],'{}');
 select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where x.id::text=any(ids);
 if w>coalesce((resource->>'max_weight')::numeric,0) or (coalesce((resource->>'max_volume')::numeric,0)>0 and v>(resource->>'max_volume')::numeric) then raise exception 'ROUTE_CAPACITY';end if;
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
end $$;
revoke all on function private.gama_tms_move_stop(jsonb) from public,anon;
grant execute on function private.gama_tms_move_stop(jsonb) to authenticated;
create function public.gama_tms_move_stop(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_move_stop(p_data)$$;
revoke all on function public.gama_tms_move_stop(jsonb) from public,anon;
grant execute on function public.gama_tms_move_stop(jsonb) to authenticated;

-- A phone reads only the routes assigned to the account's active HR employee.
create function private.gama_tms_my_route() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare driver public.fleet_drivers;day date:=(now() at time zone private.erp_timezone())::date;routes jsonb;deliveries jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select f.* into driver from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.active and h.active and h.profile_id=auth.uid();
 if driver.id is null then return jsonb_build_object('driver',null,'routes','[]'::jsonb,'deliveries','[]'::jsonb);end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.route_date,r.created_at),'[]') into routes from public.tms_routes r where r.driver_id=driver.id and (r.route_date=day or r.status in ('En ruta','En tránsito')) and r.status<>'Cancelada';
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('phone',c.phone,'shipment_number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at) order by d.delivery_date,d.id),'[]') into deliveries
 from public.tms_deliveries d left join public.customers c on c.id=d.customer_id left join public.sales_deliveries s on s.tms_delivery_id=d.id
 where d.driver_id=driver.id and exists(select 1 from jsonb_array_elements(routes) r where (r->>'id')::uuid=d.route_id) and d.status<>'Cancelada' and d.delivery_date<=day;
 return jsonb_build_object('driver',jsonb_build_object('id',driver.id,'name',driver.name),'routes',routes,'deliveries',deliveries);
end $$;
revoke all on function private.gama_tms_my_route() from public,anon;
grant execute on function private.gama_tms_my_route() to authenticated;
create function public.gama_tms_my_route() returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_my_route()$$;
revoke all on function public.gama_tms_my_route() from public,anon;
grant execute on function public.gama_tms_my_route() to authenticated;

create function private.gama_tms_today_counts() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare day date:=(now() at time zone private.erp_timezone())::date;result jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select jsonb_build_object('preparation',(select count(*) from public.sales_orders o where o.status='confirmed' and exists(
   select 1 from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=o.id and p.product_kind='goods'
   and l.quantity>coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))),
  'planning',count(*) filter(where s.departed_at is null and d.route_id is null),
  'loading',count(*) filter(where s.departed_at is null and d.route_id is not null),
  'proof',count(*) filter(where s.departed_at is not null),
  'incidents',count(*) filter(where d.status='Excepción')) into result
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.status not in ('Entregada','Cancelada');
 return result;
end $$;
revoke all on function private.gama_tms_today_counts() from public,anon;
grant execute on function private.gama_tms_today_counts() to authenticated;
create function public.gama_tms_today_counts() returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_today_counts()$$;
revoke all on function public.gama_tms_today_counts() from public,anon;
grant execute on function public.gama_tms_today_counts() to authenticated;

notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004213802','tms_today_driver_routes_gps','74753189efa991e21eaad0ce4e4b5cb802606086c99324d950e2640efb7692da','74753189efa991e21eaad0ce4e4b5cb802606086c99324d950e2640efb7692da','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004213803_tms_delivery_operations.sql; SHA256 a25d42adfde8d8a809c2c884615dd2335f41b27faad51039ba76c03a1c88f730
-- Future dates reuse the same planner, capacity rules and day-specific lock.
do $patch$
declare src text;
begin
 src:=pg_get_functiondef('private.gama_tms_plan_day()'::regprocedure);
 src:=replace(src,'private.gama_tms_plan_day()','private.gama_tms_plan_day(p_day date)');
 src:=replace(src,'planning_day date:=(now() at time zone private.erp_timezone())::date;','planning_day date:=p_day;');
 if position('planning_day date:=p_day;' in src)=0 then raise exception 'TMS_DATE_ANCHOR';end if;
 src:=replace(src,'perform pg_advisory_xact_lock(193406,','if planning_day is null or planning_day<(now() at time zone private.erp_timezone())::date or planning_day>(now() at time zone private.erp_timezone())::date+365 then raise exception ''PLANNING_DATE_INVALID'';end if;'||E'\n'||' perform pg_advisory_xact_lock(193406,');
 src:=replace(src,'select coalesce(array_agg(r.id)','update public.tms_deliveries d set lat=c.lat,lng=c.lng from public.customers c where d.customer_id=c.id and d.delivery_date=planning_day and d.lat is null and d.lng is null and d.status in (''Pendiente de preparación'',''Planificada'',''Lista para envío'',''Excepción'') and c.lat is not null and lower(btrim(d.address))=lower(btrim(c.gps_address));'||E'\n'||' select coalesce(array_agg(r.id)');
 execute src;
 src:=pg_get_functiondef('private.gama_tms_today_counts()'::regprocedure);
 src:=replace(src,'private.gama_tms_today_counts()','private.gama_tms_today_counts(p_day date)');
 src:=replace(src,'day date:=(now() at time zone private.erp_timezone())::date;','day date:=p_day;');
 execute src;
 src:=pg_get_functiondef('private.gama_tms_move_stop(jsonb)'::regprocedure);
 src:=replace(src,'day date:=(now() at time zone private.erp_timezone())::date;','day date:=coalesce(nullif(p_data->>''day'','''')::date,(now() at time zone private.erp_timezone())::date);');
 src:=replace(src,'perform pg_advisory_xact_lock(193406,','if day<(now() at time zone private.erp_timezone())::date or day>(now() at time zone private.erp_timezone())::date+365 then raise exception ''PLANNING_DATE_INVALID'';end if;'||E'\n'||' perform pg_advisory_xact_lock(193406,');
 execute src;
end $patch$;
revoke all on function private.gama_tms_plan_day(date),private.gama_tms_today_counts(date) from public,anon;
grant execute on function private.gama_tms_plan_day(date),private.gama_tms_today_counts(date) to authenticated;
create function public.gama_tms_plan_day(p_day date) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_plan_day(p_day)$$;
create function public.gama_tms_today_counts(p_day date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_today_counts(p_day)$$;
revoke all on function public.gama_tms_plan_day(date),public.gama_tms_today_counts(date) from public,anon;
grant execute on function public.gama_tms_plan_day(date),public.gama_tms_today_counts(date) to authenticated;

alter table public.tms_routes add column cost_per_km numeric,add column cost_basis text;
create function private.tms_route_cost() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select c.cost_per_km into new.cost_per_km from private.gama_fleet_consumption c where c.vehicle_id=new.vehicle_id;
 new.cost_basis:='fuel_full_tank_window';return new;
end $$;
revoke all on function private.tms_route_cost() from public,anon,authenticated;
create trigger tms_route_cost before insert on public.tms_routes for each row execute function private.tms_route_cost();

alter table public.tms_deliveries add column eta_at timestamptz;
alter table public.tms_proofs add column latitude double precision,add column longitude double precision,add column gps_accuracy_m double precision,
 add column gps_recorded_at timestamptz,add column gps_status text,add column received_at timestamptz;
alter table public.tms_proofs add constraint tms_proof_gps_pair check ((latitude is null and longitude is null) or (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180));
alter table public.tms_proofs add constraint tms_proof_gps_accuracy check(gps_accuracy_m is null or gps_accuracy_m>=0);
grant select(latitude,longitude,gps_accuracy_m,gps_recorded_at,gps_status,received_at) on public.tms_proofs to authenticated;
-- Append columns to the established invoker view; no broadened document access.
create or replace view public.tms_proofs_read with(security_invoker=true) as
 select p.delivery_id,private.document_proof_photo(p.delivery_id) photo,p.signature,p.captured_at,p.captured_by,p.erp_reference,
 p.latitude,p.longitude,p.gps_accuracy_m,p.gps_recorded_at,p.gps_status,p.received_at from public.tms_proofs p;
do $patch$
declare src text;anchor text:=' result:=jsonb_build_object(''delivery_id'',d.id';
begin
 src:=pg_get_functiondef('private.gama_tms_capture(jsonb)'::regprocedure);
 if position(anchor in src)=0 then raise exception 'PROOF_GPS_ANCHOR';end if;
 src:=replace(src,anchor,$gps$
 if p_data ? 'gps' then
  if p_data->'gps'->>'status' not in ('captured','denied','unavailable','timeout') then raise exception 'GPS_INVALID';end if;
  if p_data->'gps'->>'status'='captured' and (nullif(p_data->'gps'->>'lat','')::double precision is null or nullif(p_data->'gps'->>'lng','')::double precision is null or not((p_data->'gps'->>'lat')::double precision between -90 and 90 and (p_data->'gps'->>'lng')::double precision between -180 and 180) or nullif(p_data->'gps'->>'accuracy','')::double precision is null or (p_data->'gps'->>'accuracy')::double precision<0) then raise exception 'GPS_INVALID';end if;
  update public.tms_proofs set latitude=coalesce(nullif(p_data->'gps'->>'lat','')::double precision,latitude),longitude=coalesce(nullif(p_data->'gps'->>'lng','')::double precision,longitude),gps_accuracy_m=coalesce(nullif(p_data->'gps'->>'accuracy','')::double precision,gps_accuracy_m),gps_recorded_at=coalesce(nullif(p_data->'gps'->>'at','')::timestamptz,gps_recorded_at),gps_status=p_data->'gps'->>'status',received_at=now() where delivery_id=d.id;
 end if;
 update public.tms_proofs set received_at=now() where delivery_id=d.id;
 result:=jsonb_build_object('delivery_id',d.id$gps$);
 execute src;
end $patch$;

create table public.tms_delivery_incidents(id uuid primary key default gen_random_uuid(),delivery_id uuid not null references public.tms_deliveries(id),
 driver_id uuid references public.fleet_drivers(id),reason text not null check(reason in ('absent','refused','wrong_address')),
 note text,created_at timestamptz not null default now(),created_by uuid not null default auth.uid() references public.profiles(id),rescheduled_for date);
alter table public.tms_delivery_incidents enable row level security;
revoke all on public.tms_delivery_incidents from public,anon,authenticated;
grant select on public.tms_delivery_incidents to authenticated;
create policy tms_incident_read on public.tms_delivery_incidents for select to authenticated using(private.erp_mfa_ok() and private.erp_module_allowed('tms',array['administrador','almacenero']));
create index tms_incident_delivery on public.tms_delivery_incidents(delivery_id,created_at desc);
create index tms_incident_date on public.tms_delivery_incidents(created_at desc);

create table private.tms_tracking_links(delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 token uuid not null unique default gen_random_uuid(),expires_at timestamptz not null default now()+interval '30 days');
alter table private.tms_tracking_links enable row level security;
revoke all on private.tms_tracking_links from public,anon,authenticated;
create table private.tms_rejected_packages(delivery_id uuid not null references public.tms_deliveries(id),package_id uuid not null references public.fulfillment_packages(id),return_id uuid not null references public.return_orders(id),primary key(delivery_id,package_id));
alter table private.tms_rejected_packages enable row level security;
revoke all on private.tms_rejected_packages from public,anon,authenticated;

create function private.gama_tms_delivery_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;s public.sales_deliveries;invoice public.external_invoices;payment public.external_invoice_payments;
 u uuid:=auth.uid();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;eta timestamptz;next_day date;amount numeric;paid numeric;packages uuid[];lines jsonb;return_result jsonb;
begin
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
  if d.status<>'Excepción' then raise exception 'INCIDENT_REQUIRED';end if;
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
end $$;
revoke all on function private.gama_tms_delivery_action(text,jsonb) from public,anon;
grant execute on function private.gama_tms_delivery_action(text,jsonb) to authenticated;
create function public.gama_tms_delivery_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_delivery_action(p_action,p_data)$$;
revoke all on function public.gama_tms_delivery_action(text,jsonb) from public,anon;
grant execute on function public.gama_tms_delivery_action(text,jsonb) to authenticated;

-- Token-only public tracking exposes status and ETA; no address, phone, photo, GPS or customer name.
create function private.gama_tms_tracking(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',d.eta_at,'delivered_at',d.delivered_at)
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private.gama_tms_tracking(uuid) from public,anon,authenticated;
-- The token-only facade is the sole anonymous definer; anon has no usage on private.
create function public.gama_tms_tracking(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$select private.gama_tms_tracking(p_token)$$;
revoke all on function public.gama_tms_tracking(uuid) from public;
grant execute on function public.gama_tms_tracking(uuid) to anon,authenticated;

create function private.gama_tms_metrics(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 select jsonb_build_object('delivered',count(*) filter(where d.status='Entregada'),'with_eta',count(*) filter(where d.status='Entregada' and d.eta_at is not null),
 'on_time',count(*) filter(where d.status='Entregada' and d.eta_at is not null and d.delivered_at<=d.eta_at),
 'days',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from (select r.route_date as "day",sum(coalesce(s.road_km,r.distance)) km,
  sum(coalesce(s.road_km,r.distance)*r.cost_per_km) cost,count(*) filter(where r.cost_per_km is null) missing_cost
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id where r.route_date between p_from and p_to group by r.route_date)x),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.incidents desc,x.name) from (select coalesce(f.name,'Sin conductor') name,count(*) incidents
  from public.tms_delivery_incidents i left join public.fleet_drivers f on f.id=i.driver_id where (i.created_at at time zone private.erp_timezone())::date between p_from and p_to group by f.id,f.name)x),'[]')) into result
 from public.tms_deliveries d where d.delivery_date between p_from and p_to;
 return result;
end $$;
revoke all on function private.gama_tms_metrics(date,date) from public,anon;
grant execute on function private.gama_tms_metrics(date,date) to authenticated;
create function public.gama_tms_metrics(p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_metrics(p_from,p_to)$$;
revoke all on function public.gama_tms_metrics(date,date) from public,anon;
grant execute on function public.gama_tms_metrics(date,date) to authenticated;

notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004213803','tms_delivery_operations','a25d42adfde8d8a809c2c884615dd2335f41b27faad51039ba76c03a1c88f730','a25d42adfde8d8a809c2c884615dd2335f41b27faad51039ba76c03a1c88f730','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004214058_tms_tracking_private_facade.sql; SHA256 5abb299a999d2601ab617b9dd0eb59fbd3bf6716ce0af97fa34d30ec5746abd0
-- Keep the anonymous token resolver outside the exposed public schema.
create schema private_tracking;
revoke all on schema private_tracking from public;
grant usage on schema private_tracking to anon,authenticated;
create function private_tracking.resolve(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',d.eta_at,'delivered_at',d.delivered_at)
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private_tracking.resolve(uuid) from public;
grant execute on function private_tracking.resolve(uuid) to anon,authenticated;
create or replace function public.gama_tms_tracking(p_token uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private_tracking.resolve(p_token)$$;
drop function private.gama_tms_tracking(uuid);
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004214058','tms_tracking_private_facade','5abb299a999d2601ab617b9dd0eb59fbd3bf6716ce0af97fa34d30ec5746abd0','5abb299a999d2601ab617b9dd0eb59fbd3bf6716ce0af97fa34d30ec5746abd0','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004223009_ec_fiscal_documents.sql; SHA256 b1e8a3d1667fe516803abc24659f09fd75ae9277929f0fa2639a81a13c1e9808
-- New document families have their own immutable snapshots and legal series.
-- The existing 01 workflow and every existing fiscal number remain unchanged.
create table private.sri_document_sequences (
 environment text not null, issuer_ruc text not null, establishment text not null,
 emission_point text not null, document_type text not null, last_value integer not null check(last_value between 1 and 999999999),
 primary key(environment,issuer_ruc,establishment,emission_point,document_type)
);
alter table private.sri_document_sequences enable row level security;
revoke all on private.sri_document_sequences from public,anon,authenticated;

create table public.sri_document_issues (
 id uuid primary key default gen_random_uuid(), document_type text not null check(document_type in ('03','04','06','07')),
 source_type text not null check(source_type in ('return_credit','supplier_invoice','tms_route')),source_id uuid not null,
 customer_id uuid references public.customers(id),supplier_id uuid references public.suppliers(id),route_id uuid references public.tms_routes(id),
 environment text not null check(environment in ('pruebas','produccion')),issuer_ruc text not null check(issuer_ruc ~ '^[0-9]{13}$'),
 establishment text not null check(establishment ~ '^[0-9]{3}$'),emission_point text not null check(emission_point ~ '^[0-9]{3}$'),
 sequential text not null check(sequential ~ '^[0-9]{9}$'),numeric_code text not null default lpad(floor(random()*100000000)::bigint::text,8,'0') check(numeric_code ~ '^[0-9]{8}$'),
 access_key text unique check(access_key ~ '^[0-9]{49}$'),status text not null default 'draft' check(status in ('draft','signed','received','processing','authorized','rejected','error')),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),receipt jsonb,authorization_response jsonb,
 signed_xml_path text,authorized_xml_path text,ride_path text,sent_at timestamptz,authorized_at timestamptz,delivered_at timestamptz,last_error text,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(source_type,source_id,document_type),unique(environment,issuer_ruc,establishment,emission_point,document_type,sequential),
 check((document_type='04' and source_type='return_credit' and customer_id is not null) or
       (document_type in ('03','07') and source_type='supplier_invoice' and supplier_id is not null) or
       (document_type='06' and source_type='tms_route' and route_id=source_id))
);
create index sri_document_pending on public.sri_document_issues(status,updated_at) where status in ('draft','signed','received','processing');
create index sri_document_customer on public.sri_document_issues(customer_id) where customer_id is not null;
create index sri_document_supplier on public.sri_document_issues(supplier_id) where supplier_id is not null;
create index sri_document_route on public.sri_document_issues(route_id) where route_id is not null;
create index sri_document_author on public.sri_document_issues(created_by);

create function private.gama_sri_own_route(p_route uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and private.erp_module_allowed('tms',array['administrador','almacenero']) and exists(
 select 1 from public.tms_routes r join public.fleet_drivers f on f.id=r.driver_id join public.hr_employees e on e.id=f.employee_id
 where r.id=p_route and f.active and e.active and e.profile_id=auth.uid())
$$;
revoke all on function private.gama_sri_own_route(uuid) from public,anon;
grant execute on function private.gama_sri_own_route(uuid) to authenticated;
alter table public.sri_document_issues enable row level security;
revoke all on public.sri_document_issues from public,anon,authenticated;
grant select on public.sri_document_issues to authenticated;
grant all on public.sri_document_issues to service_role;
create policy sri_document_read on public.sri_document_issues for select to authenticated using(
 private.erp_module_allowed('accounting',array['administrador']) or
 (document_type='06' and (private.gama_sri_own_route(route_id) or
 (private.current_user_role()='administrador' and private.erp_module_allowed('tms',array['administrador'])))));

create function private.gama_sri_document_access(p_id uuid,p_action text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.sri_document_issues;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into d from public.sri_document_issues where id=p_id;if not found then raise exception 'NOT_FOUND';end if;
 if private.current_user_role()='administrador' and private.erp_module_allowed('accounting',array['administrador']) then
 return jsonb_build_object('validate',private.erp_action_allowed('accounting','validate'),'export',private.erp_action_allowed('accounting','export'));
 end if;
 if d.document_type='06' and private.current_user_role()='administrador' and private.erp_module_allowed('tms',array['administrador']) then
 return jsonb_build_object('validate',private.erp_action_allowed('tms','validate'),'export',private.erp_action_allowed('tms','export'));end if;
 if p_action='download' and d.document_type='06' and d.status='authorized' and private.gama_sri_own_route(d.route_id) then
 return jsonb_build_object('validate',false,'export',true);end if;
 raise exception 'ROLE_NOT_ALLOWED';end $$;
revoke all on function private.gama_sri_document_access(uuid,text) from public,anon;
grant execute on function private.gama_sri_document_access(uuid,text) to authenticated;
create function public.gama_sri_document_access(p_id uuid,p_action text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_sri_document_access(p_id,p_action)$$;
revoke all on function public.gama_sri_document_access(uuid,text) from public,anon;
grant execute on function public.gama_sri_document_access(uuid,text) to authenticated;

-- Internal helper: a browser cannot supply an issuer, fiscal sequence, status or authorization.
create function private.gama_sri_new_document(p_type text,p_source text,p_id uuid,p_snapshot jsonb,p_customer uuid default null,p_supplier uuid default null,p_route uuid default null)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings;s public.sri_settings;d public.sri_document_issues;n integer;begin
 select * into cfg from public.company_settings where id;
 select * into s from public.sri_settings where user_id=auth.uid();
 if not coalesce(cfg.configured,false) or cfg.country<>'EC' or s.id is null or s.ruc<>cfg.tax_id or s.accounting_obligation is null
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE';end if;
 perform pg_advisory_xact_lock(hashtextextended('sri-source:'||p_source||':'||p_id||':'||p_type,0));
 select * into d from public.sri_document_issues where source_type=p_source and source_id=p_id and document_type=p_type;
 if found then return jsonb_build_object('id',d.id,'status',d.status,'document_type',d.document_type);end if;
 insert into private.sri_document_sequences(environment,issuer_ruc,establishment,emission_point,document_type,last_value)
 values(s.environment,s.ruc,s.estab,s.pto_emi,p_type,1)
 on conflict(environment,issuer_ruc,establishment,emission_point,document_type) do update set last_value=private.sri_document_sequences.last_value+1
 returning last_value into n;
 insert into public.sri_document_issues(document_type,source_type,source_id,customer_id,supplier_id,route_id,environment,issuer_ruc,establishment,emission_point,sequential,created_by,snapshot)
 values(p_type,p_source,p_id,p_customer,p_supplier,p_route,s.environment,s.ruc,s.estab,s.pto_emi,lpad(n::text,9,'0'),auth.uid(),
 p_snapshot||jsonb_build_object('issuer',s.razon_social,'address',s.dir_matriz,'provider_ruc',s.provider_ruc,
 'accounting_obligation',s.accounting_obligation,'trade_name',s.trade_name,'establishment_address',s.establishment_address)) returning * into d;
 return jsonb_build_object('id',d.id,'status',d.status,'document_type',d.document_type);
end $$;
revoke all on function private.gama_sri_new_document(text,text,uuid,jsonb,uuid,uuid,uuid) from public,anon,authenticated;


create function private.gama_sri_authorized_invoice(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.external_invoices v where v.id=p_id and v.fiscal_status<>'cancelled' and
 ((v.document_kind='external' and v.fiscal_status='authorized') or
 (v.document_kind='internal' and v.external_status='authorized' and exists(select 1 from public.sri_invoice_issues z where z.source_invoice_id=v.id and z.status='authorized' and z.access_key=v.access_key))))
$$;
revoke all on function private.gama_sri_authorized_invoice(uuid) from public,anon,authenticated;

create function private.gama_sri_credit_note(p_credit uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.return_credits;r public.return_orders;v public.external_invoices;k public.customers;f public.accounting_fiscal_documents;
 lines jsonb;net numeric;tax numeric;number text;issued date;begin
 select * into c from public.return_credits where id=p_credit for update;
 select * into r from public.return_orders where id=c.return_id;
 select * into v from public.external_invoices where id=c.invoice_id;
 select * into k from public.customers where id=r.customer_id;
 select * into f from public.accounting_fiscal_documents where source_type='sales_invoice' and source_id=v.id;
 number:=coalesce(v.external_number,case when v.document_kind='external' then v.number end,f.document_number);issued:=coalesce(v.external_issue_date,v.issue_date);
 if c.id is null or r.kind<>'customer' or r.status in ('cancelled','to_process') or not private.gama_sri_authorized_invoice(v.id)
 or number !~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$' or number is null then raise exception 'SRI_AUTHORIZED_INVOICE_REQUIRED';end if;
 if k.identification !~ '^([0-9]{10}|[0-9]{13})$' or k.identification is null then raise exception 'SRI_CUSTOMER_INCOMPLETE';end if;
 select jsonb_agg(jsonb_build_object('code',p.reference,'description',p.name,'quantity',l.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate,'subtotal',round(l.quantity*l.unit_price,2)) order by l.id),
 sum(round(l.quantity*l.unit_price,2)),sum(round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) into lines,net,tax
 from public.return_lines l join public.products p on p.id=l.product_id where l.return_id=r.id;
 if lines is null or net+tax<>c.amount then raise exception 'SRI_CREDIT_LINES_MISMATCH';end if;
 if exists(select 1 from public.return_credits where return_id=r.id and id<>c.id) then raise exception 'SRI_CREDIT_ALREADY_EXISTS';end if;
 return private.gama_sri_new_document('04','return_credit',c.id,jsonb_build_object('issue_date',c.issued_on,'source_number',coalesce(c.erp_reference,c.number),
 'customer',k.name,'identification',k.identification,'customer_address',k.address,'customer_email',k.email,
 'support_number',number,'support_date',issued,'support_authorization',v.access_key,'reason',coalesce(nullif(c.notes,''),r.reason,'Devolución de mercadería'),
 'subtotal',net,'tax',tax,'total',c.amount,'lines',lines),k.id);
end $$;
revoke all on function private.gama_sri_credit_note(uuid) from public,anon,authenticated;

create table public.supplier_withholding_policies (
 supplier_id uuid primary key references public.suppliers(id),income_code text check(income_code ~ '^[0-9]{1,5}$'),
 income_rate numeric(7,4) not null check(income_rate between 0 and 100),income_account_id uuid references public.accounting_accounts(id),
 vat_code text check(vat_code ~ '^[0-9]{1,5}$'),vat_rate numeric(7,4) not null check(vat_rate between 0 and 100),vat_account_id uuid references public.accounting_accounts(id),
 valid_from date not null,valid_to date,evidence text not null check(length(btrim(evidence))>=10),
 reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default now(),
 check(valid_to is null or valid_to>=valid_from),check(income_rate=0 or (income_code is not null and income_account_id is not null)),
 check(vat_rate=0 or (vat_code is not null and vat_account_id is not null))
);
alter table public.supplier_withholding_policies enable row level security;
revoke all on public.supplier_withholding_policies from public,anon,authenticated;
grant select on public.supplier_withholding_policies to authenticated;
create policy supplier_withholding_read on public.supplier_withholding_policies for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create table public.sri_purchase_queue (
 supplier_invoice_id uuid primary key references public.supplier_invoices(id),created_at timestamptz not null default now(),
 issue_id uuid references public.sri_document_issues(id),last_error text
);
alter table public.sri_purchase_queue enable row level security;
revoke all on public.sri_purchase_queue from public,anon,authenticated;
grant select on public.sri_purchase_queue to authenticated;
create policy sri_purchase_queue_read on public.sri_purchase_queue for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create index sri_purchase_queue_issue on public.sri_purchase_queue(issue_id) where issue_id is not null;

create function private.gama_sri_purchase_queued() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='posted' and (tg_op='INSERT' or old.status is distinct from new.status)
 and exists(select 1 from public.company_settings c join public.accounting_ec_profile p on p.id=c.id where c.country='EC' and p.withholding_agent and p.confirmed_on is not null)
 then insert into public.sri_purchase_queue(supplier_invoice_id) values(new.id) on conflict do nothing;end if;
 return new;end $$;
revoke all on function private.gama_sri_purchase_queued() from public,anon,authenticated;
create trigger sri_purchase_queued after insert or update of status on public.supplier_invoices for each row execute function private.gama_sri_purchase_queued();

create function private.gama_sri_purchase_document(p_invoice uuid,p_type text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.supplier_invoices;k public.suppliers;f public.accounting_fiscal_documents;p public.supplier_withholding_policies;prof public.accounting_ec_profile;
 snapshot jsonb;lines jsonb:='[]';withheld jsonb:='[]';net numeric:=0;tax numeric:=0;rate numeric;total numeric:=0;row jsonb;issued date:=coalesce(nullif(p_data->>'issue_date','')::date,(now() at time zone private.erp_timezone())::date);result jsonb;
begin
 select * into v from public.supplier_invoices where id=p_invoice for update;
 select * into k from public.suppliers where id=v.supplier_id;
 if v.id is null or v.status<>'posted' or k.tax_id is null or k.tax_id !~ '^([0-9]{10}|[0-9]{13})$' or coalesce(btrim(k.address),'')='' then raise exception 'SRI_SUPPLIER_INCOMPLETE';end if;
 if issued<v.issue_date then raise exception 'SRI_INVALID_DATE';end if;
 if p_type='07' then
 select * into prof from public.accounting_ec_profile where id;
 if prof.withholding_agent is distinct from true or prof.confirmed_on is null then raise exception 'SRI_WITHHOLDING_AGENT_REQUIRED';end if;
 select * into p from public.supplier_withholding_policies where supplier_id=k.id and valid_from<=v.issue_date and (valid_to is null or valid_to>=v.issue_date);
 if p.supplier_id is null then raise exception 'SRI_SUPPLIER_POLICY_REQUIRED';end if;
 select * into f from public.accounting_fiscal_documents where source_type='supplier_invoice' and source_id=v.id;
 if f.id is null or f.identification<>k.tax_id or f.base_zero+f.base_taxed<>v.subtotal or f.vat<>v.tax or f.base_exempt<>0 or f.base_non_taxable<>0 or f.ice<>0 or f.related_party
 then raise exception 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED';end if;
 if f.base_zero>0 then lines:=lines||jsonb_build_array(jsonb_build_object('code','BASE-0','description','Base IVA 0 de la factura proveedor','quantity',1,'unit_price',f.base_zero,'tax_rate',0,'subtotal',f.base_zero));end if;
 if f.base_taxed>0 then
 select t.rate into rate from public.accounting_taxes t where t.id=v.tax_id and t.active;
 if rate is null or rate not in (5,12,13,14,15) or round(f.base_taxed*rate/100,2)<>f.vat then raise exception 'SRI_PURCHASE_TAX_RATE_REQUIRED';end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('code','BASE-IVA','description','Base IVA de la factura proveedor','quantity',1,'unit_price',f.base_taxed,'tax_rate',rate,'subtotal',f.base_taxed));end if;
 if p.income_rate>0 and v.subtotal>0 then
 total:=round(v.subtotal*p.income_rate/100,2);
 withheld:=withheld||jsonb_build_array(jsonb_build_object('tax_kind','IR','code',p.income_code,'base',v.subtotal,'rate',p.income_rate,'amount',total,'account_id',p.income_account_id));end if;
 if p.vat_rate>0 and v.tax>0 then
 total:=total+round(v.tax*p.vat_rate/100,2);
 withheld:=withheld||jsonb_build_array(jsonb_build_object('tax_kind','IVA','code',p.vat_code,'base',v.tax,'rate',p.vat_rate,'amount',round(v.tax*p.vat_rate/100,2),'account_id',p.vat_account_id));end if;
 if total<=0 then raise exception 'SRI_WITHHOLDING_NOT_APPLICABLE';end if;
 snapshot:=jsonb_build_object('support_number',f.document_number,'support_date',v.issue_date,'support_authorization',f.authorization_number,
 'support_code',f.support_code,'support_document_type',f.document_type,'related_party',false,'withholdings',withheld,'withheld_total',total,
 'payment_code',f.payment_codes->>0,'policy_evidence',p.evidence,'policy_reviewed_at',p.reviewed_at);
 else
 if p_type<>'03' or length(k.tax_id)<>10 then raise exception 'SRI_LIQUIDATION_REQUIRES_NO_RUC';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 200 then raise exception 'SRI_LINES_MISSING';end if;
 for row in select value from jsonb_array_elements(p_data->'lines') loop
 if row->>'quantity' is null or row->>'unit_price' is null or row->>'tax_rate' is null or coalesce(btrim(row->>'code'),'')='' or (row->>'quantity')::numeric<=0 or (row->>'unit_price')::numeric<0 or (row->>'tax_rate')::numeric not in (0,5,12,13,14,15) or coalesce(btrim(row->>'description'),'')='' then raise exception 'SRI_INVALID_LINES';end if;
 net:=net+round((row->>'quantity')::numeric*(row->>'unit_price')::numeric,2);
 tax:=tax+round(round((row->>'quantity')::numeric*(row->>'unit_price')::numeric,2)*(row->>'tax_rate')::numeric/100,2);
 lines:=lines||jsonb_build_array(jsonb_build_object('code',row->>'code','description',row->>'description','quantity',(row->>'quantity')::numeric,'unit_price',(row->>'unit_price')::numeric,'tax_rate',(row->>'tax_rate')::numeric));end loop;
 if net<>v.subtotal or tax<>v.tax then raise exception 'SRI_TOTAL_MISMATCH';end if;
 if p_data->>'payment_code' not in ('01','16','19','20') or p_data->>'payment_code' is null then raise exception 'SRI_PAYMENT_CODE_REQUIRED';end if;
 snapshot:=jsonb_build_object('payment_code',p_data->>'payment_code');
 end if;
 result:=private.gama_sri_new_document(p_type,'supplier_invoice',v.id,snapshot||jsonb_build_object('issue_date',issued,'source_number',v.number,
 'customer',k.name,'identification',k.tax_id,'customer_address',k.address,'customer_email',k.email,'subtotal',v.subtotal,'tax',v.tax,'total',v.total,'lines',lines),null,k.id);
 if p_type='07' then update public.sri_purchase_queue set issue_id=(result->>'id')::uuid,last_error=null where supplier_invoice_id=v.id;end if;
 return result;
end $$;
revoke all on function private.gama_sri_purchase_document(uuid,text,jsonb) from public,anon,authenticated;

create function private.gama_sri_route_guide(p_route uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;f public.fleet_drivers;h public.hr_employees;v public.fleet_vehicles;
 d public.tms_deliveries;k public.customers;s public.sales_deliveries;i public.external_invoices;
 stop text;lines jsonb;recipients jsonb:='[]';snapshot jsonb;carrier text;finish date;
begin
 select * into r from public.tms_routes where id=p_route for update;
 if r.id is null or r.status in ('Cancelada','Terminada','En ruta','En tránsito') then raise exception 'SRI_ROUTE_MUST_BE_PREPARED';end if;
 select * into f from public.fleet_drivers where id=r.driver_id and active;
 select * into h from public.hr_employees where id=f.employee_id and active;
 select * into v from public.fleet_vehicles where id=r.vehicle_id;
 carrier:=coalesce(nullif(p_data->>'carrier_identification',''),(select identification from public.hr_employee_private where employee_id=h.id));
 finish:=coalesce(nullif(p_data->>'transport_end','')::date,r.route_date);
 if carrier is null or carrier !~ '^([0-9]{10}|[0-9]{13})$' or f.id is null or v.id is null or coalesce(v.plate,'')='' or finish<r.route_date
 or coalesce(btrim(p_data->>'departure_address'),'')='' then raise exception 'SRI_ROUTE_FISCAL_DATA_REQUIRED';end if;
 for stop in select value from jsonb_array_elements_text(r.stops) loop
 if stop='__depot' then continue;end if;
 select * into d from public.tms_deliveries where id=stop::uuid and route_id=r.id and status<>'Cancelada';
 select * into k from public.customers where id=d.customer_id;
 select * into s from public.sales_deliveries where tms_delivery_id=d.id;
 if d.id is null or s.id is null or k.identification is null or k.identification !~ '^([0-9]{10}|[0-9]{13})$' then raise exception 'SRI_ROUTE_RECIPIENT_INCOMPLETE';end if;
 select jsonb_agg(jsonb_build_object('code',ol.reference,'description',ol.product_name,'quantity',l.quantity) order by l.id) into lines
 from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id where l.delivery_id=s.id;
 if lines is null then raise exception 'SRI_LINES_MISSING';end if;
 snapshot:=jsonb_build_object('identification',k.identification,'customer',k.name,'address',d.address,'reason','Venta de mercadería','lines',lines);
 select * into i from public.external_invoices where order_id=s.order_id and private.gama_sri_authorized_invoice(id) and coalesce(external_number,case when document_kind='external' then number end) ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$' order by issue_date desc limit 1;
 if i.id is not null then snapshot:=snapshot||jsonb_build_object('support_number',coalesce(i.external_number,i.number),'support_date',coalesce(i.external_issue_date,i.issue_date),'support_authorization',i.access_key);end if;
 recipients:=recipients||jsonb_build_array(snapshot);
 end loop;
 if jsonb_array_length(recipients)=0 then raise exception 'SRI_ROUTE_EMPTY';end if;
 update public.tms_routes set manual_override=true where id=r.id;
 return private.gama_sri_new_document('06','tms_route',r.id,jsonb_build_object('issue_date',r.route_date,'source_number','Ruta '||r.route_date||' / '||v.plate,
 'transport_start',r.route_date,'transport_end',finish,'carrier_name',f.name,'carrier_identification',carrier,'plate',v.plate,
 'departure_address',p_data->>'departure_address','route_version',r.version,'recipients',recipients),null,null,r.id);
end $$;
revoke all on function private.gama_sri_route_guide(uuid,jsonb) from public,anon,authenticated;

alter table public.sri_document_issues add column withholding_id uuid references public.accounting_withholdings(id);
create index sri_document_withholding on public.sri_document_issues(withholding_id) where withholding_id is not null;
create function private.gama_sri_documents(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare d public.sri_document_issues;p public.supplier_withholding_policies;row record;result jsonb;items jsonb:='[]';lines jsonb;
 kind text:=p_data->>'document_type';source uuid:=nullif(p_data->>'source_id','')::uuid;today date:=(now() at time zone private.erp_timezone())::date;
 r public.return_orders;credit public.return_credits;line record;rights jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or private.current_user_role()<>'administrador' or not private.erp_module_allowed('accounting',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action not in ('context','list') and not private.erp_action_allowed('accounting',case when p_action='settle' then 'validate' else 'create' end) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object(
 'policies',coalesce((select jsonb_agg(x) from (select p.*,s.name supplier from public.supplier_withholding_policies p join public.suppliers s on s.id=p.supplier_id order by s.name,p.supplier_id limit 200)x),'[]'),
 'suppliers',coalesce((select jsonb_agg(x) from (select s.id,s.name,s.tax_id identification from public.suppliers s where s.active and (coalesce(p_data->>'search','')='' or s.name ilike '%'||(p_data->>'search')||'%') order by s.name,s.id limit 200)x),'[]'),
 'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name)) from public.accounting_accounts a where a.active and a.type='liability'),'[]'),
 'credits',coalesce((select jsonb_agg(x) from (select c.id,c.erp_reference number,c.amount,k.name customer from public.return_credits c join public.return_orders r on r.id=c.return_id join public.customers k on k.id=r.customer_id where r.kind='customer' and not exists(select 1 from public.sri_document_issues d where d.source_type='return_credit' and d.source_id=c.id) order by c.created_at desc,c.id limit 100)x),'[]'),
 'purchases',coalesce((select jsonb_agg(x) from (select v.id,v.number,v.total amount,s.name supplier,s.tax_id identification from public.supplier_invoices v join public.suppliers s on s.id=v.supplier_id where v.status='posted' and (coalesce(p_data->>'search','')='' or concat_ws(' ',v.number,s.name) ilike '%'||(p_data->>'search')||'%') order by v.issue_date desc,v.id limit 100)x),'[]'),
 'routes',coalesce((select jsonb_agg(x) from (select r.id,r.route_date date,r.driver_name driver,r.vehicle from public.tms_routes r where r.route_date>=today and r.status not in ('En ruta','En tránsito','Cancelada','Terminada') order by r.route_date,r.id limit 100)x),'[]'),
 'purchase_queue',coalesce((select jsonb_agg(x) from (select q.*,v.number,s.name supplier from public.sri_purchase_queue q join public.supplier_invoices v on v.id=q.supplier_invoice_id join public.suppliers s on s.id=v.supplier_id where q.issue_id is null and v.status='posted' order by q.created_at,q.supplier_invoice_id limit 100)x),'[]'));
 elsif p_action='list' then return jsonb_build_object('rows',coalesce((select jsonb_agg(x) from(
 select d.id,d.document_type,d.source_type,d.source_id,d.status,d.access_key,d.last_error,d.created_at,d.authorized_at,d.withholding_id,
 d.establishment||'-'||d.emission_point||'-'||d.sequential fiscal_number,d.snapshot->>'source_number' erp_reference,
 coalesce(d.snapshot->>'customer',d.snapshot->>'carrier_name') partner,d.snapshot->>'issue_date' issue_date
 from public.sri_document_issues d where kind is null or d.document_type=kind order by d.created_at desc,d.id
 limit least(100,greatest(1,coalesce((p_data->>'limit')::int,50))) offset greatest(0,coalesce((p_data->>'offset')::int,0)))x),'[]'),
 'total',(select count(*) from public.sri_document_issues d where kind is null or d.document_type=kind));
 elsif p_action='policy_save' then
 if (p_data->>'income_rate')::numeric>0 then perform private.gama_ec_account((p_data->>'income_account_id')::uuid,'liability');end if;
 if (p_data->>'vat_rate')::numeric>0 then perform private.gama_ec_account((p_data->>'vat_account_id')::uuid,'liability');end if;
 insert into public.supplier_withholding_policies(supplier_id,income_code,income_rate,income_account_id,vat_code,vat_rate,vat_account_id,valid_from,valid_to,evidence,reviewed_by)
 values((p_data->>'supplier_id')::uuid,nullif(p_data->>'income_code',''),(p_data->>'income_rate')::numeric,nullif(p_data->>'income_account_id','')::uuid,
 nullif(p_data->>'vat_code',''),(p_data->>'vat_rate')::numeric,nullif(p_data->>'vat_account_id','')::uuid,(p_data->>'valid_from')::date,nullif(p_data->>'valid_to','')::date,p_data->>'evidence',auth.uid())
 on conflict(supplier_id) do update set income_code=excluded.income_code,income_rate=excluded.income_rate,income_account_id=excluded.income_account_id,
 vat_code=excluded.vat_code,vat_rate=excluded.vat_rate,vat_account_id=excluded.vat_account_id,valid_from=excluded.valid_from,valid_to=excluded.valid_to,evidence=excluded.evidence,reviewed_by=excluded.reviewed_by,reviewed_at=now();
 return jsonb_build_object('supplier_id',p_data->>'supplier_id');
 elsif p_action='discard_guide' then
 select * into d from public.sri_document_issues where id=(p_data->>'id')::uuid for update;
 if d.id is null or d.document_type<>'06' or d.status<>'draft' or d.access_key is not null or d.signed_xml_path is not null then raise exception 'SRI_DRAFT_GUIDE_REQUIRED';end if;
 delete from public.sri_document_issues where id=d.id;
 return jsonb_build_object('discarded',true);
 elsif p_action='prepare' then
 if kind='04' then return private.gama_sri_credit_note(source);
 elsif kind in ('03','07') then return private.gama_sri_purchase_document(source,kind,p_data);
 elsif kind='06' then return private.gama_sri_route_guide(source,p_data);end if;
 raise exception 'SRI_DOCUMENT_TYPE_UNSUPPORTED';
 elsif p_action='prepare_purchases' then
 for row in select q.supplier_invoice_id from public.sri_purchase_queue q join public.supplier_invoices v on v.id=q.supplier_invoice_id where q.issue_id is null and v.status='posted' order by q.created_at limit 50 loop
 begin result:=private.gama_sri_purchase_document(row.supplier_invoice_id,'07','{}');items:=items||jsonb_build_array(result);
 exception when others then update public.sri_purchase_queue set last_error=case when sqlerrm ~ '^[A-Z0-9_]{1,100}$' then sqlerrm else 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED' end where supplier_invoice_id=row.supplier_invoice_id;end;
 end loop;return jsonb_build_object('prepared',items);
 elsif p_action='return_complete' then
 if not private.erp_module_allowed('returns',array['administrador']) or not private.erp_action_allowed('returns','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.return_orders where id=source for update;
 if r.id is null or r.kind<>'customer' or r.status in ('closed','cancelled','to_process') then raise exception 'RETURN_NOT_RECEIVED';end if;
 select * into credit from public.return_credits where return_id=r.id;
 if credit.id is not null and exists(select 1 from public.sri_document_issues where source_type='return_credit' and source_id=credit.id) then return (select jsonb_build_object('id',id,'status',status,'document_type',document_type) from public.sri_document_issues where source_type='return_credit' and source_id=credit.id);end if;
 rights:=private.gama_returns_rights();
 if exists(select 1 from public.return_lines where return_id=r.id and processed_at is null) then
 if p_data->>'inspected' is distinct from 'true' then raise exception 'RETURN_INSPECTION_REQUIRED';end if;
 for line in select id from public.return_lines where return_id=r.id and processed_at is null order by product_id,id loop
 perform private.gama_returns_action('process_line',jsonb_build_object('id',r.id,'line_id',line.id,'disposition','restocked','location_id',p_data->>'location_id'));
 end loop;end if;
 if credit.id is null then result:=private.gama_returns_action('credit',jsonb_build_object('id',r.id,'issued_on',today,'notes',p_data->>'notes'));source:=(result->>'id')::uuid;else source:=credit.id;end if;
 return private.gama_sri_credit_note(source);
 elsif p_action='settle' then
 select * into d from public.sri_document_issues where id=(p_data->>'id')::uuid for update;
 if d.id is null or d.document_type<>'07' or d.status<>'authorized' or d.access_key is null or d.access_key is distinct from d.authorization_response->>'authorization' then raise exception 'SRI_NOT_AUTHORIZED';end if;
 if d.withholding_id is not null then return jsonb_build_object('id',d.withholding_id);end if;
 select jsonb_agg(jsonb_build_object('tax_kind',case when x->>'tax_kind'='IR' then 'income' else 'vat' end,'code',x->>'code','base',x->'base','rate',x->'rate','account_id',x->>'account_id')) into lines from jsonb_array_elements(d.snapshot->'withholdings')x;
 result:=private.gama_accounting_ec('withholding_post',jsonb_build_object('request_key',d.id,'side','supplier','invoice_id',d.source_id,'issued_on',d.snapshot->>'issue_date',
 'number',d.establishment||'-'||d.emission_point||'-'||d.sequential,'authorization_number',d.access_key,'evidence','Comprobante de retención SRI autorizado: '||d.access_key,'lines',lines));
 update public.sri_document_issues set withholding_id=(result->>'id')::uuid where id=d.id;return result;
 end if;raise exception 'UNKNOWN_ACTION';end $$;
revoke all on function private.gama_sri_documents(text,jsonb) from public,anon;
grant execute on function private.gama_sri_documents(text,jsonb) to authenticated;
create function public.gama_sri_documents(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_sri_documents(p_action,p_data)$$;
revoke all on function public.gama_sri_documents(text,jsonb) from public,anon;
grant execute on function public.gama_sri_documents(text,jsonb) to authenticated;

-- A frozen guide must retain its stop order and goods while transport proceeds.
create function private.gama_sri_route_locked() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (new.stops is distinct from old.stops or new.route_date is distinct from old.route_date or new.driver_id is distinct from old.driver_id or new.vehicle_id is distinct from old.vehicle_id) and exists(select 1 from public.sri_document_issues d where d.route_id=old.id and d.status<>'rejected') then raise exception 'SRI_ROUTE_GUIDE_LOCKED';end if;
 return new;end $$;
revoke all on function private.gama_sri_route_locked() from public,anon,authenticated;
create trigger sri_route_locked before update of stops,route_date,driver_id,vehicle_id on public.tms_routes for each row execute function private.gama_sri_route_locked();

create function private.gama_sri_purchase_reviewed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.source_type='supplier_invoice' and exists(select 1 from public.sri_purchase_queue where supplier_invoice_id=new.source_id and issue_id is null) then
 begin perform private.gama_sri_purchase_document(new.source_id,'07','{}');
 exception when others then update public.sri_purchase_queue set last_error=case when sqlerrm ~ '^[A-Z0-9_]{1,100}$' then sqlerrm else 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED' end where supplier_invoice_id=new.source_id;end;
 end if;return new;end $$;
revoke all on function private.gama_sri_purchase_reviewed() from public,anon,authenticated;
create trigger sri_purchase_reviewed after insert or update on public.accounting_fiscal_documents for each row execute function private.gama_sri_purchase_reviewed();

-- Route managers prepare guides in TMS; drivers read only their own authorized guide.
create function private.gama_tms_guide(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r uuid:=nullif(p_data->>'route_id','')::uuid;d public.sri_document_issues;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if private.current_user_role()<>'administrador' and not private.gama_sri_own_route(r) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action='get' then
 select * into d from public.sri_document_issues where route_id=r;
 return case when d.id is null then null else jsonb_build_object('id',d.id,'document_type','06','status',d.status,'number',d.establishment||'-'||d.emission_point||'-'||d.sequential,'has_pdf',d.ride_path is not null) end;
 end if;
 if private.current_user_role()<>'administrador' or not private.erp_action_allowed('tms','create') then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action='prepare' then return private.gama_sri_route_guide(r,p_data);end if;
 if p_action='discard' then
 select * into d from public.sri_document_issues where route_id=r for update;
 if d.id is null or d.status<>'draft' or d.access_key is not null or d.signed_xml_path is not null then raise exception 'SRI_DRAFT_GUIDE_REQUIRED';end if;
 delete from public.sri_document_issues where id=d.id;return jsonb_build_object('discarded',true);
 end if;raise exception 'UNKNOWN_ACTION';end $$;
revoke all on function private.gama_tms_guide(text,jsonb) from public,anon;
grant execute on function private.gama_tms_guide(text,jsonb) to authenticated;
create function public.gama_tms_guide(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_guide(p_action,p_data)$$;
revoke all on function public.gama_tms_guide(text,jsonb) from public,anon;
grant execute on function public.gama_tms_guide(text,jsonb) to authenticated;
grant all on public.supplier_withholding_policies,public.sri_purchase_queue to service_role;

create function private.gama_sri_goods_locked() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.sales_deliveries s join public.sri_document_issues d on d.route_id=(select route_id from public.tms_deliveries where id=s.tms_delivery_id) where s.id=old.delivery_id and d.status<>'rejected')
 and (tg_op='DELETE' or new.quantity is distinct from old.quantity or new.order_line_id is distinct from old.order_line_id or new.delivery_id is distinct from old.delivery_id) then raise exception 'SRI_ROUTE_GUIDE_LOCKED';end if;
 return case when tg_op='DELETE' then old else new end;end $$;
revoke all on function private.gama_sri_goods_locked() from public,anon,authenticated;
create trigger sri_goods_locked before update or delete on public.sales_delivery_lines for each row execute function private.gama_sri_goods_locked();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004223009','ec_fiscal_documents','b1e8a3d1667fe516803abc24659f09fd75ae9277929f0fa2639a81a13c1e9808','b1e8a3d1667fe516803abc24659f09fd75ae9277929f0fa2639a81a13c1e9808','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004230936_ec_received_withholdings.sql; SHA256 f37220fe7d8a0cdc29b791441b8b10b4bed47357a94b880b8cbaf3f4f248068c
-- Online SRI verification is service-only. Browsers post only a verified receipt.
create table public.accounting_received_sri (
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.external_invoices(id),
 access_key text not null check(access_key ~ '^[0-9]{49}$'),issuer_ruc text not null check(issuer_ruc ~ '^[0-9]{13}$'),
 number text not null check(number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$'),issued_on date not null,
 amount numeric(18,2) not null check(amount>0),lines jsonb not null check(jsonb_typeof(lines)='array'),
 authorized_at timestamptz not null,xml_path text not null,xml_sha256 text not null check(xml_sha256 ~ '^[a-f0-9]{64}$'),
 verified_by uuid not null references public.profiles(id),verified_at timestamptz not null default now(),
 withholding_id uuid references public.accounting_withholdings(id),unique(access_key,invoice_id)
);
alter table public.accounting_received_sri enable row level security;
revoke all on public.accounting_received_sri from public,anon,authenticated;
grant select on public.accounting_received_sri to authenticated;
grant all on public.accounting_received_sri to service_role;
create policy received_sri_read on public.accounting_received_sri for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create index received_sri_invoice on public.accounting_received_sri(invoice_id);
create index received_sri_verifier on public.accounting_received_sri(verified_by);
create index received_sri_withholding on public.accounting_received_sri(withholding_id) where withholding_id is not null;

create function private.gama_ec_received(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare d public.accounting_received_sri;r record;lines jsonb:='[]';x jsonb;result jsonb;amount numeric:=0;base_ir numeric:=0;base_iva numeric:=0;expected numeric;account uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or private.current_user_role()<>'administrador' or not private.erp_module_allowed('accounting',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then return jsonb_build_object('rows',coalesce((select jsonb_agg(z) from (select d.id,d.invoice_id,d.access_key,d.issuer_ruc,d.number,d.issued_on,d.amount,d.withholding_id,v.number invoice_number from public.accounting_received_sri d join public.external_invoices v on v.id=d.invoice_id order by d.verified_at desc,d.id limit 100)z),'[]'));end if;
 if p_action<>'post' then raise exception 'UNKNOWN_ACTION';end if;
 if not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into d from public.accounting_received_sri where id=(p_data->>'id')::uuid for update;
 if d.id is null then raise exception 'SRI_RECEIVED_VERIFICATION_REQUIRED';end if;
 if d.withholding_id is not null then return jsonb_build_object('id',d.withholding_id,'amount',d.amount);end if;
 select * into r from private.gama_receivables where id=d.invoice_id and payment_status<>'cancelled';
 if r.id is null or r.identification<>d.issuer_ruc then raise exception 'SRI_RECEIVED_PARTY_MISMATCH';end if;
 if jsonb_array_length(d.lines) not between 1 and 50 then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 for x in select value from jsonb_array_elements(d.lines) loop
 if x->>'tax_kind' not in ('income','vat') or x->>'tax_kind' is null then raise exception 'SRI_RECEIVED_TAX_UNSUPPORTED';end if;
 if (x->>'base') is null or (x->>'rate') is null or (x->>'base')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'rate')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'base')::numeric<=0 or (x->>'rate')::numeric not between 0.001 and 100 or coalesce(x->>'code','') !~ '^[0-9]{1,5}$' then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 expected:=round((x->>'base')::numeric*(x->>'rate')::numeric/100,2);
 if expected is null or expected<=0 or expected is distinct from (x->>'amount')::numeric then raise exception 'SRI_WITHHOLDING_TOTAL_MISMATCH';end if;
 amount:=amount+expected;
 if x->>'tax_kind'='income' then base_ir:=base_ir+(x->>'base')::numeric;else base_iva:=base_iva+(x->>'base')::numeric;end if;
 account:=nullif(p_data->>(case when x->>'tax_kind'='income' then 'income_account_id' else 'vat_account_id' end),'')::uuid;
 perform private.gama_ec_account(account,'asset');
 lines:=lines||jsonb_build_array(jsonb_build_object('tax_kind',x->>'tax_kind','code',x->>'code','base',x->'base','rate',x->'rate','account_id',account));
 end loop;
 if amount<>d.amount or base_ir>r.subtotal or base_iva>r.tax then raise exception 'SRI_RECEIVED_INVOICE_MISMATCH';end if;
 result:=private.gama_accounting_ec('withholding_post',jsonb_build_object('request_key',d.id,'side','customer','invoice_id',d.invoice_id,'issued_on',d.issued_on,'number',d.number,'authorization_number',d.access_key,'evidence','XML recibido verificado en línea ante el SRI: '||d.access_key,'lines',lines));
 update public.accounting_received_sri set withholding_id=(result->>'id')::uuid where id=d.id;return result;
end $$;
revoke all on function private.gama_ec_received(text,jsonb) from public,anon;
grant execute on function private.gama_ec_received(text,jsonb) to authenticated;
create function public.gama_ec_received(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_ec_received(p_action,p_data)$$;
revoke all on function public.gama_ec_received(text,jsonb) from public,anon;
grant execute on function public.gama_ec_received(text,jsonb) to authenticated;

create function private.gama_ec_received_match(p_ruc text,p_number text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or private.current_user_role()<>'administrador' or not private.erp_module_allowed('accounting',array['administrador']) or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_ruc !~ '^[0-9]{13}$' or p_number !~ '^[0-9]{15}$' then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 select jsonb_agg(jsonb_build_object('id',v.id,'number',v.number,'fiscal_number',coalesce(v.external_number,f.document_number,v.number),'issuer_ruc',c.tax_id,'customer_identification',k.identification,'issue_date',coalesce(v.external_issue_date,v.issue_date),'subtotal',v.subtotal,'tax',v.tax)) into rows
 from public.external_invoices v join public.sales_orders o on o.id=v.order_id join public.customers k on k.id=o.customer_id cross join public.company_settings c
 left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=v.id
 where c.id and c.configured and c.country='EC' and k.identification=p_ruc and v.fiscal_status<>'cancelled'
 and replace(coalesce(v.external_number,f.document_number,v.number),'-','')=p_number;
 if rows is null then raise exception 'SRI_RECEIVED_INVOICE_NOT_FOUND';end if;
 if jsonb_array_length(rows)<>1 then raise exception 'SRI_RECEIVED_INVOICE_AMBIGUOUS';end if;
 return rows->0;end $$;
revoke all on function private.gama_ec_received_match(text,text) from public,anon;
grant execute on function private.gama_ec_received_match(text,text) to authenticated;
create function public.gama_ec_received_match(p_ruc text,p_number text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_ec_received_match(p_ruc,p_number)$$;
revoke all on function public.gama_ec_received_match(text,text) from public,anon;
grant execute on function public.gama_ec_received_match(text,text) to authenticated;

-- All invoices in one received XML are settled together or none are changed.
create function private.gama_ec_received_batch(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb;rows jsonb:='[]';begin
 if auth.uid() is null or jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids') not between 1 and 50 then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 for x in select value from jsonb_array_elements(p_data->'ids') order by value::text loop
 rows:=rows||jsonb_build_array(private.gama_ec_received('post',p_data||jsonb_build_object('id',x#>>'{}')));end loop;
 return jsonb_build_object('rows',rows);end $$;
revoke all on function private.gama_ec_received_batch(jsonb) from public,anon;
grant execute on function private.gama_ec_received_batch(jsonb) to authenticated;
create function public.gama_ec_received_batch(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_ec_received_batch(p_data)$$;
revoke all on function public.gama_ec_received_batch(jsonb) from public,anon;
grant execute on function public.gama_ec_received_batch(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004230936','ec_received_withholdings','f37220fe7d8a0cdc29b791441b8b10b4bed47357a94b880b8cbaf3f4f248068c','f37220fe7d8a0cdc29b791441b8b10b4bed47357a94b880b8cbaf3f4f248068c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004233005_ec_ats_and_tax_drafts.sql; SHA256 5441bb9fcacdab06eb1d45f4d6c55dfbb6238f675bc7633ad9fab2c1aa7741bd
-- Reviewed domestic ATS sources. No cancellation is inferred from a timeout,
-- rejection or management status; legal cancellation evidence is explicit.
alter table public.accounting_fiscal_documents drop constraint accounting_fiscal_documents_source_type_check;
alter table public.accounting_fiscal_documents add constraint accounting_fiscal_documents_source_type_check check(source_type in ('sales_invoice','supplier_invoice','expense','sales_credit','supplier_credit','customer_adjustment','supplier_adjustment'));
alter table public.accounting_fiscal_documents add column document_issued_on date;
alter table public.accounting_fiscal_documents add column modified_document_type text check(modified_document_type ~ '^[0-9]{2}$');
alter table public.accounting_fiscal_documents add column modified_number text check(modified_number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$');
alter table public.accounting_fiscal_documents add column modified_authorization text check(modified_authorization ~ '^[0-9]{10,49}$');
alter table public.accounting_ec_profile add column ats_establishments jsonb check(ats_establishments is null or jsonb_typeof(ats_establishments)='array');

create table public.accounting_fiscal_cancellations (
 id uuid primary key default gen_random_uuid(),source_invoice_id uuid references public.external_invoices(id),
 document_type text not null check(document_type in ('01','03','04','05','06','07','18')),
 establishment text not null check(establishment ~ '^[0-9]{3}$'),emission_point text not null check(emission_point ~ '^[0-9]{3}$'),
 sequential_start bigint not null check(sequential_start between 1 and 999999999),sequential_end bigint not null check(sequential_end between sequential_start and 999999999),
 authorization_number text not null check(authorization_number ~ '^[0-9]{3,49}$'),cancelled_on date not null,portal_deregistered boolean not null default false,
 evidence text not null check(length(btrim(evidence))>=10),reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default now(),
 unique(document_type,establishment,emission_point,sequential_start,sequential_end,authorization_number)
);
create index fiscal_cancellation_source on public.accounting_fiscal_cancellations(source_invoice_id) where source_invoice_id is not null;
create index fiscal_cancellation_reviewer on public.accounting_fiscal_cancellations(reviewed_by);
create index fiscal_cancellation_period on public.accounting_fiscal_cancellations(cancelled_on);
alter table public.accounting_fiscal_cancellations enable row level security;
revoke all on public.accounting_fiscal_cancellations from public,anon,authenticated;
grant select on public.accounting_fiscal_cancellations to authenticated;
create policy fiscal_cancellations_read on public.accounting_fiscal_cancellations for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create trigger erp_audit_capture after insert or update or delete on public.accounting_fiscal_cancellations for each row execute function private.erp_audit_capture();

create view private.gama_ec_fiscal_extra_sources as
 select case when k.invoice_id is not null then 'sales_credit' else 'supplier_credit' end source_type,k.id source_id,coalesce(k.erp_reference,k.number) number,k.issued_on issue_date,
 coalesce(c.name,s.name) partner_name,coalesce(c.identification,s.tax_id) partner_identification,x.net subtotal,x.tax,k.amount total,
 case when k.invoice_id is not null then 'customer' else 'supplier' end side,coalesce(k.invoice_id,k.supplier_invoice_id) invoice_id,'credit' kind
 from public.return_credits k join public.return_orders o on o.id=k.return_id left join public.customers c on c.id=o.customer_id left join public.suppliers s on s.id=o.supplier_id
 cross join lateral(select coalesce(sum(round(quantity*unit_price,2)),0) net,coalesce(sum(round(round(quantity*unit_price,2)*tax_rate/100,2)),0) tax from public.return_lines where return_id=k.return_id)x
 union all select case when a.side='customer' then 'customer_adjustment' else 'supplier_adjustment' end,a.id,a.reference,a.issued_on,coalesce(c.name,s.name),coalesce(c.identification,s.tax_id),a.net,a.tax,a.total,a.side,coalesce(a.invoice_id,a.supplier_invoice_id),a.kind
 from public.accounting_adjustments a left join public.external_invoices v on v.id=a.invoice_id left join public.sales_orders o on o.id=v.order_id left join public.customers c on c.id=o.customer_id
 left join public.supplier_invoices b on b.id=a.supplier_invoice_id left join public.suppliers s on s.id=b.supplier_id where a.status='posted';
revoke all on private.gama_ec_fiscal_extra_sources from public,anon,authenticated;

-- Extend the existing command receipt and permission dispatcher, preserving its
-- request-key checks, closed periods and every existing action.
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_before_ats;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;result jsonb;rid uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());total numeric;begin
 if p_action='cancellation_save' then
  if nullif(p_data->>'source_invoice_id','') is not null then
   select v.fiscal_status,coalesce(v.external_number,f.document_number,case when v.document_kind='external' then v.number end) fiscal_number,coalesce(v.access_key,f.authorization_number) fiscal_authorization into r from public.external_invoices v left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=v.id where v.id=(p_data->>'source_invoice_id')::uuid;
   if not found or r.fiscal_status<>'cancelled' or r.fiscal_number is null or split_part(r.fiscal_number,'-',1) is distinct from p_data->>'establishment' or split_part(r.fiscal_number,'-',2) is distinct from p_data->>'emission_point' or split_part(r.fiscal_number,'-',3)::bigint not between (p_data->>'sequential_start')::bigint and (p_data->>'sequential_end')::bigint or r.fiscal_authorization is distinct from p_data->>'authorization_number' then raise exception 'FISCAL_CANCELLATION_SOURCE_MISMATCH';end if;
  end if;
  insert into public.accounting_fiscal_cancellations(id,source_invoice_id,document_type,establishment,emission_point,sequential_start,sequential_end,authorization_number,cancelled_on,portal_deregistered,evidence,reviewed_by)
  values(rid,nullif(p_data->>'source_invoice_id','')::uuid,p_data->>'document_type',p_data->>'establishment',p_data->>'emission_point',(p_data->>'sequential_start')::bigint,(p_data->>'sequential_end')::bigint,p_data->>'authorization_number',(p_data->>'cancelled_on')::date,coalesce((p_data->>'portal_deregistered')::boolean,false),p_data->>'evidence',auth.uid())
  on conflict(document_type,establishment,emission_point,sequential_start,sequential_end,authorization_number) do update set cancelled_on=excluded.cancelled_on,portal_deregistered=excluded.portal_deregistered,evidence=excluded.evidence,reviewed_by=auth.uid(),reviewed_at=now() returning id into rid;
  return jsonb_build_object('id',rid);
 elsif p_action='fiscal_save' then
  if p_data->>'source_type' in ('sales_credit','supplier_credit','customer_adjustment','supplier_adjustment') then
   select * into r from private.gama_ec_fiscal_extra_sources where source_type=p_data->>'source_type' and source_id=(p_data->>'source_id')::uuid;
   if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
   if coalesce(r.partner_identification,'')<>'' and p_data->>'identification' is distinct from r.partner_identification then raise exception 'FISCAL_PARTNER_MISMATCH';end if;
   total:=coalesce((p_data->>'base_zero')::numeric,0)+coalesce((p_data->>'base_taxed')::numeric,0)+coalesce((p_data->>'base_exempt')::numeric,0)+coalesce((p_data->>'base_non_taxable')::numeric,0);
   if total is distinct from r.subtotal or (p_data->>'vat')::numeric is distinct from r.tax or total+coalesce((p_data->>'ice')::numeric,0)+(p_data->>'vat')::numeric is distinct from r.total then raise exception 'FISCAL_TOTAL_MISMATCH';end if;
   if p_data->>'document_type' is distinct from (case when r.kind='credit' then '04' else '05' end) then raise exception 'FISCAL_DOCUMENT_TYPE_MISMATCH';end if;
   if jsonb_typeof(p_data->'payment_codes') is distinct from 'array' or jsonb_array_length(p_data->'payment_codes')=0 then raise exception 'PAYMENT_CODE_REQUIRED';end if;
   insert into public.accounting_fiscal_documents(source_type,source_id,document_type,document_number,identification_type,identification,authorization_number,support_code,payment_codes,related_party,base_zero,base_taxed,base_exempt,base_non_taxable,ice,vat,evidence,reviewed_by)
   values(p_data->>'source_type',r.source_id,p_data->>'document_type',p_data->>'document_number',p_data->>'identification_type',p_data->>'identification',p_data->>'authorization_number',nullif(p_data->>'support_code',''),p_data->'payment_codes',coalesce((p_data->>'related_party')::boolean,false),coalesce((p_data->>'base_zero')::numeric,0),coalesce((p_data->>'base_taxed')::numeric,0),coalesce((p_data->>'base_exempt')::numeric,0),coalesce((p_data->>'base_non_taxable')::numeric,0),coalesce((p_data->>'ice')::numeric,0),(p_data->>'vat')::numeric,p_data->>'evidence',auth.uid())
   on conflict(source_type,source_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,identification_type=excluded.identification_type,identification=excluded.identification,authorization_number=excluded.authorization_number,support_code=excluded.support_code,payment_codes=excluded.payment_codes,related_party=excluded.related_party,base_zero=excluded.base_zero,base_taxed=excluded.base_taxed,base_exempt=excluded.base_exempt,base_non_taxable=excluded.base_non_taxable,ice=excluded.ice,vat=excluded.vat,evidence=excluded.evidence,reviewed_by=auth.uid(),reviewed_at=now() returning id into rid;
   result:=jsonb_build_object('id',rid);
  else result:=private.gama_accounting_ec_write_before_ats(p_action,p_data);end if;
  update public.accounting_fiscal_documents set document_issued_on=nullif(p_data->>'document_issued_on','')::date,modified_document_type=nullif(p_data->>'modified_document_type',''),modified_number=nullif(p_data->>'modified_number',''),modified_authorization=nullif(p_data->>'modified_authorization','') where source_type=p_data->>'source_type' and source_id=(p_data->>'source_id')::uuid;
  return result;
 elsif p_action='profile_save' then
  result:=private.gama_accounting_ec_write_before_ats(p_action,p_data);
  if p_data ? 'ats_establishments' then
   if jsonb_typeof(p_data->'ats_establishments') is distinct from 'array' or jsonb_array_length(p_data->'ats_establishments') not between 1 and 999 or exists(select 1 from jsonb_array_elements_text(p_data->'ats_establishments')x where x !~ '^[0-9]{3}$' or x='000') or (select count(distinct x) from jsonb_array_elements_text(p_data->'ats_establishments')x)<>jsonb_array_length(p_data->'ats_establishments') then raise exception 'ATS_ESTABLISHMENTS_INVALID';end if;
   update public.accounting_ec_profile set ats_establishments=p_data->'ats_establishments' where id;
  end if;
  return result;
 end if;
 return private.gama_accounting_ec_write_before_ats(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;

-- Authorized local SRI documents supply fiscal facts without manual retyping.
create function private.gama_ec_issue_fiscal(p_issue public.sri_document_issues) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('document_type',p_issue.document_type,'document_number',p_issue.establishment||'-'||p_issue.emission_point||'-'||p_issue.sequential,
 'identification_type',case when length(p_issue.snapshot->>'identification')=13 then '04' else '05' end,'identification',p_issue.snapshot->>'identification',
 'authorization_number',p_issue.access_key,'support_code','01','payment_codes',case when p_issue.document_type='03' then jsonb_build_array(p_issue.snapshot->>'payment_code') else coalesce(p_issue.snapshot->'payment_codes','[]'::jsonb) end,'related_party',false,
 'base_zero',coalesce((select sum((l->>'subtotal')::numeric) from jsonb_array_elements(p_issue.snapshot->'lines')l where (l->>'tax_rate')::numeric=0),0),
 'base_taxed',coalesce((select sum((l->>'subtotal')::numeric) from jsonb_array_elements(p_issue.snapshot->'lines')l where (l->>'tax_rate')::numeric>0),0),
 'base_exempt',0,'base_non_taxable',0,'vat',p_issue.snapshot->'tax','ice',0,'document_issued_on',p_issue.snapshot->>'issue_date',
 'modified_document_type',case when p_issue.document_type='04' then '01' end,'modified_number',p_issue.snapshot->>'support_number','modified_authorization',p_issue.snapshot->>'support_authorization');
$$;
revoke all on function private.gama_ec_issue_fiscal(public.sri_document_issues) from public,anon,authenticated;

alter function private.gama_accounting_ec_read(text,jsonb) rename to gama_accounting_ec_read_before_ats;
create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare result jsonb;d jsonb;docs jsonb:='[]';r record;s public.sri_document_issues;from_date date;to_date date;begin
 result:=private.gama_accounting_ec_read_before_ats(p_action,p_data);
 if p_action<>'fiscal_review' then return result;end if;
 from_date:=(result->>'from')::date;to_date:=(result->>'to')::date;
 for d in select value from jsonb_array_elements(result->'documents') loop
  select * into s from public.sri_document_issues where document_type='03' and source_id=(d->>'source_id')::uuid and d->>'source_type'='supplier_invoice' and status='authorized';
  if found then d:=d||jsonb_build_object('fiscal_id',s.id,'fiscal',private.gama_ec_issue_fiscal(s));end if;
  docs:=docs||jsonb_build_array(d);
 end loop;
 for r in select x.*,f.id fiscal_id,to_jsonb(f) fiscal from private.gama_ec_fiscal_extra_sources x left join public.accounting_fiscal_documents f on f.source_type=x.source_type and f.source_id=x.source_id where x.issue_date between from_date and to_date order by x.issue_date,x.source_id loop
  d:=to_jsonb(r);select * into s from public.sri_document_issues where document_type='04' and source_id=r.source_id and source_type='return_credit' and status='authorized';
  if found then d:=d||jsonb_build_object('fiscal_id',s.id,'fiscal',private.gama_ec_issue_fiscal(s));end if;
  docs:=docs||jsonb_build_array(d);
 end loop;
 return result||jsonb_build_object('documents',docs,'adjustments','[]'::jsonb,'return_credits','[]'::jsonb,
 'withholdings',coalesce((select jsonb_agg(to_jsonb(w)||jsonb_build_object('invoice_fiscal',to_jsonb(f),'partner_identification',coalesce(c.identification,s.tax_id),'invoice_number',coalesce(v.number,b.number))) from public.accounting_withholdings w
 left join public.external_invoices v on v.id=w.invoice_id left join public.sales_orders o on o.id=v.order_id left join public.customers c on c.id=o.customer_id left join public.supplier_invoices b on b.id=w.supplier_invoice_id left join public.suppliers s on s.id=b.supplier_id
 left join public.accounting_fiscal_documents f on f.source_type=case when w.side='customer' then 'sales_invoice' else 'supplier_invoice' end and f.source_id=coalesce(w.invoice_id,w.supplier_invoice_id)
 where w.status='posted' and w.issued_on between from_date and to_date),'[]'),
 'cancellations',coalesce((select jsonb_agg(to_jsonb(x) order by cancelled_on,establishment,emission_point,sequential_start) from public.accounting_fiscal_cancellations x where cancelled_on between from_date and to_date and not portal_deregistered),'[]'),
 'reviewed_cancellations',coalesce((select jsonb_agg(to_jsonb(x) order by cancelled_on,id) from public.accounting_fiscal_cancellations x where cancelled_on between from_date and to_date),'[]'),
 'cancelled_pending',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.number,'fiscal_number',coalesce(v.external_number,f.document_number),'authorization_number',coalesce(v.access_key,f.authorization_number))) from public.external_invoices v left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=v.id where v.fiscal_status='cancelled' and v.issue_date between from_date and to_date and (v.external_number is not null or f.id is not null) and not exists(select 1 from public.accounting_fiscal_cancellations x where x.source_invoice_id=v.id)),'[]'),
 'cancelled_documents',(select count(*) from public.external_invoices v where v.fiscal_status='cancelled' and v.issue_date between from_date and to_date and (v.external_number is not null or exists(select 1 from public.accounting_fiscal_documents f where f.source_type='sales_invoice' and f.source_id=v.id)) and not exists(select 1 from public.accounting_fiscal_cancellations x where x.source_invoice_id=v.id)));
end $$;
revoke all on function private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;

create function private.gama_ec_tax_drafts(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();cfg public.company_settings;review jsonb;rows103 jsonb;vat_out numeric;vat_in numeric;received_vat numeric;retained_vat numeric;factor numeric:=coalesce((p_data->>'credit_factor')::numeric,1);previous_credit numeric:=coalesce((p_data->>'previous_credit')::numeric,0);d1 date:=(p_data->>'from')::date;d2 date:=(p_data->>'to')::date;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) or (coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false)) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if d1 is null or d2 is null or d1<>date_trunc('month',d1)::date or d2<>(date_trunc('month',d1)+interval '1 month -1 day')::date then raise exception 'FULL_MONTH_REQUIRED';end if;
 if factor::text in ('NaN','Infinity','-Infinity') or factor not between 0 and 1 or previous_credit::text in ('NaN','Infinity','-Infinity') or previous_credit<0 then raise exception 'INVALID_TAX_CREDIT';end if;
 select * into cfg from public.company_settings where id;review:=private.gama_accounting_ec_read('fiscal_review',p_data);
 select coalesce(sum(l.credit-l.debit) filter(where l.account_id=cfg.tax_collected_account_id),0),coalesce(sum(l.debit-l.credit) filter(where l.account_id=cfg.tax_deductible_account_id),0) into vat_out,vat_in
 from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where e.status in ('posted','reversed') and e.entry_date between d1 and d2 and e.source_type<>'withholding' and not exists(select 1 from public.accounting_entries original where original.id=e.reversal_of and original.source_type='withholding');
 select coalesce(sum(round((x->>'base')::numeric*(x->>'rate')::numeric/100,2)) filter(where w.side='customer' and x->>'tax_kind'='vat'),0),coalesce(sum(round((x->>'base')::numeric*(x->>'rate')::numeric/100,2)) filter(where w.side='supplier' and x->>'tax_kind'='vat'),0) into received_vat,retained_vat from public.accounting_withholdings w cross join lateral jsonb_array_elements(w.lines)x where w.status='posted' and w.issued_on between d1 and d2;
 select coalesce(jsonb_agg(to_jsonb(z) order by code),'[]') into rows103 from(select x->>'code' code,sum((x->>'base')::numeric) base,sum(round((x->>'base')::numeric*(x->>'rate')::numeric/100,2)) withheld,count(distinct w.id) documents from public.accounting_withholdings w cross join lateral jsonb_array_elements(w.lines)x where w.status='posted' and w.side='supplier' and x->>'tax_kind'='income' and w.issued_on between d1 and d2 group by x->>'code')z;
 return jsonb_build_object('from',d1,'to',d2,'status','draft_not_submitted','review',review,'form103',jsonb_build_object('rows',rows103,'total',coalesce((select sum((x->>'withheld')::numeric) from jsonb_array_elements(rows103)x),0)),
 'form104',jsonb_build_object('ledger_collected',vat_out,'ledger_deductible',vat_in,'credit_factor',factor,'deductible_credit',round(vat_in*factor,2),'received_vat',received_vat,'previous_credit',previous_credit,'own_vat_payable',greatest(vat_out-round(vat_in*factor,2)-received_vat-previous_credit,0),'credit_next_period',greatest(round(vat_in*factor,2)+received_vat+previous_credit-vat_out,0),'supplier_vat_withheld_payable',retained_vat));
end $$;
revoke all on function private.gama_ec_tax_drafts(jsonb) from public,anon;
grant execute on function private.gama_ec_tax_drafts(jsonb) to authenticated;
create function public.gama_ec_tax_drafts(p_data jsonb) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_ec_tax_drafts(p_data)$$;
revoke all on function public.gama_ec_tax_drafts(jsonb) from public,anon;
grant execute on function public.gama_ec_tax_drafts(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004233005','ec_ats_and_tax_drafts','5441bb9fcacdab06eb1d45f4d6c55dfbb6238f675bc7633ad9fab2c1aa7741bd','5441bb9fcacdab06eb1d45f4d6c55dfbb6238f675bc7633ad9fab2c1aa7741bd','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261004234447_ec_credit_identity_and_aging.sql; SHA256 a9511d5cc27af6606194d273309a04c7f07b5910762213acbe32bb4de061a993
-- Canonical remaining maturities include credits, withholding and adjustments.
create function private.gama_customer_dues(p_customer uuid default null,p_ids uuid[] default null) returns table(document_id uuid,number text,customer_id uuid,customer_name text,email text,phone text,identification text,issue_date date,due_date date,amount numeric,balance numeric,"position" integer)
 language sql stable security definer set search_path='' as $$
 with docs as(select r.id,r.number,r.customer_id,r.customer_name,r.email,c.phone,r.identification,r.issue_date,r.due_date,r.total,r.balance from private.gama_receivables r join public.customers c on c.id=r.customer_id where r.payment_status<>'cancelled' and r.balance>0 and (p_customer is null or r.customer_id=p_customer) and (p_ids is null or r.id=any(p_ids))),
 scheduled as(select d.id document_id,d.number,d.customer_id,d.customer_name,d.email,d.phone,d.identification,d.issue_date,m.due_date,m.amount,
 greatest(0,least(m.amount,d.balance-coalesce(sum(m.amount) over(partition by d.id order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0)))
 +case when row_number() over(partition by d.id order by m.due_date desc,m.position desc)=1 then greatest(0,d.balance-sum(m.amount) over(partition by d.id)) else 0 end balance,m.position
 from docs d join public.accounting_maturities m on m.side='customer' and m.invoice_id=d.id)
 select * from scheduled union all select d.id,d.number,d.customer_id,d.customer_name,d.email,d.phone,d.identification,d.issue_date,d.due_date,d.total,d.balance,1 from docs d where not exists(select 1 from public.accounting_maturities m where m.side='customer' and m.invoice_id=d.id)
$$;
revoke all on function private.gama_customer_dues(uuid,uuid[]) from public,anon,authenticated;

create function private.gama_credit_snapshot(p_customer uuid,p_order uuid default null) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c public.customers;today date:=(now() at time zone private.erp_timezone())::date;receivable numeric;commitment numeric;overdue jsonb;begin
 select * into c from public.customers where id=p_customer;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select coalesce(sum(balance),0),coalesce(jsonb_agg(jsonb_build_object('invoice_id',document_id,'number',number,'due_date',coalesce(due_date,issue_date),'balance',balance) order by coalesce(due_date,issue_date),document_id,"position") filter(where coalesce(due_date,issue_date)<today and balance>0),'[]') into receivable,overdue from private.gama_customer_dues(p_customer);
 select coalesce(sum(greatest(0,coalesce((select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) from public.sales_order_lines l where l.order_id=o.id),0)-coalesce((select sum(i.total) from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0))),0) into commitment from public.sales_orders o where (o.customer_id=p_customer and o.status='confirmed') or o.id=p_order;
 return jsonb_build_object('today',today,'customer_id',c.id,'credit_limit',c.credit_limit,'hold_reason',c.credit_hold_reason,'receivable',receivable,'commitment',commitment,'exposure',receivable+commitment,'overdue',overdue,
 'blocked',nullif(c.credit_hold_reason,'') is not null or jsonb_array_length(overdue)>0 or (c.credit_limit is not null and receivable+commitment>c.credit_limit));
end $$;
revoke all on function private.gama_credit_snapshot(uuid,uuid) from public,anon,authenticated;

alter function private.erp_document_fingerprint(text,uuid) rename to erp_document_fingerprint_before_ec_credit;
create function private.erp_document_fingerprint(p_module text,p_id uuid) returns text language plpgsql volatile security definer set search_path='' as $$
declare base text;c uuid;begin
 base:=private.erp_document_fingerprint_before_ec_credit(p_module,p_id);
 if p_module<>'credit' then return base;end if;
 select customer_id into c from public.sales_orders where id=p_id;
 return md5(jsonb_build_object('document',base,'credit',private.gama_credit_snapshot(c,p_id))::text);
end $$;
revoke all on function private.erp_document_fingerprint(text,uuid) from public,anon,authenticated;

-- Keep quote/purchase controls, and replace only the credit part of their guard.
alter function private.erp_commercial_guard() rename to erp_commercial_guard_before_ec_credit;
create function private.gama_enforce_customer_credit(p_customer uuid,p_order uuid,p_allow_exception boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare s jsonb;begin
 perform 1 from public.customers where id=p_customer for update;
 s:=private.gama_credit_snapshot(p_customer,p_order);
 if coalesce((s->>'blocked')::boolean,false) and not (p_allow_exception and exists(select 1 from public.erp_approvals a where a.module='credit' and a.document_id=p_order and a.status='approved' and a.fingerprint=private.erp_document_fingerprint('credit',p_order))) then raise exception 'APPROVAL_REQUIRED:credit:%',p_order;end if;
end $$;
revoke all on function private.gama_enforce_customer_credit(uuid,uuid,boolean) from public,anon,authenticated;
drop trigger erp_commercial_guard on public.sales_orders;
create function private.gama_customer_credit_order_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and (tg_op='INSERT' or old.status='draft' or new.customer_id is distinct from old.customer_id) then
 perform private.gama_enforce_customer_credit(new.customer_id,new.id,tg_op='UPDATE' and new.customer_id is not distinct from old.customer_id);end if;
 return new;end $$;
revoke all on function private.gama_customer_credit_order_guard() from public,anon,authenticated;
create trigger erp_commercial_guard before insert or update on public.sales_orders for each row execute function private.gama_customer_credit_order_guard();
create function private.gama_customer_credit_line_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare order_id uuid:=case when tg_op='DELETE' then old.order_id else new.order_id end;o public.sales_orders;begin
 if tg_op='UPDATE' and new.order_id is not distinct from old.order_id and new.quantity is not distinct from old.quantity and new.unit_price is not distinct from old.unit_price and new.tax_rate is not distinct from old.tax_rate then return null;end if;
 select * into o from public.sales_orders where id=order_id for update;
 if o.status='confirmed' then perform private.gama_enforce_customer_credit(o.customer_id,o.id);end if;return null;end $$;
revoke all on function private.gama_customer_credit_line_guard() from public,anon,authenticated;
create constraint trigger ec_credit_line_guard after insert or update or delete on public.sales_order_lines deferrable initially immediate for each row execute function private.gama_customer_credit_line_guard();

create function private.gama_customer_credit_status(p_customer uuid,p_order uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not (private.erp_module_allowed('sales-orders',array['administrador','comercial']) or private.erp_module_allowed('clients',array['administrador','comercial']) or private.erp_module_allowed('payments',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_order is not null and not exists(select 1 from public.sales_orders where id=p_order and customer_id=p_customer) then raise exception 'ORDER_CUSTOMER_MISMATCH';end if;
 return private.gama_credit_snapshot(p_customer,p_order);end $$;
revoke all on function private.gama_customer_credit_status(uuid,uuid) from public,anon;
grant execute on function private.gama_customer_credit_status(uuid,uuid) to authenticated;
create function public.gama_customer_credit_status(p_customer uuid,p_order uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_customer_credit_status(p_customer,p_order)$$;
revoke all on function public.gama_customer_credit_status(uuid,uuid) from public,anon;
grant execute on function public.gama_customer_credit_status(uuid,uuid) to authenticated;

create function private.gama_customer_aging(p_customer uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;rows jsonb;summary jsonb;c public.customers;lim integer:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,30)));off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));search text:=left(coalesce(p_data->>'search',''),120);begin
 if auth.uid() is null or not private.erp_mfa_ok() or not (private.erp_module_allowed('payments',array['administrador','comercial']) or private.erp_module_allowed('clients',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if coalesce((p_data->>'export')::boolean,false) and not (private.erp_action_allowed('payments','export') or private.erp_action_allowed('clients','export')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_customer is not null then
 select * into c from public.customers where id=p_customer;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by due_date nulls last,document_id,"position"),'[]') into rows from private.gama_customer_dues(p_customer)x where balance>0;
 return jsonb_build_object('today',today,'company',(select jsonb_build_object('legal_name',legal_name,'tax_id',tax_id,'currency',currency,'address',address) from public.company_settings where id),'customer',jsonb_build_object('id',c.id,'name',c.name,'identification',c.identification,'email',c.email,'phone',c.phone),'rows',rows,'total',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(rows)x),0),'overdue',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(rows)x where (x->>'due_date')::date<today),0));
 end if;
 with dues as(select * from private.gama_customer_dues(null)),groups as(select customer_id id,customer_name name,email,phone,
 sum(balance) balance,sum(balance) filter(where due_date>=today) current,sum(balance) filter(where due_date between today-30 and today-1) days_0_30,sum(balance) filter(where due_date between today-60 and today-31) days_31_60,sum(balance) filter(where due_date between today-90 and today-61) days_61_90,sum(balance) filter(where due_date<today-90) days_over_90,sum(balance) filter(where due_date is null) missing_due,min(due_date) oldest_due
 from dues where balance>0 group by customer_id,customer_name,email,phone),filtered as(select * from groups where name ilike '%'||search||'%')
 select jsonb_build_object('today',today,'total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(z) order by oldest_due nulls last,id) from(select * from filtered order by oldest_due nulls last,id offset off limit lim)z),'[]'),'balance',coalesce((select sum(balance) from filtered),0),'overdue',coalesce((select sum(coalesce(days_0_30,0)+coalesce(days_31_60,0)+coalesce(days_61_90,0)+coalesce(days_over_90,0)) from filtered),0)) into summary;return summary;
end $$;
revoke all on function private.gama_customer_aging(uuid,jsonb) from public,anon;
grant execute on function private.gama_customer_aging(uuid,jsonb) to authenticated;
create function public.gama_customer_aging(p_customer uuid default null,p_data jsonb default '{}') returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_customer_aging(p_customer,p_data)$$;
revoke all on function public.gama_customer_aging(uuid,jsonb) from public,anon;
grant execute on function public.gama_customer_aging(uuid,jsonb) to authenticated;

-- Sales displays the same balance as accounting, in one bounded batch per page.
create function private.gama_sales_invoice_balances(p_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('sales-orders',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if coalesce(cardinality(p_ids),0) not between 1 and 100 then raise exception 'INVOICE_BATCH_REQUIRED';end if;
 return (with dates as(select document_id,min(due_date) due_date from private.gama_customer_dues(null,p_ids) where balance>0 group by document_id) select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'paid',r.paid,'balance',case when r.payment_status='cancelled' then 0 else r.balance end,'payment_status',r.payment_status,'due_date',d.due_date)),'[]') from private.gama_receivables r left join dates d on d.document_id=r.id where r.id=any(p_ids));
end $$;
revoke all on function private.gama_sales_invoice_balances(uuid[]) from public,anon;
grant execute on function private.gama_sales_invoice_balances(uuid[]) to authenticated;
create function public.gama_sales_invoice_balances(p_ids uuid[]) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_sales_invoice_balances(p_ids)$$;
revoke all on function public.gama_sales_invoice_balances(uuid[]) from public,anon;
grant execute on function public.gama_sales_invoice_balances(uuid[]) to authenticated;

-- Checks apply when an Ecuadorian identification is created or changed. Existing
-- historical records can be edited without silently changing their identity.
alter table public.customers add column identification_kind text not null default 'auto' check(identification_kind in ('auto','cedula','ruc_natural','ruc_company','ruc_public','ruc_foreign','foreign_document','consumer'));
alter table public.suppliers add column identification_kind text not null default 'auto' check(identification_kind in ('auto','cedula','ruc_natural','ruc_company','ruc_public','ruc_foreign','foreign_document','consumer'));
create index customer_identification_normalized on public.customers(upper(regexp_replace(identification,'[[:space:]-]','','g'))) where identification is not null;
create index supplier_identification_normalized on public.suppliers(upper(regexp_replace(tax_id,'[[:space:]-]','','g'))) where tax_id is not null;
create function private.gama_ec_identification_valid(p_value text,p_kind text default 'auto') returns boolean language plpgsql immutable set search_path='' as $$
declare v text:=upper(regexp_replace(btrim(p_value),'[[:space:]-]','','g'));kind text:=p_kind;province integer;n integer:=0;x integer;i integer;begin
 if v is null or v='' then return false;end if;
 if kind='foreign_document' then return length(v) between 3 and 20 and v ~ '^[A-Z0-9]+$';end if;
 if kind='consumer' then return v='9999999999999';end if;
 if v !~ '^[0-9]+$' then return false;end if;
 if kind='auto' then kind:=case when length(v)=10 then 'cedula' when length(v)=13 and substring(v,3,1)::integer<6 then 'ruc_natural' when length(v)=13 then 'ruc_company' else 'invalid' end;end if;
 if kind in ('ruc_company','ruc_public','ruc_foreign') then return length(v)=13 and right(v,3)='001' and v<>'0000000000001';end if;
 if kind not in ('cedula','ruc_natural') or length(v)<>(case when kind='cedula' then 10 else 13 end) or (kind='ruc_natural' and right(v,3)<>'001') then return false;end if;
 province:=left(v,2)::integer;if province not between 1 and 24 and province<>30 then return false;end if;
 if substring(v,3,1)::integer>=6 then return false;end if;
 for i in 1..9 loop x:=substring(v,i,1)::integer*case when i%2=1 then 2 else 1 end;if x>9 then x:=x-9;end if;n:=n+x;end loop;
 return (10-n%10)%10=substring(v,10,1)::integer;
end $$;
revoke all on function private.gama_ec_identification_valid(text,text) from public,anon,authenticated;
create function private.gama_partner_identification_guard() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare v text;previous text;kind text;country text;duplicate boolean;begin
 if not exists(select 1 from public.company_settings where id and configured and country='EC') then return new;end if;
 v:=case when tg_table_name='customers' then to_jsonb(new)->>'identification' else to_jsonb(new)->>'tax_id' end;kind:=new.identification_kind;country:=upper(btrim(coalesce(new.country,'')));
 if tg_op='UPDATE' then previous:=case when tg_table_name='customers' then to_jsonb(old)->>'identification' else to_jsonb(old)->>'tax_id' end;if v is not distinct from previous and kind is not distinct from old.identification_kind and new.country is not distinct from old.country then return new;end if;end if;
 if nullif(btrim(v),'') is null then return new;end if;
 v:=upper(regexp_replace(btrim(v),'[[:space:]-]','','g'));
 if country in ('','EC','ECUADOR','ECU') and not private.gama_ec_identification_valid(v,kind) then raise exception 'EC_IDENTIFICATION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('partner-identification:'||tg_table_name||':'||v,0));
 if tg_table_name='customers' then select exists(select 1 from public.customers where upper(regexp_replace(identification,'[[:space:]-]','','g'))=v and id<>new.id) into duplicate;new.identification:=v;
 else select exists(select 1 from public.suppliers where upper(regexp_replace(tax_id,'[[:space:]-]','','g'))=v and id<>new.id) into duplicate;new.tax_id:=v;end if;
 if duplicate then raise exception 'PARTNER_IDENTIFICATION_DUPLICATE';end if;return new;
end $$;
revoke all on function private.gama_partner_identification_guard() from public,anon,authenticated;
create trigger ec_partner_identification before insert or update on public.customers for each row execute function private.gama_partner_identification_guard();
create trigger ec_partner_identification before insert or update on public.suppliers for each row execute function private.gama_partner_identification_guard();

-- Approval is an administrator validation action in the affected module.
alter function private.gama_approval_action(text,jsonb) rename to gama_approval_action_before_ec_credit;
revoke all on function private.gama_approval_action_before_ec_credit(text,jsonb) from authenticated;
create function private.gama_approval_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare module text;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='decide' then select a.module into module from public.erp_approvals a where a.id=(p_data->>'id')::uuid;module:=case when module='credit' then 'sales-orders' else module end;
 if not private.erp_module_allowed(module,array['administrador']) or not private.erp_action_allowed(module,'validate') then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;end if;
 return private.gama_approval_action_before_ec_credit(p_action,p_data);end $$;
revoke all on function private.gama_approval_action(text,jsonb) from public,anon;
grant execute on function private.gama_approval_action(text,jsonb) to authenticated;

-- Changes to receivables serialize with credit decisions for this customer.
create function private.gama_customer_debt_lock() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb:=to_jsonb(new);invoice uuid;customer uuid;begin
 if tg_table_name='external_invoices' then select customer_id into customer from public.sales_orders where id=(j->>'order_id')::uuid;
 else invoice:=nullif(j->>'invoice_id','')::uuid;select o.customer_id into customer from public.external_invoices v join public.sales_orders o on o.id=v.order_id where v.id=invoice;end if;
 if customer is not null then perform 1 from public.customers where id=customer for update;end if;return new;end $$;
revoke all on function private.gama_customer_debt_lock() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['external_invoices','external_invoice_payments','return_credits','accounting_withholdings','accounting_adjustments'] loop
 execute format('create trigger aa_ec_customer_debt_lock before insert or update on public.%I for each row execute function private.gama_customer_debt_lock()',t);end loop;end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261004234447','ec_credit_identity_and_aging','a9511d5cc27af6606194d273309a04c7f07b5910762213acbe32bb4de061a993','a9511d5cc27af6606194d273309a04c7f07b5910762213acbe32bb4de061a993','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005001842_ec_bank_statement_invoice_matching.sql; SHA256 77616734c02b563b6a4ec0a2443124c09c005be1f5106d83d1e72f107ab1c734
-- Review a statement row, record one real receipt, allocate it, and match cash once.
create table public.bank_invoice_settlements (
 bank_id uuid primary key references public.bank_transactions(id),request_key uuid not null unique,
 invoice_id uuid not null references public.external_invoices(id),receipt_id uuid not null references public.customer_receipts(id),
 payment_id uuid not null references public.external_invoice_payments(id),match_group_id uuid not null references public.bank_match_groups(id),
 created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now()
);
create index bank_invoice_settlement_invoice on public.bank_invoice_settlements(invoice_id);
create index bank_invoice_settlement_receipt on public.bank_invoice_settlements(receipt_id);
create index bank_invoice_settlement_payment on public.bank_invoice_settlements(payment_id);
create index bank_invoice_settlement_group on public.bank_invoice_settlements(match_group_id);
create index bank_invoice_settlement_actor on public.bank_invoice_settlements(created_by);
alter table public.bank_invoice_settlements enable row level security;
revoke all on public.bank_invoice_settlements from public,anon,authenticated;
grant select on public.bank_invoice_settlements to authenticated;
create policy bank_invoice_settlement_read on public.bank_invoice_settlements for select to authenticated using(private.erp_mfa_ok() and private.erp_module_allowed('accounting',array['administrador','comercial']) and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false));
create trigger erp_audit_capture after insert or update or delete on public.bank_invoice_settlements for each row execute function private.erp_audit_capture();

create function private.gama_bank_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();b public.bank_transactions;settlement public.bank_invoice_settlements;inv record;receipt jsonb;payment jsonb;grp jsonb;group_id uuid;acc uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;iid uuid:=nullif(p_data->>'invoice_id','')::uuid;rows jsonb;search text:=left(btrim(coalesce(p_data->>'search','')),120);x jsonb;amount numeric;cfg public.company_settings;command private.command_receipts;payload jsonb;result jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='import' then
 if not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into cfg from public.company_settings where id;
 if not exists(select 1 from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and account_id is not null and currency=cfg.currency and kind in ('bank','card')) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 1000 then raise exception 'BANK_IMPORT_LINES_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'rows') loop
 if jsonb_typeof(x->'amount') is distinct from 'number' or coalesce(x->>'value_date','') !~ '^\d{4}-\d{2}-\d{2}$' or length(coalesce(x->>'reference',''))>180 or length(coalesce(x->>'description',''))>300 then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
 amount:=(x->>'amount')::numeric;if amount::text in ('NaN','Infinity','-Infinity') or amount=0 or abs(amount)>999999999999.99 or amount<>round(amount,2) or (x->>'value_date')::date>(now() at time zone private.erp_timezone())::date then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
 end loop;
 payload:=jsonb_build_object('hash',md5((p_data-'request_key')::text));
 perform pg_advisory_xact_lock(hashtextextended('bank-statement-import:'||key::text,0));
 select * into command from private.command_receipts where domain='bank-statement-import' and request_key=key;
 if found then if command.actor_id<>auth.uid() or command.payload is distinct from payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return command.result;end if;
 result:=private.gama_accounting_action('bank_import',p_data);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('bank-statement-import',key,auth.uid(),payload,result);return result;
 end if;
 select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 if p_action='suggest' then
 if b.status<>'unmatched' then return jsonb_build_object('bank',to_jsonb(b),'matches','[]'::jsonb);end if;
 with cash as(
 select 'customer_payment'::text kind,p.id,concat_ws(' · ',r.number,r.customer_name,p.reference) label,p.paid_at date,p.amount from public.external_invoice_payments p join private.gama_receivables r on r.id=p.invoice_id where p.financial_account_id=b.financial_account_id and p.status='confirmed' and p.receipt_id is null
 union all select 'customer_receipt',p.id,concat_ws(' · ',c.name,p.reference),p.paid_at,p.amount from public.customer_receipts p join public.customers c on c.id=p.customer_id where p.financial_account_id=b.financial_account_id and p.status='confirmed'
 union all select 'supplier_payment',p.id,concat_ws(' · ',r.number,r.supplier_name,p.reference),p.paid_at,-p.amount from public.supplier_invoice_payments p join private.gama_payables r on r.id=p.supplier_invoice_id where p.financial_account_id=b.financial_account_id and p.status='confirmed'
 union all select 'expense',p.id,concat_ws(' · ',p.reference,p.description),p.expense_date,-p.amount_total from public.expenses p where p.financial_account_id=b.financial_account_id and p.status='posted'),
 available as(select 'cash'::text type,s.kind,s.id,s.label,s.date,s.amount,null::numeric balance,0 score from cash s where s.amount=b.amount and abs(s.date-b.value_date)<=14
 and not exists(select 1 from public.reconciliations rc where rc.match_type=s.kind and rc.match_id=s.id)
 and not exists(select 1 from public.bank_match_sources l join public.bank_match_groups g on g.id=l.group_id where g.cancelled_at is null and l.kind=s.kind and l.source_id=s.id)),
 invoices as(select 'invoice'::text type,'customer_invoice'::text kind,r.id,concat_ws(' · ',r.number,r.customer_name) label,r.issue_date date,b.amount,r.balance,
 case when concat_ws(' ',b.reference,b.description) ilike '%'||r.number||'%' then 1 when r.balance=b.amount then 2 else 3 end score from private.gama_receivables r join public.sales_orders o on o.id=r.order_id join public.external_invoices i on i.id=r.id
 where b.amount>0 and r.balance>=b.amount and r.payment_status not in ('paid','cancelled') and i.fiscal_status not in ('cancelled','rejected') and o.status='confirmed' and not exists(select 1 from public.bank_invoice_settlements s where s.bank_id=b.id)
 and (search<>'' and concat_ws(' ',r.number,r.customer_name,r.identification,i.external_number) ilike '%'||search||'%'
 or search='' and (r.balance=b.amount or concat_ws(' ',b.reference,b.description) ilike '%'||r.number||'%' or nullif(i.external_number,'') is not null and concat_ws(' ',b.reference,b.description) ilike '%'||i.external_number||'%' or length(r.customer_name)>=4 and concat_ws(' ',b.reference,b.description) ilike '%'||r.customer_name||'%')))
 select coalesce(jsonb_agg(to_jsonb(z) order by score,date,id),'[]') into rows from(select * from available union all select * from invoices order by score,date,id limit 50)z;
 return jsonb_build_object('bank',to_jsonb(b),'matches',rows);
 end if;
 if not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate') then raise exception 'VALIDATE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||b.financial_account_id::text,0));
 select * into b from public.bank_transactions where id=b.id for update;
 if p_action='undo' then
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 select g.id into group_id from public.bank_match_banks l join public.bank_match_groups g on g.id=l.group_id where l.bank_id=b.id and g.cancelled_at is null;
 if group_id is not null then return private.gama_bank_match('cancel',jsonb_build_object('account_id',b.financial_account_id,'id',group_id,'reason',p_data->>'reason'));end if;
 return private.gama_accounting_action('reconcile_undo',jsonb_build_object('id',b.id));
 elsif p_action='match_source' then
 return private.gama_bank_match('apply',jsonb_build_object('request_key',key,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',jsonb_build_array(jsonb_build_object('kind',p_data->>'kind','id',p_data->>'source_id')),'note',coalesce(p_data->>'note','')));
 elsif p_action<>'settle' then raise exception 'INVALID_ACTION';end if;
 if key is null or iid is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-invoice:'||key::text,0));
 select * into settlement from public.bank_invoice_settlements where request_key=key;
 if found and (settlement.bank_id<>b.id or settlement.invoice_id<>iid) then raise exception 'REQUEST_KEY_CONFLICT';end if;
 select * into settlement from public.bank_invoice_settlements where bank_id=b.id;
 if found then if settlement.bank_id<>b.id or settlement.invoice_id<>iid then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(settlement)||jsonb_build_object('reused',true);end if;
 if b.status<>'unmatched' or b.amount<=0 or b.amount::text in ('NaN','Infinity','-Infinity') then raise exception 'BANK_ALREADY_MATCHED';end if;
 if not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') or not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
 select o.customer_id into acc from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=iid;
 perform 1 from public.customers where id=acc for update;perform 1 from public.external_invoices where id=iid for update;
 select r.* into inv from private.gama_receivables r join public.external_invoices i on i.id=r.id where r.id=iid and exists(select 1 from public.sales_orders o where o.id=r.order_id and o.status='confirmed') and r.payment_status<>'cancelled' and i.fiscal_status not in ('cancelled','rejected');
 if not found or inv.balance<b.amount then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 receipt:=private.gama_receipt_action('receive',jsonb_build_object('request_key',b.id,'customer_id',inv.customer_id,'financial_account_id',b.financial_account_id,'amount',b.amount,'paid_at',b.value_date,'method','transfer','reference',coalesce(nullif(b.reference,''),inv.number),'notes','Cobro revisado desde extracto bancario · '||inv.number));
 payment:=private.gama_receipt_action('allocate',jsonb_build_object('request_key',md5('bank-invoice-payment:'||b.id::text)::uuid,'id',receipt->>'id','invoice_id',iid,'amount',b.amount));
 grp:=private.gama_bank_match('apply',jsonb_build_object('request_key',md5('bank-invoice-match:'||b.id::text)::uuid,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',jsonb_build_array(jsonb_build_object('kind','customer_receipt','id',receipt->>'id')),'note','Cobro y conciliación · '||inv.number));
 insert into public.bank_invoice_settlements(bank_id,request_key,invoice_id,receipt_id,payment_id,match_group_id) values(b.id,key,iid,(receipt->>'id')::uuid,(payment->>'id')::uuid,(grp->>'id')::uuid) returning * into settlement;
 return to_jsonb(settlement);
end $$;
revoke all on function private.gama_bank_invoice_action(text,jsonb) from public,anon;
grant execute on function private.gama_bank_invoice_action(text,jsonb) to authenticated;
create function public.gama_bank_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_bank_invoice_action(p_action,p_data)$$;
revoke all on function public.gama_bank_invoice_action(text,jsonb) from public,anon;
grant execute on function public.gama_bank_invoice_action(text,jsonb) to authenticated;

-- The compatible legacy import cannot introduce non-finite statement amounts.
create function private.gama_bank_statement_amount_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.amount::text in ('NaN','Infinity','-Infinity') then raise exception 'BANK_IMPORT_ROW_INVALID';end if;return new;end $$;
revoke all on function private.gama_bank_statement_amount_guard() from public,anon,authenticated;
create trigger bank_statement_amount_guard before insert or update on public.bank_transactions for each row execute function private.gama_bank_statement_amount_guard();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005001842','ec_bank_statement_invoice_matching','77616734c02b563b6a4ec0a2443124c09c005be1f5106d83d1e72f107ab1c734','77616734c02b563b6a4ec0a2443124c09c005be1f5106d83d1e72f107ab1c734','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
