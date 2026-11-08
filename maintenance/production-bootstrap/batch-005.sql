do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>159
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20260920184610_p1_commercial_controls_and_merge.sql; SHA256 2493b8d0dad9da5899d56896069b01869585c7a000571ac0bb16e2c8b52ebf36
create table public.erp_approvals(
 id uuid primary key default gen_random_uuid(),module text not null check(module in ('gamaPurchasesV14','quotes','credit')),
 document_id uuid not null,fingerprint text not null,reason text not null check(length(btrim(reason))>=3),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_by uuid not null default auth.uid() references auth.users(id),requested_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id),reviewed_at timestamptz,decision_reason text,
 unique(module,document_id,fingerprint)
);
alter table public.erp_approvals enable row level security;
revoke all on public.erp_approvals from public,anon,authenticated;
grant select on public.erp_approvals to authenticated;
create policy erp_approvals_read on public.erp_approvals for select to authenticated using(private.current_user_role()='administrador' or requested_by=auth.uid());
create index erp_approvals_status on public.erp_approvals(status,requested_at);
create trigger erp_audit_capture after insert or update or delete on public.erp_approvals for each row execute function private.erp_audit_capture();

create function private.erp_document_fingerprint(p_module text,p_id uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare h jsonb;l jsonb;begin
 if p_module='gamaPurchasesV14' then
  select to_jsonb(p)-array['status','updated_at'] into h from public.purchase_orders p where id=p_id;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') into l from public.purchase_order_lines p where purchase_order_id=p_id;
 elsif p_module='quotes' then
  select to_jsonb(p)-array['quote_state','quote_sent_at','quote_accepted_at','quote_accepted_by','quote_acceptance_channel','quote_acceptance_reference','updated_at'] into h from public.invoices p where id=p_id;
  select coalesce(jsonb_agg(to_jsonb(ln)||jsonb_build_object('current_cost',p.purchase_price) order by ln.id),'[]') into l from public.invoice_lines ln join public.products p on p.id=ln.product_id where ln.invoice_id=p_id;
 elsif p_module='credit' then
  select to_jsonb(p)-array['status','updated_at'] into h from public.sales_orders p where id=p_id;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') into l from public.sales_order_lines p where order_id=p_id;
 else raise exception 'INVALID_MODULE';end if;
 if h is null then raise exception 'DOCUMENT_NOT_FOUND';end if;return md5(jsonb_build_object('header',h,'lines',l)::text);
end $$;
revoke all on function private.erp_document_fingerprint(text,uuid) from public,anon,authenticated;
create function private.gama_approval_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m text:=p_data->>'module';doc uuid:=nullif(p_data->>'document_id','')::uuid;a public.erp_approvals;fp text;begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='request' then
  if not private.erp_module_allowed(case when m='credit' then 'sales-orders' else m end,array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  fp:=private.erp_document_fingerprint(m,doc);
  insert into public.erp_approvals(module,document_id,fingerprint,reason,requested_by) values(m,doc,fp,p_data->>'reason',auth.uid())
   on conflict(module,document_id,fingerprint) do update set reason=excluded.reason where erp_approvals.status='pending' returning * into a;
  if not found then select * into a from public.erp_approvals where module=m and document_id=doc and fingerprint=fp;end if;
  return to_jsonb(a);
 elsif p_action='decide' then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  select * into a from public.erp_approvals where id=(p_data->>'id')::uuid for update;
  if not found or a.status<>'pending' then raise exception 'APPROVAL_NOT_PENDING';end if;
  if a.fingerprint<>private.erp_document_fingerprint(a.module,a.document_id) then raise exception 'DOCUMENT_CHANGED';end if;
  if p_data->>'decision' not in ('approved','rejected') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  update public.erp_approvals set status=p_data->>'decision',reviewed_by=auth.uid(),reviewed_at=now(),decision_reason=p_data->>'reason' where id=a.id returning * into a;
  return to_jsonb(a);
 end if;raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_approval_action(text,jsonb) from public,anon;
grant execute on function private.gama_approval_action(text,jsonb) to authenticated;
create function public.gama_approval_action(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_approval_action(p_action,p_data)$$;
revoke all on function public.gama_approval_action(text,jsonb) from public,anon;
grant execute on function public.gama_approval_action(text,jsonb) to authenticated;

create function private.erp_commercial_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare policy public.erp_policies;m text;requires_approval boolean:=false;gross numeric;cost numeric;discount numeric;customer public.customers;exposure numeric;begin
 select * into policy from public.erp_policies where id;
 if tg_table_name='purchase_orders' then
  if new.status<>'sent' or old.status<>'draft' then return new;end if;
  m:='gamaPurchasesV14';requires_approval:=policy.purchase_approval_amount is not null and new.total>policy.purchase_approval_amount;
 elsif tg_table_name='invoices' then
  if new.quote_state not in ('sent','accepted') or new.quote_state is not distinct from old.quote_state then return new;end if;
  m:='quotes';
  select sum(l.quantity*l.unit_price),sum(l.quantity*p.purchase_price),max(coalesce(l.quote_discount,0)) into gross,cost,discount from public.invoice_lines l join public.products p on p.id=l.product_id where l.invoice_id=new.id;
  requires_approval:=(policy.quote_discount_limit is not null and coalesce(discount,0)>policy.quote_discount_limit)
   or (policy.minimum_margin is not null and (gross<=0 or 100*(gross-cost)/gross<policy.minimum_margin));
 elsif tg_table_name='sales_orders' then
  if new.status<>'confirmed' or old.status<>'draft' then return new;end if;
  m:='credit';select * into customer from public.customers where id=new.customer_id for update;
  if customer.credit_limit is null and nullif(customer.credit_hold_reason,'') is null then return new;end if;
  select coalesce(sum(greatest(0,i.total-coalesce((select sum(p.amount) from public.external_invoice_payments p where p.invoice_id=i.id and p.status='confirmed'),0)-coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=i.id),0))),0) into exposure
   from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=customer.id and i.fiscal_status not in ('cancelled','rejected');
  select exposure+coalesce(sum(greatest(0,(select sum(l.quantity*l.unit_price*(1+l.tax_rate/100)) from public.sales_order_lines l where l.order_id=o.id)-coalesce((select sum(i.total) from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0))),0) into exposure from public.sales_orders o where o.customer_id=customer.id and (o.status='confirmed' or o.id=new.id);
  requires_approval:=nullif(customer.credit_hold_reason,'') is not null or (customer.credit_limit is not null and exposure>customer.credit_limit);
 else return new;end if;
 if requires_approval and not exists(select 1 from public.erp_approvals a where a.module=m and a.document_id=new.id and a.status='approved' and a.fingerprint=private.erp_document_fingerprint(m,new.id)) then
  raise exception 'APPROVAL_REQUIRED:%:%',m,new.id;
 end if;return new;
end $$;
revoke all on function private.erp_commercial_guard() from public,anon,authenticated;
create trigger erp_commercial_guard before update on public.purchase_orders for each row execute function private.erp_commercial_guard();
create trigger erp_commercial_guard before update on public.invoices for each row execute function private.erp_commercial_guard();
create trigger erp_commercial_guard before update on public.sales_orders for each row execute function private.erp_commercial_guard();
create function private.erp_customer_credit_guard() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if auth.uid() is not null and ((tg_op='INSERT' and (new.credit_limit is not null or nullif(new.credit_hold_reason,'') is not null)) or (tg_op='UPDATE' and (new.credit_limit is distinct from old.credit_limit or new.credit_hold_reason is distinct from old.credit_hold_reason))) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'CREDIT_ADMIN_REQUIRED';end if;return new;end $$;
revoke all on function private.erp_customer_credit_guard() from public,anon,authenticated;
create trigger erp_customer_credit_guard before insert or update on public.customers for each row execute function private.erp_customer_credit_guard();

-- Explicit, previewable merge. Existing issued-document snapshots remain unchanged.
create function private.gama_merge_partner(p_kind text,p_source uuid,p_target uuid,p_confirm boolean default false,p_reason text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare tbl text;source jsonb;target jsonb;fk record;n integer;links jsonb:='[]';begin
 if auth.uid() is null or coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_source=p_target then raise exception 'MERGE_SAME_RECORD';end if;
 perform pg_advisory_xact_lock(hashtextextended('merge:'||p_kind,0));
 tbl:=case p_kind when 'customer' then 'customers' when 'lead' then 'crm_leads' when 'supplier' then 'suppliers' end;
 if tbl is null then raise exception 'INVALID_KIND';end if;
 if not private.erp_module_allowed(case p_kind when 'customer' then 'clients' when 'supplier' then 'suppliers' else 'crm' end,array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',tbl) into source using p_source;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',tbl) into target using p_target;
 if source is null or target is null or not (source->>'active')::boolean or not (target->>'active')::boolean then raise exception 'MERGE_RECORD_REQUIRED';end if;
 if p_kind='customer' and lower(coalesce(source->>'email',''))<>lower(coalesce(target->>'email',''))
  and exists(select 1 from auth.users u join public.profiles p on p.id=u.id where p.role='cliente' and lower(u.email)=lower(source->>'email')) then raise exception 'MERGE_PORTAL_IDENTITY_CONFLICT';end if;
 if p_kind='lead' and source->>'converted_customer_id' is not null and source->>'converted_customer_id' is distinct from target->>'converted_customer_id' then raise exception 'MERGE_CONVERTED_LEAD_CONFLICT';end if;
 for fk in select c.conrelid::regclass rel,a.attname col from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid=format('public.%I',tbl)::regclass and array_length(c.conkey,1)=1 loop
  execute format('select count(*) from %s where %I=$1',fk.rel,fk.col) into n using p_source;
  links:=links||jsonb_build_array(jsonb_build_object('table',fk.rel::text,'column',fk.col,'rows',n));
 end loop;
 if not p_confirm then return jsonb_build_object('source',source,'target',target,'links',links);end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'REASON_REQUIRED';end if;
 perform set_config('architect.change_reason','Merge: '||p_reason,true);
 -- Unique collisions intentionally abort the transaction; users resolve competing
 -- contractual prices before merging instead of silently losing either record.
 for fk in select c.conrelid::regclass rel,a.attname col from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid=format('public.%I',tbl)::regclass and array_length(c.conkey,1)=1 loop
  execute format('update %s set %I=$2 where %I=$1',fk.rel,fk.col,fk.col) using p_source,p_target;
 end loop;
 execute format('update public.%I set notes=concat_ws(E''\n'',notes,$2) where id=$1',tbl) using p_target,'['||coalesce(source->>'name',source->>'company',source->>'first_name',p_source::text)||'] '||coalesce(source->>'notes','');
 execute format('update public.%I set active=false where id=$1',tbl) using p_source;
 return jsonb_build_object('source_id',p_source,'target_id',p_target,'merged',true,'links',links);
end $$;
revoke all on function private.gama_merge_partner(text,uuid,uuid,boolean,text) from public,anon;
grant execute on function private.gama_merge_partner(text,uuid,uuid,boolean,text) to authenticated;
create function public.gama_merge_partner(p_kind text,p_source uuid,p_target uuid,p_confirm boolean default false,p_reason text default null) returns jsonb language sql security invoker set search_path='' as $$select private.gama_merge_partner(p_kind,p_source,p_target,p_confirm,p_reason)$$;
revoke all on function public.gama_merge_partner(text,uuid,uuid,boolean,text) from public,anon;
grant execute on function public.gama_merge_partner(text,uuid,uuid,boolean,text) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184610','p1_commercial_controls_and_merge','2493b8d0dad9da5899d56896069b01869585c7a000571ac0bb16e2c8b52ebf36','2493b8d0dad9da5899d56896069b01869585c7a000571ac0bb16e2c8b52ebf36','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184611_p1_price_rules_and_catalog_commands.sql; SHA256 20aee86eb3f3e575f460152229a9d55301340c46972c3baba8f379aba3672677
alter table public.products add column order_minimum numeric(14,3) not null default 0.001 check(order_minimum>0), add column order_multiple numeric(14,3) not null default 0.001 check(order_multiple>0);
alter table public.customer_requests add column requested_delivery_date date;
create table public.erp_price_books(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 160),
 kind text not null check(kind in ('contract','promotion','group')),
 category text check(category in ('A','B','C')),valid_from date not null,valid_to date,
 priority integer not null default 0 check(priority between 0 and 1000),
 status text not null default 'draft' check(status in ('draft','approved','archived')),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),
 approved_by uuid references auth.users(id),approved_at timestamptz,
 check(valid_to is null or valid_to>=valid_from)
);
create table public.erp_price_book_customers(book_id uuid references public.erp_price_books(id) on delete cascade,customer_id uuid references public.customers(id),primary key(book_id,customer_id));
create table public.erp_price_tiers(id uuid primary key default gen_random_uuid(),book_id uuid not null references public.erp_price_books(id) on delete cascade,product_id uuid not null references public.products(id),min_quantity numeric(16,3) not null default 1 check(min_quantity>0),unit_price numeric(16,4) not null check(unit_price>=0),unique(book_id,product_id,min_quantity));
create index erp_price_tiers_product on public.erp_price_tiers(product_id,book_id,min_quantity desc);
do $$declare t text;begin foreach t in array array['erp_price_books','erp_price_book_customers','erp_price_tiers'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 execute format('create policy price_read on public.%I for select to authenticated using(private.erp_module_allowed(''price-lists'',array[''administrador'',''comercial'']))',t);
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
end loop;end $$;
create function private.gama_price_book_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.erp_price_books;l jsonb;customer uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;begin
 if auth.uid() is null or not private.erp_module_allowed('price-lists',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='save' then
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('pricebook:'||key::text,0));
  select * into receipt from private.command_receipts where domain='pricebook' and request_key=key;
  if found then if receipt.actor_id<>auth.uid() or receipt.payload<>p_data-'request_key' then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 1000 then raise exception 'INVALID_LINES';end if;
  insert into public.erp_price_books(name,kind,category,valid_from,valid_to,priority) values(p_data->>'name',p_data->>'kind',nullif(p_data->>'category',''),(p_data->>'valid_from')::date,nullif(p_data->>'valid_to','')::date,coalesce((p_data->>'priority')::integer,0)) returning * into b;
  for l in select value from jsonb_array_elements(p_data->'lines') loop
   if not exists(select 1 from public.products where id=(l->>'product_id')::uuid and active) then raise exception 'PRODUCT_NOT_FOUND';end if;
   insert into public.erp_price_tiers(book_id,product_id,min_quantity,unit_price) values(b.id,(l->>'product_id')::uuid,(l->>'min_quantity')::numeric,(l->>'unit_price')::numeric);
  end loop;
  for customer in select value::uuid from jsonb_array_elements_text(coalesce(p_data->'customers','[]')) loop
   if not exists(select 1 from public.customers where id=customer and active) then raise exception 'CUSTOMER_REQUIRED';end if;
   insert into public.erp_price_book_customers values(b.id,customer);
  end loop;
  if b.kind='contract' and not exists(select 1 from public.erp_price_book_customers where book_id=b.id) then raise exception 'CONTRACT_CUSTOMER_REQUIRED';end if;
 elsif p_action in ('approve','archive') then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  select * into b from public.erp_price_books where id=(p_data->>'id')::uuid for update;if not found then raise exception 'PRICE_BOOK_NOT_FOUND';end if;
  if p_action='approve' and b.status<>'draft' then raise exception 'PRICE_BOOK_NOT_DRAFT';end if;
  update public.erp_price_books set status=case when p_action='approve' then 'approved' else 'archived' end,approved_by=case when p_action='approve' then auth.uid() else approved_by end,approved_at=case when p_action='approve' then now() else approved_at end where id=b.id returning * into b;
 else raise exception 'INVALID_ACTION';end if;
 if p_action='save' then insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('pricebook',key,auth.uid(),p_data-'request_key',to_jsonb(b));end if;
 return to_jsonb(b);
end $$;
revoke all on function private.gama_price_book_action(text,jsonb) from public,anon;
grant execute on function private.gama_price_book_action(text,jsonb) to authenticated;
create function public.gama_price_book_action(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_price_book_action(p_action,p_data)$$;
revoke all on function public.gama_price_book_action(text,jsonb) from public,anon;
grant execute on function public.gama_price_book_action(text,jsonb) to authenticated;

create function private.erp_price(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.customers;p public.products;r record;special numeric;today date;begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=p_customer and active;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 if private.current_user_role()='cliente' and not exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=lower(c.email)) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into p from public.products where id=p_product and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'INVALID_QUANTITY';end if;
 today:=coalesce(p_date,(now() at time zone (select timezone from public.erp_policies where id))::date);
 select b.name,b.kind,t.unit_price into r from public.erp_price_tiers t join public.erp_price_books b on b.id=t.book_id
 where t.product_id=p_product and t.min_quantity<=p_quantity and b.status='approved' and today>=b.valid_from and (b.valid_to is null or today<=b.valid_to)
  and (b.category is null or b.category=c.category)
  and (exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id and bc.customer_id=c.id)
       or (b.kind<>'contract' and not exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id)))
 order by case b.kind when 'contract' then 3 when 'promotion' then 2 else 1 end desc,b.priority desc,t.min_quantity desc,b.valid_from desc,b.id limit 1;
 select unit_price into special from public.customer_special_prices where customer_id=c.id and product_id=p.id;
 if r.kind='contract' then return jsonb_build_object('unit_price',r.unit_price,'source','contract','label',r.name,'date',today,'quantity',p_quantity);end if;
 if c.category='C' and special is not null then return jsonb_build_object('unit_price',special,'source','customer_contract','label','Contrato cliente','date',today,'quantity',p_quantity);end if;
 if r.kind is not null then return jsonb_build_object('unit_price',r.unit_price,'source',r.kind,'label',r.name,'date',today,'quantity',p_quantity);end if;
 return jsonb_build_object('unit_price',case when c.category='B' then p.sale_price_b else p.sale_price end,'source','category','label','Categoría '||c.category,'date',today,'quantity',p_quantity);
end $$;
revoke all on function private.erp_price(uuid,uuid,numeric,date) from public,anon;
grant execute on function private.erp_price(uuid,uuid,numeric,date) to authenticated;
create function public.gama_resolve_price(p_customer uuid,p_product uuid,p_quantity numeric default 1,p_date date default null) returns jsonb language sql security invoker set search_path='' as $$select private.erp_price(p_customer,p_product,p_quantity,p_date)$$;
revoke all on function public.gama_resolve_price(uuid,uuid,numeric,date) from public,anon;
grant execute on function public.gama_resolve_price(uuid,uuid,numeric,date) to authenticated;

-- Keep the existing catalog column contract, but use the same dated price resolver.
create or replace view public.catalog_products as
select p.id,p.name,p.reference,p.category,p.barcode,
 coalesce((price.data->>'unit_price')::numeric,p.sale_price) sale_price,p.sale_price base_price,
 coalesce(price.data->>'source','category')<>'category' contract_price,p.tax_rate,
 (case when (select stock_visibility from public.erp_policies where id)='availability' then case when p.stock>0 then 1::numeric else 0::numeric end else p.stock end)::numeric(14,3) stock,
 p.photo_data,p.active,p.created_at,p.has_photo,
 (select stock_visibility from public.erp_policies where id) stock_visibility,p.qty_per_carton,p.order_minimum,p.order_multiple
from public.products p left join lateral(select c.id from public.customers c join auth.users u on lower(u.email)=lower(c.email) where c.active and u.id=auth.uid() order by c.created_at,c.id limit 1) mine on true
left join lateral(select case when mine.id is not null then private.erp_price(mine.id,p.id,1,null) end data) price on true
where p.active and private.current_user_role() is not null;
revoke all on public.catalog_products from anon;grant select on public.catalog_products to authenticated;

create function private.gama_catalog_command(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();customer public.customers;request uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;
 line jsonb;product public.products;price jsonb;qty numeric;rid uuid;v_total numeric:=0;net numeric;result jsonb;preview jsonb:='[]';begin
 if actor is null or coalesce(private.current_user_role(),'')<>'cliente' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select c.* into customer from public.customers c join auth.users u on lower(u.email)=lower(c.email) where c.active and u.id=actor order by c.created_at,c.id limit 1;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 if p_action='history' then return(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select o.id,o.number,o.created_at,(select jsonb_agg(jsonb_build_object('product_id',l.product_id,'quantity',l.quantity)) from public.sales_order_lines l where l.order_id=o.id) lines from public.sales_orders o where o.customer_id=customer.id and o.status<>'cancelled' order by o.created_at desc limit 30)z);end if;
 if p_action='preview' then
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')>500 then raise exception 'INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   select * into product from public.products where id=(line->>'product_id')::uuid and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   qty:=(line->>'quantity')::numeric;price:=private.erp_price(customer.id,product.id,qty,null);
   preview:=preview||jsonb_build_array(jsonb_build_object('product_id',product.id,'quantity',qty,'unit_price',(price->>'unit_price')::numeric,'tax_rate',product.tax_rate,'source',price->>'label'));
  end loop;return preview;
 end if;
 if p_action<>'submit' then raise exception 'INVALID_ACTION';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('catalog:'||request::text,0));
 select * into receipt from private.command_receipts where domain='catalog' and request_key=request;
 if found then if receipt.actor_id<>actor or receipt.payload<>p_data-'request_key' then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 if nullif(p_data->>'requested_delivery_date','')::date<current_date then raise exception 'DELIVERY_DATE_IN_PAST';end if;
 insert into public.customer_requests(customer_id,created_by,status,requester_name,requester_email,notes,total,requested_delivery_date)
 values(customer.id,actor,'pending',customer.name,customer.email,p_data->>'notes',0,nullif(p_data->>'requested_delivery_date','')::date) returning id into rid;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  qty:=(line->>'quantity')::numeric;if qty is null or qty<=0 or qty>999999999 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
  select * into product from public.products where id=(line->>'product_id')::uuid and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if qty<product.order_minimum or mod(qty,product.order_multiple)<>0 then raise exception 'PACK_QUANTITY_REQUIRED:%',product.name;end if;
  price:=private.erp_price(customer.id,product.id,qty,null);
  if nullif(line->>'unit_price','')::numeric is distinct from (price->>'unit_price')::numeric then raise exception 'CART_PRICE_CHANGED';end if;
  net:=round(qty*(price->>'unit_price')::numeric,2);v_total:=v_total+net+round(net*product.tax_rate/100,2);
  insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total) values(rid,product.id,qty,(price->>'unit_price')::numeric,product.tax_rate,net);
 end loop;
 update public.customer_requests set total=v_total where id=rid;
 result:=jsonb_build_object('id',rid,'total',v_total);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('catalog',request,actor,p_data-'request_key',result);
 return result;
