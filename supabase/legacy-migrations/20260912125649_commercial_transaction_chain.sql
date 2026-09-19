-- GAMA PROD — complete commercial transaction chains.
-- Additive migration: CRM -> quote -> order -> reservation -> delivery ->
-- external invoice -> payment, and shortage -> purchase -> receipt -> stock.

begin;

-- Keep the CRM origin on the sales order itself so reporting never has to
-- reverse-engineer GAMA_META notes.
alter table public.sales_orders
  add column if not exists source_opportunity_id uuid
  references public.crm_opportunities(id) on delete set null;

create unique index if not exists sales_orders_source_opportunity_uidx
  on public.sales_orders(source_opportunity_id)
  where source_opportunity_id is not null;

create or replace function private.gama_sales_order_set_opportunity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.source_quote_id is null then
    new.source_opportunity_id := null;
  else
    select o.id into new.source_opportunity_id
      from public.crm_opportunities o
     where o.quote_invoice_id = new.source_quote_id
     order by o.created_at
     limit 1;
  end if;
  return new;
end;
$function$;

revoke all on function private.gama_sales_order_set_opportunity() from public, anon, authenticated;

drop trigger if exists sales_order_set_opportunity on public.sales_orders;
create trigger sales_order_set_opportunity
before insert or update of source_quote_id on public.sales_orders
for each row execute function private.gama_sales_order_set_opportunity();

update public.sales_orders so
   set source_opportunity_id = o.id
  from public.crm_opportunities o
 where so.source_quote_id = o.quote_invoice_id
   and so.source_opportunity_id is null;

-- A fiscal document can cover one or more partial deliveries.
create table if not exists public.external_invoice_deliveries (
  invoice_id uuid not null references public.external_invoices(id) on delete cascade,
  delivery_id uuid not null references public.sales_deliveries(id) on delete restrict,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (invoice_id, delivery_id)
);
create index if not exists external_invoice_deliveries_delivery_idx
  on public.external_invoice_deliveries(delivery_id);

-- Payments are append-only business records. A correction cancels a payment;
-- it never deletes it or rewrites the invoice total.
create table if not exists public.external_invoice_payments (
  id uuid primary key default gen_random_uuid(),
  request_key uuid not null unique,
  invoice_id uuid not null references public.external_invoices(id) on delete restrict,
  amount numeric(16,2) not null check (amount > 0 and amount < 10000000000),
  paid_at date not null default current_date,
  method text not null check (method in ('transfer','cash','card','check','other')),
  reference text not null default '' check (length(reference) <= 180),
  account text not null default '' check (length(account) <= 180),
  notes text not null default '' check (length(notes) <= 2000),
  status text not null default 'confirmed' check (status in ('confirmed','cancelled')),
  cancellation_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check ((status = 'confirmed' and cancelled_at is null and cancelled_by is null)
      or (status = 'cancelled' and cancelled_at is not null and cancelled_by is not null
          and cancellation_reason is not null and length(btrim(cancellation_reason)) >= 3))
);
create index if not exists external_invoice_payments_invoice_idx
  on public.external_invoice_payments(invoice_id, paid_at, created_at);

alter table public.external_invoice_deliveries enable row level security;
alter table public.external_invoice_payments enable row level security;
revoke all on public.external_invoice_deliveries from anon, authenticated;
revoke all on public.external_invoice_payments from anon, authenticated;
grant select on public.external_invoice_deliveries to authenticated;
grant select on public.external_invoice_payments to authenticated;
drop policy if exists external_invoice_deliveries_read on public.external_invoice_deliveries;
create policy external_invoice_deliveries_read on public.external_invoice_deliveries
for select to authenticated
using ((select auth.uid()) is not null
  and coalesce((select private.current_user_role()), '') in ('administrador','comercial'));
drop policy if exists external_invoice_payments_read on public.external_invoice_payments;
create policy external_invoice_payments_read on public.external_invoice_payments
for select to authenticated
using ((select auth.uid()) is not null
  and coalesce((select private.current_user_role()), '') in ('administrador','comercial'));

