-- Canonical remaining maturities include credits, withholding and adjustments.
create function private.gama_customer_dues(p_customer uuid default null,p_ids uuid[] default null) returns table(document_id uuid,number text,customer_id uuid,customer_name text,email text,phone text,identification text,issue_date date,due_date date,amount numeric,balance numeric,"position" integer)
 language sql stable security definer set search_path='' as $$
 with docs as(select r.id,r.number,r.customer_id,r.customer_name,r.email,c.phone,r.identification,r.issue_date,r.due_date,r.total,r.balance from private.gama_receivables r join public.customers c on c.id=r.customer_id where r.payment_status<>'cancelled' and r.balance>0 and (p_customer is null or r.customer_id=p_customer) and (p_ids is null or r.id=any(p_ids))),
 scheduled as(select d.id document_id,d.number,d.customer_id,d.customer_name,d.email,d.phone,d.identification,d.issue_date,m.due_date,m.amount,
 greatest(0,least(m.amount,d.balance-coalesce(sum(m.amount) over(partition by d.id order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0)))
 +case when row_number() over(partition by d.id order by m.due_date desc,m.position desc)=1 then greatest(0,d.balance-sum(m.amount) over(partition by d.id)) else 0 end balance,m.position
 from docs d join public.accounting_maturities m on m.side='customer' and m.invoice_id=d.id)
 select * from scheduled union all select d.id,d.number,d.customer_id,d.customer_name,d.email,d.phone,d.identification,d.issue_date,d.due_date,d.total,d.balance,1 from docs d where not exists(select 1 from public.accounting_maturities m where m.side='customer' and m.invoice_id=d.id)
$$;
revoke all on function private.gama_customer_dues(uuid,uuid[]) from public,anon,authenticated;

create function private.gama_credit_snapshot(p_customer uuid,p_order uuid default null) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c public.customers;today date:=(now() at time zone private.erp_timezone())::date;receivable numeric;commitment numeric;overdue jsonb;begin
 select * into c from public.customers where id=p_customer;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select coalesce(sum(balance),0),coalesce(jsonb_agg(jsonb_build_object('invoice_id',document_id,'number',number,'due_date',due_date,'balance',balance) order by due_date,document_id,"position") filter(where due_date<today and balance>0),'[]') into receivable,overdue from private.gama_customer_dues(p_customer);
 select coalesce(sum(greatest(0,coalesce((select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) from public.sales_order_lines l where l.order_id=o.id),0)-coalesce((select sum(i.total) from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0))),0) into commitment from public.sales_orders o where (o.customer_id=p_customer and o.status='confirmed') or o.id=p_order;
 return jsonb_build_object('today',today,'customer_id',c.id,'credit_limit',c.credit_limit,'hold_reason',c.credit_hold_reason,'receivable',receivable,'commitment',commitment,'exposure',receivable+commitment,'overdue',overdue,
 'blocked',nullif(c.credit_hold_reason,'') is not null or jsonb_array_length(overdue)>0 or (c.credit_limit is not null and receivable+commitment>c.credit_limit));
end $$;
revoke all on function private.gama_credit_snapshot(uuid,uuid) from public,anon,authenticated;

alter function private.erp_document_fingerprint(text,uuid) rename to erp_document_fingerprint_before_ec_credit;
create function private.erp_document_fingerprint(p_module text,p_id uuid) returns text language plpgsql volatile security definer set search_path='' as $$
declare base text;c uuid;begin
 base:=private.erp_document_fingerprint_before_ec_credit(p_module,p_id);
 if p_module<>'credit' then return base;end if;
 select customer_id into c from public.sales_orders where id=p_id;
 return md5(jsonb_build_object('document',base,'credit',private.gama_credit_snapshot(c,p_id))::text);
end $$;
revoke all on function private.erp_document_fingerprint(text,uuid) from public,anon,authenticated;

-- Keep quote/purchase controls, and replace only the credit part of their guard.
alter function private.erp_commercial_guard() rename to erp_commercial_guard_before_ec_credit;
create function private.gama_enforce_customer_credit(p_customer uuid,p_order uuid,p_allow_exception boolean default true) returns void language plpgsql security definer set search_path='' as $$
declare s jsonb;begin
 perform 1 from public.customers where id=p_customer for update;
 s:=private.gama_credit_snapshot(p_customer,p_order);
 if coalesce((s->>'blocked')::boolean,false) and not (p_allow_exception and exists(select 1 from public.erp_approvals a where a.module='credit' and a.document_id=p_order and a.status='approved' and a.fingerprint=private.erp_document_fingerprint('credit',p_order))) then raise exception 'APPROVAL_REQUIRED:credit:%',p_order;end if;
end $$;
revoke all on function private.gama_enforce_customer_credit(uuid,uuid,boolean) from public,anon,authenticated;
drop trigger erp_commercial_guard on public.sales_orders;
create function private.gama_customer_credit_order_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and (tg_op='INSERT' or old.status='draft' or new.customer_id is distinct from old.customer_id) then
 perform private.gama_enforce_customer_credit(new.customer_id,new.id,tg_op='UPDATE' and new.customer_id is not distinct from old.customer_id);end if;
 return new;end $$;
revoke all on function private.gama_customer_credit_order_guard() from public,anon,authenticated;
create trigger erp_commercial_guard before insert or update on public.sales_orders for each row execute function private.gama_customer_credit_order_guard();
create function private.gama_customer_credit_line_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare order_id uuid:=case when tg_op='DELETE' then old.order_id else new.order_id end;o public.sales_orders;begin
 if tg_op='UPDATE' and new.order_id is not distinct from old.order_id and new.quantity is not distinct from old.quantity and new.unit_price is not distinct from old.unit_price and new.tax_rate is not distinct from old.tax_rate then return null;end if;
 select * into o from public.sales_orders where id=order_id for update;
 if o.status='confirmed' then perform private.gama_enforce_customer_credit(o.customer_id,o.id);end if;return null;end $$;
revoke all on function private.gama_customer_credit_line_guard() from public,anon,authenticated;
create constraint trigger ec_credit_line_guard after insert or update or delete on public.sales_order_lines deferrable initially immediate for each row execute function private.gama_customer_credit_line_guard();

create function private.gama_customer_credit_status(p_customer uuid,p_order uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not (private.erp_module_allowed('sales-orders',array['administrador','comercial']) or private.erp_module_allowed('clients',array['administrador','comercial']) or private.erp_module_allowed('payments',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_order is not null and not exists(select 1 from public.sales_orders where id=p_order and customer_id=p_customer) then raise exception 'ORDER_CUSTOMER_MISMATCH';end if;
 return private.gama_credit_snapshot(p_customer,p_order);end $$;
revoke all on function private.gama_customer_credit_status(uuid,uuid) from public,anon;
grant execute on function private.gama_customer_credit_status(uuid,uuid) to authenticated;
create function public.gama_customer_credit_status(p_customer uuid,p_order uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_customer_credit_status(p_customer,p_order)$$;
revoke all on function public.gama_customer_credit_status(uuid,uuid) from public,anon;
grant execute on function public.gama_customer_credit_status(uuid,uuid) to authenticated;

create function private.gama_customer_aging(p_customer uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;rows jsonb;summary jsonb;c public.customers;lim integer:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,30)));off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));search text:=left(coalesce(p_data->>'search',''),120);begin
 if auth.uid() is null or not private.erp_mfa_ok() or not (private.erp_module_allowed('payments',array['administrador','comercial']) or private.erp_module_allowed('clients',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if coalesce((p_data->>'export')::boolean,false) and not (private.erp_action_allowed('payments','export') or private.erp_action_allowed('clients','export')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_customer is not null then
 select * into c from public.customers where id=p_customer;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by due_date nulls last,document_id,"position"),'[]') into rows from private.gama_customer_dues(p_customer)x where balance>0;
 return jsonb_build_object('today',today,'company',(select jsonb_build_object('legal_name',legal_name,'tax_id',tax_id,'currency',currency,'address',address) from public.company_settings where id),'customer',jsonb_build_object('id',c.id,'name',c.name,'identification',c.identification,'email',c.email,'phone',c.phone),'rows',rows,'total',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(rows)x),0),'overdue',coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(rows)x where (x->>'due_date')::date<today),0));
 end if;
 with dues as(select * from private.gama_customer_dues(null)),groups as(select customer_id id,customer_name name,email,phone,
 sum(balance) balance,sum(balance) filter(where due_date>=today) current,sum(balance) filter(where due_date between today-30 and today-1) days_0_30,sum(balance) filter(where due_date between today-60 and today-31) days_31_60,sum(balance) filter(where due_date between today-90 and today-61) days_61_90,sum(balance) filter(where due_date<today-90) days_over_90,sum(balance) filter(where due_date is null) missing_due,min(due_date) oldest_due
 from dues where balance>0 group by customer_id,customer_name,email,phone),filtered as(select * from groups where name ilike '%'||search||'%')
 select jsonb_build_object('today',today,'total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(z) order by oldest_due nulls last,id) from(select * from filtered order by oldest_due nulls last,id offset off limit lim)z),'[]'),'balance',coalesce((select sum(balance) from filtered),0),'overdue',coalesce((select sum(coalesce(days_0_30,0)+coalesce(days_31_60,0)+coalesce(days_61_90,0)+coalesce(days_over_90,0)) from filtered),0)) into summary;return summary;
end $$;
revoke all on function private.gama_customer_aging(uuid,jsonb) from public,anon;
grant execute on function private.gama_customer_aging(uuid,jsonb) to authenticated;
create function public.gama_customer_aging(p_customer uuid default null,p_data jsonb default '{}') returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_customer_aging(p_customer,p_data)$$;
revoke all on function public.gama_customer_aging(uuid,jsonb) from public,anon;
grant execute on function public.gama_customer_aging(uuid,jsonb) to authenticated;

-- Sales displays the same balance as accounting, in one bounded batch per page.
create function private.gama_sales_invoice_balances(p_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('sales-orders',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if coalesce(cardinality(p_ids),0) not between 1 and 100 then raise exception 'INVOICE_BATCH_REQUIRED';end if;
 return (with dates as(select document_id,min(due_date) due_date from private.gama_customer_dues(null,p_ids) where balance>0 group by document_id) select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'paid',r.paid,'balance',case when r.payment_status='cancelled' then 0 else r.balance end,'payment_status',r.payment_status,'due_date',d.due_date)),'[]') from private.gama_receivables r left join dates d on d.document_id=r.id where r.id=any(p_ids));
