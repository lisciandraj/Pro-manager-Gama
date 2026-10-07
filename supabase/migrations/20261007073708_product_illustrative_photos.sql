-- Real illustrative photos are explicitly distinguished from reference-specific photos.
-- Existing images and publication/access rules are preserved.
alter table public.products add column photo_is_illustrative boolean not null default false;
comment on column public.products.photo_is_illustrative is 'True for a representative photograph that does not guarantee brand, model, color, dosage, dimensions or packaging.';
create function private.clear_replaced_illustrative_photo() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.photo_data is distinct from old.photo_data
    and (old.photo_is_illustrative or coalesce(new.photo_data,'')='') then
  new.photo_is_illustrative:=false;
 end if;
 return new;
end $$;
revoke all on function private.clear_replaced_illustrative_photo() from public,anon,authenticated;
create trigger clear_replaced_illustrative_photo before update of photo_data on public.products
for each row execute function private.clear_replaced_illustrative_photo();

CREATE OR REPLACE FUNCTION storefront_api.gama_storefront(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb;curr text;term text;cat text;brand_filter text;sortby text;off integer;lim integer;count_items integer;rows jsonb;req uuid;prior private.website_public_inquiries;payload jsonb;visitor text;secret text;
 line jsonb;prod public.products;pid uuid;qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';rid uuid;seq bigint;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if not coalesce((cfg->>'site_enabled')::boolean,false) then
  if p_action='bootstrap' then return jsonb_build_object('paused',true,'settings',jsonb_build_object('brand_name',cfg->>'brand_name','phone',cfg->>'phone','email',cfg->>'email'));end if;
  raise exception 'WEBSITE_PUBLIC_PAUSED';
 end if;
 if p_action='bootstrap' then
  return jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from private.gama_storefront_items()),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) filter (where has_photo) photo_id from private.gama_storefront_items() group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from private.gama_storefront_items() where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from private.gama_storefront_items() where featured order by name,id limit 8) z),'[]'));
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  select count(*) into count_items from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter);
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from(select * from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
   order by case when sortby='featured' then featured end desc nulls last,case when sortby='price_asc' then unit_price end asc nulls last,case when sortby='price_desc' then unit_price end desc nulls last,name,id limit lim offset off) z;
  return jsonb_build_object('items',rows,'total',count_items,'offset',off,'limit',lim,'currency',curr);
 elsif p_action='product' then
  select to_jsonb(i) into rows from private.gama_storefront_items() i where id=(p_data->>'id')::uuid;
  if rows is null then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;return jsonb_build_object('item',rows,'currency',curr);
 elsif p_action='photos' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data,'photo_is_illustrative',p.photo_is_illustrative)) from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'),'[]');
 elsif p_action='submit' then
  if not (cfg->>'enable_quotes')::boolean then raise exception 'WEBSITE_QUOTES_DISABLED';end if;
  select token into secret from private.website_public_connection where id;
  if coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
  if coalesce(p_data->>'website','')<>'' then raise exception 'WEBSITE_INVALID_DATA';end if;
  visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'WEBSITE_VISITOR_REQUIRED';end if;visitor:=md5(secret||visitor);
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||req,0));payload:=p_data-'request_key'-'visitor'-'website';select * into prior from private.website_public_inquiries where request_key=req;
  if found then if prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;return jsonb_build_object('reference','WEB-'||lpad(prior.number::text,8,'0'));end if;
  if (p_data->>'consent') is distinct from 'true' or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web-visitor:'||visitor,0));
  if (select count(*) from private.website_public_inquiries where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8 or (select count(*) from private.website_public_inquiries where email=lower(btrim(p_data->>'email')) and created_at>now()-interval '1 hour')>=5 or (select count(*) from private.website_public_inquiries where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 30 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p.* into prod from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.id=pid and p.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax,'price_to_confirm',coalesce(prod.sale_price,0)<=0));
  end loop;
  insert into private.website_public_inquiries(request_key,payload,contact_name,email,phone,company,notes,lines,currency,total,visitor_hash,consent_at)
   values(req,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total,visitor,now()) returning id,number into rid,seq;
  return jsonb_build_object('reference','WEB-'||lpad(seq::text,8,'0'));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $function$

