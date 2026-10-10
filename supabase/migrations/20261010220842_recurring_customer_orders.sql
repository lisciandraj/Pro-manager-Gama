-- A scheduled occurrence is only a proposal. Customer confirmation uses the
-- canonical B2B request flow; credit, quotation acceptance and stock stay there.
create table private.recurring_orders(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.customers(id),name text not null check(length(btrim(name)) between 1 and 80),lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),frequency text not null check(frequency in ('weekly','monthly')),interval_count integer not null default 1 check(interval_count between 1 and 12),anchor_day integer not null check(anchor_day between 1 and 31),next_date date not null,address_id uuid references public.customer_addresses(id),notes text not null default '' check(length(notes)<=2000),active boolean not null default true,version integer not null default 1,created_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index recurring_orders_customer on private.recurring_orders(customer_id);
create index recurring_orders_due on private.recurring_orders(next_date) where active;
create table private.recurring_occurrences(id uuid primary key default gen_random_uuid(),schedule_id uuid not null references private.recurring_orders(id),due_date date not null,version integer not null,lines jsonb not null,state text not null default 'pending' check(state in ('pending','confirmed','skipped','cancelled')),request_id uuid references public.customer_requests(id),confirmation jsonb,created_at timestamptz not null default now(),decided_at timestamptz,unique(schedule_id,due_date,version));
create index recurring_occurrences_pending on private.recurring_occurrences(schedule_id) where state='pending';
alter table private.recurring_orders enable row level security;alter table private.recurring_occurrences enable row level security;
revoke all on private.recurring_orders,private.recurring_occurrences from public,anon,authenticated;
create function private.recurring_advance(s private.recurring_orders,p_date date) returns date language plpgsql immutable set search_path='' as $$
declare month date;begin
 if s.frequency='weekly' then return p_date+7*s.interval_count;end if;
 month:=(date_trunc('month',p_date)+make_interval(months=>s.interval_count))::date;
 return month+least(s.anchor_day,extract(day from month+interval '1 month -1 day')::integer)-1;
