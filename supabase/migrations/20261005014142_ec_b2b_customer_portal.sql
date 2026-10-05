-- B2B access is separate from price categories A/B/C and never inferred from an email.
-- Retired cliente profiles stay inactive in the ERP. Only these explicit memberships
-- grant the standalone portal; the ERP's restrictive customer policies remain intact.
create table public.b2b_customer_access(customer_id uuid primary key references public.customers(id),enabled boolean not null default false,updated_at timestamptz not null default now(),updated_by uuid not null references public.profiles(id));
create table public.b2b_memberships(profile_id uuid primary key references public.profiles(id),customer_id uuid not null references public.customers(id),active boolean not null default true,updated_at timestamptz not null default now(),updated_by uuid not null references public.profiles(id));
create index b2b_memberships_customer on public.b2b_memberships(customer_id);
create index b2b_memberships_actor on public.b2b_memberships(updated_by);
create index b2b_customer_access_actor on public.b2b_customer_access(updated_by);
do $$declare t text;begin foreach t in array array['b2b_customer_access','b2b_memberships'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 execute format('create policy b2b_admin_read on public.%I for select to authenticated using(private.erp_module_allowed(''website'',array[''administrador'']) and private.erp_mfa_ok())',t);
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
end loop;end $$;
alter table public.customer_requests add column delivery_address_id uuid references public.customer_addresses(id),add column delivery_address_snapshot text;
create index customer_requests_delivery_address on public.customer_requests(delivery_address_id) where delivery_address_id is not null;

create function private.gama_b2b_customer() returns uuid language plpgsql stable security definer set search_path='' as $$
declare cid uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 select m.customer_id into cid from public.b2b_memberships m join public.b2b_customer_access a on a.customer_id=m.customer_id
 join public.profiles p on p.id=m.profile_id join auth.users u on u.id=p.id join public.customers c on c.id=m.customer_id
 where m.profile_id=auth.uid() and m.active and a.enabled and c.active and p.role='cliente' and p.deleted_at is null
 and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now());
 if cid is null or exists(select 1 from public.app_modules where id='website' and not enabled) then raise exception 'B2B_ACCESS_REQUIRED';end if;return cid;
end $$;
revoke all on function private.gama_b2b_customer() from public,anon,authenticated;

