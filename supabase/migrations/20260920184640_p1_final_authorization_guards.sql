-- Invitation checks the same module and action policy as the administration UI.
create function private.gama_identity_admin_allowed() returns boolean language sql stable security definer set search_path='' as $$select private.erp_module_allowed('users',array['administrador']) and private.erp_action_allowed('users','create')$$;
revoke all on function private.gama_identity_admin_allowed() from public,anon;grant execute on function private.gama_identity_admin_allowed() to authenticated;
create function public.gama_identity_admin_allowed() returns boolean language sql stable security invoker set search_path='' as $$select private.gama_identity_admin_allowed()$$;
revoke all on function public.gama_identity_admin_allowed() from public,anon;grant execute on function public.gama_identity_admin_allowed() to authenticated;
-- New command ledgers and approval tables also obey action restrictions.
do $$declare r record;begin for r in select * from (values
 ('sales_service_completions','sales-orders'),('purchase_service_acceptances','gamaPurchasesV14'),('product_lots','warehouses'),('stock_lot_movements','warehouses'),
 ('bank_match_groups','accounting'),('pm_cost_entries','projects'),('pm_baselines','projects'),('erp_approvals','access-settings'),('service_sla_rules','settings'),('document_approvals','documents')
 )x(tbl,module) loop
 if to_regclass('public.'||r.tbl) is not null and not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||r.tbl) and tgname='erp_action_guard') then execute format('create trigger erp_action_guard before insert or update or delete on public.%I for each row execute function private.erp_action_guard(%L)',r.tbl,r.module);end if;end loop;end $$;
