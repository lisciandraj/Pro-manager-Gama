-- P0: atomic purchases, shared pricing scenarios and accountable refunds.
-- No existing business document is repriced or reassigned.
create function private.erp_module_allowed(p_module text,p_roles text[]) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active and private.current_user_role()=any(p_roles) and p.role=any(p_roles)
  and not coalesce(p_module=any(a.disabled_modules),false)
  and not exists(select 1 from public.app_modules m where m.id=p_module and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
$$;
revoke all on function private.erp_module_allowed(text,text[]) from public,anon;
grant execute on function private.erp_module_allowed(text,text[]) to authenticated;

alter table public.purchase_orders add column destination_location_id uuid references public.warehouse_locations(id);
create index purchase_orders_destination on public.purchase_orders(destination_location_id) where destination_location_id is not null;
create function private.gama_purchase_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();request uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;payload jsonb:=p_data-'request_key';po public.purchase_orders;
 supplier public.suppliers;product public.products;line jsonb;qty numeric;cost numeric;rate numeric;
 net numeric;vat numeric;v_sub numeric:=0;v_tax numeric:=0;result jsonb;location uuid:=nullif(p_data->>'destination_location_id','')::uuid;
begin
 if actor is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase:'||request::text,0));
 select * into receipt from private.command_receipts where domain='purchase' and request_key=request;
 if found then
  if receipt.actor_id<>actor or receipt.payload<>payload then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 select * into supplier from public.suppliers where id=(p_data->>'supplier_id')::uuid and active;
 if not found then raise exception 'SUPPLIER_REQUIRED';end if;
 if location is not null and not exists(select 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id=location and l.active and w.active) then raise exception 'INVALID_LOCATION';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 insert into public.purchase_orders(supplier_id,status,expected_date,notes,created_by,destination_location_id)
 values(supplier.id,'draft',nullif(p_data->>'expected_date','')::timestamptz,nullif(p_data->>'notes',''),actor,location) returning * into po;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  select * into product from public.products where id=(line->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  qty:=(line->>'quantity')::numeric;cost:=(line->>'unit_cost')::numeric;rate:=coalesce(nullif(line->>'tax_rate','')::numeric,product.tax_rate,0);
  if qty is null or qty<=0 or qty>999999999 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
  if cost is null or cost<0 or cost>999999999 or cost<>round(cost,2) then raise exception 'INVALID_PRICE';end if;
  if rate<0 or rate>100 or rate<>round(rate,3) then raise exception 'INVALID_TAX';end if;
  net:=round(qty*cost,2);vat:=round(net*rate/100,2);
  insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,unit_cost,tax_rate,line_total)
   values(po.id,product.id,qty,cost,rate,net+vat);
  v_sub:=v_sub+net;v_tax:=v_tax+vat;
 end loop;
 update public.purchase_orders set subtotal=v_sub,tax=v_tax,total=v_sub+v_tax where id=po.id returning * into po;
 result:=to_jsonb(po);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('purchase',request,actor,payload,result);
 return result;
end $$;
revoke all on function private.gama_purchase_save(jsonb) from public,anon;
grant execute on function private.gama_purchase_save(jsonb) to authenticated;
create function public.gama_purchase_save(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_purchase_save(p_data)$$;
revoke all on function public.gama_purchase_save(jsonb) from public,anon;
grant execute on function public.gama_purchase_save(jsonb) to authenticated;

alter table public.commercial_matrix drop constraint commercial_matrix_product_id_supplier_id_key;
alter table public.commercial_matrix
 add column scenario_name text not null default 'Simulación',
 add column additional_cost numeric(14,2) not null default 0 check(additional_cost>=0),
 add column target_margin numeric(8,3) check(target_margin>=0 and target_margin<100),
 add column base_sale_price numeric(14,2),
 add column created_by uuid references auth.users(id),
 add column applied_by uuid references auth.users(id),
 add column applied_at timestamptz,
 add column request_key uuid unique;
revoke insert,update,delete on public.commercial_matrix from authenticated,anon;
create function private.gama_matrix_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();product public.products;m public.commercial_matrix;
 cost numeric;extra numeric;target numeric;request uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;result jsonb;
begin
 if actor is null or not private.erp_module_allowed('matrix',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='save' then
  if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('matrix:'||request::text,0));
  select * into receipt from private.command_receipts where domain='matrix' and request_key=request;
  if found then
   if receipt.actor_id<>actor or receipt.payload<>p_data-'request_key' then raise exception 'REQUEST_KEY_REUSED';end if;
   return receipt.result;
  end if;
  select * into product from public.products where id=(p_data->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  cost:=(p_data->>'purchase_price')::numeric;extra:=coalesce((p_data->>'additional_cost')::numeric,0);target:=(p_data->>'target_margin')::numeric;
  if cost is null or cost<=0 or cost>999999999 or extra<0 or extra>999999999 or target is null or target<0 or target>=100 then raise exception 'INVALID_PRICE';end if;
  if nullif(p_data->>'supplier_id','') is not null and not exists(select 1 from public.suppliers where id=(p_data->>'supplier_id')::uuid and active) then raise exception 'SUPPLIER_REQUIRED';end if;
  insert into public.commercial_matrix(product_id,supplier_id,purchase_price,sale_price,additional_cost,target_margin,base_sale_price,scenario_name,created_by,request_key)
  values(product.id,nullif(p_data->>'supplier_id','')::uuid,round(cost,2),round((cost+extra)/(1-target/100),2),round(extra,2),target,product.sale_price,left(coalesce(nullif(btrim(p_data->>'scenario_name'),''),'Simulación'),120),actor,request) returning * into m;
  result:=to_jsonb(m);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('matrix',request,actor,p_data-'request_key',result);
  return result;
 end if;
 select * into m from public.commercial_matrix where id=(p_data->>'id')::uuid for update;
 if not found then raise exception 'SCENARIO_NOT_FOUND';end if;
 if p_action='archive' then
  update public.commercial_matrix set active=false,updated_at=now() where id=m.id;
  return jsonb_build_object('id',m.id,'archived',true);
 elsif p_action='apply' then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_REQUIRED';end if;
  if m.applied_at is not null then return to_jsonb(m);end if;
  if not m.active then raise exception 'SCENARIO_ARCHIVED';end if;
  select * into product from public.products where id=m.product_id and active for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if m.base_sale_price is null or product.sale_price is distinct from m.base_sale_price then raise exception 'PRICE_CHANGED_RECALCULATE';end if;
  update public.products set sale_price=m.sale_price where id=m.product_id;
  update public.commercial_matrix set applied_at=now(),applied_by=actor,updated_at=now() where id=m.id returning * into m;
  return to_jsonb(m);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_matrix_action(text,jsonb) from public,anon;
grant execute on function private.gama_matrix_action(text,jsonb) to authenticated;
create function public.gama_matrix_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_matrix_action(p_action,p_data)$$;
revoke all on function public.gama_matrix_action(text,jsonb) from public,anon;
grant execute on function public.gama_matrix_action(text,jsonb) to authenticated;

alter table public.return_refunds add column financial_account_id uuid references public.financial_accounts(id);
create index return_refunds_account on public.return_refunds(financial_account_id) where financial_account_id is not null;
-- Patch the existing settlement implementation, retaining all its established checks.
do $$declare source text:=pg_get_functiondef('private.gama_returns_settlement(text,jsonb,jsonb,date)'::regprocedure);begin
 if position('elsif p_action=''refund'' then' in source)=0 then raise exception 'REFUND_ANCHOR_MISSING';end if;
 source:=replace(source,'elsif p_action=''refund'' then', $body$elsif p_action='refund' then
  if not coalesce((rights->>'refund')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  if nullif(p_data->>'request_key','') is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('refund:'||(p_data->>'request_key'),0));
  select to_jsonb(f) into j from public.return_refunds f where f.request_key=(p_data->>'request_key')::uuid;
  if j is not null then
   if j->>'return_id' is distinct from o.id::text or j->>'created_by' is distinct from u::text
    or (j->>'amount')::numeric is distinct from (p_data->>'amount')::numeric
    or j->>'financial_account_id' is distinct from p_data->>'financial_account_id'
    or j->>'method' is distinct from p_data->>'method'
    or coalesce(j->>'reference','')<>coalesce(p_data->>'reference','')
    or (j->>'paid_at')::date is distinct from coalesce(nullif(p_data->>'paid_at','')::date,today)
   then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',j->>'id','amount',j->'amount');
  end if;
  if not exists(select 1 from public.financial_accounts a
   where a.id=nullif(p_data->>'financial_account_id','')::uuid and a.active
    and a.account_id is not null and a.currency=(select currency from public.company_settings where id))
  then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
$body$);
 source:=replace(source,'return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by)', 'return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by,financial_account_id)');
 source:=replace(source,'nullif(p_data->>''request_key'','''')::uuid,u)', 'nullif(p_data->>''request_key'','''')::uuid,u,(p_data->>''financial_account_id'')::uuid)');
 execute source;
 source:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
 if position('bank:=(select id from public.accounting_accounts where code=''1000'');' in source)=0 then raise exception 'REFUND_POST_ANCHOR_MISSING';end if;
 source:=replace(source,'bank:=(select id from public.accounting_accounts where code=''1000'');',
 'bank:=(select account_id from public.financial_accounts where id=rc.financial_account_id); if bank is null then return null;end if;');
 execute source;
end $$;
create function private.gama_refund_accounts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_module_allowed('returns',array['administrador','comercial'])
  or not coalesce((private.gama_returns_rights()->>'refund')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'currency',a.currency,'kind',a.kind) order by a.name),'[]')
 from public.financial_accounts a where a.active and a.account_id is not null and a.currency=(select currency from public.company_settings where id));
end $$;
revoke all on function private.gama_refund_accounts() from public,anon;
grant execute on function private.gama_refund_accounts() to authenticated;
create function public.gama_refund_accounts() returns jsonb language sql security invoker set search_path='' as $$select private.gama_refund_accounts()$$;
revoke all on function public.gama_refund_accounts() from public,anon;
grant execute on function public.gama_refund_accounts() to authenticated;

create or replace view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 f.opening_balance
  +coalesce((select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status='posted'),0)
  -coalesce((select sum(r.amount) from public.return_refunds r where r.financial_account_id=f.id),0) current_balance,
 coalesce((select count(*) from public.bank_transactions t where t.financial_account_id=f.id and t.status='unmatched'),0) unmatched
from public.financial_accounts f;
revoke all on private.gama_cash_position from public,anon,authenticated;
