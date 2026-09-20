-- Shared operating policies, contact addresses and a searchable immutable audit.
create table public.erp_policies(
 id boolean primary key default true check(id),
 timezone text not null default 'America/Guayaquil',
 purchase_approval_amount numeric(18,2) check(purchase_approval_amount>=0),
 quote_discount_limit numeric(6,3) check(quote_discount_limit between 0 and 100),
 minimum_margin numeric(6,3) check(minimum_margin>=0 and minimum_margin<100),
 stock_adjustment_limit numeric(18,3) check(stock_adjustment_limit>=0),
 stale_opportunity_days integer not null default 14 check(stale_opportunity_days between 1 and 365),
 escalation_days integer not null default 3 check(escalation_days between 1 and 365),
 stock_visibility text not null default 'exact' check(stock_visibility in ('exact','availability')),
 version integer not null default 1,updated_by uuid references auth.users(id),updated_at timestamptz not null default now()
);
insert into public.erp_policies(id) values(true);
alter table public.erp_policies enable row level security;
revoke all on public.erp_policies from public,anon,authenticated;
grant select,update on public.erp_policies to authenticated;
create policy erp_policies_read on public.erp_policies for select to authenticated using(private.current_user_role() in ('administrador','comercial','almacenero'));
create policy erp_policies_write on public.erp_policies for update to authenticated using(private.erp_module_allowed('settings',array['administrador'])) with check(private.erp_module_allowed('settings',array['administrador']));
create function private.erp_policy_stamp() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if not exists(select 1 from pg_timezone_names where name=new.timezone) then raise exception 'INVALID_TIMEZONE';end if;
 new.version:=old.version+1;new.updated_by:=auth.uid();new.updated_at:=now();return new;
end $$;
revoke all on function private.erp_policy_stamp() from public,anon,authenticated;
create trigger erp_policy_stamp before update on public.erp_policies for each row execute function private.erp_policy_stamp();

create table public.erp_audit_events(
 id bigint generated always as identity primary key,created_at timestamptz not null default now(),actor_id uuid,
 table_name text not null,record_id text,operation text not null,before_data jsonb,after_data jsonb,reason text
);
alter table public.erp_audit_events enable row level security;
revoke all on public.erp_audit_events from public,anon,authenticated;
grant select on public.erp_audit_events to authenticated;
create policy erp_audit_read on public.erp_audit_events for select to authenticated using(private.erp_module_allowed('audit',array['administrador']));
create index erp_audit_date on public.erp_audit_events(created_at desc,id desc);
create index erp_audit_entity on public.erp_audit_events(table_name,record_id,created_at desc);
create index erp_audit_actor on public.erp_audit_events(actor_id,created_at desc);
create function private.erp_audit_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare prior jsonb;next jsonb;skip text[]:=array['photo_data','data_url','signature','document_snapshot','updated_at','has_photo'];begin
 if tg_op<>'INSERT' then prior:=to_jsonb(old)-skip;end if;
 if tg_op<>'DELETE' then next:=to_jsonb(new)-skip;end if;
 if prior is not distinct from next then return null;end if;
 insert into public.erp_audit_events(actor_id,table_name,record_id,operation,before_data,after_data,reason)
 values(auth.uid(),tg_table_name,coalesce(next->>'id',prior->>'id',next->>'profile_id',prior->>'profile_id',next->>'role',prior->>'role'),tg_op,prior,next,nullif(current_setting('architect.change_reason',true),''));
 return null;
end $$;
revoke all on function private.erp_audit_capture() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['products','customers','suppliers','commercial_matrix','customer_special_prices','purchase_orders','purchase_order_lines','sales_orders','sales_order_lines','external_invoices','external_invoice_payments','supplier_invoices','supplier_invoice_payments','financial_accounts','return_refunds','inventory_counts','inventory_count_lines','profiles','role_module_access','accounting_permissions','hr_permissions','company_settings','erp_policies','crm_leads','crm_opportunities','service_tickets','business_documents'] loop
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;
end $$;

