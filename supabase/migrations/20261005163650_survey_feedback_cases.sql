-- A rating is only a satisfaction signal when an administrator explicitly
-- selects that rating question. Quiz scores and anonymous replies are excluded.
insert into private.automation_catalog(kind,module,title,interval_minutes,delegated) values('survey_feedback','surveys','Satisfacción negativa a reclamación SAV',60,true);
insert into private.automation_rules(kind,version,enabled,config) values('survey_feedback',1,false,'{}');
create table private.survey_service_links(response_id uuid primary key references private.survey_responses(id),ticket_id uuid not null unique references public.service_tickets(id),created_at timestamptz not null default now());
alter table private.survey_service_links enable row level security;
revoke all on private.survey_service_links from public,anon,authenticated,service_role;
create function private.automation_survey_feedback(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid:=nullif(p_config->>'survey_id','')::uuid;qid text:=p_config->>'rating_question_id';question jsonb;row record;ticket uuid;n integer:=0;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('surveys',array['administrador']) or not private.erp_action_allowed('surveys','edit') or not private.service_access('sav') or not private.erp_action_allowed('sav','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select q into question from private.surveys s cross join jsonb_array_elements(s.questions) q where s.id=sid and not s.quiz and q->>'id'=qid and q->>'type'='rating';
 if question is null then return jsonb_build_object('blocked',true,'reason','SATISFACTION_RATING_QUESTION_REQUIRED');end if;
 for row in select r.id,r.answers->>qid rating,i.customer_id,c.name from private.survey_responses r join private.survey_invitations i on i.id=r.invitation_id and i.survey_id=r.survey_id join public.customers c on c.id=i.customer_id and c.active where r.survey_id=sid and r.answers->>qid in ('1','2') and not exists(select 1 from private.survey_service_links l where l.response_id=r.id) order by r.created_at,r.id limit 50 for update of r skip locked loop
  ticket:=private.automation_key('survey-feedback:'||row.id);
  insert into public.service_tickets(id,subject,description,customer_id,priority,category,created_by) values(ticket,'Seguimiento de satisfacción · '||row.name,'Respuesta a la pregunta '||(question->>'title')||': '||row.rating||'/5. Contactar al cliente, confirmar el motivo y acordar una resolución.',row.customer_id,'high','other',auth.uid());
  insert into private.survey_service_links(response_id,ticket_id) values(row.id,ticket);
  perform private.automation_exception('survey-feedback:'||row.id,'survey_feedback','sav','service_ticket',ticket,'CUSTOMER_SATISFACTION_FOLLOWUP',p_job.id,(select erp_reference from public.service_tickets where id=ticket));
  n:=n+1;
 end loop;return jsonb_build_object('cases_created',n);end $$;
-- Source events only enqueue when this specific versioned rule is enabled.
create function private.survey_feedback_event() returns trigger language plpgsql security definer set search_path='' as $$begin perform private.automation_enqueue('survey_feedback','survey-response:'||new.id,jsonb_build_object('response_id',new.id),'survey_response',new.id);return new;end $$;
create trigger survey_feedback_event after insert on private.survey_responses for each row execute function private.survey_feedback_event();
alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_feedback;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin if p_job.kind='survey_feedback' then return private.automation_survey_feedback(p_job,p_config);end if;return private.automation_dispatch_before_feedback(p_job,p_config);end $$;
revoke all on function private.automation_dispatch(private.automation_jobs,jsonb),private.automation_dispatch_before_feedback(private.automation_jobs,jsonb),private.automation_survey_feedback(private.automation_jobs,jsonb),private.survey_feedback_event() from public,anon,authenticated,service_role;
