-- Source-to-target links supplement existing receipts; they do not replace any
-- stock/payment/accounting transaction, nor fill in customer/supplier/products.
create table private.automation_links(
 source_type text not null,source_id uuid not null,target_type text not null,target_id uuid not null,
 fingerprint text,created_at timestamptz not null default now(),primary key(source_type,source_id,target_type)
);
alter table private.automation_links enable row level security;
revoke all on private.automation_links from public,anon,authenticated,service_role;
create index automation_links_target on private.automation_links(target_type,target_id);
create function private.automation_key(p_key text) returns uuid language sql immutable set search_path='' as $$select md5('coco-automation:'||p_key)::uuid$$;
create table private.tms_plan_versions(
 id bigint generated always as identity primary key,day date not null,fingerprint text not null,output_hash text not null,
 summary jsonb not null,planned_at timestamptz not null,unique(day,output_hash)
);
alter table private.tms_plan_versions enable row level security;revoke all on private.tms_plan_versions from public,anon,authenticated,service_role;
create function private.tms_plan_version_capture() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into private.tms_plan_versions(day,fingerprint,output_hash,summary,planned_at) values(new.day,new.fingerprint,new.output_hash,new.summary,new.planned_at) on conflict(day,output_hash) do nothing;return new;
end $$;
create trigger tms_plan_version_capture after insert or update on private.tms_day_plans for each row execute function private.tms_plan_version_capture();

alter table public.crm_activities add column automation_key text;
create unique index crm_activities_automation on public.crm_activities(automation_key) where automation_key is not null;
create index crm_activities_pending_opportunity on public.crm_activities(opportunity_id,due_at) where status in ('pendiente','en_curso');
create index crm_activities_pending_invoice on public.crm_activities(invoice_id,due_at) where status in ('pendiente','en_curso');
create index customer_requests_pending_flow on public.customer_requests(created_at,id) where invoice_id is null and status in ('pending','accepted');

-- Missing source fields create an exception. A background job cannot mark a
-- legally unknown tax treatment as reviewed, or pay/post a provisional draft.
alter table public.expenses add column source_reviewed boolean not null default true;
alter table public.supplier_invoices add column source_reviewed boolean not null default true;
create function private.automation_finance_draft_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='posted' and not new.source_reviewed then raise exception 'SOURCE_REVIEW_REQUIRED';end if;
 return new;
end $$;
create trigger automation_finance_draft_guard before insert or update on public.expenses for each row execute function private.automation_finance_draft_guard();
create trigger automation_finance_draft_guard before insert or update on public.supplier_invoices for each row execute function private.automation_finance_draft_guard();
create function private.automation_supplier_payment_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and not exists(select 1 from public.supplier_invoices b where b.id=new.supplier_invoice_id and b.status='posted' and b.source_reviewed) then raise exception 'POSTED_SUPPLIER_INVOICE_REQUIRED';end if;return new;
end $$;
create trigger automation_supplier_payment_guard before insert or update on public.supplier_invoice_payments for each row execute function private.automation_supplier_payment_guard();

create function private.automation_finance_checks() returns jsonb language plpgsql security definer set search_path='' as $$
 declare item record;checked integer:=0;begin
 for item in select e.id,e.number from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id
  where e.status='posted' group by e.id having abs(sum(l.debit-l.credit))>.005 loop
  perform private.automation_exception('ledger-balance:'||item.id,'finance_check','accounting','entry',item.id,'LEDGER_UNBALANCED',null,item.number);checked:=checked+1;
 end loop;
 update private.automation_exceptions x set active=false,resolved_at=now(),updated_at=now() where x.kind='finance_check' and x.key like 'ledger-balance:%' and x.active
  and not exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where e.id=x.source_id and e.status='posted' group by e.id having abs(sum(l.debit-l.credit))>.005);
 for item in select i.id,i.number from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
  and not exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status='posted') loop
  perform private.automation_exception('invoice-ledger:'||item.id,'finance_check','accounting','invoice',item.id,'SOURCE_NOT_POSTED',null,item.number);checked:=checked+1;
 end loop;
 update private.automation_exceptions x set active=false,resolved_at=now(),updated_at=now() where x.kind='finance_check' and x.key like 'invoice-ledger:%' and x.active
  and (exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=x.source_id and e.status='posted') or not exists(select 1 from public.external_invoices i where i.id=x.source_id and i.fiscal_status not in ('cancelled','rejected')));
 for item in select q.product_id from public.stock_quants q where q.quantity<0 or q.reserved_quantity<0 or q.reserved_quantity>q.quantity group by q.product_id loop
  perform private.automation_exception('stock-quant:'||item.product_id,'finance_check','warehouses','product',item.product_id,'STOCK_QUANT_INVALID');checked:=checked+1;
 end loop;
 update private.automation_exceptions x set active=false,resolved_at=now(),updated_at=now() where x.kind='finance_check' and x.key like 'stock-quant:%' and x.active
  and not exists(select 1 from public.stock_quants q where q.product_id=x.source_id and (q.quantity<0 or q.reserved_quantity<0 or q.reserved_quantity>q.quantity));
 return jsonb_build_object('exceptions_checked',checked,'as_of',now());
