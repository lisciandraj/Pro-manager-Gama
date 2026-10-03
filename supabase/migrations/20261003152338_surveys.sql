-- Questionnaires are private; only explicit publication exposes their questions.
create table private.surveys (
 id uuid primary key default gen_random_uuid(), title text not null check(length(btrim(title)) between 1 and 180),
 introduction text not null default '' check(length(introduction)<=4000), thanks text not null default '' check(length(thanks)<=1000),
 language text not null default 'es' check(language in ('es','fr','en')), state text not null default 'draft' check(state in ('draft','open','closed','archived')),
 questions jsonb not null default '[]', quiz boolean not null default false, pass_percent integer not null default 70 check(pass_percent between 0 and 100),
 token uuid not null default gen_random_uuid() unique, invitation_only boolean not null default false, closes_at timestamptz,
 version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null
);
create index surveys_created_actor on private.surveys(created_by);
create index surveys_updated_actor on private.surveys(updated_by);
create table private.survey_invitations (
 id uuid primary key default gen_random_uuid(),survey_id uuid not null references private.surveys(id),token uuid not null default gen_random_uuid() unique,
 customer_id uuid references public.customers(id) on delete set null,supplier_id uuid references public.suppliers(id) on delete set null,
 contact_id uuid references public.crm_contacts(id) on delete set null, label text not null, revoked boolean not null default false,
 created_at timestamptz not null default now(),created_by uuid references auth.users(id) on delete set null
);
create index survey_invitations_survey on private.survey_invitations(survey_id);
create index survey_invitations_customer on private.survey_invitations(customer_id);
create index survey_invitations_supplier on private.survey_invitations(supplier_id);
create index survey_invitations_contact on private.survey_invitations(contact_id);
create index survey_invitations_actor on private.survey_invitations(created_by);
create table private.survey_responses (
 id uuid primary key default gen_random_uuid(), survey_id uuid not null references private.surveys(id), invitation_id uuid unique references private.survey_invitations(id),
 request_key uuid not null unique, payload jsonb not null, answers jsonb not null, score integer, maximum integer,
 visitor_hash text not null, created_at timestamptz not null default now()
);
create index survey_responses_survey on private.survey_responses(survey_id,created_at desc,id);
create index survey_responses_visitor on private.survey_responses(visitor_hash,created_at desc);
alter table private.surveys enable row level security;
alter table private.survey_invitations enable row level security;
alter table private.survey_responses enable row level security;
revoke all on private.surveys,private.survey_invitations,private.survey_responses from public,anon,authenticated;
do $$declare src text;begin
 select pg_get_constraintdef(oid) into src from pg_constraint where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if strpos(src,'''website''::text')=0 then raise exception 'SURVEY_PERMISSION_ANCHOR';end if;
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||replace(src,'''website''::text','''website''::text, ''surveys''::text');
 src:=pg_get_functiondef('private.gama_save_action_permissions(text,jsonb,jsonb)'::regprocedure);
 if strpos(src,'''website'')')=0 then raise exception 'SURVEY_ACTION_ANCHOR';end if;
 execute replace(src,'''website'')','''website'',''surveys'')');
end $$;