;
CREATE OR REPLACE FUNCTION private.gama_b2b_action_before_documents(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.gama_b2b_customer();off integer:=coalesce((p_data->>'offset')::integer,0);v_id uuid:=nullif(p_data->>'id','')::uuid;
 today date:=(now() at time zone private.erp_timezone())::date;customer public.customers;invoice public.external_invoices;f public.external_invoice_files;sri public.sri_invoice_issues;adr public.customer_addresses;key uuid;receipt private.command_receipts;payload jsonb:=p_data-'request_key';cart jsonb;line jsonb;rid uuid;reference text;rows jsonb;cnt integer;result jsonb;balance numeric;overdue numeric;begin
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 select * into customer from public.customers where customers.id=cid;
 if p_action='bootstrap' then
 select coalesce(sum(d.balance),0),coalesce(sum(d.balance) filter(where coalesce(d.due_date,d.issue_date)<today),0) into balance,overdue from private.gama_customer_dues(cid) d;
 return jsonb_build_object('customer',jsonb_build_object('name',customer.name,'identification',customer.identification,'category',customer.category),'today',today,'currency',(select currency from public.company_settings where company_settings.id),
 'total',balance,'overdue',overdue,'addresses',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'label',a.label,'address',a.address,'city',a.city) order by a.label) from public.customer_addresses a where a.customer_id=cid and a.active and a.purpose in ('delivery','order')),'[]'));
 end if;
 if p_action='catalog' then
 with filtered as(select p.id,p.name,p.reference,p.category,p.description,p.has_photo,p.photo_is_illustrative,p.order_minimum,p.order_multiple,p.tax_rate
  from public.products p where p.active and p.product_kind='goods' and (p.name ilike '%'||left(coalesce(p_data->>'search',''),100)||'%' or p.reference ilike '%'||left(coalesce(p_data->>'search',''),100)||'%')),
 limited as(select * from filtered order by name,id limit 30 offset off)
 select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('unit_price',private.erp_price_calculate(cid,l.id,greatest(1,l.order_minimum),null)->'unit_price') order by name,id),'[]') into cnt,rows from limited l;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='photo' then
 if not exists(select 1 from public.products p where p.id=v_id and p.active and p.product_kind='goods') then raise exception 'PRODUCT_NOT_FOUND';end if;
 return jsonb_build_object('photo',(select ph.photo from public.product_photos ph where ph.product_id=v_id));
 end if;
 if p_action='preview' then return private.gama_b2b_cart(cid,p_data->'lines');end if;
 if p_action='favorites' then return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'lines',coalesce((select jsonb_agg(jsonb_build_object('product_id',l.product_id,'quantity',l.quantity,'name',p.name,'active',p.active) order by p.name) from public.favorite_order_lines l join public.products p on p.id=l.product_id where l.favorite_order_id=o.id),'[]')) order by o.created_at desc,o.id) from public.favorite_orders o where o.created_by=auth.uid()),'[]');end if;
 if p_action='favorite_delete' then delete from public.favorite_orders where favorite_orders.id=v_id and created_by=auth.uid();if not found then raise exception 'NOT_FOUND';end if;return jsonb_build_object('deleted',true);end if;
 if p_action in ('submit','favorite_save') then
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('b2b-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='b2b-'||p_action and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if (select count(*) from private.command_receipts where actor_id=auth.uid() and domain='b2b-'||p_action and created_at>now()-interval '1 hour')>=60 then raise exception 'B2B_RATE_LIMIT';end if;
 cart:=private.gama_b2b_cart(cid,p_data->'lines');
 if p_action='favorite_save' then
 if length(btrim(coalesce(p_data->>'name',''))) not between 1 and 80 or (select count(*) from public.favorite_orders where created_by=auth.uid())>=30 then raise exception 'B2B_FAVORITE_LIMIT';end if;
 insert into public.favorite_orders(created_by,name) values(auth.uid(),btrim(p_data->>'name')) returning favorite_orders.id into rid;
 for line in select value from jsonb_array_elements(cart->'lines') loop insert into public.favorite_order_lines(favorite_order_id,product_id,quantity) values(rid,(line->>'product_id')::uuid,(line->>'quantity')::numeric);end loop;result:=jsonb_build_object('id',rid);
 else
 if cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
 if length(coalesce(p_data->>'notes',''))>2000 or (nullif(p_data->>'requested_delivery_date','')::date is not null and nullif(p_data->>'requested_delivery_date','')::date<today) then raise exception 'INVALID_DATA';end if;
 if nullif(p_data->>'address_id','') is not null then select * into adr from public.customer_addresses where customer_addresses.id=(p_data->>'address_id')::uuid and customer_id=cid and active and purpose in ('delivery','order');if not found then raise exception 'B2B_ADDRESS_NOT_FOUND';end if;end if;
 insert into public.customer_requests(customer_id,created_by,status,requester_name,requester_email,notes,total,requested_delivery_date,delivery_address_id,delivery_address_snapshot)
 values(cid,auth.uid(),'pending',customer.name,customer.email,coalesce(p_data->>'notes',''),(cart->>'total')::numeric,nullif(p_data->>'requested_delivery_date','')::date,adr.id,case when adr.id is not null then concat_ws(', ',adr.address,adr.city) else customer.address end) returning customer_requests.id,erp_reference into rid,reference;
 for line in select value from jsonb_array_elements(cart->'lines') loop insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total) values(rid,(line->>'product_id')::uuid,(line->>'quantity')::numeric,(line->>'unit_price')::numeric,(line->>'tax_rate')::numeric,(line->>'net')::numeric);end loop;
 result:=jsonb_build_object('id',rid,'reference',reference,'total',cart->'total');
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('b2b-'||p_action,key,auth.uid(),payload,result);return result;
 end if;
 if p_action='requests' then return coalesce((select jsonb_agg(to_jsonb(z)) from(select r.erp_reference reference,r.status,r.total,r.created_at,r.requested_delivery_date,r.delivery_address_snapshot from public.customer_requests r where r.customer_id=cid order by r.created_at desc,r.id limit 30 offset off) z),'[]');end if;
 if p_action='invoices' then
 with owned as(select i.* from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected')),
 limited as(select * from owned order by issue_date desc,id limit 30 offset off)
 select (select count(*) from owned),coalesce(jsonb_agg(jsonb_build_object('id',i.id,'reference',coalesce(i.erp_reference,i.number),'fiscal_number',coalesce(i.external_number,i.number),'issue_date',i.issue_date,'due_date',i.due_date,'total',i.total,'status',case when i.document_kind='internal' then coalesce(i.external_status,i.fiscal_status) else i.fiscal_status end,
 'balance',coalesce((select sum(d.balance) from private.gama_customer_dues(cid,array[i.id]) d),0),
 'sri_id',(select s.id from public.sri_invoice_issues s where s.source_invoice_id=i.id and s.status='authorized'),
 'files',coalesce((select jsonb_agg(jsonb_build_object('id',fl.id,'mime_type',fl.mime_type)) from public.external_invoice_files fl where fl.invoice_id=i.id),'[]')) order by i.issue_date desc,i.id),'[]') into cnt,rows from limited i;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='invoice_file' then
 select x.* into f from public.external_invoice_files x join public.external_invoices i on i.id=x.invoice_id join public.sales_orders o on o.id=i.order_id where x.id=v_id and o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected');if not found then raise exception 'NOT_FOUND';end if;
 select coalesce(i.erp_reference,i.number) into reference from public.external_invoices i where i.id=f.invoice_id;
 return jsonb_build_object('content_base64',f.content_base64,'mime_type',f.mime_type,'filename',reference||case when f.mime_type='application/pdf' then '.pdf' else '.xml' end);
 end if;
 if p_action='sri_document' then
 select x.* into sri from public.sri_invoice_issues x join public.external_invoices i on i.id=x.source_invoice_id join public.sales_orders o on o.id=i.order_id where x.id=v_id and x.customer_id=cid and o.customer_id=cid and x.status='authorized' and i.fiscal_status not in ('cancelled','rejected');if not found then raise exception 'NOT_FOUND';end if;
 if p_data->>'kind' not in ('xml','ride') then raise exception 'INVALID_DATA';end if;
 select coalesce(i.erp_reference,i.number) into reference from public.external_invoices i where i.id=sri.source_invoice_id;
 return jsonb_build_object('path',case when p_data->>'kind'='xml' then sri.authorized_xml_path else sri.ride_path end,'filename',reference||case when p_data->>'kind'='xml' then '.xml' else '.pdf' end);
 end if;
 if p_action='deliveries' then
 with owned as(select d.* from public.tms_deliveries d where d.customer_id=cid and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid)),limited as(select * from owned order by delivery_date desc,id limit 30 offset off)
 select (select count(*) from owned),coalesce(jsonb_agg(jsonb_build_object('id',d.id,'reference',d.erp_reference,'date',d.delivery_date,'address',d.address,'status',d.status,'delivered_at',d.delivered_at,'has_proof',exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)) order by d.delivery_date desc,d.id),'[]') into cnt,rows from limited d;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='proof' then
 select jsonb_build_object('reference',d.erp_reference,'customer',customer.name,'address',d.address,'date',d.delivery_date,'delivered_at',d.delivered_at,'photo',p.photo,'signature',p.signature,'captured_at',p.captured_at,'latitude',p.latitude,'longitude',p.longitude,'accuracy',p.gps_accuracy_m)
 into result from public.tms_deliveries d join public.tms_proofs p on p.delivery_id=d.id where d.id=v_id and d.customer_id=cid and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid);if result is null then raise exception 'NOT_FOUND';end if;return result;
 end if;
 if p_action='statement' then
 select count(*),coalesce(sum(d.balance),0),coalesce(sum(d.balance) filter(where coalesce(d.due_date,d.issue_date)<today),0) into cnt,balance,overdue from private.gama_customer_dues(cid) d;
 if coalesce((p_data->>'export')::boolean,false) and cnt>10000 then raise exception 'B2B_STATEMENT_EXPORT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(d) order by coalesce(d.due_date,d.issue_date),d.number,d.position),'[]') into rows from(select d.number,d.issue_date,d.due_date,d.amount,d.balance,d.position from private.gama_customer_dues(cid) d order by coalesce(d.due_date,d.issue_date),d.number,d.position limit case when coalesce((p_data->>'export')::boolean,false) then 10000 else 30 end offset off) d;
 return jsonb_build_object('customer',jsonb_build_object('name',customer.name,'identification',customer.identification),'today',today,'total',balance,'overdue',overdue,'count',cnt,'rows',rows,
 'company',(select jsonb_build_object('legal_name',c.legal_name,'tax_id',c.tax_id,'address',c.address,'phone',c.phone,'email',c.email,'currency',c.currency,'country',c.country,'logo_data',c.logo_data,'website',c.website,'document_primary',c.document_primary,'document_secondary',c.document_secondary) from public.company_settings c where c.id));
 end if;raise exception 'INVALID_ACTION';
end $function$

;
notify pgrst,'reload schema';
