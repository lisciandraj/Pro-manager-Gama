alter table public.products add column base_unit text not null default 'unit' check(length(btrim(base_unit)) between 1 and 40);
create table public.product_units(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),label text not null check(length(btrim(label)) between 1 and 60),factor numeric(18,6) not null check(factor>0),barcode text,active boolean not null default true,unique(product_id,label));
create unique index product_units_barcode on public.product_units(barcode) where nullif(barcode,'') is not null;
alter table public.product_units enable row level security;
revoke all on public.product_units from public,anon,authenticated;grant select,insert,update on public.product_units to authenticated;
create policy units_read on public.product_units for select to authenticated using(private.current_user_role() in ('administrador','comercial','almacenero'));
create policy units_write on public.product_units for all to authenticated using(private.erp_module_allowed('products',array['administrador','comercial'])) with check(private.erp_module_allowed('products',array['administrador','comercial']));
create table public.product_price_history(sequence bigint generated always as identity unique,id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),changed_at timestamptz not null default now(),changed_by uuid references public.profiles(id),before_prices jsonb,after_prices jsonb not null);
alter table public.product_price_history enable row level security;
revoke all on public.product_price_history from public,anon,authenticated;grant select on public.product_price_history to authenticated;
create policy product_price_history_read on public.product_price_history for select to authenticated using(private.erp_module_allowed('products',array['administrador','comercial']));
create index product_price_history_product on public.product_price_history(product_id,changed_at);create index product_price_history_actor on public.product_price_history(changed_by);
create function private.erp_product_history() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.base_unit is distinct from old.base_unit and (exists(select 1 from public.stock_movements where product_id=new.id) or exists(select 1 from public.sales_order_lines where product_id=new.id) or exists(select 1 from public.purchase_order_lines where product_id=new.id)) then raise exception 'BASE_UNIT_ALREADY_USED';end if;
 if tg_op='INSERT' or (new.purchase_price,new.sale_price,new.sale_price_b,new.tax_rate) is distinct from (old.purchase_price,old.sale_price,old.sale_price_b,old.tax_rate) then
 insert into public.product_price_history(product_id,changed_by,before_prices,after_prices) values(new.id,auth.uid(),case when tg_op='UPDATE' then jsonb_build_object('cost',old.purchase_price,'a',old.sale_price,'b',old.sale_price_b,'tax',old.tax_rate) end,jsonb_build_object('cost',new.purchase_price,'a',new.sale_price,'b',new.sale_price_b,'tax',new.tax_rate));end if;return new;end $$;
revoke all on function private.erp_product_history() from public,anon,authenticated;
create trigger erp_product_history after insert or update on public.products for each row execute function private.erp_product_history();
create function private.erp_unit_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if nullif(new.barcode,'') is not null and exists(select 1 from public.products where barcode=new.barcode) then raise exception 'BARCODE_ALREADY_USED';end if;
 if tg_op='UPDATE' and new.factor<>old.factor then raise exception 'UNIT_FACTOR_IMMUTABLE_CREATE_NEW';end if;return new;end $$;
revoke all on function private.erp_unit_guard() from public,anon,authenticated;
create trigger erp_unit_guard before insert or update on public.product_units for each row execute function private.erp_unit_guard();
create function private.gama_convert_unit(p_product uuid,p_unit uuid,p_quantity numeric) returns jsonb language plpgsql stable security definer set search_path='' as $$declare p public.products;u public.product_units;q numeric;begin
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into p from public.products where id=p_product and active;select * into u from public.product_units where id=p_unit and product_id=p_product and active;
 if p.id is null or u.id is null or p_quantity is null or p_quantity<=0 then raise exception 'UNIT_QUANTITY_REQUIRED';end if;q:=p_quantity*u.factor;
 if q<>round(q,3) or q>=100000000 then raise exception 'BASE_QUANTITY_PRECISION';end if;
 return jsonb_build_object('product_id',p.id,'unit_id',u.id,'quantity',p_quantity,'factor',u.factor,'base_quantity',q,'base_unit',p.base_unit,'label',u.label);
end $$;
revoke all on function private.gama_convert_unit(uuid,uuid,numeric) from public,anon;grant execute on function private.gama_convert_unit(uuid,uuid,numeric) to authenticated;
create function public.gama_convert_unit(p_product uuid,p_unit uuid,p_quantity numeric) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_convert_unit(p_product,p_unit,p_quantity)$$;
revoke all on function public.gama_convert_unit(uuid,uuid,numeric) from public,anon;grant execute on function public.gama_convert_unit(uuid,uuid,numeric) to authenticated;

