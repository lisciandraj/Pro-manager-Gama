-- Projections over canonical commercial/stock records, no parallel ledger.
-- Fix the existing quote-only activity event (its alias collided with the
-- PL/pgSQL quote variable; activities on confirmed dossiers were unaffected).
do $$declare body text;old text:=$q$select q.id,q.quote_revision,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices q where q.id=d.quote_id$q$;begin
 select pg_get_functiondef('private.gama_sales_dossier_before_deposits(text,jsonb)'::regprocedure) into body;
 if strpos(body,old)=0 then raise exception 'ACTIVITY_EVENT_ANCHOR';end if;
 execute replace(body,old,$q$select iq.id,iq.quote_revision,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices iq where iq.id=d.quote_id$q$);
end $$;
-- Closing an activity is idempotent and visible in the same dossier history.
do $$declare body text;old text:=$q$update private.sales_activities set completed_at=coalesce(completed_at,now()) where id=(p_data->>'id')::uuid
   and (owner_id=auth.uid() or private.current_user_role()='administrador') returning * into act;
  if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(act);$q$;begin
 select pg_get_functiondef('private.gama_sales_dossier_before_deposits(text,jsonb)'::regprocedure) into body;
 if strpos(body,old)=0 then raise exception 'ACTIVITY_COMPLETE_ANCHOR';end if;
 execute replace(body,old,$q$select * into act from private.sales_activities where id=(p_data->>'id')::uuid
   and (owner_id=auth.uid() or private.current_user_role()='administrador') for update;
  if not found then raise exception 'NOT_FOUND';end if;
  if act.completed_at is null then
   update private.sales_activities set completed_at=now() where id=act.id returning * into act;
   select * into d from private.sales_dossiers where id=act.dossier_id;
   if d.order_id is not null then insert into public.sales_events(order_id,action,actor_id,detail)
    values(d.order_id,'activity_completed',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind));
   else insert into public.quote_events(quote_id,revision,action,actor_id,detail)
    select iq.id,iq.quote_revision,'activity_completed',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices iq where iq.id=d.quote_id;end if;
  end if;return to_jsonb(act);$q$);
end $$;
create index sales_activities_next_open on private.sales_activities(dossier_id,due_at,id) where completed_at is null;
create function private.sales_next_activity(p_dossier uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',a.id,'title',a.title,'due_at',a.due_at,'owner_id',a.owner_id,
  'owner_name',p.full_name,'overdue',coalesce(a.due_at<now(),false))
 from private.sales_activities a join public.profiles p on p.id=a.owner_id
 where a.dossier_id=p_dossier and a.completed_at is null
 order by a.due_at nulls last,a.created_at,a.id limit 1
$$;
do $$declare body text;begin
 select pg_get_functiondef('private.sales_unified_quote_list(jsonb)'::regprocedure) into body;
 if strpos(body,'return result;')=0 then raise exception 'QUOTE_ACTIVITY_ANCHOR';end if;
 body:=replace(body,'return result;',$code$
 result:=jsonb_set(result,'{rows}',coalesce((select jsonb_agg(r||jsonb_build_object('next_activity',
  case when r->>'row_kind'='quote' then private.sales_next_activity((r->>'id')::uuid) end) order by n)
  from jsonb_array_elements(result->'rows') with ordinality x(r,n)),'[]'));
 return result;$code$);execute body;
end $$;

