-- Alert copies must retain the source's current audience, including history.
-- Existing finance/warehouse filters still apply in each reader.
create function private.gama_alert_source_allowed(p_key text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare kind text:=split_part(p_key,':',1);source_id uuid;module_id text;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then return false;end if;
 if kind='fleet_deadline' then return coalesce(private.gama_fleet_may(),false);end if;
 if kind='stock_integrity' then return private.erp_module_allowed('warehouses',array['administrador']);end if;
 if kind='delivery' then
  begin source_id:=split_part(p_key,':',2)::uuid;exception when invalid_text_representation then return false;end;
  return private.tms_can_read(source_id);
 end if;
 if kind in ('sales_option','sales_promise') then
  return private.erp_module_allowed('sales-orders',case when kind='sales_promise' then array['administrador','comercial','almacenero'] else array['administrador','comercial'] end);
 end if;
 if kind='sales_activity' then
  select case when d.order_id is null then 'quotes' else 'sales-orders' end into module_id
   from private.sales_activities a join private.sales_dossiers d on d.id=a.dossier_id where a.id::text=split_part(p_key,':',2);
  return module_id is not null and private.erp_module_allowed(module_id,array['administrador','comercial']);
 end if;
 if kind in ('returns_to_process','returns_received','returns_to_ship','returns_supplier_credit','returns_refund_due','service_late') then
  return private.erp_module_allowed('returns',array['administrador','comercial','almacenero']);
 end if;
 if kind in ('payable_overdue','payable_due_soon','expense_no_receipt','bank_unmatched','entry_unbalanced') then
  return private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all';
 end if;
 -- Other kinds retain their existing source and role predicates.
 return true;
end $$;
revoke all on function private.gama_alert_source_allowed(text) from public,anon,authenticated;

do $audit$
declare src text;before_text text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as select scoped.* from ('||src||') scoped where private.gama_alert_source_allowed(scoped.alert_key)';
 src:=pg_get_functiondef('private.gama_operations_action(text,jsonb)'::regprocedure);
 before_text:='where alert_key=p_data->>''key'' and (not finance_only or fin)';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:alert_history';end if;
 src:=replace(src,before_text,'where alert_key=p_data->>''key'' and private.gama_alert_source_allowed(alert_key) and (not finance_only or fin)');
 before_text:='where (not finance_only or fin) and (not warehouse_only or wh) and active';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:alert_resolution';end if;
 execute replace(src,before_text,'where private.gama_alert_source_allowed(alert_key) and (not finance_only or fin) and (not warehouse_only or wh) and active');
 src:=pg_get_functiondef('private.gama_operations_core(text,jsonb)'::regprocedure);
 before_text:='from public.tms_deliveries where';
 if (length(src)-length(replace(src,before_text,'')))/length(before_text)<>2 then raise exception 'SECURITY_PATCH_ANCHOR:alert_delivery_metrics';end if;
 execute replace(src,before_text,'from public.tms_deliveries where private.tms_can_read(id) and');
end $audit$;
notify pgrst,'reload schema';