-- Historical standard-cost valuation starts at this observed opening snapshot.
-- Earlier dates are explicitly unavailable; no guessed historical cost is backfilled.
create table private.erp_stock_cost_epoch(id boolean primary key default true check(id),observed_at timestamptz not null default now());
insert into private.erp_stock_cost_epoch(id) values(true);
revoke all on private.erp_stock_cost_epoch from public,anon,authenticated;
create table private.erp_stock_cost_opening(product_id uuid primary key references public.products(id),quantity numeric not null,unit_cost numeric not null,observed_at timestamptz not null default now());
insert into private.erp_stock_cost_opening(product_id,quantity,unit_cost) select p.id,coalesce((select sum(q.quantity) from public.stock_quants q where q.product_id=p.id),0),coalesce(p.purchase_price,0) from public.products p;
revoke all on private.erp_stock_cost_opening from public,anon,authenticated;
alter table public.stock_movements add column unit_cost_at_movement numeric;
create function private.erp_movement_cost() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and new.unit_cost_at_movement is distinct from old.unit_cost_at_movement then raise exception 'MOVEMENT_COST_IMMUTABLE';end if;
 if tg_op='INSERT' then
 select coalesce(p.purchase_price,0) into new.unit_cost_at_movement from public.products p where p.id=new.product_id;
 if new.reference_type='purchase_order' then select coalesce(sum(l.quantity*l.unit_cost)/nullif(sum(l.quantity),0),new.unit_cost_at_movement) into new.unit_cost_at_movement from public.purchase_order_lines l where l.purchase_order_id=new.reference_id and l.product_id=new.product_id;end if;
 end if;return new;end $$;
revoke all on function private.erp_movement_cost() from public,anon,authenticated;
create trigger erp_movement_cost before insert or update on public.stock_movements for each row execute function private.erp_movement_cost();
create function private.gama_historical_stock(p_asof timestamptz) returns jsonb language plpgsql stable security definer set search_path='' as $$declare starts timestamptz;rights jsonb:=private.gama_accounting_rights();begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select observed_at into starts from private.erp_stock_cost_epoch where id;if p_asof is null or p_asof<starts or p_asof>now() then raise exception 'VALUATION_DATE_UNAVAILABLE:%',starts;end if;
 return jsonb_build_object('as_of',p_asof,'available_from',starts,'method','registered_standard_cost','rows',(with source as(
 select p.id,p.name,p.reference,p.base_unit,coalesce(o.quantity,0)+coalesce((select sum(case when m.stock_before is not null and m.stock_after is not null then m.stock_after-m.stock_before when m.type='in' then m.quantity when m.type='out' then -abs(m.quantity) when m.type='adjustment' then m.quantity else 0 end) from public.stock_movements m where m.product_id=p.id and m.created_at>=coalesce(o.observed_at,starts) and m.created_at<=p_asof),0) quantity,
 coalesce((select (h.after_prices->>'cost')::numeric from public.product_price_history h where h.product_id=p.id and h.changed_at<=p_asof order by h.changed_at desc,h.sequence desc limit 1),o.unit_cost,0) cost
 from public.products p left join private.erp_stock_cost_opening o on o.product_id=p.id where p.created_at<=p_asof)
 select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('value',round(quantity*cost,2)) order by name,id),'[]') from source s));
end $$;
revoke all on function private.gama_historical_stock(timestamptz) from public,anon;grant execute on function private.gama_historical_stock(timestamptz) to authenticated;
create function public.gama_historical_stock(p_asof timestamptz) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_historical_stock(p_asof)$$;
revoke all on function public.gama_historical_stock(timestamptz) from public,anon;grant execute on function public.gama_historical_stock(timestamptz) to authenticated;

alter table public.invoices add column accepted_snapshot jsonb;
create function private.erp_quote_snapshot() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and old.accepted_snapshot is not null then
 if new.accepted_snapshot is distinct from old.accepted_snapshot then raise exception 'ACCEPTED_SNAPSHOT_IMMUTABLE';end if;
 elsif new.quote_state='accepted' then
 new.accepted_snapshot:=jsonb_build_object('captured_at',now(),'company',(select private.gama_company_public(c) from public.company_settings c where id),'header',to_jsonb(new)-'accepted_snapshot','lines',(select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]') from public.invoice_lines l where l.invoice_id=new.id));
 elsif new.accepted_snapshot is not null then raise exception 'ACCEPTANCE_REQUIRED';end if;return new;end $$;
revoke all on function private.erp_quote_snapshot() from public,anon,authenticated;
create trigger erp_quote_snapshot before insert or update on public.invoices for each row execute function private.erp_quote_snapshot();
