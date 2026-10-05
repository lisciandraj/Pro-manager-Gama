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