alter table public.customers add column credit_limit numeric(18,2) check(credit_limit>=0),add column credit_hold_reason text;
create table public.customer_addresses(
 id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.customers(id),
 label text not null check(length(btrim(label)) between 1 and 120),purpose text not null check(purpose in ('billing','delivery','order')),
 contact_name text,phone text,email text,address text not null,city text,notes text,
 active boolean not null default true,created_by uuid default auth.uid() references auth.users(id),created_at timestamptz not null default now()
);
create index customer_addresses_customer on public.customer_addresses(customer_id);
alter table public.customer_addresses enable row level security;
revoke all on public.customer_addresses from public,anon,authenticated;
grant select,insert,update on public.customer_addresses to authenticated;
create policy customer_addresses_read on public.customer_addresses for select to authenticated using(private.erp_module_allowed('clients',array['administrador','comercial']) and exists(select 1 from public.customers c where c.id=customer_id));
create policy customer_addresses_insert on public.customer_addresses for insert to authenticated with check(private.erp_module_allowed('clients',array['administrador','comercial']) and created_by=auth.uid() and exists(select 1 from public.customers c where c.id=customer_id));
create policy customer_addresses_update on public.customer_addresses for update to authenticated using(private.erp_module_allowed('clients',array['administrador','comercial'])) with check(private.erp_module_allowed('clients',array['administrador','comercial']) and exists(select 1 from public.customers c where c.id=customer_id));

create function public.gama_partner_context(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare entity jsonb;history jsonb:='[]';x jsonb;begin
 if p_kind='customer' then
  if not private.erp_module_allowed('clients',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  select to_jsonb(c) into entity from public.customers c where id=p_id;
  if entity is null then raise exception 'CUSTOMER_REQUIRED';end if;
  if private.dashboard_access('quotes') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','quotes','reference',invoice_number,'status',quote_state,'date',issue_date,'amount',total)),'[]') into x from public.invoices where customer_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('sales-orders') then
   select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'module','sales-orders','reference',o.number,'status',o.status,'date',o.created_at,'amount',(select sum(l.quantity*l.unit_price*(1+l.tax_rate/100)) from public.sales_order_lines l where l.order_id=o.id))),'[]') into x from public.sales_orders o where customer_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('payments') then
   select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'module','payments','reference',i.number,'status',i.fiscal_status,'date',i.issue_date,'amount',i.total,'paid',(select coalesce(sum(p.amount),0) from public.external_invoice_payments p where p.invoice_id=i.id and p.status='confirmed'))),'[]') into x from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('returns') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','returns','reference',number,'status',status,'date',created_at)),'[]') into x from public.return_orders where customer_id=p_id;history:=history||x;
  end if;
  if private.service_access('sav') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','sav','reference',erp_reference,'status',status,'date',created_at,'subject',subject)),'[]') into x from public.service_tickets where customer_id=p_id;history:=history||x;
  end if;
  return jsonb_build_object('entity',entity,'history',history,'addresses',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.customer_addresses a where customer_id=p_id and active),'contacts',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.crm_contacts c where customer_id=p_id and active));
 elsif p_kind='supplier' then
  if not private.erp_module_allowed('suppliers',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  select to_jsonb(s) into entity from public.suppliers s where id=p_id;if entity is null then raise exception 'SUPPLIER_REQUIRED';end if;
  if private.dashboard_access('gamaPurchasesV14') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','gamaPurchasesV14','reference',order_number,'status',status,'date',order_date,'amount',total)),'[]') into x from public.purchase_orders where supplier_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('accounting') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','accounting','reference',number,'status',status,'date',issue_date,'amount',total)),'[]') into x from public.supplier_invoices where supplier_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('returns') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','returns','reference',number,'status',status,'date',created_at)),'[]') into x from public.return_orders where supplier_id=p_id;history:=history||x;
  end if;
  return jsonb_build_object('entity',entity,'history',history,'addresses','[]'::jsonb,'contacts','[]'::jsonb);
 end if;
 raise exception 'INVALID_KIND';
end $$;
revoke all on function public.gama_partner_context(text,uuid) from public,anon;
grant execute on function public.gama_partner_context(text,uuid) to authenticated;
