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
