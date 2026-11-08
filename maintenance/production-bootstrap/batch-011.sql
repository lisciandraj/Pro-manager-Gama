do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>275
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261010220840_commercial_profitability_and_cash_scenarios.sql; SHA256 a416829c2008abd082541493d28494c16ce50ea49a9db114204dbf6015dc8415
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261010220840','commercial_profitability_and_cash_scenarios','a416829c2008abd082541493d28494c16ce50ea49a9db114204dbf6015dc8415','a416829c2008abd082541493d28494c16ce50ea49a9db114204dbf6015dc8415','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261010220842_recurring_customer_orders.sql; SHA256 ff79c30c912ea3646fb31a5ee35aa69f1357afb0bc445dc4703669bdb4d2229e
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261010220842','recurring_customer_orders','ff79c30c912ea3646fb31a5ee35aa69f1357afb0bc445dc4703669bdb4d2229e','ff79c30c912ea3646fb31a5ee35aa69f1357afb0bc445dc4703669bdb4d2229e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261010220932_scheduled_collection_sequences.sql; SHA256 a6e617097e9edf18ce9e3e8bf30f76cfc3e7e035988dcee1bc4e2fbfe542c048
-- Explicit opt-in sequences reuse the durable outbox. No provider or customer
-- preference is activated by this migration and no existing draft is queued.
alter table private.message_outbox add column collection_step integer,add column maturity_date date,add column automatic_collection boolean not null default false;
create table private.collection_holds(invoice_id uuid primary key references public.external_invoices(id),disputed boolean not null default false,promise_date date,promise_amount numeric check(promise_amount>0 and promise_amount<1000000000),suspend_until date,reason text not null check(length(btrim(reason)) between 3 and 1000),version integer not null default 1,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
alter table private.collection_holds enable row level security;revoke all on private.collection_holds from public,anon,authenticated;
alter function private.message_draft_valid(private.message_outbox) rename to message_valid_before_sequences;
create function private.message_draft_valid(m private.message_outbox) returns boolean language plpgsql stable security definer set search_path='' as $$
declare valid boolean;today date:=(now() at time zone private.erp_timezone())::date;begin
 if m.kind='invoice_reminder' and exists(select 1 from private.collection_holds h where h.invoice_id=m.source_id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) then return false;end if;
 if m.collection_step is null then return private.message_valid_before_sequences(m);end if;
 select exists(select 1 from public.customers c join private.customer_message_preferences p on p.customer_id=c.id where c.id=m.customer_id and c.active and c.email=m.recipient and p.invoice_reminders)
 and exists(select 1 from private.automation_jobs j join private.automation_rules r on r.kind=j.kind and r.version=j.rule_version join public.profiles a on a.id=m.actor join auth.users u on u.id=a.id where j.id=m.job_id and r.enabled and r.version=m.rule_version and r.version=(select max(version) from private.automation_rules where kind=r.kind) and r.executor=m.actor and r.approved_until>now() and a.active and a.role='administrador' and a.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and exists(select 1 from private.gama_receivables r where r.id=m.source_id and r.customer_id=m.customer_id and r.balance=m.source_amount and r.balance>0)
 and exists(select 1 from private.gama_customer_dues(m.customer_id,array[m.source_id]) d where d.balance>0 group by d.document_id having min(d.due_date)=m.maturity_date and today>=min(d.due_date)+m.collection_step and (m.collection_step>=0 or today<=min(d.due_date)))
 and not exists(select 1 from private.collection_holds h where h.invoice_id=m.source_id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) into valid;
 return coalesce(valid,false);
end $$;
alter function private.automation_reminders(private.automation_jobs,jsonb) rename to automation_reminders_before_sequences;
create function private.automation_reminders(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row record;n integer:=0;changed integer;step integer;today date:=(now() at time zone private.erp_timezone())::date;steps jsonb:=coalesce(p_config->'steps','[-3,7,14,30]'::jsonb);lang text:=coalesce(p_config->>'language','es');mode text:=coalesce(p_config->>'delivery_mode','manual');subject text;body text;company text;currency text;begin
 if not (p_config ? 'steps') then return private.automation_reminders_before_sequences(p_job,p_config);end if;
 if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(steps)<>'array' or jsonb_array_length(steps) not between 1 and 8 or exists(select 1 from jsonb_array_elements_text(steps)x where x!~'^-?[0-9]{1,3}$' or x::integer not between -30 and 180) then raise exception 'INVALID_SEQUENCE';end if;
 if mode not in ('manual','automatic') or lang not in ('es','fr','en') then raise exception 'INVALID_SEQUENCE';end if;
 if mode='automatic' and not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 select coalesce(nullif(legal_name,''),'Coco ERP'),c.currency into company,currency from public.company_settings c where id;
 update private.message_outbox m set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where collection_step is not null and state in ('draft','queued') and not private.message_draft_valid(m);
 for row in select r.*,c.email outbound_email,d.maturity from private.gama_receivables r join public.customers c on c.id=r.customer_id and c.active join private.customer_message_preferences p on p.customer_id=c.id and p.invoice_reminders join lateral(select min(d.due_date) maturity from private.gama_customer_dues(c.id,array[r.id])d where d.balance>0)d on d.maturity is not null
 where r.balance>0 and c.email~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' and not exists(select 1 from private.collection_holds h where h.invoice_id=r.id and (h.disputed or h.suspend_until>=today or h.promise_date>=today)) order by d.maturity,r.id limit 200 loop
  select max(value::integer) into step from jsonb_array_elements_text(steps) where today>=row.maturity+value::integer and (value::integer>=0 or today<=row.maturity);
  if step is null then continue;end if;
  subject:=company||' · '||case lang when 'fr' then 'Rappel de facture ' when 'en' then 'Invoice reminder ' else 'Recordatorio de factura ' end||row.number;
  body:=case lang when 'fr' then 'Bonjour '||row.customer_name||E',\nFacture : '||row.number||E'\nÉchéance : '||row.maturity||E'\nSolde restant : '||currency||' '||row.balance||E'\nSi vous avez déjà réglé cette facture, merci de nous transmettre la preuve de paiement.' when 'en' then 'Hello '||row.customer_name||E',\nInvoice: '||row.number||E'\nDue date: '||row.maturity||E'\nOutstanding: '||currency||' '||row.balance||E'\nIf you have already paid, please send us the payment confirmation.' else 'Hola '||row.customer_name||E',\nFactura: '||row.number||E'\nVencimiento: '||row.maturity||E'\nSaldo pendiente: '||currency||' '||row.balance||E'\nSi ya has pagado, envíanos el comprobante para actualizar el registro.' end;
  insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,source_amount,subject,body,state,collection_step,maturity_date,automatic_collection)
  values('sequence:'||row.id||':'||row.maturity||':'||step,'invoice_reminder',row.customer_id,row.id,p_job.id,auth.uid(),p_job.rule_version,row.outbound_email,row.balance,subject,body,case mode when 'automatic' then 'queued' else 'draft' end,step,row.maturity,mode='automatic')
  on conflict(key) do update set job_id=excluded.job_id,actor=excluded.actor,rule_version=excluded.rule_version,recipient=excluded.recipient,source_amount=excluded.source_amount,subject=excluded.subject,body=excluded.body,state=excluded.state,automatic_collection=excluded.automatic_collection,error_code=null,updated_at=now() where message_outbox.state='cancelled' and message_outbox.attempts=0 and message_outbox.manual_sent_at is null;
  get diagnostics changed=row_count;n:=n+changed;
 end loop;return jsonb_build_object('prepared',n,'mode',mode);end $$;

create function private.gama_collections_schedule(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare h private.collection_holds;target uuid;r private.automation_rules;conf private.message_provider;secret uuid;steps jsonb;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('payments',array['administrador','comercial']) or (p_action<>'context' and not private.erp_action_allowed('payments','create')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  select * into r from private.automation_rules where kind='reminders' order by version desc limit 1;
  return jsonb_build_object('rule',to_jsonb(r)-'executor'-'approved_by','provider',coalesce((select jsonb_build_object('enabled',enabled,'sender',sender) from private.message_provider where id),'{"enabled":false}'::jsonb),'holds',coalesce((select jsonb_agg(to_jsonb(x)) from(select hold.*,recv.number,recv.customer_name from private.collection_holds hold join private.gama_receivables recv on recv.id=hold.invoice_id order by hold.updated_at desc limit 200)x),'[]'),'invoices',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,number,customer_name,balance,due_date from private.gama_receivables where balance>0 order by due_date nulls last,id limit 300)x),'[]'));
 elsif p_action='hold_save' then
  target:=(p_data->>'invoice_id')::uuid;perform 1 from public.external_invoices where id=target for update;if not found then raise exception 'NOT_FOUND';end if;
  select * into h from private.collection_holds where invoice_id=target;if coalesce(h.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  insert into private.collection_holds(invoice_id,disputed,promise_date,promise_amount,suspend_until,reason,updated_by) values(target,coalesce((p_data->>'disputed')::boolean,false),nullif(p_data->>'promise_date','')::date,nullif(p_data->>'promise_amount','')::numeric,nullif(p_data->>'suspend_until','')::date,p_data->>'reason',auth.uid()) on conflict(invoice_id) do update set disputed=excluded.disputed,promise_date=excluded.promise_date,promise_amount=excluded.promise_amount,suspend_until=excluded.suspend_until,reason=excluded.reason,version=collection_holds.version+1,updated_by=auth.uid(),updated_at=now();
  update private.message_outbox m set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where source_id=target and state in ('draft','queued') and not private.message_draft_valid(m);return jsonb_build_object('saved',true);
 end if;
 if not private.erp_module_allowed('access-settings',array['administrador']) or not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='rule_save' then
  steps:=p_data->'steps';if jsonb_typeof(steps) is distinct from 'array' or jsonb_array_length(steps) not between 1 and 8 or exists(select 1 from jsonb_array_elements_text(steps)x where x!~'^-?[0-9]{1,3}$' or x::integer not between -30 and 180) or p_data->>'delivery_mode' not in ('manual','automatic') or p_data->>'language' not in ('fr','es','en') then raise exception 'INVALID_SEQUENCE';end if;
  return private.gama_automation('rule_save',jsonb_build_object('kind','reminders','expected_version',p_data->'version','enabled',p_data->'enabled','delegation_days',90,'config',jsonb_build_object('interval_minutes',60,'steps',steps,'language',p_data->>'language','delivery_mode',p_data->>'delivery_mode')));
 elsif p_action='provider_save' then
  if not coalesce((p_data->>'enabled')::boolean,false) then update private.message_provider set enabled=false,updated_at=now(),updated_by=auth.uid() where id;if exists(select 1 from cron.job where jobname='coco-message-dispatch') then perform cron.unschedule('coco-message-dispatch');end if;return jsonb_build_object('enabled',false);end if;
  if not coalesce((p_data->>'domain_verified')::boolean,false) or coalesce(p_data->>'sender','')!~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
  select * into conf from private.message_provider where id for update;
  if nullif(p_data->>'api_key','') is not null then
   if length(p_data->>'api_key') not between 10 and 300 then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
   if conf.secret_id is null then secret:=vault.create_secret(p_data->>'api_key','coco_email_provider');else secret:=conf.secret_id;perform vault.update_secret(secret,p_data->>'api_key');end if;
  else secret:=conf.secret_id;end if;if secret is null then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
  insert into private.message_provider(id,sender,secret_id,enabled,updated_by) values(true,p_data->>'sender',secret,true,auth.uid()) on conflict(id) do update set sender=excluded.sender,secret_id=excluded.secret_id,enabled=true,updated_by=auth.uid(),updated_at=now();perform cron.schedule('coco-message-dispatch','* * * * *','select private.message_dispatch()');return jsonb_build_object('enabled',true);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_collections_schedule(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_collections_schedule(p_action,p_data)$$;
revoke all on function private.message_draft_valid(private.message_outbox),private.gama_collections_schedule(text,jsonb),public.gama_collections_schedule(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_collections_schedule(text,jsonb),public.gama_collections_schedule(text,jsonb) to authenticated;

create or replace function private.message_dispatch() returns jsonb language plpgsql security definer set search_path='' as $$
declare message private.message_outbox;provider private.message_provider;rule private.automation_rules;job private.automation_jobs;response record;key text;response_payload jsonb;valid boolean;status text;n integer:=0;request bigint;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-message-dispatch',0)) then return jsonb_build_object('busy',true);end if;
 select * into provider from private.message_provider where id and enabled;if not found then return jsonb_build_object('configured',false,'mode','manual','dispatched',0);end if;
 select decrypted_secret into key from vault.decrypted_secrets where id=provider.secret_id;if nullif(key,'') is null then return jsonb_build_object('configured',false,'mode','manual','dispatched',0);end if;
 for message in select * from private.message_outbox where automatic_collection and collection_step is not null and state in ('queued','dispatching','accepted') and coalesce(next_poll_at,created_at)<=now() order by created_at,id limit 25 for update skip locked loop
  if message.state='dispatching' then
   select * into response from net._http_response where id=message.request_id;
   if not found and message.lease_until>now() then continue;end if;
   if found and response.status_code=200 then
    response_payload:=response.content::jsonb;if coalesce(response_payload->>'id','')~'^[0-9a-f-]{36}$' then update private.message_outbox set state='accepted',provider_id=response_payload->>'id',request_id=null,next_poll_at=now()+interval '10 minutes',lease_until=null,updated_at=now() where id=message.id;continue;end if;
   end if;
   if message.attempts>=5 or message.first_sent_at<now()-interval '23 hours' then update private.message_outbox set state='uncertain',error_code='PROVIDER_CONFIRMATION_REQUIRED',lease_until=null,updated_at=now() where id=message.id;continue;end if;
   update private.message_outbox set state='queued',request_id=null,lease_until=null,next_poll_at=now()+interval '5 minutes',error_code='PROVIDER_RETRY',updated_at=now() where id=message.id;continue;
  elsif message.state='accepted' then
   if message.request_id is not null then
    select * into response from net._http_response where id=message.request_id;
    if found and response.status_code=200 then
     response_payload:=response.content::jsonb;status:=response_payload->>'last_event';
     if status in ('delivered','bounced','complained','failed') then update private.message_outbox set state=status,request_id=null,lease_until=null,updated_at=now() where id=message.id;continue;end if;
    elsif not found and message.lease_until>now() then continue;end if;
   end if;
   if message.first_sent_at<now()-interval '7 days' then update private.message_outbox set state='uncertain',error_code='DELIVERY_STATUS_UNCONFIRMED',request_id=null,updated_at=now() where id=message.id;continue;end if;
   request:=net.http_get(url:='https://api.resend.com/emails/'||message.provider_id,headers:=jsonb_build_object('Authorization','Bearer '||key),timeout_milliseconds:=10000);
   update private.message_outbox set request_id=request,lease_until=now()+interval '2 minutes',next_poll_at=now()+interval '10 minutes',updated_at=now() where id=message.id;continue;
  end if;
  -- Check the current rule, actor, rights, customer preference, source balance
  -- and recipient immediately before dispatch; a changed email requires review.
  select * into job from private.automation_jobs where id=message.job_id for update;select * into rule from private.automation_rules where kind=job.kind order by version desc limit 1;
  valid:=private.message_draft_valid(message);
  if not valid then update private.message_outbox set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where id=message.id;continue;end if;
  begin
   update private.automation_jobs set state='running' where id=job.id;
   perform set_config('request.jwt.claim.sub',message.actor::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',message.actor,'role','authenticated')::text,true);
   insert into private.automation_execution_context(backend,transaction,job_id,actor) values(pg_backend_pid(),txid_current(),job.id,message.actor);
   if not private.erp_mfa_ok() or not private.automation_visible(case message.kind when 'survey' then 'surveys' else 'payments' end) or not private.erp_action_allowed(case message.kind when 'survey' then 'surveys' else 'payments' end,case message.kind when 'survey' then 'edit' else 'create' end) then raise exception 'DELEGATION_ACCESS_REVOKED';end if;
   response_payload:=jsonb_build_object('from',provider.sender,'to',jsonb_build_array(message.recipient),'subject',message.subject,'text',message.body);
   request:=net.http_post(url:='https://api.resend.com/emails',body:=response_payload,headers:=jsonb_build_object('Authorization','Bearer '||key,'Content-Type','application/json','Idempotency-Key','coco-'||message.id),timeout_milliseconds:=10000);
   update private.message_outbox set state='dispatching',request_id=request,attempts=attempts+1,first_sent_at=coalesce(first_sent_at,now()),lease_until=now()+interval '2 minutes',next_poll_at=now()+interval '1 minute',updated_at=now() where id=message.id;
   delete from private.automation_execution_context where backend=pg_backend_pid() and transaction=txid_current();update private.automation_jobs set state=job.state where id=job.id;n:=n+1;
  exception when others then update private.message_outbox set state='failed',error_code='DISPATCH_ACCESS_OR_REQUEST_FAILED',updated_at=now() where id=message.id;
  end;
  perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
 end loop;return jsonb_build_object('dispatched',n);end $$;
revoke all on function private.message_dispatch() from public,anon,authenticated,service_role;



create trigger planning_audit after insert or update or delete on private.collection_holds for each row execute function private.erp_audit_capture();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261010220932','scheduled_collection_sequences','a6e617097e9edf18ce9e3e8bf30f76cfc3e7e035988dcee1bc4e2fbfe542c048','a6e617097e9edf18ce9e3e8bf30f76cfc3e7e035988dcee1bc4e2fbfe542c048','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261010221437_supplier_document_ocr_review.sql; SHA256 17a6b2387c9ba01eaff89acd708d8863e3d24ea02c1ceccec5346e71ce83b817
create table private.supplier_ocr_intakes(id uuid primary key default gen_random_uuid(),hash text not null unique,filename text not null,mime_type text not null,content bytea not null check(octet_length(content) between 10 and 5242880),state text not null default 'processing' check(state in ('processing','review','draft','failed')),extracted jsonb,reviewed jsonb,bill_id uuid references public.supplier_invoices(id),lease uuid,lease_until timestamptz,error_code text,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index supplier_ocr_creator on private.supplier_ocr_intakes(created_by,created_at);
alter table private.supplier_ocr_intakes enable row level security;revoke all on private.supplier_ocr_intakes from public,anon,authenticated;
create table private.supplier_ocr_attempts(actor uuid not null references public.profiles(id),created_at timestamptz not null default now());
create index supplier_ocr_attempts_actor on private.supplier_ocr_attempts(actor,created_at);
alter table private.supplier_ocr_attempts enable row level security;revoke all on private.supplier_ocr_attempts from public,anon,authenticated;
create function private.gama_supplier_ocr(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare r private.supplier_ocr_intakes;raw bytea;hash text;result jsonb;vendor uuid;purchase uuid;bill public.supplier_invoices;net numeric;tax numeric;total numeric;number text;issued date;currency text;begin
 perform private.commercial_require(case when p_action in ('list','context','file') then 'view' else 'create' end);
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>7200000 then raise exception 'INVALID_REQUEST';end if;
 if p_action='list' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select id,filename,state,bill_id,error_code,created_at from private.supplier_ocr_intakes order by created_at desc limit 100)x),'[]');end if;
 if p_action='begin' then
  if coalesce(p_data->>'mime_type','') not in ('application/pdf','image/jpeg','image/png','image/webp') or coalesce(p_data->>'content_base64','')!~'^[A-Za-z0-9+/]+={0,2}$' then raise exception 'OCR_FILE_INVALID';end if;
  raw:=decode(p_data->>'content_base64','base64');if octet_length(raw) not between 10 and 5242880 then raise exception 'OCR_FILE_INVALID';end if;
  if (p_data->>'mime_type'='application/pdf' and substring(raw from 1 for 5)<>decode('255044462d','hex')) or (p_data->>'mime_type'='image/png' and substring(raw from 1 for 8)<>decode('89504e470d0a1a0a','hex')) or (p_data->>'mime_type'='image/jpeg' and substring(raw from 1 for 3)<>decode('ffd8ff','hex')) or (p_data->>'mime_type'='image/webp' and (substring(raw from 1 for 4)<>decode('52494646','hex') or substring(raw from 9 for 4)<>decode('57454250','hex'))) then raise exception 'OCR_FILE_INVALID';end if;
  hash:=encode(sha256(raw),'hex');perform pg_advisory_xact_lock(hashtextextended('supplier-ocr:'||hash,0));select * into r from private.supplier_ocr_intakes where supplier_ocr_intakes.hash=hash for update;
  if r.id is not null then
   if r.state in ('review','draft') then return jsonb_build_object('id',r.id,'state',r.state,'existing',true);end if;
   if r.lease_until>now() then raise exception 'OCR_PROCESSING';end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('supplier-ocr-actor:'||auth.uid(),0));
  if (select count(*) from private.supplier_ocr_attempts where actor=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'RATE_LIMIT';end if;
  insert into private.supplier_ocr_attempts(actor) values(auth.uid());
  delete from private.supplier_ocr_attempts where created_at<now()-interval '7 days';
  if r.id is null then insert into private.supplier_ocr_intakes(hash,filename,mime_type,content,created_by,lease,lease_until) values(hash,left(coalesce(nullif(p_data->>'filename',''),'invoice'),180),p_data->>'mime_type',raw,auth.uid(),gen_random_uuid(),now()+interval '3 minutes') returning * into r;
  else update private.supplier_ocr_intakes set state='processing',error_code=null,lease=gen_random_uuid(),lease_until=now()+interval '3 minutes',updated_at=now() where id=r.id returning * into r;end if;
  return jsonb_build_object('id',r.id,'state',r.state,'lease',r.lease);
 end if;
 select * into r from private.supplier_ocr_intakes where id=(p_data->>'id')::uuid for update;if not found then raise exception 'NOT_FOUND';end if;
 if p_action='complete' or p_action='fail' then
  if r.state<>'processing' or r.lease is distinct from (p_data->>'lease')::uuid or r.lease_until<now() then raise exception 'OCR_LEASE_EXPIRED';end if;
  if p_action='complete' then
   result:=p_data->'extracted';if jsonb_typeof(result) is distinct from 'object' or octet_length(result::text)>64000 or jsonb_typeof(result->'lines') is distinct from 'array' or jsonb_array_length(result->'lines')>200 then raise exception 'OCR_RESPONSE_INVALID';end if;
   update private.supplier_ocr_intakes set extracted=result,state='review',lease=null,lease_until=null,error_code=null,updated_at=now() where id=r.id;
  else update private.supplier_ocr_intakes set state='failed',error_code=left(regexp_replace(coalesce(p_data->>'error','OCR_FAILED'),'[^A-Z0-9_]','','g'),80),lease=null,lease_until=null,updated_at=now() where id=r.id;end if;
  return jsonb_build_object('id',r.id,'state',case p_action when 'complete' then 'review' else 'failed' end);
 elsif p_action='file' then return jsonb_build_object('filename',r.filename,'mime_type',r.mime_type,'content_base64',encode(r.content,'base64'));
 elsif p_action='context' then
  return (to_jsonb(r)-'content'-'lease'-'lease_until'-'created_by')||jsonb_build_object('suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'tax_id',tax_id)) from public.suppliers where active),'[]'),'purchases',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.supplier_id,p.order_number,p.total,p.status,coalesce((select sum(round(l.received_quantity*l.unit_cost,2)+round(round(l.received_quantity*l.unit_cost,2)*l.tax_rate/100,2)) from public.purchase_order_lines l where l.purchase_order_id=p.id),0) received_total from public.purchase_orders p where p.status in ('sent','partial','received') order by p.order_date desc limit 300)x),'[]'),'buyer_tax_id',(select tax_id from public.company_settings where id),'currency',(select c.currency from public.company_settings c where id));
 elsif p_action='draft' then
  if r.state='draft' then if r.reviewed is distinct from (p_data-'id') then raise exception 'REQUEST_KEY_REUSED';end if;return jsonb_build_object('id',r.bill_id,'existing',true);end if;
  if r.state<>'review' or not coalesce((p_data->>'reviewed')::boolean,false) then raise exception 'SOURCE_REVIEW_REQUIRED';end if;
  vendor:=(p_data->>'supplier_id')::uuid;purchase:=nullif(p_data->>'purchase_order_id','')::uuid;number:=btrim(p_data->>'number');issued:=(p_data->>'issue_date')::date;net:=(p_data->>'subtotal')::numeric;tax:=(p_data->>'tax')::numeric;total:=(p_data->>'total')::numeric;
  select c.currency into currency from public.company_settings c where id;
  if p_data->>'currency' is distinct from currency or net is null or tax is null or total is null or net<0 or tax<0 or total<=0 or total>=1000000000 or net<>round(net,2) or tax<>round(tax,2) or total<>net+tax then raise exception 'OCR_TOTAL_OR_CURRENCY_INVALID';end if;
  if number is null or length(number) not between 1 and 100 or issued is null then raise exception 'NUMBER_REQUIRED';end if;
  if not exists(select 1 from public.suppliers where id=vendor and active) then raise exception 'SUPPLIER_MATCH_REQUIRED';end if;
  if purchase is not null and not exists(select 1 from public.purchase_orders where id=purchase and supplier_id=vendor and status<>'cancelled') then raise exception 'SUPPLIER_MISMATCH';end if;
  perform pg_advisory_xact_lock(hashtextextended('supplier-invoice:'||vendor||':'||number,0));
  if exists(select 1 from public.supplier_invoices b where b.supplier_id=vendor and b.number=number and b.status<>'cancelled') then raise exception 'SUPPLIER_INVOICE_DUPLICATE';end if;
  insert into public.supplier_invoices(supplier_id,purchase_order_id,number,issue_date,payment_terms_days,due_date,subtotal,tax,total,status,source_reviewed,request_key,created_by,notes) values(vendor,purchase,number,issued,coalesce((p_data->>'payment_terms_days')::integer,0),issued+coalesce((p_data->>'payment_terms_days')::integer,0),net,tax,total,'draft',false,r.id,auth.uid(),'OCR · '||r.filename||E'\n'||coalesce(p_data->>'notes','')) returning * into bill;
  update private.supplier_ocr_intakes set bill_id=bill.id,reviewed=p_data-'id',state='draft',updated_at=now() where id=r.id;
  perform private.automation_exception('supplier-draft:'||bill.id,'receipt_bill','accounting','supplier_invoice',bill.id,'OCR_RECEIPT_REVIEW_REQUIRED',null,bill.erp_reference);
  return jsonb_build_object('id',bill.id,'status','draft');
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_supplier_ocr(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_supplier_ocr(p_action,p_data)$$;
revoke all on function private.gama_supplier_ocr(text,jsonb),public.gama_supplier_ocr(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_supplier_ocr(text,jsonb),public.gama_supplier_ocr(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261010221437','supplier_document_ocr_review','17a6b2387c9ba01eaff89acd708d8863e3d24ea02c1ceccec5346e71ce83b817','17a6b2387c9ba01eaff89acd708d8863e3d24ea02c1ceccec5346e71ce83b817','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261010222011_collection_sequence_stage_revalidation.sql; SHA256 5a81f74d841a8090da23eb203e045de5e31dfe7b8e73af569adedf9be7eaa6e4
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261010222011','collection_sequence_stage_revalidation','5a81f74d841a8090da23eb203e045de5e31dfe7b8e73af569adedf9be7eaa6e4','5a81f74d841a8090da23eb203e045de5e31dfe7b8e73af569adedf9be7eaa6e4','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261011155754_performance_paged_stock_and_dashboard.sql; SHA256 ce5b8a5831cac656c7191c98aa0adb72a197ec05afccaa64ab680808d5a3f734
-- The stock list is paged in SQL. Its KPIs cover the entire filtered, authorized
-- catalogue, never the visible page. Reads remain invoker and respect every RLS
-- boundary; no stock, reservation, snapshot or financial row is rewritten.
create function public.gama_inventory_page(
 p_warehouse uuid default null,p_until date default null,p_search text default '',
 p_category text default '',p_state text default '',p_query text default '',p_sort text default 'name',
 p_direction text default 'asc',p_page integer default 0,p_page_size integer default 20
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;can_incoming boolean;size integer:=least(50,greatest(1,coalesce(p_page_size,20)));
begin
 if auth.uid() is null or not private.erp_mfa_ok() or
  not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if coalesce(p_sort,'name') not in ('name','warehouse','physical','reserved','available','status')
  or coalesce(p_direction,'asc') not in ('asc','desc')
  or coalesce(p_state,'') not in ('','agotado','bajo','sobre','reservado','ok')
  or length(coalesce(p_search,''))>200 or length(coalesce(p_query,''))>200 or length(coalesce(p_category,''))>200 then raise exception 'INVALID_FILTER';end if;
 can_incoming:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
 with stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved,count(*) locations,
   string_agg(distinct w.name,', ' order by w.name) warehouse
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id
   join public.warehouses w on w.id=l.warehouse_id
  where p_warehouse is null or l.warehouse_id=p_warehouse group by q.product_id
 ), incoming as (
  select l.product_id,sum(greatest(0,l.quantity-l.received_quantity)) incoming
  from public.purchase_orders o join public.purchase_order_lines l on l.purchase_order_id=o.id
   left join public.warehouse_locations loc on loc.id=o.destination_location_id
  where can_incoming and o.status in ('sent','partial')
   and (p_warehouse is null or loc.warehouse_id=p_warehouse)
   and (p_until is null or o.expected_date::date<=p_until) group by l.product_id
 ), base as materialized (
  select p.id,p.name,p.reference,p.barcode,p.category,p.min_stock,p.max_stock,p.purchase_price,p.has_photo,p.active,
   coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,coalesce(s.locations,0) locations,
   coalesce(s.warehouse,'—') warehouse,
   case when can_incoming then coalesce(i.incoming,0) end incoming,
   case when can_incoming then coalesce(s.physical,0)-coalesce(s.reserved,0)+coalesce(i.incoming,0) end projected,
   coalesce(s.physical,0)*coalesce(p.purchase_price,0) current_cost_value,
   case when coalesce(s.physical,0)<=0 then 'agotado'
    when coalesce(p.min_stock,0)>0 and coalesce(s.physical,0)-coalesce(s.reserved,0)<=p.min_stock then 'bajo'
    when coalesce(p.max_stock,0)>0 and coalesce(s.physical,0)>p.max_stock then 'sobre'
    when coalesce(s.reserved,0)>0 then 'reservado' else 'ok' end status
  from public.products p left join stock s on s.product_id=p.id left join incoming i on i.product_id=p.id
  where p.active and p.product_kind='goods'
 ), matched as materialized (
  select * from base b where (p_warehouse is null or b.locations>0 or b.incoming>0)
   and (coalesce(p_search,'')='' or position(lower(trim(p_search)) in lower(concat_ws(' ',b.name,b.reference,b.barcode)))>0)
   and (coalesce(p_category,'')='' or b.category=p_category)
   and (coalesce(p_state,'')='' or b.status=p_state)
   and not exists(select 1 from regexp_split_to_table(translate(lower(trim(coalesce(p_query,''))),'áàäâéèëêíìïîóòöôúùüûñ','aaaaeeeeiiiioooouuuun'),E'\\s+') term
    where term<>'' and position(term in translate(lower(concat_ws(' ',b.name,b.warehouse,b.physical,b.reserved,b.available,
     case b.status when 'agotado' then 'Sin stock' when 'bajo' then 'Stock bajo' when 'sobre' then 'Sobre stock' when 'reservado' then 'Con reservas' else 'Disponible' end)),
     'áàäâéèëêíìïîóòöôúùüûñ','aaaaeeeeiiiioooouuuun'))=0)
 ), meta as (
  select count(*) total,count(*) filter(where status='bajo') low,count(*) filter(where physical<=0) out,
   coalesce(sum(current_cost_value),0) current_cost_value,
   least(greatest(0,coalesce(p_page,0)),greatest(0,(count(*)::integer-1)/size)) page from matched
 ), page_rows as materialized (
  select b.* from matched b order by
   case when p_direction='asc' and p_sort='name' then b.name end asc nulls last,
   case when p_direction='desc' and p_sort='name' then b.name end desc nulls last,
   case when p_direction='asc' and p_sort='warehouse' then b.warehouse end asc nulls last,
   case when p_direction='desc' and p_sort='warehouse' then b.warehouse end desc nulls last,
   case when p_direction='asc' and p_sort='status' then case b.status when 'agotado' then 'Sin stock' when 'bajo' then 'Stock bajo' when 'sobre' then 'Sobre stock' when 'reservado' then 'Con reservas' else 'Disponible' end end asc nulls last,
   case when p_direction='desc' and p_sort='status' then case b.status when 'agotado' then 'Sin stock' when 'bajo' then 'Stock bajo' when 'sobre' then 'Sobre stock' when 'reservado' then 'Con reservas' else 'Disponible' end end desc nulls last,
   case when p_direction='asc' then case p_sort when 'physical' then b.physical when 'reserved' then b.reserved when 'available' then b.available end end asc nulls last,
   case when p_direction='desc' then case p_sort when 'physical' then b.physical when 'reserved' then b.reserved when 'available' then b.available end end desc nulls last,
   b.id asc offset (select page*size from meta) limit size
 )
 select jsonb_build_object('generated_at',now(),'warehouse_id',p_warehouse,'until',p_until,'incoming_visible',can_incoming,
  'page',m.page,'page_size',size,'total',m.total,
  'totals',jsonb_build_object('products',m.total,'low',m.low,'out',m.out,'current_cost_value',m.current_cost_value),
  'categories',(select coalesce(jsonb_agg(category order by category),'[]') from (select distinct category from base where coalesce(category,'')<>'') c),
  'rows',(select coalesce(jsonb_agg(to_jsonb(b)-'locations'||jsonb_build_object('lines',
   (select coalesce(jsonb_agg(jsonb_build_object('product_id',q.product_id,'location_id',q.location_id,'quantity',q.quantity,'reserved_quantity',q.reserved_quantity) order by l.code,q.id),'[]')
    from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id
    where q.product_id=b.id and (p_warehouse is null or l.warehouse_id=p_warehouse)))),'[]') from page_rows b)) into result from meta m;
 return result;
end $$;
revoke all on function public.gama_inventory_page(uuid,date,text,text,text,text,text,text,integer,integer) from public,anon,service_role;
grant execute on function public.gama_inventory_page(uuid,date,text,text,text,text,text,text,integer,integer) to authenticated;

-- Keep the old complete Dashboard API and its access/date/currency rules.
-- Context follows the accounting API's existing MFA, role and scope checks,
-- and omits the expensive overview aggregates when opening SRI.
do $$declare src text;anchor text:='if p_action=''overview'' then';begin
 src:=pg_get_functiondef('private.gama_accounting_action_before_ec(text,jsonb)'::regprocedure);
 if position('if p_action=''context'' then' in src)>0 then return;end if;
 if position(anchor in src)=0 then raise exception 'ACCOUNTING_CONTEXT_ANCHOR_MISSING';end if;
 execute replace(src,anchor,'if p_action=''context'' then return jsonb_build_object(''currency'',cfg.currency,''country'',cfg.country,''scope'',scope,''rights'',rights,''today'',today);end if; '||anchor);
end $$;

-- One implementation accepts an explicit subset for the first visible panels;
-- remaining sections are requested only when their details are expanded.
do $$declare src text;anchor text:='if not private.dashboard_access(module_id) then continue;end if;';begin
 if to_regprocedure('public.gama_company_dashboard_sections(date,date,text[])') is not null then return;end if;
 src:=pg_get_functiondef('public.gama_company_dashboard(date,date)'::regprocedure);
 if position(anchor in src)=0 then raise exception 'DASHBOARD_SECTION_ANCHOR_MISSING';end if;
 src:=replace(src,'public.gama_company_dashboard(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)',
  'public.gama_company_dashboard_sections(p_from date, p_to date, p_modules text[])');
 if position('gama_company_dashboard_sections(' in src)=0 then raise exception 'DASHBOARD_SIGNATURE_ANCHOR_MISSING';end if;
 execute replace(src,anchor,'if p_modules is not null and not module_id=any(p_modules) then continue;end if; '||anchor);
end $$;
revoke all on function public.gama_company_dashboard_sections(date,date,text[]) from public,anon,service_role;
grant execute on function public.gama_company_dashboard_sections(date,date,text[]) to authenticated;
create or replace function public.gama_company_dashboard(p_from date default null,p_to date default null)
returns jsonb language sql stable security invoker set search_path='' as $$select public.gama_company_dashboard_sections(p_from,p_to,null)$$;

-- Aggregate reorder rules once and reuse one stock analysis for management.
CREATE OR REPLACE FUNCTION private.stock_insight_rows(p_purchases boolean)
 RETURNS TABLE(product_id uuid, data jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with demand as (
  select m.product_id,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '30 days'),0) d30,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '60 days'),0) d60,
   coalesce(sum(m.quantity) filter(where m.created_at>=now()-interval '90 days'),0) d90,
   max(m.created_at) last_out
  from public.stock_movements m where m.type='out' and m.quantity>0
   and (m.movement_type is null or m.movement_type in ('delivery','manual_out','production_out')) group by m.product_id
 ), stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved from public.stock_quants q group by q.product_id
 ), purchases as (
  select l.product_id,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status in ('sent','partial')),0) incoming,
   coalesce(sum(l.quantity) filter(where o.status='draft'),0) drafts
  from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
  where p_purchases and o.status in ('draft','sent','partial') group by l.product_id
 ), discrepancies as (
  select l.product_id,count(distinct l.count_id) repeats from public.inventory_count_lines l
   join public.inventory_counts c on c.id=l.count_id
  where c.status='validated' and l.validated and l.variance<>0 and c.completed_at>=now()-interval '180 days' group by l.product_id
 ), rules as (
  select z.product_id,sum(z.min_quantity) minimum,sum(z.max_quantity) maximum,max(z.lead_time_days) lead,
   (array_agg(z.supplier_id order by z.created_at desc) filter(where z.supplier_id is not null))[1] supplier
  from public.reorder_rules z where z.active and (z.warehouse_id is null or not exists
   (select 1 from public.reorder_rules g where g.product_id=z.product_id and g.active and g.warehouse_id is null))
  group by z.product_id
 ), base as (
  select p.id,p.name,p.reference,p.category,p.purchase_price,p.replenishment_excluded,p.order_minimum,p.order_multiple,
   coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,
   coalesce(b.incoming,0) incoming,coalesce(b.drafts,0) drafts,
   coalesce(d.d30,0) d30,coalesce(d.d60,0) d60,coalesce(d.d90,0) d90,d.last_out,
   coalesce(d.d30,0)/30*.5+coalesce(d.d60,0)/60*.3+coalesce(d.d90,0)/90*.2 daily,
   greatest(0,current_date-coalesce(d.last_out::date,p.created_at::date)) days_without_out,
   coalesce(r.minimum,p.min_stock,0) minimum,coalesce(r.maximum,p.max_stock,0) maximum,
   coalesce(r.supplier,p.supplier_id) supplier,
   greatest(1,coalesce(r.lead,7)) lead,r.lead is not null lead_configured,
   coalesce(x.repeats,0) repeats,coalesce(s.physical,0)*coalesce(p.purchase_price,0) stock_value
  from public.products p left join stock s on s.product_id=p.id left join demand d on d.product_id=p.id
   left join purchases b on b.product_id=p.id left join discrepancies x on x.product_id=p.id
   left join rules r on r.product_id=p.id
  where p.active and p.product_kind='goods'
 ), targets as (
  select b.*,case when daily>0 then greatest(minimum,ceil(daily*lead*1.5)) else minimum end target_min,
   case when daily>0 then greatest(maximum,minimum,ceil(daily*(lead+14)+daily*lead*.5)) else greatest(maximum,minimum) end target_max,
   available+incoming+drafts net,
   sum(greatest(stock_value,0)) over() total_value,
   coalesce(sum(greatest(stock_value,0)) over(order by stock_value desc,id rows between unbounded preceding and 1 preceding),0) prior_value
  from base b
 ), proposal as (
  select t.*,case when not replenishment_excluded and net<target_min then greatest(target_max-net,coalesce(order_minimum,0)) else 0 end need
  from targets t
 )
 select p.id,jsonb_build_object(
  'id',p.id,'name',p.name,'reference',p.reference,'category',p.category,
  'on_hand',p.physical,'reserved',p.reserved,'available',p.available,
  'incoming',case when p_purchases then p.incoming end,'draft_quantity',case when p_purchases then p.drafts end,
  'projected',case when p_purchases then p.net end,
  'min_quantity',p.minimum,'max_quantity',p.maximum,'target_min',p.target_min,'target_max',p.target_max,
  'lead_time_days',p.lead,'lead_configured',p.lead_configured,
  'demand30',p.d30,'demand60',p.d60,'demand90',p.d90,'avg_daily',round(p.daily,3),
  'last_out',p.last_out,'days_without_out',p.days_without_out,
  'unit_cost',p.purchase_price,'value',p.stock_value,'excluded',p.replenishment_excluded,
  'supplier_id',case when p_purchases and s.active then s.id end,
  'supplier_name',case when p_purchases and s.active then s.name end,
  'suggested_quantity',case when p_purchases then case when p.need>0 and coalesce(p.order_multiple,0)>0 then round(ceil(p.need/p.order_multiple)*p.order_multiple,3) else round(p.need,3) end end,
  'basis',case when p.daily>0 then 'recent_demand' else 'thresholds' end,
  'repeated_discrepancies',p.repeats,
  'importance',case when p.total_value>0 and p.prior_value/p.total_value<.8 then 'A' when p.total_value>0 and p.prior_value/p.total_value<.95 then 'B' else 'C' end
 ) from proposal p left join public.suppliers s on s.id=p.supplier
$function$
;
CREATE OR REPLACE FUNCTION private.gama_management_overview(p_context text DEFAULT 'dashboard'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare today date:=(now() at time zone private.erp_timezone())::date;month_start date;metrics jsonb:='{}';clients jsonb:='[]';purchase jsonb:='[]';client_count integer:=0;purchase_count integer:=0;value jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(p_context,array['administrador']) or p_context not in ('dashboard','assistant-ia') then raise exception 'ROLE_NOT_ALLOWED';end if;
 month_start:=date_trunc('month',today)::date;
 if private.erp_module_allowed('payments',array['administrador']) then
  with valid as(select i.* from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')),
  reductions as(select coalesce(sum(c.amount*i.subtotal/nullif(i.total,0)),0) net from public.return_credits c join valid i on i.id=c.invoice_id where c.issued_on between month_start and today),
  movement_cost as(select m.reference_id delivery_id,m.product_id,sum(m.quantity*m.unit_cost_at_movement)/nullif(sum(m.quantity),0) cost,bool_and(m.unit_cost_at_movement is not null) complete
   from public.stock_movements m where m.type='out' and m.movement_type='delivery' and m.reference_type='sales_delivery' group by m.reference_id,m.product_id),
  cost_by_line as(select l.id,sum(d.quantity*c.cost)/nullif(sum(d.quantity),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.sales_order_lines l join public.sales_delivery_lines d on d.order_line_id=l.id left join movement_cost c on c.delivery_id=d.delivery_id and c.product_id=l.product_id group by l.id),
  invoice_cost as(select x.invoice_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x left join cost_by_line c on c.id=x.order_line_id group by x.invoice_id),
  restored as(select coalesce(sum(l.quantity*c.cost),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.return_lines l join public.return_orders r on r.id=l.return_id join public.sales_delivery_lines d on d.id=l.delivery_line_id left join cost_by_line c on c.id=d.order_line_id
   where l.disposition='restocked' and l.processed_at is not null and exists(select 1 from public.return_credits n where n.return_id=r.id and n.invoice_id is not null and n.issued_on between month_start and today)),
  totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost,count(*) missing
   from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today and not coalesce(c.complete,false)),
  full_totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today)
  select jsonb_build_object('sales_month',round(f.net-r.net,2),'margin_month',case when t.missing=0 and coalesce(s.complete,true) then round(f.net-r.net-f.cost+s.cost,2) end,'margin_missing_invoices',t.missing,'margin_basis','historical_dispatch_cost',
   'overdue',coalesce((select sum(balance) from private.gama_customer_dues() where coalesce(due_date,issue_date)<today),0)) into value from full_totals f cross join reductions r cross join totals t cross join restored s;
  if not private.erp_module_allowed('accounting',array['administrador']) then value:=value-'margin_month'-'margin_missing_invoices'-'margin_basis';end if;
  metrics:=metrics||value;
  with grouped as(select customer_id id,customer_name name,sum(balance) balance,min(coalesce(due_date,issue_date)) oldest_due from private.gama_customer_dues() where coalesce(due_date,issue_date)<today group by customer_id,customer_name),
  limited as(select * from grouped order by balance desc,oldest_due,id limit 10)
  select (select count(*) from grouped),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('days_late',today-l.oldest_due) order by l.balance desc,l.oldest_due,l.id),'[]') into client_count,clients from limited l;
 end if;
 if private.erp_module_allowed('warehouses',array['administrador']) then
  with all_rows as materialized (
   select data from private.stock_insight_rows(private.erp_module_allowed('gamaPurchasesV14',array['administrador']))
  ), limited as (
   select data from all_rows where (data->>'suggested_quantity')::numeric>0
   order by (data->>'available')::numeric,data->>'name' limit 20
  )
  select jsonb_build_object('stockouts',count(*) filter(where (data->>'available')::numeric<=0),
   'dormant_stock_value',coalesce(sum((data->>'value')::numeric) filter(where (data->>'on_hand')::numeric>0 and (data->>'days_without_out')::integer>=90),0)),
   (select count(*) from all_rows where (data->>'suggested_quantity')::numeric>0),
   (select coalesce(jsonb_agg(data),'[]') from limited) into value,purchase_count,purchase from all_rows;
  metrics:=metrics||value;
 end if;
 if private.erp_module_allowed('tms',array['administrador']) then
  select jsonb_build_object('late_deliveries',count(*) filter(where status not in ('Entregada','Cancelada') and (delivery_date<today or (delivery_date=today and eta_at<now())))) into value from public.tms_deliveries;metrics:=metrics||value;
 end if;
 return jsonb_build_object('today',today,'month_start',month_start,'generated_at',now(),'metrics',metrics,'clients',clients,'client_count',client_count,'purchases',purchase,'purchase_count',purchase_count);
end $function$
;


insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261011155754','performance_paged_stock_and_dashboard','ce5b8a5831cac656c7191c98aa0adb72a197ec05afccaa64ab680808d5a3f734','ce5b8a5831cac656c7191c98aa0adb72a197ec05afccaa64ab680808d5a3f734','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261011211512_accounting_audit_core.sql; SHA256 9055989e75934fc874fc17c2aa70b9a0ac1a72da2077a3de2468251d4c11831d
-- Accounting audit A01-A12: the ledger is the financial source of truth.
-- Existing posted amounts and closed periods are never rewritten by this migration.
alter table public.accounting_permissions add column can_read_all boolean not null default false;
alter table public.accounting_permissions add column can_pay boolean;
alter table public.accounting_entry_lines add column financial_account_id uuid references public.financial_accounts(id);
create index accounting_line_financial on public.accounting_entry_lines(financial_account_id) where financial_account_id is not null;
alter table public.accounting_accounts add column cashflow_class text not null default 'operating'
 check(cashflow_class in ('operating','investing','financing'));
alter table public.accounting_accounts disable trigger ac_audit_accounting_accounts;
update public.accounting_accounts set cashflow_class='financing' where type='equity';
alter table public.accounting_accounts enable trigger ac_audit_accounting_accounts;

create table private.accounting_bank_bindings(
 line_id uuid primary key references public.accounting_entry_lines(id),
 financial_account_id uuid not null references public.financial_accounts(id),
 assigned_at timestamptz not null default now(),assigned_by uuid references auth.users(id),reason text not null
);
create index accounting_binding_bank on private.accounting_bank_bindings(financial_account_id);
create table private.accounting_audit_commands(request_key uuid primary key,actor uuid not null,action text not null,payload jsonb not null,result jsonb not null);
create table private.accounting_closure_reviews(id uuid primary key default gen_random_uuid(),period_id uuid not null references public.accounting_periods(id),
 reviewed_at timestamptz not null default now(),reviewed_by uuid not null references auth.users(id),review jsonb not null,exceptions text);
create index accounting_closure_period on private.accounting_closure_reviews(period_id);
create table private.accounting_bank_statements(import_batch uuid primary key,financial_account_id uuid not null references public.financial_accounts(id),
 name text not null check(length(btrim(name)) between 1 and 180),date_from date not null,date_to date not null,
 opening_balance numeric(18,2) not null,closing_balance numeric(18,2) not null,evidence text not null check(length(btrim(evidence))>=3),
 updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id),check(date_to>=date_from));
create index accounting_statement_bank on private.accounting_bank_statements(financial_account_id);
revoke all on private.accounting_bank_bindings,private.accounting_audit_commands,private.accounting_closure_reviews,private.accounting_bank_statements from public,anon,authenticated;
alter table private.accounting_bank_bindings enable row level security;
alter table private.accounting_audit_commands enable row level security;
alter table private.accounting_closure_reviews enable row level security;
alter table private.accounting_bank_statements enable row level security;

create or replace function private.gama_accounting_rights() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text;p public.accounting_permissions;rights jsonb;begin
 if auth.uid() is null then return jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'pay',false,'scope','none');end if;
 r:=coalesce(private.current_user_role(),'');
 rights:=case when r='administrador' then jsonb_build_object('view',true,'create',true,'edit',true,'delete',true,'validate',true,'export',true,'close',true,'pay',true,'scope','all')
 when r='comercial' then jsonb_build_object('view',true,'create',false,'edit',false,'delete',false,'validate',false,'export',true,'close',false,'pay',false,'scope','commercial')
 else jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'pay',false,'scope','none') end;
 select * into p from public.accounting_permissions where profile_id=auth.uid();
 if found then
  rights:=rights||jsonb_build_object('view',p.can_view,'create',p.can_create,'edit',p.can_edit,'delete',p.can_delete,'validate',p.can_validate,'export',p.can_export,'close',p.can_close,'pay',coalesce(p.can_pay,p.can_create));
  if p.can_view and (p.can_read_all or p.can_create or p.can_validate or p.can_close) then rights:=rights||jsonb_build_object('scope','all');
  elsif p.can_view and rights->>'scope'='none' then rights:=rights||jsonb_build_object('scope','commercial');end if;
 end if;
 return rights;
