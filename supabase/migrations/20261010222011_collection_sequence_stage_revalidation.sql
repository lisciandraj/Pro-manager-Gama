-- On resuming a queue, only the currently due stage may be dispatched.
-- Already prepared invoices must not consume the next batch's 200 slots.
alter function private.message_draft_valid(private.message_outbox) rename to message_valid_before_stage_check;
create function private.message_draft_valid(m private.message_outbox) returns boolean language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;stage integer;begin
 if not private.message_valid_before_stage_check(m) then return false;end if;
 if m.collection_step is null then return true;end if;
 select max(x.value::integer) into stage from private.automation_rules r cross join lateral jsonb_array_elements_text(r.config->'steps')x where r.kind='reminders' and r.version=m.rule_version and today>=m.maturity_date+x.value::integer and (x.value::integer>=0 or today<=m.maturity_date);
 return m.collection_step is not distinct from stage;
end $$;
revoke all on function private.message_draft_valid(private.message_outbox),private.message_valid_before_stage_check(private.message_outbox) from public,anon,authenticated,service_role;

create or replace function private.automation_reminders(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row record;n integer:=0;changed integer;step integer;today date:=(now() at time zone private.erp_timezone())::date;steps jsonb:=coalesce(p_config->'steps','[-3,7,14,30]'::jsonb);lang text:=coalesce(p_config->>'language','es');mode text:=coalesce(p_config->>'delivery_mode','manual');subject text;body text;company text;currency text;begin
 if not (p_config ? 'steps') then return private.automation_reminders_before_sequences(p_job,p_config);end if;
 if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(steps)<>'array' or jsonb_array_length(steps) not between 1 and 8 or exists(select 1 from jsonb_array_elements_text(steps)x where x!~'^-?[0-9]{1,3}$' or x::integer not between -30 and 180) then raise exception 'INVALID_SEQUENCE';end if;
 if mode not in ('manual','automatic') or lang not in ('es','fr','en') then raise exception 'INVALID_SEQUENCE';end if;
 if mode='automatic' and not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 select coalesce(nullif(legal_name,''),'Coco ERP'),c.currency into company,currency from public.company_settings c where id;
 update private.message_outbox m set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where collection_step is not null and state in ('draft','queued') and not private.message_draft_valid(m);
 for row in select r.*,c.email outbound_email,d.maturity,stage.step stage from private.gama_receivables r join public.customers c on c.id=r.customer_id and c.active join private.customer_message_preferences p on p.customer_id=c.id and p.invoice_reminders join lateral(select min(d.due_date) maturity from private.gama_customer_dues(c.id,array[r.id])d where d.balance>0)d on d.maturity is not null join lateral(select max(value::integer) step from jsonb_array_elements_text(steps) where today>=d.maturity+value::integer and (value::integer>=0 or today<=d.maturity))stage on stage.step is not null
 where r.balance>0 and c.email~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' and not exists(select 1 from private.collection_holds h where h.invoice_id=r.id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) and not exists(select 1 from private.message_outbox m where m.key='sequence:'||r.id||':'||d.maturity||':'||stage.step and not (m.state='cancelled' and m.attempts=0 and m.manual_sent_at is null)) order by d.maturity,r.id limit 200 loop
  step:=row.stage;
  if step is null then continue;end if;
  subject:=company||' · '||case lang when 'fr' then 'Rappel de facture ' when 'en' then 'Invoice reminder ' else 'Recordatorio de factura ' end||row.number;
  body:=case lang when 'fr' then 'Bonjour '||row.customer_name||E',\nFacture : '||row.number||E'\nÉchéance : '||row.maturity||E'\nSolde restant : '||currency||' '||row.balance||E'\nSi vous avez déjà réglé cette facture, merci de nous transmettre la preuve de paiement.' when 'en' then 'Hello '||row.customer_name||E',\nInvoice: '||row.number||E'\nDue date: '||row.maturity||E'\nOutstanding: '||currency||' '||row.balance||E'\nIf you have already paid, please send us the payment confirmation.' else 'Hola '||row.customer_name||E',\nFactura: '||row.number||E'\nVencimiento: '||row.maturity||E'\nSaldo pendiente: '||currency||' '||row.balance||E'\nSi ya has pagado, envíanos el comprobante para actualizar el registro.' end;
  insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,source_amount,subject,body,state,collection_step,maturity_date,automatic_collection)
  values('sequence:'||row.id||':'||row.maturity||':'||step,'invoice_reminder',row.customer_id,row.id,p_job.id,auth.uid(),p_job.rule_version,row.outbound_email,row.balance,subject,body,case mode when 'automatic' then 'queued' else 'draft' end,step,row.maturity,mode='automatic')
  on conflict(key) do update set job_id=excluded.job_id,actor=excluded.actor,rule_version=excluded.rule_version,recipient=excluded.recipient,source_amount=excluded.source_amount,subject=excluded.subject,body=excluded.body,state=excluded.state,automatic_collection=excluded.automatic_collection,error_code=null,updated_at=now() where message_outbox.state='cancelled' and message_outbox.attempts=0 and message_outbox.manual_sent_at is null;
  get diagnostics changed=row_count;n:=n+changed;
 end loop;return jsonb_build_object('prepared',n,'mode',mode);end $$;
