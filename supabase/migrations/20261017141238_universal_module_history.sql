-- A sanitized activity index. Business tables and their RLS remain authoritative.
create table private.coco_history_modules(
 module_id text primary key,label text not null,roles text[] not null
);
create table private.coco_history_tables(
 table_name text primary key,module_id text not null references private.coco_history_modules,
 label text not null,parent_column text,parent_table text,
 table_schema text not null default 'public' check(table_schema in ('public','private')),
 key_column text not null default 'id' check(key_column ~ '^[a-z_]+$'),
 check(table_name ~ '^[a-z_]+$' and (parent_table is null or parent_table ~ '^[a-z_]+$'))
);
create table private.coco_module_events(
 id uuid primary key default gen_random_uuid(),module_id text not null references private.coco_history_modules,
 record_table text references private.coco_history_tables,record_id text,record_owner uuid,
 type text not null check(type in ('action','note','proposal')),action text not null,
 subject text not null,body text not null default '',reference text,
 actor_id uuid references public.profiles on delete set null,actor_name text not null,
 created_at timestamptz not null default now(),transaction_id bigint not null default txid_current(),
 references_list jsonb not null default '[]',links jsonb not null default '[]',
 source_type text not null default 'erp' check(source_type in ('erp','mail','chat','file','import')),
 source_id text,source_label text,source_email text,proposal_id uuid,request_key uuid,
 unique(actor_id,request_key),check(length(body)<=10000 and length(subject)<=300)
);
create index coco_module_events_page on private.coco_module_events(module_id,created_at desc,id);
create index coco_module_events_record on private.coco_module_events(record_table,record_id);
create index coco_module_events_actor on private.coco_module_events(actor_id);
create index coco_module_events_proposal on private.coco_module_events(proposal_id);
alter table private.coco_history_modules enable row level security;
alter table private.coco_history_tables enable row level security;
alter table private.coco_module_events enable row level security;
revoke all on private.coco_history_modules,private.coco_history_tables,private.coco_module_events from public,anon,authenticated;
grant select on private.coco_history_modules,private.coco_history_tables,private.coco_module_events to authenticated;
create policy coco_history_catalog on private.coco_history_modules for select to authenticated using(true);
create policy coco_history_table_catalog on private.coco_history_tables for select to authenticated using(true);

