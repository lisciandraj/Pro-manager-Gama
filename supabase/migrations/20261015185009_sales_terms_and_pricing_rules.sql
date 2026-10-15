-- Reuse the existing tier engine, observed costs and single-company currency.
alter table private.sales_dossiers add column currency text,add column payment_terms_days integer,
 add column terms_frozen_at timestamptz,add column terms_origin text;
update private.sales_dossiers d set currency=coalesce(q.accepted_snapshot#>>'{company,currency}',q.quote_details->>'currency',c.currency),
 payment_terms_days=cl.payment_terms_days,terms_origin='configuration_observed_at_migration'
 from public.company_settings c,public.customers cl left join public.invoices q on false
 where c.id and cl.id=coalesce((select customer_id from public.sales_orders where id=d.order_id),(select customer_id from public.invoices where id=d.quote_id));
create function private.sales_freeze_terms() returns trigger language plpgsql security definer set search_path='' as $$
declare did uuid;terms jsonb;freeze_terms boolean;begin
 if tg_table_name='invoices' then
  did:=new.id;terms:=new.quote_details;
  freeze_terms:=new.quote_state in ('sent','accepted');
 else
  did:=coalesce(new.source_quote_id,new.id);terms:=(select quote_details from public.invoices where id=new.source_quote_id);
  freeze_terms:=new.status='confirmed';
 end if;
 update private.sales_dossiers d set currency=coalesce(nullif(terms->>'currency',''),(select currency from public.company_settings where id)),
  payment_terms_days=coalesce(nullif(terms->>'payment_terms_days','')::integer,(select payment_terms_days from public.customers where id=new.customer_id)),
  terms_frozen_at=case when freeze_terms then now() end,terms_origin=case when freeze_terms then 'commercial_confirmation' else 'draft_defaults' end
  where d.id=did and (d.terms_frozen_at is null or not freeze_terms);
 return new;
end $$;
create trigger zz_sales_freeze_terms after insert or update of quote_state,customer_id,quote_details on public.invoices for each row execute function private.sales_freeze_terms();
create trigger zz_sales_freeze_terms after insert or update of status,customer_id on public.sales_orders for each row execute function private.sales_freeze_terms();
create function private.sales_invoice_terms() returns trigger language plpgsql security definer set search_path='' as $$
declare d private.sales_dossiers;begin
 if new.document_kind<>'internal' then return new;end if;
 select * into d from private.sales_dossiers where order_id=new.order_id;
 if d.currency is distinct from (select currency from public.company_settings where id) then raise exception 'SALES_CURRENCY_CONFIGURATION_REQUIRED';end if;
 new.payment_terms_days:=coalesce(new.payment_terms_days,d.payment_terms_days);
 new.document_snapshot:=new.document_snapshot||jsonb_build_object('currency',d.currency,'payment_terms_days',new.payment_terms_days);
 return new;
end $$;
create trigger a_sales_invoice_terms before insert on public.external_invoices for each row execute function private.sales_invoice_terms();
do $$declare src text;old text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 old:='select * into anchor from public.sales_orders where id=ids[1];';
 if strpos(src,old)=0 then raise exception 'SALES_GROUP_TERMS_ANCHOR';end if;
 src:=replace(src,old,'if (select count(distinct jsonb_build_array(currency,payment_terms_days)) from private.sales_dossiers where order_id=any(ids))>1 then raise exception ''INCOMPATIBLE_INVOICE_TERMS'';end if;'||old);execute src;
end $$;

alter table public.erp_price_tiers alter column product_id drop not null,
 add column product_category text,
 add column price_method text not null default 'fixed' check(price_method in ('fixed','discount','formula')),
 add column discount_percent numeric(9,4) not null default 0 check(discount_percent between 0 and 100),
 add column price_factor numeric(18,6) not null default 1 check(price_factor>=0 and price_factor<100000),
 add column surcharge numeric(18,4) not null default 0 check(abs(surcharge)<100000000),
 add column rounding_increment numeric(18,4) check(rounding_increment>0 and rounding_increment<100000000),
 add constraint sales_price_rule_target check((product_id is not null and product_category is null) or (product_id is null and length(btrim(product_category))>0));
create unique index erp_price_category_tier on public.erp_price_tiers(book_id,product_category,min_quantity) where product_id is null;
create index erp_price_tiers_category on public.erp_price_tiers(product_category,book_id,min_quantity desc) where product_id is null;
create or replace function private.erp_price_calculate(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c public.customers;p public.products;r record;special numeric;today date;base numeric;price numeric;begin
 select * into c from public.customers where id=p_customer and active;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select * into p from public.products where id=p_product and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_quantity is null or p_quantity::text in ('NaN','Infinity','-Infinity') or p_quantity<=0 then raise exception 'INVALID_QUANTITY';end if;
 today:=coalesce(p_date,(now() at time zone private.erp_timezone())::date);
 base:=case when c.category='B' then p.sale_price_b else p.sale_price end;
 select b.id book_id,b.name,b.kind,t.* into r from public.erp_price_tiers t join public.erp_price_books b on b.id=t.book_id
 where (t.product_id=p.id or (t.product_id is null and t.product_category=p.category)) and t.min_quantity<=p_quantity
  and b.status='approved' and today>=b.valid_from and (b.valid_to is null or today<=b.valid_to) and (b.category is null or b.category=c.category)
  and (exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id and bc.customer_id=c.id)
   or (b.kind<>'contract' and not exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id)))
 order by case b.kind when 'contract' then 3 when 'promotion' then 2 else 1 end desc,b.priority desc,
  (t.product_id is not null) desc,t.min_quantity desc,b.valid_from desc,b.id,t.id limit 1;
 select unit_price into special from public.customer_special_prices where customer_id=c.id and product_id=p.id;
 if r.kind is distinct from 'contract' and c.category='C' and special is not null then
  return jsonb_build_object('unit_price',special,'source','customer_contract','label','Contrato cliente','date',today,'quantity',p_quantity);
 end if;
 if r.kind is null then return jsonb_build_object('unit_price',base,'source','category','label','Categoría '||c.category,'date',today,'quantity',p_quantity);end if;
 price:=case r.price_method when 'discount' then base*(1-r.discount_percent/100) when 'formula' then base*r.price_factor+r.surcharge else r.unit_price end;
 if r.rounding_increment is not null then price:=round(price/r.rounding_increment)*r.rounding_increment;end if;
 if price is null or price<0 or price>=100000000 then raise exception 'PRICE_RULE_RESULT_INVALID';end if;
 return jsonb_build_object('unit_price',round(price,4),'source',r.kind,'label',r.name,'rule_id',r.id,'book_id',r.book_id,
  'method',r.price_method,'date',today,'quantity',p_quantity,'rounding_increment',r.rounding_increment);