end $$;

create function private.gama_accounting_currency_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended('accounting-base-currency',0));
 if tg_table_name='company_settings' then
  if new.currency is distinct from old.currency and exists(select 1 from public.accounting_entries where status in ('posted','reversed')) then raise exception 'BASE_CURRENCY_LOCKED';end if;
 end if;
 return new;
end $$;
create trigger accounting_currency_locked before update of currency on public.company_settings for each row execute function private.gama_accounting_currency_guard();
create trigger accounting_currency_post_lock before update of status on public.accounting_entries for each row when(new.status='posted') execute function private.gama_accounting_currency_guard();

create function private.gama_accounting_source_bank(p_entry uuid) returns uuid language sql stable security definer set search_path='' as $$
 select coalesce(case e.source_type
  when 'opening' then e.source_id
  when 'customer_payment' then (select financial_account_id from public.external_invoice_payments where id=e.source_id and receipt_id is null)
  when 'customer_receipt' then (select financial_account_id from public.customer_receipts where id=e.source_id)
  when 'supplier_payment' then (select financial_account_id from public.supplier_invoice_payments where id=e.source_id)
  when 'expense' then (select financial_account_id from public.expenses where id=e.source_id)
  when 'return_refund' then (select financial_account_id from public.return_refunds where id=e.source_id)
  when 'payroll_payment' then (select financial_account_id from public.hr_payroll_payments where id=e.source_id)
  end,j.financial_account_id)
 from public.accounting_entries x join public.accounting_entries e on e.id=coalesce(x.reversal_of,case when x.source_type='reversal' then x.source_id end,x.id)
 join public.accounting_journals j on j.id=e.journal_id where x.id=p_entry
