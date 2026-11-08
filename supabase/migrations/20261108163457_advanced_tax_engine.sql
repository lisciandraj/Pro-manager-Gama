-- Native exact-decimal tax rules, immutable calculations and fiscal positions.
-- This is opt-in for named taxes; existing percentage-only documents are retained.
alter table public.accounting_taxes
 add column calculation_type text not null default 'percent' check(calculation_type in('percent','fixed')),
 add column fixed_amount numeric(18,4) not null default 0 check(fixed_amount>=0 and fixed_amount<100000000),
 add column price_included boolean not null default false,
 add column sequence integer not null default 10 check(sequence between 0 and 10000),
 add column include_base_amount boolean not null default false;
alter table public.company_settings add column tax_rounding text not null default 'line' check(tax_rounding in('line','global'));
create table private.coco_fiscal_positions(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 active boolean not null default true,country text check(country ~ '^[A-Z]{2}$'),
 version integer not null default 1 check(version>0),created_by uuid not null default auth.uid() references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table private.coco_fiscal_tax_rules(
 id uuid primary key default gen_random_uuid(),position_id uuid not null references private.coco_fiscal_positions(id) on delete cascade,
 source_tax_id uuid not null references public.accounting_taxes(id),target_tax_id uuid references public.accounting_taxes(id),
 unique(position_id,source_tax_id),check(source_tax_id is distinct from target_tax_id)
);
create table private.coco_fiscal_account_rules(
 id uuid primary key default gen_random_uuid(),position_id uuid not null references private.coco_fiscal_positions(id) on delete cascade,
 source_account_id uuid not null references public.accounting_accounts(id),target_account_id uuid not null references public.accounting_accounts(id),
 unique(position_id,source_account_id),check(source_account_id<>target_account_id)
);
create table private.coco_partner_fiscal_positions(
 id uuid primary key default gen_random_uuid(),side text not null check(side in('sale','purchase')),partner_id uuid not null,
 position_id uuid not null references private.coco_fiscal_positions(id),unique(side,partner_id)
);
alter table private.coco_fiscal_positions enable row level security;
alter table private.coco_fiscal_tax_rules enable row level security;
alter table private.coco_fiscal_account_rules enable row level security;
alter table private.coco_partner_fiscal_positions enable row level security;
revoke all on private.coco_fiscal_positions,private.coco_fiscal_tax_rules,private.coco_fiscal_account_rules,private.coco_partner_fiscal_positions from public,anon,authenticated,service_role;
alter table public.invoices add column if not exists tax_fiscal_position_id uuid references private.coco_fiscal_positions(id),add column if not exists tax_rounding text check(tax_rounding in('line','global')),add column if not exists tax_calculation jsonb;
alter table public.sales_orders add column if not exists tax_fiscal_position_id uuid references private.coco_fiscal_positions(id),add column if not exists tax_rounding text check(tax_rounding in('line','global')),add column if not exists tax_calculation jsonb;
alter table public.invoice_lines add column if not exists tax_ids uuid[],add column if not exists tax_snapshot jsonb;
alter table public.sales_order_lines add column if not exists tax_ids uuid[],add column if not exists tax_snapshot jsonb;
alter table public.supplier_invoices add column if not exists tax_calculation jsonb;
alter table public.expenses add column if not exists tax_calculation jsonb;

create function private.coco_tax_number(p_value jsonb) returns numeric
language plpgsql immutable security invoker set search_path='' as $$declare n numeric;begin
 if p_value is null or p_value='null'::jsonb or length(p_value::text)>80 then raise exception 'TAX_NUMBER_INVALID';end if;
 begin n:=(p_value#>>'{}')::numeric;exception when others then raise exception 'TAX_NUMBER_INVALID';end;
 if n::text in('NaN','Infinity','-Infinity') or abs(n)>=1e16 then raise exception 'TAX_NUMBER_INVALID';end if;return n;
end $$;
-- Pure arithmetic over frozen rules. No tax master data, current rates or accounts
-- are looked up here, so early-payment adjustments can reproduce an issued piece.
create function private.coco_tax_calculate_frozen(p_lines jsonb,p_rounding text default 'line') returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
#variable_conflict use_column
declare item jsonb;r jsonb;rules jsonb;components jsonb;stage jsonb:='[]';outlines jsonb;aggregated jsonb;
 qty numeric;price numeric;discount numeric;factor numeric;tqty numeric;direction numeric;entered numeric;
 coefficient numeric;constant numeric;a numeric;b numeric;inc_a numeric;inc_b numeric;rate numeric;fixed numeric;
 rawbase numeric;base numeric;taxamount numeric;taxsum numeric;sub numeric;total_sub numeric;total_tax numeric;kind text;legacy boolean;idx integer:=0;included_left integer;included_sum numeric;included_percent integer;residual numeric;li bigint;ti bigint;adjustment numeric;component_row record;
begin
 if p_rounding not in('line','global') or p_rounding is null then raise exception 'TAX_ROUNDING_INVALID';end if;
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 1000 then raise exception 'TAX_LINES_INVALID';end if;
 for item in select value from jsonb_array_elements(p_lines) loop
  idx:=idx+1;qty:=private.coco_tax_number(item->'quantity');price:=private.coco_tax_number(coalesce(item->'entered_unit_price',item->'unit_price'));
  discount:=private.coco_tax_number(coalesce(item->'discount','0'));factor:=private.coco_tax_number(coalesce(item->'tax_base_factor','1'));
  tqty:=private.coco_tax_number(coalesce(item->'tax_quantity',item->'quantity'));
  if qty<=0 or qty>=100000000 or qty<>round(qty,3) or abs(price)>=100000000 or discount not between 0 and 100 or factor not between 0 and 1 or tqty<0 or tqty>qty then raise exception 'TAX_LINES_INVALID';end if;
  direction:=case when price<0 then -1 else 1 end;rules:=coalesce(item->'rules','[]');
  if coalesce((item->>'force_price_excluded')::boolean,false) then select coalesce(jsonb_agg(value||jsonb_build_object('price_included',false) order by ordinality),'[]') into rules from jsonb_array_elements(rules) with ordinality;end if;
  if jsonb_typeof(rules) is distinct from 'array' or jsonb_array_length(rules)>30 then raise exception 'TAX_RULES_INVALID';end if;
  coefficient:=1;constant:=0;inc_a:=0;inc_b:=0;legacy:=jsonb_array_length(rules)=1 and coalesce((rules#>>'{0,legacy}')::boolean,false);
  for r in select value from jsonb_array_elements(rules) order by coalesce((value->>'sequence')::integer,10),coalesce(value->>'id',value->>'code','') loop
   kind:=coalesce(r->>'calculation_type','percent');rate:=private.coco_tax_number(coalesce(r->'rate','0'));fixed:=private.coco_tax_number(coalesce(r->'fixed_amount','0'));
   if kind not in('percent','fixed') or rate<0 or rate>100 or fixed<0 or fixed>=100000000 then raise exception 'TAX_RULES_INVALID';end if;
   if kind='fixed' then a:=0;b:=tqty*fixed*direction;else a:=coefficient*rate/100;b:=constant*rate/100;end if;
   if coalesce((r->>'price_included')::boolean,false) then inc_a:=inc_a+a;inc_b:=inc_b+b;end if;
   if coalesce((r->>'include_base_amount')::boolean,false) then coefficient:=coefficient+a;constant:=constant+b;end if;
  end loop;
  entered:=qty*price*(1-discount/100);
  rawbase:=(entered-inc_b)/(1+inc_a);
  if direction>=0 and rawbase<0 then raise exception 'TAX_INCLUDED_PRICE_TOO_LOW';end if;
  if legacy then rawbase:=round(qty*round(price*(1-discount/100),4),2);end if;
  sub:=round(rawbase,2);
  select count(*) filter(where coalesce((r->>'price_included')::boolean,false)),count(*) filter(where coalesce((r->>'price_included')::boolean,false) and coalesce(r->>'calculation_type','percent')='percent') into included_left,included_percent from jsonb_array_elements(rules)r;
  if p_rounding='line' and factor=1 and included_left>0 then select coalesce(sum(round(tqty*(r->>'fixed_amount')::numeric*direction,2)),0) into residual from jsonb_array_elements(rules)r where coalesce((r->>'price_included')::boolean,false) and r->>'calculation_type'='fixed';if direction>=0 and round(entered,2)<residual then raise exception 'TAX_INCLUDED_PRICE_TOO_LOW';end if;if included_percent=0 then sub:=round(entered,2)-residual;elsif direction>=0 then sub:=least(sub,round(entered,2)-residual);else sub:=greatest(sub,round(entered,2)-residual);end if;end if;
  included_sum:=0;base:=(case when p_rounding='line' or legacy then sub else rawbase end)*factor;components:='[]';taxsum:=0;
  for r in select value from jsonb_array_elements(rules) order by coalesce((value->>'sequence')::integer,10),coalesce(value->>'id',value->>'code','') loop
   kind:=coalesce(r->>'calculation_type','percent');rate:=private.coco_tax_number(coalesce(r->'rate','0'));fixed:=private.coco_tax_number(coalesce(r->'fixed_amount','0'));
   taxamount:=case when kind='fixed' then tqty*fixed*direction else base*rate/100 end;
   if p_rounding='line' and factor=1 and coalesce((r->>'price_included')::boolean,false) then
    if kind='percent' then included_percent:=included_percent-1;select coalesce(sum(round(tqty*(later.value->>'fixed_amount')::numeric*direction,2)),0) into residual from jsonb_array_elements(rules) later where coalesce((later.value->>'price_included')::boolean,false) and later.value->>'calculation_type'='fixed' and (coalesce((later.value->>'sequence')::integer,10),coalesce(later.value->>'id',later.value->>'code',''))>(coalesce((r->>'sequence')::integer,10),coalesce(r->>'id',r->>'code',''));residual:=round(entered,2)-sub-included_sum-residual;if included_percent=0 then taxamount:=residual;elsif direction>=0 then taxamount:=greatest(0,least(round(taxamount,2),residual));else taxamount:=least(0,greatest(round(taxamount,2),residual));end if;end if;
    included_sum:=included_sum+round(taxamount,2);
   end if;
   components:=components||jsonb_build_array(r||jsonb_build_object('base_unrounded',base,'base',round(base,2),'amount_unrounded',taxamount,'amount',round(taxamount,2),
    'group_key',jsonb_build_array(r->'id',r->'code',kind,rate,fixed,r->'account_id')::text));
   if p_rounding='line' then taxamount:=round(taxamount,2);end if;
   taxsum:=taxsum+taxamount;if coalesce((r->>'include_base_amount')::boolean,false) then base:=base+taxamount;end if;
  end loop;
  if abs(rawbase)+abs(taxsum)>=1e15 then raise exception 'TAX_AMOUNT_OUT_OF_RANGE';end if;
  stage:=stage||jsonb_build_array(item||jsonb_build_object('key',coalesce(item->>'key',idx::text),'quantity',qty,'entered_unit_price',price,'discount',discount,'tax_quantity',tqty,'tax_base_factor',factor,
   'net_unit_price',round(rawbase/qty,12),'subtotal_unrounded',rawbase,'subtotal',sub,'rules',rules,'taxes',components));
 end loop;
 if p_rounding='global' then
  -- Allocate currency residuals deterministically; allocations always sum to the
  -- rounded global base and each tax/account total, including credit lines.
  with rows as(select value obj,ordinality i,(value->>'subtotal_unrounded')::numeric raw,(value->>'subtotal')::numeric rounded from jsonb_array_elements(stage) with ordinality),
   delta as(select round(sum(raw),2)-sum(rounded) d from rows),
   ranked as(select rows.*,d,row_number() over(order by case when d>=0 then raw-rounded else rounded-raw end desc,i) rank from rows cross join delta)
  select jsonb_agg(obj||jsonb_build_object('subtotal',rounded+case when rank<=round(abs(d)*100) then sign(d)*.01 else 0 end) order by i) into stage from ranked;
  with amounts as(select l.ordinality li,t.ordinality ti,t.value obj,t.value->>'group_key' g,(t.value->>'amount_unrounded')::numeric raw,round((t.value->>'amount_unrounded')::numeric,2) rounded from jsonb_array_elements(stage) with ordinality l cross join lateral jsonb_array_elements(l.value->'taxes') with ordinality t),
   deltas as(select g,round(sum(raw),2)-sum(rounded) d from amounts group by g),
   ranked as(select amounts.*,d,row_number() over(partition by amounts.g order by case when d>=0 then raw-rounded else rounded-raw end desc,li,ti) rank from amounts join deltas using(g)),
   revised as(select li,jsonb_agg(obj||jsonb_build_object('amount',rounded+case when rank<=round(abs(d)*100) then sign(d)*.01 else 0 end) order by ti) taxes from ranked group by li)
  select jsonb_agg(l.value||jsonb_build_object('taxes',coalesce(r.taxes,'[]')) order by l.ordinality) into stage from jsonb_array_elements(stage) with ordinality l left join revised r on r.li=l.ordinality;
 end if;
 if p_rounding='global' then
  with eligible as(select l.value obj,l.ordinality li from jsonb_array_elements(stage) with ordinality l where (l.value->>'tax_base_factor')::numeric=1 and exists(select 1 from jsonb_array_elements(l.value->'taxes')t where coalesce((t->>'price_included')::boolean,false)))
  select round(sum((obj->>'quantity')::numeric*(obj->>'entered_unit_price')::numeric*(1-(obj->>'discount')::numeric/100)),2)-sum((obj->>'subtotal')::numeric)-coalesce(sum((select coalesce(sum((t->>'amount')::numeric),0) from jsonb_array_elements(obj->'taxes')t where coalesce((t->>'price_included')::boolean,false))),0) into residual from eligible;
  if coalesce(residual,0)<>0 then
   select l.ordinality,t.ordinality into li,ti from jsonb_array_elements(stage) with ordinality l cross join lateral jsonb_array_elements(l.value->'taxes') with ordinality t where (l.value->>'tax_base_factor')::numeric=1 and coalesce((t.value->>'price_included')::boolean,false) and t.value->>'calculation_type'='percent' order by abs((t.value->>'amount')::numeric) desc,l.ordinality desc,t.ordinality desc limit 1;
   if found then
    for component_row in select l.ordinality li,t.ordinality ti,(t.value->>'amount')::numeric amount from jsonb_array_elements(stage) with ordinality l cross join lateral jsonb_array_elements(l.value->'taxes') with ordinality t where (l.value->>'tax_base_factor')::numeric=1 and coalesce((t.value->>'price_included')::boolean,false) and t.value->>'calculation_type'='percent' order by abs((t.value->>'amount')::numeric) desc,l.ordinality desc,t.ordinality desc loop
     adjustment:=case when residual>=0 then residual else -least(-residual,greatest(component_row.amount,0)) end;
     stage:=jsonb_set(stage,array[(component_row.li-1)::text,'taxes',(component_row.ti-1)::text,'amount'],to_jsonb(component_row.amount+adjustment));residual:=residual-adjustment;exit when residual=0;
    end loop;
    if residual<>0 then raise exception 'TAX_INCLUDED_ROUNDING_INVALID';end if;
   else select l.ordinality into li from jsonb_array_elements(stage) with ordinality l where (l.value->>'tax_base_factor')::numeric=1 and exists(select 1 from jsonb_array_elements(l.value->'taxes')t where coalesce((t->>'price_included')::boolean,false)) order by l.ordinality desc limit 1;stage:=jsonb_set(stage,array[(li-1)::text,'subtotal'],to_jsonb((stage#>>array[(li-1)::text,'subtotal'])::numeric+residual));end if;
  end if;
 end if;
 select jsonb_agg(l.value||jsonb_build_object('net_unit_price',round((l.value->>'subtotal')::numeric/(l.value->>'quantity')::numeric,12),'tax',coalesce((select sum((t->>'amount')::numeric) from jsonb_array_elements(l.value->'taxes')t),0),
  'total',(l.value->>'subtotal')::numeric+coalesce((select sum((t->>'amount')::numeric) from jsonb_array_elements(l.value->'taxes')t),0)) order by l.ordinality) into outlines from jsonb_array_elements(stage) with ordinality l;
 select coalesce(sum((x->>'subtotal')::numeric),0),coalesce(sum((x->>'tax')::numeric),0) into total_sub,total_tax from jsonb_array_elements(outlines)x;
 select coalesce(jsonb_agg(obj||jsonb_build_object('amount',amount,'base',base) order by obj->>'code',obj->>'id'),'[]') into aggregated
 from(select (array_agg(t order by l.ordinality))[1]-'base_unrounded'-'amount_unrounded'-'group_key' obj,sum((t->>'amount')::numeric) amount,round(sum((t->>'base_unrounded')::numeric),2) base
  from jsonb_array_elements(outlines) with ordinality l cross join lateral jsonb_array_elements(l.value->'taxes')t group by t->>'group_key')g;
 return jsonb_build_object('schema','coco.tax.v1','rounding',p_rounding,'subtotal',total_sub,'tax',total_tax,'total',total_sub+total_tax,'lines',outlines,'taxes',aggregated);
end $$;
create function private.coco_tax_recompute_snapshot(p_calculation jsonb,p_factor numeric) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$declare lines jsonb;begin
 if p_calculation->>'schema'<>'coco.tax.v1' or p_factor is null or p_factor::text in('NaN','Infinity','-Infinity') or p_factor not between 0 and 1 then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 select jsonb_agg(value||jsonb_build_object('tax_base_factor',p_factor) order by ordinality) into lines from jsonb_array_elements(p_calculation->'lines') with ordinality;
 return private.coco_tax_calculate_frozen(lines,p_calculation->>'rounding')||jsonb_build_object('fiscal_position_id',p_calculation->'fiscal_position_id','side',p_calculation->'side','date',p_calculation->'date');
end $$;

create function private.coco_tax_compute(p_side text,p_partner uuid,p_date date,p_lines jsonb,p_fiscal_position uuid default null,p_rounding text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare tax_side text;position uuid:=p_fiscal_position;item jsonb;rule jsonb;rules jsonb;prepared jsonb:='[]';tid uuid;mapped uuid;ids uuid[];seen uuid[];tax public.accounting_taxes;cfg public.company_settings;aid uuid;newaid uuid;result jsonb;rounding text;rate numeric;begin
 tax_side:=case when p_side in('sale','customer') then 'sale' when p_side in('purchase','supplier') then 'purchase' else null end;
 if tax_side is null or p_date is null then raise exception 'TAX_CONTEXT_INVALID';end if;
 select * into cfg from public.company_settings where id;rounding:=coalesce(p_rounding,cfg.tax_rounding,'line');
 if position is null and p_partner is not null then select position_id into position from private.coco_partner_fiscal_positions where coco_partner_fiscal_positions.side=tax_side and partner_id=p_partner;end if;
 if position is not null and not exists(select 1 from private.coco_fiscal_positions where id=position and active) then raise exception 'FISCAL_POSITION_INVALID';end if;
 if jsonb_typeof(p_lines) is distinct from 'array' then raise exception 'TAX_LINES_INVALID';end if;
 for item in select value from jsonb_array_elements(p_lines) loop
  aid:=nullif(item->>'account_id','')::uuid;
  if aid is null then
   if to_regprocedure('private.coco_product_account(text,uuid)') is not null then execute 'select private.coco_product_account($1,$2)' into aid using tax_side,nullif(item->>'product_id','')::uuid;
   else aid:=case when tax_side='sale' then cfg.sales_account_id else cfg.purchase_account_id end;end if;
  end if;
  if position is not null then select target_account_id into newaid from private.coco_fiscal_account_rules where position_id=position and source_account_id=aid;if found then aid:=newaid;end if;end if;
  if not exists(select 1 from public.accounting_accounts where id=aid and active and type=case when tax_side='sale' then 'income' else 'expense' end) then raise exception 'TAX_BASE_ACCOUNT_INVALID';end if;
  rules:='[]';seen:='{}';
  if item ? 'tax_ids' and item->'tax_ids'<>'null'::jsonb then
   if jsonb_typeof(item->'tax_ids') is distinct from 'array' or jsonb_array_length(item->'tax_ids')>30 then raise exception 'TAX_RULES_INVALID';end if;
   for tid in select value::uuid from jsonb_array_elements_text(item->'tax_ids') loop
    mapped:=tid;
    if position is not null then select target_tax_id into mapped from private.coco_fiscal_tax_rules where position_id=position and source_tax_id=tid;if not found then mapped:=tid;end if;end if;
    if mapped is null or mapped=any(seen) then continue;end if;seen:=array_append(seen,mapped);
    select * into tax from public.accounting_taxes where id=mapped;
    if not found or not tax.active or (tax.valid_from is not null and p_date<tax.valid_from) or (tax.valid_to is not null and p_date>tax.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
    if tax.kind not in('both',case when tax_side='sale' then 'collected' else 'deductible' end) then raise exception 'TAX_KIND_INVALID';end if;
    newaid:=case when tax_side='sale' then tax.collected_account_id else tax.deductible_account_id end;
    if position is not null then select target_account_id into aid from private.coco_fiscal_account_rules where position_id=position and source_account_id=newaid;if found then newaid:=aid;end if;end if;
    if not exists(select 1 from public.accounting_accounts where id=newaid and active and type=case when tax_side='sale' then 'liability' else 'asset' end) then raise exception 'TAX_ACCOUNT_INVALID';end if;
    rules:=rules||jsonb_build_array(to_jsonb(tax)||jsonb_build_object('account_id',newaid));
   end loop;
  else
   rate:=private.coco_tax_number(coalesce(item->'tax_rate','0'));
   if rate<0 or rate>100 then raise exception 'TAX_RATE_INVALID';end if;
   newaid:=case when tax_side='sale' then cfg.tax_collected_account_id else cfg.tax_deductible_account_id end;
   if position is not null then select target_account_id into mapped from private.coco_fiscal_account_rules where position_id=position and source_account_id=newaid;if found then newaid:=mapped;end if;end if;
   if rate<>0 and not exists(select 1 from public.accounting_accounts where id=newaid and active and type=case when tax_side='sale' then 'liability' else 'asset' end) then raise exception 'TAX_ACCOUNT_INVALID';end if;
   rules:=jsonb_build_array(jsonb_build_object('id',null,'code','LEGACY-'||trim_scale(rate),'rate',rate,'fixed_amount',0,'kind',case when tax_side='sale' then 'collected' else 'deductible' end,'calculation_type','percent','price_included',false,'sequence',10,'include_base_amount',false,'account_id',newaid,'legacy',true));
  end if;
  -- Re-resolve the base account after tax-account mapping, keeping the two roles separate.
  aid:=nullif(item->>'account_id','')::uuid;
  if aid is null then if to_regprocedure('private.coco_product_account(text,uuid)') is not null then execute 'select private.coco_product_account($1,$2)' into aid using tax_side,nullif(item->>'product_id','')::uuid;else aid:=case when tax_side='sale' then cfg.sales_account_id else cfg.purchase_account_id end;end if;end if;
  if position is not null then select target_account_id into newaid from private.coco_fiscal_account_rules where position_id=position and source_account_id=aid;if found then aid:=newaid;end if;end if;
  prepared:=prepared||jsonb_build_array(item||jsonb_build_object('rules',rules,'account_id',aid));
 end loop;
 result:=private.coco_tax_calculate_frozen(prepared,rounding);
 return result||jsonb_build_object('side',tax_side,'date',p_date,'fiscal_position_id',position);
end $$;
revoke all on function private.coco_tax_number(jsonb),private.coco_tax_calculate_frozen(jsonb,text),private.coco_tax_recompute_snapshot(jsonb,numeric),private.coco_tax_compute(text,uuid,date,jsonb,uuid,text) from public,anon,authenticated,service_role;

-- Extend the existing tax command itself, preserving its actor-bound receipt and
-- single optimistic version update instead of layering a second mutation.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.gama_accounting_tax_save(jsonb)'::regprocedure);
 anchor:='collected uuid;deductible uuid;next_version integer;';if strpos(s,anchor)=0 then raise exception 'ADVANCED_TAX_SAVE_ANCHOR';end if;
 s:=replace(s,anchor,anchor||'calc text;fixed numeric;included boolean;seq integer;compound boolean;');
 anchor:='if kind not in (''collected'',''deductible'',''both'') then raise exception ''TAX_KIND_INVALID'';end if;';
 if strpos(s,anchor)=0 then raise exception 'ADVANCED_TAX_KIND_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$body$
 calc:=coalesce(nullif(p_data->>'calculation_type',''),old_tax.calculation_type,'percent');
 fixed:=case when p_data ? 'fixed_amount' then private.coco_tax_number(p_data->'fixed_amount') else coalesce(old_tax.fixed_amount,0) end;
 included:=coalesce((p_data->>'price_included')::boolean,old_tax.price_included,false);
 seq:=coalesce((p_data->>'sequence')::integer,old_tax.sequence,10);compound:=coalesce((p_data->>'include_base_amount')::boolean,old_tax.include_base_amount,false);
 if calc not in('percent','fixed') or fixed<0 or fixed>=100000000 or fixed<>round(fixed,4) or seq not between 0 and 10000 then raise exception 'TAX_RULES_INVALID';end if;
 $body$);
 anchor:='insert into public.accounting_taxes(name,code,rate,kind,country,valid_from,valid_to,collected_account_id,deductible_account_id,active)';
 if strpos(s,anchor)=0 then raise exception 'ADVANCED_TAX_INSERT_ANCHOR';end if;
 s:=replace(s,anchor,'insert into public.accounting_taxes(name,code,rate,kind,country,valid_from,valid_to,collected_account_id,deductible_account_id,active,calculation_type,fixed_amount,price_included,sequence,include_base_amount)');
 s:=replace(s,'values(nm,code,rate,kind,country,starts,ends,collected,deductible,enabled)','values(nm,code,rate,kind,country,starts,ends,collected,deductible,enabled,calc,fixed,included,seq,compound)');
 anchor:='collected_account_id=collected,deductible_account_id=deductible,active=enabled,version=old_tax.version+1';
 if strpos(s,anchor)=0 then raise exception 'ADVANCED_TAX_UPDATE_ANCHOR';end if;
 s:=replace(s,anchor,'collected_account_id=collected,deductible_account_id=deductible,active=enabled,calculation_type=calc,fixed_amount=fixed,price_included=included,sequence=seq,include_base_amount=compound,version=old_tax.version+1');execute s;
end $$;
create function private.coco_tax_access(p_write boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_accounting_rights();
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((r->>'view')::boolean,false) or r->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_write and (not coalesce((r->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit')) then raise exception 'NOT_ALLOWED';end if;
 return r;
end $$;
create function private.coco_tax_engine(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare rights jsonb;result jsonb;side text;key uuid;old private.command_receipts;pid uuid;fp private.coco_fiscal_positions;item jsonb;sid uuid;tid uuid;aid uuid;bid uuid;partner uuid;new_country text;taxrules jsonb;accountrules jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_action in('context','preview') then
  side:=coalesce(p_data->>'side','sale');if side in('customer','sale') then side:='sale';perform private.sales_access('quote');
  elsif side in('supplier','purchase') then side:='purchase';perform private.coco_tax_access(false);else raise exception 'TAX_CONTEXT_INVALID';end if;
  if p_action='context' then
   return jsonb_build_object('rounding',(select tax_rounding from public.company_settings where id),
    'taxes',coalesce((select jsonb_agg(to_jsonb(t)-'collected_account_id'-'deductible_account_id' order by sequence,code) from public.accounting_taxes t where active and kind in('both',case when side='sale' then 'collected' else 'deductible' end)),'[]'),
    'positions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'country',country) order by name,id) from private.coco_fiscal_positions where active),'[]'));
  end if;
  result:=private.coco_tax_compute(side,nullif(p_data->>'partner_id','')::uuid,coalesce(nullif(p_data->>'date','')::date,(now() at time zone private.erp_timezone())::date),p_data->'lines',nullif(p_data->>'fiscal_position_id','')::uuid,nullif(p_data->>'rounding',''));
  return result;
 end if;
 rights:=private.coco_tax_access(p_action not in('config','tax_save'));
 if p_action='config' then
  return jsonb_build_object('rights',rights,'rounding',(select tax_rounding from public.company_settings where id),
   'taxes',coalesce((select jsonb_agg(to_jsonb(t) order by sequence,code) from public.accounting_taxes t),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'type',type,'active',active) order by code) from public.accounting_accounts),'[]'),
   'positions',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('tax_rules',coalesce((select jsonb_agg(to_jsonb(r) order by id) from private.coco_fiscal_tax_rules r where position_id=f.id),'[]'),'account_rules',coalesce((select jsonb_agg(to_jsonb(r) order by id) from private.coco_fiscal_account_rules r where position_id=f.id),'[]')) order by name,id) from private.coco_fiscal_positions f),'[]'),
   'assignments',coalesce((select jsonb_agg(to_jsonb(a) order by side,partner_id) from private.coco_partner_fiscal_positions a),'[]'),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name,id) from public.customers where active),'[]'),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name,id) from public.suppliers),'[]'));
 end if;
 if p_action='tax_save' then return private.gama_accounting_tax_save(p_data);end if;
 if p_action not in('position_save','assignment_save','rounding_save') then raise exception 'UNKNOWN_ACTION';end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('tax-config:'||key,0));
 select * into old from private.command_receipts where domain='tax-config:'||p_action and request_key=key;
 if found then if old.actor_id<>auth.uid() or old.payload<>p_data-'request_key' then raise exception 'REQUEST_KEY_CONFLICT';end if;return old.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('coco-tax-configuration',0));
 if p_action='rounding_save' then
  if p_data->>'rounding' not in('line','global') or p_data->>'rounding' is null then raise exception 'TAX_ROUNDING_INVALID';end if;
  update public.company_settings set tax_rounding=p_data->>'rounding' where id;result:=jsonb_build_object('ok',true);
 elsif p_action='assignment_save' then
  side:=p_data->>'side';partner:=nullif(p_data->>'partner_id','')::uuid;pid:=nullif(p_data->>'position_id','')::uuid;
  if side not in('sale','purchase') or partner is null then raise exception 'TAX_CONTEXT_INVALID';end if;
  if not(case when side='sale' then exists(select 1 from public.customers where id=partner) else exists(select 1 from public.suppliers where id=partner) end) then raise exception 'PARTNER_NOT_FOUND';end if;
  if pid is not null and not exists(select 1 from private.coco_fiscal_positions where id=pid and active) then raise exception 'FISCAL_POSITION_INVALID';end if;
  if pid is null then delete from private.coco_partner_fiscal_positions where coco_partner_fiscal_positions.side=(p_data->>'side') and partner_id=partner;
  else insert into private.coco_partner_fiscal_positions(side,partner_id,position_id) values(side,partner,pid) on conflict(side,partner_id) do update set position_id=excluded.position_id;end if;
  result:=jsonb_build_object('ok',true);
 else
  pid:=nullif(p_data->>'id','')::uuid;new_country:=nullif(upper(btrim(p_data->>'country')),'');
  if length(btrim(coalesce(p_data->>'name',''))) not between 1 and 120 or (new_country is not null and new_country !~ '^[A-Z]{2}$') then raise exception 'FISCAL_POSITION_INVALID';end if;
  taxrules:=coalesce(p_data->'tax_rules','[]');accountrules:=coalesce(p_data->'account_rules','[]');
  if jsonb_typeof(taxrules) is distinct from 'array' or jsonb_typeof(accountrules) is distinct from 'array' or jsonb_array_length(taxrules)>100 or jsonb_array_length(accountrules)>100 then raise exception 'FISCAL_RULES_INVALID';end if;
  if pid is not null then
   select * into fp from private.coco_fiscal_positions where id=pid for update;
   if not found then raise exception 'FISCAL_POSITION_INVALID';end if;
   if (p_data->>'version')::integer is distinct from fp.version then raise exception 'FISCAL_POSITION_CHANGED';end if;
   update private.coco_fiscal_positions set name=btrim(p_data->>'name'),country=new_country,active=coalesce((p_data->>'active')::boolean,true),version=version+1,updated_at=now() where id=pid;
  else insert into private.coco_fiscal_positions(name,country,active) values(btrim(p_data->>'name'),new_country,coalesce((p_data->>'active')::boolean,true)) returning id into pid;end if;
  delete from private.coco_fiscal_tax_rules where position_id=pid;delete from private.coco_fiscal_account_rules where position_id=pid;
  for item in select value from jsonb_array_elements(taxrules) loop
   sid:=(item->>'source_tax_id')::uuid;tid:=nullif(item->>'target_tax_id','')::uuid;
   if not exists(select 1 from public.accounting_taxes where id=sid) or (tid is not null and not exists(select 1 from public.accounting_taxes where id=tid and active)) or sid=tid then raise exception 'FISCAL_RULES_INVALID';end if;
   insert into private.coco_fiscal_tax_rules(position_id,source_tax_id,target_tax_id) values(pid,sid,tid);
  end loop;
  for item in select value from jsonb_array_elements(accountrules) loop
   aid:=(item->>'source_account_id')::uuid;bid:=(item->>'target_account_id')::uuid;
   if not exists(select 1 from public.accounting_accounts a join public.accounting_accounts b on b.id=bid and b.type=a.type and b.active where a.id=aid) or aid=bid then raise exception 'FISCAL_RULES_INVALID';end if;
   insert into private.coco_fiscal_account_rules(position_id,source_account_id,target_account_id) values(pid,aid,bid);
  end loop;
  result:=jsonb_build_object('id',pid,'version',(select version from private.coco_fiscal_positions where id=pid));
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tax-config:'||p_action,key,auth.uid(),p_data-'request_key',result);return result;
end $$;
create function public.coco_tax_engine(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_tax_engine(p_action,p_data)$$;
revoke all on function private.coco_tax_access(boolean),private.coco_tax_engine(text,jsonb),public.coco_tax_engine(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_tax_engine(text,jsonb),public.coco_tax_engine(text,jsonb) to authenticated;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('coco_fiscal_positions','accounting','Posición fiscal','private','id'),('coco_fiscal_tax_rules','accounting','Sustitución de impuesto','private','id'),
 ('coco_fiscal_account_rules','accounting','Sustitución contable','private','id'),('coco_partner_fiscal_positions','accounting','Posición fiscal del contacto','private','id');
create trigger coco_module_history after insert or update or delete on private.coco_fiscal_positions for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.coco_fiscal_tax_rules for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.coco_fiscal_account_rules for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.coco_partner_fiscal_positions for each row execute function private.coco_capture_module_event();
do $$begin
 execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_tax_engine(');
 execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_tax_engine(');
end $$;
revoke all on function private.coco_history_record_visible_before_tax_engine(text,text,uuid),private.coco_history_typed_link_before_tax_engine(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_tax_engine(text,text,uuid),private.coco_history_typed_link_before_tax_engine(text,text,text,text) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in('coco_fiscal_positions','coco_fiscal_tax_rules','coco_fiscal_account_rules','coco_partner_fiscal_positions') then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_tax_engine(p_table,p_id,p_owner);
end $$;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language sql immutable security invoker set search_path='' as $$
 select case when p_table in('coco_fiscal_positions','coco_fiscal_tax_rules','coco_fiscal_account_rules','coco_partner_fiscal_positions') then jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_configuration','tab','tax_rules')
 else private.coco_history_typed_link_before_tax_engine(p_module,p_table,p_id,p_reference) end
$$;

-- Keep named quote rules on the canonical commercial lines. Acceptance freezes
-- these snapshots and invoice creation below resolves the issue-date rules anew.
alter function private.gama_quote_action(text,jsonb) rename to gama_quote_action_before_tax_engine;
revoke all on function private.gama_quote_action_before_tax_engine(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_quote_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;q public.invoices;x jsonb;cl jsonb;ls jsonb;calc jsonb;position uuid;rounding text;existing_creation boolean:=false;begin
 if p_action='save' and nullif(p_data->>'id','') is null then perform pg_advisory_xact_lock(741932,1);select exists(select 1 from public.invoices where quote_request_key=nullif(p_data->>'request_key','')::uuid) into existing_creation;end if;
 r:=private.gama_quote_action_before_tax_engine(p_action,p_data);if existing_creation then return r;end if;
 if p_action='save' then
  select * into q from public.invoices where id=(r->>'id')::uuid;
  if q.quote_state='draft' then
   position:=case when p_data ? 'tax_fiscal_position_id' then nullif(p_data->>'tax_fiscal_position_id','')::uuid else q.tax_fiscal_position_id end;
   rounding:=case when p_data ? 'tax_rounding' then nullif(p_data->>'tax_rounding','') else q.tax_rounding end;
   for x in select value from jsonb_array_elements(p_data->'lines') loop
    update public.invoice_lines set tax_ids=case when x ? 'tax_ids' and x->'tax_ids'<>'null'::jsonb then array(select value::uuid from jsonb_array_elements_text(x->'tax_ids')) end
     where invoice_id=q.id and product_id=(x->>'product_id')::uuid;
   end loop;
   select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('key',l.id,'product_id',l.product_id,'quantity',l.quantity,'unit_price',l.quote_list_price,'discount',l.quote_discount,'tax_rate',l.tax_rate,'tax_ids',to_jsonb(l.tax_ids))) order by l.id) into ls from public.invoice_lines l where l.invoice_id=q.id;
   calc:=private.coco_tax_compute('sale',q.customer_id,(q.issue_date at time zone private.erp_timezone())::date,ls,position,rounding);
   for cl in select value from jsonb_array_elements(calc->'lines') loop
    update public.invoice_lines set unit_price=round((cl->>'net_unit_price')::numeric,4),line_total=(cl->>'subtotal')::numeric,tax_snapshot=cl where id=(cl->>'key')::uuid;
   end loop;
   update public.invoices set tax_fiscal_position_id=position,tax_rounding=calc->>'rounding',tax_calculation=calc,subtotal=(calc->>'subtotal')::numeric,tax=(calc->>'tax')::numeric,total=(calc->>'total')::numeric where id=q.id;
   if to_regprocedure('private.coco_sales_quote_retotal(uuid)') is not null then execute 'select private.coco_sales_quote_retotal($1)' using q.id;end if;
  end if;
 end if;
 return r;
end $$;
revoke all on function private.gama_quote_action(text,jsonb) from public,anon,service_role;grant execute on function private.gama_quote_action(text,jsonb) to authenticated;
alter function private.sales_quote_fingerprint(uuid) rename to sales_quote_fingerprint_before_tax_engine;
revoke all on function private.sales_quote_fingerprint_before_tax_engine(uuid) from public,anon,authenticated,service_role;
create function private.sales_quote_fingerprint(p_quote uuid) returns text language sql stable security definer set search_path='' as $$
 select md5(private.sales_quote_fingerprint_before_tax_engine(p_quote)||coalesce(q.tax_calculation::text,'')) from public.invoices q where id=p_quote
$$;
revoke all on function private.sales_quote_fingerprint(uuid) from public,anon,authenticated,service_role;
create function private.coco_sales_order_tax_freeze() returns trigger language plpgsql security definer set search_path='' as $$
declare q public.invoices;begin
 if tg_table_name='sales_orders' then
  select * into q from public.invoices where id=new.source_quote_id;
  if found then new.tax_fiscal_position_id:=q.tax_fiscal_position_id;new.tax_rounding:=q.tax_rounding;new.tax_calculation:=q.tax_calculation;end if;
 else
  select q0.* into q from public.invoices q0 join public.sales_orders o on o.source_quote_id=q0.id where o.id=new.order_id;
  if q.id is not null then
   if new.product_id is not null then select tax_ids,tax_snapshot into new.tax_ids,new.tax_snapshot from public.invoice_lines where invoice_id=q.id and product_id=new.product_id;
   elsif to_jsonb(new)->>'commercial_source_id' is not null then
    select value into new.tax_snapshot from jsonb_array_elements(q.tax_calculation->'lines') where value->>'key'=coalesce(to_jsonb(new)#>>'{commercial_metadata,quote_commercial_line_id}',to_jsonb(new)->>'commercial_source_id');
   end if;
  end if;
 end if;return new;
end $$;
create trigger coco_sales_order_tax_freeze before insert on public.sales_orders for each row execute function private.coco_sales_order_tax_freeze();
create trigger coco_sales_order_tax_freeze before insert on public.sales_order_lines for each row execute function private.coco_sales_order_tax_freeze();
revoke all on function private.coco_sales_order_tax_freeze() from public,anon,authenticated,service_role;

-- The preview and mutation share this preparation, including the exact selected
-- quantities of commercial discounts. A changed accepted tax needs confirmation.
create function private.coco_sales_invoice_tax_prepare(p_data jsonb,p_items jsonb default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare ids uuid[];customer uuid;position uuid;rounding text;issue date;line public.sales_order_lines;o public.sales_orders;x jsonb;cl jsonb;qty numeric;available numeric;raw jsonb:='[]';previous jsonb:='[]';items jsonb:='[]';calc jsonb;oldcalc jsonb;one jsonb;frozen jsonb;changed boolean:=false;factor numeric;begin
 select array_agg(distinct value::uuid order by value::uuid) into ids from jsonb_array_elements_text(p_data->'order_ids');
 if ids is null or cardinality(ids) not between 1 and 30 then raise exception 'INVALID_ORDERS';end if;
 issue:=coalesce(nullif(p_data->>'issue_date','')::date,(now() at time zone private.erp_timezone())::date);
 if issue>(now() at time zone private.erp_timezone())::date then raise exception 'INVALID_DATE';end if;
 if (select count(*) from public.sales_orders where id=any(ids) and status='confirmed')<>cardinality(ids) then raise exception 'CONFIRM_ORDER_FIRST';end if;
 if (select count(distinct customer_id) from public.sales_orders where id=any(ids))<>1 then raise exception 'CUSTOMER_MISMATCH';end if;
 if (select count(distinct coalesce(tax_fiscal_position_id::text,'')||':'||coalesce(tax_rounding,'line')) from public.sales_orders where id=any(ids))<>1 then raise exception 'TAX_GROUP_CONFIGURATION_MISMATCH';end if;
 select * into o from public.sales_orders where id=ids[1];customer:=o.customer_id;position:=o.tax_fiscal_position_id;rounding:=coalesce(o.tax_rounding,'line');
 for line in select * from public.sales_order_lines where order_id=any(ids) order by order_id,id loop
  if p_items is not null then select value into x from jsonb_array_elements(p_items) where value->>'line_id'=line.id::text;qty:=coalesce((x->>'qty')::numeric,0);
  else
   select greatest(0,coalesce(private.sales_line_entitlement(line.id),0)-coalesce(sum(il.quantity),0)) into available from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=line.id and i.fiscal_status not in('cancelled','rejected');
   if p_data ? 'lines' then select value into x from jsonb_array_elements(p_data->'lines') where value->>'line_id'=line.id::text;qty:=coalesce((x->>'quantity')::numeric,0);else qty:=available;end if;
   if coalesce(to_jsonb(line)->>'line_kind','product') in('discount','reward') and to_regprocedure('private.coco_sales_commercial_invoice_quantity(uuid,jsonb)') is not null then execute 'select private.coco_sales_commercial_invoice_quantity($1,$2)' into factor using line.id,p_data;if factor is not null then qty:=factor;end if;end if;
   if qty<0 or qty<>round(qty,3) or qty>available then raise exception 'EXCEEDS_UNBILLED';end if;
   x:=jsonb_build_object('line_id',line.id,'order_id',line.order_id,'product_id',line.product_id,'name',line.product_name,'reference',line.reference,'qty',qty,'price',line.unit_price,'listPrice',line.unit_price,'discount',0,'taxRate',line.tax_rate);
  end if;
  if qty=0 then continue;end if;
  one:=jsonb_strip_nulls(jsonb_build_object('key',line.id,'product_id',line.product_id,'quantity',qty,'unit_price',coalesce((line.tax_snapshot->>'entered_unit_price')::numeric,line.unit_price),'discount',coalesce((line.tax_snapshot->>'discount')::numeric,0),'tax_rate',line.tax_rate,'tax_ids',to_jsonb(line.tax_ids),'tax_quantity',case when coalesce(to_jsonb(line)->>'line_kind','product') in('discount','reward') then 0 else qty end,'force_price_excluded',coalesce(to_jsonb(line)->>'line_kind','product')<>'product','line_kind',coalesce(to_jsonb(line)->>'line_kind','product')));
  raw:=raw||jsonb_build_array(one);
  if line.tax_snapshot->'rules' is not null then frozen:=one||jsonb_build_object('rules',line.tax_snapshot->'rules','account_id',line.tax_snapshot->'account_id');
  else frozen:=private.coco_tax_compute('sale',customer,issue,jsonb_build_array(one),position,rounding)#>'{lines,0}';end if;
  previous:=previous||jsonb_build_array(frozen);items:=items||jsonb_build_array(x);
 end loop;
 if raw='[]'::jsonb then raise exception 'NO_DELIVERED_UNBILLED';end if;
 calc:=private.coco_tax_compute('sale',customer,issue,raw,position,rounding);oldcalc:=private.coco_tax_calculate_frozen(previous,rounding);
 -- Account substitutions may change ledger allocation without changing the price;
 -- tax definitions, included-price behavior and money are the reviewed terms.
 select exists(select 1 from jsonb_array_elements(calc->'lines') n join jsonb_array_elements(oldcalc->'lines') old on old->>'key'=n->>'key' where
  (select jsonb_agg(r-'account_id'-'created_at'-'updated_at'-'version'-'active'-'valid_from'-'valid_to' order by r->>'id') from jsonb_array_elements(n->'rules')r)
   is distinct from (select jsonb_agg(r-'account_id'-'created_at'-'updated_at'-'version'-'active'-'valid_from'-'valid_to' order by r->>'id') from jsonb_array_elements(old->'rules')r)
  or n->'subtotal' is distinct from old->'subtotal' or n->'tax' is distinct from old->'tax') into changed;
 select jsonb_agg(x.value||jsonb_build_object('subtotal',c.value->'subtotal','tax',c.value->'tax','price',case when round((x.value->>'qty')::numeric*round((c.value->>'net_unit_price')::numeric,6),2)=(c.value->>'subtotal')::numeric then to_jsonb(round((c.value->>'net_unit_price')::numeric,6)) else c.value->'net_unit_price' end,'taxRate',case when jsonb_array_length(c.value->'taxes')=0 then '0'::jsonb when jsonb_array_length(c.value->'taxes')=1 and c.value#>>'{taxes,0,calculation_type}'='percent' then to_jsonb(trim_scale((c.value#>>'{taxes,0,rate}')::numeric)) else 'null'::jsonb end,'tax_snapshot',c.value) order by x.ordinality) into items from jsonb_array_elements(items) with ordinality x join jsonb_array_elements(calc->'lines') c on c.value->>'key'=x.value->>'line_id';
 if p_items is not null and exists(select 1 from jsonb_array_elements(p_items)d where coalesce((d->>'is_deposit_deduction')::boolean,false)) then
  if exists(select 1 from jsonb_array_elements(raw)r where r ? 'tax_ids') then raise exception 'ADVANCED_TAX_DEPOSIT_REVIEW_REQUIRED';end if;
  -- Existing legacy deposits retain their frozen amounts and liability handling.
  for x in select value from jsonb_array_elements(p_items)d where coalesce((d->>'is_deposit_deduction')::boolean,false) loop
   items:=items||jsonb_build_array(x);calc:=calc||jsonb_build_object('subtotal',(calc->>'subtotal')::numeric+(x->>'subtotal')::numeric,'tax',(calc->>'tax')::numeric+(x->>'tax')::numeric,'total',(calc->>'total')::numeric+(x->>'subtotal')::numeric+(x->>'tax')::numeric);
  end loop;
  calc:=calc||jsonb_build_object('legacy_deposit_deductions',true);
 end if;
 if (calc->>'total')::numeric<0 then raise exception 'INVOICE_TOTAL_INVALID';end if;
 return jsonb_build_object('calculation',calc,'previous_calculation',oldcalc,'items',items,'tax_rules_changed',changed,'confirmation_key',md5(calc::text));
end $$;
revoke all on function private.coco_sales_invoice_tax_prepare(jsonb,jsonb) from public,anon,authenticated,service_role;
do $$declare s text;a text;begin
 s:=pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure);
 a:='links uuid[];';if strpos(s,a)=0 then raise exception 'TAX_INVOICE_DECLARATION_ANCHOR';end if;s:=replace(s,a,'links uuid[];taxprep jsonb;taxcalc jsonb;');
 a:='select jsonb_agg(jsonb_build_object(''id'',id,''number'',number,''quote_id'',source_quote_id) order by id) into orders';
 if strpos(s,a)=0 then raise exception 'TAX_INVOICE_COMPUTE_ANCHOR';end if;
 s:=replace(s,a,$body$taxprep:=private.coco_sales_invoice_tax_prepare(p_data,items);taxcalc:=taxprep->'calculation';
 if (taxprep->>'tax_rules_changed')::boolean and p_data->>'tax_confirmation' is distinct from taxprep->>'confirmation_key' then raise exception 'TAX_RULES_CHANGED' using detail=taxprep::text;end if;
 items:=taxprep->'items';s:=(taxcalc->>'subtotal')::numeric;t:=(taxcalc->>'tax')::numeric;
 $body$||a);
 a:='jsonb_build_object(''sales_schema'',''coco.sales.invoice.v2'',''company''';if strpos(s,a)=0 then raise exception 'TAX_INVOICE_SNAPSHOT_ANCHOR';end if;
 s:=replace(s,a,'jsonb_build_object(''sales_schema'',''coco.sales.invoice.v2'',''tax_calculation'',taxcalc,''company''');execute s;
end $$;
-- Keep the public RPC stable and route the additional preview through the same
-- authenticated sales gate. No anonymous or service-role path is introduced.
alter function private.coco_tax_engine(text,jsonb) rename to coco_tax_engine_before_sales_tax;
revoke all on function private.coco_tax_engine_before_sales_tax(text,jsonb) from public,anon,authenticated,service_role;
create function private.coco_tax_engine(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action='invoice_preview' then perform private.sales_access('invoice_create');return private.coco_sales_invoice_tax_prepare(p_data);end if;
 return private.coco_tax_engine_before_sales_tax(p_action,p_data);
end $$;
revoke all on function private.coco_tax_engine(text,jsonb) from public,anon,service_role;grant execute on function private.coco_tax_engine(text,jsonb) to authenticated;

create function private.coco_purchase_tax_prepare(p_data jsonb,p_expense boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ls jsonb;calc jsonb;item jsonb;tid uuid;net numeric;tax numeric;category_account uuid;factor numeric:=1;begin
 if p_data#>>'{early_discount,tax_reduction}'='always' then factor:=1-private.coco_tax_number(p_data#>'{early_discount,percent}')/100;if factor<=0 or factor>=1 then raise exception 'EARLY_DISCOUNT_TERMS_INVALID';end if;end if;
 if p_data ? 'lines' then
  ls:=p_data->'lines';if jsonb_typeof(ls) is distinct from 'array' or jsonb_array_length(ls) not between 1 and 200 then raise exception 'TAX_LINES_INVALID';end if;
  if exists(select 1 from jsonb_array_elements(ls)x where private.coco_tax_number(x->'unit_price')<0 or x ? 'account_id' or x ? 'rules' or x ? 'force_price_excluded') then raise exception 'TAX_LINES_INVALID';end if;
  select jsonb_agg(value||jsonb_build_object('tax_base_factor',factor) order by ordinality) into ls from jsonb_array_elements(ls) with ordinality;
 else
  net:=private.coco_tax_number(coalesce(p_data->case when p_expense then 'amount_untaxed' else 'subtotal' end,'0'));
  tax:=private.coco_tax_number(coalesce(p_data->case when p_expense then 'tax_amount' else 'tax' end,'0'));
  if net<0 or tax<0 then raise exception 'TAX_LINES_INVALID';end if;
  item:=jsonb_build_object('key','summary','quantity',1,'unit_price',net,'discount',0,'tax_base_factor',factor);
  if p_data ? 'tax_ids' and p_data->'tax_ids'<>'null'::jsonb then item:=item||jsonb_build_object('tax_ids',p_data->'tax_ids');
  elsif nullif(p_data->>'tax_id','') is not null then item:=item||jsonb_build_object('tax_ids',jsonb_build_array((p_data->>'tax_id')::uuid));
  else
   if net=0 and tax<>0 or net>0 and tax/net>1 then return null;end if;
   item:=item||jsonb_build_object('tax_rate',case when net=0 then 0 else tax/net*100 end);
  end if;ls:=jsonb_build_array(item);
 end if;
 if p_expense then select account_id into category_account from public.expense_categories where id=nullif(p_data->>'category_id','')::uuid;if category_account is null then select id into category_account from public.accounting_accounts where code='6140' and active;end if;if category_account is not null then select jsonb_agg(value||jsonb_build_object('account_id',category_account) order by ordinality) into ls from jsonb_array_elements(ls) with ordinality;end if;end if;
 calc:=private.coco_tax_compute('purchase',nullif(p_data->>'supplier_id','')::uuid,(p_data->>case when p_expense then 'expense_date' else 'issue_date' end)::date,ls,nullif(p_data->>'tax_fiscal_position_id','')::uuid,nullif(p_data->>'tax_rounding',''));
 if (calc->>'total')::numeric<=0 then raise exception 'INVOICE_TOTAL_INVALID';end if;return calc;
end $$;
revoke all on function private.coco_purchase_tax_prepare(jsonb,boolean) from public,anon,authenticated,service_role;
do $$declare s text;a text;begin
 s:=pg_get_functiondef('private.gama_accounting_banking(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 a:='declare eid uuid;';if strpos(s,a)=0 then raise exception 'PURCHASE_TAX_DECLARATION_ANCHOR';end if;s:=replace(s,a,'declare taxcalc jsonb;eid uuid;');
 a:='insert into public.supplier_invoices(number,supplier_id,purchase_order_id,issue_date,payment_terms_days,';
 if strpos(s,a)=0 then raise exception 'PURCHASE_TAX_INSERT_ANCHOR';end if;
 s:=replace(s,a,$body$taxcalc:=private.coco_purchase_tax_prepare(p_data,false);
 if taxcalc is not null then p_data:=p_data||jsonb_build_object('subtotal',taxcalc->'subtotal','tax',taxcalc->'tax','total',taxcalc->'total');end if;
 $body$||a);
 s:=replace(s,'due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by,deferral_lines)','due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by,deferral_lines,tax_calculation)');
 a:='coalesce(p_data->''deferral_lines'',''[]''::jsonb)) returning id into eid;';if strpos(s,a)=0 then raise exception 'PURCHASE_TAX_VALUES_ANCHOR';end if;s:=replace(s,a,'coalesce(p_data->''deferral_lines'',''[]''::jsonb),taxcalc) returning id into eid;');
 a:='return jsonb_build_object(''id'',eid,''entry'',private.gama_accounting_post(''supplier_invoice'',eid));';
 if strpos(s,a)=0 then raise exception 'PURCHASE_TAX_BIND_ANCHOR';end if;
 s:=replace(s,a,$body$if p_data->'early_discount' is not null and p_data->'early_discount'<>'null'::jsonb then
  if to_regprocedure('private.coco_early_discount_bind(uuid,text,jsonb)') is null then raise exception 'EARLY_DISCOUNT_UNAVAILABLE';end if;
  execute 'select private.coco_early_discount_bind($1,$2,$3)' using eid,'supplier',p_data->'early_discount';
 end if;
 $body$||a);execute s;
 s:=pg_get_functiondef('private.gama_accounting_expenses(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 a:='declare result jsonb;';if strpos(s,a)=0 then raise exception 'EXPENSE_TAX_DECLARATION_ANCHOR';end if;s:=replace(s,a,'declare taxcalc jsonb;result jsonb;');
 a:='if eid is null then'||chr(10)||'   if not may_create then';if strpos(s,a)=0 then raise exception 'EXPENSE_TAX_PREPARE_ANCHOR';end if;
 s:=replace(s,a,$body$taxcalc:=private.coco_purchase_tax_prepare(p_data,true);
  if taxcalc is not null then p_data:=p_data||jsonb_build_object('amount_untaxed',taxcalc->'subtotal','tax_amount',taxcalc->'tax','amount_total',taxcalc->'total');end if;
  $body$||a);
 a:='financial_account_id,project_id,notes,request_key,created_by)';if strpos(s,a)=0 then raise exception 'EXPENSE_TAX_INSERT_ANCHOR';end if;s:=replace(s,a,'financial_account_id,project_id,notes,request_key,created_by,tax_calculation)');
 a:='p_data->>''notes'',key,u) returning id into eid;';if strpos(s,a)=0 then raise exception 'EXPENSE_TAX_VALUES_ANCHOR';end if;s:=replace(s,a,'p_data->>''notes'',key,u,taxcalc) returning id into eid;');
 a:='project_id=nullif(p_data->>''project_id'','''')::uuid,notes=p_data->>''notes'',updated_at=now() where id=eid;';if strpos(s,a)=0 then raise exception 'EXPENSE_TAX_UPDATE_ANCHOR';end if;
 s:=replace(s,a,'project_id=nullif(p_data->>''project_id'','''')::uuid,notes=p_data->>''notes'',tax_calculation=taxcalc,updated_at=now() where id=eid;');execute s;
end $$;

-- Trust only server-persisted arithmetic snapshots, and keep archived tax IDs on
-- issued invoices, reversals and their persisted credit/early-payment corrections.
create or replace function private.gama_purchase_tax_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.accounting_taxes;d date;calc jsonb;checkcalc jsonb;net numeric;tax numeric;begin
 calc:=new.tax_calculation;
 if calc is not null then
  if calc->>'schema' is distinct from 'coco.tax.v1' then raise exception 'TAX_SNAPSHOT_INVALID';end if;
  checkcalc:=private.coco_tax_calculate_frozen(calc->'lines',calc->>'rounding');
  if tg_table_name='expenses' then net:=new.amount_untaxed;tax:=new.tax_amount;else net:=new.subtotal;tax:=new.tax;end if;
  if (checkcalc->>'subtotal')::numeric<>net or (checkcalc->>'tax')::numeric<>tax or calc->'taxes' is distinct from checkcalc->'taxes' then raise exception 'TAX_SNAPSHOT_INVALID';end if;
  if tg_op='UPDATE' and old.status<>'draft' and old.tax_calculation is distinct from calc then raise exception 'TAX_SNAPSHOT_IMMUTABLE';end if;
  return new;
 end if;
 if new.tax_id is null or new.status not in('draft','posted') then return new;end if;
 if tg_table_name='expenses' then d:=new.expense_date;else d:=new.issue_date;end if;
 select * into t from public.accounting_taxes where id=new.tax_id;
 if not found or not t.active or (t.valid_from is not null and d<t.valid_from) or (t.valid_to is not null and d>t.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
 if t.kind not in('deductible','both') then raise exception 'TAX_KIND_INVALID';end if;
 if tg_table_name='expenses' then if new.tax_amount<>round(new.amount_untaxed*t.rate/100,2) then raise exception 'TAX_AMOUNT_INVALID';end if;
 else if new.tax<>round(new.subtotal*t.rate/100,2) then raise exception 'TAX_AMOUNT_INVALID';end if;end if;
 if not exists(select 1 from public.accounting_accounts where id=t.deductible_account_id and active and type='asset') then raise exception 'TAX_DEDUCTIBLE_ACCOUNT_INVALID';end if;return new;
end $$;
create or replace function private.gama_ec_line_tax_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;t public.accounting_taxes;d date;calc jsonb;begin
 if new.tax_id is null then return new;end if;select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='reversal' then return new;end if;
 if e.source_type='supplier_invoice' then select tax_calculation into calc from public.supplier_invoices where id=e.source_id;
 elsif e.source_type='expense' then select tax_calculation into calc from public.expenses where id=e.source_id;
 elsif e.source_type='sales_invoice' then select document_snapshot->'tax_calculation' into calc from public.external_invoices where id=e.source_id;
 elsif e.source_type='adjustment' and exists(select 1 from information_schema.columns where table_schema='public' and table_name='accounting_adjustments' and column_name='tax_calculation') then execute 'select tax_calculation from public.accounting_adjustments where id=$1' into calc using e.source_id;end if;
 if calc is not null then
  if exists(select 1 from jsonb_array_elements(coalesce(calc->'taxes','[]')) x where x->>'id'=new.tax_id::text and x->>'account_id'=new.account_id::text and abs((x->>'amount')::numeric)=abs(new.debit-new.credit)) then return new;end if;
  raise exception 'TAX_SNAPSHOT_LINE_INVALID';
 end if;
 d:=e.entry_date;if e.source_type='supplier_invoice' then select issue_date into d from public.supplier_invoices where id=e.source_id;elsif e.source_type='expense' then select expense_date into d from public.expenses where id=e.source_id;end if;
 select * into t from public.accounting_taxes where id=new.tax_id;
 if not found or not t.active or (t.valid_from is not null and d<t.valid_from) or (t.valid_to is not null and d>t.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
 if e.source_type in('expense','supplier_invoice') then
  if t.kind not in('deductible','both') then raise exception 'TAX_KIND_INVALID';end if;
  if not exists(select 1 from public.accounting_accounts where id=t.deductible_account_id and active and type='asset') then raise exception 'TAX_DEDUCTIBLE_ACCOUNT_INVALID';end if;new.account_id:=t.deductible_account_id;
 end if;return new;
end $$;
revoke all on function private.gama_purchase_tax_guard(),private.gama_ec_line_tax_guard() from public,anon,authenticated,service_role;
