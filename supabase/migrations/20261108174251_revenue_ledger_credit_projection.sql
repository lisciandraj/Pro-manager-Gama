-- Revenue follows posted income movements, including dated credits and their
-- reversals. Frozen commercial lines supply dimensions, never new money.
begin;
create function private.coco_revenue_pieces(p_entry uuid,p_depth integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare e public.accounting_entries;inv public.external_invoices;a public.accounting_adjustments;r public.return_orders;
 calc jsonb;items jsonb;pieces jsonb:='[]';outlines jsonb:='[]';x jsonb;detail jsonb;plan private.accounting_plans;batch private.accounting_deferral_batches;
 iid uuid;rid uuid;source_entry uuid;customer uuid;client text;weight numeric;denominator numeric;sign numeric:=1;label text;
begin
 if p_depth>8 then return '[]';end if;
 select * into e from public.accounting_entries where id=p_entry;if not found then return '[]';end if;
 if e.reversal_of is not null or e.source_type in('reversal','accounting_plan_reversal') then
  pieces:=private.coco_revenue_pieces(coalesce(e.reversal_of,e.source_id),p_depth+1);
  return coalesce((select jsonb_agg(v||jsonb_build_object('subtotal',-(v->>'subtotal')::numeric) order by n) from jsonb_array_elements(pieces) with ordinality z(v,n)),'[]');
 end if;
 if e.source_type='sales_invoice' then iid:=e.source_id;
 elsif e.source_type='adjustment' then
  select * into a from public.accounting_adjustments where id=e.source_id and side='customer';if not found then return '[]';end if;
  iid:=a.invoice_id;calc:=a.tax_calculation;sign:=case when a.kind='credit' then -1 else 1 end;
 elsif e.source_type in('return_credit','return_refund') then
  if e.source_type='return_credit' then
   select k.tax_calculation,k.return_id into calc,rid from public.return_credits k where k.id=e.source_id and k.invoice_id is not null;
  else
   select k.tax_calculation,k.return_id into calc,rid from public.return_refunds k where k.id=e.source_id;
  end if;
  select * into r from public.return_orders where id=rid;if r.id is null then return '[]';end if;iid:=r.invoice_id;sign:=-1;
  if calc is null then
   select jsonb_agg(jsonb_build_object('product_id',l.product_id,'name',coalesce((select ol.product_name from public.sales_delivery_lines dl join public.sales_order_lines ol on ol.id=dl.order_line_id where dl.id=l.delivery_line_id),p.name),'subtotal',l.quantity*l.unit_price) order by l.id)
    into items from public.return_lines l join public.products p on p.id=l.product_id where l.return_id=r.id;
  end if;
 elsif e.source_type in('accounting_plan_opening','accounting_schedule') then
  if e.source_type='accounting_plan_opening' then select * into plan from private.accounting_plans where id=e.source_id;
  else select p.* into plan from private.accounting_plan_items it join private.accounting_plans p on p.id=it.plan_id where it.id=e.source_id;end if;
  if plan.id is null then return '[]';end if;
  select entry_id into source_entry from public.accounting_entry_lines where id=plan.source_line_id;
  pieces:=private.coco_revenue_pieces(source_entry,p_depth+1);
  if plan.invoice_line_key is not null and exists(select 1 from jsonb_array_elements(pieces)v where v->>'key'=plan.invoice_line_key) then
   select jsonb_agg(v order by n) into pieces from jsonb_array_elements(pieces) with ordinality z(v,n) where v->>'key'=plan.invoice_line_key;
  else
   select coalesce(jsonb_agg(v order by n),'[]') into pieces from jsonb_array_elements(pieces) with ordinality z(v,n)
    where (v->>'account_id' is null or v->>'account_id'=(select account_id::text from public.accounting_entry_lines where id=plan.source_line_id));
  end if;return pieces;
 elsif e.source_type in('deferral_closing','deferral_reversal','deferral_correction') then
  select * into batch from private.accounting_deferral_batches b where b.id=e.source_id or e.id in(b.entry_id,b.reversal_entry_id,b.correction_id,b.reversal_correction_id) limit 1;
  if batch.id is null then return '[]';end if;
  for plan in select p.* from private.accounting_deferral_batch_plans bp join private.accounting_plans p on p.id=bp.plan_id where bp.batch_id=batch.id order by p.id loop
   select entry_id into source_entry from public.accounting_entry_lines where id=plan.source_line_id;
   pieces:=private.coco_revenue_pieces(source_entry,p_depth+1);
   select coalesce(jsonb_agg(v order by n),'[]') into pieces from jsonb_array_elements(pieces) with ordinality z(v,n)
    where (v->>'account_id' is null or v->>'account_id'=(select account_id::text from public.accounting_entry_lines where id=plan.source_line_id))
    and (plan.invoice_line_key is null or v->>'key'=plan.invoice_line_key);
   select coalesce((v->>'remaining')::numeric,plan.amount) into weight from jsonb_array_elements(batch.snapshot->'rows')v where v->>'id'=plan.id::text;
   select sum((v->>'subtotal')::numeric) into denominator from jsonb_array_elements(pieces)v;
   if denominator is not null and denominator<>0 then
    select outlines||coalesce(jsonb_agg(v||jsonb_build_object('subtotal',(v->>'subtotal')::numeric*coalesce(weight,plan.amount)/denominator) order by n),'[]') into outlines from jsonb_array_elements(pieces) with ordinality z(v,n);
   end if;
  end loop;return outlines;
 else return '[]';end if;
 select * into inv from public.external_invoices where id=iid;if not found then return '[]';end if;
 customer:=inv.customer_id;client:=coalesce(inv.document_snapshot->>'customer',(select customer_name from public.sales_orders where id=inv.order_id),(select name from public.customers where id=customer));
 if calc is null then calc:=inv.document_snapshot->'tax_calculation';end if;
 if items is null then items:=coalesce(calc->'lines',inv.document_snapshot->'lines','[]');end if;
 if items='[]'::jsonb then
  select coalesce(jsonb_agg(jsonb_build_object('key',l.id,'product_id',l.product_id,'name',l.product_name,'subtotal',l.subtotal) order by l.id),'[]') into items from private.coco_invoice_line_values l where l.invoice_id=inv.id;
 end if;
 for x in select value from jsonb_array_elements(items) loop
  -- Expense compensation on an earned cash discount is not sales revenue.
  if nullif(x->>'account_id','') is not null and not exists(select 1 from public.accounting_accounts ac where ac.id=(x->>'account_id')::uuid and ac.type='income') then continue;end if;
  select value into detail from jsonb_array_elements(coalesce(inv.document_snapshot->'lines','[]'))v where
   coalesce(v->>'source_line_id',v->>'line_id',v->>'key')=coalesce(x->>'source_line_id',x->>'key',x->>'line_id') limit 1;
  label:=coalesce(nullif(x->>'name',''),nullif(x->>'description',''),nullif(detail->>'name',''),nullif(detail->>'description',''),(select name from public.products where id=nullif(x->>'product_id','')::uuid),'—');
  weight:=coalesce((x->>'subtotal')::numeric,(x->>'qty')::numeric*(x->>'price')::numeric,(x->>'quantity')::numeric*(x->>'unit_price')::numeric,0);
  outlines:=outlines||jsonb_build_array(jsonb_build_object('key',coalesce(x->>'source_line_id',x->>'key',x->>'line_id'),'account_id',x->>'account_id','product',label,'customer_id',customer,'customer',coalesce(client,'—'),'subtotal',weight*sign));
 end loop;return outlines;
end $$;
revoke all on function private.coco_revenue_pieces(uuid,integer) from public,anon,authenticated,service_role;

create function private.coco_revenue_ledger(p_from date,p_to date,p_scope text) returns jsonb
language sql stable security definer set search_path='' as $$
 with ledger as materialized(
  select e.id entry_id,e.entry_date,l.account_id,sum(l.credit-l.debit) amount
  from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id join public.accounting_accounts ac on ac.id=l.account_id
  where e.status in('posted','reversed') and ac.type='income' and e.entry_date between p_from and p_to
  group by e.id,e.entry_date,l.account_id
 ),sources as materialized(
  select e.entry_id,private.coco_revenue_pieces(e.entry_id) pieces from(select distinct entry_id from ledger)e
 ),eligible as(
  select g.*,s.pieces,
   exists(select 1 from jsonb_array_elements(s.pieces)x where x->>'account_id'=g.account_id::text) matching
  from ledger g join sources s using(entry_id)
 ),weighted as(
  select g.entry_id,g.entry_date,g.account_id,g.amount,x.value obj,x.ordinality n,
   (x.value->>'subtotal')::numeric weight
  from eligible g cross join lateral jsonb_array_elements(g.pieces) with ordinality x
  where (not g.matching or x.value->>'account_id'=g.account_id::text)
 ),running as(
  select w.*,sum(weight) over(partition by entry_id,account_id) denominator,
   sum(weight) over(partition by entry_id,account_id order by n) prefix from weighted w
 ),pieces as(
  select entry_id,entry_date,account_id,coalesce(obj->>'customer','—') customer,coalesce(obj->>'product','—') product,
   case when denominator<>0 then round(amount*prefix/denominator,2)-round(amount*(prefix-weight)/denominator,2) else round(weight,2) end amount
  from running where denominator<>0 or amount=0
  union all
  select g.entry_id,g.entry_date,g.account_id,'—','—',g.amount from eligible g
  where (p_scope='all') and(not exists(select 1 from weighted w where w.entry_id=g.entry_id and w.account_id=g.account_id)
   or(g.amount<>0 and(select sum(w.weight) from weighted w where w.entry_id=g.entry_id and w.account_id=g.account_id)=0))
 ),months as(select to_char(entry_date,'YYYY-MM') key,sum(amount) amount from pieces group by 1),
 customers as(select customer key,sum(amount) amount from pieces group by 1 order by sum(amount) desc,customer limit 20),
 products as(select product key,sum(amount) amount from pieces group by 1 order by sum(amount) desc,product limit 20)
 select jsonb_build_object('from',p_from,'to',p_to,
  'by_month',coalesce((select jsonb_agg(jsonb_build_object('key',key,'amount',round(amount,2)) order by key) from months),'[]'),
  'by_customer',coalesce((select jsonb_agg(jsonb_build_object('key',key,'amount',round(amount,2)) order by amount desc,key) from customers),'[]'),
  'by_product',coalesce((select jsonb_agg(jsonb_build_object('key',key,'amount',round(amount,2)) order by amount desc,key) from products),'[]'))
$$;
revoke all on function private.coco_revenue_ledger(date,date,text) from public,anon,authenticated,service_role;

-- Keep the established authorization/default-date chain and every other report.
do $$declare s text;anchor text:='elsif p_action=''report_revenue'' then';begin
 s:=pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure);
 if strpos(s,anchor)=0 then raise exception 'REVENUE_LEDGER_REPORT_ANCHOR';end if;
 execute replace(s,anchor,anchor||' return private.coco_revenue_ledger(d1,d2,scope);');
end $$;
commit;