$$;

create function private.gama_accounting_bind_line() returns trigger language plpgsql security definer set search_path='' as $$
declare fid uuid;cnt integer;begin
 fid:=coalesce(new.financial_account_id,private.gama_accounting_source_bank(new.entry_id));
 if fid is not null and not exists(select 1 from public.financial_accounts where id=fid and account_id=new.account_id) then
  if new.financial_account_id is not null then raise exception 'BANK_ACCOUNT_MISMATCH';end if;fid:=null;
 end if;
 if fid is null then
  select count(*),min(id::text)::uuid into cnt,fid from public.financial_accounts where account_id=new.account_id;
  if cnt>1 then raise exception 'LINE_FINANCIAL_ACCOUNT_REQUIRED';end if;
 end if;
 new.financial_account_id:=fid;return new;
end $$;
create trigger accounting_bind_line before insert on public.accounting_entry_lines for each row execute function private.gama_accounting_bind_line();
-- Freeze only deterministic historical account associations, without updating a posted line.
insert into private.accounting_bank_bindings(line_id,financial_account_id,reason)
select l.id,f.id,'Deterministic association at accounting audit migration'
from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id
join public.financial_accounts f on f.account_id=l.account_id
where f.id=private.gama_accounting_source_bank(e.id) or
 (private.gama_accounting_source_bank(e.id) is null and (select count(*) from public.financial_accounts z where z.account_id=l.account_id)=1);

-- Preserve explicit bank metadata in manual posting and counter-entries.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 if position('project_id,position)' in s)=0 then raise exception 'BOOK_BANK_ANCHOR_MISSING';end if;
 s:=replace(s,'project_id,position)','project_id,position,financial_account_id)');
 s:=replace(s,'nullif(x->>''project_id'','''')::uuid,i);','nullif(x->>''project_id'','''')::uuid,i,nullif(x->>''financial_account_id'','''')::uuid);');execute s;
 s:=pg_get_functiondef('private.gama_accounting_reverse(uuid,text)'::regprocedure);
 s:=replace(s,'''tax_id'',l.tax_id,''project_id'',l.project_id)', '''tax_id'',l.tax_id,''project_id'',l.project_id,''financial_account_id'',coalesce(l.financial_account_id,(select financial_account_id from private.accounting_bank_bindings where line_id=l.id)))');execute s;
end $$;

create view private.gama_cash_ledger with(security_invoker=true) as
select l.id line_id,l.entry_id,l.account_id,coalesce(l.financial_account_id,b.financial_account_id) financial_account_id,
 e.entry_date,e.number,e.reference,e.memo,e.source_type,e.source_id,e.status,l.label,l.debit,l.credit,l.debit-l.credit amount
from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id
left join private.accounting_bank_bindings b on b.line_id=l.id
where e.status in ('posted','reversed') and exists(select 1 from public.financial_accounts f where f.account_id=l.account_id);
revoke all on private.gama_cash_ledger from public,anon,authenticated;
alter view private.gama_cash_position rename to gama_cash_operational;
create view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 coalesce((select sum(l.amount) from private.gama_cash_ledger l where l.financial_account_id=f.id),0) current_balance,
 (select count(*) from public.bank_transactions t where t.financial_account_id=f.id and t.status='unmatched') unmatched
