-- Operational profitability and cash planning. Planning never posts accounting entries.
create table private.commercial_settings(id boolean primary key default true check(id),minimum_margin numeric not null default 20 check(minimum_margin between 0 and 100));
insert into private.commercial_settings(id) values(true);
create table private.order_cost_snapshots(line_id uuid primary key references public.sales_order_lines(id) on delete cascade,unit_cost numeric check(unit_cost>=0 and unit_cost<'Infinity'::numeric),captured_at timestamptz not null default now());
create table private.order_operating_costs(order_id uuid not null references public.sales_orders(id),kind text not null check(kind in ('preparation','delivery','returns','other')),amount numeric not null check(amount>=0 and amount<1000000000 and amount=round(amount,2)),basis text not null check(basis in ('estimated','actual')),evidence text not null check(length(btrim(evidence)) between 3 and 1000),version integer not null default 1,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now(),primary key(order_id,kind));
create table private.cash_scenarios(id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 80),customer_delay integer not null default 0 check(customer_delay between 0 and 180),supplier_delay integer not null default 0 check(supplier_delay between 0 and 180),collection_percent numeric not null default 100 check(collection_percent between 0 and 100),minimum_balance numeric not null default 0 check(abs(minimum_balance)<1000000000),version integer not null default 1,created_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create table private.cash_commitments(id uuid primary key default gen_random_uuid(),label text not null check(length(btrim(label)) between 1 and 160),kind text not null check(kind in ('payroll','tax','rent','other')),direction text not null check(direction in ('in','out')),amount numeric not null check(amount>0 and amount<1000000000 and amount=round(amount,2)),due_date date not null,repeat_monthly boolean not null default false,end_date date,active boolean not null default true,version integer not null default 1,created_by uuid not null references public.profiles(id),updated_at timestamptz not null default now(),check(end_date is null or end_date>=due_date));
create index cash_commitments_due on private.cash_commitments(due_date) where active;
do $$declare t text;begin foreach t in array array['commercial_settings','order_cost_snapshots','order_operating_costs','cash_scenarios','cash_commitments'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;end $$;
create function private.commercial_require(p_right text default 'view') returns void language plpgsql stable security definer set search_path='' as $$
declare r jsonb:=private.gama_accounting_rights();begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or r->>'scope'<>'all' or not coalesce((r->>p_right)::boolean,false) or (p_right<>'view' and not private.erp_action_allowed('accounting',p_right)) then raise exception 'ROLE_NOT_ALLOWED';end if;
end $$;
create function private.capture_order_cost() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.product_id is not distinct from old.product_id then return new;end if;
 insert into private.order_cost_snapshots(line_id,unit_cost) select new.id,case when p.purchase_price>0 then p.purchase_price end from public.products p where p.id=new.product_id on conflict(line_id) do update set unit_cost=excluded.unit_cost,captured_at=now();return new;
end $$;
create trigger capture_order_cost after insert or update of product_id on public.sales_order_lines for each row execute function private.capture_order_cost();

create function private.commercial_profit(p_from date,p_to date,p_customer uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 perform private.commercial_require();if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 with orders as materialized(select o.* from public.sales_orders o where o.status<>'cancelled' and (p_customer is null or o.customer_id=p_customer) and (o.created_at at time zone private.erp_timezone())::date between p_from and p_to),
 movement_cost as(select m.reference_id,m.product_id,sum(m.quantity*m.unit_cost_at_movement)/nullif(sum(m.quantity),0) cost,bool_and(m.unit_cost_at_movement is not null) complete from public.stock_movements m where m.type='out' and m.movement_type='delivery' and m.reference_type='sales_delivery' and exists(select 1 from public.sales_deliveries d join orders o on o.id=d.order_id where d.id=m.reference_id) group by m.reference_id,m.product_id),
 line_cost as(select l.id,sum(d.quantity*c.cost)/nullif(sum(d.quantity),0) cost,bool_and(coalesce(c.complete,false)) complete from public.sales_order_lines l join orders o on o.id=l.order_id join public.sales_delivery_lines d on d.order_line_id=l.id left join movement_cost c on c.reference_id=d.delivery_id and c.product_id=l.product_id group by l.id),
 expected as(select l.order_id,sum(round(l.quantity*l.unit_price,2)) revenue,sum(l.quantity*coalesce(s.unit_cost,nullif(p.purchase_price,0))) cost,count(*) filter(where coalesce(s.unit_cost,nullif(p.purchase_price,0)) is null) missing from public.sales_order_lines l join orders o on o.id=l.order_id left join private.order_cost_snapshots s on s.line_id=l.id left join public.products p on p.id=l.product_id group by l.order_id),
 billed_cost as(select x.invoice_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x join public.sales_order_lines l on l.id=x.order_line_id join orders o on o.id=l.order_id left join line_cost c on c.id=l.id group by x.invoice_id),
 billed as(select i.order_id,sum(i.subtotal) revenue,sum(c.cost) cost,count(*) filter(where not coalesce(c.complete,false)) missing from public.external_invoices i join orders o on o.id=i.order_id left join billed_cost c on c.invoice_id=i.id where i.fiscal_status not in ('cancelled','rejected') group by i.order_id),
 credits as(select i.order_id,sum(c.amount*i.subtotal/nullif(i.total,0)) net from public.return_credits c join public.external_invoices i on i.id=c.invoice_id join orders o on o.id=i.order_id where i.fiscal_status not in ('cancelled','rejected') group by i.order_id),
 restored as(select r.order_id,sum(l.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.return_lines l join public.return_orders r on r.id=l.return_id join orders o on o.id=r.order_id join public.sales_delivery_lines d on d.id=l.delivery_line_id left join line_cost c on c.id=d.order_line_id where l.disposition='restocked' and l.processed_at is not null and exists(select 1 from public.return_credits n where n.return_id=r.id and n.invoice_id is not null) group by r.order_id),
 stops as(select r.id,r.cost_per_km,round(coalesce(s.road_km,r.distance)*r.cost_per_km*100) cents,x.stop,count(*) over(partition by r.id) n,row_number() over(partition by r.id order by x.stop collate "C") pos from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id cross join lateral(select distinct value stop from jsonb_array_elements_text(case when jsonb_typeof(r.stops)='array' then r.stops else '[]' end) where value<>'__depot')x),
 route_cost as(select d.order_id,sum((floor(s.cents/s.n)+case when s.pos<=mod(s.cents,s.n) then 1 else 0 end)/100) cost,count(*) filter(where s.cents is null) missing from public.sales_deliveries d join orders o on o.id=d.order_id join stops s on s.stop=d.tms_delivery_id::text group by d.order_id),
 operating as(select c.order_id,sum(c.amount) cost,bool_and(c.basis='actual') actual,bool_or(c.kind='delivery') delivery,count(*) filter(where c.kind='preparation') preparation from private.order_operating_costs c join orders o on o.id=c.order_id group by c.order_id),
 rows as(select o.id,o.customer_id,o.customer_name customer,coalesce(o.erp_reference,o.number) reference,o.created_at,
 coalesce(e.revenue,0) ordered_net,case when e.missing=0 then round(e.cost,2) end estimated_product_cost,
 round(coalesce(b.revenue,0)-coalesce(c.net,0),2) invoiced_net,round(coalesce(c.net,0),2) credits_net,
 case when coalesce(b.missing,0)=0 and coalesce(r.complete,true) then round(coalesce(b.cost,0)-coalesce(r.cost,0),2) end historical_product_cost,
 round(coalesce(a.cost,0)+case when coalesce(a.delivery,false) then 0 else coalesce(t.cost,0) end,2) operating_cost,
 coalesce(a.actual,false) and coalesce(a.delivery,false) and coalesce(a.preparation,0)>0 complete_operating_cost,
 coalesce(b.missing,0) missing_invoices,coalesce(t.missing,0) missing_route_costs,
 coalesce((select jsonb_agg(to_jsonb(k)-'updated_by' order by kind) from private.order_operating_costs k where k.order_id=o.id),'[]') costs
 from orders o left join expected e on e.order_id=o.id left join billed b on b.order_id=o.id left join credits c on c.order_id=o.id left join restored r on r.order_id=o.id left join route_cost t on t.order_id=o.id left join operating a on a.order_id=o.id),
 amounts as(select *,round(ordered_net-estimated_product_cost-operating_cost,2) estimated_margin,round(invoiced_net-historical_product_cost-operating_cost,2) known_margin from rows),
 customers as(select customer_id,customer,count(*) orders,sum(invoiced_net) invoiced_net,case when bool_and(known_margin is not null) then sum(known_margin) end known_margin,bool_and(complete_operating_cost and known_margin is not null) complete from amounts group by customer_id,customer)
 select jsonb_build_object('from',p_from,'to',p_to,'currency',(select currency from public.company_settings where id),'minimum_margin',(select minimum_margin from private.commercial_settings where id),
 'orders',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('margin_percent',round(100*known_margin/nullif(invoiced_net,0),2)) order by created_at desc,id) from amounts a),'[]'),
 'customers',coalesce((select jsonb_agg(to_jsonb(c) order by customer) from customers c),'[]')) into result;return result;
