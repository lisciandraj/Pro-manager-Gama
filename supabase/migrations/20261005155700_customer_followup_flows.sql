-- Real email dispatch is opt-in and requires a verified provider/domain. Until
-- configured, jobs expose a setup exception. Private sources are never guessed.
create extension if not exists pg_net with schema extensions;
create table private.customer_message_preferences(customer_id uuid primary key references public.customers(id),invoice_reminders boolean not null default false,surveys boolean not null default false,evidence text not null,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index customer_message_preference_actor on private.customer_message_preferences(updated_by);
create table private.message_provider(id boolean primary key default true check(id),enabled boolean not null default false,sender text not null,secret_id uuid not null,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index message_provider_actor on private.message_provider(updated_by);
create table private.message_outbox(id uuid primary key default gen_random_uuid(),key text not null unique,kind text not null check(kind in ('invoice_reminder','survey')),customer_id uuid not null references public.customers(id),source_id uuid not null,job_id uuid not null references private.automation_jobs(id),actor uuid not null references public.profiles(id),rule_version integer not null,recipient text not null,source_amount numeric,subject text not null,body text not null,state text not null default 'queued' check(state in ('queued','dispatching','accepted','delivered','bounced','complained','failed','cancelled','uncertain')),request_id bigint,provider_id text,attempts integer not null default 0,first_sent_at timestamptz,next_poll_at timestamptz,lease_until timestamptz,error_code text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index message_outbox_customer on private.message_outbox(customer_id);
create index message_outbox_job on private.message_outbox(job_id);
create index message_outbox_actor on private.message_outbox(actor);
create index message_outbox_due on private.message_outbox(state,next_poll_at,created_at);
create index message_outbox_source on private.message_outbox(kind,source_id);
do $$declare t text;begin foreach t in array array['customer_message_preferences','message_provider','message_outbox'] loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end $$;

create function private.gama_messages(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare customer uuid:=(p_data->>'customer_id')::uuid;secret uuid;conf private.message_provider;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object('provider',(select jsonb_build_object('enabled',enabled,'sender',sender,'configured',true) from private.message_provider where id),'outbox',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select id,kind,customer_id,source_id,state,subject,attempts,error_code,created_at,updated_at from private.message_outbox order by created_at desc,id limit 100)z));
 elsif p_action='configure' then
  if not private.erp_action_allowed('access-settings','edit') or p_data->>'sender' !~ '^[^\r\n<>]+@[^\r\n<>]+\.[^\r\n<>]+$' or length(coalesce(p_data->>'api_key','')) not between 10 and 300 then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
  select * into conf from private.message_provider where id for update;
  if conf.secret_id is null then secret:=vault.create_secret(p_data->>'api_key','coco_email_provider');else secret:=conf.secret_id;perform vault.update_secret(secret,p_data->>'api_key');end if;
  insert into private.message_provider(id,sender,secret_id,enabled,updated_by) values(true,p_data->>'sender',secret,coalesce((p_data->>'enabled')::boolean,false),auth.uid()) on conflict(id) do update set sender=excluded.sender,secret_id=excluded.secret_id,enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('configured',true);
 elsif p_action='preferences' then return coalesce((select jsonb_build_object('invoice_reminders',invoice_reminders,'surveys',surveys) from private.customer_message_preferences where customer_id=customer),'{"invoice_reminders":false,"surveys":false}'::jsonb);
 elsif p_action='preferences_save' then
  if not private.erp_action_allowed('access-settings','edit') or length(btrim(coalesce(p_data->>'evidence','')))<3 or not exists(select 1 from public.customers where id=customer and active) then raise exception 'PREFERENCE_EVIDENCE_REQUIRED';end if;
  insert into private.customer_message_preferences(customer_id,invoice_reminders,surveys,evidence,updated_by) values(customer,coalesce((p_data->>'invoice_reminders')::boolean,false),coalesce((p_data->>'surveys')::boolean,false),p_data->>'evidence',auth.uid()) on conflict(customer_id) do update set invoice_reminders=excluded.invoice_reminders,surveys=excluded.surveys,evidence=excluded.evidence,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_messages(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_messages(p_action,p_data)$$;
revoke all on function public.gama_messages(text,jsonb),private.gama_messages(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_messages(text,jsonb),private.gama_messages(text,jsonb) to authenticated;

create function private.automation_reminders(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row record;days integer:=greatest(1,least(coalesce((p_config->>'interval_days')::integer,7),90));n integer:=0;slot bigint:=floor(extract(epoch from now())/(86400*days));begin
 if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 for row in select r.*,c.email outbound_email from private.gama_receivables r join public.customers c on c.id=r.customer_id join private.customer_message_preferences p on p.customer_id=c.id and p.invoice_reminders where c.active and r.balance>0 and r.due_date<current_date and c.email~'^[^\s@]+@[^\s@]+\.[^\s@]+$' order by r.due_date,r.id limit 100 loop
  insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,source_amount,subject,body) values('invoice:'||row.id||':'||slot,'invoice_reminder',row.customer_id,row.id,p_job.id,auth.uid(),p_job.rule_version,row.outbound_email,row.balance,'GAMA · saldo pendiente '||row.number,'Hola '||row.customer_name||E',\nLa factura '||row.number||' tiene un saldo pendiente de USD '||row.balance||E'.\nSi ya has pagado, envíanos el comprobante para actualizar el registro.\nPuedes consultar tus documentos en https://gama-coco.pages.dev/b2b.html') on conflict(key) do nothing;n:=n+1;
 end loop;return jsonb_build_object('prepared',n);end $$;
create function private.automation_service_followup(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare ticket public.service_tickets;n integer:=0;begin
 if not private.service_access('sav') then raise exception 'ROLE_NOT_ALLOWED';end if;
 update private.automation_exceptions e set active=false,resolved_at=now(),updated_at=now() where e.kind='service_followup' and e.active and not exists(select 1 from public.service_tickets s where s.id=e.source_id and not s.archived and s.status not in ('resolved','closed') and coalesce(s.resolution_due_at,s.due_date::timestamptz)<now());
 for ticket in select * from public.service_tickets where not archived and status not in ('resolved','closed') and coalesce(resolution_due_at,due_date::timestamptz)<now() order by created_at,id limit 200 loop
  perform private.automation_exception('service-followup:'||ticket.id,'service_followup','returns','service_ticket',ticket.id,'SERVICE_SLA_OVERDUE',p_job.id,ticket.erp_reference);
  update private.automation_exceptions set assigned_to=coalesce(assigned_to,ticket.assigned_to),next_action=coalesce(nullif(next_action,''),'Revisar SLA, recepción y resolución del caso') where key='service-followup:'||ticket.id;n:=n+1;
 end loop;return jsonb_build_object('followups',n);end $$;
create function private.automation_surveys(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid:=nullif(p_config->>'survey_id','')::uuid;s private.surveys;row record;inv jsonb;n integer:=0;begin
 if not private.erp_action_allowed('surveys','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into s from private.surveys where id=sid and state='open' and (closes_at is null or closes_at>now());if not found then return jsonb_build_object('blocked',true,'reason','PUBLISHED_SURVEY_REQUIRED');end if;
 if not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 for row in select distinct c.id,c.email from public.customers c join private.customer_message_preferences pref on pref.customer_id=c.id and pref.surveys where c.active and c.email~'^[^\s@]+@[^\s@]+\.[^\s@]+$' and (exists(select 1 from public.tms_deliveries d where d.customer_id=c.id and d.status='Entregada' and d.delivery_date>=current_date-30) or exists(select 1 from public.service_tickets t where t.customer_id=c.id and t.status in ('resolved','closed') and t.resolved_at>=now()-interval '30 days')) order by c.id limit 100 loop
  inv:=private.gama_surveys('invite',jsonb_build_object('id',sid,'kind','customer','contact_id',row.id));
  if not exists(select 1 from private.survey_responses where invitation_id=(inv->>'id')::uuid) then
   insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,subject,body) values('survey:'||(inv->>'id'),'survey',row.id,(inv->>'id')::uuid,p_job.id,auth.uid(),p_job.rule_version,row.email,'GAMA · '||s.title,E'Gracias por confiar en GAMA. Puedes compartir tu experiencia aquí:\nhttps://gama-coco.pages.dev/surveys.html#'||(inv->>'token')) on conflict(key) do nothing;n:=n+1;
  end if;
 end loop;return jsonb_build_object('prepared',n);end $$;

create function private.message_dispatch() returns jsonb language plpgsql security definer set search_path='' as $$
declare message private.message_outbox;provider private.message_provider;rule private.automation_rules;job private.automation_jobs;response record;key text;response_payload jsonb;valid boolean;status text;n integer:=0;request bigint;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-message-dispatch',0)) then return jsonb_build_object('busy',true);end if;
 select * into provider from private.message_provider where id and enabled;if not found then return jsonb_build_object('configured',false);end if;
 select decrypted_secret into key from vault.decrypted_secrets where id=provider.secret_id;if nullif(key,'') is null then return jsonb_build_object('configured',false);end if;
 for message in select * from private.message_outbox where state in ('queued','dispatching','accepted') and coalesce(next_poll_at,created_at)<=now() order by created_at,id limit 25 for update skip locked loop
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
  valid:=rule.enabled and rule.version=message.rule_version and rule.executor=message.actor and rule.approved_until>now() and exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=message.actor and p.active and p.deleted_at is null and p.role='administrador' and (u.banned_until is null or u.banned_until<=now()));
  valid:=coalesce(valid,false) and exists(select 1 from public.customers c join private.customer_message_preferences pref on pref.customer_id=c.id where c.id=message.customer_id and c.active and c.email=message.recipient and case message.kind when 'survey' then pref.surveys else pref.invoice_reminders end);
  if message.kind='invoice_reminder' then valid:=valid and exists(select 1 from private.gama_receivables r where r.id=message.source_id and r.customer_id=message.customer_id and r.balance>0 and r.balance=message.source_amount and r.due_date<current_date);
  else valid:=valid and exists(select 1 from private.survey_invitations i join private.surveys s on s.id=i.survey_id where i.id=message.source_id and not i.revoked and s.state='open' and (s.closes_at is null or s.closes_at>now()) and not exists(select 1 from private.survey_responses r where r.invitation_id=i.id));end if;
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
select cron.schedule('coco-message-dispatch','* * * * *','select private.message_dispatch()');

alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_customer_followup;
revoke all on function private.automation_dispatch_before_customer_followup(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 case p_job.kind when 'reminders' then return private.automation_reminders(p_job,p_config);when 'service_followup' then return private.automation_service_followup(p_job,p_config);when 'survey_followup' then return private.automation_surveys(p_job,p_config);else return private.automation_dispatch_before_customer_followup(p_job,p_config);end case;end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'automation_%' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);end loop;end $$;
-- The asynchronous networking schema is scheduler-only, never exposed to
-- anonymous visitors, staff SQL calls or browser service-role credentials.
revoke all on schema net from public,anon,authenticated,service_role;

alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_preferences;
revoke all on function private.gama_b2b_action_before_preferences(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare cid uuid:=private.gama_b2b_customer();begin
 if p_action='preferences' then return coalesce((select jsonb_build_object('invoice_reminders',invoice_reminders,'surveys',surveys) from private.customer_message_preferences where customer_id=cid),'{"invoice_reminders":false,"surveys":false}'::jsonb);
 elsif p_action='preferences_save' then
  insert into private.customer_message_preferences(customer_id,invoice_reminders,surveys,evidence,updated_by) values(cid,coalesce((p_data->>'invoice_reminders')::boolean,false),coalesce((p_data->>'surveys')::boolean,false),'Solicitud del titular desde el portal B2B',auth.uid()) on conflict(customer_id) do update set invoice_reminders=excluded.invoice_reminders,surveys=excluded.surveys,evidence=excluded.evidence,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;return private.gama_b2b_action_before_preferences(p_action,p_data);end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;