from public.financial_accounts f;
revoke all on private.gama_cash_position,private.gama_cash_operational from public,anon,authenticated;

create view private.gama_accounting_eligible_sources with(security_invoker=true) as
select 'sales_invoice'::text source_type,i.id source_id,i.issue_date source_date,i.number reference,i.total amount from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
union all select 'customer_payment',id,paid_at,coalesce(reference,id::text),amount from public.external_invoice_payments where status='confirmed'
union all select 'supplier_invoice',id,issue_date,number,total from public.supplier_invoices where status='posted'
union all select 'supplier_payment',id,paid_at,coalesce(reference,id::text),amount from public.supplier_invoice_payments where status='confirmed'
union all select 'expense',id,expense_date,reference,amount_total from public.expenses where status='posted'
union all select case when o.kind='supplier' then 'supplier_credit' else 'return_credit' end,k.id,k.issued_on,k.number,k.amount from public.return_credits k join public.return_orders o on o.id=k.return_id
union all select 'return_refund',id,paid_at,coalesce(reference,id::text),amount from public.return_refunds where financial_account_id is not null
union all select 'customer_receipt',id,paid_at,coalesce(reference,id::text),amount from public.customer_receipts where status='confirmed'
union all select 'payroll',id,period,source_ref,employer_cost from public.hr_payroll where status='validated'
union all select 'payroll_payment',id,paid_on,coalesce(reference,id::text),amount from public.hr_payroll_payments where status='confirmed' and financial_account_id is not null;
revoke all on private.gama_accounting_eligible_sources from public,anon,authenticated;

create function private.gama_accounting_controls(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare missing jsonb;openings jsonb;banks jsonb;stock jsonb;checks jsonb;drafts integer;unbalanced integer;unassigned integer;stock_missing integer;stock_difference numeric;begin
 select coalesce(jsonb_agg(to_jsonb(s) order by source_date,source_type,reference),'[]') into missing from private.gama_accounting_eligible_sources s
 where s.source_date<=p_to and not exists(select 1 from public.accounting_entries e where e.source_type=s.source_type and e.source_id=s.source_id);
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'amount',f.opening_balance)),'[]') into openings from public.financial_accounts f
 where f.opening_balance<>0 and f.created_at::date<=p_to and not exists(select 1 from public.accounting_entries where source_type='opening' and source_id=f.id);
 select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'ledger',g.current_balance,'operations',o.current_balance,'difference',g.current_balance-o.current_balance,'unmatched',g.unmatched)),'[]') into banks
 from private.gama_cash_position g join private.gama_cash_operational o on o.id=g.id where g.active;
 select count(*) into drafts from public.accounting_entries where status='draft' and entry_date between p_from and p_to;
 select count(*) into unbalanced from public.accounting_entries e where status in ('posted','reversed') and entry_date<=p_to
 and (select coalesce(sum(debit-credit),0) from public.accounting_entry_lines where entry_id=e.id)<>0;
 select count(*) into unassigned from private.gama_cash_ledger where financial_account_id is null and entry_date<=p_to;
 select count(*) into stock_missing from public.stock_valuation_entries v where v.kind not in ('method','transfer') and round(abs(v.value_delta)+abs(v.expense_delta),2)>0
 and (v.created_at at time zone private.erp_timezone())::date<=p_to and not exists(select 1 from public.accounting_source_links l where l.source_type='stock_valuation' and l.source_id=v.sequence::text);
 with amounts as(select b.stock_account_id aid,coalesce(sum(v.value_delta) filter(where (v.created_at at time zone private.erp_timezone())::date<=p_to),0) subledger
 from public.stock_cost_books b left join public.stock_valuation_entries v on v.product_id=b.product_id where b.stock_account_id is not null group by b.stock_account_id),
 totals as(select a.*,coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=a.aid and e.status in ('posted','reversed') and e.entry_date<=p_to),0) ledger from amounts a)
 select coalesce(jsonb_agg(jsonb_build_object('account_id',aid,'subledger',round(subledger,2),'ledger',ledger,'difference',round(subledger,2)-ledger)),'[]'),coalesce(sum(abs(round(subledger,2)-ledger)),0) into stock,stock_difference from totals;
 checks:=jsonb_build_array(
 jsonb_build_object('code','missing_sources','count',jsonb_array_length(missing),'blocking',true),
 jsonb_build_object('code','opening_balances','count',jsonb_array_length(openings),'blocking',true),
 jsonb_build_object('code','draft_entries','count',drafts,'blocking',true),
 jsonb_build_object('code','unbalanced_entries','count',unbalanced,'blocking',true),
 jsonb_build_object('code','unassigned_bank_lines','count',unassigned,'blocking',true),
 jsonb_build_object('code','unposted_stock','count',stock_missing,'blocking',true),
 jsonb_build_object('code','stock_difference','count',case when stock_difference<>0 then 1 else 0 end,'blocking',true),
 jsonb_build_object('code','unconfigured_stock','count',case when p_to>=(now() at time zone private.erp_timezone())::date then (select count(*) from public.products p where p.product_kind='goods' and p.active and exists(select 1 from public.stock_quants q where q.product_id=p.id and q.quantity<>0) and not exists(select 1 from public.stock_cost_books b where b.product_id=p.id)) else 0 end,'blocking',false),
 jsonb_build_object('code','unmatched_bank','count',(select count(*) from public.bank_transactions where status='unmatched' and value_date between p_from and p_to),'blocking',false));
 return jsonb_build_object('from',p_from,'to',p_to,'generated_at',statement_timestamp(),'checks',checks,'missing',missing,'openings',openings,'banks',banks,'stock',stock,
 'can_close',not exists(select 1 from jsonb_array_elements(checks)c where (c->>'blocking')::boolean and (c->>'count')::integer>0),
 'unassigned',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from private.gama_cash_ledger where financial_account_id is null and entry_date<=p_to order by entry_date limit 200)z),'[]'));
end $$;

-- Clone the source poster with an explicitly reviewed correction date. No source date is changed.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
 s:=replace(s,'private.gama_accounting_post(p_source_type text, p_source_id uuid)','private.gama_accounting_post_at(p_source_type text, p_source_id uuid, p_date date)');
 foreach s in array array[s] loop
 s:=replace(s,'inv.issue_date,inv.number','p_date,inv.number');s:=replace(s,'pay.paid_at,coalesce','p_date,coalesce');s:=replace(s,'si.issue_date,si.number','p_date,si.number');
 s:=replace(s,'sp.paid_at,coalesce','p_date,coalesce');s:=replace(s,'ex.expense_date,ex.reference','p_date,ex.reference');s:=replace(s,'rc.issued_on,','p_date,');s:=replace(s,'rc.paid_at,coalesce','p_date,coalesce');
 execute s;end loop;
end $$;

alter function private.gama_accounting_action(text,jsonb) rename to gama_accounting_action_before_audit;
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare rights jsonb:=private.gama_accounting_rights();result jsonb;cfg public.company_settings;d1 date;d2 date;today date:=(now() at time zone private.erp_timezone())::date;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim integer:=least(2000,greatest(1,coalesce((p_data->>'limit')::integer,50)));search text:=left(btrim(coalesce(p_data->>'search','')),120);
 review jsonb;p public.accounting_periods;prev_from date;prev_to date;fy date;period_result jsonb;rec record;opening numeric;closing numeric;rows jsonb;categories jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_REQUEST';end if;
 if rights->>'scope'<>'all' then return private.gama_accounting_action_before_audit(p_action,p_data);end if;
 select * into cfg from public.company_settings where id;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);d2:=coalesce(nullif(p_data->>'to','')::date,today);if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action in ('supplier_payment','supplier_payment_cancel') and not coalesce((rights->>'pay')::boolean,false) then raise exception 'PAYMENT_NOT_ALLOWED';end if;
 if p_action='entry_reverse' and exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind='ledger_entry' and s.source_id=(p_data->>'id')::uuid and g.cancelled_at is null) then raise exception 'ENTRY_BANK_MATCHED';end if;
 if p_action='period_close' then
  if not coalesce((rights->>'close')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  p:=private.gama_accounting_period((p_data->>'period_start')::date);select * into p from public.accounting_periods where id=p.id for update;
  if p.status='closed' then return jsonb_build_object('id',p.id,'status','closed');end if;
  review:=private.gama_accounting_controls(p.period_start,p.period_end);
  if not (review->>'can_close')::boolean then raise exception 'CLOSURE_BLOCKED';end if;
  if exists(select 1 from jsonb_array_elements(review->'checks')c where not (c->>'blocking')::boolean and (c->>'count')::integer>0)
   and length(btrim(coalesce(p_data->>'exceptions','')))<3 then raise exception 'CLOSURE_EXCEPTION_REQUIRED';end if;
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  insert into private.accounting_closure_reviews(period_id,reviewed_by,review,exceptions) values(p.id,auth.uid(),review,nullif(p_data->>'exceptions',''));return result||jsonb_build_object('review',review);
 elsif p_action='permission_save' then
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  update public.accounting_permissions set can_read_all=coalesce((p_data->>'can_read_all')::boolean,false),can_pay=coalesce((p_data->>'can_pay')::boolean,false) where profile_id=(p_data->>'profile_id')::uuid;return result;
 elsif p_action='bank_list' then
  with filtered as(select t.*,f.name account_name from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id
   where (nullif(p_data->>'financial_account_id','') is null or t.financial_account_id=(p_data->>'financial_account_id')::uuid)
   and (nullif(p_data->>'status','') is null or p_data->>'status'='all' or t.status=p_data->>'status')
   and (nullif(p_data->>'import_batch','') is null or t.import_batch=(p_data->>'import_batch')::uuid)
   and (nullif(p_data->>'from','') is null or t.value_date>=d1) and (nullif(p_data->>'to','') is null or t.value_date<=d2)
   and (nullif(p_data->>'min_amount','') is null or t.amount>=(p_data->>'min_amount')::numeric)
   and (nullif(p_data->>'max_amount','') is null or t.amount<=(p_data->>'max_amount')::numeric)
   and (search='' or concat_ws(' ',t.reference,t.description,f.name,t.amount::text) ilike '%'||search||'%'))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from filtered order by value_date desc,id offset off limit lim)z),'[]'),
   'total',(select count(*) from filtered),'offset',off,'limit',lim,
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.financial_accounts where active),'[]'),
   'batches',coalesce((select jsonb_agg(to_jsonb(z)) from(select t.import_batch id,min(t.value_date) date_from,max(t.value_date) date_to,count(*) lines,f.name account_name from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id where t.import_batch is not null group by t.import_batch,f.name order by max(t.imported_at) desc)z),'[]')) into result;return result;
 elsif p_action='account_movements' then
  return coalesce((select jsonb_agg(jsonb_build_object('date',entry_date,'reference',reference,'label',coalesce(label,memo),'number',number,'entry_id',entry_id,'in',debit,'out',credit,'balance',balance) order by entry_date desc,number desc,line_id desc)
   from(select *,sum(amount) over(order by entry_date,number,line_id rows between unbounded preceding and current row) balance from private.gama_cash_ledger where financial_account_id=(p_data->>'id')::uuid and entry_date<=d2)z where entry_date>=d1),'[]');
 elsif p_action='report_balance' then
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  select coalesce(sum(v.value_delta),0) into closing from public.stock_valuation_entries v where (v.created_at at time zone private.erp_timezone())::date<=d2;
  return jsonb_set(result,'{stock}',to_jsonb(round(closing,2)))||jsonb_build_object('stock_basis','dated_valuation','stock_controls',private.gama_accounting_controls(d1,d2)->'stock',
   'stock_coverage',jsonb_build_object('configured',(select count(*) from public.stock_cost_books where started_at::date<=d2),
    'before_opening',(select count(*) from public.stock_cost_books where started_at::date>d2),
    'unconfigured',(select count(*) from public.products prod where prod.product_kind='goods' and prod.active and prod.created_at::date<=d2 and not exists(select 1 from public.stock_cost_books where product_id=prod.id)),
    'complete',not exists(select 1 from public.products prod left join public.stock_cost_books b on b.product_id=prod.id where prod.product_kind='goods' and prod.active and prod.created_at::date<=d2 and (b.product_id is null or b.started_at::date>d2))));
 elsif p_action='report_cashflow' then
  select coalesce(sum(amount) filter(where entry_date<d1),0),coalesce(sum(amount),0) into opening,closing from private.gama_cash_ledger where entry_date<=d2;
  with cash_entries as(select entry_id,sum(amount) amount from private.gama_cash_ledger where entry_date between d1 and d2 group by entry_id having sum(amount)<>0),
  classified as(select e.entry_date,case when exists(select 1 from public.accounting_assets where asset_account_id=l.account_id) then 'investing' else a.cashflow_class end category,
   l.credit-l.debit amount from cash_entries c join public.accounting_entries e on e.id=c.entry_id join public.accounting_entry_lines l on l.entry_id=e.id join public.accounting_accounts a on a.id=l.account_id
   where not exists(select 1 from public.financial_accounts f where f.account_id=l.account_id)),
  cash_monthly as(select to_char(e.entry_date,'YYYY-MM') period_month,sum(greatest(c.amount,0)) incoming,sum(greatest(-c.amount,0)) outgoing from cash_entries c join public.accounting_entries e on e.id=c.entry_id group by 1),
  monthly as(select to_char(entry_date,'YYYY-MM') as period_month,sum(amount) net,
   sum(amount) filter(where category='operating') operating,sum(amount) filter(where category='investing') investing,sum(amount) filter(where category='financing') financing from classified group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('month',m.period_month,'in',c.incoming,'out',c.outgoing,'net',m.net,'operating',coalesce(m.operating,0),'investing',coalesce(m.investing,0),'financing',coalesce(m.financing,0)) order by m.period_month),'[]') into rows from monthly m join cash_monthly c using(period_month);
  return jsonb_build_object('from',d1,'to',d2,'opening',opening,'balance',closing,'net',closing-opening,'rows',rows,'basis','ledger');
 elsif p_action='overview' then
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  prev_from:=(date_trunc('month',today)-interval '1 month')::date;
  prev_to:=least((date_trunc('month',today)-interval '1 day')::date,prev_from+extract(day from today)::integer-1);
  fy:=make_date(extract(year from today)::integer,cfg.fiscal_year_start_month,1);if fy>today then fy:=(fy-interval '1 year')::date;end if;
  select jsonb_build_object('month',coalesce(sum(l.credit-l.debit) filter(where a.type='income' and e.entry_date>=date_trunc('month',today)::date),0),
   'previous',coalesce(sum(l.credit-l.debit) filter(where a.type='income' and e.entry_date between prev_from and prev_to),0),'year',coalesce(sum(l.credit-l.debit) filter(where a.type='income' and e.entry_date>=fy),0)),
   jsonb_build_object('month',coalesce(sum(l.debit-l.credit) filter(where a.type='expense' and e.entry_date>=date_trunc('month',today)::date),0),
   'previous',coalesce(sum(l.debit-l.credit) filter(where a.type='expense' and e.entry_date between prev_from and prev_to),0),'year',coalesce(sum(l.debit-l.credit) filter(where a.type='expense' and e.entry_date>=fy),0))
   into period_result,review from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id where e.status in ('posted','reversed') and e.source_type<>'year_close' and e.entry_date<=today;
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into categories from(select a.name,sum(l.debit-l.credit) amount from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id join public.accounting_entries e on e.id=l.entry_id where a.type='expense' and e.status in ('posted','reversed') and e.source_type<>'year_close' and e.entry_date between fy and today group by a.name having sum(l.debit-l.credit)>0 order by sum(l.debit-l.credit) desc limit 6)z;
  result:=jsonb_set(result,'{revenue}',period_result);result:=jsonb_set(result,'{expense}',review||jsonb_build_object('categories',categories));
  result:=jsonb_set(result,'{taxes}',private.gama_accounting_action_before_audit('taxes',jsonb_build_object('from',date_trunc('month',today)::date,'to',today))->'summary');
  result:=jsonb_set(result,'{treasury}',jsonb_build_object('balance',(select coalesce(sum(current_balance),0) from private.gama_cash_position where active),
   'accounts',coalesce((select jsonb_agg(to_jsonb(c) order by name) from private.gama_cash_position c where active),'[]'),
   'inflow',(select coalesce(sum(debit),0) from private.gama_cash_ledger where entry_date between date_trunc('month',today)::date and today),
   'outflow',(select coalesce(sum(credit),0) from private.gama_cash_ledger where entry_date between date_trunc('month',today)::date and today)));
  return result||jsonb_build_object('generated_at',statement_timestamp(),'basis','ledger','previous_from',prev_from,'previous_to',prev_to,'fiscal_from',fy);
 end if;
 result:=private.gama_accounting_action_before_audit(p_action,p_data);
 if p_action='settings' then result:=result||jsonb_build_object('currency_locked',exists(select 1 from public.accounting_entries where status in ('posted','reversed')));end if;
 return result;
end $$;
revoke all on function private.gama_accounting_action_before_audit(text,jsonb) from public,anon,authenticated;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

-- Private helpers can only be reached through the checked public facade below.
revoke all on function private.gama_accounting_currency_guard(),private.gama_accounting_source_bank(uuid),private.gama_accounting_bind_line(),private.gama_accounting_controls(date,date),private.gama_accounting_post_at(text,uuid,date) from public,anon,authenticated;

-- Reviewed manual entries can be reconciled like business payments.
alter table public.bank_match_sources drop constraint bank_match_sources_kind_check;
alter table public.bank_match_sources add constraint bank_match_sources_kind_check check(kind in ('customer_payment','customer_receipt','supplier_payment','expense','ledger_entry'));
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_bank_match_core(text,jsonb)'::regprocedure);
 if position('else raise exception ''MATCH_SOURCE_INVALID'';' in s)=0 then raise exception 'BANK_LEDGER_ANCHOR_MISSING';end if;
 s:=replace(s,'else raise exception ''MATCH_SOURCE_INVALID'';',
 'elsif x->>''kind''=''ledger_entry'' then select sum(amount) amount,min(financial_account_id::text)::uuid financial_account_id,''confirmed''::text status into source from private.gama_cash_ledger where entry_id=(x->>''id'')::uuid and financial_account_id=acc having count(distinct financial_account_id)=1 and sum(amount)<>0; else raise exception ''MATCH_SOURCE_INVALID'';');execute s;
end $$;

