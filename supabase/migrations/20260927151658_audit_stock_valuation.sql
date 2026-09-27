-- Opt-in perpetual valuation. Existing products retain their labelled standard-cost estimate.
-- An opening records the quantity/cost observed at activation, never a reconstructed earlier history.
create table public.stock_cost_books(
 product_id uuid primary key references public.products(id),method text not null check(method in ('fifo','avco')),
 quantity numeric(24,9) not null check(quantity>=0),value numeric(24,6) not null check(value>=0),
 started_at timestamptz not null default now(),created_by uuid not null references auth.users(id),
 stock_account_id uuid references public.accounting_accounts(id),expense_account_id uuid references public.accounting_accounts(id)
);
create table public.stock_cost_layers(
 id uuid primary key default gen_random_uuid(),product_id uuid not null references public.stock_cost_books(product_id),
 movement_id uuid unique references public.stock_movements(id) deferrable initially deferred,
 quantity numeric(24,9) not null check(quantity>0),remaining numeric(24,9) not null check(remaining>=0 and remaining<=quantity),
 unit_cost numeric(24,9) not null check(unit_cost>=0),created_at timestamptz not null default now(),opening boolean not null default false
);
create index cost_layers_fifo on public.stock_cost_layers(product_id,created_at,id) where remaining>0;
create table public.stock_landed_costs(
 id uuid primary key default gen_random_uuid(),request_key uuid not null unique,source_reference text not null unique check(length(btrim(source_reference))>=3),
 amount numeric(18,6) not null check(amount<>0),currency text not null default 'USD' check(currency='USD'),
 allocation text not null check(allocation in ('quantity','value','weight')),reason text not null check(length(btrim(reason))>=3),
 created_at timestamptz not null default now(),created_by uuid not null references auth.users(id)
);
create table public.stock_landed_allocations(
 landed_cost_id uuid not null references public.stock_landed_costs(id),layer_id uuid not null references public.stock_cost_layers(id),
 amount numeric(24,6) not null,stock_value numeric(24,6) not null,consumed_value numeric(24,6) not null,
 primary key(landed_cost_id,layer_id),check(amount=stock_value+consumed_value)
);
create table public.stock_valuation_entries(
 sequence bigint generated always as identity primary key,product_id uuid not null references public.stock_cost_books(product_id),
 movement_id uuid unique references public.stock_movements(id) deferrable initially deferred,
 landed_cost_id uuid references public.stock_landed_costs(id),kind text not null check(kind in ('opening','in','out','transfer','landed','method')),
 quantity numeric(24,9) not null,value_delta numeric(24,6) not null,expense_delta numeric(24,6) not null default 0,
 quantity_after numeric(24,9) not null,value_after numeric(24,6) not null,method text not null,
 source text not null,created_at timestamptz not null default now(),created_by uuid references auth.users(id)
);
create index valuation_product_date on public.stock_valuation_entries(product_id,created_at,sequence);
create index valuation_landed on public.stock_valuation_entries(landed_cost_id);
create index valuation_actor on public.stock_valuation_entries(created_by);
create index valuation_layer_alloc on public.stock_landed_allocations(layer_id);
create index valuation_book_actor on public.stock_cost_books(created_by);
create index valuation_book_stock_account on public.stock_cost_books(stock_account_id);
create index valuation_book_expense_account on public.stock_cost_books(expense_account_id);
create index valuation_landed_actor on public.stock_landed_costs(created_by);
create table private.stock_valuation_commands(request_key uuid primary key,actor uuid not null,action text not null,payload jsonb not null,result jsonb not null);
revoke all on private.stock_valuation_commands from public,anon,authenticated;
do $$declare tbl text;begin
 foreach tbl in array array['stock_cost_books','stock_cost_layers','stock_landed_costs','stock_landed_allocations','stock_valuation_entries'] loop
 execute format('alter table public.%I enable row level security',tbl);
 execute format('revoke all on public.%I from public,anon,authenticated',tbl);
 execute format('grant select on public.%I to authenticated',tbl);
 execute format('create policy valuation_read on public.%I for select to authenticated using(private.erp_module_allowed(''accounting'',array[''administrador'',''comercial'']) and coalesce((private.gama_accounting_rights()->>''view'')::boolean,false) and private.gama_accounting_rights()->>''scope''=''all'')',tbl);
 end loop;
end $$;