end $$;

create function private.automation_replenish(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare row record;item jsonb;items jsonb:='[]';result jsonb;grouped record;cap numeric:=coalesce((p_config->>'max_order_total')::numeric,1000);begin
 if cap<=0 or cap>1000000 then return jsonb_build_object('blocked',true,'reason','PURCHASE_LIMIT_REQUIRED');end if;
 if not private.erp_action_allowed('gamaPurchasesV14','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 for row in select x.product_id,x.data from private.stock_insight_rows(true) x where (x.data->>'suggested_quantity')::numeric>0 order by x.product_id limit 3000 loop
  item:=row.data;
  if nullif(item->>'supplier_id','') is null or coalesce((item->>'unit_cost')::numeric,0)<=0 or not coalesce((item->>'lead_configured')::boolean,false) then
   perform private.automation_exception('replenish:'||row.product_id,'replenishment','gamaPurchasesV14','product',row.product_id,'SUPPLIER_COST_OR_LEAD_TIME_REQUIRED',p_job.id,item->>'reference');
  else items:=items||jsonb_build_array(jsonb_build_object('product_id',row.product_id,'supplier_id',item->>'supplier_id','quantity',(item->>'suggested_quantity')::numeric,'unit_cost',(item->>'unit_cost')::numeric));
   update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='replenish:'||row.product_id;
  end if;
 end loop;
 for grouped in select x->>'supplier_id' supplier,sum((x->>'quantity')::numeric*(x->>'unit_cost')::numeric*(1+p.tax_rate/100)) total,count(*) lines
  from jsonb_array_elements(items) x join public.products p on p.id=(x->>'product_id')::uuid group by x->>'supplier_id' loop
  if grouped.total>cap or grouped.lines>500 then
   perform private.automation_exception('replenish-limit:'||grouped.supplier,'replenishment','gamaPurchasesV14','supplier',grouped.supplier::uuid,'PURCHASE_LIMIT_EXCEEDED',p_job.id);
   select coalesce(jsonb_agg(x),'[]') into items from jsonb_array_elements(items) x where x->>'supplier_id'<>grouped.supplier;
  end if;
 end loop;
 if jsonb_array_length(items)=0 then return jsonb_build_object('orders','[]'::jsonb,'products',0,'as_of',now());end if;
 select jsonb_agg(x-'unit_cost') into items from jsonb_array_elements(items) x;
 result:=private.gama_stock_replenish(jsonb_build_object('request_key',p_job.id,'destination_location_id',p_config->>'destination_location_id','items',items));
 return result;
end $$;

create function private.automation_counts(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare row record;parent public.inventory_counts;created jsonb:='[]';r jsonb;w uuid:=nullif(p_config->>'warehouse_id','')::uuid;days integer;today date:=(now() at time zone private.erp_timezone())::date;begin
 if not private.erp_action_allowed('warehouses','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if w is null or not exists(select 1 from public.warehouses where id=w and active) then return jsonb_build_object('blocked',true,'reason','WAREHOUSE_REQUIRED');end if;
 for parent in select * from public.inventory_counts c where c.warehouse_id=w and c.status='validated' and c.next_due<=today
  and not exists(select 1 from public.inventory_counts n where n.repeat_of=c.id and n.status<>'cancelled') order by next_due,id limit 5 loop
  r:=private.gama_count_create_core(jsonb_build_object('request_key',private.automation_key('repeat-count:'||parent.id),'warehouse_id',w,'repeat_of',parent.id,'assigned_to',parent.assigned_to,'due_date',today,'blind',true,'cycle_days',parent.cycle_days,'product_id',parent.scope_product_id,'location_id',parent.scope_location_id,'category',parent.scope_category,'priority',parent.priority,'reference','Ciclo · '||parent.reference));created:=created||jsonb_build_array(r->'id');
 end loop;
 for row in select x.product_id,x.data from private.stock_insight_rows(false) x
  where (x.data->>'on_hand')::numeric>0 and exists(select 1 from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id where q.product_id=x.product_id and q.quantity>0 and l.warehouse_id=w and l.active)
  and not exists(select 1 from public.inventory_counts c where c.warehouse_id=w and c.status in ('draft','in_progress') and (c.scope_product_id=x.product_id or c.scope_product_id is null))
  and not exists(select 1 from public.inventory_count_lines l join public.inventory_counts c on c.id=l.count_id where l.product_id=x.product_id and c.warehouse_id=w and c.status='validated' and c.completed_at>now()-make_interval(days=>case x.data->>'importance' when 'A' then 30 when 'B' then 90 else 180 end))
  order by case x.data->>'importance' when 'A' then 0 when 'B' then 1 else 2 end,x.product_id limit 5 loop
  days:=case row.data->>'importance' when 'A' then 30 when 'B' then 90 else 180 end;
  r:=private.gama_count_create_core(jsonb_build_object('request_key',private.automation_key('abc-count:'||w||':'||row.product_id||':'||today),'warehouse_id',w,'due_date',today+7,'blind',true,'cycle_days',days,'product_id',row.product_id,'priority',case when row.data->>'importance'='A' then 'high' else 'normal' end,'reference','ABC '||(row.data->>'importance')||' · '||(row.data->>'reference')));created:=created||jsonb_build_array(r->'id');
 end loop;
 return jsonb_build_object('counts',created);
end $$;

create function private.automation_crm(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
 declare o public.crm_opportunities;key text;created integer:=0;owner uuid;begin
 if not private.erp_action_allowed('crm','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 for o in select * from public.crm_opportunities o where o.active and o.won_at is null and o.lost_at is null
  and not exists(select 1 from public.crm_activities a where a.opportunity_id=o.id and a.status in ('pendiente','en_curso')) order by o.updated_at,o.id limit 100 loop
  owner:=o.owner_id;if owner is null or not exists(select 1 from public.profiles where id=owner and active and role in ('administrador','comercial')) then
   perform private.automation_exception('crm-owner:'||o.id,'crm_followup','crm','opportunity',o.id,'OWNER_REQUIRED',p_job.id,o.reference);continue;
  end if;
  key:='opportunity:'||o.id||':'||coalesce((select max(a.done_at)::text from public.crm_activities a where a.opportunity_id=o.id),o.created_at::text);
  insert into public.crm_activities(kind,subject,status,owner_id,due_at,customer_id,lead_id,opportunity_id,created_by,automation_key)
   values('seguimiento','Seguimiento · '||o.reference,'pendiente',owner,now()+make_interval(days=>greatest(1,least(coalesce((p_config->>'followup_days')::integer,3),90))),o.customer_id,o.lead_id,o.id,auth.uid(),key) on conflict(automation_key) where automation_key is not null do nothing;
  if found then created:=created+1;end if;
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='crm-owner:'||o.id;
 end loop;
 return jsonb_build_object('activities',created);
end $$;

create function private.automation_request_quote(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare req public.customer_requests;c public.customers;p public.products;l public.customer_request_lines;resolved jsonb;lines jsonb:='[]';total numeric:=0;cap numeric:=coalesce((p_config->>'max_quote_total')::numeric,1000);details jsonb;begin
 if not private.erp_action_allowed('quotes','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for req in select * from public.customer_requests where invoice_id is null and status in ('pending','accepted') order by created_at,id limit 100 loop
   perform private.automation_enqueue('request_quote','request-quote:'||req.id,jsonb_build_object('request_id',req.id),'request',req.id);
  end loop;
  return jsonb_build_object('scanned',true);
 end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into req from public.customer_requests where id=p_job.source_id for update;
 if not found or req.status in ('cancelled','rejected') then return jsonb_build_object('skipped','REQUEST_CLOSED');end if;
 if req.invoice_id is not null then return jsonb_build_object('id',req.invoice_id,'existing',true);end if;
 select * into c from public.customers where id=req.customer_id and active;
 if not found or nullif(btrim(c.identification),'') is null or nullif(btrim(coalesce(req.delivery_address_snapshot,c.address)),'') is null then return jsonb_build_object('blocked',true,'reason','CUSTOMER_OR_DELIVERY_DETAILS_REQUIRED');end if;
 for l in select * from public.customer_request_lines where request_id=req.id order by product_id loop
  select * into p from public.products where id=l.product_id and active;
  if not found or p.purchase_price<=0 then return jsonb_build_object('blocked',true,'reason','PRODUCT_COST_REQUIRED');end if;
  resolved:=private.erp_price(c.id,p.id,l.quantity,current_date);
  if (resolved->>'unit_price')::numeric<=0 then return jsonb_build_object('blocked',true,'reason','PRICE_REQUIRED');end if;
  total:=total+round(l.quantity*(resolved->>'unit_price')::numeric,2)+round(round(l.quantity*(resolved->>'unit_price')::numeric,2)*p.tax_rate/100,2);
  lines:=lines||jsonb_build_array(jsonb_build_object('product_id',p.id,'quantity',l.quantity,'list_price',(resolved->>'unit_price')::numeric,'discount',0,'tax_rate',p.tax_rate,'description',p.name));
 end loop;
 if jsonb_array_length(lines)=0 or jsonb_array_length(lines)>200 then return jsonb_build_object('blocked',true,'reason','INVALID_LINES');end if;
 if cap<=0 or total>cap then return jsonb_build_object('blocked',true,'reason','QUOTE_LIMIT_EXCEEDED');end if;
 details:=jsonb_build_object('client',c.name,'clientId',c.identification,'seller',(select full_name from public.profiles where id=auth.uid()),'delivery_address',coalesce(req.delivery_address_snapshot,c.address),'notes',req.notes);
 return private.gama_quote_from_request(req.id,jsonb_build_object('customer_id',c.id,'issue_date',current_date,'valid_until',current_date+30,'details',details,'lines',lines));
end $$;

create function private.automation_business_event() returns trigger language plpgsql security definer set search_path='' as $$declare source uuid;begin
 if tg_table_name='customer_requests' then
  if new.invoice_id is null and new.status in ('pending','accepted') then perform private.automation_enqueue('request_quote','request-quote:'||new.id,jsonb_build_object('request_id',new.id),'request',new.id);end if;
 elsif tg_table_name='purchase_order_lines' then
  if new.received_quantity>0 and (tg_op='INSERT' or new.received_quantity is distinct from old.received_quantity) then
   source:=new.purchase_order_id;perform private.automation_enqueue('receipt_bill','receipt-bill:'||source||':'||txid_current(),jsonb_build_object('purchase_order_id',source),'purchase',source);
  end if;
 elsif tg_table_name in ('fleet_fuel_logs','fleet_maintenance') then
  perform private.automation_enqueue('fleet_expense','fleet-expense:'||tg_table_name||':'||new.id||':'||md5(to_jsonb(new)::text),jsonb_build_object('table',tg_table_name),tg_table_name,new.id);
 elsif tg_table_name='tms_deliveries' then
  perform private.automation_enqueue('tms_planning','tms-plan:'||new.delivery_date||':'||txid_current(),jsonb_build_object('day',new.delivery_date),'delivery',new.id);
 end if;
 return new;
end $$;
create trigger automation_business_event after insert or update on public.customer_requests for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update of received_quantity on public.purchase_order_lines for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update on public.fleet_fuel_logs for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update on public.fleet_maintenance for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update of delivery_date,address,priority on public.tms_deliveries for each row execute function private.automation_business_event();

alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_checks;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;day date;begin
 case p_job.kind
 when 'finance_checks' then return private.automation_finance_checks();
 when 'replenishment' then return private.automation_replenish(p_job,p_config);
 when 'cycle_counts' then return private.automation_counts(p_job,p_config);
 when 'tms_planning' then
  day:=coalesce(nullif(p_job.payload->>'day','')::date,(now() at time zone private.erp_timezone())::date);
  if day<(now() at time zone private.erp_timezone())::date then return jsonb_build_object('skipped','PLANNING_DATE_PAST');end if;
  result:=private.gama_tms_plan_day(day);
  if (result->>'without_coordinates')::integer>0 then perform private.automation_exception('tms-gps:'||day,'tms_planning','tms',null,null,'DELIVERY_COORDINATES_REQUIRED',p_job.id,day::text);
  else update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='tms-gps:'||day;end if;
  return result;
 when 'crm_followup' then return private.automation_crm(p_job,p_config);
 when 'request_quote' then return private.automation_request_quote(p_job,p_config);
 when 'accepted_order' then return jsonb_build_object('existing_flow','Accepted quotes already create their confirmed order transactionally.');
 else return private.automation_dispatch_checks(p_job,p_config);
 end case;
end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'automation_%' or p.proname in ('tms_plan_version_capture')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
