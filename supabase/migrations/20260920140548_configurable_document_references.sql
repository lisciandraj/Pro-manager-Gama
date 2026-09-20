-- Canonical, immutable ERP numbers. External fiscal/bank numbers and printed barcodes remain separate.
create table public.erp_reference_formats(
 kind text primary key,module_id text not null,label_es text not null,
 prefix text not null unique check(prefix ~ '^[A-Z]{3}$'),default_prefix text not null check(default_prefix ~ '^[A-Z]{3}$'),
 source_table text,number_column text,kind_value text,
 version integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid references auth.users(id)
);
create index erp_reference_formats_updated_by on public.erp_reference_formats(updated_by);
alter table public.erp_reference_formats enable row level security;
revoke all on public.erp_reference_formats from public,anon,authenticated;
grant select on public.erp_reference_formats to authenticated;
create policy reference_formats_read on public.erp_reference_formats for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active));
insert into public.erp_reference_formats(kind,module_id,label_es,prefix,source_table,number_column,kind_value,default_prefix)
 select *,prefix from (values
('dossier','dossier-flow','Expediente','EXP',null,null,null),
('request','quotes','Solicitud de cliente','SOL','customer_requests',null,null),
('quote','quotes','Cotización','COT','invoices','invoice_number',null),
('order','sales-orders','Pedido de venta','PED','sales_orders','number',null),
('preparation','order-preparation','Preparación','PRE','fulfillment_preparations','number',null),
('package','order-preparation','Paquete','PAQ','fulfillment_packages',null,null),
('shipment','sales-orders','Envío','ENV','sales_deliveries','number',null),
('delivery','tms','Entrega','ENT','tms_deliveries',null,null),
('proof','tms','Prueba de entrega','PDE','tms_proofs',null,null),
('invoice','payments','Factura','FAC','external_invoices',null,null),
('collection','payments','Cobro','COB','external_invoice_payments',null,null),
('return','returns','Devolución','DEV','return_orders','number',null),
('purchase','gamaPurchasesV14','Orden de compra','OCO','purchase_orders','order_number',null),
('inventory','warehouses','Inventario físico','INV','inventory_counts','reference',null),
('reservation','warehouses','Reserva de existencias','RES','stock_reservations',null,null),
('movement','movement','Movimiento de existencias','MOV','stock_movements',null,null),
('opportunity','crm','Oportunidad','OPO','crm_opportunities','reference',null),
('project','projects','Proyecto','PRO','pm_projects','reference',null),
('vehicle','fleet','Vehículo','VEH','fleet_vehicles','reference',null),
('hr_document','hr','Documento de recursos humanos','DRH','hr_documents',null,null),
('payroll','hr','Nómina','NOM','hr_payroll',null,null),
('service','sav','Servicio posventa','SPV','service_tickets',null,null),
('document','documents','Documento','DOC','business_documents',null,null),
('entry','accounting','Asiento contable','ASI','accounting_entries','number',null),
('expense','accounting','Gasto','GAS','expenses','reference',null),
('supplier_invoice','accounting','Factura de proveedor','FPR','supplier_invoices',null,null),
('supplier_payment','accounting','Pago a proveedor','PPR','supplier_invoice_payments',null,null),
('credit','returns','Nota de crédito','NCR','return_credits','number',null),
('refund','returns','Reembolso','REE','return_refunds',null,null),
('route','tms','Ruta','RUT','tms_routes',null,null),
('article','knowledge','Artículo de documentación','ART','knowledge_articles',null,null),
('project_phase','projects','Fase','FAS','pm_items','reference','phase'),
('project_task','projects','Tarea','TAR','pm_items','reference','task'),
('project_milestone','projects','Hito','HIT','pm_items','reference','milestone'),
('project_work_package','projects','Paquete de trabajo','PTR','pm_items','reference','work_package'),
('project_deliverable','projects','Entregable','ETG','pm_items','reference','deliverable'),
('project_risk','projects','Riesgo','RIE','pm_items','reference','risk'),
('project_issue','projects','Incidencia','INC','pm_items','reference','issue'),
('project_change','projects','Cambio','CAM','pm_items','reference','change'),
('project_decision','projects','Decisión','DEC','pm_items','reference','decision'),
('project_lesson','projects','Lección aprendida','LEC','pm_items','reference','lesson'),
('project_assumption','projects','Supuesto','SUP','pm_items','reference','assumption'),
('project_dependency','projects','Dependencia','DEP','pm_items','reference','dependency'),
('project_stakeholder','projects','Interesado','INT','pm_items','reference','stakeholder'),
('project_raci','projects','Responsabilidad RACI','RAC','pm_items','reference','raci')
) x(kind,module_id,label_es,prefix,source_table,number_column,kind_value);
create table private.erp_reference_counters(kind text primary key references public.erp_reference_formats(kind),last_number bigint not null default 0 check(last_number between 0 and 99999999));
create table private.erp_reference_prefixes(prefix text primary key,kind text not null references public.erp_reference_formats(kind));
create index erp_reference_prefixes_kind on private.erp_reference_prefixes(kind);
create table private.erp_issued_references(
 kind text not null references public.erp_reference_formats(kind),document_key text not null,
 serial_number bigint not null check(serial_number between 1 and 99999999),reference text not null unique check(reference ~ '^[A-Z]{3}-[0-9]{8}$'),
 legacy_reference text,issued_at timestamptz not null default now(),primary key(kind,document_key),unique(kind,serial_number)
);
alter table private.erp_reference_counters enable row level security;
alter table private.erp_reference_prefixes enable row level security;
alter table private.erp_issued_references enable row level security;
revoke all on private.erp_reference_counters,private.erp_reference_prefixes,private.erp_issued_references from public,anon,authenticated;
insert into private.erp_reference_counters(kind) select kind from public.erp_reference_formats;
insert into private.erp_reference_prefixes select prefix,kind from public.erp_reference_formats;