end $$;
revoke all on function private.gama_catalog_command(text,jsonb) from public,anon;
grant execute on function private.gama_catalog_command(text,jsonb) to authenticated;
create function public.gama_catalog_command(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_catalog_command(p_action,p_data)$$;
revoke all on function public.gama_catalog_command(text,jsonb) from public,anon;
grant execute on function public.gama_catalog_command(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184611','p1_price_rules_and_catalog_commands','20aee86eb3f3e575f460152229a9d55301340c46972c3baba8f379aba3672677','20aee86eb3f3e575f460152229a9d55301340c46972c3baba8f379aba3672677','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184612_p1_alert_followup_and_operating_controls.sql; SHA256 22c10363ffadab06c04a57f548abebd11489cc93720426cddff3206c08c6f604
alter table private.gama_alert_handling add column next_action text not null default '' check(length(next_action)<=500),add column due_at timestamptz,add column root_cause text not null default '' check(length(root_cause)<=1000);
create table public.erp_notification_preferences(user_id uuid primary key default auth.uid() references auth.users(id),hidden_kinds text[] not null default '{}',only_mine boolean not null default false,updated_at timestamptz not null default now());
alter table public.erp_notification_preferences enable row level security;
revoke all on public.erp_notification_preferences from public,anon,authenticated;
grant select,insert,update on public.erp_notification_preferences to authenticated;
create policy own_preferences on public.erp_notification_preferences for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create table private.erp_alert_state(alert_key text primary key,fingerprint text not null,finance_only boolean not null,warehouse_only boolean not null,active boolean not null default true,changed_at timestamptz not null default now());
alter table private.erp_alert_state enable row level security;
revoke all on private.erp_alert_state from public,anon,authenticated;
-- Business exceptions keep one stable identity across both screens.
do $$declare src text:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');begin
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'crm_stale:'||o.id,'crm_stale',o.id,'opportunity',o.reference,coalesce(c.name,o.title),'Oportunidad sin próxima acción',
  'Responsable: '||coalesce(p.full_name,'Sin asignar')||' · Última actividad: '||o.updated_at::date,
  o.updated_at,2,true,false from public.crm_opportunities o left join public.customers c on c.id=o.customer_id left join public.profiles p on p.id=o.owner_id
 where o.active and o.won_at is null and o.lost_at is null and
 (o.updated_at<now()-make_interval(days=>(select stale_opportunity_days from public.erp_policies where id)) or not exists(select 1 from public.crm_activities a where a.opportunity_id=o.id and a.status in ('pendiente','en_curso') and a.due_at>=now()))
 union all
 select 'service_late:'||s.id,'service_late',s.id,'service',coalesce(s.erp_reference,'SAV-'||s.number),coalesce(c.name,''),'SAV fuera de plazo',s.subject,s.due_date::timestamptz,3,true,false
 from public.service_tickets s left join public.customers c on c.id=s.customer_id where not s.archived and s.status not in ('resolved','closed') and s.due_date<current_date
 $extra$;end $$;
-- Preserve the established metrics and alert computation; extend handling atomically.
alter function private.gama_operations_action(text,jsonb) rename to gama_operations_core;
revoke all on function private.gama_operations_core(text,jsonb) from public,anon,authenticated;
create function private.gama_operations_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r text:=private.current_user_role();result jsonb;x record;live record;fin boolean;wh boolean;owner uuid;prefs jsonb;begin
 if auth.uid() is null or r not in ('administrador','comercial','almacenero') or not(private.erp_module_allowed('operations',array['administrador','comercial','almacenero']) or private.erp_module_allowed('notifications',array['administrador','comercial','almacenero'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 fin:=r in ('administrador','comercial');wh:=r in ('administrador','almacenero');
 if p_action='history' then
  if not exists(select 1 from private.erp_alert_state where alert_key=p_data->>'key' and (not finance_only or fin) and (not warehouse_only or wh)) then raise exception 'ALERT_NOT_FOUND';end if;
  return(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from(select e.id,e.action,e.note,e.created_at,p.full_name actor from private.gama_alert_events e left join public.profiles p on p.id=e.actor where e.alert_key=p_data->>'key' order by e.id desc limit 100)e);
 elsif p_action='handle' then
  result:=private.gama_operations_core(p_action,p_data);
  owner:=coalesce(nullif(p_data->>'assigned_to','')::uuid,auth.uid());
  if not exists(select 1 from public.profiles p where p.id=owner and p.active and p.role in ('administrador','comercial','almacenero')) then raise exception 'ASSIGNEE_REQUIRED';end if;
  update private.gama_alert_handling set next_action=coalesce(p_data->>'next_action',next_action),root_cause=coalesce(p_data->>'root_cause',root_cause),due_at=nullif(p_data->>'due_at','')::timestamptz,assigned_to=case when p_data->>'status'='open' then null else owner end where alert_key=p_data->>'key';
  update private.gama_alert_events set note=concat_ws(E'\n',note,p_data->>'next_action',p_data->>'root_cause',p_data->>'due_at') where id=(select max(id) from private.gama_alert_events where alert_key=p_data->>'key' and actor=auth.uid());
  return result;
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 if coalesce((p_data->>'track')::boolean,false) then
 -- Resolution/reopening is observed from the underlying record, never by dismissing a card.
 for x in select * from private.erp_alert_state where (not finance_only or fin) and (not warehouse_only or wh) and active and not exists(select 1 from private.gama_live_alerts a where a.alert_key=erp_alert_state.alert_key) for update loop
  update private.erp_alert_state set active=false,changed_at=now() where alert_key=x.alert_key;
  insert into private.gama_alert_events(alert_key,fingerprint,action,note,actor) values(x.alert_key,x.fingerprint,'resolved','Causa resuelta en el documento de origen',auth.uid());
 end loop;
 for live in select a.*,md5(a.kind||coalesce(a.detail,'')||coalesce(a.since::text,'')) fingerprint from private.gama_live_alerts a where (not a.finance_only or fin) and (not a.warehouse_only or wh) loop
  select * into x from private.erp_alert_state where alert_key=live.alert_key for update;
  if found and not x.active then insert into private.gama_alert_events(alert_key,fingerprint,action,note,actor) values(live.alert_key,live.fingerprint,'reopened','La causa vuelve a estar activa',auth.uid());end if;
  insert into private.erp_alert_state(alert_key,fingerprint,finance_only,warehouse_only) values(live.alert_key,live.fingerprint,live.finance_only,live.warehouse_only)
   on conflict(alert_key) do update set fingerprint=excluded.fingerprint,active=true;
 end loop;
 end if;
 result:=private.gama_operations_core('snapshot',p_data);
 select coalesce(jsonb_agg(a.value||jsonb_build_object('next_action',h.next_action,'root_cause',h.root_cause,'due_at',h.due_at,'escalated',coalesce(h.due_at<now() or (h.assigned_to is null and (a.value->>'since')::timestamptz<now()-make_interval(days=>(select escalation_days from public.erp_policies where id))),false)) order by a.n),'[]') into prefs
 from jsonb_array_elements(result->'alerts') with ordinality a(value,n) left join private.gama_alert_handling h on h.alert_key=a.value->>'alert_key';
 result:=jsonb_set(result,'{alerts}',prefs);
 return result;
end $$;
revoke all on function private.gama_operations_action(text,jsonb) from public,anon;
grant execute on function private.gama_operations_action(text,jsonb) to authenticated;
create or replace function public.gama_operations_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_operations_action(p_action,p_data)$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184612','p1_alert_followup_and_operating_controls','22c10363ffadab06c04a57f548abebd11489cc93720426cddff3206c08c6f604','22c10363ffadab06c04a57f548abebd11489cc93720426cddff3206c08c6f604','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184613_p1_counts_and_adjustment_approval.sql; SHA256 5e98cec860790ceda07c28d41b8f9e046dcd48ec876ca3d6e134cb97668c5c78
alter table public.inventory_counts add column blind boolean not null default true,add column cycle_days integer check(cycle_days between 1 and 366),add column next_due date,add column scope_location_id uuid references public.warehouse_locations(id),add column scope_category text,add column request_key uuid unique;
alter table public.inventory_count_lines add column counted_by uuid references auth.users(id),add column counted_at timestamptz,add column recount_quantity numeric check(recount_quantity>=0),add column recounted_by uuid references auth.users(id),add column recounted_at timestamptz;
create function private.erp_count_line_stamp() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.counted_quantity is distinct from old.counted_quantity then
  if new.counted_quantity<0 or new.counted_quantity>999999999 or new.counted_quantity<>round(new.counted_quantity,3) then raise exception 'INVALID_QUANTITY';end if;
  new.counted_by:=auth.uid();new.counted_at:=now();new.recount_quantity:=null;new.recounted_by:=null;new.recounted_at:=null;
 elsif new.recount_quantity is distinct from old.recount_quantity then
  if auth.uid()=old.counted_by then raise exception 'SECOND_COUNTER_REQUIRED';end if;
  if new.recount_quantity<>round(new.recount_quantity,3) or new.recount_quantity>999999999 then raise exception 'INVALID_QUANTITY';end if;
  new.recounted_by:=auth.uid();new.recounted_at:=now();
 else new.counted_by:=old.counted_by;new.counted_at:=old.counted_at;new.recounted_by:=old.recounted_by;new.recounted_at:=old.recounted_at;
 end if;return new;end $$;
revoke all on function private.erp_count_line_stamp() from public,anon,authenticated;
create trigger erp_count_line_stamp before update on public.inventory_count_lines for each row execute function private.erp_count_line_stamp();
create function private.gama_count_create(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.inventory_counts;key uuid:=(p_data->>'request_key')::uuid;begin
 if auth.uid() is null or not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('count:'||key::text,0));
 select * into c from public.inventory_counts where request_key=key;if found then if c.created_by<>auth.uid() then raise exception 'ROLE_NOT_ALLOWED';end if;return to_jsonb(c);end if;
 if nullif(p_data->>'location_id','') is not null and not exists(select 1 from public.warehouse_locations where id=(p_data->>'location_id')::uuid and warehouse_id=(p_data->>'warehouse_id')::uuid and active) then raise exception 'LOCATION_NOT_FOUND';end if;
 insert into public.inventory_counts(warehouse_id,reference,status,created_by,started_at,blind,cycle_days,scope_location_id,scope_category,request_key)
 values((p_data->>'warehouse_id')::uuid,p_data->>'reference','in_progress',auth.uid(),now(),coalesce((p_data->>'blind')::boolean,true),nullif(p_data->>'cycle_days','')::integer,nullif(p_data->>'location_id','')::uuid,nullif(p_data->>'category',''),key) returning * into c;
 insert into public.inventory_count_lines(count_id,product_id,location_id,expected_quantity)
 select c.id,q.product_id,q.location_id,q.quantity from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.products p on p.id=q.product_id where l.warehouse_id=c.warehouse_id and (c.scope_location_id is null or q.location_id=c.scope_location_id) and (c.scope_category is null or p.category=c.scope_category);
 if not found then raise exception 'COUNT_SCOPE_EMPTY';end if;return to_jsonb(c);
end $$;
revoke all on function private.gama_count_create(jsonb) from public,anon;
grant execute on function private.gama_count_create(jsonb) to authenticated;
create function public.gama_count_create(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_count_create(p_data)$$;
revoke all on function public.gama_count_create(jsonb) from public,anon;
grant execute on function public.gama_count_create(jsonb) to authenticated;

create or replace function public.gama_count_validate(p_count_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.inventory_counts;l public.inventory_count_lines;q public.stock_quants;limit_qty numeric;adjustments integer:=0;begin
 if auth.uid() is null or not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.inventory_counts where id=p_count_id for update;
 if not found then raise exception 'COUNT_NOT_FOUND';end if;
 if c.status='validated' then return jsonb_build_object('count_id',c.id,'adjustments',0,'already_validated',true);end if;
 if c.status not in ('draft','in_progress') then raise exception 'COUNT_CANCELLED';end if;
 if not exists(select 1 from public.inventory_count_lines where count_id=c.id) or exists(select 1 from public.inventory_count_lines where count_id=c.id and counted_quantity is null) then raise exception 'COUNT_INCOMPLETE';end if;
 select stock_adjustment_limit into limit_qty from public.erp_policies where id;
 -- Lock in product order, matching stock command lock ordering.
 perform 1 from public.products where id in(select product_id from public.inventory_count_lines where count_id=c.id) order by id for update;
 for l in select * from public.inventory_count_lines where count_id=c.id order by product_id,location_id for update loop
  q:=private.gama_lock_quant(l.product_id,l.location_id);
  if q.quantity<>l.expected_quantity then raise exception 'COUNT_STOCK_CHANGED:%',l.product_id;end if;
  if limit_qty is not null and abs(l.counted_quantity-l.expected_quantity)>limit_qty then
   if l.recount_quantity is null or l.recounted_by is null or l.recount_quantity<>l.counted_quantity then raise exception 'RECOUNT_REQUIRED:%',l.product_id;end if;
   if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'COUNT_APPROVAL_REQUIRED';end if;
  end if;
  if l.counted_quantity<>l.expected_quantity then
   perform public.gama_stock_adjust(l.product_id,l.location_id,l.counted_quantity,null,'Inventario físico','Conteo '||c.reference,'inventory_count',c.id);adjustments:=adjustments+1;
  end if;
  update public.inventory_count_lines set validated=true where id=l.id;
 end loop;
 update public.inventory_counts set status='validated',completed_at=now(),next_due=case when cycle_days is not null then current_date+cycle_days end where id=c.id;
 return jsonb_build_object('count_id',c.id,'adjustments',adjustments);
end $$;
-- The stock command checks limits under the same product/quant locks as its write.
do $$declare src text:=pg_get_functiondef('public.gama_stock_adjust(uuid,uuid,numeric,numeric,text,text,text,uuid)'::regprocedure);begin
 src:=replace(src,'v_delta := v_new - v_quant.quantity;',$patch$v_delta := v_new - v_quant.quantity;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
  if exists(select 1 from public.erp_policies where id and stock_adjustment_limit is not null and abs(v_delta)>stock_adjustment_limit) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;$patch$);
 execute src;
end $$;

create table public.stock_adjustment_requests(id uuid primary key default gen_random_uuid(),request_key uuid not null unique,product_id uuid not null references public.products(id),location_id uuid not null references public.warehouse_locations(id),expected_quantity numeric not null,target_quantity numeric not null check(target_quantity>=0),reason text not null check(length(btrim(reason))>=3),status text not null default 'pending' check(status in ('pending','approved','rejected')),requested_by uuid not null default auth.uid() references auth.users(id),requested_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),reviewed_at timestamptz,decision_reason text,movement_id uuid references public.stock_movements(id));
alter table public.stock_adjustment_requests enable row level security;
revoke all on public.stock_adjustment_requests from public,anon,authenticated;grant select on public.stock_adjustment_requests to authenticated;
create policy adjustment_read on public.stock_adjustment_requests for select to authenticated using(private.erp_module_allowed('movement',array['administrador','almacenero']));
create trigger erp_audit_capture after insert or update or delete on public.stock_adjustment_requests for each row execute function private.erp_audit_capture();
create function private.gama_adjustment_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.stock_adjustment_requests;q public.stock_quants;m public.stock_movements;begin
 if auth.uid() is null or not private.erp_module_allowed('movement',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='submit' then
  if nullif(p_data->>'request_key','') is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('adjust:'||(p_data->>'request_key'),0));
  select * into a from public.stock_adjustment_requests where request_key=(p_data->>'request_key')::uuid;
  if found then if a.requested_by<>auth.uid() or a.product_id<>(p_data->>'product_id')::uuid or a.location_id<>(p_data->>'location_id')::uuid or a.target_quantity<>(p_data->>'target_quantity')::numeric or a.reason<>p_data->>'reason' then raise exception 'REQUEST_KEY_REUSED';end if;return to_jsonb(a);end if;
  perform 1 from public.products where id=(p_data->>'product_id')::uuid and active for update;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  q:=private.gama_lock_quant((p_data->>'product_id')::uuid,(p_data->>'location_id')::uuid);
  insert into public.stock_adjustment_requests(request_key,product_id,location_id,expected_quantity,target_quantity,reason) values((p_data->>'request_key')::uuid,q.product_id,q.location_id,q.quantity,(p_data->>'target_quantity')::numeric,p_data->>'reason') returning * into a;
 elsif p_action in ('approve','reject') then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  select * into a from public.stock_adjustment_requests where id=(p_data->>'id')::uuid for update;if not found or a.status<>'pending' then raise exception 'APPROVAL_NOT_PENDING';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if p_action='approve' then
   perform 1 from public.products where id=a.product_id for update;q:=private.gama_lock_quant(a.product_id,a.location_id);
   if q.quantity<>a.expected_quantity then raise exception 'STOCK_CHANGED_RECOUNT';end if;
   m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity,null,a.reason,p_data->>'reason','adjustment_request',a.id);
  end if;
  update public.stock_adjustment_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),decision_reason=p_data->>'reason',movement_id=m.id where id=a.id returning * into a;
 else raise exception 'INVALID_ACTION';end if;return to_jsonb(a);
end $$;
revoke all on function private.gama_adjustment_request(text,jsonb) from public,anon;
grant execute on function private.gama_adjustment_request(text,jsonb) to authenticated;
create function public.gama_adjustment_request(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_adjustment_request(p_action,p_data)$$;
revoke all on function public.gama_adjustment_request(text,jsonb) from public,anon;
grant execute on function public.gama_adjustment_request(text,jsonb) to authenticated;

create function private.gama_register_stock_movement_once(p_request_key uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare receipt private.command_receipts;result jsonb;begin
 if auth.uid() is null or not private.erp_module_allowed('movement',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_request_key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('movement:'||p_request_key::text,0));
 select * into receipt from private.command_receipts where domain='movement' and request_key=p_request_key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if length(btrim(coalesce(p_data->>'p_reason','')))<3 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
 if exists(select 1 from public.erp_policies where id and stock_adjustment_limit is not null and abs((p_data->>'p_quantity')::numeric)>stock_adjustment_limit) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;
 select to_jsonb(r) into result from public.gama_register_stock_movement((p_data->>'p_product_id')::uuid,p_data->>'p_type',(p_data->>'p_quantity')::numeric,p_data->>'p_reason',p_data->>'p_comment')r;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('movement',p_request_key,auth.uid(),p_data,result);
 return result;
end $$;
revoke all on function private.gama_register_stock_movement_once(uuid,jsonb) from public,anon;
grant execute on function private.gama_register_stock_movement_once(uuid,jsonb) to authenticated;
create function public.gama_register_stock_movement_once(p_request_key uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_register_stock_movement_once(p_request_key,p_data)$$;
revoke all on function public.gama_register_stock_movement_once(uuid,jsonb) from public,anon;
grant execute on function public.gama_register_stock_movement_once(uuid,jsonb) to authenticated;
-- Protect callers of the legacy command as well as the new idempotent wrapper.
do $$declare src text:=pg_get_functiondef('public.gama_register_stock_movement(uuid,text,numeric,text,text)'::regprocedure);begin
 src:=regexp_replace(src,'begin', $p$begin
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
 if exists(select 1 from public.erp_policies where id and stock_adjustment_limit is not null and abs(p_quantity)>stock_adjustment_limit) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;
 $p$,'i');execute src;end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184613','p1_counts_and_adjustment_approval','5e98cec860790ceda07c28d41b8f9e046dcd48ec876ca3d6e134cb97668c5c78','5e98cec860790ceda07c28d41b8f9e046dcd48ec876ca3d6e134cb97668c5c78','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184615_p1_supplier_offers_and_three_way_match.sql; SHA256 6ea5e697537ebb23238716d9e143a3ebc6268901b2c80c941d087c06fef6ecd3
create table public.supplier_product_offers(id uuid primary key default gen_random_uuid(),supplier_id uuid not null references public.suppliers(id),product_id uuid not null references public.products(id),supplier_reference text,unit_cost numeric(16,4) not null check(unit_cost>=0),currency text not null check(currency~'^[A-Z]{3}$'),minimum_quantity numeric(16,3) not null default 1 check(minimum_quantity>0),pack_quantity numeric(16,3) not null default 1 check(pack_quantity>0),lead_time_days integer not null default 0 check(lead_time_days between 0 and 3650),additional_unit_cost numeric(16,4) not null default 0 check(additional_unit_cost>=0),valid_from date not null default current_date,valid_to date,active boolean not null default true,created_by uuid default auth.uid() references auth.users(id),created_at timestamptz not null default now(),check(valid_to is null or valid_to>=valid_from));
alter table public.supplier_product_offers enable row level security;
revoke all on public.supplier_product_offers from public,anon,authenticated;grant select,insert,update on public.supplier_product_offers to authenticated;
create policy offer_read on public.supplier_product_offers for select to authenticated using(private.erp_module_allowed('suppliers',array['administrador','comercial']) or private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']));
create policy offer_write on public.supplier_product_offers for all to authenticated using(private.erp_module_allowed('suppliers',array['administrador','comercial'])) with check(private.erp_module_allowed('suppliers',array['administrador','comercial']));
create index supplier_product_offer_product on public.supplier_product_offers(product_id,valid_from,valid_to) where active;
create trigger erp_audit_capture after insert or update or delete on public.supplier_product_offers for each row execute function private.erp_audit_capture();
create function public.gama_supplier_performance(p_id uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$declare result jsonb;begin
 if not private.erp_module_allowed('suppliers',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 with orders as(select o.*,(select max(m.created_at) from public.stock_movements m where m.reference_type='purchase_order' and m.reference_id=o.id and m.movement_type='receipt') last_receipt from public.purchase_orders o where o.supplier_id=p_id and o.status<>'cancelled'),
 measured as(select *,case when status='received' and expected_date is not null and last_receipt is not null then last_receipt::date<=expected_date::date end on_time from orders)
 select jsonb_build_object('orders',count(*),'received',count(*) filter(where status='received'),'measured',count(on_time),'on_time',count(*) filter(where on_time),'on_time_percent',round(100.0*count(*) filter(where on_time)/nullif(count(on_time),0),1),'average_lead_days',avg(last_receipt::date-order_date::date) filter(where status='received' and last_receipt is not null),'late_open',count(*) filter(where status in ('sent','partial') and expected_date<now()),'returns',(select count(*) from public.return_orders where supplier_id=p_id and status<>'cancelled'),'generated_at',now()) into result from measured;return result;
end $$;
revoke all on function public.gama_supplier_performance(uuid) from public,anon;grant execute on function public.gama_supplier_performance(uuid) to authenticated;

alter table public.supplier_invoices add column match_required boolean not null default false;
alter table public.supplier_invoices alter column match_required set default true;
alter table public.supplier_invoices add constraint supplier_invoice_totals check(total=round(subtotal+tax,2)) not valid;
create table public.supplier_invoice_matches(id uuid primary key default gen_random_uuid(),invoice_id uuid not null unique references public.supplier_invoices(id),purchase_order_id uuid not null references public.purchase_orders(id),variance_reason text,approved_by uuid not null default auth.uid() references auth.users(id),approved_at timestamptz not null default now(),lines jsonb not null);
create table public.supplier_invoice_match_lines(id uuid primary key default gen_random_uuid(),match_id uuid not null references public.supplier_invoice_matches(id),purchase_line_id uuid not null references public.purchase_order_lines(id),quantity numeric(16,3) not null check(quantity>0),unit_cost numeric(16,4) not null check(unit_cost>=0),tax_rate numeric(8,3) not null check(tax_rate between 0 and 100),unique(match_id,purchase_line_id));
do $$declare t text;begin foreach t in array array['supplier_invoice_matches','supplier_invoice_match_lines'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy match_read on public.%I for select to authenticated using((private.gama_accounting_rights()->>''view'')::boolean and private.gama_accounting_rights()->>''scope''=''all'')',t);execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);end loop;end $$;
create function private.gama_supplier_match(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();bill public.supplier_invoices;po public.purchase_orders;l public.purchase_order_lines;x jsonb;m public.supplier_invoice_matches;qty numeric;price numeric;rate numeric;used numeric;net numeric:=0;tax numeric:=0;variance boolean:=false;begin
 if auth.uid() is null or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into bill from public.supplier_invoices where id=(p_data->>'id')::uuid for update;if not found then raise exception 'INVOICE_NOT_FOUND';end if;
 if bill.purchase_order_id is null then raise exception 'PURCHASE_LINK_REQUIRED';end if;
 select * into po from public.purchase_orders where id=bill.purchase_order_id for update;
 if po.supplier_id<>bill.supplier_id then raise exception 'SUPPLIER_MISMATCH';end if;
 select * into m from public.supplier_invoice_matches where invoice_id=bill.id;
 if p_action='preview' then return jsonb_build_object('invoice',to_jsonb(bill),'purchase',to_jsonb(po),'match',to_jsonb(m),'lines',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select pol.*,p.name,p.reference,coalesce((select sum(matched.quantity) from public.supplier_invoice_match_lines matched join public.supplier_invoice_matches mx on mx.id=matched.match_id join public.supplier_invoices b on b.id=mx.invoice_id where matched.purchase_line_id=pol.id and b.status<>'cancelled' and b.id<>bill.id),0) already_matched from public.purchase_order_lines pol join public.products p on p.id=pol.product_id where pol.purchase_order_id=po.id order by p.name)z));end if;
 if p_action<>'approve' or not coalesce((rights->>'validate')::boolean,false) then raise exception 'APPROVAL_REQUIRED';end if;
 if m.id is not null then if m.lines<>p_data->'lines' then raise exception 'MATCH_IMMUTABLE';end if;return to_jsonb(m);end if;
 if bill.status<>'posted' or jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 1000 then raise exception 'INVALID_LINES';end if;
 insert into public.supplier_invoice_matches(invoice_id,purchase_order_id,variance_reason,lines) values(bill.id,po.id,p_data->>'reason',p_data->'lines') returning * into m;
 for x in select value from jsonb_array_elements(p_data->'lines') loop
  select * into l from public.purchase_order_lines where id=(x->>'purchase_line_id')::uuid and purchase_order_id=po.id for update;if not found then raise exception 'PURCHASE_LINE_NOT_FOUND';end if;
  qty:=(x->>'quantity')::numeric;price:=(x->>'unit_cost')::numeric;rate:=(x->>'tax_rate')::numeric;
  select coalesce(sum(ml.quantity),0) into used from public.supplier_invoice_match_lines ml join public.supplier_invoice_matches mx on mx.id=ml.match_id join public.supplier_invoices b on b.id=mx.invoice_id where ml.purchase_line_id=l.id and b.status<>'cancelled';
  if qty is null or qty<=0 or qty<>round(qty,3) or qty+used>l.received_quantity then raise exception 'INVOICE_EXCEEDS_RECEIPT';end if;
  if price is null or price<0 or rate is null or rate<0 or rate>100 then raise exception 'INVALID_LINES';end if;
  variance:=variance or price<>l.unit_cost or rate<>l.tax_rate;
  net:=net+round(qty*price,2);tax:=tax+round(round(qty*price,2)*rate/100,2);
  insert into public.supplier_invoice_match_lines(match_id,purchase_line_id,quantity,unit_cost,tax_rate) values(m.id,l.id,qty,price,rate);
 end loop;
 if net<>bill.subtotal or tax<>bill.tax or net+tax<>bill.total then raise exception 'INVOICE_TOTAL_MISMATCH';end if;
 if variance and length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'PRICE_VARIANCE_REASON_REQUIRED';end if;
 return to_jsonb(m);
end $$;
revoke all on function private.gama_supplier_match(text,jsonb) from public,anon;grant execute on function private.gama_supplier_match(text,jsonb) to authenticated;
create function public.gama_supplier_match(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_supplier_match(p_action,p_data)$$;
revoke all on function public.gama_supplier_match(text,jsonb) from public,anon;grant execute on function public.gama_supplier_match(text,jsonb) to authenticated;
create function private.erp_supplier_payment_guard() returns trigger language plpgsql security definer set search_path='' as $$declare b public.supplier_invoices;begin
 if new.status='confirmed' then
  select * into b from public.supplier_invoices where id=new.supplier_invoice_id for update;
  if b.match_required and b.purchase_order_id is not null and not exists(select 1 from public.supplier_invoice_matches where invoice_id=b.id) then raise exception 'THREE_WAY_MATCH_REQUIRED';end if;
 end if;return new;end $$;
revoke all on function private.erp_supplier_payment_guard() from public,anon,authenticated;
create trigger erp_supplier_payment_guard before insert or update on public.supplier_invoice_payments for each row execute function private.erp_supplier_payment_guard();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184615','p1_supplier_offers_and_three_way_match','6ea5e697537ebb23238716d9e143a3ebc6268901b2c80c941d087c06fef6ecd3','6ea5e697537ebb23238716d9e143a3ebc6268901b2c80c941d087c06fef6ecd3','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184617_p1_import_dry_run_and_retry.sql; SHA256 3798b6a4daf7b2883b23e7f74340ec4ada5c6558569da86a10748f956b6d96fe
create table public.erp_import_batches(id uuid primary key default gen_random_uuid(),request_key uuid not null unique,kind text not null check(kind in ('products','clients','suppliers','customerPrices')),filename text not null,created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),status text not null default 'preview' check(status in ('preview','partial','completed')),source_rows jsonb not null);
create table public.erp_import_rows(id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.erp_import_batches(id),row_number integer not null,data jsonb not null,status text not null check(status in ('ready','error','imported')),error text,result_id uuid,imported_at timestamptz,unique(batch_id,row_number));
do $$declare t text;begin foreach t in array array['erp_import_batches','erp_import_rows'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy import_admin on public.%I for select to authenticated using(private.erp_module_allowed(''reports'',array[''administrador'']))',t);execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);end loop;end $$;
create function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;fields text[];tbl text;data jsonb:=p_row;columns text;values_sql text;cid uuid;pid uuid;n integer;begin
 if p_row ? '_errors' then raise exception '%',p_row->>'_errors';end if;
 if p_kind='customerPrices' then
  select count(*),(array_agg(id))[1] into n,cid from public.customers where active and ((nullif(p_row->>'customer_tax_id','') is not null and lower(identification)=lower(p_row->>'customer_tax_id')) or (nullif(p_row->>'customer_tax_id','') is null and lower(name)=lower(p_row->>'customer')));
  if n<>1 then raise exception 'CUSTOMER_UNKNOWN_OR_AMBIGUOUS';end if;
  select count(*),(array_agg(id))[1] into n,pid from public.products where active and ((nullif(p_row->>'reference','') is not null and lower(reference)=lower(p_row->>'reference')) or (nullif(p_row->>'reference','') is null and lower(barcode)=lower(p_row->>'barcode')));
  if n<>1 then raise exception 'PRODUCT_UNKNOWN_OR_AMBIGUOUS';end if;
  if p_row->>'unit_price' is null or (p_row->>'unit_price')::numeric<0 then raise exception 'PRICE_REQUIRED';end if;
  begin
   insert into public.customer_special_prices(customer_id,product_id,unit_price,contract_ref) values(cid,pid,(p_row->>'unit_price')::numeric,p_row->>'contract_ref') on conflict(customer_id,product_id) do update set unit_price=excluded.unit_price,contract_ref=excluded.contract_ref;
   if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
  exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
  return pid;
 end if;
 if length(btrim(coalesce(p_row->>'name','')))=0 then raise exception 'NAME_REQUIRED';end if;
 if p_kind='products' then tbl:='products';fields:=array['name','description','reference','barcode','category','family','lines','brand','presentation','location','stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','sale_price_b','purchase_price','tax_rate'];
 elsif p_kind='clients' then tbl:='customers';fields:=array['name','identification','category','email','phone','address','city','province','notes'];data:=(data-'tax_id')||jsonb_build_object('identification',data->>'tax_id','category',upper(coalesce(nullif(data->>'category',''),'A')));if data->>'category' not in ('A','B','C') then raise exception 'INVALID_CUSTOMER_CATEGORY';end if;
 elsif p_kind='suppliers' then tbl:='suppliers';fields:=array['name','tax_id','email','phone','address','city','contact_name','notes'];
 else raise exception 'INVALID_IMPORT_KIND';end if;
 if p_kind in ('clients','suppliers') then
  execute format('select count(*) from public.%I where lower(btrim(name))=lower(btrim($1)) and lower(btrim(coalesce(address,'''')))=lower(btrim(coalesce($2,'''')))',tbl) into n using data->>'name',data->>'address';
  if n>0 then raise exception 'DUPLICATE_CONTACT';end if;
 end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key) into columns,values_sql from jsonb_object_keys(data) key where key=any(fields);
 begin
  execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning id',tbl,columns,values_sql,tbl) into result using data;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return result;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;
create function private.gama_import_batch(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.erp_import_batches;r public.erp_import_rows;x jsonb;rowno integer:=1;error text;rid uuid;k text;seen text[]:='{}';begin
 if auth.uid() is null or not private.erp_module_allowed('reports',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='prepare' then
  if nullif(p_data->>'request_key','') is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('import:'||(p_data->>'request_key'),0));
  select * into b from public.erp_import_batches where request_key=(p_data->>'request_key')::uuid;
  if found then if b.created_by<>auth.uid() or b.source_rows<>p_data->'rows' or b.kind<>p_data->>'kind' then raise exception 'REQUEST_KEY_REUSED';end if;
  else
   if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 2000 then raise exception 'IMPORT_LIMIT_2000_ROWS';end if;
   insert into public.erp_import_batches(request_key,kind,filename,source_rows) values((p_data->>'request_key')::uuid,p_data->>'kind',coalesce(p_data->>'filename','Import'),p_data->'rows') returning * into b;
   for x in select value from jsonb_array_elements(b.source_rows) loop
    rowno:=rowno+1;error:=null;
    k:=case b.kind when 'products' then lower(coalesce(nullif(x->>'barcode',''),nullif(x->>'reference',''),x->>'name')) when 'customerPrices' then lower(coalesce(nullif(x->>'customer_tax_id',''),x->>'customer'))||'|'||lower(coalesce(nullif(x->>'reference',''),x->>'barcode')) else lower(btrim(x->>'name'))||'|'||lower(btrim(coalesce(x->>'address',''))) end;
    begin
     if k=any(seen) then raise exception 'DUPLICATE_IN_FILE';end if;perform private.erp_import_row(b.kind,x,true);
    exception when others then error:=sqlerrm;end;
    seen:=array_append(seen,k);
    insert into public.erp_import_rows(batch_id,row_number,data,status,error) values(b.id,rowno,x,case when error is null then 'ready' else 'error' end,error);
   end loop;
  end if;
 elsif p_action in ('apply','detail') then
  select * into b from public.erp_import_batches where id=(p_data->>'id')::uuid for update;if not found then raise exception 'IMPORT_NOT_FOUND';end if;
  if p_action='apply' then
   for r in select ir.* from public.erp_import_rows ir where ir.batch_id=b.id and ir.status<>'imported' and ir.error is distinct from 'DUPLICATE_IN_FILE' order by row_number for update loop
    begin
     rid:=private.erp_import_row(b.kind,r.data,false);
     update public.erp_import_rows set status='imported',error=null,result_id=rid,imported_at=now() where id=r.id;
    exception when others then update public.erp_import_rows set status='error',error=sqlerrm where id=r.id;end;
   end loop;
   update public.erp_import_batches set status=case when exists(select 1 from public.erp_import_rows where batch_id=b.id and status<>'imported') then 'partial' else 'completed' end where id=b.id returning * into b;
  end if;
 else raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('batch',to_jsonb(b)-'source_rows','rows',(select jsonb_agg(to_jsonb(ir) order by ir.row_number) from public.erp_import_rows ir where ir.batch_id=b.id));
end $$;
revoke all on function private.gama_import_batch(text,jsonb) from public,anon;grant execute on function private.gama_import_batch(text,jsonb) to authenticated;
create function public.gama_import_batch(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_import_batch(p_action,p_data)$$;
revoke all on function public.gama_import_batch(text,jsonb) from public,anon;grant execute on function public.gama_import_batch(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184617','p1_import_dry_run_and_retry','3798b6a4daf7b2883b23e7f74340ec4ada5c6558569da86a10748f956b6d96fe','3798b6a4daf7b2883b23e7f74340ec4ada5c6558569da86a10748f956b6d96fe','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184618_p1_service_portal_and_document_approval.sql; SHA256 fc264d806d7036e8e406d92f2610ad59659509c693efb25462d3743083034988
alter table public.service_tickets add column delivery_id uuid references public.tms_deliveries(id),add column return_id uuid references public.return_orders(id),add column replacement_order_id uuid references public.sales_orders(id),add column root_cause text not null default '',add column response_due_at timestamptz,add column first_response_at timestamptz,add column resolution_due_at timestamptz,add column portal_request_key uuid unique;
alter table public.service_messages add column visibility text not null default 'internal' check(visibility in ('internal','public'));
create table public.service_sla_rules(priority text primary key check(priority in ('normal','high','urgent')),response_hours integer not null check(response_hours between 1 and 8760),resolution_hours integer not null check(resolution_hours between 1 and 8760));
insert into public.service_sla_rules values('normal',24,72),('high',8,48),('urgent',2,24);
alter table public.service_sla_rules enable row level security;revoke all on public.service_sla_rules from public,anon,authenticated;grant select,update on public.service_sla_rules to authenticated;
create policy sla_read on public.service_sla_rules for select to authenticated using(private.service_access('sav'));
create policy sla_write on public.service_sla_rules for update to authenticated using(private.erp_module_allowed('settings',array['administrador']));
create trigger erp_audit_capture after insert or update or delete on public.service_sla_rules for each row execute function private.erp_audit_capture();
create function private.erp_service_controls() returns trigger language plpgsql security definer set search_path='' as $$declare sla public.service_sla_rules;begin
 if tg_op='INSERT' then
  select * into sla from public.service_sla_rules where priority=new.priority;
  new.response_due_at:=now()+make_interval(hours=>sla.response_hours);new.resolution_due_at:=now()+make_interval(hours=>sla.resolution_hours);new.due_date:=coalesce(new.due_date,new.resolution_due_at::date);
 else new.response_due_at:=old.response_due_at;new.resolution_due_at:=old.resolution_due_at;end if;
 if new.return_id is not null and not exists(select 1 from public.return_orders where id=new.return_id and customer_id=new.customer_id) then raise exception 'SERVICE_RETURN_CUSTOMER';end if;
 if new.replacement_order_id is not null and not exists(select 1 from public.sales_orders where id=new.replacement_order_id and customer_id=new.customer_id) then raise exception 'SERVICE_REPLACEMENT_CUSTOMER';end if;
 if new.delivery_id is not null and not exists(select 1 from public.tms_deliveries where id=new.delivery_id and customer_id=new.customer_id) then raise exception 'SERVICE_DELIVERY_CUSTOMER';end if;
 return new;
end $$;
revoke all on function private.erp_service_controls() from public,anon,authenticated;
create trigger erp_service_controls before insert or update on public.service_tickets for each row execute function private.erp_service_controls();
create function private.erp_service_response() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.visibility='public' and private.current_user_role() in ('administrador','comercial') then update public.service_tickets set first_response_at=coalesce(first_response_at,now()) where id=new.ticket_id;end if;return null;
end $$;
revoke all on function private.erp_service_response() from public,anon,authenticated;
create trigger erp_service_response after insert on public.service_messages for each row execute function private.erp_service_response();
create function private.gama_client_service(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.customers;d public.tms_deliveries;ticket public.service_tickets;oid uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;result jsonb;begin
 if auth.uid() is null or not private.erp_module_allowed('client-deliveries',array['cliente']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select x.* into c from public.customers x where x.active and private.gama_owns_customer(x.id) order by x.created_at,x.id limit 1;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid and customer_id=c.id;if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
 select order_id into oid from public.sales_deliveries where tms_delivery_id=d.id;
 if p_action in ('create','reply') then
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('service:'||key::text,0));
  select * into receipt from private.command_receipts where domain='service' and request_key=key;
  if found then if receipt.actor_id<>auth.uid() or receipt.payload<>p_data-'request_key'||jsonb_build_object('action',p_action) then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
  if p_action='create' then
   insert into public.service_tickets(subject,description,customer_id,sales_order_id,delivery_id,category,portal_request_key) values(p_data->>'subject',p_data->>'body',c.id,oid,d.id,'delivery',key) returning * into ticket;
  else
   select * into ticket from public.service_tickets where id=(p_data->>'ticket_id')::uuid and customer_id=c.id and delivery_id=d.id and not archived for update;
   if not found or ticket.status='closed' then raise exception 'TICKET_CLOSED';end if;
   insert into public.service_messages(ticket_id,body,visibility) values(ticket.id,p_data->>'body','public');
  end if;
  result:=jsonb_build_object('id',ticket.id,'number',ticket.number);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('service',key,auth.uid(),p_data-'request_key'||jsonb_build_object('action',p_action),result);return result;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('tickets',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'number',s.number,'subject',s.subject,'description',s.description,'status',s.status,'created_at',s.created_at,'messages',(select coalesce(jsonb_agg(jsonb_build_object('body',m.body,'created_at',m.created_at,'author',case when m.created_by=auth.uid() then 'customer' else 'company' end) order by m.created_at),'[]') from public.service_messages m where m.ticket_id=s.id and m.visibility='public')) order by s.created_at desc),'[]') from public.service_tickets s where s.delivery_id=d.id and s.customer_id=c.id and not s.archived),
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('name',l.product_name,'ordered',l.quantity,'delivered',coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl join public.sales_deliveries sd on sd.id=dl.delivery_id join public.tms_deliveries td on td.id=sd.tms_delivery_id where dl.order_line_id=l.id and td.status='Entregada'),0),'promised_date',l.promised_date)),'[]') from public.sales_order_lines l where l.order_id=oid),
 'events',jsonb_build_array(jsonb_build_object('label','Entrega prevista','date',d.delivery_date),jsonb_build_object('label','Estado','status',d.status,'date',d.delivered_at)));
end $$;
revoke all on function private.gama_client_service(text,jsonb) from public,anon;grant execute on function private.gama_client_service(text,jsonb) to authenticated;
create function public.gama_client_service(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_client_service(p_action,p_data)$$;
revoke all on function public.gama_client_service(text,jsonb) from public,anon;grant execute on function public.gama_client_service(text,jsonb) to authenticated;

alter table public.business_documents add column owner_id uuid references public.profiles(id),add column next_action text not null default '';
grant insert(owner_id,next_action),update(owner_id,next_action) on public.business_documents to authenticated;
-- Extend the existing atomic save rather than adding a second, unversioned write.
do $$declare src text:=pg_get_functiondef('public.gama_save_business_document(jsonb,integer,jsonb)'::regprocedure);begin
 src:=replace(src,'ticket_id,expires_on)','ticket_id,expires_on,owner_id,next_action)');
 src:=replace(src,$a$nullif(p_document->>'expires_on','')::date) returning$a$, $a$nullif(p_document->>'expires_on','')::date,nullif(p_document->>'owner_id','')::uuid,coalesce(p_document->>'next_action','')) returning$a$);
 src:=replace(src,$a$expires_on=nullif(p_document->>'expires_on','')::date$a$, $a$expires_on=nullif(p_document->>'expires_on','')::date,owner_id=nullif(p_document->>'owner_id','')::uuid,next_action=coalesce(p_document->>'next_action','')$a$);
 execute src;
end $$;
create table public.business_document_approvals(id uuid primary key default gen_random_uuid(),document_id uuid not null references public.business_documents(id),fingerprint text not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),requested_by uuid not null default auth.uid() references auth.users(id),requested_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),reviewed_at timestamptz,reason text,unique(document_id,fingerprint));
alter table public.business_document_approvals enable row level security;revoke all on public.business_document_approvals from public,anon,authenticated;grant select on public.business_document_approvals to authenticated;
create policy document_approval_read on public.business_document_approvals for select to authenticated using(exists(select 1 from public.business_documents d where d.id=document_id));
create trigger erp_audit_capture after insert or update or delete on public.business_document_approvals for each row execute function private.erp_audit_capture();
create function private.gama_document_approval(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.business_documents;a public.business_document_approvals;fp text;begin
 select * into d from public.business_documents where id=(p_data->>'id')::uuid for update;
 if auth.uid() is null or not found or not private.document_read(d) then raise exception 'DOCUMENT_UNAVAILABLE';end if;
 fp:=md5((to_jsonb(d)-array['updated_at','version','owner_id','next_action'])::text||coalesce((select jsonb_agg(to_jsonb(f) order by f.revision)::text from public.business_document_files f where f.document_id=d.id),'[]'));
 if p_action='request' then
  if not private.document_write(d) then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into public.business_document_approvals(document_id,fingerprint) values(d.id,fp) on conflict(document_id,fingerprint) do nothing;
 elsif p_action='decide' then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  if p_data->>'status' not in ('approved','rejected') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'DECISION_REQUIRED';end if;
  update public.business_document_approvals set status=p_data->>'status',reviewed_by=auth.uid(),reviewed_at=now(),reason=p_data->>'reason' where document_id=d.id and fingerprint=fp and status='pending';if not found then raise exception 'DOCUMENT_CHANGED_OR_NOT_PENDING';end if;
 elsif p_action<>'detail' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('current',(select to_jsonb(x) from public.business_document_approvals x where x.document_id=d.id and x.fingerprint=fp),'history',(select coalesce(jsonb_agg(to_jsonb(x) order by requested_at desc),'[]') from public.business_document_approvals x where x.document_id=d.id));
end $$;
revoke all on function private.gama_document_approval(text,jsonb) from public,anon;grant execute on function private.gama_document_approval(text,jsonb) to authenticated;
create function public.gama_document_approval(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_document_approval(p_action,p_data)$$;
revoke all on function public.gama_document_approval(text,jsonb) from public,anon;grant execute on function public.gama_document_approval(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184618','p1_service_portal_and_document_approval','fc264d806d7036e8e406d92f2610ad59659509c693efb25462d3743083034988','fc264d806d7036e8e406d92f2610ad59659509c693efb25462d3743083034988','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184619_p1_hr_staffing_and_handover.sql; SHA256 7a8f50d7f200a84974ea31eb1e201890e6f96a5c1320de88bafe04cd405ed2c7
create table public.hr_staffing_rules (
 id uuid primary key default gen_random_uuid(),department text not null unique check(length(btrim(department))>0),
 minimum numeric(8,1) not null check(minimum>=0),weekdays integer[] not null default array[1,2,3,4,5] check(weekdays <@ array[0,1,2,3,4,5,6]),
 updated_at timestamptz not null default now()
);
create table public.hr_employee_skills (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 skill text not null check(length(btrim(skill))>0),level text not null default '',valid_until date,verified_on date,
 notes text not null default '',unique(employee_id,skill)
);
create table public.hr_lifecycle_tasks (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 kind text not null check(kind in ('onboarding','offboarding','expiry')),title text not null check(length(btrim(title))>0),
 owner_id uuid not null references public.profiles(id),due_date date not null,completed_at timestamptz,
 completed_by uuid references public.profiles(id),note text not null default '',created_at timestamptz not null default now()
);
do $$declare t text;begin foreach t in array array['hr_staffing_rules','hr_employee_skills','hr_lifecycle_tasks'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update on public.%I to authenticated',t);
 execute format('create policy hr_admin_write on public.%I for all to authenticated using(private.hr_admin()) with check(private.hr_admin())',t);
 execute format('create trigger hr_audit after insert or update or delete on public.%I for each row execute function private.hr_audit_change()',t);
 end loop;end $$;
create policy hr_skill_self on public.hr_employee_skills for select to authenticated using(private.hr_own(employee_id) or private.hr_manage(employee_id));
create policy hr_lifecycle_self on public.hr_lifecycle_tasks for select to authenticated using(private.hr_own(employee_id) or private.hr_manage(employee_id));
create index hr_lifecycle_owner on public.hr_lifecycle_tasks(owner_id,due_date) where completed_at is null;
create index hr_lifecycle_employee on public.hr_lifecycle_tasks(employee_id);
create index hr_lifecycle_completed_by on public.hr_lifecycle_tasks(completed_by);
create function private.erp_hr_task_guard() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if new.completed_at is not null and (tg_op='INSERT' or old.completed_at is null) then new.completed_at=now();new.completed_by=auth.uid();
 elsif new.completed_at is null then new.completed_by=null;
 else new.completed_at=old.completed_at;new.completed_by=old.completed_by;end if;return new;
end $$;
revoke all on function private.erp_hr_task_guard() from public,anon,authenticated;
create trigger hr_task_guard before insert or update on public.hr_lifecycle_tasks for each row execute function private.erp_hr_task_guard();
create function private.gama_hr_staffing(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not coalesce(private.hr_admin(),false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>92 then raise exception 'DATE_RANGE_REQUIRED';end if;
 return (with days as (select d::date as day from generate_series(p_from,p_to,interval '1 day')d),coverage as (
 select d.day,r.department,r.minimum,coalesce(sum(case when e.id is null then 0 else greatest(0,1-coalesce((select max(case when d.day=a.start_date then a.start_fraction when d.day=a.end_date then a.end_fraction else 1 end) from public.hr_absences a where a.employee_id=e.id and a.status='aprobada' and d.day between a.start_date and a.end_date),0)) end),0) available
 from days d join public.hr_staffing_rules r on extract(dow from d.day)::int=any(r.weekdays)
 left join public.hr_employees e on e.active and e.department=r.department and extract(dow from d.day)::int=any(coalesce((select w.weekdays from public.hr_work_patterns w where w.employee_id=e.id and w.effective_from<=d.day order by w.effective_from desc limit 1),array[1,2,3,4,5]))
 where not exists(select 1 from public.hr_holidays h where h.day=d.day)
 group by d.day,r.department,r.minimum)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('shortage',greatest(0,minimum-available)) order by day,department),'[]') from coverage c);
end $$;
revoke all on function private.gama_hr_staffing(date,date) from public,anon;
grant execute on function private.gama_hr_staffing(date,date) to authenticated;
create function public.gama_hr_staffing(p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_hr_staffing(p_from,p_to)$$;
revoke all on function public.gama_hr_staffing(date,date) from public,anon;
grant execute on function public.gama_hr_staffing(date,date) to authenticated;

-- Only operational ownership moves; document authors and audit actors never do.
create table public.erp_handovers(id uuid primary key,source_id uuid not null references public.profiles(id),target_id uuid not null references public.profiles(id),actor_id uuid not null default auth.uid() references public.profiles(id),reason text not null,impact jsonb not null,created_at timestamptz not null default now());
alter table public.erp_handovers enable row level security;
revoke all on public.erp_handovers from public,anon,authenticated;grant select on public.erp_handovers to authenticated;
create policy handover_read on public.erp_handovers for select to authenticated using(private.erp_module_allowed('users',array['administrador']));
create index handover_source on public.erp_handovers(source_id);create index handover_target on public.erp_handovers(target_id);create index handover_actor on public.erp_handovers(actor_id);
create function private.gama_user_handover(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare src uuid:=(p_data->>'source')::uuid;dst uuid:=(p_data->>'target')::uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;s public.profiles;t public.profiles;item record;n bigint;impact jsonb:='[]';old public.erp_handovers;begin
 if not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if src is null or dst is null or src=dst then raise exception 'HANDOVER_TARGET_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('erp-user-handover',0));
 select * into s from public.profiles where id=src for update;select * into t from public.profiles where id=dst for update;
 if s.id is null or t.id is null or not t.active or t.role='cliente' or s.role='cliente' then raise exception 'HANDOVER_STAFF_REQUIRED';end if;
 if t.role<>s.role and t.role<>'administrador' then raise exception 'HANDOVER_ROLE_MISMATCH';end if;
 if exists(select 1 from public.role_module_access a where a.role=coalesce(t.access_profile,t.role) and cardinality(a.disabled_modules)>0) then raise exception 'HANDOVER_TARGET_RESTRICTED';end if;
 if key is not null then select * into old from public.erp_handovers where id=key;if found then
 if old.source_id<>src or old.target_id<>dst or old.actor_id<>auth.uid() or old.reason is distinct from p_data->>'reason' then raise exception 'REQUEST_KEY_CONFLICT';end if;return jsonb_build_object('applied',true,'impact',old.impact);end if;end if;
 for item in select * from (values
 ('public.crm_leads','owner_id','active'),('public.crm_opportunities','owner_id','active and won_at is null and lost_at is null'),
 ('public.customers','owner_id','active'),('public.service_tickets','assigned_to','not archived and status not in (''resolved'',''closed'')'),
 ('public.pm_projects','manager_id','status not in (''closed'',''completed'',''cancelled'')'),('public.pm_projects','sponsor_id','status not in (''closed'',''completed'',''cancelled'')'),
 ('public.pm_items','owner_id','status not in (''done'',''completed'',''approved'',''cancelled'')'),('public.pm_items','approver_id','status not in (''done'',''completed'',''approved'',''cancelled'')'),
 ('public.hr_employees','manager_profile_id','active'),('public.hr_lifecycle_tasks','owner_id','completed_at is null'),
 ('private.gama_alert_handling','assigned_to','true'),('public.business_documents','owner_id','not archived'))v(tbl,col,cond) loop
 execute format('select count(*) from %s where %I=$1 and (%s)',item.tbl,item.col,item.cond) into n using src;
 impact:=impact||jsonb_build_array(jsonb_build_object('table',item.tbl,'field',item.col,'count',n));
 if coalesce((p_data->>'confirm')::boolean,false) and n>0 then execute format('update %s set %I=$2 where %I=$1 and (%s)',item.tbl,item.col,item.col,item.cond) using src,dst;end if;
 end loop;
 if coalesce((p_data->>'confirm')::boolean,false) then
 if key is null or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUEST_KEY_REQUIRED';end if;
 insert into public.erp_handovers(id,source_id,target_id,reason,impact) values(key,src,dst,p_data->>'reason',impact);
 end if;return jsonb_build_object('applied',coalesce((p_data->>'confirm')::boolean,false),'impact',impact);
end $$;
revoke all on function private.gama_user_handover(jsonb) from public,anon;grant execute on function private.gama_user_handover(jsonb) to authenticated;
create function public.gama_user_handover(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_user_handover(p_data)$$;
revoke all on function public.gama_user_handover(jsonb) from public,anon;grant execute on function public.gama_user_handover(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184619','p1_hr_staffing_and_handover','7a8f50d7f200a84974ea31eb1e201890e6f96a5c1320de88bafe04cd405ed2c7','7a8f50d7f200a84974ea31eb1e201890e6f96a5c1320de88bafe04cd405ed2c7','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184620_p1_identity_security_and_access_review.sql; SHA256 b103d15d98cb328ea77bfcfaef7c53b993b468420b4a0c30c61945c86516c22a
-- A verified TOTP factor requires AAL2 for application data and role-based RPCs.
create function private.erp_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (auth.jwt()->>'aal'='aal2' or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
$$;
revoke all on function private.erp_mfa_ok() from public,anon;grant execute on function private.erp_mfa_ok() to authenticated;
create or replace function private.current_user_role() returns text language sql stable security definer set search_path='' as $$
 select role from public.profiles where id=auth.uid() and active and private.erp_mfa_ok() limit 1
$$;
do $$declare t record;begin for t in select tablename from pg_tables where schemaname='public' loop
 execute format('create policy erp_mfa_session on public.%I as restrictive for all to authenticated using((select private.erp_mfa_ok())) with check((select private.erp_mfa_ok()))',t.tablename);
 end loop;end $$;
create table public.erp_access_reviews (
 id uuid primary key default gen_random_uuid(),reviewed_by uuid not null default auth.uid() references public.profiles(id),reviewed_at timestamptz not null default now(),
 next_review date not null,note text not null check(length(btrim(note))>=3),snapshot jsonb not null
);
alter table public.erp_access_reviews enable row level security;
revoke all on public.erp_access_reviews from public,anon,authenticated;grant select on public.erp_access_reviews to authenticated;
create policy access_review_admin on public.erp_access_reviews for select to authenticated using(private.erp_module_allowed('access-settings',array['administrador']));
create index access_review_actor on public.erp_access_reviews(reviewed_by);
create function private.gama_access_review(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;r public.erp_access_reviews;begin
 if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select jsonb_build_object('profiles',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role,'active',p.active,'access_profile',p.access_profile)),'[]') from public.profiles p),'rights',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.role_module_access a),'modules',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.app_modules m)) into result;
 if p_action='snapshot' then return result;
 elsif p_action='confirm' then
 if nullif(p_data->>'next_review','')::date<=current_date then raise exception 'NEXT_REVIEW_FUTURE_REQUIRED';end if;
 insert into public.erp_access_reviews(next_review,note,snapshot) values((p_data->>'next_review')::date,p_data->>'note',result) returning * into r;return to_jsonb(r);
 end if;raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_access_review(text,jsonb) from public,anon;grant execute on function private.gama_access_review(text,jsonb) to authenticated;
create function public.gama_access_review(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_access_review(p_action,p_data)$$;
revoke all on function public.gama_access_review(text,jsonb) from public,anon;grant execute on function public.gama_access_review(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184620','p1_identity_security_and_access_review','b103d15d98cb328ea77bfcfaef7c53b993b468420b4a0c30c61945c86516c22a','b103d15d98cb328ea77bfcfaef7c53b993b468420b4a0c30c61945c86516c22a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184630_p1_receipts_reconciliation_and_followup.sql; SHA256 776e92efd113994402418891c7177541685f0a70c7b2ba8602ef109da613ef79
create table public.customer_receipts (
 id uuid primary key default gen_random_uuid(),request_key uuid not null unique,customer_id uuid not null references public.customers(id),
 financial_account_id uuid not null references public.financial_accounts(id),amount numeric(18,2) not null check(amount>0),
 paid_at date not null,method text not null check(method in ('transfer','cash','card','check','other')),reference text not null,notes text not null default '',
 status text not null default 'confirmed' check(status in ('confirmed','cancelled')),created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),
 cancelled_at timestamptz,cancellation_reason text
);
alter table public.external_invoice_payments add column receipt_id uuid references public.customer_receipts(id);
create index payment_receipt on public.external_invoice_payments(receipt_id);
create index receipt_customer on public.customer_receipts(customer_id,paid_at);create index receipt_account on public.customer_receipts(financial_account_id);create index receipt_actor on public.customer_receipts(created_by);
create table public.receivable_followups (
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.external_invoices(id),kind text not null check(kind in ('promise','dispute')),
 amount numeric(18,2) not null check(amount>0),due_date date,owner_id uuid not null references public.profiles(id),note text not null check(length(btrim(note))>=3),
 status text not null default 'open' check(status in ('open','resolved')),resolution text,created_at timestamptz not null default now(),created_by uuid not null default auth.uid() references public.profiles(id)
);
create index followup_invoice on public.receivable_followups(invoice_id);create index followup_owner on public.receivable_followups(owner_id,due_date);create index followup_actor on public.receivable_followups(created_by);
do $$declare t text;begin foreach t in array array['customer_receipts','receivable_followups'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 execute format('create policy receipt_read on public.%I for select to authenticated using(private.erp_module_allowed(''payments'',array[''administrador'',''comercial'']))',t);
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;end $$;
alter table public.accounting_accounts disable trigger ac_audit_accounting_accounts;
insert into public.accounting_accounts(code,name,type,is_system) values('2090','Anticipos de clientes','liability',true) on conflict(code) do nothing;
alter table public.accounting_accounts enable trigger ac_audit_accounting_accounts;
alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
alter table public.accounting_entries add constraint accounting_entries_source_type_check check(source_type in ('manual','sales_invoice','customer_payment','supplier_invoice','supplier_payment','expense','reversal','opening','return_credit','return_refund','supplier_credit','customer_receipt'));
-- Allocating an advance clears its liability, without recording cash a second time.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure) into src;
 if position($a$bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));$a$ in src)=0 then raise exception 'PAYMENT_POST_ANCHOR';end if;
 src:=replace(src,$a$bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));$a$, $a$bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000')); if p_source_type='customer_payment' then if pay.receipt_id is not null then select id into bank from public.accounting_accounts where code='2090' and active;end if;end if;$a$);execute src;
end $$;
-- View carries all received cash, including unapplied advances, and excludes allocations.
create or replace view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 f.opening_balance+coalesce((select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.receipt_id is null),0)
 +coalesce((select sum(r.amount) from public.customer_receipts r where r.financial_account_id=f.id and r.status='confirmed'),0)
 -coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed'),0)
 -coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status='posted'),0)
 -coalesce((select sum(r.amount) from public.return_refunds r where r.financial_account_id=f.id),0) current_balance,
 coalesce((select count(*) from public.bank_transactions b where b.financial_account_id=f.id and b.status='unmatched'),0) unmatched from public.financial_accounts f;

create function private.gama_receipt_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.customer_receipts;f public.financial_accounts;amount numeric;remaining numeric;line jsonb;inv record;key uuid:=nullif(p_data->>'request_key','')::uuid;payment uuid;entry uuid;cfg public.company_settings;advance uuid;result jsonb;begin
 if not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into cfg from public.company_settings where id;select id into advance from public.accounting_accounts where code='2090' and active;
 if p_action='context' then
 return jsonb_build_object('accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'currency',currency)),'[]') from public.financial_accounts where active and account_id is not null and currency=cfg.currency),
 'receipts',(select coalesce(jsonb_agg(to_jsonb(x) order by x.paid_at desc),'[]') from (select receipt.*,c.name customer_name,receipt.amount-coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=receipt.id and p.status='confirmed'),0) remaining from public.customer_receipts receipt join public.customers c on c.id=receipt.customer_id where nullif(p_data->>'customer_id','') is null or receipt.customer_id=(p_data->>'customer_id')::uuid order by receipt.paid_at desc limit 200)x),
 'followups',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (select follow.*,i.number from public.receivable_followups follow join public.external_invoices i on i.id=follow.invoice_id where nullif(p_data->>'invoice_id','') is null or follow.invoice_id=(p_data->>'invoice_id')::uuid order by follow.created_at desc limit 200)x));
 elsif p_action='receive' then
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended(key::text,0));
 select * into r from public.customer_receipts where request_key=key;if found then
 if r.customer_id is distinct from (p_data->>'customer_id')::uuid or r.amount is distinct from (p_data->>'amount')::numeric or r.financial_account_id is distinct from (p_data->>'financial_account_id')::uuid or r.paid_at is distinct from (p_data->>'paid_at')::date or r.method is distinct from p_data->>'method' or r.reference is distinct from p_data->>'reference' or r.created_by<>auth.uid() then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(r);end if;
 select * into f from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and account_id is not null and currency=cfg.currency;if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if not exists(select 1 from public.customers where id=(p_data->>'customer_id')::uuid and active) then raise exception 'CUSTOMER_REQUIRED';end if;
 if (p_data->>'paid_at')::date>current_date then raise exception 'FUTURE_PAYMENT';end if;
 insert into public.customer_receipts(request_key,customer_id,financial_account_id,amount,paid_at,method,reference,notes) values(key,(p_data->>'customer_id')::uuid,f.id,(p_data->>'amount')::numeric,(p_data->>'paid_at')::date,p_data->>'method',p_data->>'reference',coalesce(p_data->>'notes','')) returning * into r;
 perform private.gama_accounting_book(case when r.method='cash' then 'CAJ' else 'BAN' end,r.paid_at,r.reference,'customer_receipt',r.id,'Anticipo cliente',jsonb_build_array(jsonb_build_object('account_id',f.account_id,'debit',r.amount),jsonb_build_object('account_id',advance,'credit',r.amount,'partner_type','customer','partner_id',r.customer_id)));
 return to_jsonb(r);
 elsif p_action='allocate' then
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended(key::text,0));
 select * into r from public.customer_receipts where id=(p_data->>'id')::uuid for update;if not found or r.status<>'confirmed' then raise exception 'RECEIPT_NOT_AVAILABLE';end if;
 select * into inv from public.external_invoice_payments where request_key=key;if found then if inv.receipt_id<>r.id or inv.invoice_id<>(p_data->>'invoice_id')::uuid or inv.amount<>(p_data->>'amount')::numeric then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(inv);end if;
 perform 1 from public.external_invoices where id=(p_data->>'invoice_id')::uuid for update;
 select * into inv from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and customer_id=r.customer_id and payment_status<>'cancelled';if not found then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 amount:=(p_data->>'amount')::numeric;select r.amount-coalesce(sum(p.amount),0) into remaining from public.external_invoice_payments p where receipt_id=r.id and status='confirmed';
 if amount is null or amount<=0 or amount>remaining or amount>inv.balance or amount<>round(amount,2) then raise exception 'ALLOCATION_AMOUNT_EXCEEDED';end if;
 insert into public.external_invoice_payments(request_key,invoice_id,receipt_id,amount,paid_at,method,reference,account,financial_account_id,created_by)
 values(key,inv.id,r.id,amount,greatest(current_date,r.paid_at),r.method,r.reference,'Anticipo',r.financial_account_id,auth.uid()) returning id into payment;
 perform private.gama_accounting_post('customer_payment',payment);return jsonb_build_object('id',payment,'amount',amount);
 elsif p_action='cancel' then
 select * into r from public.customer_receipts where id=(p_data->>'id')::uuid for update;if not found then raise exception 'RECEIPT_NOT_FOUND';end if;if r.status='cancelled' then return to_jsonb(r);end if;
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 if exists(select 1 from public.external_invoice_payments where receipt_id=r.id and status='confirmed') then raise exception 'ALLOCATIONS_REMAIN';end if;
 select id into entry from public.accounting_entries where source_type='customer_receipt' and source_id=r.id and status='posted';
 if entry is not null then perform private.gama_accounting_reverse(entry,p_data->>'reason');end if;
 update public.customer_receipts set status='cancelled',cancelled_at=now(),cancellation_reason=p_data->>'reason' where id=r.id returning * into r;return to_jsonb(r);
 elsif p_action='followup' then
 if nullif(p_data->>'id','') is not null then
 if length(btrim(coalesce(p_data->>'resolution','')))<3 then raise exception 'RESOLUTION_REQUIRED';end if;
 update public.receivable_followups set status='resolved',resolution=p_data->>'resolution' where id=(p_data->>'id')::uuid and status='open' returning to_jsonb(receivable_followups) into result;return result;
 end if;
 select * into inv from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and payment_status not in ('paid','cancelled');if not found then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 if (p_data->>'amount')::numeric>inv.balance then raise exception 'AMOUNT_EXCEEDED';end if;
 if p_data->>'kind'='promise' and nullif(p_data->>'due_date','') is null then raise exception 'PROMISE_DATE_REQUIRED';end if;
 if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
 insert into public.receivable_followups(invoice_id,kind,amount,due_date,owner_id,note) values(inv.id,p_data->>'kind',(p_data->>'amount')::numeric,nullif(p_data->>'due_date','')::date,(p_data->>'owner_id')::uuid,p_data->>'note') returning to_jsonb(receivable_followups) into result;return result;
 end if;raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_receipt_action(text,jsonb) from public,anon;grant execute on function private.gama_receipt_action(text,jsonb) to authenticated;