end $$;
revoke all on function private.gama_sales_invoice_balances(uuid[]) from public,anon;
grant execute on function private.gama_sales_invoice_balances(uuid[]) to authenticated;
create function public.gama_sales_invoice_balances(p_ids uuid[]) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_sales_invoice_balances(p_ids)$$;
revoke all on function public.gama_sales_invoice_balances(uuid[]) from public,anon;
grant execute on function public.gama_sales_invoice_balances(uuid[]) to authenticated;

-- Checks apply when an Ecuadorian identification is created or changed. Existing
-- historical records can be edited without silently changing their identity.
alter table public.customers add column identification_kind text not null default 'auto' check(identification_kind in ('auto','cedula','ruc_natural','ruc_company','ruc_public','ruc_foreign','foreign_document','consumer'));
alter table public.suppliers add column identification_kind text not null default 'auto' check(identification_kind in ('auto','cedula','ruc_natural','ruc_company','ruc_public','ruc_foreign','foreign_document','consumer'));
create index customer_identification_normalized on public.customers(upper(regexp_replace(identification,'[[:space:]-]','','g'))) where identification is not null;
create index supplier_identification_normalized on public.suppliers(upper(regexp_replace(tax_id,'[[:space:]-]','','g'))) where tax_id is not null;
create function private.gama_ec_identification_valid(p_value text,p_kind text default 'auto') returns boolean language plpgsql immutable set search_path='' as $$
declare v text:=upper(regexp_replace(btrim(p_value),'[[:space:]-]','','g'));kind text:=p_kind;province integer;n integer:=0;x integer;i integer;begin
 if v is null or v='' then return false;end if;
 if kind='foreign_document' then return length(v) between 3 and 20 and v ~ '^[A-Z0-9]+$';end if;
 if kind='consumer' then return v='9999999999999';end if;
 if v !~ '^[0-9]+$' then return false;end if;
 if kind='auto' then kind:=case when length(v)=10 then 'cedula' when length(v)=13 and substring(v,3,1)::integer<6 then 'ruc_natural' when length(v)=13 then 'ruc_company' else 'invalid' end;end if;
 if kind in ('ruc_company','ruc_public','ruc_foreign') then return length(v)=13 and right(v,3)='001' and v<>'0000000000001';end if;
 if kind not in ('cedula','ruc_natural') or length(v)<>(case when kind='cedula' then 10 else 13 end) or (kind='ruc_natural' and right(v,3)<>'001') then return false;end if;
 province:=left(v,2)::integer;if province not between 1 and 24 and province<>30 then return false;end if;
 if substring(v,3,1)::integer>=6 then return false;end if;
 for i in 1..9 loop x:=substring(v,i,1)::integer*case when i%2=1 then 2 else 1 end;if x>9 then x:=x-9;end if;n:=n+x;end loop;
 return (10-n%10)%10=substring(v,10,1)::integer;
