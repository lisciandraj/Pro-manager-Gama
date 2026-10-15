-- Stable commercial identity over the historical quote/order tables. No references
-- are renumbered and no operational or accounting records are recreated.
create table private.sales_dossiers(
 id uuid primary key,quote_id uuid unique references public.invoices(id),
 order_id uuid unique references public.sales_orders(id),created_at timestamptz not null default now(),
 check(id=coalesce(quote_id,order_id)));
create table private.sales_dossier_lines(
 id uuid primary key,dossier_id uuid not null references private.sales_dossiers(id),
 quote_line_id uuid unique references public.invoice_lines(id) on delete set null,
 order_line_id uuid unique references public.sales_order_lines(id),
 invoice_policy text not null check(invoice_policy in ('ordered','delivered')));
create index sales_dossier_lines_dossier on private.sales_dossier_lines(dossier_id);
create table private.sales_product_billing(
 product_id uuid primary key references public.products(id),
 invoice_policy text not null check(invoice_policy in ('ordered','delivered')),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now());
alter table private.sales_workspace_settings add column default_invoice_policy text not null default 'delivered'
 check(default_invoice_policy in ('ordered','delivered'));
create table private.sales_quote_extras(
 quote_id uuid primary key references public.invoices(id),blocks jsonb not null default '[]'
 check(jsonb_typeof(blocks)='array'),updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now());
alter table private.sales_templates add column offer_blocks jsonb not null default '[]';
create table private.sales_activities(
 id uuid primary key default gen_random_uuid(),dossier_id uuid not null references private.sales_dossiers(id),
 kind text not null check(kind in ('call','followup','task','appointment','note')),
 title text not null check(length(btrim(title)) between 1 and 1000),
 owner_id uuid not null references public.profiles(id),due_at timestamptz,completed_at timestamptz,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 request_key uuid not null unique,payload jsonb not null);
create index sales_activities_dossier on private.sales_activities(dossier_id,created_at desc);
create index sales_activities_owner on private.sales_activities(owner_id,due_at) where completed_at is null;
create table private.sales_portal_acceptances(
 quote_id uuid primary key references public.invoices(id),revision integer not null,
 accepted_by uuid not null references auth.users(id),accepted_at timestamptz not null default now(),
 snapshot jsonb not null,processed_order_id uuid references public.sales_orders(id));
