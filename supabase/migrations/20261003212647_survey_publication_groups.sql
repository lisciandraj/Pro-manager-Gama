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
