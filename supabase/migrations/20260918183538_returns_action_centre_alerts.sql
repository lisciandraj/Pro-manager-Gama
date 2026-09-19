-- Cinco avisos y ni uno más, los que de verdad piden una acción. Se reparten
-- por quien tiene que actuar: el almacén recibe y expide, finanzas abona y
-- reembolsa. El administrador es las dos cosas, así que los ve todos.
--
-- El centro de acción se lee desde una función SECURITY DEFINER, donde la RLS
-- de estas tablas no se aplica: el filtro por rol va explícito en cada rama.
do $mig$
declare def text:=pg_get_viewdef('private.gama_live_alerts'::regclass,true);
begin
 if position('returns_to_process' in def)>0 then raise exception 'ALREADY_APPLIED';end if;
 def:=rtrim(btrim(def),';');
 execute 'create or replace view private.gama_live_alerts with (security_invoker=true) as '||def||$sql$
union all
select 'returns_to_process:'||o.id, 'return_to_process', o.id, 'return', o.number,
 coalesce(c.name,'—'),
 'Devolución de cliente por recibir',
 'Creada el '||(o.created_at at time zone 'America/Guayaquil')::date,
 o.created_at, 3, false, true
from public.return_orders o left join public.customers c on c.id=o.customer_id
where coalesce(private.current_user_role(),'') in ('administrador','comercial','almacenero')
  and o.kind='customer' and o.status='to_process'
union all
select 'returns_received:'||o.id, 'return_received', o.id, 'return', o.number,
 coalesce(c.name,'—'),
 'Devolución recibida sin decidir',
 'Recibida el '||(o.received_at at time zone 'America/Guayaquil')::date,
 o.received_at, 2, false, true
from public.return_orders o left join public.customers c on c.id=o.customer_id
where coalesce(private.current_user_role(),'') in ('administrador','comercial','almacenero')
  and o.kind='customer' and o.status='received'
union all
select 'returns_to_ship:'||o.id, 'return_to_ship', o.id, 'return', o.number,
 coalesce(s.name,'—'),
 'Devolución a proveedor por expedir',
 'Creada el '||(o.created_at at time zone 'America/Guayaquil')::date,
 o.created_at, 1, false, true
from public.return_orders o left join public.suppliers s on s.id=o.supplier_id
where coalesce(private.current_user_role(),'') in ('administrador','comercial','almacenero')
  and o.kind='supplier' and o.status='to_process'
union all
select 'returns_supplier_credit:'||o.id, 'return_supplier_credit', o.id, 'return', o.number,
 coalesce(s.name,'—'),
 'Abono del proveedor pendiente',
 'Expedida el '||coalesce(o.shipped_on::text,'—'),
 coalesce((o.shipped_on::timestamp at time zone 'America/Guayaquil'),o.updated_at), 2, true, false
from public.return_orders o left join public.suppliers s on s.id=o.supplier_id
where coalesce(private.current_user_role(),'') in ('administrador','comercial','almacenero')
  and o.kind='supplier' and o.status='shipped'
  and not exists(select 1 from public.return_credits k where k.return_id=o.id)
union all
select 'returns_refund_due:'||o.id, 'return_refund_due', o.id, 'return', o.number,
 coalesce(c.name,'—'),
 'Reembolso de cliente pendiente',
 'Quedan por reembolsar '||round(private.gama_return_amount(o.id)
   -coalesce((select sum(f.amount) from public.return_refunds f where f.return_id=o.id),0),2),
 o.updated_at, 3, true, false
from public.return_orders o left join public.customers c on c.id=o.customer_id
where coalesce(private.current_user_role(),'') in ('administrador','comercial','almacenero')
  and o.kind='customer' and o.status not in ('cancelled','closed')
  and o.financial_action='refund'
  and coalesce((select sum(f.amount) from public.return_refunds f where f.return_id=o.id),0)
      < private.gama_return_amount(o.id)
$sql$;
end $mig$;
