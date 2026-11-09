-- Hosted checkout is opt-in. Provider keys remain in Edge Function secrets.
-- Test events prove transport only and can never create a receipt or order.
create table private.sales_checkout_payment_settings(
 id boolean primary key default true check(id),stripe_enabled boolean not null default false,stripe_livemode boolean not null default false,
 stripe_financial_account_id uuid references public.financial_accounts(id),wire_enabled boolean not null default false,
 wire_financial_account_id uuid references public.financial_accounts(id),wire_instructions text not null default '' check(length(wire_instructions)<=2000),
 version integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id),
 check(not stripe_enabled or stripe_financial_account_id is not null),check(not wire_enabled or (wire_financial_account_id is not null and length(btrim(wire_instructions))>=3))
);
insert into private.sales_checkout_payment_settings(id) values(true);
create table private.sales_checkout_payment_intents(
 id uuid primary key,invitation_id uuid not null references private.sales_checkout_invitations(id),quote_id uuid references public.invoices(id),invoice_id uuid references public.external_invoices(id),
 request_key uuid not null unique,payload_hash text not null,document_hash text not null,revision integer not null,customer_id uuid not null references public.customers(id),
 amount numeric(18,2) not null check(amount>0),amount_cents bigint not null check(amount_cents between 1 and 99999999),currency text not null check(currency ~ '^[A-Z]{3}$'),
 financial_account_id uuid not null references public.financial_accounts(id),payment_method_id uuid references private.accounting_payment_methods(id),
 environment text not null,livemode boolean not null,issuer uuid not null references public.profiles(id),issuer_aal text not null,
 status text not null default 'prepared' check(status in('prepared','session_open','expired','failed','paid_review','posted','test_confirmed','refund_review','dispute_review')),
 session_id text unique,payment_intent_id text unique,paid_on date,receipt_id uuid references public.customer_receipts(id),allocation_key uuid not null default gen_random_uuid(),
 result jsonb,review_code text,early_terms jsonb,reservation_released_at timestamptz,release_reason text,created_at timestamptz not null default now(),expires_at timestamptz not null,updated_at timestamptz not null default now(),
 check((quote_id is not null)<>(invoice_id is not null))
);
create unique index checkout_quote_active_payment on private.sales_checkout_payment_intents(quote_id) where quote_id is not null and status in('prepared','session_open','paid_review');
create unique index checkout_invoice_active_payment on private.sales_checkout_payment_intents(invoice_id) where invoice_id is not null and status in('prepared','session_open','paid_review');
create index checkout_intent_invitation on private.sales_checkout_payment_intents(invitation_id);
create index checkout_intent_customer on private.sales_checkout_payment_intents(customer_id);
create index checkout_intent_account on private.sales_checkout_payment_intents(financial_account_id);
create index checkout_intent_method on private.sales_checkout_payment_intents(payment_method_id);
create index checkout_intent_issuer on private.sales_checkout_payment_intents(issuer);
create index checkout_intent_receipt on private.sales_checkout_payment_intents(receipt_id);
create table private.sales_checkout_provider_events(
 id text primary key check(length(id) between 5 and 200),intent_id uuid references private.sales_checkout_payment_intents(id),event_type text not null,
 object_id text not null,livemode boolean not null,amount_cents bigint,currency text,occurred_at timestamptz not null,
 status text not null,result jsonb,created_at timestamptz not null default now()
);
create index checkout_event_intent on private.sales_checkout_provider_events(intent_id);
create table private.sales_checkout_wire_receipts(
 id uuid primary key default gen_random_uuid(),invitation_id uuid not null references private.sales_checkout_invitations(id),receipt_id uuid not null unique references public.customer_receipts(id),
 amount numeric(18,2) not null check(amount>0),baseline_payment_ids uuid[] not null default '{}',released_at timestamptz,release_reason text,verified_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);
create index checkout_wire_invitation on private.sales_checkout_wire_receipts(invitation_id);
create index checkout_wire_verifier on private.sales_checkout_wire_receipts(verified_by);
create table private.sales_checkout_wire_reports(
 id uuid primary key,invitation_id uuid not null references private.sales_checkout_invitations(id),reference text not null check(length(reference) between 3 and 100),
 reported_on date not null,created_at timestamptz not null default now(),status text not null default 'reported' check(status in('reported','reviewed'))
);
create index checkout_wire_report_invitation on private.sales_checkout_wire_reports(invitation_id,created_at desc);
do $$declare name text;begin foreach name in array array['sales_checkout_payment_settings','sales_checkout_payment_intents','sales_checkout_provider_events','sales_checkout_wire_receipts','sales_checkout_wire_reports'] loop
 execute format('alter table private.%I enable row level security',name);execute format('revoke all on private.%I from public,anon,authenticated,service_role',name);end loop;end $$;

create function private.coco_checkout_payment_staff(p_write boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and private.erp_module_allowed('accounting',array['administrador','comercial'])
 and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false)
 and (not p_write or (coalesce((private.gama_accounting_rights()->>'create')::boolean,false) and coalesce((private.gama_accounting_rights()->>'pay')::boolean,false)
 and private.erp_action_allowed('accounting','create')))
$$;

-- Shared caller-bound capability validation, never delegated to a machine.
create function private.coco_checkout_payment_invitation(p_token text) returns private.sales_checkout_invitations
language plpgsql security definer set search_path='' as $$
declare i private.sales_checkout_invitations;q public.invoices;inv public.external_invoices;begin
 if not coalesce((select environment='production' from private.coco_environment where id),false) and not private.coco_environment_admin() then raise exception 'CHECKOUT_PUBLIC_DISABLED';end if;
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 select * into i from private.sales_checkout_invitations where token_hash=private.coco_checkout_hash(p_token);
 if not found or i.revoked_at is not null then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 if i.invoice_id is not null then
  select * into inv from public.external_invoices where id=i.invoice_id;
  if not found or inv.fiscal_status in('cancelled','rejected') or (inv.invoice_origin='direct' and inv.direct_status<>'posted') or inv.direct_revision<>i.revision then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 else
  select * into q from public.invoices where id=i.quote_id;
  if not found or not coalesce(((q.quote_state='sent' and q.quote_revision=i.revision) or(q.quote_state='accepted' and q.quote_revision=i.revision+1)),false) then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 end if;return i;