do $$declare t text;begin
 foreach t in array array['sales_dossiers','sales_dossier_lines','sales_product_billing','sales_quote_extras','sales_activities','sales_portal_acceptances'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $$;
insert into private.sales_dossiers(id,quote_id,created_at) select id,id,created_at from public.invoices;
insert into private.sales_dossiers(id,order_id,created_at)
 select id,id,created_at from public.sales_orders where source_quote_id is null;
update private.sales_dossiers d set order_id=o.id from public.sales_orders o where o.source_quote_id=d.quote_id;
insert into private.sales_dossier_lines(id,dossier_id,quote_line_id,order_line_id,invoice_policy)
 select ql.id,ql.invoice_id,ql.id,ol.id,'delivered' from public.invoice_lines ql
 left join public.sales_orders o on o.source_quote_id=ql.invoice_id
 left join public.sales_order_lines ol on ol.order_id=o.id and ol.product_id=ql.product_id;
insert into private.sales_dossier_lines(id,dossier_id,order_line_id,invoice_policy)
 select l.id,d.id,l.id,'delivered' from public.sales_order_lines l join private.sales_dossiers d on d.order_id=l.order_id
 where not exists(select 1 from private.sales_dossier_lines x where x.order_line_id=l.id);

create function private.sales_bind_dossier() returns trigger language plpgsql security definer set search_path='' as $$
declare did uuid;ql uuid;policy text;begin
 if tg_table_name='invoices' then
  insert into private.sales_dossiers(id,quote_id,created_at) values(new.id,new.id,new.created_at) on conflict(quote_id) do nothing;
 elsif tg_table_name='sales_orders' then
  if new.source_quote_id is null then
   insert into private.sales_dossiers(id,order_id,created_at) values(new.id,new.id,new.created_at) on conflict(order_id) do nothing;
  else
   insert into private.sales_dossiers(id,quote_id,order_id) values(new.source_quote_id,new.source_quote_id,new.id)
    on conflict(quote_id) do update set order_id=excluded.order_id;
  end if;
 elsif tg_table_name='invoice_lines' then
  select coalesce(b.invoice_policy,s.default_invoice_policy) into policy from private.sales_workspace_settings s
   left join private.sales_product_billing b on b.product_id=new.product_id where s.id;
  insert into private.sales_dossier_lines(id,dossier_id,quote_line_id,invoice_policy) values(new.id,new.invoice_id,new.id,policy);
 else
  select d.id,l.id into did,ql from private.sales_dossiers d left join public.invoice_lines l
   on l.invoice_id=d.quote_id and l.product_id=new.product_id where d.order_id=new.order_id;
  if ql is not null then
   update private.sales_dossier_lines set order_line_id=new.id where quote_line_id=ql;
  else
   select coalesce(b.invoice_policy,s.default_invoice_policy) into policy from private.sales_workspace_settings s
    left join private.sales_product_billing b on b.product_id=new.product_id where s.id;
   insert into private.sales_dossier_lines(id,dossier_id,order_line_id,invoice_policy) values(new.id,did,new.id,policy);
  end if;
 end if;return new;
end $$;
create trigger sales_bind_dossier after insert on public.invoices for each row execute function private.sales_bind_dossier();
create trigger sales_bind_dossier after insert on public.sales_orders for each row execute function private.sales_bind_dossier();
create trigger sales_bind_dossier after insert on public.invoice_lines for each row execute function private.sales_bind_dossier();
create trigger sales_bind_dossier after insert on public.sales_order_lines for each row execute function private.sales_bind_dossier();

create function private.sales_line_entitlement(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select case when o.status<>'confirmed' then 0 when d.invoice_policy='ordered' then l.quantity
 else least(l.quantity,coalesce(private.gama_line_performed(l.id,true),0)) end
 from public.sales_order_lines l join public.sales_orders o on o.id=l.order_id
 left join private.sales_dossier_lines d on d.order_line_id=l.id where l.id=p_line;
$$;
-- Both grouped allocations and the old one-order invoices reduce commitments.
-- Receivables already include payments/credits; subtract the gross invoice only
-- once from its original order(s), then add the canonical residual balance.
create or replace function private.gama_credit_snapshot(p_customer uuid,p_order uuid default null) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare c public.customers;today date:=(now() at time zone private.erp_timezone())::date;
 receivable numeric;commitment numeric;overdue jsonb;begin
 select * into c from public.customers where id=p_customer;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select coalesce(sum(balance),0),coalesce(jsonb_agg(jsonb_build_object('invoice_id',document_id,'number',number,'due_date',coalesce(due_date,issue_date),'balance',balance)
  order by coalesce(due_date,issue_date),document_id,"position") filter(where coalesce(due_date,issue_date)<today and balance>0),'[]') into receivable,overdue
  from private.gama_customer_dues(p_customer);
 select coalesce(sum(greatest(0,coalesce((select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2))
  from public.sales_order_lines l where l.order_id=o.id),0)-coalesce((select sum(a.subtotal+a.tax)
  from private.sales_invoice_orders a join public.external_invoices i on i.id=a.invoice_id
  where a.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0)-coalesce((select sum(i.total)
  from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')
  and not exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id)),0))),0) into commitment
  from public.sales_orders o where o.customer_id=p_customer and (o.status='confirmed' or (o.id=p_order and o.status='draft'));
 return jsonb_build_object('today',today,'customer_id',c.id,'credit_limit',c.credit_limit,'hold_reason',c.credit_hold_reason,
  'receivable',receivable,'commitment',commitment,'exposure',receivable+commitment,'overdue',overdue,
  'blocked',nullif(c.credit_hold_reason,'') is not null or jsonb_array_length(overdue)>0
   or (c.credit_limit is not null and receivable+commitment>c.credit_limit));
