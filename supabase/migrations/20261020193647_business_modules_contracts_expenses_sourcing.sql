-- Internal contracts, expense claims and multi-product supplier consultations.
-- Existing sales, purchasing and accounting gateways remain authoritative.
create table private.customer_contracts (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 100),
 customer_id uuid not null references public.customers(id), delivery_address text not null check(length(btrim(delivery_address)) between 1 and 500),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 price_mode text not null check(price_mode in ('current','fixed')),
 frequency text not null check(frequency in ('weekly','monthly')), interval_count integer not null check(interval_count between 1 and 12),
 anchor_day integer not null check(anchor_day between 1 and 31), start_date date not null, next_date date not null, end_date date,
 active boolean not null default true, automatic boolean not null default true,
 notes text not null default '' check(length(notes)<=2000), last_error text, version integer not null default 1,
 created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now(),
 check(end_date is null or end_date>=start_date)
);
create index customer_contracts_customer on private.customer_contracts(customer_id);
create index customer_contracts_due on private.customer_contracts(next_date) where active;
create index customer_contracts_actor on private.customer_contracts(created_by);
create table private.contract_occurrences (
 id uuid primary key default gen_random_uuid(), contract_id uuid not null references private.customer_contracts(id),
 due_date date not null, order_id uuid unique references public.sales_orders(id),
 status text not null check(status in ('draft','skipped')), created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), unique(contract_id,due_date)
);
create index contract_occurrences_creator on private.contract_occurrences(created_by);
create table private.expense_claims (
 id uuid primary key references public.expenses(id), employee_id uuid references public.hr_employees(id), vehicle_id uuid references public.fleet_vehicles(id),
 paid_by text not null check(paid_by in ('company','employee')), status text not null default 'draft' check(status in ('draft','submitted','approved','paid','rejected')),
 due_date date not null, purpose text not null default '' check(length(purpose)<=500), reason text not null default '' check(length(reason)<=1000),
 ocr_id uuid unique references private.supplier_ocr_intakes(id), liability_account_id uuid references public.accounting_accounts(id),
 payment_entry_id uuid unique references public.accounting_entries(id), paid_on date, payment_reference text,
 approved_by uuid references public.profiles(id), approved_at timestamptz, created_by uuid not null references public.profiles(id),
 request_fingerprint text, version integer not null default 1, updated_at timestamptz not null default now(),
 check(paid_by<>'employee' or employee_id is not null)
);
create index expense_claims_employee on private.expense_claims(employee_id);
create index expense_claims_vehicle on private.expense_claims(vehicle_id);
create index expense_claims_creator on private.expense_claims(created_by);
create index expense_claims_approver on private.expense_claims(approved_by);
create index expense_claims_liability on private.expense_claims(liability_account_id);
create table private.purchase_consultations (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 120),
 required_on date, lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 status text not null default 'open' check(status in ('open','awarded','cancelled')),
 version integer not null default 1, created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now()
);
create index purchase_consultations_creator on private.purchase_consultations(created_by);
create table private.consultation_offers (
 id uuid primary key default gen_random_uuid(), consultation_id uuid not null references private.purchase_consultations(id),
 supplier_id uuid not null references public.suppliers(id), reference text not null default '' check(length(reference)<=100),
 currency text not null check(currency ~ '^[A-Z]{3}$'), valid_until date not null,
 payment_terms_days integer not null default 0 check(payment_terms_days between 0 and 365),
 lead_days integer not null default 0 check(lead_days between 0 and 365), freight numeric(18,2) not null default 0 check(freight>=0),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 notes text not null default '' check(length(notes)<=2000), purchase_order_id uuid unique references public.purchase_orders(id),
 award_reason text, version integer not null default 1, created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now(),
 unique(consultation_id,supplier_id)
);
create index consultation_offers_supplier on private.consultation_offers(supplier_id);
create index consultation_offers_creator on private.consultation_offers(created_by);
do $$declare t text;begin
 foreach t in array array['customer_contracts','contract_occurrences','expense_claims','purchase_consultations','consultation_offers'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;

create function private.business_require(p_module text,p_action text default 'view') returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(p_module,array['administrador','comercial'])
 or (p_action<>'view' and not private.erp_action_allowed(p_module,p_action)) then raise exception 'ROLE_NOT_ALLOWED';end if;
end $$;
create function private.contract_next(s private.customer_contracts,p_date date) returns date
language plpgsql immutable set search_path='' as $$
#variable_conflict use_column
declare m date;begin
 if s.frequency='weekly' then return p_date+7*s.interval_count;end if;
 m:=(date_trunc('month',p_date)+make_interval(months=>s.interval_count))::date;
 return m+least(s.anchor_day,extract(day from m+interval '1 month -1 day')::integer)-1;
end $$;
create function private.contract_generate(p_id uuid,p_date date,p_skip boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s private.customer_contracts;occ private.contract_occurrences;answer jsonb;ls jsonb;next_day date;today date:=(now() at time zone private.erp_timezone())::date;
begin
 perform private.business_require('contracts','edit');perform private.business_require('sales-orders','create');
 select * into s from private.customer_contracts where id=p_id for update;if not found then raise exception 'NOT_FOUND';end if;
 select * into occ from private.contract_occurrences where contract_id=s.id and due_date=p_date;
 if found then return jsonb_build_object('id',occ.order_id,'status',occ.status,'existing',true);end if;
 if not s.active or p_date is distinct from s.next_date or p_date>today or (s.end_date is not null and p_date>s.end_date) then raise exception 'CONTRACT_NOT_DUE';end if;
 if not exists(select 1 from public.customers where id=s.customer_id and active) then raise exception 'CUSTOMER_REQUIRED';end if;
 insert into private.contract_occurrences(contract_id,due_date,status,created_by) values(s.id,p_date,case when p_skip then 'skipped' else 'draft' end,auth.uid()) returning * into occ;
 if not p_skip then
  select jsonb_agg(x||jsonb_build_object('price_mode',case when s.price_mode='fixed' then 'manual' else 'auto' end,'price_reason','Contrato · '||s.name)) into ls from jsonb_array_elements(s.lines)x;
  answer:=private.gama_sales_action('create',jsonb_build_object('request_key',occ.id,'source','manual','customer_id',s.customer_id,'delivery_address',s.delivery_address,'notes','Contrato · '||s.name||' · '||p_date||E'\n'||s.notes,'lines',ls));
  update private.contract_occurrences set order_id=(answer->>'id')::uuid where id=occ.id;
 end if;
 next_day:=private.contract_next(s,p_date);
 while next_day<=today loop next_day:=private.contract_next(s,next_day);end loop;
 update private.customer_contracts set next_date=next_day,active=(end_date is null or next_day<=end_date),last_error=null,version=version+1,updated_at=now() where id=s.id;
 return jsonb_build_object('id',answer->>'id','status',case when p_skip then 'skipped' else 'draft' end);
end $$;
create function private.coco_contracts(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s private.customer_contracts;target uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());x jsonb;ls jsonb:='[]';p public.products;today date:=(now() at time zone private.erp_timezone())::date;v integer;search text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>100000 then raise exception 'INVALID_REQUEST';end if;
 perform private.business_require('contracts',case when p_action in ('list','lookups') then 'view' when p_action='save' and coalesce((p_data->>'version')::integer,0)=0 then 'create' else 'edit' end);
 perform private.business_require('sales-orders');
 if p_action='lookups' then
  if p_data->>'kind'='customers' then return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,address from public.customers where active and (name ilike '%'||search||'%' or id::text=p_data->>'selected') order by name limit 50)r),'[]');end if;
  return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,reference,sale_price,tax_rate from public.products where active and (concat_ws(' ',name,reference,barcode) ilike '%'||search||'%' or id::text=p_data->>'selected') order by name limit 50)r),'[]');
 elsif p_action='list' then
  return jsonb_build_object('today',today,'total',(select count(*) from private.customer_contracts s join public.customers c on c.id=s.customer_id where concat_ws(' ',s.name,c.name) ilike '%'||search||'%'),
   'rows',coalesce((select jsonb_agg(to_jsonb(r)) from(select s.*,c.name customer from private.customer_contracts s join public.customers c on c.id=s.customer_id where concat_ws(' ',s.name,c.name) ilike '%'||search||'%' order by s.active desc,s.next_date,s.id offset off limit 30)r),'[]'),
   'occurrences',coalesce((select jsonb_agg(to_jsonb(r)) from(select o.*,s.name,so.number from private.contract_occurrences o join private.customer_contracts s on s.id=o.contract_id left join public.sales_orders so on so.id=o.order_id order by o.created_at desc limit 100)r),'[]'));
 elsif p_action in ('generate','skip') then return private.contract_generate(target,(p_data->>'due_date')::date,p_action='skip');
 elsif p_action='save' then
  perform pg_advisory_xact_lock(hashtextextended('contract:'||target,0));select * into s from private.customer_contracts where id=target for update;
  if coalesce(s.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  if not exists(select 1 from public.customers where id=(p_data->>'customer_id')::uuid and active) then raise exception 'CUSTOMER_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'lines') a group by a->>'product_id' having count(*)>1) then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   select * into p from public.products where id=(x->>'product_id')::uuid and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not coalesce((x->>'quantity')::numeric>0 and (x->>'quantity')::numeric<=100000 and (x->>'quantity')::numeric=round((x->>'quantity')::numeric,3) and (x->>'unit_price')::numeric>=0 and (x->>'unit_price')::numeric<1000000000,false) then raise exception 'INVALID_LINES';end if;
   ls:=ls||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'quantity',(x->>'quantity')::numeric,'unit_price',(x->>'unit_price')::numeric,'tax_rate',p.tax_rate));
  end loop;
  if (p_data->>'next_date')::date<today or (p_data->>'next_date')::date<(p_data->>'start_date')::date or (nullif(p_data->>'end_date','') is not null and (p_data->>'next_date')::date>(p_data->>'end_date')::date) then raise exception 'INVALID_DATE';end if;
  if exists(select 1 from private.contract_occurrences where contract_id=target and due_date=(p_data->>'next_date')::date) then raise exception 'CONTRACT_DATE_USED';end if;
  insert into private.customer_contracts(id,name,customer_id,delivery_address,lines,price_mode,frequency,interval_count,anchor_day,start_date,next_date,end_date,active,automatic,notes,created_by)
  values(target,p_data->>'name',(p_data->>'customer_id')::uuid,p_data->>'delivery_address',ls,p_data->>'price_mode',p_data->>'frequency',(p_data->>'interval_count')::integer,extract(day from (p_data->>'next_date')::date),(p_data->>'start_date')::date,(p_data->>'next_date')::date,nullif(p_data->>'end_date','')::date,coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'automatic')::boolean,true),coalesce(p_data->>'notes',''),auth.uid())
  on conflict(id) do update set name=excluded.name,customer_id=excluded.customer_id,delivery_address=excluded.delivery_address,lines=excluded.lines,price_mode=excluded.price_mode,frequency=excluded.frequency,interval_count=excluded.interval_count,anchor_day=case when customer_contracts.next_date=excluded.next_date then customer_contracts.anchor_day else excluded.anchor_day end,start_date=excluded.start_date,next_date=excluded.next_date,end_date=excluded.end_date,active=excluded.active,automatic=excluded.automatic,notes=excluded.notes,version=customer_contracts.version+1,updated_at=now(),last_error=null;
  return jsonb_build_object('id',target);
 elsif p_action='toggle' then
  select * into s from private.customer_contracts where id=target for update;if not found then raise exception 'NOT_FOUND';end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  update private.customer_contracts set active=not active,version=version+1,updated_at=now() where id=target;return jsonb_build_object('id',target);
 end if;raise exception 'INVALID_ACTION';end $$;

