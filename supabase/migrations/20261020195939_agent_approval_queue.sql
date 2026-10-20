-- Human-reviewed queue. Ingestion and preview never perform business writes.
alter table private.coco_module_proposals drop constraint coco_module_proposals_action_check;
alter table private.coco_module_proposals add constraint coco_module_proposals_action_check check(action in
 ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note','bank_settlement'));
create or replace function private.coco_proposal_payload(a text,p jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(coalesce(p,'{}')) where key=any(case a
 when 'bank_settlement' then array['bank_id','invoice_id']
 when 'contact_draft' then array['first_name','last_name','email','phone','job_title','company','customer_id','lead_id']
 when 'absence_request' then array['employee_id','kind','start_date','end_date']
 when 'document_create' then array['title','folder','visibility','customer_id','supplier_id','employee_id','file']
 when 'fuel_log' then array['vehicle_id','logged_on','litres','amount','odometer','station','document_id']
 when 'accounting_entry' then array['journal','entry_date','reference','memo','lines','document_id']
 else array['body'] end)
$$;
revoke all on function private.coco_proposal_payload(text,jsonb) from public,anon,authenticated;


-- Keep existing typed validators; bank previews include all consequential values
-- in the review hash, and lock in the same order as the canonical settlement.
alter function private.coco_module_validate(private.coco_module_proposals,jsonb) rename to coco_module_validate_base;
create function private.coco_module_validate(p private.coco_module_proposals,raw jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb; b public.bank_transactions; i record; a public.financial_accounts; c uuid;
begin
 if p.action<>'bank_settlement' then return private.coco_module_validate_base(p,raw);end if;
 if p.module_id<>'accounting' or not private.coco_module_reviewer('accounting') or nullif(auth.jwt()->>'client_id','') is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not private.erp_action_allowed('accounting','validate') or not private.erp_module_allowed('payments',array['administrador','comercial'])
 or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
 d:=private.coco_proposal_payload(p.action,raw);
 select * into b from public.bank_transactions where id=(d->>'bank_id')::uuid;
 if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||b.financial_account_id::text,0));
 select * into b from public.bank_transactions where id=b.id for update;
 select o.customer_id into c from public.external_invoices v join public.sales_orders o on o.id=v.order_id where v.id=(d->>'invoice_id')::uuid;
 perform 1 from public.customers where id=c for update;
 perform 1 from public.external_invoices where id=(d->>'invoice_id')::uuid for update;
 if b.status<>'unmatched' or b.amount<=0 or exists(select 1 from public.bank_invoice_settlements where bank_id=b.id) then raise exception 'BANK_ALREADY_MATCHED';end if;
 select r.*,v.fiscal_status,o.status order_status into i from private.gama_receivables r join public.external_invoices v on v.id=r.id join public.sales_orders o on o.id=r.order_id where r.id=(d->>'invoice_id')::uuid;
 if not found or i.balance<b.amount or i.payment_status in ('paid','cancelled') or i.fiscal_status in ('cancelled','rejected') or i.order_status<>'confirmed' then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 select * into a from public.financial_accounts where id=b.financial_account_id and active and account_id is not null and kind in ('bank','card') and currency=(select currency from public.company_settings where id);
 if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if not private.gama_accounting_period_open(b.value_date) then raise exception 'PERIOD_CLOSED';end if;
 return jsonb_build_object('payload',d,'details',jsonb_build_array(i.number||' · '||i.customer_name,a.name||' · '||a.currency,b.value_date::text,coalesce(b.reference,'')||' · '||coalesce(b.description,'')),
 'settlement',jsonb_build_object('invoice',i.number,'customer',i.customer_name,'customer_id',i.customer_id,'financial_account_id',a.id,'accounting_account_id',a.account_id,'account',a.name,'currency',a.currency,'amount',b.amount,'balance_before',i.balance,'balance_after',i.balance-b.amount,'date',b.value_date,'bank_reference',b.reference,'invoice_status',i.payment_status,'fiscal_status',i.fiscal_status));
end $$;
revoke all on function private.coco_module_validate(private.coco_module_proposals,jsonb) from public,anon,authenticated;
create or replace function private.coco_module_proposal_action(p_action text,p_data jsonb) returns jsonb
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
  if p.action='bank_settlement' then
   v_result:=public.gama_bank_invoice_action('settle',pl||jsonb_build_object('request_key',p.id));rid:=(pl->>'invoice_id')::uuid;
  elsif p.action='contact_draft' then
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
  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('module',p.module_id,'id',rid,'action',p.action);
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


-- A narrow draft creator: the browser selects an existing invoice and bank row.
-- No arbitrary SQL, RPC name, amount, or paid status is accepted from the client.
create function private.coco_queue_prepare_bank(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.coco_module_proposals; r jsonb; old private.coco_module_proposals;
begin
 if auth.uid() is null or not private.coco_module_allowed('assistant-ia') or private.current_user_role()<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
 p.account_id:=auth.uid();p.module_id:='accounting';p.action:='bank_settlement';p.payload:=private.coco_proposal_payload(p.action,p_data);
 r:=private.coco_module_validate(p,p.payload);
 -- Bank lock held by validator serializes duplicate preparation.
 select * into old from private.coco_module_proposals where action=p.action and payload->>'bank_id'=p.payload->>'bank_id' and status='pending' order by created_at limit 1;
 if found then
  if old.account_id<>auth.uid() or old.payload<>p.payload then raise exception 'PROPOSAL_ALREADY_PENDING';end if;
  return jsonb_build_object('id',old.id,'status',old.status,'reused',true);
 end if;
 p.id:=gen_random_uuid();p.summary:=(r->'settlement'->>'invoice')||' · '||(r->'settlement'->>'amount')||' '||(r->'settlement'->>'currency');
 insert into private.coco_module_proposals(id,account_id,module_id,action,source_type,source_id,source_label,received_at,summary,payload)
 values(p.id,p.account_id,p.module_id,p.action,'chat','bank-review:'||p.id,'Agent Coco · rapprochement bancaire',now(),p.summary,p.payload);
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_id,actor_name,proposal_id,source_type,source_id,source_label)
 values('accounting','action','propose','proposal_pending',p.summary,auth.uid(),'Agent Coco',p.id,'chat','bank-review:'||p.id,'Agent Coco · rapprochement bancaire');
 return jsonb_build_object('id',p.id,'status','pending');
end $$;
revoke all on function private.coco_queue_prepare_bank(jsonb) from public,anon;
grant execute on function private.coco_queue_prepare_bank(jsonb) to authenticated;

-- Invoker listing retains proposal RLS and current source-module permissions.
create function public.coco_action_queue(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare rows jsonb; total bigint; item jsonb; p private.coco_module_proposals; result jsonb; results jsonb:='[]';
 st text:=coalesce(p_data->>'status','pending');off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 old_type text:=current_setting('coco.activity_source_type',true);old_id text:=current_setting('coco.activity_source_id',true);old_label text:=current_setting('coco.activity_source_label',true);
begin
 if auth.uid() is null or private.current_user_role()<>'administrador' or not private.coco_module_allowed('assistant-ia')
 or nullif(auth.jwt()->>'client_id','') is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='prepare_bank' then return private.coco_queue_prepare_bank(p_data);end if;
 if p_action='list' then
  if st not in ('pending','approved','rejected') then raise exception 'INVALID_STATUS';end if;
  select count(*) into total from private.coco_module_proposals x where x.status=st and private.coco_module_reviewer(x.module_id);
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from (
   select id,module_id,action,summary,source_type,source_label,created_at,status,decided_at from private.coco_module_proposals x
   where x.status=st and private.coco_module_reviewer(x.module_id) order by created_at desc,id limit 25 offset off
  ) x;
  return jsonb_build_object('rows',rows,'total',total);
 end if;
 if p_action not in ('review_batch','approve_batch','reject_batch') then raise exception 'INVALID_ACTION';end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items') not between 1 and 25 then raise exception 'INVALID_BATCH';end if;
 if (select count(distinct value->>'id') from jsonb_array_elements(p_data->'items'))<>jsonb_array_length(p_data->'items') then raise exception 'INVALID_BATCH';end if;
 if p_action in ('approve_batch','reject_batch') and p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'CONFIRMATION_REQUIRED';end if;
 -- Stable lock order avoids competing batches deadlocking on the proposal rows.
 for item in select value from jsonb_array_elements(p_data->'items') order by value->>'id' loop
  begin
   select * into p from private.coco_module_proposals where id=(item->>'id')::uuid;
   if not found or not private.coco_module_reviewer(p.module_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
   result:=private.coco_module_proposal_action(case p_action when 'review_batch' then 'review_proposal' when 'approve_batch' then 'approve_proposal' else 'reject_proposal' end,
    jsonb_build_object('proposal_id',p.id,'module_id',p.module_id,'hash',item->>'hash'));
   results:=results||jsonb_build_array(jsonb_build_object('id',p.id,'ok',true,'summary',p.summary,'result',result));
  exception when others then
   -- Do not expose SQL details or private rows in batch errors.
   results:=results||jsonb_build_array(jsonb_build_object('id',item->>'id','ok',false,'error',case when sqlerrm ~ '^[A-Z][A-Z0-9_]{2,80}$' then sqlerrm else 'ACTION_FAILED' end));
  end;
  perform set_config('coco.activity_source_type',coalesce(old_type,''),true);perform set_config('coco.activity_source_id',coalesce(old_id,''),true);perform set_config('coco.activity_source_label',coalesce(old_label,''),true);
 end loop;
 return jsonb_build_object('rows',results);
end $$;
revoke all on function public.coco_action_queue(text,jsonb) from public,anon;
grant execute on function public.coco_action_queue(text,jsonb) to authenticated;

-- Trusted assistant ingestion can propose a bank settlement, never approve it.
create or replace function private.coco_assistant_bridge(p_action text,p_data jsonb) returns jsonb
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
 if a not in ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note','bank_settlement')
 or a='contact_draft' and m<>'contacts' or a='absence_request' and m<>'hr' or a='document_create' and m<>'documents'
 or a='bank_settlement' and (m<>'accounting' or account.role<>'administrador') or a='fuel_log' and m<>'fleet' or a='accounting_entry' and m<>'accounting' then raise exception 'INVALID_PROPOSAL_ACTION';end if;
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