end $$;

create function private.sales_invoice_accounting_state(p_invoice uuid) returns text language sql stable security definer set search_path='' as $$
 select case when i.fiscal_status in ('cancelled','rejected') then 'cancelled'
 when exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status='posted') then 'posted'
 else 'draft' end from public.external_invoices i where i.id=p_invoice;
$$;

create or replace function private.sales_order_summary(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.sales_orders;ls jsonb;ivs jsonb;financial boolean;qty numeric;delivered numeric;shipped numeric;billable numeric;billed numeric;
 invcount integer;paid numeric;balance numeric;overdue boolean;prep text;logistic text;begin
 select * into o from public.sales_orders where id=p_order;if not found then raise exception 'ORDER_NOT_FOUND';end if;
 financial:=private.erp_module_allowed('payments',array['administrador','comercial']);
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'dossier_line_id',d.id,'product_id',l.product_id,'ordered',l.quantity,
 'invoice_policy',d.invoice_policy,
 'reserved',coalesce((select sum(sr.quantity) from public.stock_reservations sr join public.sales_reservation_links rl on rl.reservation_id=sr.id where rl.line_id=l.id and sr.status='active'),0),
 'shipped',coalesce(private.gama_line_performed(l.id,false),0),'delivered',coalesce(private.gama_line_performed(l.id,true),0),
 'returned',coalesce((select sum(rl.quantity) from public.return_lines rl join public.return_orders r on r.id=rl.return_id
  join public.sales_delivery_lines dl on dl.id=rl.delivery_line_id where dl.order_line_id=l.id and r.received_at is not null and r.status<>'cancelled'),0),
 'billed',case when financial then b.qty end,
 'billable',case when financial then greatest(0,private.sales_line_entitlement(l.id)-b.qty) end,
 'remaining_to_invoice',case when financial then greatest(0,l.quantity-b.qty) end) order by l.id),'[]') into ls
 from public.sales_order_lines l left join private.sales_dossier_lines d on d.order_line_id=l.id
 cross join lateral(select coalesce(sum(il.quantity),0) qty from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
 where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')) b where l.order_id=o.id;
 if financial then
  select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('accounting_status',private.sales_invoice_accounting_state(i.id)) order by i.created_at desc),'[]') into ivs
  from public.external_invoices i where i.order_id=o.id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=o.id);
  select count(*),coalesce(sum(r.balance),0),coalesce(sum(r.total-r.balance),0),coalesce(bool_or(r.balance>0 and r.due_date<(now() at time zone private.erp_timezone())::date),false)
   into invcount,balance,paid,overdue from private.gama_receivables r
   where (r.order_id=o.id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=r.id and a.order_id=o.id))
   and r.payment_status<>'cancelled' and private.sales_invoice_accounting_state(r.id)='posted';
 end if;
 select coalesce(sum((x->>'ordered')::numeric),0),coalesce(sum(least((x->>'ordered')::numeric,(x->>'delivered')::numeric)),0),
 coalesce(sum(least((x->>'ordered')::numeric,(x->>'shipped')::numeric)),0),coalesce(sum((x->>'billable')::numeric),0),coalesce(sum((x->>'billed')::numeric),0)
 into qty,delivered,shipped,billable,billed from jsonb_array_elements(ls)x;
 select status into prep from public.fulfillment_preparations where order_id=o.id order by updated_at desc limit 1;
 logistic:=case when delivered>=qty and qty>0 then 'delivered' when delivered>0 then 'partially_delivered'
  when shipped>=qty and qty>0 then 'shipped' when shipped>0 then 'partially_shipped'
  when prep in ('ready','packed','dispatched') then 'ready' when prep in ('picking','packing','in_progress') then 'preparing' else 'to_prepare' end;
 return jsonb_build_object('order_id',o.id,'dossier_id',coalesce(o.source_quote_id,o.id),'quote_id',o.source_quote_id,
 'quote_reference',(select invoice_number from public.invoices where id=o.source_quote_id),'order_reference',o.number,
 'commercial_status',o.status,'logistics_status',logistic,
 'invoicing_status',case when not financial then null when billed>=qty and qty>0 then 'invoiced' when billed>0 then 'partially_invoiced' when billable>0 then 'to_invoice' else 'not_invoiceable' end,
 'payment_status',case when not financial then null when invcount=0 then 'no_posted_invoice' when balance<0.005 then 'paid' when paid>0.005 then 'partially_paid' else 'unpaid' end,
 'overdue',case when financial then overdue end,'balance',case when financial then balance end,
 'quote_expired',exists(select 1 from public.invoices q where q.id=o.source_quote_id and q.quote_state in ('draft','sent') and q.quote_valid_until<(now() at time zone private.erp_timezone())::date),
 'lines',ls,'invoices',coalesce(ivs,'[]'::jsonb),
 'billing_mode',coalesce((select mode from private.sales_customer_billing where customer_id=o.customer_id),'on_delivery'));
