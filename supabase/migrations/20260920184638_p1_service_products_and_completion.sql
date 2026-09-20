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