end $$;
create function private.recurring_tick(p_customer uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare n integer;begin
 if not pg_try_advisory_xact_lock(hashtextextended('recurring-orders',0)) then return jsonb_build_object('busy',true);end if;
 insert into private.recurring_occurrences(schedule_id,due_date,version,lines)
 select s.id,s.next_date,s.version,s.lines from private.recurring_orders s join public.customers c on c.id=s.customer_id and c.active join public.b2b_customer_access a on a.customer_id=c.id and a.enabled
 where s.active and (p_customer is null or s.customer_id=p_customer) and s.next_date<=(now() at time zone private.erp_timezone())::date and not exists(select 1 from private.recurring_occurrences o where o.schedule_id=s.id and o.state='pending') order by s.next_date,s.id limit 200 for update of s skip locked on conflict do nothing;
 get diagnostics n=row_count;return jsonb_build_object('prepared',n);end $$;
create function private.gama_recurring_orders(p_action text,p_data jsonb,p_portal boolean) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare customer uuid;target uuid;s private.recurring_orders;o private.recurring_occurrences;basket jsonb;lines jsonb;result jsonb;next_day date;today date:=(now() at time zone private.erp_timezone())::date;payload jsonb;begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>64000 then raise exception 'INVALID_REQUEST';end if;
 if p_portal then customer:=private.gama_b2b_customer();
 else
  if not private.erp_mfa_ok() or not private.erp_module_allowed('sales-orders',array['administrador','comercial']) or (p_action<>'list' and not private.erp_action_allowed('sales-orders','create')) then raise exception 'ROLE_NOT_ALLOWED';end if;
  customer:=nullif(p_data->>'customer_id','')::uuid;
 end if;
 if p_action='list' then
  perform private.recurring_tick(customer);
  return jsonb_build_object('today',today,'plans',coalesce((select jsonb_agg(to_jsonb(x)) from(select sched.*,c.name customer from private.recurring_orders sched join public.customers c on c.id=sched.customer_id where customer is null or sched.customer_id=customer order by sched.next_date,sched.id limit 100)x),'[]'),
   'occurrences',coalesce((select jsonb_agg(to_jsonb(x)) from(select occ.*,sched.name,sched.customer_id,c.name customer from private.recurring_occurrences occ join private.recurring_orders sched on sched.id=occ.schedule_id join public.customers c on c.id=sched.customer_id where customer is null or sched.customer_id=customer order by (occ.state='pending') desc,occ.due_date desc,occ.id limit 200)x),'[]'));
 elsif p_action='save' then
  target:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());perform pg_advisory_xact_lock(hashtextextended('recurring:'||target,0));
  select * into s from private.recurring_orders where id=target for update;
  if s.id is not null and (customer is not null and s.customer_id<>customer) then raise exception 'NOT_FOUND';end if;
  if coalesce(s.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  customer:=coalesce(s.customer_id,customer);lines:=p_data->'lines';
  if not p_portal and nullif(p_data->>'order_id','') is not null then
   select customer_id into customer from public.sales_orders where id=(p_data->>'order_id')::uuid and status<>'cancelled';if customer is null then raise exception 'NOT_FOUND';end if;
   if s.id is not null and s.customer_id<>customer then raise exception 'NOT_FOUND';end if;
   select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity) order by id) into lines from public.sales_order_lines where order_id=(p_data->>'order_id')::uuid;
  end if;
  if not exists(select 1 from public.customers where id=customer and active) then raise exception 'CUSTOMER_REQUIRED';end if;
  if s.id is null and (select count(*) from private.recurring_orders where customer_id=customer)>=50 then raise exception 'RECURRING_LIMIT';end if;
  basket:=private.gama_b2b_cart(customer,lines);
  select jsonb_agg(jsonb_build_object('product_id',x->>'product_id','quantity',x->'quantity','name',x->>'name')) into lines from jsonb_array_elements(basket->'lines')x;
  next_day:=(p_data->>'next_date')::date;if next_day is null or next_day<today or next_day>today+366 then raise exception 'INVALID_DATE';end if;
  if nullif(p_data->>'address_id','') is not null and not exists(select 1 from public.customer_addresses where id=(p_data->>'address_id')::uuid and customer_id=customer and active) then raise exception 'B2B_ADDRESS_INVALID';end if;
  insert into private.recurring_orders(id,customer_id,name,lines,frequency,interval_count,anchor_day,next_date,address_id,notes,active,created_by) values(target,customer,p_data->>'name',lines,p_data->>'frequency',coalesce((p_data->>'interval_count')::integer,1),extract(day from next_day),next_day,nullif(p_data->>'address_id','')::uuid,coalesce(p_data->>'notes',''),coalesce((p_data->>'active')::boolean,true),auth.uid()) on conflict(id) do update set name=excluded.name,lines=excluded.lines,frequency=excluded.frequency,interval_count=excluded.interval_count,anchor_day=excluded.anchor_day,next_date=excluded.next_date,address_id=excluded.address_id,notes=excluded.notes,active=excluded.active,version=recurring_orders.version+1,updated_at=now();
  update private.recurring_occurrences set state='cancelled',decided_at=now() where schedule_id=target and state='pending';perform private.recurring_tick(customer);return jsonb_build_object('id',target);
 elsif p_action='toggle' then
  select * into s from private.recurring_orders where id=(p_data->>'id')::uuid and (customer is null or customer_id=customer) for update;if not found then raise exception 'NOT_FOUND';end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  update private.recurring_orders set active=(p_data->>'active')::boolean,version=version+1,updated_at=now() where id=s.id;update private.recurring_occurrences set state='cancelled',decided_at=now() where schedule_id=s.id and state='pending';return jsonb_build_object('saved',true);
 elsif p_action in ('preview','confirm','skip') then
  if not p_portal then raise exception 'CUSTOMER_CONFIRMATION_REQUIRED';end if;
  select r.* into s from private.recurring_orders r join private.recurring_occurrences x on x.schedule_id=r.id where x.id=(p_data->>'id')::uuid and r.customer_id=customer for update of r;if not found then raise exception 'NOT_FOUND';end if;
  select * into o from private.recurring_occurrences where id=(p_data->>'id')::uuid for update;
  payload:=p_data-'price_hash';
  if o.state='confirmed' and p_action='confirm' then if o.confirmation is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return jsonb_build_object('id',o.request_id,'existing',true);end if;
  if o.state<>'pending' or not s.active or s.version<>o.version then raise exception 'RECORD_CHANGED';end if;
  lines:=coalesce(p_data->'lines',o.lines);
  if p_action='preview' then return private.gama_b2b_cart(customer,lines)||jsonb_build_object('address_id',s.address_id,'notes',s.notes);end if;
  if p_action='confirm' then
   result:=private.gama_b2b_action('submit',jsonb_build_object('request_key',o.id,'lines',lines,'price_hash',p_data->>'price_hash','address_id',s.address_id,'notes',s.notes,'requested_delivery_date',p_data->>'requested_delivery_date'));
   update private.recurring_occurrences set state='confirmed',request_id=(result->>'id')::uuid,confirmation=payload,decided_at=now() where id=o.id;
  else update private.recurring_occurrences set state='skipped',decided_at=now() where id=o.id;result:=jsonb_build_object('skipped',true);end if;
  next_day:=private.recurring_advance(s,s.next_date);while next_day<=today loop next_day:=private.recurring_advance(s,next_day);end loop;
  update private.recurring_orders set next_date=next_day,updated_at=now() where id=s.id;return result;
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_recurring_orders(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_recurring_orders(p_action,p_data,false)$$;
create function public.gama_b2b_recurring(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_recurring_orders(p_action,p_data,true)$$;
revoke all on function private.recurring_advance(private.recurring_orders,date),private.recurring_tick(uuid),private.gama_recurring_orders(text,jsonb,boolean),public.gama_recurring_orders(text,jsonb),public.gama_b2b_recurring(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_recurring_orders(text,jsonb,boolean),public.gama_recurring_orders(text,jsonb),public.gama_b2b_recurring(text,jsonb) to authenticated;
select cron.schedule('coco-recurring-orders','15 * * * *','select private.recurring_tick()');

create trigger planning_audit after insert or update or delete on private.recurring_orders for each row execute function private.erp_audit_capture();
create trigger planning_audit after insert or update or delete on private.recurring_occurrences for each row execute function private.erp_audit_capture();
