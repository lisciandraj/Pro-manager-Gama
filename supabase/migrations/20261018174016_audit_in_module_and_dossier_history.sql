-- Read the existing audit trail in context; do not copy or rewrite its journals.
-- The audit permission remains required, in addition to the destination module.
create function private.coco_audit_events() returns table(
 kind text,at timestamptz,actor uuid,action text,label text,detail text,reference text,
 amount numeric,quantity numeric,target_table text,target_id text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('audit',array['administrador']) then return;end if;
 return query
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
  select 'transfer',e.at,e.user_id,'delivery_'||e.type,
   case e.type when 'Creada' then 'Entrega creada' when 'Entregada' then 'Entrega completada'
    when 'SALIDA_VALIDADA' then 'Salida de entrega validada' when 'CARGA_ESCANEADA' then 'Carga de entrega escaneada'
    when 'COORDENADAS' then 'Coordenadas de entrega corregidas' when 'RUTA_AJUSTADA' then 'Ruta de entrega ajustada'
    when 'INCIDENTE' then 'Incidencia de entrega registrada' when 'REPROGRAMADA' then 'Entrega reprogramada'
    when 'ENTREGA_PARCIAL' then 'Entrega parcial y retorno' when 'COBRO' then 'Cobro en la entrega'
    when 'AVISO_PREPARADO' then 'Aviso de llegada preparado'
    else 'Entrega · '||e.type end,
   concat_ws(' · ',coalesce(nullif(e.customer,''),d.customer),nullif(e.note,'')),
   d.erp_reference,null,null,'tms_events',e.id::text
  from public.tms_events e left join public.tms_deliveries d on d.id=e.delivery_id
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
 )
 select * from ev where ev.at is not null;
end $$;
revoke all on function private.coco_audit_events() from public,anon,authenticated;

-- One canonical projection for the standalone audit trail and embedded history.
do $$declare src text;start_at integer;end_at integer;begin
 src:=pg_get_functiondef('private.gama_audit_trail(jsonb)'::regprocedure);
 start_at:=strpos(src,' with ev(');end_at:=strpos(src,' ), hits as (');
 if start_at=0 or end_at<=start_at then raise exception 'AUDIT_TRAIL_PROJECTION_MISMATCH';end if;
 src:=left(src,start_at-1)||' with ev as (select * from private.coco_audit_events()'||substr(src,end_at);
 execute src;
end $$;

