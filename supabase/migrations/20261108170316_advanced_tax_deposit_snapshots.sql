-- Advance invoices preserve each accepted tax component and release exactly the
-- same components over partial final invoices, including fixed/compound rules.
-- These overrides exist only in trusted frozen snapshots, never in tax masters.
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_tax_calculate_frozen(jsonb,text)'::regprocedure);
 s:=replace(s,$replace$if kind='fixed' then a:=0;b:=tqty*fixed*direction;else a:=coefficient*rate/100;b:=constant*rate/100;end if;$replace$,$replace$if r ? 'frozen_amount' then a:=0;b:=private.coco_tax_number(r->'frozen_amount');elsif kind='fixed' then a:=0;b:=tqty*fixed*direction;else a:=coefficient*rate/100;b:=constant*rate/100;end if; $replace$);
 s:=replace(s,$replace$taxamount:=case when kind='fixed' then tqty*fixed*direction else base*rate/100 end;$replace$,$replace$taxamount:=case when r ? 'frozen_amount' then private.coco_tax_number(r->'frozen_amount')*case when kind='percent' then factor else 1 end when kind='fixed' then tqty*fixed*direction else base*rate/100 end; if r ? 'frozen_base' then base:=private.coco_tax_number(r->'frozen_base')*factor;end if;$replace$);execute s;
end $$;
create function private.coco_tax_scale_snapshot(p_calc jsonb,p_factor numeric,p_account uuid default null) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
#variable_conflict use_column
declare ls jsonb:='[]';l jsonb;r jsonb;rules jsonb;begin
 if p_calc->>'schema'<>'coco.tax.v1' or p_factor::text in('NaN','Infinity','-Infinity') or abs(p_factor)>1 then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 for l in select value from jsonb_array_elements(p_calc->'lines') loop
  rules:='[]';for r in select value from jsonb_array_elements(l->'taxes') loop
   rules:=rules||jsonb_build_array(r-'amount'-'base'-'amount_unrounded'-'base_unrounded'-'group_key'||jsonb_build_object('frozen_amount',(r->>'amount')::numeric*p_factor,'frozen_base',(r->>'base')::numeric*p_factor,'price_included',false));
  end loop;
  ls:=ls||jsonb_build_array(l||jsonb_build_object('source_line_id',coalesce(l->'source_line_id',l->'key'),'quantity',1,'tax_quantity',1,'unit_price',(l->>'subtotal')::numeric*p_factor,'entered_unit_price',(l->>'subtotal')::numeric*p_factor,'discount',0,'tax_base_factor',1,'force_price_excluded',true,'rules',rules,'account_id',coalesce(p_account::text,l->>'account_id')));
 end loop;return private.coco_tax_calculate_frozen(ls,'global')||jsonb_build_object('side',p_calc->'side','date',p_calc->'date','fiscal_position_id',p_calc->'fiscal_position_id');
