-- Single-use internal authorization prevents legacy adjustment RPCs bypassing approval rules.
create table private.stock_adjustment_authorizations(
 transaction_id bigint not null,actor uuid not null,product_id uuid not null,location_id uuid not null,target numeric not null,
 primary key(transaction_id,actor,product_id,location_id)
);
revoke all on private.stock_adjustment_authorizations from public,anon,authenticated;
create function private.erp_authorize_stock_adjustment(pid uuid,lid uuid,target numeric) returns void language sql security definer set search_path='' as $$
 insert into private.stock_adjustment_authorizations values(pg_catalog.txid_current(),auth.uid(),pid,lid,target)
 on conflict(transaction_id,actor,product_id,location_id) do update set target=excluded.target;
$$;
revoke all on function private.erp_authorize_stock_adjustment(uuid,uuid,numeric) from public,anon,authenticated;
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.gama_adjustment_request(text,jsonb)'::regprocedure);
 s:=replace(s,'m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity', 'perform private.erp_authorize_stock_adjustment(a.product_id,a.location_id,a.target_quantity);m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity');execute s;
 s:=pg_get_functiondef('private.api_gama_count_validate(uuid)'::regprocedure);
 anchor:='if limit_qty is not null and abs(l.counted_quantity-l.expected_quantity)>limit_qty then';
 if strpos(s,anchor)=0 then raise exception 'COUNT_APPROVAL_ANCHOR_MISSING';end if;
 s:=replace(s,anchor,$p$if (limit_qty is not null and abs(l.counted_quantity-l.expected_quantity)>limit_qty)
  or exists(select 1 from public.erp_policies pol where pol.id and ((pol.stock_adjustment_value_limit is not null and (coalesce((select purchase_price from public.products where id=l.product_id),0)<=0 or abs(l.counted_quantity-l.expected_quantity)*coalesce((select purchase_price from public.products where id=l.product_id),0)>pol.stock_adjustment_value_limit)) or 'inventory_difference'=any(pol.stock_adjustment_approval_kinds))) then$p$);
 s:=replace(s,'perform public.gama_stock_adjust(l.product_id,l.location_id,l.counted_quantity','perform private.erp_authorize_stock_adjustment(l.product_id,l.location_id,l.counted_quantity);perform public.gama_stock_adjust(l.product_id,l.location_id,l.counted_quantity');execute s;
 s:=pg_get_functiondef('private.api_gama_stock_adjust(uuid,uuid,numeric,numeric,text,text,text,uuid)'::regprocedure);
 anchor:='if v_delta = 0 then';
 if strpos(s,anchor)=0 then raise exception 'ADJUSTMENT_APPROVAL_ANCHOR_MISSING';end if;
 s:=replace(s,anchor,$p$
  delete from private.stock_adjustment_authorizations where transaction_id=pg_catalog.txid_current() and actor=auth.uid() and product_id=p_product_id and location_id=p_location_id and target=v_new;
  if not found and exists(select 1 from public.erp_policies pol where pol.id and
   ((pol.stock_adjustment_limit is not null and abs(v_delta)>pol.stock_adjustment_limit)
    or (pol.stock_adjustment_value_limit is not null and (coalesce((select purchase_price from public.products where id=p_product_id),0)<=0 or abs(v_delta)*coalesce((select purchase_price from public.products where id=p_product_id),0)>pol.stock_adjustment_value_limit))
    or cardinality(pol.stock_adjustment_approval_kinds)>0)) then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;
 $p$||anchor);execute s;
end $$;
alter table public.erp_policies add constraint adjustment_approval_kinds_known check(stock_adjustment_approval_kinds<@array['inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening']);

-- Exclusion is a deliberate replenishment decision, not merely a readiness label.
do $$declare s text;cols text;begin
 s:=rtrim(pg_get_viewdef('public.replenishment_needs'::regclass,true),';');
 select string_agg(case when attname='suggested_purchase' then 'case when p.replenishment_excluded then 0::numeric else b.suggested_purchase end as suggested_purchase' else format('b.%I',attname) end,',' order by attnum) into cols
 from pg_attribute where attrelid='public.replenishment_needs'::regclass and attnum>0 and not attisdropped;
 execute 'create or replace view public.replenishment_needs with(security_invoker=true) as select '||cols||' from ('||s||') b join public.products p on p.id=b.product_id';