-- Explicit foreign-key relationships only. No matching by name, text or UUID alone.
create function private.coco_audit_links(p_table text,p_id text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;ln jsonb:='[]';oid uuid;poid uuid;qid uuid;tid uuid;cid uuid;sid uuid;pid uuid;rid uuid;subtable text;
begin
 if p_table not in ('stock_movements','tms_events','external_invoice_payments','supplier_invoice_payments','return_refunds','external_invoices','supplier_invoices','erp_approvals','stock_adjustment_requests','accounting_entries','profiles','role_module_access','erp_action_permissions') then return ln;end if;
 -- Access changes can concern deleted records and composite role keys.
 if p_table in ('profiles','role_module_access','erp_action_permissions') then
  return jsonb_build_array(jsonb_build_object('module',case when p_table='profiles' then 'users' else 'access-settings' end,'action','module','id',p_id));
 end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1::uuid',p_table) into r using p_id;
 if r is null then return ln;end if;
 if p_table='stock_movements' then
  ln:='[{"module":"warehouses","action":"module"}]';pid:=(r->>'product_id')::uuid;
  case r->>'reference_type'
   when 'purchase_order' then poid:=(r->>'reference_id')::uuid;
   when 'sales_order' then oid:=(r->>'reference_id')::uuid;
   when 'sales_delivery' then select order_id,tms_delivery_id into oid,tid from public.sales_deliveries where id=(r->>'reference_id')::uuid;
   when 'customer_return' then rid:=(r->>'reference_id')::uuid;
   when 'supplier_return' then rid:=(r->>'reference_id')::uuid;
   else null;
  end case;
 elsif p_table='stock_adjustment_requests' then
  ln:='[{"module":"warehouses","action":"module"}]';pid:=(r->>'product_id')::uuid;
 elsif p_table='tms_events' then
  tid:=(r->>'delivery_id')::uuid;select order_id into oid from public.sales_deliveries where tms_delivery_id=tid;
 elsif p_table='erp_approvals' then
  if r->>'module'='credit' then oid:=(r->>'document_id')::uuid;
  elsif r->>'module'='quotes' then qid:=(r->>'document_id')::uuid;
  elsif r->>'module'='gamaPurchasesV14' then poid:=(r->>'document_id')::uuid;end if;
 elsif p_table='accounting_entries' then
  ln:=jsonb_build_array(jsonb_build_object('module','accounting','action','module','id',p_id));
  subtable:=case r->>'source_type' when 'sales_invoice' then 'external_invoices' when 'customer_payment' then 'external_invoice_payments' when 'supplier_invoice' then 'supplier_invoices' when 'supplier_payment' then 'supplier_invoice_payments' when 'return_refund' then 'return_refunds' end;
  if subtable is not null and r->>'source_id' is not null then ln:=ln||private.coco_audit_links(subtable,r->>'source_id');end if;
 elsif p_table in ('external_invoices','external_invoice_payments') then
  ln:='[{"module":"accounting","action":"module"}]';
  if p_table='external_invoice_payments' then select to_jsonb(i) into r from public.external_invoices i where id=(r->>'invoice_id')::uuid;end if;
  ln:=ln||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',r->>'id','reference',r->>'number'));oid:=(r->>'order_id')::uuid;
 elsif p_table in ('supplier_invoices','supplier_invoice_payments') then
  if p_table='supplier_invoice_payments' then select to_jsonb(i) into r from public.supplier_invoices i where id=(r->>'supplier_invoice_id')::uuid;end if;
  ln:=jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',r->>'id','reference',r->>'number'));poid:=(r->>'purchase_order_id')::uuid;sid:=(r->>'supplier_id')::uuid;
  -- Invoice matching can link a supplier invoice to more than one purchase.
  ln:=ln||coalesce((select jsonb_agg(jsonb_build_object('module','gamaPurchasesV14','action','purchase','id',m.purchase_order_id)) from public.supplier_invoice_matches m where m.invoice_id=(r->>'id')::uuid),'[]');
 elsif p_table='return_refunds' then rid:=(r->>'return_id')::uuid;ln:='[{"module":"accounting","action":"module"}]';
 end if;
 if rid is not null then
  ln:=ln||jsonb_build_array(jsonb_build_object('module','returns','action','return','id',rid));
  select customer_id,supplier_id,order_id,purchase_order_id into cid,sid,oid,poid from public.return_orders where id=rid;
 end if;
 if oid is not null then
  select source_quote_id,customer_id into qid,cid from public.sales_orders where id=oid;
  ln:=ln||jsonb_build_array(jsonb_build_object('module','sales-orders','action','order','id',oid));
 end if;
 if poid is not null then
  select supplier_id into sid from public.purchase_orders where id=poid;
  ln:=ln||jsonb_build_array(jsonb_build_object('module','gamaPurchasesV14','action','purchase','id',poid));
 end if;
 if qid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','quotes','action','quote','id',qid));end if;
 if tid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','tms','action','delivery','id',tid));end if;
 if pid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','products','action','module','id',pid));end if;
 if cid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','contacts','action','module','id',cid));end if;
 if sid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','contacts','action','module','id',sid));end if;
 return ln;
end $$;
revoke all on function private.coco_audit_links(text,text) from public,anon,authenticated;

-- Is this precise event already represented by the canonical dossier timeline?
-- This runs before pagination, not against only the currently visible page.
create function private.coco_audit_in_process(p_table text,p_id text,p_at timestamptz,p_action text,p_kind text) returns boolean
language sql stable security definer set search_path='' as $$
 select case
 when p_kind is null then false
 when p_table='tms_events' then true
 when p_table='stock_movements' and p_kind='purchase' then exists(select 1 from public.stock_movements where id=p_id::uuid and reference_type='purchase_order')
 when p_table='external_invoice_payments' and p_action='customer_payment' then true
 when p_table='supplier_invoice_payments' and p_action='supplier_payment' then true
 when p_table in ('external_invoices','supplier_invoices','external_invoice_payments','supplier_invoice_payments') then exists(
  select 1 from public.erp_audit_events a where a.table_name=p_table and a.record_id=p_id and a.created_at=p_at and
  (a.operation='INSERT' and p_table in ('external_invoices','supplier_invoices') or a.operation='UPDATE' and exists(select 1 from unnest(array['status','fiscal_status','received_quantity','processed_at','closed_at','received_at','shipped_on','financial_action','approved_at','cancelled_at','external_status']) f where a.before_data->f is distinct from a.after_data->f)))
 else false end
$$;
revoke all on function private.coco_audit_in_process(text,text,timestamptz,text,text) from public,anon,authenticated;

-- Virtual rows preserve the existing grouping and pagination contract. Nothing
-- is inserted into the index, and original timestamps/authors remain unchanged.
create function private.coco_scoped_audit(p_module text,p_record text default null,p_kind text default null)
returns setof private.coco_module_events
language plpgsql stable security definer set search_path='' as $$
declare e record;ln jsonb;author text;ctx jsonb;key text;refs jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('audit',array['administrador']) or not private.coco_module_allowed(p_module) then return;end if;
 if p_kind is not null then
  if p_module is distinct from (case p_kind when 'sales' then 'sales-orders' when 'quote' then 'quotes' when 'purchase' then 'gamaPurchasesV14' when 'tms' then 'tms' end) then raise exception 'INVALID_ORDER_KIND';end if;
  ctx:=private.coco_dossier_context(p_kind,p_record::uuid);
 end if;
 for e in select * from private.coco_audit_events() a where
  case p_module
   when 'users' then a.target_table='profiles'
   when 'access-settings' then a.target_table in ('role_module_access','erp_action_permissions')
   when 'products' then a.target_table in ('stock_movements','stock_adjustment_requests')
   when 'warehouses' then a.target_table in ('stock_movements','stock_adjustment_requests')
   when 'payments' then a.target_table in ('external_invoices','external_invoice_payments','accounting_entries')
   when 'accounting' then a.kind in ('payment','invoice') or a.target_table='accounting_entries'
   when 'tms' then a.target_table in ('tms_events','stock_movements')
   when 'returns' then a.target_table in ('stock_movements','return_refunds','accounting_entries')
   when 'contacts' then a.kind<>'access'
   when 'sales-orders' then a.kind<>'access'
   when 'quotes' then a.kind<>'access'
   when 'gamaPurchasesV14' then a.kind<>'access' and a.kind<>'transfer'
   else false end loop
  -- Financial/access traces retain their originating module restrictions, even
  -- when the associated purchase or contact can be read by another profile.
  if e.kind in ('payment','invoice') and not private.coco_module_allowed(case when e.target_table in ('external_invoices','external_invoice_payments') then 'payments' else 'accounting' end) then continue;end if;
  if e.target_table='accounting_entries' and not private.coco_module_allowed('accounting') then continue;end if;
  if e.kind='stock' and not private.coco_module_allowed('warehouses') then continue;end if;
  if e.kind='transfer' and not private.coco_module_allowed('tms') then continue;end if;
  ln:=private.coco_audit_links(e.target_table,e.target_id);
  if not exists(select 1 from jsonb_array_elements(ln) l where l->>'module'=p_module and (p_record is null or l->>'id'=p_record)) then continue;end if;
  if p_record is not null and p_kind is not null and private.coco_audit_in_process(e.target_table,e.target_id,e.at,e.action,p_kind) then continue;end if;
  select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=e.actor;
  select coalesce(jsonb_agg(distinct l),'[]') into ln from jsonb_array_elements(ln) l where private.coco_module_allowed(l->>'module');
  key:='audit-trail:'||e.target_table||':'||e.target_id||':'||e.action||':'||e.at::text;
  refs:=jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('kind','document','id',e.target_id,'reference',coalesce(e.reference,e.target_id),'name',e.detail,'quantity',e.quantity,'amount',e.amount)));
  return next jsonb_populate_record(null::private.coco_module_events,jsonb_build_object(
   'id',md5(key)::uuid,'module_id',p_module,'record_table',e.target_table,'record_id',e.target_id,
   'type','action','action',e.action,'subject',e.label,'body','','reference',e.reference,
   'actor_id',e.actor,'actor_name',coalesce(author,'AUTHOR_NOT_RECORDED'),'created_at',e.at,
   'transaction_id',hashtextextended('audit:'||e.at::text,0),'references_list',refs,'links',ln,'source_type','audit'));
 end loop;
