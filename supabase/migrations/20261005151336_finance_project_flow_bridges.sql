create function private.automation_receipt_bill(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare po public.purchase_orders;bill public.supplier_invoices;linked private.automation_links;net numeric;taxes numeric;lines jsonb;begin
 if not private.erp_action_allowed('accounting','create') or private.gama_accounting_rights()->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for po in select o.* from public.purchase_orders o where o.status in ('partial','received') and exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id and l.received_quantity>0)
   order by o.updated_at,o.id limit 100 loop
   perform private.automation_enqueue('receipt_bill','receipt-bill-scan:'||po.id||':'||md5((select jsonb_agg(jsonb_build_array(l.id,l.received_quantity) order by l.id)::text from public.purchase_order_lines l where l.purchase_order_id=po.id)),jsonb_build_object('purchase_order_id',po.id),'purchase',po.id);
  end loop;return jsonb_build_object('scanned',true);
 end if;
 select * into po from public.purchase_orders where id=p_job.source_id for update;
 if not found or po.status='cancelled' then return jsonb_build_object('skipped','PURCHASE_CLOSED');end if;
 select coalesce(sum(round(z.quantity*z.unit_cost,2)),0),coalesce(sum(round(round(z.quantity*z.unit_cost,2)*z.tax_rate/100,2)),0),coalesce(jsonb_agg(to_jsonb(z) order by z.line_id),'[]') into net,taxes,lines
 from(select l.id line_id,l.unit_cost,l.tax_rate,greatest(0,l.received_quantity-coalesce((select sum(ml.quantity) from public.supplier_invoice_match_lines ml join public.supplier_invoice_matches m on m.id=ml.match_id join public.supplier_invoices b on b.id=m.invoice_id where ml.purchase_line_id=l.id and b.status='posted'),0)) quantity
  from public.purchase_order_lines l where l.purchase_order_id=po.id)z where z.quantity>0;
 if net+taxes<=0 then return jsonb_build_object('skipped','NO_UNBILLED_RECEIPT');end if;
 select * into linked from private.automation_links where source_type='purchase_receipt' and source_id=po.id and target_type='supplier_invoice';
 if linked.target_id is not null then
  select * into bill from public.supplier_invoices where id=linked.target_id for update;
  if bill.status='posted' then
   -- A subsequent partial receipt uses a new draft; never revise a posted bill.
   delete from private.automation_links where source_type='purchase_receipt' and source_id=po.id and target_type='supplier_invoice';bill.id:=null;
  elsif bill.status='cancelled' then return jsonb_build_object('blocked',true,'reason','CANCELLED_DRAFT_REVIEW_REQUIRED');
  elsif bill.source_reviewed then return jsonb_build_object('blocked',true,'reason','RECEIPT_CHANGED_AFTER_REVIEW');end if;
 end if;
 if bill.id is null then
  insert into public.supplier_invoices(number,supplier_id,purchase_order_id,issue_date,subtotal,tax,total,status,notes,request_key,created_by,source_reviewed)
   values('BOR-'||po.order_number,po.supplier_id,po.id,current_date,net,taxes,net+taxes,'draft','Preparado desde cantidades recibidas. Verificar número, fecha y fiscalidad con el documento del proveedor.',p_job.id,auth.uid(),false) returning * into bill;
  insert into private.automation_links(source_type,source_id,target_type,target_id,fingerprint) values('purchase_receipt',po.id,'supplier_invoice',bill.id,md5(lines::text));
 else update public.supplier_invoices set subtotal=net,tax=taxes,total=net+taxes,updated_at=now() where id=bill.id returning * into bill;
  update private.automation_links set fingerprint=md5(lines::text) where source_type='purchase_receipt' and source_id=po.id and target_type='supplier_invoice';
 end if;
 perform private.automation_exception('supplier-draft:'||bill.id,'receipt_bill','accounting','supplier_invoice',bill.id,'SUPPLIER_DOCUMENT_REVIEW_REQUIRED',p_job.id,bill.erp_reference);
 return jsonb_build_object('id',bill.id,'status','draft','lines',lines);
