do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>178
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20260920184641_p1_dashboard_drilldowns_and_stage_metrics.sql; SHA256 4e55b7a03b2edabad7792b8fc1b6f5978599ee4b07d6023c4370b12b80afdcba
-- Dashboard cash uses actual receipts, without counting allocation a second time.
do $$declare src text;anchor text;begin
 select pg_get_functiondef('public.gama_company_dashboard(date,date)'::regprocedure) into src;
 anchor:=$a$cash as (select p.paid_at,p.amount from public.external_invoice_payments p join invoices i on i.id=p.invoice_id where p.status='confirmed')$a$;
 if strpos(src,anchor)=0 then raise exception 'DASHBOARD_CASH_ANCHOR';end if;
 src:=replace(src,anchor,$b$cash as (select p.paid_at,p.amount from public.external_invoice_payments p join invoices i on i.id=p.invoice_id where p.status='confirmed' and p.receipt_id is null union all select paid_at,amount from public.customer_receipts where status='confirmed')$b$);
 anchor:=$a$select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today$a$;
 if strpos(src,anchor)=0 then raise exception 'DASHBOARD_ACCOUNT_CASH_ANCHOR';end if;
 src:=replace(src,anchor,$b$select sum(p.amount) from (select amount,financial_account_id,status,paid_at from public.external_invoice_payments where receipt_id is null union all select amount,financial_account_id,status,paid_at from public.customer_receipts)p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today$b$);
 src:=replace(src,'sum(greatest(l.quantity-coalesce(s.quantity,0),0)) remaining',$b$sum(greatest(l.quantity-case when l.product_kind='service' then coalesce((select sum(c.quantity) from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null),0) else coalesce(s.quantity,0) end,0)) remaining$b$);
 src:=replace(src,'where p.active;','where p.active and p.product_kind=''goods'';');
 src:=replace(src,'''weighted'',coalesce(sum(o.amount*o.probability/100),0),',$b$'weighted',coalesce(sum(o.amount*o.probability/100),0),
 'won',(select coalesce(sum(w.amount),0) from public.crm_opportunities w where w.active and (w.won_at at time zone private.erp_timezone())::date between first_day and last_day),
 'invoiced',case when private.dashboard_access('payments') then (select coalesce(sum(i.subtotal),0) from public.external_invoices i join public.sales_orders so on so.id=i.order_id where so.source_opportunity_id is not null and i.fiscal_status not in ('cancelled','rejected') and i.issue_date between first_day and last_day) end,$b$);execute src;
end $$;
-- RLS-preserving drilldowns use the same dates and monetary definitions as KPIs.
create function public.gama_dashboard_details(p_module text,p_metric text,p_from date,p_to date,p_offset integer default 0) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;q text;result jsonb;begin
 if not private.dashboard_access('dashboard') or not private.dashboard_access(p_module) then raise exception 'DASHBOARD_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to>today or p_to-p_from>730 then raise exception 'DASHBOARD_INVALID_PERIOD';end if;
 if p_module='payments' and p_metric='net' then q:=$q$select i.id,i.order_id,i.number label,o.customer_name customer,i.issue_date date,i.subtotal amount,'invoice'::text kind from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between $1 and $2$q$;
 elsif p_module='payments' and p_metric='collected' then q:=$q$select p.id,i.order_id,coalesce(nullif(p.reference,''),i.number) label,o.customer_name customer,p.paid_at date,p.amount,'payment'::text kind from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id join public.sales_orders o on o.id=i.order_id where p.status='confirmed' and p.receipt_id is null and i.fiscal_status not in ('cancelled','rejected') and p.paid_at between $1 and $2 union all select r.id,null::uuid,r.reference,c.name,r.paid_at,r.amount,'receipt' from public.customer_receipts r join public.customers c on c.id=r.customer_id where r.status='confirmed' and r.paid_at between $1 and $2$q$;
 elsif p_module='payments' and p_metric='receivable' then q:=$q$select * from (select i.id,i.order_id,i.number label,o.customer_name customer,i.issue_date date,greatest(0,i.total-coalesce((select sum(amount) from public.external_invoice_payments p where p.invoice_id=i.id and status='confirmed' and paid_at<=$3),0)-coalesce((select sum(amount) from public.return_credits c where c.invoice_id=i.id and issued_on<=$3),0)) amount,'invoice'::text kind from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.fiscal_status not in ('cancelled','rejected') and i.issue_date<=$3) r where amount>0$q$;
 elsif p_module='sales-orders' and p_metric in ('orders','to_ship') then q:=$q$select o.id,o.id order_id,o.number label,o.customer_name customer,(o.created_at at time zone private.erp_timezone())::date date,1::numeric amount,'order'::text kind from public.sales_orders o where o.status='confirmed'$q$||case when p_metric='orders' then $q$ and (o.created_at at time zone private.erp_timezone())::date between $1 and $2$q$ else $q$ and exists(select 1 from public.sales_order_lines l where l.order_id=o.id and l.quantity>case when l.product_kind='service' then coalesce((select sum(quantity) from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null),0) else coalesce((select sum(quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0) end)$q$ end;
 elsif p_module='warehouses' and p_metric='out' then q:=$q$select p.id,null::uuid order_id,coalesce(p.reference,p.barcode) label,p.name customer,null::date date,1::numeric amount,'product'::text kind from public.products p where p.active and p.product_kind='goods' and coalesce((select sum(quantity-reserved_quantity) from public.stock_quants q where q.product_id=p.id),0)<=0$q$;
 elsif p_module='tms' and p_metric='delivered' then q:=$q$select d.id,(select order_id from public.sales_deliveries s where s.tms_delivery_id=d.id limit 1) order_id,d.id::text label,d.customer customer,(d.delivered_at at time zone private.erp_timezone())::date date,1::numeric amount,'delivery'::text kind from public.tms_deliveries d where d.status='Entregada' and (d.delivered_at at time zone private.erp_timezone())::date between $1 and $2$q$;
 elsif p_module='crm' and p_metric in ('weighted','won') then q:=$q$select o.id,null::uuid order_id,o.title label,''::text customer,(o.won_at at time zone private.erp_timezone())::date date,$q$||case when p_metric='weighted' then 'o.amount*o.probability/100' else 'o.amount' end||$q$ amount,'opportunity'::text kind from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active$q$||case when p_metric='weighted' then ' and not s.is_won and not s.is_lost' else $q$ and (o.won_at at time zone private.erp_timezone())::date between $1 and $2$q$ end;
 else raise exception 'METRIC_NOT_SUPPORTED';end if;
 execute 'with rows as ('||q||') select jsonb_build_object(''generated_at'',now(),''count'',(select count(*) from rows),''total'',(select coalesce(sum(amount),0) from rows),''rows'',(select coalesce(jsonb_agg(to_jsonb(r)),''[]'') from (select * from rows order by date desc nulls last,id limit 100 offset $4)r))' into result using p_from,p_to,today,greatest(0,coalesce(p_offset,0));return result;
end $$;
revoke all on function public.gama_dashboard_details(text,text,date,date,integer) from public,anon;grant execute on function public.gama_dashboard_details(text,text,date,date,integer) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184641','p1_dashboard_drilldowns_and_stage_metrics','4e55b7a03b2edabad7792b8fc1b6f5978599ee4b07d6023c4370b12b80afdcba','4e55b7a03b2edabad7792b8fc1b6f5978599ee4b07d6023c4370b12b80afdcba','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922171925_dashboard_priorities.sql; SHA256 4f76b0a236bb1f0114346950e702c3c2c06fe3d49724238f0f97d3e343e60a1f
-- Prioridades de hoy: el seguimiento comercial y logístico pasa al panel de control.
--
-- Cada alerta viva recibe un tono calculado donde están los hechos —fechas de
-- vencimiento, existencias, validez, kilómetros— y no adivinado en el navegador:
--   danger  · rojo    la fecha o el límite ya se superó (o el caso está bloqueado)
--   warning · naranja vence en los próximos siete días, el límite está cerca,
--                     o es una acción pendiente sin fecha
--   info    ·         aviso lejano (flota a 8–30 días): sigue en Notificaciones,
--                     no entra en las prioridades del día
-- y la fecha que lo decide, due_on, cuando existe.
--
-- La vista se reescribe a partir de su propia definición: cada rama recibe sus
-- dos columnas en orden, y se comprueba que la rama es la esperada antes de
-- tocarla. Si la vista hubiera cambiado, la migración se detiene en lugar de
-- pegar un tono a la alerta equivocada.
do $mig$
declare
  src text := pg_get_viewdef('private.gama_live_alerts'::regclass, true);
  parts text[];
  today constant text := '(now() AT TIME ZONE private.erp_timezone())::date';
  spec text[][] := array[
    ['''quote''::text AS kind',            'CASE WHEN q.quote_valid_until < '||today||' THEN ''danger'' ELSE ''warning'' END', 'q.quote_valid_until'],
    ['''shortage''::text AS kind',         '''danger''', 'NULL::date'],
    ['''backorder''::text AS kind',        '''warning''', 'NULL::date'],
    ['''receipt''::text AS kind',          '''danger''', '(p.expected_date AT TIME ZONE private.erp_timezone())::date'],
    ['''failed_delivery''::text',          '''danger''', 'd.delivery_date'],
    ['''stock_variance''::text AS kind',   '''warning''', 'NULL::date'],
    ['''unbilled''::text AS kind',         '''warning''', 'NULL::date'],
    ['''low_stock''::text AS kind',        'CASE WHEN n.available <= 0::numeric THEN ''danger'' ELSE ''warning'' END', 'NULL::date'],
    ['''overdue_invoice''::text AS kind',  '''danger''', 'i.due_date'],
    ['''due_soon_invoice''::text AS kind', '''warning''', 'i.due_date'],
    ['''payable_overdue''::text AS kind',  '''danger''', 'p.due_date'],
    ['''expense_no_receipt''::text AS kind','''warning''', 'NULL::date'],
    ['''bank_unmatched''::text AS kind',   '''warning''', 'NULL::date'],
    ['''entry_unbalanced''::text AS kind', '''danger''', 'NULL::date'],
    ['''fleet_deadline''::text AS kind',   'CASE WHEN COALESCE(d.days_remaining,1) < 0 OR COALESCE(d.km_remaining,1::numeric) < 0::numeric THEN ''danger'' WHEN COALESCE(d.days_remaining,999) <= 7 OR COALESCE(d.km_remaining,999999::numeric) <= 200::numeric THEN ''warning'' ELSE ''info'' END', 'd.due_on'],
    ['''return_to_process''::text AS kind','''warning''', 'NULL::date'],
    ['''return_received''::text AS kind',  '''warning''', 'NULL::date'],
    ['''return_to_ship''::text AS kind',   '''warning''', 'NULL::date'],
    ['''return_supplier_credit''::text AS kind','''warning''', 'NULL::date'],
    ['''return_refund_due''::text AS kind','''warning''', 'NULL::date'],
    ['''crm_stale''::text AS kind',        'CASE WHEN o.updated_at < (now() - make_interval(days => (SELECT e.stale_opportunity_days FROM public.erp_policies e WHERE e.id))) THEN ''danger'' ELSE ''warning'' END', 'NULL::date'],
    ['''service_late''::text AS kind',     '''danger''', 's.due_date::date']
  ];
  i int;
  rebuilt text := '';
begin
  if src ~ '\mAS tone\M' then
    raise notice 'gama_live_alerts ya tiene tono; nada que hacer';
    return;
  end if;
  parts := regexp_split_to_array(src, '\nUNION ALL\n');
  if array_length(parts,1) <> array_length(spec,1) then
    raise exception 'gama_live_alerts tiene % ramas, se esperaban %', array_length(parts,1), array_length(spec,1);
  end if;
  for i in 1..array_length(parts,1) loop
    if position(spec[i][1] in parts[i]) = 0 then
      raise exception 'La rama % no es la esperada (%)', i, spec[i][1];
    end if;
    if (length(parts[i]) - length(replace(parts[i], 'AS warehouse_only', ''))) / length('AS warehouse_only') <> 1 then
      raise exception 'La rama % no tiene exactamente una columna warehouse_only', i;
    end if;
    parts[i] := replace(parts[i], 'AS warehouse_only',
      'AS warehouse_only,'||E'\n    '||spec[i][2]||'::text AS tone,'||E'\n    '||spec[i][3]||' AS due_on');
    rebuilt := rebuilt || case when i > 1 then E'\nUNION ALL\n' else '' end || parts[i];
  end loop;
  -- Pagos a proveedor que vencen esta semana: el espejo de due_soon_invoice.
  rebuilt := rtrim(rtrim(rebuilt), ';') || $b$
UNION ALL
 SELECT 'payable_due_soon:'::text || p.id AS alert_key,
    'payable_due_soon'::text AS kind,
    p.id AS target_id,
    'supplier_invoice'::text AS target,
    p.number AS reference,
    p.supplier_name AS customer,
    'Pago a proveedor próximo a vencer'::text AS title,
    (('Vencimiento: '::text || p.due_date) || ' · saldo: '::text) || round(p.balance, 2) AS detail,
    (p.due_date::timestamp without time zone AT TIME ZONE private.erp_timezone()) AS since,
    2 AS priority,
    true AS finance_only,
    false AS warehouse_only,
    'warning'::text AS tone,
    p.due_date AS due_on
   FROM private.gama_payables p
  WHERE (p.payment_status = ANY (ARRAY['pending'::text, 'partial'::text])) AND p.balance > 0::numeric AND p.days_remaining >= 0 AND p.days_remaining <= 7$b$;
  execute 'create or replace view private.gama_live_alerts as ' || rebuilt;
end
$mig$;

-- Lo que el panel enseña en «Prioridades de hoy»: sólo rojo y naranja, sin lo
-- pospuesto, con las mismas barreras de rol que el centro de acción. El panel
-- de control es ahora la puerta principal, así que también abre el acceso.
create or replace function private.gama_dashboard_priorities() returns jsonb
language plpgsql security definer set search_path='' as $$
declare r text := private.current_user_role(); fin boolean; wh boolean;
begin
  if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED'; end if;
  if r not in ('administrador','comercial','almacenero')
     or not (private.erp_module_allowed('dashboard',array['administrador','comercial','almacenero'])
          or private.erp_module_allowed('operations',array['administrador','comercial','almacenero'])
          or private.erp_module_allowed('notifications',array['administrador','comercial','almacenero'])) then
    raise exception 'ROLE_NOT_ALLOWED';
  end if;
  fin := r in ('administrador','comercial');
  wh := r in ('administrador','almacenero');
  return (
    with live as (
      select a.alert_key, a.kind, a.target_id, a.target, a.reference, a.customer, a.title, a.detail,
             a.since, a.priority, a.tone, a.due_on,
             h.status as handling, pr.full_name as assigned_name, h.next_action
        from private.gama_live_alerts a
        left join private.gama_alert_handling h on h.alert_key = a.alert_key
        left join public.profiles pr on pr.id = h.assigned_to
       where a.tone in ('danger','warning')
         and (not a.finance_only or fin) and (not a.warehouse_only or wh)
         and coalesce(h.snoozed_until, '-infinity'::timestamptz) <= now()
    )
    select jsonb_build_object(
      'generated_at', now(),
      'today', (now() at time zone private.erp_timezone())::date,
      'counts', jsonb_build_object(
        'danger', (select count(*) from live where tone = 'danger'),
        'warning', (select count(*) from live where tone = 'warning')),
      'items', coalesce((
        select jsonb_agg(to_jsonb(z) order by z.rank, z.due_on nulls last, z.since nulls last, z.alert_key)
          from (select l.*, case l.tone when 'danger' then 0 else 1 end as rank
                  from live l
                 order by case l.tone when 'danger' then 0 else 1 end, l.due_on nulls last, l.since nulls last, l.alert_key
                 limit 200) z), '[]'::jsonb))
  );
end $$;

create or replace function public.gama_dashboard_priorities() returns jsonb
language sql security invoker set search_path='' as $$ select private.gama_dashboard_priorities() $$;

revoke all on function private.gama_dashboard_priorities(), public.gama_dashboard_priorities() from public, anon;
grant execute on function private.gama_dashboard_priorities(), public.gama_dashboard_priorities() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922171925','dashboard_priorities','4f76b0a236bb1f0114346950e702c3c2c06fe3d49724238f0f97d3e343e60a1f','4f76b0a236bb1f0114346950e702c3c2c06fe3d49724238f0f97d3e343e60a1f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922172746_dashboard_priorities_groups.sql; SHA256 a8bb35749b6eb6e9f62854c4f1d1e648522abb4b5c9e99d74347443c82507646
-- Prioridades de hoy, segunda vuelta: lo contable en bloque.
--
-- En producción, 56 de las 66 alertas naranjas eran movimientos bancarios sin
-- conciliar. Cada uno es real, pero no es seguimiento comercial ni logístico,
-- y listarlos uno a uno enterraba lo que sí lo es. Los tipos de tareas de
-- oficina —conciliar el banco, adjuntar justificantes— se devuelven ahora como
-- un grupo con su número; el resto sigue una por una. Los contadores siguen
-- contando todo, así que el total de cada columna no cambia.
create or replace function private.gama_dashboard_priorities() returns jsonb
language plpgsql security definer set search_path='' as $$
declare r text := private.current_user_role(); fin boolean; wh boolean;
  grouped constant text[] := array['bank_unmatched','expense_no_receipt'];
begin
  if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED'; end if;
  if r not in ('administrador','comercial','almacenero')
     or not (private.erp_module_allowed('dashboard',array['administrador','comercial','almacenero'])
          or private.erp_module_allowed('operations',array['administrador','comercial','almacenero'])
          or private.erp_module_allowed('notifications',array['administrador','comercial','almacenero'])) then
    raise exception 'ROLE_NOT_ALLOWED';
  end if;
  fin := r in ('administrador','comercial');
  wh := r in ('administrador','almacenero');
  return (
    with live as (
      select a.alert_key, a.kind, a.target_id, a.target, a.reference, a.customer, a.title, a.detail,
             a.since, a.priority, a.tone, a.due_on,
             h.status as handling, pr.full_name as assigned_name, h.next_action
        from private.gama_live_alerts a
        left join private.gama_alert_handling h on h.alert_key = a.alert_key
        left join public.profiles pr on pr.id = h.assigned_to
       where a.tone in ('danger','warning')
         and (not a.finance_only or fin) and (not a.warehouse_only or wh)
         and coalesce(h.snoozed_until, '-infinity'::timestamptz) <= now()
    )
    select jsonb_build_object(
      'generated_at', now(),
      'today', (now() at time zone private.erp_timezone())::date,
      'counts', jsonb_build_object(
        'danger', (select count(*) from live where tone = 'danger'),
        'warning', (select count(*) from live where tone = 'warning')),
      'groups', coalesce((
        select jsonb_agg(jsonb_build_object('kind', g.kind, 'tone', g.tone, 'target', g.target, 'count', g.n) order by g.tone, g.kind)
          from (select kind, tone, min(target) as target, count(*) as n from live where kind = any(grouped) group by kind, tone) g), '[]'::jsonb),
      'items', coalesce((
        select jsonb_agg(to_jsonb(z) order by z.rank, z.due_on nulls last, z.since nulls last, z.alert_key)
          from (select l.*, case l.tone when 'danger' then 0 else 1 end as rank
                  from live l
                 where not (l.kind = any(grouped))
                 order by case l.tone when 'danger' then 0 else 1 end, l.due_on nulls last, l.since nulls last, l.alert_key
                 limit 200) z), '[]'::jsonb))
  );
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922172746','dashboard_priorities_groups','a8bb35749b6eb6e9f62854c4f1d1e648522abb4b5c9e99d74347443c82507646','a8bb35749b6eb6e9f62854c4f1d1e648522abb4b5c9e99d74347443c82507646','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922174307_purchase_process_number.sql; SHA256 876ddb0a19e32eab36fdcd69b98da5eb6627dfad7dc01011b32571399ced24f2
-- Proceso de compra (PDC): un solo número para todos sus documentos.
--
-- En la venta, solicitud, presupuesto, pedido, preparación, envío, factura y
-- cobro comparten el número de su expediente (SOL-, COT-, PED-…-00001246).
-- En la compra cada documento llevaba su propio contador: el pedido OCO-7, su
-- factura FPR-45 y su pago PPR-12 hablaban del mismo proceso con tres números.
-- Desde aquí el pedido de compra abre un expediente, su factura de proveedor
-- entra en él y el pago entra en el de su factura: OCO-, FPR- y PPR-00001330.
--
-- Además, el pedido guarda de dónde nace la necesidad —el paso 1 del proceso—:
--   manual       creado en el módulo Compras
--   low_stock    preparado desde la alerta de stock bajo el mínimo
--   sales_order  preparado desde un pedido de cliente que supera el stock
--
-- Las referencias ya emitidas no cambian. Los pedidos existentes entran cada
-- uno en un expediente nuevo, conservando su OCO; el número único vale para
-- los procesos que se abran a partir de ahora.

alter table public.purchase_orders
  add column if not exists source_kind text not null default 'manual',
  add column if not exists source_order_id uuid references public.sales_orders(id) on delete set null;
alter table public.purchase_orders drop constraint if exists purchase_orders_source_kind_check;
alter table public.purchase_orders add constraint purchase_orders_source_kind_check
  check (source_kind in ('manual','low_stock','sales_order') and (source_kind = 'sales_order' or source_order_id is null));

-- La creación acepta el origen; lo demás, idéntico.
create or replace function private.gama_purchase_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare actor uuid:=auth.uid();request uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;payload jsonb:=p_data-'request_key';po public.purchase_orders;
 supplier public.suppliers;product public.products;line jsonb;qty numeric;cost numeric;rate numeric;
 net numeric;vat numeric;v_sub numeric:=0;v_tax numeric:=0;result jsonb;location uuid:=nullif(p_data->>'destination_location_id','')::uuid;
 origin text:=coalesce(nullif(p_data->>'source_kind',''),'manual');origin_order uuid:=nullif(p_data->>'source_order_id','')::uuid;
begin if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if actor is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase:'||request::text,0));
 select * into receipt from private.command_receipts where domain='purchase' and request_key=request;
 if found then
  if receipt.actor_id<>actor or receipt.payload<>payload then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 if origin not in ('manual','low_stock','sales_order') then raise exception 'INVALID_SOURCE';end if;
 if origin='sales_order' and not exists(select 1 from public.sales_orders o where o.id=origin_order) then raise exception 'INVALID_SOURCE';end if;
 if origin<>'sales_order' then origin_order:=null;end if;
 select * into supplier from public.suppliers where id=(p_data->>'supplier_id')::uuid and active;
 if not found then raise exception 'SUPPLIER_REQUIRED';end if;
 if location is not null and not exists(select 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id=location and l.active and w.active) then raise exception 'INVALID_LOCATION';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 insert into public.purchase_orders(supplier_id,status,expected_date,notes,created_by,destination_location_id,source_kind,source_order_id)
 values(supplier.id,'draft',nullif(p_data->>'expected_date','')::timestamptz,nullif(p_data->>'notes',''),actor,location,origin,origin_order) returning * into po;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  select * into product from public.products where id=(line->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  qty:=(line->>'quantity')::numeric;cost:=(line->>'unit_cost')::numeric;rate:=coalesce(nullif(line->>'tax_rate','')::numeric,product.tax_rate,0);
  if qty is null or qty<=0 or qty>999999999 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
  if cost is null or cost<0 or cost>999999999 or cost<>round(cost,2) then raise exception 'INVALID_PRICE';end if;
  if rate<0 or rate>100 or rate<>round(rate,3) then raise exception 'INVALID_TAX';end if;
  net:=round(qty*cost,2);vat:=round(net*rate/100,2);
  insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,unit_cost,tax_rate,line_total)
   values(po.id,product.id,qty,cost,rate,net+vat);
  v_sub:=v_sub+net;v_tax:=v_tax+vat;
 end loop;
 update public.purchase_orders set subtotal=v_sub,tax=v_tax,total=v_sub+v_tax where id=po.id returning * into po;
 result:=to_jsonb(po);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('purchase',request,actor,payload,result);
 return result;
end $function$;

-- Registro de documentos: la cadena de compra se suma a la de venta.
-- El 0 no es un expediente sino «todavía sin expediente»: no se busca en él,
-- y un documento que lo tenga entra en el expediente que le corresponda
-- conservando su referencia.
create or replace function private.gama_register_document(t text, j jsonb) returns void
language plpgsql security definer set search_path to '' as $function$
declare id uuid:=coalesce((j->>'id')::uuid,(j->>'delivery_id')::uuid); edges jsonb:='[]'; e jsonb;
 cases bigint[]:='{}'; target bigint; p uuid;
begin
 if id is null then return;end if;
 perform pg_advisory_xact_lock(724613092);
 case t
  when 'customer_requests' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'invoice_id'));
  when 'sales_orders' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'source_quote_id'),jsonb_build_array('customer_requests',j->>'source_request_id'));
  when 'fulfillment_preparations' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('sales_deliveries',j->>'shipment_id'));
  when 'fulfillment_packages' then edges:=jsonb_build_array(jsonb_build_array('fulfillment_preparations',j->>'preparation_id'));
  when 'sales_deliveries' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('tms_deliveries',j->>'tms_delivery_id'));
  when 'tms_proofs' then edges:=jsonb_build_array(jsonb_build_array('tms_deliveries',j->>'delivery_id'));
  when 'external_invoices' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('invoices',j->>'source_quote_id'));
  when 'external_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('external_invoices',j->>'invoice_id'));
  when 'return_orders' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('external_invoices',j->>'invoice_id'));
  -- Proceso de compra: la factura del proveedor, con su pedido; el pago, con su factura.
  when 'supplier_invoices' then edges:=jsonb_build_array(jsonb_build_array('purchase_orders',j->>'purchase_order_id'));
  when 'supplier_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('supplier_invoices',j->>'supplier_invoice_id'));
  else null;end case;

 -- Mirar antes de pedir: el documento y sus enlaces, por si ya tienen casa.
 cases:=coalesce((select array_agg(dossier_number) from public.gama_document_references
   where table_name=t and document_id=id and dossier_number>0),'{}');
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   cases:=cases||coalesce((select array_agg(dossier_number) from public.gama_document_references
     where table_name=e->>0 and document_id=p and dossier_number>0),'{}');
  end if;
 end loop;
 select min(x) into target from unnest(cases) x;
 -- Y sólo aquí, cuando de verdad nace un expediente, se gasta un número.
 if target is null then target:=nextval('private.gama_dossier_sequence');end if;

 insert into public.gama_document_references(table_name,document_id,dossier_number)
  values(t,id,target) on conflict do nothing;
 update public.gama_document_references set dossier_number=target
  where table_name=t and document_id=id and dossier_number=0;
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   insert into public.gama_document_references(table_name,document_id,dossier_number)
    values(e->>0,p,target) on conflict do nothing;
   update public.gama_document_references set dossier_number=target
    where table_name=e->>0 and document_id=p and dossier_number=0;
  end if;
 end loop;

 update public.gama_document_references set dossier_number=target
  where dossier_number=any(cases) and dossier_number<>target;

 update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;
end $function$;

-- El sello de referencias envía la cadena de compra al registro. Una factura
-- de proveedor sin pedido, o el pago de una factura así, no es un proceso de
-- compra: sigue con su contador propio, como hasta ahora.
create or replace function private.erp_stamp_reference() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare j jsonb:=to_jsonb(new);f public.erp_reference_formats;key text:=coalesce(j->>'id',j->>'delivery_id');ref text;begin
 select * into f from public.erp_reference_formats where source_table=tg_table_name and (kind_value is null or kind_value=j->>'kind');
 if not found then raise exception 'REFERENCE_KIND_INVALID';end if;
 if tg_table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders','purchase_orders')
    or (tg_table_name='supplier_invoices' and j->>'purchase_order_id' is not null)
    or (tg_table_name='supplier_invoice_payments' and exists(select 1 from public.gama_document_references d where d.table_name='supplier_invoices' and d.document_id=(j->>'supplier_invoice_id')::uuid and d.dossier_number>0)) then
 perform private.gama_register_document(tg_table_name,j);
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 else
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 if ref is null then ref:=private.erp_issue_reference(f.kind,tg_table_name||'/'||key,null,j->>f.number_column);end if;
 insert into public.gama_document_references(table_name,document_id,dossier_number,document_reference) values(tg_table_name,key::uuid,0,ref) on conflict(table_name,document_id) do nothing;
 end if;
 j:=jsonb_build_object('erp_reference',ref);
 if f.number_column is not null then j:=j||jsonb_build_object(f.number_column,ref);end if;
 if tg_table_name='external_invoices' and to_jsonb(new)->>'document_kind'='internal' then j:=j||jsonb_build_object('number',ref);end if;
 new:=jsonb_populate_record(new,j);return new;
end $function$;

-- Los pedidos de compra existentes entran cada uno en su expediente, con sus
-- facturas y pagos; las referencias ya emitidas se conservan.
do $$declare r record;begin
 for r in select to_jsonb(p) j from public.purchase_orders p order by p.created_at,p.id loop
  perform private.gama_register_document('purchase_orders',r.j);
 end loop;
 for r in select to_jsonb(s) j from public.supplier_invoices s where s.purchase_order_id is not null order by s.created_at,s.id loop
  perform private.gama_register_document('supplier_invoices',r.j);
 end loop;
 for r in select to_jsonb(x) j from public.supplier_invoice_payments x
   where exists(select 1 from public.gama_document_references d where d.table_name='supplier_invoices' and d.document_id=x.supplier_invoice_id and d.dossier_number>0)
   order by x.created_at,x.id loop
  perform private.gama_register_document('supplier_invoice_payments',r.j);
 end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922174307','purchase_process_number','876ddb0a19e32eab36fdcd69b98da5eb6627dfad7dc01011b32571399ced24f2','876ddb0a19e32eab36fdcd69b98da5eb6627dfad7dc01011b32571399ced24f2','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922180027_return_process_number.sql; SHA256 a13dfe811d1e2a70896d5a04ac592ec1eb199966877ff79cbe7f32fb6e7c2967
-- Procesos de devolución: PRC (cliente) y PRP (proveedor), un número cada uno.
--
-- Como la venta (PDV) y la compra (PDC), cada devolución es ahora un proceso
-- con un número que llevan todos sus documentos: la devolución DEV-00001340,
-- su abono NCR-00001340 y su reembolso REE-00001340.
--
-- Hasta aquí la devolución de un cliente entraba en el expediente de su venta:
-- dos devoluciones de la misma venta habrían compartido número, y el abono y el
-- reembolso llevaban contadores propios. Ahora la devolución abre su propio
-- expediente —el pedido, la entrega y la factura de origen siguen enlazados en
-- sus columnas y se enseñan en el paso 1—, y el abono y el reembolso entran en
-- él. Las referencias ya emitidas no cambian.

create or replace function private.gama_register_document(t text, j jsonb) returns void
language plpgsql security definer set search_path to '' as $function$
declare id uuid:=coalesce((j->>'id')::uuid,(j->>'delivery_id')::uuid); edges jsonb:='[]'; e jsonb;
 cases bigint[]:='{}'; target bigint; p uuid;
begin
 if id is null then return;end if;
 perform pg_advisory_xact_lock(724613092);
 case t
  when 'customer_requests' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'invoice_id'));
  when 'sales_orders' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'source_quote_id'),jsonb_build_array('customer_requests',j->>'source_request_id'));
  when 'fulfillment_preparations' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('sales_deliveries',j->>'shipment_id'));
  when 'fulfillment_packages' then edges:=jsonb_build_array(jsonb_build_array('fulfillment_preparations',j->>'preparation_id'));
  when 'sales_deliveries' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('tms_deliveries',j->>'tms_delivery_id'));
  when 'tms_proofs' then edges:=jsonb_build_array(jsonb_build_array('tms_deliveries',j->>'delivery_id'));
  when 'external_invoices' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('invoices',j->>'source_quote_id'));
  when 'external_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('external_invoices',j->>'invoice_id'));
  -- Una devolución es su propio proceso (PRC o PRP): abre su expediente en vez
  -- de entrar en el de la venta. El enlace con el pedido sigue en sus columnas.
  when 'return_orders' then edges:='[]'::jsonb;
  -- Su abono y su reembolso llevan su número.
  when 'return_credits' then edges:=jsonb_build_array(jsonb_build_array('return_orders',j->>'return_id'));
  when 'return_refunds' then edges:=jsonb_build_array(jsonb_build_array('return_orders',j->>'return_id'));
  -- Proceso de compra: la factura del proveedor, con su pedido; el pago, con su factura.
  when 'supplier_invoices' then edges:=jsonb_build_array(jsonb_build_array('purchase_orders',j->>'purchase_order_id'));
  when 'supplier_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('supplier_invoices',j->>'supplier_invoice_id'));
  else null;end case;

 -- Mirar antes de pedir: el documento y sus enlaces, por si ya tienen casa.
 cases:=coalesce((select array_agg(dossier_number) from public.gama_document_references
   where table_name=t and document_id=id and dossier_number>0),'{}');
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   cases:=cases||coalesce((select array_agg(dossier_number) from public.gama_document_references
     where table_name=e->>0 and document_id=p and dossier_number>0),'{}');
  end if;
 end loop;
 select min(x) into target from unnest(cases) x;
 -- Y sólo aquí, cuando de verdad nace un expediente, se gasta un número.
 if target is null then target:=nextval('private.gama_dossier_sequence');end if;

 insert into public.gama_document_references(table_name,document_id,dossier_number)
  values(t,id,target) on conflict do nothing;
 update public.gama_document_references set dossier_number=target
  where table_name=t and document_id=id and dossier_number=0;
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   insert into public.gama_document_references(table_name,document_id,dossier_number)
    values(e->>0,p,target) on conflict do nothing;
   update public.gama_document_references set dossier_number=target
    where table_name=e->>0 and document_id=p and dossier_number=0;
  end if;
 end loop;

 update public.gama_document_references set dossier_number=target
  where dossier_number=any(cases) and dossier_number<>target;

 update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;
end $function$;

create or replace function private.erp_stamp_reference() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare j jsonb:=to_jsonb(new);f public.erp_reference_formats;key text:=coalesce(j->>'id',j->>'delivery_id');ref text;begin
 select * into f from public.erp_reference_formats where source_table=tg_table_name and (kind_value is null or kind_value=j->>'kind');
 if not found then raise exception 'REFERENCE_KIND_INVALID';end if;
 if tg_table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders','purchase_orders','return_credits','return_refunds')
    or (tg_table_name='supplier_invoices' and j->>'purchase_order_id' is not null)
    or (tg_table_name='supplier_invoice_payments' and exists(select 1 from public.gama_document_references d where d.table_name='supplier_invoices' and d.document_id=(j->>'supplier_invoice_id')::uuid and d.dossier_number>0)) then
 perform private.gama_register_document(tg_table_name,j);
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 else
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 if ref is null then ref:=private.erp_issue_reference(f.kind,tg_table_name||'/'||key,null,j->>f.number_column);end if;
 insert into public.gama_document_references(table_name,document_id,dossier_number,document_reference) values(tg_table_name,key::uuid,0,ref) on conflict(table_name,document_id) do nothing;
 end if;
 j:=jsonb_build_object('erp_reference',ref);
 if f.number_column is not null then j:=j||jsonb_build_object(f.number_column,ref);end if;
 if tg_table_name='external_invoices' and to_jsonb(new)->>'document_kind'='internal' then j:=j||jsonb_build_object('number',ref);end if;
 new:=jsonb_populate_record(new,j);return new;
end $function$;

-- Abonos y reembolsos existentes: entran en el expediente de su devolución,
-- conservando su referencia.
do $$declare r record;begin
 for r in select to_jsonb(c) j from public.return_credits c order by c.created_at,c.id loop
  perform private.gama_register_document('return_credits',r.j);
 end loop;
 for r in select to_jsonb(f) j from public.return_refunds f order by f.created_at,f.id loop
  perform private.gama_register_document('return_refunds',r.j);
 end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922180027','return_process_number','a13dfe811d1e2a70896d5a04ac592ec1eb199966877ff79cbe7f32fb6e7c2967','a13dfe811d1e2a70896d5a04ac592ec1eb199966877ff79cbe7f32fb6e7c2967','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922181448_delivery_module.sql; SHA256 b8bfb5d2e725af35b7eaf2e63b6e376cbe5a4133bca05be25743cf63f634cbb4
-- Preparación de pedidos deja de ser un módulo: es la primera pestaña de
-- Entrega (tms). El interruptor de 'tms' gobierna también las comprobaciones
-- de servidor que siguen nombrando 'order-preparation' (lectura de códigos de
-- barras y plan de lotes al preparar), para que apagar Entrega a un perfil no
-- deje media cadena abierta.
create or replace function private.erp_module_allowed(p_module text,p_roles text[]) returns boolean
language sql stable set search_path='' as $$
 select coalesce((select p.active and private.current_user_role()=any(p_roles) and p.role=any(p_roles)
  and not coalesce(a.disabled_modules && array[p_module,case when p_module='order-preparation' then 'tms' end],false)
  and not exists(select 1 from public.app_modules m where m.id in (p_module,case when p_module='order-preparation' then 'tms' end) and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922181448','delivery_module','b8bfb5d2e725af35b7eaf2e63b6e376cbe5a4133bca05be25743cf63f634cbb4','b8bfb5d2e725af35b7eaf2e63b6e376cbe5a4133bca05be25743cf63f634cbb4','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922185312_contacts_module.sql; SHA256 05fff5235d41297b4bd8803001613e8a46fea34d522ffd3c2f41abd0b7990400
-- Clientes y Proveedores se funden en un módulo, Contactos (contacts). Los ids
-- antiguos siguen nombrando políticas y comprobaciones de servidor; desde ahora
-- el interruptor del módulo que los absorbió las gobierna también, igual que
-- Entrega (tms) con order-preparation y el panel de control con operations.
create function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard' end
$$;
revoke all on function private.erp_module_parent(text) from public,anon;
grant execute on function private.erp_module_parent(text) to authenticated;

create or replace function private.erp_module_allowed(p_module text,p_roles text[]) returns boolean
language sql stable set search_path='' as $$
 select coalesce((select p.active and private.current_user_role()=any(p_roles) and p.role=any(p_roles)
  and not coalesce(a.disabled_modules && array[p_module,private.erp_module_parent(p_module)],false)
  and not exists(select 1 from public.app_modules m where m.id in (p_module,private.erp_module_parent(p_module)) and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
$$;

-- «contacts» pasa a ser un id conocido: se puede cerrar a un perfil y tener
-- permisos de acción propios. Los ids antiguos se conservan para no invalidar
-- las filas que ya los nombran.
alter table public.role_module_access drop constraint role_module_access_known;
alter table public.role_module_access add constraint role_module_access_known check(
 disabled_modules <@ array['sav','documents','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing','contacts']::text[] and array_position(disabled_modules,null::text) is null);

create or replace function private.gama_save_action_permissions(p_role text,p_rows jsonb,p_expected jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_rows jsonb;item jsonb;begin if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.role_module_access where role=p_role for update;if not found then raise exception 'PROFILE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(a) order by a.module),'[]') into current_rows from public.erp_action_permissions a where role=p_role;
 if current_rows is distinct from (select coalesce(jsonb_agg(v order by v->>'module'),'[]') from jsonb_array_elements(p_expected)v) then raise exception 'ACCESS_SETTINGS_CHANGED';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>100 then raise exception 'INVALID_PERMISSIONS';end if;
 for item in select value from jsonb_array_elements(p_rows) loop
 if coalesce(item->>'module','') not in ('mainmenu','sav','documents','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing','contacts') then raise exception 'MODULE_NOT_FOUND';end if;
 insert into public.erp_action_permissions(role,module,allow_create,allow_edit,allow_delete,allow_validate,allow_export,updated_at,updated_by)
 values(p_role,item->>'module',(item->>'allow_create')::boolean,(item->>'allow_edit')::boolean,(item->>'allow_delete')::boolean,(item->>'allow_validate')::boolean,(item->>'allow_export')::boolean,now(),auth.uid())
 on conflict(role,module) do update set allow_create=excluded.allow_create,allow_edit=excluded.allow_edit,allow_delete=excluded.allow_delete,allow_validate=excluded.allow_validate,allow_export=excluded.allow_export,updated_at=now(),updated_by=auth.uid();
 end loop;return jsonb_build_object('saved',true);
end $$;

-- Un perfil que tenía cerrados Clientes o Proveedores no gana acceso con la
-- fusión: Contactos queda cerrado para él. El disparador de sellado exige un
-- administrador conectado, que una migración no tiene; se sella a mano.
alter table public.role_module_access disable trigger stamp_role_module_access;
update public.role_module_access
 set disabled_modules=array_append(disabled_modules,'contacts'),version=version+1,updated_at=now()
 where disabled_modules && array['clients','suppliers'] and not 'contacts'=any(disabled_modules);
alter table public.role_module_access enable trigger stamp_role_module_access;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922185312','contacts_module','05fff5235d41297b4bd8803001613e8a46fea34d522ffd3c2f41abd0b7990400','05fff5235d41297b4bd8803001613e8a46fea34d522ffd3c2f41abd0b7990400','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922190824_audit_trail.sql; SHA256 6c117cf12f765269daf572656b51ac55ccc47cbab7f6b065b142f8b946b8edcc
-- Pista de auditoría: sólo lo que importa, dicho con palabras de negocio.
-- Movimientos de stock, cobros y pagos, facturas emitidas, validaciones y
-- cambios de acceso, leídos de sus propias tablas —que son la fuente de verdad—
-- y no del registro técnico fila a fila, que sigue existiendo para quien lo
-- necesite (erp_audit_events, gama_audit).
create function private.gama_audit_trail(p_filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
 f jsonb:=coalesce(p_filters,'{}');
 f_kind text:=nullif(f->>'kind','');
 f_from timestamptz:=nullif(f->>'from','')::date;
 f_to timestamptz:=nullif(f->>'to','')::date+1;
 f_actor uuid:=nullif(f->>'actor','')::uuid;
 f_q text:=lower(nullif(btrim(coalesce(f->>'search','')),''));
 f_offset int:=greatest(coalesce(nullif(f->>'offset','')::int,0),0);
 f_limit int:=least(greatest(coalesce(nullif(f->>'limit','')::int,50),1),200);
 page jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('audit',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if f_kind is not null and f_kind not in ('stock','payment','invoice','validation','access') then raise exception 'INVALID_KIND';end if;
 with ev(kind,at,actor,action,label,detail,reference,amount,quantity,target_table,target_id) as (
  select 'stock',m.created_at,m.user_id,coalesce(nullif(m.movement_type,''),m.type),
   case m.movement_type when 'receipt' then 'Recepción de compra' when 'delivery' then 'Salida por entrega'
    when 'internal_transfer' then 'Transferencia entre ubicaciones' when 'inventory_adjustment' then 'Ajuste de inventario'
    when 'return_in' then 'Devolución recibida' when 'return_out' then 'Devolución a proveedor'
    else case when m.type='in' then 'Entrada de stock' else 'Salida de stock' end end,
   concat_ws(' · ',p.name,nullif(btrim(coalesce(m.reason,'')),''),nullif(btrim(coalesce(m.comment,'')),'')),
   m.erp_reference,null::numeric,case when m.type='in' then m.quantity else -m.quantity end,'stock_movements',m.id::text
  from public.stock_movements m left join public.products p on p.id=m.product_id
  union all
  select 'payment',x.created_at,x.created_by,'customer_payment','Cobro de cliente',
   concat_ws(' · ',i.number,o.customer_name,x.method),x.erp_reference,x.amount,null,'external_invoice_payments',x.id::text
  from public.external_invoice_payments x left join public.external_invoices i on i.id=x.invoice_id left join public.sales_orders o on o.id=i.order_id
  union all
  select 'payment',x.cancelled_at,x.cancelled_by,'customer_payment_cancelled','Cobro anulado',
   concat_ws(' · ',i.number,o.customer_name,x.cancellation_reason),x.erp_reference,-x.amount,null,'external_invoice_payments',x.id::text
  from public.external_invoice_payments x left join public.external_invoices i on i.id=x.invoice_id left join public.sales_orders o on o.id=i.order_id
  where x.status='cancelled' and x.cancelled_at is not null
  union all
  select 'payment',x.created_at,x.created_by,'supplier_payment',
   case when x.status='cancelled' then 'Pago a proveedor anulado' else 'Pago a proveedor' end,
   concat_ws(' · ',si.number,s.name,x.method),x.erp_reference,-x.amount,null,'supplier_invoice_payments',x.id::text
  from public.supplier_invoice_payments x left join public.supplier_invoices si on si.id=x.supplier_invoice_id left join public.suppliers s on s.id=si.supplier_id
  union all
  select 'payment',x.created_at,x.created_by,'refund','Reembolso a cliente',
   concat_ws(' · ',r.number,c.name,x.method),x.erp_reference,-x.amount,null,'return_refunds',x.id::text
  from public.return_refunds x left join public.return_orders r on r.id=x.return_id left join public.customers c on c.id=r.customer_id
  union all
  select 'invoice',i.created_at,i.created_by,'invoice_issued','Factura emitida',
   concat_ws(' · ',o.customer_name,nullif(i.external_number,'')),coalesce(i.erp_reference,i.number),i.total,null,'external_invoices',i.id::text
  from public.external_invoices i left join public.sales_orders o on o.id=i.order_id
  union all
  select 'invoice',si.created_at,si.created_by,'supplier_invoice','Factura de proveedor registrada',
   concat_ws(' · ',s.name,si.number),coalesce(si.erp_reference,si.number),si.total,null,'supplier_invoices',si.id::text
  from public.supplier_invoices si left join public.suppliers s on s.id=si.supplier_id
  union all
  select 'validation',a.reviewed_at,a.reviewed_by,'approval_'||a.status,
   case when a.status='approved' then 'Validación aprobada' else 'Validación rechazada' end,
   concat_ws(' · ',a.module,a.reason,a.decision_reason),null,null,null,'erp_approvals',a.id::text
  from public.erp_approvals a where a.reviewed_at is not null and a.status in ('approved','rejected')
  union all
  select 'validation',q.reviewed_at,q.reviewed_by,'adjustment_'||q.status,
   case when q.status='approved' then 'Ajuste de stock aprobado' else 'Ajuste de stock rechazado' end,
   concat_ws(' · ',p.name,q.reason,q.decision_reason),null,null,q.target_quantity-q.expected_quantity,'stock_adjustment_requests',q.id::text
  from public.stock_adjustment_requests q left join public.products p on p.id=q.product_id
  where q.reviewed_at is not null and q.status in ('approved','rejected')
  union all
  select 'validation',e.posted_at,e.posted_by,'entry_posted','Asiento contabilizado',
   concat_ws(' · ',e.memo,e.reference),coalesce(e.erp_reference,e.number),null,null,'accounting_entries',e.id::text
  from public.accounting_entries e where e.posted_at is not null
  union all
  select 'access',a.created_at,a.actor_id,lower(a.table_name||'_'||a.operation),
   case a.table_name when 'profiles' then case a.operation when 'INSERT' then 'Usuario creado' when 'DELETE' then 'Usuario eliminado' else 'Usuario modificado' end
    when 'role_module_access' then 'Módulos de un perfil modificados' else 'Permisos de acción modificados' end,
   concat_ws(' · ',coalesce(a.after_data->>'full_name',a.before_data->>'full_name',a.after_data->>'display_name',a.after_data->>'role',a.before_data->>'role'),
    coalesce(a.after_data->>'email',a.before_data->>'email'),a.after_data->>'module',a.reason),
   null,null,null,a.table_name,a.record_id
  from public.erp_audit_events a where a.table_name in ('profiles','role_module_access','erp_action_permissions')
 ), hits as (
  select * from ev where at is not null and (f_kind is null or kind=f_kind) and (f_from is null or at>=f_from)
   and (f_to is null or at<f_to) and (f_actor is null or actor=f_actor)
   and (f_q is null or strpos(lower(concat_ws(' ',label,detail,reference)),f_q)>0)
  order by at desc,target_id limit f_limit+1 offset f_offset
 )
 select coalesce(jsonb_agg(jsonb_build_object('kind',h.kind,'at',h.at,'actor_id',h.actor,'actor',coalesce(nullif(pr.full_name,''),pr.email),
   'action',h.action,'label',h.label,'detail',nullif(h.detail,''),'reference',h.reference,'amount',h.amount,'quantity',h.quantity,
   'target_table',h.target_table,'target_id',h.target_id) order by h.at desc,h.target_id),'[]')
  into page from hits h left join public.profiles pr on pr.id=h.actor;
 return jsonb_build_object('items',(select coalesce(jsonb_agg(e order by n),'[]') from jsonb_array_elements(page) with ordinality t(e,n) where n<=f_limit),
  'has_more',jsonb_array_length(page)>f_limit,'offset',f_offset,'limit',f_limit);
end $$;
revoke all on function private.gama_audit_trail(jsonb) from public,anon;
grant execute on function private.gama_audit_trail(jsonb) to authenticated;
create function public.gama_audit_trail(p_filters jsonb default '{}') returns jsonb
language sql stable security invoker set search_path='' as $$select private.gama_audit_trail(p_filters)$$;
revoke all on function public.gama_audit_trail(jsonb) from public,anon;
grant execute on function public.gama_audit_trail(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922190824','audit_trail','6c117cf12f765269daf572656b51ac55ccc47cbab7f6b065b142f8b946b8edcc','6c117cf12f765269daf572656b51ac55ccc47cbab7f6b065b142f8b946b8edcc','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922191148_invitation_template.sql; SHA256 b22e5fe990b555096ad44b072a1ad1e9e2fb596ce2aedbe0cf738a535b57bd7d
-- El correo con el que se crea un acceso se personaliza: asunto y mensaje,
-- con {nombre}, {empresa}, {rol} y {correo}. Una sola fila; la escribe sólo
-- quien administra Usuarios, por su RPC y con control de versión.
create table public.access_invitation_template(
 id boolean primary key default true check(id),
 subject text not null check(length(btrim(subject)) between 1 and 150),
 message text not null check(length(btrim(message)) between 1 and 4000),
 version integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id)
);
create index access_invitation_template_updated_by on public.access_invitation_template(updated_by);
insert into public.access_invitation_template(subject,message) values(
 'Tu acceso a {empresa}',
 E'Hola {nombre}:\n\n{empresa} te ha creado un acceso a Architect ERP con el perfil {rol}.\n\nPulsa el botón de este correo para elegir tu contraseña. Después, un administrador activará la cuenta y podrás entrar con {correo}.\n\nUn saludo.');
alter table public.access_invitation_template enable row level security;
revoke all on public.access_invitation_template from public,anon,authenticated;
grant select on public.access_invitation_template to authenticated;
create policy invitation_template_read on public.access_invitation_template for select to authenticated
 using(private.erp_module_allowed('users',array['administrador']));
create trigger erp_audit_capture after insert or update or delete on public.access_invitation_template
 for each row execute function private.erp_audit_capture();

create function private.gama_save_invitation_template(p_subject text,p_message text,p_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved public.access_invitation_template;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.gama_identity_admin_allowed() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if length(btrim(coalesce(p_subject,''))) not between 1 and 150 or length(btrim(coalesce(p_message,''))) not between 1 and 4000 then raise exception 'INVALID_TEMPLATE';end if;
 update public.access_invitation_template set subject=btrim(p_subject),message=btrim(p_message),version=version+1,updated_at=now(),updated_by=auth.uid()
  where id and version=p_version returning * into saved;
 if not found then raise exception 'TEMPLATE_STALE';end if;
 return to_jsonb(saved);
end $$;
revoke all on function private.gama_save_invitation_template(text,text,integer) from public,anon;
grant execute on function private.gama_save_invitation_template(text,text,integer) to authenticated;
create function public.gama_save_invitation_template(p_subject text,p_message text,p_version integer) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_save_invitation_template(p_subject,p_message,p_version)$$;
revoke all on function public.gama_save_invitation_template(text,text,integer) from public,anon;
grant execute on function public.gama_save_invitation_template(text,text,integer) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922191148','invitation_template','b22e5fe990b555096ad44b072a1ad1e9e2fb596ce2aedbe0cf738a535b57bd7d','b22e5fe990b555096ad44b072a1ad1e9e2fb596ce2aedbe0cf738a535b57bd7d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260922204512_warehouse_shelves.sql; SHA256 cc8606299c44ee1f13cf1b18c82a82c7b008b79bef506f331cd8c4bd641859e9
-- Estanterías simuladas: cada almacén describe sus estanterías (dos letras,
-- número de columnas y de filas) y el servidor genera un espacio de
-- almacenamiento por celda con la referencia AAXX-XX —estantería, columna,
-- fila—. Los espacios son ubicaciones de verdad (warehouse_locations), así
-- que aparecen en todos los desplegables que ya listan ubicaciones.
create table public.warehouse_shelves(
 id uuid primary key default gen_random_uuid(),
 warehouse_id uuid not null references public.warehouses(id) on delete cascade,
 code text not null check(code ~ '^[A-Z]{2}$'),
 name text not null default '' check(length(name)<=120),
 column_count smallint not null check(column_count between 1 and 99),
 row_count smallint not null check(row_count between 1 and 99),
 parent_id uuid references public.warehouse_locations(id) on delete set null,
 version integer not null default 1,
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id),
 unique(warehouse_id,code)
);
create index warehouse_shelves_parent_id on public.warehouse_shelves(parent_id);
create index warehouse_shelves_created_by on public.warehouse_shelves(created_by);
create index warehouse_shelves_updated_by on public.warehouse_shelves(updated_by);
alter table public.warehouse_shelves enable row level security;
revoke all on public.warehouse_shelves from public,anon,authenticated;
grant select on public.warehouse_shelves to authenticated;
create policy warehouse_shelves_read on public.warehouse_shelves for select to authenticated using(private.is_staff());
create trigger erp_audit_capture after insert or update or delete on public.warehouse_shelves
 for each row execute function private.erp_audit_capture();

alter table public.warehouse_locations add column shelf_id uuid references public.warehouse_shelves(id) on delete set null;
create index warehouse_locations_shelf_id on public.warehouse_locations(shelf_id);

-- Un espacio está en uso si guarda existencias, reservas o lotes, o si una
-- compra abierta lo tiene como destino. Sólo los vacíos se quitan.
create function private.gama_shelf_spaces_in_use(p_ids uuid[]) returns text[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(l.code order by l.code),'{}') from public.warehouse_locations l where l.id=any(p_ids) and (
  exists(select 1 from public.stock_quants q where q.location_id=l.id and (q.quantity<>0 or q.reserved_quantity<>0))
  or exists(select 1 from public.stock_reservations r where r.location_id=l.id and r.status='active')
  or exists(select 1 from public.stock_lot_balances b where b.location_id=l.id and b.quantity<>0)
  or exists(select 1 from public.purchase_orders o where o.destination_location_id=l.id and o.status not in ('received','cancelled')))
$$;
revoke all on function private.gama_shelf_spaces_in_use(uuid[]) from public,anon,authenticated;

-- Quita espacios vacíos: se borran si nada los nombra y, si el historial los
-- nombra (movimientos, recuentos…), se archivan para no romperlo.
create function private.gama_shelf_drop_spaces(p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;deleted int:=0;archived int:=0;
begin
 foreach s in array coalesce(p_ids,'{}') loop
  begin
   delete from public.stock_quants where location_id=s and quantity=0 and reserved_quantity=0;
   delete from public.warehouse_locations where id=s;deleted:=deleted+1;
  exception when foreign_key_violation then
   update public.warehouse_locations set active=false,shelf_id=null where id=s;archived:=archived+1;
  end;
 end loop;
 return jsonb_build_object('deleted',deleted,'archived',archived);
end $$;
revoke all on function private.gama_shelf_drop_spaces(uuid[]) from public,anon,authenticated;

create function private.gama_shelf_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sh public.warehouse_shelves;wid uuid;cc int;rc int;pid uuid;nm text;v_code text;c int;r int;
 space text;existing public.warehouse_locations;extra uuid[];busy text[];dropped jsonb:='{"deleted":0,"archived":0}';created int:=0;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 p_data:=coalesce(p_data,'{}');
 if p_action='save' then
  cc:=nullif(p_data->>'column_count','')::int;rc:=nullif(p_data->>'row_count','')::int;
  if cc is null or rc is null or cc not between 1 and 99 or rc not between 1 and 99 then raise exception 'SHELF_SIZE_INVALID';end if;
  nm:=left(btrim(coalesce(p_data->>'name','')),120);pid:=nullif(p_data->>'parent_id','')::uuid;
  if nullif(p_data->>'id','') is null then
   wid:=nullif(p_data->>'warehouse_id','')::uuid;v_code:=upper(btrim(coalesce(p_data->>'code','')));
   if v_code !~ '^[A-Z]{2}$' then raise exception 'SHELF_CODE_INVALID';end if;
   perform 1 from public.warehouses where id=wid;if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
   if exists(select 1 from public.warehouse_shelves w where w.warehouse_id=wid and w.code=v_code) then raise exception 'SHELF_CODE_TAKEN';end if;
   insert into public.warehouse_shelves(warehouse_id,code,name,column_count,row_count,parent_id,created_by,updated_by)
    values(wid,v_code,nm,cc,rc,null,auth.uid(),auth.uid()) returning * into sh;
  else
   select * into sh from public.warehouse_shelves where id=(p_data->>'id')::uuid for update;
   if not found then raise exception 'SHELF_NOT_FOUND';end if;
   if nullif(p_data->>'version','')::int is distinct from sh.version then raise exception 'SHELF_STALE';end if;
   if nullif(p_data->>'code','') is not null and upper(p_data->>'code')<>sh.code then raise exception 'SHELF_CODE_IMMUTABLE';end if;
  end if;
  if pid is not null and not exists(select 1 from public.warehouse_locations where id=pid and warehouse_id=sh.warehouse_id and shelf_id is null) then raise exception 'SHELF_PARENT_INVALID';end if;
  -- Sin zona elegida, los espacios cuelgan de la raíz del almacén si la hay.
  if pid is null then select id into pid from public.warehouse_locations where warehouse_id=sh.warehouse_id and type='warehouse' and parent_id is null order by created_at limit 1;end if;
  -- Lo que queda fuera de las nuevas medidas tiene que estar vacío.
  select array_agg(id) into extra from public.warehouse_locations where shelf_id=sh.id and not (
   substr(warehouse_locations.code,3,2)::int<=cc and substr(warehouse_locations.code,6,2)::int<=rc);
  if extra is not null then
   busy:=private.gama_shelf_spaces_in_use(extra);
   if cardinality(busy)>0 then raise exception 'SHELF_SPACE_IN_USE:%',array_to_string(busy,', ');end if;
   dropped:=private.gama_shelf_drop_spaces(extra);
  end if;
  for c in 1..cc loop for r in 1..rc loop
   space:=sh.code||lpad(c::text,2,'0')||'-'||lpad(r::text,2,'0');
   select * into existing from public.warehouse_locations where warehouse_id=sh.warehouse_id and warehouse_locations.code=space;
   if found then
    if existing.shelf_id is distinct from sh.id and not (existing.shelf_id is null and not existing.active and existing.type='bin') then
     raise exception 'SHELF_SPACE_TAKEN:%',space;
    end if;
    update public.warehouse_locations set shelf_id=sh.id,active=true,type='bin',parent_id=pid,
     name=coalesce(nullif(nm,''),'Estantería '||sh.code)||' · columna '||lpad(c::text,2,'0')||' · fila '||lpad(r::text,2,'0')
     where id=existing.id;
   else
    insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,active,shelf_id)
     values(sh.warehouse_id,pid,space,coalesce(nullif(nm,''),'Estantería '||sh.code)||' · columna '||lpad(c::text,2,'0')||' · fila '||lpad(r::text,2,'0'),'bin',true,sh.id);
    created:=created+1;
   end if;
  end loop;end loop;
  update public.warehouse_shelves set name=nm,column_count=cc,row_count=rc,parent_id=nullif(p_data->>'parent_id','')::uuid,
   version=case when nullif(p_data->>'id','') is null then version else version+1 end,updated_at=now(),updated_by=auth.uid()
   where id=sh.id returning * into sh;
  return to_jsonb(sh)||jsonb_build_object('spaces',cc*rc,'created',created,'removed',dropped);
 elsif p_action='delete' then
  select * into sh from public.warehouse_shelves where id=nullif(p_data->>'id','')::uuid for update;
  if not found then raise exception 'SHELF_NOT_FOUND';end if;
  select array_agg(id) into extra from public.warehouse_locations where shelf_id=sh.id;
  busy:=private.gama_shelf_spaces_in_use(coalesce(extra,'{}'));
  if cardinality(busy)>0 then raise exception 'SHELF_NOT_EMPTY:%',array_to_string(busy,', ');end if;
  dropped:=private.gama_shelf_drop_spaces(extra);
  delete from public.warehouse_shelves where id=sh.id;
  return jsonb_build_object('id',sh.id,'code',sh.code,'removed',dropped);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_shelf_action(text,jsonb) from public,anon;
grant execute on function private.gama_shelf_action(text,jsonb) to authenticated;
create function public.gama_shelf_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_shelf_action(p_action,p_data)$$;
revoke all on function public.gama_shelf_action(text,jsonb) from public,anon;
grant execute on function public.gama_shelf_action(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260922204512','warehouse_shelves','cc8606299c44ee1f13cf1b18c82a82c7b008b79bef506f331cd8c4bd641859e9','cc8606299c44ee1f13cf1b18c82a82c7b008b79bef506f331cd8c4bd641859e9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923061244_warehouse_default_zones.sql; SHA256 aee1fde586d4473f5a7b0a06e561644cb5490ca870330369503d61b4c6f72175
-- Otras ubicaciones, a medida. Cada almacén trae tres zonas con un papel
-- —llegada, salida y cuarentena— y el resto lo crea, renombra o quita quien
-- gestiona el almacén. Los procesos usan esas zonas por su papel, no por un
-- código escrito a mano:
--   · las recepciones y las entradas manuales llegan a la zona de llegada;
--   · la preparación de pedidos deja lo preparado en la zona de salida (antes
--     creaba una zona PR-… por preparación, que llenaba la lista);
--   · las devoluciones de clientes esperan en cuarentena (antes RET-QUARANTINE).
-- Las zonas con papel se renombran pero no se borran. Lo que había en las
-- demás ubicaciones pasa a la zona de llegada con su movimiento; las
-- ubicaciones se borran, o se archivan si el historial las nombra.

alter table public.warehouse_locations add column role text
 constraint warehouse_locations_role_check check (role in ('arrival','departure','quarantine'));
create unique index warehouse_locations_role_key on public.warehouse_locations(warehouse_id,role) where role is not null;

-- La raíz del almacén (tipo 'warehouse', sin padre): el almacén en sí, no un sitio.
create function private.gama_warehouse_root(p_warehouse uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select id from public.warehouse_locations
  where warehouse_id=p_warehouse and type='warehouse' and parent_id is null
  order by (code='STOCK') desc,created_at limit 1
$$;
revoke all on function private.gama_warehouse_root(uuid) from public,anon,authenticated;

-- La zona de un papel en un almacén; si falta, se crea con su nombre por defecto.
-- Sin código de barras propio, como los espacios de estantería: el índice de
-- códigos de barras es único en todos los almacenes.
create function private.gama_zone(p_warehouse uuid,p_role text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v uuid;c text;n text;
begin
 select id into v from public.warehouse_locations where warehouse_id=p_warehouse and role=p_role;
 if v is not null then return v;end if;
 c:=case p_role when 'arrival' then 'LLEGADA' when 'departure' then 'SALIDA' when 'quarantine' then 'CUARENTENA' end;
 n:=case p_role when 'arrival' then 'Zona de llegada' when 'departure' then 'Zona de salida' when 'quarantine' then 'Cuarentena' end;
 if c is null then raise exception 'LOCATION_ROLE_INVALID';end if;
 insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,role,active)
  values(p_warehouse,private.gama_warehouse_root(p_warehouse),c,n,'zone',p_role,true)
  on conflict(warehouse_id,code) do update set role=excluded.role,active=true
  returning id into v;
 return v;
end $$;
revoke all on function private.gama_zone(uuid,text) from public,anon,authenticated;

-- Las recepciones y las entradas sin ubicación llegan a la zona de llegada del
-- almacén principal; la raíz STOCK queda como último recurso.
create or replace function private.gama_default_location() returns uuid
language sql stable security definer set search_path to 'public','private' as $$
 select l.id from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
  where w.code='PRINCIPAL' and l.active and (l.role='arrival' or l.code='STOCK')
  order by (l.role is not distinct from 'arrival') desc limit 1;
$$;

-- Vacía las otras ubicaciones de un almacén: todo menos la raíz, las
-- estanterías y las zonas con papel. Las existencias pasan a la zona de
-- llegada con un movimiento de transferencia interna; lo que estaba pendiente
-- de salir de ellas (preparaciones abiertas, compras por recibir) apunta a la
-- zona de llegada. El total de cada producto no cambia, así que no hay que
-- recalcularlo. Una ubicación se borra si nada la nombra y, si el historial la
-- nombra, se archiva.
create function private.gama_locations_reset(p_warehouse uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare root uuid:=private.gama_warehouse_root(p_warehouse);arr uuid;q record;x record;before_qty numeric;
 moved int:=0;deleted int:=0;archived int:=0;
begin
 -- La cuarentena de devoluciones que ya existía es la zona de cuarentena.
 update public.warehouse_locations set role='quarantine',code='CUARENTENA',name='Cuarentena',barcode=null,parent_id=root,active=true
  where warehouse_id=p_warehouse and code='RET-QUARANTINE' and role is null
    and not exists(select 1 from public.warehouse_locations c where c.warehouse_id=p_warehouse and (c.code='CUARENTENA' or c.role='quarantine'));
 arr:=private.gama_zone(p_warehouse,'arrival');
 perform private.gama_zone(p_warehouse,'departure');perform private.gama_zone(p_warehouse,'quarantine');
 create temporary table if not exists gama_reset_targets(id uuid primary key) on commit drop;
 delete from gama_reset_targets;
 insert into gama_reset_targets select id from public.warehouse_locations where warehouse_id=p_warehouse and shelf_id is null and role is null;
 if exists(select 1 from public.stock_reservations r join gama_reset_targets t on t.id=r.location_id where r.status='active')
  or exists(select 1 from public.stock_quants s join gama_reset_targets t on t.id=s.location_id where s.reserved_quantity<>0 or s.quantity<0)
 then raise exception 'LOCATION_RESET_RESERVED';end if;
 for q in select s.* from public.stock_quants s join gama_reset_targets t on t.id=s.location_id where s.quantity>0 order by s.product_id,s.location_id loop
  perform 1 from public.products where id=q.product_id for update;
  select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=q.product_id;
  update public.stock_quants set quantity=0,updated_at=now() where id=q.id;
  insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity) values(q.product_id,arr,q.quantity,0)
   on conflict(product_id,location_id) do update set quantity=public.stock_quants.quantity+excluded.quantity,updated_at=now();
  insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,source_location_id,destination_location_id,movement_type)
   values(q.product_id,'adjustment',q.quantity,'Reorganización de ubicaciones','Otras ubicaciones vaciadas: pasa a la zona de llegada.',auth.uid(),before_qty,before_qty,q.location_id,arr,'internal_transfer');
  moved:=moved+1;
 end loop;
 update public.fulfillment_pick_lines pl set source_location_id=arr
  from public.fulfillment_preparations p,gama_reset_targets t
  where p.id=pl.preparation_id and t.id=pl.source_location_id and p.status in ('queued','picking') and pl.picked<pl.planned;
 update public.purchase_orders o set destination_location_id=arr from gama_reset_targets t
  where t.id=o.destination_location_id and o.status not in ('received','cancelled');
 update public.warehouse_shelves s set parent_id=null from gama_reset_targets t where t.id=s.parent_id;
 update public.warehouse_locations l set parent_id=root from gama_reset_targets t
  where t.id=l.parent_id and (l.shelf_id is not null or l.role is not null);
 -- De las hojas a la raíz: un padre se quita después que sus hijos.
 for x in with recursive tree as (
   select id,0 depth from public.warehouse_locations where warehouse_id=p_warehouse and parent_id is null
   union all select l.id,tree.depth+1 from public.warehouse_locations l join tree on l.parent_id=tree.id)
  select tree.id from tree join gama_reset_targets t on t.id=tree.id join public.warehouse_locations l on l.id=tree.id
  where tree.id is distinct from root and l.active order by tree.depth desc loop
  begin
   delete from public.stock_quants where location_id=x.id and quantity=0 and reserved_quantity=0;
   delete from public.warehouse_locations where id=x.id;deleted:=deleted+1;
  exception when foreign_key_violation then
   update public.warehouse_locations set active=false where id=x.id;archived:=archived+1;
  end;
 end loop;
 return jsonb_build_object('arrival',arr,'moved',moved,'deleted',deleted,'archived',archived);
end $$;
revoke all on function private.gama_locations_reset(uuid) from public,anon,authenticated;

-- Crear, renombrar y quitar otras ubicaciones. El código se elige al crear y
-- ya no cambia; no puede tener la forma de un espacio de estantería (AAXX-XX).
-- Sólo se quita lo vacío y lo que ningún proceso tiene pendiente.
create function private.gama_location_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare l public.warehouse_locations;w uuid;c text;nm text;v uuid;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if p_action='save' then
  nm:=nullif(btrim(coalesce(p_data->>'name','')),'');
  if nm is null or length(nm)>120 then raise exception 'LOCATION_NAME_REQUIRED';end if;
  if nullif(p_data->>'id','') is not null then
   select * into l from public.warehouse_locations where id=(p_data->>'id')::uuid for update;
   if not found or l.shelf_id is not null or l.type='warehouse' or not l.active then raise exception 'LOCATION_NOT_FOUND';end if;
   if nullif(btrim(coalesce(p_data->>'code','')),'') is not null and upper(btrim(p_data->>'code'))<>l.code then raise exception 'LOCATION_CODE_IMMUTABLE';end if;
   update public.warehouse_locations set name=nm where id=l.id;
   return jsonb_build_object('id',l.id,'code',l.code,'name',nm,'role',l.role);
  end if;
  w:=nullif(p_data->>'warehouse_id','')::uuid;
  if w is null or not exists(select 1 from public.warehouses where id=w) then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  c:=upper(btrim(coalesce(p_data->>'code','')));
  if c !~ '^[A-Z0-9][A-Z0-9._-]{0,23}$' then raise exception 'LOCATION_CODE_INVALID';end if;
  if c ~ '^[A-Z]{2}[0-9]{2}-[0-9]{2}$' then raise exception 'LOCATION_CODE_RESERVED';end if;
  select * into l from public.warehouse_locations where warehouse_id=w and code=c for update;
  if found then
   -- Un código archivado vuelve con su historial en vez de chocar.
   if l.active or l.shelf_id is not null or l.type='warehouse' or l.role is not null then raise exception 'LOCATION_CODE_TAKEN';end if;
   update public.warehouse_locations set active=true,name=nm,parent_id=private.gama_warehouse_root(w) where id=l.id;
   return jsonb_build_object('id',l.id,'code',c,'name',nm,'role',null,'restored',true);
  end if;
  insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type)
   values(w,private.gama_warehouse_root(w),c,nm,'zone') returning id into v;
  return jsonb_build_object('id',v,'code',c,'name',nm,'role',null);
 elsif p_action='delete' then
  select * into l from public.warehouse_locations where id=nullif(p_data->>'id','')::uuid for update;
  if not found or l.shelf_id is not null or l.type='warehouse' or not l.active then raise exception 'LOCATION_NOT_FOUND';end if;
  if l.role is not null then raise exception 'LOCATION_ROLE_REQUIRED';end if;
  if cardinality(private.gama_shelf_spaces_in_use(array[l.id]))>0 then raise exception 'LOCATION_NOT_EMPTY';end if;
  if exists(select 1 from public.warehouse_locations where parent_id=l.id and active)
   or exists(select 1 from public.warehouse_shelves where parent_id=l.id) then raise exception 'LOCATION_HAS_CHILDREN';end if;
  if exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id
   where (pl.source_location_id=l.id or pl.stage_location_id=l.id) and p.status in ('queued','picking','picked','packed')) then raise exception 'LOCATION_IN_USE';end if;
  return private.gama_shelf_drop_spaces(array[l.id])||jsonb_build_object('id',l.id,'code',l.code);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_location_action(text,jsonb) from public,anon;
grant execute on function private.gama_location_action(text,jsonb) to authenticated;
create function public.gama_location_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_location_action(p_action,p_data)$$;
revoke all on function public.gama_location_action(text,jsonb) from public,anon;
grant execute on function public.gama_location_action(text,jsonb) to authenticated;

-- Los procesos, por papel. Se cambia sólo la línea que creaba la zona; si el
-- texto no está donde se espera, la migración se detiene en vez de adivinar.
do $$
declare f regprocedure;d text;o text;
begin
 f:='private.gama_fulfillment_action(text,jsonb)'::regprocedure;d:=pg_get_functiondef(f);
 o:=E'   insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)\n   values(loc.warehouse_id,p.number,''Preparación ''||p.number,''zone'',p.number) on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;';
 if position(o in d)=0 then raise exception 'PATCH_NOT_FOUND:gama_fulfillment_action';end if;
 execute replace(d,o,E'   stage:=private.gama_zone(loc.warehouse_id,''departure'');');

 f:='private.gama_returns_processing(text,jsonb,jsonb,date)'::regprocedure;d:=pg_get_functiondef(f);
 o:=E'  insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)\n   values(loc.warehouse_id,''RET-QUARANTINE'',''Devoluciones — cuarentena'',''zone'',''RET-QUARANTINE'')\n   on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;';
 if position(o in d)=0 then raise exception 'PATCH_NOT_FOUND:gama_returns_processing';end if;
 execute replace(d,o,E'  stage:=private.gama_zone(loc.warehouse_id,''quarantine'');');

 -- Destinos de una devolución revisada: ni la cuarentena, ni la salida, ni la raíz.
 f:='private.gama_returns_action(text,jsonb)'::regprocedure;d:=pg_get_functiondef(f);
 o:='where active and code<>''RET-QUARANTINE'' and code not like ''PR-%''';
 if position(o in d)=0 then raise exception 'PATCH_NOT_FOUND:gama_returns_action';end if;
 execute replace(d,o,'where active and shelf_id is null and type<>''warehouse'' and coalesce(role,'''') not in (''quarantine'',''departure'') or active and shelf_id is not null');
end $$;

-- Cada almacén, con sus tres zonas y sus otras ubicaciones vacías.
do $$
declare w uuid;
begin
 for w in select id from public.warehouses order by code loop perform private.gama_locations_reset(w);end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923061244','warehouse_default_zones','aee1fde586d4473f5a7b0a06e561644cb5490ca870330369503d61b4c6f72175','aee1fde586d4473f5a7b0a06e561644cb5490ca870330369503d61b4c6f72175','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923071616_sales_orders_tab_of_quotes.sql; SHA256 bac8a96e2440979087538bd32714674c20dd9713a8c55d972b4d15a945375da1
-- Los pedidos de venta dejan de ser un módulo aparte: son la pestaña
-- «Pedidos» de Presupuestos y facturas, sin tarjeta ni línea propia en las
-- listas de módulos. Su id sigue nombrando permisos y comprobaciones de
-- servidor; desde ahora el interruptor de Presupuestos y facturas —para toda
-- la empresa o para un perfil— los gobierna también, como Contactos gobierna
-- clients y suppliers.
create or replace function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard' when 'sales-orders' then 'quotes' end
$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923071616','sales_orders_tab_of_quotes','bac8a96e2440979087538bd32714674c20dd9713a8c55d972b4d15a945375da1','bac8a96e2440979087538bd32714674c20dd9713a8c55d972b4d15a945375da1','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923090300_payments_tab_of_quotes.sql; SHA256 ca66d23df65ef44755de3af68719d7333c1b43510cf2fbb138d0e5ca2c3a1039
-- Las facturas y cobros dejan de ser un módulo aparte, como los pedidos: son
-- la pestaña «Facturas» de Presupuestos y facturas, sin tarjeta ni línea
-- propia en las listas de módulos. Su id sigue nombrando permisos y
-- comprobaciones de servidor; el interruptor de Presupuestos y facturas —para
-- toda la empresa o para un perfil— los gobierna también.
create or replace function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard'
  when 'sales-orders' then 'quotes' when 'payments' then 'quotes' end
$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923090300','payments_tab_of_quotes','ca66d23df65ef44755de3af68719d7333c1b43510cf2fbb138d0e5ca2c3a1039','ca66d23df65ef44755de3af68719d7333c1b43510cf2fbb138d0e5ca2c3a1039','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923102828_coco_erp_brand.sql; SHA256 c3e01bda8c31daea3f63a9bcaa6daae81049902036f48edd4e9139c4c5f8b664
alter table public.access_invitation_template disable trigger erp_audit_capture;
-- La aplicación se llama ahora Coco ERP. El modelo del correo de invitación
-- guarda su texto en la base: si todavía nombra Architect ERP (el texto por
-- defecto), se cambia el nombre; un texto redactado por la empresa sin esa
-- mención no se toca.
update public.access_invitation_template
   set subject=replace(subject,'Architect ERP','Coco ERP'),
       message=replace(message,'Architect ERP','Coco ERP'),
       version=version+1,updated_at=now()
 where subject like '%Architect ERP%' or message like '%Architect ERP%';

alter table public.access_invitation_template enable trigger erp_audit_capture;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923102828','coco_erp_brand','c3e01bda8c31daea3f63a9bcaa6daae81049902036f48edd4e9139c4c5f8b664','de2bad057d2917589585cf4fe4520cdd852420d162ca157b68fd590d80357e8d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923181223_warehouse_admin.sql; SHA256 510c7c35d0f0cc8e579ed83dea15638649833c67dd895ca2ad9fd2a995bdd3ff
-- Crear y modificar almacenes desde Almacenes y existencias → Ubicaciones.
-- El código se elige al crear y ya no cambia: lo llevan las etiquetas, los
-- informes y la ubicación por defecto (PRINCIPAL). El nombre, la dirección y
-- la ciudad se cambian cuando haga falta. Un almacén nuevo nace listo para
-- trabajar: su raíz STOCK y sus tres zonas con papel —llegada, salida y
-- cuarentena—, las que buscan las recepciones, la preparación de pedidos y
-- las devoluciones. Lo hacen el administrador y el almacenero.
create function private.gama_warehouse_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w public.warehouses;c text;nm text;dir text;ciudad text;v uuid;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if p_action is distinct from 'save' then raise exception 'INVALID_ACTION';end if;
 nm:=nullif(btrim(coalesce(p_data->>'name','')),'');
 if nm is null or length(nm)>120 then raise exception 'WAREHOUSE_NAME_REQUIRED';end if;
 dir:=nullif(btrim(coalesce(p_data->>'address','')),'');
 ciudad:=nullif(btrim(coalesce(p_data->>'city','')),'');
 if length(dir)>240 or length(ciudad)>120 then raise exception 'WAREHOUSE_TEXT_TOO_LONG';end if;
 if nullif(p_data->>'id','') is not null then
  select * into w from public.warehouses where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  if nullif(btrim(coalesce(p_data->>'code','')),'') is not null and upper(btrim(p_data->>'code'))<>w.code then raise exception 'WAREHOUSE_CODE_IMMUTABLE';end if;
  update public.warehouses set name=nm,address=dir,city=ciudad,updated_at=now() where id=w.id;
  return jsonb_build_object('id',w.id,'code',w.code,'name',nm,'address',dir,'city',ciudad);
 end if;
 c:=upper(btrim(coalesce(p_data->>'code','')));
 if c !~ '^[A-Z0-9][A-Z0-9._-]{0,23}$' then raise exception 'WAREHOUSE_CODE_INVALID';end if;
 begin
  insert into public.warehouses(code,name,address,city) values(c,nm,dir,ciudad) returning id into v;
 exception when unique_violation then raise exception 'WAREHOUSE_CODE_TAKEN';
 end;
 insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,picking_priority)
  values(v,null,'STOCK','Existencias','warehouse',10);
 perform private.gama_zone(v,'arrival');
 perform private.gama_zone(v,'departure');
 perform private.gama_zone(v,'quarantine');
 return jsonb_build_object('id',v,'code',c,'name',nm,'address',dir,'city',ciudad,'created',true);
end $$;
revoke all on function private.gama_warehouse_action(text,jsonb) from public,anon;
grant execute on function private.gama_warehouse_action(text,jsonb) to authenticated;
create function public.gama_warehouse_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_warehouse_action(p_action,p_data)$$;
revoke all on function public.gama_warehouse_action(text,jsonb) from public,anon;
grant execute on function public.gama_warehouse_action(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923181223','warehouse_admin','510c7c35d0f0cc8e579ed83dea15638649833c67dd895ca2ad9fd2a995bdd3ff','510c7c35d0f0cc8e579ed83dea15638649833c67dd895ca2ad9fd2a995bdd3ff','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923185148_tms_proofs_read_reference.sql; SHA256 240537bc565fa717bf9fec2cdffc79b2ace9108c49f29d49925d9beeeed14a62
-- Seguimiento de procesos lee la referencia del proceso que lleva la prueba de
-- entrega (erp_reference). Las pruebas se leen por tms_proofs_read, la vista
-- que sirve la foto; la vista es anterior a la columna y no la tenía, así que
-- toda venta con una entrega creada —justo después de la preparación— dejaba
-- de abrirse. La misma vista, con la columna al final.
create or replace view public.tms_proofs_read with(security_invoker=true) as
 select p.delivery_id,private.document_proof_photo(p.delivery_id) photo,p.signature,p.captured_at,p.captured_by,p.erp_reference
 from public.tms_proofs p;
revoke all on public.tms_proofs_read from anon,authenticated;
grant select on public.tms_proofs_read to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923185148','tms_proofs_read_reference','240537bc565fa717bf9fec2cdffc79b2ace9108c49f29d49925d9beeeed14a62','240537bc565fa717bf9fec2cdffc79b2ace9108c49f29d49925d9beeeed14a62','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923211728_hr_base_role_org_chart.sql; SHA256 8a393fd6d81aa10bd3428a5712c36e00ebbc3554d967e9b5e63ca8cc94d54b32
-- RRHH: «Responsable RH» deja de ser un derecho añadido a otro perfil
-- (hr_permissions) y pasa a ser un perfil de base de la aplicación, como
-- Comercial o Almacenero: profiles.role = 'rrhh'. Y el responsable de cada
-- empleado es su N+1, otro empleado (tenga o no cuenta): de ahí sale el
-- organigrama, y quien es N+1 de alguien valida lo de su equipo sin necesitar
-- un derecho aparte.
--
-- Compatible con la pantalla anterior mientras se publica la nueva: la tabla
-- hr_permissions y la columna manager_profile_id se quedan, sin efecto, y se
-- retiran en la migración siguiente.

-- 1. El perfil de base «Responsable RH». No es personal de ventas ni de
--    almacén: is_staff() no cambia, y no lee productos, existencias ni clientes.
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check
 check (role in ('administrador','comercial','almacenero','cliente','rrhh'));
alter table public.role_module_access drop constraint access_profile_base;
alter table public.role_module_access add constraint access_profile_base
 check (base_role in ('administrador','comercial','almacenero','cliente','rrhh'));
alter table public.role_module_access disable trigger erp_audit_capture;
insert into public.role_module_access(role,base_role,is_custom,display_name,disabled_modules)
values('rrhh','rrhh',false,'Responsable RH','{}') on conflict (role) do nothing;
alter table public.role_module_access enable trigger erp_audit_capture;

-- Quien tenía el derecho «Responsable RH» sin ser administrador pasa al perfil.
update public.profiles p set role='rrhh',access_profile=null
 from public.hr_permissions h
 where h.profile_id=p.id and h.role='hr' and p.role<>'administrador';

-- 2. El N+1 de cada empleado es otro empleado. Se hereda del responsable que
--    tenía (una cuenta), por la ficha ligada a esa cuenta.
alter table public.hr_employees add column manager_id uuid references public.hr_employees(id) on delete set null;
create index hr_employees_manager_id_idx on public.hr_employees(manager_id);
update public.hr_employees e set manager_id=m.id
 from public.hr_employees m
 where m.profile_id=e.manager_profile_id and m.id<>e.id;

-- Ni uno mismo ni un círculo (A depende de B que depende de A), y el N+1 que se
-- elige está activo. Un candado serializa los cambios del organigrama: dos
-- cambios a la vez no pueden cerrar un círculo entre los dos.
create or replace function private.hr_manager_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.manager_id is null or (tg_op='UPDATE' and new.manager_id is not distinct from old.manager_id) then return new; end if;
 if new.manager_id=new.id then raise exception 'HR_MANAGER_SELF'; end if;
 perform pg_advisory_xact_lock(hashtextextended('hr-org-chart',0));
 if not exists(select 1 from public.hr_employees where id=new.manager_id and active) then raise exception 'HR_MANAGER_INACTIVE'; end if;
 if exists(
  with recursive up(id,depth) as (
   select new.manager_id,1
   union all
   select e.manager_id,up.depth+1 from public.hr_employees e join up on e.id=up.id
   where e.manager_id is not null and up.depth<1000)
  select 1 from up where id=new.id) then raise exception 'HR_MANAGER_CYCLE'; end if;
 return new;
end $$;
revoke all on function private.hr_manager_guard() from public,anon,authenticated;
create trigger hr_manager_guard before insert or update of manager_id on public.hr_employees
 for each row execute function private.hr_manager_guard();

-- 3. Quién gestiona RRHH y quién valida a su equipo.
create or replace function private.hr_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(private.current_user_role() in ('administrador','rrhh'),false)
$$;
-- El N+1 con cuenta valida ausencias, turnos y horas de su equipo directo; nunca
-- lo suyo. Sigue haciendo falta ser personal activo.
create or replace function private.hr_manage(p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.hr_admin() or (private.is_staff() and exists(
  select 1 from public.hr_employees e join public.hr_employees m on m.id=e.manager_id
  where e.id=p_employee and m.profile_id=auth.uid() and m.active and e.profile_id is distinct from auth.uid())))
$$;
-- Su propia ficha también la ve y la usa (fichaje, solicitudes) quien es de RRHH.
create or replace function private.hr_own(p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.is_staff() or private.current_user_role()='rrhh')
  and exists(select 1 from public.hr_employees where id=p_employee and profile_id=auth.uid() and active)
$$;
-- Las cuentas que se pueden ligar a una ficha incluyen las de RRHH.
create or replace function private.hr_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null or not private.hr_admin() then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'role',role,'active',active) order by full_name),'[]'::jsonb)
  from public.profiles where active and role in ('administrador','comercial','almacenero','rrhh'));
 end $$;
-- Los documentos de RRHH clasificados para «RRHH» o «equipo» siguen visibles
-- para RRHH: la política restrictiva de hr_documents pasa por aquí.
create or replace function private.document_audience(v text) returns boolean language sql stable set search_path='' as $$
 select auth.uid() is not null and (private.is_staff() or private.hr_admin()) and
 (v='team' or (v='management' and private.current_user_role()='administrador') or (v='hr' and private.hr_admin()))
$$;

-- 4. La ficha guarda su N+1. Sin la clave manager_id no lo toca: la pantalla
--    anterior sigue pudiendo guardar sin borrarlo.
create or replace function public.gama_hr_save_employee(p_employee jsonb,p_private jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
 declare e uuid; begin
 if not private.hr_admin() then raise exception 'HR permission required'; end if;
 if nullif(trim(p_employee->>'full_name'),'') is null then raise exception 'Employee name required'; end if;
 if (p_private->>'salary')::numeric<0 or (p_private->>'annual_leave_days')::numeric<0 then raise exception 'Amounts cannot be negative'; end if;
 if (p_private->>'end_date')::date<(p_private->>'hire_date')::date then raise exception 'Invalid contract dates'; end if;
 if p_id is null then
 insert into public.hr_employees(full_name,position,department,profile_id,manager_id) values(trim(p_employee->>'full_name'),p_employee->>'position',p_employee->>'department',(p_employee->>'profile_id')::uuid,nullif(p_employee->>'manager_id','')::uuid) returning id into e;
 else
 update public.hr_employees set full_name=trim(p_employee->>'full_name'),position=p_employee->>'position',department=p_employee->>'department',profile_id=(p_employee->>'profile_id')::uuid,
  manager_id=case when p_employee ? 'manager_id' then nullif(p_employee->>'manager_id','')::uuid else manager_id end
  where id=p_id returning id into e;
 if e is null then raise exception 'Employee not found'; end if;
 end if;
 insert into public.hr_employee_private(employee_id,identification,email,phone,contract_type,hire_date,end_date,salary,annual_leave_days,notes)
 values(e,p_private->>'identification',p_private->>'email',p_private->>'phone',p_private->>'contract_type',(p_private->>'hire_date')::date,(p_private->>'end_date')::date,(p_private->>'salary')::numeric,coalesce((p_private->>'annual_leave_days')::numeric,15),p_private->>'notes')
 on conflict(employee_id) do update set identification=excluded.identification,email=excluded.email,phone=excluded.phone,contract_type=excluded.contract_type,hire_date=excluded.hire_date,end_date=excluded.end_date,salary=excluded.salary,annual_leave_days=excluded.annual_leave_days,notes=excluded.notes;
 return e;
 end $$;

-- 5. El Asistente conoce la columna del N+1.
do $mig$
declare src text:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure); before int:=length(src);
begin
 src:=replace(src,'"profile_id","manager_profile_id"],"pk":["id"],"module":"hr"}','"profile_id","manager_profile_id","manager_id"],"pk":["id"],"module":"hr"}');
 if length(src)<=before then raise exception 'ANCHOR_AI_HR_EMPLOYEES';end if;
 execute src;
end $mig$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923211728','hr_base_role_org_chart','8a393fd6d81aa10bd3428a5712c36e00ebbc3554d967e9b5e63ca8cc94d54b32','2bd737414a5ffdae7e24b3496202455033030da56d4c49a7c23b066cad1d9400','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260923220018_hr_retire_legacy_rights.sql; SHA256 9c970ef2a3b603564cb8a6520ab0c9c86023d928d558635dea2b6546210c000e
-- RRHH, segunda parte: con la pantalla nueva publicada se retira lo que sólo la
-- anterior leía. Los derechos ya no viven en hr_permissions —los sustituyen el
-- perfil de base «Responsable RH» y el N+1— y el responsable-cuenta
-- (manager_profile_id) quedó copiado en manager_id, el N+1 empleado.

-- El traspaso de una cuenta ya no mueve un equipo: el N+1 es un empleado, y lo
-- cambia RRHH en el organigrama.
do $mig$
declare src text:=pg_get_functiondef('private.gama_user_handover(jsonb)'::regprocedure); before int:=length(src);
begin
 src:=replace(src,'(''public.hr_employees'',''manager_profile_id'',''active''),','');
 if length(src)>=before then raise exception 'ANCHOR_HANDOVER_MANAGER';end if;
 execute src;
end $mig$;

-- El Asistente deja de conocer lo retirado.
do $mig$
declare src text:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure); before int;
begin
 before:=length(src);
 src:=replace(src,'"profile_id","manager_profile_id","manager_id"],"pk":["id"],"module":"hr"}','"profile_id","manager_id"],"pk":["id"],"module":"hr"}');
 if length(src)>=before then raise exception 'ANCHOR_AI_HR_EMPLOYEES';end if;
 before:=length(src);
 src:=replace(src,'{"table":"hr_permissions","columns":["profile_id","role"],"pk":["profile_id"],"module":"hr"},','');
 if length(src)>=before then raise exception 'ANCHOR_AI_HR_PERMISSIONS';end if;
 execute src;
end $mig$;

drop table public.hr_permissions;
alter table public.hr_employees drop column manager_profile_id;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260923220018','hr_retire_legacy_rights','9c970ef2a3b603564cb8a6520ab0c9c86023d928d558635dea2b6546210c000e','9c970ef2a3b603564cb8a6520ab0c9c86023d928d558635dea2b6546210c000e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260925221500_product_import_enrichment.sql; SHA256 6ca6ab6df96cfad5b9531ecd32aa02c661be6028708a3c3d6b46033838d21e73
-- Product Excel imports may enrich an existing product instead of failing on
-- name/barcode/reference identity. Only non-empty incoming fields are applied.
-- Existing populated values are preserved, except price fields: an explicitly
-- supplied price is treated as a deliberate update.
create or replace function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 result uuid; fields text[]; tbl text; data jsonb:=p_row; columns text; values_sql text;
 cid uuid; pid uuid; n integer; existing public.products; patch jsonb:='{}'::jsonb; f text;
begin
 if p_row ? '_errors' then raise exception '%',p_row->>'_errors';end if;
 if p_kind='customerPrices' then
  select count(*),(array_agg(id))[1] into n,cid from public.customers where active and ((nullif(p_row->>'customer_tax_id','') is not null and lower(identification)=lower(p_row->>'customer_tax_id')) or (nullif(p_row->>'customer_tax_id','') is null and lower(name)=lower(p_row->>'customer')));
  if n<>1 then raise exception 'CUSTOMER_UNKNOWN_OR_AMBIGUOUS';end if;
  select count(*),(array_agg(id))[1] into n,pid from public.products where active and ((nullif(p_row->>'reference','') is not null and lower(reference)=lower(p_row->>'reference')) or (nullif(p_row->>'reference','') is null and lower(barcode)=lower(p_row->>'barcode')));
  if n<>1 then raise exception 'PRODUCT_UNKNOWN_OR_AMBIGUOUS';end if;
  if p_row->>'unit_price' is null or (p_row->>'unit_price')::numeric<0 then raise exception 'PRICE_REQUIRED';end if;
  begin
   insert into public.customer_special_prices(customer_id,product_id,unit_price,contract_ref) values(cid,pid,(p_row->>'unit_price')::numeric,p_row->>'contract_ref') on conflict(customer_id,product_id) do update set unit_price=excluded.unit_price,contract_ref=excluded.contract_ref;
   if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
  exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
  return pid;
 end if;
 if length(btrim(coalesce(p_row->>'name','')))=0 then raise exception 'NAME_REQUIRED';end if;

 if p_kind='products' then
  fields:=array['name','description','reference','barcode','category','family','lines','brand','presentation','location','stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','sale_price_b','purchase_price','tax_rate'];

  -- Resolve by barcode first, then reference, then normalized name. More than one
  -- different match is rejected rather than merging two products accidentally.
  select count(distinct id),(array_agg(distinct id))[1] into n,pid
  from public.products
  where active and (
    (nullif(btrim(p_row->>'barcode'),'') is not null and lower(btrim(barcode))=lower(btrim(p_row->>'barcode')))
    or (nullif(btrim(p_row->>'reference'),'') is not null and lower(btrim(reference))=lower(btrim(p_row->>'reference')))
    or lower(btrim(name))=lower(btrim(p_row->>'name'))
  );
  if n>1 then raise exception 'PRODUCT_IDENTITY_AMBIGUOUS';end if;

  if n=1 then
   select * into existing from public.products where id=pid;
   foreach f in array fields loop
    if not (data ? f) or nullif(btrim(data->>f),'') is null then continue;end if;
    -- Identity fields never overwrite a different populated identity.
    if f in ('name','reference','barcode') then
      if nullif(btrim(to_jsonb(existing)->>f),'') is null then patch:=patch||jsonb_build_object(f,data->f);end if;
    -- Prices are intentional refresh fields when present in the import.
    elsif f in ('sale_price','sale_price_b','purchase_price','tax_rate') then
      patch:=patch||jsonb_build_object(f,data->f);
    -- Other fields only fill blanks / nulls / zero defaults.
    elsif nullif(btrim(to_jsonb(existing)->>f),'') is null
       or (f in ('stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3') and coalesce((to_jsonb(existing)->>f)::numeric,0)=0)
    then patch:=patch||jsonb_build_object(f,data->f);
    end if;
   end loop;
   if p_dry then return pid;end if;
   if patch<>'{}'::jsonb then
    update public.products p set
      name=coalesce(patch->>'name',p.name),
      description=coalesce(patch->>'description',p.description),
      reference=coalesce(patch->>'reference',p.reference),
      barcode=coalesce(patch->>'barcode',p.barcode),
      category=coalesce(patch->>'category',p.category),
      family=coalesce(patch->>'family',p.family),
      lines=coalesce(patch->>'lines',p.lines),
      brand=coalesce(patch->>'brand',p.brand),
      presentation=coalesce(patch->>'presentation',p.presentation),
      location=coalesce(patch->>'location',p.location),
      stock=case when patch ? 'stock' then (patch->>'stock')::numeric else p.stock end,
      min_stock=case when patch ? 'min_stock' then (patch->>'min_stock')::numeric else p.min_stock end,
      max_stock=case when patch ? 'max_stock' then (patch->>'max_stock')::numeric else p.max_stock end,
      qty_per_carton=case when patch ? 'qty_per_carton' then (patch->>'qty_per_carton')::numeric else p.qty_per_carton end,
      weight_g=case when patch ? 'weight_g' then (patch->>'weight_g')::numeric else p.weight_g end,
      volume_cm3=case when patch ? 'volume_cm3' then (patch->>'volume_cm3')::numeric else p.volume_cm3 end,
      sale_price=case when patch ? 'sale_price' then (patch->>'sale_price')::numeric else p.sale_price end,
      sale_price_b=case when patch ? 'sale_price_b' then (patch->>'sale_price_b')::numeric else p.sale_price_b end,
      purchase_price=case when patch ? 'purchase_price' then (patch->>'purchase_price')::numeric else p.purchase_price end,
      tax_rate=case when patch ? 'tax_rate' then (patch->>'tax_rate')::numeric else p.tax_rate end
    where p.id=pid;
   end if;
   return pid;
  end if;
  tbl:='products';
 elsif p_kind='clients' then tbl:='customers';fields:=array['name','identification','category','email','phone','address','city','province','notes'];data:=(data-'tax_id')||jsonb_build_object('identification',data->>'tax_id','category',upper(coalesce(nullif(data->>'category',''),'A')));if data->>'category' not in ('A','B','C') then raise exception 'INVALID_CUSTOMER_CATEGORY';end if;
 elsif p_kind='suppliers' then tbl:='suppliers';fields:=array['name','tax_id','email','phone','address','city','contact_name','notes'];
 else raise exception 'INVALID_IMPORT_KIND';end if;

 if p_kind in ('clients','suppliers') then
  execute format('select count(*) from public.%I where lower(btrim(name))=lower(btrim($1)) and lower(btrim(coalesce(address,'''')))=lower(btrim(coalesce($2,'''')))',tbl) into n using data->>'name',data->>'address';
  if n>0 then raise exception 'DUPLICATE_CONTACT';end if;
 end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key) into columns,values_sql from jsonb_object_keys(data) key where key=any(fields);
 begin
  execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning id',tbl,columns,values_sql,tbl) into result using data;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return result;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260925221500','product_import_enrichment','6ca6ab6df96cfad5b9531ecd32aa02c661be6028708a3c3d6b46033838d21e73','6ca6ab6df96cfad5b9531ecd32aa02c661be6028708a3c3d6b46033838d21e73','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260925223000_product_import_restore_archived.sql; SHA256 997320cd82045a42a47ac8d8636030c5a8b20c82ef5b6f81d5b28c50c5d616ca
-- Product Excel imports may enrich an existing product instead of failing on
-- name/barcode/reference identity. Only non-empty incoming fields are applied.
-- Existing populated values are preserved, except price fields: an explicitly
-- supplied price is treated as a deliberate update.
create or replace function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 result uuid; fields text[]; tbl text; data jsonb:=p_row; columns text; values_sql text;
 cid uuid; pid uuid; n integer; existing public.products; patch jsonb:='{}'::jsonb; f text;
begin
 if p_row ? '_errors' then raise exception '%',p_row->>'_errors';end if;
 if p_kind='customerPrices' then
  select count(*),(array_agg(id))[1] into n,cid from public.customers where active and ((nullif(p_row->>'customer_tax_id','') is not null and lower(identification)=lower(p_row->>'customer_tax_id')) or (nullif(p_row->>'customer_tax_id','') is null and lower(name)=lower(p_row->>'customer')));
  if n<>1 then raise exception 'CUSTOMER_UNKNOWN_OR_AMBIGUOUS';end if;
  select count(*),(array_agg(id))[1] into n,pid from public.products where active and ((nullif(p_row->>'reference','') is not null and lower(reference)=lower(p_row->>'reference')) or (nullif(p_row->>'reference','') is null and lower(barcode)=lower(p_row->>'barcode')));
  if n<>1 then raise exception 'PRODUCT_UNKNOWN_OR_AMBIGUOUS';end if;
  if p_row->>'unit_price' is null or (p_row->>'unit_price')::numeric<0 then raise exception 'PRICE_REQUIRED';end if;
  begin
   insert into public.customer_special_prices(customer_id,product_id,unit_price,contract_ref) values(cid,pid,(p_row->>'unit_price')::numeric,p_row->>'contract_ref') on conflict(customer_id,product_id) do update set unit_price=excluded.unit_price,contract_ref=excluded.contract_ref;
   if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
  exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
  return pid;
 end if;
 if length(btrim(coalesce(p_row->>'name','')))=0 then raise exception 'NAME_REQUIRED';end if;

 if p_kind='products' then
  fields:=array['name','description','reference','barcode','category','family','lines','brand','presentation','location','stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','sale_price_b','purchase_price','tax_rate'];

  -- Resolve by barcode first, then reference, then normalized name. More than one
  -- different match is rejected rather than merging two products accidentally.
  select count(distinct id),(array_agg(distinct id))[1] into n,pid
  from public.products
  where (
    (nullif(btrim(p_row->>'barcode'),'') is not null and lower(btrim(barcode))=lower(btrim(p_row->>'barcode')))
    or (nullif(btrim(p_row->>'reference'),'') is not null and lower(btrim(reference))=lower(btrim(p_row->>'reference')))
    or lower(btrim(name))=lower(btrim(p_row->>'name'))
  );
  if n>1 then raise exception 'PRODUCT_IDENTITY_AMBIGUOUS';end if;

  if n=1 then
   select * into existing from public.products where id=pid;
   -- Re-importing an archived product restores that same record instead of trying to create a duplicate.
   if not existing.active and not p_dry then update public.products set active=true where id=pid; existing.active:=true; end if;
   foreach f in array fields loop
    if not (data ? f) or nullif(btrim(data->>f),'') is null then continue;end if;
    -- Identity fields never overwrite a different populated identity.
    if f in ('name','reference','barcode') then
      if nullif(btrim(to_jsonb(existing)->>f),'') is null then patch:=patch||jsonb_build_object(f,data->f);end if;
    -- Prices are intentional refresh fields when present in the import.
    elsif f in ('sale_price','sale_price_b','purchase_price','tax_rate') then
      patch:=patch||jsonb_build_object(f,data->f);
    -- Other fields only fill blanks / nulls / zero defaults.
    elsif nullif(btrim(to_jsonb(existing)->>f),'') is null
       or (f in ('stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3') and coalesce((to_jsonb(existing)->>f)::numeric,0)=0)
    then patch:=patch||jsonb_build_object(f,data->f);
    end if;
   end loop;
   if p_dry then return pid;end if;
   if patch<>'{}'::jsonb then
    update public.products p set
      name=coalesce(patch->>'name',p.name),
      description=coalesce(patch->>'description',p.description),
      reference=coalesce(patch->>'reference',p.reference),
      barcode=coalesce(patch->>'barcode',p.barcode),
      category=coalesce(patch->>'category',p.category),
      family=coalesce(patch->>'family',p.family),
      lines=coalesce(patch->>'lines',p.lines),
      brand=coalesce(patch->>'brand',p.brand),
      presentation=coalesce(patch->>'presentation',p.presentation),
      location=coalesce(patch->>'location',p.location),
      stock=case when patch ? 'stock' then (patch->>'stock')::numeric else p.stock end,
      min_stock=case when patch ? 'min_stock' then (patch->>'min_stock')::numeric else p.min_stock end,
      max_stock=case when patch ? 'max_stock' then (patch->>'max_stock')::numeric else p.max_stock end,
      qty_per_carton=case when patch ? 'qty_per_carton' then (patch->>'qty_per_carton')::numeric else p.qty_per_carton end,
      weight_g=case when patch ? 'weight_g' then (patch->>'weight_g')::numeric else p.weight_g end,
      volume_cm3=case when patch ? 'volume_cm3' then (patch->>'volume_cm3')::numeric else p.volume_cm3 end,
      sale_price=case when patch ? 'sale_price' then (patch->>'sale_price')::numeric else p.sale_price end,
      sale_price_b=case when patch ? 'sale_price_b' then (patch->>'sale_price_b')::numeric else p.sale_price_b end,
      purchase_price=case when patch ? 'purchase_price' then (patch->>'purchase_price')::numeric else p.purchase_price end,
      tax_rate=case when patch ? 'tax_rate' then (patch->>'tax_rate')::numeric else p.tax_rate end
    where p.id=pid;
   end if;
   return pid;
  end if;
  tbl:='products';
 elsif p_kind='clients' then tbl:='customers';fields:=array['name','identification','category','email','phone','address','city','province','notes'];data:=(data-'tax_id')||jsonb_build_object('identification',data->>'tax_id','category',upper(coalesce(nullif(data->>'category',''),'A')));if data->>'category' not in ('A','B','C') then raise exception 'INVALID_CUSTOMER_CATEGORY';end if;
 elsif p_kind='suppliers' then tbl:='suppliers';fields:=array['name','tax_id','email','phone','address','city','contact_name','notes'];
 else raise exception 'INVALID_IMPORT_KIND';end if;

 if p_kind in ('clients','suppliers') then
  execute format('select count(*) from public.%I where lower(btrim(name))=lower(btrim($1)) and lower(btrim(coalesce(address,'''')))=lower(btrim(coalesce($2,'''')))',tbl) into n using data->>'name',data->>'address';
  if n>0 then raise exception 'DUPLICATE_CONTACT';end if;
 end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key) into columns,values_sql from jsonb_object_keys(data) key where key=any(fields);
 begin
  execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning id',tbl,columns,values_sql,tbl) into result using data;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return result;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260925223000','product_import_restore_archived','997320cd82045a42a47ac8d8636030c5a8b20c82ef5b6f81d5b28c50c5d616ca','997320cd82045a42a47ac8d8636030c5a8b20c82ef5b6f81d5b28c50c5d616ca','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260926003000_coco_intelligence.sql; SHA256 24365d6f1f0ee889df3ea29618a9257f3d41fa33ce783d81231b932ce6b89dcf
-- Coco Intelligence V1 — deterministic inventory intelligence + recommendations.
-- The LLM explains these values; it never computes or writes stock policy.
create table if not exists public.coco_inventory_intelligence (
 product_id uuid primary key references public.products(id) on delete cascade,
 calculated_at timestamptz not null default now(),
 demand_30d numeric not null default 0,
 demand_60d numeric not null default 0,
 demand_90d numeric not null default 0,
 avg_daily_demand numeric not null default 0,
 physical_stock numeric not null default 0,
 reserved_stock numeric not null default 0,
 available_stock numeric not null default 0,
 incoming_stock numeric not null default 0,
 lead_time_days numeric not null default 7,
 safety_stock numeric not null default 0,
 recommended_min numeric not null default 0,
 recommended_max numeric not null default 0,
 recommended_order_qty numeric not null default 0,
 days_of_cover numeric,
 confidence numeric not null default 0 check(confidence between 0 and 100),
 calculation_version text not null default 'inventory-v1'
);
create table if not exists public.coco_recommendations (
 id uuid primary key default gen_random_uuid(),
 module text not null,
 entity_type text not null,
 entity_id uuid not null,
 recommendation_type text not null,
 priority text not null check(priority in ('low','medium','high','critical')),
 title text not null,
 confidence numeric not null default 0 check(confidence between 0 and 100),
 current_value jsonb not null default '{}'::jsonb,
 recommended_value jsonb not null default '{}'::jsonb,
 reasoning jsonb not null default '{}'::jsonb,
 status text not null default 'pending' check(status in ('pending','accepted','modified','rejected','expired')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id) on delete set null
);
create unique index if not exists coco_recommendations_open_inventory_idx
 on public.coco_recommendations(entity_id,recommendation_type) where module='inventory' and status='pending';
alter table public.coco_inventory_intelligence enable row level security;
alter table public.coco_recommendations enable row level security;
create policy coco_inventory_read on public.coco_inventory_intelligence for select to authenticated using(private.is_staff());
create policy coco_recommendations_read on public.coco_recommendations for select to authenticated using(private.is_staff());
revoke insert,update,delete on public.coco_inventory_intelligence from authenticated;
revoke insert,update,delete on public.coco_recommendations from authenticated;

create or replace function public.gama_coco_inventory_analyze()
returns jsonb language plpgsql security definer set search_path='public','private' as $$
declare r record; v_count int:=0; v_now timestamptz:=now();
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if private.current_user_role() <> 'administrador' then raise exception 'ADMIN_REQUIRED'; end if;
 for r in
  with demand as (
   select p.id product_id,
    coalesce(sum(sm.quantity) filter(where sm.created_at>=v_now-interval '30 days' and sm.type='out' and coalesce(sm.movement_type,'') not in ('internal_transfer','inventory_adjustment')),0) d30,
    coalesce(sum(sm.quantity) filter(where sm.created_at>=v_now-interval '60 days' and sm.type='out' and coalesce(sm.movement_type,'') not in ('internal_transfer','inventory_adjustment')),0) d60,
    coalesce(sum(sm.quantity) filter(where sm.created_at>=v_now-interval '90 days' and sm.type='out' and coalesce(sm.movement_type,'') not in ('internal_transfer','inventory_adjustment')),0) d90
   from products p left join stock_movements sm on sm.product_id=p.id where p.active group by p.id
  ), stock as (
   select p.id product_id,coalesce(sum(q.quantity),0) physical,coalesce(sum(q.reserved_quantity),0) reserved
   from products p left join stock_quants q on q.product_id=p.id where p.active group by p.id
  ), incoming as (
   select pol.product_id,coalesce(sum(greatest(pol.quantity-coalesce(pol.received_quantity,0),0)),0) qty
   from purchase_order_lines pol join purchase_orders po on po.id=pol.purchase_order_id
   where po.status in ('draft','sent','partial') group by pol.product_id
  ), rules as (
   select distinct on(product_id) product_id,coalesce(lead_time_days,7) lead_days,min_quantity,max_quantity
   from reorder_rules where active order by product_id,warehouse_id nulls first
  )
  select p.id,p.name,d.d30,d.d60,d.d90,s.physical,s.reserved,coalesce(i.qty,0) incoming,
   coalesce(rr.lead_days,7) lead_days,
   ((d.d30/30.0)*.5+(d.d60/60.0)*.3+(d.d90/90.0)*.2) avgd,
   coalesce(rr.min_quantity,p.min_stock,0) current_min,coalesce(rr.max_quantity,p.max_stock,0) current_max,
   least(100,greatest(20,(case when d.d90>0 then 45 else 15 end)+(case when rr.lead_days is not null then 25 else 5 end)+(case when d.d30>0 then 20 else 5 end))) confidence
  from products p join demand d on d.product_id=p.id join stock s on s.product_id=p.id
  left join incoming i on i.product_id=p.id left join rules rr on rr.product_id=p.id where p.active
 loop
  -- V1 safety stock: 50% of expected lead-time demand. Conservative and transparent until daily variance history is mature.
  insert into coco_inventory_intelligence(product_id,calculated_at,demand_30d,demand_60d,demand_90d,avg_daily_demand,
   physical_stock,reserved_stock,available_stock,incoming_stock,lead_time_days,safety_stock,recommended_min,recommended_max,
   recommended_order_qty,days_of_cover,confidence)
  values(r.id,v_now,r.d30,r.d60,r.d90,round(r.avgd,3),r.physical,r.reserved,greatest(r.physical-r.reserved,0),r.incoming,r.lead_days,
   ceil(r.avgd*r.lead_days*.5),ceil(r.avgd*r.lead_days*1.5),ceil(r.avgd*(r.lead_days+14)+r.avgd*r.lead_days*.5),
   greatest(0,ceil(r.avgd*(r.lead_days+14)+r.avgd*r.lead_days*.5)-greatest(r.physical-r.reserved,0)-r.incoming),
   case when r.avgd>0 then round(greatest(r.physical-r.reserved,0)/r.avgd,1) end,r.confidence)
  on conflict(product_id) do update set calculated_at=excluded.calculated_at,demand_30d=excluded.demand_30d,demand_60d=excluded.demand_60d,
   demand_90d=excluded.demand_90d,avg_daily_demand=excluded.avg_daily_demand,physical_stock=excluded.physical_stock,
   reserved_stock=excluded.reserved_stock,available_stock=excluded.available_stock,incoming_stock=excluded.incoming_stock,
   lead_time_days=excluded.lead_time_days,safety_stock=excluded.safety_stock,recommended_min=excluded.recommended_min,
   recommended_max=excluded.recommended_max,recommended_order_qty=excluded.recommended_order_qty,days_of_cover=excluded.days_of_cover,
   confidence=excluded.confidence,calculation_version=excluded.calculation_version;
  if r.avgd>0 and (r.physical-r.reserved+r.incoming) < ceil(r.avgd*r.lead_days*1.5) then
   insert into coco_recommendations(module,entity_type,entity_id,recommendation_type,priority,title,confidence,current_value,recommended_value,reasoning)
   values('inventory','product',r.id,'reorder',
    case when (r.physical-r.reserved) < r.avgd*r.lead_days then 'critical' else 'high' end,
    'Réapprovisionnement recommandé · '||r.name,r.confidence,
    jsonb_build_object('available_stock',greatest(r.physical-r.reserved,0),'incoming_stock',r.incoming,'min',r.current_min,'max',r.current_max),
    (select jsonb_build_object('min',recommended_min,'max',recommended_max,'order_qty',recommended_order_qty) from coco_inventory_intelligence where product_id=r.id),
    jsonb_build_object('demand_30d',r.d30,'demand_60d',r.d60,'demand_90d',r.d90,'avg_daily_demand',round(r.avgd,3),'lead_time_days',r.lead_days))
   on conflict(entity_id,recommendation_type) where module='inventory' and status='pending'
   do update set priority=excluded.priority,title=excluded.title,confidence=excluded.confidence,current_value=excluded.current_value,
    recommended_value=excluded.recommended_value,reasoning=excluded.reasoning,created_at=v_now;
  else
   update coco_recommendations set status='expired',reviewed_at=v_now
    where module='inventory' and entity_id=r.id and recommendation_type='reorder' and status='pending';
  end if;
  v_count:=v_count+1;
 end loop;
 return jsonb_build_object('products_analyzed',v_count,'calculated_at',v_now);
end $$;
revoke all on function public.gama_coco_inventory_analyze() from public,anon,authenticated;
grant execute on function public.gama_coco_inventory_analyze() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260926003000','coco_intelligence','24365d6f1f0ee889df3ea29618a9257f3d41fa33ce783d81231b932ce6b89dcf','24365d6f1f0ee889df3ea29618a9257f3d41fa33ce783d81231b932ce6b89dcf','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260926003100_coco_intelligence_ai_catalog.sql; SHA256 6606c35f23f9a6cbcb0d86302288ab001233bd29671b3049d7bdb73eaa0827c7
-- Expose deterministic Coco Intelligence results to the existing read-only AI catalog.
-- Keep the technical module id assistant-ia for backwards-compatible authorization.
create or replace function public.gama_coco_inventory_overview()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador'
 or exists(select 1 from public.app_modules where id='assistant-ia' and not enabled) then
  raise exception 'ADMIN_REQUIRED' using errcode='42501';
 end if;
 return jsonb_build_object(
  'calculated_at',(select max(calculated_at) from public.coco_inventory_intelligence),
  'products_analyzed',(select count(*) from public.coco_inventory_intelligence),
  'reorder_count',(select count(*) from public.coco_recommendations where module='inventory' and recommendation_type='reorder' and status='pending'),
  'critical_count',(select count(*) from public.coco_recommendations where module='inventory' and status='pending' and priority='critical'),
  'recommended_units',(select coalesce(sum(recommended_order_qty),0) from public.coco_inventory_intelligence),
  'recommendations',(select coalesce(jsonb_agg(x order by (x->>'priority') asc),'[]'::jsonb) from (
    select jsonb_build_object('id',r.id,'product_id',r.entity_id,'title',r.title,'priority',r.priority,'confidence',r.confidence,
      'current_value',r.current_value,'recommended_value',r.recommended_value,'reasoning',r.reasoning) x
    from public.coco_recommendations r where r.module='inventory' and r.status='pending' order by r.created_at desc limit 25
  ) q)
 );
end $$;
grant execute on function public.gama_coco_inventory_overview() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260926003100','coco_intelligence_ai_catalog','6606c35f23f9a6cbcb0d86302288ab001233bd29671b3049d7bdb73eaa0827c7','6606c35f23f9a6cbcb0d86302288ab001233bd29671b3049d7bdb73eaa0827c7','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260926082444_coco_intelligence_reliability.sql; SHA256 7f3b3374a259dfaf4b6aad1713c67615a0b9982f31ddc6283adc10380e3aad6a
-- Coco Intelligence: guarded cache refresh, explainable stock policy and paged reads.
-- Business stock, thresholds and purchase orders are never changed by this engine.
alter table public.coco_inventory_intelligence add column if not exists draft_purchase_stock numeric not null default 0;

create or replace function private.coco_admin_allowed()
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null
  and private.current_user_role() is not distinct from 'administrador'
  and not exists(select 1 from public.app_modules where id='assistant-ia' and not enabled)
$$;
revoke all on function private.coco_admin_allowed() from public,anon;
grant execute on function private.coco_admin_allowed() to authenticated;
revoke all on public.coco_inventory_intelligence,public.coco_recommendations from public,anon,authenticated;
grant select on public.coco_inventory_intelligence,public.coco_recommendations to authenticated;
drop policy if exists coco_inventory_read on public.coco_inventory_intelligence;
drop policy if exists coco_recommendations_read on public.coco_recommendations;
create policy coco_inventory_read on public.coco_inventory_intelligence for select to authenticated using((select private.coco_admin_allowed()));
create policy coco_recommendations_read on public.coco_recommendations for select to authenticated using((select private.coco_admin_allowed()));

create or replace function private.coco_inventory_refresh()
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; v_now timestamptz:=now(); v_count integer:=0;
 v_min numeric; v_max numeric; v_qty numeric; v_safety numeric; v_available numeric; v_kind text;
begin
 if not private.coco_admin_allowed() then raise exception 'ADMIN_REQUIRED' using errcode='42501'; end if;
 if not pg_try_advisory_xact_lock(260926,1) then raise exception 'ANALYSIS_BUSY' using errcode='55P03'; end if;
 for r in
  with demand as (
   select sm.product_id,
    sum(sm.quantity) filter(where sm.created_at>=v_now-interval '30 days') d30,
    sum(sm.quantity) filter(where sm.created_at>=v_now-interval '60 days') d60,
    sum(sm.quantity) d90, count(distinct sm.created_at::date) demand_days,
    extract(day from v_now-min(sm.created_at)) history_days
   from public.stock_movements sm
   where sm.type='out' and sm.quantity>0 and sm.created_at between v_now-interval '90 days' and v_now
    and (sm.movement_type is null or sm.movement_type in ('delivery','manual_out','production_out'))
   group by sm.product_id
  ), stock as (
   select product_id,sum(quantity) physical,sum(reserved_quantity) reserved from public.stock_quants group by product_id
  ), incoming as (
   select l.product_id,
    sum(greatest(l.quantity-coalesce(l.received_quantity,0),0)) filter(where o.status in ('sent','partial')) qty,
    sum(greatest(l.quantity-coalesce(l.received_quantity,0),0)) filter(where o.status='draft') draft_qty
   from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
   where o.status in ('draft','sent','partial') group by l.product_id
  ), rules as (
   -- A global rule takes precedence; otherwise combine warehouse policies.
   select product_id,coalesce(max(lead_time_days) filter(where warehouse_id is null),max(lead_time_days),7) lead_days,
    coalesce(max(min_quantity) filter(where warehouse_id is null),sum(min_quantity)) min_qty,
    coalesce(max(max_quantity) filter(where warehouse_id is null),sum(max_quantity)) max_qty
   from public.reorder_rules where active group by product_id
  )
  select p.id,p.name,coalesce(d.d30,0) d30,coalesce(d.d60,0) d60,coalesce(d.d90,0) d90,
   coalesce(d.demand_days,0) demand_days,coalesce(d.history_days,0) history_days,
   coalesce(s.physical,p.stock,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(i.qty,0) incoming,coalesce(i.draft_qty,0) draft_qty,
   greatest(coalesce(rr.lead_days,7),1) lead_days,rr.product_id is not null lead_configured,
   coalesce(d.d30,0)/30.0*.5+coalesce(d.d60,0)/60.0*.3+coalesce(d.d90,0)/90.0*.2 avgd,
   greatest(coalesce(rr.min_qty,p.min_stock,0),0) current_min,
   greatest(coalesce(rr.max_qty,p.max_stock,0),coalesce(rr.min_qty,p.min_stock,0),0) current_max,
   case when coalesce(d.d90,0)=0 then 20
    else least(90,30+least(40,coalesce(d.history_days,0)*40/90)+least(10,coalesce(d.demand_days,0))+case when rr.product_id is not null then 10 else 0 end) end confidence
  from public.products p left join demand d on d.product_id=p.id left join stock s on s.product_id=p.id
  left join incoming i on i.product_id=p.id left join rules rr on rr.product_id=p.id
  where p.active and p.product_kind='goods'
 loop
  v_available:=greatest(r.physical-r.reserved,0);
  v_safety:=ceil(r.avgd*r.lead_days*.5);
  -- Without observed demand retain the configured policy, never recommend zeroing it.
  v_min:=case when r.avgd>0 then ceil(r.avgd*r.lead_days*1.5) else r.current_min end;
  v_max:=case when r.avgd>0 then ceil(r.avgd*(r.lead_days+14)+r.avgd*r.lead_days*.5) else r.current_max end;
  v_qty:=case when v_available+r.incoming+r.draft_qty<v_min
   then greatest(0,ceil(v_max-v_available-r.incoming-r.draft_qty)) else 0 end;
  insert into public.coco_inventory_intelligence(product_id,calculated_at,demand_30d,demand_60d,demand_90d,avg_daily_demand,
   physical_stock,reserved_stock,available_stock,incoming_stock,draft_purchase_stock,lead_time_days,safety_stock,
   recommended_min,recommended_max,recommended_order_qty,days_of_cover,confidence,calculation_version)
  values(r.id,v_now,r.d30,r.d60,r.d90,round(r.avgd,3),r.physical,r.reserved,v_available,r.incoming,r.draft_qty,r.lead_days,v_safety,
   v_min,v_max,v_qty,case when r.avgd>0 then round(v_available/r.avgd,1) end,round(r.confidence),'inventory-v1.1')
  on conflict(product_id) do update set calculated_at=excluded.calculated_at,demand_30d=excluded.demand_30d,
   demand_60d=excluded.demand_60d,demand_90d=excluded.demand_90d,avg_daily_demand=excluded.avg_daily_demand,
   physical_stock=excluded.physical_stock,reserved_stock=excluded.reserved_stock,available_stock=excluded.available_stock,
   incoming_stock=excluded.incoming_stock,draft_purchase_stock=excluded.draft_purchase_stock,lead_time_days=excluded.lead_time_days,
   safety_stock=excluded.safety_stock,recommended_min=excluded.recommended_min,recommended_max=excluded.recommended_max,
   recommended_order_qty=excluded.recommended_order_qty,days_of_cover=excluded.days_of_cover,confidence=excluded.confidence,
   calculation_version=excluded.calculation_version;
  v_kind:=case when v_qty>0 then 'reorder'
   when r.avgd>0 and (v_min<>r.current_min or v_max<>r.current_max) then 'stock_policy' end;
  update public.coco_recommendations set status='expired',reviewed_at=v_now
   where module='inventory' and entity_id=r.id and status='pending' and recommendation_type is distinct from v_kind;
  if v_kind is not null then
   insert into public.coco_recommendations(module,entity_type,entity_id,recommendation_type,priority,title,confidence,current_value,recommended_value,reasoning)
   values('inventory','product',r.id,v_kind,
    case when v_kind='stock_policy' then 'medium' when v_available<=0 or (r.avgd>0 and v_available<r.avgd*r.lead_days) then 'critical' else 'high' end,
    r.name,round(r.confidence),
    jsonb_build_object('available_stock',v_available,'physical_stock',r.physical,'reserved_stock',r.reserved,
     'incoming_stock',r.incoming,'draft_purchase_stock',r.draft_qty,'min',r.current_min,'max',r.current_max),
    jsonb_build_object('min',v_min,'max',v_max,'order_qty',v_qty),
    jsonb_build_object('basis',case when r.avgd>0 then 'observed_demand' else 'configured_thresholds' end,
     'demand_30d',r.d30,'demand_60d',r.d60,'demand_90d',r.d90,'avg_daily_demand',round(r.avgd,3),
     'demand_days',r.demand_days,'history_days',r.history_days,'lead_time_days',r.lead_days,'lead_time_configured',r.lead_configured,
     'safety_stock',v_safety,'days_of_cover',case when r.avgd>0 then round(v_available/r.avgd,1) end,
     'review_days',14,'calculation_version','inventory-v1.1'))
   on conflict(entity_id,recommendation_type) where module='inventory' and status='pending'
   do update set priority=excluded.priority,title=excluded.title,confidence=excluded.confidence,current_value=excluded.current_value,
    recommended_value=excluded.recommended_value,reasoning=excluded.reasoning,created_at=v_now;
  end if;
  v_count:=v_count+1;
 end loop;
 update public.coco_recommendations stale set status='expired',reviewed_at=v_now where module='inventory' and status='pending'
  and not exists(select 1 from public.products p where p.id=stale.entity_id and p.active and p.product_kind='goods');
 delete from public.coco_inventory_intelligence i where not exists(select 1 from public.products p where p.id=i.product_id and p.active and p.product_kind='goods');
 return jsonb_build_object('products_analyzed',v_count,'calculated_at',v_now);
end $$;
revoke all on function private.coco_inventory_refresh() from public,anon;
grant execute on function private.coco_inventory_refresh() to authenticated;
create or replace function public.gama_coco_inventory_analyze()
returns jsonb language sql security invoker set search_path='' as $$select private.coco_inventory_refresh()$$;
revoke all on function public.gama_coco_inventory_analyze() from public,anon,authenticated;
grant execute on function public.gama_coco_inventory_analyze() to authenticated;

drop function public.gama_coco_inventory_overview();
create function public.gama_coco_inventory_overview(p_limit integer default 25,p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_total integer;
begin
 if not private.coco_admin_allowed() then raise exception 'ADMIN_REQUIRED' using errcode='42501'; end if;
 if p_limit is null or p_limit<1 or p_limit>100 or p_offset is null or p_offset<0 or p_offset>100000 then
  raise exception 'INVALID_PAGE' using errcode='22023'; end if;
 select count(*) into v_total from public.coco_recommendations r join public.products p on p.id=r.entity_id
  where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods';
 return jsonb_build_object(
  'calculated_at',(select max(calculated_at) from public.coco_inventory_intelligence),
  'products_analyzed',(select count(*) from public.coco_inventory_intelligence i join public.products p on p.id=i.product_id where p.active and p.product_kind='goods'),
  'without_history',(select count(*) from public.coco_inventory_intelligence i join public.products p on p.id=i.product_id where p.active and p.product_kind='goods' and i.demand_90d=0),
  'recommendation_count',v_total,'offset',p_offset,'limit',p_limit,'has_more',p_offset+p_limit<v_total,
  'reorder_count',(select count(*) from public.coco_recommendations r join public.products p on p.id=r.entity_id where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods' and r.recommendation_type='reorder'),
  'critical_count',(select count(*) from public.coco_recommendations r join public.products p on p.id=r.entity_id where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods' and r.priority='critical'),
  'recommended_units',(select coalesce(sum((r.recommended_value->>'order_qty')::numeric),0) from public.coco_recommendations r join public.products p on p.id=r.entity_id where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods' and r.recommendation_type='reorder'),
  'recommendations',(select coalesce(jsonb_agg(to_jsonb(q) order by q.rank,q.product_name,q.id),'[]'::jsonb) from (
   select r.id,r.entity_id product_id,p.name product_name,p.reference,p.supplier_id,r.title,r.recommendation_type,r.priority,r.confidence,
    r.current_value,r.recommended_value,r.reasoning,
    case r.priority when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end rank
   from public.coco_recommendations r join public.products p on p.id=r.entity_id
   where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods'
   order by rank,p.name,r.id limit p_limit offset p_offset
  ) q)
 );
end $$;
revoke all on function public.gama_coco_inventory_overview(integer,integer) from public,anon,authenticated;
grant execute on function public.gama_coco_inventory_overview(integer,integer) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260926082444','coco_intelligence_reliability','7f3b3374a259dfaf4b6aad1713c67615a0b9982f31ddc6283adc10380e3aad6a','7f3b3374a259dfaf4b6aad1713c67615a0b9982f31ddc6283adc10380e3aad6a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260926111248_stock_exception_adjustments.sql; SHA256 a2d6fd6df8cd8a0ffbcf2ba4c52e5176b43be5be52f663e56b3fd510d69e2be0
-- Exceptional stock operations live in Warehouses, independently of retired IN/OUT.
alter table public.stock_adjustment_requests
 add column kind text not null default 'inventory_difference'
  check(kind in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening')),
 add column submission_hash text,
 add column approval_limit numeric,
 add column lot_id uuid references public.product_lots(id),
 add column erp_reference text;
create index stock_adjustments_date on public.stock_adjustment_requests(requested_at desc,id);
create index stock_adjustments_status on public.stock_adjustment_requests(status,requested_at desc);
create index stock_adjustments_product on public.stock_adjustment_requests(product_id);
create index stock_adjustments_location on public.stock_adjustment_requests(location_id);
create index stock_adjustments_lot on public.stock_adjustment_requests(lot_id);
insert into public.erp_reference_formats(kind,module_id,label_es,prefix,default_prefix,source_table)
 values('stock_adjustment','warehouses','Ajuste de stock','AJU','AJU','stock_adjustment_requests');
insert into private.erp_reference_counters(kind) values('stock_adjustment');
insert into private.erp_reference_prefixes(prefix,kind) values('AJU','stock_adjustment');
do $$declare definition text;begin
 select pg_get_constraintdef(oid) into definition from pg_constraint where conrelid='public.gama_document_references'::regclass and conname='gama_document_references_table_name_check';
 if definition is null then raise exception 'REFERENCE_TABLE_CONSTRAINT_MISSING';end if;
 alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
 execute 'alter table public.gama_document_references add constraint gama_document_references_table_name_check '||replace(definition,'CHECK (','CHECK ((table_name = ''stock_adjustment_requests'') OR ');
end $$;
create trigger zz_erp_reference before insert or update on public.stock_adjustment_requests for each row execute function private.erp_stamp_reference();
update public.stock_adjustment_requests set erp_reference=erp_reference;
alter table public.stock_adjustment_requests add constraint stock_adjustment_reference check(erp_reference ~ '^[A-Z]{3}-[0-9]{8}$');
create unique index stock_adjustment_reference on public.stock_adjustment_requests(erp_reference);
drop policy adjustment_read on public.stock_adjustment_requests;
create policy adjustment_read on public.stock_adjustment_requests for select to authenticated
 using(private.erp_module_allowed('warehouses',array['administrador','almacenero']));

create table public.stock_adjustment_files(
 id uuid primary key default gen_random_uuid(),adjustment_id uuid not null unique references public.stock_adjustment_requests(id) on delete cascade,
 filename text not null check(length(filename) between 1 and 200),
 data_url text not null check(length(data_url)<=1500000 and data_url ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$'),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now()
);
alter table public.stock_adjustment_files enable row level security;
revoke all on public.stock_adjustment_files from public,anon,authenticated;
grant select on public.stock_adjustment_files to authenticated;
create index stock_adjustment_file_actor on public.stock_adjustment_files(created_by);
create policy adjustment_file_read on public.stock_adjustment_files for select to authenticated using(
 private.erp_module_allowed('warehouses',array['administrador','almacenero']) and private.document_source_visible('stock_adjustment_files',id));
-- Index evidence in Documents while retaining the owning module's permissions.
alter table public.business_documents drop constraint business_document_source_known;
alter table public.business_documents add constraint business_document_source_known check(source_table is null or source_table in
 ('hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs','stock_adjustment_files'));
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.document_index(text,jsonb,boolean)'::regprocedure);anchor:='case t';
 if strpos(s,anchor)=0 then raise exception 'DOCUMENT_INDEX_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$p$
 when 'stock_adjustment_files' then cat:='Ajustes de stock';mod:='warehouses';parent:=(j->>'adjustment_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 $p$);execute s;
 s:=pg_get_functiondef('private.document_original_access(public.business_documents)'::regprocedure);anchor:='case d.source_table';
 if strpos(s,anchor)=0 then raise exception 'DOCUMENT_ACCESS_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$p$
 when 'stock_adjustment_files' then return private.erp_module_allowed('warehouses',array['administrador','almacenero']);
 $p$);execute s;
 s:=pg_get_functiondef('private.document_download(uuid)'::regprocedure);anchor:='case d.source_table';
 if strpos(s,anchor)=0 then raise exception 'DOCUMENT_DOWNLOAD_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$p$
 when 'stock_adjustment_files' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.stock_adjustment_files where id=d.source_id;
 $p$);execute s;
end $$;
create trigger document_index after insert or update or delete on public.stock_adjustment_files for each row execute function private.document_index_trigger();
create trigger document_source_guard before insert or update or delete on public.stock_adjustment_files for each row execute function private.document_source_guard();

-- Use the selected lot for an exceptional operation; retain the existing FEFO
-- rules for deliveries and transfers. The selection comes from the locked request.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.erp_lot_movement()'::regprocedure);
 anchor:='if new.source_location_id is null then';
 if strpos(s,anchor)=0 then raise exception 'LOT_ADJUSTMENT_ANCHOR';end if;
 s:=replace(s,anchor,$p$
 if new.reference_type='adjustment_request' then
  select jsonb_build_array(jsonb_build_object('lot_id',a.lot_id,'quantity',abs(new.quantity))) into plan
   from public.stock_adjustment_requests a where a.id=new.reference_id and a.product_id=new.product_id
    and a.location_id=coalesce(new.source_location_id,new.destination_location_id) and a.lot_id is not null;
  if plan is null then raise exception 'ADJUSTMENT_LOT_REQUIRED';end if;
  x:=plan->0;
  if new.source_location_id is not null then
   update public.stock_lot_balances set quantity=quantity-abs(new.quantity)
    where lot_id=(x->>'lot_id')::uuid and location_id=new.source_location_id and quantity>=abs(new.quantity);
   if not found then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  else
   insert into public.stock_lot_balances(lot_id,location_id,quantity) values((x->>'lot_id')::uuid,new.destination_location_id,abs(new.quantity))
    on conflict(lot_id,location_id) do update set quantity=public.stock_lot_balances.quantity+excluded.quantity;
  end if;
  insert into public.stock_lot_movements(movement_id,lot_id,source_location_id,destination_location_id,quantity,created_by)
   values(new.id,(x->>'lot_id')::uuid,new.source_location_id,new.destination_location_id,abs(new.quantity),auth.uid());
  return new;
 end if;
 $p$||anchor);execute s;
end $$;

create or replace function private.gama_adjustment_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 a public.stock_adjustment_requests;q public.stock_quants;m public.stock_movements;p public.products;
 k text:=coalesce(nullif(p_data->>'kind',''),'inventory_difference');key uuid;target numeric;delta numeric;lim numeric;
 v_reason text:=btrim(coalesce(p_data->>'reason',''));lot public.product_lots;rows jsonb;off integer;label text;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then
  off:=greatest(0,coalesce((p_data->>'offset')::integer,0));
  select stock_adjustment_limit into lim from public.erp_policies where id;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into rows from (
   select req.*,prod.name product_name,prod.reference product_reference,l.code location_code,l.name location_name,
    u.full_name requested_name,v.full_name reviewed_name,lotrow.code lot_code,
    exists(select 1 from public.stock_adjustment_files f where f.adjustment_id=req.id and private.document_source_visible('stock_adjustment_files',f.id)) has_photo
   from public.stock_adjustment_requests req join public.products prod on prod.id=req.product_id
   join public.warehouse_locations l on l.id=req.location_id left join public.profiles u on u.id=req.requested_by
   left join public.profiles v on v.id=req.reviewed_by left join public.product_lots lotrow on lotrow.id=req.lot_id
   where (nullif(p_data->>'status','') is null or req.status=p_data->>'status')
   order by req.requested_at desc,req.id desc limit 26 offset off
  )r;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value-'submission_hash'),'[]') from jsonb_array_elements(rows) with ordinality x(value,n) where n<=25),
   'has_more',jsonb_array_length(rows)>25,'approval_limit',lim);
 elsif p_action='photo' then
  select jsonb_build_object('data_url',f.data_url,'filename',f.filename) into rows from public.stock_adjustment_files f
   where f.adjustment_id=(p_data->>'id')::uuid and private.document_source_visible('stock_adjustment_files',f.id);
  if rows is null then raise exception 'DOCUMENT_UNAVAILABLE';end if;return rows;
 elsif p_action='submit' then
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('adjust:'||key::text,0));
  select * into a from public.stock_adjustment_requests where request_key=key;
  if found then
   if a.requested_by is distinct from auth.uid() or (a.submission_hash is not null and a.submission_hash<>md5(p_data::text))
    or (a.submission_hash is null and (a.product_id is distinct from (p_data->>'product_id')::uuid or a.location_id is distinct from (p_data->>'location_id')::uuid or a.target_quantity is distinct from (p_data->>'target_quantity')::numeric or a.reason is distinct from v_reason)) then raise exception 'REQUEST_KEY_REUSED';end if;
   return to_jsonb(a)-'submission_hash';
  end if;
  if k not in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening') then raise exception 'INVALID_ADJUSTMENT_KIND';end if;
  if length(v_reason)<3 or length(v_reason)>2000 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
  if k='opening' and private.current_user_role()<>'administrador' then raise exception 'OPENING_ADMIN_REQUIRED';end if;
  select * into p from public.products where id=(p_data->>'product_id')::uuid and active for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if p.product_kind<>'goods' then raise exception 'STOCK_GOODS_ONLY';end if;
  perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
   where l.id=(p_data->>'location_id')::uuid and l.active and w.active;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
  q:=private.gama_lock_quant(p.id,(p_data->>'location_id')::uuid);
  target:=(p_data->>'target_quantity')::numeric;
  if target is null or target::text in ('NaN','Infinity','-Infinity') or target<0 or target>999999999 or target<>round(target,3) then raise exception 'INVALID_QUANTITY';end if;
  if p_data ? 'kind' and (p_data->>'expected_quantity')::numeric is distinct from q.quantity then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  delta:=target-q.quantity;
  if delta=0 then raise exception 'NO_CHANGE';end if;
  if k not in ('inventory_difference','opening') and delta>=0 then raise exception 'EXCEPTION_OUT_ONLY';end if;
  if target<q.reserved_quantity then raise exception 'RESERVED_EXCEEDS_QUANTITY';end if;
  if k='opening' and (q.quantity<>0 or exists(select 1 from public.stock_movements where product_id=p.id and (source_location_id=q.location_id or destination_location_id=q.location_id))) then raise exception 'OPENING_ALREADY_USED';end if;
  if p.lot_tracking then
   if nullif(p_data->>'lot_id','') is not null then select * into lot from public.product_lots where id=(p_data->>'lot_id')::uuid and product_id=p.id;
   elsif delta>0 and length(btrim(coalesce(p_data->>'lot_code',''))) between 1 and 100 then
    select * into lot from public.product_lots where product_id=p.id and code=btrim(p_data->>'lot_code');
    if lot.id is null then insert into public.product_lots(product_id,code,expires_on,created_by)
     values(p.id,btrim(p_data->>'lot_code'),nullif(p_data->>'expires_on','')::date,auth.uid()) returning * into lot;end if;
   end if;
   if lot.id is null then raise exception 'ADJUSTMENT_LOT_REQUIRED';end if;
   if delta<0 and coalesce((select quantity from public.stock_lot_balances where lot_id=lot.id and location_id=q.location_id),0)<abs(delta) then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  end if;
  select stock_adjustment_limit into lim from public.erp_policies where id;
  insert into public.stock_adjustment_requests(request_key,product_id,location_id,expected_quantity,target_quantity,reason,kind,submission_hash,approval_limit,lot_id)
   values(key,p.id,q.location_id,q.quantity,target,v_reason,k,md5(p_data::text),lim,lot.id) returning * into a;
  if p_data->'photo' is not null and p_data->'photo'<>'null'::jsonb then
   insert into public.stock_adjustment_files(adjustment_id,filename,data_url)
    values(a.id,p_data->'photo'->>'filename',p_data->'photo'->>'data_url');
  end if;
  -- Older clients explicitly requested approval; preserve their pending behavior.
  if p_data ? 'kind' and (lim is null or abs(delta)<=lim) then
   label:=case k when 'breakage' then 'Rotura' when 'loss' then 'Pérdida' when 'expiry' then 'Caducidad' when 'sample' then 'Muestra' when 'donation' then 'Donación' when 'internal_use' then 'Consumo interno' when 'opening' then 'Stock inicial' else 'Diferencia de inventario' end;
   m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity,null,label||' · '||a.reason,a.erp_reference,'adjustment_request',a.id);
   update public.stock_adjustment_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),decision_reason='Aplicado según el umbral configurado',movement_id=m.id where id=a.id returning * into a;
  end if;
 elsif p_action in ('approve','reject','cancel') then
  select * into a from public.stock_adjustment_requests where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'APPROVAL_NOT_PENDING';end if;
  if p_action='cancel' then
   if a.requested_by<>auth.uid() and private.current_user_role()<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
  elsif private.current_user_role()<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  if length(v_reason)<3 or length(v_reason)>2000 then raise exception 'REASON_REQUIRED';end if;
  if a.status<>'pending' then
   if a.status=(case when p_action='approve' then 'approved' else 'rejected' end) and a.reviewed_by=auth.uid() and a.decision_reason=v_reason then return to_jsonb(a)-'submission_hash';end if;
   raise exception 'APPROVAL_NOT_PENDING';
  end if;
  if p_action='approve' then
   select * into p from public.products where id=a.product_id and active for update;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id=a.location_id and l.active and w.active;
   if not found then raise exception 'LOCATION_NOT_FOUND';end if;
   q:=private.gama_lock_quant(a.product_id,a.location_id);
   if q.quantity<>a.expected_quantity then raise exception 'STOCK_CHANGED_RECOUNT';end if;
   m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity,null,a.kind||' · '||a.reason,a.erp_reference||' · '||v_reason,'adjustment_request',a.id);
  end if;
  update public.stock_adjustment_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,
   reviewed_by=auth.uid(),reviewed_at=now(),decision_reason=v_reason,movement_id=m.id where id=a.id returning * into a;
 else raise exception 'INVALID_ACTION';end if;
 return to_jsonb(a)-'submission_hash';
end $$;
revoke all on function private.gama_adjustment_request(text,jsonb) from public,anon;
grant execute on function private.gama_adjustment_request(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260926111248','stock_exception_adjustments','a2d6fd6df8cd8a0ffbcf2ba4c52e5176b43be5be52f663e56b3fd510d69e2be0','a2d6fd6df8cd8a0ffbcf2ba4c52e5176b43be5be52f663e56b3fd510d69e2be0','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927111220_empty_warehouse_deletion.sql; SHA256 a74ec4f2f4e3c3b3f0e6992baa500aa3dda150d3ce0a36e444e9a50e154121f3
-- Remove empty storage structures without deleting their movement history.
create or replace function private.gama_shelf_spaces_in_use(p_ids uuid[]) returns text[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(l.code order by l.code),'{}') from public.warehouse_locations l where l.id=any(p_ids) and (
  exists(select 1 from public.stock_quants q where q.location_id=l.id and (q.quantity<>0 or q.reserved_quantity<>0))
  or exists(select 1 from public.stock_reservations r where r.location_id=l.id and r.status='active')
  or exists(select 1 from public.stock_lot_balances b where b.location_id=l.id and b.quantity<>0)
  or exists(select 1 from public.purchase_orders o where o.destination_location_id=l.id and o.status not in ('received','cancelled'))
  or exists(select 1 from public.stock_adjustment_requests a where a.location_id=l.id and a.status='pending')
  or exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id
    where (pl.source_location_id=l.id or pl.stage_location_id=l.id) and p.status in ('queued','picking','picked','packed'))
  or exists(select 1 from public.inventory_counts c where c.warehouse_id=l.warehouse_id and c.status in ('draft','in_progress')
    and (c.scope_location_id is null or c.scope_location_id=l.id
      or exists(select 1 from public.inventory_count_lines cl where cl.count_id=c.id and cl.location_id=l.id))))
$$;
revoke all on function private.gama_shelf_spaces_in_use(uuid[]) from public,anon,authenticated;

create or replace function private.gama_shelf_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sh public.warehouse_shelves;wid uuid;cc int;rc int;pid uuid;nm text;v_code text;c int;r int;
 space text;existing public.warehouse_locations;extra uuid[];busy text[];dropped jsonb:='{"deleted":0,"archived":0}';created int:=0;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 lock table public.warehouses,public.warehouse_shelves,public.warehouse_locations,
   public.stock_quants,public.stock_reservations,public.stock_lot_balances,public.purchase_orders,
   public.inventory_counts,public.inventory_count_lines,public.stock_adjustment_requests,
   public.fulfillment_preparations,public.fulfillment_pick_lines in share row exclusive mode;
 p_data:=coalesce(p_data,'{}');
 if p_action='save' then
  cc:=nullif(p_data->>'column_count','')::int;rc:=nullif(p_data->>'row_count','')::int;
  if cc is null or rc is null or cc not between 1 and 99 or rc not between 1 and 99 then raise exception 'SHELF_SIZE_INVALID';end if;
  nm:=left(btrim(coalesce(p_data->>'name','')),120);pid:=nullif(p_data->>'parent_id','')::uuid;
  if nullif(p_data->>'id','') is null then
   wid:=nullif(p_data->>'warehouse_id','')::uuid;v_code:=upper(btrim(coalesce(p_data->>'code','')));
   if v_code !~ '^[A-Z]{2}$' then raise exception 'SHELF_CODE_INVALID';end if;
   perform 1 from public.warehouses where id=wid and active;if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
   if exists(select 1 from public.warehouse_shelves w where w.warehouse_id=wid and w.code=v_code) then raise exception 'SHELF_CODE_TAKEN';end if;
   insert into public.warehouse_shelves(warehouse_id,code,name,column_count,row_count,parent_id,created_by,updated_by)
    values(wid,v_code,nm,cc,rc,null,auth.uid(),auth.uid()) returning * into sh;
  else
   select * into sh from public.warehouse_shelves where id=(p_data->>'id')::uuid for update;
   if not found then raise exception 'SHELF_NOT_FOUND';end if;
   if nullif(p_data->>'version','')::int is distinct from sh.version then raise exception 'SHELF_STALE';end if;
   if nullif(p_data->>'code','') is not null and upper(p_data->>'code')<>sh.code then raise exception 'SHELF_CODE_IMMUTABLE';end if;
  end if;
  if pid is not null and not exists(select 1 from public.warehouse_locations where id=pid and warehouse_id=sh.warehouse_id and shelf_id is null) then raise exception 'SHELF_PARENT_INVALID';end if;
  -- Sin zona elegida, los espacios cuelgan de la raíz del almacén si la hay.
  if pid is null then select id into pid from public.warehouse_locations where warehouse_id=sh.warehouse_id and type='warehouse' and parent_id is null order by created_at limit 1;end if;
  -- Lo que queda fuera de las nuevas medidas tiene que estar vacío.
  select array_agg(id) into extra from public.warehouse_locations where shelf_id=sh.id and not (
   substr(warehouse_locations.code,3,2)::int<=cc and substr(warehouse_locations.code,6,2)::int<=rc);
  if extra is not null then
   busy:=private.gama_shelf_spaces_in_use(extra);
   if cardinality(busy)>0 then raise exception 'SHELF_SPACE_IN_USE:%',array_to_string(busy,', ');end if;
   dropped:=private.gama_shelf_drop_spaces(extra);
  end if;
  for c in 1..cc loop for r in 1..rc loop
   space:=sh.code||lpad(c::text,2,'0')||'-'||lpad(r::text,2,'0');
   select * into existing from public.warehouse_locations where warehouse_id=sh.warehouse_id and warehouse_locations.code=space;
   if found then
    if existing.shelf_id is distinct from sh.id and not (existing.shelf_id is null and not existing.active and existing.type='bin') then
     raise exception 'SHELF_SPACE_TAKEN:%',space;
    end if;
    update public.warehouse_locations set shelf_id=sh.id,active=true,type='bin',parent_id=pid,
     name=coalesce(nullif(nm,''),'Estantería '||sh.code)||' · columna '||lpad(c::text,2,'0')||' · fila '||lpad(r::text,2,'0')
     where id=existing.id;
   else
    insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,active,shelf_id)
     values(sh.warehouse_id,pid,space,coalesce(nullif(nm,''),'Estantería '||sh.code)||' · columna '||lpad(c::text,2,'0')||' · fila '||lpad(r::text,2,'0'),'bin',true,sh.id);
    created:=created+1;
   end if;
  end loop;end loop;
  update public.warehouse_shelves set name=nm,column_count=cc,row_count=rc,parent_id=nullif(p_data->>'parent_id','')::uuid,
   version=case when nullif(p_data->>'id','') is null then version else version+1 end,updated_at=now(),updated_by=auth.uid()
   where id=sh.id returning * into sh;
  return to_jsonb(sh)||jsonb_build_object('spaces',cc*rc,'created',created,'removed',dropped);
 elsif p_action='delete' then
  select * into sh from public.warehouse_shelves where id=nullif(p_data->>'id','')::uuid for update;
  if not found then raise exception 'SHELF_NOT_FOUND';end if;
  select array_agg(id) into extra from public.warehouse_locations where shelf_id=sh.id;
  busy:=private.gama_shelf_spaces_in_use(coalesce(extra,'{}'));
  if cardinality(busy)>0 then raise exception 'SHELF_NOT_EMPTY:%',array_to_string(busy,', ');end if;
  dropped:=private.gama_shelf_drop_spaces(extra);
  delete from public.warehouse_shelves where id=sh.id;
  return jsonb_build_object('id',sh.id,'code',sh.code,'removed',dropped);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create or replace function private.gama_warehouse_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w public.warehouses;c text;nm text;dir text;ciudad text;v uuid;ids uuid[];busy text[];archived boolean:=false;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if p_action='delete' then
  lock table public.warehouses,public.warehouse_shelves,public.warehouse_locations,
   public.stock_quants,public.stock_reservations,public.stock_lot_balances,public.purchase_orders,
   public.inventory_counts,public.inventory_count_lines,public.stock_adjustment_requests,
   public.fulfillment_preparations,public.fulfillment_pick_lines in share row exclusive mode;
  select * into w from public.warehouses where id=nullif(p_data->>'id','')::uuid and active for update;
  if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  select coalesce(array_agg(id),'{}') into ids from public.warehouse_locations where warehouse_id=w.id;
  busy:=private.gama_shelf_spaces_in_use(ids);
  if cardinality(busy)>0 then raise exception 'WAREHOUSE_NOT_EMPTY:%',array_to_string(busy,', ');end if;
  if exists(select 1 from public.inventory_counts where warehouse_id=w.id and status in ('draft','in_progress')) then
   raise exception 'WAREHOUSE_IN_USE';end if;
  -- Delete only unreferenced records; keep all historical foreign keys intact.
  begin
   delete from public.warehouse_shelves where warehouse_id=w.id;
   delete from public.stock_quants where location_id=any(ids) and quantity=0 and reserved_quantity=0;
   delete from public.warehouse_locations where warehouse_id=w.id;
   delete from public.warehouses where id=w.id;
  exception when foreign_key_violation then
   archived:=true;
   delete from public.warehouse_shelves where warehouse_id=w.id;
   update public.warehouse_locations set active=false,shelf_id=null where warehouse_id=w.id;
   update public.reorder_rules set active=false where warehouse_id=w.id;
   update public.warehouses set active=false,updated_at=now() where id=w.id;
  end;
  return jsonb_build_object('id',w.id,'code',w.code,'archived',archived);
 end if;
 if p_action is distinct from 'save' then raise exception 'INVALID_ACTION';end if;
 nm:=nullif(btrim(coalesce(p_data->>'name','')),'');
 if nm is null or length(nm)>120 then raise exception 'WAREHOUSE_NAME_REQUIRED';end if;
 dir:=nullif(btrim(coalesce(p_data->>'address','')),'');
 ciudad:=nullif(btrim(coalesce(p_data->>'city','')),'');
 if length(dir)>240 or length(ciudad)>120 then raise exception 'WAREHOUSE_TEXT_TOO_LONG';end if;
 if nullif(p_data->>'id','') is not null then
  select * into w from public.warehouses where id=(p_data->>'id')::uuid and active for update;
  if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  if nullif(btrim(coalesce(p_data->>'code','')),'') is not null and upper(btrim(p_data->>'code'))<>w.code then raise exception 'WAREHOUSE_CODE_IMMUTABLE';end if;
  update public.warehouses set name=nm,address=dir,city=ciudad,updated_at=now() where id=w.id;
  return jsonb_build_object('id',w.id,'code',w.code,'name',nm,'address',dir,'city',ciudad);
 end if;
 c:=upper(btrim(coalesce(p_data->>'code','')));
 if c !~ '^[A-Z0-9][A-Z0-9._-]{0,23}$' then raise exception 'WAREHOUSE_CODE_INVALID';end if;
 begin
  insert into public.warehouses(code,name,address,city) values(c,nm,dir,ciudad) returning id into v;
 exception when unique_violation then raise exception 'WAREHOUSE_CODE_TAKEN';
 end;
 insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,picking_priority)
  values(v,null,'STOCK','Existencias','warehouse',10);
 perform private.gama_zone(v,'arrival');
 perform private.gama_zone(v,'departure');
 perform private.gama_zone(v,'quarantine');
 return jsonb_build_object('id',v,'code',c,'name',nm,'address',dir,'city',ciudad,'created',true);
end $$;

-- An archived location must never receive fresh stock from a stale screen.
create function private.gama_quant_active_location() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.quantity<>0 or new.reserved_quantity<>0 then
  perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
   where l.id=new.location_id and l.active and w.active for share of l,w;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
 end if;
 return new;
end $$;
revoke all on function private.gama_quant_active_location() from public,anon,authenticated;
create trigger gama_quant_active_location before insert or update of location_id,quantity,reserved_quantity
 on public.stock_quants for each row execute function private.gama_quant_active_location();

-- Prefer PRINCIPAL while it exists; otherwise use the first active warehouse.
create or replace function private.gama_default_location() returns uuid
language sql stable security definer set search_path='' as $$
 select l.id from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
 where w.active and l.active and (l.role='arrival' or l.code='STOCK')
 order by (w.code='PRINCIPAL') desc,w.created_at,w.id,(l.role is not distinct from 'arrival') desc limit 1
$$;
revoke all on function private.gama_default_location() from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927111220','empty_warehouse_deletion','a74ec4f2f4e3c3b3f0e6992baa500aa3dda150d3ce0a36e444e9a50e154121f3','a74ec4f2f4e3c3b3f0e6992baa500aa3dda150d3ce0a36e444e9a50e154121f3','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927150402_audit_stock_integrity.sql; SHA256 23bd2dfe8c69a77b064532f75385d156ea5dfaa51dbc22761dc78f1611a0e76d
-- Audit: catalogue writes must never create unlocated stock.
create table public.stock_integrity_cases (
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id),
 observed_at timestamptz not null default now(), catalogue_quantity numeric not null, located_quantity numeric not null,
 resolved_at timestamptz, resolved_by uuid references auth.users(id), resolution text,
 check ((resolved_at is null and resolved_by is null) or (resolved_at is not null and resolved_by is not null and length(btrim(resolution))>=10))
);
create index stock_integrity_product on public.stock_integrity_cases(product_id);
create index stock_integrity_resolver on public.stock_integrity_cases(resolved_by);
alter table public.stock_integrity_cases enable row level security;
revoke all on public.stock_integrity_cases from public,anon,authenticated;
grant select on public.stock_integrity_cases to authenticated;
create policy stock_integrity_read on public.stock_integrity_cases for select to authenticated using(private.erp_module_allowed('warehouses',array['administrador']));
insert into public.stock_integrity_cases(product_id,catalogue_quantity,located_quantity)
 select p.id,p.stock,coalesce(q.quantity,0) from public.products p left join
 (select product_id,sum(quantity) quantity from public.stock_quants group by product_id) q on q.product_id=p.id
 where p.stock is distinct from coalesce(q.quantity,0);

create function private.erp_product_stock_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.stock is not distinct from old.stock then return new;end if;
 if new.stock is distinct from coalesce((select sum(quantity) from public.stock_quants where product_id=new.id),0) then
  raise exception 'STOCK_REQUIRES_MOVEMENT' using hint='Use a receipt or a located, justified stock adjustment.';
 end if;return new;
end $$;
create trigger product_stock_from_quants before insert or update of stock on public.products for each row execute function private.erp_product_stock_guard();
create function private.erp_quant_sync() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid:=case when tg_op='DELETE' then old.product_id else new.product_id end;
begin
 if tg_op='UPDATE' and (new.product_id<>old.product_id or new.location_id<>old.location_id) then raise exception 'QUANT_IDENTITY_IMMUTABLE';end if;
 -- The product lock serializes all located quantities, including independent locations.
 perform 1 from public.products where id=pid for update;
 update public.products set stock=coalesce((select sum(quantity) from public.stock_quants where product_id=pid),0),updated_at=now() where id=pid;
 return null;
end $$;
create trigger zz_quant_sync after insert or update of quantity,product_id,location_id or delete on public.stock_quants for each row execute function private.erp_quant_sync();
revoke all on function private.erp_product_stock_guard(),private.erp_quant_sync() from public,anon,authenticated;

-- Keep catalogue enrichment, but remove its ability to update stock.
alter function private.erp_import_row(text,jsonb,boolean) rename to erp_import_catalogue_row;
revoke all on function private.erp_import_catalogue_row(text,jsonb,boolean) from public,anon,authenticated;
-- Draft catalogue imports can be completed before the optional activation gate.
-- Existing active products are never archived by a catalogue enrichment.
do $$declare s text;begin
 s:=pg_get_functiondef('private.erp_import_catalogue_row(text,jsonb,boolean)'::regprocedure);
 s:=replace(s,'fields:=array[''name'',''description''','fields:=array[''active'',''name'',''description''');
 s:=replace(s,'if not existing.active and not p_dry then','if not existing.active and not p_dry and not coalesce((p_row->>''_catalogue_draft'')::boolean,false) then');execute s;
end $$;
create function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid;qty numeric;result jsonb;
begin
 if p_kind<>'products' then return private.erp_import_catalogue_row(p_kind,p_row,p_dry);end if;
 qty:=coalesce(nullif(p_row->>'stock','')::numeric,0);
 if qty::text in ('NaN','Infinity','-Infinity') or qty<0 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
 if coalesce((p_row->>'_catalogue_draft')::boolean,false) then
  if qty>0 then raise exception 'DRAFT_CANNOT_OPEN_STOCK';end if;
  p_row:=p_row||jsonb_build_object('active',false);
 end if;
 if qty>0 and (nullif(p_row->>'opening_location_id','') is null or length(btrim(coalesce(p_row->>'opening_reason','')))<10) then raise exception 'OPENING_LOCATION_AND_REASON_REQUIRED';end if;
 begin
  pid:=private.erp_import_catalogue_row(p_kind,p_row-'stock',false);
  if qty>0 then
   -- Opening is explicit, located, one-time and uses the same approval/lot controls as the stock screen.
   result:=private.gama_adjustment_request('submit',jsonb_build_object('request_key',gen_random_uuid(),'kind','opening','product_id',pid,
    'location_id',p_row->>'opening_location_id','expected_quantity',0,'target_quantity',qty,'reason',p_row->>'opening_reason',
    'lot_code',p_row->>'lot_code','expires_on',p_row->>'expires_on'));
  end if;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return pid;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;

alter table public.erp_policies
 add column stock_adjustment_value_limit numeric check(stock_adjustment_value_limit>=0 and stock_adjustment_value_limit::text not in ('NaN','Infinity','-Infinity')),
 add column stock_adjustment_approval_kinds text[] not null default '{}',
 add column allow_self_approval_exception boolean not null default false,
 add column picking_scan_mode text not null default 'confirm' check(picking_scan_mode in ('unit','pack','confirm')),
 add column picking_location_required boolean not null default false,
 add column product_readiness_required boolean not null default false;
alter table public.products
 add column replenishment_excluded boolean not null default false,
 add column replenishment_exclusion_reason text,
 add constraint replenishment_exclusion_explained check(not replenishment_excluded or length(btrim(coalesce(replenishment_exclusion_reason,'')))>=3);
alter table public.stock_adjustment_requests add column approval_value numeric,add column approval_value_limit numeric;

create function private.erp_independent_approval(requester uuid,data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if requester=auth.uid() and not (coalesce((select allow_self_approval_exception from public.erp_policies where id),false)
  and coalesce((data->>'self_approval_exception')::boolean,false) and length(btrim(coalesce(data->>'reason','')))>=20) then
 raise exception 'INDEPENDENT_APPROVER_REQUIRED';end if;
end $$;
revoke all on function private.erp_independent_approval(uuid,jsonb) from public,anon,authenticated;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_approval_action(text,jsonb)'::regprocedure);
 s:=replace(s,'if a.fingerprint<>','perform private.erp_independent_approval(a.requested_by,p_data); if a.fingerprint<>');execute s;
 s:=pg_get_functiondef('private.gama_adjustment_request(text,jsonb)'::regprocedure);
 s:=replace(s,'if p_data ? ''kind'' and (lim is null or abs(delta)<=lim) then',
 $p$update public.stock_adjustment_requests set approval_value=abs(delta)*coalesce(p.purchase_price,0),approval_value_limit=(select stock_adjustment_value_limit from public.erp_policies where id) where id=a.id returning * into a;
  if p_data ? 'kind' and (lim is null or abs(delta)<=lim)
   and (a.approval_value_limit is null or (coalesce(p.purchase_price,0)>0 and a.approval_value<=a.approval_value_limit))
   and not (k=any((select stock_adjustment_approval_kinds from public.erp_policies where id)::text[])) then$p$);
 s:=replace(s,'if p_action=''approve'' then','if p_action=''approve'' then perform private.erp_independent_approval(a.requested_by,p_data);');execute s;
end $$;

create function private.erp_product_readiness(pid uuid) returns text[] language sql stable security definer set search_path='' as $$
 select array_remove(array[
 case when nullif(btrim(p.reference),'') is null then 'reference' end,
 case when nullif(btrim(p.base_unit),'') is null then 'unit' end,
 case when coalesce(p.sale_price,0)<=0 then 'sale_price' end,
 case when p.product_kind='goods' and coalesce(p.purchase_price,0)<=0 then 'purchase_price' end,
 case when p.product_kind='goods' and not p.replenishment_excluded and p.supplier_id is null
  and not exists(select 1 from public.supplier_product_offers s where s.product_id=p.id and s.active)
  and not exists(select 1 from public.commercial_matrix s where s.product_id=p.id and s.active and s.supplier_id is not null) then 'supplier' end,
 case when p.product_kind='goods' and not p.replenishment_excluded and not(p.min_stock>0 and p.max_stock>=p.min_stock)
  and not exists(select 1 from public.reorder_rules r where r.product_id=p.id and r.active) then 'replenishment' end
 ],null) from public.products p where p.id=pid;
$$;
create function private.erp_product_activation() returns trigger language plpgsql security definer set search_path='' as $$
declare missing text[];
begin
 if new.active and (tg_op='INSERT' or not old.active) and coalesce((select product_readiness_required from public.erp_policies where id),false) then
 missing:=private.erp_product_readiness(new.id);if cardinality(missing)>0 then raise exception 'PRODUCT_NOT_READY: %',array_to_string(missing,', ');end if;
 end if;return null;
end $$;
create trigger product_activation_check after insert or update of active on public.products for each row execute function private.erp_product_activation();
create function private.gama_integrity(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;c public.stock_integrity_cases;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('products',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='resolve' then
  select * into c from public.stock_integrity_cases where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'CASE_NOT_FOUND';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<10 then raise exception 'REASON_REQUIRED';end if;
  perform 1 from public.products where id=c.product_id for update;
  if (select stock from public.products where id=c.product_id) is distinct from coalesce((select sum(quantity) from public.stock_quants where product_id=c.product_id),0) then raise exception 'STOCK_STILL_INCONSISTENT';end if;
  update public.stock_integrity_cases set resolved_at=now(),resolved_by=auth.uid(),resolution=p_data->>'reason' where id=c.id and resolved_at is null;
  return jsonb_build_object('resolved',true);
 elsif p_action='products' then
  with items as (
   select p.id,p.name,p.reference,p.base_unit,p.active,p.replenishment_excluded,p.replenishment_exclusion_reason,p.lot_tracking,
    p.stock catalogue_quantity,coalesce(q.quantity,0) located_quantity,private.erp_product_readiness(p.id) missing,
    (select jsonb_agg(ic) from public.stock_integrity_cases ic where ic.product_id=p.id and ic.resolved_at is null) cases
   from public.products p left join (select product_id,sum(quantity) quantity from public.stock_quants group by product_id) q on q.product_id=p.id
   where p.active and (nullif(p_data->>'search','') is null or concat_ws(' ',p.name,p.reference,p.barcode) ilike '%'||(p_data->>'search')||'%')
  ), filtered as(select * from items where not coalesce((p_data->>'issues_only')::boolean,true) or cardinality(missing)>0 or cases is not null or catalogue_quantity<>located_quantity)
  select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce((select jsonb_agg(r) from
   (select * from filtered order by cases is not null desc,name,id limit 25 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))r),'[]')) into result;
  return result;
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_integrity(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_integrity(p_action,p_data)$$;
revoke all on function private.erp_product_readiness(uuid),private.erp_product_activation() from public,anon,authenticated;
revoke all on function private.gama_integrity(text,jsonb),public.gama_integrity(text,jsonb) from public,anon;
grant execute on function private.gama_integrity(text,jsonb),public.gama_integrity(text,jsonb) to authenticated;

-- A product identity scan is no longer an implicit whole-line quantity confirmation.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure);
 s:=replace(s,'''preparations'',coalesce', '''scan_policy'',(select jsonb_build_object(''mode'',picking_scan_mode,''location_required'',picking_location_required) from public.erp_policies where id),''preparations'',coalesce');
 anchor:='if qty is null or pl.picked+qty>pl.planned then';
 if strpos(s,anchor)=0 then raise exception 'PICK_CONTROL_ANCHOR_MISSING';end if;
 s:=replace(s,'and btrim(p_data->>''product_code'')<>btrim(coalesce(pr.barcode,''''))','and btrim(p_data->>''product_code'')<>btrim(coalesce(pr.barcode,'''')) and btrim(p_data->>''product_code'')<>btrim(coalesce(pr.reference,''''))');
 s:=replace(s,anchor,$p$
  if coalesce((select picking_location_required from public.erp_policies where id),false) and btrim(coalesce(p_data->>'scanned_location',''))<>loc.code then raise exception 'LOCATION_SCAN_REQUIRED';end if;
  if p_data->>'scan_mode'='confirm' then
   if not coalesce((p_data->>'quantity_confirmed')::boolean,false) then raise exception 'QUANTITY_CONFIRMATION_REQUIRED';end if;
  elsif p_data->>'scan_mode'='unit' then
   if nullif(btrim(p_data->>'product_code'),'') is null or qty<>1
    or exists(select 1 from public.product_units where product_id=pr.id and active and barcode=p_data->>'product_code' and factor<>1) then raise exception 'UNIT_SCAN_QUANTITY_REQUIRED';end if;
  elsif p_data->>'scan_mode'='pack' then
   if not exists(select 1 from public.product_units where product_id=pr.id and active and barcode=p_data->>'product_code' and factor=qty) then raise exception 'PACK_SCAN_QUANTITY_REQUIRED';end if;
  else raise exception 'SCAN_MODE_REQUIRED';end if;
 $p$||anchor);
 execute s;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927150402','audit_stock_integrity','23bd2dfe8c69a77b064532f75385d156ea5dfaa51dbc22761dc78f1611a0e76d','23bd2dfe8c69a77b064532f75385d156ea5dfaa51dbc22761dc78f1611a0e76d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927150859_audit_process_state.sql; SHA256 7b9758311a76dbcb7242fe3de4faffb96e18144c77e05ba7ac3038a3b2b2e858
-- Net balances must include credit notes in every consumer, without calling them cash receipts.
do $$declare s text;credit text;begin
 s:=pg_get_viewdef('private.gama_receivables'::regclass,true);
 credit:='COALESCE((select sum(k.amount) from public.return_credits k where k.invoice_id=i.id),0)';
 s:=replace(s,'i.total - COALESCE(p.paid, 0::numeric)','i.total - COALESCE(p.paid, 0::numeric) - '||credit);
 s:=replace(s,'i.total <= COALESCE(p.paid, 0::numeric)','i.total <= COALESCE(p.paid, 0::numeric) + '||credit);
 execute 'create or replace view private.gama_receivables as '||s;
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);
 -- The payables view already subtracts supplier credits in recent versions; only change missing implementations.
 if strpos(s,'return_credits')=0 then
  credit:='COALESCE((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=si.id),0)';
  s:=replace(s,'i.total - COALESCE(p.paid, 0::numeric)','i.total - COALESCE(p.paid, 0::numeric) - '||credit);
  s:=replace(s,'i.total <= COALESCE(p.paid, 0::numeric)','i.total <= COALESCE(p.paid, 0::numeric) + '||credit);
  execute 'create or replace view private.gama_payables as '||s;
 end if;
end $$;
create index if not exists process_sales_page on public.sales_orders(created_at desc,id);
create index if not exists process_purchase_page on public.purchase_orders(created_at desc,id);
create index if not exists process_followup_deadline on public.dossier_followups(due_date) where closed_at is null;
create index if not exists process_credit_invoice on public.return_credits(invoice_id);
create index if not exists process_credit_supplier_invoice on public.return_credits(supplier_invoice_id);

-- One read model supplies cards, details, closure checks and process alerts.
create function private.gama_process_state(k text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 source uuid:=split_part(k,':',2)::uuid;kind text:=split_part(k,':',1);o public.sales_orders;po public.purchase_orders;q public.invoices;r public.customer_requests;
 totalqty numeric:=0;performed numeric:=0;sent numeric:=0;missing numeric:=0;received numeric:=0;unbilled numeric:=0;balance numeric:=0;overdue numeric:=0;credits numeric:=0;paid numeric:=0;goods numeric:=0;stocked numeric:=0;
 returns_count bigint:=0;external_pending bigint:=0;invoice_count bigint:=0;fin boolean;cancelled boolean:=false;confirmed boolean:=false;complete boolean:=false;
 states text[];titles text[];steps jsonb;checks jsonb;f public.dossier_followups;fp text;closed boolean;late_receipt boolean:=false;info text[];
begin
 if kind='o' then
  select * into o from public.sales_orders where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  select * into q from public.invoices where id=o.source_quote_id;
  select * into r from public.customer_requests where id=o.source_request_id;
  fin:=private.erp_module_allowed('payments',array['administrador','comercial']);cancelled:=o.status='cancelled';confirmed:=o.status='confirmed';
  select coalesce(sum(l.quantity),0),coalesce(sum(least(l.quantity,private.gama_line_performed(l.id,true))),0),coalesce(sum(least(l.quantity,private.gama_line_performed(l.id,false))),0),
   coalesce(sum(case when l.product_kind='goods' then greatest(0,l.quantity-private.gama_line_performed(l.id,false)-coalesce((select sum(s.quantity) from public.stock_reservations s join public.sales_reservation_links x on x.reservation_id=s.id where x.line_id=l.id and s.status='active'),0)) else 0 end),0),
   coalesce(sum(greatest(0,l.quantity-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('rejected','cancelled') and (i.document_kind='internal' or i.fiscal_status='authorized')),0))),0)
   into totalqty,performed,sent,missing,unbilled from public.sales_order_lines l where l.order_id=source;
  select coalesce(sum(a.balance),0),coalesce(sum(a.balance) filter(where a.due_date<(now() at time zone private.erp_timezone())::date),0),coalesce(sum(a.paid),0),count(*)
   into balance,overdue,paid,invoice_count from private.gama_receivables a where a.order_id=source and a.payment_status<>'cancelled';
  select coalesce(sum(c.amount),0) into credits from public.return_credits c join public.external_invoices i on i.id=c.invoice_id where i.order_id=source and i.fiscal_status not in ('cancelled','rejected');
  select count(*) into returns_count from public.return_orders where order_id=source and status not in ('closed','cancelled');
  select count(*) into external_pending from public.external_invoices where order_id=source and fiscal_status not in ('cancelled','rejected') and
   (case when document_kind='internal' then external_number is null or external_status is distinct from 'authorized' else fiscal_status<>'authorized' end);
  titles:=array['Origen de la demanda','Presupuesto','Pedido','Reserva de stock y preparación','Expedición y recepción','Facturación','Seguimiento del pago','Cierre del proceso de venta'];
  complete:=confirmed and totalqty>0 and performed>=totalqty and unbilled=0 and invoice_count>0 and balance<=0.005 and returns_count=0;
  states:=array[case when r.id is not null or o.source_opportunity_id is not null then 'done' else 'skip' end,case when q.id is null then 'skip' when confirmed or q.quote_state in ('accepted','converted') then 'done' else 'active' end,
   case when confirmed then 'done' else 'active' end,case when not confirmed then 'pending' when missing>0 then 'blocked' when sent>=totalqty and totalqty>0 then 'done' else 'active' end,
   case when totalqty>0 and performed>=totalqty then 'done' when sent>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when unbilled=0 and invoice_count>0 then 'done' when invoice_count>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when overdue>0.005 then 'blocked' when unbilled=0 and invoice_count>0 and balance<=0.005 then 'done' when invoice_count>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when returns_count>0 then 'blocked' when complete then 'done' else 'pending' end];
  info:=array['','','','Sin reservar: '||missing,'Entregas firmadas / servicios ejecutados: '||performed||' / '||totalqty,'Cantidad sin facturar: '||unbilled,'Cobros: '||paid||' · Abonos: '||credits||' · Saldo: '||balance,'Devoluciones abiertas: '||returns_count];
 elsif kind='p' then
  select * into po from public.purchase_orders where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  fin:=private.erp_module_allowed('accounting',array['administrador','comercial']) and coalesce((private.gama_accounting_rights()->>'view')::boolean,false) and private.gama_accounting_rights()->>'scope'='all';cancelled:=po.status='cancelled';confirmed:=po.status in ('sent','partial','received');
  select coalesce(sum(l.quantity),0),coalesce(sum(l.received_quantity),0),coalesce(sum(l.received_quantity) filter(where p.product_kind='goods'),0),
   coalesce(sum(greatest(0,l.received_quantity-coalesce((select sum(ml.quantity) from public.supplier_invoice_match_lines ml join public.supplier_invoice_matches m on m.id=ml.match_id join public.supplier_invoices i on i.id=m.invoice_id where ml.purchase_line_id=l.id and i.status='posted' and m.approved_at is not null),0))),0)
   into totalqty,received,goods,unbilled from public.purchase_order_lines l join public.products p on p.id=l.product_id where l.purchase_order_id=source;
  select coalesce(sum(m.quantity),0) into stocked from public.stock_movements m where reference_type='purchase_order' and reference_id=source and m.destination_location_id is not null and m.source_location_id is null;
  select coalesce(sum(greatest(0,i.total-coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.supplier_invoice_id=i.id and p.status='confirmed'),0)-coalesce((select sum(c.amount) from public.return_credits c where c.supplier_invoice_id=i.id),0))),0),count(*)
   into balance,invoice_count from public.supplier_invoices i where i.status='posted' and (i.purchase_order_id=source or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=source));
  select coalesce(sum(greatest(0,i.total-coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.supplier_invoice_id=i.id and p.status='confirmed'),0)-coalesce((select sum(c.amount) from public.return_credits c where c.supplier_invoice_id=i.id),0))),0)
   into overdue from public.supplier_invoices i where i.status='posted' and i.due_date<(now() at time zone private.erp_timezone())::date and (i.purchase_order_id=source or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=source));
  select count(*) into returns_count from public.return_orders where purchase_order_id=source and status not in ('closed','cancelled');
  late_receipt:=po.expected_date<now() and received<totalqty and confirmed;
  performed:=received;complete:=confirmed and totalqty>0 and received>=totalqty and stocked>=goods and unbilled=0 and invoice_count>0 and balance<=0.005 and returns_count=0;
  titles:=array['Origen de la demanda','Pedido de compra','Recepción y control','Puesta en stock','Factura del proveedor','Seguimiento del pago','Cierre del proceso de compra'];
  states:=array['done',case when confirmed then 'done' else 'active' end,
   case when totalqty>0 and received>=totalqty then 'done' when late_receipt then 'blocked' when received>0 then 'active' else 'pending' end,
   case when goods=0 and received>0 then 'skip' when stocked>=goods and goods>0 then 'done' else 'pending' end,
   case when not fin then 'restricted' when unbilled=0 and invoice_count>0 and received>=totalqty then 'done' when unbilled>0 then 'blocked' else 'pending' end,
   case when not fin then 'restricted' when overdue>0.005 then 'blocked' when invoice_count>0 and balance<=0.005 then 'done' when invoice_count>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when returns_count>0 then 'blocked' when complete then 'done' else 'pending' end];
  info:=array['','','Recibido / aceptado: '||received||' / '||totalqty,'Mercancía ubicada: '||stocked||' / '||goods,'Recepción sin factura conciliada: '||unbilled,'Saldo neto de abonos: '||balance,'Devoluciones abiertas: '||returns_count];
 elsif kind in ('q','r') then
  if kind='q' then select * into q from public.invoices where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  else select * into r from public.customer_requests where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;select * into q from public.invoices where id=r.invoice_id;end if;
  fin:=false;cancelled:=coalesce(q.quote_state in ('cancelled','rejected'),false) or coalesce(r.status in ('cancelled','rejected'),false);
  titles:=array['Origen de la demanda','Presupuesto','Pedido','Reserva de stock y preparación','Expedición y recepción','Facturación','Seguimiento del pago','Cierre del proceso de venta'];
  states:=array[case when r.id is null then 'skip' else 'done' end,case when q.id is null then 'pending' when q.quote_state in ('accepted','converted') then 'done' when q.quote_state='sent' and q.quote_valid_until<(now() at time zone private.erp_timezone())::date then 'blocked' else 'active' end,'pending','pending','pending','pending','pending','pending'];
 else raise exception 'DOSSIER_NOT_FOUND';end if;
 checks:=jsonb_build_object('delivery_remainder',greatest(0,totalqty-performed),'unbilled_quantity',unbilled,'unpaid_amount',balance,'open_returns',returns_count,'empty_order',totalqty=0,'order_confirmed',confirmed,'stock_not_located',greatest(0,goods-stocked),'order_required',kind in ('q','r'));
 fp:=md5(checks::text||cancelled::text);select * into f from public.dossier_followups where dossier_key=k;
 closed:=coalesce(f.closed_at is not null and f.closure_fingerprint=fp,false);
 select jsonb_agg(jsonb_build_object('title',titles[i],'state',case when cancelled then 'closed' else states[i] end,'info',case when states[i]='restricted' then '' else coalesce(info[i],'') end) order by i) into steps from generate_subscripts(titles,1) i;
 if not fin then checks:=checks-'unbilled_quantity'-'unpaid_amount';complete:=false;end if;
 return jsonb_build_object('key',k,'metrics',jsonb_build_object('ordered',totalqty,'performed',performed,'shipped',sent,'missing',missing,'received',received,'goods',goods,'stocked',stocked,'unbilled',case when fin then unbilled else null end,'balance',case when fin then balance else null end,'paid',case when fin then paid else null end,'credits',case when fin then credits else null end,'open_returns',returns_count),'steps',steps,'checks',checks,'fingerprint',fp,'followup',case when f.id is null then null else to_jsonb(f) end,'operational_complete',complete,'external_complete',case when fin and kind='o' then external_pending=0 and invoice_count>0 else null end,'external_pending',case when fin then external_pending else null end,'closed',closed,'cancelled',cancelled,'reopened',coalesce(f.closed_at is not null and not closed,false),'unbilled_received',case when fin and kind='p' then unbilled else null end,'financial_access',fin);
end $$;
revoke all on function private.gama_process_state(text) from public,anon,authenticated;

create or replace function private.gama_dossier_followup(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'key';r jsonb;source uuid;kind text;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('dossier-flow',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 kind:=split_part(k,':',1);source:=split_part(k,':',2)::uuid;
 if kind='p' then
  if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  perform 1 from public.purchase_orders where id=source for update;
 elsif kind='o' then perform 1 from public.sales_orders where id=source for update;end if;
 r:=private.gama_process_state(k);
 if p_action='save' then
  if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
  insert into public.dossier_followups(dossier_key,owner_id,next_action,due_date) values(k,(p_data->>'owner_id')::uuid,p_data->>'next_action',(p_data->>'due_date')::date)
   on conflict(dossier_key) do update set owner_id=excluded.owner_id,next_action=excluded.next_action,due_date=excluded.due_date,updated_by=auth.uid(),updated_at=now();
 elsif p_action='close' then
  if r->'followup'='null'::jsonb then raise exception 'FOLLOWUP_REQUIRED';end if;
  if not coalesce((r->>'operational_complete')::boolean,false) then raise exception 'DOSSIER_INCOMPLETE';end if;
  if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'CLOSURE_NOTE_REQUIRED';end if;
  update public.dossier_followups set closed_at=now(),closed_by=auth.uid(),closure_note=p_data->>'note',closure_fingerprint=r->>'fingerprint' where dossier_key=k;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return private.gama_process_state(k)-'fingerprint';
end $$;

create function private.gama_processes(p_action text,p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;k text:=p_data->>'key';purchase boolean:=p_data->>'kind'='PDC';off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));search text:=btrim(coalesce(p_data->>'search',''));
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('dossier-flow',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if (purchase or k like 'p:%') and not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='state' then return private.gama_process_state(k)-'fingerprint';end if;
 if p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 with candidates as (
  select 'p:'||p.id key,p.created_at,(to_jsonb(p)||jsonb_build_object('dossier_number',dr.dossier_number)) o,null::jsonb q,null::jsonb r,s.name party,'PDC-'||lpad(dr.dossier_number::text,8,'0') number
   from public.purchase_orders p left join public.gama_document_references dr on dr.table_name='purchase_orders' and dr.document_id=p.id left join public.suppliers s on s.id=p.supplier_id where purchase
  union all
  select 'o:'||o.id,o.created_at,to_jsonb(o)||jsonb_build_object('dossier_number',dr.dossier_number),case when private.erp_module_allowed('quotes',array['administrador','comercial']) then to_jsonb(q)-'accepted_snapshot' end,case when private.erp_module_allowed('customer-requests',array['administrador','comercial']) then to_jsonb(r) end,o.customer_name,'PDV-'||lpad(dr.dossier_number::text,8,'0') from public.sales_orders o left join public.gama_document_references dr on dr.table_name='sales_orders' and dr.document_id=o.id
   left join public.customer_requests r on r.id=o.source_request_id left join public.invoices q on q.id=coalesce(o.source_quote_id,r.invoice_id) where not purchase
  union all
  select 'q:'||q.id,q.created_at,null,(to_jsonb(q)-'accepted_snapshot')||jsonb_build_object('dossier_number',dr.dossier_number),to_jsonb(r),q.quote_details->>'client','PDV-'||lpad(dr.dossier_number::text,8,'0') from public.invoices q left join public.gama_document_references dr on dr.table_name='invoices' and dr.document_id=q.id
   left join public.customer_requests r on r.invoice_id=q.id where not purchase and private.erp_module_allowed('quotes',array['administrador','comercial']) and not exists(select 1 from public.sales_orders o where o.source_quote_id=q.id or o.source_request_id=r.id)
  union all
  select 'r:'||r.id,r.created_at,null,null,to_jsonb(r)||jsonb_build_object('dossier_number',dr.dossier_number),r.requester_name,'PDV-'||lpad(dr.dossier_number::text,8,'0') from public.customer_requests r left join public.gama_document_references dr on dr.table_name='customer_requests' and dr.document_id=r.id where not purchase and private.erp_module_allowed('customer-requests',array['administrador','comercial']) and r.invoice_id is null and not exists(select 1 from public.sales_orders o where o.source_request_id=r.id)
 ), filtered as (select * from candidates where (k is null or candidates.key=k) and (search='' or concat_ws(' ',number,party,o->>'number',o->>'order_number',q->>'invoice_number') ilike '%'||search||'%')), page as(select * from filtered order by created_at desc,key limit 25 offset off)
 select jsonb_build_object('total',(select count(*) from filtered),'offset',off,'items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('state',private.gama_process_state(p.key)-'fingerprint')) from page p),'[]')) into result;
 return result;
end $$;
create function public.gama_processes(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_processes(p_action,p_data)$$;
revoke all on function private.gama_processes(text,jsonb),public.gama_processes(text,jsonb) from public,anon;
grant execute on function private.gama_processes(text,jsonb),public.gama_processes(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927150859','audit_process_state','7b9758311a76dbcb7242fe3de4faffb96e18144c77e05ba7ac3038a3b2b2e858','7b9758311a76dbcb7242fe3de4faffb96e18144c77e05ba7ac3038a3b2b2e858','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927151658_audit_stock_valuation.sql; SHA256 ec3a403d0c9384d242f35a1694d6e07b5666c29050346b5c4a8c240bcf89cb32
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927151658','audit_stock_valuation','ec3a403d0c9384d242f35a1694d6e07b5666c29050346b5c4a8c240bcf89cb32','ec3a403d0c9384d242f35a1694d6e07b5666c29050346b5c4a8c240bcf89cb32','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927152533_audit_monitoring.sql; SHA256 63498a9cbd1b3cb07bd2448ff3e8c0c7d400ac10e140af4a7d5a50db69e82368
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927152533','audit_monitoring','63498a9cbd1b3cb07bd2448ff3e8c0c7d400ac10e140af4a7d5a50db69e82368','63498a9cbd1b3cb07bd2448ff3e8c0c7d400ac10e140af4a7d5a50db69e82368','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
