-- Explicit opt-in sequences reuse the durable outbox. No provider or customer
-- preference is activated by this migration and no existing draft is queued.
alter table private.message_outbox add column collection_step integer,add column maturity_date date,add column automatic_collection boolean not null default false;
create table private.collection_holds(invoice_id uuid primary key references public.external_invoices(id),disputed boolean not null default false,promise_date date,promise_amount numeric check(promise_amount>0 and promise_amount<1000000000),suspend_until date,reason text not null check(length(btrim(reason)) between 3 and 1000),version integer not null default 1,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
alter table private.collection_holds enable row level security;revoke all on private.collection_holds from public,anon,authenticated;
alter function private.message_draft_valid(private.message_outbox) rename to message_valid_before_sequences;
create function private.message_draft_valid(m private.message_outbox) returns boolean language plpgsql stable security definer set search_path='' as $$
declare valid boolean;today date:=(now() at time zone private.erp_timezone())::date;begin
 if m.kind='invoice_reminder' and exists(select 1 from private.collection_holds h where h.invoice_id=m.source_id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) then return false;end if;
 if m.collection_step is null then return private.message_valid_before_sequences(m);end if;
 select exists(select 1 from public.customers c join private.customer_message_preferences p on p.customer_id=c.id where c.id=m.customer_id and c.active and c.email=m.recipient and p.invoice_reminders)
 and exists(select 1 from private.automation_jobs j join private.automation_rules r on r.kind=j.kind and r.version=j.rule_version join public.profiles a on a.id=m.actor join auth.users u on u.id=a.id where j.id=m.job_id and r.enabled and r.version=m.rule_version and r.version=(select max(version) from private.automation_rules where kind=r.kind) and r.executor=m.actor and r.approved_until>now() and a.active and a.role='administrador' and a.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and exists(select 1 from private.gama_receivables r where r.id=m.source_id and r.customer_id=m.customer_id and r.balance=m.source_amount and r.balance>0)
 and exists(select 1 from private.gama_customer_dues(m.customer_id,array[m.source_id]) d where d.balance>0 group by d.document_id having min(d.due_date)=m.maturity_date and today>=min(d.due_date)+m.collection_step and (m.collection_step>=0 or today<=min(d.due_date)))
 and not exists(select 1 from private.collection_holds h where h.invoice_id=m.source_id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) into valid;
 return coalesce(valid,false);
end $$;
alter function private.automation_reminders(private.automation_jobs,jsonb) rename to automation_reminders_before_sequences;
create function private.automation_reminders(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row record;n integer:=0;changed integer;step integer;today date:=(now() at time zone private.erp_timezone())::date;steps jsonb:=coalesce(p_config->'steps','[-3,7,14,30]'::jsonb);lang text:=coalesce(p_config->>'language','es');mode text:=coalesce(p_config->>'delivery_mode','manual');subject text;body text;company text;currency text;begin
 if not (p_config ? 'steps') then return private.automation_reminders_before_sequences(p_job,p_config);end if;
 if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(steps)<>'array' or jsonb_array_length(steps) not between 1 and 8 or exists(select 1 from jsonb_array_elements_text(steps)x where x!~'^-?[0-9]{1,3}$' or x::integer not between -30 and 180) then raise exception 'INVALID_SEQUENCE';end if;
 if mode not in ('manual','automatic') or lang not in ('es','fr','en') then raise exception 'INVALID_SEQUENCE';end if;
 if mode='automatic' and not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 select coalesce(nullif(legal_name,''),'Coco ERP'),c.currency into company,currency from public.company_settings c where id;
 update private.message_outbox m set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where collection_step is not null and state in ('draft','queued') and not private.message_draft_valid(m);
 for row in select r.*,c.email outbound_email,d.maturity from private.gama_receivables r join public.customers c on c.id=r.customer_id and c.active join private.customer_message_preferences p on p.customer_id=c.id and p.invoice_reminders join lateral(select min(d.due_date) maturity from private.gama_customer_dues(c.id,array[r.id])d where d.balance>0)d on d.maturity is not null
 where r.balance>0 and c.email~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' and not exists(select 1 from private.collection_holds h where h.invoice_id=r.id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) order by d.maturity,r.id limit 200 loop
  select max(value::integer) into step from jsonb_array_elements_text(steps) where today>=row.maturity+value::integer and (value::integer>=0 or today<=row.maturity);
  if step is null then continue;end if;
  subject:=company||' · '||case lang when 'fr' then 'Rappel de facture ' when 'en' then 'Invoice reminder ' else 'Recordatorio de factura ' end||row.number;
  body:=case lang when 'fr' then 'Bonjour '||row.customer_name||E',\nFacture : '||row.number||E'\nÉchéance : '||row.maturity||E'\nSolde restant : '||currency||' '||row.balance||E'\nSi vous avez déjà réglé cette facture, merci de nous transmettre la preuve de paiement.' when 'en' then 'Hello '||row.customer_name||E',\nInvoice: '||row.number||E'\nDue date: '||row.maturity||E'\nOutstanding: '||currency||' '||row.balance||E'\nIf you have already paid, please send us the payment confirmation.' else 'Hola '||row.customer_name||E',\nFactura: '||row.number||E'\nVencimiento: '||row.maturity||E'\nSaldo pendiente: '||currency||' '||row.balance||E'\nSi ya has pagado, envíanos el comprobante para actualizar el registro.' end;
  insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,source_amount,subject,body,state,collection_step,maturity_date,automatic_collection)
  values('sequence:'||row.id||':'||row.maturity||':'||step,'invoice_reminder',row.customer_id,row.id,p_job.id,auth.uid(),p_job.rule_version,row.outbound_email,row.balance,subject,body,case mode when 'automatic' then 'queued' else 'draft' end,step,row.maturity,mode='automatic')
  on conflict(key) do update set job_id=excluded.job_id,actor=excluded.actor,rule_version=excluded.rule_version,recipient=excluded.recipient,source_amount=excluded.source_amount,subject=excluded.subject,body=excluded.body,state=excluded.state,automatic_collection=excluded.automatic_collection,error_code=null,updated_at=now() where message_outbox.state='cancelled' and message_outbox.attempts=0 and message_outbox.manual_sent_at is null;
  get diagnostics changed=row_count;n:=n+changed;
 end loop;return jsonb_build_object('prepared',n,'mode',mode);end $$;

create function private.gama_collections_schedule(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare h private.collection_holds;target uuid;r private.automation_rules;conf private.message_provider;secret uuid;steps jsonb;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('payments',array['administrador','comercial']) or (p_action<>'context' and not private.erp_action_allowed('payments','create')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  select * into r from private.automation_rules where kind='reminders' order by version desc limit 1;
  return jsonb_build_object('rule',to_jsonb(r)-'executor'-'approved_by','provider',coalesce((select jsonb_build_object('enabled',enabled,'sender',sender) from private.message_provider where id),'{"enabled":false}'::jsonb),'holds',coalesce((select jsonb_agg(to_jsonb(x)) from(select hold.*,recv.number,recv.customer_name from private.collection_holds hold join private.gama_receivables recv on recv.id=hold.invoice_id order by hold.updated_at desc limit 200)x),'[]'),'invoices',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,number,customer_name,balance,due_date from private.gama_receivables where balance>0 order by due_date nulls last,id limit 300)x),'[]'));
 elsif p_action='hold_save' then
  target:=(p_data->>'invoice_id')::uuid;perform 1 from public.external_invoices where id=target for update;if not found then raise exception 'NOT_FOUND';end if;
  select * into h from private.collection_holds where invoice_id=target;if coalesce(h.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  insert into private.collection_holds(invoice_id,disputed,promise_date,promise_amount,suspend_until,reason,updated_by) values(target,coalesce((p_data->>'disputed')::boolean,false),nullif(p_data->>'promise_date','')::date,nullif(p_data->>'promise_amount','')::numeric,nullif(p_data->>'suspend_until','')::date,p_data->>'reason',auth.uid()) on conflict(invoice_id) do update set disputed=excluded.disputed,promise_date=excluded.promise_date,promise_amount=excluded.promise_amount,suspend_until=excluded.suspend_until,reason=excluded.reason,version=collection_holds.version+1,updated_by=auth.uid(),updated_at=now();
  update private.message_outbox m set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where source_id=target and state in ('draft','queued') and not private.message_draft_valid(m);return jsonb_build_object('saved',true);
 end if;
 if not private.erp_module_allowed('access-settings',array['administrador']) or not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='rule_save' then
  steps:=p_data->'steps';if jsonb_typeof(steps) is distinct from 'array' or jsonb_array_length(steps) not between 1 and 8 or exists(select 1 from jsonb_array_elements_text(steps)x where x!~'^-?[0-9]{1,3}$' or x::integer not between -30 and 180) or p_data->>'delivery_mode' not in ('manual','automatic') or p_data->>'language' not in ('fr','es','en') then raise exception 'INVALID_SEQUENCE';end if;
  return private.gama_automation('rule_save',jsonb_build_object('kind','reminders','expected_version',p_data->'version','enabled',p_data->'enabled','delegation_days',90,'config',jsonb_build_object('interval_minutes',60,'steps',steps,'language',p_data->>'language','delivery_mode',p_data->>'delivery_mode')));
 elsif p_action='provider_save' then
  if not coalesce((p_data->>'enabled')::boolean,false) then update private.message_provider set enabled=false,updated_at=now(),updated_by=auth.uid() where id;if exists(select 1 from cron.job where jobname='coco-message-dispatch') then perform cron.unschedule('coco-message-dispatch');end if;return jsonb_build_object('enabled',false);end if;
  if not coalesce((p_data->>'domain_verified')::boolean,false) or coalesce(p_data->>'sender','')!~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
  select * into conf from private.message_provider where id for update;
  if nullif(p_data->>'api_key','') is not null then
   if length(p_data->>'api_key') not between 10 and 300 then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
   if conf.secret_id is null then secret:=vault.create_secret(p_data->>'api_key','coco_email_provider');else secret:=conf.secret_id;perform vault.update_secret(secret,p_data->>'api_key');end if;
  else secret:=conf.secret_id;end if;if secret is null then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
  insert into private.message_provider(id,sender,secret_id,enabled,updated_by) values(true,p_data->>'sender',secret,true,auth.uid()) on conflict(id) do update set sender=excluded.sender,secret_id=excluded.secret_id,enabled=true,updated_by=auth.uid(),updated_at=now();perform cron.schedule('coco-message-dispatch','* * * * *','select private.message_dispatch()');return jsonb_build_object('enabled',true);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_collections_schedule(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_collections_schedule(p_action,p_data)$$;
revoke all on function private.message_draft_valid(private.message_outbox),private.gama_collections_schedule(text,jsonb),public.gama_collections_schedule(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_collections_schedule(text,jsonb),public.gama_collections_schedule(text,jsonb) to authenticated;

create or replace function private.message_dispatch() returns jsonb language plpgsql security definer set search_path='' as $$
declare message private.message_outbox;provider private.message_provider;rule private.automation_rules;job private.automation_jobs;response record;key text;response_payload jsonb;valid boolean;status text;n integer:=0;request bigint;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-message-dispatch',0)) then return jsonb_build_object('busy',true);end if;
 select * into provider from private.message_provider where id and enabled;if not found then return jsonb_build_object('configured',false,'mode','manual','dispatched',0);end if;
 select decrypted_secret into key from vault.decrypted_secrets where id=provider.secret_id;if nullif(key,'') is null then return jsonb_build_object('configured',false,'mode','manual','dispatched',0);end if;
 for message in select * from private.message_outbox where automatic_collection and collection_step is not null and state in ('queued','dispatching','accepted') and coalesce(next_poll_at,created_at)<=now() order by created_at,id limit 25 for update skip locked loop
  if message.state='dispatching' then
   select * into response from net._http_response where id=message.request_id;
   if not found and message.lease_until>now() then continue;end if;
   if found and response.status_code=200 then
    response_payload:=response.content::jsonb;if coalesce(response_payload->>'id','')~'^[0-9a-f-]{36}$' then update private.message_outbox set state='accepted',provider_id=response_payload->>'id',request_id=null,next_poll_at=now()+interval '10 minutes',lease_until=null,updated_at=now() where id=message.id;continue;end if;
   end if;
   if message.attempts>=5 or message.first_sent_at<now()-interval '23 hours' then update private.message_outbox set state='uncertain',error_code='PROVIDER_CONFIRMATION_REQUIRED',lease_until=null,updated_at=now() where id=message.id;continue;end if;
   update private.message_outbox set state='queued',request_id=null,lease_until=null,next_poll_at=now()+interval '5 minutes',error_code='PROVIDER_RETRY',updated_at=now() where id=message.id;continue;
  elsif message.state='accepted' then
   if message.request_id is not null then
    select * into response from net._http_response where id=message.request_id;
    if found and response.status_code=200 then
     response_payload:=response.content::jsonb;status:=response_payload->>'last_event';
     if status in ('delivered','bounced','complained','failed') then update private.message_outbox set state=status,request_id=null,lease_until=null,updated_at=now() where id=message.id;continue;end if;
    elsif not found and message.lease_until>now() then continue;end if;
   end if;
   if message.first_sent_at<now()-interval '7 days' then update private.message_outbox set state='uncertain',error_code='DELIVERY_STATUS_UNCONFIRMED',request_id=null,updated_at=now() where id=message.id;continue;end if;
   request:=net.http_get(url:='https://api.resend.com/emails/'||message.provider_id,headers:=jsonb_build_object('Authorization','Bearer '||key),timeout_milliseconds:=10000);
   update private.message_outbox set request_id=request,lease_until=now()+interval '2 minutes',next_poll_at=now()+interval '10 minutes',updated_at=now() where id=message.id;continue;
  end if;
  -- Check the current rule, actor, rights, customer preference, source balance
  -- and recipient immediately before dispatch; a changed email requires review.
  select * into job from private.automation_jobs where id=message.job_id for update;select * into rule from private.automation_rules where kind=job.kind order by version desc limit 1;
  valid:=private.message_draft_valid(message);
  if not valid then update private.message_outbox set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where id=message.id;continue;end if;
  begin
   update private.automation_jobs set state='running' where id=job.id;
   perform set_config('request.jwt.claim.sub',message.actor::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',message.actor,'role','authenticated')::text,true);
   insert into private.automation_execution_context(backend,transaction,job_id,actor) values(pg_backend_pid(),txid_current(),job.id,message.actor);
   if not private.erp_mfa_ok() or not private.automation_visible(case message.kind when 'survey' then 'surveys' else 'payments' end) or not private.erp_action_allowed(case message.kind when 'survey' then 'surveys' else 'payments' end,case message.kind when 'survey' then 'edit' else 'create' end) then raise exception 'DELEGATION_ACCESS_REVOKED';end if;
   response_payload:=jsonb_build_object('from',provider.sender,'to',jsonb_build_array(message.recipient),'subject',message.subject,'text',message.body);
   request:=net.http_post(url:='https://api.resend.com/emails',body:=response_payload,headers:=jsonb_build_object('Authorization','Bearer '||key,'Content-Type','application/json','Idempotency-Key','coco-'||message.id),timeout_milliseconds:=10000);
   update private.message_outbox set state='dispatching',request_id=request,attempts=attempts+1,first_sent_at=coalesce(first_sent_at,now()),lease_until=now()+interval '2 minutes',next_poll_at=now()+interval '1 minute',updated_at=now() where id=message.id;
   delete from private.automation_execution_context where backend=pg_backend_pid() and transaction=txid_current();update private.automation_jobs set state=job.state where id=job.id;n:=n+1;
  exception when others then update private.message_outbox set state='failed',error_code='DISPATCH_ACCESS_OR_REQUEST_FAILED',updated_at=now() where id=message.id;
  end;
  perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
 end loop;return jsonb_build_object('dispatched',n);end $$;
revoke all on function private.message_dispatch() from public,anon,authenticated,service_role;



create trigger planning_audit after insert or update or delete on private.collection_holds for each row execute function private.erp_audit_capture();