end $$;

create function private.automation_fleet_expense(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare src record;expense public.expenses;linked private.automation_links;answer jsonb;begin
 if not private.erp_module_allowed('fleet',array['administrador']) or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for src in select 'fleet_fuel_logs' source,id,md5(to_jsonb(f)::text) hash from public.fleet_fuel_logs f where f.logged_on>=current_date-90
   union all select 'fleet_maintenance',id,md5(to_jsonb(m)::text) from public.fleet_maintenance m where m.performed_on>=current_date-90 limit 200 loop
   perform private.automation_enqueue('fleet_expense','fleet-expense:'||src.source||':'||src.id||':'||src.hash,jsonb_build_object('table',src.source),src.source,src.id);
  end loop;return jsonb_build_object('scanned',true);
 end if;
 if p_job.source_type='fleet_fuel_logs' then select f.id,f.vehicle_id,f.logged_on source_day,f.amount amount,'Combustible · '||v.plate description,md5(to_jsonb(f)::text) hash into src from public.fleet_fuel_logs f join public.fleet_vehicles v on v.id=f.vehicle_id where f.id=p_job.source_id for update of f;
 elsif p_job.source_type='fleet_maintenance' then select m.id,m.vehicle_id,m.performed_on source_day,m.cost amount,'Mantenimiento · '||v.plate||' · '||m.kind description,md5(to_jsonb(m)::text) hash into src from public.fleet_maintenance m join public.fleet_vehicles v on v.id=m.vehicle_id where m.id=p_job.source_id for update of m;
 else raise exception 'INVALID_SOURCE';end if;
 if src.id is null or src.amount<=0 then return jsonb_build_object('skipped','NO_COST');end if;
 select * into linked from private.automation_links where source_type=p_job.source_type and source_id=src.id and target_type='expense';
 if linked.target_id is not null then select * into expense from public.expenses where id=linked.target_id for update;
  if linked.fingerprint=src.hash then return jsonb_build_object('id',expense.id,'existing',true);end if;
  if expense.status<>'draft' or expense.source_reviewed then return jsonb_build_object('blocked',true,'reason','FLEET_COST_CHANGED_AFTER_REVIEW');end if;
 end if;
 answer:=private.gama_accounting_action('expense_save',jsonb_build_object('id',expense.id,'request_key',case when expense.id is null then private.automation_key(p_job.source_type||':'||src.id) end,'expense_date',src.source_day,'description',src.description,'amount_untaxed',src.amount,'tax_amount',0,'amount_total',src.amount,'notes','Preparado desde Flota. Revisar justificante, IVA y medio de pago antes de contabilizar.'));
 update public.expenses set source_reviewed=false where id=(answer->>'id')::uuid and status='draft';
 insert into private.automation_links(source_type,source_id,target_type,target_id,fingerprint) values(p_job.source_type,src.id,'expense',(answer->>'id')::uuid,src.hash)
  on conflict(source_type,source_id,target_type) do update set fingerprint=excluded.fingerprint;
 perform private.automation_exception('expense-draft:'||(answer->>'id'),'fleet_expense','accounting','expense',(answer->>'id')::uuid,'RECEIPT_TAX_AND_PAYMENT_REVIEW_REQUIRED',p_job.id);
 return answer||jsonb_build_object('status','draft');
end $$;

create table private.finance_flow_receipts(request_key uuid primary key,actor uuid not null references public.profiles(id),payload jsonb not null,result jsonb not null,created_at timestamptz not null default now());
alter table private.finance_flow_receipts enable row level security;
revoke all on private.finance_flow_receipts from public,anon,authenticated,service_role;
create index finance_flow_receipt_actor on private.finance_flow_receipts(actor);
create function private.gama_flow_finance(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare rights jsonb:=private.gama_accounting_rights();bill public.supplier_invoices;result jsonb;receipt private.finance_flow_receipts;request uuid;net numeric;taxes numeric;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='drafts' then return jsonb_build_object('bills',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select b.*,s.name supplier_name from public.supplier_invoices b join public.suppliers s on s.id=b.supplier_id where b.status='draft' order by b.updated_at,b.id limit 100)z));end if;
 if p_action='expense_review' then
  if not (rights->>'edit')::boolean or not private.erp_action_allowed('accounting','edit') or not coalesce((p_data->>'reviewed')::boolean,false) then raise exception 'SOURCE_REVIEW_REQUIRED';end if;
  update public.expenses set source_reviewed=true,updated_at=now() where id=(p_data->>'id')::uuid and status='draft';if not found then raise exception 'EXPENSE_NOT_FOUND';end if;
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='expense-draft:'||(p_data->>'id');return jsonb_build_object('reviewed',true);
 end if;
 if p_action='post' then
  if not (rights->>'validate')::boolean or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
  request:=nullif(p_data->>'request_key','')::uuid;if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('finance-flow:'||request,0));
  select * into receipt from private.finance_flow_receipts where request_key=request;
  if found then if receipt.actor<>auth.uid() or receipt.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 end if;
 select * into bill from public.supplier_invoices where id=(p_data->>'id')::uuid for update;if not found then raise exception 'INVOICE_NOT_FOUND';end if;
 if p_action='context' then return jsonb_build_object('bill',to_jsonb(bill),'matching',case when bill.purchase_order_id is not null then private.gama_supplier_match('preview',p_data) else null end);end if;
 if bill.status<>'draft' then raise exception 'DRAFT_REQUIRED';end if;
 if bill.updated_at is distinct from nullif(p_data->>'expected_updated_at','')::timestamptz then raise exception 'DOCUMENT_CHANGED';end if;
 if p_action='save' then
  if not (rights->>'edit')::boolean or not private.erp_action_allowed('accounting','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  net:=round((p_data->>'subtotal')::numeric,2);taxes:=round((p_data->>'tax')::numeric,2);
  if net is null or taxes is null or net<0 or taxes<0 or net+taxes<=0 or net+taxes>1000000000 then raise exception 'INVALID_TOTAL';end if;
  if nullif(btrim(p_data->>'number'),'') is null or length(p_data->>'number')>100 then raise exception 'NUMBER_REQUIRED';end if;
  update public.supplier_invoices set number=btrim(p_data->>'number'),issue_date=(p_data->>'issue_date')::date,payment_terms_days=coalesce((p_data->>'payment_terms_days')::integer,0),due_date=(p_data->>'issue_date')::date+coalesce((p_data->>'payment_terms_days')::integer,0),subtotal=net,tax=taxes,total=net+taxes,notes=p_data->>'notes',source_reviewed=false,updated_at=now() where id=bill.id returning * into bill;return to_jsonb(bill);
 elsif p_action='post' then
  if not (rights->>'validate')::boolean or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not coalesce((p_data->>'reviewed')::boolean,false) or bill.number like 'BOR-%' then raise exception 'SUPPLIER_DOCUMENT_REVIEW_REQUIRED';end if;
  if exists(select 1 from public.supplier_invoices b where b.id<>bill.id and b.supplier_id=bill.supplier_id and b.number=bill.number and b.status<>'cancelled') then raise exception 'SUPPLIER_INVOICE_DUPLICATE';end if;
  if not private.gama_accounting_period_open(bill.issue_date) then raise exception 'PERIOD_CLOSED';end if;
  update public.supplier_invoices set source_reviewed=true,status='posted',updated_at=now() where id=bill.id;
  if bill.match_required and bill.purchase_order_id is not null then perform private.gama_supplier_match('approve',jsonb_build_object('id',bill.id,'lines',p_data->'lines','reason',p_data->>'reason'));end if;
  result:=jsonb_build_object('id',bill.id,'entry',private.gama_accounting_post('supplier_invoice',bill.id),'status','posted');
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='supplier-draft:'||bill.id;
  insert into private.finance_flow_receipts(request_key,actor,payload,result) values(request,auth.uid(),p_data,result);return result;
 elsif p_action='cancel' then
  if not (rights->>'edit')::boolean or not private.erp_action_allowed('accounting','edit') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'ROLE_NOT_ALLOWED';end if;
  update public.supplier_invoices set status='cancelled',notes=concat_ws(E'\n',notes,p_data->>'reason'),updated_at=now() where id=bill.id;
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='supplier-draft:'||bill.id;return jsonb_build_object('id',bill.id,'status','cancelled');
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_flow_finance(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_flow_finance(p_action,p_data)$$;

create table public.project_time_entries(
 id uuid primary key default gen_random_uuid(),request_key uuid not null unique,project_id uuid not null references public.pm_projects(id),employee_id uuid not null references public.hr_employees(id),
 worked_on date not null,hours numeric(8,3) not null check(hours>0 and hours<=24),description text not null check(length(btrim(description)) between 3 and 1000),
 status text not null default 'submitted' check(status in ('submitted','approved','transferred','cancelled')),
 hourly_cost numeric(14,4) check(hourly_cost>0),evidence text,approved_by uuid references public.profiles(id),approved_at timestamptz,
 cost_entry_id uuid references public.pm_cost_entries(id),created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(status not in ('approved','transferred') or (approved_by is not null and approved_at is not null and hourly_cost>0 and length(btrim(evidence))>=3))
);
alter table public.project_time_entries enable row level security;
revoke all on public.project_time_entries from public,anon,authenticated;grant select on public.project_time_entries to authenticated;
create policy project_time_read on public.project_time_entries for select to authenticated using((select private.erp_mfa_ok()) and private.pm_manage(project_id) and private.hr_manage(employee_id));
create index project_time_project on public.project_time_entries(project_id,worked_on,id);
create index project_time_employee on public.project_time_entries(employee_id,worked_on);
create index project_time_approver on public.project_time_entries(approved_by);
create index project_time_creator on public.project_time_entries(created_by);
create index project_time_cost on public.project_time_entries(cost_entry_id);
create index project_time_pending on public.project_time_entries(updated_at,id) where status='approved';
create trigger erp_audit_capture after insert or update or delete on public.project_time_entries for each row execute function private.erp_audit_capture();
create function private.gama_project_time(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare pid uuid:=(p_data->>'project_id')::uuid;entry public.project_time_entries;employee uuid;key uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('projects',array['administrador','comercial','almacenero']) or not private.pm_manage(pid) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select t.*,e.full_name employee_name from public.project_time_entries t join public.hr_employees e on e.id=t.employee_id where t.project_id=pid and private.hr_manage(e.id) order by t.worked_on desc,t.id limit 200)z),
  'employees',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name),'[]') from public.hr_employees where active and private.hr_manage(id)));end if;
 if p_action='submit' then
  if not private.erp_action_allowed('projects','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
  employee:=(p_data->>'employee_id')::uuid;if not private.hr_manage(employee) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if (p_data->>'worked_on')::date>current_date then raise exception 'WORK_DATE_FUTURE';end if;
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  select * into entry from public.project_time_entries where request_key=key;if found then
   if entry.project_id<>pid or entry.employee_id<>employee or entry.created_by<>auth.uid() or entry.worked_on<>(p_data->>'worked_on')::date or entry.hours<>(p_data->>'hours')::numeric or entry.description<>p_data->>'description' then raise exception 'REQUEST_KEY_REUSED';end if;return to_jsonb(entry);
  end if;
  if exists(select 1 from public.pm_projects where id=pid and status in ('completed','cancelled')) then raise exception 'PROJECT_CLOSED';end if;
  insert into public.project_time_entries(request_key,project_id,employee_id,worked_on,hours,description) values(key,pid,employee,(p_data->>'worked_on')::date,(p_data->>'hours')::numeric,p_data->>'description') returning * into entry;return to_jsonb(entry);
 end if;
 select * into entry from public.project_time_entries where id=(p_data->>'id')::uuid and project_id=pid for update;
 if not found or not private.hr_manage(entry.employee_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='approve' then
  if entry.status<>'submitted' then raise exception 'TIME_ENTRY_CHANGED';end if;
  if not private.erp_action_allowed('projects','validate') or not private.erp_module_allowed('hr',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  update public.project_time_entries set status='approved',hourly_cost=(p_data->>'hourly_cost')::numeric,evidence=p_data->>'evidence',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=entry.id returning * into entry;
  perform private.automation_enqueue('project_hours','project-time:'||entry.id,jsonb_build_object('time_entry_id',entry.id),'project_time',entry.id);
 elsif p_action='cancel' then
  if not private.erp_action_allowed('projects','edit') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if entry.cost_entry_id is not null then perform private.gama_project_finance('cancel_cost',jsonb_build_object('id',entry.cost_entry_id,'project_id',pid,'reason',p_data->>'reason'));end if;
  update public.project_time_entries set status='cancelled',updated_at=now() where id=entry.id returning * into entry;
 else raise exception 'INVALID_ACTION';end if;
 return to_jsonb(entry);
end $$;
create function public.gama_project_time(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_project_time(p_action,p_data)$$;
create function private.automation_project_hours(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare entry public.project_time_entries;cid uuid;result jsonb;begin
 if not private.erp_action_allowed('projects','create') or not private.erp_module_allowed('hr',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for entry in select * from public.project_time_entries where status='approved' and cost_entry_id is null order by worked_on,id limit 100 loop
   perform private.automation_enqueue('project_hours','project-time:'||entry.id,jsonb_build_object('time_entry_id',entry.id),'project_time',entry.id);
  end loop;return jsonb_build_object('scanned',true);
 end if;
 select * into entry from public.project_time_entries where id=p_job.source_id for update;
 if not found or entry.status='cancelled' then return jsonb_build_object('skipped','TIME_ENTRY_CLOSED');end if;
 if entry.cost_entry_id is not null then return jsonb_build_object('id',entry.cost_entry_id,'existing',true);end if;
 if entry.status<>'approved' or not private.hr_manage(entry.employee_id) then return jsonb_build_object('blocked',true,'reason','TIME_APPROVAL_REQUIRED');end if;
 cid:=private.automation_key('project-time:'||entry.id);
 result:=private.gama_project_finance('cost',jsonb_build_object('id',cid,'project_id',entry.project_id,'entry_date',entry.worked_on,'kind','labor','description',entry.description,'quantity',entry.hours,'unit_cost',entry.hourly_cost,'source_reference','hr-time:'||entry.id));
 update public.project_time_entries set status='transferred',cost_entry_id=cid,updated_at=now() where id=entry.id;
 insert into private.automation_links(source_type,source_id,target_type,target_id) values('project_time',entry.id,'pm_cost_entry',cid) on conflict do nothing;
 return jsonb_build_object('id',cid,'hours',entry.hours);
end $$;

alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_business;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 case p_job.kind when 'receipt_bill' then return private.automation_receipt_bill(p_job,p_config);
 when 'fleet_expense' then return private.automation_fleet_expense(p_job,p_config);
 when 'project_hours' then return private.automation_project_hours(p_job,p_config);
 else return private.automation_dispatch_business(p_job,p_config);end case;
end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and (p.proname like 'automation_%' or p.proname in ('gama_flow_finance','gama_project_time')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
grant execute on function public.gama_flow_finance(text,jsonb),private.gama_flow_finance(text,jsonb),public.gama_project_time(text,jsonb),private.gama_project_time(text,jsonb) to authenticated;
