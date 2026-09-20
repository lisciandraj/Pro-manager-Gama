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