end $$;

create function private.cash_projection(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;s private.cash_scenarios;balance numeric;events jsonb;weeks jsonb;begin
 perform private.commercial_require();
 if nullif(p_data->>'scenario_id','') is not null then select * into s from private.cash_scenarios where id=(p_data->>'scenario_id')::uuid;if not found then raise exception 'NOT_FOUND';end if;end if;
 select coalesce(sum(current_balance),0) into balance from private.gama_cash_position where active;
 with source as(
 select 'receivable' kind,d.document_id id,d.number label,coalesce(d.due_date,today)+coalesce(s.customer_delay,0) due,round(d.balance*coalesce(s.collection_percent,100)/100,2) amount,'in' direction,d.due_date is null missing_date from private.gama_customer_dues() d where d.balance>0
 union all select 'payable',d.document_id,d.number,coalesce(d.due_date,today)+coalesce(s.supplier_delay,0),d.balance,'out',d.due_date is null from private.gama_ec_schedule() d join public.supplier_invoices p on p.id=d.document_id and p.status='posted' where d.side='supplier' and d.balance>0
 union all select 'purchase',p.id,p.order_number,coalesce(p.expected_date::date,today)+coalesce(s.supplier_delay,0),greatest(0,p.total-coalesce((select sum(i.total) from public.supplier_invoices i where i.purchase_order_id=p.id and i.status='posted'),0)),'out',p.expected_date is null from public.purchase_orders p where p.status in ('sent','partial','received')
 union all select 'payroll',null::uuid,'Nómina · '||p.period::text,(p.period+interval '1 month -1 day')::date,sum(greatest(0,p.net-coalesce((select sum(q.amount) from public.hr_payroll_payments q where q.payroll_id=p.id and q.status='confirmed'),0))),'out',false from public.hr_payroll p where p.status='validated' group by p.period
 union all select c.kind,c.id,c.label,(c.due_date+make_interval(months=>n))::date,c.amount,c.direction,false from private.cash_commitments c cross join generate_series(0,120)n where c.active and (n=0 or c.repeat_monthly) and ((not c.repeat_monthly and n=0 and c.due_date<=today+90) or (c.repeat_monthly and (c.due_date+make_interval(months=>n))::date between today and today+90)) and (c.end_date is null or (c.due_date+make_interval(months=>n))::date<=c.end_date)
 ),bounded as(select *,greatest(today,due) planned_date from source where amount>0 and due<=today+90)
 select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'label',label,'due_date',due,'planned_date',planned_date,'amount',amount,'direction',direction,'missing_date',missing_date) order by planned_date,kind,id),'[]') into events from bounded;
 with buckets as(select n,today+n*7 starts,today+least(90,n*7+6) ends from generate_series(0,12)n),totals as(select b.*,coalesce(sum((e->>'amount')::numeric) filter(where e->>'direction'='in'),0) incoming,coalesce(sum((e->>'amount')::numeric) filter(where e->>'direction'='out'),0) outgoing from buckets b left join jsonb_array_elements(events)e on (e->>'planned_date')::date between b.starts and b.ends group by b.n,b.starts,b.ends),running as(select *,balance+sum(incoming-outgoing) over(order by n) closing from totals)
 select jsonb_agg(jsonb_build_object('from',starts,'to',ends,'incoming',incoming,'outgoing',outgoing,'closing',closing,'below_minimum',closing<coalesce(s.minimum_balance,0)) order by n) into weeks from running;
 return jsonb_build_object('today',today,'currency',(select currency from public.company_settings where id),'balance',balance,'minimum_balance',coalesce(s.minimum_balance,0),'weeks',weeks,'events',events,'scenarios',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by name) from private.cash_scenarios x),'[]'),'commitments',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by due_date,label) from private.cash_commitments x where active),'[]'));