create function private.gama_b2b_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=nullif(p_data->>'customer_id','')::uuid;uid uuid:=nullif(p_data->>'profile_id','')::uuid;search text:=left(coalesce(p_data->>'search',''),100);old_member public.b2b_memberships;begin
 if not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then return jsonb_build_object('customers',coalesce((select jsonb_agg(to_jsonb(z)) from(select c.id,c.name,c.identification,c.category,coalesce(a.enabled,false) enabled from public.customers c left join public.b2b_customer_access a on a.customer_id=c.id where c.active and c.name ilike '%'||search||'%' order by c.name,c.id limit 100) z),'[]'),
 'accounts',case when private.erp_module_allowed('users',array['administrador']) then coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.full_name,u.email,(u.email_confirmed_at is not null) verified,m.customer_id linked_customer_id,c.name linked_customer_name from public.profiles p join auth.users u on u.id=p.id left join public.b2b_memberships m on m.profile_id=p.id left join public.customers c on c.id=m.customer_id where p.deleted_at is null and p.role='cliente' and (coalesce(u.email,'') ilike '%'||left(coalesce(p_data->>'account_search',''),100)||'%' or p.full_name ilike '%'||left(coalesce(p_data->>'account_search',''),100)||'%') order by p.full_name,p.id limit 100) z),'[]') else '[]'::jsonb end,
 'memberships',coalesce((select jsonb_agg(jsonb_build_object('profile_id',m.profile_id,'customer_id',m.customer_id,'active',m.active,'name',p.full_name)) from public.b2b_memberships m join public.profiles p on p.id=m.profile_id where m.customer_id in(select c.id from public.customers c where c.active and c.name ilike '%'||search||'%' order by c.name,c.id limit 100)),'[]'));
 end if;
 if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('clients',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.customers where id=cid and active for update;if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 if p_action='invitation_context' then
 if not private.gama_identity_admin_allowed() or not private.erp_action_allowed('users','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from public.b2b_customer_access where customer_id=cid and enabled) then raise exception 'B2B_ACCESS_REQUIRED';end if;
 return jsonb_build_object('allowed',true,'customer_name',(select name from public.customers where id=cid));
 end if;
 if p_action='access' then
 if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'INVALID_DATA';end if;
 insert into public.b2b_customer_access(customer_id,enabled,updated_by) values(cid,(p_data->>'enabled')::boolean,auth.uid()) on conflict(customer_id) do update set enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;
 if p_action='member' then
 if not private.erp_module_allowed('users',array['administrador']) or not private.erp_action_allowed('users','edit') or jsonb_typeof(p_data->'active') is distinct from 'boolean' then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.profiles p join auth.users u on u.id=p.id where p.id=uid and p.deleted_at is null and p.role='cliente' for update of p;if not found then raise exception 'B2B_CLIENT_ACCOUNT_REQUIRED';end if;
 select * into old_member from public.b2b_memberships where profile_id=uid for update;
 if old_member.customer_id=cid and old_member.active=(p_data->>'active')::boolean then return jsonb_build_object('saved',true);end if;
 if old_member.customer_id is distinct from nullif(p_data->>'expected_customer_id','')::uuid then raise exception 'B2B_MEMBERSHIP_CHANGED';end if;
 insert into public.b2b_memberships(profile_id,customer_id,active,updated_by) values(uid,cid,(p_data->>'active')::boolean,auth.uid()) on conflict(profile_id) do update set customer_id=excluded.customer_id,active=excluded.active,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_b2b_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_b2b_admin(p_action,p_data)$$;

-- One price calculation for staff and the scoped portal; this pure helper is
-- inaccessible to authenticated callers. Existing staff resolver guards remain.
create function private.erp_price_calculate(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.customers;p public.products;r record;special numeric;today date;begin
 select * into c from public.customers where id=p_customer and active;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
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
revoke all on function private.erp_price_calculate(uuid,uuid,numeric,date) from public,anon,authenticated;
create or replace function private.erp_price(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.customers;begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=p_customer and active;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 if private.current_user_role()='cliente' and not exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=lower(c.email)) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return private.erp_price_calculate(p_customer,p_product,p_quantity,p_date);
end $$;

create function private.gama_b2b_cart(p_customer uuid,p_lines jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare line jsonb;p public.products;price jsonb;qty numeric;net numeric;tax numeric;items jsonb:='[]';total numeric:=0;begin
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 100 or (select count(distinct x->>'product_id') from jsonb_array_elements(p_lines) x)<>jsonb_array_length(p_lines) then raise exception 'B2B_INVALID_LINES';end if;
 for line in select value from jsonb_array_elements(p_lines) order by value->>'product_id' loop
 select * into p from public.products where id=(line->>'product_id')::uuid and active and product_kind='goods';if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 qty:=(line->>'quantity')::numeric;if qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
 if qty<p.order_minimum or mod(qty,p.order_multiple)<>0 then raise exception 'PACK_QUANTITY_REQUIRED';end if;
 price:=private.erp_price_calculate(p_customer,p.id,qty,null);net:=round(qty*(price->>'unit_price')::numeric,2);tax:=round(net*p.tax_rate/100,2);total:=total+net+tax;
 items:=items||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'reference',p.reference,'quantity',qty,'unit_price',(price->>'unit_price')::numeric,'tax_rate',p.tax_rate,'net',net,'tax',tax,'total',net+tax,'price_source',price->>'label'));
 end loop;return jsonb_build_object('lines',items,'total',total,'price_hash',md5(items::text));end $$;
revoke all on function private.gama_b2b_cart(uuid,jsonb) from public,anon,authenticated;

create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
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
 with filtered as(select p.id,p.name,p.reference,p.category,p.description,p.has_photo,p.order_minimum,p.order_multiple,p.tax_rate
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
end $$;
create function public.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_b2b_action(p_action,p_data)$$;
revoke all on function private.gama_b2b_admin(text,jsonb),public.gama_b2b_admin(text,jsonb),private.gama_b2b_action(text,jsonb),public.gama_b2b_action(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_admin(text,jsonb),public.gama_b2b_admin(text,jsonb),private.gama_b2b_action(text,jsonb),public.gama_b2b_action(text,jsonb) to authenticated;

-- Preserve the reviewed delivery address through request → quote → confirmed order → TMS.
alter function private.gama_quote_from_request(uuid,jsonb) rename to gama_quote_from_request_before_b2b;
create function private.gama_quote_from_request(p_request_id uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.customer_requests;d jsonb;begin
 if auth.uid() is null or not private.erp_module_allowed('customer-requests',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into r from public.customer_requests where id=p_request_id for update;
 d:=p_data;
 if r.delivery_address_id is not null then
 if r.customer_id is distinct from nullif(p_data->>'customer_id','')::uuid then raise exception 'B2B_ADDRESS_CUSTOMER_CHANGED';end if;
 d:=jsonb_set(d,'{details}',coalesce(d->'details','{}')||jsonb_build_object('delivery_address',r.delivery_address_snapshot));
 end if;
 return private.gama_quote_from_request_before_b2b(p_request_id,d);
end $$;
revoke all on function private.gama_quote_from_request_before_b2b(uuid,jsonb) from public,anon,authenticated;
revoke all on function private.gama_quote_from_request(uuid,jsonb) from public,anon;
grant execute on function private.gama_quote_from_request(uuid,jsonb) to authenticated;
