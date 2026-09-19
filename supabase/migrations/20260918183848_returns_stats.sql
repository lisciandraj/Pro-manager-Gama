-- Las cifras del pliego, calculadas donde están los datos. Viven en la propia
-- pantalla de Devoluciones y no en el tablero general: ahí sólo añadirían
-- ruido a quien no lleva las devoluciones.
do $mig$
declare src text:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
begin
 if position('p_action=''stats''' in src)>0 then raise exception 'ALREADY_APPLIED';end if;
 if position(' elsif p_action=''detail'' then' in src)=0 then raise exception 'ANCHOR_DETAIL';end if;
 src:=replace(src,' elsif p_action=''detail'' then',$body$ elsif p_action='stats' then
  return jsonb_build_object(
   'month_count',(select count(*) from public.return_orders o
     where o.status<>'cancelled'
       and (o.created_at at time zone 'America/Guayaquil')::date>=date_trunc('month',today)::date),
   'month_value',(select coalesce(round(sum(private.gama_return_amount(o.id)),2),0) from public.return_orders o
     where o.status<>'cancelled'
       and (o.created_at at time zone 'America/Guayaquil')::date>=date_trunc('month',today)::date),
   -- Tasa de devolución: lo devuelto sobre lo expedido, en unidades y sobre el
   -- mismo periodo, que es la única comparación que significa algo.
   'return_rate',(select case when sold>0 then round(100*returned/sold,2) else 0 end from (
      select coalesce((select sum(l.quantity) from public.return_lines l
               join public.return_orders o on o.id=l.return_id
              where o.kind='customer' and o.status<>'cancelled'
                and (o.created_at at time zone 'America/Guayaquil')::date between d1 and d2),0) returned,
             coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl
               join public.sales_deliveries sd on sd.id=dl.delivery_id
              where (sd.dispatched_at at time zone 'America/Guayaquil')::date between d1 and d2),0) sold) z),
   'reasons',coalesce((select jsonb_agg(to_jsonb(z)) from (
      select o.reason,count(*) n from public.return_orders o
      where o.status<>'cancelled' group by o.reason order by count(*) desc limit 3) z),'[]'::jsonb),
   'products',coalesce((select jsonb_agg(to_jsonb(z)) from (
      select p.name product,sum(l.quantity) quantity from public.return_lines l
      join public.return_orders o on o.id=l.return_id
      join public.products p on p.id=l.product_id
      where o.status<>'cancelled' group by p.name order by sum(l.quantity) desc limit 5) z),'[]'::jsonb),
   'suppliers',coalesce((select jsonb_agg(to_jsonb(z)) from (
      select s.name supplier,count(*) n from public.return_orders o
      join public.suppliers s on s.id=o.supplier_id
      where o.kind='supplier' and o.status<>'cancelled' group by s.name order by count(*) desc limit 5) z),'[]'::jsonb));

 elsif p_action='detail' then$body$);
 execute src;
end $mig$;