end $$;

-- Adapt the existing locked invoice transaction, preview and queue together.
-- A policy never changes what a TMS event means or moves physical stock.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 old:='coalesce(private.gama_line_performed(l.id,true),0)';
 if strpos(src,old)=0 then raise exception 'SALES_INVOICE_POLICY_ANCHOR';end if;
 src:=replace(src,old,'coalesce(private.sales_line_entitlement(l.id),0)');execute src;
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'private.gama_line_performed(l.id,true)-coalesce','private.sales_line_entitlement(l.id)-coalesce');
 src:=replace(src,'private.gama_line_performed(l.id,true)>coalesce','private.sales_line_entitlement(l.id)>coalesce');
 execute src;
end $$;

-- Extended quote data goes through the same atomic quote transaction.
alter function private.gama_quote_action(text,jsonb) rename to gama_quote_action_before_dossier;
revoke all on function private.gama_quote_action_before_dossier(text,jsonb) from public,anon,authenticated;
create function private.gama_quote_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;x jsonb;blocks jsonb;price jsonb;ls jsonb:='[]';qid uuid;begin
 perform private.sales_access('quote');perform pg_advisory_xact_lock(741932,1);
 if p_action='save' then
  blocks:=coalesce(p_data->'offer_blocks','[]');
  if jsonb_typeof(blocks)<>'array' or jsonb_array_length(blocks)>100 or length(blocks::text)>60000 then raise exception 'INVALID_OFFER_BLOCKS';end if;
  for x in select value from jsonb_array_elements(blocks) loop
   if x->>'kind' not in ('section','note','option') or length(btrim(coalesce(x->>'description','')))<1 or length(x->>'description')>2000 then raise exception 'INVALID_OFFER_BLOCKS';end if;
   if x->>'kind'='option' then
    if not exists(select 1 from public.products where id=(x->>'product_id')::uuid and active) or
     (x->>'quantity')::numeric is null or (x->>'quantity')::numeric::text in ('NaN','Infinity','-Infinity') or
     (x->>'quantity')::numeric<=0 or (x->>'quantity')::numeric>=100000000 or (x->>'quantity')::numeric<>round((x->>'quantity')::numeric,3)
     or (x->>'list_price')::numeric is null or (x->>'list_price')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'list_price')::numeric<0
     or (x->>'tax_rate')::numeric is null or (x->>'tax_rate')::numeric not between 0 and 100 then raise exception 'INVALID_OFFER_BLOCKS';end if;
   end if;
  end loop;
  -- The new editor marks manual prices explicitly. Historical API payloads keep
  -- their existing review controls; the new contract always requires a reason.
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   if x->>'price_mode'='manual' and length(btrim(coalesce(x->>'price_reason','')))<3 then raise exception 'SALES_PRICE_REASON_REQUIRED';end if;
   ls:=ls||jsonb_build_array(x);
  end loop;
  p_data:=p_data||jsonb_build_object('lines',ls);
 end if;
 result:=private.gama_quote_action_before_dossier(p_action,p_data);qid:=(result->>'id')::uuid;
 if p_action='save' then
  insert into private.sales_quote_extras(quote_id,blocks,updated_by) values(qid,blocks,auth.uid())
   on conflict(quote_id) do update set blocks=excluded.blocks,updated_by=excluded.updated_by,updated_at=now();
  for x in select value from jsonb_array_elements(ls) loop
   update public.invoice_lines set price_source=price_source||jsonb_build_object('manual',x->>'price_mode'='manual','reason',x->>'price_reason')
   where invoice_id=qid and product_id=(x->>'product_id')::uuid;
  end loop;
 elsif p_action='accept' then
  update private.sales_portal_acceptances set processed_order_id=(result->>'order_id')::uuid where quote_id=qid;
 end if;
 return result||jsonb_build_object('dossier_id',qid);