-- Undo removes an association, not its payment or cash entry. Reuse the existing source.
create function private.gama_bank_existing_posting(p_bank uuid) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.bank_match_banks b join public.bank_match_sources s on s.group_id=b.group_id where b.bank_id=p_bank and (
 (s.kind='ledger_entry' and exists(select 1 from public.accounting_entries e where e.id=s.source_id and e.status='posted')) or
 (s.kind='customer_receipt' and exists(select 1 from public.customer_receipts r where r.id=s.source_id and r.status='confirmed')) or
 (s.kind='customer_payment' and exists(select 1 from public.external_invoice_payments r where r.id=s.source_id and r.status='confirmed')) or
 (s.kind='supplier_payment' and exists(select 1 from public.supplier_invoice_payments r where r.id=s.source_id and r.status='confirmed')) or
 (s.kind='expense' and exists(select 1 from public.expenses r where r.id=s.source_id and r.status='posted'))));
$$;
revoke all on function private.gama_bank_existing_posting(uuid) from public,anon,authenticated;

create function private.gama_accounting_audit_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);
 result jsonb;batch uuid:=nullif(p_data->>'import_batch','')::uuid;b public.bank_transactions;context jsonb;search text:=left(btrim(coalesce(p_data->>'search','')),120);begin
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 if p_action='controls' then return private.gama_accounting_controls(d1,d2);
 elsif p_action='context' then return private.gama_accounting_ec_read('context',p_data)||jsonb_build_object('closures',coalesce((select jsonb_agg(to_jsonb(z)) from(select id,period_id,reviewed_at,reviewed_by,exceptions from private.accounting_closure_reviews order by reviewed_at desc limit 36)z),'[]'));
 elsif p_action='statements' then
  with batches as(select t.import_batch,t.financial_account_id,f.name account_name,min(t.value_date) first_date,max(t.value_date) last_date,sum(t.amount) net,
   count(*) lines,count(*) filter(where t.status='matched') matched,count(*) filter(where t.status='unmatched') unmatched,count(*) filter(where t.status='ignored') ignored
   from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id where t.import_batch is not null
   and (batch is null or t.import_batch=batch) group by t.import_batch,t.financial_account_id,f.name),
  reviewed as(select bt.*,s.name,coalesce(s.date_from,bt.first_date) date_from,coalesce(s.date_to,bt.last_date) date_to,s.opening_balance,s.closing_balance,s.evidence,s.updated_at,
   coalesce((select sum(l.amount) from private.gama_cash_ledger l where l.financial_account_id=bt.financial_account_id and l.entry_date<=coalesce(s.date_to,bt.last_date)),0) ledger_balance
   from batches bt left join private.accounting_bank_statements s on s.import_batch=bt.import_batch)
  select jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('arithmetic_difference',closing_balance-opening_balance-net,'ledger_difference',closing_balance-ledger_balance) order by date_to desc),'[]')) into result from reviewed r;return result;
 elsif p_action='bank_choices' then
  select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
  context:=private.gama_bank_match('context',jsonb_build_object('account_id',b.financial_account_id));
  select coalesce(jsonb_agg(x),'[]') into result from jsonb_array_elements(context->'sources')x where ((x->>'amount')::numeric>0)=(b.amount>0) and (search='' or concat_ws(' ',x->>'label',x->>'id',x->>'date') ilike '%'||search||'%');
  return jsonb_build_object('bank',to_jsonb(b),'sources',result,'has_posting',private.gama_bank_existing_posting(b.id),
   'invoice_total',case when b.amount>0 then (select count(*) from private.gama_receivables r where r.balance>0 and r.payment_status<>'cancelled' and (search='' or concat_ws(' ',r.number,r.customer_name) ilike '%'||search||'%')) else (select count(*) from private.gama_payables r where r.balance>0 and r.status='posted' and (search='' or concat_ws(' ',r.number,r.supplier_name) ilike '%'||search||'%')) end,
   'invoices',case when b.amount>0 then coalesce((select jsonb_agg(to_jsonb(z)) from(select id,number,customer_name partner_name,customer_id partner_id,balance,issue_date from private.gama_receivables r where balance>0 and payment_status<>'cancelled' and (search='' or concat_ws(' ',r.number,r.customer_name) ilike '%'||search||'%') order by issue_date,id limit 500)z),'[]')
   else coalesce((select jsonb_agg(to_jsonb(z)) from(select id,number,supplier_name partner_name,supplier_id partner_id,balance,issue_date from private.gama_payables r where balance>0 and status='posted' and (search='' or concat_ws(' ',r.number,r.supplier_name) ilike '%'||search||'%') order by issue_date,id limit 500)z),'[]') end,
   'ledger',coalesce((select jsonb_agg(to_jsonb(z)) from(select entry_id id,max(coalesce(reference,number)) label,max(entry_date) date,sum(amount) amount from private.gama_cash_ledger l
    where financial_account_id=b.financial_account_id and source_type='manual' and (search='' or concat_ws(' ',l.reference,l.number,l.memo) ilike '%'||search||'%') and not exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind='ledger_entry' and s.source_id=l.entry_id and g.cancelled_at is null)
    group by entry_id having (sum(amount)>0)=(b.amount>0) and sum(amount)<>0 order by max(entry_date) desc limit 100)z),'[]'));
 elsif p_action='package' then
  return jsonb_build_object('from',d1,'to',d2,'generated_at',statement_timestamp(),'currency',(select currency from public.company_settings where id),
   'revision',md5(jsonb_build_object('entries',(select jsonb_agg(jsonb_build_array(e.id,e.status,e.entry_date,e.posted_at) order by e.id) from public.accounting_entries e),
    'customers',(select jsonb_agg(jsonb_build_array(r.id,r.total,r.paid,r.balance) order by r.id) from private.gama_receivables r),
    'suppliers',(select jsonb_agg(jsonb_build_array(r.id,r.total,r.paid,r.balance) order by r.id) from private.gama_payables r),
    'stock',(select max(sequence) from public.stock_valuation_entries),'banks',(select jsonb_agg(jsonb_build_array(t.id,t.amount,t.status) order by t.id) from public.bank_transactions t))::text),
   'pl',private.gama_accounting_action('report_pl',p_data),'previous_pl',private.gama_accounting_action('report_pl',jsonb_build_object('from',(d1-interval '1 year')::date,'to',(d2-interval '1 year')::date)),
   'balance',private.gama_accounting_action('report_balance',p_data),'cashflow',private.gama_accounting_action('report_cashflow',p_data),
   'trial',private.gama_accounting_ec_read('trial_balance',p_data),'controls',private.gama_accounting_controls(d1,d2),
   'customers',private.gama_accounting_action('receivables',p_data||jsonb_build_object('limit',2000)),
   'suppliers',private.gama_accounting_action('payables',p_data||jsonb_build_object('limit',2000)));
 end if;
 raise exception 'INVALID_ACTION';
end $$;

