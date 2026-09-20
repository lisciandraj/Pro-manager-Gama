-- Los cinco permisos del encargo, resueltos sobre los roles que GAMA ya tiene.
-- No se inventa un rol «finanzas»: quien manda en el dinero es el
-- administrador o quien tenga derechos en Contabilidad, que es donde esa
-- decisión ya vivía.
create or replace function private.gama_returns_rights() returns jsonb
language plpgsql stable security definer set search_path='' as $fn$
declare r text:=coalesce(private.current_user_role(),''); fin boolean;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if r not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 fin:=r='administrador' or exists(select 1 from public.accounting_permissions
   where profile_id=auth.uid() and coalesce(can_validate,false));
 return jsonb_build_object(
  'role',r,
  'view',true,
  'create',r in ('administrador','comercial','almacenero'),
  'process',r in ('administrador','almacenero'),
  'refund',fin,
  'delete',r='administrador');
end $fn$;
revoke all on function private.gama_returns_rights() from public,anon;
grant execute on function private.gama_returns_rights() to authenticated;

-- Importe devuelto de una línea, con su impuesto. Un solo sitio para la
-- cuenta: el abono, el reembolso y los indicadores la leen de aquí.
create or replace function private.gama_return_amount(p_return uuid) returns numeric
language sql stable security definer set search_path='' as $fn$
 select coalesce(round(sum(l.quantity*l.unit_price*(1+l.tax_rate/100)),2),0)
 from public.return_lines l where l.return_id=p_return
$fn$;
revoke all on function private.gama_return_amount(uuid) from public,anon;
grant execute on function private.gama_return_amount(uuid) to authenticated;

create or replace function private.gama_returns_action(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 rights jsonb:=private.gama_returns_rights();
 today date:=(now() at time zone 'America/Guayaquil')::date;
 d1 date; d2 date; search text:=btrim(coalesce(p_data->>'search',''));
 kind text:=nullif(p_data->>'kind','');
 r record; j jsonb;
begin
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 d2:=coalesce(nullif(p_data->>'to','')::date,today);
 if d2<d1 then raise exception 'INVALID_PERIOD';end if;

 if p_action='overview' then
  return jsonb_build_object('rights',rights,'today',today,
   'kpis',jsonb_build_object(
    'open',(select count(*) from public.return_orders where status not in ('closed','cancelled')),
    'to_process',(select count(*) from public.return_orders where status='to_process'),
    'financial_pending',(select count(*) from public.return_orders o
      where o.status not in ('cancelled')
        and ((o.financial_action='credit' and not exists(select 1 from public.return_credits c where c.return_id=o.id))
          or (o.financial_action='refund' and coalesce((select sum(amount) from public.return_refunds f where f.return_id=o.id),0)
              < private.gama_return_amount(o.id)))),
    'closed_month',(select count(*) from public.return_orders
      where status='closed' and (closed_at at time zone 'America/Guayaquil')::date
        between date_trunc('month',today)::date and today)),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
     select o.id,o.number,o.kind,o.status,o.reason,o.financial_action,
      (o.created_at at time zone 'America/Guayaquil')::date created_on,o.created_at,
      coalesce(c.name,s.name) partner,
      private.gama_return_amount(o.id) amount,
      (select count(*) from public.return_lines l where l.return_id=o.id) lines,
      (select coalesce(sum(amount),0) from public.return_refunds f where f.return_id=o.id) refunded,
      exists(select 1 from public.return_credits k where k.return_id=o.id) credited
     from public.return_orders o
     left join public.customers c on c.id=o.customer_id
     left join public.suppliers s on s.id=o.supplier_id
     where (kind is null or o.kind=kind)
       and (nullif(p_data->>'status','') is null or o.status=p_data->>'status')
       and (nullif(p_data->>'customer_id','') is null or o.customer_id=(p_data->>'customer_id')::uuid)
       and (nullif(p_data->>'supplier_id','') is null or o.supplier_id=(p_data->>'supplier_id')::uuid)
       and (coalesce((p_data->>'all_dates')::boolean,false)
            or (o.created_at at time zone 'America/Guayaquil')::date between d1 and d2)
       and (search='' or concat_ws(' ',o.number,c.name,s.name,o.notes) ilike '%'||search||'%')
     order by o.created_at desc limit 200) z),'[]'::jsonb),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.customers where active and exists(select 1 from public.return_orders o where o.customer_id=customers.id)),'[]'::jsonb),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.suppliers where active and exists(select 1 from public.return_orders o where o.supplier_id=suppliers.id)),'[]'::jsonb));

 elsif p_action='detail' then
  select * into r from public.return_orders where id=(p_data->>'id')::uuid;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  return to_jsonb(r)||jsonb_build_object(
   'rights',rights,
   'amount',private.gama_return_amount(r.id),
   'partner',coalesce((select name from public.customers where id=r.customer_id),
                      (select name from public.suppliers where id=r.supplier_id)),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'product_id',l.product_id,
      'product',p.name,'reference',p.reference,'quantity',l.quantity,'unit_price',l.unit_price,
      'tax_rate',l.tax_rate,'disposition',l.disposition,'processed_at',l.processed_at,'notes',l.notes,
      'amount',round(l.quantity*l.unit_price*(1+l.tax_rate/100),2)) order by p.name)
     from public.return_lines l join public.products p on p.id=l.product_id
     where l.return_id=r.id),'[]'::jsonb),
   'credits',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'number',k.number,'amount',k.amount,
      'issued_on',k.issued_on,'supplier_reference',k.supplier_reference,'notes',k.notes,
      'has_file',k.data_url is not null) order by k.created_at)
     from public.return_credits k where k.return_id=r.id),'[]'::jsonb),
   'refunds',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'amount',f.amount,'paid_at',f.paid_at,
      'method',f.method,'reference',f.reference,'notes',f.notes) order by f.paid_at)
     from public.return_refunds f where f.return_id=r.id),'[]'::jsonb),
   'refunded',(select coalesce(sum(amount),0) from public.return_refunds where return_id=r.id),
   'files',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'filename',x.filename,
      'mime_type',x.mime_type) order by x.created_at) from public.return_files x where x.return_id=r.id),'[]'::jsonb),
   -- Documentos ligados: nunca se duplican, se enlazan.
   'documents',(select jsonb_build_object(
      'order',(select jsonb_build_object('id',o.id,'number',o.number) from public.sales_orders o where o.id=r.order_id),
      'delivery',(select jsonb_build_object('id',s.id,'number',s.number) from public.sales_deliveries s where s.id=r.delivery_id),
      'invoice',(select jsonb_build_object('id',i.id,'number',i.number) from public.external_invoices i where i.id=r.invoice_id),
      'purchase_order',(select jsonb_build_object('id',po.id,'number',po.order_number) from public.purchase_orders po where po.id=r.purchase_order_id),
      'supplier_invoice',(select jsonb_build_object('id',si.id,'number',si.number) from public.supplier_invoices si where si.id=r.supplier_invoice_id))));
 end if;
 return private.gama_returns_action2(p_action,p_data,rights,today);
end $fn$;
revoke all on function private.gama_returns_action(text,jsonb) from public,anon;
grant execute on function private.gama_returns_action(text,jsonb) to authenticated;
