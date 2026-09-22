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