-- Only this non-exposed job can use the contract's saved delegation. Every run
-- rechecks its author's current rights through the same sales gateway. MFA is
-- never bypassed: when required, preparation waits for an interactive session.
create function private.contract_tick() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s private.customer_contracts;oldsub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');oldclaims text:=coalesce(current_setting('request.jwt.claims',true),'');n integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('contract-tick',0)) then return jsonb_build_object('busy',true);end if;
 for s in select * from private.customer_contracts where active and automatic and next_date<=(now() at time zone private.erp_timezone())::date and (end_date is null or next_date<=end_date) order by next_date,id limit 100 for update skip locked loop
  begin
   perform set_config('request.jwt.claim.sub',s.created_by::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',s.created_by,'role','authenticated','aal','aal1')::text,true);
   perform private.contract_generate(s.id,s.next_date);n:=n+1;
  exception when others then update private.customer_contracts set last_error=case when sqlerrm ~ '^[A-Z_]+$' then sqlerrm else 'PREPARATION_FAILED' end where id=s.id;
  end;
 end loop;
 perform set_config('request.jwt.claim.sub',oldsub,true);perform set_config('request.jwt.claims',oldclaims,true);
 return jsonb_build_object('prepared',n);
end $$;
select cron.schedule('coco-contract-drafts','25 * * * *','select private.contract_tick()');

create function private.coco_expenses(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e public.expenses;c private.expense_claims;target uuid;result jsonb;right_name text;f public.financial_accounts;cfg public.company_settings;entry_id uuid;receipt jsonb;ocr private.supplier_ocr_intakes;search text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));today date:=(now() at time zone private.erp_timezone())::date;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>3600000 then raise exception 'INVALID_REQUEST';end if;
 right_name:=case when p_action in ('list','context','receipts','file') then 'view' when p_action in ('approve','reject') then 'validate' when p_action in ('pay','cancel_payment') then 'pay' when p_action='save' and nullif(p_data->>'id','') is null then 'create' else 'edit' end;
 perform private.business_require('expenses',case when right_name='pay' then 'validate' else right_name end);
 perform private.commercial_require(case when right_name='pay' then 'validate' else right_name end);
 if p_action in ('pay','cancel_payment') and not coalesce((private.gama_accounting_rights()->>'pay')::boolean,false) then raise exception 'PAYMENT_NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('today',today,'rights',private.gama_accounting_rights(),'currency',(select currency from public.company_settings where id),
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.expense_categories where active),'[]'),
   'employees',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name) from public.hr_employees where active),'[]'),
   'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',plate||' · '||brand||' '||model) order by plate) from public.fleet_vehicles where active),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.financial_accounts where active and currency=(select currency from public.company_settings where id)),'[]'));
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from public.expenses e where concat_ws(' ',e.reference,e.description) ilike '%'||search||'%'),
   'rows',coalesce((select jsonb_agg(to_jsonb(r)) from(select e.*,coalesce(c.status,e.status) workflow,c.paid_by,c.employee_id,c.vehicle_id,c.purpose,c.due_date,c.reason,c.paid_on,c.payment_reference,c.ocr_id,coalesce(c.version,0) version,p.full_name employee,v.plate,
    exists(select 1 from public.expense_receipts r where r.expense_id=e.id) has_receipt
    from public.expenses e left join private.expense_claims c on c.id=e.id left join public.hr_employees p on p.id=c.employee_id left join public.fleet_vehicles v on v.id=c.vehicle_id
    where concat_ws(' ',e.reference,e.description) ilike '%'||search||'%' order by e.expense_date desc,e.id offset off limit 30)r),'[]'));
 elsif p_action in ('receipts','file') then
  return private.gama_accounting_action(case when p_action='file' then 'expense_receipt_get' else 'expense_receipts' end,p_data);
 elsif p_action='save' then
  target:=nullif(p_data->>'id','')::uuid;
  perform pg_advisory_xact_lock(hashtextextended('claim:'||coalesce(target::text,p_data->>'request_key'),0));
  if target is null then select id into target from public.expenses where request_key=(p_data->>'request_key')::uuid; if found then
   if not exists(select 1 from private.expense_claims where id=target and request_fingerprint=md5(p_data::text)) then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',target,'existing',true);end if;end if;
  if target is not null then select * into e from public.expenses where id=target for update;if not found or e.status<>'draft' then raise exception 'EXPENSE_POSTED';end if;end if;
  select * into c from private.expense_claims where id=target;
  if coalesce(c.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  if c.status is not null and c.status not in ('draft','rejected') then raise exception 'CLAIM_LOCKED';end if;
  if (p_data->>'expense_date')::date>today or (p_data->>'amount_total')::numeric is distinct from round((p_data->>'amount_untaxed')::numeric+coalesce((p_data->>'tax_amount')::numeric,0),2) then raise exception 'INVALID_AMOUNT';end if;
  if p_data->>'paid_by'='employee' and not exists(select 1 from public.hr_employees where id=nullif(p_data->>'employee_id','')::uuid and active) then raise exception 'EMPLOYEE_REQUIRED';end if;
  if nullif(p_data->>'ocr_id','') is not null then select * into ocr from private.supplier_ocr_intakes where id=(p_data->>'ocr_id')::uuid for update;
   if not found or ocr.state<>'review' or ocr.bill_id is not null then raise exception 'SOURCE_ALREADY_USED';end if;
   if exists(select 1 from private.expense_claims where ocr_id=ocr.id and id is distinct from target) then raise exception 'SOURCE_ALREADY_USED';end if;
  end if;
  result:=private.gama_accounting_action('expense_save',p_data||jsonb_build_object('id',target,'financial_account_id',case when p_data->>'paid_by'='employee' then null else nullif(p_data->>'financial_account_id','') end));
  target:=(result->>'id')::uuid;
  insert into private.expense_claims(id,employee_id,vehicle_id,paid_by,due_date,purpose,ocr_id,created_by,request_fingerprint)
  values(target,nullif(p_data->>'employee_id','')::uuid,nullif(p_data->>'vehicle_id','')::uuid,p_data->>'paid_by',coalesce(nullif(p_data->>'due_date','')::date,today),coalesce(p_data->>'purpose',''),nullif(p_data->>'ocr_id','')::uuid,auth.uid(),md5(p_data::text))
  on conflict(id) do update set employee_id=excluded.employee_id,vehicle_id=excluded.vehicle_id,paid_by=excluded.paid_by,due_date=excluded.due_date,purpose=excluded.purpose,ocr_id=excluded.ocr_id,status='draft',reason='',version=expense_claims.version+1,updated_at=now();
  receipt:=p_data->'receipt';
  if receipt is not null and receipt<>'null'::jsonb then
   if receipt->>'mime_type' not in ('application/pdf','image/jpeg','image/png','image/webp') or receipt->>'data_url' not like 'data:'||(receipt->>'mime_type')||';base64,%' then raise exception 'OCR_FILE_INVALID';end if;
   if not exists(select 1 from public.expense_receipts where expense_id=target and data_url=receipt->>'data_url') then perform private.gama_accounting_action('expense_receipt',receipt||jsonb_build_object('expense_id',target));end if;
  end if;
  if ocr.id is not null and not exists(select 1 from public.expense_receipts where expense_id=target) then
   perform private.gama_accounting_action('expense_receipt',jsonb_build_object('expense_id',target,'filename',ocr.filename,'mime_type',ocr.mime_type,'data_url','data:'||ocr.mime_type||';base64,'||replace(encode(ocr.content,'base64'),E'\n','')));
  end if;
  return result;
 end if;
 target:=(p_data->>'id')::uuid;select * into e from public.expenses where id=target for update;select * into c from private.expense_claims where id=target for update;
 if c.id is null or e.id is null then raise exception 'NOT_FOUND';end if;
 if p_action='pay' and c.status='paid' then return jsonb_build_object('id',target,'existing',true);end if;
 if c.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
 if p_action='submit' then
  if c.status not in ('draft','rejected') or e.status<>'draft' then raise exception 'CLAIM_LOCKED';end if;
  if not exists(select 1 from public.expense_receipts where expense_id=target) then raise exception 'RECEIPT_REQUIRED';end if;
  update private.expense_claims set status='submitted',reason='',version=version+1,updated_at=now() where id=target;
 elsif p_action='reject' then
  if c.status<>'submitted' or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  update private.expense_claims set status='rejected',reason=p_data->>'reason',version=version+1,updated_at=now() where id=target;
 elsif p_action='approve' then
  if c.status<>'submitted' or e.status<>'draft' then raise exception 'CLAIM_LOCKED';end if;
  if c.paid_by='company' and e.financial_account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  select * into cfg from public.company_settings where id;
  update private.expense_claims set status='approved',liability_account_id=case when c.paid_by='employee' then cfg.payable_account_id end,approved_by=auth.uid(),approved_at=now(),version=version+1,updated_at=now() where id=target;
  update public.expenses set source_reviewed=true where id=target;
  perform private.gama_accounting_action('expense_post',jsonb_build_object('id',target));
  if c.paid_by='company' then update private.expense_claims set status='paid',paid_on=e.expense_date where id=target;end if;
 elsif p_action='cancel_payment' then
  if c.status<>'paid' or c.paid_by<>'employee' or c.payment_entry_id is null then raise exception 'CLAIM_LOCKED';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  perform private.gama_accounting_action('entry_reverse',jsonb_build_object('id',c.payment_entry_id,'reason',p_data->>'reason'));
 elsif p_action='pay' then
  if c.status<>'approved' or c.paid_by<>'employee' or e.status<>'posted' then raise exception 'CLAIM_LOCKED';end if;
  if (p_data->>'paid_on')::date>today or (p_data->>'paid_on')::date<e.expense_date or length(btrim(coalesce(p_data->>'reference','')))<3 then raise exception 'INVALID_DATE';end if;
  select * into f from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and currency=e.currency;if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  entry_id:=private.gama_accounting_book('OD',(p_data->>'paid_on')::date,e.reference,'manual',target,'Reembolso · '||e.description,jsonb_build_array(
   jsonb_build_object('account_id',c.liability_account_id,'label','Reembolso · '||e.reference,'debit',e.amount_total),
   jsonb_build_object('account_id',f.account_id,'financial_account_id',f.id,'label',p_data->>'reference','credit',e.amount_total)));
  update private.expense_claims set status='paid',paid_on=(p_data->>'paid_on')::date,payment_reference=left(p_data->>'reference',180),payment_entry_id=entry_id,version=version+1,updated_at=now() where id=target;
 else raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('id',target);
end $$;

create function private.expense_claim_guard() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.expense_claims;begin
 select * into c from private.expense_claims where id=old.id;if not found then return new;end if;
 if c.status in ('submitted','approved','paid') and (new.amount_total,new.amount_untaxed,new.tax_amount,new.financial_account_id,new.expense_date,new.category_id,new.description,new.currency,new.supplier_id,new.project_id,new.tax_id) is distinct from (old.amount_total,old.amount_untaxed,old.tax_amount,old.financial_account_id,old.expense_date,old.category_id,old.description,old.currency,old.supplier_id,old.project_id,old.tax_id) then raise exception 'CLAIM_LOCKED';end if;
 if new.status='posted' and old.status<>'posted' and c.status<>'approved' then raise exception 'CLAIM_APPROVAL_REQUIRED';end if;
 if new.status='cancelled' and c.status in ('submitted','approved','paid') then raise exception 'CLAIM_LOCKED';end if;
 return new;
end $$;
create trigger expense_claim_guard before update on public.expenses for each row execute function private.expense_claim_guard();

create function private.consultation_quote(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare o private.consultation_offers;c private.purchase_consultations;ls jsonb;subtotal numeric;tax numeric;begin
 select * into o from private.consultation_offers where id=p_id;select * into c from private.purchase_consultations where id=o.consultation_id;
 with quantities as(select x,ceil(greatest((r->>'quantity')::numeric,(x->>'minimum')::numeric)/(x->>'pack')::numeric)*(x->>'pack')::numeric quantity
  from jsonb_array_elements(o.lines)x join jsonb_array_elements(c.lines)r on r->>'product_id'=x->>'product_id'),
 priced as(select x,quantity,round(quantity*(x->>'unit_cost')::numeric,2) net from quantities)
 select jsonb_agg(x||jsonb_build_object('quantity',quantity)),sum(net),sum(round(net*(x->>'tax_rate')::numeric/100,2)) into ls,subtotal,tax from priced;
 return to_jsonb(o)||jsonb_build_object('lines',ls,'subtotal',subtotal,'tax',tax,'comparison_total',subtotal+o.freight,'supplier',(select name from public.suppliers where id=o.supplier_id),'late',c.required_on is not null and (now() at time zone private.erp_timezone())::date+o.lead_days>c.required_on);
end $$;
create function private.coco_consultations(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.purchase_consultations;o private.consultation_offers;target uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());ls jsonb:='[]';x jsonb;p public.products;result jsonb;q jsonb;search text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>100000 then raise exception 'INVALID_REQUEST';end if;
 perform private.business_require('gamaPurchasesV14',case when p_action in ('list','get','lookups') then 'view' when p_action='award' then 'create' when coalesce((p_data->>'version')::integer,0)=0 then 'create' else 'edit' end);
 if p_action='lookups' then
  if p_data->>'kind'='suppliers' then return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name from public.suppliers where active and name ilike '%'||search||'%' order by name limit 50)r),'[]');end if;
  return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,reference,purchase_price,tax_rate from public.products where active and concat_ws(' ',name,reference,barcode) ilike '%'||search||'%' order by name limit 50)r),'[]');
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from private.purchase_consultations where name ilike '%'||search||'%'),'rows',coalesce((select jsonb_agg(to_jsonb(r)) from(select c.*,(select count(*) from private.consultation_offers o where o.consultation_id=c.id) offers from private.purchase_consultations c where name ilike '%'||search||'%' order by updated_at desc,id offset off limit 30)r),'[]'));
 elsif p_action='get' then
  select * into c from private.purchase_consultations where id=target;if not found then raise exception 'NOT_FOUND';end if;
  return to_jsonb(c)||jsonb_build_object('currency',(select currency from public.company_settings where id),'offers',coalesce((select jsonb_agg(private.consultation_quote(id) order by updated_at) from private.consultation_offers where consultation_id=target),'[]'));
 elsif p_action='save' then
  perform pg_advisory_xact_lock(hashtextextended('consultation:'||target,0));select * into c from private.purchase_consultations where id=target for update;
  if coalesce(c.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  if c.status is not null and c.status<>'open' then raise exception 'RECORD_CHANGED';end if;
  if exists(select 1 from private.consultation_offers where consultation_id=target) then raise exception 'CONSULTATION_HAS_OFFERS';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   select * into p from public.products where id=(x->>'product_id')::uuid and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not coalesce((x->>'quantity')::numeric>0 and (x->>'quantity')::numeric<=100000 and (x->>'quantity')::numeric=round((x->>'quantity')::numeric,3),false) then raise exception 'INVALID_LINES';end if;
   if exists(select 1 from jsonb_array_elements(ls)l where l->>'product_id'=p.id::text) then raise exception 'INVALID_LINES';end if;
   ls:=ls||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'quantity',(x->>'quantity')::numeric,'tax_rate',p.tax_rate));
  end loop;
  insert into private.purchase_consultations(id,name,required_on,lines,created_by) values(target,p_data->>'name',nullif(p_data->>'required_on','')::date,ls,auth.uid())
  on conflict(id) do update set name=excluded.name,required_on=excluded.required_on,lines=excluded.lines,version=purchase_consultations.version+1,updated_at=now();return jsonb_build_object('id',target);
 elsif p_action='offer_save' then
  select * into c from private.purchase_consultations where id=(p_data->>'consultation_id')::uuid for update;if not found or c.status<>'open' then raise exception 'RECORD_CHANGED';end if;
  select * into o from private.consultation_offers where id=target for update;
  if coalesce(o.version,0)<>coalesce((p_data->>'version')::integer,0) or (o.id is not null and o.consultation_id<>c.id) then raise exception 'RECORD_CHANGED';end if;
  if not exists(select 1 from public.suppliers where id=(p_data->>'supplier_id')::uuid and active) then raise exception 'SUPPLIER_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')<>jsonb_array_length(c.lines) then raise exception 'OFFER_INCOMPLETE';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   if not exists(select 1 from jsonb_array_elements(c.lines)r where r->>'product_id'=x->>'product_id') or exists(select 1 from jsonb_array_elements(ls)r where r->>'product_id'=x->>'product_id') then raise exception 'OFFER_INCOMPLETE';end if;
   if not coalesce((x->>'unit_cost')::numeric>=0 and (x->>'unit_cost')::numeric<1000000000 and (x->>'unit_cost')::numeric=round((x->>'unit_cost')::numeric,2) and (x->>'minimum')::numeric>0 and (x->>'minimum')::numeric<=100000 and (x->>'pack')::numeric>0 and (x->>'pack')::numeric<=100000 and (x->>'tax_rate')::numeric between 0 and 100,false) then raise exception 'INVALID_LINES';end if;
   ls:=ls||jsonb_build_array(jsonb_build_object('product_id',x->>'product_id','unit_cost',(x->>'unit_cost')::numeric,'minimum',(x->>'minimum')::numeric,'pack',(x->>'pack')::numeric,'tax_rate',(x->>'tax_rate')::numeric));
  end loop;
  insert into private.consultation_offers(id,consultation_id,supplier_id,reference,currency,valid_until,payment_terms_days,lead_days,freight,lines,notes,created_by)
  values(target,c.id,(p_data->>'supplier_id')::uuid,coalesce(p_data->>'reference',''),p_data->>'currency',(p_data->>'valid_until')::date,(p_data->>'payment_terms_days')::integer,(p_data->>'lead_days')::integer,(p_data->>'freight')::numeric,ls,coalesce(p_data->>'notes',''),auth.uid())
  on conflict(id) do update set supplier_id=excluded.supplier_id,reference=excluded.reference,currency=excluded.currency,valid_until=excluded.valid_until,payment_terms_days=excluded.payment_terms_days,lead_days=excluded.lead_days,freight=excluded.freight,lines=excluded.lines,notes=excluded.notes,version=consultation_offers.version+1,updated_at=now();return jsonb_build_object('id',target);
 elsif p_action='award' then
  select pc.* into c from private.purchase_consultations pc join private.consultation_offers qo on qo.consultation_id=pc.id where qo.id=target for update of pc;
  select * into o from private.consultation_offers where id=target for update;if not found then raise exception 'NOT_FOUND';end if;
  if o.purchase_order_id is not null then return jsonb_build_object('id',o.purchase_order_id,'existing',true);end if;
  if c.status<>'open' or o.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  if o.currency is distinct from (select currency from public.company_settings where id) or o.valid_until<(now() at time zone private.erp_timezone())::date then raise exception 'OFFER_EXPIRED_OR_CURRENCY';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  q:=private.consultation_quote(o.id);
  result:=private.gama_purchase_save(jsonb_build_object('request_key',o.id,'supplier_id',o.supplier_id,'expected_date',(now() at time zone private.erp_timezone())::date+o.lead_days,'notes','Consulta · '||c.name||' · '||o.reference||E'\nPago: '||o.payment_terms_days||' días. Transporte adicional cotizado: '||o.freight||' '||o.currency||E' (no incluido en las líneas de mercancía).\n'||o.notes,'lines',q->'lines'));
  update private.consultation_offers set purchase_order_id=(result->>'id')::uuid,award_reason=p_data->>'reason',version=version+1,updated_at=now() where id=o.id;
  update private.purchase_consultations set status='awarded',version=version+1,updated_at=now() where id=c.id;return result;
 end if;raise exception 'INVALID_ACTION';end $$;