create function private.gama_accounting_audit_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare key uuid:=(p_data->>'request_key')::uuid;fid uuid:=nullif(p_data->>'financial_account_id','')::uuid;eid uuid;aid uuid;counter uuid;rid uuid;
 amt numeric;total numeric;cfg public.company_settings;b public.bank_transactions;allocation jsonb;src record;r record;receipt jsonb;payment jsonb;sources jsonb:='[]';
 lines jsonb;date date:=(p_data->>'entry_date')::date;reason text:=btrim(coalesce(p_data->>'reason',''));begin
 select * into cfg from public.company_settings where id;
 if p_action in ('recovery_post','cash_operation','bank_adjustment','line_bank_assign') and length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
 if p_action='opening_post' then return private.gama_accounting_ec('opening_post',p_data);
 elsif p_action='recovery_post' then
  select * into src from private.gama_accounting_eligible_sources where source_type=p_data->>'source_type' and source_id=(p_data->>'source_id')::uuid;
  if not found then raise exception 'SOURCE_UNAVAILABLE';end if;
  if exists(select 1 from public.accounting_entries where source_type=src.source_type and source_id=src.source_id) then raise exception 'SOURCE_ALREADY_POSTED';end if;
  if date<src.source_date then raise exception 'DOCUMENT_DATE_BEFORE_INVOICE';end if;
  if src.source_type in ('payroll','payroll_payment') then
   if date<>src.source_date then raise exception 'RECOVERY_PAYROLL_ORIGINAL_DATE_REQUIRED';end if;
   eid:=private.gama_ec_payroll_post(src.source_id,src.source_type='payroll_payment');
  elsif src.source_type='customer_receipt' then
   select * into r from public.customer_receipts where id=src.source_id and status='confirmed' for update;
   aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=r.financial_account_id),'asset');counter:=private.gama_ec_account((select id from public.accounting_accounts where code='2090' and active),'liability');
   eid:=private.gama_accounting_book(case when r.method='cash' then 'CAJ' else 'BAN' end,date,r.reference,'customer_receipt',r.id,reason,jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',r.financial_account_id,'debit',r.amount),jsonb_build_object('account_id',counter,'credit',r.amount,'partner_type','customer','partner_id',r.customer_id)));
  else eid:=private.gama_accounting_post_at(src.source_type,src.source_id,date);end if;
  if eid is null then raise exception 'SOURCE_UNAVAILABLE';end if;
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data) values('accounting_entries',eid::text,'VALIDATE',auth.uid(),private.current_user_role(),jsonb_build_object('action','recovery','source_type',src.source_type,'source_id',src.source_id,'original_date',src.source_date,'correction_date',date,'reason',reason));
  return jsonb_build_object('entry_id',eid,'original_date',src.source_date,'correction_date',date);
 elsif p_action='line_bank_assign' then
  select * into src from private.gama_cash_ledger where line_id=(p_data->>'line_id')::uuid and financial_account_id is null;
  if not found or not exists(select 1 from public.financial_accounts where id=fid and account_id=src.account_id) then raise exception 'BANK_ACCOUNT_MISMATCH';end if;
  insert into private.accounting_bank_bindings(line_id,financial_account_id,assigned_by,reason) values(src.line_id,fid,auth.uid(),reason);return jsonb_build_object('id',src.line_id);
 elsif p_action='statement_save' then
  select min(financial_account_id::text)::uuid bank_id,count(distinct financial_account_id) bank_count,coalesce(sum(amount),0) net,min(value_date) first_date,max(value_date) last_date into src from public.bank_transactions where import_batch=(p_data->>'import_batch')::uuid;
  if src.bank_count<>1 then raise exception 'STATEMENT_NOT_FOUND';end if;
  if (p_data->>'closing_balance')::numeric-(p_data->>'opening_balance')::numeric<>src.net then raise exception 'STATEMENT_UNBALANCED';end if;
  if (p_data->>'date_from')::date>src.first_date or (p_data->>'date_to')::date<src.last_date then raise exception 'STATEMENT_DATES_INVALID';end if;
  insert into private.accounting_bank_statements(import_batch,financial_account_id,name,date_from,date_to,opening_balance,closing_balance,evidence,updated_by)
  values((p_data->>'import_batch')::uuid,src.bank_id,p_data->>'name',(p_data->>'date_from')::date,(p_data->>'date_to')::date,(p_data->>'opening_balance')::numeric,(p_data->>'closing_balance')::numeric,p_data->>'evidence',auth.uid())
  on conflict(import_batch) do update set name=excluded.name,date_from=excluded.date_from,date_to=excluded.date_to,opening_balance=excluded.opening_balance,closing_balance=excluded.closing_balance,evidence=excluded.evidence,updated_at=now(),updated_by=auth.uid();
  return jsonb_build_object('id',p_data->>'import_batch');
 elsif p_action='cash_operation' then
  aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=fid and active and currency=cfg.currency),'asset');
  amt:=(p_data->>'amount')::numeric;if amt<=0 or amt<>round(amt,2) or amt::text in ('NaN','Infinity','-Infinity') then raise exception 'INVALID_AMOUNT';end if;
  if p_data->>'kind'='transfer' then
   counter:=private.gama_ec_account((select account_id from public.financial_accounts where id=(p_data->>'destination_id')::uuid and active and currency=cfg.currency),'asset');
   if fid=(p_data->>'destination_id')::uuid then raise exception 'TRANSFER_SAME_ACCOUNT';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'credit',amt),jsonb_build_object('account_id',counter,'financial_account_id',p_data->>'destination_id','debit',amt));
  else
   counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,case when p_data->>'kind'='contribution' then 'equity' end);
   if exists(select 1 from public.financial_accounts where account_id=counter) then raise exception 'USE_TRANSFER_OPERATION';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'debit',case when p_data->>'direction'='out' then 0 else amt end,'credit',case when p_data->>'direction'='out' then amt else 0 end),jsonb_build_object('account_id',counter,'credit',case when p_data->>'direction'='out' then 0 else amt end,'debit',case when p_data->>'direction'='out' then amt else 0 end));
  end if;
  eid:=private.gama_accounting_book('BAN',date,p_data->>'reference','manual',null,reason,lines);return jsonb_build_object('entry_id',eid);
 elsif p_action in ('bank_group','bank_settle','bank_adjustment') then
  select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
  perform pg_advisory_xact_lock(hashtextextended('bank-match:'||b.financial_account_id::text,0));select * into b from public.bank_transactions where id=b.id for update;
  if b.status<>'unmatched' then raise exception 'BANK_ALREADY_MATCHED';end if;
  if p_action='bank_group' then return private.gama_bank_match('apply',jsonb_build_object('request_key',key,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',p_data->'sources','note',p_data->>'note'));end if;
  if private.gama_bank_existing_posting(b.id) then raise exception 'BANK_EXISTING_POSTING_USE_GROUP';end if;
  if not private.gama_accounting_may('create') or not private.gama_accounting_may('pay') then raise exception 'PAYMENT_NOT_ALLOWED';end if;
  if p_action='bank_adjustment' then
   aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=b.financial_account_id),'asset');counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,case when b.amount>0 then 'income' else 'expense' end);
   eid:=private.gama_accounting_book('BAN',b.value_date,coalesce(b.reference,'Ajuste bancario'),'manual',null,reason,jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',b.financial_account_id,'debit',greatest(b.amount,0),'credit',greatest(-b.amount,0)),jsonb_build_object('account_id',counter,'credit',greatest(b.amount,0),'debit',greatest(-b.amount,0))));
   sources:=jsonb_build_array(jsonb_build_object('kind','ledger_entry','id',eid));
  else
   if jsonb_typeof(p_data->'allocations') is distinct from 'array' or jsonb_array_length(p_data->'allocations') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
   select sum((x->>'amount')::numeric) into total from jsonb_array_elements(p_data->'allocations')x;
   if total<>abs(b.amount) or exists(select 1 from jsonb_array_elements(p_data->'allocations')x where (x->>'amount')::numeric<=0 or (x->>'amount')::numeric<>round((x->>'amount')::numeric,2)) then raise exception 'MATCH_DIFFERENCE';end if;
   if (select count(distinct x->>'invoice_id') from jsonb_array_elements(p_data->'allocations')x)<>jsonb_array_length(p_data->'allocations') then raise exception 'DUPLICATE_INVOICE';end if;
   if b.amount>0 then
    if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
    select count(distinct customer_id),min(customer_id::text)::uuid into src from private.gama_receivables where id in(select (x->>'invoice_id')::uuid from jsonb_array_elements(p_data->'allocations')x);
    if src.count<>1 then raise exception 'ONE_CUSTOMER_REQUIRED';end if;
    perform 1 from public.customers where id=src.min for update;
    receipt:=private.gama_receipt_action('receive',jsonb_build_object('request_key',key,'customer_id',src.min,'financial_account_id',b.financial_account_id,'amount',b.amount,'paid_at',b.value_date,'method','transfer','reference',coalesce(nullif(b.reference,''),nullif(b.description,''),b.id::text),'notes','Cobro revisado desde extracto'));
    for allocation in select value from jsonb_array_elements(p_data->'allocations') order by value->>'invoice_id' loop
     perform private.gama_receipt_action('allocate',jsonb_build_object('request_key',md5(key::text||(allocation->>'invoice_id'))::uuid,'id',receipt->>'id','invoice_id',allocation->>'invoice_id','amount',allocation->>'amount'));
    end loop;sources:=jsonb_build_array(jsonb_build_object('kind','customer_receipt','id',receipt->>'id'));
   else
    perform 1 from public.supplier_invoices where id in(select (x->>'invoice_id')::uuid from jsonb_array_elements(p_data->'allocations')x) order by id for update;
    for allocation in select value from jsonb_array_elements(p_data->'allocations') order by value->>'invoice_id' loop
     payment:=private.gama_accounting_action('supplier_payment',jsonb_build_object('request_key',md5(key::text||(allocation->>'invoice_id'))::uuid,'supplier_invoice_id',allocation->>'invoice_id','financial_account_id',b.financial_account_id,'amount',allocation->>'amount','paid_at',b.value_date,'method','transfer','reference',b.reference));
     sources:=sources||jsonb_build_array(jsonb_build_object('kind','supplier_payment','id',payment->>'id'));
    end loop;
   end if;
  end if;
  return private.gama_bank_match('apply',jsonb_build_object('request_key',md5('audit-match:'||key::text)::uuid,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',sources,'note',coalesce(p_data->>'note',reason)));
 elsif p_action='cashflow_class_save' then
  update public.accounting_accounts set cashflow_class=p_data->>'cashflow_class' where id=(p_data->>'account_id')::uuid;if not found then raise exception 'ACCOUNT_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 raise exception 'INVALID_ACTION';
end $$;

create function private.gama_accounting_audit(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.accounting_audit_commands;result jsonb;permission text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'INVALID_REQUEST';end if;
 if p_action in ('controls','context','statements','bank_choices','package','readiness','management','fx','assets') then
  if (p_action='package' or coalesce((p_data->>'export')::boolean,false)) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  return private.gama_accounting_audit_read(p_action,p_data);
 end if;
 permission:=case when p_action in ('statement_save','cashflow_class_save','dimension_save','budget_save','stock_accounting_save','readiness_save','line_dimensions_save','asset_policy_save') then 'edit' else 'validate' end;
 if not coalesce((rights->>permission)::boolean,false) or not private.erp_action_allowed('accounting',permission) then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting_audit:'||key::text,0));select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 result:=private.gama_accounting_audit_write(p_action,p_data);
 insert into private.accounting_audit_commands values(key,auth.uid(),p_action,p_data,result);
 insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data) values('accounting_audit',coalesce(result->>'entry_id',result->>'id',key::text),case when permission='validate' then 'VALIDATE' else 'UPDATE' end,auth.uid(),private.current_user_role(),jsonb_build_object('action',p_action,'request',p_data,'result',result));return result;
end $$;
create function public.gama_accounting_audit(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_audit(p_action,p_data)$$;
revoke all on function public.gama_accounting_audit(text,jsonb),private.gama_accounting_audit(text,jsonb) from public,anon;
grant execute on function public.gama_accounting_audit(text,jsonb),private.gama_accounting_audit(text,jsonb) to authenticated;
revoke all on function private.gama_accounting_audit_read(text,jsonb),private.gama_accounting_audit_write(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261011211512','accounting_audit_core','9055989e75934fc874fc17c2aa70b9a0ac1a72da2077a3de2468251d4c11831d','212b97b9c12b24b337b29e42c5306218f6c4fda19e34fc453c3f725bbf36f949','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261011213506_accounting_audit_extensions.sql; SHA256 68bf30b21b1770f3edcf1bad69c29eda0dc158440405e03306a53eca1ed4cd4b
-- Audit A08, A11, A13-A16. Opt-in configurations; no historical cost, FX rate or fiscal proof is invented.
create table private.accounting_dimensions(id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('cost_center','branch','product_family')),code text not null,name text not null,active boolean not null default true,unique(kind,code));
create table private.accounting_line_dimensions(line_id uuid not null references public.accounting_entry_lines(id),dimension_id uuid not null references private.accounting_dimensions(id),assigned_by uuid not null references auth.users(id),reason text not null,primary key(line_id,dimension_id));
create index accounting_dimension_line on private.accounting_line_dimensions(dimension_id);
create table private.accounting_budgets(id uuid primary key default gen_random_uuid(),period_start date not null,account_id uuid not null references public.accounting_accounts(id),dimension_id uuid references private.accounting_dimensions(id),amount numeric(18,2) not null check(amount>=0),updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),check(extract(day from period_start)=1));
create unique index accounting_budget_period on private.accounting_budgets(period_start,account_id,coalesce(dimension_id,'00000000-0000-0000-0000-000000000000'::uuid));
create index accounting_budget_account on private.accounting_budgets(account_id);
create index accounting_budget_dimension on private.accounting_budgets(dimension_id);
create table private.accounting_readiness(code text primary key check(code in ('sri_invoice','sri_credit','sri_withholding','sri_guide','ats_review','forms_review','ocr_review','collections_review','forecast_review','margin_review')),applicable boolean not null default true,verified boolean not null default false,evidence text not null check(length(btrim(evidence)) between 3 and 1000),verified_at timestamptz not null default now(),verified_by uuid not null references auth.users(id));
create table private.accounting_fx_documents(id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),invoice_id uuid not null,currency text not null check(currency~'^[A-Z]{3}$'),foreign_amount numeric(18,2) not null check(foreign_amount>0),historical_rate numeric(18,8) not null check(historical_rate>0),base_amount numeric(18,2) not null check(base_amount>0),rate_date date not null,evidence text not null,created_by uuid not null references auth.users(id),unique(side,invoice_id));
create table private.accounting_fx_settlements(id uuid primary key default gen_random_uuid(),document_id uuid not null references private.accounting_fx_documents(id),paid_on date not null,foreign_amount numeric(18,2) not null check(foreign_amount>0),rate numeric(18,8) not null check(rate>0),carrying_amount numeric(18,2) not null,bank_amount numeric(18,2) not null,payment_id uuid not null,adjustment_entry_id uuid references public.accounting_entries(id),financial_account_id uuid not null references public.financial_accounts(id),evidence text not null,created_by uuid not null references auth.users(id));
create index accounting_fx_settlement_doc on private.accounting_fx_settlements(document_id);
create index accounting_fx_settlement_entry on private.accounting_fx_settlements(adjustment_entry_id);
create index accounting_fx_settlement_bank on private.accounting_fx_settlements(financial_account_id);
create table private.accounting_asset_schedules(asset_id uuid not null references public.accounting_assets(id),period date not null,amount numeric(18,2) not null check(amount>=0),primary key(asset_id,period));
create table private.accounting_asset_events(id uuid primary key default gen_random_uuid(),asset_id uuid not null references public.accounting_assets(id),kind text not null check(kind in ('impairment','disposal')),entry_date date not null,amount numeric(18,2) not null,accumulated_account_id uuid references public.accounting_accounts(id),entry_id uuid not null references public.accounting_entries(id),reason text not null,created_by uuid not null references auth.users(id));
create index accounting_asset_event_asset on private.accounting_asset_events(asset_id);
create index accounting_asset_event_entry on private.accounting_asset_events(entry_id);
create index accounting_asset_event_account on private.accounting_asset_events(accumulated_account_id);
alter table private.accounting_asset_events add column proceeds_invoice_id uuid references public.external_invoices(id);
create unique index accounting_asset_sale_invoice on private.accounting_asset_events(proceeds_invoice_id) where proceeds_invoice_id is not null;
do $$declare t text;begin foreach t in array array['accounting_dimensions','accounting_line_dimensions','accounting_budgets','accounting_readiness','accounting_fx_documents','accounting_fx_settlements','accounting_asset_schedules','accounting_asset_events'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);end loop;end $$;
alter table public.stock_cost_books add column auto_accounting boolean not null default false,
 add column receipt_account_id uuid references public.accounting_accounts(id),add column opening_counter_account_id uuid references public.accounting_accounts(id);
create index stock_cost_receipt_account on public.stock_cost_books(receipt_account_id);
create index stock_cost_opening_account on public.stock_cost_books(opening_counter_account_id);

-- Posted valuation mappings are historical metadata, including through the older accounts RPC.
create function private.gama_stock_mapping_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (new.stock_account_id,new.expense_account_id,new.receipt_account_id,new.opening_counter_account_id) is distinct from
    (old.stock_account_id,old.expense_account_id,old.receipt_account_id,old.opening_counter_account_id)
 and exists(select 1 from public.stock_valuation_entries v join public.accounting_source_links l on l.source_type='stock_valuation' and l.source_id=v.sequence::text where v.product_id=old.product_id) then raise exception 'STOCK_MAPPING_LOCKED';end if;
 if old.auto_accounting and not new.auto_accounting then raise exception 'STOCK_AUTOMATION_LOCKED';end if;return new;
end $$;
create trigger accounting_stock_mapping_guard before update on public.stock_cost_books for each row execute function private.gama_stock_mapping_guard();
-- A supplier return reduces receipts, not cost of goods sold.
do $$declare s text;begin
 s:=pg_get_functiondef('private.erp_cost_post(public.stock_movements)'::regprocedure);
 if strpos(s,'case when kind=''out'' then -v')=0 then raise exception 'STOCK_RETURN_COST_ANCHOR_MISSING';end if;
 s:=replace(s,'case when kind=''out'' then -v','case when m.reference_type=''supplier_return'' then 0 when kind=''out'' then -v');execute s;
end $$;

create function private.gama_stock_accounting_post(p_sequence bigint) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.stock_valuation_entries;b public.stock_cost_books;eid uuid;lines jsonb;value numeric;expense numeric;counter uuid;movement public.stock_movements;begin
 select * into v from public.stock_valuation_entries where sequence=p_sequence for update;
 select * into b from public.stock_cost_books where product_id=v.product_id;
 if not b.auto_accounting or v.kind in ('method','transfer') then return null;end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_valuation' and source_id=v.sequence::text) then return null;end if;
 perform private.gama_ec_account(b.stock_account_id,'asset');perform private.gama_ec_account(b.expense_account_id,'expense');
 value:=round(v.value_delta,2);expense:=round(v.expense_delta,2);if value=0 and expense=0 then return null;end if;
 select * into movement from public.stock_movements where id=v.movement_id;
 if v.kind='out' then
  counter:=case when movement.reference_type='supplier_return' then private.gama_ec_account(b.receipt_account_id,'liability') else b.expense_account_id end;
  lines:=jsonb_build_array(jsonb_build_object('account_id',b.stock_account_id,'credit',-value),jsonb_build_object('account_id',counter,'debit',-value));
 elsif v.kind in ('opening','in') then
  counter:=private.gama_ec_account(case when v.kind='opening' then b.opening_counter_account_id when movement.reference_type='customer_return' then b.expense_account_id else b.receipt_account_id end,case when v.kind='opening' then 'equity' when movement.reference_type='customer_return' then 'expense' else 'liability' end);
  lines:=jsonb_build_array(jsonb_build_object('account_id',b.stock_account_id,'debit',greatest(value,0),'credit',greatest(-value,0)),jsonb_build_object('account_id',counter,'credit',greatest(value,0),'debit',greatest(-value,0)));
 else return null;end if;
 eid:=private.gama_accounting_book('OD',(v.created_at at time zone private.erp_timezone())::date,'STOCK-'||v.sequence,'stock_valuation',gen_random_uuid(),'Valoración automática configurada',lines);
 insert into public.accounting_source_links(source_type,source_id,entry_id) values('stock_valuation',v.sequence::text,eid);return eid;
end $$;
create function private.gama_stock_accounting_trigger() returns trigger language plpgsql security definer set search_path='' as $$begin perform private.gama_stock_accounting_post(new.sequence);return new;end $$;
create trigger accounting_stock_auto after insert on public.stock_valuation_entries for each row execute function private.gama_stock_accounting_trigger();

-- Clear GRNI against the existing supplier bill instead of recording its purchase expense twice.
create function private.gama_stock_invoice_reclass(p_invoice uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.supplier_invoices;cfg public.company_settings;counter uuid;eid uuid;net numeric;received numeric;already numeric;begin
 select * into b from public.supplier_invoices where id=p_invoice;
 if b.purchase_order_id is null or b.status<>'posted' then return null;end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_invoice' and source_id=b.id::text) then return null;end if;
 if not exists(select 1 from public.stock_movements m join public.stock_cost_books c on c.product_id=m.product_id where m.reference_type='purchase_order' and m.reference_id=b.purchase_order_id and c.auto_accounting) then return null;end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-invoice:'||b.purchase_order_id::text,0));
 if exists(select 1 from public.purchase_order_lines l left join public.stock_cost_books c on c.product_id=l.product_id where l.purchase_order_id=b.purchase_order_id and (c.product_id is null or not c.auto_accounting)) then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select count(distinct c.receipt_account_id),min(c.receipt_account_id::text)::uuid into net,counter from public.stock_movements m join public.stock_cost_books c on c.product_id=m.product_id where m.reference_type='purchase_order' and m.reference_id=b.purchase_order_id;
 if net<>1 then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select coalesce(sum(v.value_delta),0) into received from public.stock_valuation_entries v join public.stock_movements m on m.id=v.movement_id where m.reference_type='purchase_order' and m.reference_id=b.purchase_order_id and v.kind='in';
 select coalesce(sum(s.total-s.tax),0) into already from public.supplier_invoices s join public.accounting_source_links l on l.source_type='stock_invoice' and l.source_id=s.id::text where s.purchase_order_id=b.purchase_order_id;
 net:=b.total-b.tax;if net>round(received,2)-already then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select * into cfg from public.company_settings where id;
 eid:=private.gama_accounting_book('CMP',b.issue_date,b.number,'stock_valuation',gen_random_uuid(),'Factura de stock · compensación recibido no facturado',jsonb_build_array(jsonb_build_object('account_id',counter,'debit',net),jsonb_build_object('account_id',cfg.purchase_account_id,'credit',net)));
 insert into public.accounting_source_links values('stock_invoice',b.id::text,eid);return eid;
end $$;
create function private.gama_stock_credit_reclass(p_credit uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare k public.return_credits;cfg public.company_settings;counter uuid;n integer;net numeric;eid uuid;begin
 select * into k from public.return_credits where id=p_credit;
 if not exists(select 1 from public.accounting_source_links where source_type='stock_invoice' and source_id=k.supplier_invoice_id::text) then return null;end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_credit' and source_id=k.id::text) then return null;end if;
 select count(distinct c.receipt_account_id),min(c.receipt_account_id::text)::uuid into n,counter from public.stock_movements m join public.stock_cost_books c on c.product_id=m.product_id where m.reference_type='supplier_return' and m.reference_id=k.return_id and c.auto_accounting;
 if n<>1 then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select * into cfg from public.company_settings where id;net:=(private.gama_return_split(k.return_id,k.amount)->>'net')::numeric;
 eid:=private.gama_accounting_book('CMP',k.issued_on,k.number,'stock_valuation',gen_random_uuid(),'Abono de stock · compensación recibido no facturado',jsonb_build_array(jsonb_build_object('account_id',cfg.purchase_account_id,'debit',net),jsonb_build_object('account_id',counter,'credit',net)));
 insert into public.accounting_source_links values('stock_credit',k.id::text,eid);return eid;
end $$;
alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_stock;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid;begin
 eid:=private.gama_accounting_post_before_stock(p_source_type,p_source_id);if p_source_type='supplier_invoice' and eid is not null then perform private.gama_stock_invoice_reclass(p_source_id);elsif p_source_type='supplier_credit' and eid is not null then perform private.gama_stock_credit_reclass(p_source_id);end if;return eid;
end $$;

alter function private.gama_accounting_audit_read(text,jsonb) rename to gama_accounting_audit_read_base;
create function private.gama_accounting_audit_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);dim uuid:=nullif(p_data->>'dimension_id','')::uuid;
 result jsonb;rows jsonb;cfg public.company_settings;p public.accounting_ec_profile;s public.sri_settings;revenue numeric;receivables numeric;stock0 numeric;stock1 numeric;cogs numeric;begin
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 select * into cfg from public.company_settings where id;
 if p_action='context' then return private.gama_accounting_audit_read_base(p_action,p_data)||jsonb_build_object('dimensions',coalesce((select jsonb_agg(to_jsonb(x) order by kind,code) from private.accounting_dimensions x),'[]'),
  'stock_books',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('name',prod.name)) from public.stock_cost_books c join public.products prod on prod.id=c.product_id),'[]'),
  'stock_products',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,purchase_price from public.products where product_kind='goods' order by name limit 1000)x),'[]'));
 elsif p_action='readiness' then
  select * into p from public.accounting_ec_profile where id;select * into s from public.sri_settings where user_id=auth.uid();
  return jsonb_build_object('checks',jsonb_build_array(
   jsonb_build_object('code','identity','ok',coalesce(cfg.tax_id~'^[0-9]{13}$' and length(btrim(cfg.legal_name))>0 and length(btrim(cfg.address))>0,false)),
   jsonb_build_object('code','fiscal_profile','ok',coalesce(p.regime<>'unconfigured' and p.confirmed_on is not null and p.accounting_required is not null and p.ats_required is not null and p.withholding_agent is not null,false)),
   jsonb_build_object('code','ledger_accounts','ok',cfg.receivable_account_id is not null and cfg.payable_account_id is not null and cfg.sales_account_id is not null and cfg.purchase_account_id is not null and cfg.tax_collected_account_id is not null and cfg.tax_deductible_account_id is not null),
   jsonb_build_object('code','sri_configuration','ok',coalesce(s.provider_ruc is not null and s.environment='pruebas' and s.accounting_obligation is not null,false)),
   jsonb_build_object('code','source_coverage','ok',(private.gama_accounting_controls(d1,d2)->>'can_close')::boolean)),
   'records',coalesce((select jsonb_agg(to_jsonb(r)-'verified_by' order by code) from private.accounting_readiness r),'[]'),
   'sri_test_authorizations',(select count(*) from public.sri_invoice_issues where status='authorized' and environment='pruebas'),
   'ocr_reviewed',(select count(*) from private.supplier_ocr_intakes where state='draft'),
   'collections_rules',(select count(*) from private.collection_holds),
   'cash_scenarios',(select count(*) from private.cash_scenarios),'fiscal_submission',false);
 elsif p_action='management' then
  with actual as(select date_trunc('month',e.entry_date)::date period_start,l.account_id,
   sum(case when a.type='income' then l.credit-l.debit else l.debit-l.credit end) amount from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in ('posted','reversed') and e.source_type<>'year_close' and a.type in ('income','expense') and e.entry_date between d1 and d2
   and (dim is null or exists(select 1 from private.accounting_line_dimensions ld where ld.line_id=l.id and ld.dimension_id=dim)) group by 1,l.account_id),
  budget as(select period_start,account_id,sum(amount) amount from private.accounting_budgets where period_start between date_trunc('month',d1)::date and d2 and dimension_id is not distinct from dim group by period_start,account_id),
  merged as(select coalesce(a.period_start,b.period_start) period_start,coalesce(a.account_id,b.account_id) account_id,coalesce(a.amount,0) actual,coalesce(b.amount,0) budget from actual a full join budget b using(period_start,account_id))
  select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('code',a.code,'name',a.name,'type',a.type,'variance',m.actual-m.budget) order by period_start,a.code),'[]') into rows from merged m join public.accounting_accounts a on a.id=m.account_id;
  select coalesce(sum(l.credit-l.debit),0) into revenue from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=cfg.sales_account_id and e.status in ('posted','reversed') and e.source_type<>'year_close' and e.entry_date between d1 and d2;
  select coalesce(sum(l.debit-l.credit),0) into receivables from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=cfg.receivable_account_id and e.status in ('posted','reversed') and e.entry_date<=d2;
  select coalesce(sum(value_delta) filter(where (created_at at time zone private.erp_timezone())::date<d1),0),coalesce(sum(value_delta),0),coalesce(sum(expense_delta) filter(where (created_at at time zone private.erp_timezone())::date between d1 and d2),0) into stock0,stock1,cogs from public.stock_valuation_entries where (created_at at time zone private.erp_timezone())::date<=d2;
  return jsonb_build_object('from',d1,'to',d2,'rows',rows,'dso',case when revenue>0 then round(greatest(receivables,0)/revenue*(d2-d1+1),2) end,'dso_method','Closing trade receivables / net sales during period × days',
   'stock_rotation',case when stock0+stock1>0 then round(cogs/((stock0+stock1)/2),3) end,'rotation_method','Valued consumption / mean of opening and closing valued stock',
   'missing_costs',(select count(*) from public.products where product_kind='goods' and coalesce(purchase_price,0)<=0),'budget_partial_period',extract(day from d1)<>1 or d2<>(date_trunc('month',d2)+interval '1 month - 1 day')::date);
 elsif p_action='fx' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('foreign_paid',coalesce((select sum(foreign_amount) from private.accounting_fx_settlements where document_id=f.id),0),'settlements',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by paid_on) from private.accounting_fx_settlements x where document_id=f.id),'[]'))) from private.accounting_fx_documents f),'[]'),'currency',cfg.currency);
 elsif p_action='assets' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('depreciated',coalesce((select sum(amount) from public.accounting_depreciations where asset_id=a.id),0),'impaired',coalesce((select sum(amount) from private.accounting_asset_events where asset_id=a.id and kind='impairment'),0),
   'schedule',coalesce((select jsonb_agg(to_jsonb(schedule) order by period) from private.accounting_asset_schedules schedule where asset_id=a.id),'[]'),'events',coalesce((select jsonb_agg(to_jsonb(ev)-'created_by' order by entry_date) from private.accounting_asset_events ev where asset_id=a.id),'[]'))) from public.accounting_assets a),'[]'));
 end if;
 return private.gama_accounting_audit_read_base(p_action,p_data);