create function public.gama_receipt_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_receipt_action(p_action,p_data)$$;
revoke all on function public.gama_receipt_action(text,jsonb) from public,anon;grant execute on function public.gama_receipt_action(text,jsonb) to authenticated;

create table public.bank_match_groups(id uuid primary key default gen_random_uuid(),request_key uuid not null unique,financial_account_id uuid not null references public.financial_accounts(id),note text not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),cancelled_at timestamptz,cancellation_reason text);
create table public.bank_match_banks(group_id uuid not null references public.bank_match_groups(id),bank_id uuid not null references public.bank_transactions(id),amount numeric(18,2) not null,primary key(group_id,bank_id));
create table public.bank_match_sources(group_id uuid not null references public.bank_match_groups(id),kind text not null check(kind in ('customer_payment','customer_receipt','supplier_payment','expense')),source_id uuid not null,amount numeric(18,2) not null check(amount<>0),primary key(group_id,kind,source_id));
create index bank_match_bank on public.bank_match_banks(bank_id);create index bank_match_source on public.bank_match_sources(kind,source_id);create index bank_match_account on public.bank_match_groups(financial_account_id);create index bank_match_actor on public.bank_match_groups(created_by);
do $$declare t text;begin foreach t in array array['bank_match_groups','bank_match_banks','bank_match_sources'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy bank_match_read on public.%I for select to authenticated using(private.erp_module_allowed(''accounting'',array[''administrador'',''comercial'']) and coalesce(private.gama_accounting_rights()->>''scope'','''')=''all'')',t);end loop;end $$;
create function private.gama_bank_match(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();bank public.bank_transactions;grp public.bank_match_groups;source record;x jsonb;total numeric:=0;bank_total numeric:=0;used numeric;key uuid:=nullif(p_data->>'request_key','')::uuid;acc uuid:=(p_data->>'account_id')::uuid;begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object('banks',(select coalesce(jsonb_agg(to_jsonb(b) order by value_date),'[]') from public.bank_transactions b where b.financial_account_id=acc and b.status='unmatched'),
 'sources',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (
 select 'customer_payment'::text kind,p.id,p.reference label,p.paid_at date,p.amount from public.external_invoice_payments p where p.financial_account_id=acc and p.status='confirmed' and p.receipt_id is null
 union all select 'customer_receipt',r.id,r.reference,r.paid_at,r.amount from public.customer_receipts r where r.financial_account_id=acc and r.status='confirmed'
 union all select 'supplier_payment',p.id,p.reference,p.paid_at,-p.amount from public.supplier_invoice_payments p where p.financial_account_id=acc and p.status='confirmed'
 union all select 'expense',e.id,e.description,e.expense_date,-e.amount_total from public.expenses e where e.financial_account_id=acc and e.status='posted')s
 where not exists(select 1 from public.reconciliations r where r.match_type=s.kind and r.match_id=s.id) and not exists(select 1 from public.bank_match_sources l join public.bank_match_groups g on g.id=l.group_id where g.cancelled_at is null and l.kind=s.kind and l.source_id=s.id)),
 'groups',(select coalesce(jsonb_agg(to_jsonb(g) order by created_at desc),'[]') from public.bank_match_groups g where g.financial_account_id=acc));end if;
 if not coalesce((rights->>'validate')::boolean,false) then raise exception 'VALIDATE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||acc::text,0));
 if p_action='cancel' then
 select * into grp from public.bank_match_groups where id=(p_data->>'id')::uuid and financial_account_id=acc for update;if not found then raise exception 'MATCH_NOT_FOUND';end if;
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 update public.bank_match_groups set cancelled_at=coalesce(cancelled_at,now()),cancellation_reason=p_data->>'reason' where id=grp.id;
 update public.bank_transactions set status='unmatched' where id in(select bank_id from public.bank_match_banks where group_id=grp.id);return jsonb_build_object('cancelled',true);end if;
 if p_action<>'apply' or key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into grp from public.bank_match_groups where request_key=key;if found then if grp.financial_account_id<>acc or grp.created_by<>auth.uid() then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(grp);end if;
 if jsonb_array_length(coalesce(p_data->'banks','[]'))=0 or jsonb_array_length(coalesce(p_data->'sources','[]'))=0 then raise exception 'MATCH_LINES_REQUIRED';end if;
 insert into public.bank_match_groups(request_key,financial_account_id,note) values(key,acc,coalesce(p_data->>'note','')) returning * into grp;
 for x in select value from jsonb_array_elements(p_data->'banks') loop
 select * into bank from public.bank_transactions where id=(x#>>'{}')::uuid and financial_account_id=acc for update;
 if not found or bank.status<>'unmatched' then raise exception 'BANK_ALREADY_MATCHED';end if;
 bank_total:=bank_total+bank.amount;insert into public.bank_match_banks values(grp.id,bank.id,bank.amount);
 end loop;
 for x in select value from jsonb_array_elements(p_data->'sources') loop
 if x->>'kind'='customer_payment' then select amount,financial_account_id,status into source from public.external_invoice_payments where id=(x->>'id')::uuid and receipt_id is null for update;
 elsif x->>'kind'='customer_receipt' then select amount,financial_account_id,status into source from public.customer_receipts where id=(x->>'id')::uuid for update;
 elsif x->>'kind'='supplier_payment' then select -amount amount,financial_account_id,status into source from public.supplier_invoice_payments where id=(x->>'id')::uuid for update;
 elsif x->>'kind'='expense' then select -amount_total amount,financial_account_id,case when status='posted' then 'confirmed' else status end status into source from public.expenses where id=(x->>'id')::uuid for update;
 else raise exception 'MATCH_SOURCE_INVALID';end if;
 if not found or source.financial_account_id is distinct from acc or source.status<>'confirmed' then raise exception 'MATCH_SOURCE_UNAVAILABLE';end if;
 if exists(select 1 from public.reconciliations r where r.match_type=x->>'kind' and r.match_id=(x->>'id')::uuid) or exists(select 1 from public.bank_match_sources l join public.bank_match_groups g on g.id=l.group_id where g.cancelled_at is null and l.kind=x->>'kind' and l.source_id=(x->>'id')::uuid) then raise exception 'SOURCE_ALREADY_MATCHED';end if;
 total:=total+source.amount;insert into public.bank_match_sources values(grp.id,x->>'kind',(x->>'id')::uuid,source.amount);
 end loop;
 if total<>bank_total then raise exception 'MATCH_DIFFERENCE:%',bank_total-total;end if;
 update public.bank_transactions set status='matched' where id in(select bank_id from public.bank_match_banks where group_id=grp.id);return to_jsonb(grp);
end $$;
revoke all on function private.gama_bank_match(text,jsonb) from public,anon;grant execute on function private.gama_bank_match(text,jsonb) to authenticated;
create function public.gama_bank_match(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_bank_match(p_action,p_data)$$;
revoke all on function public.gama_bank_match(text,jsonb) from public,anon;grant execute on function public.gama_bank_match(text,jsonb) to authenticated;
-- The legacy single-match endpoint cannot consume sources/banks already grouped.
create function private.erp_reconcile_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.bank_transaction_id and g.cancelled_at is null) or exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind=new.match_type and s.source_id=new.match_id and g.cancelled_at is null) then raise exception 'ALREADY_GROUPED';end if;return new;end $$;
revoke all on function private.erp_reconcile_guard() from public,anon,authenticated;
create trigger erp_reconcile_guard before insert or update on public.reconciliations for each row execute function private.erp_reconcile_guard();
create function private.erp_bank_match_guard() returns trigger language plpgsql security definer set search_path='' as $$declare v_kind text;begin
 if tg_table_name='bank_transactions' then
 if new.status='unmatched' and exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.id and g.cancelled_at is null) then raise exception 'CANCEL_GROUP_FIRST';end if;
 else
 v_kind:=case tg_table_name when 'external_invoice_payments' then 'customer_payment' when 'customer_receipts' then 'customer_receipt' when 'supplier_invoice_payments' then 'supplier_payment' else 'expense' end;
 if new.status is distinct from old.status and exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind=v_kind and s.source_id=new.id and g.cancelled_at is null) then raise exception 'CANCEL_GROUP_FIRST';end if;
 end if;return new;end $$;
revoke all on function private.erp_bank_match_guard() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['bank_transactions','external_invoice_payments','customer_receipts','supplier_invoice_payments','expenses'] loop execute format('create trigger erp_bank_match_guard before update on public.%I for each row execute function private.erp_bank_match_guard()',t);end loop;end $$;
-- PL/pgSQL plans CASE branches against the current trigger record. Separate
-- statements avoid resolving entry_id on the header record (and id on deletes).
create or replace function private.gama_accounting_balance_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare eid uuid;e public.accounting_entries;d numeric;c numeric;begin
 if tg_table_name='accounting_entries' then eid:=coalesce(new.id,old.id);else eid:=coalesce(new.entry_id,old.entry_id);end if;
 select * into e from public.accounting_entries where id=eid;if not found or e.status='draft' then return null;end if;
 select coalesce(sum(debit),0),coalesce(sum(credit),0) into d,c from public.accounting_entry_lines where entry_id=eid;
 if d<>c then raise exception 'ENTRY_UNBALANCED';end if;if d=0 then raise exception 'ENTRY_EMPTY';end if;return null;end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184630','p1_receipts_reconciliation_and_followup','776e92efd113994402418891c7177541685f0a70c7b2ba8602ef109da613ef79','09a3855d87deb518fcf8ab9217a4222d91e18374acb190b376721c04e5c704dc','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184631_p1_product_units_and_historical_costs.sql; SHA256 b54d24d5c9d9d60d2227023bc710d5b74846a8d2a10ba2b2737100f2dfa17220
alter table public.products add column base_unit text not null default 'unit' check(length(btrim(base_unit)) between 1 and 40);
create table public.product_units(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),label text not null check(length(btrim(label)) between 1 and 60),factor numeric(18,6) not null check(factor>0),barcode text,active boolean not null default true,unique(product_id,label));
create unique index product_units_barcode on public.product_units(barcode) where nullif(barcode,'') is not null;
alter table public.product_units enable row level security;
revoke all on public.product_units from public,anon,authenticated;grant select,insert,update on public.product_units to authenticated;
create policy units_read on public.product_units for select to authenticated using(private.current_user_role() in ('administrador','comercial','almacenero'));
create policy units_write on public.product_units for all to authenticated using(private.erp_module_allowed('products',array['administrador','comercial'])) with check(private.erp_module_allowed('products',array['administrador','comercial']));
create table public.product_price_history(sequence bigint generated always as identity unique,id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),changed_at timestamptz not null default now(),changed_by uuid references public.profiles(id),before_prices jsonb,after_prices jsonb not null);
alter table public.product_price_history enable row level security;
revoke all on public.product_price_history from public,anon,authenticated;grant select on public.product_price_history to authenticated;
create policy product_price_history_read on public.product_price_history for select to authenticated using(private.erp_module_allowed('products',array['administrador','comercial']));
create index product_price_history_product on public.product_price_history(product_id,changed_at);create index product_price_history_actor on public.product_price_history(changed_by);
create function private.erp_product_history() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.base_unit is distinct from old.base_unit and (exists(select 1 from public.stock_movements where product_id=new.id) or exists(select 1 from public.sales_order_lines where product_id=new.id) or exists(select 1 from public.purchase_order_lines where product_id=new.id)) then raise exception 'BASE_UNIT_ALREADY_USED';end if;
 if tg_op='INSERT' or (new.purchase_price,new.sale_price,new.sale_price_b,new.tax_rate) is distinct from (old.purchase_price,old.sale_price,old.sale_price_b,old.tax_rate) then
 insert into public.product_price_history(product_id,changed_by,before_prices,after_prices) values(new.id,auth.uid(),case when tg_op='UPDATE' then jsonb_build_object('cost',old.purchase_price,'a',old.sale_price,'b',old.sale_price_b,'tax',old.tax_rate) end,jsonb_build_object('cost',new.purchase_price,'a',new.sale_price,'b',new.sale_price_b,'tax',new.tax_rate));end if;return new;end $$;
revoke all on function private.erp_product_history() from public,anon,authenticated;
create trigger erp_product_history after insert or update on public.products for each row execute function private.erp_product_history();
create function private.erp_unit_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if nullif(new.barcode,'') is not null and exists(select 1 from public.products where barcode=new.barcode) then raise exception 'BARCODE_ALREADY_USED';end if;
 if tg_op='UPDATE' and new.factor<>old.factor then raise exception 'UNIT_FACTOR_IMMUTABLE_CREATE_NEW';end if;return new;end $$;
revoke all on function private.erp_unit_guard() from public,anon,authenticated;
create trigger erp_unit_guard before insert or update on public.product_units for each row execute function private.erp_unit_guard();
create function private.gama_convert_unit(p_product uuid,p_unit uuid,p_quantity numeric) returns jsonb language plpgsql stable security definer set search_path='' as $$declare p public.products;u public.product_units;q numeric;begin
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into p from public.products where id=p_product and active;select * into u from public.product_units where id=p_unit and product_id=p_product and active;
 if p.id is null or u.id is null or p_quantity is null or p_quantity<=0 then raise exception 'UNIT_QUANTITY_REQUIRED';end if;q:=p_quantity*u.factor;
 if q<>round(q,3) or q>=100000000 then raise exception 'BASE_QUANTITY_PRECISION';end if;
 return jsonb_build_object('product_id',p.id,'unit_id',u.id,'quantity',p_quantity,'factor',u.factor,'base_quantity',q,'base_unit',p.base_unit,'label',u.label);
end $$;
revoke all on function private.gama_convert_unit(uuid,uuid,numeric) from public,anon;grant execute on function private.gama_convert_unit(uuid,uuid,numeric) to authenticated;
create function public.gama_convert_unit(p_product uuid,p_unit uuid,p_quantity numeric) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_convert_unit(p_product,p_unit,p_quantity)$$;
revoke all on function public.gama_convert_unit(uuid,uuid,numeric) from public,anon;grant execute on function public.gama_convert_unit(uuid,uuid,numeric) to authenticated;

-- Historical standard-cost valuation starts at this observed opening snapshot.
-- Earlier dates are explicitly unavailable; no guessed historical cost is backfilled.
create table private.erp_stock_cost_epoch(id boolean primary key default true check(id),observed_at timestamptz not null default now());
insert into private.erp_stock_cost_epoch(id) values(true);
revoke all on private.erp_stock_cost_epoch from public,anon,authenticated;
create table private.erp_stock_cost_opening(product_id uuid primary key references public.products(id),quantity numeric not null,unit_cost numeric not null,observed_at timestamptz not null default now());
insert into private.erp_stock_cost_opening(product_id,quantity,unit_cost) select p.id,coalesce((select sum(q.quantity) from public.stock_quants q where q.product_id=p.id),0),coalesce(p.purchase_price,0) from public.products p;
revoke all on private.erp_stock_cost_opening from public,anon,authenticated;
alter table public.stock_movements add column unit_cost_at_movement numeric;
create function private.erp_movement_cost() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.unit_cost_at_movement is distinct from old.unit_cost_at_movement then raise exception 'MOVEMENT_COST_IMMUTABLE';end if;
 if tg_op='INSERT' then
 select coalesce(p.purchase_price,0) into new.unit_cost_at_movement from public.products p where p.id=new.product_id;
 if new.reference_type='purchase_order' then select coalesce(sum(l.quantity*l.unit_cost)/nullif(sum(l.quantity),0),new.unit_cost_at_movement) into new.unit_cost_at_movement from public.purchase_order_lines l where l.purchase_order_id=new.reference_id and l.product_id=new.product_id;end if;
 end if;return new;end $$;
revoke all on function private.erp_movement_cost() from public,anon,authenticated;
create trigger erp_movement_cost before insert or update on public.stock_movements for each row execute function private.erp_movement_cost();
create function private.gama_historical_stock(p_asof timestamptz) returns jsonb language plpgsql stable security definer set search_path='' as $$declare starts timestamptz;rights jsonb:=private.gama_accounting_rights();begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select observed_at into starts from private.erp_stock_cost_epoch where id;if p_asof is null or p_asof<starts or p_asof>now() then raise exception 'VALUATION_DATE_UNAVAILABLE:%',starts;end if;
 return jsonb_build_object('as_of',p_asof,'available_from',starts,'method','registered_standard_cost','rows',(with source as(
 select p.id,p.name,p.reference,p.base_unit,coalesce(o.quantity,0)+coalesce((select sum(case when m.stock_before is not null and m.stock_after is not null then m.stock_after-m.stock_before when m.type='in' then m.quantity when m.type='out' then -abs(m.quantity) when m.type='adjustment' then m.quantity else 0 end) from public.stock_movements m where m.product_id=p.id and m.created_at>=coalesce(o.observed_at,starts) and m.created_at<=p_asof),0) quantity,
 coalesce((select (h.after_prices->>'cost')::numeric from public.product_price_history h where h.product_id=p.id and h.changed_at<=p_asof order by h.changed_at desc,h.sequence desc limit 1),o.unit_cost,0) cost
 from public.products p left join private.erp_stock_cost_opening o on o.product_id=p.id where p.created_at<=p_asof)
 select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('value',round(quantity*cost,2)) order by name,id),'[]') from source s));
end $$;
revoke all on function private.gama_historical_stock(timestamptz) from public,anon;grant execute on function private.gama_historical_stock(timestamptz) to authenticated;
create function public.gama_historical_stock(p_asof timestamptz) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_historical_stock(p_asof)$$;
revoke all on function public.gama_historical_stock(timestamptz) from public,anon;grant execute on function public.gama_historical_stock(timestamptz) to authenticated;

alter table public.invoices add column accepted_snapshot jsonb;
create function private.erp_quote_snapshot() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and old.accepted_snapshot is not null then
 if new.accepted_snapshot is distinct from old.accepted_snapshot then raise exception 'ACCEPTED_SNAPSHOT_IMMUTABLE';end if;
 elsif new.quote_state='accepted' then
 new.accepted_snapshot:=jsonb_build_object('captured_at',now(),'company',(select private.gama_company_public(c) from public.company_settings c where id),'header',to_jsonb(new)-'accepted_snapshot','lines',(select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]') from public.invoice_lines l where l.invoice_id=new.id));
 elsif new.accepted_snapshot is not null then raise exception 'ACCEPTANCE_REQUIRED';end if;return new;end $$;
revoke all on function private.erp_quote_snapshot() from public,anon,authenticated;
create trigger erp_quote_snapshot before insert or update on public.invoices for each row execute function private.erp_quote_snapshot();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184631','p1_product_units_and_historical_costs','b54d24d5c9d9d60d2227023bc710d5b74846a8d2a10ba2b2737100f2dfa17220','b54d24d5c9d9d60d2227023bc710d5b74846a8d2a10ba2b2737100f2dfa17220','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184632_p1_dossier_and_project_followthrough.sql; SHA256 41c461a224c12838a1f7518d5ba7efff61bc33bebce6f5424336bafe8bfc4619
create table public.dossier_followups(id uuid primary key default gen_random_uuid(),dossier_key text not null unique,owner_id uuid not null references public.profiles(id),next_action text not null check(length(btrim(next_action))>0),due_date date not null,updated_at timestamptz not null default now(),updated_by uuid not null default auth.uid() references public.profiles(id),closed_at timestamptz,closed_by uuid references public.profiles(id),closure_fingerprint text,closure_note text);
alter table public.dossier_followups enable row level security;revoke all on public.dossier_followups from public,anon,authenticated;grant select on public.dossier_followups to authenticated;
create policy dossier_followup_read on public.dossier_followups for select to authenticated using(private.erp_module_allowed('dossier-flow',array['administrador','comercial']));
create index dossier_followup_owner on public.dossier_followups(owner_id,due_date);create index dossier_followup_actor on public.dossier_followups(updated_by);create index dossier_followup_closer on public.dossier_followups(closed_by);
create trigger erp_audit_capture after insert or update or delete on public.dossier_followups for each row execute function private.erp_audit_capture();
create function private.gama_dossier_followup(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'key';source uuid;kind text;f public.dossier_followups;checks jsonb;fp text;missing numeric;unbilled numeric;balance numeric;ret bigint;begin
 if not private.erp_module_allowed('dossier-flow',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 kind:=split_part(k,':',1);source:=split_part(k,':',2)::uuid;
 if (kind='o' and not exists(select 1 from public.sales_orders where id=source)) or (kind='q' and not exists(select 1 from public.invoices where id=source)) or (kind='r' and not exists(select 1 from public.customer_requests where id=source)) or kind not in ('o','q','r') then raise exception 'DOSSIER_NOT_FOUND';end if;
 if kind='o' then
 perform 1 from public.sales_orders where id=source for update;
 select coalesce(sum(greatest(0,l.quantity-coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl join public.sales_deliveries s on s.id=dl.delivery_id join public.tms_deliveries t on t.id=s.tms_delivery_id join public.tms_proofs pr on pr.delivery_id=t.id where dl.order_line_id=l.id and t.status='Entregada' and nullif(pr.signature,'') is not null),0))),0) into missing from public.sales_order_lines l where l.order_id=source;
 select coalesce(sum(greatest(0,l.quantity-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('rejected','cancelled')),0))),0) into unbilled from public.sales_order_lines l where l.order_id=source;
 select coalesce(sum(r.balance),0) into balance from private.gama_receivables r where r.order_id=source and r.payment_status<>'cancelled';select count(*) into ret from public.return_orders where order_id=source and status not in ('closed','cancelled');
 checks:=jsonb_build_object('delivery_remainder',missing,'unbilled_quantity',unbilled,'unpaid_amount',balance,'open_returns',ret,'empty_order',not exists(select 1 from public.sales_order_lines where order_id=source),'order_confirmed',exists(select 1 from public.sales_orders where id=source and status='confirmed'));
 else checks:=jsonb_build_object('order_required',true);end if;
 fp:=md5(checks::text);select * into f from public.dossier_followups where dossier_key=k for update;
 if p_action='save' then
 if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
 insert into public.dossier_followups(dossier_key,owner_id,next_action,due_date) values(k,(p_data->>'owner_id')::uuid,p_data->>'next_action',(p_data->>'due_date')::date) on conflict(dossier_key) do update set owner_id=excluded.owner_id,next_action=excluded.next_action,due_date=excluded.due_date,updated_by=auth.uid(),updated_at=now() returning * into f;
 elsif p_action='close' then
 if f.id is null then raise exception 'FOLLOWUP_REQUIRED';end if;
 if kind<>'o' or missing>0 or unbilled>0 or balance>0.005 or ret>0 or (checks->>'empty_order')::boolean or not(checks->>'order_confirmed')::boolean then raise exception 'DOSSIER_INCOMPLETE';end if;
 if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'CLOSURE_NOTE_REQUIRED';end if;
 update public.dossier_followups set closed_at=now(),closed_by=auth.uid(),closure_note=p_data->>'note',closure_fingerprint=fp where id=f.id returning * into f;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('followup',case when f.id is null then null else to_jsonb(f) end,'checks',checks,'closed',coalesce(f.closed_at is not null and f.closure_fingerprint=fp,false),'reopened',coalesce(f.closed_at is not null and f.closure_fingerprint<>fp,false));
end $$;
revoke all on function private.gama_dossier_followup(text,jsonb) from public,anon;grant execute on function private.gama_dossier_followup(text,jsonb) to authenticated;
create function public.gama_dossier_followup(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_dossier_followup(p_action,p_data)$$;
revoke all on function public.gama_dossier_followup(text,jsonb) from public,anon;grant execute on function public.gama_dossier_followup(text,jsonb) to authenticated;

create table public.pm_cost_entries(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.pm_projects(id),entry_date date not null,kind text not null check(kind in ('labor','other')),description text not null check(length(btrim(description))>=3),quantity numeric(14,3) not null check(quantity>0),unit_cost numeric(16,4) not null check(unit_cost>=0),amount numeric(18,2) generated always as(round(quantity*unit_cost,2)) stored,source_reference text not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),cancelled_at timestamptz,cancellation_reason text,unique(project_id,source_reference));
create table public.pm_baselines(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.pm_projects(id),name text not null check(length(btrim(name))>=3),snapshot jsonb not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now());
do $$declare t text;begin foreach t in array array['pm_cost_entries','pm_baselines'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy pm_finance_read on public.%I for select to authenticated using(private.pm_manage(project_id))',t);execute format('create index %I on public.%I(project_id)',t||'_project',t);execute format('create index %I on public.%I(created_by)',t||'_actor',t);execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);end loop;end $$;
create function private.pm_financials(pid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with p as(select * from public.pm_projects where id=pid),extra as(
 select coalesce((select sum(amount) from public.pm_cost_entries where project_id=pid and cancelled_at is null),0) entered,
 coalesce((select sum(e.amount_untaxed) from public.expenses e,p where e.project_id=pid and e.status='posted' and e.currency=p.currency),0) expenses,
 coalesce((select sum(b.subtotal) from public.supplier_invoices b,p where b.project_id=pid and b.status='posted' and p.currency=(select currency from public.company_settings where id) and not exists(select 1 from public.pm_links l where l.kind='purchase' and l.target_id=b.purchase_order_id)),0) supplier_bills,
 (select count(*) from public.expenses e,p where e.project_id=pid and e.status='posted' and e.currency<>p.currency)+(select count(*) from public.supplier_invoices b,p where b.project_id=pid and b.status='posted' and p.currency<>(select currency from public.company_settings where id) and not exists(select 1 from public.pm_links l where l.kind='purchase' and l.target_id=b.purchase_order_id)) unconverted_costs
 ),revenue as(select distinct i.id,i.subtotal-coalesce((select sum((private.gama_return_split(c.return_id,c.amount)->>'net')::numeric) from public.return_credits c where c.invoice_id=i.id),0) net,
 case when p.currency=(select currency from public.company_settings where id) then 1 when l.currency=(select currency from public.company_settings where id) then l.exchange_rate else null end fx
 from public.external_invoices i join public.sales_orders o on o.id=i.order_id join public.pm_links l on l.project_id=pid and ((l.kind='order' and l.target_id=o.id) or (l.kind='quote' and l.target_id=o.source_quote_id)) cross join p where i.fiscal_status not in ('rejected','cancelled'))
 select jsonb_build_object('entered',entered,'expenses',expenses,'supplier_bills',supplier_bills,'additional_cost',entered+expenses+supplier_bills,'unconverted_costs',unconverted_costs,'revenue',coalesce((select sum(net*fx) from (select id,max(net) net,max(fx) fx from revenue group by id)r),0),'unconverted_revenue',(select count(distinct id) from revenue where fx is null)) from extra
$$;
revoke all on function private.pm_financials(uuid) from public,anon,authenticated;
-- Retain the existing metrics contract while completing its actual cost base.
alter function private.pm_metrics(uuid) rename to pm_metrics_purchases;
create function private.pm_metrics(pid uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$declare m jsonb:=private.pm_metrics_purchases(pid);f jsonb:=private.pm_financials(pid);p public.pm_projects;actual numeric;forecast numeric;ch int;begin
 select * into p from public.pm_projects where id=pid;actual:=(m->>'actual')::numeric+(f->>'additional_cost')::numeric;forecast:=actual+(m->>'committed')::numeric+coalesce(p.estimate_remaining,greatest(0,p.budget-actual-(m->>'committed')::numeric));ch:=case when p.status in ('completed','cancelled') then 0 when forecast>p.budget*(1+p.budget_tolerance/100) then 2 when forecast>p.budget then 1 else 0 end;
 return m||f||jsonb_build_object('actual',actual,'remaining',p.budget-actual,'forecast',forecast,'etc',forecast-actual,'vac',p.budget-forecast,'cost_health',ch,'health',greatest(ch,(m->>'schedule_health')::int,(m->>'risk_health')::int),'margin',(f->>'revenue')::numeric-actual);
end $$;
revoke all on function private.pm_metrics(uuid) from public,anon,authenticated;
create function private.gama_project_finance(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare pid uuid:=(p_data->>'project_id')::uuid;p public.pm_projects;x jsonb;begin
 if not private.erp_module_allowed('projects',array['administrador','comercial','almacenero']) or not private.pm_manage(pid) then raise exception 'ROLE_NOT_ALLOWED';end if;select * into p from public.pm_projects where id=pid for update;
 if p_action='cost' then
 if p.status in ('completed','cancelled') then raise exception 'PROJECT_CLOSED';end if;
 insert into public.pm_cost_entries(id,project_id,entry_date,kind,description,quantity,unit_cost,source_reference) values((p_data->>'id')::uuid,pid,(p_data->>'entry_date')::date,p_data->>'kind',p_data->>'description',(p_data->>'quantity')::numeric,(p_data->>'unit_cost')::numeric,p_data->>'source_reference') on conflict(id) do nothing;
 elsif p_action='cancel_cost' then if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;update public.pm_cost_entries set cancelled_at=coalesce(cancelled_at,now()),cancellation_reason=p_data->>'reason' where id=(p_data->>'id')::uuid and project_id=pid;
 elsif p_action='baseline' then
 insert into public.pm_baselines(id,project_id,name,snapshot) values((p_data->>'id')::uuid,pid,p_data->>'name',jsonb_build_object('project',to_jsonb(p),'metrics',private.pm_metrics(pid),'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') from public.pm_items i where project_id=pid))) on conflict(id) do nothing;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('project',to_jsonb(p),'metrics',private.pm_metrics(pid),'costs',(select coalesce(jsonb_agg(to_jsonb(e) order by entry_date desc),'[]') from public.pm_cost_entries e where project_id=pid),'baselines',(select coalesce(jsonb_agg(to_jsonb(b) order by created_at desc),'[]') from public.pm_baselines b where project_id=pid));
end $$;
revoke all on function private.gama_project_finance(text,jsonb) from public,anon;grant execute on function private.gama_project_finance(text,jsonb) to authenticated;
create function public.gama_project_finance(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_project_finance(p_action,p_data)$$;
revoke all on function public.gama_project_finance(text,jsonb) from public,anon;grant execute on function public.gama_project_finance(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184632','p1_dossier_and_project_followthrough','41c461a224c12838a1f7518d5ba7efff61bc33bebce6f5424336bafe8bfc4619','41c461a224c12838a1f7518d5ba7efff61bc33bebce6f5424336bafe8bfc4619','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184634_p1_transport_proofs_and_notification_preferences.sql; SHA256 361098acf91309946e10333397d0fbb06e9777fef547b63c1c393b339c54c29f
create function private.gama_tms_capture(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;pr public.tms_proofs;key uuid:=(p_data->>'request_key')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('hash',md5((p_data-'request_key')::text));stamp timestamptz:=nullif(p_data->>'captured_at','')::timestamptz;signature text:=p_data->>'signature';photo text:=p_data->>'photo';result jsonb;begin
 if not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended('tms-capture:'||key::text,0));
 select * into receipt from private.command_receipts where domain='tms-capture' and request_key=key;if found then if receipt.actor_id<>auth.uid() or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;if not found or d.status in ('Entregada','Cancelada') then raise exception 'DELIVERY_CLOSED';end if;
 if stamp is null or stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
 if signature is null and photo is null then raise exception 'PROOF_REQUIRED';end if;
 if (signature is not null and (signature!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(signature)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
 if p_data->>'complete'='true' and nullif(signature,'') is null then raise exception 'SIGNATURE_REQUIRED';end if;
 select * into pr from public.tms_proofs where delivery_id=d.id for update;
 if pr.signature is not null and signature is not null and pr.signature<>signature then raise exception 'PROOF_CONFLICT';end if;
 insert into public.tms_proofs(delivery_id,photo,signature,captured_at,captured_by) values(d.id,photo,signature,stamp,auth.uid()) on conflict(delivery_id) do update set photo=coalesce(excluded.photo,tms_proofs.photo),signature=coalesce(excluded.signature,tms_proofs.signature),captured_at=excluded.captured_at,captured_by=excluded.captured_by;
 if p_data->>'complete'='true' then
 update public.tms_deliveries set status='Entregada',actual_arrival=coalesce(actual_arrival,stamp),delivered_at=stamp where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'Entregada','Prueba de entrega registrada',d.customer,auth.uid());end if;
 result:=jsonb_build_object('delivery_id',d.id,'captured_at',stamp,'completed',p_data->>'complete'='true');insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-capture',key,auth.uid(),payload,result);return result;
end $$;
revoke all on function private.gama_tms_capture(jsonb) from public,anon;grant execute on function private.gama_tms_capture(jsonb) to authenticated;
create function public.gama_tms_capture(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_capture(p_data)$$;
revoke all on function public.gama_tms_capture(jsonb) from public,anon;grant execute on function public.gama_tms_capture(jsonb) to authenticated;

alter table public.tms_deliveries add column service_minutes integer not null default 10 check(service_minutes between 0 and 480);
create table public.tms_route_schedules(id uuid primary key default gen_random_uuid(),route_id uuid not null unique references public.tms_routes(id),starts_at timestamptz not null,legs jsonb not null,road_source text not null check(length(btrim(road_source))>=3),road_km numeric not null check(road_km>=0),duration_minutes integer not null check(duration_minutes>=0),updated_by uuid not null default auth.uid() references public.profiles(id),updated_at timestamptz not null default now());
alter table public.tms_route_schedules enable row level security;revoke all on public.tms_route_schedules from public,anon,authenticated;grant select on public.tms_route_schedules to authenticated;
create policy route_schedule_read on public.tms_route_schedules for select to authenticated using(private.erp_module_allowed('tms',array['administrador','almacenero']));create index route_schedule_actor on public.tms_route_schedules(updated_by);
create trigger erp_audit_capture after insert or update or delete on public.tms_route_schedules for each row execute function private.erp_audit_capture();
create function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes int:=0;km numeric:=0;n int:=0;travel int;service int;row public.tms_route_schedules;begin
 if not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 if stamp is null or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
 if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
 travel:=(x->>'drive_minutes')::int;service:=(x->>'service_minutes')::int;
 if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric<0 then raise exception 'ROUTE_TIME_REQUIRED';end if;
 minutes:=minutes+travel;km:=km+(x->>'road_km')::numeric;legs:=legs||jsonb_build_array(x||jsonb_build_object('arrival_at',stamp+make_interval(mins=>minutes),'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;
 end loop;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes) values(r.id,stamp,legs,p_data->>'road_source',km,minutes) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,updated_by=auth.uid(),updated_at=now() returning * into row;return to_jsonb(row);
end $$;
revoke all on function private.gama_route_schedule(jsonb) from public,anon;grant execute on function private.gama_route_schedule(jsonb) to authenticated;
create function public.gama_route_schedule(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_route_schedule(p_data)$$;
revoke all on function public.gama_route_schedule(jsonb) from public,anon;grant execute on function public.gama_route_schedule(jsonb) to authenticated;

-- Preferences filter the notification list and its count, never the operations KPIs.
do $$declare src text;begin select pg_get_functiondef('private.gama_operations_core(text,jsonb)'::regprocedure) into src;
 if position('), filtered as (' in src)=0 then raise exception 'NOTIFICATION_FILTER_ANCHOR';end if;
 src:=replace(src,'), filtered as (',$patch$), preferred as (
 select h.* from handled h where not coalesce((p_data->>'respect_preferences')::boolean,false) or (
 not exists(select 1 from public.erp_notification_preferences pref where pref.user_id=auth.uid() and (h.kind=any(pref.hidden_kinds) or (pref.only_mine and h.assigned_to is distinct from auth.uid())))
 and (coalesce(p_data->>'notification_class','all')='all' or (p_data->>'notification_class'='action' and h.priority>=2) or (p_data->>'notification_class'='information' and h.priority<2)))) , filtered as ($patch$);
 src:=replace(src,'select * from handled where','select * from preferred where');src:=replace(src,$p$from handled where handling<>'snoozed'$p$,$p$from preferred where handling<>'snoozed'$p$);src:=replace(src,'from handled group by kind','from preferred group by kind');execute src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184634','p1_transport_proofs_and_notification_preferences','361098acf91309946e10333397d0fbb06e9777fef547b63c1c393b339c54c29f','361098acf91309946e10333397d0fbb06e9777fef547b63c1c393b339c54c29f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184635_p1_action_permissions_and_closing_controls.sql; SHA256 14cff5d6562d40d9a93a938809da4da82bdde2bbf71cf0eddaf1f0ec4f0f610d
-- Action restrictions narrow the existing business roles; they never grant privileges.
create table public.erp_action_permissions(role text not null references public.role_module_access(role),module text not null,allow_create boolean not null default true,allow_edit boolean not null default true,allow_delete boolean not null default true,allow_validate boolean not null default true,allow_export boolean not null default true,updated_at timestamptz not null default now(),updated_by uuid not null default auth.uid() references public.profiles(id),primary key(role,module));
alter table public.erp_action_permissions enable row level security;revoke all on public.erp_action_permissions from public,anon,authenticated;grant select,insert,update on public.erp_action_permissions to authenticated;
create policy action_rights_read on public.erp_action_permissions for select to authenticated using(private.current_user_role()='administrador' or role=(select coalesce(p.access_profile,p.role) from public.profiles p where p.id=auth.uid()));
create policy action_rights_admin on public.erp_action_permissions for all to authenticated using(private.current_user_role()='administrador') with check(private.current_user_role()='administrador');
create index action_rights_actor on public.erp_action_permissions(updated_by);
create trigger erp_audit_capture after insert or update or delete on public.erp_action_permissions for each row execute function private.erp_audit_capture();
create function private.erp_action_allowed(p_module text,p_action text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select p.active and private.erp_mfa_ok() and coalesce(case p_action when 'create' then a.allow_create when 'edit' then a.allow_edit when 'delete' then a.allow_delete when 'validate' then a.allow_validate when 'export' then a.allow_export else false end,true) from public.profiles p left join public.erp_action_permissions a on a.role=coalesce(p.access_profile,p.role) and a.module=p_module where p.id=auth.uid()),false)
$$;
revoke all on function private.erp_action_allowed(text,text) from public,anon;grant execute on function private.erp_action_allowed(text,text) to authenticated;
create function public.gama_action_allowed(p_module text,p_action text) returns boolean language sql stable security invoker set search_path='' as $$select private.erp_action_allowed(p_module,p_action)$$;
revoke all on function public.gama_action_allowed(text,text) from public,anon;grant execute on function public.gama_action_allowed(text,text) to authenticated;
create function private.erp_action_guard() returns trigger language plpgsql security definer set search_path='' as $$declare action text:=case tg_op when 'INSERT' then 'create' when 'DELETE' then 'delete' else 'edit' end;n jsonb;o jsonb;begin
 if auth.uid() is null then if tg_op='DELETE' then return old;else return new;end if;end if;
 if not private.erp_action_allowed(tg_argv[0],action) then raise exception 'ACTION_NOT_ALLOWED:%:%',tg_argv[0],action;end if;
 if tg_op in ('INSERT','UPDATE') then n:=to_jsonb(new);o:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
 if ((n->>'status' is distinct from o->>'status' and n->>'status' in ('accepted','confirmed','posted','approved','validated','closed','received','completed','Entregada','Terminada')) or (n->>'quote_state' is distinct from o->>'quote_state' and n->>'quote_state' in ('sent','accepted'))) and not private.erp_action_allowed(tg_argv[0],'validate') then raise exception 'ACTION_NOT_ALLOWED:%:validate',tg_argv[0];end if;
 end if;if tg_op='DELETE' then return old;else return new;end if;
end $$;
revoke all on function private.erp_action_guard() from public,anon,authenticated;
do $$declare r record;begin for r in select * from (values
 ('products','products'),('product_units','products'),('customers','clients'),('customer_addresses','clients'),('suppliers','suppliers'),('supplier_product_offers','suppliers'),
 ('crm_leads','crm'),('crm_opportunities','crm'),('crm_contacts','crm'),('crm_activities','crm'),('invoices','quotes'),('invoice_lines','quotes'),('sales_orders','sales-orders'),('sales_order_lines','sales-orders'),
 ('purchase_orders','gamaPurchasesV14'),('purchase_order_lines','gamaPurchasesV14'),('stock_movements','movement'),('inventory_counts','warehouses'),('inventory_count_lines','warehouses'),
 ('customer_receipts','payments'),('external_invoice_payments','payments'),('receivable_followups','payments'),('service_tickets','sav'),('service_messages','sav'),('business_documents','documents'),
 ('expenses','accounting'),('supplier_invoices','accounting'),('supplier_invoice_payments','accounting'),('return_orders','returns'),('return_refunds','returns'),('hr_employees','hr'),('hr_absences','hr'),('hr_lifecycle_tasks','hr'),('pm_projects','projects'),('pm_items','projects'),('pm_cost_entries','projects'),('tms_routes','tms'),('tms_deliveries','tms'),('fleet_vehicles','fleet'))m(tbl,module) loop
 if to_regclass('public.'||r.tbl) is not null then execute format('create trigger erp_action_guard before insert or update or delete on public.%I for each row execute function private.erp_action_guard(%L)',r.tbl,r.module);end if;end loop;end $$;
-- Direct stock routines predate the common role helper. Gate all authenticated
-- public PL/pgSQL security-definer entrypoints before their first statement.
do $$declare r record;src text;begin for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='public' and p.prokind='f' and p.prosecdef and l.lanname='plpgsql' and has_function_privilege('authenticated',p.oid,'EXECUTE') loop
 src:=pg_get_functiondef(r.oid);src:=regexp_replace(src,'\mBEGIN\M',E'BEGIN\n IF auth.uid() IS NOT NULL AND NOT private.erp_mfa_ok() THEN RAISE EXCEPTION ''MFA_REQUIRED''; END IF;','i');execute src;
 end loop;end $$;
-- An inactive/AAL1 account must not recover permissions through an accounting override.
do $$declare src text;begin select pg_get_functiondef('private.gama_accounting_rights()'::regprocedure) into src;src:=replace(src,' select * into p from public.accounting_permissions', ' if r='''' then return rights;end if; select * into p from public.accounting_permissions');execute src;end $$;

create function private.erp_timezone() returns text language sql stable security definer set search_path='' as $$select coalesce((select timezone from public.erp_policies where id),'America/Guayaquil')$$;
revoke all on function private.erp_timezone() from public,anon;grant execute on function private.erp_timezone() to authenticated;
-- Replace hard-coded reporting timezone expressions, retaining source timestamps.
do $$declare r record;src text;opts text;begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname in ('private','public') and p.prokind='f' and l.lanname in ('plpgsql','sql') and p.proname<>'erp_timezone' and position('''America/Guayaquil''' in p.prosrc)>0 loop
 src:=pg_get_functiondef(r.oid);src:=replace(src,'''America/Guayaquil''','private.erp_timezone()');src:=replace(src,'IMMUTABLE','STABLE');execute src;end loop;
 for r in select c.oid,n.nspname,c.relname,c.reloptions from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('private','public') and c.relkind='v' loop
 src:=pg_get_viewdef(r.oid,true);if position('''America/Guayaquil''' in src)>0 then
 opts:=case when r.reloptions is null then '' else ' with ('||array_to_string(r.reloptions,',')||')' end;
 execute format('create or replace view %I.%I%s as %s',r.nspname,r.relname,opts,replace(src,'''America/Guayaquil''','private.erp_timezone()'));end if;end loop;
end $$;
-- Surface the same timezone to every client through the safe company profile.
do $$declare src text;begin select pg_get_functiondef('private.gama_company_public(public.company_settings)'::regprocedure) into src;src:=replace(src,'IMMUTABLE','STABLE');src:=replace(src,'''legal_name'',c.legal_name','''timezone'',private.erp_timezone(),''legal_name'',c.legal_name');execute src;end $$;

create function private.gama_closing_review(p_month date) returns jsonb language plpgsql stable security definer set search_path='' as $$declare rights jsonb:=private.gama_accounting_rights();first date:=date_trunc('month',p_month)::date;last date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return jsonb_build_object('from',first,'to',last,'draft_entries',(select count(*) from public.accounting_entries where entry_date between first and last and status='draft'),
 'unposted_invoices',(select count(*) from public.external_invoices i where i.issue_date between first and last and i.fiscal_status not in ('cancelled','rejected') and not exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status='posted')),
 'unposted_payments',(select count(*) from public.external_invoice_payments p where p.paid_at between first and last and p.status='confirmed' and not exists(select 1 from public.accounting_entries e where e.source_type='customer_payment' and e.source_id=p.id and e.status='posted')),
 'unmatched_bank',(select count(*) from public.bank_transactions where value_date between first and last and status='unmatched'),
 'unmatched_bills',(select count(*) from public.supplier_invoices b where b.issue_date between first and last and b.status='posted' and b.purchase_order_id is not null and b.match_required and not exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=b.id)),
 'unassigned_payments',(select count(*) from public.external_invoice_payments where paid_at between first and last and status='confirmed' and financial_account_id is null));
end $$;
revoke all on function private.gama_closing_review(date) from public,anon;grant execute on function private.gama_closing_review(date) to authenticated;
create function public.gama_closing_review(p_month date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_closing_review(p_month)$$;
revoke all on function public.gama_closing_review(date) from public,anon;grant execute on function public.gama_closing_review(date) to authenticated;
create function private.erp_closing_guard() returns trigger language plpgsql security definer set search_path='' as $$declare checks jsonb;begin
 if new.status='closed' and old.status<>'closed' and auth.uid() is not null then
 if not private.erp_action_allowed('accounting','validate') then raise exception 'ACTION_NOT_ALLOWED:accounting:validate';end if;
 checks:=private.gama_closing_review(new.period_start);
 if (checks->>'draft_entries')::int+(checks->>'unposted_invoices')::int+(checks->>'unposted_payments')::int>0 then raise exception 'CLOSING_POSTINGS_REQUIRED';end if;
 end if;return new;end $$;
revoke all on function private.erp_closing_guard() from public,anon,authenticated;
create trigger erp_closing_guard before update on public.accounting_periods for each row execute function private.erp_closing_guard();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184635','p1_action_permissions_and_closing_controls','14cff5d6562d40d9a93a938809da4da82bdde2bbf71cf0eddaf1f0ec4f0f610d','14cff5d6562d40d9a93a938809da4da82bdde2bbf71cf0eddaf1f0ec4f0f610d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184636_p1_workflow_guardrails_and_access_controls.sql; SHA256 7e992c76077068b3cd6567b1e600da0bb020bb04007fb39d87e7d6abf4e9c9da
-- Complete the user-facing access review and prevent stale policy writes.
create function private.gama_save_action_permissions(p_role text,p_rows jsonb,p_expected jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_rows jsonb;item jsonb;begin
 if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.role_module_access where role=p_role for update;if not found then raise exception 'PROFILE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(a) order by a.module),'[]') into current_rows from public.erp_action_permissions a where role=p_role;
 if current_rows is distinct from (select coalesce(jsonb_agg(v order by v->>'module'),'[]') from jsonb_array_elements(p_expected)v) then raise exception 'ACCESS_SETTINGS_CHANGED';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>100 then raise exception 'INVALID_PERMISSIONS';end if;
 for item in select value from jsonb_array_elements(p_rows) loop
 if coalesce(item->>'module','') not in ('mainmenu','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing','sav','documents') then raise exception 'MODULE_NOT_FOUND';end if;
 insert into public.erp_action_permissions(role,module,allow_create,allow_edit,allow_delete,allow_validate,allow_export,updated_at,updated_by)
 values(p_role,item->>'module',(item->>'allow_create')::boolean,(item->>'allow_edit')::boolean,(item->>'allow_delete')::boolean,(item->>'allow_validate')::boolean,(item->>'allow_export')::boolean,now(),auth.uid())
 on conflict(role,module) do update set allow_create=excluded.allow_create,allow_edit=excluded.allow_edit,allow_delete=excluded.allow_delete,allow_validate=excluded.allow_validate,allow_export=excluded.allow_export,updated_at=now(),updated_by=auth.uid();
 end loop;return jsonb_build_object('saved',true);
end $$;
revoke all on function private.gama_save_action_permissions(text,jsonb,jsonb) from public,anon;grant execute on function private.gama_save_action_permissions(text,jsonb,jsonb) to authenticated;
create function public.gama_save_action_permissions(p_role text,p_rows jsonb,p_expected jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_save_action_permissions(p_role,p_rows,p_expected)$$;
revoke all on function public.gama_save_action_permissions(text,jsonb,jsonb) from public,anon;grant execute on function public.gama_save_action_permissions(text,jsonb,jsonb) to authenticated;
-- RPC only: a table upsert cannot bypass the version check.
revoke insert,update on public.erp_action_permissions from authenticated;

do $$declare src text;begin
 select pg_get_functiondef('private.gama_access_review(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'''modules'',(select', '''actions'',(select coalesce(jsonb_agg(to_jsonb(a) order by a.role,a.module),''[]'') from public.erp_action_permissions a),''modules'',(select');
 
 src:=replace(src,'elsif p_action=''confirm'' then','elsif p_action=''confirm'' then if p_data->''expected'' is distinct from result then raise exception ''ACCESS_SETTINGS_CHANGED'';end if;');
 execute src;
end $$;
create function private.gama_customer_credit_save(p_id uuid,p_limit numeric,p_hold text,p_expected jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare c public.customers;begin
 if not private.erp_module_allowed('clients',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=p_id for update;if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 if jsonb_build_object('credit_limit',c.credit_limit,'credit_hold_reason',c.credit_hold_reason) is distinct from p_expected then raise exception 'CUSTOMER_CHANGED';end if;
 update public.customers set credit_limit=p_limit,credit_hold_reason=nullif(btrim(p_hold),'') where id=p_id returning * into c;return to_jsonb(c);
end $$;
revoke all on function private.gama_customer_credit_save(uuid,numeric,text,jsonb) from public,anon;grant execute on function private.gama_customer_credit_save(uuid,numeric,text,jsonb) to authenticated;
create function public.gama_customer_credit_save(p_id uuid,p_limit numeric,p_hold text,p_expected jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_customer_credit_save(p_id,p_limit,p_hold,p_expected)$$;
revoke all on function public.gama_customer_credit_save(uuid,numeric,text,jsonb) from public,anon;grant execute on function public.gama_customer_credit_save(uuid,numeric,text,jsonb) to authenticated;

-- Cache only committed results; the key binds the actor and the whole command.
-- Read and cancellation calls still run their normal authorization on every call.
do $$declare r record;declaration text;core_call text;key_expr text;predicate text;extra text;begin
 for r in select * from (values
 ('gama_count_create','jsonb','p_data jsonb','count-create','warehouses','array[''administrador'',''almacenero'']','true','nullif(p_data->>''request_key'','''')::uuid'),
 ('gama_project_finance','text,jsonb','p_action text,p_data jsonb','project-finance','projects','array[''administrador'',''comercial'',''almacenero'']','p_action in (''cost'',''baseline'')','nullif(p_data->>''id'','''')::uuid'),
 ('gama_bank_match','text,jsonb','p_action text,p_data jsonb','bank-match','accounting','array[''administrador'',''comercial'']','p_action=''apply''','nullif(p_data->>''request_key'','''')::uuid'),
 ('gama_receipt_action','text,jsonb','p_action text,p_data jsonb','receipt-followup','payments','array[''administrador'',''comercial'']','p_action=''followup'' and nullif(p_data->>''id'','''') is null','nullif(p_data->>''request_key'','''')::uuid')
 )x(fn,signature,args,domain,module,roles,predicate,key_expression) loop
 execute format('alter function private.%I(%s) rename to %I',r.fn,r.signature,r.fn||'_core');
 execute format('revoke all on function private.%I(%s) from public,anon,authenticated',r.fn||'_core',r.signature);
 core_call:=format('private.%I(%s)',r.fn||'_core',case when r.signature='jsonb' then 'p_data' else 'p_action,p_data' end);
 extra:=case when r.fn='gama_project_finance' then 'if not private.pm_manage((p_data->>''project_id'')::uuid) then raise exception ''ROLE_NOT_ALLOWED'';end if;' when r.fn='gama_bank_match' then 'if private.gama_accounting_rights()->>''scope''<>''all'' or not coalesce((private.gama_accounting_rights()->>''validate'')::boolean,false) then raise exception ''ROLE_NOT_ALLOWED'';end if;' else '' end;
 execute format($fn$create function private.%I(%s) returns jsonb language plpgsql security definer set search_path='' as $body$
 declare k uuid;prior private.command_receipts;result jsonb;payload jsonb;begin
 if not private.erp_module_allowed(%L,%s) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not(%s) then return %s;end if;
 %s
 k:=%s;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 payload:=p_data%s;
 perform pg_advisory_xact_lock(hashtextextended(%L||k::text,0));
 select * into prior from private.command_receipts where domain=%L and request_key=k;
 if found then if prior.actor_id<>auth.uid() or prior.payload is distinct from payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 result:=%s;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values(%L,k,auth.uid(),payload,result);return result;
 end $body$ $fn$,r.fn,r.args,r.module,r.roles,r.predicate,core_call,extra,r.key_expression,case when r.signature='jsonb' then '' else '||jsonb_build_object(''_action'',p_action)' end,r.domain,r.domain,core_call,r.domain);
 execute format('revoke all on function private.%I(%s) from public,anon;grant execute on function private.%I(%s) to authenticated',r.fn,r.signature,r.fn,r.signature);
 -- Recompile SQL wrappers after the rename so their cached function OID is current.
 execute format('create or replace function public.%I(%s) returns jsonb language sql security invoker set search_path='''' as %L',r.fn,replace(r.args,'p_data jsonb','p_data jsonb default ''{}'''),format('select private.%I(%s)',r.fn,case when r.signature='jsonb' then 'p_data' else 'p_action,p_data' end));
 end loop;
end $$;

-- New direct customer payments must identify the actual active financial account.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_commercial_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by)', 'request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by,financial_account_id)');
 src:=replace(src,'coalesce(p_data->>''notes'',''''),v_uid)', 'coalesce(p_data->>''notes'',''''),v_uid,nullif(p_data->>''financial_account_id'','''')::uuid)');
 src:=replace(src,'if p_action = ''payment'' then', 'if p_action = ''payment'' then
 if not exists(select 1 from public.financial_accounts f join public.company_settings c on c.id where f.id=nullif(p_data->>''financial_account_id'','''')::uuid and f.active and f.account_id is not null and f.currency=c.currency) then raise exception ''FINANCIAL_ACCOUNT_REQUIRED'';end if;');
 src:=replace(src,'if v_payment.invoice_id <> v_invoice.id or v_payment.amount <> (p_data->>''amount'')::numeric then', 'if v_payment.invoice_id <> v_invoice.id or v_payment.amount <> (p_data->>''amount'')::numeric or v_payment.financial_account_id is distinct from nullif(p_data->>''financial_account_id'','''')::uuid or v_payment.created_by<>auth.uid() or v_payment.method is distinct from p_data->>''method'' or v_payment.paid_at is distinct from coalesce(nullif(p_data->>''paid_at'','''')::date,current_date) or v_payment.reference is distinct from coalesce(p_data->>''reference'','''') then');
 execute src;
end $$;

-- Legacy single-line matching enforces the same amount, source and account invariants.
create or replace function private.erp_reconcile_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare bank public.bank_transactions;source record;begin
 select * into bank from public.bank_transactions where id=new.bank_transaction_id for update;
 if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 if new.match_type='customer_payment' then select amount,financial_account_id,status into source from public.external_invoice_payments where id=new.match_id and receipt_id is null for update;
 elsif new.match_type='supplier_payment' then select -amount amount,financial_account_id,status into source from public.supplier_invoice_payments where id=new.match_id for update;
 elsif new.match_type='expense' then select -amount_total amount,financial_account_id,case when status='posted' then 'confirmed' else status end status into source from public.expenses where id=new.match_id for update;
 else raise exception 'INVALID_MATCH_TYPE';end if;
 if not found or source.status<>'confirmed' or source.financial_account_id is distinct from bank.financial_account_id or source.amount is distinct from bank.amount or new.amount is distinct from bank.amount then raise exception 'MATCH_AMOUNT_OR_ACCOUNT_MISMATCH';end if;
 if exists(select 1 from public.reconciliations r where r.match_type=new.match_type and r.match_id=new.match_id and r.bank_transaction_id<>new.bank_transaction_id) then raise exception 'SOURCE_ALREADY_MATCHED';end if;
 if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.bank_transaction_id and g.cancelled_at is null) or exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind=new.match_type and s.source_id=new.match_id and g.cancelled_at is null) then raise exception 'ALREADY_GROUPED';end if;
 return new;end $$;
revoke all on function private.erp_reconcile_guard() from public,anon,authenticated;

-- Reversed entries remain part of the ledger alongside their reversal; excluding
-- the original would count the reversal twice in balance and profit reports.
do $$declare r record;src text;begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('gama_accounting_reports','gama_accounting_project_pl') loop
 src:=pg_get_functiondef(r.oid);src:=replace(src,'e.status=''posted'' and e.entry_date','e.status in (''posted'',''reversed'') and e.entry_date');src:=replace(src,'en.status=''posted''','en.status in (''posted'',''reversed'')');execute src;end loop;
end $$;
-- Cash reporting recognizes deposits on receipt, not again on invoice allocation.
do $$declare r record;src text;before text;after text;begin
 for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('gama_accounting_reports','gama_accounting_action','gama_company_dashboard') loop
 src:=pg_get_functiondef(r.oid);
 if r.proname='gama_accounting_reports' then
 before:=$old$select to_char(p.paid_at,'YYYY-MM') m,p.amount cin,0::numeric cout from public.external_invoice_payments p
      where p.status='confirmed' and p.paid_at between d1 and d2$old$;
 after:=$new$select to_char(p.paid_at,'YYYY-MM') m,p.amount cin,0::numeric cout from public.external_invoice_payments p
      where p.status='confirmed' and p.receipt_id is null and p.paid_at between d1 and d2
     union all select to_char(r.paid_at,'YYYY-MM'),r.amount,0 from public.customer_receipts r where r.status='confirmed' and r.paid_at between d1 and d2$new$;
 src:=replace(src,before,after);
 elsif r.proname='gama_company_dashboard' then
 before:=$old$select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today$old$;
 after:=$new$select sum(p.amount) from (select amount,financial_account_id,status,paid_at from public.external_invoice_payments where receipt_id is null union all select amount,financial_account_id,status,paid_at from public.customer_receipts)p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today$new$;
 src:=replace(src,before,after);
 elsif r.proname='gama_accounting_action' then
 before:=$old$from public.external_invoice_payments
      where status='confirmed' and paid_at between date_trunc('month',today)::date and today$old$;
 after:=$new$from (select amount,status,paid_at from public.external_invoice_payments where receipt_id is null union all select amount,status,paid_at from public.customer_receipts)cash_receipts
      where status='confirmed' and paid_at between date_trunc('month',today)::date and today$new$;
 src:=replace(src,before,after);
 end if;execute src;
 end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184636','p1_workflow_guardrails_and_access_controls','7e992c76077068b3cd6567b1e600da0bb020bb04007fb39d87e7d6abf4e9c9da','7e992c76077068b3cd6567b1e600da0bb020bb04007fb39d87e7d6abf4e9c9da','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184637_p1_barcode_lookup_and_service_sla.sql; SHA256 30da263f18e95beea9a204b02482b008042ab717642ec936966965895354fa37
create function private.gama_barcode_lookup(p_code text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare code text:=btrim(p_code);p public.products;u public.product_units;pk public.fulfillment_packages;begin
 if not(private.erp_module_allowed('barcode',array['administrador','comercial','almacenero']) or private.erp_module_allowed('order-preparation',array['administrador','almacenero']) or private.erp_module_allowed('movement',array['administrador','almacenero'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if code is null or length(code) not between 1 and 180 then raise exception 'BARCODE_REQUIRED';end if;
 select * into p from public.products where (barcode=code or reference=code) and active;
 if found then return jsonb_build_object('kind','item','product_id',p.id,'code',coalesce(nullif(p.barcode,''),p.reference),'name',p.name,'factor',1,'base_unit',p.base_unit);end if;
 select * into u from public.product_units where barcode=code and active;
 if found then select * into p from public.products where id=u.product_id and active;if found then return jsonb_build_object('kind','pack','product_id',p.id,'unit_id',u.id,'code',u.barcode,'name',p.name,'label',u.label,'factor',u.factor,'base_unit',p.base_unit);end if;end if;
 select * into pk from public.fulfillment_packages where barcode=code and status='active';
 if found then return jsonb_build_object('kind','parcel','id',pk.id,'code',pk.barcode,'name',(select o.number from public.fulfillment_preparations f join public.sales_orders o on o.id=f.order_id where f.id=pk.preparation_id),'order_id',(select order_id from public.fulfillment_preparations where id=pk.preparation_id),'factor',null,'base_unit',null);end if;
 raise exception 'BARCODE_NOT_FOUND';
end $$;
revoke all on function private.gama_barcode_lookup(text) from public,anon;grant execute on function private.gama_barcode_lookup(text) to authenticated;
create function public.gama_barcode_lookup(p_code text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_barcode_lookup(p_code)$$;
revoke all on function public.gama_barcode_lookup(text) from public,anon;grant execute on function public.gama_barcode_lookup(text) to authenticated;
create function private.erp_barcode_namespace() returns trigger language plpgsql security definer set search_path='' as $$declare code text:=nullif(btrim(new.barcode),'');begin
 if code is null or (tg_op='UPDATE' and new.barcode is not distinct from old.barcode) then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('barcode:'||code,0));
 if exists(select 1 from public.products where (barcode=code or reference=code) and not(tg_table_name='products' and id=new.id)) or exists(select 1 from public.product_units where barcode=code and not(tg_table_name='product_units' and id=new.id)) or exists(select 1 from public.fulfillment_packages where barcode=code and not(tg_table_name='fulfillment_packages' and id=new.id)) then raise exception 'BARCODE_ALREADY_USED';end if;
 return new;end $$;
revoke all on function private.erp_barcode_namespace() from public,anon,authenticated;
create trigger erp_barcode_namespace before insert or update on public.products for each row execute function private.erp_barcode_namespace();
create trigger erp_barcode_namespace before insert or update on public.product_units for each row execute function private.erp_barcode_namespace();
create trigger erp_barcode_namespace before insert or update on public.fulfillment_packages for each row execute function private.erp_barcode_namespace();
-- A scanned pack is verified against its product. Quantities sent by the picker
-- remain base quantities, so opening a line never silently counts a carton as one.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 old:=$old$btrim(p_data->>'product_code')<>btrim(coalesce(pr.barcode,'')) then raise exception 'PRODUCT_SCAN_MISMATCH'$old$;
 if position(old in src)=0 then raise exception 'PICK_SCAN_ANCHOR';end if;
 src:=replace(src,old,$new$btrim(p_data->>'product_code')<>btrim(coalesce(pr.barcode,'')) and not exists(select 1 from public.product_units pu where pu.product_id=pr.id and pu.active and pu.barcode=btrim(p_data->>'product_code')) then raise exception 'PRODUCT_SCAN_MISMATCH'$new$);execute src;
end $$;
-- Preview and save SLA rules together. Existing ticket deadlines remain fixed.
create function private.gama_sla_rules(p_rows jsonb default null,p_expected jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$declare rows jsonb;x jsonb;begin
 if not private.erp_module_allowed('settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.service_sla_rules order by priority for update;
 select jsonb_agg(to_jsonb(r) order by priority) into rows from public.service_sla_rules r;
 if p_rows is not null then
 if rows is distinct from p_expected then raise exception 'SLA_CHANGED';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<>3 or (select count(distinct value->>'priority') from jsonb_array_elements(p_rows))<>3 then raise exception 'INVALID_SLA';end if;
 for x in select value from jsonb_array_elements(p_rows) loop
 if x->>'priority' not in ('normal','high','urgent') or (x->>'resolution_hours')::int<(x->>'response_hours')::int then raise exception 'INVALID_SLA';end if;
 update public.service_sla_rules set response_hours=(x->>'response_hours')::int,resolution_hours=(x->>'resolution_hours')::int where priority=x->>'priority';end loop;
 select jsonb_agg(to_jsonb(r) order by priority) into rows from public.service_sla_rules r;
 end if;return rows;end $$;
revoke all on function private.gama_sla_rules(jsonb,jsonb) from public,anon;grant execute on function private.gama_sla_rules(jsonb,jsonb) to authenticated;
create function public.gama_sla_rules(p_rows jsonb default null,p_expected jsonb default null) returns jsonb language sql security invoker set search_path='' as $$select private.gama_sla_rules(p_rows,p_expected)$$;
revoke all on function public.gama_sla_rules(jsonb,jsonb) from public,anon;grant execute on function public.gama_sla_rules(jsonb,jsonb) to authenticated;
revoke update on public.service_sla_rules from authenticated;

-- Allocation pickers page through this customer's invoices, not all customers.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_payment_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,$old$where (nullif(p_data->>'order_id','') is null$old$,$new$where (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid) and (nullif(p_data->>'order_id','') is null$new$);execute src;
 select pg_get_functiondef('private.gama_receipt_action_core(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'order by receipt.paid_at desc limit 200','order by receipt.paid_at desc,receipt.id limit 200 offset greatest(0,coalesce((p_data->>''offset'')::int,0))');execute src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184637','p1_barcode_lookup_and_service_sla','30da263f18e95beea9a204b02482b008042ab717642ec936966965895354fa37','30da263f18e95beea9a204b02482b008042ab717642ec936966965895354fa37','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184638_p1_service_products_and_completion.sql; SHA256 3d04e343be86812752bb408aaae4bb0cb003312858f07597f8095f4cd8ada083
-- Services use an execution ledger, never physical stock or fictitious deliveries.
alter table public.products add column product_kind text not null default 'goods' check(product_kind in ('goods','service'));
alter table public.sales_order_lines add column product_kind text not null default 'goods' check(product_kind in ('goods','service'));
create function private.erp_product_kind_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.product_kind<>old.product_kind and (
 exists(select 1 from public.invoice_lines where product_id=new.id) or exists(select 1 from public.sales_order_lines where product_id=new.id) or exists(select 1 from public.purchase_order_lines where product_id=new.id) or exists(select 1 from public.stock_movements where product_id=new.id) or exists(select 1 from public.stock_quants where product_id=new.id and (quantity<>0 or reserved_quantity<>0))) then raise exception 'PRODUCT_KIND_ALREADY_USED';end if;
 if new.product_kind='service' and coalesce(new.stock,0)<>0 then raise exception 'SERVICE_HAS_NO_STOCK';end if;return new;end $$;
revoke all on function private.erp_product_kind_guard() from public,anon,authenticated;
create trigger erp_product_kind_guard before insert or update on public.products for each row execute function private.erp_product_kind_guard();
create function private.erp_sales_line_kind() returns trigger language plpgsql security definer set search_path='' as $$begin
 select product_kind into new.product_kind from public.products where id=new.product_id;return new;end $$;
revoke all on function private.erp_sales_line_kind() from public,anon,authenticated;
create trigger erp_sales_line_kind before insert or update on public.sales_order_lines for each row execute function private.erp_sales_line_kind();
create function private.erp_physical_product_only() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.products where id=new.product_id and product_kind='service') and (tg_table_name<>'stock_quants' or (to_jsonb(new)->>'quantity')::numeric<>0 or (to_jsonb(new)->>'reserved_quantity')::numeric<>0) then raise exception 'SERVICE_HAS_NO_STOCK';end if;return new;end $$;
revoke all on function private.erp_physical_product_only() from public,anon,authenticated;
create trigger erp_physical_only before insert or update on public.stock_movements for each row execute function private.erp_physical_product_only();
create trigger erp_physical_only before insert or update on public.stock_quants for each row execute function private.erp_physical_product_only();
create trigger erp_physical_only before insert or update on public.stock_reservations for each row execute function private.erp_physical_product_only();
create table public.sales_service_completions(id uuid primary key default gen_random_uuid(),order_line_id uuid not null references public.sales_order_lines(id),quantity numeric(14,3) not null check(quantity>0),performed_on date not null,evidence text not null check(length(btrim(evidence)) between 3 and 2000),created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id),cancelled_at timestamptz,cancelled_by uuid references public.profiles(id),cancellation_reason text);
alter table public.sales_service_completions enable row level security;
revoke all on public.sales_service_completions from public,anon,authenticated;grant select on public.sales_service_completions to authenticated;
create policy service_completion_read on public.sales_service_completions for select to authenticated using(private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']));
create index service_completion_line on public.sales_service_completions(order_line_id,performed_on);
create index service_completion_actor on public.sales_service_completions(created_by);
create index service_completion_cancel_actor on public.sales_service_completions(cancelled_by);
create trigger erp_audit_capture after insert or update or delete on public.sales_service_completions for each row execute function private.erp_audit_capture();
create function private.gama_line_performed(p_line uuid,p_signed boolean default false) returns numeric language sql stable security definer set search_path='' as $$
 select case when l.product_kind='service' then coalesce((select sum(c.quantity) from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null),0)
 else coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl join public.sales_deliveries sd on sd.id=dl.delivery_id left join public.tms_deliveries td on td.id=sd.tms_delivery_id where dl.order_line_id=l.id and (not p_signed or (td.status='Entregada' and exists(select 1 from public.tms_proofs p where p.delivery_id=td.id and nullif(btrim(p.signature),'') is not null)))),0) end from public.sales_order_lines l where l.id=p_line
$$;
revoke all on function private.gama_line_performed(uuid,boolean) from public,anon,authenticated;
create or replace function private.gama_order_delivery_validated(p_order uuid) returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.sales_order_lines where order_id=p_order) and not exists(select 1 from public.sales_order_lines l where l.order_id=p_order and l.quantity>private.gama_line_performed(l.id,true));
$$;
-- Service-specific completion date: invoice lines consume executions in invoice order.
create function private.gama_service_invoice_date(p_invoice public.external_invoices) returns date language plpgsql stable security definer set search_path='' as $$
declare l record;needed numeric;d date;last_date date;begin
 for l in select ol.id,ol.quantity from public.sales_order_lines ol where ol.order_id=p_invoice.order_id and ol.product_kind='service' and (p_invoice.document_kind='internal' or exists(select 1 from public.external_invoice_lines il where il.invoice_id=p_invoice.id and il.order_line_id=ol.id)) loop
 if p_invoice.document_kind='internal' then needed:=l.quantity;else
 select coalesce(sum(il.quantity),0) into needed from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected') and (i.created_at,i.id)<=(p_invoice.created_at,p_invoice.id);
 end if;
 select performed_on into d from (select c.performed_on,c.id,sum(c.quantity) over(order by c.performed_on,c.created_at,c.id) done from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null)c where c.done>=needed order by performed_on,id limit 1;
 if d is null then return null;end if;last_date:=greatest(last_date,d);
 end loop;return last_date;
end $$;
revoke all on function private.gama_service_invoice_date(public.external_invoices) from public,anon,authenticated;
-- Preserve the existing physical-delivery calculation; include service execution.
do $$declare src text;anchor text;begin
 select pg_get_functiondef('private.gama_set_invoice_payment_due()'::regprocedure) into src;
 anchor:='new.due_date:=new.payment_delivery_date+new.payment_terms_days;';
 if strpos(src,anchor)=0 then raise exception 'PAYMENT_DUE_ANCHOR';end if;
 src:=replace(src,anchor,$patch$
 if exists(select 1 from public.sales_order_lines ol where ol.order_id=new.order_id and ol.product_kind='service' and (new.document_kind='internal' or exists(select 1 from public.external_invoice_lines il where il.invoice_id=new.id and il.order_line_id=ol.id))) then
  if private.gama_service_invoice_date(new) is null then new.payment_delivery_date:=null;
  elsif not exists(select 1 from public.sales_order_lines ol where ol.order_id=new.order_id and ol.product_kind='goods' and (new.document_kind='internal' or exists(select 1 from public.external_invoice_lines il where il.invoice_id=new.id and il.order_line_id=ol.id))) then new.payment_delivery_date:=private.gama_service_invoice_date(new);
  elsif new.payment_delivery_date is not null then new.payment_delivery_date:=greatest(new.payment_delivery_date,private.gama_service_invoice_date(new));end if;
 end if;
 new.due_date:=new.payment_delivery_date+new.payment_terms_days;
$patch$);execute src;
end $$;
create function private.gama_service_execution(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare oid uuid:=(p_data->>'order_id')::uuid;o public.sales_orders;l public.sales_order_lines;c public.sales_service_completions;k uuid;prior private.command_receipts;result jsonb;qty numeric;invoice jsonb;qid uuid;begin
 if not private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 -- Keep the quote/order lock ordering shared by invoice creation.
 select source_quote_id into qid from public.sales_orders where id=oid;perform 1 from public.invoices where id=qid for update;
 select * into o from public.sales_orders where id=oid for update;if not found then raise exception 'ORDER_NOT_FOUND';end if;
 if p_action in ('complete','cancel') then
 if not private.erp_module_allowed('sales-orders',array['administrador','comercial']) or not private.erp_action_allowed('sales-orders','validate') or not private.erp_action_allowed('sales-orders','edit') then raise exception 'ACTION_NOT_ALLOWED';end if;
 k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('service-execution:'||k::text,0));
 select * into prior from private.command_receipts where domain='service-execution' and request_key=k;
 if found then if prior.actor_id<>auth.uid() or prior.payload is distinct from (p_data||jsonb_build_object('_action',p_action)) then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 if o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
 if p_action='complete' then
 select * into l from public.sales_order_lines where id=(p_data->>'line_id')::uuid and order_id=oid and product_kind='service' for update;if not found then raise exception 'SERVICE_LINE_REQUIRED';end if;
 qty:=(p_data->>'quantity')::numeric;if qty is null or qty<=0 or qty<>round(qty,3) or qty+private.gama_line_performed(l.id)>l.quantity then raise exception 'SERVICE_QUANTITY_EXCEEDED';end if;
 if (p_data->>'performed_on')::date>current_date then raise exception 'SERVICE_DATE_FUTURE';end if;
 insert into public.sales_service_completions(order_line_id,quantity,performed_on,evidence,created_by) values(l.id,qty,(p_data->>'performed_on')::date,p_data->>'evidence',auth.uid()) returning * into c;
 else
 select x.* into c from public.sales_service_completions x join public.sales_order_lines ol on ol.id=x.order_line_id where x.id=(p_data->>'id')::uuid and ol.order_id=oid for update of x;if not found then raise exception 'EXECUTION_NOT_FOUND';end if;
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 if exists(select 1 from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=c.order_line_id and i.fiscal_status not in ('cancelled','rejected')) then raise exception 'CANCEL_INVOICE_FIRST';end if;
 update public.sales_service_completions set cancelled_at=coalesce(cancelled_at,now()),cancelled_by=coalesce(cancelled_by,auth.uid()),cancellation_reason=coalesce(cancellation_reason,p_data->>'reason') where id=c.id returning * into c;
 end if;
 update public.external_invoices set updated_at=now() where order_id=oid;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(oid,'service_'||p_action,c.id,auth.uid(),jsonb_build_object('line_id',c.order_line_id,'quantity',c.quantity,'performed_on',c.performed_on,'evidence',c.evidence,'reason',p_data->>'reason'));
 if p_action='complete' and qid is not null and private.gama_order_delivery_validated(oid) and not exists(select 1 from public.external_invoices where order_id=oid) then
 begin invoice:=private.gama_delivery_invoice_create('create',jsonb_build_object('quote_id',qid));
 exception when others then insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(oid,'invoice_auto_failed',c.id,auth.uid(),jsonb_build_object('source','service_execution','error_code',sqlstate,'error',sqlerrm));end;
 end if;
 result:=to_jsonb(c)||jsonb_build_object('invoice',invoice);insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('service-execution',k,auth.uid(),p_data||jsonb_build_object('_action',p_action),result);return result;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('order',to_jsonb(o),'lines',(select coalesce(jsonb_agg(to_jsonb(ol)||jsonb_build_object('performed',private.gama_line_performed(ol.id)) order by ol.product_name,ol.id),'[]') from public.sales_order_lines ol where ol.order_id=oid and ol.product_kind='service'),'history',(select coalesce(jsonb_agg(to_jsonb(x) order by x.performed_on desc,x.created_at desc),'[]') from public.sales_service_completions x join public.sales_order_lines ol on ol.id=x.order_line_id where ol.order_id=oid));
end $$;
revoke all on function private.gama_service_execution(text,jsonb) from public,anon;grant execute on function private.gama_service_execution(text,jsonb) to authenticated;
create function public.gama_service_execution(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_service_execution(p_action,p_data)$$;
revoke all on function public.gama_service_execution(text,jsonb) from public,anon;grant execute on function public.gama_service_execution(text,jsonb) to authenticated;

create or replace function private.gama_queue_preparation() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and exists(select 1 from public.sales_order_lines l where l.order_id=new.id and l.product_kind='goods' and l.quantity>private.gama_line_performed(l.id)) then insert into public.fulfillment_preparations(order_id) values(new.id) on conflict do nothing;end if;return new;end $$;
-- Adapt the established transaction functions without changing their API.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_allocate_sales_product(uuid)'::regprocedure) into src;
 src:=replace(src,'perform 1 from public.products where id=p_product_id for update;', 'perform 1 from public.products where id=p_product_id for update;if exists(select 1 from public.products where id=p_product_id and product_kind=''service'') then return 0;end if;');execute src;
 select pg_get_functiondef('private.gama_sales_action_before_fulfillment(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'where order_id=oid order by product_id loop','where order_id=oid and product_kind=''goods'' order by product_id loop');
 src:=replace(src,'if exists(select 1 from public.sales_deliveries where order_id=oid)', 'if exists(select 1 from public.sales_service_completions c join public.sales_order_lines ol on ol.id=c.order_line_id where ol.order_id=oid and c.cancelled_at is null) or exists(select 1 from public.sales_deliveries where order_id=oid)');execute src;
 select pg_get_functiondef('private.gama_sales_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'ol.delivery_policy=''wait''','ol.product_kind=''goods'' and ol.delivery_policy=''wait''');
 src:=replace(src,'l.order_id=o.id and l.quantity>','l.order_id=o.id and l.product_kind=''goods'' and l.quantity>');execute src;
 select pg_get_functiondef('private.gama_dossier_followup(text,jsonb)'::regprocedure) into src;
 src:=regexp_replace(src,'select coalesce\(sum\(greatest\(0,l.quantity-coalesce\(\(select sum\(dl.quantity\).*?into missing from public.sales_order_lines l where l.order_id=source;', 'select coalesce(sum(greatest(0,l.quantity-private.gama_line_performed(l.id,true))),0) into missing from public.sales_order_lines l where l.order_id=source;');execute src;
 src:=pg_get_viewdef('public.replenishment_needs'::regclass,true);src:=replace(src,'WHERE p.active','WHERE p.active AND p.product_kind=''goods''');execute 'create or replace view public.replenishment_needs with(security_invoker=true) as '||src;
 src:=pg_get_viewdef('private.gama_order_progress'::regclass,true);
 src:=replace(src,'COALESCE(s.qty, 0::numeric)','private.gama_line_performed(l.id)');
 src:=replace(src,'sum(GREATEST(0::numeric, l.quantity - private.gama_line_performed(l.id) - COALESCE(r.qty, 0::numeric)))','sum(CASE WHEN l.product_kind=''service'' THEN 0 ELSE GREATEST(0::numeric, l.quantity - private.gama_line_performed(l.id) - COALESCE(r.qty, 0::numeric)) END)');execute 'create or replace view private.gama_order_progress as '||src;
end $$;

-- Supplier service acceptance is quantity-based evidence, without a stock movement.
create table public.purchase_service_acceptances(id uuid primary key default gen_random_uuid(),purchase_line_id uuid not null references public.purchase_order_lines(id),quantity numeric(14,3) not null check(quantity>0),evidence text not null check(length(btrim(evidence))>=3),created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id));
alter table public.purchase_service_acceptances enable row level security;revoke all on public.purchase_service_acceptances from public,anon,authenticated;grant select on public.purchase_service_acceptances to authenticated;
create policy purchase_service_read on public.purchase_service_acceptances for select to authenticated using(private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial','almacenero']));
create index purchase_service_line on public.purchase_service_acceptances(purchase_line_id);create index purchase_service_actor on public.purchase_service_acceptances(created_by);
create trigger erp_audit_capture after insert on public.purchase_service_acceptances for each row execute function private.erp_audit_capture();
do $$declare src text;anchor text;begin
 select pg_get_functiondef('private.gama_receive_purchase_impl(uuid,jsonb,text)'::regprocedure) into src;
 anchor:='v_location := coalesce';if strpos(src,anchor)=0 then raise exception 'RECEIVE_SERVICE_ANCHOR';end if;
 src:=replace(src,anchor,$patch$
 if v_product.product_kind='service' then
 if length(btrim(coalesce(p_comment,'')))<3 then raise exception 'SERVICE_EVIDENCE_REQUIRED';end if;
 insert into public.purchase_service_acceptances(purchase_line_id,quantity,evidence,created_by) values(v_pol.id,v_qty,p_comment,auth.uid());
 update public.purchase_order_lines set received_quantity=received_quantity+v_qty where id=v_pol.id;
 update public.products set purchase_price=v_pol.unit_cost,updated_at=now() where id=v_product.id;
 continue;
 end if;
 v_location := coalesce$patch$);execute src;
end $$;
create function private.gama_receive_purchase_once(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k uuid:=nullif(p_data->>'request_key','')::uuid;prior private.command_receipts;result jsonb;begin
 if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','almacenero']) or not private.erp_action_allowed('gamaPurchasesV14','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended('purchase-receipt:'||k::text,0));
 select * into prior from private.command_receipts where domain='purchase-receipt' and request_key=k;
 if found then if prior.actor_id<>auth.uid() or prior.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 result:=private.gama_receive_purchase((p_data->>'purchase_order_id')::uuid,p_data->'lines',p_data->>'comment');
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('purchase-receipt',k,auth.uid(),p_data,result);return result;
end $$;
revoke all on function private.gama_receive_purchase_once(jsonb) from public,anon;grant execute on function private.gama_receive_purchase_once(jsonb) to authenticated;
create function public.gama_receive_purchase_once(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_receive_purchase_once(p_data)$$;
revoke all on function public.gama_receive_purchase_once(jsonb) from public,anon;grant execute on function public.gama_receive_purchase_once(jsonb) to authenticated;
-- Refresh after an external invoice receives service lines. No fake delivery link.
create function private.gama_service_line_due() returns trigger language plpgsql security definer set search_path='' as $$begin
 update public.external_invoices set updated_at=now() where order_id=(select order_id from public.external_invoices where id=coalesce(new.invoice_id,old.invoice_id)) and exists(select 1 from public.sales_order_lines l where l.order_id=external_invoices.order_id and l.product_kind='service');return null;end $$;
revoke all on function private.gama_service_line_due() from public,anon,authenticated;
create trigger service_line_invoice_due after insert or update or delete on public.external_invoice_lines for each row execute function private.gama_service_line_due();
create function private.gama_client_services() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.erp_module_allowed('client-deliveries',array['cliente']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('order_id',o.id,'number',o.number,'status',o.status,'product',l.product_name,'quantity',l.quantity,'performed',private.gama_line_performed(l.id),'promised_date',l.promised_date,'history',(select coalesce(jsonb_agg(jsonb_build_object('quantity',c.quantity,'performed_on',c.performed_on) order by c.performed_on),'[]') from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null)) order by o.created_at desc,o.id,l.id) from public.sales_orders o join public.sales_order_lines l on l.order_id=o.id and l.product_kind='service' where o.status<>'draft' and private.gama_owns_customer(o.customer_id)),'[]');
end $$;
revoke all on function private.gama_client_services() from public,anon;grant execute on function private.gama_client_services() to authenticated;
create function public.gama_client_services() returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_client_services()$$;
revoke all on function public.gama_client_services() from public,anon;grant execute on function public.gama_client_services() to authenticated;
-- Catalogue conveys service availability without a misleading zero-stock warning.
do $$declare src text;begin
 src:=pg_get_viewdef('public.catalog_products'::regclass,true);if strpos(src,'p.order_multiple')=0 then raise exception 'CATALOG_KIND_ANCHOR';end if;src:=replace(src,'p.order_multiple','p.order_multiple, p.product_kind');execute 'create or replace view public.catalog_products as '||src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184638','p1_service_products_and_completion','3d04e343be86812752bb408aaae4bb0cb003312858f07597f8095f4cd8ada083','3d04e343be86812752bb408aaae4bb0cb003312858f07597f8095f4cd8ada083','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184639_p1_optional_lot_traceability.sql; SHA256 79e7da95ab92e60a9810f144e035929e24046e3bf4c2d947b161e0a7ccf5be20
-- Optional traceability starts with zero stock. Received lots must be identified
-- before removal; every removal/transfer keeps a movement-to-lot ledger.
alter table public.products add column lot_tracking boolean not null default false,add column lot_tracking_since timestamptz;
create table public.product_lots(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),code text not null check(length(btrim(code)) between 1 and 100),expires_on date,created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id),unique(product_id,code));
create table public.stock_lot_balances(lot_id uuid not null references public.product_lots(id),location_id uuid not null references public.warehouse_locations(id),quantity numeric(14,3) not null check(quantity>=0),primary key(lot_id,location_id));
create table public.stock_lot_movements(id uuid primary key default gen_random_uuid(),movement_id uuid not null references public.stock_movements(id),lot_id uuid not null references public.product_lots(id),source_location_id uuid references public.warehouse_locations(id),destination_location_id uuid references public.warehouse_locations(id),quantity numeric(14,3) not null check(quantity>0),created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id));
do $$declare tbl text;begin foreach tbl in array array['product_lots','stock_lot_balances','stock_lot_movements'] loop
 execute format('alter table public.%I enable row level security',tbl);execute format('revoke all on public.%I from public,anon,authenticated;grant select on public.%I to authenticated',tbl,tbl);
 execute format('create policy lot_read on public.%I for select to authenticated using(private.erp_module_allowed(''warehouses'',array[''administrador'',''almacenero'']) or private.erp_module_allowed(''products'',array[''administrador'',''comercial'']))',tbl);
 end loop;end $$;
create index lot_balance_location on public.stock_lot_balances(location_id);
create index lot_movement_source on public.stock_lot_movements(source_location_id);create index lot_movement_destination on public.stock_lot_movements(destination_location_id);
create index lot_movement_stock on public.stock_lot_movements(movement_id);create index lot_movement_lot on public.stock_lot_movements(lot_id,created_at);
create index lot_movement_actor on public.stock_lot_movements(created_by);create index product_lot_actor on public.product_lots(created_by);
create trigger erp_audit_capture after insert on public.product_lots for each row execute function private.erp_audit_capture();
create trigger erp_audit_capture after insert on public.stock_lot_movements for each row execute function private.erp_audit_capture();
create function private.erp_lot_mode_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.lot_tracking and new.product_kind<>'goods' then raise exception 'LOT_GOODS_ONLY';end if;
 if tg_op='INSERT' then if new.lot_tracking and not private.erp_module_allowed('products',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;new.lot_tracking_since:=case when new.lot_tracking then now() end;
 elsif new.lot_tracking is distinct from old.lot_tracking then
 if not private.erp_module_allowed('products',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if exists(select 1 from public.stock_quants where product_id=new.id and (quantity<>0 or reserved_quantity<>0)) or coalesce(new.stock,0)<>0 then raise exception 'LOT_MODE_REQUIRES_ZERO_STOCK';end if;
 if exists(select 1 from public.product_lots where product_id=new.id) then raise exception 'LOT_MODE_ALREADY_USED';end if;
 new.lot_tracking_since:=case when new.lot_tracking then now() end;
 else new.lot_tracking_since:=old.lot_tracking_since;end if;return new;end $$;
revoke all on function private.erp_lot_mode_guard() from public,anon,authenticated;
create trigger erp_lot_mode_guard before insert or update on public.products for each row execute function private.erp_lot_mode_guard();
create function private.erp_lot_plan(p_product uuid,p_location uuid,p_quantity numeric,p_expiry boolean default true) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare x record;remaining numeric:=p_quantity;take numeric;result jsonb:='[]';begin
 if not exists(select 1 from public.products where id=p_product and lot_tracking) then return null;end if;
 if p_quantity is null or p_quantity<=0 or p_quantity<>round(p_quantity,3) then raise exception 'INVALID_QUANTITY';end if;
 for x in select l.id,l.code,l.expires_on,b.quantity from public.product_lots l join public.stock_lot_balances b on b.lot_id=l.id where l.product_id=p_product and b.location_id=p_location and b.quantity>0 and (not p_expiry or l.expires_on is null or l.expires_on>=current_date) order by l.expires_on nulls last,l.created_at,l.id loop
 exit when remaining<=0;take:=least(remaining,x.quantity);result:=result||jsonb_build_array(jsonb_build_object('lot_id',x.id,'code',x.code,'expires_on',x.expires_on,'quantity',take));remaining:=remaining-take;
 end loop;
 if remaining>0 then raise exception 'IDENTIFY_RECEIVED_LOTS_OR_CHECK_EXPIRY';end if;return result;
end $$;
revoke all on function private.erp_lot_plan(uuid,uuid,numeric,boolean) from public,anon,authenticated;
create function private.gama_lot_pick_plan(p_product uuid,p_location uuid,p_quantity numeric) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.erp_module_allowed('order-preparation',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;return private.erp_lot_plan(p_product,p_location,p_quantity,true);end $$;
revoke all on function private.gama_lot_pick_plan(uuid,uuid,numeric) from public,anon;grant execute on function private.gama_lot_pick_plan(uuid,uuid,numeric) to authenticated;
create function public.gama_lot_pick_plan(p_product uuid,p_location uuid,p_quantity numeric) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_lot_pick_plan(p_product,p_location,p_quantity)$$;
revoke all on function public.gama_lot_pick_plan(uuid,uuid,numeric) from public,anon;grant execute on function public.gama_lot_pick_plan(uuid,uuid,numeric) to authenticated;
create function private.erp_lot_movement() returns trigger language plpgsql security definer set search_path='' as $$
declare plan jsonb;x jsonb;strict_expiry boolean;begin
 if not exists(select 1 from public.products where id=new.product_id and lot_tracking) then return new;end if;
 if new.source_location_id is null then
 if new.destination_location_id is null then raise exception 'LOT_LOCATION_REQUIRED';end if;return new;-- Identify inbound lot codes in the receiving register.
 end if;
 perform 1 from public.products where id=new.product_id for update;
 strict_expiry:=(new.reference_type='sales_order' or new.movement_type in ('issue','shipment','manual_out')) and coalesce(current_setting('erp.lot_reset',true),'')<>'yes';
 plan:=private.erp_lot_plan(new.product_id,new.source_location_id,abs(new.quantity),coalesce(strict_expiry,false));
 for x in select value from jsonb_array_elements(plan) loop
 update public.stock_lot_balances set quantity=quantity-(x->>'quantity')::numeric where lot_id=(x->>'lot_id')::uuid and location_id=new.source_location_id;
 if new.destination_location_id is not null then insert into public.stock_lot_balances(lot_id,location_id,quantity) values((x->>'lot_id')::uuid,new.destination_location_id,(x->>'quantity')::numeric) on conflict(lot_id,location_id) do update set quantity=public.stock_lot_balances.quantity+excluded.quantity;end if;
 insert into public.stock_lot_movements(movement_id,lot_id,source_location_id,destination_location_id,quantity,created_by) values(new.id,(x->>'lot_id')::uuid,new.source_location_id,new.destination_location_id,(x->>'quantity')::numeric,auth.uid());
 end loop;return new;
end $$;
revoke all on function private.erp_lot_movement() from public,anon,authenticated;
create trigger erp_lot_movement after insert on public.stock_movements for each row execute function private.erp_lot_movement();
create function private.gama_lots(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare pid uuid:=(p_data->>'product_id')::uuid;m public.stock_movements;l public.product_lots;p public.products;k uuid;prior private.command_receipts;result jsonb;qty numeric;begin
 if not(private.erp_module_allowed('warehouses',array['administrador','almacenero']) or private.erp_module_allowed('products',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into p from public.products where id=pid;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_action='identify' then
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) or not private.erp_action_allowed('warehouses','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.products where id=pid for update;k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('identify-lot:'||k::text,0));select * into prior from private.command_receipts where domain='identify-lot' and request_key=k;
 if found then if prior.actor_id<>auth.uid() or prior.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 select * into m from public.stock_movements where id=(p_data->>'movement_id')::uuid and product_id=pid for update;
 if m.id is null or not p.lot_tracking or m.created_at<p.lot_tracking_since or m.source_location_id is not null or m.destination_location_id is null then raise exception 'INBOUND_LOT_MOVEMENT_REQUIRED';end if;
 qty:=(p_data->>'quantity')::numeric;
 if qty is null or qty<=0 or qty<>round(qty,3) or qty+coalesce((select sum(quantity) from public.stock_lot_movements where movement_id=m.id),0)>abs(m.quantity) then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
 select * into l from public.product_lots where product_id=pid and code=btrim(p_data->>'code');
 if found then if l.expires_on is distinct from nullif(p_data->>'expires_on','')::date then raise exception 'LOT_EXPIRY_MISMATCH';end if;
 else insert into public.product_lots(product_id,code,expires_on,created_by) values(pid,btrim(p_data->>'code'),nullif(p_data->>'expires_on','')::date,auth.uid()) returning * into l;end if;
 insert into public.stock_lot_balances(lot_id,location_id,quantity) values(l.id,m.destination_location_id,qty) on conflict(lot_id,location_id) do update set quantity=public.stock_lot_balances.quantity+excluded.quantity;
 insert into public.stock_lot_movements(movement_id,lot_id,destination_location_id,quantity,created_by) values(m.id,l.id,m.destination_location_id,qty,auth.uid());
 result:=to_jsonb(l);insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('identify-lot',k,auth.uid(),p_data,result);return result;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('product',to_jsonb(p)-'photo_data','pending',(select coalesce(jsonb_agg(to_jsonb(movement_row)||jsonb_build_object('remaining',abs(movement_row.quantity)-coalesce((select sum(lm.quantity) from public.stock_lot_movements lm where lm.movement_id=movement_row.id),0)) order by movement_row.created_at),'[]') from public.stock_movements movement_row where movement_row.product_id=pid and movement_row.source_location_id is null and movement_row.destination_location_id is not null and p.lot_tracking and movement_row.created_at>=p.lot_tracking_since and abs(movement_row.quantity)>coalesce((select sum(lm.quantity) from public.stock_lot_movements lm where lm.movement_id=movement_row.id),0)),
 'balances',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('code',lot_row.code,'expires_on',lot_row.expires_on,'location',(select code from public.warehouse_locations where id=b.location_id)) order by lot_row.expires_on nulls last,lot_row.code),'[]') from public.stock_lot_balances b join public.product_lots lot_row on lot_row.id=b.lot_id where lot_row.product_id=pid),
 'history',(select coalesce(jsonb_agg(to_jsonb(lm)||jsonb_build_object('code',lot_row.code,'reference_type',movement_row.reference_type,'reference_id',movement_row.reference_id,'reason',movement_row.reason,'comment',movement_row.comment) order by lm.created_at desc,lm.id),'[]') from public.stock_lot_movements lm join public.product_lots lot_row on lot_row.id=lm.lot_id join public.stock_movements movement_row on movement_row.id=lm.movement_id where lot_row.product_id=pid));
end $$;
revoke all on function private.gama_lots(text,jsonb) from public,anon;grant execute on function private.gama_lots(text,jsonb) to authenticated;
create function public.gama_lots(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_lots(p_action,p_data)$$;
revoke all on function public.gama_lots(text,jsonb) from public,anon;grant execute on function public.gama_lots(text,jsonb) to authenticated;
-- Pickers explicitly check lot codes. Recompute under the stock transaction lock
-- so a concurrent pick cannot silently change the displayed FEFO allocation.
do $$declare src text;anchor text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 anchor:='select * into loc from public.warehouse_locations where id=pl.source_location_id and active;';
 if strpos(src,anchor)=0 then raise exception 'LOT_PICK_ANCHOR';end if;
 src:=replace(src,anchor,$patch$if exists(select 1 from public.products where id=l.product_id and lot_tracking) then
 if p_data->'lot_plan' is distinct from private.erp_lot_plan(l.product_id,pl.source_location_id,qty,true) then raise exception 'LOT_PLAN_CHANGED';end if;end if;
 $patch$||anchor);execute src;
end $$;
-- Returning a cancelled preparation to storage is allowed even after expiry.
-- The expiry gate still applies to its next pick and shipment.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_reset_preparation(uuid,text)'::regprocedure) into src;
 src:=replace(src,'perform private.gama_fulfillment_move(l.order_line_id,l.stage_location_id,l.source_location_id,l.picked);',$patch$perform set_config('erp.lot_reset','yes',true);perform private.gama_fulfillment_move(l.order_line_id,l.stage_location_id,l.source_location_id,l.picked);perform set_config('erp.lot_reset','',true);$patch$);execute src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184639','p1_optional_lot_traceability','79e7da95ab92e60a9810f144e035929e24046e3bf4c2d947b161e0a7ccf5be20','79e7da95ab92e60a9810f144e035929e24046e3bf4c2d947b161e0a7ccf5be20','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184640_p1_final_authorization_guards.sql; SHA256 0b1990e319cfecedbc411ded3aecfe372d2ad1b0511f4da975b54784f59b219e
-- Invitation checks the same module and action policy as the administration UI.
create function private.gama_identity_admin_allowed() returns boolean language sql stable security definer set search_path='' as $$select private.erp_module_allowed('users',array['administrador']) and private.erp_action_allowed('users','create')$$;
revoke all on function private.gama_identity_admin_allowed() from public,anon;grant execute on function private.gama_identity_admin_allowed() to authenticated;
create function public.gama_identity_admin_allowed() returns boolean language sql stable security invoker set search_path='' as $$select private.gama_identity_admin_allowed()$$;
revoke all on function public.gama_identity_admin_allowed() from public,anon;grant execute on function public.gama_identity_admin_allowed() to authenticated;
-- New command ledgers and approval tables also obey action restrictions.
do $$declare r record;begin for r in select * from (values
 ('sales_service_completions','sales-orders'),('purchase_service_acceptances','gamaPurchasesV14'),('product_lots','warehouses'),('stock_lot_movements','warehouses'),
 ('bank_match_groups','accounting'),('pm_cost_entries','projects'),('pm_baselines','projects'),('erp_approvals','access-settings'),('service_sla_rules','settings'),('document_approvals','documents')
 )x(tbl,module) loop
 if to_regclass('public.'||r.tbl) is not null and not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||r.tbl) and tgname='erp_action_guard') then execute format('create trigger erp_action_guard before insert or update or delete on public.%I for each row execute function private.erp_action_guard(%L)',r.tbl,r.module);end if;end loop;end $$;
-- A bank reconciliation validates a transaction even though it has no status field.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_bank_match(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'begin', 'begin if p_action in (''apply'',''cancel'') and not private.erp_action_allowed(''accounting'',''validate'') then raise exception ''ACTION_NOT_ALLOWED'';end if;');execute src;
 select pg_get_functiondef('private.gama_commercial_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'if p_action = ''payment'' then','if p_action = ''payment'' then if not private.erp_module_allowed(''payments'',array[''administrador'',''comercial'']) then raise exception ''ROLE_NOT_ALLOWED'';end if;');execute src;
end $$;
-- Legacy entry points with direct role lookups must also require the MFA level.
do $$declare r record;src text;begin for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='private' and p.proname like 'gama_%' and p.prosecdef and l.lanname='plpgsql' and p.prorettype<>'trigger'::regtype and has_function_privilege('authenticated',p.oid,'execute') loop
 src:=pg_get_functiondef(r.oid);src:=regexp_replace(src,'\mbegin\M','begin if auth.uid() is null or not private.erp_mfa_ok() then raise exception ''AUTH_OR_MFA_REQUIRED'';end if;','i');execute src;end loop;end $$;
-- Expose legacy privileged stock commands through invoker-only API wrappers.
-- The original implementations retain their authorization and transaction locks.
do $$declare r record;args text;argnames text;result_type text;internal_name text;begin
 for r in select p.*,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and p.proname in ('gama_count_generate_lines','gama_count_validate','gama_register_stock_movement','gama_stock_adjust','gama_stock_reserve','gama_stock_transfer') loop
 args:=pg_get_function_arguments(r.oid);result_type:=pg_get_function_result(r.oid);internal_name:='api_'||r.proname;
 select string_agg(format('%I',name),',' order by pos) into argnames from unnest(r.proargnames[1:r.pronargs]) with ordinality a(name,pos);
 execute format('alter function %s rename to %I',r.oid::regprocedure,internal_name);
 execute format('alter function public.%I(%s) set schema private',internal_name,pg_get_function_identity_arguments(r.oid));
 execute format('revoke all on function %s from public,anon;grant execute on function %s to authenticated',r.oid::regprocedure,r.oid::regprocedure);
 execute format('create function public.%I(%s) returns %s language sql security invoker set search_path='''' as %L',r.proname,args,result_type,format('select private.%I(%s)',internal_name,argnames));
 execute format('revoke all on function public.%I(%s) from public,anon;grant execute on function public.%I(%s) to authenticated',r.proname,pg_get_function_identity_arguments(r.oid),r.proname,pg_get_function_identity_arguments(r.oid));
 end loop;end $$;
-- Index the foreign keys introduced in this delivery, preserving existing indexes.
do $$declare r record;cols text;begin
 for r in select c.conrelid,c.conname,c.conkey,n.nspname,t.relname from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where c.contype='f' and n.nspname in ('public','private') and t.relname in ('erp_audit_events','erp_approvals','price_books','price_book_lines','supplier_product_offers','supplier_invoice_matches','supplier_invoice_match_lines','import_batches','import_batch_rows','customer_receipts','bank_match_groups','bank_match_banks','bank_match_sources','erp_access_reviews','hr_staffing_rules','hr_employee_skills','hr_lifecycle_tasks','tms_route_schedules','service_sla_rules','document_approvals') and not exists(select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid and i.indpred is null and i.indkey::smallint[] @> c.conkey) loop
 select string_agg(format('%I',a.attname),',' order by k.ord) into cols from unnest(r.conkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=r.conrelid and a.attnum=k.num;
 execute format('create index %I on %I.%I(%s)',left('p1_fk_'||r.conname,63),r.nspname,r.relname,cols);end loop;end $$;
-- Private ledgers are intentionally inaccessible except through checked commands.
do $$declare r record;begin for r in select tablename from pg_tables where schemaname='private' loop execute format('alter table private.%I enable row level security',r.tablename);end loop;end $$;
-- Keep narrow directory/catalogue projections behind explicit caller filters,
-- while making the public views invoker-only (no RLS-bypassing view ownership).
do $$declare v text;src text;cols text;projection text;previous_path text:=current_setting('search_path');begin
 perform set_config('search_path','',true);
 foreach v in array array['crm_team','catalog_products'] loop
 src:=rtrim(pg_get_viewdef(('public.'||v)::regclass,true),E';\n ');
 select string_agg(format('%I %s',attname,format_type(atttypid,atttypmod)),',' order by attnum) into cols from pg_attribute where attrelid=('public.'||v)::regclass and attnum>0 and not attisdropped;
 select string_agg(format('%I::%s as %I',attname,format_type(atttypid,atttypmod),attname),',' order by attnum) into projection from pg_attribute where attrelid=('public.'||v)::regclass and attnum>0 and not attisdropped;
 execute format('create function private.%I() returns table(%s) language sql stable security definer set search_path='''' as %L','api_'||v,cols,src);
 execute format('revoke all on function private.%I() from public,anon;grant execute on function private.%I() to authenticated','api_'||v,'api_'||v);
 execute format('create or replace view public.%I with(security_invoker=true,security_barrier=true) as select %s from private.%I()',v,projection,'api_'||v);
 end loop;perform set_config('search_path',previous_path,true);end $$;
-- Warehouse aggregates and historical physical valuation exclude services.
do $$declare src text;begin
 select pg_get_functiondef('public.gama_inventory_snapshot(uuid,date)'::regprocedure) into src;src:=replace(src,'where p.active','where p.active and p.product_kind=''goods''');execute src;
 select pg_get_functiondef('private.gama_historical_stock(timestamptz)'::regprocedure) into src;src:=replace(src,'where p.created_at<=p_asof','where p.created_at<=p_asof and p.product_kind=''goods''');execute src;
 select pg_get_functiondef('private.gama_count_create_core(jsonb)'::regprocedure) into src;src:=replace(src,'where l.warehouse_id=c.warehouse_id','where p.product_kind=''goods'' and l.warehouse_id=c.warehouse_id');execute src;
end $$;
-- Product references share the barcode namespace, including generated references.
create function private.erp_reference_barcode_namespace() returns trigger language plpgsql security definer set search_path='' as $$declare code text:=nullif(btrim(new.reference),'');begin
 if code is null or (tg_op='UPDATE' and new.reference is not distinct from old.reference) then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('barcode:'||code,0));
 if exists(select 1 from public.products where id<>new.id and barcode=code) or exists(select 1 from public.product_units where barcode=code) or exists(select 1 from public.fulfillment_packages where barcode=code) then raise exception 'BARCODE_ALREADY_USED';end if;return new;end $$;
revoke all on function private.erp_reference_barcode_namespace() from public,anon,authenticated;
create trigger erp_reference_barcode_namespace after insert or update on public.products for each row execute function private.erp_reference_barcode_namespace();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184640','p1_final_authorization_guards','0b1990e319cfecedbc411ded3aecfe372d2ad1b0511f4da975b54784f59b219e','0b1990e319cfecedbc411ded3aecfe372d2ad1b0511f4da975b54784f59b219e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