end $$;

-- Alert balances now use the same credited balances as collection and process closure.
do $$declare s text;begin
 s:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),';');
 execute 'create or replace view private.gama_live_alerts as select * from ('||s||$view$) previous
 where previous.kind not in ('overdue_invoice','due_soon_invoice','payable_overdue','payable_due_soon')
 and (previous.kind<>'low_stock' or not coalesce((select replenishment_excluded from public.products where id=previous.target_id),false))
 union all
 select (case when r.days_remaining<0 then 'overdue_invoice:' else 'due_soon_invoice:' end)||r.id,
  case when r.days_remaining<0 then 'overdue_invoice' else 'due_soon_invoice' end,r.id,'invoice',r.number,r.customer_name,
  case when r.days_remaining<0 then 'Factura vencida' else 'Pago próximo a vencer' end,'Saldo neto de abonos: '||round(r.balance,2),r.due_date::timestamp at time zone private.erp_timezone(),
  case when r.days_remaining<0 then 3 else 2 end,true,false,case when r.days_remaining<0 then 'danger' else 'warning' end,r.due_date
 from private.gama_receivables r where r.payment_status<>'cancelled' and r.balance>0.005 and r.days_remaining<=7
 union all
 select (case when r.days_remaining<0 then 'payable_overdue:' else 'payable_due_soon:' end)||r.id,
  case when r.days_remaining<0 then 'payable_overdue' else 'payable_due_soon' end,r.id,'supplier_invoice',r.number,r.supplier_name,
  case when r.days_remaining<0 then 'Factura de proveedor vencida' else 'Pago a proveedor próximo a vencer' end,'Saldo neto de abonos: '||round(r.balance,2),r.due_date::timestamp at time zone private.erp_timezone(),
  case when r.days_remaining<0 then 3 else 2 end,true,false,case when r.days_remaining<0 then 'danger' else 'warning' end,r.due_date
 from private.gama_payables r where r.status='posted' and r.balance>0.005 and r.days_remaining<=7
 union all
 select 'receipt_unbilled:'||po.id,'receipt_unbilled',po.id,'purchase',po.order_number,s.name,'Recepción sin factura conciliada',
  'Cantidad recibida sin conciliar: '||(st.j->>'unbilled_received'),coalesce((select min(m.created_at) from public.stock_movements m where m.reference_type='purchase_order' and m.reference_id=po.id),po.created_at),2,true,false,'warning',null::date
 from public.purchase_orders po join public.suppliers s on s.id=po.supplier_id cross join lateral(select private.gama_process_state('p:'||po.id) j) st
 where po.status in ('partial','received') and (st.j->>'unbilled_received')::numeric>0
 union all
 select 'process_deadline:'||f.dossier_key,'process_deadline',split_part(f.dossier_key,':',2)::uuid,'process',coalesce(dr.dossier_label,f.dossier_key),coalesce(p.full_name,'Sin responsable'),
  'Proceso fuera del plazo de seguimiento',f.next_action,f.due_date::timestamp at time zone private.erp_timezone(),
  case when (now() at time zone private.erp_timezone())::date-f.due_date>=pol.escalation_days then 3 else 2 end,true,false,
  case when (now() at time zone private.erp_timezone())::date-f.due_date>=pol.escalation_days then 'danger' else 'warning' end,f.due_date
 from public.dossier_followups f left join public.profiles p on p.id=f.owner_id
 left join public.gama_document_references dr on dr.document_id=split_part(f.dossier_key,':',2)::uuid and dr.table_name=case split_part(f.dossier_key,':',1) when 'p' then 'purchase_orders' when 'o' then 'sales_orders' when 'q' then 'invoices' else 'customer_requests' end
 cross join public.erp_policies pol cross join lateral(select private.gama_process_state(f.dossier_key) j) st
 where pol.id and f.due_date<(now() at time zone private.erp_timezone())::date and not(st.j->>'closed')::boolean and not(st.j->>'cancelled')::boolean and not(st.j->>'operational_complete')::boolean
 union all
 select 'process_unowned:'||c.key,'process_unowned',c.id,'process',coalesce(dr.dossier_label,c.key),'Sin responsable',
  'Proceso bloqueado sin responsable de seguimiento','Asigna responsable, próxima acción y plazo.',c.created_at,2,true,false,'warning',null::date
 from (select 'o:'||id key,id,created_at,'sales_orders' tbl from public.sales_orders where status='confirmed'
       union all select 'p:'||id,id,created_at,'purchase_orders' from public.purchase_orders where status in ('sent','partial','received')) c
 left join public.dossier_followups f on f.dossier_key=c.key left join public.profiles owner on owner.id=f.owner_id
 left join public.gama_document_references dr on dr.document_id=c.id and dr.table_name=c.tbl
 cross join lateral(select private.gama_process_state(c.key) j) st
 where (f.id is null or not coalesce(owner.active,false)) and exists(select 1 from jsonb_array_elements(st.j->'steps') step where step->>'state'='blocked')
 union all
 select 'stock_integrity:'||c.id,'stock_integrity',c.product_id,'product',coalesce(p.reference,p.name),p.name,'Diferencia histórica de stock por justificar',
  'Ficha observada: '||c.catalogue_quantity||' · ubicaciones observadas: '||c.located_quantity,c.observed_at,3,true,false,'danger',null::date
 from public.stock_integrity_cases c join public.products p on p.id=c.product_id where c.resolved_at is null and private.current_user_role()='administrador'
 $view$;
