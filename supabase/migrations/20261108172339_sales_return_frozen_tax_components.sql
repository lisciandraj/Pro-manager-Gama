-- Customer goods returns reverse the issued components, including their accounts.
-- Physical quantities reduce fixed levies; financial discounts have no unit levy.
begin;
alter table public.return_orders add column tax_calculation jsonb;
alter table public.return_credits add column tax_calculation jsonb;
alter table public.return_refunds add column tax_calculation jsonb;


-- Allocate each tax component's declared base over the original lines once;
-- global rounding can leave sub-cent bases which must not each round upward.
create function private.coco_return_component_bases(p_calc jsonb) returns jsonb language sql immutable security invoker set search_path='' as $$
 with original as(select ln.ordinality li,tx.ordinality ti,tx.value obj,
  jsonb_build_array(tx.value->>'id',tx.value->>'code',tx.value->>'account_id')::text bucket,
  coalesce((tx.value->>'base_unrounded')::numeric,(tx.value->>'base')::numeric,0) raw_base,
  coalesce((select (g->>'base')::numeric from jsonb_array_elements(p_calc->'taxes')g where g->'id' is not distinct from tx.value->'id' and g->>'code'=tx.value->>'code' and g->>'account_id'=tx.value->>'account_id' limit 1),0) group_base
  from jsonb_array_elements(p_calc->'lines') with ordinality ln cross join lateral jsonb_array_elements(ln.value->'taxes') with ordinality tx),
 running as(select o.*,sum(raw_base) over(partition by bucket) all_base,sum(raw_base) over(partition by bucket order by li,ti) prefix_base from original o),
 targets as(select r.*,case when all_base=0 then 0 else round(group_base*prefix_base/all_base,2) end target_base from running r),
 revised as(select li,ti,obj||jsonb_build_object('base',target_base-lag(target_base,1,0::numeric) over(partition by bucket order by li,ti)) obj from targets),
 taxlines as(select li,jsonb_agg(obj order by ti) taxes from revised group by li)
 select p_calc||jsonb_build_object('lines',coalesce(jsonb_agg(l.value||jsonb_build_object('taxes',coalesce(r.taxes,'[]')) order by l.ordinality),'[]')) from jsonb_array_elements(p_calc->'lines') with ordinality l left join taxlines r on r.li=l.ordinality
$$;