insert into private.coco_history_modules values
('surveys','Encuestas y marketing',array['administrador','comercial']),
('sri','Facturación SRI',array['administrador']),
('website','Sitio web',array['administrador']),
('sav','Reclamaciones',array['administrador','comercial']),
('documents','Documentos',array['administrador','comercial','almacenero']),
('tms','TMS',array['administrador','almacenero']),
('accounting','Contabilidad',array['administrador','comercial']),
('fleet','Gestión de flota',array['administrador']),
('projects','Proyectos',array['administrador','comercial','almacenero']),
('assistant-ia','Agent Coco',array['administrador']),
('dashboard','Panel de control',array['administrador','comercial','almacenero']),
('notifications','Notificaciones',array['administrador','comercial','almacenero']),
('knowledge','Base de conocimientos',array['administrador','comercial','almacenero']),
('products','Productos',array['administrador','comercial','almacenero']),
('warehouses','Almacenes y existencias',array['administrador','comercial','almacenero']),
('gamaPurchasesV14','Compras',array['administrador','comercial','almacenero']),
('matrix','Matriz comercial',array['administrador','comercial']),
('barcode','Códigos de barras',array['administrador','almacenero']),
('quotes','Ventas',array['administrador','comercial']),
('contacts','Contactos',array['administrador','comercial']),
('dossier-flow','Seguimiento de procesos',array['administrador','comercial','almacenero']),
('sales-orders','Pedidos de venta',array['administrador','comercial','almacenero']),
('payments','Facturas y cobros',array['administrador','comercial']),
('returns','Devoluciones y posventa',array['administrador','comercial','almacenero']),
('crm','CRM',array['administrador','comercial']),
('price-lists','Tarifas',array['administrador','comercial']),
('reports','Importar datos',array['administrador','comercial']),
('hr','Recursos humanos',array['administrador','comercial','almacenero','rrhh']),
('audit','Auditoría',array['administrador']),
('users','Usuarios',array['administrador']),
('access-settings','Parámetros de acceso',array['administrador']),
('settings','Configuración',array['administrador','comercial','almacenero','rrhh']),
('backup','Copias de seguridad',array['administrador']),
('billing','Formulario anterior de presupuestos',array['administrador','comercial']),
('customer-requests','Solicitudes de clientes',array['administrador','comercial']);
insert into private.coco_history_tables(table_name,module_id,label,parent_column,parent_table) select v.* from (values
('products','products','Producto',null,null),
('product_units','products','Productos',null,null),
('product_lots','products','Productos',null,null),
('product_price_history','products','Productos',null,null),
('customers','contacts','Cliente',null,null),
('suppliers','contacts','Proveedor',null,null),
('customer_addresses','contacts','Contactos',null,null),
('crm_contacts','contacts','Contacto',null,null),
('crm_leads','crm','Prospecto',null,null),
('crm_opportunities','crm','CRM',null,null),
('crm_opportunity_lines','crm','CRM',null,null),
('crm_activities','crm','CRM',null,null),
('crm_targets','crm','CRM',null,null),
('crm_team','crm','CRM',null,null),
('crm_pipeline_stages','crm','CRM',null,null),
('crm_sources','crm','CRM',null,null),
('warehouses','warehouses','Almacenes y existencias',null,null),
('warehouse_locations','warehouses','Almacenes y existencias',null,null),
('warehouse_shelves','warehouses','Almacenes y existencias',null,null),
('stock_movements','warehouses','Almacenes y existencias',null,null),
('stock_quants','warehouses','Almacenes y existencias',null,null),
('stock_reservations','warehouses','Almacenes y existencias',null,null),
('stock_lot_movements','warehouses','Almacenes y existencias',null,null),
('inventory_counts','warehouses','Almacenes y existencias',null,null),
('inventory_count_lines','warehouses','Almacenes y existencias',null,null),
('reorder_rules','warehouses','Almacenes y existencias',null,null),
('stock_adjustment_requests','warehouses','Almacenes y existencias',null,null),
('stock_integrity_cases','warehouses','Almacenes y existencias',null,null),
('stock_landed_costs','warehouses','Almacenes y existencias',null,null),
('accounting_entries','accounting','Asiento contable',null,null),
('accounting_entry_lines','accounting','Líneas contables','entry_id','accounting_entries'),
('accounting_accounts','accounting','Contabilidad',null,null),
('accounting_journals','accounting','Contabilidad',null,null),
('accounting_periods','accounting','Contabilidad',null,null),
('accounting_taxes','accounting','Contabilidad',null,null),
('financial_accounts','accounting','Contabilidad',null,null),
('bank_transactions','accounting','Movimiento bancario',null,null),
('bank_match_groups','accounting','Contabilidad',null,null),
('reconciliations','accounting','Contabilidad',null,null),
('expenses','accounting','Contabilidad',null,null),
('expense_receipts','accounting','Contabilidad',null,null),
('supplier_invoices','accounting','Contabilidad',null,null),
('supplier_invoice_payments','accounting','Contabilidad',null,null),
('accounting_assets','accounting','Contabilidad',null,null),
('accounting_depreciations','accounting','Contabilidad',null,null),
('accounting_maturities','accounting','Contabilidad',null,null),
('accounting_payment_terms','accounting','Contabilidad',null,null),
('accounting_adjustments','accounting','Contabilidad',null,null),
('accounting_withholdings','accounting','Contabilidad',null,null),
('accounting_received_sri','accounting','Contabilidad',null,null),
('fleet_vehicles','fleet','Vehículo',null,null),
('fleet_drivers','fleet','Gestión de flota',null,null),
('fleet_assignments','fleet','Gestión de flota',null,null),
('fleet_documents','fleet','Gestión de flota',null,null),
('fleet_fuel_logs','fleet','Carga de combustible',null,null),
('fleet_maintenance','fleet','Gestión de flota',null,null),
('fleet_alert_log','fleet','Gestión de flota',null,null),
('hr_employees','hr','Ficha de empleado',null,null),
('hr_absences','hr','Solicitud de ausencia','employee_id','hr_employees'),
('hr_attendance','hr','Recursos humanos',null,null),
('hr_documents','hr','Documento RH',null,null),
('hr_payroll','hr','Recursos humanos',null,null),
('hr_payroll_payments','hr','Recursos humanos',null,null),
('hr_leave_accounts','hr','Recursos humanos',null,null),
('hr_employee_skills','hr','Recursos humanos',null,null),
('hr_shifts','hr','Recursos humanos',null,null),
('hr_work_patterns','hr','Recursos humanos',null,null),
('hr_lifecycle_tasks','hr','Recursos humanos',null,null),
('hr_ec_employee_terms','hr','Recursos humanos',null,null),
('hr_ec_benefits','hr','Recursos humanos',null,null),
('hr_ec_benefit_payments','hr','Recursos humanos',null,null),
('hr_ec_utilities','hr','Recursos humanos',null,null),
('business_documents','documents','Documento',null,null),
('business_document_files','documents','Archivo del documento','document_id','business_documents'),
('business_document_approvals','documents','Documentos',null,null),
('document_categories','documents','Documentos',null,null),
('pm_projects','projects','Proyectos',null,null),
('pm_items','projects','Proyectos',null,null),
('pm_comments','projects','Proyectos',null,null),
('pm_files','projects','Proyectos',null,null),
('pm_members','projects','Proyectos',null,null),
('pm_links','projects','Proyectos',null,null),
('pm_baselines','projects','Proyectos',null,null),
('pm_cost_entries','projects','Proyectos',null,null),
('pm_templates','projects','Proyectos',null,null),
('project_time_entries','projects','Proyectos',null,null),
('return_orders','returns','Devoluciones y posventa',null,null),
('return_lines','returns','Devoluciones y posventa','return_id','return_orders'),
('return_files','returns','Devoluciones y posventa',null,null),
('return_credits','returns','Devoluciones y posventa',null,null),
('return_refunds','returns','Devoluciones y posventa',null,null),
('service_tickets','sav','Reclamaciones',null,null),
('service_messages','sav','Reclamaciones',null,null),
('invoices','quotes','Ventas',null,null),
('invoice_lines','quotes','Ventas','invoice_id','invoices'),
('external_invoices','payments','Facturas y cobros',null,null),
('external_invoice_lines','payments','Facturas y cobros',null,null),
('external_invoice_payments','payments','Facturas y cobros',null,null),
('external_invoice_files','payments','Facturas y cobros',null,null),
('customer_receipts','payments','Facturas y cobros',null,null),
('receivable_followups','payments','Facturas y cobros',null,null),
('purchase_orders','gamaPurchasesV14','Compras',null,null),
('purchase_order_lines','gamaPurchasesV14','Compras','purchase_order_id','purchase_orders'),
('purchase_service_acceptances','gamaPurchasesV14','Compras',null,null),
('supplier_product_offers','gamaPurchasesV14','Compras',null,null),
('supplier_invoice_matches','gamaPurchasesV14','Compras',null,null),
('supplier_invoice_match_lines','gamaPurchasesV14','Compras',null,null),
('sales_orders','sales-orders','Pedidos de venta',null,null),
('sales_order_lines','sales-orders','Pedidos de venta','order_id','sales_orders'),
('sales_deliveries','sales-orders','Pedidos de venta',null,null),
('sales_delivery_lines','sales-orders','Pedidos de venta',null,null),
('sales_service_completions','sales-orders','Pedidos de venta',null,null),
('tms_deliveries','tms','TMS',null,null),
('tms_routes','tms','TMS',null,null),
('tms_delivery_attempts','tms','TMS',null,null),
('tms_delivery_incidents','tms','TMS',null,null),
('tms_loading_scans','tms','TMS',null,null),
('tms_route_schedules','tms','TMS',null,null),
('fulfillment_preparations','tms','TMS',null,null),
('fulfillment_pick_lines','tms','TMS',null,null),
('fulfillment_packages','tms','TMS',null,null),
('fulfillment_incidents','tms','TMS',null,null),
('knowledge_articles','knowledge','Artículo',null,null),
('storefront_settings','website','Sitio web',null,null),
('marketing_campaigns','surveys','Encuestas y marketing',null,null),
('survey_forms','surveys','Encuestas y marketing',null,null),
('sri_document_issues','sri','Facturación SRI',null,null),
('sri_electronic_documents','sri','Facturación SRI',null,null),
('profiles','users','Usuarios',null,null),
('erp_price_books','price-lists','Tarifas',null,null),
('erp_price_tiers','price-lists','Tarifas',null,null),
('customer_special_prices','price-lists','Tarifas',null,null),
('commercial_matrix','matrix','Matriz comercial',null,null),
('company_settings','settings','Configuración',null,null),
('app_modules','settings','Configuración',null,null),
('erp_policies','settings','Configuración',null,null),
('erp_import_batches','reports','Importar datos',null,null),
('erp_import_rows','reports','Importar datos',null,null)) v(table_name,module_id,label,parent_column,parent_table) where exists(select 1 from information_schema.tables t where t.table_schema='public' and t.table_name=v.table_name and t.table_type='BASE TABLE') and exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=v.table_name and c.column_name='id');


insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) select v.* from (values
 ('surveys','surveys','Encuesta','private','id'),('marketing_campaigns','surveys','Campaña','private','id'),
 ('website_public_settings','website','Configuración del sitio web','private','id'),
 ('website_public_inquiries','website','Solicitud del sitio web','private','id'),
 ('automation_rules','access-settings','Regla de automatización','private','kind'),
 ('hr_employee_private','hr','Ficha de empleado','public','employee_id'),
 ('hr_absence_private','hr','Solicitud de ausencia','public','absence_id'),
 ('role_module_access','access-settings','Permisos de módulo','public','role'),
 ('erp_action_permissions','access-settings','Permisos de acción','public','role'),
 ('accounting_permissions','accounting','Permisos contables','public','profile_id'),
 ('hr_permissions','hr','Permisos RH','public','profile_id'),
 ('gama_ai_history','assistant-ia','Acción de Agent Coco','public','id')) v(table_name,module_id,label,table_schema,key_column)
 where exists(select 1 from information_schema.columns c where c.table_schema=v.table_schema and c.table_name=v.table_name and c.column_name=v.key_column);

create function private.coco_module_allowed(p_module text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and exists(select 1 from private.coco_history_modules m where m.module_id=p_module
  and private.erp_module_allowed(m.module_id,m.roles))
 and case when p_module='accounting' then private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all'
 when p_module='fleet' then private.gama_fleet_may() else true end
$$;
revoke all on function private.coco_module_allowed(text) from public,anon;
grant execute on function private.coco_module_allowed(text) to authenticated;

-- Invoker is essential here: a definer must never test row visibility on behalf
-- of the caller. Missing grants and unknown/deleted records fail closed.
create function private.coco_history_record_exists(p_table text,p_id text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare cfg private.coco_history_tables;present boolean;begin
 select * into cfg from private.coco_history_tables where table_name=p_table;
 if cfg.table_name is null or not private.coco_module_allowed(cfg.module_id) or private.current_user_role()<>'administrador' then return false;end if;
 execute format('select exists(select 1 from %I.%I where %I::text=$1)',cfg.table_schema,p_table,cfg.key_column) into present using p_id;
 return coalesce(present,false);
end $$;
revoke all on function private.coco_history_record_exists(text,text) from public,anon;
grant execute on function private.coco_history_record_exists(text,text) to authenticated;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
declare cfg private.coco_history_tables;visible boolean;
begin
 select * into cfg from private.coco_history_tables where table_name=p_table;
 if cfg.table_name is null or not private.coco_module_allowed(cfg.module_id) then return false;end if;
 -- These RPC-only tables have module-wide read contracts. No row contents
 -- enter this index; other private tables never acquire a fallback grant.
 if cfg.table_schema='private' and cfg.table_name in ('surveys','marketing_campaigns','website_public_settings','website_public_inquiries','automation_rules') then return true;end if;
 if cfg.module_id='fleet' then return private.gama_fleet_may();end if;
 if cfg.module_id in ('accounting','sri') and not has_table_privilege(current_user,'public.'||p_table,'SELECT') then
  return private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all';
 end if;
 if not has_table_privilege(current_user,'public.'||p_table,'SELECT') then return false;end if;
 execute format('select exists(select 1 from %I.%I where %I::text=$1)',cfg.table_schema,p_table,cfg.key_column) into visible using p_id;
 return coalesce(visible,false) or private.current_user_role()='administrador' and not private.coco_history_record_exists(p_table,p_id);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
create policy coco_module_events_read on private.coco_module_events for select to authenticated using(
 private.coco_module_allowed(module_id) and
 case when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid()
 else true end
);

-- Record only references, action and status. No snapshots, diagnoses, addresses,
-- salaries, bank details, credentials, attachment bodies or free-text HR reasons.
create function private.coco_capture_module_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare cfg private.coco_history_tables;n jsonb:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 before_row jsonb;ref text;author text;actor uuid:=auth.uid();ln jsonb:='[]';refs jsonb:='[]';parent jsonb;
 st text;src jsonb;act text:=lower(tg_op);rid text:=n->>'id';
begin
 select * into cfg from private.coco_history_tables where table_name=tg_table_name and table_schema=tg_table_schema;
 if cfg.table_name is null then return null;end if;
 rid:=n->>cfg.key_column;
 if tg_op='UPDATE' then
  before_row:=to_jsonb(old);
  if (before_row-array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at'])
   is not distinct from (n-array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at']) then return null;end if;
 end if;
 if actor is null then actor:=nullif(coalesce(n->>'updated_by',n->>'created_by',n->>'user_id'),'')::uuid;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=actor;
 ref:=left(coalesce(nullif(n->>'erp_reference',''),nullif(n->>'number',''),nullif(n->>'reference',''),nullif(n->>'code',''),
  case when cfg.module_id not in ('hr','users','access-settings','settings','sri') then coalesce(n->>'title',n->>'name',n->>'plate') end,rid),180);
 if cfg.module_id='hr' then ref:=left(coalesce(n->>'erp_reference',n->>'start_date',n->>'work_date',rid),180);end if;
 st:=case when n->>'status' in ('draft','posted','reversed','pendiente','aprobada','rechazada','cancelada','active','closed','confirmed','cancelled','paid','pending','approved','rejected') then n->>'status' end;
 if tg_op='UPDATE' and st is not null and st is distinct from before_row->>'status' then act:='status';end if;
 ln:=jsonb_build_array(jsonb_build_object('module',cfg.module_id,'action','module','id',rid,'reference',ref));
 if cfg.parent_column is not null and n->>cfg.parent_column is not null then
  execute format('select to_jsonb(t) from public.%I t where id::text=$1',cfg.parent_table) into parent using n->>cfg.parent_column;
  if parent is not null then
   ref:=left(coalesce(parent->>'erp_reference',parent->>'number',parent->>'order_number',parent->>'name',parent->>'title',n->>cfg.parent_column),180);
  end if;
 end if;
 if n->>'product_id' is not null then
  select jsonb_build_array(jsonb_build_object('kind','product','id',p.id,'reference',p.reference,'name',p.name,
    'quantity',case when (n->>'quantity') ~ '^[0-9]+([.][0-9]+)?$' then (n->>'quantity')::numeric end)) into refs from public.products p where p.id::text=n->>'product_id';
 end if;
 if refs='[]'::jsonb or refs is null then refs:=jsonb_build_array(jsonb_build_object('kind','document','id',rid,'reference',ref));end if;
 -- Known business relationships only; no arbitrary routes or external URLs.
 for src in select * from jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('key','customer_id','module','contacts'),jsonb_build_object('key','supplier_id','module','contacts'),
  jsonb_build_object('key','employee_id','module','hr'),jsonb_build_object('key','vehicle_id','module','fleet'),
  jsonb_build_object('key','project_id','module','projects'),jsonb_build_object('key','document_id','module','documents'),
  jsonb_build_object('key','sales_order_id','module','sales-orders'),jsonb_build_object('key','purchase_order_id','module','gamaPurchasesV14'),
  jsonb_build_object('key','entry_id','module','accounting'),jsonb_build_object('key','source_module','module',n->>'source_module')
 )) loop
  if n->>(src->>'key') is not null and exists(select 1 from private.coco_history_modules where module_id=src->>'module') then
   ln:=ln||jsonb_build_array(jsonb_build_object('module',src->>'module','action','module','id',n->>(src->>'key')));
  end if;
 end loop;
 insert into private.coco_module_events(module_id,record_table,record_id,record_owner,type,action,subject,body,reference,actor_id,actor_name,references_list,links,source_type,source_id,source_label)
 values(cfg.module_id,tg_table_name,rid,nullif(n->>'created_by','')::uuid,'action',act,cfg.label,coalesce(st,''),ref,actor,coalesce(author,'AUTHOR_NOT_RECORDED'),refs,ln,
  coalesce(nullif(current_setting('coco.activity_source_type',true),''),'erp'),nullif(current_setting('coco.activity_source_id',true),''),nullif(current_setting('coco.activity_source_label',true),''));
 return null;
end $$;
revoke all on function private.coco_capture_module_event() from public,anon,authenticated;
create function private.coco_history_actor_deleted() returns trigger
language plpgsql security definer set search_path='' as $$begin
 update private.coco_module_events set actor_id=null,actor_name='USER_UNAVAILABLE' where actor_id=old.id;
 update private.coco_module_events set record_owner=null where record_owner=old.id;
 return old;
end $$;
revoke all on function private.coco_history_actor_deleted() from public,anon,authenticated;
create trigger coco_history_actor_deleted before delete on public.profiles for each row execute function private.coco_history_actor_deleted();
do $$declare cfg private.coco_history_tables;begin
 for cfg in select * from private.coco_history_tables loop
  execute format('create trigger coco_module_history after insert or update or delete on %I.%I for each row execute function private.coco_capture_module_event()',cfg.table_schema,cfg.table_name);
 end loop;
end $$;

create function private.coco_module_note(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m text:=p_data->>'module_id';key uuid:=(p_data->>'request_key')::uuid;msg text:=btrim(p_data->>'body');r private.coco_module_events;author text;
begin
 if not private.coco_module_allowed(m) or not private.erp_action_allowed(m,'edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if m='hr' and not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null or coalesce(length(msg),0) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_id,actor_name,request_key)
 values(m,'note','note','',msg,auth.uid(),author,key) on conflict(actor_id,request_key) do nothing returning * into r;
 if r.id is null then select * into r from private.coco_module_events where actor_id=auth.uid() and request_key=key;end if;
 if r.module_id<>m or r.body<>msg or r.type<>'note' then raise exception 'REQUEST_KEY_REUSED';end if;
 return jsonb_build_object('id',r.id);
end $$;
revoke all on function private.coco_module_note(jsonb) from public,anon;
grant execute on function private.coco_module_note(jsonb) to authenticated;

create function public.coco_module_history(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare m text:=p_data->>'module_id';ctx jsonb;items jsonb;off integer:=coalesce((p_data->>'offset')::integer,0);
begin
 if not private.coco_module_allowed(m) then raise exception 'ROLE_NOT_ALLOWED';end if;
 ctx:=jsonb_build_object('kind','module','module_id',m,'number',(select label from private.coco_history_modules where module_id=m),'status','recorded','party','',
 'actor_id',auth.uid(),'can_note',private.erp_action_allowed(m,'edit') and (m<>'hr' or private.hr_admin()),'can_review',false,'stages','[]'::jsonb);
 if p_action='context' then return ctx;end if;
 if p_action='note' then return private.coco_module_note(p_data);end if;
 if p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 with visible as materialized(
  select * from private.coco_module_events where module_id=m
 ), grouped as (
  select min(id::text) id,max(created_at) at,actor_id,max(actor_name) actor_name,type,action,subject,body,source_type,source_id,source_label,source_email,proposal_id,
   count(*) action_count,jsonb_agg(references_list) refs,jsonb_agg(links) all_links
  from visible
  group by case when type='action' and proposal_id is null then transaction_id::text else id::text end,actor_id,type,action,subject,body,source_type,source_id,source_label,source_email,proposal_id
 ), paged as (select *,count(*) over() total from grouped order by at desc,id offset off limit 50)
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'at',p.at,'actor_id',p.actor_id,'actor_name',p.actor_name,'type',p.type,'action',p.action,'subject',p.subject,'body',p.body,
  'action_count',p.action_count,'source_type',p.source_type,'source_id',p.source_id,'source_label',p.source_label,'source_email',p.source_email,'proposal_id',p.proposal_id,'total',p.total,
  'references',(select coalesce(jsonb_agg(r),'[]') from jsonb_array_elements(p.refs) a cross join lateral jsonb_array_elements(a) r),
  'links',(select coalesce(jsonb_agg(distinct l),'[]') from jsonb_array_elements(p.all_links) a cross join lateral jsonb_array_elements(a) l where private.coco_module_allowed(l->>'module'))
 ) order by p.at desc,p.id),'[]') into items from paged p;
 return jsonb_build_object('context',ctx,'entries','[]'::jsonb,'history',items,'proposals','[]'::jsonb,'portraits','{}'::jsonb);
end $$;
revoke all on function public.coco_module_history(text,jsonb) from public,anon;
grant execute on function public.coco_module_history(text,jsonb) to authenticated;
notify pgrst,'reload schema';