end $$;
create function private.coco_checkout_real_funds(p_invitation uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce((select sum(p.amount) from private.sales_checkout_payment_intents p join public.customer_receipts r on r.id=p.receipt_id
 join private.sales_checkout_invitations x on x.id=p.invitation_id join private.sales_checkout_invitations target on target.id=p_invitation
 where p.livemode and p.environment='production' and p.status in('paid_review','posted') and p.reservation_released_at is null and r.status='confirmed'
 and ((target.quote_id is not null and x.quote_id=target.quote_id) or(target.invoice_id is not null and x.invoice_id=target.invoice_id))),0)
 +coalesce((select sum(w.amount) from private.sales_checkout_wire_receipts w join public.customer_receipts r on r.id=w.receipt_id
 join private.sales_checkout_invitations x on x.id=w.invitation_id join private.sales_checkout_invitations target on target.id=p_invitation
 where r.status='confirmed' and w.released_at is null and((target.quote_id is not null and x.quote_id=target.quote_id) or(target.invoice_id is not null and x.invoice_id=target.invoice_id))),0)
$$;
create function private.coco_checkout_payment_due(p_invitation uuid,p_day date default null) returns numeric
language plpgsql stable security definer set search_path='' as $$
declare i private.sales_checkout_invitations;due numeric;manual numeric;begin
 select * into i from private.sales_checkout_invitations where id=p_invitation;
 if i.payment_percent<=0 then return 0;end if;
 if i.invoice_id is not null then
  return (private.coco_early_discount_quote('customer',i.invoice_id,coalesce(p_day,(now() at time zone private.erp_timezone())::date))->>'due')::numeric;
 end if;
 -- A manually paid invoice stemming from this quote also reduces its deposit.
 select coalesce(sum(p.amount),0) into manual from public.external_invoice_payments p join public.external_invoices inv on inv.id=p.invoice_id
 where p.status='confirmed' and inv.fiscal_status not in('cancelled','rejected') and (inv.source_quote_id=i.quote_id or exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id join public.sales_orders o on o.id=ol.order_id where il.invoice_id=inv.id and o.source_quote_id=i.quote_id))
 and not exists(select 1 from private.sales_checkout_payment_intents online join private.sales_checkout_invitations x on x.id=online.invitation_id where online.receipt_id=p.receipt_id and x.quote_id=i.quote_id)
 and not exists(select 1 from private.sales_checkout_wire_receipts w join private.sales_checkout_invitations x on x.id=w.invitation_id where w.receipt_id=p.receipt_id and x.quote_id=i.quote_id and not(p.id=any(w.baseline_payment_ids)));
 due:=round((i.document->>'total')::numeric*i.payment_percent/100,2)-private.coco_checkout_real_funds(i.id)-manual;return greatest(0,due);
end $$;