end $$;

alter function private.gama_accounting_audit_write(text,jsonb) rename to gama_accounting_audit_write_base;
create function private.gama_accounting_audit_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare cfg public.company_settings;key uuid:=(p_data->>'request_key')::uuid;rid uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());aid uuid;counter uuid;eid uuid;
 amount numeric;total numeric;rate numeric;carrying numeric;paid numeric;bank_amount numeric;delta numeric;gain uuid;loss uuid;fid uuid;foreign_currency text;invoice record;f private.accounting_fx_documents;a public.accounting_assets;depreciated numeric;impaired numeric;nbv numeric;lines jsonb;payment jsonb;receipt jsonb;x record;vat numeric;proceeds_invoice uuid;
 period date;first_factor numeric;weight numeric;remaining numeric;n integer;i integer;prorata boolean;reason text:=btrim(coalesce(p_data->>'reason',''));begin
 select * into cfg from public.company_settings where id;
 if p_action='dimension_save' then
  insert into private.accounting_dimensions(id,kind,code,name,active) values(rid,p_data->>'kind',btrim(p_data->>'code'),btrim(p_data->>'name'),coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set code=excluded.code,name=excluded.name,active=excluded.active;return jsonb_build_object('id',rid);
 elsif p_action='line_dimensions_save' then
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  if not exists(select 1 from public.accounting_entry_lines where id=(p_data->>'line_id')::uuid) then raise exception 'ENTRY_NOT_FOUND';end if;
  if exists(select 1 from jsonb_array_elements_text(p_data->'dimensions')v left join private.accounting_dimensions d on d.id=v::uuid where d.id is null or not d.active) or
   (select count(distinct d.kind) from jsonb_array_elements_text(p_data->'dimensions')v join private.accounting_dimensions d on d.id=v::uuid)<>jsonb_array_length(p_data->'dimensions') then raise exception 'ONE_DIMENSION_PER_KIND';end if;
  delete from private.accounting_line_dimensions where line_id=(p_data->>'line_id')::uuid;
  insert into private.accounting_line_dimensions select (p_data->>'line_id')::uuid,v::uuid,auth.uid(),reason from jsonb_array_elements_text(p_data->'dimensions')v;return jsonb_build_object('ok',true);
 elsif p_action='budget_save' then
  aid:=private.gama_ec_account((p_data->>'account_id')::uuid);if not exists(select 1 from public.accounting_accounts where id=aid and type in ('income','expense')) then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
  insert into private.accounting_budgets(period_start,account_id,dimension_id,amount,updated_by) values((p_data->>'period_start')::date,aid,nullif(p_data->>'dimension_id','')::uuid,(p_data->>'amount')::numeric,auth.uid())
  on conflict(period_start,account_id,(coalesce(dimension_id,'00000000-0000-0000-0000-000000000000'::uuid))) do update set amount=excluded.amount,updated_by=auth.uid(),updated_at=now();return jsonb_build_object('ok',true);
 elsif p_action='readiness_save' then
  insert into private.accounting_readiness(code,applicable,verified,evidence,verified_by) values(p_data->>'code',coalesce((p_data->>'applicable')::boolean,true),coalesce((p_data->>'verified')::boolean,false),p_data->>'evidence',auth.uid())
  on conflict(code) do update set applicable=excluded.applicable,verified=excluded.verified,evidence=excluded.evidence,verified_at=now(),verified_by=auth.uid();return jsonb_build_object('ok',true);
 elsif p_action='stock_accounting_save' then
  if not private.gama_accounting_may('validate') or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
  aid:=private.gama_ec_account((p_data->>'stock_account_id')::uuid,'asset');counter:=private.gama_ec_account((p_data->>'receipt_account_id')::uuid,'liability');
  perform private.gama_ec_account((p_data->>'expense_account_id')::uuid,'expense');perform private.gama_ec_account((p_data->>'opening_counter_account_id')::uuid,'equity');
  update public.stock_cost_books set stock_account_id=aid,expense_account_id=(p_data->>'expense_account_id')::uuid,receipt_account_id=counter,opening_counter_account_id=(p_data->>'opening_counter_account_id')::uuid,auto_accounting=coalesce((p_data->>'auto_accounting')::boolean,false) where product_id=(p_data->>'product_id')::uuid;
  if not found then raise exception 'VALUATION_NOT_CONFIGURED';end if;
  for x in select sequence from public.stock_valuation_entries where product_id=(p_data->>'product_id')::uuid order by sequence loop perform private.gama_stock_accounting_post(x.sequence);end loop;return jsonb_build_object('ok',true);
 elsif p_action='fx_register' then
  if length(btrim(coalesce(p_data->>'evidence','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if p_data->>'side'='supplier' then select * into invoice from private.gama_payables where id=(p_data->>'invoice_id')::uuid and status='posted';else select * into invoice from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and payment_status<>'cancelled';end if;
  if not found or invoice.paid<>0 or invoice.balance<>invoice.total then raise exception 'FX_UNPAID_INVOICE_REQUIRED';end if;
  amount:=(p_data->>'foreign_amount')::numeric;rate:=(p_data->>'historical_rate')::numeric;foreign_currency:=upper(p_data->>'currency');
  if foreign_currency=cfg.currency or amount is null or rate is null or amount<=0 or rate<=0 or amount::text in ('NaN','Infinity','-Infinity') or rate::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or rate<>round(rate,8) or round(amount*rate,2)<>invoice.total then raise exception 'FX_BASE_AMOUNT_MISMATCH';end if;
  insert into private.accounting_fx_documents(id,side,invoice_id,currency,foreign_amount,historical_rate,base_amount,rate_date,evidence,created_by) values(rid,p_data->>'side',invoice.id,foreign_currency,amount,rate,invoice.total,(p_data->>'rate_date')::date,p_data->>'evidence',auth.uid());return jsonb_build_object('id',rid);
 elsif p_action='fx_pay' then
  if not private.gama_accounting_may('create') or not private.gama_accounting_may('pay') then raise exception 'PAYMENT_NOT_ALLOWED';end if;
  fid:=(p_data->>'financial_account_id')::uuid;perform pg_advisory_xact_lock(hashtextextended('bank-match:'||fid::text,0));
  select * into f from private.accounting_fx_documents where id=(p_data->>'id')::uuid for update;if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
  aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=fid and active and currency=cfg.currency),'asset');
  amount:=(p_data->>'foreign_amount')::numeric;rate:=(p_data->>'rate')::numeric;if amount is null or rate is null or amount<=0 or rate<=0 or amount::text in ('NaN','Infinity','-Infinity') or rate::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or rate<>round(rate,8) or length(btrim(coalesce(p_data->>'evidence','')))<3 or (p_data->>'paid_on')::date<f.rate_date then raise exception 'INVALID_AMOUNT';end if;
  select coalesce(sum(foreign_amount),0),coalesce(sum(carrying_amount),0) into paid,total from private.accounting_fx_settlements where document_id=f.id;
  if amount>f.foreign_amount-paid then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
  carrying:=case when amount=f.foreign_amount-paid then f.base_amount-total else round(amount*f.historical_rate,2) end;bank_amount:=round(amount*rate,2);
  if f.side='supplier' then
   perform 1 from public.supplier_invoices where id=f.invoice_id for update;select * into invoice from private.gama_payables where id=f.invoice_id;
   if invoice.paid<>total then raise exception 'FX_PAYMENT_REVIEW_REQUIRED';end if;
   payment:=private.gama_accounting_action('supplier_payment',jsonb_build_object('request_key',key,'supplier_invoice_id',f.invoice_id,'financial_account_id',fid,'amount',carrying,'paid_at',p_data->>'paid_on','method','transfer','reference',coalesce(nullif(p_data->>'reference',''),invoice.number)));
  else
   perform 1 from public.external_invoices where id=f.invoice_id for update;select * into invoice from private.gama_receivables where id=f.invoice_id;
   if invoice.paid<>total then raise exception 'FX_PAYMENT_REVIEW_REQUIRED';end if;
   receipt:=private.gama_receipt_action('receive',jsonb_build_object('request_key',key,'customer_id',invoice.customer_id,'financial_account_id',fid,'amount',carrying,'paid_at',p_data->>'paid_on','method','transfer','reference',coalesce(nullif(p_data->>'reference',''),invoice.number)));
   payment:=private.gama_receipt_action('allocate',jsonb_build_object('request_key',md5('fx-allocate:'||key::text)::uuid,'id',receipt->>'id','invoice_id',f.invoice_id,'amount',carrying));
  end if;
  delta:=case when f.side='supplier' then carrying-bank_amount else bank_amount-carrying end;
  if delta<>0 then
   counter:=private.gama_ec_account(case when delta>0 then (p_data->>'gain_account_id')::uuid else (p_data->>'loss_account_id')::uuid end,case when delta>0 then 'income' else 'expense' end);
   eid:=private.gama_accounting_book('BAN',(p_data->>'paid_on')::date,p_data->>'reference','manual',null,'Diferencia de cambio · '||f.currency,jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'debit',greatest(delta,0),'credit',greatest(-delta,0)),jsonb_build_object('account_id',counter,'credit',greatest(delta,0),'debit',greatest(-delta,0))));
  end if;
  insert into private.accounting_fx_settlements(document_id,paid_on,foreign_amount,rate,carrying_amount,bank_amount,payment_id,adjustment_entry_id,financial_account_id,evidence,created_by)
  values(f.id,(p_data->>'paid_on')::date,amount,rate,carrying,bank_amount,(payment->>'id')::uuid,eid,fid,p_data->>'evidence',auth.uid());return jsonb_build_object('id',f.id,'entry_id',eid,'bank_amount',bank_amount,'carrying_amount',carrying,'exchange_difference',delta);
 elsif p_action in ('asset_policy_save','asset_depreciate','asset_impair','asset_dispose') then
  select * into a from public.accounting_assets where id=(p_data->>'id')::uuid and status='active' for update;if not found then raise exception 'ASSET_REQUIRED';end if;
  select coalesce(sum(d.amount),0) into depreciated from public.accounting_depreciations d where asset_id=a.id;
  select coalesce(sum(ev.amount),0) into impaired from private.accounting_asset_events ev where asset_id=a.id and kind='impairment';nbv:=a.cost-depreciated-impaired;
  if p_action='asset_policy_save' then
   if depreciated>0 then raise exception 'ASSET_SCHEDULE_LOCKED';end if;
   prorata:=coalesce((p_data->>'prorata')::boolean,false);first_factor:=1;
   if prorata and date_trunc('month',a.acquired_on)=date_trunc('month',a.first_depreciation) then first_factor:=((date_trunc('month',a.acquired_on)+interval '1 month')::date-a.acquired_on)::numeric/extract(day from (date_trunc('month',a.acquired_on)+interval '1 month - 1 day'));end if;
   n:=a.months+case when first_factor<1 then 1 else 0 end;remaining:=a.cost-a.residual-impaired;
   delete from private.accounting_asset_schedules where asset_id=a.id;
   for i in 0..n-1 loop
    period:=(date_trunc('month',a.first_depreciation)+make_interval(months=>i+1)-interval '1 day')::date;
    weight:=case when i=0 then first_factor when i=n-1 and first_factor<1 then 1-first_factor else 1 end;
    amount:=case when i=n-1 then remaining else round((a.cost-a.residual-impaired)/a.months*weight,2) end;remaining:=remaining-amount;
    insert into private.accounting_asset_schedules values(a.id,period,amount);
   end loop;return jsonb_build_object('id',a.id,'periods',n);
  elsif p_action='asset_depreciate' then
   period:=(p_data->>'period')::date;select s.amount into amount from private.accounting_asset_schedules s where asset_id=a.id and s.period=period;
   if not found then return private.gama_accounting_ec('depreciation_post',p_data);end if;
   if exists(select 1 from public.accounting_depreciations where asset_id=a.id and accounting_depreciations.period=period) then raise exception 'DEPRECIATION_ALREADY_POSTED';end if;
   if exists(select 1 from private.accounting_asset_schedules s where asset_id=a.id and s.period<period and s.amount>0 and not exists(select 1 from public.accounting_depreciations d where d.asset_id=a.id and d.period=s.period)) then raise exception 'DEPRECIATION_PREVIOUS_PERIOD_REQUIRED';end if;
   amount:=least(amount,greatest(nbv-a.residual,0));if amount<=0 then raise exception 'ENTRY_EMPTY';end if;
   eid:=private.gama_accounting_book('OD',period,a.name,'depreciation',gen_random_uuid(),'Amortización según plan aprobado',jsonb_build_array(jsonb_build_object('account_id',a.expense_account_id,'debit',amount),jsonb_build_object('account_id',a.depreciation_account_id,'credit',amount)));
   insert into public.accounting_depreciations(asset_id,period,amount,entry_id) values(a.id,period,amount,eid);return jsonb_build_object('entry_id',eid,'amount',amount);
  end if;
  if length(reason)<3 or (p_data->>'entry_date')::date<a.acquired_on or exists(select 1 from public.accounting_depreciations where asset_id=a.id and accounting_depreciations.period>(p_data->>'entry_date')::date) then raise exception 'ASSET_EVENT_DATE_INVALID';end if;
  counter:=private.gama_ec_account((p_data->>'loss_account_id')::uuid,'expense');
  if p_action='asset_impair' then
   amount:=(p_data->>'amount')::numeric;if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or amount>greatest(nbv-a.residual,0) then raise exception 'ASSET_IMPAIRMENT_EXCEEDED';end if;
   aid:=private.gama_ec_account((p_data->>'accumulated_account_id')::uuid,'asset');if aid=a.asset_account_id or aid=a.depreciation_account_id then raise exception 'ASSET_IMPAIRMENT_ACCOUNT_DISTINCT';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',counter,'debit',amount),jsonb_build_object('account_id',aid,'credit',amount));
   eid:=private.gama_accounting_book('OD',(p_data->>'entry_date')::date,a.name,'manual',null,reason,lines);
   insert into private.accounting_asset_events(asset_id,kind,entry_date,amount,accumulated_account_id,entry_id,reason,created_by) values(a.id,'impairment',(p_data->>'entry_date')::date,amount,aid,eid,reason,auth.uid());
   -- Reduce the unposted schedule proportionally; put rounding on its last period.
   select sum(s.amount) into total from private.accounting_asset_schedules s where asset_id=a.id and not exists(select 1 from public.accounting_depreciations d where d.asset_id=a.id and d.period=s.period);
   remaining:=greatest(nbv-a.residual-amount,0);
   for x in select s.* from private.accounting_asset_schedules s where asset_id=a.id and not exists(select 1 from public.accounting_depreciations d where d.asset_id=a.id and d.period=s.period) order by period loop
    amount:=case when x.period=(select max(s.period) from private.accounting_asset_schedules s where asset_id=a.id) then remaining else round(x.amount/nullif(total,0)*(nbv-a.residual-(p_data->>'amount')::numeric),2) end;remaining:=remaining-amount;
    update private.accounting_asset_schedules set amount=amount where asset_id=a.id and accounting_asset_schedules.period=x.period;
   end loop;return jsonb_build_object('entry_id',eid);
  else
   amount:=coalesce((p_data->>'proceeds')::numeric,0);vat:=coalesce(nullif(p_data->>'vat','')::numeric,0);proceeds_invoice:=nullif(p_data->>'proceeds_invoice_id','')::uuid;
   if amount<0 or vat<0 or amount::text in ('NaN','Infinity','-Infinity') or vat::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or vat<>round(vat,2) or (amount=0 and vat<>0) then raise exception 'INVALID_AMOUNT';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',a.asset_account_id,'credit',a.cost),jsonb_build_object('account_id',a.depreciation_account_id,'debit',depreciated));
   for x in select accumulated_account_id,sum(accounting_asset_events.amount) amount from private.accounting_asset_events where asset_id=a.id and kind='impairment' group by accumulated_account_id loop lines:=lines||jsonb_build_array(jsonb_build_object('account_id',x.accumulated_account_id,'debit',x.amount));end loop;
   if proceeds_invoice is not null then
    select * into invoice from public.external_invoices where id=proceeds_invoice for update;
    if not found or invoice.fiscal_status in ('cancelled','rejected') or invoice.total-invoice.tax<>amount or invoice.tax<>vat or invoice.issue_date<>(p_data->>'entry_date')::date or not exists(select 1 from public.accounting_entries where source_type='sales_invoice' and source_id=invoice.id and status='posted') or exists(select 1 from private.accounting_asset_events ev where ev.proceeds_invoice_id=invoice.id) then raise exception 'ASSET_DISPOSAL_INVOICE_INVALID';end if;
    aid:=private.gama_ec_account(cfg.sales_account_id,'income');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',aid,'debit',amount));
   elsif amount>0 then
    fid:=(p_data->>'financial_account_id')::uuid;aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=fid and active and currency=cfg.currency),'asset');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'debit',amount+vat));
    if vat>0 then perform private.gama_ec_account(cfg.tax_collected_account_id,'liability');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.tax_collected_account_id,'credit',vat));end if;
   end if;
   if amount>nbv then gain:=private.gama_ec_account((p_data->>'gain_account_id')::uuid,'income');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',gain,'credit',amount-nbv));else lines:=lines||jsonb_build_array(jsonb_build_object('account_id',counter,'debit',nbv-amount));end if;
   eid:=private.gama_accounting_book('OD',(p_data->>'entry_date')::date,a.name,'manual',null,reason,lines);
   insert into private.accounting_asset_events(asset_id,kind,entry_date,amount,entry_id,reason,created_by,proceeds_invoice_id) values(a.id,'disposal',(p_data->>'entry_date')::date,nbv,eid,reason,auth.uid(),proceeds_invoice);update public.accounting_assets set status='disposed' where id=a.id;return jsonb_build_object('entry_id',eid);
  end if;
 end if;
 return private.gama_accounting_audit_write_base(p_action,p_data);
