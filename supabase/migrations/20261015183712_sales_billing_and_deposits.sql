-- Deposits share external_invoices and the accounting ledger. They have no
-- stock quantities and require an explicitly configured liability account.
alter table private.sales_workspace_settings add column deposit_account_id uuid references public.accounting_accounts(id);
create table private.sales_down_payments(
 invoice_id uuid not null references public.external_invoices(id),order_id uuid not null references public.sales_orders(id),
 tax_rate numeric(9,4) not null,subtotal numeric(18,2) not null check(subtotal>0),tax numeric(18,2) not null check(tax>=0),
 liability_account_id uuid not null references public.accounting_accounts(id),primary key(invoice_id,tax_rate));
create index sales_down_payments_order on private.sales_down_payments(order_id);
create table private.sales_deposit_uses(
 deposit_invoice_id uuid not null,tax_rate numeric(9,4) not null,invoice_id uuid not null references public.external_invoices(id),
 subtotal numeric(18,2) not null check(subtotal>0),tax numeric(18,2) not null check(tax>=0),
 primary key(deposit_invoice_id,tax_rate,invoice_id),
 foreign key(deposit_invoice_id,tax_rate) references private.sales_down_payments(invoice_id,tax_rate));
create index sales_deposit_uses_invoice on private.sales_deposit_uses(invoice_id);
alter table private.sales_down_payments enable row level security;
alter table private.sales_deposit_uses enable row level security;
revoke all on private.sales_down_payments,private.sales_deposit_uses from public,anon,authenticated;