end $$;

create function private.gama_technical_checks() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;started timestamptz:=clock_timestamp();begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select jsonb_build_object('checked_at',now(),
  'stock_mismatches',(select count(*) from public.products p where p.stock is distinct from coalesce((select sum(q.quantity) from public.stock_quants q where q.product_id=p.id),0)),
  'historical_cases',(select count(*) from public.stock_integrity_cases where resolved_at is null),
  'valuation_mismatches',(select count(*) from public.stock_cost_books b where b.quantity is distinct from coalesce((select sum(q.quantity) from public.stock_quants q where q.product_id=b.product_id),0)),
  'waiting_locks',(select count(*) from pg_catalog.pg_locks where not granted),
  'locks',coalesce((select jsonb_agg(r) from(select locktype,mode,granted,count(*) count from pg_catalog.pg_locks where database=(select oid from pg_catalog.pg_database where datname=current_database()) or locktype='advisory' group by locktype,mode,granted order by count(*) desc)r),'[]'),
  'longest_wait_seconds',(select coalesce(max(extract(epoch from now()-query_start)),0) from pg_catalog.pg_stat_activity where datname=current_database() and wait_event_type='Lock'),
  'tables',(select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname in ('public','private')),
  'storage_objects',(select count(*) from storage.objects),
  'recovery_scope',jsonb_build_array('application_tables','workflow_state','identity_mapping','storage_manifest'),
  'recovery_external_steps',jsonb_build_array('auth_provider_restore','secrets_and_environment','storage_file_verification','production_smoke_test'),
  'rules',jsonb_build_object('quantity_limit_configured',p.stock_adjustment_limit is not null,'value_limit_configured',p.stock_adjustment_value_limit is not null,'scan_mode',p.picking_scan_mode,'scan_location_required',p.picking_location_required,'readiness_required',p.product_readiness_required)) into result from public.erp_policies p where id;
 return result||jsonb_build_object('duration_ms',round(extract(epoch from clock_timestamp()-started)*1000,2));
end $$;
create function public.gama_technical_checks() returns jsonb language sql security invoker set search_path='' as $$select private.gama_technical_checks()$$;
revoke all on function private.gama_technical_checks(),public.gama_technical_checks() from public,anon;
grant execute on function private.gama_technical_checks(),public.gama_technical_checks() to authenticated;
