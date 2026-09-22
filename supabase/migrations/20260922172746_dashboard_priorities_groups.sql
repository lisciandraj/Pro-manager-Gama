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