create function public.coco_contracts(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_contracts(p_action,p_data)$$;
create function public.coco_expenses(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_expenses(p_action,p_data)$$;
create function public.coco_consultations(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_consultations(p_action,p_data)$$;
revoke all on function private.business_require(text,text),private.contract_next(private.customer_contracts,date),private.contract_generate(uuid,date,boolean),private.contract_tick(),private.expense_claim_guard(),private.consultation_quote(uuid),private.coco_contracts(text,jsonb),private.coco_expenses(text,jsonb),private.coco_consultations(text,jsonb),public.coco_contracts(text,jsonb),public.coco_expenses(text,jsonb),public.coco_consultations(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.coco_contracts(text,jsonb),private.coco_expenses(text,jsonb),private.coco_consultations(text,jsonb),public.coco_contracts(text,jsonb),public.coco_expenses(text,jsonb),public.coco_consultations(text,jsonb) to authenticated;

-- Attribute the two configuration records; DDL itself stays in the migration ledger.
select set_config('coco.activity_source_type','chat',true);
select set_config('coco.activity_source_id','coco-business-modules-20261020',true);
select set_config('coco.activity_source_label','Agent Coco · Modules métier',true);
insert into public.app_modules(id,enabled) values('contracts',true),('expenses',true) on conflict(id) do nothing;
insert into private.coco_history_modules(module_id,label,roles) values('contracts','Contratos',array['administrador','comercial']),('expenses','Gastos y justificantes',array['administrador','comercial']);
insert into private.coco_history_tables(table_name,module_id,label,table_schema) values
 ('customer_contracts','contracts','Contrato recurrente','private'),('contract_occurrences','contracts','Pedido del contrato','private'),
 ('expense_claims','expenses','Nota de gastos','private'),('purchase_consultations','gamaPurchasesV14','Consulta a proveedores','private'),('consultation_offers','gamaPurchasesV14','Oferta de proveedor','private');
do $$declare t text;begin foreach t in array array['customer_contracts','contract_occurrences','expense_claims','purchase_consultations','consultation_offers'] loop
 execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
end loop;end $$;

-- Keep the function OID: existing event/proposal RLS policies must use the extension.
do $patch$ declare body text;needle text:='if cfg.table_schema=''private'' and cfg.table_name in';begin
 select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'HISTORY_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,$insert$if cfg.table_schema='private' and cfg.table_name in ('customer_contracts','contract_occurrences') then return private.erp_module_allowed('sales-orders',array['administrador','comercial']);end if;
 if cfg.table_schema='private' and cfg.table_name='expense_claims' then return private.gama_accounting_rights()->>'scope'='all' and private.gama_accounting_may('view');end if;
 if cfg.table_schema='private' and cfg.table_name in ('purchase_consultations','consultation_offers') then return private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);end if;
 $insert$||needle);execute body;
end $patch$;

-- Both consumers lock the same original before linking it to an accounting document.
do $patch$ declare body text;needle text:='elsif p_action=''draft'' then';begin
 select pg_get_functiondef('private.gama_supplier_ocr(text,jsonb)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'OCR_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,needle||'
  if exists(select 1 from private.expense_claims where ocr_id=r.id) then raise exception ''SOURCE_ALREADY_USED'';end if;');execute body;
end $patch$;

-- Approved employee reimbursements remain outgoing until the balanced payment is recorded.
create or replace function private.cash_projection(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare today date:=(now() at time zone private.erp_timezone())::date;s private.cash_scenarios;balance numeric;events jsonb;weeks jsonb;begin
 perform private.commercial_require();
 if nullif(p_data->>'scenario_id','') is not null then select * into s from private.cash_scenarios where id=(p_data->>'scenario_id')::uuid;if not found then raise exception 'NOT_FOUND';end if;end if;
 select coalesce(sum(current_balance),0) into balance from private.gama_cash_position where active;
 with source as(
 select 'receivable' kind,d.document_id id,d.number label,coalesce(d.due_date,today)+coalesce(s.customer_delay,0) due,round(d.balance*coalesce(s.collection_percent,100)/100,2) amount,'in' direction,d.due_date is null missing_date from private.gama_customer_dues() d where d.balance>0
 union all select 'payable',d.document_id,d.number,coalesce(d.due_date,today)+coalesce(s.supplier_delay,0),d.balance,'out',d.due_date is null from private.gama_ec_schedule() d join public.supplier_invoices p on p.id=d.document_id and p.status='posted' where d.side='supplier' and d.balance>0
 union all select 'purchase',p.id,p.order_number,coalesce(p.expected_date::date,today)+coalesce(s.supplier_delay,0),greatest(0,p.total-coalesce((select sum(i.total) from public.supplier_invoices i where i.purchase_order_id=p.id and i.status='posted'),0)),'out',p.expected_date is null from public.purchase_orders p where p.status in ('sent','partial','received')
 union all select 'payroll',null::uuid,'Nómina · '||p.period::text,(p.period+interval '1 month -1 day')::date,sum(greatest(0,p.net-coalesce((select sum(q.amount) from public.hr_payroll_payments q where q.payroll_id=p.id and q.status='confirmed'),0))),'out',false from public.hr_payroll p where p.status='validated' group by p.period
 union all select 'expense_claim',e.id,e.reference,c.due_date,e.amount_total,'out',false from private.expense_claims c join public.expenses e on e.id=c.id where c.status='approved' and c.paid_by='employee' and e.status='posted' and e.currency=(select currency from public.company_settings where id)
 union all select c.kind,c.id,c.label,(c.due_date+make_interval(months=>n))::date,c.amount,c.direction,false from private.cash_commitments c cross join generate_series(0,120)n where c.active and (n=0 or c.repeat_monthly) and ((not c.repeat_monthly and n=0 and c.due_date<=today+90) or (c.repeat_monthly and (c.due_date+make_interval(months=>n))::date between today and today+90)) and (c.end_date is null or (c.due_date+make_interval(months=>n))::date<=c.end_date)
 ),bounded as(select *,greatest(today,due) planned_date from source where amount>0 and due<=today+90)
 select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'label',label,'due_date',due,'planned_date',planned_date,'amount',amount,'direction',direction,'missing_date',missing_date,'basis',case when kind in ('receivable','payable','expense_claim') or (kind='payroll' and id is null) then 'recorded' else 'planned' end) order by planned_date,kind,id),'[]') into events from bounded;
 with buckets as(select n,today+n*7 starts,today+least(90,n*7+6) ends from generate_series(0,12)n),totals as(select b.*,coalesce(sum((e->>'amount')::numeric) filter(where e->>'direction'='in'),0) incoming,coalesce(sum((e->>'amount')::numeric) filter(where e->>'direction'='out'),0) outgoing from buckets b left join jsonb_array_elements(events)e on (e->>'planned_date')::date between b.starts and b.ends group by b.n,b.starts,b.ends),running as(select *,balance+sum(incoming-outgoing) over(order by n) closing from totals)
 select jsonb_agg(jsonb_build_object('from',starts,'to',ends,'incoming',incoming,'outgoing',outgoing,'closing',closing,'below_minimum',closing<coalesce(s.minimum_balance,0)) order by n) into weeks from running;
 return jsonb_build_object('today',today,'currency',(select currency from public.company_settings where id),'balance',balance,'minimum_balance',coalesce(s.minimum_balance,0),'weeks',weeks,'events',events,'scenarios',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by name) from private.cash_scenarios x),'[]'),'commitments',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by due_date,label) from private.cash_commitments x where active),'[]'));
end $$;


-- Reversal from either the claim or the ledger reopens the same payable.
create function private.expense_reimbursement_reversed() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.status='posted' and new.status='reversed' then
  update private.expense_claims set status='approved',paid_on=null,payment_reference=null,version=version+1,updated_at=now()
  where payment_entry_id=new.id and status='paid' and paid_by='employee';
 end if;return new;
end $$;
revoke all on function private.expense_reimbursement_reversed() from public,anon,authenticated,service_role;
create trigger expense_reimbursement_reversed after update of status on public.accounting_entries for each row execute function private.expense_reimbursement_reversed();