end $$;
create table private.coco_tax_deposit_buckets(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.external_invoices(id),order_id uuid not null references public.sales_orders(id),
 order_line_id uuid not null references public.sales_order_lines(id),tax_calculation jsonb not null,created_at timestamptz not null default now(),unique(invoice_id,order_line_id)
);
create table private.coco_tax_deposit_uses(
 id uuid primary key default gen_random_uuid(),bucket_id uuid not null references private.coco_tax_deposit_buckets(id),invoice_id uuid not null references public.external_invoices(id),
 tax_calculation jsonb not null,created_at timestamptz not null default now(),unique(bucket_id,invoice_id)
);
create index coco_tax_deposit_buckets_order on private.coco_tax_deposit_buckets(order_id);
alter table private.coco_tax_deposit_buckets enable row level security;alter table private.coco_tax_deposit_uses enable row level security;
revoke all on private.coco_tax_deposit_buckets,private.coco_tax_deposit_uses from public,anon,authenticated,service_role;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('coco_tax_deposit_buckets','accounting','Impuestos del anticipo','private','id'),('coco_tax_deposit_uses','accounting','Deducción del anticipo','private','id');
create trigger coco_module_history after insert or update or delete on private.coco_tax_deposit_buckets for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.coco_tax_deposit_uses for each row execute function private.coco_capture_module_event();
create function private.coco_tax_deposit_preview(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare o public.sales_orders;l public.sales_order_lines;raw jsonb:='[]';previous jsonb:='[]';one jsonb;calc jsonb;oldcalc jsonb;dep jsonb;target numeric;used numeric;begin
 select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid;if not found or o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
 for l in select * from public.sales_order_lines where order_id=o.id order by id loop
  one:=jsonb_strip_nulls(jsonb_build_object('key',l.id,'product_id',l.product_id,'quantity',l.quantity,'unit_price',coalesce((l.tax_snapshot->>'entered_unit_price')::numeric,l.unit_price),'discount',coalesce((l.tax_snapshot->>'discount')::numeric,0),'tax_rate',l.tax_rate,'tax_ids',to_jsonb(l.tax_ids),'tax_quantity',case when l.line_kind in('discount','reward') then 0 else l.quantity end,'force_price_excluded',l.line_kind<>'product'));
  raw:=raw||jsonb_build_array(one);if l.tax_snapshot is not null then previous:=previous||jsonb_build_array(one||jsonb_build_object('rules',l.tax_snapshot->'rules','account_id',l.tax_snapshot->'account_id'));else previous:=previous||jsonb_build_array(private.coco_tax_compute('sale',o.customer_id,(now() at time zone private.erp_timezone())::date,jsonb_build_array(one),o.tax_fiscal_position_id,coalesce(o.tax_rounding,'line'))#>'{lines,0}');end if;
 end loop;
 calc:=private.coco_tax_compute('sale',o.customer_id,(now() at time zone private.erp_timezone())::date,raw,o.tax_fiscal_position_id,coalesce(o.tax_rounding,'line'));oldcalc:=private.coco_tax_calculate_frozen(previous,coalesce(o.tax_rounding,'line'));
 if p_data->>'kind'='percent' then target:=round((calc->>'subtotal')::numeric*private.coco_tax_number(p_data->'amount')/100,2);elsif p_data->>'kind'='fixed' then target:=private.coco_tax_number(p_data->'amount');else raise exception 'INVALID_DATA';end if;
 if target<=0 or target<>round(target,2) or (p_data->>'kind'='percent' and private.coco_tax_number(p_data->'amount')>100) then raise exception 'INVALID_AMOUNT';end if;
 select coalesce(sum((i.document_snapshot#>>'{tax_calculation,subtotal}')::numeric),0) into used from public.external_invoices i where order_id=o.id and fiscal_status not in('cancelled','rejected') and document_snapshot->>'invoice_role'='down_payment';
 if target+used>(calc->>'subtotal')::numeric then raise exception 'DEPOSIT_EXCEEDS_ORDER';end if;
 dep:=private.coco_tax_scale_snapshot(calc,target/(calc->>'subtotal')::numeric);
 return jsonb_build_object('calculation',dep,'previous_calculation',private.coco_tax_scale_snapshot(oldcalc,least(1,target/(oldcalc->>'subtotal')::numeric)),'tax_rules_changed',calc->'tax' is distinct from oldcalc->'tax' or calc->'subtotal' is distinct from oldcalc->'subtotal','confirmation_key',md5(dep::text));
end $$;
alter function private.sales_deposit_create(jsonb) rename to sales_deposit_create_before_tax_components;
create function private.sales_deposit_create(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare o public.sales_orders;cfg public.company_settings;client public.customers;account uuid;key uuid;old private.sales_workspace_requests;prep jsonb;calc jsonb;items jsonb;l jsonb;bucketcalc jsonb;inv public.external_invoices;begin
 perform private.sales_access('invoice_create');perform pg_advisory_xact_lock(741932,1);
 select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid;
 if not exists(select 1 from public.sales_order_lines where order_id=o.id and tax_ids is not null) then return private.sales_deposit_create_before_tax_components(p_data);end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into old from private.sales_workspace_requests where request_key=key for update;if found then if old.actor_id<>auth.uid() or old.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;if old.response is not null then return old.response;end if;else insert into private.sales_workspace_requests(request_key,actor_id,payload) values(key,auth.uid(),p_data);end if;
 perform 1 from public.sales_orders where id=o.id for update;
 if exists(select 1 from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id join public.sales_order_lines sl on sl.id=il.order_line_id where sl.order_id=o.id and i.fiscal_status not in('cancelled','rejected')) then raise exception 'DEPOSIT_BEFORE_FINAL_INVOICE_REQUIRED';end if;
 select deposit_account_id into account from private.sales_workspace_settings where id;if not exists(select 1 from public.accounting_accounts where id=account and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
 prep:=private.coco_tax_deposit_preview(p_data);if (prep->>'tax_rules_changed')::boolean and p_data->>'tax_confirmation' is distinct from prep->>'confirmation_key' then raise exception 'TAX_RULES_CHANGED' using detail=prep::text;end if;
 calc:=private.coco_tax_scale_snapshot(prep->'calculation',1,account);
 select jsonb_agg(jsonb_build_object('order_id',o.id,'name','Anticipo / Down payment','qty',1,'price',value->'subtotal','taxRate',0,'subtotal',value->'subtotal','tax',value->'tax','is_down_payment',true,'tax_snapshot',value) order by ordinality) into items from jsonb_array_elements(calc->'lines') with ordinality;
 select * into cfg from public.company_settings where id;select * into client from public.customers where id=o.customer_id;
 insert into public.external_invoices(request_key,order_id,number,software,issue_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot)
 values(key,o.id,'FI-'||to_char((now() at time zone private.erp_timezone())::date,'YYYY')||'-'||lpad(nextval('private.gama_internal_invoice_number')::text,8,'0'),'Coco ERP',(now() at time zone private.erp_timezone())::date,(calc->>'subtotal')::numeric,(calc->>'tax')::numeric,'unverified',auth.uid(),'internal',o.source_quote_id,
 jsonb_build_object('sales_schema','coco.sales.invoice.v2','invoice_role','down_payment','liability_account_id',account,'tax_calculation',calc,'company',private.gama_company_public(cfg),'order_number',o.number,'orders',jsonb_build_array(jsonb_build_object('id',o.id,'number',o.number)),'customer',o.customer_name,'customer_identification',o.customer_identification,'lines',items,'details',jsonb_build_object('seller',cfg.legal_name,'sellerRuc',cfg.tax_id,'client',o.customer_name,'clientId',o.customer_identification,'clientEmail',client.email,'clientAddress',client.address,'delivery_address',o.delivery_address))) returning * into inv;
 for l in select value from jsonb_array_elements(calc->'lines') loop
  bucketcalc:=private.coco_tax_calculate_frozen(jsonb_build_array(l),'line');
  insert into private.coco_tax_deposit_buckets(invoice_id,order_id,order_line_id,tax_calculation) values(inv.id,o.id,(l->>'source_line_id')::uuid,bucketcalc);
 end loop;
 insert into private.sales_invoice_orders values(inv.id,o.id,inv.subtotal,inv.tax);update public.external_invoices set due_date=issue_date+payment_terms_days where id=inv.id;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(o.id,'deposit_created',inv.id,auth.uid(),jsonb_build_object('number',inv.number,'subtotal',inv.subtotal));
 update private.sales_workspace_requests set response=jsonb_build_object('id',inv.id,'number',inv.number) where request_key=key;return jsonb_build_object('id',inv.id,'number',inv.number);
end $$;

alter function private.sales_deposit_deductions(uuid[],jsonb) rename to sales_deposit_deductions_before_tax_components;
create function private.sales_deposit_deductions(p_orders uuid[],p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare items jsonb;d record;used_qty numeric;selected_qty numeric;ratio numeric;target jsonb;piece jsonb;l jsonb;r jsonb;rules jsonb;net numeric;prior numeric;priorbase numeric;prioramount numeric;begin
 items:=private.sales_deposit_deductions_before_tax_components(p_orders,p_items);
 for d in select b.*,sl.quantity ordered_quantity,inv.number from private.coco_tax_deposit_buckets b join public.external_invoices inv on inv.id=b.invoice_id join public.sales_order_lines sl on sl.id=b.order_line_id where b.order_id=any(p_orders) and inv.fiscal_status not in('cancelled','rejected') order by b.invoice_id,b.order_line_id for update of b loop
  select coalesce(sum(il.quantity),0) into used_qty from public.external_invoice_lines il join public.external_invoices inv on inv.id=il.invoice_id where il.order_line_id=d.order_line_id and inv.fiscal_status not in('cancelled','rejected');
  select coalesce(sum((x->>'qty')::numeric),0) into selected_qty from jsonb_array_elements(p_items)x where x->>'line_id'=d.order_line_id::text;
  if selected_qty<=0 then continue;end if;ratio:=least(1,(used_qty+selected_qty)/d.ordered_quantity);
  target:=private.coco_tax_scale_snapshot(d.tax_calculation,ratio);l:=target#>'{lines,0}';
  select coalesce(sum((u.tax_calculation->>'subtotal')::numeric),0) into prior from private.coco_tax_deposit_uses u join public.external_invoices inv on inv.id=u.invoice_id where u.bucket_id=d.id and inv.fiscal_status not in('cancelled','rejected');net:=(target->>'subtotal')::numeric-prior;
  rules:='[]';for r in select value from jsonb_array_elements(l->'taxes') loop
   select coalesce(sum((x->>'amount')::numeric),0),coalesce(sum((x->>'base')::numeric),0) into prioramount,priorbase from private.coco_tax_deposit_uses u join public.external_invoices inv on inv.id=u.invoice_id cross join lateral jsonb_array_elements(u.tax_calculation->'taxes')x where u.bucket_id=d.id and inv.fiscal_status not in('cancelled','rejected') and x->'id' is not distinct from r->'id' and x->'account_id' is not distinct from r->'account_id';
   rules:=rules||jsonb_build_array(r||jsonb_build_object('price_included',false,'frozen_amount',(r->>'amount')::numeric-prioramount,'frozen_base',(r->>'base')::numeric-priorbase));
  end loop;
  piece:=private.coco_tax_calculate_frozen(jsonb_build_array(l||jsonb_build_object('unit_price',net,'entered_unit_price',net,'rules',rules)),'line');
  if net=0 and (piece->>'tax')::numeric=0 then continue;end if;
  items:=items||jsonb_build_array(jsonb_build_object('order_id',d.order_id,'name','Deducción anticipo '||d.number,'qty',-1,'price',net,'taxRate',0,'subtotal',-net,'tax',-(piece->>'tax')::numeric,'is_deposit_deduction',true,'deposit_invoice_id',d.invoice_id,'liability_account_id',l->'account_id','tax_deposit_bucket_id',d.id,'tax_deposit_use',piece,'tax_snapshot',private.coco_tax_scale_snapshot(piece,-1)#>'{lines,0}'));
 end loop;return items;
end $$;
-- Extend the existing allocation transaction; merchandise quantities remain in
-- external_invoice_lines and advance allocations have their own immutable rows.
do $$declare s text;a text;begin
 s:=pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure);
 a:='insert into private.sales_deposit_uses(deposit_invoice_id,tax_rate,invoice_id,subtotal,tax) values((x->>''deposit_invoice_id'')::uuid,(x->>''taxRate'')::numeric,inv.id,-(x->>''subtotal'')::numeric,-(x->>''tax'')::numeric);';
 if strpos(s,a)=0 then raise exception 'TAX_DEPOSIT_USE_ANCHOR';end if;
 s:=replace(s,a,$body$if x ? 'tax_deposit_bucket_id' then insert into private.coco_tax_deposit_uses(bucket_id,invoice_id,tax_calculation) values((x->>'tax_deposit_bucket_id')::uuid,inv.id,x->'tax_deposit_use');else $body$||a||'end if;');execute s;
end $$;
alter function private.coco_sales_invoice_tax_prepare(jsonb,jsonb) rename to coco_sales_invoice_tax_prepare_before_deposits;
create function private.coco_sales_invoice_tax_prepare(p_data jsonb,p_items jsonb default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare result jsonb;items jsonb;adv jsonb;ls jsonb;calc jsonb;idlist uuid[];x jsonb;begin
 if p_items is not null then select coalesce(jsonb_agg(value order by ordinality),'[]') into items from jsonb_array_elements(p_items) with ordinality where not(value ? 'tax_deposit_bucket_id');end if;
 result:=private.coco_sales_invoice_tax_prepare_before_deposits(p_data,items);
 if p_items is null then
  select array_agg(value::uuid) into idlist from jsonb_array_elements_text(p_data->'order_ids');
  adv:=private.sales_deposit_deductions(idlist,result->'items');
 else select coalesce(jsonb_agg(value order by ordinality),'[]') into adv from jsonb_array_elements(p_items) with ordinality where value ? 'tax_deposit_bucket_id';end if;
 if adv='[]'::jsonb then return result;end if;
 calc:=private.coco_tax_scale_snapshot(result->'calculation',1);ls:=calc->'lines';items:=result->'items';
 for x in select value from jsonb_array_elements(adv) loop
  if not(x ? 'tax_deposit_bucket_id') then continue;end if;ls:=ls||jsonb_build_array(x->'tax_snapshot');items:=items||jsonb_build_array(x);
 end loop;
 calc:=private.coco_tax_calculate_frozen(ls,'global')||jsonb_build_object('side','sale','date',result#>'{calculation,date}','fiscal_position_id',result#>'{calculation,fiscal_position_id}','deposit_allocations',true);
 if (calc->>'total')::numeric<0 then raise exception 'INVOICE_TOTAL_INVALID';end if;
 return result||jsonb_build_object('calculation',calc,'items',items,'confirmation_key',md5(calc::text));
end $$;
-- The immutable component snapshot is also the posting source for advances and
-- deductions. Positive liability bases are credited; deductions debit them.
alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_tax_deposits;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare inv public.external_invoices;o public.sales_orders;calc jsonb;lines jsonb;x jsonb;eid uuid;ar uuid;amount numeric;begin
 if p_source_type<>'sales_invoice' then return private.gama_accounting_post_before_tax_deposits(p_source_type,p_source_id);end if;
 select * into inv from public.external_invoices where id=p_source_id;calc:=inv.document_snapshot->'tax_calculation';
 if calc->>'schema' is distinct from 'coco.tax.v1' or not(coalesce(inv.document_snapshot->>'invoice_role'='down_payment',false) or coalesce((calc->>'deposit_allocations')::boolean,false)) then return private.gama_accounting_post_before_tax_deposits(p_source_type,p_source_id);end if;
 if inv.fiscal_status in('cancelled','rejected') then return null;end if;perform pg_advisory_xact_lock(741932,1);
 select id into eid from public.accounting_entries where source_type=p_source_type and source_id=p_source_id and status<>'reversed';if eid is not null then return eid;end if;
 if (calc->>'subtotal')::numeric<>inv.subtotal or (calc->>'tax')::numeric<>inv.tax or (select sum((x->>'subtotal')::numeric) from jsonb_array_elements(calc->'lines')x)<>inv.subtotal or (select coalesce(sum((x->>'amount')::numeric),0) from jsonb_array_elements(calc->'taxes')x)<>inv.tax then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 select * into o from public.sales_orders where id=inv.order_id;ar:=private.gama_partner_account('customer',o.customer_id,inv.id);
 lines:=jsonb_build_array(jsonb_build_object('account_id',ar,'label',o.customer_name,'debit',inv.total,'partner_type','customer','partner_id',o.customer_id,'partner_account_fixed',true));
 for x in select value from jsonb_array_elements(calc->'lines') loop amount:=(x->>'subtotal')::numeric;if amount=0 then continue;end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',x->'account_id','label',case when inv.document_snapshot->>'invoice_role'='down_payment' then 'Anticipo' else 'Venta / Deducción anticipo' end,'debit',greatest(-amount,0),'credit',greatest(amount,0)));
 end loop;
 for x in select value from jsonb_array_elements(calc->'taxes') loop amount:=(x->>'amount')::numeric;if amount=0 then continue;end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',x->'account_id','tax_id',x->'id','label',coalesce(x->>'name',x->>'code','Impuesto'),'debit',greatest(-amount,0),'credit',greatest(amount,0)));
 end loop;
 eid:=private.gama_accounting_book('VTA',inv.issue_date,inv.number,'sales_invoice',inv.id,o.customer_name,lines);
 perform private.gama_invoice_deferrals_post(eid,'sales_invoice',inv.id);return eid;
end $$;
-- A consumed advance cannot be cancelled until its final invoices are cancelled.
create function private.coco_tax_deposit_cancel_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.fiscal_status in('cancelled','rejected') and old.fiscal_status not in('cancelled','rejected') and exists(select 1 from private.coco_tax_deposit_buckets b join private.coco_tax_deposit_uses u on u.bucket_id=b.id join public.external_invoices i on i.id=u.invoice_id where b.invoice_id=new.id and i.fiscal_status not in('cancelled','rejected')) then raise exception 'DEPOSIT_ALREADY_DEDUCTED';end if;return new;
end $$;
create trigger coco_tax_deposit_cancel before update on public.external_invoices for each row execute function private.coco_tax_deposit_cancel_guard();
alter function private.coco_tax_engine(text,jsonb) rename to coco_tax_engine_before_deposits;
create function private.coco_tax_engine(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action='deposit_preview' then perform private.sales_access('invoice_create');return private.coco_tax_deposit_preview(p_data);end if;return private.coco_tax_engine_before_deposits(p_action,p_data);
end $$;
revoke all on function private.coco_tax_scale_snapshot(jsonb,numeric,uuid),private.coco_tax_deposit_preview(jsonb),private.sales_deposit_create_before_tax_components(jsonb),private.sales_deposit_create(jsonb),private.sales_deposit_deductions_before_tax_components(uuid[],jsonb),private.sales_deposit_deductions(uuid[],jsonb),private.coco_sales_invoice_tax_prepare_before_deposits(jsonb,jsonb),private.coco_sales_invoice_tax_prepare(jsonb,jsonb),private.gama_accounting_post_before_tax_deposits(text,uuid),private.gama_accounting_post(text,uuid),private.coco_tax_deposit_cancel_guard(),private.coco_tax_engine_before_deposits(text,jsonb),private.coco_tax_engine(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.coco_tax_engine(text,jsonb) to authenticated;

-- Classification is explicit: a fixed levy is not silently declared as VAT.
alter table public.accounting_taxes add column tax_category text not null default 'vat' check(tax_category in('vat','other'));
update public.accounting_taxes set tax_category='other' where calculation_type='fixed';
do $$declare s text;a text;begin
 s:=pg_get_functiondef('private.gama_accounting_tax_save(jsonb)'::regprocedure);
 a:='compound boolean;';if strpos(s,a)=0 then raise exception 'TAX_CATEGORY_DECLARATION_ANCHOR';end if;s:=replace(s,a,a||'category text;');
 a:='if calc not in(''percent'',''fixed'')';if strpos(s,a)=0 then raise exception 'TAX_CATEGORY_VALIDATE_ANCHOR';end if;
 s:=replace(s,a,$body$category:=coalesce(nullif(p_data->>'tax_category',''),old_tax.tax_category,case when calc='fixed' then 'other' else 'vat' end);if category not in('vat','other') then raise exception 'TAX_CATEGORY_INVALID';end if;
 $body$||a);
 s:=replace(s,'active,calculation_type,fixed_amount,price_included,sequence,include_base_amount)','active,calculation_type,fixed_amount,price_included,sequence,include_base_amount,tax_category)');
 s:=replace(s,'enabled,calc,fixed,included,seq,compound)','enabled,calc,fixed,included,seq,compound,category)');
 s:=replace(s,'include_base_amount=compound,version=old_tax.version+1','include_base_amount=compound,tax_category=category,version=old_tax.version+1');execute s;
end $$;
-- Component bases are read from issued snapshots. Reversals follow their actual
-- ledger dates, and credit/early-payment corrections retain their original tax.
create function private.coco_tax_report_components(p_from date,p_to date) returns jsonb language sql stable security definer set search_path='' as $$
 with origins as(
  select 'sales_invoice' typ,i.id,'sale' side,1 adjustment_sign,i.document_snapshot->'tax_calculation' calc from public.external_invoices i where i.document_snapshot->'tax_calculation' is not null
  union all select 'supplier_invoice',i.id,'purchase',1,i.tax_calculation from public.supplier_invoices i where i.tax_calculation is not null
  union all select 'expense',i.id,'purchase',1,i.tax_calculation from public.expenses i where i.tax_calculation is not null
  union all select 'adjustment',i.id,case when i.side='customer' then 'sale' else 'purchase' end,case when i.kind='credit' then -1 else 1 end,i.tax_calculation from public.accounting_adjustments i where i.tax_calculation is not null
 ),entries as(
  select e.id,e.entry_date,coalesce(original.source_type,e.source_type) typ,coalesce(original.source_id,e.source_id) origin,case when e.reversal_of is null then 1 else -1 end reversal_sign
  from public.accounting_entries e left join public.accounting_entries original on original.id=e.reversal_of where e.status in('posted','reversed') and e.entry_date between p_from and p_to
 ),components as(
  select e.id,e.origin,o.side,o.adjustment_sign*e.reversal_sign multiplier,t.* from entries e join origins o on o.typ=e.typ and o.id=e.origin cross join lateral jsonb_array_elements(coalesce(o.calc->'taxes','[]')) t(obj)
 ),grouped as(
  select side,obj->>'id' tax_id,obj->>'account_id' account_id,obj->>'code' code,coalesce(obj->>'name',obj->>'code') name,obj->>'calculation_type' calculation_type,
   coalesce(obj->>'tax_category',case when obj->>'calculation_type'='fixed' then 'other' else 'vat' end) tax_category,(obj->>'rate')::numeric rate,(obj->>'fixed_amount')::numeric fixed_amount,
   sum(multiplier*(obj->>'base')::numeric) base,sum(multiplier*(obj->>'amount')::numeric) amount,count(distinct origin) documents
  from components group by side,obj->>'id',obj->>'account_id',obj->>'code',coalesce(obj->>'name',obj->>'code'),obj->>'calculation_type',coalesce(obj->>'tax_category',case when obj->>'calculation_type'='fixed' then 'other' else 'vat' end),(obj->>'rate')::numeric,(obj->>'fixed_amount')::numeric
 )select coalesce(jsonb_agg(to_jsonb(g) order by side,code,account_id),'[]') from grouped g
$$;
revoke all on function private.coco_tax_report_components(date,date) from public,anon,authenticated,service_role;
alter function private.gama_accounting_action(text,jsonb) rename to gama_accounting_action_before_tax_components;
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;d1 date;d2 date;r jsonb;begin
 result:=private.gama_accounting_action_before_tax_components(p_action,p_data);
 if p_action='taxes' and private.gama_accounting_rights()->>'scope'='all' then
  d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',(now() at time zone private.erp_timezone())::date)::date);d2:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
  r:=private.coco_tax_report_components(d1,d2);result:=result||jsonb_build_object('components',r);
 end if;return result;
end $$;
revoke all on function private.gama_accounting_action_before_tax_components(text,jsonb),private.gama_accounting_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;
-- Form 104 remains a draft, and includes only explicitly classified VAT. Other
-- levies stay visible in the complete component report and the general ledger.
alter function private.gama_ec_tax_drafts(jsonb) rename to gama_ec_tax_drafts_before_tax_components;
create function private.gama_ec_tax_drafts(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;components jsonb;other_out numeric;other_in numeric;vat_out numeric;vat_in numeric;factor numeric;previous numeric;received numeric;form jsonb;begin
 result:=private.gama_ec_tax_drafts_before_tax_components(p_data);components:=private.coco_tax_report_components((p_data->>'from')::date,(p_data->>'to')::date);
 select coalesce(sum((x->>'amount')::numeric) filter(where x->>'side'='sale'),0),coalesce(sum((x->>'amount')::numeric) filter(where x->>'side'='purchase'),0) into other_out,other_in from jsonb_array_elements(components)x where x->>'tax_category'<>'vat';
 form:=result->'form104';vat_out:=(form->>'ledger_collected')::numeric-other_out;vat_in:=(form->>'ledger_deductible')::numeric-other_in;factor:=(form->>'credit_factor')::numeric;previous:=(form->>'previous_credit')::numeric;received:=(form->>'received_vat')::numeric;
 form:=form||jsonb_build_object('ledger_collected',vat_out,'ledger_deductible',vat_in,'other_taxes_collected',other_out,'other_taxes_deductible',other_in,'deductible_credit',round(vat_in*factor,2),'own_vat_payable',greatest(vat_out-round(vat_in*factor,2)-received-previous,0),'credit_next_period',greatest(round(vat_in*factor,2)+received+previous-vat_out,0),'frozen_components',components);
 return result||jsonb_build_object('form104',form);
end $$;
revoke all on function private.gama_ec_tax_drafts_before_tax_components(jsonb),private.gama_ec_tax_drafts(jsonb) from public,anon,service_role;grant execute on function private.gama_ec_tax_drafts(jsonb) to authenticated;
-- Existing provider-neutral preparation can encode one supported EC VAT rate.
-- Reject only fiscal preparation when the frozen legal mapping is unavailable.
do $$declare s text;a text;f regprocedure;n integer:=0;begin
 a:='saved:=v.document_snapshot;';
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='private' and p.proname like 'gama_sri_prepare%' and position(a in p.prosrc)>0 loop
 s:=pg_get_functiondef(f);n:=n+1;
 s:=replace(s,a,a||$body$
 if saved#>>'{tax_calculation,schema}'='coco.tax.v1' and exists(select 1 from jsonb_array_elements(saved#>'{tax_calculation,lines}') x where
   jsonb_array_length(x->'taxes')>1 or coalesce((x->>'tax_base_factor')::numeric,1)<>1 or coalesce((x->>'subtotal')::numeric,0)<0 or exists(select 1 from jsonb_array_elements(x->'taxes')t where t->>'calculation_type'<>'percent' or coalesce(t->>'tax_category','vat')<>'vat' or coalesce((t->>'include_base_amount')::boolean,false) or t ? 'frozen_amount' or (t->>'rate')::numeric not in(0,5,12,13,14,15))) then
  raise exception 'SRI_TAX_MAPPING_REQUIRED' using detail='La preparación fiscal requiere un código SRI y bases legales para cada componente fijo, compuesto, anticipo o deducción. La factura interna y el asiento conservan sus importes exactos.';
 end if;
 if saved#>>'{tax_calculation,schema}'='coco.tax.v1' and exists(select 1 from jsonb_array_elements(saved->'lines') x where round((x->>'qty')::numeric*round((x->>'price')::numeric,6),2) is distinct from (x->>'subtotal')::numeric) then raise exception 'SRI_TAX_PRICE_PRECISION_REQUIRED';end if;
 $body$);execute s;end loop;if n=0 then raise exception 'TAX_SRI_SNAPSHOT_ANCHOR';end if;
end $$;
do $$declare s text;f regprocedure;begin
 s:=pg_get_functiondef('private.coco_tax_calculate_frozen(jsonb,text)'::regprocedure);s:=replace(s,'r->''account_id'')::text','r->''account_id'',r->''tax_category'')::text');execute s;
 for f in select x::regprocedure from unnest(array['private.coco_history_record_visible(text,text,uuid)','private.coco_history_typed_link(text,text,text,text)'])x loop
  s:=pg_get_functiondef(f);s:=replace(s,'''coco_partner_fiscal_positions'')','''coco_partner_fiscal_positions'',''coco_tax_deposit_buckets'',''coco_tax_deposit_uses'')');execute s;
 end loop;
end $$;
revoke all on function private.gama_accounting_action_before_tax_components(text,jsonb),private.gama_ec_tax_drafts_before_tax_components(jsonb) from authenticated;

-- Optional country rules run after an explicit contact assignment. Priority and
-- ID order make overlapping automatic positions deterministic.
alter table private.coco_fiscal_positions add column auto_apply boolean not null default false,add column auto_side text not null default 'both' check(auto_side in('both','sale','purchase')),add column priority integer not null default 10 check(priority between 0 and 10000),add constraint fiscal_auto_country check(not auto_apply or country is not null);
create index coco_fiscal_positions_automatic on private.coco_fiscal_positions(country,auto_side,priority,id) where active and auto_apply;
do $$declare s text;a text;begin
 s:=pg_get_functiondef('private.coco_tax_compute(text,uuid,date,jsonb,uuid,text)'::regprocedure);a:='if position is not null and not exists(select 1 from private.coco_fiscal_positions';
 if strpos(s,a)=0 then raise exception 'AUTO_FISCAL_POSITION_ANCHOR';end if;
 s:=replace(s,a,$body$if position is null and p_partner is not null then
  select f.id into position from private.coco_fiscal_positions f where f.active and f.auto_apply and f.auto_side in('both',tax_side) and f.country=private.contact_country_code(case when tax_side='sale' then (select c.country from public.customers c where c.id=p_partner) else (select c.country from public.suppliers c where c.id=p_partner) end) order by f.priority,f.id limit 1;
 end if;
 $body$||a);execute s;
 s:=pg_get_functiondef('private.coco_tax_engine_before_sales_tax(text,jsonb)'::regprocedure);a:='new_country text;';if strpos(s,a)=0 then raise exception 'AUTO_FISCAL_CONFIG_ANCHOR';end if;s:=replace(s,a,a||'auto_enabled boolean;auto_kind text;auto_priority integer;');
 a:='taxrules:=coalesce(p_data->''tax_rules'',''[]'');';if strpos(s,a)=0 then raise exception 'AUTO_FISCAL_VALIDATE_ANCHOR';end if;
 s:=replace(s,a,$body$auto_enabled:=coalesce((p_data->>'auto_apply')::boolean,false);auto_kind:=coalesce(nullif(p_data->>'auto_side',''),'both');auto_priority:=coalesce((p_data->>'priority')::integer,10);
 if auto_kind not in('both','sale','purchase') or auto_priority not between 0 and 10000 or(auto_enabled and new_country is null) then raise exception 'FISCAL_POSITION_INVALID';end if;
 $body$||a);
 s:=replace(s,'country=new_country,active=coalesce','country=new_country,auto_apply=auto_enabled,auto_side=auto_kind,priority=auto_priority,active=coalesce');
 s:=replace(s,'coco_fiscal_positions(name,country,active) values(btrim(p_data->>''name''),new_country,coalesce((p_data->>''active'')::boolean,true))','coco_fiscal_positions(name,country,active,auto_apply,auto_side,priority) values(btrim(p_data->>''name''),new_country,coalesce((p_data->>''active'')::boolean,true),auto_enabled,auto_kind,auto_priority)');execute s;
end $$;
-- Included taxes change taxable revenue, not the commercial discount percentage.
create function private.coco_tax_quote_list_base(p_line uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare l public.invoice_lines;price numeric;calc jsonb;begin
 select * into l from public.invoice_lines where id=p_line;price:=greatest(l.quote_list_price,coalesce((l.price_source->>'unit_price')::numeric,l.quote_list_price));
 if l.tax_snapshot is null then return l.quantity*price;end if;
 calc:=private.coco_tax_calculate_frozen(jsonb_build_array(l.tax_snapshot||jsonb_build_object('unit_price',price,'entered_unit_price',price,'discount',0)),'line');return(calc->>'subtotal')::numeric;
end $$;
revoke all on function private.coco_tax_quote_list_base(uuid) from public,anon,authenticated,service_role;
do $$declare s text;f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='private' and p.proname like 'sales_quote_review%' loop
  s:=pg_get_functiondef(f);s:=replace(s,'1-l.unit_price/coalesce((l.price_source->>''unit_price'')::numeric,l.quote_list_price)','1-(case when l.tax_ids is not null then l.quote_list_price*(1-coalesce(l.quote_discount,0)/100) else l.unit_price end)/coalesce((l.price_source->>''unit_price'')::numeric,l.quote_list_price)');
  s:=replace(s,'sum(l.quantity*l.unit_price)','sum(l.line_total)');s:=replace(s,'sum(l.quantity*greatest(l.quote_list_price,coalesce((l.price_source->>''unit_price'')::numeric,l.quote_list_price)))','sum(private.coco_tax_quote_list_base(l.id))');execute s;
 end loop;
end $$;