end $$;
-- Cash flow also recognizes a disposal already invoiced, including allocations from a grouped receipt.
create function private.gama_accounting_cashflow(p_from date,p_to date) returns jsonb language sql stable security definer set search_path='' as $$
with cash as(select entry_id,sum(amount) amount from private.gama_cash_ledger where entry_date between p_from and p_to group by entry_id having sum(amount)<>0),
meta as(select c.*,e.entry_date,coalesce(original.source_type,e.source_type) source_type,coalesce(original.source_id,e.source_id) source_id,
 coalesce(original.id,e.id) original_id from cash c join public.accounting_entries e on e.id=c.entry_id left join public.accounting_entries original on original.id=e.reversal_of),
special as(select m.*,case
 when exists(select 1 from private.accounting_asset_events ev where ev.kind='disposal' and ev.entry_id=m.original_id) then m.amount
 when m.source_type='customer_payment' and exists(select 1 from public.external_invoice_payments p join private.accounting_asset_events ev on ev.proceeds_invoice_id=p.invoice_id where p.id=m.source_id) then m.amount
 when m.source_type='customer_receipt' then sign(m.amount)*least(abs(m.amount),coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=m.source_id and exists(select 1 from private.accounting_asset_events ev where ev.proceeds_invoice_id=p.invoice_id)),0))
 else null end investing_amount from meta m),
classified as(select entry_date,'investing' category,investing_amount amount from special where investing_amount is not null
 union all select entry_date,'operating',amount-investing_amount from special where investing_amount is not null
 union all select s.entry_date,case when exists(select 1 from public.accounting_assets where asset_account_id=l.account_id) then 'investing' else a.cashflow_class end,l.credit-l.debit
 from special s join public.accounting_entry_lines l on l.entry_id=s.entry_id join public.accounting_accounts a on a.id=l.account_id where s.investing_amount is null and not exists(select 1 from public.financial_accounts f where f.account_id=l.account_id)),
classes as(select to_char(entry_date,'YYYY-MM') period_month,sum(amount) net,sum(amount) filter(where category='operating') operating,sum(amount) filter(where category='investing') investing,sum(amount) filter(where category='financing') financing from classified group by 1),
gross as(select to_char(entry_date,'YYYY-MM') period_month,sum(greatest(amount,0)) incoming,sum(greatest(-amount,0)) outgoing from meta group by 1),
balances as(select coalesce(sum(amount) filter(where entry_date<p_from),0) opening,coalesce(sum(amount),0) closing from private.gama_cash_ledger where entry_date<=p_to)
select jsonb_build_object('from',p_from,'to',p_to,'opening',b.opening,'balance',b.closing,'net',b.closing-b.opening,'basis','ledger',
 'rows',coalesce((select jsonb_agg(jsonb_build_object('month',c.period_month,'in',g.incoming,'out',g.outgoing,'net',c.net,'operating',coalesce(c.operating,0),'investing',coalesce(c.investing,0),'financing',coalesce(c.financing,0)) order by c.period_month) from classes c join gross g using(period_month)),'[]')) from balances b;
$$;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure);
 s:=replace(s,'elsif p_action=''report_cashflow'' then','elsif p_action=''report_cashflow'' then return private.gama_accounting_cashflow(d1,d2);');execute s;
end $$;

-- Route the historical depreciation endpoint through the approved schedule too.
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_before_schedule;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare review jsonb;result jsonb;p public.accounting_periods;d date;begin
 if p_action='depreciation_post' and exists(select 1 from private.accounting_asset_schedules where asset_id=(p_data->>'id')::uuid) then return private.gama_accounting_audit_write('asset_depreciate',p_data);end if;
 if p_action='year_close' then
  if (p_data->>'from')::date is null or (p_data->>'to')::date is null or (p_data->>'from')::date>(p_data->>'to')::date then raise exception 'INVALID_FISCAL_YEAR';end if;
  for d in select generate_series((p_data->>'from')::date,(p_data->>'to')::date,interval '1 month')::date loop p:=private.gama_accounting_period(d);perform 1 from public.accounting_periods where id=p.id for update;end loop;
  review:=private.gama_accounting_controls((p_data->>'from')::date,(p_data->>'to')::date);
  if not (review->>'can_close')::boolean then raise exception 'CLOSURE_BLOCKED';end if;
  if exists(select 1 from jsonb_array_elements(review->'checks')c where not(c->>'blocking')::boolean and (c->>'count')::integer>0) and length(btrim(coalesce(p_data->>'exceptions','')))<3 then raise exception 'CLOSURE_EXCEPTION_REQUIRED';end if;
  result:=private.gama_accounting_ec_write_before_schedule(p_action,p_data);
  insert into private.accounting_closure_reviews(period_id,reviewed_by,review,exceptions) select id,auth.uid(),review,nullif(p_data->>'exceptions','') from public.accounting_periods where period_start between (p_data->>'from')::date and (p_data->>'to')::date;return result;
 end if;
 return private.gama_accounting_ec_write_before_schedule(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_cashflow(date,date),private.gama_stock_mapping_guard(),private.gama_stock_accounting_post(bigint),private.gama_stock_accounting_trigger(),private.gama_stock_invoice_reclass(uuid),private.gama_stock_credit_reclass(uuid),private.gama_accounting_post_before_stock(text,uuid),private.gama_accounting_post(text,uuid),
 private.gama_accounting_audit_read_base(text,jsonb),private.gama_accounting_audit_read(text,jsonb),private.gama_accounting_audit_write_base(text,jsonb),private.gama_accounting_audit_write(text,jsonb),private.gama_accounting_ec_write_before_schedule(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261011213506','accounting_audit_extensions','68bf30b21b1770f3edcf1bad69c29eda0dc158440405e03306a53eca1ed4cd4b','68bf30b21b1770f3edcf1bad69c29eda0dc158440405e03306a53eca1ed4cd4b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261011214628_accounting_return_recovery.sql; SHA256 b013f3bd2404f6be1578671dd58ce91a9c54887009702e7097cb62a87ced677e
-- Direct refunds reverse sales/tax; refunds following a credit clear that credit.
-- Original source dates and posted journals are retained during recovery.
create function private.gama_accounting_refund_post(p_id uuid,p_date date) returns uuid
language plpgsql security definer set search_path='' as $$
declare r record;cfg public.company_settings;eid uuid;bank uuid;credited numeric;prior numeric;covered numeric;direct numeric;split jsonb;lines jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended('return_refund'||p_id::text,0));
 select id into eid from public.accounting_entries where source_type='return_refund' and source_id=p_id;
 if eid is not null then return eid;end if;
 select f.*,o.customer_id,o.number return_number,c.name customer_name into r from public.return_refunds f join public.return_orders o on o.id=f.return_id left join public.customers c on c.id=o.customer_id where f.id=p_id;
 if not found then return null;end if;
 perform 1 from public.return_orders where id=r.return_id for update;
 select account_id into bank from public.financial_accounts where id=r.financial_account_id;
 if bank is null then return null;end if;
 select * into cfg from public.company_settings where id;
 select coalesce(sum(amount),0) into credited from public.return_credits where return_id=r.return_id;
 select coalesce(sum(amount),0) into prior from public.return_refunds where return_id=r.return_id and (created_at,id)<(r.created_at,r.id);
 covered:=least(r.amount,greatest(credited-prior,0));direct:=r.amount-covered;
 if covered>0 and exists(select 1 from public.return_credits k where k.return_id=r.return_id and not exists(select 1 from public.accounting_entries e where e.source_type='return_credit' and e.source_id=k.id and e.status in ('posted','reversed'))) then raise exception 'REFUND_CREDIT_UNPOSTED';end if;
 lines:=jsonb_build_array(jsonb_build_object('account_id',bank,'financial_account_id',r.financial_account_id,'label',r.return_number,'credit',r.amount));
 if covered>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.receivable_account_id,'label',r.return_number,'debit',covered,'partner_type','customer','partner_id',r.customer_id));end if;
 if direct>0 then
  split:=private.gama_return_split(r.return_id,direct);
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.sales_account_id,'label',r.return_number,'debit',(split->>'net')::numeric),jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','debit',(split->>'tax')::numeric));
 end if;
 return private.gama_accounting_book(case when r.method ~* '(efectivo|cash|caja)' then 'CAJ' else 'BAN' end,p_date,coalesce(r.reference,r.return_number),'return_refund',r.id,r.customer_name,lines);
end $$;

create function private.gama_accounting_credit_refund_guard(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare rid uuid;begin
 select return_id into rid from public.return_credits where id=p_id;
 perform 1 from public.return_orders where id=rid for update;
 if exists(select 1 from public.return_refunds f join public.accounting_entries e on e.source_type='return_refund' and e.source_id=f.id join public.accounting_entry_lines l on l.entry_id=e.id join public.accounting_accounts a on a.id=l.account_id where f.return_id=rid and e.status in ('posted','reversed') and a.type='income' and l.debit>0) then raise exception 'RETURN_REFUND_ALREADY_REVERSED_SALE';end if;
end $$;

alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_refund_fix;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$begin
 if p_source_type='return_refund' then return private.gama_accounting_refund_post(p_source_id,(select paid_at from public.return_refunds where id=p_source_id));end if;
 if p_source_type='return_credit' and not exists(select 1 from public.accounting_entries where source_type=p_source_type and source_id=p_source_id) then perform private.gama_accounting_credit_refund_guard(p_source_id);end if;
 return private.gama_accounting_post_before_refund_fix(p_source_type,p_source_id);
end $$;
alter function private.gama_accounting_post_at(text,uuid,date) rename to gama_accounting_post_at_before_refund_fix;
create function private.gama_accounting_post_at(p_source_type text,p_source_id uuid,p_date date) returns uuid
language plpgsql security definer set search_path='' as $$begin
 if p_source_type='return_refund' then return private.gama_accounting_refund_post(p_source_id,p_date);end if;
 if p_source_type='return_credit' and not exists(select 1 from public.accounting_entries where source_type=p_source_type and source_id=p_source_id) then perform private.gama_accounting_credit_refund_guard(p_source_id);end if;
 return private.gama_accounting_post_at_before_refund_fix(p_source_type,p_source_id,p_date);
end $$;

-- Search the complete goods catalogue without an inaccessible 1000-product cap.
alter function private.gama_accounting_audit_read(text,jsonb) rename to gama_accounting_audit_read_before_product_search;
create function private.gama_accounting_audit_read(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;search text:=btrim(coalesce(p_data->>'stock_search',''));off integer:=greatest(coalesce((p_data->>'stock_offset')::integer,0),0);begin
 result:=private.gama_accounting_audit_read_before_product_search(p_action,p_data);
 if p_action='context' then result:=result||jsonb_build_object(
  'stock_product_total',(select count(*) from public.products where product_kind='goods' and (search='' or concat_ws(' ',name,reference) ilike '%'||search||'%')),
  'stock_products',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,purchase_price from public.products where product_kind='goods' and (search='' or concat_ws(' ',name,reference) ilike '%'||search||'%') order by name,id limit 100 offset off)x),'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_accounting_refund_post(uuid,date),private.gama_accounting_credit_refund_guard(uuid),private.gama_accounting_post_before_refund_fix(text,uuid),private.gama_accounting_post(text,uuid),private.gama_accounting_post_at_before_refund_fix(text,uuid,date),private.gama_accounting_post_at(text,uuid,date),private.gama_accounting_audit_read_before_product_search(text,jsonb),private.gama_accounting_audit_read(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261011214628','accounting_return_recovery','b013f3bd2404f6be1578671dd58ce91a9c54887009702e7097cb62a87ced677e','b013f3bd2404f6be1578671dd58ce91a9c54887009702e7097cb62a87ced677e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261011214826_accounting_audit_actor_indexes.sql; SHA256 9689967f37ca7e9f9f5ee95a139397ac3c74cf8761f3947c5d008d2d1e70f6db
-- Cover actor references on the new accounting audit tables.
create index accounting_asset_event_actor on private.accounting_asset_events(created_by);
create index accounting_binding_actor on private.accounting_bank_bindings(assigned_by);
create index accounting_statement_actor on private.accounting_bank_statements(updated_by);
create index accounting_budget_actor on private.accounting_budgets(updated_by);
create index accounting_closure_actor on private.accounting_closure_reviews(reviewed_by);
create index accounting_fx_document_actor on private.accounting_fx_documents(created_by);
create index accounting_fx_settlement_actor on private.accounting_fx_settlements(created_by);
create index accounting_dimension_actor on private.accounting_line_dimensions(assigned_by);
create index accounting_readiness_actor on private.accounting_readiness(verified_by);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261011214826','accounting_audit_actor_indexes','9689967f37ca7e9f9f5ee95a139397ac3c74cf8761f3947c5d008d2d1e70f6db','9689967f37ca7e9f9f5ee95a139397ac3c74cf8761f3947c5d008d2d1e70f6db','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261012180222_preparation_auto_dispatch.sql; SHA256 ee23a1a7bb5634946e3d8ff641eee954b7e91d37c2d28a61d13a716bad611be5
-- Complete preparation handoff is one transaction. Existing pick, packing,
-- partial-delivery, stock, audit and transport APIs remain authoritative.
-- No historical preparation is changed by installing this endpoint.
create function private.gama_preparation_dispatch(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid();key_id uuid;oid uuid;pid uuid;
 prep public.fulfillment_preparations;receipt private.fulfillment_requests;
 items jsonb;result jsonb;reason text;delivery_day date;
begin
 if actor is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('tms',array['administrador','almacenero'])
  or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then
  raise exception 'TMS_ACCESS_DENIED';
 end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 key_id:=nullif(p_data->>'request_key','')::uuid;
 oid:=nullif(p_data->>'order_id','')::uuid;pid:=nullif(p_data->>'preparation_id','')::uuid;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 if oid is null or pid is null then raise exception 'PREPARATION_NOT_FOUND';end if;
 reason:=btrim(coalesce(p_data->>'reason',''));
 if length(reason)>2000 then raise exception 'TEXT_TOO_LONG';end if;

 -- Match the existing logistics lock order before locking the document.
 perform pg_advisory_xact_lock(741932,1);
 perform 1 from public.sales_orders where id=oid and status='confirmed' for update;
 if not found then raise exception 'CONFIRM_ORDER_FIRST';end if;
 select * into prep from public.fulfillment_preparations where id=pid and order_id=oid for update;
 if not found then raise exception 'PREPARATION_NOT_FOUND';end if;
 if prep.assigned_to is distinct from actor and private.current_user_role()<>'administrador' then
  raise exception 'ASSIGNED_TO_OTHER';
 end if;
 select * into receipt from private.fulfillment_requests where request_key=key_id;
 if found then
  if receipt.actor_id<>actor or receipt.action<>'auto_dispatch'
   or receipt.payload_hash<>encode(sha256(convert_to(p_data::text,'UTF8')),'hex') then
   raise exception 'REQUEST_KEY_REUSED';
  end if;
  return receipt.result;
 end if;

 -- A refreshed tab or another retry key can only return the same shipment.
 if prep.status='shipped' and prep.shipment_id is not null then
  result:=jsonb_build_object('id',prep.shipment_id,'order_id',oid,'preparation_id',pid);
 else
  if prep.status not in ('picking','packed') then raise exception 'PREPARATION_CLOSED';end if;
  if not exists(select 1 from public.fulfillment_pick_lines where preparation_id=pid and picked>0)
   or (prep.status='picking' and exists(select 1 from public.fulfillment_pick_lines
    where preparation_id=pid and picked<>planned)) then
   raise exception 'PREPARATION_INCOMPLETE';
  end if;

  -- Keep manually made parcels; pack only quantities not yet in an active one.
  -- The existing package API accepts at most 200 lines per parcel.
  loop
   select jsonb_agg(jsonb_build_object('pick_line_id',a.id,'quantity',a.quantity) order by a.id)
    into items from (
     select pl.id,pl.picked-coalesce(sum(pk.quantity),0) quantity
     from public.fulfillment_pick_lines pl left join (
      select l.pick_line_id,l.quantity from public.fulfillment_package_lines l
       join public.fulfillment_packages p on p.id=l.package_id and p.status='active'
     ) pk on pk.pick_line_id=pl.id
     where pl.preparation_id=pid group by pl.id,pl.picked
     having pl.picked>coalesce(sum(pk.quantity),0) order by pl.id limit 200
    ) a;
   exit when items is null;
   perform public.gama_fulfillment_action('package',jsonb_build_object(
    'order_id',oid,'preparation_id',pid,'request_key',gen_random_uuid(),'lines',items));
  end loop;
  if prep.status='picking' then
   perform public.gama_fulfillment_action('finish',jsonb_build_object(
    'order_id',oid,'preparation_id',pid,'request_key',gen_random_uuid(),'reason',reason));
  end if;
  -- Use the agreed date for the prepared goods, never a past planning date.
  select greatest((now() at time zone private.erp_timezone())::date,max(ol.promised_date))
   into delivery_day from public.sales_order_lines ol join public.fulfillment_pick_lines pl
    on pl.order_line_id=ol.id where pl.preparation_id=pid and pl.picked>0;
  result:=public.gama_sales_action('ship',jsonb_build_object(
   'order_id',oid,'preparation_id',pid,'request_key',gen_random_uuid(),'delivery_date',delivery_day))
    ||jsonb_build_object('preparation_id',pid);
 end if;
 result:=result||jsonb_build_object('tms_delivery_id',(
  select tms_delivery_id from public.sales_deliveries where id=(result->>'id')::uuid));
 insert into private.fulfillment_requests(request_key,actor_id,action,payload_hash,result)
  values(key_id,actor,'auto_dispatch',encode(sha256(convert_to(p_data::text,'UTF8')),'hex'),result);
 return result;
end $$;

create function public.gama_preparation_dispatch(p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_preparation_dispatch(p_data)$$;
revoke all on function private.gama_preparation_dispatch(jsonb),public.gama_preparation_dispatch(jsonb) from public,anon;
grant execute on function private.gama_preparation_dispatch(jsonb),public.gama_preparation_dispatch(jsonb) to authenticated;
comment on function public.gama_preparation_dispatch(jsonb) is
 'Empaqueta las cantidades validadas, cierra la preparación completa y crea una única entrega TMS de forma atómica.';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261012180222','preparation_auto_dispatch','ee23a1a7bb5634946e3d8ff641eee954b7e91d37c2d28a61d13a716bad611be5','ee23a1a7bb5634946e3d8ff641eee954b7e91d37c2d28a61d13a716bad611be5','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
