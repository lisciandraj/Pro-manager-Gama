-- The first website is an authenticated administrator preview. No anonymous
-- catalogue, prices, customer data or write endpoint is opened by this release.
create table private.website_settings (
 id boolean primary key default true check(id),
 version integer not null default 1,
 preview_enabled boolean not null default true,
 show_prices boolean not null default true,
 headline text not null default 'Todo para abastecer tu empresa.' check(length(headline) between 1 and 120),
 introduction text not null default 'Productos para tu día a día, con la atención de Distribuidora GAMA.' check(length(introduction)<=500),
 phone text not null default '(593-2) 250-1350' check(length(phone)<=60),
 email text not null default '' check(length(email)<=254),
 address text not null default 'Puerto Rico N27-108 y Selva Alegre, Quito' check(length(address)<=300),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null
);
create table private.website_products (
 product_id uuid primary key references public.products(id) on delete cascade,
 visible boolean not null default false, featured boolean not null default false,
 description text not null default '' check(length(description)<=2000),
 version integer not null default 1,
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null
);
create table private.website_inquiries (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 request_key uuid not null unique, actor_id uuid references auth.users(id) on delete set null,
 payload jsonb not null, contact_name text not null, email text not null, phone text not null default '',
 company text not null default '', notes text not null default '', lines jsonb not null,
 currency text not null, total numeric not null, is_test boolean not null default true check(is_test),
 status text not null default 'new' check(status in ('new','reviewed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index website_inquiries_created_at on private.website_inquiries(created_at desc,id);
create index website_inquiries_actor on private.website_inquiries(actor_id);
alter table private.website_settings enable row level security;
alter table private.website_products enable row level security;
alter table private.website_inquiries enable row level security;
revoke all on private.website_settings,private.website_products,private.website_inquiries from public,anon,authenticated;
insert into private.website_settings(id) values(true);
-- A small, private preview selection; nothing is published to anonymous users.
insert into private.website_products(product_id,visible,featured)
 select id,true,row_number() over(order by (photo_data is not null) desc,name,id)<=4
 from public.products where active order by (photo_data is not null) desc,name,id limit 12;

-- Register the module in the existing permissions editor without replacing
-- unrelated module rules or granting it to any additional business role.
do $$declare src text;begin
 select pg_get_constraintdef(oid) into src from pg_constraint where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if strpos(src,'''contacts''::text')=0 then raise exception 'WEBSITE_MODULE_CONSTRAINT_ANCHOR';end if;
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||replace(src,'''contacts''::text','''contacts''::text, ''website''::text');
 src:=pg_get_functiondef('private.gama_save_action_permissions(text,jsonb,jsonb)'::regprocedure);
 if strpos(src,'''contacts'')')=0 then raise exception 'WEBSITE_ACTION_ANCHOR';end if;
 execute replace(src,'''contacts'')','''contacts'',''website'')');
end $$;

create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cfg private.website_settings;item private.website_products;prior private.website_inquiries;
 actor uuid:=auth.uid();pid uuid;req uuid;rid uuid;seq bigint;payload jsonb;line jsonb;prod public.products;
 qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';curr text;
 term text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 lim integer:=greatest(1,least(coalesce((p_data->>'limit')::integer,24),60));
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>65536 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select * into cfg from private.website_settings where id=true;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if p_action='overview' then
  return jsonb_build_object('settings',to_jsonb(cfg),'currency',curr,'selected',(select count(*) from private.website_products w join public.products p on p.id=w.product_id where w.visible and p.active),'inquiries',(select count(*) from private.website_inquiries),'unread',(select count(*) from private.website_inquiries where status='new'));
 elsif p_action='save_settings' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  update private.website_settings set preview_enabled=(p_data->>'preview_enabled')::boolean,show_prices=(p_data->>'show_prices')::boolean,
   headline=btrim(p_data->>'headline'),introduction=btrim(p_data->>'introduction'),phone=btrim(p_data->>'phone'),email=btrim(p_data->>'email'),address=btrim(p_data->>'address'),
   version=version+1,updated_at=now(),updated_by=actor where id=true and version=(p_data->>'version')::integer returning * into cfg;
  if not found then raise exception 'WEBSITE_CHANGED';end if;return to_jsonb(cfg);
 elsif p_action='save_product' then
  if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  pid:=(p_data->>'id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended('website-product:'||pid,0));
  if not exists(select 1 from public.products where id=pid and active) then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  select * into item from private.website_products where product_id=pid;
  if coalesce(item.version,0) is distinct from (p_data->>'version')::integer then raise exception 'WEBSITE_CHANGED';end if;
  insert into private.website_products(product_id,visible,featured,description,updated_by)
   values(pid,(p_data->>'visible')::boolean,(p_data->>'featured')::boolean,btrim(coalesce(p_data->>'description','')),actor)
   on conflict(product_id) do update set visible=excluded.visible,featured=excluded.featured,description=excluded.description,version=private.website_products.version+1,updated_at=now(),updated_by=actor returning * into item;
  return to_jsonb(item);
 elsif p_action in ('inquiries','inquiry') then
  return jsonb_build_object('total',(select count(*) from private.website_inquiries),'items',coalesce((select jsonb_agg(to_jsonb(x)-'payload'-'request_key'-'actor_id') from
   (select i.*,'WEB-TEST-'||lpad(i.number::text,8,'0') reference from private.website_inquiries i where p_action='inquiries' or i.id=(p_data->>'id')::uuid order by created_at desc,id limit lim offset off)x),'[]'));
 elsif p_action='review' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  update private.website_inquiries set status='reviewed',updated_at=now() where id=(p_data->>'id')::uuid;
  if not found then raise exception 'WEBSITE_INQUIRY_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 if not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action in ('catalog','photo','submit') and not cfg.preview_enabled then raise exception 'WEBSITE_PREVIEW_PAUSED';end if;
 if p_action in ('products','catalog') then
  return jsonb_build_object('settings',case when p_action='catalog' then jsonb_build_object('headline',cfg.headline,'introduction',cfg.introduction,'phone',cfg.phone,'email',cfg.email,'address',cfg.address,'show_prices',cfg.show_prices) else null end,'currency',curr,'is_test',true,
   'categories',(select coalesce(jsonb_agg(c order by c),'[]') from(select distinct coalesce(nullif(p.category,''),'Otros productos') c from public.products p left join private.website_products w on w.product_id=p.id where p.active and (p_action='products' or w.visible))z),
   'total',(select count(*) from public.products p left join private.website_products w on w.product_id=p.id where p.active and (p_action='products' or w.visible) and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0) and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category')),
   'items',coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.name,p.reference,coalesce(nullif(p.category,''),'Otros productos') category,p.product_kind,p.order_minimum,p.order_multiple,
    case when cfg.show_prices or p_action='products' then p.sale_price end unit_price,case when cfg.show_prices or p_action='products' then p.tax_rate end tax_rate,
    p.photo_data is not null has_photo,coalesce(w.visible,false) visible,coalesce(w.featured,false) featured,coalesce(w.description,'') description,coalesce(w.version,0) version
    from public.products p left join private.website_products w on w.product_id=p.id where p.active and (p_action='products' or w.visible)
     and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0)
     and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category')
    order by coalesce(w.featured,false) desc,p.name,p.id limit lim offset off)z),'[]'));
 elsif p_action='photo' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data)) from public.products p join private.website_products w on w.product_id=p.id and w.visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids'))),'[]');
 elsif p_action='submit' then
  if not private.erp_action_allowed('website','create') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('website-inquiry:'||req,0));
  payload:=p_data-'request_key';select * into prior from private.website_inquiries where request_key=req;
  if found then
   if prior.actor_id is distinct from actor or prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',prior.id,'reference','WEB-TEST-'||lpad(prior.number::text,8,'0'),'is_test',true);
  end if;
  if length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 50 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p0.* into prod from public.products p0 join private.website_products w on w.product_id=p0.id and w.visible where p0.id=pid and p0.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax));
  end loop;
  insert into private.website_inquiries(request_key,actor_id,payload,contact_name,email,phone,company,notes,lines,currency,total)
   values(req,actor,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total)
   returning id,number into rid,seq;
  return jsonb_build_object('id',rid,'reference','WEB-TEST-'||lpad(seq::text,8,'0'),'is_test',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_website(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;
create function public.gama_website(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_website(p_action,p_data)$$;
revoke all on function public.gama_website(text,jsonb) from public,anon;
grant execute on function public.gama_website(text,jsonb) to authenticated;
notify pgrst,'reload schema';