end $$;
-- Extend the existing creation transaction and its immutable receipt, including
-- category targets. Approval/archive and all role checks remain in that API.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_price_book_action(text,jsonb)'::regprocedure) into src;
 old:='if not exists(select 1 from public.products where id=(l->>''product_id'')::uuid and active) then raise exception ''PRODUCT_NOT_FOUND'';end if;';
 if strpos(src,old)=0 then raise exception 'SALES_PRICE_TARGET_ANCHOR';end if;
 src:=replace(src,old,'if nullif(l->>''product_category'','''') is not null then
  if not exists(select 1 from public.products where active and category=l->>''product_category'') then raise exception ''PRODUCT_NOT_FOUND'';end if;
 else '||old||'end if;');
 old:='insert into public.erp_price_tiers(book_id,product_id,min_quantity,unit_price) values(b.id,(l->>''product_id'')::uuid,(l->>''min_quantity'')::numeric,(l->>''unit_price'')::numeric);';
 if strpos(src,old)=0 then raise exception 'SALES_PRICE_FORMULA_ANCHOR';end if;
 src:=replace(src,old,'insert into public.erp_price_tiers(book_id,product_id,product_category,min_quantity,unit_price,price_method,discount_percent,price_factor,surcharge,rounding_increment)
 values(b.id,nullif(l->>''product_id'','''')::uuid,nullif(l->>''product_category'',''''),(l->>''min_quantity'')::numeric,(l->>''unit_price'')::numeric,
 coalesce(l->>''price_method'',''fixed''),coalesce((l->>''discount_percent'')::numeric,0),coalesce((l->>''price_factor'')::numeric,1),coalesce((l->>''surcharge'')::numeric,0),nullif(l->>''rounding_increment'','''')::numeric);');execute src;
end $$;
revoke all on function private.sales_freeze_terms(),private.sales_invoice_terms() from public,anon,authenticated;