create function private.sales_deposit_create(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.sales_orders;cfg public.company_settings;client public.customers;account uuid;old private.sales_workspace_requests;
 key uuid:=(p_data->>'request_key')::uuid;inv public.external_invoices;r record;items jsonb:='[]';net numeric;rate numeric;
 target numeric;total_net numeric;remaining numeric;part numeric;tax numeric;taxes numeric:=0;pos integer:=0;cnt integer;begin
 perform private.sales_access('invoice_create');perform pg_advisory_xact_lock(741932,1);
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into old from private.sales_workspace_requests where request_key=key for update;
 if found then
  if old.actor_id<>auth.uid() or old.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;
  if old.response is not null then return old.response;end if;
 else insert into private.sales_workspace_requests(request_key,actor_id,payload) values(key,auth.uid(),p_data);end if;
 select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid for update;
 if not found or o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
 select deposit_account_id into account from private.sales_workspace_settings where id;
 if not exists(select 1 from public.accounting_accounts where id=account and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
 select sum(round(quantity*unit_price,2)) into total_net from public.sales_order_lines where order_id=o.id;
 if p_data->>'kind'='percent' then
  rate:=(p_data->>'amount')::numeric;
  if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<=0 or rate>100 then raise exception 'INVALID_AMOUNT';end if;
  target:=round(total_net*rate/100,2);
 elsif p_data->>'kind'='fixed' then target:=(p_data->>'amount')::numeric;
 else raise exception 'INVALID_DATA';end if;
 if target is null or target::text in ('NaN','Infinity','-Infinity') or target<=0 or target<>round(target,2) then raise exception 'INVALID_AMOUNT';end if;
 if target+coalesce((select sum(d.subtotal) from private.sales_down_payments d join public.external_invoices i on i.id=d.invoice_id
  where d.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0)>total_net then raise exception 'DEPOSIT_EXCEEDS_ORDER';end if;
 if exists(select 1 from public.external_invoice_lines l join public.external_invoices i on i.id=l.invoice_id
  join public.sales_order_lines ol on ol.id=l.order_line_id where ol.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')) then raise exception 'DEPOSIT_BEFORE_FINAL_INVOICE_REQUIRED';end if;
 select count(distinct tax_rate) into cnt from public.sales_order_lines where order_id=o.id;
 remaining:=target;
 for r in select tax_rate,sum(round(quantity*unit_price,2)) net from public.sales_order_lines where order_id=o.id group by tax_rate order by tax_rate loop
  pos:=pos+1;part:=case when pos=cnt then remaining else round(target*r.net/nullif(total_net,0),2) end;remaining:=remaining-part;
  if part<=0 then continue;end if;tax:=round(part*r.tax_rate/100,2);taxes:=taxes+tax;
  items:=items||jsonb_build_array(jsonb_build_object('order_id',o.id,'name','Anticipo / Down payment','qty',1,'price',part,'taxRate',r.tax_rate,'subtotal',part,'tax',tax,'is_down_payment',true));
 end loop;
 select * into cfg from public.company_settings where id;select * into client from public.customers where id=o.customer_id;
 insert into public.external_invoices(request_key,order_id,number,software,issue_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot)
 values(key,o.id,'FI-'||to_char((now() at time zone private.erp_timezone())::date,'YYYY')||'-'||lpad(nextval('private.gama_internal_invoice_number')::text,8,'0'),
 'Coco ERP',(now() at time zone private.erp_timezone())::date,target,taxes,'unverified',auth.uid(),'internal',o.source_quote_id,
 jsonb_build_object('sales_schema','coco.sales.invoice.v2','invoice_role','down_payment','liability_account_id',account,
 'company',private.gama_company_public(cfg),'order_number',o.number,'orders',jsonb_build_array(jsonb_build_object('id',o.id,'number',o.number)),
 'customer',o.customer_name,'customer_identification',o.customer_identification,'lines',items,'details',jsonb_build_object('seller',cfg.legal_name,'sellerRuc',cfg.tax_id,
 'client',o.customer_name,'clientId',o.customer_identification,'clientEmail',client.email,'clientAddress',client.address,'delivery_address',o.delivery_address))) returning * into inv;
 insert into private.sales_down_payments select inv.id,o.id,(x->>'taxRate')::numeric,(x->>'subtotal')::numeric,(x->>'tax')::numeric,account from jsonb_array_elements(items)x;
 insert into private.sales_invoice_orders values(inv.id,o.id,target,taxes);
 update public.external_invoices set due_date=issue_date+payment_terms_days where id=inv.id;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(o.id,'deposit_created',inv.id,auth.uid(),jsonb_build_object('number',inv.number,'subtotal',target));
 update private.sales_workspace_requests set response=jsonb_build_object('id',inv.id,'number',inv.number) where request_key=key;
 return jsonb_build_object('id',inv.id,'number',inv.number);
end $$;

create function private.sales_deposit_deductions(p_orders uuid[],p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;items jsonb:='[]';net numeric;tax numeric;capacity numeric;begin
 for d in select dp.*,i.number,dp.subtotal-coalesce((select sum(u.subtotal) from private.sales_deposit_uses u join public.external_invoices used on used.id=u.invoice_id
  where u.deposit_invoice_id=dp.invoice_id and u.tax_rate=dp.tax_rate and used.fiscal_status not in ('cancelled','rejected')),0) available_net,
  dp.tax-coalesce((select sum(u.tax) from private.sales_deposit_uses u join public.external_invoices used on used.id=u.invoice_id
  where u.deposit_invoice_id=dp.invoice_id and u.tax_rate=dp.tax_rate and used.fiscal_status not in ('cancelled','rejected')),0) available_tax
  from private.sales_down_payments dp join public.external_invoices i on i.id=dp.invoice_id
  where dp.order_id=any(p_orders) and i.fiscal_status not in ('cancelled','rejected') order by i.created_at,dp.invoice_id,dp.tax_rate for update of dp loop
  select coalesce(sum((x->>'subtotal')::numeric),0)-coalesce((select -sum((y->>'subtotal')::numeric) from jsonb_array_elements(items)y
   where y->>'order_id'=d.order_id::text and (y->>'taxRate')::numeric=d.tax_rate),0) into capacity
   from jsonb_array_elements(p_items)x where x->>'order_id'=d.order_id::text and (x->>'taxRate')::numeric=d.tax_rate;
  net:=least(d.available_net,greatest(0,capacity));if net<=0 then continue;end if;
  tax:=case when net=d.available_net then d.available_tax else least(d.available_tax,round(net*d.tax_rate/100,2)) end;
  items:=items||jsonb_build_array(jsonb_build_object('order_id',d.order_id,'name','Deducción anticipo '||d.number,'qty',-1,'price',net,'taxRate',d.tax_rate,
   'subtotal',-net,'tax',-tax,'is_deposit_deduction',true,'deposit_invoice_id',d.invoice_id,'liability_account_id',d.liability_account_id));
 end loop;return items;
end $$;
-- Reuse the existing transaction and quantity allocations. Deduction lines never
-- enter external_invoice_lines (which represent actual invoiced merchandise).
do $$declare src text;old text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 src:=replace(src,'links uuid[];begin','links uuid[];deductions jsonb;begin');
 old:='if items=''[]''::jsonb then raise exception ''NO_DELIVERED_UNBILLED'';end if;';
 if strpos(src,old)=0 then raise exception 'DEPOSIT_INVOICE_ANCHOR';end if;
 src:=replace(src,old,old||E'\n deductions:=private.sales_deposit_deductions(ids,items);\n for x in select value from jsonb_array_elements(deductions) loop s:=s+(x->>''subtotal'')::numeric;t:=t+(x->>''tax'')::numeric;end loop;items:=items||deductions;');
 old:='insert into public.external_invoice_lines(invoice_id,order_line_id,quantity) values(inv.id,(x->>''line_id'')::uuid,(x->>''qty'')::numeric);';
 if strpos(src,old)=0 then raise exception 'DEPOSIT_QUANTITY_ANCHOR';end if;
 src:=replace(src,old,'if coalesce((x->>''is_deposit_deduction'')::boolean,false) then
 insert into private.sales_deposit_uses(deposit_invoice_id,tax_rate,invoice_id,subtotal,tax) values((x->>''deposit_invoice_id'')::uuid,(x->>''taxRate'')::numeric,inv.id,-(x->>''subtotal'')::numeric,-(x->>''tax'')::numeric);
 else '||old||'end if;');execute src;
end $$;
-- Commanded quantities and deposits use issue-date terms, instead of waiting
-- for a delivery that the invoice policy does not require.
alter function private.gama_set_invoice_payment_due() rename to gama_set_invoice_payment_due_before_dossier;
create function private.gama_set_invoice_payment_due() returns trigger language plpgsql security definer set search_path='' as $$
declare src text;begin
 if new.document_snapshot->>'invoice_role'='down_payment' or
 (new.document_snapshot->>'sales_schema'='coco.sales.invoice.v2' and exists(select 1 from jsonb_array_elements(new.document_snapshot->'lines') x
  join private.sales_dossier_lines d on d.order_line_id=nullif(x->>'line_id','')::uuid where d.invoice_policy='ordered')) then
  if new.payment_terms_days is null then select c.payment_terms_days into new.payment_terms_days from public.sales_orders o join public.customers c on c.id=o.customer_id where o.id=new.order_id;end if;
  new.due_date:=new.issue_date+new.payment_terms_days;return new;
 end if;
 -- The trigger's original body is inlined below by the checked DDL adaptation.
 return new;
end $$;
do $$declare src text;old text;newbody text;begin
 select pg_get_functiondef('private.gama_set_invoice_payment_due_before_dossier()'::regprocedure) into src;
 select pg_get_functiondef('private.gama_set_invoice_payment_due()'::regprocedure) into newbody;
 old:='declare d date;begin';
 if strpos(src,old)=0 then raise exception 'DEPOSIT_DUE_DATE_ANCHOR';end if;
 newbody:=substring(newbody from 'if new.document_snapshot[\s\S]*?end if;\s*-- The trigger');
 newbody:=split_part(newbody,'-- The trigger',1);
 src:=replace(src,'gama_set_invoice_payment_due_before_dossier','gama_set_invoice_payment_due');
 src:=replace(src,old,old||E'\n'||newbody);execute src;
end $$;
-- Existing triggers still reference the original function OID after a rename.
-- Repoint them explicitly; do not silently leave issue terms inactive.
do $$declare r record;src text;begin
 for r in select t.tgname,c.oid::regclass relation,pg_get_triggerdef(t.oid) definition from pg_trigger t join pg_class c on c.oid=t.tgrelid
 where t.tgfoid='private.gama_set_invoice_payment_due_before_dossier()'::regprocedure loop
  execute format('drop trigger %I on %s',r.tgname,r.relation);
  execute replace(r.definition,'gama_set_invoice_payment_due_before_dossier','gama_set_invoice_payment_due');
 end loop;
end $$;

alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_sales_deposits;
revoke all on function private.gama_accounting_post_before_sales_deposits(text,uuid) from public,anon,authenticated;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare inv public.external_invoices;cfg public.company_settings;o public.sales_orders;eid uuid;lines jsonb;liab uuid;deduction numeric;gross numeric;begin
 if p_source_type<>'sales_invoice' then return private.gama_accounting_post_before_sales_deposits(p_source_type,p_source_id);end if;
 select * into inv from public.external_invoices where id=p_source_id;
 if inv.document_snapshot->>'invoice_role' is distinct from 'down_payment' and not exists(select 1 from jsonb_array_elements(inv.document_snapshot->'lines') x where coalesce((x->>'is_deposit_deduction')::boolean,false)) then
  return private.gama_accounting_post_before_sales_deposits(p_source_type,p_source_id);end if;
 if inv.id is null or inv.fiscal_status in ('cancelled','rejected') then return null;end if;
 perform pg_advisory_xact_lock(741932,1);
 select id into eid from public.accounting_entries where source_type=p_source_type and source_id=p_source_id and status<>'reversed';if eid is not null then return eid;end if;
 select * into cfg from public.company_settings where id;select * into o from public.sales_orders where id=inv.order_id;
 liab:=nullif(inv.document_snapshot->>'liability_account_id','')::uuid;
 lines:=jsonb_build_array(jsonb_build_object('account_id',cfg.receivable_account_id,'label',o.customer_name,'debit',inv.total,'partner_type','customer','partner_id',o.customer_id));
 if inv.document_snapshot->>'invoice_role'='down_payment' then
  if not exists(select 1 from public.accounting_accounts where id=liab and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',liab,'label','Anticipo '||inv.number,'credit',inv.subtotal));
 else
  select coalesce(sum(-(x->>'subtotal')::numeric),0) into deduction from jsonb_array_elements(inv.document_snapshot->'lines')x where coalesce((x->>'is_deposit_deduction')::boolean,false);
  gross:=inv.subtotal+deduction;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.sales_account_id,'label',o.number,'credit',gross));
  select lines||coalesce(jsonb_agg(jsonb_build_object('account_id',a.account_id,'label','Deducción anticipos','debit',a.amount)),'[]') into lines
   from(select (x->>'liability_account_id')::uuid account_id,sum(-(x->>'subtotal')::numeric) amount from jsonb_array_elements(inv.document_snapshot->'lines')x
   where coalesce((x->>'is_deposit_deduction')::boolean,false) group by x->>'liability_account_id')a;
 end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','credit',inv.tax));
 return private.gama_accounting_book('VTA',inv.issue_date,inv.number,'sales_invoice',inv.id,o.customer_name,lines);
end $$;
revoke all on function private.gama_accounting_post(text,uuid) from public,anon,authenticated;

-- Cancellation cannot release a deposit that is already deducted elsewhere.
create function private.sales_deposit_cancel_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.fiscal_status in ('cancelled','rejected') and old.fiscal_status not in ('cancelled','rejected') and
 exists(select 1 from private.sales_deposit_uses u join public.external_invoices i on i.id=u.invoice_id
 where u.deposit_invoice_id=new.id and i.fiscal_status not in ('cancelled','rejected')) then raise exception 'DEPOSIT_ALREADY_DEDUCTED';end if;return new;
end $$;
create trigger sales_deposit_cancel_guard before update on public.external_invoices for each row execute function private.sales_deposit_cancel_guard();

alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_deposits;
revoke all on function private.gama_sales_dossier_before_deposits(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if p_action='deposit_create' then return private.sales_deposit_create(p_data);end if;
 if p_action='deposit_account_save' then
  perform private.sales_access('settings_save');
  if nullif(p_data->>'account_id','') is not null and not exists(select 1 from public.accounting_accounts where id=(p_data->>'account_id')::uuid and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
  update private.sales_workspace_settings set deposit_account_id=nullif(p_data->>'account_id','')::uuid,version=version+1,updated_by=auth.uid(),updated_at=now() where id;
  return private.gama_sales_dossier_before_deposits('configuration','{}');
 elsif p_action='deposit_accounts' then
  perform private.sales_access('settings_save');
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code) order by code) from public.accounting_accounts where active and type='liability'),'[]');
 end if;
 return private.gama_sales_dossier_before_deposits(p_action,p_data);
end $$;
revoke all on function private.gama_sales_dossier(text,jsonb) from public,anon;grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;
do $$declare f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in ('sales_deposit_create','sales_deposit_deductions','sales_deposit_cancel_guard','gama_set_invoice_payment_due_before_dossier') loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
 end loop;
end $$;