create function private.survey_validate_questions(qs jsonb) returns void language plpgsql set search_path='' as $$
declare q jsonb;c jsonb;ids text[]:='{}';choices text[];correct text[];
begin
 if jsonb_typeof(qs) is distinct from 'array' or jsonb_array_length(qs)>60 or octet_length(qs::text)>60000 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
 for q in select value from jsonb_array_elements(qs) loop
  if jsonb_typeof(q) is distinct from 'object' or coalesce(q->>'id','') !~ '^[a-zA-Z0-9_-]{1,60}$' or (q->>'id')=any(ids)
   or coalesce(q->>'type','') not in ('section','text','textarea','single','multiple','number','date','datetime','rating')
   or length(btrim(coalesce(q->>'title',''))) not between 1 and 300 or length(coalesce(q->>'help',''))>1000
   or jsonb_typeof(q->'required') is distinct from 'boolean' then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  ids:=array_append(ids,q->>'id');
  if q->>'type' in ('single','multiple') then
   if jsonb_typeof(q->'choices') is distinct from 'array' or jsonb_array_length(q->'choices') not between 2 and 30 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   choices:='{}';for c in select value from jsonb_array_elements(q->'choices') loop
    if jsonb_typeof(c)<>'string' or length(btrim(c#>>'{}')) not between 1 and 180 or (c#>>'{}')=any(choices) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
    choices:=array_append(choices,c#>>'{}');
   end loop;
   if jsonb_typeof(q->'correct') is distinct from 'array' then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   correct:='{}';for c in select value from jsonb_array_elements(q->'correct') loop
    if jsonb_typeof(c)<>'string' or not (c#>>'{}')=any(choices) or (c#>>'{}')=any(correct) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
    correct:=array_append(correct,c#>>'{}');
   end loop;
   if q->>'type'='single' and cardinality(correct)>1 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  elsif coalesce(jsonb_array_length(q->'correct'),0)>0 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  if q->>'type'='number' then
   if q->>'min' is not null and (jsonb_typeof(q->'min')<>'number' or abs((q->>'min')::numeric)>1e12) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   if q->>'max' is not null and (jsonb_typeof(q->'max')<>'number' or abs((q->>'max')::numeric)>1e12) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   if (q->>'min')::numeric>(q->>'max')::numeric then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  end if;
 end loop;
end $$;
revoke all on function private.survey_validate_questions(jsonb) from public,anon,authenticated;

create function private.gama_surveys(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
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
   case when private.erp_module_allowed('contacts',array['administrador','comercial']) and (inv.contact_id is null or private.erp_module_allowed('crm',array['administrador','comercial'])) then inv.label else null end contact_label
   from private.survey_responses r left join private.survey_invitations inv on inv.id=r.invitation_id where r.survey_id=sid order by r.created_at,r.id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='invitations' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select coalesce(jsonb_agg(x),'[]') into items from (select inv.id,inv.token,inv.label,inv.revoked,exists(select 1 from private.survey_responses r where r.invitation_id=inv.id) answered from private.survey_invitations inv where survey_id=sid and (contact_id is null or private.erp_module_allowed('crm',array['administrador','comercial'])) order by created_at desc,id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',(select count(*) from private.survey_invitations where survey_id=sid and (contact_id is null or private.erp_module_allowed('crm',array['administrador','comercial']))));
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
  end if;
  if label is null then raise exception 'SURVEY_INVALID_CONTACT';end if;
  select * into i from private.survey_invitations where survey_id=sid and not revoked and (case p_data->>'kind' when 'customer' then customer_id when 'supplier' then supplier_id else contact_id end)=target;
  if not found then insert into private.survey_invitations(survey_id,customer_id,supplier_id,contact_id,label,created_by) values(sid,case when p_data->>'kind'='customer' then target end,case when p_data->>'kind'='supplier' then target end,case when p_data->>'kind'='contact' then target end,label,actor) returning * into i;end if;return to_jsonb(i);
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
   if not exists(select 1 from jsonb_array_elements(s.questions) q where q->>'type'<>'section') or (s.closes_at is not null and s.closes_at<=now()) then raise exception 'SURVEY_CANNOT_PUBLISH';end if;
   if s.quiz and not exists(select 1 from jsonb_array_elements(s.questions) q where jsonb_array_length(coalesce(q->'correct','[]'))>0) then raise exception 'SURVEY_CANNOT_PUBLISH';end if;
  elsif not (p_data->>'state'='closed' and s.state='open' or p_data->>'state'='archived' and s.state in ('draft','closed')) then raise exception 'SURVEY_INVALID_STATE';end if;
  update private.surveys set state=p_data->>'state',version=version+1,updated_at=now(),updated_by=actor where id=sid returning * into s;
 else raise exception 'SURVEY_INVALID_ACTION';end if;
 return to_jsonb(s);
end $$;
revoke all on function private.gama_surveys(text,jsonb) from public,anon;
grant execute on function private.gama_surveys(text,jsonb) to authenticated;
create function public.gama_surveys(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_surveys(p_action,p_data)$$;
revoke all on function public.gama_surveys(text,jsonb) from public,anon;
grant execute on function public.gama_surveys(text,jsonb) to authenticated;

create function storefront_api.gama_survey(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.surveys;i private.survey_invitations;r private.survey_responses;q jsonb;a jsonb;v jsonb;answers jsonb;qs jsonb;key text;txt text;
 v_token uuid;req uuid;secret text;visitor text;payload jsonb;score integer:=0;maximum integer:=0;chosen text[];correct text[];
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>70000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if exists(select 1 from public.app_modules where id='surveys' and not enabled) then raise exception 'SURVEY_UNAVAILABLE';end if;
 v_token:=nullif(p_data->>'token','')::uuid;
 select * into i from private.survey_invitations where survey_invitations.token=v_token and not revoked;
 if found then select * into s from private.surveys where id=i.survey_id for update;
 else select * into s from private.surveys where surveys.token=v_token and not invitation_only for update;end if;
 if s.id is null or s.state<>'open' or s.closes_at<=now() then raise exception 'SURVEY_UNAVAILABLE';end if;
 if p_action='get' then
  select coalesce(jsonb_agg(item-'correct'),'[]') into qs from jsonb_array_elements(s.questions) item;
  return jsonb_build_object('title',s.title,'introduction',s.introduction,'language',s.language,'questions',qs,'quiz',s.quiz,'personal',i.id is not null,'answered',exists(select 1 from private.survey_responses where invitation_id=i.id));
 elsif p_action<>'submit' then raise exception 'SURVEY_INVALID_ACTION';end if;
 select website_public_connection.token into secret from private.website_public_connection where id;
 if secret is null or coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'SURVEY_SERVER_KEY_REQUIRED';end if;
 if (p_data->>'consent') is distinct from 'true' or coalesce(p_data->>'website','')<>'' then raise exception 'SURVEY_INVALID_DATA';end if;
 visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'SURVEY_INVALID_DATA';end if;visitor:=md5(secret||visitor);
 req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'SURVEY_INVALID_DATA';end if;
 payload:=p_data-'visitor'-'request_key'-'website';
 perform pg_advisory_xact_lock(hashtextextended('survey-request:'||req,0));
 select * into r from private.survey_responses where request_key=req;
 if found then
  if r.payload is distinct from payload then raise exception 'SURVEY_REQUEST_KEY_REUSED';end if;
 else
  if i.id is not null and exists(select 1 from private.survey_responses where invitation_id=i.id) then raise exception 'SURVEY_ALREADY_ANSWERED';end if;
  perform pg_advisory_xact_lock(hashtextextended('survey-visitor:'||visitor,0));
  if (select count(*) from private.survey_responses where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=20 or (select count(*) from private.survey_responses where survey_id=s.id and created_at>now()-interval '1 day')>=3000 then raise exception 'SURVEY_RATE_LIMIT';end if;
  answers:=p_data->'answers';if jsonb_typeof(answers) is distinct from 'object' then raise exception 'SURVEY_INVALID_ANSWER';end if;
  for key in select jsonb_object_keys(answers) loop if not exists(select 1 from jsonb_array_elements(s.questions) x where x->>'id'=key and x->>'type'<>'section') then raise exception 'SURVEY_INVALID_ANSWER';end if;end loop;
  for q in select value from jsonb_array_elements(s.questions) loop
   if q->>'type'='section' then continue;end if;
   a:=answers->(q->>'id');txt:=a#>>'{}';
   if coalesce(jsonb_array_length(q->'correct'),0)>0 then maximum:=maximum+1;end if;
   if a is null or a='null' or a='""' or a='[]' then
    if (q->>'required')::boolean then raise exception 'SURVEY_REQUIRED_ANSWER';end if;continue;
   end if;
   if q->>'type' in ('text','textarea') then
    if jsonb_typeof(a)<>'string' or length(txt)>(case when q->>'type'='text' then 500 else 4000 end) or ((q->>'required')::boolean and btrim(txt)='') then raise exception 'SURVEY_INVALID_ANSWER';end if;
   elsif q->>'type' in ('number','rating') then
    if jsonb_typeof(a)<>'number' or abs(txt::numeric)>1e12 or txt::numeric<(q->>'min')::numeric or txt::numeric>(q->>'max')::numeric then raise exception 'SURVEY_INVALID_ANSWER';end if;
    if q->>'type'='rating' and (txt::numeric not between 1 and 5 or trunc(txt::numeric)<>txt::numeric) then raise exception 'SURVEY_INVALID_ANSWER';end if;
   elsif q->>'type' in ('date','datetime') then
    if jsonb_typeof(a)<>'string' or (q->>'type'='date' and txt !~ '^\d{4}-\d{2}-\d{2}$') or (q->>'type'='datetime' and txt !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$') then raise exception 'SURVEY_INVALID_ANSWER';end if;
    perform txt::timestamp;
   elsif q->>'type'='single' then
    if jsonb_typeof(a)<>'string' or not (q->'choices')?txt then raise exception 'SURVEY_INVALID_ANSWER';end if;
    if (q->'correct')?txt then score:=score+1;end if;
   elsif q->>'type'='multiple' then
    if jsonb_typeof(a)<>'array' or jsonb_array_length(a)>30 then raise exception 'SURVEY_INVALID_ANSWER';end if;
    chosen:='{}';for v in select value from jsonb_array_elements(a) loop
     if jsonb_typeof(v)<>'string' or not (q->'choices')?(v#>>'{}') or (v#>>'{}')=any(chosen) then raise exception 'SURVEY_INVALID_ANSWER';end if;chosen:=array_append(chosen,v#>>'{}');
    end loop;
    select array_agg(value) into correct from jsonb_array_elements_text(q->'correct');
    if cardinality(correct)>0 and chosen @> correct and correct @> chosen then score:=score+1;end if;
   end if;
  end loop;
  insert into private.survey_responses(survey_id,invitation_id,request_key,payload,answers,score,maximum,visitor_hash)
  values(s.id,i.id,req,payload,answers,case when s.quiz then score end,case when s.quiz then maximum end,visitor) returning * into r;
 end if;
 return jsonb_build_object('id',r.id,'thanks',s.thanks,'score',r.score,'maximum',r.maximum,'passed',case when r.maximum>0 then r.score*100.0/r.maximum>=s.pass_percent else null end);
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then raise exception 'SURVEY_INVALID_DATA';
end $$;
revoke all on function storefront_api.gama_survey(text,jsonb) from public;
grant execute on function storefront_api.gama_survey(text,jsonb) to anon,authenticated;
create function public.gama_survey(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select storefront_api.gama_survey(p_action,p_data)$$;
revoke all on function public.gama_survey(text,jsonb) from public;
grant execute on function public.gama_survey(text,jsonb) to anon,authenticated;
notify pgrst,'reload schema';