create function private.coco_supplier_return_calculation(p_return uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare o public.return_orders;inv public.supplier_invoices;ls jsonb;tx jsonb;net numeric;tax numeric;begin
 select * into o from public.return_orders where id=p_return;if o.tax_calculation is not null then return o.tax_calculation;end if;select * into inv from public.supplier_invoices where id=o.supplier_invoice_id;
 if o.kind is distinct from 'supplier' or inv.tax_calculation->>'schema' is distinct from 'coco.tax.v1' then return null;end if;
 inv.tax_calculation:=private.coco_return_component_bases(inv.tax_calculation);
 with physical as materialized(select r.product_id,coalesce(sum(r.quantity) filter(where ro.id=o.id),0) current_quantity,
  coalesce(sum(r.quantity) filter(where ro.id<>o.id and ro.tax_calculation is not null),0) prior_quantity from public.return_lines r join public.return_orders ro on ro.id=r.return_id
  where ro.supplier_invoice_id=inv.id and ro.status<>'cancelled' and (ro.id=o.id or ro.tax_calculation is not null) group by r.product_id),
 pieces as(select l.value piece,r.current_quantity,r.prior_quantity,sum((l.value->>'quantity')::numeric) over(partition by l.value->>'product_id') invoiced_quantity
  from jsonb_array_elements(inv.tax_calculation->'lines')l left join physical r on r.product_id::text=l.value->>'product_id'),
 scaled as(select piece,least(1,greatest(0,coalesce(prior_quantity,0)/nullif(invoiced_quantity,0))) previous,
  least(1,greatest(0,(coalesce(prior_quantity,0)+current_quantity)/nullif(invoiced_quantity,0))) cumulative from pieces where current_quantity>0),
 rows as(select s.piece||jsonb_build_object('return_id',o.id,'source_invoice_id',inv.id,'subtotal',round((s.piece->>'subtotal')::numeric*s.cumulative,2)-round((s.piece->>'subtotal')::numeric*s.previous,2),
  'taxes',coalesce((select jsonb_agg(t||jsonb_build_object('base',round((t->>'base')::numeric*s.cumulative,2)-round((t->>'base')::numeric*s.previous,2),
   'amount',round((t->>'amount')::numeric*s.cumulative,2)-round((t->>'amount')::numeric*s.previous,2))) from jsonb_array_elements(s.piece->'taxes')t),'[]')) obj from scaled s),
 totals as(select obj||jsonb_build_object('tax',(select coalesce(sum((t->>'amount')::numeric),0) from jsonb_array_elements(obj->'taxes')t),
  'total',(obj->>'subtotal')::numeric+(select coalesce(sum((t->>'amount')::numeric),0) from jsonb_array_elements(obj->'taxes')t)) obj from rows)
 select coalesce(jsonb_agg(obj order by obj->>'key'),'[]') into ls from totals;
 select coalesce(jsonb_agg(g.obj||jsonb_build_object('base',g.base,'amount',g.amount)),'[]') into tx from(select (array_agg(t))[1] obj,sum((t->>'base')::numeric) base,sum((t->>'amount')::numeric) amount from jsonb_array_elements(ls)l cross join lateral jsonb_array_elements(l->'taxes')t group by t->>'id',t->>'code',t->>'account_id')g;
 select coalesce(sum((l->>'subtotal')::numeric),0),coalesce(sum((l->>'tax')::numeric),0) into net,tax from jsonb_array_elements(ls)l;
 return jsonb_build_object('schema','coco.tax.v1','return_id',o.id,'supplier_invoice_id',inv.id,'side','purchase','rounding','global','lines',ls,'taxes',tx,'subtotal',net,'tax',tax,'total',net+tax);
end $$;

create function private.coco_sales_return_calculation(p_return uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare o public.return_orders;inv public.external_invoices;ls jsonb;tx jsonb;net numeric;tax numeric;begin
 select * into o from public.return_orders where id=p_return;if o.tax_calculation is not null then return o.tax_calculation;end if;
 if o.kind='supplier' then return private.coco_supplier_return_calculation(p_return);end if;
 select * into inv from public.external_invoices where id=o.invoice_id;
 if o.kind is distinct from 'customer' or inv.document_snapshot#>>'{tax_calculation,schema}' is distinct from 'coco.tax.v1' then return null;end if;
 inv.document_snapshot:=jsonb_set(inv.document_snapshot,'{tax_calculation}',private.coco_return_component_bases(inv.document_snapshot->'tax_calculation'));
 -- The invoice line fixes both the charged quantity and tax combination. The
 -- cumulative physical share assigns the final cent once across several returns.
 with pieces as materialized(
  select x.value piece,l.*,il.quantity invoiced_quantity,(x.value->>'subtotal')::numeric original_net
  from jsonb_array_elements(inv.document_snapshot#>'{tax_calculation,lines}') x
  join public.sales_order_lines l on l.id::text=coalesce(x.value->>'source_line_id',x.value->>'key')
  join public.external_invoice_lines il on il.invoice_id=inv.id and il.order_line_id=l.id
 ),physical as materialized(
  select d.order_line_id,
   coalesce(sum(r.quantity) filter(where ro.id=o.id),0) current_quantity,
   coalesce(sum(r.quantity) filter(where ro.id<>o.id and ro.tax_calculation is not null),0) prior_quantity
  from public.return_lines r join public.return_orders ro on ro.id=r.return_id join public.sales_delivery_lines d on d.id=r.delivery_line_id
  where ro.invoice_id=inv.id and ro.status<>'cancelled' and (ro.id=o.id or ro.tax_calculation is not null) group by d.order_line_id
 ),weights as(
  select p.*,
   case when p.line_kind='product' then coalesce(r.current_quantity,0)/p.invoiced_quantity else coalesce(w.current_base,0)/nullif(w.denominator,0) end current_factor,
   case when p.line_kind='product' then coalesce(r.prior_quantity,0)/p.invoiced_quantity else coalesce(w.prior_base,0)/nullif(w.denominator,0) end prior_factor
  from pieces p left join physical r on r.order_line_id=p.id
  left join lateral(select sum(g.original_net) denominator,
   sum(g.original_net*coalesce(gq.current_quantity,0)/g.invoiced_quantity) current_base,
   sum(g.original_net*coalesce(gq.prior_quantity,0)/g.invoiced_quantity) prior_base
   from pieces g left join physical gq on gq.order_line_id=g.id where g.line_kind='product' and g.order_id=p.order_id and g.tax_rate=p.tax_rate and g.tax_ids is not distinct from p.tax_ids
   and (nullif(p.commercial_metadata->>'target_product_id','') is null or g.product_id=(p.commercial_metadata->>'target_product_id')::uuid)) w on p.line_kind in('discount','reward') and p.commercial_scope='products'
  where p.line_kind='product' or (p.line_kind in('discount','reward') and p.commercial_scope='products')
 ),scaled as(
  select piece,least(1,greatest(0,coalesce(prior_factor,0))) previous,least(1,greatest(0,coalesce(prior_factor,0)+coalesce(current_factor,0))) cumulative
  from weights where current_factor>0
 ),rows as(
  select s.piece||jsonb_build_object('return_id',o.id,'source_invoice_id',inv.id,'subtotal',round((s.piece->>'subtotal')::numeric*s.cumulative,2)-round((s.piece->>'subtotal')::numeric*s.previous,2),
   'taxes',coalesce((select jsonb_agg(t||jsonb_build_object('base',round((t->>'base')::numeric*s.cumulative,2)-round((t->>'base')::numeric*s.previous,2),
    'amount',round((t->>'amount')::numeric*s.cumulative,2)-round((t->>'amount')::numeric*s.previous,2))) from jsonb_array_elements(s.piece->'taxes')t),'[]')) obj from scaled s
 ),totals as(select obj||jsonb_build_object('tax',(select coalesce(sum((t->>'amount')::numeric),0) from jsonb_array_elements(obj->'taxes')t),
  'total',(obj->>'subtotal')::numeric+(select coalesce(sum((t->>'amount')::numeric),0) from jsonb_array_elements(obj->'taxes')t)) obj from rows)
 select coalesce(jsonb_agg(obj order by obj->>'key'),'[]') into ls from totals;
 select coalesce(jsonb_agg(g.obj||jsonb_build_object('base',g.base,'amount',g.amount)),'[]') into tx from(
  select (array_agg(t))[1] obj,sum((t->>'base')::numeric) base,sum((t->>'amount')::numeric) amount from jsonb_array_elements(ls)l cross join lateral jsonb_array_elements(l->'taxes')t group by t->>'id',t->>'code',t->>'account_id')g;
 select coalesce(sum((l->>'subtotal')::numeric),0),coalesce(sum((l->>'tax')::numeric),0) into net,tax from jsonb_array_elements(ls)l;
 return jsonb_build_object('schema','coco.tax.v1','return_id',o.id,'invoice_id',inv.id,'side','sale','rounding','global','lines',ls,'taxes',tx,'subtotal',net,'tax',tax,'total',net+tax);
end $$;
create function private.coco_sales_return_money_delta(p_calc jsonb,p_previous numeric,p_amount numeric) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
#variable_conflict use_column
declare previous jsonb;target jsonb;ls jsonb;tx jsonb;net numeric;tax numeric;residual numeric;first_key text;begin
 if p_previous<0 or p_amount<0 or p_previous+p_amount>(p_calc->>'total')::numeric or (p_calc->>'total')::numeric<=0 then raise exception 'CREDIT_EXCEEDS_RETURN';end if;
 previous:=private.coco_tax_scale_snapshot(p_calc,p_previous/(p_calc->>'total')::numeric);
 target:=private.coco_tax_scale_snapshot(p_calc,(p_previous+p_amount)/(p_calc->>'total')::numeric);
 with pieces as(select l.value obj,p.value old from jsonb_array_elements(target->'lines')l left join lateral(select value from jsonb_array_elements(previous->'lines')p where p.value->>'key'=l.value->>'key')p on true),
 rows as(select obj||jsonb_build_object('subtotal',(obj->>'subtotal')::numeric-coalesce((old->>'subtotal')::numeric,0),'taxes',coalesce((select jsonb_agg(t||jsonb_build_object('base',(t->>'base')::numeric-coalesce((x->>'base')::numeric,0),'amount',(t->>'amount')::numeric-coalesce((x->>'amount')::numeric,0))) from jsonb_array_elements(obj->'taxes')t left join lateral(select value x from jsonb_array_elements(coalesce(old->'taxes','[]')) x where x.value->'id' is not distinct from t->'id' and x.value->>'code'=t->>'code' and x.value->>'account_id'=t->>'account_id')z on true),'[]')) obj from pieces)
 select jsonb_agg(obj||jsonb_build_object('tax',(select coalesce(sum((t->>'amount')::numeric),0) from jsonb_array_elements(obj->'taxes')t))) into ls from rows;
 select coalesce(sum((l->>'subtotal')::numeric),0),coalesce(sum((l->>'tax')::numeric),0) into net,tax from jsonb_array_elements(ls)l;
 residual:=p_amount-net-tax;select l->>'key' into first_key from jsonb_array_elements(ls)l where (l->>'subtotal')::numeric>0 limit 1;
 select jsonb_agg(l||jsonb_build_object('subtotal',(l->>'subtotal')::numeric+case when l->>'key'=first_key then residual else 0 end,'total',(l->>'subtotal')::numeric+(l->>'tax')::numeric+case when l->>'key'=first_key then residual else 0 end)) into ls from jsonb_array_elements(ls)l;
 select coalesce(jsonb_agg(g.obj||jsonb_build_object('base',g.base,'amount',g.amount)),'[]') into tx from(select (array_agg(t))[1] obj,sum((t->>'base')::numeric) base,sum((t->>'amount')::numeric) amount from jsonb_array_elements(ls)l cross join lateral jsonb_array_elements(l->'taxes')t group by t->>'id',t->>'code',t->>'account_id')g;
 return p_calc||jsonb_build_object('lines',ls,'taxes',tx,'subtotal',p_amount-tax,'tax',tax,'total',p_amount);
end $$;

alter function private.gama_return_amount(uuid) rename to gama_return_amount_before_frozen_components;
create function private.gama_return_amount(p_return uuid) returns numeric language plpgsql stable security definer set search_path='' as $$declare calc jsonb;begin
 calc:=private.coco_sales_return_calculation(p_return);if calc is not null then return (calc->>'total')::numeric;end if;return private.gama_return_amount_before_frozen_components(p_return);end $$;
alter function private.gama_return_split(uuid,numeric) rename to gama_return_split_before_frozen_components;
create function private.gama_return_split(p_return uuid,p_amount numeric) returns jsonb language plpgsql stable security definer set search_path='' as $$declare calc jsonb;begin
 calc:=private.coco_sales_return_calculation(p_return);if calc is not null and (calc->>'total')::numeric>0 then calc:=private.coco_sales_return_money_delta(calc,0,p_amount);return jsonb_build_object('net',calc->'subtotal','tax',calc->'tax');end if;return private.gama_return_split_before_frozen_components(p_return,p_amount);end $$;

create function private.coco_sales_return_freeze() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare calc jsonb;o public.return_orders;used numeric;credited numeric;prior numeric;covered numeric;begin
 if tg_table_name='return_refunds' and nullif(to_jsonb(new)->>'adjustment_id','') is not null then return new;end if;
 if tg_op='UPDATE' then if new.tax_calculation is distinct from old.tax_calculation then raise exception 'RETURN_TAX_SNAPSHOT_IMMUTABLE';end if;return new;end if;
 select * into o from public.return_orders where id=new.return_id for update;
 if o.invoice_id is not null then perform 1 from public.external_invoices where id=o.invoice_id for update;elsif o.supplier_invoice_id is not null then perform 1 from public.supplier_invoices where id=o.supplier_invoice_id for update;end if;
 calc:=private.coco_sales_return_calculation(new.return_id);
 new.tax_calculation:=null;if calc is null then return new;end if;
 if o.tax_calculation is null then update public.return_orders set tax_calculation=calc,updated_at=now() where id=o.id;end if;
 if tg_table_name='return_credits' then select coalesce(sum(amount),0) into used from public.return_credits where return_id=new.return_id;
  new.tax_calculation:=private.coco_sales_return_money_delta(calc,used,new.amount);
 else
  select coalesce(sum(amount),0) into credited from public.return_credits where return_id=new.return_id;
  select coalesce(sum(amount),0) into prior from public.return_refunds where return_id=new.return_id;
  covered:=least(new.amount,greatest(credited-prior,0));used:=greatest(prior-credited,0);
  if new.amount>covered then new.tax_calculation:=private.coco_sales_return_money_delta(calc,credited+used,new.amount-covered);end if;
 end if;return new;
end $$;
create function private.coco_return_order_tax_freeze() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.tax_calculation is not null and (tg_op='DELETE' or new.status='cancelled') then raise exception 'RETURN_HAS_FINANCIAL_DOCUMENTS';end if;
 if tg_op='DELETE' then return old;end if;
 if old.tax_calculation is not null and (new.tax_calculation is distinct from old.tax_calculation or new.invoice_id is distinct from old.invoice_id or new.supplier_invoice_id is distinct from old.supplier_invoice_id) then raise exception 'RETURN_TAX_SNAPSHOT_IMMUTABLE';end if;return new;end $$;
create trigger coco_return_order_tax_freeze before update or delete on public.return_orders for each row execute function private.coco_return_order_tax_freeze();
create trigger coco_return_tax_freeze before insert or update on public.return_credits for each row execute function private.coco_sales_return_freeze();
create trigger coco_return_tax_freeze before insert or update on public.return_refunds for each row execute function private.coco_sales_return_freeze();

create function private.coco_sales_return_post(p_type text,p_id uuid,p_date date default null) returns uuid language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare r record;l jsonb;lines jsonb:='[]';eid uuid;ar uuid;bank uuid;covered numeric;begin
 perform pg_advisory_xact_lock(hashtextextended(p_type||p_id::text,0));select id into eid from public.accounting_entries where source_type=p_type and source_id=p_id;if eid is not null then return eid;end if;
 if p_type in('return_credit','supplier_credit') then
  select k.*,o.customer_id,o.supplier_id,c.name customer_name into r from public.return_credits k join public.return_orders o on o.id=k.return_id left join public.customers c on c.id=o.customer_id where k.id=p_id;
  if r.tax_calculation is null then return null;end if;if p_type='return_credit' then perform private.gama_accounting_credit_refund_guard(p_id);end if;
  if p_type='supplier_credit' then ar:=private.gama_partner_account('supplier',r.supplier_id,r.supplier_invoice_id);lines:=jsonb_build_array(jsonb_build_object('account_id',ar,'debit',r.amount,'partner_type','supplier','partner_id',r.supplier_id,'partner_account_fixed',true));
  else ar:=private.gama_partner_account('customer',r.customer_id,r.invoice_id);lines:=jsonb_build_array(jsonb_build_object('account_id',ar,'credit',r.amount,'partner_type','customer','partner_id',r.customer_id,'partner_account_fixed',true));end if;
 else
  select f.*,o.invoice_id,o.customer_id,o.number,c.name customer_name into r from public.return_refunds f join public.return_orders o on o.id=f.return_id left join public.customers c on c.id=o.customer_id where f.id=p_id;
  if r.tax_calculation is null then return null;end if;
  select account_id into bank from public.financial_accounts where id=r.financial_account_id;if bank is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  covered:=r.amount-(r.tax_calculation->>'total')::numeric;
  if covered>0 and exists(select 1 from public.return_credits k where k.return_id=r.return_id and not exists(select 1 from public.accounting_entries e where e.source_type='return_credit' and e.source_id=k.id and e.status in('posted','reversed'))) then raise exception 'REFUND_CREDIT_UNPOSTED';end if;
  lines:=jsonb_build_array(jsonb_build_object('account_id',bank,'financial_account_id',r.financial_account_id,'credit',r.amount));
  if covered>0 then ar:=private.gama_partner_account('customer',r.customer_id,r.invoice_id);lines:=lines||jsonb_build_array(jsonb_build_object('account_id',ar,'debit',covered,'partner_type','customer','partner_id',r.customer_id,'partner_account_fixed',true));end if;
 end if;
 for l in select value from jsonb_array_elements(r.tax_calculation->'lines') loop if (l->>'subtotal')::numeric<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',l->>'account_id','debit',greatest((l->>'subtotal')::numeric*case when p_type='supplier_credit' then -1 else 1 end,0),'credit',greatest(-(l->>'subtotal')::numeric*case when p_type='supplier_credit' then -1 else 1 end,0)));end if;end loop;
 for l in select value from jsonb_array_elements(r.tax_calculation->'taxes') loop if (l->>'amount')::numeric<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',l->>'account_id','tax_id',l->'id','debit',greatest((l->>'amount')::numeric*case when p_type='supplier_credit' then -1 else 1 end,0),'credit',greatest(-(l->>'amount')::numeric*case when p_type='supplier_credit' then -1 else 1 end,0)));end if;end loop;
 if p_type='supplier_credit' then eid:=private.gama_accounting_book('CMP',coalesce(p_date,r.issued_on),coalesce(r.supplier_reference,r.number),p_type,p_id,(select name from public.suppliers where id=r.supplier_id),lines);perform private.gama_stock_credit_reclass(p_id);return eid;end if;
 if p_type='return_credit' then return private.gama_accounting_book('VTA',coalesce(p_date,r.issued_on),r.number,p_type,p_id,r.customer_name,lines);end if;
 return private.gama_accounting_book(case when r.method ~* '(efectivo|cash|caja)' then 'CAJ' else 'BAN' end,coalesce(p_date,r.paid_at),coalesce(r.reference,r.number),p_type,p_id,r.customer_name,lines);
end $$;
alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_frozen_returns;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid;begin
 if p_source_type in('return_credit','supplier_credit','return_refund') then eid:=private.coco_sales_return_post(p_source_type,p_source_id);if eid is not null then return eid;end if;end if;return private.gama_accounting_post_before_frozen_returns(p_source_type,p_source_id);end $$;
alter function private.gama_accounting_post_at(text,uuid,date) rename to gama_accounting_post_at_before_frozen_returns;
create function private.gama_accounting_post_at(p_source_type text,p_source_id uuid,p_date date) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid;begin
 if p_source_type in('return_credit','supplier_credit','return_refund') then eid:=private.coco_sales_return_post(p_source_type,p_source_id,p_date);if eid is not null then return eid;end if;end if;return private.gama_accounting_post_at_before_frozen_returns(p_source_type,p_source_id,p_date);end $$;

do $$declare s text;a text;begin
 s:=pg_get_functiondef('private.gama_ec_line_tax_guard()'::regprocedure);a:='elsif e.source_type=''adjustment''';if strpos(s,a)=0 then raise exception 'RETURN_TAX_GUARD_ANCHOR';end if;
 s:=replace(s,a,'elsif e.source_type in(''return_credit'',''supplier_credit'') then select tax_calculation into calc from public.return_credits where id=e.source_id;elsif e.source_type=''return_refund'' then select tax_calculation into calc from public.return_refunds where id=e.source_id;'||a);execute s;
 s:=pg_get_functiondef('private.coco_tax_report_components(date,date)'::regprocedure);a:='union all select ''adjustment''';if strpos(s,a)=0 then raise exception 'RETURN_TAX_REPORT_ANCHOR';end if;
 s:=replace(s,a,'union all select case when i.invoice_id is not null then ''return_credit'' else ''supplier_credit'' end,i.id,case when i.invoice_id is not null then ''sale'' else ''purchase'' end,-1,i.tax_calculation from public.return_credits i where i.tax_calculation is not null union all select ''return_refund'',i.id,''sale'',-1,i.tax_calculation from public.return_refunds i where i.tax_calculation is not null '||a);execute s;
end $$;
revoke all on function private.coco_sales_return_calculation(uuid),private.coco_sales_return_money_delta(jsonb,numeric,numeric),private.coco_sales_return_freeze(),private.coco_return_order_tax_freeze(),private.coco_sales_return_post(text,uuid,date),private.gama_accounting_post_before_frozen_returns(text,uuid),private.gama_accounting_post_at_before_frozen_returns(text,uuid,date),private.gama_accounting_post(text,uuid),private.gama_accounting_post_at(text,uuid,date),private.gama_return_amount_before_frozen_components(uuid),private.gama_return_split_before_frozen_components(uuid,numeric),private.gama_return_split(uuid,numeric) from public,anon,authenticated,service_role;
revoke all on function private.gama_return_amount(uuid) from public,anon,service_role;grant execute on function private.gama_return_amount(uuid) to authenticated;
-- Reverse the original stock invoice's actual expense accounts, preserving its
-- received-not-invoiced counter account and existing stock credit source link.
create function private.coco_return_stock_reclass_lines(p_calc jsonb,p_counter uuid,p_net numeric,p_legacy uuid) returns jsonb language sql immutable security invoker set search_path='' as $$
 select case when p_calc->>'schema'='coco.tax.v1' then jsonb_build_array(jsonb_build_object('account_id',p_counter,'credit',p_net))||coalesce((select jsonb_agg(jsonb_build_object('account_id',g.aid,'debit',g.net)) from(select x->>'account_id' aid,sum((x->>'subtotal')::numeric) net from jsonb_array_elements(p_calc->'lines')x group by x->>'account_id')g),'[]')
 else jsonb_build_array(jsonb_build_object('account_id',p_legacy,'debit',p_net),jsonb_build_object('account_id',p_counter,'credit',p_net)) end
$$;
do $$declare s text;a text;begin s:=pg_get_functiondef('private.gama_stock_credit_reclass(uuid)'::regprocedure);
 a:='jsonb_build_array(jsonb_build_object(''account_id'',cfg.purchase_account_id,''debit'',net),jsonb_build_object(''account_id'',counter,''credit'',net))';if strpos(s,a)=0 then raise exception 'FROZEN_RETURN_STOCK_ANCHOR';end if;
 s:=replace(s,a,'private.coco_return_stock_reclass_lines(k.tax_calculation,counter,net,cfg.purchase_account_id)');
 a:='net:=(private.gama_return_split(k.return_id,k.amount)->>''net'')::numeric;';if strpos(s,a)=0 then raise exception 'FROZEN_RETURN_STOCK_NET_ANCHOR';end if;execute replace(s,a,'net:=coalesce((k.tax_calculation->>''subtotal'')::numeric,(private.gama_return_split(k.return_id,k.amount)->>''net'')::numeric);');end $$;

alter function private.gama_returns_action(text,jsonb) rename to gama_returns_action_before_frozen_components;
create function private.gama_returns_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare result jsonb;o public.return_orders;bill public.supplier_invoices;iid uuid;n integer;begin
 if p_action='supplier_credit' then
  -- Resolve the existing document with the established rights checks first.
  perform private.gama_returns_action_before_frozen_components('detail',jsonb_build_object('id',p_data->'id'));
  if not (private.gama_returns_rights()->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  select * into o from public.return_orders where id=(p_data->>'id')::uuid for update;iid:=coalesce(nullif(p_data->>'supplier_invoice_id','')::uuid,o.supplier_invoice_id);
  if iid is not null and iid is distinct from o.supplier_invoice_id then
   select * into bill from public.supplier_invoices where id=iid and supplier_id=o.supplier_id and status='posted' and (purchase_order_id is null or purchase_order_id=o.purchase_order_id);
   if not found then raise exception 'SUPPLIER_INVOICE_NOT_AVAILABLE';end if;
   if exists(select 1 from public.return_credits where return_id=o.id) then raise exception 'RETURN_INVOICE_LOCKED';end if;
   update public.return_orders set supplier_invoice_id=iid,updated_at=now() where id=o.id;
  end if;
 end if;
 result:=private.gama_returns_action_before_frozen_components(p_action,p_data);
 if p_action='create' and p_data->>'kind'='supplier' then
  select * into o from public.return_orders where id=(result->>'id')::uuid;
  select count(*),min(id::text)::uuid into n,iid from public.supplier_invoices where supplier_id=o.supplier_id and purchase_order_id=o.purchase_order_id and status='posted';
  if n=1 then update public.return_orders set supplier_invoice_id=iid,updated_at=now() where id=o.id;end if;
 elsif p_action='detail' and result->>'kind'='supplier' and coalesce((result#>>'{rights,refund}')::boolean,false) then
  select * into o from public.return_orders where id=(p_data->>'id')::uuid;
  result:=result||jsonb_build_object('supplier_invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'number',i.number,'total',i.total) order by i.issue_date desc,i.id) from public.supplier_invoices i where i.supplier_id=o.supplier_id and i.status='posted' and (i.purchase_order_id is null or i.purchase_order_id=o.purchase_order_id)),'[]'));
 end if;return result;
end $$;
revoke all on function private.coco_return_component_bases(jsonb),private.coco_supplier_return_calculation(uuid),private.coco_return_stock_reclass_lines(jsonb,uuid,numeric,uuid),private.gama_returns_action_before_frozen_components(text,jsonb) from public,anon,authenticated,service_role;
revoke all on function private.gama_returns_action(text,jsonb) from public,anon,service_role;grant execute on function private.gama_returns_action(text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