-- A bank reconciliation validates a transaction even though it has no status field.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_bank_match(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'begin', 'begin if p_action in (''apply'',''cancel'') and not private.erp_action_allowed(''accounting'',''validate'') then raise exception ''ACTION_NOT_ALLOWED'';end if;');execute src;
 select pg_get_functiondef('private.gama_commercial_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'if p_action = ''payment'' then','if p_action = ''payment'' then if not private.erp_module_allowed(''payments'',array[''administrador'',''comercial'']) then raise exception ''ROLE_NOT_ALLOWED'';end if;');execute src;
end $$;
-- Legacy entry points with direct role lookups must also require the MFA level.
do $$declare r record;src text;begin for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='private' and p.proname like 'gama_%' and p.prosecdef and l.lanname='plpgsql' and p.prorettype<>'trigger'::regtype and has_function_privilege('authenticated',p.oid,'execute') loop
 src:=pg_get_functiondef(r.oid);src:=regexp_replace(src,'\mbegin\M','begin if auth.uid() is null or not private.erp_mfa_ok() then raise exception ''AUTH_OR_MFA_REQUIRED'';end if;','i');execute src;end loop;end $$;
-- Expose legacy privileged stock commands through invoker-only API wrappers.
-- The original implementations retain their authorization and transaction locks.
do $$declare r record;args text;argnames text;result_type text;internal_name text;begin
 for r in select p.*,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and p.proname in ('gama_count_generate_lines','gama_count_validate','gama_register_stock_movement','gama_stock_adjust','gama_stock_reserve','gama_stock_transfer') loop
 args:=pg_get_function_arguments(r.oid);result_type:=pg_get_function_result(r.oid);internal_name:='api_'||r.proname;
 select string_agg(format('%I',name),',' order by pos) into argnames from unnest(r.proargnames[1:r.pronargs]) with ordinality a(name,pos);
 execute format('alter function %s rename to %I',r.oid::regprocedure,internal_name);
 execute format('alter function public.%I(%s) set schema private',internal_name,pg_get_function_identity_arguments(r.oid));
 execute format('revoke all on function %s from public,anon;grant execute on function %s to authenticated',r.oid::regprocedure,r.oid::regprocedure);
 execute format('create function public.%I(%s) returns %s language sql security invoker set search_path='''' as %L',r.proname,args,result_type,format('select private.%I(%s)',internal_name,argnames));
 execute format('revoke all on function public.%I(%s) from public,anon;grant execute on function public.%I(%s) to authenticated',r.proname,pg_get_function_identity_arguments(r.oid),r.proname,pg_get_function_identity_arguments(r.oid));
 end loop;end $$;
-- Index the foreign keys introduced in this delivery, preserving existing indexes.
do $$declare r record;cols text;begin
 for r in select c.conrelid,c.conname,c.conkey,n.nspname,t.relname from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where c.contype='f' and n.nspname in ('public','private') and t.relname in ('erp_audit_events','erp_approvals','price_books','price_book_lines','supplier_product_offers','supplier_invoice_matches','supplier_invoice_match_lines','import_batches','import_batch_rows','customer_receipts','bank_match_groups','bank_match_banks','bank_match_sources','erp_access_reviews','hr_staffing_rules','hr_employee_skills','hr_lifecycle_tasks','tms_route_schedules','service_sla_rules','document_approvals') and not exists(select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid and i.indpred is null and i.indkey::smallint[] @> c.conkey) loop
 select string_agg(format('%I',a.attname),',' order by k.ord) into cols from unnest(r.conkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=r.conrelid and a.attnum=k.num;
 execute format('create index %I on %I.%I(%s)',left('p1_fk_'||r.conname,63),r.nspname,r.relname,cols);end loop;end $$;
-- Private ledgers are intentionally inaccessible except through checked commands.
do $$declare r record;begin for r in select tablename from pg_tables where schemaname='private' loop execute format('alter table private.%I enable row level security',r.tablename);end loop;end $$;
-- Keep narrow directory/catalogue projections behind explicit caller filters,
-- while making the public views invoker-only (no RLS-bypassing view ownership).
do $$declare v text;src text;cols text;projection text;previous_path text:=current_setting('search_path');begin
 perform set_config('search_path','',true);
 foreach v in array array['crm_team','catalog_products'] loop
 src:=rtrim(pg_get_viewdef(('public.'||v)::regclass,true),E';\n ');
 select string_agg(format('%I %s',attname,format_type(atttypid,atttypmod)),',' order by attnum) into cols from pg_attribute where attrelid=('public.'||v)::regclass and attnum>0 and not attisdropped;
 select string_agg(format('%I::%s as %I',attname,format_type(atttypid,atttypmod),attname),',' order by attnum) into projection from pg_attribute where attrelid=('public.'||v)::regclass and attnum>0 and not attisdropped;
 execute format('create function private.%I() returns table(%s) language sql stable security definer set search_path='''' as %L','api_'||v,cols,src);
 execute format('revoke all on function private.%I() from public,anon;grant execute on function private.%I() to authenticated','api_'||v,'api_'||v);
 execute format('create or replace view public.%I with(security_invoker=true,security_barrier=true) as select %s from private.%I()',v,projection,'api_'||v);
 end loop;perform set_config('search_path',previous_path,true);end $$;
-- Warehouse aggregates and historical physical valuation exclude services.
do $$declare src text;begin
 select pg_get_functiondef('public.gama_inventory_snapshot(uuid,date)'::regprocedure) into src;src:=replace(src,'where p.active','where p.active and p.product_kind=''goods''');execute src;
 select pg_get_functiondef('private.gama_historical_stock(timestamptz)'::regprocedure) into src;src:=replace(src,'where p.created_at<=p_asof','where p.created_at<=p_asof and p.product_kind=''goods''');execute src;
 select pg_get_functiondef('private.gama_count_create_core(jsonb)'::regprocedure) into src;src:=replace(src,'where l.warehouse_id=c.warehouse_id','where p.product_kind=''goods'' and l.warehouse_id=c.warehouse_id');execute src;
end $$;
-- Product references share the barcode namespace, including generated references.
create function private.erp_reference_barcode_namespace() returns trigger language plpgsql security definer set search_path='' as $$declare code text:=nullif(btrim(new.reference),'');begin
 if code is null or (tg_op='UPDATE' and new.reference is not distinct from old.reference) then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('barcode:'||code,0));
 if exists(select 1 from public.products where id<>new.id and barcode=code) or exists(select 1 from public.product_units where barcode=code) or exists(select 1 from public.fulfillment_packages where barcode=code) then raise exception 'BARCODE_ALREADY_USED';end if;return new;end $$;
revoke all on function private.erp_reference_barcode_namespace() from public,anon,authenticated;
create trigger erp_reference_barcode_namespace after insert or update on public.products for each row execute function private.erp_reference_barcode_namespace();