end $$;
revoke all on function private.coco_scoped_audit(text,text,text) from public,anon;
grant execute on function private.coco_scoped_audit(text,text,text) to authenticated;

-- Merge before grouping/pagination; a precise audit event replaces only its
-- matching generic insert/status trace, never a note, deletion or source link.
do $$declare src text;needle text;replacement text;begin
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:='with visible as materialized(';
 replacement:=$patch$with audit_rows as materialized (
  select * from private.coco_scoped_audit(m,nullif(p_data->>'record_id',''),nullif(p_data->>'dossier_kind',''))
  where not coalesce((p_data->>'annotations_only')::boolean,false) or coalesce((p_data->>'include_audit')::boolean,false)
 ), combined as (
  select e.* from private.coco_module_events e where not exists(
   select 1 from audit_rows a where a.record_table=e.record_table and a.record_id=e.record_id and a.created_at=e.created_at
    and a.actor_id is not distinct from e.actor_id and e.type='action' and e.proposal_id is null and e.source_type='erp' and
    (e.action='insert' and a.action not in ('customer_payment_cancelled','entry_posted','approval_approved','approval_rejected','adjustment_approved','adjustment_rejected')
     or e.action='status' and a.action in ('customer_payment_cancelled','entry_posted','approval_approved','approval_rejected','adjustment_approved','adjustment_rejected')
     or e.action='update' and a.action in ('profiles_update','role_module_access_update','erp_action_permissions_update')))
  union all select * from audit_rows
 ), visible as materialized($patch$;
 if strpos(src,needle)=0 then raise exception 'MODULE_HISTORY_MERGE_MISMATCH';end if;
 src:=replace(src,needle,replacement);
 src:=replace(src,'select * from private.coco_module_events e where module_id=m','select * from combined e where module_id=m');
 src:=replace(src,$text$or e.action='source_linked'$text$,$text$or e.source_type='audit' or e.action='source_linked'$text$);
 execute src;
end $$;

-- Existing sales/purchase/TMS panels request scoped audit as well as annotations.
do $$declare src text;begin
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 if strpos(src,$text$'annotations_only',true$text$)=0 then raise exception 'DOSSIER_AUDIT_MERGE_MISMATCH';end if;
 src:=replace(src,$text$'annotations_only',true$text$,$text$'annotations_only',true,'include_audit',true,'dossier_kind',p_data->>'kind'$text$);
 src:=replace(src,$text$e->>'action'='source_linked'$text$,$text$e->>'source_type'='audit' or e->>'action'='source_linked'$text$);
 execute src;
end $$;
notify pgrst,'reload schema';
