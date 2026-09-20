-- Extend existing informational invoices into versioned customer quotations.
-- Fiscal invoices remain external. All new writes use one checked transaction.
alter table public.invoices
 add column quote_state text check (quote_state in ('draft','sent','accepted','rejected','cancelled')),
 add column quote_request_key uuid unique,
 add column quote_revision integer not null default 0,
 add column quote_details jsonb not null default '{}'::jsonb,
 add column quote_valid_until date,
 add column quote_sent_at timestamptz,
 add column quote_accepted_at timestamptz,
 add column quote_accepted_by uuid references auth.users(id),
 add column quote_acceptance_channel text,
 add column quote_acceptance_reference text;
alter table public.invoice_lines
 add column quote_description text,
 add column quote_list_price numeric,
 add column quote_discount numeric not null default 0 check (quote_discount between 0 and 100);
create index invoices_customer_quote_idx on public.invoices(customer_id,created_at desc) where quote_state is not null;
create index invoices_quote_accepted_by_idx on public.invoices(quote_accepted_by) where quote_accepted_by is not null;
create index if not exists tms_deliveries_customer_idx on public.tms_deliveries(customer_id);

-- Uses the verified Auth email, never user-editable metadata or name matching.
create function private.gama_owns_customer(p_customer uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.current_user_role()='cliente'
 and exists(select 1 from public.customers c join auth.users u on u.id=auth.uid()
 where c.id=p_customer and c.active and u.email_confirmed_at is not null
 and lower(btrim(c.email))=lower(btrim(u.email)) and length(btrim(c.email))>0);
$$;
revoke all on function private.gama_owns_customer(uuid) from public,anon;
grant execute on function private.gama_owns_customer(uuid) to authenticated;
create policy quotes_client_read on public.invoices for select to authenticated
 using (quote_state in ('sent','accepted','rejected') and private.gama_owns_customer(customer_id));
create policy quote_lines_client_read on public.invoice_lines for select to authenticated
 using (exists(select 1 from public.invoices i where i.id=invoice_id and i.quote_state in ('sent','accepted','rejected') and private.gama_owns_customer(i.customer_id)));

create table public.quote_events (
 id uuid primary key default gen_random_uuid(),
 quote_id uuid not null references public.invoices(id),
 revision integer not null,
 action text not null,
 actor_id uuid not null references auth.users(id),
 at timestamptz not null default now(),
 detail jsonb not null default '{}'::jsonb
);
create index quote_events_quote_idx on public.quote_events(quote_id,at);
create index quote_events_actor_idx on public.quote_events(actor_id);
alter table public.quote_events enable row level security;
revoke all on public.quote_events from anon,authenticated;
grant select on public.quote_events to authenticated;
create policy quote_events_read on public.quote_events for select to authenticated
 using (private.current_user_role() in ('administrador','comercial'));

-- Managed quotations cannot be altered by legacy direct REST writers. The
-- invoker trigger sees authenticated for REST and the owner for checked RPCs.
create function private.gama_guard_managed_quote() returns trigger
language plpgsql set search_path='' as $$
declare managed boolean;
begin
 if tg_table_name='invoices' then
  managed:=case when tg_op='INSERT' then new.quote_state is not null
    when tg_op='DELETE' then old.quote_state is not null
    else old.quote_state is not null or new.quote_state is not null end;
 else
  select exists(select 1 from public.invoices where id=case when tg_op='DELETE' then old.invoice_id else new.invoice_id end and quote_state is not null) into managed;
  if tg_op='UPDATE' then managed:=managed or exists(select 1 from public.invoices where id=old.invoice_id and quote_state is not null); end if;
 end if;
 if managed and current_user in ('anon','authenticated') then raise exception 'USE_QUOTE_ACTION'; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function private.gama_guard_managed_quote() from public,anon,authenticated;
create trigger managed_quote_guard before insert or update or delete on public.invoices for each row execute function private.gama_guard_managed_quote();
create trigger managed_quote_line_guard before insert or update or delete on public.invoice_lines for each row execute function private.gama_guard_managed_quote();

create function private.gama_quote_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); r text:=coalesce(private.current_user_role(),'');
 q public.invoices; c public.customers; p public.products; o public.sales_orders;
 x jsonb; ls jsonb; d jsonb; n numeric; price numeric; discount numeric; taxrate numeric;
 sub numeric:=0; taxes numeric:=0; net numeric; line_sub numeric; pid uuid;
 qid uuid:=nullif(p_data->>'id','')::uuid; action_channel text; reference text;
 result jsonb;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if r not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('save','send','reopen','accept','reject','cancel') then raise exception 'INVALID_ACTION'; end if;
 if r='cliente' and p_action not in ('accept','reject') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 -- Same lock order as the existing sales/receipt chain.
 perform pg_advisory_xact_lock(741932,1);
 if qid is null and p_action='save' then
  if nullif(p_data->>'request_key','')::uuid is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select * into q from public.invoices where quote_request_key=(p_data->>'request_key')::uuid;
  if found then return jsonb_build_object('id',q.id,'revision',q.quote_revision,'state',q.quote_state); end if;
 end if;
 if qid is not null then
  select * into q from public.invoices where id=qid for update;
  if not found then raise exception 'QUOTE_NOT_FOUND'; end if;
  if r='cliente' and (not private.gama_owns_customer(q.customer_id) or q.quote_state not in ('sent','accepted','rejected') or q.quote_state is null) then raise exception 'QUOTE_NOT_FOUND'; end if;
  -- Retrying a successful accept returns its original order and never reserves twice.
  if p_action='accept' and q.quote_state='accepted' then
   select * into o from public.sales_orders where source_quote_id=q.id;
   return jsonb_build_object('id',q.id,'order_id',o.id,'state','accepted');
  end if;
  if q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED'; end if;
 elsif p_action<>'save' then raise exception 'QUOTE_NOT_FOUND';
 end if;
 if p_action='save' then
  if q.id is not null and (coalesce(q.quote_state,'draft')<>'draft' or q.status='cancelled') then raise exception 'QUOTE_LOCKED'; end if;
  if exists(select 1 from public.sales_orders where source_quote_id=qid) then raise exception 'QUOTE_HAS_ORDER'; end if;
  select * into c from public.customers where id=(p_data->>'customer_id')::uuid and active;
  if not found then raise exception 'CUSTOMER_REQUIRED'; end if;
  d:=p_data->'details'; ls:=p_data->'lines';
  if jsonb_typeof(d) is distinct from 'object' or length(d::text)>12000 then raise exception 'INVALID_DETAILS'; end if;
  if length(btrim(coalesce(d->>'client','')))=0 or length(btrim(coalesce(d->>'seller','')))=0 or length(btrim(coalesce(d->>'delivery_address','')))=0 then raise exception 'DETAILS_REQUIRED'; end if;
  if jsonb_typeof(ls) is distinct from 'array' or jsonb_array_length(ls) not between 1 and 200 then raise exception 'INVALID_LINES'; end if;
  if exists(select 1 from jsonb_array_elements(ls) a group by a->>'product_id' having count(*)>1) then raise exception 'DUPLICATE_PRODUCT'; end if;
  if nullif(p_data->>'issue_date','')::date is null or nullif(p_data->>'valid_until','')::date is null or (p_data->>'valid_until')::date<(p_data->>'issue_date')::date then raise exception 'VALIDITY_REQUIRED'; end if;
  if q.id is null then
   insert into public.invoices(customer_id,user_id,quote_state,quote_request_key) values(c.id,u,'draft',(p_data->>'request_key')::uuid) returning * into q;
  end if;
  delete from public.invoice_lines where invoice_id=q.id;
  for x in select value from jsonb_array_elements(ls) loop
   select * into p from public.products where id=(x->>'product_id')::uuid and active;
   if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
   n:=(x->>'quantity')::numeric; price:=(x->>'list_price')::numeric;
   discount:=(x->>'discount')::numeric; taxrate:=(x->>'tax_rate')::numeric;
   if n is null or n<=0 or n>=100000000 or n<>round(n,3) or price is null or price<0 or price>=100000000 or price<>round(price,4) or discount is null or discount not between 0 and 100 or taxrate is null or taxrate not between 0 and 100 then raise exception 'INVALID_LINES'; end if;
   if length(btrim(coalesce(x->>'description','')))=0 or length(x->>'description')>500 then raise exception 'DESCRIPTION_REQUIRED'; end if;
   net:=round(price*(1-discount/100),4); line_sub:=round(n*net,2);
   sub:=sub+line_sub; taxes:=taxes+round(line_sub*taxrate/100,2);
   insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total,quote_description,quote_list_price,quote_discount)
    values(q.id,p.id,n,net,taxrate,line_sub,x->>'description',price,discount);
  end loop;
  update public.invoices set customer_id=c.id,quote_details=d,quote_state='draft',
   invoice_number=coalesce(nullif(btrim(p_data->>'number'),''),'COT-'||lpad(q.archive_number::text,9,'0')),
   issue_date=(p_data->>'issue_date')::date,quote_valid_until=(p_data->>'valid_until')::date,
   subtotal=sub,tax=taxes,total=sub+taxes,quote_revision=quote_revision+1,updated_at=now()
   where id=q.id returning * into q;
 elsif p_action='reopen' then
  if q.quote_state not in ('sent','rejected') or q.quote_state is null then raise exception 'QUOTE_LOCKED'; end if;
  if exists(select 1 from public.sales_orders where source_quote_id=q.id) then raise exception 'QUOTE_HAS_ORDER'; end if;
  update public.invoices set quote_state='draft',quote_revision=quote_revision+1,updated_at=now() where id=q.id returning * into q;
 elsif p_action='send' then
  if q.quote_state is distinct from 'draft' then raise exception 'QUOTE_LOCKED'; end if;
  if q.quote_valid_until<current_date then raise exception 'QUOTE_EXPIRED'; end if;
  if not exists(select 1 from public.invoice_lines where invoice_id=q.id) then raise exception 'INVALID_LINES'; end if;
  update public.invoices set quote_state='sent',quote_sent_at=now(),quote_revision=quote_revision+1,updated_at=now() where id=q.id returning * into q;
 elsif p_action in ('accept','reject') then
  if q.quote_state is distinct from 'sent' then raise exception 'QUOTE_LOCKED'; end if;
  if q.quote_valid_until<current_date then raise exception 'QUOTE_EXPIRED'; end if;
  if p_action='reject' then
   update public.invoices set quote_state='rejected',quote_revision=quote_revision+1,updated_at=now() where id=q.id returning * into q;
  else
   if not exists(select 1 from public.customers where id=q.customer_id and active) then raise exception 'CUSTOMER_REQUIRED'; end if;
   action_channel:=case when r='cliente' then 'app' else p_data->>'channel' end;
   reference:=case when r='cliente' then '' else btrim(p_data->>'reference') end;
   if r<>'cliente' and (action_channel is null or action_channel not in ('email','phone','in_person','other') or length(coalesce(reference,''))<3 or length(reference)>2000) then raise exception 'ACCEPTANCE_REFERENCE_REQUIRED'; end if;
   if exists(select 1 from public.sales_orders where source_quote_id=q.id) then raise exception 'QUOTE_HAS_ORDER'; end if;
   if exists(select 1 from public.invoice_lines l join public.products pr on pr.id=l.product_id where l.invoice_id=q.id and not pr.active) then raise exception 'PRODUCT_NOT_FOUND'; end if;
   update public.invoices set quote_state='accepted',quote_accepted_at=now(),quote_accepted_by=u,
    quote_acceptance_channel=action_channel,quote_acceptance_reference=reference,quote_revision=quote_revision+1,updated_at=now() where id=q.id returning * into q;
   insert into public.sales_orders(request_key,customer_id,customer_name,customer_identification,delivery_address,source_quote_id,status,notes,created_by)
    values(gen_random_uuid(),q.customer_id,q.quote_details->>'client',coalesce(q.quote_details->>'clientId',''),q.quote_details->>'delivery_address',q.id,'confirmed',coalesce(q.quote_details->>'notes',''),u) returning * into o;
   insert into public.sales_order_lines(order_id,product_id,product_name,reference,quantity,unit_price,tax_rate)
    select o.id,l.product_id,l.quote_description,coalesce(pr.reference,''),l.quantity,l.unit_price,l.tax_rate from public.invoice_lines l join public.products pr on pr.id=l.product_id where l.invoice_id=q.id;
   for pid in select product_id from public.sales_order_lines where order_id=o.id order by product_id loop
    perform private.gama_allocate_sales_product(pid);
   end loop;
   insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(o.id,'quote_accepted',q.id,u,jsonb_build_object('channel',action_channel,'revision',q.quote_revision,'reference',reference));
  end if;
 elsif p_action='cancel' then
  if coalesce(q.quote_state,'draft') not in ('draft','sent','rejected') then raise exception 'QUOTE_LOCKED'; end if;
  if exists(select 1 from public.sales_orders where source_quote_id=q.id) then raise exception 'QUOTE_HAS_ORDER'; end if;
  update public.invoices set quote_state='cancelled',quote_revision=quote_revision+1,updated_at=now() where id=q.id returning * into q;
 end if;
 insert into public.quote_events(quote_id,revision,action,actor_id,detail) values(q.id,q.quote_revision,p_action,u,
  case when p_action='save' then jsonb_build_object('document',to_jsonb(q),'lines',ls)
   else jsonb_build_object('channel',action_channel,'reference',reference,'total',q.total,'order_id',o.id) end);
 return jsonb_build_object('id',q.id,'revision',q.quote_revision,'state',q.quote_state,'order_id',o.id);