-- One checked RPC for delivery links and cash collection. The public wrapper
-- is invoker; the definer implementation stays in the private schema and
-- validates the authenticated user's active profile on every call.
create or replace function private.gama_commercial_action(p_action text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(private.current_user_role(), '');
  v_invoice public.external_invoices;
  v_payment public.external_invoice_payments;
  v_delivery_id uuid;
  v_request_key uuid;
  v_paid numeric;
  v_amount numeric;
  v_reason text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if v_role not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if p_action is null or p_action not in ('link_invoice_delivery','payment','cancel_payment') then raise exception 'INVALID_ACTION'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'INVALID_DATA'; end if;

  select * into v_invoice
    from public.external_invoices
   where id = nullif(p_data->>'invoice_id','')::uuid
   for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;

  if p_action = 'link_invoice_delivery' then
    if jsonb_typeof(coalesce(p_data->'delivery_ids','[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_data->'delivery_ids','[]'::jsonb)) = 0 then
      raise exception 'DELIVERY_REQUIRED';
    end if;
    for v_delivery_id in
      select distinct value::uuid
        from jsonb_array_elements_text(coalesce(p_data->'delivery_ids','[]'::jsonb))
    loop
      if not exists(select 1 from public.sales_deliveries d
                    where d.id=v_delivery_id and d.order_id=v_invoice.order_id) then
        raise exception 'DELIVERY_ORDER_MISMATCH';
      end if;
      insert into public.external_invoice_deliveries(invoice_id,delivery_id,created_by)
      values(v_invoice.id,v_delivery_id,v_uid)
      on conflict do nothing;
    end loop;
    insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
    values(v_invoice.order_id,'invoice_delivery_linked',v_invoice.id,v_uid,
           jsonb_build_object('delivery_ids',p_data->'delivery_ids'));
    return jsonb_build_object('invoice_id',v_invoice.id,'order_id',v_invoice.order_id);
  end if;

  if p_action = 'payment' then
    if v_invoice.fiscal_status in ('rejected','cancelled') then raise exception 'INVOICE_CLOSED'; end if;
    v_request_key := nullif(p_data->>'request_key','')::uuid;
    if v_request_key is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
    perform pg_advisory_xact_lock(hashtextextended(v_request_key::text,0));
    select * into v_payment from public.external_invoice_payments where request_key=v_request_key;
    if found then
      if v_payment.invoice_id <> v_invoice.id or v_payment.amount <> (p_data->>'amount')::numeric then
        raise exception 'REQUEST_KEY_CONFLICT';
      end if;
      return to_jsonb(v_payment);
    end if;
    v_amount := (p_data->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 or v_amount <> round(v_amount,2) then raise exception 'INVALID_PAYMENT_AMOUNT'; end if;
    if coalesce(p_data->>'method','') not in ('transfer','cash','card','check','other') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
    select coalesce(sum(amount),0) into v_paid
      from public.external_invoice_payments
     where invoice_id=v_invoice.id and status='confirmed';
    if v_paid + v_amount > v_invoice.total then raise exception 'PAYMENT_EXCEEDS_BALANCE'; end if;
    insert into public.external_invoice_payments(
      request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by)
    values(
      v_request_key,v_invoice.id,v_amount,
      coalesce(nullif(p_data->>'paid_at','')::date,current_date),p_data->>'method',
      coalesce(p_data->>'reference',''),coalesce(p_data->>'account',''),
      coalesce(p_data->>'notes',''),v_uid)
    returning * into v_payment;
    insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
    values(v_invoice.order_id,'payment',v_payment.id,v_uid,
           jsonb_build_object('invoice_id',v_invoice.id,'amount',v_amount,'method',v_payment.method));
    return to_jsonb(v_payment);
  end if;

  select p.* into v_payment
    from public.external_invoice_payments p
   where p.id=nullif(p_data->>'payment_id','')::uuid
     and p.invoice_id=v_invoice.id
   for update;
  if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if v_payment.status='cancelled' then return to_jsonb(v_payment); end if;
  v_reason := btrim(coalesce(p_data->>'reason',''));
  if length(v_reason)<3 then raise exception 'REASON_REQUIRED'; end if;
  update public.external_invoice_payments
     set status='cancelled',cancellation_reason=v_reason,cancelled_at=now(),cancelled_by=v_uid
   where id=v_payment.id returning * into v_payment;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
  values(v_invoice.order_id,'payment_cancelled',v_payment.id,v_uid,
         jsonb_build_object('invoice_id',v_invoice.id,'amount',v_payment.amount,'reason',v_reason));
  return to_jsonb(v_payment);
end;
$function$;

revoke all on function private.gama_commercial_action(text,jsonb) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.gama_commercial_action(text,jsonb) to authenticated;

create or replace function public.gama_commercial_action(p_action text,p_data jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.gama_commercial_action(p_action,p_data);
$function$;
revoke all on function public.gama_commercial_action(text,jsonb) from public,anon;
grant execute on function public.gama_commercial_action(text,jsonb) to authenticated;

-- Creating the fiscal reference and linking deliveries is one transaction.
create or replace function public.gama_sales_action(p_action text,p_data jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $function$
declare result jsonb;
begin
  result := private.gama_sales_action(p_action,p_data);
  if p_action='invoice' and jsonb_array_length(coalesce(p_data->'delivery_ids','[]'::jsonb))>0 then
    perform private.gama_commercial_action('link_invoice_delivery',
      jsonb_build_object('invoice_id',result->>'id','delivery_ids',p_data->'delivery_ids'));
  end if;
  return result;
end;
$function$;

-- Automatically allocate newly received stock to the oldest confirmed sales
-- orders first. The receipt and every reservation commit or roll back together.
-- Serialize the two entry points BEFORE any row locks. This prevents a receipt
-- from allocating to an order being cancelled or shipped concurrently.
-- Preserve the installed implementations and their existing business checks.
do $migration$
declare definition text;
begin
  definition := pg_get_functiondef('private.gama_sales_action(text,jsonb)'::regprocedure);
  definition := regexp_replace(definition, '\m[Bb][Ee][Gg][Ii][Nn]\M',
    E'begin\n perform pg_advisory_xact_lock(741932, 1);');
  execute definition;
end;
$migration$;

alter function public.gama_receive_purchase(uuid,jsonb,text) set schema private;
alter function private.gama_receive_purchase(uuid,jsonb,text) rename to gama_receive_purchase_impl;
revoke all on function private.gama_receive_purchase_impl(uuid,jsonb,text) from public,anon,authenticated;

create function private.gama_receive_purchase(p_purchase_order_id uuid,p_lines jsonb,p_comment text default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(private.current_user_role(),'') not in ('administrador','almacenero') then
    raise exception 'ROLE_NOT_ALLOWED';
  end if;
  perform pg_advisory_xact_lock(741932, 1);
  return private.gama_receive_purchase_impl(p_purchase_order_id,p_lines,p_comment);
end;
$function$;
revoke all on function private.gama_receive_purchase(uuid,jsonb,text) from public,anon;
grant execute on function private.gama_receive_purchase(uuid,jsonb,text) to authenticated;
create function public.gama_receive_purchase(p_purchase_order_id uuid,p_lines jsonb,p_comment text default null)
returns jsonb language sql security invoker set search_path = '' as $function$
  select private.gama_receive_purchase(p_purchase_order_id,p_lines,p_comment);
$function$;
revoke all on function public.gama_receive_purchase(uuid,jsonb,text) from public,anon;
grant execute on function public.gama_receive_purchase(uuid,jsonb,text) to authenticated;

create or replace function private.gama_allocate_sales_product(p_product_id uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_line record;
  v_quant public.stock_quants;
  v_need numeric;
  v_available numeric;
  v_take numeric;
  v_reservation_id uuid;
  v_allocated numeric := 0;
begin
  perform 1 from public.products where id=p_product_id for update;
  for v_line in
    select ol.id,ol.order_id,ol.quantity,o.created_by
      from public.sales_order_lines ol
      join public.sales_orders o on o.id=ol.order_id
     where ol.product_id=p_product_id and o.status='confirmed'
     order by o.created_at,o.id,ol.id
     for update of ol
  loop
    select v_line.quantity
           - coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=v_line.id),0)
           - coalesce((select sum(sr.quantity)
                         from public.stock_reservations sr
                         join public.sales_reservation_links sl on sl.reservation_id=sr.id
                        where sl.line_id=v_line.id and sr.status='active'),0)
      into v_need;
    if v_need <= 0 then continue; end if;
    for v_quant in
      select sq.*
        from public.stock_quants sq
        join public.warehouse_locations wl on wl.id=sq.location_id
        join public.warehouses w on w.id=wl.warehouse_id
       where sq.product_id=p_product_id and wl.active and w.active
       order by wl.picking_priority,sq.location_id
       for update of sq
    loop
      exit when v_need <= 0;
      v_available := v_quant.quantity-v_quant.reserved_quantity;
      v_take := least(v_need,v_available);
      if v_take <= 0 then continue; end if;
      update public.stock_quants
         set reserved_quantity=reserved_quantity+v_take,updated_at=now()
       where id=v_quant.id;
      insert into public.stock_reservations(
        product_id,location_id,quantity,reference_type,reference_id,created_by)
      values(p_product_id,v_quant.location_id,v_take,'sales_order',v_line.order_id,
             coalesce(auth.uid(),v_line.created_by))
      returning id into v_reservation_id;
      insert into public.sales_reservation_links(reservation_id,line_id)
      values(v_reservation_id,v_line.id);
      insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
      values(v_line.order_id,'receipt_auto_reserved',v_reservation_id,auth.uid(),
        jsonb_build_object('product_id',p_product_id,'line_id',v_line.id,
          'location_id',v_quant.location_id,'quantity',v_take));
      v_need := v_need-v_take;
      v_allocated := v_allocated+v_take;
    end loop;
  end loop;
  return v_allocated;
end;
$function$;
revoke all on function private.gama_allocate_sales_product(uuid) from public,anon,authenticated;

create or replace function private.gama_allocate_after_receipt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.movement_type='receipt' and new.type='in' then
    perform private.gama_allocate_sales_product(new.product_id);
  end if;
  return new;
end;
$function$;
revoke all on function private.gama_allocate_after_receipt() from public,anon,authenticated;

drop trigger if exists stock_receipt_allocate_sales on public.stock_movements;
create trigger stock_receipt_allocate_sales
after insert on public.stock_movements
for each row execute function private.gama_allocate_after_receipt();

-- Live purchasing signal. The view respects all underlying RLS policies and
-- is exposed explicitly because new Supabase tables/views are no longer
-- automatically added to the Data API grants.
create or replace view public.replenishment_needs
with (security_invoker=on)
as
with
physical as (
  select p.id product_id,
         coalesce(sum(q.quantity),0)::numeric on_hand,
         coalesce(sum(q.reserved_quantity),0)::numeric reserved
    from public.products p
    left join public.stock_quants q on q.product_id=p.id
   where p.active
   group by p.id
),
demand as (
  select ol.product_id,
         sum(greatest(ol.quantity-coalesce(sh.shipped,0),0))::numeric sales_demand,
         sum(greatest(ol.quantity-coalesce(sh.shipped,0)-coalesce(rs.reserved,0),0))::numeric unreserved_demand
    from public.sales_order_lines ol
    join public.sales_orders o on o.id=ol.order_id and o.status='confirmed'
    left join (
      select order_line_id,sum(quantity) shipped
        from public.sales_delivery_lines group by order_line_id
    ) sh on sh.order_line_id=ol.id
    left join (
      select sl.line_id,sum(sr.quantity) reserved
      from public.sales_reservation_links sl
      join public.stock_reservations sr on sr.id=sl.reservation_id and sr.status='active'
      group by sl.line_id
    ) rs on rs.line_id=ol.id
   group by ol.product_id
),
incoming as (
  select pol.product_id,
         sum(greatest(pol.quantity-coalesce(pol.received_quantity,0),0))::numeric incoming
    from public.purchase_order_lines pol
    join public.purchase_orders po on po.id=pol.purchase_order_id
   where po.status in ('sent','partial')
   group by pol.product_id
),
metrics as (
  select p.id product_id,p.name,p.reference,p.supplier_id,
         coalesce(p.min_stock,0)::numeric min_stock,
         coalesce(p.max_stock,0)::numeric max_stock,
         ph.on_hand,ph.reserved,(ph.on_hand-ph.reserved)::numeric available,
         coalesce(i.incoming,0)::numeric incoming,
         coalesce(d.sales_demand,0)::numeric sales_demand,
         coalesce(d.unreserved_demand,0)::numeric unreserved_demand,
         (ph.on_hand-ph.reserved+coalesce(i.incoming,0)-coalesce(d.unreserved_demand,0))::numeric projected_available
    from public.products p
    join physical ph on ph.product_id=p.id
    left join demand d on d.product_id=p.id
    left join incoming i on i.product_id=p.id
   where p.active
)
select m.*,
       (case when m.projected_available < m.min_stock or m.projected_available < 0
         then greatest(m.max_stock,m.min_stock,0)-m.projected_available
         else 0 end)::numeric suggested_purchase
  from metrics m;

revoke all on public.replenishment_needs from anon,authenticated;
grant select on public.replenishment_needs to authenticated;

-- The warehouse role already owns the receiving workflow in the UI and RPC;
-- let it read the purchase header and lines needed to perform that receipt.
drop policy if exists purchase_orders_read on public.purchase_orders;
create policy purchase_orders_read on public.purchase_orders
for select to authenticated
using ((select private.current_user_role()) in ('administrador','comercial','almacenero'));
drop policy if exists purchase_order_lines_read on public.purchase_order_lines;
create policy purchase_order_lines_read on public.purchase_order_lines
for select to authenticated
using ((select private.current_user_role()) in ('administrador','comercial','almacenero'));

commit;
