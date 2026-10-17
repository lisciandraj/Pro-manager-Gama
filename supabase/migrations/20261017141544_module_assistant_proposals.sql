-- Typed proposals from the trusted ChatGPT bridge. Ingestion never executes a
-- business action. Existing quote/purchase/TMS mail contracts remain unchanged.
create table private.coco_module_proposals(
 id uuid primary key default gen_random_uuid(),account_id uuid not null references public.profiles on delete cascade,
 module_id text not null references private.coco_history_modules,action text not null check(action in
 ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note')),
 source_type text not null check(source_type in ('mail','chat','file','import')),source_id text not null,
 source_label text not null,source_email text,received_at timestamptz not null,summary text not null,
 payload jsonb not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),review jsonb,reviewed_by uuid references public.profiles on delete set null,
 reviewed_at timestamptz,review_hash text,decided_at timestamptz,decided_by uuid references public.profiles on delete set null,result jsonb,
 unique(account_id,source_type,source_id,module_id,action),
 check(length(source_id) between 1 and 500 and length(source_label)<=300 and length(summary)<=3000 and octet_length(payload::text)<=60000)
);
create index coco_module_proposals_inbox on private.coco_module_proposals(module_id,status,created_at desc);
create index coco_module_proposals_reviewer on private.coco_module_proposals(reviewed_by);
create index coco_module_proposals_decider on private.coco_module_proposals(decided_by);
create unique index coco_module_source_once on private.coco_module_events(actor_id,source_type,source_id,module_id,record_table,record_id) where action='source_linked';
alter table private.coco_module_proposals enable row level security;
revoke all on private.coco_module_proposals from public,anon,authenticated;
grant select on private.coco_module_proposals to authenticated;

create function private.coco_module_reviewer(m text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_module_allowed(m) and (private.current_user_role()='administrador' or m='hr' and private.hr_admin())
 and private.erp_action_allowed(m,'create') and private.erp_action_allowed(m,'edit')
 and case when m='accounting' then private.gama_accounting_may('create') and private.gama_accounting_may('validate') and private.gama_accounting_rights()->>'scope'='all'
 when m='contacts' then private.erp_module_allowed('crm',array['administrador','comercial']) and private.erp_action_allowed('crm','create')
 else true end
$$;
revoke all on function private.coco_module_reviewer(text) from public,anon;
grant execute on function private.coco_module_reviewer(text) to authenticated;
create policy coco_module_proposals_read on private.coco_module_proposals for select to authenticated using(
 private.coco_module_allowed(module_id) and (account_id=auth.uid() or private.coco_module_reviewer(module_id))
);
-- Proposal summaries/decisions are private to their mailbox and module reviewer.
alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and (module_id<>'hr' or private.hr_admin() or actor_id=auth.uid()) and
 (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id)) and
 case when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid()
 else true end
);