create function private.erp_issue_reference(k text,doc_key text,preferred bigint default null,legacy text default null) returns text
language plpgsql security definer set search_path='' as $$
declare n bigint;p text;result text;begin
 -- Same transaction lock as dossier registration: one lock order for every generator and settings update.
 perform pg_advisory_xact_lock(724613092);
 select reference into result from private.erp_issued_references where kind=k and document_key=doc_key;
 if found then return result;end if;
 select prefix into p from public.erp_reference_formats where kind=k;
 if p is null or doc_key is null then raise exception 'REFERENCE_KIND_INVALID';end if;
 select last_number into n from private.erp_reference_counters where kind=k for update;
 if preferred between 1 and 99999999 and not exists(select 1 from private.erp_issued_references where kind=k and serial_number=preferred) then n:=preferred;else n:=n+1;end if;
 if n>99999999 then raise exception 'REFERENCE_SEQUENCE_EXHAUSTED';end if;
 result:=p||'-'||lpad(n::text,8,'0');
 insert into private.erp_issued_references(kind,document_key,serial_number,reference,legacy_reference) values(k,doc_key,n,result,nullif(legacy,result));
 update private.erp_reference_counters set last_number=greatest(last_number,n) where kind=k;
 return result;
end $$;
revoke all on function private.erp_issue_reference(text,text,bigint,text) from public,anon,authenticated;

