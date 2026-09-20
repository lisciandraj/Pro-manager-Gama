-- Aggregates computed in one statement, independent of PostgREST row caps.
create function public.gama_inventory_snapshot(p_warehouse uuid default null,p_until date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;can_incoming boolean:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
begin
 if not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 with stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id
  where p_warehouse is null or l.warehouse_id=p_warehouse group by q.product_id
 ), incoming as (
  select l.product_id,sum(greatest(0,l.quantity-l.received_quantity)) incoming
  from public.purchase_orders p join public.purchase_order_lines l on l.purchase_order_id=p.id
  left join public.warehouse_locations loc on loc.id=p.destination_location_id
  where p.status in ('sent','partial') and (p_warehouse is null or loc.warehouse_id=p_warehouse)
   and (p_until is null or p.expected_date::date<=p_until) group by l.product_id
 ), rows as (
  select p.id,coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,
   case when can_incoming then coalesce(i.incoming,0) end incoming,
   case when can_incoming then coalesce(s.physical,0)-coalesce(s.reserved,0)+coalesce(i.incoming,0) end projected,
   coalesce(s.physical,0)*p.purchase_price current_cost_value
  from public.products p left join stock s on s.product_id=p.id left join incoming i on i.product_id=p.id where p.active
 ) select jsonb_build_object('generated_at',now(),'warehouse_id',p_warehouse,'until',p_until,
  'incoming_visible',can_incoming,'rows',coalesce(jsonb_agg(to_jsonb(rows)),'[]'),
  'totals',jsonb_build_object('physical',coalesce(sum(physical),0),'reserved',coalesce(sum(reserved),0),'available',coalesce(sum(available),0),
    'incoming',case when can_incoming then coalesce(sum(incoming),0) end,'current_cost_value',coalesce(sum(current_cost_value),0))) into result from rows;
 return result;
end $$;
revoke all on function public.gama_inventory_snapshot(uuid,date) from public,anon;
grant execute on function public.gama_inventory_snapshot(uuid,date) to authenticated;

-- Include actual-account refunds in the dashboard, retaining its date/currency semantics.
do $$declare source text:=pg_get_functiondef('public.gama_company_dashboard(date,date)'::regprocedure);anchor text:='-coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status=''posted'' and e.expense_date<=today),0)) amount';begin
 if position(anchor in source)=0 then raise exception 'CASH_DASHBOARD_ANCHOR_MISSING';end if;
 execute replace(source,anchor,'-coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status=''posted'' and e.expense_date<=today),0) -coalesce((select sum(r.amount) from public.return_refunds r where r.financial_account_id=f.id and r.paid_at<=today),0)) amount');
end $$;

-- Portable application export. Infrastructure and Auth secrets are deliberately
-- excluded and identified; this is not advertised as a physical disaster backup.
create function private.gama_recovery_export() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t record;rows jsonb;tables jsonb:='{}';counts jsonb:='{}';meta jsonb:='{}';
begin
 if auth.uid() is null or not private.erp_module_allowed('backup',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 for t in select n.nspname schema_name,c.relname table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and n.nspname in ('public','private') order by n.nspname,c.relname
 loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from %I.%I t',t.schema_name,t.table_name) into rows;
  tables:=tables||jsonb_build_object(t.schema_name||'.'||t.table_name,rows);
  counts:=counts||jsonb_build_object(t.schema_name||'.'||t.table_name,jsonb_array_length(rows));
  meta:=meta||jsonb_build_object(t.schema_name||'.'||t.table_name,(select jsonb_agg(jsonb_build_object('name',column_name,'generated',is_generated,'identity',is_identity) order by ordinal_position) from information_schema.columns where table_schema=t.schema_name and table_name=t.table_name));
 end loop;
 return jsonb_build_object('format','architect-application-export','version',1,'created_at',now(),'created_by',auth.uid(),
  'scope','application_data_and_files','excludes',jsonb_build_array('authentication_secrets','infrastructure_configuration','physical_database_backup'),
  'tables',tables,'counts',counts,'columns',meta,
  'identities',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'email',u.email)),'[]') from auth.users u),
  'storage_objects',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'bucket',o.bucket_id,'path',o.name)),'[]') from storage.objects o),
  'storage_buckets',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from storage.buckets b));
end $$;
revoke all on function private.gama_recovery_export() from public,anon;
grant execute on function private.gama_recovery_export() to authenticated;
create function public.gama_recovery_export() returns jsonb language sql security invoker set search_path='' as $$select private.gama_recovery_export()$$;
revoke all on function public.gama_recovery_export() from public,anon;
grant execute on function public.gama_recovery_export() to authenticated;