end $$;
revoke all on function private.gama_quote_action(text,jsonb) from public,anon;
grant execute on function private.gama_quote_action(text,jsonb) to authenticated;
create function public.gama_quote_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.gama_quote_action(p_action,p_data); $$;
revoke all on function public.gama_quote_action(text,jsonb) from public,anon;
grant execute on function public.gama_quote_action(text,jsonb) to authenticated;

-- A separate checked, read-only projection avoids exposing routes, internal
-- notes, other stops or other customers' personal data through the TMS tables.
create function private.gama_client_deliveries(p_id uuid default null,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r text:=coalesce(private.current_user_role(),''); result jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if r not in ('cliente','administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_offset is null or p_offset<0 or p_offset>1000000 then raise exception 'INVALID_OFFSET'; end if;
 select coalesce(jsonb_agg(j),'[]'::jsonb) into result from (
  select jsonb_build_object('id',d.id,'customer',d.customer,'address',d.address,'date',d.delivery_date,'time_window',d.time_window,
   'status',d.status,'delivered_at',d.delivered_at,'has_proof',exists(select 1 from public.tms_proofs p where p.delivery_id=d.id),
   'shipment_number',s.number,'order_number',o.number,
   'lines',case when p_id is not null then coalesce((select jsonb_agg(jsonb_build_object('description',l.product_name,'quantity',dl.quantity)) from public.sales_delivery_lines dl join public.sales_order_lines l on l.id=dl.order_line_id where dl.delivery_id=s.id),'[]'::jsonb) else '[]'::jsonb end,
   'proof',case when p_id is not null then (select jsonb_build_object('photo',p.photo,'signature',p.signature,'captured_at',p.captured_at) from public.tms_proofs p where p.delivery_id=d.id) else null end) j
  from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id left join public.sales_orders o on o.id=s.order_id
  where (r in ('administrador','comercial') or private.gama_owns_customer(d.customer_id)) and (p_id is null or d.id=p_id)
  order by d.delivery_date desc,d.id limit 21 offset p_offset
 ) a;
 return result;
end $$;
revoke all on function private.gama_client_deliveries(uuid,integer) from public,anon;
grant execute on function private.gama_client_deliveries(uuid,integer) to authenticated;
create function public.gama_client_deliveries(p_id uuid default null,p_offset integer default 0) returns jsonb
language sql security invoker set search_path='' as $$ select private.gama_client_deliveries(p_id,p_offset); $$;
revoke all on function public.gama_client_deliveries(uuid,integer) from public,anon;
grant execute on function public.gama_client_deliveries(uuid,integer) to authenticated;

-- Prevent the older conversion endpoint from bypassing client acceptance.
create function private.gama_guard_quote_order() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.source_quote_id is not null and exists(select 1 from public.invoices i where i.id=new.source_quote_id and i.quote_state is not null and i.quote_state<>'accepted') then raise exception 'QUOTE_ACCEPT_FIRST'; end if;
 return new;
end $$;
revoke all on function private.gama_guard_quote_order() from public,anon,authenticated;
create trigger quote_order_guard before insert or update of source_quote_id on public.sales_orders for each row execute function private.gama_guard_quote_order();

create function private.gama_quote_reservations(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare q public.invoices; result jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into q from public.invoices where id=p_id;
 if not found or q.quote_state is distinct from 'accepted' or not (coalesce(private.current_user_role(),'') in ('administrador','comercial') or private.gama_owns_customer(q.customer_id)) then raise exception 'QUOTE_NOT_FOUND'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('description',l.product_name,'quantity',l.quantity,'reserved',
  coalesce((select sum(sr.quantity) from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id where sl.line_id=l.id and sr.status='active'),0),
  'shipped',coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0),'order_status',o.status)),'[]'::jsonb)
 into result from public.sales_order_lines l join public.sales_orders o on o.id=l.order_id where o.source_quote_id=p_id;
 return result;
end $$;
revoke all on function private.gama_quote_reservations(uuid) from public,anon;
grant execute on function private.gama_quote_reservations(uuid) to authenticated;
create function public.gama_quote_reservations(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.gama_quote_reservations(p_id); $$;
revoke all on function public.gama_quote_reservations(uuid) from public,anon;
grant execute on function public.gama_quote_reservations(uuid) to authenticated;