-- A bounded allowlist strips untrusted fields before they can enter a proposal.
create function private.coco_proposal_payload(a text,p jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(coalesce(p,'{}')) where key=any(case a
 when 'contact_draft' then array['first_name','last_name','email','phone','job_title','company','customer_id','lead_id']
 when 'absence_request' then array['employee_id','kind','start_date','end_date']
 when 'document_create' then array['title','folder','visibility','customer_id','supplier_id','employee_id','file']
 when 'fuel_log' then array['vehicle_id','logged_on','litres','amount','odometer','station','document_id']
 when 'accounting_entry' then array['journal','entry_date','reference','memo','lines','document_id']
 else array['body'] end)
$$;
revoke all on function private.coco_proposal_payload(text,jsonb) from public,anon,authenticated;

-- Only the bridge can ingest: no sessions, JWT impersonation, arbitrary tables
-- or direct business writes. Account identity is resolved from the verified app.
create function private.coco_source_employee(p_email text) returns uuid
language sql stable security definer set search_path='' as $$
 select case when count(distinct e.id)=1 then min(e.id::text)::uuid end from public.hr_employees e
 left join public.hr_employee_private d on d.employee_id=e.id left join auth.users u on u.id=e.profile_id
 where e.active and p_email is not null and (lower(btrim(d.email))=p_email or lower(btrim(u.email))=p_email)
$$;
revoke all on function private.coco_source_employee(text) from public,anon,authenticated;
create function private.coco_assistant_bridge(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare account public.profiles;cfg private.coco_history_modules;tc private.coco_history_tables;rec jsonb;existing private.coco_module_proposals;
 m text:=p_data->>'module_id';a text:=p_data->>'action';s jsonb:=p_data->'source';pl jsonb;
 sid text:=btrim(s->>'id');typ text:=s->>'type';sender text:=lower(btrim(s->>'email'));
 label text:=left(coalesce(s->>'label',''),300);summary text:=btrim(p_data->>'summary');stamp timestamptz;
 eid uuid;employee uuid;mods jsonb;matches jsonb;lookups jsonb:='[]';term text:=left(btrim(p_data->>'search'),100);author text;
begin
 select p.* into account from public.profiles p join auth.users u on u.id=p.id
 where p.active and lower(u.email)=lower(btrim(p_data->>'account_email')) and p.role in ('administrador','comercial','rrhh');
 if account.id is null then raise exception 'BRIDGE_ACCOUNT_NOT_FOUND';end if;
 if typ='mail' and not exists(select 1 from private.coco_mail_bridge_accounts b where b.user_id=account.id and b.enabled and lower(b.email)=lower(p_data->>'account_email')) then raise exception 'BRIDGE_DISABLED';end if;
 if p_action='context' then
  select coalesce(jsonb_agg(jsonb_build_object('module_id',c.module_id,'label',c.label) order by c.module_id),'[]') into mods
  from private.coco_history_modules c left join public.role_module_access r on r.role=coalesce(account.access_profile,account.role)
  where account.role=any(c.roles) and not coalesce(c.module_id=any(r.disabled_modules),false)
  and not exists(select 1 from public.app_modules z where z.id=c.module_id and not z.enabled);
  select coalesce(jsonb_agg(c),'[]') into matches from (
   select 'customer' kind,id,name from public.customers where sender is not null and lower(btrim(email))=sender
   union all select 'supplier',id,name from public.suppliers where sender is not null and lower(btrim(email))=sender
   union all select 'person',id,concat_ws(' ',first_name,last_name) from public.crm_contacts where active and sender is not null and lower(btrim(email))=sender
  ) c;
  if length(term)>=2 and account.role='administrador' then
   if p_data->>'lookup'='vehicles' and mods @> '[{"module_id":"fleet"}]' then
    select coalesce(jsonb_agg(x),'[]') into lookups from (select id,plate reference,brand||' '||model label from public.fleet_vehicles where active and plate ilike '%'||term||'%' order by plate limit 25) x;
   elsif p_data->>'lookup' in ('accounts','journals','financial_accounts') and mods @> '[{"module_id":"accounting"}]'
    and not exists(select 1 from public.accounting_permissions where profile_id=account.id and not can_view) then
    if p_data->>'lookup'='accounts' then
     select coalesce(jsonb_agg(x),'[]') into lookups from (select id,code reference,name label from public.accounting_accounts where active and (code=term or name ilike '%'||term||'%') order by code limit 25) x;
    elsif p_data->>'lookup'='journals' then
     select coalesce(jsonb_agg(x),'[]') into lookups from (select code id,code reference,name label from public.accounting_journals where active and (code=term or name ilike '%'||term||'%') order by code limit 25) x;
    else
     select coalesce(jsonb_agg(x),'[]') into lookups from (select id,name label from public.financial_accounts where active and name ilike '%'||term||'%' order by name limit 25) x;
    end if;
   end if;
  end if;
  return jsonb_build_object('modules',mods,'contacts',matches,'lookups',lookups,'employee',case when account.role in ('administrador','rrhh') and mods @> '[{"module_id":"hr"}]' then
    (select jsonb_build_object('id',id,'name',full_name) from public.hr_employees where id=private.coco_source_employee(sender)) end,
   'existing',(select jsonb_agg(jsonb_build_object('id',id,'module_id',module_id,'action',action,'status',status)) from private.coco_module_proposals where account_id=account.id and source_type=typ and source_id=sid));
 end if;
 if p_action not in ('propose','record') then raise exception 'INVALID_ACTION';end if;
 select * into cfg from private.coco_history_modules where module_id=m;
 if cfg.module_id is null or not account.role=any(cfg.roles)
 or exists(select 1 from public.role_module_access r where r.role=coalesce(account.access_profile,account.role) and m=any(r.disabled_modules))
 or exists(select 1 from public.app_modules z where z.id=m and not z.enabled) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if typ not in ('mail','chat','file','import') or coalesce(length(sid),0) not between 1 and 500 then raise exception 'SOURCE_REQUIRED';end if;
 stamp:=(s->>'received_at')::timestamptz;
 if stamp is null or stamp>now()+interval '5 minutes' then raise exception 'INVALID_SOURCE_DATE';end if;
 if typ='mail' then
  if sender is null or sender !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'INVALID_SOURCE_EMAIL';end if;
  if not exists(select 1 from private.coco_mail_bridge_accounts b where b.user_id=account.id and b.enabled and lower(b.email)=lower(p_data->>'account_email')) then raise exception 'BRIDGE_DISABLED';end if;
 end if;
 if coalesce(length(summary),0) not between 1 and 3000 then raise exception 'INVALID_MESSAGE';end if;
 if m='hr' then
  if account.role not in ('administrador','rrhh') then raise exception 'ROLE_NOT_ALLOWED';end if;
  summary:='Solicitud de ausencia recibida; pendiente de revisión RH.';label:=case when typ='mail' then 'Correo RH' else 'Solicitud RH' end;
 end if;
 if p_action='record' then
  if m='hr' then summary:='Acción RH vinculada a su origen.';end if;
  select * into tc from private.coco_history_tables where table_name=p_data->>'record_table' and module_id=m;
  if not found then raise exception 'INVALID_RECORD_TABLE';end if;
  execute format('select to_jsonb(t) from %I.%I t where %I::text=$1',tc.table_schema,tc.table_name,tc.key_column) into rec using p_data->>'record_id';
  if rec is null then raise exception 'RECORD_NOT_FOUND';end if;
  insert into private.coco_module_events(module_id,record_table,record_id,type,action,subject,body,actor_id,actor_name,source_type,source_id,source_label,source_email,links)
  values(m,p_data->>'record_table',p_data->>'record_id','action','source_linked','Origen de la acción',summary,account.id,coalesce(nullif(account.full_name,''),'USER_UNAVAILABLE'),typ,sid,label,sender,
   jsonb_build_array(jsonb_build_object('module',m,'action','module','id',p_data->>'record_id')))
  on conflict do nothing returning id into eid;
  return jsonb_build_object('recorded',true,'id',eid);
 end if;
 if a not in ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note')
 or a='contact_draft' and m<>'contacts' or a='absence_request' and m<>'hr' or a='document_create' and m<>'documents'
 or a='fuel_log' and m<>'fleet' or a='accounting_entry' and m<>'accounting' then raise exception 'INVALID_PROPOSAL_ACTION';end if;
 pl:=private.coco_proposal_payload(a,p_data->'payload');
 perform pg_advisory_xact_lock(hashtextextended(account.id||':'||typ||':'||sid||':'||m||':'||a,0));
 select * into existing from private.coco_module_proposals where account_id=account.id and source_type=typ and source_id=sid and module_id=m and action=a;
 if found then return jsonb_build_object('id',existing.id,'status',existing.status,'duplicate',true);end if;
 if a='contact_draft' and typ='mail' and lower(btrim(pl->>'email')) is distinct from sender then raise exception 'SOURCE_CONTACT_MISMATCH';end if;
 if a='contact_draft' and exists(select 1 from public.customers where lower(btrim(email))=lower(btrim(pl->>'email')) union all
   select 1 from public.suppliers where lower(btrim(email))=lower(btrim(pl->>'email')) union all
   select 1 from public.crm_contacts where active and lower(btrim(email))=lower(btrim(pl->>'email')) union all
   select 1 from public.crm_leads where active and lower(btrim(email))=lower(btrim(pl->>'email'))) then return jsonb_build_object('skipped','CONTACT_EXISTS');end if;
 if a='absence_request' and typ='mail' then
  employee:=private.coco_source_employee(sender);
  if employee is null or (pl->>'employee_id')::uuid is distinct from employee then raise exception 'SOURCE_EMPLOYEE_MISMATCH';end if;
 end if;
 insert into private.coco_module_proposals(account_id,module_id,action,source_type,source_id,source_label,source_email,received_at,summary,payload)
 values(account.id,m,a,typ,sid,label,sender,stamp,summary,pl) returning * into existing;
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_name,proposal_id,source_type,source_id,source_label,source_email)
 values(m,'proposal','proposal','mail_analysis',summary,'Agent Coco',existing.id,typ,sid,label,sender);
 return jsonb_build_object('id',existing.id,'status','pending','module_id',m);
end $$;
revoke all on function private.coco_assistant_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_assistant_bridge(text,jsonb) to service_role;
create function public.coco_assistant_bridge(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_assistant_bridge(p_action,p_data)$$;
revoke all on function public.coco_assistant_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_assistant_bridge(text,jsonb) to service_role;

-- A real reviewer sees editable fields and a server-built readable preview.
-- Accounting and fleet keep their existing transaction and period checks.
create function private.coco_module_validate(p private.coco_module_proposals,raw jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=private.coco_proposal_payload(p.action,raw);details jsonb:='[]';x jsonb;debit numeric:=0;credit numeric:=0;v text;obj jsonb;
begin
 if not private.coco_module_reviewer(p.module_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p.action='record_note' then
  if coalesce(length(btrim(d->>'body')),0) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  return jsonb_build_object('payload',d,'details',jsonb_build_array(d->>'body'));
 elsif p.action='contact_draft' then
  d:=d||jsonb_build_object('email',lower(btrim(d->>'email')));
  if coalesce(length(concat_ws('',nullif(btrim(d->>'first_name'),''),nullif(btrim(d->>'last_name'),''))),0)=0 or d->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'CONTACT_INVALID_DATA';end if;
  if exists(select 1 from public.crm_contacts where active and lower(btrim(email))=d->>'email' union all select 1 from public.crm_leads where active and lower(btrim(email))=d->>'email'
   union all select 1 from public.customers where lower(btrim(email))=d->>'email' union all select 1 from public.suppliers where lower(btrim(email))=d->>'email') then raise exception 'CONTACT_EXISTS';end if;
  if nullif(d->>'customer_id','') is not null then
   select name into v from public.customers where id=(d->>'customer_id')::uuid and active;if not found then raise exception 'CONTACT_INVALID_PARENT';end if;
  elsif nullif(d->>'lead_id','') is not null then
   select coalesce(company,concat_ws(' ',first_name,last_name)) into v from public.crm_leads where id=(d->>'lead_id')::uuid and active;if not found then raise exception 'CONTACT_INVALID_PARENT';end if;
  else v:=coalesce(nullif(d->>'company',''),concat_ws(' ',d->>'first_name',d->>'last_name'));end if;
  details:=jsonb_build_array(concat_ws(' ',d->>'first_name',d->>'last_name'),d->>'email',d->>'phone',v);
 elsif p.action='absence_request' then
  select full_name into v from public.hr_employees where id=(d->>'employee_id')::uuid and active;
  if not found or not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;
  if d->>'kind' not in ('vacaciones','enfermedad','permiso','formacion','otro') or nullif(d->>'start_date','') is null or nullif(d->>'end_date','') is null
  or (d->>'end_date')::date<(d->>'start_date')::date then raise exception 'INVALID_ABSENCE';end if;
  if exists(select 1 from public.hr_absences where employee_id=(d->>'employee_id')::uuid and status not in ('rechazada','cancelada') and start_date<=(d->>'end_date')::date and end_date>=(d->>'start_date')::date) then raise exception 'ABSENCE_OVERLAP';end if;
  details:=jsonb_build_array(v,d->>'kind',(d->>'start_date')||' → '||(d->>'end_date'),'pendiente');
 elsif p.action='document_create' then
  if coalesce(length(btrim(d->>'title')),0) not between 1 and 200 or coalesce(d->>'visibility','management') not in ('team','management','hr') then raise exception 'INVALID_DOCUMENT';end if;
  if d->>'visibility'='hr' and not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;
  if d->'file' is null or not exists(select 1 from storage.objects o where o.bucket_id='business-documents' and o.name=d->'file'->>'storage_path'
    and o.name like auth.uid()::text||'/%') then raise exception 'DOCUMENT_FILE_MISSING';end if;
  if coalesce((d->'file'->>'file_size')::bigint,0) not between 1 and 20000000 or coalesce(length(d->'file'->>'filename'),0) not between 1 and 255 then raise exception 'INVALID_DOCUMENT_FILE';end if;
  d:=d||jsonb_build_object('visibility',coalesce(d->>'visibility','management'));
  details:=jsonb_build_array(d->>'title',d->>'folder',d->>'visibility',d->'file'->>'filename');
 elsif p.action='fuel_log' then
  select plate into v from public.fleet_vehicles where id=(d->>'vehicle_id')::uuid and active;
  if not found or nullif(d->>'logged_on','') is null or coalesce((d->>'litres')::numeric,0)<=0 or coalesce((d->>'amount')::numeric,-1)<0 or coalesce((d->>'odometer')::numeric,-1)<0 then raise exception 'INVALID_FUEL_LOG';end if;
  details:=jsonb_build_array(v,d->>'logged_on',(d->>'litres')||' L',d->>'amount',d->>'station');
 elsif p.action='accounting_entry' then
  if nullif(d->>'entry_date','') is null or not exists(select 1 from public.accounting_journals where code=d->>'journal' and active) then raise exception 'INVALID_JOURNAL';end if;
  if not private.gama_accounting_period_open((d->>'entry_date')::date) then raise exception 'PERIOD_CLOSED';end if;
  if jsonb_typeof(d->'lines') is distinct from 'array' or jsonb_array_length(d->'lines') not between 2 and 200 then raise exception 'INVALID_LINES';end if;
  for x in select * from jsonb_array_elements(d->'lines') loop
   select code||' · '||name into v from public.accounting_accounts where id=(x->>'account_id')::uuid and active;
   if not found or coalesce((x->>'debit')::numeric,0)<0 or coalesce((x->>'credit')::numeric,0)<0 or ((coalesce((x->>'debit')::numeric,0)>0)=(coalesce((x->>'credit')::numeric,0)>0)) then raise exception 'INVALID_LINES';end if;
   debit:=debit+round(coalesce((x->>'debit')::numeric,0),2);credit:=credit+round(coalesce((x->>'credit')::numeric,0),2);
   details:=details||jsonb_build_array(v||' · D '||coalesce(x->>'debit','0')||' / C '||coalesce(x->>'credit','0'));
  end loop;
  if debit=0 or debit<>credit then raise exception 'ENTRY_UNBALANCED';end if;
  details:=jsonb_build_array(d->>'journal',d->>'entry_date',d->>'reference')||details;
 end if;
 return jsonb_build_object('payload',d,'details',details);
end $$;
revoke all on function private.coco_module_validate(private.coco_module_proposals,jsonb) from public,anon,authenticated;

create function private.coco_module_proposal_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.coco_module_proposals;r jsonb;h text;author text;rid uuid;parent uuid;v_result jsonb;pl jsonb;ctx jsonb;v jsonb;
begin
 select * into p from private.coco_module_proposals where id=(p_data->>'proposal_id')::uuid and module_id=p_data->>'module_id' for update;
 if p.id is null or not private.coco_module_reviewer(p.module_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='approve_proposal' and p.status='approved' then return p.result;end if;
 if p.status<>'pending' then raise exception 'PROPOSAL_DECIDED';end if;
 if p_action='review_proposal' then
  r:=private.coco_module_validate(p,coalesce(p_data->'payload',p.payload));h:=md5(p.id::text||auth.uid()::text||r::text);
  update private.coco_module_proposals set review=r,review_hash=h,reviewed_by=auth.uid(),reviewed_at=now() where id=p.id;
  return jsonb_build_object('hash',h,'review',r,'action',p.action);
 end if;
 if p_action='approve_proposal' then
  if p.review_hash is null or p.review_hash is distinct from p_data->>'hash' or p.reviewed_by is distinct from auth.uid() or p.reviewed_at<now()-interval '10 minutes' then raise exception 'PROPOSAL_CHANGED';end if;
  r:=private.coco_module_validate(p,p.review->'payload');h:=md5(p.id::text||auth.uid()::text||r::text);
  if h<>p.review_hash then raise exception 'PROPOSAL_CHANGED';end if;
  pl:=r->'payload';
  perform set_config('coco.activity_source_type',p.source_type,true);perform set_config('coco.activity_source_id',p.source_id,true);perform set_config('coco.activity_source_label',p.source_label,true);
  if p.action='contact_draft' then
   perform pg_advisory_xact_lock(hashtextextended('coco-contact:'||(pl->>'email'),0));
   perform private.coco_module_validate(p,pl);
   parent:=nullif(pl->>'lead_id','')::uuid;
   if nullif(pl->>'customer_id','') is null and parent is null then
    insert into public.crm_leads(kind,first_name,last_name,company,email,phone,job_title,owner_id,created_by)
    values(case when nullif(pl->>'company','') is null then 'particular' else 'empresa' end,pl->>'first_name',pl->>'last_name',nullif(pl->>'company',''),pl->>'email',pl->>'phone',pl->>'job_title',auth.uid(),auth.uid()) returning id into parent;
   end if;
   v_result:=public.gama_contact_person_save(null,pl||jsonb_build_object('lead_id',parent));rid:=(v_result->>'id')::uuid;
  elsif p.action='absence_request' then
   perform pg_advisory_xact_lock(hashtextextended('coco-absence:'||(pl->>'employee_id'),0));perform private.coco_module_validate(p,pl);
   insert into public.hr_absences(employee_id,kind,start_date,end_date,status,start_fraction,end_fraction)
   values((pl->>'employee_id')::uuid,pl->>'kind',(pl->>'start_date')::date,(pl->>'end_date')::date,'pendiente',1,1) returning id into rid;
  elsif p.action='document_create' then
   v_result:=public.gama_save_business_document(pl||jsonb_build_object('id',p.id),0,pl->'file');rid:=(v_result->>'id')::uuid;
  elsif p.action='fuel_log' then
   v_result:=public.gama_fleet_action('fuel_save',pl||jsonb_build_object('request_key',p.id));rid:=(v_result->>'id')::uuid;
  elsif p.action='accounting_entry' then
   v_result:=public.gama_accounting_action('entry_manual',pl||jsonb_build_object('request_key',p.id));rid:=(v_result->>'id')::uuid;
  end if;
  v_result:=jsonb_build_object('module',p.module_id,'id',rid,'action',p.action);
 else
  if p_action<>'reject_proposal' then raise exception 'INVALID_ACTION';end if;
  v_result:=jsonb_build_object('status','rejected');
 end if;
 update private.coco_module_proposals set status=case when p_action='approve_proposal' then 'approved' else 'rejected' end,decided_at=now(),decided_by=auth.uid(),result=v_result where id=p.id;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_id,actor_name,proposal_id,source_type,source_id,source_label,source_email,links)
 values(p.module_id,'action',p_action,case when p_action='approve_proposal' then 'proposal_approved' else 'proposal_rejected' end,
  case when p.module_id='hr' then 'Solicitud RH revisada.' when p_action='approve_proposal' and p.action='record_note' then r->'payload'->>'body' else p.summary end,
  auth.uid(),author,p.id,p.source_type,p.source_id,p.source_label,p.source_email,
  case when rid is not null then jsonb_build_array(jsonb_build_object('module',p.module_id,'action','module','id',rid)) else '[]'::jsonb end);
 return v_result;
end $$;
revoke all on function private.coco_module_proposal_action(text,jsonb) from public,anon;
grant execute on function private.coco_module_proposal_action(text,jsonb) to authenticated;

-- Add proposal context/list/review without changing the activity read's invoker.
alter function public.coco_module_history(text,jsonb) rename to coco_module_history_events;
revoke all on function public.coco_module_history_events(text,jsonb) from public,anon;
create function public.coco_module_history(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare r jsonb;m text:=p_data->>'module_id';opts jsonb:='{}';
begin
 if not private.coco_module_allowed(m) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('review_proposal','approve_proposal','reject_proposal') then return private.coco_module_proposal_action(p_action,p_data);end if;
 if p_action='proposal_options' then
  if not private.coco_module_reviewer(m) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if m='hr' then opts:=jsonb_build_object('employees',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',full_name) order by full_name),'[]') from public.hr_employees where active));
  elsif m='fleet' then opts:=jsonb_build_object('vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',plate) order by plate),'[]') from public.fleet_vehicles where active));
  elsif m='contacts' then opts:=jsonb_build_object('customers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',name) order by name),'[]') from public.customers where active),
   'leads',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',coalesce(company,concat_ws(' ',first_name,last_name))) order by created_at desc),'[]') from public.crm_leads where active));
  elsif m='accounting' then opts:=jsonb_build_object('journals',(select coalesce(jsonb_agg(jsonb_build_object('id',code,'label',code||' · '||name) order by code),'[]') from public.accounting_journals where active),
   'accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',code||' · '||name) order by code),'[]') from public.accounting_accounts where active),
   'financial_accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',name) order by name),'[]') from public.financial_accounts where active));end if;
  return opts;
 end if;
 r:=public.coco_module_history_events(p_action,p_data);
 if p_action='list' then
  -- Other successful actions from the same real source remain one click away.
  r:=jsonb_set(r,'{history}',(select coalesce(jsonb_agg(e||jsonb_build_object('links',coalesce(e->'links','[]')||coalesce((
   select jsonb_agg(jsonb_build_object('module',p.module_id,'action','module','id',p.result->>'id')) from private.coco_module_proposals p
   where e->>'source_id' is not null and p.source_id=e->>'source_id' and p.source_type=e->>'source_type' and p.status='approved' and p.result->>'id' is not null
   and p.account_id=coalesce((select o.account_id from private.coco_module_proposals o where o.id=(e->>'proposal_id')::uuid),(e->>'actor_id')::uuid)
   and p.module_id<>m and private.coco_module_allowed(p.module_id)
  ),'[]'::jsonb)) order by h.n),'[]') from jsonb_array_elements(r->'history') with ordinality h(e,n)));
  r:=jsonb_set(r,'{proposals}',(select coalesce(jsonb_agg((to_jsonb(p)-array['account_id','review','review_hash','reviewed_by','reviewed_at'])||jsonb_build_object('can_review',private.coco_module_reviewer(m))),'[]') from private.coco_module_proposals p where p.module_id=m and
   p.id in (select (x->>'proposal_id')::uuid from jsonb_array_elements(r->'history') x where x->>'proposal_id' is not null)));
 end if;
 if p_action in ('context','list') then
  if p_action='context' then return r||jsonb_build_object('can_review',private.coco_module_reviewer(m));end if;
  r:=jsonb_set(r,'{context,can_review}',to_jsonb(private.coco_module_reviewer(m)));
 end if;
 return r;
