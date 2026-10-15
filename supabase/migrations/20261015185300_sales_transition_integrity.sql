-- A quote may need a credit exception before its order exists. Bind the
-- administrator's decision to the immutable quote and exact customer exposure.
create table private.sales_quote_credit_reviews(
 quote_id uuid primary key references public.invoices(id),fingerprint text not null,revision integer not null,
 requested_by uuid not null references auth.users(id),requested_at timestamptz not null default now(),
 approved_by uuid references auth.users(id),approved_at timestamptz,reason text not null check(length(btrim(reason))>=3),
 exposure numeric(18,2) not null,order_amount numeric(18,2) not null);
alter table private.sales_quote_credit_reviews enable row level security;
revoke all on private.sales_quote_credit_reviews from public,anon,authenticated;
create function private.sales_quote_credit_context(p_quote uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare q public.invoices;s jsonb;candidate_commitment numeric;before_exposure numeric;review private.sales_quote_credit_reviews;fp text;begin
 select * into q from public.invoices where id=p_quote;if not found then raise exception 'QUOTE_NOT_FOUND';end if;
 s:=private.gama_credit_snapshot(q.customer_id);
 select coalesce(sum(greatest(0,coalesce((select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) from public.sales_order_lines l where l.order_id=o.id),0)
  -coalesce((select sum(a.subtotal+a.tax) from private.sales_invoice_orders a join public.external_invoices i on i.id=a.invoice_id where a.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0)
  -coalesce((select sum(i.total) from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected') and not exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id)),0))),0)
  into candidate_commitment from public.sales_orders o where o.source_quote_id=q.id and o.status='confirmed';
 before_exposure:=(s->>'exposure')::numeric-candidate_commitment;
 fp:=md5(jsonb_build_object('quote',private.sales_quote_fingerprint(q.id),'existing_exposure',before_exposure,'overdue',s->'overdue','limit',s->'credit_limit','hold',s->'hold_reason')::text);
 select * into review from private.sales_quote_credit_reviews where quote_id=q.id;
 return jsonb_build_object('fingerprint',fp,'quote_id',q.id,'revision',q.quote_revision,'existing_exposure',before_exposure,'order_amount',q.total,
  'exposure',before_exposure+q.total,'credit_limit',s->'credit_limit','overdue',s->'overdue','hold_reason',s->'hold_reason',
  'blocked',nullif(s->>'hold_reason','') is not null or jsonb_array_length(s->'overdue')>0 or
   ((s->>'credit_limit')::numeric is not null and before_exposure+q.total>(s->>'credit_limit')::numeric),
  'approved',review.approved_by is not null and review.fingerprint=fp,'requested',review.quote_id is not null and review.fingerprint=fp);
end $$;
create function private.sales_quote_credit_allowed(p_quote uuid) returns boolean language sql volatile security definer set search_path='' as $$
 select coalesce((private.sales_quote_credit_context(p_quote)->>'approved')::boolean,false)
 and exists(select 1 from private.sales_quote_credit_reviews r join public.profiles p on p.id=r.approved_by
 where r.quote_id=p_quote and p.active and p.role='administrador');
$$;
create or replace function private.gama_customer_credit_order_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and (tg_op='INSERT' or old.status='draft' or new.customer_id is distinct from old.customer_id) then
  if new.source_quote_id is not null and private.sales_quote_credit_allowed(new.source_quote_id) then return new;end if;
  perform private.gama_enforce_customer_credit(new.customer_id,new.id,tg_op='UPDATE' and new.customer_id is not distinct from old.customer_id);
 end if;return new;
end $$;
create or replace function private.gama_enforce_customer_credit(p_customer uuid,p_order uuid,p_allow_exception boolean default true) returns void
language plpgsql security definer set search_path='' as $$
declare s jsonb;qid uuid;begin
 perform 1 from public.customers where id=p_customer for update;s:=private.gama_credit_snapshot(p_customer,p_order);
 if coalesce((s->>'blocked')::boolean,false) then
  if p_allow_exception and exists(select 1 from public.erp_approvals a where a.module='credit' and a.document_id=p_order and a.status='approved' and a.fingerprint=private.erp_document_fingerprint('credit',p_order)) then return;end if;
  select source_quote_id into qid from public.sales_orders where id=p_order and customer_id=p_customer;
  if p_allow_exception and qid is not null and private.sales_quote_credit_allowed(qid) then return;end if;
  raise exception 'APPROVAL_REQUIRED:credit:%',p_order;
 end if;
end $$;
alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_credit;
revoke all on function private.gama_sales_dossier_before_credit(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare review jsonb;q public.invoices;role_name text;begin
 if p_action in ('quote_credit_review','quote_credit_request','quote_credit_approve') then
  perform private.sales_access('quote');
  if not private.erp_module_allowed('quotes',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  perform pg_advisory_xact_lock(741932,1);select * into q from public.invoices where id=(p_data->>'quote_id')::uuid for update;
  if not found then raise exception 'QUOTE_NOT_FOUND';end if;
  perform 1 from public.customers where id=q.customer_id for update;review:=private.sales_quote_credit_context(q.id);
  if p_action='quote_credit_review' then return review;end if;
  if q.quote_state<>'sent' or q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if p_action='quote_credit_approve' and (private.current_user_role()<>'administrador' or not private.erp_action_allowed('sales-orders','validate')) then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  if p_data->>'fingerprint' is distinct from review->>'fingerprint' then raise exception 'RECORD_CHANGED';end if;
  insert into private.sales_quote_credit_reviews(quote_id,fingerprint,revision,requested_by,approved_by,approved_at,reason,exposure,order_amount)
   values(q.id,review->>'fingerprint',q.quote_revision,auth.uid(),case when p_action='quote_credit_approve' then auth.uid() end,
   case when p_action='quote_credit_approve' then now() end,p_data->>'reason',(review->>'exposure')::numeric,q.total)
   on conflict(quote_id) do update set fingerprint=excluded.fingerprint,revision=excluded.revision,requested_by=excluded.requested_by,requested_at=now(),
    approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason,exposure=excluded.exposure,order_amount=excluded.order_amount;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) values(q.id,q.quote_revision,p_action,auth.uid(),
   jsonb_build_object('reason',p_data->>'reason','exposure',review->'exposure','order_amount',q.total,'source','sales_credit_review'));
  return private.sales_quote_credit_context(q.id);
 end if;return private.gama_sales_dossier_before_credit(p_action,p_data);
end $$;
revoke all on function private.gama_sales_dossier(text,jsonb) from public,anon;grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;
revoke all on function private.sales_quote_credit_context(uuid),private.sales_quote_credit_allowed(uuid) from public,anon,authenticated;

-- A retry of quote creation must not rewrite an offer that has since been sent
-- or accepted. Bind new creation keys to actor AND the exact original payload.
create table private.sales_quote_command_receipts(
 request_key uuid primary key,actor_id uuid not null references auth.users(id),payload jsonb not null,response jsonb not null);
alter table private.sales_quote_command_receipts enable row level security;
revoke all on private.sales_quote_command_receipts from public,anon,authenticated;
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_quote_action(text,jsonb)'::regprocedure) into src;
 old:='declare result jsonb;';
 if strpos(src,old)=0 then raise exception 'SALES_QUOTE_RECEIPT_DECLARATION';end if;
 src:=replace(src,old,'declare incoming jsonb:=p_data;receipt private.sales_quote_command_receipts;existing public.invoices;result jsonb;');
 old:='if p_action=''save'' then';
 src:=overlay(src placing 'if p_action=''save'' and nullif(p_data->>''id'','''') is null then
 select * into existing from public.invoices where quote_request_key=nullif(p_data->>''request_key'','''')::uuid;
 if found then
  select * into receipt from private.sales_quote_command_receipts where request_key=existing.quote_request_key;
  if found then
   if receipt.actor_id<>auth.uid() or receipt.payload<>incoming then raise exception ''REQUEST_KEY_REUSED'';end if;
   return receipt.response;
  end if;
  if existing.user_id<>auth.uid() then raise exception ''REQUEST_KEY_REUSED'';end if;
  return jsonb_build_object(''id'',existing.id,''dossier_id'',existing.id,''revision'',existing.quote_revision,''state'',existing.quote_state);
 end if;end if;
 '||old from strpos(src,old) for length(old));
 src:=replace(src,'blocks:=coalesce(p_data->''offer_blocks'',''[]'');',
  'blocks:=coalesce(p_data->''offer_blocks'',(select e.blocks from private.sales_quote_extras e where e.quote_id=nullif(p_data->>''id'','''')::uuid),''[]'');');
 old:='return result||jsonb_build_object(''dossier_id'',qid);';
 if strpos(src,old)=0 then raise exception 'SALES_QUOTE_RECEIPT_RESULT';end if;
 src:=replace(src,old,'if p_action=''save'' and nullif(incoming->>''id'','''') is null then
 insert into private.sales_quote_command_receipts(request_key,actor_id,payload,response) values((incoming->>''request_key'')::uuid,auth.uid(),incoming,result||jsonb_build_object(''dossier_id'',qid));end if;'||old);
 execute src;
end $$;