end $$;
revoke all on function private.gama_ec_identification_valid(text,text) from public,anon,authenticated;
create function private.gama_partner_identification_guard() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare v text;previous text;kind text;country text;duplicate boolean;begin
 if not exists(select 1 from public.company_settings where id and configured and country='EC') then return new;end if;
 v:=case when tg_table_name='customers' then to_jsonb(new)->>'identification' else to_jsonb(new)->>'tax_id' end;kind:=new.identification_kind;country:=upper(btrim(coalesce(new.country,'')));
 if tg_op='UPDATE' then previous:=case when tg_table_name='customers' then to_jsonb(old)->>'identification' else to_jsonb(old)->>'tax_id' end;if v is not distinct from previous and kind is not distinct from old.identification_kind and new.country is not distinct from old.country then return new;end if;end if;
 if nullif(btrim(v),'') is null then return new;end if;
 v:=upper(regexp_replace(btrim(v),'[[:space:]-]','','g'));
 if country in ('','EC','ECUADOR','ECU') and not private.gama_ec_identification_valid(v,kind) then raise exception 'EC_IDENTIFICATION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('partner-identification:'||tg_table_name||':'||v,0));
 if tg_table_name='customers' then select exists(select 1 from public.customers where upper(regexp_replace(identification,'[[:space:]-]','','g'))=v and id<>new.id) into duplicate;new.identification:=v;
 else select exists(select 1 from public.suppliers where upper(regexp_replace(tax_id,'[[:space:]-]','','g'))=v and id<>new.id) into duplicate;new.tax_id:=v;end if;
 if duplicate then raise exception 'PARTNER_IDENTIFICATION_DUPLICATE';end if;return new;