-- Signature alone does not accept a quote whose agreed deposit is unpaid.
do $$begin execute replace(pg_get_functiondef('private.coco_checkout_confirm(uuid)'::regprocedure),'FUNCTION private.coco_checkout_confirm(', 'FUNCTION private.coco_checkout_confirm_before_payments(');end $$;
revoke all on function private.coco_checkout_confirm_before_payments(uuid) from public,anon,authenticated,service_role;
create or replace function private.coco_checkout_confirm(p_invitation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.sales_checkout_invitations;begin
 select * into i from private.sales_checkout_invitations where id=p_invitation;
 if i.revoked_at is not null then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 if exists(select 1 from private.sales_checkout_payment_intents where quote_id=i.quote_id and status in('refund_review','dispute_review')) then raise exception 'CHECKOUT_PAYMENT_REVIEW_REQUIRED';end if;
 if i.payment_percent>0 and private.coco_checkout_real_funds(i.id)<round((i.document->>'total')::numeric*i.payment_percent/100,2) then raise exception 'CHECKOUT_PAYMENT_REQUIRED';end if;
 return private.coco_checkout_confirm_before_payments(p_invitation);
end $$;
revoke all on function private.coco_checkout_confirm(uuid) from public,anon,authenticated,service_role;

create function private.coco_checkout_payment_public(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare i private.sales_checkout_invitations:=private.coco_checkout_payment_invitation(p_data->>'token');cfg private.sales_checkout_payment_settings;intent private.sales_checkout_payment_intents;
 due numeric;key uuid:=nullif(p_data->>'request_key','')::uuid;ccy text;env text;method uuid;fingerprint text;v_reference text:=btrim(p_data->>'reference');result jsonb;begin
 select * into cfg from private.sales_checkout_payment_settings where id;select environment into env from private.coco_environment where id;
 due:=private.coco_checkout_payment_due(i.id);ccy:=upper(i.document->>'currency');
 if p_action='payment_options' then
  return jsonb_build_object('today',(now() at time zone private.erp_timezone())::date,'due',due,'currency',ccy,'expired',i.expires_at<=now(),'signature_required',i.require_signature and i.signed_at is null,
   'stripe_enabled',cfg.stripe_enabled and i.payment_percent>0,'livemode',cfg.stripe_livemode and env='production',
   'wire_enabled',cfg.wire_enabled and i.payment_percent>0,'wire_instructions',case when cfg.wire_enabled and i.payment_percent>0 then cfg.wire_instructions end,
   'payments',coalesce((select jsonb_agg(jsonb_build_object('status',p.status,'amount',p.amount,'currency',p.currency,'created_at',p.created_at,'livemode',p.livemode,'confirmation_pending',coalesce((p.result->>'confirmation_pending')::boolean,false)) order by p.created_at desc) from private.sales_checkout_payment_intents p where p.invitation_id=i.id),'[]'));
 end if;
 if p_data->>'agree' is distinct from 'true' or p_data->>'pdf_sha256' is distinct from i.pdf_sha256 then raise exception 'CHECKOUT_PAYMENT_CONSENT_REQUIRED';end if;
 if i.expires_at<=now() or i.payment_percent<=0 then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
 if i.require_signature and i.signed_at is null then raise exception 'CHECKOUT_SIGNATURE_REQUIRED';end if;
 if due<=0 then raise exception 'CHECKOUT_NOTHING_DUE';end if;
 if p_action='payment_report_wire' then
  if not cfg.wire_enabled or key is null or v_reference is null or length(v_reference) not between 3 and 100 or nullif(p_data->>'reported_on','') is null or (p_data->>'reported_on')::date>(now() at time zone private.erp_timezone())::date then raise exception 'CHECKOUT_TRANSFER_INVALID';end if;
  if exists(select 1 from private.sales_checkout_wire_reports where id=key and (invitation_id<>i.id or reference<>v_reference or reported_on is distinct from (p_data->>'reported_on')::date)) then raise exception 'REQUEST_KEY_CONFLICT';end if;
  if (select count(*) from private.sales_checkout_wire_reports where invitation_id=i.id and created_at>now()-interval '1 day')>=5 and not exists(select 1 from private.sales_checkout_wire_reports where id=key) then raise exception 'CHECKOUT_TRANSFER_LIMIT';end if;
  insert into private.sales_checkout_wire_reports(id,invitation_id,reference,reported_on) values(key,i.id,v_reference,(p_data->>'reported_on')::date) on conflict(id) do nothing;
  return jsonb_build_object('state','reported','paid',false);
 end if;
 if not exists(select 1 from public.profiles where id=i.issuer and active and deleted_at is null) then raise exception 'CHECKOUT_ISSUER_UNAVAILABLE';end if;
 if p_action<>'payment_prepare' or not cfg.stripe_enabled or key is null then raise exception 'CHECKOUT_PAYMENT_UNAVAILABLE';end if;
 if ccy not in('USD','EUR','GBP','CAD','AUD','CHF','MXN','COP','PEN') or ccy<>(select currency from public.company_settings where id) then raise exception 'CHECKOUT_CURRENCY_UNSUPPORTED';end if;
 if due*100<>round(due*100) or due*100 not between 1 and 99999999 then raise exception 'CHECKOUT_PAYMENT_AMOUNT_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('checkout-pay:'||coalesce(i.quote_id,i.invoice_id)::text,0));
 due:=private.coco_checkout_payment_due(i.id);if due<=0 then raise exception 'CHECKOUT_NOTHING_DUE';end if;
 fingerprint:=private.coco_checkout_hash(jsonb_build_object('invitation',i.id,'provider','stripe')::text);
 select * into intent from private.sales_checkout_payment_intents where request_key=key;
 if found then if intent.invitation_id<>i.id or intent.payload_hash<>fingerprint then raise exception 'REQUEST_KEY_CONFLICT';end if;return jsonb_build_object('id',intent.id,'amount_cents',intent.amount_cents,'currency',intent.currency,'livemode',intent.livemode);end if;
 if exists(select 1 from private.sales_checkout_payment_intents p where coalesce(p.quote_id,p.invoice_id)=coalesce(i.quote_id,i.invoice_id) and p.status in('paid_review','refund_review','dispute_review')) then raise exception 'CHECKOUT_PAYMENT_REVIEW_REQUIRED';end if;
 update private.sales_checkout_payment_intents p set status='expired',updated_at=now() where coalesce(p.quote_id,p.invoice_id)=coalesce(i.quote_id,i.invoice_id) and p.status='prepared' and p.session_id is null and p.expires_at<=now();
 select * into intent from private.sales_checkout_payment_intents p where coalesce(p.quote_id,p.invoice_id)=coalesce(i.quote_id,i.invoice_id) and p.status in('prepared','session_open');
 if found then
  if intent.invitation_id<>i.id and intent.expires_at>now() and intent.document_hash=i.document_hash and not exists(select 1 from private.sales_checkout_invitations x where x.id=intent.invitation_id and x.revoked_at is not null) then raise exception 'CHECKOUT_PAYMENT_PENDING';end if;
  return jsonb_build_object('id',intent.id,'amount_cents',intent.amount_cents,'currency',intent.currency,'livemode',intent.livemode);
 end if;
 if i.expires_at<now()+interval '31 minutes' then raise exception 'CHECKOUT_PAYMENT_EXPIRY_SHORT';end if;
 if not exists(select 1 from public.financial_accounts f where f.id=cfg.stripe_financial_account_id and f.active and f.account_id is not null and f.currency=ccy) then raise exception 'CHECKOUT_FINANCIAL_ACCOUNT_UNAVAILABLE';end if;
 select m.id into method from private.accounting_payment_methods m where m.financial_account_id=cfg.stripe_financial_account_id and m.direction='in' and m.method='card' and m.is_default and m.active;
 if exists(select 1 from private.accounting_payment_methods where id=method and mode='none') then raise exception 'CHECKOUT_PAYMENT_METHOD_UNAVAILABLE';end if;
 insert into private.sales_checkout_payment_intents(id,invitation_id,quote_id,invoice_id,request_key,payload_hash,document_hash,revision,customer_id,amount,amount_cents,currency,financial_account_id,payment_method_id,environment,livemode,issuer,issuer_aal,early_terms,expires_at)
 values(gen_random_uuid(),i.id,i.quote_id,i.invoice_id,key,fingerprint,i.document_hash,i.revision,i.customer_id,due,(due*100)::bigint,ccy,cfg.stripe_financial_account_id,method,env,cfg.stripe_livemode and env='production',i.issuer,i.issuer_aal,(select jsonb_build_object('id',t.id,'version',t.version,'deadline',t.deadline) from private.coco_early_discount_terms t where t.invoice_id=i.invoice_id and t.status='active'),least(i.expires_at,now()+interval '1 day')) returning * into intent;
 return jsonb_build_object('id',intent.id,'amount_cents',intent.amount_cents,'currency',intent.currency,'livemode',intent.livemode);
end $$;

create function private.coco_checkout_post_verified(p_intent uuid,p_actor uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.sales_checkout_payment_intents;i private.sales_checkout_invitations;r jsonb;allocation jsonb;confirmed jsonb;amount numeric;pending boolean:=false;
 actor uuid;aal text;old_sub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');old_claims text:=coalesce(current_setting('request.jwt.claims',true),'');
 old_source text:=coalesce(current_setting('coco.activity_source_type',true),'');old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');begin
 select * into p from private.sales_checkout_payment_intents where id=p_intent for update;select * into i from private.sales_checkout_invitations where id=p.invitation_id;
 if p.status not in('paid_review','posted','test_confirmed') then raise exception 'CHECKOUT_PAYMENT_NOT_VERIFIED';end if;
 if not p.livemode or p.environment<>'production' then return jsonb_build_object('state','test_confirmed','posted',false);end if;
 allocation:=p.result->'allocation';actor:=coalesce(p_actor,p.issuer);aal:=case when p_actor is null then p.issuer_aal else coalesce(auth.jwt()->>'aal','aal1') end;
 if not exists(select 1 from public.profiles where id=actor and active and deleted_at is null) then raise exception 'CHECKOUT_ISSUER_UNAVAILABLE';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','aal',aal)::text,true);
 perform set_config('coco.activity_source_type','erp',true);perform set_config('coco.activity_source_id',p.id::text,true);perform set_config('coco.activity_source_label','Stripe · pago verificado',true);
 if not private.coco_checkout_payment_staff(true) or not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
 if p.receipt_id is null then
  r:=private.gama_receipt_action('receive',jsonb_build_object('request_key',p.id,'customer_id',p.customer_id,'financial_account_id',p.financial_account_id,'amount',p.amount,'paid_at',p.paid_on,'method','card','payment_method_id',p.payment_method_id,'reference','Stripe '||p.session_id,'notes','Pago verificado · enlace '||p.invitation_id::text));
  update private.sales_checkout_payment_intents set receipt_id=(r->>'id')::uuid where id=p.id returning * into p;
 end if;
 if i.invoice_id is not null then
  if exists(select 1 from public.external_invoices inv join private.gama_receivables ar on ar.id=inv.id where inv.id=i.invoice_id and ar.customer_id=p.customer_id and inv.fiscal_status not in('cancelled','rejected')) then
   amount:=least(p.amount,private.coco_checkout_payment_due(i.id,p.paid_on));
   if amount>0 then allocation:=private.gama_receipt_action('allocate',jsonb_build_object('request_key',p.allocation_key,'id',p.receipt_id,'invoice_id',i.invoice_id,'amount',amount));end if;
  else pending:=true;end if;
 elsif i.quote_id is not null and (not i.require_signature or i.signed_at is not null) then
  -- A valid cash receipt remains an advance if stock/credit/approval blocks the order.
  begin
   if exists(select 1 from public.invoices q where q.id=i.quote_id and q.quote_state='sent') then confirmed:=private.coco_checkout_confirm(i.id);update private.sales_checkout_invitations set result=coalesce(result,'{}')||confirmed where id=i.id;end if;
  exception when others then pending:=true;end;
 else pending:=true;end if;
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('request.jwt.claims',old_claims,true);perform set_config('coco.activity_source_type',old_source,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);
 return jsonb_build_object('state','posted','receipt_id',p.receipt_id,'allocation',allocation,'confirmation_pending',pending);
exception when others then
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('request.jwt.claims',old_claims,true);perform set_config('coco.activity_source_type',old_source,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);raise;
end $$;

-- Machine API: only the Edge adapter can bind a Stripe session or submit a
-- signature-verified, minimal event projection. No provider secret is returned.
create function public.coco_checkout_payment_machine(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p private.sales_checkout_payment_intents;i private.sales_checkout_invitations;event private.sales_checkout_provider_events;result jsonb;eid text:=p_data->>'event_id';kind text:=p_data->>'event_type';sid text:=p_data->>'session_id';pid text:=p_data->>'payment_intent';occurred timestamptz;failure text;stale boolean;current_terms jsonb;begin
 if current_setting('role',true)<>'service_role' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='event' then
  if eid is null or eid !~ '^evt_[A-Za-z0-9_]{1,180}$' or length(coalesce(kind,''))>100 then raise exception 'CHECKOUT_EVENT_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended('stripe-event:'||eid,0));
  select * into event from private.sales_checkout_provider_events where id=eid;if found then return event.result;end if;
 end if;
 select * into p from private.sales_checkout_payment_intents where id=nullif(p_data->>'intent_id','')::uuid;
 if not found and p_action='event' and pid is not null then select * into p from private.sales_checkout_payment_intents where payment_intent_id=pid;end if;
 if not found then if p_action='event' then return jsonb_build_object('state','ignored');end if;raise exception 'CHECKOUT_PAYMENT_NOT_FOUND';end if;
 perform pg_advisory_xact_lock(hashtextextended('checkout-pay:'||coalesce(p.quote_id,p.invoice_id)::text,0));
 select * into p from private.sales_checkout_payment_intents where id=p.id for update;select * into i from private.sales_checkout_invitations where id=p.invitation_id;
 if p_action='config' then
  if p.status not in('prepared','session_open') then raise exception 'CHECKOUT_PAYMENT_UNAVAILABLE';end if;
  select jsonb_build_object('id',t.id,'version',t.version,'deadline',t.deadline) into current_terms from private.coco_early_discount_terms t where t.invoice_id=i.invoice_id and t.status='active';
  stale:=p.expires_at<=now() or i.revoked_at is not null or not(select stripe_enabled from private.sales_checkout_payment_settings where id) or private.coco_checkout_payment_due(i.id)<>p.amount or current_terms is distinct from p.early_terms;
  if i.quote_id is not null and not exists(select 1 from public.invoices q where q.id=i.quote_id and ((q.quote_state='sent' and q.quote_revision=i.revision) or(q.quote_state='accepted' and q.quote_revision=i.revision+1))) then stale:=true;end if;
  if i.invoice_id is not null and not exists(select 1 from public.external_invoices x where x.id=i.invoice_id and x.direct_revision=i.revision and x.fiscal_status not in('cancelled','rejected')) then stale:=true;end if;
  return jsonb_build_object('id',p.id,'session_id',p.session_id,'amount_cents',p.amount_cents,'currency',lower(p.currency),'livemode',p.livemode,'expires_at',floor(extract(epoch from p.expires_at))::bigint,'stale',stale,'label',left('Coco · '||(i.document->>'number'),120));
 elsif p_action='expire' then
  if p.status not in('prepared','session_open') or (p.session_id is not null and (p_data->>'session_id' is distinct from p.session_id or p_data->>'provider_status' is distinct from 'expired')) then raise exception 'CHECKOUT_SESSION_MISMATCH';end if;
  update private.sales_checkout_payment_intents set status='expired',updated_at=now() where id=p.id;return jsonb_build_object('state','expired');
 elsif p_action='bind' then
  if sid is null or sid !~ '^cs_(test|live)_[A-Za-z0-9_]{5,200}$' or (p_data->>'livemode')::boolean is distinct from p.livemode or (p_data->>'amount_cents')::bigint is distinct from p.amount_cents or upper(p_data->>'currency') is distinct from p.currency or (p.session_id is not null and p.session_id<>sid) then raise exception 'CHECKOUT_SESSION_MISMATCH';end if;
  if p.status not in('prepared','session_open') then raise exception 'CHECKOUT_PAYMENT_UNAVAILABLE';end if;
  update private.sales_checkout_payment_intents set session_id=sid,status='session_open',updated_at=now() where id=p.id;return jsonb_build_object('id',p.id);
 elsif p_action<>'event' then raise exception 'INVALID_ACTION';end if;
 occurred:=to_timestamp((p_data->>'occurred_at')::bigint);
 if occurred is null or occurred<date '2020-01-01' or occurred>now()+interval '5 minutes' or (p_data->>'livemode')::boolean is distinct from p.livemode then raise exception 'CHECKOUT_EVENT_MISMATCH';end if;
 if kind in('charge.refunded','charge.dispute.created','charge.dispute.closed') then
  if pid is null or (p.payment_intent_id is not null and pid<>p.payment_intent_id) or upper(p_data->>'currency') is distinct from p.currency then raise exception 'CHECKOUT_EVENT_MISMATCH';end if;
  if p.payment_intent_id is null then update private.sales_checkout_payment_intents set payment_intent_id=pid where id=p.id;end if;
  result:=jsonb_build_object('state',case when kind='charge.refunded' then 'refund_review' else 'dispute_review' end,'posted',false,'review_required',true);
  update private.sales_checkout_payment_intents set status=result->>'state',review_code=kind,updated_at=now() where id=p.id;
 else
  if sid is null or (p.session_id is not null and p.session_id<>sid) or (p_data->>'amount_cents')::bigint is distinct from p.amount_cents or upper(p_data->>'currency') is distinct from p.currency then raise exception 'CHECKOUT_EVENT_MISMATCH';end if;
  if p.session_id is null then update private.sales_checkout_payment_intents set session_id=sid where id=p.id;end if;
  if kind in('checkout.session.completed','checkout.session.async_payment_succeeded') and p_data->>'payment_status'='paid' then
   if pid is null or pid !~ '^pi_[A-Za-z0-9_]{3,200}$' then raise exception 'CHECKOUT_EVENT_MISMATCH';end if;
   if p.status in('posted','test_confirmed') then result:=p.result;
   elsif p.status in('refund_review','dispute_review') then result:=jsonb_build_object('state',p.status,'review_required',true);
   else
    update private.sales_checkout_payment_intents set status='paid_review',payment_intent_id=pid,paid_on=(occurred at time zone private.erp_timezone())::date,updated_at=now() where id=p.id;
    begin result:=private.coco_checkout_post_verified(p.id);
    exception when others then get stacked diagnostics failure=returned_sqlstate;result:=jsonb_build_object('state','paid_review','review_required',true);end;
    update private.sales_checkout_payment_intents set status=result->>'state',result=result,review_code=failure,updated_at=now() where id=p.id;
   end if;
  elsif kind in('checkout.session.expired','checkout.session.async_payment_failed') and p.status in('prepared','session_open') then
   result:=jsonb_build_object('state',case when kind='checkout.session.expired' then 'expired' else 'failed' end);update private.sales_checkout_payment_intents set status=result->>'state',updated_at=now() where id=p.id;
  else result:=jsonb_build_object('state',p.status);end if;
 end if;
 insert into private.sales_checkout_provider_events(id,intent_id,event_type,object_id,livemode,amount_cents,currency,occurred_at,status,result)
 values(eid,p.id,kind,coalesce(sid,p_data->>'object_id'),p.livemode,nullif(p_data->>'amount_cents','')::bigint,upper(p_data->>'currency'),occurred,result->>'state',result);return result;
end $$;
revoke all on function public.coco_checkout_payment_machine(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_checkout_payment_machine(text,jsonb) to service_role;

create function private.coco_checkout_payment_staff_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare cfg private.sales_checkout_payment_settings;i private.sales_checkout_invitations;p private.sales_checkout_payment_intents;r public.customer_receipts;wire private.sales_checkout_wire_receipts;
 result jsonb;confirmation jsonb;amount numeric;remaining numeric;invoice uuid:=nullif(p_data->>'invoice_id','')::uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;method uuid;begin
 if p_action='payment_context' then
  if not private.coco_checkout_staff(false) and not private.coco_checkout_payment_staff(false) then raise exception 'NOT_ALLOWED';end if;
  select * into cfg from private.sales_checkout_payment_settings where id;
  return jsonb_build_object('settings',to_jsonb(cfg),'currency',(select currency from public.company_settings where id),'can_pay',private.coco_checkout_payment_staff(true),'can_validate',coalesce((private.gama_accounting_rights()->>'validate')::boolean,false),'can_configure',private.coco_environment_admin() and private.coco_checkout_payment_staff(true),
   'accounts',case when private.coco_checkout_payment_staff(false) then coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'currency',f.currency) order by f.name) from public.financial_accounts f where f.active and f.account_id is not null),'[]') else '[]'::jsonb end,
   'intents',coalesce((select jsonb_agg(to_jsonb(x)-'issuer_aal'-'payload_hash' order by x.created_at desc) from private.sales_checkout_payment_intents x where (p_data->>'quote_id' is not null and x.quote_id=(p_data->>'quote_id')::uuid) or(invoice is not null and x.invoice_id=invoice)),'[]'),
   'wire_receipts',coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from private.sales_checkout_wire_receipts w join private.sales_checkout_invitations x on x.id=w.invitation_id where (p_data->>'quote_id' is not null and x.quote_id=(p_data->>'quote_id')::uuid) or(invoice is not null and x.invoice_id=invoice)),'[]'),
   'invoices',coalesce((select jsonb_agg(jsonb_build_object('id',ar.id,'number',ar.number,'balance',ar.balance)) from private.gama_receivables ar where ar.customer_id=coalesce((select q.customer_id from public.invoices q where q.id=nullif(p_data->>'quote_id','')::uuid),(select x.customer_id from public.external_invoices x where x.id=invoice)) and ar.balance>0 and ar.payment_status<>'cancelled' and (nullif(p_data->>'quote_id','') is null or private.coco_checkout_invoice_link(ar.id,(p_data->>'quote_id')::uuid,null))),'[]'),
   'receipts',case when private.coco_checkout_payment_staff(true) then coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'reference',r.reference,'amount',r.amount,'paid_at',r.paid_at,'available',private.coco_reward_receipt_remaining(r.id,null))) from public.customer_receipts r where r.status='confirmed' and r.customer_id=coalesce((select q.customer_id from public.invoices q where q.id=nullif(p_data->>'quote_id','')::uuid),(select x.customer_id from public.external_invoices x where x.id=invoice)) and private.gama_payment_mode_matched('customer_receipt',r.id) and private.coco_reward_receipt_remaining(r.id,null)>0 and not exists(select 1 from private.sales_checkout_payment_intents p where p.receipt_id=r.id)),'[]') else '[]'::jsonb end,
   'wire_reports',coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from private.sales_checkout_wire_reports w join private.sales_checkout_invitations x on x.id=w.invitation_id where (p_data->>'quote_id' is not null and x.quote_id=(p_data->>'quote_id')::uuid) or(invoice is not null and x.invoice_id=invoice)),'[]'));
 end if;
 if not private.coco_checkout_payment_staff(true) then raise exception 'NOT_ALLOWED';end if;
 if p_action='payment_settings' then
  if not private.coco_environment_admin() or not coalesce((private.gama_accounting_rights()->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') then raise exception 'NOT_ALLOWED';end if;
  select * into cfg from private.sales_checkout_payment_settings where id for update;
  if (p_data->>'version')::integer is distinct from cfg.version then raise exception 'CHECKOUT_SETTINGS_CHANGED';end if;
  if coalesce((p_data->>'stripe_livemode')::boolean,false) and not coalesce((select environment='production' from private.coco_environment where id),false) then raise exception 'CHECKOUT_LIVE_DISABLED';end if;
  if coalesce((p_data->>'stripe_enabled')::boolean,false) and not exists(select 1 from public.financial_accounts f join public.company_settings c on c.id where f.id=nullif(p_data->>'stripe_financial_account_id','')::uuid and f.active and f.account_id is not null and f.currency=c.currency) then raise exception 'CHECKOUT_FINANCIAL_ACCOUNT_UNAVAILABLE';end if;
  if coalesce((p_data->>'wire_enabled')::boolean,false) and (length(btrim(coalesce(p_data->>'wire_instructions',''))) not between 3 and 2000 or not exists(select 1 from public.financial_accounts f join public.company_settings c on c.id where f.id=nullif(p_data->>'wire_financial_account_id','')::uuid and f.active and f.account_id is not null and f.currency=c.currency)) then raise exception 'CHECKOUT_FINANCIAL_ACCOUNT_UNAVAILABLE';end if;
  update private.sales_checkout_payment_settings set stripe_enabled=coalesce((p_data->>'stripe_enabled')::boolean,false),stripe_livemode=coalesce((p_data->>'stripe_livemode')::boolean,false),stripe_financial_account_id=nullif(p_data->>'stripe_financial_account_id','')::uuid,
   wire_enabled=coalesce((p_data->>'wire_enabled')::boolean,false),wire_financial_account_id=nullif(p_data->>'wire_financial_account_id','')::uuid,wire_instructions=coalesce(p_data->>'wire_instructions',''),version=version+1,updated_at=now(),updated_by=auth.uid() where id returning to_jsonb(sales_checkout_payment_settings) into result;return result;
 elsif p_action='payment_release' then
  if not coalesce((private.gama_accounting_rights()->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'NOT_ALLOWED';end if;
  if nullif(p_data->>'intent_id','') is not null then
   select * into p from private.sales_checkout_payment_intents where id=(p_data->>'intent_id')::uuid and status='posted' for update;if not found then raise exception 'CHECKOUT_PAYMENT_NOT_VERIFIED';end if;
   update private.sales_checkout_payment_intents set reservation_released_at=coalesce(reservation_released_at,now()),release_reason=btrim(p_data->>'reason') where id=p.id;
  else
   update private.sales_checkout_wire_receipts set released_at=coalesce(released_at,now()),release_reason=btrim(p_data->>'reason') where id=(p_data->>'wire_id')::uuid returning * into wire;if not found then raise exception 'CHECKOUT_PAYMENT_NOT_VERIFIED';end if;
  end if;return jsonb_build_object('state','released');
 elsif p_action='payment_retry' then
  select * into p from private.sales_checkout_payment_intents where id=(p_data->>'intent_id')::uuid for update;
  if not found or p.status not in('paid_review','posted','test_confirmed') then raise exception 'CHECKOUT_PAYMENT_NOT_VERIFIED';end if;
  result:=private.coco_checkout_post_verified(p.id,auth.uid());update private.sales_checkout_payment_intents set status=result->>'state',result=result,review_code=null,updated_at=now() where id=p.id;return result;
 elsif p_action='payment_allocate' then
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  select * into p from private.sales_checkout_payment_intents where id=(p_data->>'intent_id')::uuid for update;
  if p.status<>'posted' or p.receipt_id is null or not p.livemode or p.environment<>'production' then raise exception 'CHECKOUT_PAYMENT_NOT_VERIFIED';end if;
  if exists(select 1 from public.external_invoice_payments where request_key=key) then
   select to_jsonb(x) into result from public.external_invoice_payments x where x.request_key=key and x.receipt_id=p.receipt_id and x.invoice_id=invoice;if result is null then raise exception 'REQUEST_KEY_CONFLICT';end if;return result;
  end if;
  select * into r from public.customer_receipts where id=p.receipt_id and status='confirmed' for update;if not found then raise exception 'RECEIPT_NOT_AVAILABLE';end if;
  if not exists(select 1 from private.gama_receivables where id=invoice and customer_id=p.customer_id and payment_status<>'cancelled') then raise exception 'INVOICE_NOT_AVAILABLE';end if;
  select r.amount-coalesce(sum(x.amount),0) into remaining from public.external_invoice_payments x where x.receipt_id=r.id and x.status='confirmed';
  amount:=least(remaining,(private.coco_early_discount_quote('customer',invoice,r.paid_at)->>'due')::numeric);
  if amount<=0 then raise exception 'CHECKOUT_NOTHING_DUE';end if;
  return private.gama_receipt_action('allocate',jsonb_build_object('request_key',key,'id',r.id,'invoice_id',invoice,'amount',amount));
 elsif p_action='payment_attach_wire' then
  select * into i from private.sales_checkout_invitations where id=(p_data->>'invitation_id')::uuid for update;if not found then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
  select * into r from public.customer_receipts where id=(p_data->>'receipt_id')::uuid and status='confirmed' and customer_id=i.customer_id for update;if not found then raise exception 'RECEIPT_NOT_AVAILABLE';end if;
  select * into wire from private.sales_checkout_wire_receipts where receipt_id=r.id;if found then if wire.invitation_id<>i.id then raise exception 'REQUEST_KEY_CONFLICT';end if;return jsonb_build_object('id',wire.id);end if;
  if exists(select 1 from private.sales_checkout_payment_intents where receipt_id=r.id) then raise exception 'CHECKOUT_RECEIPT_RESERVED';end if;
  if not private.gama_payment_mode_matched('customer_receipt',r.id) or not exists(select 1 from public.financial_accounts f where f.id=r.financial_account_id and f.currency=i.document->>'currency') then raise exception 'CHECKOUT_WIRE_NOT_VERIFIED';end if;
  remaining:=private.coco_reward_receipt_remaining(r.id,null);amount:=least(remaining,private.coco_checkout_payment_due(i.id,r.paid_at));if amount<=0 then raise exception 'CHECKOUT_NOTHING_DUE';end if;
  insert into private.sales_checkout_wire_receipts(invitation_id,receipt_id,amount,baseline_payment_ids,verified_by) values(i.id,r.id,amount,array(select x.id from public.external_invoice_payments x where x.receipt_id=r.id and x.status='confirmed'),auth.uid()) returning * into wire;
  if i.invoice_id is not null then result:=private.gama_receipt_action('allocate',jsonb_build_object('request_key',wire.id,'id',r.id,'invoice_id',i.invoice_id,'amount',amount));
  elsif not i.require_signature or i.signed_at is not null then begin confirmation:=private.coco_checkout_confirm(i.id);update private.sales_checkout_invitations set result=coalesce(result,'{}')||confirmation where id=i.id;exception when others then confirmation:=jsonb_build_object('confirmation_pending',true);end;end if;
  update private.sales_checkout_wire_reports set status='reviewed' where invitation_id=i.id;return jsonb_build_object('id',wire.id,'allocation',result,'confirmation',confirmation);
 end if;raise exception 'INVALID_ACTION';
end $$;

do $$begin execute replace(pg_get_functiondef('private.coco_sales_checkout(text,jsonb)'::regprocedure),'FUNCTION private.coco_sales_checkout(', 'FUNCTION private.coco_sales_checkout_before_payments(');end $$;
revoke all on function private.coco_sales_checkout_before_payments(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.coco_sales_checkout(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_action like 'payment_%' then return private.coco_checkout_payment_staff_action(p_action,p_data);end if;
 if p_action='create' and coalesce((p_data->>'payment_percent')::numeric,0)>0 and not private.coco_checkout_payment_staff(true) then raise exception 'NOT_ALLOWED';end if;
 return private.coco_sales_checkout_before_payments(p_action,p_data);
end $$;
revoke all on function private.coco_sales_checkout(text,jsonb) from public,anon,service_role;grant execute on function private.coco_sales_checkout(text,jsonb) to authenticated;

do $$begin execute replace(pg_get_functiondef('private.coco_checkout_public(text,jsonb)'::regprocedure),'FUNCTION private.coco_checkout_public(', 'FUNCTION private.coco_checkout_public_before_payments(');end $$;
revoke all on function private.coco_checkout_public_before_payments(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.coco_checkout_public(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i private.sales_checkout_invitations;result jsonb;q public.invoices;begin
 if p_action like 'payment_%' then return private.coco_checkout_payment_public(p_action,p_data);end if;
 i:=private.coco_checkout_payment_invitation(p_data->>'token');
 if i.invoice_id is not null then
  if p_action<>'view' or i.expires_at<=now() then raise exception 'CHECKOUT_LINK_UNAVAILABLE';end if;
  return jsonb_build_object('id',i.id,'document',i.document,'document_hash',i.document_hash,'pdf_sha256',i.pdf_sha256,'expires_at',i.expires_at,'require_signature',false,'payment_percent',i.payment_percent,'signed_at',null,'confirmed',true,'await_payment',private.coco_checkout_payment_due(i.id)>0);
 end if;
 if p_action='view' and not i.require_signature and i.expires_at>now() and exists(select 1 from public.invoices x where x.id=i.quote_id and x.quote_state='accepted' and x.quote_revision=i.revision+1) then
  return jsonb_build_object('id',i.id,'document',i.document,'document_hash',i.document_hash,'pdf_sha256',i.pdf_sha256,'expires_at',i.expires_at,'require_signature',false,'payment_percent',i.payment_percent,'signed_at',null,'confirmed',true,'await_payment',private.coco_checkout_payment_due(i.id)>0);
 end if;
 result:=private.coco_checkout_public_before_payments(p_action,p_data);
 if p_action='view' then result:=result||jsonb_build_object('await_payment',i.payment_percent>0 and private.coco_checkout_real_funds(i.id)<round((i.document->>'total')::numeric*i.payment_percent/100,2));end if;return result;
end $$;
revoke all on function private.coco_checkout_public(text,jsonb) from public,anon,authenticated,service_role;

revoke all on function private.coco_checkout_payment_staff(boolean),private.coco_checkout_payment_invitation(text),private.coco_checkout_real_funds(uuid),private.coco_checkout_payment_due(uuid,date),private.coco_checkout_payment_public(text,jsonb),private.coco_checkout_post_verified(uuid,uuid),private.coco_checkout_payment_staff_action(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.coco_checkout_payment_staff(boolean) to authenticated;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('sales_checkout_payment_settings','accounting','Configuración de cobros a distancia','private','id'),('sales_checkout_payment_intents','accounting','Cobro a distancia','private','id'),
 ('sales_checkout_provider_events','accounting','Confirmación del proveedor de pago','private','id'),('sales_checkout_wire_receipts','accounting','Transferencia verificada','private','id'),('sales_checkout_wire_reports','accounting','Transferencia comunicada por cliente','private','id');
do $$declare name text;begin foreach name in array array['sales_checkout_payment_settings','sales_checkout_payment_intents','sales_checkout_provider_events','sales_checkout_wire_receipts','sales_checkout_wire_reports'] loop execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',name);end loop;end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_checkout_payments(');end $$;
revoke all on function private.coco_history_record_visible_before_checkout_payments(text,text,uuid) from public,anon,service_role;grant execute on function private.coco_history_record_visible_before_checkout_payments(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in('sales_checkout_payment_settings','sales_checkout_payment_intents','sales_checkout_provider_events','sales_checkout_wire_receipts','sales_checkout_wire_reports') then return private.coco_checkout_payment_staff(false);end if;
 return private.coco_history_record_visible_before_checkout_payments(p_table,p_id,p_owner);end $$;

-- One canonical cash budget is shared by advances, stored value and checkout.
create function private.coco_checkout_invoice_link(p_invoice uuid,p_quote uuid,p_target uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select case when p_target is not null then p_invoice=p_target else exists(select 1 from public.external_invoices i where i.id=p_invoice and (i.source_quote_id=p_quote or exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id join public.sales_orders o on o.id=ol.order_id where il.invoice_id=i.id and o.source_quote_id=p_quote))) end
$$;
create function private.coco_checkout_receipt_reserved(p_receipt uuid,p_invoice uuid default null) returns numeric
language sql stable security definer set search_path='' as $$
 with holds as(
  select p.quote_id,p.invoice_id,p.amount,'{}'::uuid[] baseline,p.status in('refund_review','dispute_review') blocked from private.sales_checkout_payment_intents p where p.receipt_id=p_receipt and p.livemode and p.environment='production' and p.reservation_released_at is null
  union all select i.quote_id,i.invoice_id,w.amount,w.baseline_payment_ids,false from private.sales_checkout_wire_receipts w join private.sales_checkout_invitations i on i.id=w.invitation_id where w.receipt_id=p_receipt and w.released_at is null
 )select coalesce(sum(greatest(0,h.amount-coalesce((select sum(x.amount) from public.external_invoice_payments x where x.receipt_id=p_receipt and x.status='confirmed' and not(x.id=any(h.baseline)) and private.coco_checkout_invoice_link(x.invoice_id,h.quote_id,h.invoice_id)),0))) filter(where h.blocked or p_invoice is null or not private.coco_checkout_invoice_link(p_invoice,h.quote_id,h.invoice_id)),0) from holds h
$$;
do $$begin execute replace(pg_get_functiondef('private.coco_reward_receipt_remaining(uuid,uuid)'::regprocedure),'FUNCTION private.coco_reward_receipt_remaining(', 'FUNCTION private.coco_reward_receipt_remaining_before_checkout(');end $$;
revoke all on function private.coco_reward_receipt_remaining_before_checkout(uuid,uuid) from public,anon,authenticated,service_role;
create or replace function private.coco_reward_receipt_remaining(p_receipt uuid,p_invoice uuid default null) returns numeric
language sql stable security definer set search_path='' as $$
 select greatest(0,private.coco_reward_receipt_remaining_before_checkout(p_receipt,p_invoice)-private.coco_checkout_receipt_reserved(p_receipt,p_invoice))
$$;
revoke all on function private.coco_reward_receipt_remaining(uuid,uuid),private.coco_checkout_invoice_link(uuid,uuid,uuid),private.coco_checkout_receipt_reserved(uuid,uuid) from public,anon,authenticated,service_role;
do $$begin execute replace(pg_get_functiondef('private.gama_receipt_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_receipt_action(', 'FUNCTION private.gama_receipt_action_before_checkout(');end $$;
revoke all on function private.gama_receipt_action_before_checkout(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_receipt_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_action='cancel' and private.coco_checkout_receipt_reserved((p_data->>'id')::uuid,null)>0 then raise exception 'CHECKOUT_RECEIPT_RESERVED';end if;
 return private.gama_receipt_action_before_checkout(p_action,p_data);
end $$;
revoke all on function private.gama_receipt_action(text,jsonb) from public,anon,service_role;grant execute on function private.gama_receipt_action(text,jsonb) to authenticated;