end $$;

create function private.gama_commercial_planning(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare target uuid;result jsonb;version integer;begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>64000 then raise exception 'INVALID_REQUEST';end if;
 if p_action='quote_margin' then
  if not private.erp_mfa_ok() or not private.erp_module_allowed('quotes',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 200 then raise exception 'INVALID_LINES';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'lines')x where not coalesce((x->>'quantity')::numeric>0 and (x->>'quantity')::numeric<=100000 and (x->>'unit_price')::numeric>=0 and (x->>'unit_price')::numeric<1000000000,false)) then raise exception 'INVALID_LINES';end if;
  with lines as(select (x->>'quantity')::numeric qty,(x->>'unit_price')::numeric price,p.purchase_price cost from jsonb_array_elements(p_data->'lines')x left join public.products p on p.id=(x->>'product_id')::uuid),s as(select sum(round(qty*price,2)) revenue,sum(qty*cost) cost,count(*) filter(where cost is null or cost<=0 or qty<=0 or price<0) missing from lines)
  select jsonb_build_object('net',revenue,'product_cost',case when missing=0 then cost end,'margin_percent',case when missing=0 then round(100*(revenue-cost)/nullif(revenue,0),2) end,'minimum_margin',(select minimum_margin from private.commercial_settings where id),'estimated',true,'missing_costs',missing) into result from s;return result;
 end if;
 perform private.commercial_require(case when p_action in ('profit','cash') then 'view' else 'edit' end);
 if p_action='profit' then return private.commercial_profit((p_data->>'from')::date,(p_data->>'to')::date,nullif(p_data->>'customer_id','')::uuid);
 elsif p_action='cash' then return private.cash_projection(p_data);
 elsif p_action='cost_save' then
  target:=(p_data->>'order_id')::uuid;perform 1 from public.sales_orders where id=target and status<>'cancelled' for update;if not found then raise exception 'NOT_FOUND';end if;
  select c.version into version from private.order_operating_costs c where order_id=target and kind=p_data->>'kind';if coalesce(version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  insert into private.order_operating_costs(order_id,kind,amount,basis,evidence,updated_by) values(target,p_data->>'kind',(p_data->>'amount')::numeric,p_data->>'basis',p_data->>'evidence',auth.uid()) on conflict(order_id,kind) do update set amount=excluded.amount,basis=excluded.basis,evidence=excluded.evidence,updated_by=auth.uid(),updated_at=now(),version=order_operating_costs.version+1;return jsonb_build_object('saved',true);
 elsif p_action='margin_setting' then update private.commercial_settings set minimum_margin=(p_data->>'minimum_margin')::numeric where id;return jsonb_build_object('saved',true);
 elsif p_action='scenario_save' then
  target:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());perform pg_advisory_xact_lock(hashtextextended('cash-scenario:'||target,0));select c.version into version from private.cash_scenarios c where id=target;
  if coalesce(version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  insert into private.cash_scenarios(id,name,customer_delay,supplier_delay,collection_percent,minimum_balance,created_by) values(target,p_data->>'name',(p_data->>'customer_delay')::integer,(p_data->>'supplier_delay')::integer,(p_data->>'collection_percent')::numeric,(p_data->>'minimum_balance')::numeric,auth.uid()) on conflict(id) do update set name=excluded.name,customer_delay=excluded.customer_delay,supplier_delay=excluded.supplier_delay,collection_percent=excluded.collection_percent,minimum_balance=excluded.minimum_balance,version=cash_scenarios.version+1,updated_at=now();return jsonb_build_object('id',target);
 elsif p_action='commitment_save' then
  target:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());perform pg_advisory_xact_lock(hashtextextended('cash-commitment:'||target,0));select c.version into version from private.cash_commitments c where id=target;
  if coalesce(version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  insert into private.cash_commitments(id,label,kind,direction,amount,due_date,repeat_monthly,end_date,active,created_by) values(target,p_data->>'label',p_data->>'kind',p_data->>'direction',(p_data->>'amount')::numeric,(p_data->>'due_date')::date,coalesce((p_data->>'repeat_monthly')::boolean,false),nullif(p_data->>'end_date','')::date,coalesce((p_data->>'active')::boolean,true),auth.uid()) on conflict(id) do update set label=excluded.label,kind=excluded.kind,direction=excluded.direction,amount=excluded.amount,due_date=excluded.due_date,repeat_monthly=excluded.repeat_monthly,end_date=excluded.end_date,active=excluded.active,version=cash_commitments.version+1,updated_at=now();return jsonb_build_object('id',target);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_commercial_planning(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_commercial_planning(p_action,p_data)$$;
revoke all on function private.commercial_require(text),private.capture_order_cost(),private.commercial_profit(date,date,uuid),private.cash_projection(jsonb),private.gama_commercial_planning(text,jsonb),public.gama_commercial_planning(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_commercial_planning(text,jsonb),public.gama_commercial_planning(text,jsonb) to authenticated;

create trigger planning_audit after insert or update or delete on private.commercial_settings for each row execute function private.erp_audit_capture();
create trigger planning_audit after insert or update or delete on private.order_operating_costs for each row execute function private.erp_audit_capture();
create trigger planning_audit after insert or update or delete on private.cash_scenarios for each row execute function private.erp_audit_capture();
create trigger planning_audit after insert or update or delete on private.cash_commitments for each row execute function private.erp_audit_capture();