create function private.erp_cost_post(m public.stock_movements) returns numeric language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare b public.stock_cost_books;l public.stock_cost_layers;qty numeric:=abs(m.quantity);v numeric:=0;cost numeric:=coalesce(m.unit_cost_at_movement,0);take numeric;leftqty numeric;newqty numeric;newvalue numeric;kind text;src text:='movement';
begin
 select * into b from public.stock_cost_books where product_id=m.product_id for update;
 if not found then return cost;end if;
 if m.source_location_id is not null and m.destination_location_id is not null then kind:='transfer';qty:=0;
 elsif m.source_location_id is null and m.destination_location_id is not null then
  kind:='in';
  if m.reference_type='customer_return' then
   -- Restore the recorded shipment cost, not today's catalogue cost. Old shipments remain explicitly estimated.
   select sum(sm.quantity*sm.unit_cost_at_movement)/nullif(sum(sm.quantity),0) into take from public.stock_movements sm
    where sm.product_id=m.product_id and sm.reference_type='sales_delivery' and sm.reference_id in
     (select dl.delivery_id from public.return_lines rl join public.sales_delivery_lines dl on dl.id=rl.delivery_line_id where rl.return_id=m.reference_id and rl.product_id=m.product_id);
   if take is not null then cost:=take;src:='original_shipment';else src:='return_estimated_standard';end if;
  end if;
  v:=round(qty*cost,6);
  insert into public.stock_cost_layers(product_id,movement_id,quantity,remaining,unit_cost) values(m.product_id,m.id,qty,qty,cost);
 elsif m.destination_location_id is null and m.source_location_id is not null then
  kind:='out';if qty>b.quantity then raise exception 'VALUATION_QUANTITY_MISMATCH';end if;
  if b.method='avco' then
   cost:=case when b.quantity>0 then b.value/b.quantity else 0 end;v:=case when qty=b.quantity then -b.value else -round(qty*cost,6) end;
   leftqty:=b.quantity-qty;
   for l in select * from public.stock_cost_layers where product_id=m.product_id and remaining>0 order by created_at,id for update loop
    take:=least(leftqty,round(l.remaining*(b.quantity-qty)/b.quantity,9));leftqty:=leftqty-take;
    update public.stock_cost_layers set remaining=take where id=l.id;
   end loop;
   -- Keep fractional layer shares exactly equal to the physical remainder.
   if leftqty<>0 then update public.stock_cost_layers set remaining=remaining+leftqty where id=l.id;end if;
  else
   leftqty:=qty;
   for l in select * from public.stock_cost_layers where product_id=m.product_id and remaining>0 order by created_at,id for update loop
    take:=least(leftqty,l.remaining);v:=v-round(take*l.unit_cost,6);leftqty:=leftqty-take;
    update public.stock_cost_layers set remaining=remaining-take where id=l.id;exit when leftqty=0;
   end loop;
   if leftqty<>0 then raise exception 'VALUATION_LAYERS_INCOMPLETE';end if;
   if qty=b.quantity then v:=-b.value;end if;cost:=-v/qty;
  end if;
  qty:=-qty;
 else raise exception 'VALUATION_LOCATION_REQUIRED';end if;
 newqty:=b.quantity+qty;newvalue:=round(b.value+v,6);
 if newvalue<0 and newvalue>=-0.000001 then newvalue:=0;end if;
 update public.stock_cost_books set quantity=newqty,value=newvalue where product_id=b.product_id;
 insert into public.stock_valuation_entries(product_id,movement_id,kind,quantity,value_delta,expense_delta,quantity_after,value_after,method,source,created_by)
 values(b.product_id,m.id,kind,qty,v,case when kind='out' then -v when m.reference_type='customer_return' then -v else 0 end,newqty,newvalue,b.method,src,auth.uid());
 return cost;
end $$;
revoke all on function private.erp_cost_post(public.stock_movements) from public,anon,authenticated;
do $$declare s text;begin
 s:=pg_get_functiondef('private.erp_movement_cost()'::regprocedure);
 if strpos(s,'end if;return new;')=0 then raise exception 'MOVEMENT_COST_ANCHOR_MISSING';end if;
 s:=replace(s,'end if;return new;','end if; if tg_op=''INSERT'' then new.unit_cost_at_movement:=private.erp_cost_post(new);end if;return new;');execute s;
end $$;