end $$;
revoke all on function private.gama_partner_identification_guard() from public,anon,authenticated;
create trigger ec_partner_identification before insert or update on public.customers for each row execute function private.gama_partner_identification_guard();
create trigger ec_partner_identification before insert or update on public.suppliers for each row execute function private.gama_partner_identification_guard();

-- Approval is an administrator validation action in the affected module.
alter function private.gama_approval_action(text,jsonb) rename to gama_approval_action_before_ec_credit;
revoke all on function private.gama_approval_action_before_ec_credit(text,jsonb) from authenticated;
create function private.gama_approval_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare module text;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='decide' then select a.module into module from public.erp_approvals a where a.id=(p_data->>'id')::uuid;module:=case when module='credit' then 'sales-orders' else module end;
 if not private.erp_module_allowed(module,array['administrador']) or not private.erp_action_allowed(module,'validate') then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;end if;
 return private.gama_approval_action_before_ec_credit(p_action,p_data);end $$;
revoke all on function private.gama_approval_action(text,jsonb) from public,anon;
grant execute on function private.gama_approval_action(text,jsonb) to authenticated;

-- Changes to receivables serialize with credit decisions for this customer.
create function private.gama_customer_debt_lock() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb:=to_jsonb(new);invoice uuid;customer uuid;begin
 if tg_table_name='external_invoices' then select customer_id into customer from public.sales_orders where id=(j->>'order_id')::uuid;
 else invoice:=nullif(j->>'invoice_id','')::uuid;select o.customer_id into customer from public.external_invoices v join public.sales_orders o on o.id=v.order_id where v.id=invoice;end if;
 if customer is not null then perform 1 from public.customers where id=customer for update;end if;return new;end $$;
revoke all on function private.gama_customer_debt_lock() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['external_invoices','external_invoice_payments','return_credits','accounting_withholdings','accounting_adjustments'] loop
 execute format('create trigger aa_ec_customer_debt_lock before insert or update on public.%I for each row execute function private.gama_customer_debt_lock()',t);end loop;end $$;
