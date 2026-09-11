-- GAMA sales: independent order, dispatch and external fiscal-document lifecycles.
-- No existing business rows are migrated or rewritten. Public RPC is invoker;
-- the checked implementation is private. Tables are read-only via the Data API.
create sequence public.gama_sales_order_seq;
create sequence public.gama_sales_delivery_seq;
create table public.sales_orders (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('PV-'||lpad(nextval('public.gama_sales_order_seq')::text,8,'0')),
 request_key uuid not null unique,
 customer_id uuid not null references public.customers(id),
 customer_name text not null, customer_identification text not null default '',
 delivery_address text not null default '',
 source_quote_id uuid unique references public.invoices(id),
 source_request_id uuid unique references public.customer_requests(id),
 status text not null default 'draft' check(status in ('draft','confirmed','cancelled')),
 notes text not null default '', created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.sales_order_lines (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.sales_orders(id),
 product_id uuid not null references public.products(id), product_name text not null, reference text not null default '',
 quantity numeric(16,3) not null check(quantity>0 and quantity<100000000),
 unit_price numeric(16,4) not null check(unit_price>=0 and unit_price<100000000),
 tax_rate numeric(7,4) not null check(tax_rate>=0 and tax_rate<=100),
 unique(order_id,product_id)
);
create table public.sales_reservation_links (
 reservation_id uuid primary key references public.stock_reservations(id),
 line_id uuid not null references public.sales_order_lines(id)
);
create table public.sales_deliveries (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('EX-'||lpad(nextval('public.gama_sales_delivery_seq')::text,8,'0')),
 order_id uuid not null references public.sales_orders(id), request_key uuid not null unique,
 tms_delivery_id uuid not null unique references public.tms_deliveries(id),
 dispatched_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
 notes text not null default ''
);
create table public.sales_delivery_lines (
 id uuid primary key default gen_random_uuid(), delivery_id uuid not null references public.sales_deliveries(id),
 order_line_id uuid not null references public.sales_order_lines(id),
 location_id uuid not null references public.warehouse_locations(id),
 quantity numeric(16,3) not null check(quantity>0 and quantity<100000000),
 unique(delivery_id,order_line_id,location_id)
);
create table public.external_invoices (
 id uuid primary key default gen_random_uuid(), request_key uuid not null unique,
 order_id uuid not null references public.sales_orders(id),
 number text not null check(length(btrim(number)) between 1 and 80),
 issuer_ruc text not null check(issuer_ruc ~ '^[0-9]{13}$'),
 access_key text unique check(access_key is null or access_key ~ '^[0-9]{49}$'),
 software text not null default '', issue_date date not null, due_date date,
 subtotal numeric(16,2) not null check(subtotal>=0 and subtotal<10000000000),
 tax numeric(16,2) not null check(tax>=0 and tax<10000000000),
 total numeric(16,2) generated always as (subtotal+tax) stored,
 fiscal_status text not null check(fiscal_status in ('unverified','authorized','rejected','cancelled')),
 notes text not null default '', cancellation_reason text,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(due_date is null or due_date>=issue_date), unique(issuer_ruc,number)
);
create table public.external_invoice_lines (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.external_invoices(id),
 order_line_id uuid not null references public.sales_order_lines(id),
 quantity numeric(16,3) not null check(quantity>0 and quantity<100000000),
 unique(invoice_id,order_line_id)
);
-- Small optional documentary attachments, fetched only when downloading.
-- They are stored separately so list/detail queries never transfer PDF/XML bytes.
create table public.external_invoice_files (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.external_invoices(id),
 filename text not null check(length(filename) between 1 and 180),
 mime_type text not null check(mime_type in ('application/pdf','application/xml')),
 content_base64 text not null check(length(content_base64)<=7000000),
 created_at timestamptz not null default now()
);
create table public.sales_events (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.sales_orders(id),
 action text not null, entity_id uuid, actor_id uuid not null references auth.users(id),
 detail jsonb not null default '{}', created_at timestamptz not null default now()
);
create index on public.sales_orders(customer_id);
create index on public.sales_orders(created_at desc);
create index on public.sales_reservation_links(line_id);
create index on public.sales_deliveries(order_id);
create index on public.sales_delivery_lines(order_line_id);
create index on public.external_invoices(order_id);
create index on public.external_invoice_lines(order_line_id);
create index on public.external_invoice_files(invoice_id);
create index on public.sales_events(order_id,created_at desc);

do $$ declare t text; begin
 foreach t in array array['sales_orders','sales_order_lines','sales_reservation_links','sales_deliveries','sales_delivery_lines','external_invoices','external_invoice_lines','external_invoice_files','sales_events'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy sales_read on public.%I for select to authenticated using (auth.uid() is not null and coalesce(private.current_user_role(),'''') = any (%L::text[]))',t,
    case when t like 'external_%' then '{administrador,comercial}' else '{administrador,comercial,almacenero}' end);
 end loop;
end $$;

create function private.gama_sales_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); role_name text:=coalesce(private.current_user_role(),'');
 o public.sales_orders; l public.sales_order_lines; c public.customers; p public.products;
 r public.stock_reservations; q public.stock_quants; inv public.external_invoices;
 v record; x jsonb; items jsonb; files jsonb;
 oid uuid; eid uuid; tid uuid; qid uuid; rid uuid; key_id uuid;
 qty numeric; remain numeric; shipped numeric; billed numeric; reserved numeric; before_stock numeric;
 subtotal numeric; taxes numeric; part numeric; source text; source_id uuid;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if role_name not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('create','confirm','reserve','cancel','ship','invoice','invoice_status','attach') then raise exception 'INVALID_ACTION'; end if;
 if p_action in ('create','confirm','cancel','invoice','invoice_status','attach') and role_name not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action='ship' and role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_DATA'; end if;

 if p_action='create' then
  key_id:=(p_data->>'request_key')::uuid;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(key_id::text,0));
  select * into o from public.sales_orders where request_key=key_id;
  if found then return to_jsonb(o); end if;
  source:=p_data->>'source'; source_id:=nullif(p_data->>'source_id','')::uuid;
  if source='quote' then
   qid:=source_id;
   select id into rid from public.customer_requests where invoice_id=qid order by id limit 1 for update;
  elsif source='request' then
   select * into v from public.customer_requests where id=source_id for update;
   if not found or v.status in ('cancelled','rejected') then raise exception 'INVALID_SOURCE'; end if;
   rid:=v.id; qid:=v.invoice_id;
  elsif coalesce(source,'manual')<>'manual' then raise exception 'INVALID_SOURCE'; end if;
  if source in ('quote','request') and source_id is null then raise exception 'INVALID_SOURCE'; end if;
  if qid is not null then
   select * into v from public.invoices where id=qid for update;
   if not found or v.status in ('cancelled','rejected') then raise exception 'INVALID_SOURCE'; end if;
   select * into c from public.customers where id=v.customer_id and active;
   select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity,'unit_price',unit_price,'tax_rate',tax_rate)) into items from public.invoice_lines where invoice_id=qid;
  elsif rid is not null then
   select * into c from public.customers where id=coalesce(v.customer_id,nullif(p_data->>'customer_id','')::uuid) and active;
   select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity,'unit_price',unit_price,'tax_rate',tax_rate)) into items from public.customer_request_lines where request_id=rid;
  else
   select * into c from public.customers where id=nullif(p_data->>'customer_id','')::uuid and active;
   items:=p_data->'lines';
  end if;
  if c.id is null then raise exception 'CUSTOMER_REQUIRED'; end if;
  select * into o from public.sales_orders where (qid is not null and source_quote_id=qid) or (rid is not null and source_request_id=rid) limit 1;
  if found then return to_jsonb(o); end if;
  if items is null or jsonb_typeof(items)<>'array' or jsonb_array_length(items) not between 1 and 200 then raise exception 'INVALID_LINES'; end if;
  -- Preserve different negotiated prices by a weighted average when a quote
  -- contains the same product twice. Different tax rates must be corrected first.
  if exists(select 1 from jsonb_array_elements(items) a group by a->>'product_id' having count(distinct a->>'tax_rate')>1) then raise exception 'MIXED_PRODUCT_TAX'; end if;
  for x in select value from jsonb_array_elements(items) loop
   if not(x ?& array['product_id','quantity','unit_price','tax_rate']) or (x->>'quantity')::numeric<=0 or (x->>'quantity')::numeric<>round((x->>'quantity')::numeric,3) or (x->>'unit_price')::numeric<0 or (x->>'tax_rate')::numeric not between 0 and 100 then raise exception 'INVALID_LINES'; end if;
  end loop;
  insert into public.sales_orders(request_key,customer_id,customer_name,customer_identification,delivery_address,source_quote_id,source_request_id,notes,created_by)
  values(key_id,c.id,c.name,coalesce(c.identification,''),coalesce(nullif(btrim(p_data->>'delivery_address'),''),c.address,''),qid,rid,coalesce(p_data->>'notes',''),u) returning * into o;
  for v in select (a->>'product_id')::uuid product_id,sum((a->>'quantity')::numeric) quantity,
    sum((a->>'quantity')::numeric*(a->>'unit_price')::numeric)/sum((a->>'quantity')::numeric) price,max((a->>'tax_rate')::numeric) tax_rate
    from jsonb_array_elements(items) a group by a->>'product_id' loop
   select * into p from public.products where id=v.product_id and active;
   if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
   insert into public.sales_order_lines(order_id,product_id,product_name,reference,quantity,unit_price,tax_rate)
   values(o.id,p.id,p.name,coalesce(p.reference,''),v.quantity,v.price,v.tax_rate);
  end loop;
  insert into public.sales_events(order_id,action,actor_id) values(o.id,'created',u);
  return to_jsonb(o);
 end if;

 oid:=(p_data->>'order_id')::uuid;
 select * into o from public.sales_orders where id=oid for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if p_action in ('confirm','reserve','ship','invoice') and o.status='cancelled' then raise exception 'ORDER_CANCELLED'; end if;
 if p_action in ('reserve','ship','invoice') and o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST'; end if;
 -- Serialise this order's reservation changes, using the same lock direction
 -- as gama_stock_unreserve (reservation -> product -> quant).
 if p_action in ('confirm','reserve','cancel','ship') then
  perform 1 from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id
   join public.sales_order_lines ol on ol.id=sl.line_id where ol.order_id=oid order by sr.id for update of sr;
  perform 1 from public.products pr where pr.id in(select product_id from public.sales_order_lines where order_id=oid) order by pr.id for update;
 end if;

 if p_action in ('confirm','reserve') then
  if o.status='cancelled' then raise exception 'ORDER_CANCELLED'; end if;
  update public.sales_orders set status='confirmed',updated_at=now() where id=oid returning * into o;
  for l in select * from public.sales_order_lines where order_id=oid order by product_id loop
   select coalesce(sum(dl.quantity),0) into shipped from public.sales_delivery_lines dl where dl.order_line_id=l.id;
   select coalesce(sum(sr.quantity),0) into reserved from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id where sl.line_id=l.id and sr.status='active';
   remain:=l.quantity-shipped-reserved;
   for q in select sq.* from public.stock_quants sq join public.warehouse_locations wl on wl.id=sq.location_id join public.warehouses w on w.id=wl.warehouse_id
    where sq.product_id=l.product_id and wl.active and w.active order by sq.location_id for update of sq loop
    exit when remain<=0;
    qty:=least(remain,q.quantity-q.reserved_quantity);
    if qty>0 then
     r:=public.gama_stock_reserve(l.product_id,q.location_id,qty,'sales_order',oid);
     insert into public.sales_reservation_links(reservation_id,line_id) values(r.id,l.id);
     remain:=remain-qty;
    end if;
   end loop;
  end loop;
 elsif p_action='cancel' then
  if exists(select 1 from public.sales_deliveries where order_id=oid) or exists(select 1 from public.external_invoices where order_id=oid and fiscal_status not in ('rejected','cancelled')) then raise exception 'ORDER_HAS_DOCUMENTS'; end if;
  for r in select sr.* from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id join public.sales_order_lines ol on ol.id=sl.line_id where ol.order_id=oid and sr.status='active' order by sr.id loop
   perform public.gama_stock_unreserve(r.id,false);
  end loop;
  update public.sales_orders set status='cancelled',updated_at=now() where id=oid returning * into o;
 elsif p_action='ship' then
  key_id:=(p_data->>'request_key')::uuid;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select id into eid from public.sales_deliveries where request_key=key_id and order_id=oid;
  if found then return jsonb_build_object('id',eid,'order_id',oid); end if;
  items:=p_data->'lines';
  if items is null or jsonb_typeof(items)<>'array' or jsonb_array_length(items) not between 1 and 200 then raise exception 'INVALID_LINES'; end if;
  if btrim(o.delivery_address)='' then raise exception 'ADDRESS_REQUIRED'; end if;
  insert into public.tms_deliveries(customer,customer_id,address,delivery_date,notes,created_by)
  values(o.customer_name,o.customer_id,o.delivery_address,coalesce((p_data->>'delivery_date')::date,current_date),o.number||' · '||coalesce(p_data->>'notes',''),u) returning id into tid;
  insert into public.sales_deliveries(order_id,request_key,tms_delivery_id,notes,created_by)
   values(oid,key_id,tid,coalesce(p_data->>'notes',''),u) returning id into eid;
  for x in select value from jsonb_array_elements(items) order by value->>'line_id',value->>'location_id' loop
   qty:=(x->>'quantity')::numeric;
   if qty is null or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY'; end if;
   select * into l from public.sales_order_lines where id=(x->>'line_id')::uuid and order_id=oid;
   if not found then raise exception 'INVALID_ORDER_LINE'; end if;
   select coalesce(sum(quantity),0) into shipped from public.sales_delivery_lines where order_line_id=l.id;
   if shipped+qty>l.quantity then raise exception 'EXCEEDS_ORDERED'; end if;
   select coalesce(sum(sr.quantity),0) into reserved from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id where sl.line_id=l.id and sr.location_id=(x->>'location_id')::uuid and sr.status='active';
   if qty>reserved then raise exception 'INSUFFICIENT_RESERVED'; end if;
   select * into q from public.stock_quants where product_id=l.product_id and location_id=(x->>'location_id')::uuid for update;
   if not found or q.quantity<qty or q.reserved_quantity<qty then raise exception 'INSUFFICIENT_STOCK'; end if;
   remain:=qty;
   for r in select sr.* from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id where sl.line_id=l.id and sr.location_id=q.location_id and sr.status='active' order by sr.id loop
    exit when remain<=0;
    part:=least(remain,r.quantity);
    if part=r.quantity then update public.stock_reservations set status='consumed',released_at=now() where id=r.id;
    else update public.stock_reservations set quantity=quantity-part where id=r.id; end if;
    remain:=remain-part;
   end loop;
   select coalesce(sum(quantity),0) into before_stock from public.stock_quants where product_id=l.product_id;
   update public.stock_quants set quantity=quantity-qty,reserved_quantity=reserved_quantity-qty,updated_at=now() where id=q.id;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,source_location_id,movement_type,reference_type,reference_id)
   values(l.product_id,'out',qty,'Expedición de pedido',o.number,u,before_stock,before_stock-qty,q.location_id,'delivery','sales_delivery',eid);
   perform private.gama_sync_product_stock(l.product_id);
   insert into public.sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values(eid,l.id,q.location_id,qty);
  end loop;
  update public.tms_deliveries set weight=coalesce((select sum(dl.quantity*coalesce(pr.weight_g,0)/1000) from public.sales_delivery_lines dl join public.sales_order_lines ol on ol.id=dl.order_line_id join public.products pr on pr.id=ol.product_id where dl.delivery_id=eid),0),
   volume=coalesce((select sum(dl.quantity*coalesce(pr.volume_cm3,0)/1000000) from public.sales_delivery_lines dl join public.sales_order_lines ol on ol.id=dl.order_line_id join public.products pr on pr.id=ol.product_id where dl.delivery_id=eid),0) where id=tid;
 elsif p_action='invoice' then
  key_id:=(p_data->>'request_key')::uuid;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select * into inv from public.external_invoices where request_key=key_id and order_id=oid;
  if found then return to_jsonb(inv); end if;
  if p_data->>'customer_identification' is distinct from o.customer_identification then raise exception 'CUSTOMER_MISMATCH'; end if;
  items:=p_data->'lines';
  if items is null or jsonb_typeof(items)<>'array' or jsonb_array_length(items) not between 1 and 200 then raise exception 'INVALID_LINES'; end if;
  subtotal:=0; taxes:=0;
  for x in select value from jsonb_array_elements(items) loop
   qty:=(x->>'quantity')::numeric;
   if qty is null or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY'; end if;
   select * into l from public.sales_order_lines where id=(x->>'line_id')::uuid and order_id=oid;
   if not found then raise exception 'INVALID_ORDER_LINE'; end if;
   select coalesce(sum(il.quantity),0) into billed from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('rejected','cancelled');
   if billed+qty>l.quantity then raise exception 'EXCEEDS_UNBILLED'; end if;
   subtotal:=subtotal+round(qty*l.unit_price,2); taxes:=taxes+round(round(qty*l.unit_price,2)*l.tax_rate/100,2);
  end loop;
  if (p_data->>'subtotal')::numeric is null or (p_data->>'tax')::numeric is null or abs(subtotal-(p_data->>'subtotal')::numeric)>0.02 or abs(taxes-(p_data->>'tax')::numeric)>0.02 then raise exception 'AMOUNT_MISMATCH'; end if;
  insert into public.external_invoices(request_key,order_id,number,issuer_ruc,access_key,software,issue_date,due_date,subtotal,tax,fiscal_status,notes,created_by)
  values(key_id,oid,btrim(p_data->>'number'),btrim(p_data->>'issuer_ruc'),nullif(btrim(p_data->>'access_key'),''),coalesce(p_data->>'software',''),(p_data->>'issue_date')::date,nullif(p_data->>'due_date','')::date,(p_data->>'subtotal')::numeric,(p_data->>'tax')::numeric,coalesce(p_data->>'fiscal_status','unverified'),coalesce(p_data->>'notes',''),u) returning * into inv;
  eid:=inv.id;
  for x in select value from jsonb_array_elements(items) loop
   insert into public.external_invoice_lines(invoice_id,order_line_id,quantity) values(eid,(x->>'line_id')::uuid,(x->>'quantity')::numeric);
  end loop;
 elsif p_action in ('invoice_status','attach') then
  select * into inv from public.external_invoices where id=(p_data->>'invoice_id')::uuid and order_id=oid for update;
  if not found then raise exception 'INVOICE_NOT_FOUND'; end if;
  eid:=inv.id;
  if p_action='invoice_status' then
   if inv.fiscal_status in ('cancelled','rejected') then raise exception 'INVOICE_CLOSED'; end if;
   if p_data->>'fiscal_status' not in ('authorized','rejected','cancelled') or p_data->>'fiscal_status' is null then raise exception 'INVALID_STATUS'; end if;
   if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED'; end if;
   update public.external_invoices set fiscal_status=p_data->>'fiscal_status',cancellation_reason=p_data->>'reason',updated_at=now() where id=eid;
  end if;
 end if;
 if p_action in ('invoice','attach') then
  files:=coalesce(p_data->'files','[]'::jsonb);
  if jsonb_typeof(files)<>'array' or jsonb_array_length(files)>2 then raise exception 'INVALID_FILES'; end if;
  if jsonb_array_length(files)+(select count(*) from public.external_invoice_files where invoice_id=eid)>4 then raise exception 'TOO_MANY_FILES'; end if;
  for x in select value from jsonb_array_elements(files) loop
   if length(coalesce(x->>'content_base64',''))=0 or octet_length(decode(x->>'content_base64','base64'))>5000000 then raise exception 'INVALID_FILE_SIZE'; end if;
   insert into public.external_invoice_files(invoice_id,filename,mime_type,content_base64) values(eid,x->>'filename',x->>'mime_type',x->>'content_base64');
  end loop;
 end if;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(oid,p_action,eid,u,jsonb_build_object('reason',p_data->>'reason','status',p_data->>'fiscal_status'));
 return jsonb_build_object('id',coalesce(eid,oid),'order_id',oid);
end $$;
revoke all on function private.gama_sales_action(text,jsonb) from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.gama_sales_action(text,jsonb) to authenticated;
create function public.gama_sales_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.gama_sales_action(p_action,p_data); $$;
revoke all on function public.gama_sales_action(text,jsonb) from public,anon;
grant execute on function public.gama_sales_action(text,jsonb) to authenticated;
