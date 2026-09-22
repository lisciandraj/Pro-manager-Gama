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