end $$;
revoke all on function private.gama_quote_action(text,jsonb) from public,anon;
grant execute on function private.gama_quote_action(text,jsonb) to authenticated;

-- Freeze options/sections as part of the already immutable acceptance snapshot.
create function private.sales_snapshot_extras() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.quote_state='accepted' and old.quote_state is distinct from 'accepted' then
  new.accepted_snapshot:=new.accepted_snapshot||jsonb_build_object('offer_blocks',coalesce((select blocks from private.sales_quote_extras where quote_id=new.id),'[]'));
 end if;return new;
end $$;
create trigger zz_sales_snapshot_extras before update on public.invoices for each row execute function private.sales_snapshot_extras();

create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare did uuid;d private.sales_dossiers;q public.invoices;o public.sales_orders;result jsonb;act private.sales_activities;
 s private.sales_workspace_settings;tpl private.sales_templates;x jsonb;price jsonb;begin
 perform private.sales_access('summary');
 if private.current_user_role()='almacenero' and p_action not in ('dossier','status') then raise exception 'ROLE_NOT_ALLOWED';end if;
 did:=coalesce(nullif(p_data->>'dossier_id','')::uuid,nullif(p_data->>'quote_id','')::uuid,
  (select id from private.sales_dossiers where order_id=nullif(p_data->>'order_id','')::uuid));
 if did is not null then select * into d from private.sales_dossiers where id=did;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;end if;
 if p_action in ('dossier','status') then
  if d.id is null then raise exception 'DOSSIER_NOT_FOUND';end if;
  if d.order_id is not null then result:=private.sales_order_summary(d.order_id);
  else select * into q from public.invoices where id=d.quote_id;
   result:=jsonb_build_object('dossier_id',d.id,'quote_id',q.id,'quote_reference',q.invoice_number,'commercial_status',coalesce(q.quote_state,'draft'),
    'quote_expired',q.quote_state in ('draft','sent') and q.quote_valid_until<(now() at time zone private.erp_timezone())::date);
  end if;
  if private.current_user_role()='almacenero' then return result;end if;
  return result||jsonb_build_object('offer_blocks',coalesce((select blocks from private.sales_quote_extras where quote_id=d.quote_id),'[]'),
   'portal_acceptance',(select jsonb_build_object('revision',revision,'accepted_at',accepted_at,'actor_id',accepted_by,'processed_order_id',processed_order_id) from private.sales_portal_acceptances where quote_id=d.quote_id),
   'activities',coalesce((select jsonb_agg(to_jsonb(z)) from(select a.id,a.kind,a.title,a.owner_id,a.due_at,a.completed_at,a.created_at,p.full_name author_name
    from private.sales_activities a left join public.profiles p on p.id=a.created_by where a.dossier_id=did order by a.created_at desc limit 50)z),'[]'));
 elsif p_action='activity_save' then
  if d.id is null or not private.erp_action_allowed('quotes','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('sales-activity:'||(p_data->>'request_key'),0));
  select * into act from private.sales_activities where request_key=(p_data->>'request_key')::uuid;
  if found then if act.created_by<>auth.uid() or act.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return to_jsonb(act);end if;
  insert into private.sales_activities(dossier_id,kind,title,owner_id,due_at,created_by,request_key,payload)
   values(did,p_data->>'kind',p_data->>'title',(p_data->>'owner_id')::uuid,nullif(p_data->>'due_at','')::timestamptz,auth.uid(),(p_data->>'request_key')::uuid,p_data) returning * into act;
  if d.order_id is not null then insert into public.sales_events(order_id,action,actor_id,detail) values(d.order_id,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind));
  else insert into public.quote_events(quote_id,revision,action,actor_id,detail) select q.id,q.quote_revision,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices q where q.id=d.quote_id;end if;
  return to_jsonb(act);
 elsif p_action='activity_complete' then
  if not private.erp_action_allowed('quotes','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  update private.sales_activities set completed_at=coalesce(completed_at,now()) where id=(p_data->>'id')::uuid
   and (owner_id=auth.uid() or private.current_user_role()='administrador') returning * into act;
  if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(act);
 elsif p_action in ('configuration','configuration_save','product_policy_save') then
  if private.current_user_role()<>'administrador' or not private.erp_action_allowed('price-lists','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into s from private.sales_workspace_settings where id for update;
  if p_action='configuration_save' then
   if (p_data->>'version')::integer is distinct from s.version then raise exception 'RECORD_CHANGED';end if;
   update private.sales_workspace_settings set default_invoice_policy=p_data->>'default_invoice_policy',version=version+1,updated_by=auth.uid(),updated_at=now() where id returning * into s;
  elsif p_action='product_policy_save' then
   insert into private.sales_product_billing(product_id,invoice_policy,updated_by) values((p_data->>'product_id')::uuid,p_data->>'invoice_policy',auth.uid())
    on conflict(product_id) do update set invoice_policy=excluded.invoice_policy,updated_by=excluded.updated_by,updated_at=now();
  end if;
  return jsonb_build_object('settings',to_jsonb(s),'policies',coalesce((select jsonb_agg(jsonb_build_object('id',p.product_id,'name',pr.name,'invoice_policy',p.invoice_policy))
   from private.sales_product_billing p join public.products pr on pr.id=p.product_id),'[]'));
 elsif p_action='extras' then
  return coalesce((select blocks from private.sales_quote_extras where quote_id=d.quote_id),'[]');
 elsif p_action='owners' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)) from public.profiles p where p.active and p.role in ('administrador','comercial')),'[]');
 elsif p_action in ('document_generated','email_prepared','email_opened') then
  if d.quote_id is null or not private.erp_action_allowed('quotes','export') then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) select id,quote_revision,p_action,auth.uid(),jsonb_build_object('source','manual_compose') from public.invoices where id=d.quote_id;
  return jsonb_build_object('recorded',true,'sent',false);
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_sales_dossier(p_action,p_data)$$;
revoke all on function public.gama_sales_dossier(text,jsonb),private.gama_sales_dossier(text,jsonb) from public,anon;
grant execute on function public.gama_sales_dossier(text,jsonb),private.gama_sales_dossier(text,jsonb) to authenticated;
do $$declare f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in ('sales_bind_dossier','sales_line_entitlement','sales_invoice_accounting_state','sales_snapshot_extras') loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
 end loop;
end $$;
