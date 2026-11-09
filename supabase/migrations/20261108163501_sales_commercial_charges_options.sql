-- Commercial components are genuine service/discount lines. They never create
-- catalogue products, stock moves, employee reimbursements or fiscal documents.
begin;
create table private.sales_quote_commercial_lines(
 id uuid primary key default gen_random_uuid(),quote_id uuid not null references public.invoices(id),
 kind text not null check(kind in ('discount','reward','freight')),source_id uuid not null,
 scope text not null default 'products' check(scope in ('products','freight')),target_product_id uuid references public.products(id),
 description text not null check(length(btrim(description)) between 1 and 500),
 quantity numeric(16,3) not null check(quantity>0 and quantity<100000000),
 unit_price numeric(16,4) not null check(abs(unit_price)<100000000),
 tax_rate numeric(7,4) not null check(tax_rate between 0 and 100),tax_ids uuid[],
 metadata jsonb not null default '{}',updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 check((kind in ('discount','reward') and unit_price=-1) or (kind='freight' and unit_price>=0))
);
create index sales_quote_commercial_quote on private.sales_quote_commercial_lines(quote_id);
create index sales_quote_commercial_source on private.sales_quote_commercial_lines(quote_id,source_id);
create table private.sales_quote_discount_policies(
 quote_id uuid primary key references public.invoices(id),source_id uuid not null unique default gen_random_uuid(),
 mode text not null check(mode in ('fixed','percent')),amount numeric not null check(amount>=0 and amount<100000000),
 description text not null,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create table private.sales_freight_rules(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 pricing text not null check(pricing in ('fixed','rules')),fixed_price numeric not null default 0,
 base_price numeric not null default 0,per_kg numeric not null default 0,per_m3 numeric not null default 0,per_km numeric not null default 0,
 free_over numeric,tax_rate numeric(7,4) not null default 0 check(tax_rate between 0 and 100),tax_ids uuid[],
 active boolean not null default true,version integer not null default 1,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 check(least(fixed_price,base_price,per_kg,per_m3,per_km)>=0 and greatest(fixed_price,base_price,per_kg,per_m3,per_km)<100000000),
 check(free_over is null or free_over>=0)
);
create table private.sales_expense_rebills(
 id uuid primary key default gen_random_uuid(),expense_id uuid not null unique references public.expenses(id),
 sales_order_id uuid not null references public.sales_orders(id),order_line_id uuid not null unique references public.sales_order_lines(id),
 policy text not null check(policy in ('cost','sale_price')),cost numeric not null check(cost>=0),sale_price numeric not null check(sale_price>=0),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create index sales_expense_rebills_order on private.sales_expense_rebills(sales_order_id);
create table private.sales_product_options(
 id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),optional_product_id uuid not null references public.products(id),
 relation text not null check(relation in ('optional','upsell')),quantity numeric(16,3) not null default 1 check(quantity>0 and quantity<100000000),
 active boolean not null default true,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 unique(product_id,optional_product_id),check(product_id<>optional_product_id)
);
create index sales_product_options_optional on private.sales_product_options(optional_product_id);
create table private.sales_commercial_receipts(request_key uuid primary key,actor_id uuid not null references auth.users(id),payload jsonb not null,response jsonb not null);
alter table public.sales_order_lines alter column product_id drop not null;
alter table public.sales_order_lines add column line_kind text not null default 'product' check(line_kind in ('product','discount','reward','freight','expense_rebill')),
 add column commercial_source_id uuid,add column commercial_scope text not null default 'products' check(commercial_scope in ('products','freight')),
 add column commercial_metadata jsonb not null default '{}';
alter table public.sales_order_lines drop constraint sales_order_lines_unit_price_check;
alter table public.sales_order_lines add constraint sales_order_lines_commercial_identity check(
 (line_kind='product' and product_id is not null and unit_price>=0 and unit_price<100000000)
 or (line_kind in ('discount','reward') and product_id is null and unit_price=-1 and commercial_source_id is not null)
 or (line_kind in ('freight','expense_rebill') and product_id is null and unit_price>=0 and unit_price<100000000 and commercial_source_id is not null));
create unique index sales_order_commercial_source on public.sales_order_lines(order_id,commercial_source_id,tax_rate,coalesce(tax_ids,'{}')) where line_kind<>'product';
create or replace function private.erp_sales_line_kind() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.product_id is null then new.product_kind:='service';else select product_kind into new.product_kind from public.products where id=new.product_id;end if;return new;
end $$;

create function private.coco_sales_commercial_require(p_quote uuid default null,p_order uuid default null,p_write boolean default false) returns void
language plpgsql stable security definer set search_path='' as $$
declare m text:=case when p_order is not null then 'sales-orders' else 'quotes' end;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(m,array['administrador','comercial'])
  or (p_write and not private.erp_action_allowed(m,'edit')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_quote is not null and not exists(select 1 from public.invoices where id=p_quote and quote_state is not null) then raise exception 'QUOTE_NOT_FOUND';end if;
 if p_order is not null and not exists(select 1 from public.sales_orders where id=p_order) then raise exception 'ORDER_NOT_FOUND';end if;
end $$;

create function private.coco_sales_quote_commercial_lines(p_quote uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('key',id,'id',id,'kind',kind,'line_kind',kind,'source_id',source_id,'scope',scope,
 'description',description,'name',description,'product_id',null,'quantity',quantity,'unit_price',unit_price,'discount',0,'tax_rate',tax_rate,
 'tax_quantity',case when kind in ('discount','reward') then 0 else quantity end,'force_price_excluded',true,'subtotal',round(quantity*unit_price,2))
 ||case when tax_ids is null then '{}'::jsonb else jsonb_build_object('tax_ids',tax_ids) end order by kind,id),'[]')
 from private.sales_quote_commercial_lines where quote_id=p_quote
$$;

create function private.coco_sales_quote_retotal(p_quote uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.invoices;ls jsonb;calc jsonb;begin
 select * into q from public.invoices where id=p_quote for update;if not found then raise exception 'QUOTE_NOT_FOUND';end if;
 if q.quote_state='accepted' then return q.tax_calculation;end if;
 select coalesce(jsonb_agg(jsonb_build_object('key',l.id,'product_id',l.product_id,'quantity',l.quantity,
 'unit_price',l.quote_list_price,'discount',coalesce(l.quote_discount,0),'tax_rate',l.tax_rate)
 ||case when l.tax_ids is null then '{}'::jsonb else jsonb_build_object('tax_ids',l.tax_ids) end order by l.id),'[]') into ls from public.invoice_lines l where l.invoice_id=q.id;
 calc:=private.coco_tax_compute('sale',q.customer_id,(q.issue_date at time zone private.erp_timezone())::date,ls||private.coco_sales_quote_commercial_lines(q.id),q.tax_fiscal_position_id,q.tax_rounding);
 if (calc->>'subtotal')::numeric<0 or (calc->>'total')::numeric<0 then raise exception 'DISCOUNT_EXCEEDS_BASE';end if;
 update public.invoices set subtotal=(calc->>'subtotal')::numeric,tax=(calc->>'tax')::numeric,total=(calc->>'total')::numeric,tax_calculation=calc where id=q.id;
 return calc;
end $$;

-- Positive amounts mean a reduction. Split by the original tax signature and
-- allocate the final residual cent deterministically; never reduce fixed taxes.
create function private.coco_sales_adjustment_apply(p_quote uuid,p_kind text,p_amount numeric,p_reference text,p_source uuid,p_scope jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare q public.invoices;g record;base numeric;remaining numeric;part numeric;freight_row record;fee jsonb;scope_name text:=case when p_kind='reward_shipping' then 'freight' else 'products' end;
 k text:=case when p_kind='discount' then 'discount' else 'reward' end;target_product uuid:=nullif(p_scope->>'product_id','')::uuid;begin
 perform private.coco_sales_commercial_require(p_quote,null,true);perform pg_advisory_xact_lock(741932,1);
 select * into q from public.invoices where id=p_quote for update;
 if q.quote_state<>'draft' or exists(select 1 from public.sales_orders where source_quote_id=q.id) then raise exception 'QUOTE_LOCKED';end if;
 if p_kind not in ('discount','reward','reward_shipping','reward_product') or (p_kind='reward_product' and target_product is null) or p_source is null or p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity')
  or p_amount<0 or p_amount<>round(p_amount,2) or length(btrim(coalesce(p_reference,''))) not between 1 and 500 then raise exception 'INVALID_ADJUSTMENT';end if;
 select sum(amount) into base from(
  select l.line_total amount from public.invoice_lines l where invoice_id=p_quote and scope_name='products' and (target_product is null or l.product_id=target_product)
  union all select round(l.quantity*l.unit_price,2) from private.sales_quote_commercial_lines l where quote_id=p_quote and kind='freight' and scope_name='freight')s;
 if p_amount>coalesce(base,0) then raise exception 'DISCOUNT_EXCEEDS_BASE';end if;
 delete from private.sales_quote_commercial_lines where quote_id=p_quote and kind=k and source_id=p_source;
 remaining:=p_amount;
 for g in select tax_rate,tax_ids,sum(amount) amount,row_number() over(order by tax_rate,tax_ids) n,count(*) over() cnt from(
  select l.tax_rate,l.tax_ids,l.line_total amount from public.invoice_lines l where invoice_id=p_quote and scope_name='products' and (target_product is null or l.product_id=target_product)
  union all select l.tax_rate,l.tax_ids,round(l.quantity*l.unit_price,2) from private.sales_quote_commercial_lines l where quote_id=p_quote and kind='freight' and scope_name='freight')s
  where amount>0 group by tax_rate,tax_ids order by tax_rate,tax_ids loop
  part:=case when g.n=g.cnt then remaining else round(p_amount*g.amount/base,2) end;remaining:=remaining-part;
  if part+coalesce((select sum(quantity) from private.sales_quote_commercial_lines where quote_id=p_quote and kind in ('discount','reward')
   and scope=scope_name and tax_rate=g.tax_rate and tax_ids is not distinct from g.tax_ids),0)>g.amount then raise exception 'DISCOUNT_EXCEEDS_BASE';end if;
  if part>0 then insert into private.sales_quote_commercial_lines(quote_id,kind,source_id,scope,target_product_id,description,quantity,unit_price,tax_rate,tax_ids,updated_by)
   values(p_quote,k,p_source,scope_name,target_product,p_reference,part,-1,g.tax_rate,g.tax_ids,auth.uid());end if;
 end loop;
 for freight_row in select * from private.sales_quote_commercial_lines where quote_id=p_quote and kind='freight' loop
  fee:=private.coco_sales_freight_amount(freight_row.source_id,p_quote,null,coalesce((freight_row.metadata->>'distance_km')::numeric,0));
  update private.sales_quote_commercial_lines set unit_price=(fee->>'amount')::numeric,metadata=fee,updated_by=auth.uid(),updated_at=now() where id=freight_row.id;
 end loop;
 perform private.coco_sales_quote_retotal(p_quote);
 update public.invoices set quote_revision=quote_revision+1,updated_at=now() where id=p_quote returning * into q;
 return jsonb_build_object('id',p_quote,'revision',q.quote_revision,'quote_revision',q.quote_revision,'adjustment_ids',
 (select coalesce(jsonb_agg(id order by id),'[]') from private.sales_quote_commercial_lines where quote_id=p_quote and source_id=p_source));
end $$;

create function private.coco_sales_freight_amount(p_rule uuid,p_quote uuid,p_order uuid,p_km numeric default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r private.sales_freight_rules;weight numeric;volume numeric;net numeric;amount numeric;begin
 select * into r from private.sales_freight_rules where id=p_rule and active;if not found then raise exception 'FREIGHT_RULE_NOT_FOUND';end if;
 if p_km is null or p_km::text in ('NaN','Infinity','-Infinity') or p_km not between 0 and 100000 then raise exception 'INVALID_DISTANCE';end if;
 select coalesce(sum(x.quantity*coalesce(p.weight_g,0)/1000),0),coalesce(sum(x.quantity*coalesce(p.volume_cm3,0)/1000000),0),coalesce(sum(round(x.quantity*x.unit_price,2)),0)
 into weight,volume,net from(
 select l.product_id,l.quantity,case when l.quantity>0 then l.line_total/l.quantity else 0 end unit_price from public.invoice_lines l where invoice_id=p_quote
 union all select l.product_id,l.quantity,l.unit_price from public.sales_order_lines l where order_id=p_order and line_kind='product')x join public.products p on p.id=x.product_id;
 if p_quote is not null then net:=net+coalesce((select sum(quantity*unit_price) from private.sales_quote_commercial_lines where quote_id=p_quote and kind in ('discount','reward') and scope='products'),0);
 else net:=net+coalesce((select sum(quantity*unit_price) from public.sales_order_lines where order_id=p_order and line_kind in ('discount','reward') and commercial_scope='products'),0);end if;
 amount:=case when r.free_over is not null and net>=r.free_over then 0 when r.pricing='fixed' then r.fixed_price else r.base_price+weight*r.per_kg+volume*r.per_m3+p_km*r.per_km end;
 return jsonb_build_object('amount',round(amount,2),'weight_kg',weight,'volume_m3',volume,'distance_km',p_km,'base',net,'rule_id',r.id,'version',r.version,'name',r.name);
end $$;

create function private.coco_sales_commercial_bind(p_quote uuid,p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare r private.sales_quote_commercial_lines;begin
 for r in select * from private.sales_quote_commercial_lines where quote_id=p_quote order by kind,id loop
  if exists(select 1 from public.sales_order_lines where order_id=p_order and commercial_source_id=r.id) then continue;end if;
  insert into public.sales_order_lines(order_id,product_id,product_name,reference,quantity,unit_price,tax_rate,tax_ids,line_kind,commercial_source_id,commercial_scope,commercial_metadata)
   values(p_order,null,r.description,'',r.quantity,r.unit_price,r.tax_rate,r.tax_ids,r.kind,r.id,r.scope,r.metadata||jsonb_build_object('source_id',r.source_id,'quote_commercial_line_id',r.id,'target_product_id',r.target_product_id));
 end loop;
 update private.sales_dossier_lines d set invoice_policy='ordered' from public.sales_order_lines l where l.id=d.order_line_id and l.order_id=p_order and l.line_kind<>'product';
end $$;

create function private.coco_sales_order_line_net(p_line uuid,p_quantity numeric) returns numeric language sql stable security definer set search_path='' as $$
 select round(coalesce((tax_snapshot->>'subtotal')::numeric*p_quantity/nullif(quantity,0),p_quantity*unit_price),2) from public.sales_order_lines where id=p_line
$$;

-- Entitlement is monetary for reductions (unit price -1). An amount can only be
-- consumed in proportion to its taxable merchandise, including active drafts.
alter function private.sales_line_entitlement(uuid) rename to sales_line_entitlement_before_commercial;
create function private.sales_line_entitlement(p_line uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare l public.sales_order_lines;base numeric;eligible numeric;begin
 select * into l from public.sales_order_lines where id=p_line;
 if l.line_kind not in ('discount','reward') then return private.sales_line_entitlement_before_commercial(p_line);end if;
 select sum(private.coco_sales_order_line_net(x.id,x.quantity)),sum(private.coco_sales_order_line_net(x.id,private.sales_line_entitlement_before_commercial(x.id))) into base,eligible
 from public.sales_order_lines x where x.order_id=l.order_id and x.line_kind=case when l.commercial_scope='freight' then 'freight' else 'product' end
 and x.tax_rate=l.tax_rate and x.tax_ids is not distinct from l.tax_ids
 and (nullif(l.commercial_metadata->>'target_product_id','') is null or x.product_id=(l.commercial_metadata->>'target_product_id')::uuid);
 return least(l.quantity,coalesce(round(l.quantity*eligible/nullif(base,0),2),0));
end $$;
create function private.coco_sales_commercial_invoice_quantity(p_line uuid,p_data jsonb) returns numeric language plpgsql stable security definer set search_path='' as $$
declare l public.sales_order_lines;x public.sales_order_lines;base numeric:=0;before_base numeric:=0;selected_base numeric:=0;used numeric;qty numeric;prior numeric;avail numeric;begin
 select * into l from public.sales_order_lines where id=p_line;
 for x in select * from public.sales_order_lines where order_id=l.order_id and line_kind=case when l.commercial_scope='freight' then 'freight' else 'product' end
  and tax_rate=l.tax_rate and tax_ids is not distinct from l.tax_ids
  and (nullif(l.commercial_metadata->>'target_product_id','') is null or product_id=(l.commercial_metadata->>'target_product_id')::uuid) loop
  select coalesce(sum(il.quantity),0) into used from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=x.id and i.fiscal_status not in ('cancelled','rejected');
  avail:=greatest(0,private.sales_line_entitlement(x.id)-used);
  if p_data ? 'lines' then select coalesce(sum((v->>'quantity')::numeric),0) into qty from jsonb_array_elements(p_data->'lines') v where v->>'line_id'=x.id::text;else qty:=avail;end if;
  if qty<0 or qty>avail then raise exception 'EXCEEDS_UNBILLED';end if;
  base:=base+private.coco_sales_order_line_net(x.id,x.quantity);before_base:=before_base+private.coco_sales_order_line_net(x.id,used);selected_base:=selected_base+private.coco_sales_order_line_net(x.id,qty);
 end loop;
 if selected_base<=0 then return 0;end if;
 select coalesce(sum(il.quantity),0) into prior from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected');
 return greatest(0,least(l.quantity,round(l.quantity*(before_base+selected_base)/nullif(base,0),2))-prior);
end $$;
-- Returned goods retain the invoiced reduction; transport is not automatically
-- refunded with merchandise. This also handles a return of one partial invoice.
create function private.coco_sales_return_unit(p_invoice uuid,p_line uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare inv public.external_invoices;l public.sales_order_lines;il public.external_invoice_lines;discount record;piece jsonb;denominator numeric;linebase numeric;gross numeric;share numeric:=0;begin
 select * into inv from public.external_invoices where id=p_invoice;select * into l from public.sales_order_lines where id=p_line;
 select * into il from public.external_invoice_lines where invoice_id=p_invoice and order_line_id=p_line;
 if il.id is null then return l.unit_price*(1+l.tax_rate/100);end if;
 select value into piece from jsonb_array_elements(coalesce(inv.document_snapshot#>'{tax_calculation,lines}',inv.document_snapshot->'lines','[]')) where coalesce(value->>'key',value->>'line_id')=p_line::text;
 linebase:=coalesce((piece->>'subtotal')::numeric,round(il.quantity*l.unit_price,2));
 gross:=coalesce((piece->>'total')::numeric,linebase+coalesce((piece->>'tax')::numeric,round(linebase*l.tax_rate/100,2)));
 for discount in select d.*,x.quantity invoiced_qty from public.sales_order_lines d join public.external_invoice_lines x on x.order_line_id=d.id
 where x.invoice_id=p_invoice and d.order_id=l.order_id and d.line_kind in ('discount','reward') and d.commercial_scope='products'
 and d.tax_rate=l.tax_rate and d.tax_ids is not distinct from l.tax_ids
 and (nullif(d.commercial_metadata->>'target_product_id','') is null or (d.commercial_metadata->>'target_product_id')::uuid=l.product_id) loop
  select coalesce(sum(private.coco_sales_order_line_net(p.id,x.quantity)),0) into denominator from public.external_invoice_lines x join public.sales_order_lines p on p.id=x.order_line_id
  where x.invoice_id=p_invoice and p.order_id=l.order_id and p.line_kind='product' and p.tax_rate=l.tax_rate and p.tax_ids is not distinct from l.tax_ids
  and (nullif(discount.commercial_metadata->>'target_product_id','') is null or p.product_id=(discount.commercial_metadata->>'target_product_id')::uuid);
  select value into piece from jsonb_array_elements(coalesce(inv.document_snapshot#>'{tax_calculation,lines}',inv.document_snapshot->'lines','[]')) where coalesce(value->>'key',value->>'line_id')=discount.id::text;
  share:=share+coalesce((piece->>'total')::numeric,(piece->>'subtotal')::numeric+(piece->>'tax')::numeric,-discount.invoiced_qty*(1+discount.tax_rate/100))*linebase/nullif(denominator,0);
 end loop;
 return greatest(0,(gross+share)/il.quantity);
end $$;
alter function private.gama_return_amount(uuid) rename to gama_return_amount_before_commercial;
create function private.gama_return_amount(p_return uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare o public.return_orders;amount numeric;begin
 select * into o from public.return_orders where id=p_return;
 if o.kind='customer' and o.invoice_id is not null and exists(select 1 from public.external_invoice_lines x join public.sales_order_lines l on l.id=x.order_line_id where x.invoice_id=o.invoice_id and l.line_kind in ('discount','reward')) then
  select coalesce(round(sum(r.quantity*private.coco_sales_return_unit(o.invoice_id,d.order_line_id)),2),0) into amount from public.return_lines r
  join public.sales_delivery_lines d on d.id=r.delivery_line_id where r.return_id=p_return;return amount;
 end if;return private.gama_return_amount_before_commercial(p_return);
end $$;
do $$declare src text;needle text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 needle:=$a$if p_data ? 'lines' then select value into x from jsonb_array_elements(p_data->'lines') where value->>'line_id'=l.id::text;qty:=coalesce((x->>'quantity')::numeric,0);else qty:=available;end if;$a$;
 if strpos(src,needle)=0 then raise exception 'COMMERCIAL_INVOICE_QUANTITY_ANCHOR';end if;
 src:=replace(src,needle,$a$if l.line_kind in ('discount','reward') then qty:=private.coco_sales_commercial_invoice_quantity(l.id,p_data);available:=greatest(available,qty);
 else if p_data ? 'lines' then select value into x from jsonb_array_elements(p_data->'lines') where value->>'line_id'=l.id::text;qty:=coalesce((x->>'quantity')::numeric,0);else qty:=available;end if;end if;$a$);
 needle:=$a$'reference',l.reference,'qty',qty$a$;
 if strpos(src,needle)=0 then raise exception 'COMMERCIAL_INVOICE_SNAPSHOT_ANCHOR';end if;
 src:=replace(src,needle,$a$'reference',l.reference,'line_kind',l.line_kind,'commercial_source_id',l.commercial_source_id,'commercial_metadata',l.commercial_metadata,'force_price_excluded',l.line_kind<>'product','tax_quantity',case when l.line_kind in ('discount','reward') then 0 else qty end,'qty',qty$a$);
 execute src;
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into src;
 needle:=$a$'name',l.product_name,'quantity',r.quantity$a$;
 if strpos(src,needle)=0 then raise exception 'COMMERCIAL_PREVIEW_ANCHOR';end if;
 execute replace(src,needle,$a$'name',l.product_name,'line_kind',l.line_kind,'tax_ids',l.tax_ids,'commercial_scope',l.commercial_scope,'commercial_metadata',l.commercial_metadata,'quantity',r.quantity$a$);
end $$;

alter function private.gama_quote_action(text,jsonb) rename to gama_quote_action_before_commercial;
create function private.gama_quote_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;qid uuid;policy private.sales_quote_discount_policies;row private.sales_quote_commercial_lines;fee jsonb;amount numeric;existing_creation boolean:=false;begin
 if p_action='save' and nullif(p_data->>'id','') is null then select exists(select 1 from public.invoices where quote_request_key=nullif(p_data->>'request_key','')::uuid) into existing_creation;end if;
 if p_action='accept' then set constraints public.ec_credit_line_guard deferred;end if;
 result:=private.gama_quote_action_before_commercial(p_action,p_data);qid:=(result->>'id')::uuid;
 if existing_creation then return result;end if;
 if p_action='save' then
  for row in select * from private.sales_quote_commercial_lines where quote_id=qid and kind='freight' loop
   fee:=private.coco_sales_freight_amount(row.source_id,qid,null,coalesce((row.metadata->>'distance_km')::numeric,0));
   update private.sales_quote_commercial_lines set unit_price=(fee->>'amount')::numeric,metadata=fee,updated_by=auth.uid(),updated_at=now() where id=row.id;
  end loop;
  select * into policy from private.sales_quote_discount_policies where quote_id=qid;
  if found then
   select case when policy.mode='percent' then round(sum(line_total)*policy.amount/100,2) else policy.amount end into amount from public.invoice_lines where invoice_id=qid;
   result:=result||private.coco_sales_adjustment_apply(qid,'discount',amount,policy.description,policy.source_id);
  else perform private.coco_sales_quote_retotal(qid);end if;
  result:=result||jsonb_build_object('commercial_lines',private.coco_sales_quote_commercial_lines(qid),'tax_calculation',(select tax_calculation from public.invoices where id=qid));
 elsif p_action='accept' then
  perform private.coco_sales_commercial_bind(qid,(result->>'order_id')::uuid);set constraints public.ec_credit_line_guard immediate;
 end if;
 return result;
end $$;
create function private.coco_sales_commercial_snapshot() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.quote_state='accepted' and old.accepted_snapshot is null then new.accepted_snapshot:=new.accepted_snapshot||jsonb_build_object('commercial_lines',private.coco_sales_quote_commercial_lines(new.id));end if;return new;
end $$;
create trigger zzz_sales_commercial_snapshot before update on public.invoices for each row execute function private.coco_sales_commercial_snapshot();
alter function private.sales_quote_fingerprint(uuid) rename to sales_quote_fingerprint_before_commercial;
create function private.sales_quote_fingerprint(p_quote uuid) returns text language sql stable security definer set search_path='' as $$
 select md5(private.sales_quote_fingerprint_before_commercial(p_quote)||private.coco_sales_quote_commercial_lines(p_quote)::text)
$$;
alter function private.sales_quote_review(uuid) rename to sales_quote_review_before_commercial;
create function private.sales_quote_review(p_quote uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;limitrow private.sales_workspace_settings;base numeric;listbase numeric;reduction numeric;cost numeric;missing integer;discount numeric;margin numeric;required boolean;begin
 r:=private.sales_quote_review_before_commercial(p_quote);select * into limitrow from private.sales_workspace_settings where id;
 select sum(l.line_total),sum(l.quantity*greatest(l.quote_list_price,coalesce((l.price_source->>'unit_price')::numeric,l.quote_list_price))),sum(l.quantity*p.purchase_price),count(*) filter(where p.purchase_price is null)
 into base,listbase,cost,missing from public.invoice_lines l join public.products p on p.id=l.product_id where invoice_id=p_quote;
 select coalesce(-sum(quantity*unit_price),0) into reduction from private.sales_quote_commercial_lines where quote_id=p_quote and kind in ('discount','reward') and scope='products';
 discount:=greatest((r->>'maximum_discount')::numeric,coalesce(round(100*(1-(base-reduction)/nullif(listbase,0)),4),0));
 margin:=case when missing=0 and base>reduction then round(100*(base-reduction-cost)/(base-reduction),2) end;
 required:=coalesce((r->>'required')::boolean,false) or coalesce(discount>limitrow.maximum_discount,false) or coalesce(margin<limitrow.minimum_margin,false)
  or (limitrow.minimum_margin is not null and missing>0);
 return r||jsonb_build_object('maximum_discount',discount,'margin',margin,'required',required,'fingerprint',private.sales_quote_fingerprint(p_quote));
end $$;
-- Service components affect billing, but never prevent goods being delivered.
do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.sales_order_summary(uuid)'::regprocedure);
 src:=replace(src,'paid numeric;balance numeric;overdue boolean;prep text;logistic text;', 'paid numeric;balance numeric;overdue boolean;prep text;logistic text;all_qty numeric;');
 needle:='logistic:=case when';if strpos(src,needle)=0 then raise exception 'COMMERCIAL_SUMMARY_ANCHOR';end if;
 src:=replace(src,needle,$a$all_qty:=qty;
 select coalesce(sum((x->>'ordered')::numeric),0),coalesce(sum(least((x->>'ordered')::numeric,(x->>'delivered')::numeric)),0),coalesce(sum(least((x->>'ordered')::numeric,(x->>'shipped')::numeric)),0)
 into qty,delivered,shipped from jsonb_array_elements(ls)x join public.sales_order_lines pl on pl.id=(x->>'id')::uuid where pl.line_kind='product';
 logistic:=case when$a$);
 src:=replace(src,'when billed>=qty and qty>0','when billed>=all_qty and all_qty>0');execute src;
end $$;
alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_commercial;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;qid uuid;begin
 r:=private.gama_sales_dossier_before_commercial(p_action,p_data);
 if p_action='dossier' then qid:=coalesce(nullif(p_data->>'quote_id','')::uuid,(select source_quote_id from public.sales_orders where id=nullif(p_data->>'order_id','')::uuid));
  r:=r||jsonb_build_object('commercial_lines',case when qid is null then '[]'::jsonb else private.coco_sales_quote_commercial_lines(qid) end);
 end if;return r;
end $$;

create function private.coco_sales_commercial(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare qid uuid:=nullif(p_data->>'quote_id','')::uuid;oid uuid:=nullif(p_data->>'order_id','')::uuid;
 q public.invoices;o public.sales_orders;r private.sales_freight_rules;policy private.sales_quote_discount_policies;e public.expenses;c private.expense_claims;
 rec private.sales_commercial_receipts;key uuid;result jsonb;target uuid;source uuid;fee jsonb;amount numeric;line uuid;iswrite boolean:=p_action not in ('context','suggestions','options');begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>40000 then raise exception 'INVALID_REQUEST';end if;
 perform private.coco_sales_commercial_require(qid,oid,iswrite);perform pg_advisory_xact_lock(741932,1);
 if p_action='suggestions' then
  return coalesce((select jsonb_agg(to_jsonb(s)) from(select x.id,x.product_id,x.optional_product_id,x.relation,x.quantity,p.name,p.reference,p.tax_rate,p.product_kind,
   private.erp_price(nullif(p_data->>'customer_id','')::uuid,p.id,x.quantity,coalesce(nullif(p_data->>'date','')::date,current_date)) price
   from private.sales_product_options x join public.products p on p.id=x.optional_product_id where x.active and p.active
   and x.product_id in(select v::uuid from jsonb_array_elements_text(p_data->'product_ids')v) order by p.name,x.id limit 60)s),'[]');
 elsif p_action='options' then
  return coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('product_name',p.name,'optional_name',op.name)) from private.sales_product_options x join public.products p on p.id=x.product_id join public.products op on op.id=x.optional_product_id),'[]');
 elsif p_action='context' then
  return jsonb_build_object('commercial_lines',case when qid is null then '[]'::jsonb else private.coco_sales_quote_commercial_lines(qid) end,
   'discount',case when qid is null then null else (select to_jsonb(d) from private.sales_quote_discount_policies d where quote_id=qid) end,
   'freight_rules',(select coalesce(jsonb_agg(to_jsonb(x) order by name),'[]') from private.sales_freight_rules x where active or private.current_user_role()='administrador'),
   'expenses',case when oid is not null and private.erp_module_allowed('expenses',array['administrador','comercial'])
    and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false) then
    (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'reference',x.reference,'description',x.description,'amount',x.amount_untaxed) order by x.expense_date desc),'[]') from public.expenses x
     join private.expense_claims claim on claim.id=x.id where x.status='posted' and claim.status in ('approved','paid')
     and not exists(select 1 from private.sales_expense_rebills rb where rb.expense_id=x.id)) else '[]'::jsonb end,
   'rebills',(select coalesce(jsonb_agg(to_jsonb(b)-'cost'),'[]') from private.sales_expense_rebills b where b.sales_order_id=oid));
 end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into rec from private.sales_commercial_receipts where request_key=key for update;
 if found then if rec.actor_id<>auth.uid() or rec.payload<>jsonb_build_object('action',p_action,'data',p_data) then raise exception 'REQUEST_KEY_REUSED';end if;return rec.response;end if;
 if qid is not null then select * into q from public.invoices where id=qid for update;
  if q.quote_state<>'draft' or exists(select 1 from public.sales_orders where source_quote_id=qid) then raise exception 'QUOTE_LOCKED';end if;
  if q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
 end if;
 if oid is not null then select * into o from public.sales_orders where id=oid for update;if o.status='cancelled' then raise exception 'ORDER_CANCELLED';end if;end if;
 if p_action='discount_save' then
  if qid is null or p_data->>'mode' not in ('fixed','percent') or (p_data->>'amount')::numeric is null or (p_data->>'amount')::numeric::text in ('NaN','Infinity','-Infinity')
   or (p_data->>'amount')::numeric<0 or (p_data->>'mode'='percent' and (p_data->>'amount')::numeric>100) then raise exception 'INVALID_ADJUSTMENT';end if;
  insert into private.sales_quote_discount_policies(quote_id,mode,amount,description,updated_by) values(qid,p_data->>'mode',(p_data->>'amount')::numeric,coalesce(nullif(btrim(p_data->>'description'),''),'Descuento global'),auth.uid())
   on conflict(quote_id) do update set mode=excluded.mode,amount=excluded.amount,description=excluded.description,updated_by=excluded.updated_by,updated_at=now() returning * into policy;
  select case when policy.mode='percent' then round(sum(line_total)*policy.amount/100,2) else policy.amount end into amount from public.invoice_lines where invoice_id=qid;
  result:=private.coco_sales_adjustment_apply(qid,'discount',amount,policy.description,policy.source_id);
 elsif p_action='freight_rule_save' then
  if private.current_user_role()<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
  target:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
  select * into r from private.sales_freight_rules where id=target for update;
  if found and r.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  insert into private.sales_freight_rules(id,name,pricing,fixed_price,base_price,per_kg,per_m3,per_km,free_over,tax_rate,tax_ids,active,updated_by)
  values(target,p_data->>'name',p_data->>'pricing',coalesce((p_data->>'fixed_price')::numeric,0),coalesce((p_data->>'base_price')::numeric,0),coalesce((p_data->>'per_kg')::numeric,0),coalesce((p_data->>'per_m3')::numeric,0),coalesce((p_data->>'per_km')::numeric,0),nullif(p_data->>'free_over','')::numeric,coalesce((p_data->>'tax_rate')::numeric,0),case when p_data ? 'tax_ids' then array(select v::uuid from jsonb_array_elements_text(p_data->'tax_ids')v) end,coalesce((p_data->>'active')::boolean,true),auth.uid())
  on conflict(id) do update set name=excluded.name,pricing=excluded.pricing,fixed_price=excluded.fixed_price,base_price=excluded.base_price,per_kg=excluded.per_kg,per_m3=excluded.per_m3,per_km=excluded.per_km,free_over=excluded.free_over,tax_rate=excluded.tax_rate,tax_ids=excluded.tax_ids,active=excluded.active,version=sales_freight_rules.version+1,updated_by=excluded.updated_by,updated_at=now();
  result:=jsonb_build_object('id',target);
 elsif p_action='freight_apply' then
  if (qid is null)=(oid is null) then raise exception 'SOURCE_REQUIRED';end if;
  source:=(p_data->>'rule_id')::uuid;select * into r from private.sales_freight_rules where id=source and active;if not found then raise exception 'FREIGHT_RULE_NOT_FOUND';end if;
  fee:=private.coco_sales_freight_amount(source,qid,oid,coalesce((p_data->>'distance_km')::numeric,0));amount:=(fee->>'amount')::numeric;
  if qid is not null then
   delete from private.sales_quote_commercial_lines where quote_id=qid and kind='freight';
   insert into private.sales_quote_commercial_lines(quote_id,kind,source_id,description,quantity,unit_price,tax_rate,tax_ids,metadata,updated_by)
    values(qid,'freight',source,r.name,1,amount,r.tax_rate,r.tax_ids,fee,auth.uid());
   perform private.coco_sales_quote_retotal(qid);update public.invoices set quote_revision=quote_revision+1,updated_at=now() where id=qid returning * into q;
   result:=fee||jsonb_build_object('id',qid,'revision',q.quote_revision);
  else
   if exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id where ol.order_id=oid and ol.line_kind='freight') then raise exception 'FREIGHT_ALREADY_INVOICED';end if;
   if exists(select 1 from public.sales_order_lines where order_id=oid and line_kind in ('discount','reward') and commercial_scope='freight') then raise exception 'REWARD_REVIEW_REQUIRED';end if;
   delete from private.sales_dossier_lines where order_line_id in(select id from public.sales_order_lines where order_id=oid and line_kind='freight');
   delete from public.sales_order_lines where order_id=oid and line_kind='freight';
   insert into public.sales_order_lines(order_id,product_name,quantity,unit_price,tax_rate,tax_ids,line_kind,commercial_source_id,commercial_metadata)
    values(oid,r.name,1,amount,r.tax_rate,r.tax_ids,'freight',source,fee) returning id into line;
   update private.sales_dossier_lines set invoice_policy='ordered' where order_line_id=line;
   result:=fee||jsonb_build_object('id',line,'order_id',oid);
  end if;
 elsif p_action='expense_rebill' then
  if oid is null or not private.erp_module_allowed('expenses',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  perform private.business_require('expenses','view');perform private.commercial_require('view');
  select * into e from public.expenses where id=(p_data->>'expense_id')::uuid for update;select * into c from private.expense_claims where id=e.id for update;
  if e.id is null or e.status<>'posted' or c.status not in ('approved','paid') or not exists(select 1 from public.accounting_entries where source_type='expense' and source_id=e.id and status='posted') then raise exception 'APPROVED_EXPENSE_REQUIRED';end if;
  if exists(select 1 from private.sales_expense_rebills where expense_id=e.id) then raise exception 'EXPENSE_ALREADY_REBILLED';end if;
  if e.currency is distinct from (select currency from public.company_settings where id) then raise exception 'CURRENCY_MISMATCH';end if;
  if p_data->>'policy' not in ('cost','sale_price') then raise exception 'INVALID_REBILL_POLICY';end if;
  amount:=case when p_data->>'policy'='cost' then e.amount_untaxed else (p_data->>'sale_price')::numeric end;
  if amount is null or amount::text in ('NaN','Infinity','-Infinity') or amount<0 or amount>=100000000 or amount<>round(amount,2) then raise exception 'INVALID_AMOUNT';end if;
  source:=gen_random_uuid();
  insert into public.sales_order_lines(order_id,product_name,reference,quantity,unit_price,tax_rate,tax_ids,line_kind,commercial_source_id,commercial_metadata)
   values(oid,left('Refacturación · '||e.description,500),e.reference,1,amount,coalesce((p_data->>'tax_rate')::numeric,0),case when p_data ? 'tax_ids' then array(select v::uuid from jsonb_array_elements_text(p_data->'tax_ids')v) end,'expense_rebill',source,jsonb_build_object('expense_id',e.id,'policy',p_data->>'policy')) returning id into line;
  update private.sales_dossier_lines set invoice_policy='ordered' where order_line_id=line;
  insert into private.sales_expense_rebills(id,expense_id,sales_order_id,order_line_id,policy,cost,sale_price,created_by) values(source,e.id,oid,line,p_data->>'policy',e.amount_untaxed,amount,auth.uid());
  insert into private.order_cost_snapshots(line_id,unit_cost) values(line,e.amount_untaxed);
  result:=jsonb_build_object('id',source,'order_line_id',line,'order_id',oid,'amount',amount);
 elsif p_action='option_save' then
  if private.current_user_role()<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not exists(select 1 from public.products where id=(p_data->>'product_id')::uuid and active) or not exists(select 1 from public.products where id=(p_data->>'optional_product_id')::uuid and active) then raise exception 'PRODUCT_NOT_FOUND';end if;
  insert into private.sales_product_options(product_id,optional_product_id,relation,quantity,active,updated_by) values((p_data->>'product_id')::uuid,(p_data->>'optional_product_id')::uuid,p_data->>'relation',(p_data->>'quantity')::numeric,coalesce((p_data->>'active')::boolean,true),auth.uid())
   on conflict(product_id,optional_product_id) do update set relation=excluded.relation,quantity=excluded.quantity,active=excluded.active,updated_by=excluded.updated_by,updated_at=now() returning id into target;
  result:=jsonb_build_object('id',target);
 else raise exception 'INVALID_ACTION';end if;
 insert into private.sales_commercial_receipts(request_key,actor_id,payload,response) values(key,auth.uid(),jsonb_build_object('action',p_action,'data',p_data),result);
 return result;
end $$;
create function public.coco_sales_commercial(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_sales_commercial(p_action,p_data)$$;

do $$declare t text;begin foreach t in array array['sales_quote_commercial_lines','sales_quote_discount_policies','sales_freight_rules','sales_expense_rebills','sales_product_options','sales_commercial_receipts'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 if t<>'sales_commercial_receipts' then
  insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values(t,case when t='sales_expense_rebills' then 'sales-orders' else 'quotes' end,'Condición comercial','private',case when t='sales_quote_discount_policies' then 'quote_id' else 'id' end);
  execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
 end if;
end loop;end $$;
do $$declare src text;begin
 select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) into src;
 execute replace(src,'FUNCTION private.coco_history_record_visible(','FUNCTION private.coco_history_record_visible_before_commercial(');
end $$;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in ('sales_quote_commercial_lines','sales_quote_discount_policies','sales_freight_rules','sales_product_options') then return private.coco_module_allowed('quotes');end if;
 if p_table='sales_expense_rebills' then return private.coco_module_allowed('sales-orders');end if;
 return private.coco_history_record_visible_before_commercial(p_table,p_id,p_owner);
end $$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and
 (p.proname like 'coco_sales_commercial%' or p.proname in ('coco_sales_quote_commercial_lines','coco_sales_quote_retotal','coco_sales_adjustment_apply','coco_sales_freight_amount','coco_sales_order_line_net','sales_line_entitlement_before_commercial','gama_quote_action_before_commercial','gama_sales_dossier_before_commercial')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);end loop;
end $$;
revoke all on function private.gama_quote_action(text,jsonb),private.gama_sales_dossier(text,jsonb),private.sales_line_entitlement(uuid),private.gama_return_amount(uuid),private.gama_return_amount_before_commercial(uuid),private.coco_sales_return_unit(uuid,uuid),
 private.sales_quote_fingerprint(uuid),private.sales_quote_review(uuid),private.sales_quote_fingerprint_before_commercial(uuid),private.sales_quote_review_before_commercial(uuid),
 private.coco_history_record_visible_before_commercial(text,text,uuid),public.coco_sales_commercial(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.coco_history_record_visible_before_commercial(text,text,uuid),private.coco_sales_commercial(text,jsonb),public.coco_sales_commercial(text,jsonb),private.gama_quote_action(text,jsonb),private.gama_sales_dossier(text,jsonb),private.gama_return_amount(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