end $$;
revoke all on function public.coco_module_history(text,jsonb) from public,anon;
grant execute on function public.coco_module_history(text,jsonb) to authenticated;

-- Keep the established dossier APIs while exposing new source annotations in
-- their existing panel. Canonical sales/purchase/TMS actions are not duplicated.
create or replace function public.coco_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare r jsonb;extra jsonb;items jsonb;m text;oid text:=p_data->>'order_id';
begin
 r:=private.coco_dossier(p_action,p_data);
 if p_action<>'list' then return r;end if;
 m:=case p_data->>'kind' when 'sales' then 'sales-orders' when 'quote' then 'quotes' when 'purchase' then 'gamaPurchasesV14' when 'tms' then 'tms' end;
 if m is null or not private.coco_module_allowed(m) then return r;end if;
 extra:=public.coco_module_history('list',jsonb_build_object('module_id',m,'annotations_only',true,'record_id',oid,'offset',coalesce((p_data->>'offset')::integer,0)));
 select coalesce(jsonb_agg(e order by e->>'at' desc,e->>'id'),'[]') into items from jsonb_array_elements(extra->'history') e
 where (e->>'action'='source_linked' or e->>'type' in ('note','proposal') or e->>'proposal_id' is not null)
 and (oid is null or exists(select 1 from jsonb_array_elements(e->'links') l where l->>'module'=m and l->>'id'=oid));
 r:=jsonb_set(r,'{history}',coalesce(r->'history','[]')||items);
 r:=jsonb_set(r,'{proposals}',coalesce(r->'proposals','[]')||coalesce((select jsonb_agg(p) from jsonb_array_elements(extra->'proposals') p
  where p->>'id' in (select e->>'proposal_id' from jsonb_array_elements(items) e)),'[]'));
 return r;
end $$;
revoke all on function public.coco_dossier(text,jsonb) from public,anon;
grant execute on function public.coco_dossier(text,jsonb) to authenticated;
notify pgrst,'reload schema';
