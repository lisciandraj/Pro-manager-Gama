-- Live exceptions are derived from business records; handling never resolves their cause.
create table private.gama_alert_handling (
 alert_key text primary key, fingerprint text not null, status text not null check(status in ('open','in_progress','snoozed')),
 assigned_to uuid references auth.users(id), snoozed_until timestamptz, note text not null default '' check(length(note)<=1000),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create table private.gama_alert_events (
 id bigint generated always as identity primary key,alert_key text not null,fingerprint text not null,
 action text not null,note text not null,actor uuid not null references auth.users(id),created_at timestamptz not null default now()
);
alter table private.gama_alert_handling enable row level security;
alter table private.gama_alert_events enable row level security;
create policy no_direct_access on private.gama_alert_handling for all to authenticated using(false) with check(false);
create policy no_direct_access on private.gama_alert_events for all to authenticated using(false) with check(false);
revoke all on private.gama_alert_handling,private.gama_alert_events from public,anon,authenticated;

create view private.gama_order_progress with (security_invoker=true) as
with shipped as (select order_line_id,sum(quantity) qty from public.sales_delivery_lines group by order_line_id),
reserved as (select l.line_id,sum(r.quantity) qty from public.sales_reservation_links l join public.stock_reservations r on r.id=l.reservation_id and r.status='active' group by l.line_id),
billed as (select l.order_line_id,sum(l.quantity) qty from public.external_invoice_lines l join public.external_invoices i on i.id=l.invoice_id and i.fiscal_status not in ('cancelled','rejected') group by l.order_line_id)
select o.id,o.number,o.customer_name,o.created_at,o.status,
 coalesce(sum(l.quantity*l.unit_price*(1+l.tax_rate/100)),0) amount,
 coalesce(sum(greatest(0,l.quantity-coalesce(s.qty,0))),0) remaining,
 coalesce(sum(coalesce(s.qty,0)),0) shipped,
 coalesce(sum(greatest(0,l.quantity-coalesce(s.qty,0)-coalesce(r.qty,0))),0) missing,
 coalesce(sum(greatest(0,l.quantity-coalesce(b.qty,0))*l.unit_price*(1+l.tax_rate/100)),0) unbilled,
 coalesce(sum(greatest(0,least(l.quantity,coalesce(s.qty,0))-coalesce(b.qty,0))*l.unit_price*(1+l.tax_rate/100)),0) shipped_unbilled
from public.sales_orders o left join public.sales_order_lines l on l.order_id=o.id
left join shipped s on s.order_line_id=l.id left join reserved r on r.line_id=l.id left join billed b on b.order_line_id=l.id
group by o.id;

create view private.gama_live_alerts with (security_invoker=true) as
select 'quote:'||q.id alert_key,'quote' kind,q.id target_id,'quote' target,
 coalesce(q.invoice_number,'Presupuesto') reference,coalesce(q.quote_details->>'client','Cliente') customer,
 'Presupuesto sin respuesta' title,'Enviado: '||coalesce(q.quote_sent_at::text,'-')||' · revisión '||q.quote_revision detail,
 q.quote_sent_at since,case when q.quote_valid_until<(now() at time zone 'America/Guayaquil')::date then 2 else 1 end priority,
 true finance_only,false warehouse_only
from public.invoices q where q.quote_state='sent'
union all
select 'shortage:'||o.id,'shortage',o.id,'order',o.number,o.customer_name,'Pedido bloqueado por stock',o.missing||' unidades sin reservar',o.created_at,2,false,false
from private.gama_order_progress o where o.status='confirmed' and o.missing>0
union all
select 'backorder:'||o.id,'backorder',o.id,'order',o.number,o.customer_name,'Reliquat pendiente',o.remaining||' unidades pendientes de expedición',o.created_at,1,false,false
from private.gama_order_progress o where o.status='confirmed' and o.remaining>0 and o.shipped>0
union all
select 'receipt:'||p.id,'receipt',p.id,'purchase',p.order_number,coalesce(s.name,'Proveedor'),'Recepción atrasada',
 'Prevista: '||(p.expected_date at time zone 'America/Guayaquil')::date||' · '||sum(greatest(0,l.quantity-l.received_quantity))||' unidades pendientes',p.expected_date,2,false,false
from public.purchase_orders p join public.purchase_order_lines l on l.purchase_order_id=p.id left join public.suppliers s on s.id=p.supplier_id
where p.status in ('sent','partial') and (p.expected_date at time zone 'America/Guayaquil')::date<(now() at time zone 'America/Guayaquil')::date
group by p.id,s.name having sum(greatest(0,l.quantity-l.received_quantity))>0
union all
select 'delivery:'||d.id,case when d.status='Excepción' then 'failed_delivery' else 'late_delivery' end,d.id,'delivery',coalesce(s.number,'TMS-'||left(d.id::text,8)),d.customer,
 case when d.status='Excepción' then 'Entrega fallida' else 'Entrega atrasada' end,
 d.status||' · prevista: '||coalesce(d.delivery_date::text,'-'),coalesce(d.delivery_date::timestamptz,d.created_at),3,false,s.id is null
from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id
where d.status='Excepción' or (d.delivery_date<(now() at time zone 'America/Guayaquil')::date and d.status not in ('Entregada','Cancelada'))
union all
select 'count:'||c.id,'stock_variance',c.id,'count',c.reference,'Almacén','Diferencias de inventario',
 count(*)||' líneas con diferencia · '||sum(abs(l.counted_quantity-l.expected_quantity))||' unidades (valor absoluto)',c.created_at,2,false,true
from public.inventory_counts c join public.inventory_count_lines l on l.count_id=c.id
where c.status not in ('validated','cancelled') and l.counted_quantity is not null and l.counted_quantity<>l.expected_quantity
group by c.id
union all
select 'billing:'||o.id,'unbilled',o.id,'order',o.number,o.customer_name,'Pendiente de facturar',
 round(o.unbilled,2)||' USD por vincular · expedido sin factura: '||round(o.shipped_unbilled,2)||' USD',o.created_at,1,true,false
from private.gama_order_progress o where o.status='confirmed' and o.unbilled>0;
revoke all on private.gama_order_progress,private.gama_live_alerts from public,anon,authenticated;

create function private.gama_operations_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();r text:=coalesce(private.current_user_role(),'');fin boolean;wh boolean;
 first_day date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',now() at time zone 'America/Guayaquil')::date);
 last_day date:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone 'America/Guayaquil')::date);
 a record;finger text;newstate text;metrics jsonb;result jsonb;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if r not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 fin:=r in ('administrador','comercial');wh:=r in ('administrador','almacenero');
 if first_day>last_day then raise exception 'INVALID_PERIOD';end if;
 if p_action='handle' then
  select * into a from private.gama_live_alerts x where x.alert_key=p_data->>'key' and (not x.finance_only or fin) and (not x.warehouse_only or wh);
  if not found then raise exception 'ALERT_RESOLVED';end if;
  finger:=md5(a.kind||coalesce(a.detail,'')||coalesce(a.since::text,''));
  if finger is distinct from p_data->>'fingerprint' then raise exception 'ALERT_CHANGED';end if;
  newstate:=p_data->>'status';
  if newstate not in ('open','in_progress','snoozed') or newstate is null then raise exception 'INVALID_STATUS';end if;
  if length(coalesce(p_data->>'note',''))>1000 then raise exception 'NOTE_TOO_LONG';end if;
  insert into private.gama_alert_handling(alert_key,fingerprint,status,assigned_to,snoozed_until,note,updated_by)
  values(a.alert_key,finger,newstate,case when newstate='open' then null else u end,case when newstate='snoozed' then now()+interval '1 day' end,coalesce(p_data->>'note',''),u)
  on conflict(alert_key) do update set fingerprint=excluded.fingerprint,status=excluded.status,assigned_to=excluded.assigned_to,snoozed_until=excluded.snoozed_until,note=excluded.note,updated_by=u,updated_at=now();
  insert into private.gama_alert_events(alert_key,fingerprint,action,note,actor) values(a.alert_key,finger,newstate,coalesce(p_data->>'note',''),u);
  return jsonb_build_object('success',true);
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 select jsonb_build_object(
 'orders',(select count(*) from public.sales_orders where status='confirmed' and (created_at at time zone 'America/Guayaquil')::date between first_day and last_day),
 'order_amount',case when fin then (select coalesce(sum(amount),0) from private.gama_order_progress where status='confirmed' and (created_at at time zone 'America/Guayaquil')::date between first_day and last_day) end,
 'dispatches',(select count(*) from public.sales_deliveries where (dispatched_at at time zone 'America/Guayaquil')::date between first_day and last_day),
 'delivered',(select count(*) from public.tms_deliveries where status='Entregada' and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day),
 'invoices',case when fin then (select count(*) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between first_day and last_day) end,
 'invoiced',case when fin then (select coalesce(sum(total),0) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between first_day and last_day) end,
 'collected',case when fin then (select coalesce(sum(p.amount),0) from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where p.status='confirmed' and i.fiscal_status not in ('cancelled','rejected') and p.paid_at between first_day and last_day) end,
 'receivable',case when fin then (select coalesce(sum(greatest(0,i.total-coalesce(p.paid,0))),0) from public.external_invoices i left join (select invoice_id,sum(amount) paid from public.external_invoice_payments where status='confirmed' group by invoice_id) p on p.invoice_id=i.id where i.fiscal_status not in ('cancelled','rejected')) end,
 'unbilled',case when fin then (select coalesce(sum(unbilled),0) from private.gama_order_progress where status='confirmed') end,
 'shipped_unbilled',case when fin then (select coalesce(sum(shipped_unbilled),0) from private.gama_order_progress where status='confirmed') end,
 'blocked',(select count(*) from private.gama_order_progress where status='confirmed' and missing>0),
 'backorders',(select count(*) from private.gama_order_progress where status='confirmed' and remaining>0 and shipped>0),
 'late_deliveries',(select count(*) from public.tms_deliveries where delivery_date<(now() at time zone 'America/Guayaquil')::date and status not in ('Entregada','Cancelada')),
 'stock_variances',case when wh then (select count(*) from private.gama_live_alerts where kind='stock_variance') end
 ) into metrics;
 with live as (
  select x.*,md5(x.kind||coalesce(x.detail,'')||coalesce(x.since::text,'')) fingerprint from private.gama_live_alerts x where (not x.finance_only or fin) and (not x.warehouse_only or wh)
 ), handled as (
  select l.*,case when h.status='snoozed' and h.snoozed_until<=now() then 'open' else coalesce(h.status,'open') end handling,
  h.snoozed_until,h.note,p.full_name assigned_name,h.assigned_to
  from live l left join private.gama_alert_handling h on h.alert_key=l.alert_key and h.fingerprint=l.fingerprint left join public.profiles p on p.id=h.assigned_to
 ), filtered as (
  select * from handled where (coalesce(p_data->>'kind','all')='all' or kind=p_data->>'kind' or (p_data->>'kind'='late_delivery' and kind='failed_delivery' and (since at time zone 'America/Guayaquil')::date<(now() at time zone 'America/Guayaquil')::date))
  and (coalesce(p_data->>'state','active')='all' or (p_data->>'state'='mine' and assigned_to=u) or (p_data->>'state'='snoozed' and handling='snoozed') or (coalesce(p_data->>'state','active')='active' and handling<>'snoozed'))
 )
 select jsonb_build_object('metrics',metrics,'finance',fin,'warehouse',wh,'from',first_day,'to',last_day,'generated_at',now(),
 'active_count',(select count(*) from handled where handling<>'snoozed'),
 'counts',(select coalesce(jsonb_object_agg(kind,n),'{}') from (select kind,count(*) n from handled group by kind) g),
 'total',(select count(*) from filtered),
 'alerts',coalesce((select jsonb_agg(to_jsonb(z) order by priority desc,since,alert_key) from (select * from filtered order by priority desc,since,alert_key offset off limit 50) z),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function private.gama_operations_action(text,jsonb) from public,anon;
grant execute on function private.gama_operations_action(text,jsonb) to authenticated;
create function public.gama_operations_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_operations_action(p_action,p_data)$$;
revoke all on function public.gama_operations_action(text,jsonb) from public,anon;
grant execute on function public.gama_operations_action(text,jsonb) to authenticated;