-- Keep the existing total calculation and permission boundary. Detailed costs
-- require the same financial module access as other sales financial details.
alter function private.gama_commercial_planning(text,jsonb) rename to gama_commercial_planning_before_distribution;
revoke all on function private.gama_commercial_planning_before_distribution(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_commercial_planning(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;rows jsonb;allowed boolean;begin
 result:=private.gama_commercial_planning_before_distribution(p_action,p_data);
 if p_action='quote_margin' then
  allowed:=private.erp_module_allowed('payments',array['administrador','comercial']);
  if allowed then
   select coalesce(jsonb_agg(jsonb_build_object('index',n-1,'product_id',x->>'product_id',
    'net',round((x->>'quantity')::numeric*(x->>'unit_price')::numeric,2),
    'cost_known',p.purchase_price>0,'unit_cost',case when p.purchase_price>0 then p.purchase_price end,
    'margin_percent',case when p.purchase_price>0 and (x->>'unit_price')::numeric>0 then
      round(100*((x->>'unit_price')::numeric-p.purchase_price)/(x->>'unit_price')::numeric,2) end)
     order by n),'[]') into rows from jsonb_array_elements(p_data->'lines') with ordinality a(x,n)
     left join public.products p on p.id=(x->>'product_id')::uuid;
  end if;
  result:=result||jsonb_build_object('can_view_line_margins',allowed,'line_margins',coalesce(rows,'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_commercial_planning(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_commercial_planning(text,jsonb) to authenticated;

-- Match gama_allocate_sales_product's FIFO order. Active reservations are
-- excluded from free supply and from queued demand, never subtracted twice.
create function private.sales_availability_line(p_product uuid,p_quantity numeric,p_order uuid default null,p_line uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare pr public.products;o public.sales_orders;free numeric;own_reserved numeric:=0;prior numeric:=0;
 needed numeric;supply numeric;earliest date;today date:=(now() at time zone private.erp_timezone())::date;
 incoming jsonb;late numeric;undated numeric;r record;begin
 if p_quantity is null or p_quantity::text='NaN' or p_quantity<0 or p_quantity>=100000000 then raise exception 'INVALID_QUANTITY';end if;
 select * into pr from public.products where id=p_product and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if pr.product_kind='service' then return jsonb_build_object('product_id',pr.id,'name',pr.name,'quantity',p_quantity,'service',true,'available_date',null);end if;
 if p_order is not null then select * into o from public.sales_orders where id=p_order;end if;
 select coalesce(sum(greatest(q.quantity-q.reserved_quantity,0)),0) into free
 from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id
 where q.product_id=p_product and l.active and w.active;
 if p_line is not null then
  select coalesce(sum(sr.quantity),0) into own_reserved from public.stock_reservations sr
   join public.sales_reservation_links sl on sl.reservation_id=sr.id
   join public.sales_order_lines ol on ol.id=sl.line_id
   where ol.id=p_line and ol.order_id=p_order and ol.product_id=p_product and sr.status='active';
 end if;
 select coalesce(sum(greatest(0,l.quantity
  -coalesce((select sum(d.quantity) from public.sales_delivery_lines d where d.order_line_id=l.id),0)
  -coalesce((select sum(sr.quantity) from public.sales_reservation_links sl join public.stock_reservations sr on sr.id=sl.reservation_id where sl.line_id=l.id and sr.status='active'),0))),0)
 into prior from public.sales_order_lines l join public.sales_orders so on so.id=l.order_id
 where l.product_id=p_product and so.status='confirmed' and l.id is distinct from p_line
  and (o.id is null or o.status<>'confirmed' or (so.created_at,so.id)<=(o.created_at,o.id));
 needed:=greatest(p_quantity-own_reserved,0);supply:=free;
 if needed=0 or free>=prior+needed then earliest:=today;end if;
 select coalesce(jsonb_agg(jsonb_build_object('purchase_id',po.id,'number',po.order_number,
  'date',(po.expected_date at time zone private.erp_timezone())::date,'quantity',l.quantity-l.received_quantity)
  order by po.expected_date,po.id,l.id),'[]'),
  coalesce(sum(l.quantity-l.received_quantity) filter(where (po.expected_date at time zone private.erp_timezone())::date<today),0),
  coalesce(sum(l.quantity-l.received_quantity) filter(where po.expected_date is null),0)
 into incoming,late,undated from public.purchase_order_lines l join public.purchase_orders po on po.id=l.purchase_order_id
 left join public.warehouse_locations loc on loc.id=po.destination_location_id left join public.warehouses w on w.id=loc.warehouse_id
 where l.product_id=p_product and po.status in ('sent','partial') and l.quantity>l.received_quantity
  and (po.destination_location_id is null or (loc.active and w.active));
 if earliest is null then
  supply:=free;
  for r in select (x->>'date')::date expected,(x->>'quantity')::numeric quantity from jsonb_array_elements(incoming)x
    where (x->>'date')::date>=today order by (x->>'date')::date,x->>'purchase_id' loop
   supply:=supply+r.quantity;
   if supply>=prior+needed then earliest:=r.expected;exit;end if;
  end loop;
 end if;
 return jsonb_build_object('product_id',pr.id,'name',pr.name,'quantity',p_quantity,'service',false,
  'free_now',free,'reserved_for_order',own_reserved,'prior_unreserved',prior,'available_date',earliest,
  'late_incoming',late,'undated_incoming',undated,'incoming',incoming,'missing',greatest(prior+needed-supply,0));
end $$;

create function private.sales_availability(p_data jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.sales_orders;x jsonb;ls jsonb;rows jsonb:='[]';r jsonb;finger text;
 prep integer:=coalesce((p_data->>'preparation_days')::integer,0);transit integer:=coalesce((p_data->>'transport_days')::integer,0);begin
 perform private.sales_access('summary');
 if prep not between 0 and 60 or transit not between 0 and 60 then raise exception 'INVALID_LEAD_DAYS';end if;
 if nullif(p_data->>'order_id','') is not null then
  select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid;
  if not found or o.status='cancelled' then raise exception 'ORDER_NOT_FOUND';end if;
  select jsonb_agg(jsonb_build_object('line_id',l.id,'product_id',l.product_id,'quantity',greatest(0,l.quantity-coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))) order by l.id)
   into ls from public.sales_order_lines l where l.order_id=o.id and l.quantity>0;
 else ls:=p_data->'lines';end if;
 if jsonb_typeof(ls) is distinct from 'array' or jsonb_array_length(ls) not between 1 and 200 then raise exception 'INVALID_LINES';end if;
 if exists(select 1 from jsonb_array_elements(ls) item group by item->>'product_id' having count(*)>1) then raise exception 'DUPLICATE_PRODUCT';end if;
 for x in select value from jsonb_array_elements(ls) loop
  if o.id is not null and x->>'line_id'=p_data->>'line_id' and p_data ? 'quantity' then
   if (p_data->>'quantity')::numeric<=0 or (p_data->>'quantity')::numeric>(x->>'quantity')::numeric then raise exception 'INVALID_QUANTITY';end if;
   x:=jsonb_set(x,'{quantity}',to_jsonb((p_data->>'quantity')::numeric));
  end if;
  r:=private.sales_availability_line((x->>'product_id')::uuid,(x->>'quantity')::numeric,o.id,nullif(x->>'line_id','')::uuid);
  r:=r||jsonb_build_object('line_id',x->'line_id','delivery_date',((r->>'available_date')::date+prep+transit),
   'promised_date',(select promised_date from public.sales_order_lines where id=nullif(x->>'line_id','')::uuid));
  rows:=rows||jsonb_build_array(r);
 end loop;
 finger:=md5(jsonb_build_object('order',o.id,'lines',rows,'preparation_days',prep,'transport_days',transit)::text);
 return jsonb_build_object('today',(now() at time zone private.erp_timezone())::date,'rows',rows,'fingerprint',finger,
  'preparation_days',prep,'transport_days',transit,'confirmed',o.status='confirmed','order_id',o.id);
end $$;

alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_distribution;
revoke all on function private.gama_sales_dossier_before_distribution(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_action='availability' then return private.sales_availability(p_data);end if;
 if p_action in ('option_review','option_approve') then return private.sales_option_review(p_data,p_action='option_approve');end if;
 return private.gama_sales_dossier_before_distribution(p_action,p_data);
end $$;
revoke all on function private.sales_next_activity(uuid),private.sales_availability_line(uuid,numeric,uuid,uuid),private.sales_availability(jsonb),private.gama_sales_dossier(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;

-- Review metadata belongs to the existing option. No second option state machine.
create table private.sales_option_terms(
 option_id uuid primary key references public.sales_fulfillment_options(id) on delete cascade,
 order_fingerprint text not null,pricing jsonb,price_mode text,price_reason text,
 shipped_at_agreement numeric check(shipped_at_agreement>=0),
 preparation_days integer not null default 0 check(preparation_days between 0 and 60),
 transport_days integer not null default 0 check(transport_days between 0 and 60),
 approved_by uuid references auth.users(id),approved_at timestamptz,approval_reason text,approval_fingerprint text,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now());
alter table private.sales_option_terms enable row level security;
revoke all on private.sales_option_terms from public,anon,authenticated,service_role;

create function private.sales_option_review(p_data jsonb,p_approve boolean default false,p_internal boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare opt public.sales_fulfillment_options;terms private.sales_option_terms;review jsonb;revenue numeric;cost numeric;missing integer;reason text;finger text;begin
 if not p_internal then
  perform private.sales_access('review_order');
  if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 elsif p_approve then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into opt from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid;
 if not found or opt.status<>'proposed' or opt.kind<>'substitute' then raise exception 'OPTION_CLOSED';end if;
 select * into terms from private.sales_option_terms where option_id=opt.id;
 review:=private.sales_order_review(opt.order_id);
 if terms.order_fingerprint is distinct from review->>'fingerprint' then raise exception 'OPTION_TERMS_CHANGED';end if;
 with candidate as(
  select greatest(0,l.quantity-case when l.id=opt.line_id then opt.quantity else 0 end) qty,l.unit_price price,c.unit_cost cost
   from public.sales_order_lines l left join private.order_cost_snapshots c on c.line_id=l.id where l.order_id=opt.order_id
  union all select opt.quantity,opt.unit_price,nullif(p.purchase_price,0) from public.products p where p.id=opt.replacement_product_id)
 select sum(c.qty*c.price),sum(c.qty*c.cost),count(*) filter(where c.qty>0 and c.cost is null) into revenue,cost,missing from candidate c;
 finger:=md5(jsonb_build_object('order',terms.order_fingerprint,'option',to_jsonb(opt),'revenue',revenue,'cost',cost,'missing',missing,
  'limits',(select to_jsonb(s) from private.sales_workspace_settings s where id))::text);
 if p_approve then
  perform private.sales_access('approve_order');reason:=btrim(coalesce(p_data->>'reason',''));
  if length(reason) not between 3 and 1000 then raise exception 'REASON_REQUIRED';end if;
  if p_data->>'fingerprint' is distinct from finger then raise exception 'OPTION_TERMS_CHANGED';end if;
  update private.sales_option_terms set approved_by=auth.uid(),approved_at=now(),approval_reason=reason,approval_fingerprint=finger where option_id=opt.id;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(opt.order_id,'substitution_commercial_approved',opt.id,auth.uid(),jsonb_build_object('reason',reason,'fingerprint',terms.order_fingerprint));
 end if;
 return jsonb_build_object('option_id',opt.id,'fingerprint',finger,'net',revenue,'missing_costs',missing,
  'margin_percent',case when private.erp_module_allowed('payments',array['administrador','comercial']) and missing=0 and revenue>0 then round(100*(revenue-cost)/revenue,2) end,
  'price_mode',terms.price_mode,'price_reason',terms.price_reason,'approved',(terms.approved_by is not null and terms.approval_fingerprint=finger) or p_approve);
end $$;
revoke all on function private.sales_option_review(jsonb,boolean,boolean) from public,anon,authenticated,service_role;

create function private.sales_option_date_check(p_order uuid,p_line uuid,p_date date,p_prep integer,p_transit integer,p_fingerprint text default null,p_quantity numeric default null)
returns void language plpgsql security definer set search_path='' as $$
declare forecast jsonb;line jsonb;begin
 if p_date is null then return;end if;
 forecast:=private.sales_availability(jsonb_build_object('order_id',p_order,'preparation_days',p_prep,'transport_days',p_transit)||case when p_quantity is not null then jsonb_build_object('line_id',p_line,'quantity',p_quantity) else '{}'::jsonb end);
 if p_fingerprint is not null and forecast->>'fingerprint'<>p_fingerprint then raise exception 'FORECAST_CHANGED';end if;
 select x into line from jsonb_array_elements(forecast->'rows')x where x->>'line_id'=p_line::text;
 if line is null or nullif(line->>'delivery_date','') is null or p_date<(line->>'delivery_date')::date then raise exception 'PROMISE_NOT_FEASIBLE';end if;
end $$;

alter function private.gama_fulfillment_action(text,jsonb) rename to gama_fulfillment_action_before_distribution;
revoke all on function private.gama_fulfillment_action_before_distribution(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_fulfillment_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;opt public.sales_fulfillment_options;terms private.sales_option_terms;o public.sales_orders;
 old_line public.sales_order_lines;replacement public.sales_order_lines;pr public.products;price jsonb;review jsonb;option_review jsonb;
 prep integer:=coalesce((p_data->>'preparation_days')::integer,0);transit integer:=coalesce((p_data->>'transport_days')::integer,0);
 before_credit numeric;after_credit numeric;mode text;reason text;begin
 if p_action not in ('propose_option','respond_option') then return private.gama_fulfillment_action_before_distribution(p_action,p_data);end if;
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 perform pg_advisory_xact_lock(741932,1);
 -- Let the canonical receipt validate actor, action and exact payload on retry.
 if exists(select 1 from private.fulfillment_requests where request_key=nullif(p_data->>'request_key','')::uuid) then
  return private.gama_fulfillment_action_before_distribution(p_action,p_data);
 end if;
 if p_action='propose_option' then
  perform private.sales_access('summary');
  if coalesce(private.current_user_role(),'') not in ('administrador','comercial') or not private.erp_action_allowed('sales-orders','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid and status='confirmed' for update;
  if not found then raise exception 'CONFIRM_ORDER_FIRST';end if;
  select * into old_line from public.sales_order_lines where id=(p_data->>'line_id')::uuid and order_id=o.id;
  if not found then raise exception 'INVALID_ORDER_LINE';end if;
  if prep not between 0 and 60 or transit not between 0 and 60 then raise exception 'INVALID_LEAD_DAYS';end if;
  if p_data->>'kind'='substitute' then
   select * into pr from public.products where id=(p_data->>'replacement_product_id')::uuid and active;
   if not found or pr.product_kind<>'goods' then raise exception 'PRODUCT_NOT_FOUND';end if;
   if old_line.product_id=pr.id then raise exception 'PRODUCT_NOT_FOUND';end if;
   if mod(old_line.quantity-(p_data->>'quantity')::numeric,coalesce(old_line.sales_unit_factor,1))<>0
     and coalesce(old_line.sales_unit_factor,1)<>1 then raise exception 'SALES_UNIT_QUANTITY';end if;
   price:=private.erp_price(o.customer_id,pr.id,(p_data->>'quantity')::numeric,(now() at time zone private.erp_timezone())::date);
   mode:=coalesce(p_data->>'price_mode','manual');reason:=btrim(coalesce(p_data->>'price_reason',''));
   if mode not in ('auto','manual') then raise exception 'INVALID_PRICE_MODE';end if;
   if mode='manual' and length(reason) not between 3 and 500 then raise exception 'SALES_PRICE_REASON_REQUIRED';end if;
   if mode='auto' and (p_data->>'unit_price')::numeric is distinct from (price->>'unit_price')::numeric then raise exception 'SALES_PRICE_CHANGED';end if;
   if (p_data->>'tax_rate')::numeric is distinct from pr.tax_rate then raise exception 'SALES_TAX_CHANGED';end if;
   -- Replacement is an independently agreed base-unit quantity. The accepted
   -- quote and its original pack/price explanation remain untouched.
   if nullif(p_data->>'promised_date','') is not null then raise exception 'SUBSTITUTION_DATE_SEPARATE';end if;
  elsif nullif(p_data->>'promised_date','') is not null then
   if nullif(p_data->>'forecast_fingerprint','') is null then raise exception 'FORECAST_REQUIRED';end if;
   perform private.sales_option_date_check(o.id,old_line.id,(p_data->>'promised_date')::date,prep,transit,p_data->>'forecast_fingerprint',case when p_data->>'kind'='partial' then (p_data->>'quantity')::numeric end);
  end if;
  review:=private.sales_order_review(o.id);
  result:=private.gama_fulfillment_action_before_distribution(p_action,p_data);
  insert into private.sales_option_terms(option_id,order_fingerprint,pricing,price_mode,price_reason,preparation_days,transport_days,created_by)
   values((result->>'id')::uuid,review->>'fingerprint',price,mode,reason,prep,transit,auth.uid());
  return result;
 end if;
 select * into opt from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid;
 select * into o from public.sales_orders where id=opt.order_id;
 if o.id is null or (private.current_user_role()='cliente' and not private.gama_owns_customer(o.customer_id)) then raise exception 'ORDER_NOT_FOUND';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if private.current_user_role()<>'cliente' and not private.erp_action_allowed('sales-orders','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data->>'decision'<>'accepted' then return private.gama_fulfillment_action_before_distribution(p_action,p_data);end if;
 select * into terms from private.sales_option_terms where option_id=opt.id;
 if not found then raise exception 'OPTION_REPROPOSE_REQUIRED';end if;
 review:=private.sales_order_review(o.id);
 if terms.order_fingerprint is distinct from review->>'fingerprint' then raise exception 'OPTION_TERMS_CHANGED';end if;
 -- The customer's own portal path cannot call a staff-only forecast RPC.
 -- The internal helper performs the same checks under the verified option scope.
 if opt.promised_date is not null then
  if private.current_user_role()='cliente' then
   select * into old_line from public.sales_order_lines where id=opt.line_id;
   price:=private.sales_availability_line(old_line.product_id,case when opt.kind='partial' then opt.quantity else greatest(0,old_line.quantity-coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=old_line.id),0)) end,o.id,old_line.id);
   if nullif(price->>'available_date','') is null or opt.promised_date<(price->>'available_date')::date+terms.preparation_days+terms.transport_days then raise exception 'PROMISE_NOT_FEASIBLE';end if;
  else perform private.sales_option_date_check(o.id,opt.line_id,opt.promised_date,terms.preparation_days,terms.transport_days,null,case when opt.kind='partial' then opt.quantity end);end if;
 end if;
 if opt.kind='substitute' then
  perform 1 from public.customers where id=o.customer_id for update;
  perform 1 from public.products where id=opt.replacement_product_id for update;
  -- Staff commercial approval is checked without exposing any cost to clients.
  option_review:=private.sales_option_review(jsonb_build_object('option_id',opt.id),false,true);
  before_credit:=(private.gama_credit_snapshot(o.customer_id,o.id)->>'exposure')::numeric;
  select * into old_line from public.sales_order_lines where id=opt.line_id;
  select * into replacement from public.sales_order_lines where order_id=o.id and product_id=opt.replacement_product_id;
  if replacement.id is not null and coalesce(replacement.sales_unit_factor,1)<>1
    and mod(replacement.quantity+opt.quantity,replacement.sales_unit_factor)<>0 then raise exception 'SALES_UNIT_QUANTITY';end if;
 end if;
 update private.sales_option_terms set shipped_at_agreement=coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=opt.line_id),0) where option_id=opt.id;
 result:=private.gama_fulfillment_action_before_distribution(p_action,p_data);
 if opt.kind='substitute' then
  update public.sales_order_lines set sales_quantity=nullif(quantity/coalesce(sales_unit_factor,1),0),next_dispatch_quantity=null where id=opt.line_id;
  if replacement.id is null then
   update public.sales_order_lines set sales_quantity=quantity,sales_unit_factor=1,
    price_source=terms.pricing||jsonb_build_object('manual',terms.price_mode='manual','reason',terms.price_reason,'option_id',opt.id)
    where order_id=o.id and product_id=opt.replacement_product_id;
  else update public.sales_order_lines set sales_quantity=quantity/coalesce(sales_unit_factor,1) where id=replacement.id;end if;
  review:=private.sales_order_review(o.id);
  if (review->>'required')::boolean and not coalesce((review->>'approved')::boolean,false) then
   if terms.approved_by is null or terms.approval_fingerprint is distinct from option_review->>'fingerprint' or not exists(select 1 from public.profiles where id=terms.approved_by and active and role='administrador') then raise exception 'SALES_APPROVAL_REQUIRED';end if;
   insert into private.sales_order_approvals(order_id,fingerprint,requested_by,requested_at,approved_by,approved_at,reason)
    values(o.id,review->>'fingerprint',terms.created_by,terms.created_at,terms.approved_by,terms.approved_at,terms.approval_reason)
    on conflict(order_id) do update set fingerprint=excluded.fingerprint,requested_by=excluded.requested_by,requested_at=excluded.requested_at,approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason;
  end if;
  after_credit:=(private.gama_credit_snapshot(o.customer_id,o.id)->>'exposure')::numeric;
  if after_credit>before_credit then perform private.gama_enforce_customer_credit(o.customer_id,o.id,false);end if;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
   values(o.id,'substitution_agreement_applied',opt.id,auth.uid(),jsonb_build_object('line_id',opt.line_id,'product_id',opt.replacement_product_id,'quantity',opt.quantity,'agreement_reference',p_data->>'agreement_reference','price_mode',terms.price_mode));
 end if;return result;
end $$;
revoke all on function private.sales_option_date_check(uuid,uuid,date,integer,integer,text,numeric),private.gama_fulfillment_action(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_fulfillment_action(text,jsonb) to authenticated;

-- A partial promise covers the agreed batch plus earlier dispatches, not all
-- future backorders. Completion still uses the canonical signed-delivery total.
create function private.sales_promise_target(p_line uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select case when l.delivery_policy='partial' and f.shipped_at_agreement is not null
  then least(l.quantity,f.shipped_at_agreement+f.quantity) else l.quantity end
 from public.sales_order_lines l left join lateral(
  select o.quantity,t.shipped_at_agreement from public.sales_fulfillment_options o
  join private.sales_option_terms t on t.option_id=o.id
  where o.line_id=l.id and o.status='accepted' and o.kind=l.delivery_policy and o.promised_date is not distinct from l.promised_date
  order by o.responded_at desc,o.id desc limit 1) f on true where l.id=p_line
$$;
revoke all on function private.sales_promise_target(uuid) from public,anon,authenticated,service_role;

-- Feed the current role-aware exception hub instead of creating another queue.
do $$declare src text:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');begin
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$view$
 union all
 select 'sales_activity:'||a.id,'sales_activity',coalesce(d.order_id,d.quote_id),case when d.order_id is null then 'quote' else 'order' end,
  coalesce(o.number,q.invoice_number),'Seguimiento comercial','Actividad comercial vencida',a.title||' · '||coalesce(p.full_name,'—'),a.due_at,2,true,false,'danger',(a.due_at at time zone private.erp_timezone())::date
 from private.sales_activities a join private.sales_dossiers d on d.id=a.dossier_id
 left join public.sales_orders o on o.id=d.order_id left join public.invoices q on q.id=d.quote_id left join public.profiles p on p.id=a.owner_id
 where a.completed_at is null and a.due_at<now() and private.erp_module_allowed(case when d.order_id is null then 'quotes' else 'sales-orders' end,array['administrador','comercial'])
 union all
 select 'sales_option:'||f.id,'sales_option',o.id,'order',o.number,o.customer_name,'Acuerdo del cliente pendiente',l.product_name||' · '||f.quantity::text,f.created_at,1,true,false,'warning',f.promised_date
 from public.sales_fulfillment_options f join public.sales_orders o on o.id=f.order_id join public.sales_order_lines l on l.id=f.line_id
 where f.status='proposed' and o.status='confirmed' and private.erp_module_allowed('sales-orders',array['administrador','comercial'])
 union all
 select 'sales_promise:'||l.id,'sales_promise',o.id,'order',o.number,o.customer_name,'Compromiso de entrega vencido',l.product_name||' · '||l.promised_date::text,
  l.promised_date::timestamp at time zone private.erp_timezone(),3,false,false,'danger',l.promised_date
 from public.sales_order_lines l join public.sales_orders o on o.id=l.order_id
 where o.status='confirmed' and l.promised_date<(now() at time zone private.erp_timezone())::date
  and private.sales_promise_target(l.id)>coalesce(private.gama_line_performed(l.id,true),0)
  and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero'])
 $view$;
end $$;
-- Reuse the sanitized module history and its transaction-local Agent Coco
-- provenance. No snapshot, price or free-text approval reason enters the index.
insert into private.coco_history_tables(table_name,module_id,label,parent_column,parent_table,table_schema,key_column) values
 ('sales_fulfillment_options','sales-orders','Acuerdo de entrega / sustitución','order_id','sales_orders','public','id'),
 ('sales_option_terms','sales-orders','Condiciones de sustitución','option_id','sales_fulfillment_options','private','option_id');
create trigger coco_module_history after insert or update or delete on public.sales_fulfillment_options
 for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.sales_option_terms
 for each row execute function private.coco_capture_module_event();
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_distribution(');end $$;
revoke all on function private.coco_history_record_visible_before_distribution(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible_before_distribution(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_option_terms' then
  return coalesce(private.current_user_role(),'') in ('administrador','comercial')
   and private.coco_module_allowed('sales-orders')
   and exists(select 1 from public.sales_fulfillment_options f where f.id::text=p_id);
 end if;
 return private.coco_history_record_visible_before_distribution(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
notify pgrst,'reload schema';