create function private.gama_valuation(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare b public.stock_cost_books;p public.products;key uuid;old private.stock_valuation_commands;result jsonb;qty numeric;cost numeric;
 l public.stock_cost_layers;c public.stock_landed_costs;allocation text;total numeric;weight numeric;denom numeric;amount numeric;remaining_amount numeric;stockpart numeric;n integer:=0;idx integer:=0;
 asof timestamptz:=coalesce(nullif(p_data->>'as_of','')::timestamptz,now());rights jsonb:=private.gama_accounting_rights();
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('configure','landed','accounts') then
  if private.current_user_role()<>'administrador' or not coalesce((rights->>'validate')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('valuation:'||key::text,0));select * into old from private.stock_valuation_commands where request_key=key;
  if found then if old.actor<>auth.uid() or old.action<>p_action or old.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return old.result;end if;
 end if;
 if p_action='configure' then
  if p_data->>'method' not in ('fifo','avco') or length(btrim(coalesce(p_data->>'reason','')))<10 then raise exception 'VALUATION_METHOD_AND_REASON_REQUIRED';end if;
  select * into p from public.products where id=(p_data->>'product_id')::uuid and product_kind='goods' for update;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  select * into b from public.stock_cost_books where product_id=p.id for update;
  if found then if b.quantity<>0 then raise exception 'METHOD_CHANGE_REQUIRES_EMPTY_STOCK';end if;
   update public.stock_cost_books set method=p_data->>'method' where product_id=p.id returning * into b;
   insert into public.stock_valuation_entries(product_id,kind,quantity,value_delta,quantity_after,value_after,method,source,created_by) values(p.id,'method',0,0,0,0,b.method,p_data->>'reason',auth.uid());
  else
   select coalesce(sum(quantity),0) into qty from public.stock_quants where product_id=p.id;
   cost:=nullif(p_data->>'opening_unit_cost','')::numeric;
   if cost is null or cost<0 or cost::text in ('NaN','Infinity','-Infinity') then raise exception 'OPENING_COST_REQUIRED';end if;
   insert into public.stock_cost_books(product_id,method,quantity,value,created_by) values(p.id,p_data->>'method',qty,round(qty*cost,6),auth.uid()) returning * into b;
   if qty>0 then insert into public.stock_cost_layers(product_id,quantity,remaining,unit_cost,opening) values(p.id,qty,qty,cost,true);end if;
   insert into public.stock_valuation_entries(product_id,kind,quantity,value_delta,quantity_after,value_after,method,source,created_by) values(p.id,'opening',qty,b.value,qty,b.value,b.method,'Observed opening · '||(p_data->>'reason'),auth.uid());
  end if;result:=to_jsonb(b);
 elsif p_action='accounts' then
  select * into b from public.stock_cost_books where product_id=(p_data->>'product_id')::uuid for update;if not found then raise exception 'VALUATION_NOT_CONFIGURED';end if;
  if not exists(select 1 from public.accounting_accounts where id=(p_data->>'stock_account_id')::uuid and active and type='asset') or not exists(select 1 from public.accounting_accounts where id=(p_data->>'expense_account_id')::uuid and active and type='expense') then raise exception 'VALUATION_ACCOUNTS_REQUIRED';end if;
  update public.stock_cost_books set stock_account_id=(p_data->>'stock_account_id')::uuid,expense_account_id=(p_data->>'expense_account_id')::uuid where product_id=b.product_id returning * into b;result:=to_jsonb(b);
 elsif p_action='landed' then
  allocation:=p_data->>'allocation';total:=(p_data->>'amount')::numeric;
  if allocation not in ('quantity','value','weight') or total is null or total=0 or total::text in ('NaN','Infinity','-Infinity') or total<>round(total,6) then raise exception 'INVALID_LANDED_COST';end if;
  if p_data->>'currency' is distinct from 'USD' then raise exception 'CURRENCY_CONVERSION_REQUIRED';end if;
  if jsonb_typeof(p_data->'movement_ids') is distinct from 'array' or jsonb_array_length(p_data->'movement_ids')=0 then raise exception 'RECEIPTS_REQUIRED';end if;
  if (select count(distinct value) from jsonb_array_elements_text(p_data->'movement_ids'))<>jsonb_array_length(p_data->'movement_ids') then raise exception 'DUPLICATE_RECEIPT';end if;
  -- Same product lock order as all stock operations. The layer shares are captured atomically.
  perform p.id from public.products p where p.id in(select product_id from public.stock_cost_layers where movement_id in(select value::uuid from jsonb_array_elements_text(p_data->'movement_ids'))) order by p.id for update;
  perform product_id from public.stock_cost_books where product_id in(select product_id from public.stock_cost_layers where movement_id in(select value::uuid from jsonb_array_elements_text(p_data->'movement_ids'))) order by product_id for update;
  select count(*),sum(case allocation when 'quantity' then layers.quantity when 'value' then layers.quantity*layers.unit_cost else layers.quantity*coalesce(prod.weight_g,0) end) into n,denom
   from public.stock_cost_layers layers join public.stock_movements m on m.id=layers.movement_id join public.products prod on prod.id=layers.product_id
   where layers.movement_id in(select value::uuid from jsonb_array_elements_text(p_data->'movement_ids')) and m.reference_type='purchase_order' and m.source_location_id is null;
  if n<>jsonb_array_length(p_data->'movement_ids') then raise exception 'RECEIPT_COST_LAYER_REQUIRED';end if;
  if denom<=0 then raise exception 'ALLOCATION_BASIS_MISSING';end if;
  if allocation='weight' and exists(select 1 from public.stock_cost_layers layers join public.products prod on prod.id=layers.product_id where layers.movement_id in(select value::uuid from jsonb_array_elements_text(p_data->'movement_ids')) and coalesce(prod.weight_g,0)<=0) then raise exception 'PRODUCT_WEIGHT_REQUIRED';end if;
  insert into public.stock_landed_costs(request_key,source_reference,amount,currency,allocation,reason,created_by) values(key,btrim(p_data->>'source_reference'),total,'USD',allocation,p_data->>'reason',auth.uid()) returning * into c;
  remaining_amount:=total;
  for l in select * from public.stock_cost_layers where movement_id in(select value::uuid from jsonb_array_elements_text(p_data->'movement_ids')) order by product_id,id for update loop
   idx:=idx+1;weight:=case allocation when 'quantity' then l.quantity when 'value' then l.quantity*l.unit_cost else l.quantity*(select weight_g from public.products where id=l.product_id) end;
   amount:=case when idx=n then remaining_amount else round(total*weight/denom,6) end;remaining_amount:=remaining_amount-amount;
   stockpart:=round(amount*l.remaining/l.quantity,6);
   update public.stock_cost_layers set unit_cost=unit_cost+amount/quantity where id=l.id;
   update public.stock_cost_books set value=value+stockpart where product_id=l.product_id returning * into b;
   insert into public.stock_landed_allocations(landed_cost_id,layer_id,amount,stock_value,consumed_value) values(c.id,l.id,amount,stockpart,amount-stockpart);
   insert into public.stock_valuation_entries(product_id,landed_cost_id,kind,quantity,value_delta,expense_delta,quantity_after,value_after,method,source,created_by) values(l.product_id,c.id,'landed',0,stockpart,amount-stockpart,b.quantity,b.value,b.method,c.source_reference,auth.uid());
  end loop;
  result:=to_jsonb(c)||jsonb_build_object('allocations',(select jsonb_agg(a) from public.stock_landed_allocations a where a.landed_cost_id=c.id));
 elsif p_action='report' then
  if asof>now() then raise exception 'VALUATION_DATE_UNAVAILABLE';end if;
  with items as(select prod.id,prod.name,prod.reference,coalesce(book.method,'standard_estimate') method,book.started_at,
   coalesce(physical.quantity,0) physical_quantity,coalesce(v.quantity_after,0) book_quantity,
   case when book.product_id is null then case when p_data?'as_of' then null else round(coalesce(physical.quantity,0)*coalesce(prod.purchase_price,0),6) end when asof<book.started_at then null else coalesce(v.value_after,0) end value,
   book.stock_account_id,book.expense_account_id,prod.purchase_price,
   case when book.product_id is null then 'standard_estimate' when asof<book.started_at then 'before_opening' when v.quantity_after is distinct from coalesce(physical.quantity,0) and not(p_data?'as_of') then 'quantity_mismatch' else 'observed_opening' end provenance
   from public.products prod left join public.stock_cost_books book on book.product_id=prod.id left join (select product_id,sum(quantity) quantity from public.stock_quants group by product_id) physical on physical.product_id=prod.id
   left join lateral(select e.quantity_after,e.value_after from public.stock_valuation_entries e where e.product_id=prod.id and e.created_at<=asof order by e.created_at desc,e.sequence desc limit 1) v on true
   where prod.product_kind='goods' and prod.active and (nullif(p_data->>'search','') is null or concat_ws(' ',prod.name,prod.reference) ilike '%'||(p_data->>'search')||'%'))
  select jsonb_build_object('as_of',asof,'total',(select count(*) from items),'items',coalesce((select jsonb_agg(r) from (select * from items order by name,id limit 25 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))r),'[]'),
   'reconciliation',coalesce((select jsonb_agg(r) from (select a.id,a.code,a.name,'stock' kind,coalesce((select sum(val.value_after) from public.stock_cost_books cb left join lateral(select e.value_after from public.stock_valuation_entries e where e.product_id=cb.product_id and e.created_at<=asof order by e.created_at desc,e.sequence desc limit 1) val on true where cb.stock_account_id=a.id),0) inventory_value,
    coalesce((select sum(el.debit-el.credit) from public.accounting_entry_lines el join public.accounting_entries en on en.id=el.entry_id where el.account_id=a.id and en.status in ('posted','reversed') and en.entry_date<=asof::date),0) ledger_value
    from public.accounting_accounts a where a.id in(select stock_account_id from public.stock_cost_books)
    union all select a.id,a.code,a.name,'expense',coalesce((select sum(e.expense_delta) from public.stock_valuation_entries e join public.stock_cost_books cb on cb.product_id=e.product_id where cb.expense_account_id=a.id and e.created_at<=asof),0),
    coalesce((select sum(el.debit-el.credit) from public.accounting_entry_lines el join public.accounting_entries en on en.id=el.entry_id where el.account_id=a.id and en.status in ('posted','reversed') and en.entry_date<=asof::date),0)
    from public.accounting_accounts a where a.id in(select expense_account_id from public.stock_cost_books))r),'[]')) into result;
  return result;
 elsif p_action='history' then
  return jsonb_build_object('total',(select count(*) from public.stock_valuation_entries where product_id=(p_data->>'product_id')::uuid and (nullif(p_data->>'search','') is null or concat_ws(' ',kind,source,created_at::text) ilike '%'||(p_data->>'search')||'%')),'items',coalesce((select jsonb_agg(r) from (select * from public.stock_valuation_entries where product_id=(p_data->>'product_id')::uuid and (nullif(p_data->>'search','') is null or concat_ws(' ',kind,source,created_at::text) ilike '%'||(p_data->>'search')||'%') order by sequence desc limit 25 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))r),'[]'));
 elsif p_action='receipts' then
  return jsonb_build_object('total',(select count(*) from public.stock_movements m join public.stock_cost_layers l on l.movement_id=m.id join public.products p on p.id=m.product_id join public.purchase_orders po on po.id=m.reference_id where m.reference_type='purchase_order' and m.source_location_id is null and (nullif(p_data->>'search','') is null or concat_ws(' ',p.name,p.reference,po.order_number,m.erp_reference) ilike '%'||(p_data->>'search')||'%')),'items',coalesce((select jsonb_agg(r) from (select m.id,p.name,p.reference,m.quantity,m.created_at,m.erp_reference,l.remaining,l.unit_cost,po.order_number
   from public.stock_movements m join public.stock_cost_layers l on l.movement_id=m.id join public.products p on p.id=m.product_id join public.purchase_orders po on po.id=m.reference_id
   where m.reference_type='purchase_order' and m.source_location_id is null and (nullif(p_data->>'search','') is null or concat_ws(' ',p.name,p.reference,po.order_number,m.erp_reference) ilike '%'||(p_data->>'search')||'%') order by m.created_at desc,m.id limit 25 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))r),'[]'));
 else raise exception 'INVALID_ACTION';end if;
 insert into private.stock_valuation_commands(request_key,actor,action,payload,result) values(key,auth.uid(),p_action,p_data,result);
 return result;
end $$;
create function public.gama_valuation(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_valuation(p_action,p_data)$$;
revoke all on function private.gama_valuation(text,jsonb),public.gama_valuation(text,jsonb) from public,anon;
grant execute on function private.gama_valuation(text,jsonb),public.gama_valuation(text,jsonb) to authenticated;