-- Settings writes are atomic, admin-only, and reject stale edits and ambiguous prefix reuse.
create function private.erp_save_reference_formats(changes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb;r public.erp_reference_formats;p text;begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'REFERENCE_ADMIN_REQUIRED' using errcode='42501';end if;
 if jsonb_typeof(changes)<>'array' or jsonb_array_length(changes)>100 then raise exception 'REFERENCE_FORMAT_INVALID';end if;
 perform pg_advisory_xact_lock(724613092);
 for x in select value from jsonb_array_elements(changes) loop
 select * into r from public.erp_reference_formats where kind=x->>'kind' for update;
 if not found or r.version is distinct from (x->>'version')::integer then raise exception 'REFERENCE_FORMAT_STALE';end if;
 p:=upper(btrim(x->>'prefix'));
 if p is null or p !~ '^[A-Z]{3}$' then raise exception 'REFERENCE_FORMAT_INVALID';end if;
 if exists(select 1 from private.erp_reference_prefixes where prefix=p and kind<>r.kind) then raise exception 'REFERENCE_PREFIX_USED';end if;
 insert into private.erp_reference_prefixes(prefix,kind) values(p,r.kind) on conflict do nothing;
 update public.erp_reference_formats set prefix=p,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where kind=r.kind;
 end loop;
 return (select jsonb_agg(to_jsonb(f) order by module_id,label_es) from public.erp_reference_formats f);
end $$;
create function public.gama_save_reference_formats(p_changes jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.erp_save_reference_formats(p_changes)$$;
revoke all on function private.erp_save_reference_formats(jsonb),public.gama_save_reference_formats(jsonb) from public,anon;
grant execute on function private.erp_save_reference_formats(jsonb),public.gama_save_reference_formats(jsonb) to authenticated;

alter table public.gama_document_references add column dossier_label text,add column legacy_reference text;
alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
alter table public.gama_document_references add constraint gama_document_references_table_name_check check(table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders','purchase_orders','inventory_counts','stock_reservations','stock_movements','crm_opportunities','pm_projects','fleet_vehicles','hr_documents','hr_payroll','service_tickets','business_documents','accounting_entries','expenses','supplier_invoices','supplier_invoice_payments','return_credits','return_refunds','tms_routes','knowledge_articles','pm_items'));
-- Reserve the highest existing dossier number before allocating replacement numbers for repeated steps.
update private.erp_reference_counters set last_number=coalesce((select max(dossier_number) from public.gama_document_references),0)
 where kind='dossier' or kind in (select kind from public.erp_reference_formats where source_table in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders'));
do $$declare d record;r record;k text;ref text;label text;begin
 for d in select distinct dossier_number from public.gama_document_references order by dossier_number loop
 label:=private.erp_issue_reference('dossier',d.dossier_number::text,d.dossier_number,'EXP-'||lpad(d.dossier_number::text,8,'0'));
 end loop;
 for r in select * from public.gama_document_references order by ordinal,node_index loop
 select kind into k from public.erp_reference_formats where source_table=r.table_name;
 ref:=private.erp_issue_reference(k,r.table_name||'/'||r.document_id,r.dossier_number,r.document_reference);
 label:=private.erp_issue_reference('dossier',r.dossier_number::text,r.dossier_number);
 update public.gama_document_references set document_reference=ref,legacy_reference=nullif(r.document_reference,ref),dossier_label=label where table_name=r.table_name and document_id=r.document_id;
 end loop;
end $$;
-- Dossier membership may merge, but issued document numbers never change.
do $$declare s text;a integer;begin
 s:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 a:=position(' with numbered as' in s);
 if a=0 then raise exception 'REFERENCE_REGISTER_ANCHOR';end if;
 s:=left(s,a-1)||$tail$
 update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;
end $function$;
$tail$;
 execute s;
end $$;

create function private.erp_stamp_reference() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb:=to_jsonb(new);f public.erp_reference_formats;key text:=coalesce(j->>'id',j->>'delivery_id');ref text;begin
 select * into f from public.erp_reference_formats where source_table=tg_table_name and (kind_value is null or kind_value=j->>'kind');
 if not found then raise exception 'REFERENCE_KIND_INVALID';end if;
 if tg_table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders') then
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
end $$;
revoke all on function private.erp_stamp_reference() from public,anon,authenticated;

-- Backfill only identifiers, without replaying financial/stock workflows.
-- Restore each user trigger to its original mode; foreign-key triggers stay enabled.
-- UUID relationships, amounts, statuses, external numbers and package barcodes remain intact.
do $$declare t text;r record;f public.erp_reference_formats;k text;key text;ref text;n bigint;legacy text;triggers jsonb;tr jsonb;begin
 for t in select distinct source_table from public.erp_reference_formats where source_table is not null loop
 execute format('alter table public.%I add column erp_reference text',t);
 select jsonb_agg(jsonb_build_object('name',tgname,'mode',tgenabled)) into triggers from pg_trigger where tgrelid=('public.'||t)::regclass and not tgisinternal and tgenabled<>'D';
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.%I disable trigger %I',t,tr->>'name');end loop;
 for r in execute format('select to_jsonb(x) j from public.%I x order by %I',t,case when t='tms_proofs' then 'delivery_id' else 'id' end) loop
 select * into f from public.erp_reference_formats where source_table=t and (kind_value is null or kind_value=r.j->>'kind');
 key:=coalesce(r.j->>'id',r.j->>'delivery_id');legacy:=coalesce(r.j->>f.number_column,r.j->>'reference',r.j->>'number');
 select document_reference into ref from public.gama_document_references where table_name=t and document_id=key::uuid;
 if ref is null then
 n:=null;if legacy ~ '[0-9]{1,8}$' then n:=substring(legacy from '([0-9]{1,8})$')::bigint;end if;
 ref:=private.erp_issue_reference(f.kind,t||'/'||key,n,legacy);
 insert into public.gama_document_references(table_name,document_id,dossier_number,document_reference,legacy_reference) values(t,key::uuid,0,ref,nullif(legacy,ref));
 end if;
 execute format('update public.%I set erp_reference=$1%s where %I=$2',t,case when t='external_invoices' and r.j->>'document_kind'='internal' then ', number=$1' when f.number_column is null then '' else ', '||quote_ident(f.number_column)||'=$1' end,case when t='tms_proofs' then 'delivery_id' else 'id' end) using ref,key::uuid;
 end loop;
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.%I enable %s trigger %I',t,case tr->>'mode' when 'A' then 'always' when 'R' then 'replica' else '' end,tr->>'name');end loop;
 execute format('create trigger zz_erp_reference before insert or update on public.%I for each row execute function private.erp_stamp_reference()',t);
 -- Imported external identifiers can retain their original numbers; the generated ERP reference always follows the strict format.
 execute format('alter table public.%I add constraint erp_reference_format check(erp_reference ~ ''^[A-Z]{3}-[0-9]{8}$'')',t);
 end loop;
end $$;
-- Preserve source RLS for every registered document, including HR and confidential attachments.
alter policy dossier_reference_read on public.gama_document_references using(case table_name
 when 'customer_requests' then exists(select 1 from public.customer_requests x where x.id=document_id)
 when 'invoices' then exists(select 1 from public.invoices x where x.id=document_id)
 when 'sales_orders' then exists(select 1 from public.sales_orders x where x.id=document_id)
 when 'fulfillment_preparations' then exists(select 1 from public.fulfillment_preparations x where x.id=document_id)
 when 'fulfillment_packages' then exists(select 1 from public.fulfillment_packages x where x.id=document_id)
 when 'sales_deliveries' then exists(select 1 from public.sales_deliveries x where x.id=document_id)
 when 'tms_deliveries' then exists(select 1 from public.tms_deliveries x where x.id=document_id)
 when 'tms_proofs' then exists(select 1 from public.tms_proofs x where x.delivery_id=document_id)
 when 'external_invoices' then exists(select 1 from public.external_invoices x where x.id=document_id)
 when 'external_invoice_payments' then exists(select 1 from public.external_invoice_payments x where x.id=document_id)
 when 'return_orders' then exists(select 1 from public.return_orders x where x.id=document_id)
 when 'purchase_orders' then exists(select 1 from public.purchase_orders x where x.id=document_id)
 when 'inventory_counts' then exists(select 1 from public.inventory_counts x where x.id=document_id)
 when 'stock_reservations' then exists(select 1 from public.stock_reservations x where x.id=document_id)
 when 'stock_movements' then exists(select 1 from public.stock_movements x where x.id=document_id)
 when 'crm_opportunities' then exists(select 1 from public.crm_opportunities x where x.id=document_id)
 when 'pm_projects' then exists(select 1 from public.pm_projects x where x.id=document_id)
 when 'fleet_vehicles' then exists(select 1 from public.fleet_vehicles x where x.id=document_id)
 when 'hr_documents' then exists(select 1 from public.hr_documents x where x.id=document_id)
 when 'hr_payroll' then exists(select 1 from public.hr_payroll x where x.id=document_id)
 when 'service_tickets' then exists(select 1 from public.service_tickets x where x.id=document_id)
 when 'business_documents' then exists(select 1 from public.business_documents x where x.id=document_id)
 when 'accounting_entries' then exists(select 1 from public.accounting_entries x where x.id=document_id)
 when 'expenses' then exists(select 1 from public.expenses x where x.id=document_id)
 when 'supplier_invoices' then exists(select 1 from public.supplier_invoices x where x.id=document_id)
 when 'supplier_invoice_payments' then exists(select 1 from public.supplier_invoice_payments x where x.id=document_id)
 when 'return_credits' then exists(select 1 from public.return_credits x where x.id=document_id)
 when 'return_refunds' then exists(select 1 from public.return_refunds x where x.id=document_id)
 when 'tms_routes' then exists(select 1 from public.tms_routes x where x.id=document_id)
 when 'knowledge_articles' then exists(select 1 from public.knowledge_articles x where x.id=document_id)
 when 'pm_items' then exists(select 1 from public.pm_items x where x.id=document_id)
 else false end);
alter table public.gama_document_references add constraint canonical_reference_format check(document_reference='' or document_reference ~ '^[A-Z]{3}-[0-9]{8}$');
grant select(erp_reference) on public.tms_proofs,public.return_credits to authenticated;
-- Table defaults no longer issue a second, unused number. The trusted BEFORE trigger assigns it.
alter table public.invoices alter column invoice_number drop default;
alter table public.sales_orders alter column number drop default;
alter table public.fulfillment_preparations alter column number drop default;
alter table public.sales_deliveries alter column number drop default;
alter table public.return_orders alter column number drop default;
alter table public.purchase_orders alter column order_number drop default;
alter table public.inventory_counts alter column reference drop default;
alter table public.crm_opportunities alter column reference drop default;
alter table public.pm_projects alter column reference drop default;
alter table public.fleet_vehicles alter column reference drop default;
alter table public.accounting_entries alter column number drop default;
alter table public.expenses alter column reference drop default;
alter table public.return_credits alter column number drop default;

do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);
 if position('si.number,' in s)=0 then raise exception 'REFERENCE_PAYABLES_ANCHOR';end if;
 -- Keep the existing column order so dependent views/functions remain valid.
 s:=regexp_replace(s,'(\s+FROM public.supplier_invoices si)',', si.erp_reference\1');
 execute 'create or replace view private.gama_payables with(security_invoker=true) as '||s;
end $$;
