-- Read-only deployment checks. No product activation and no financial fixtures.
begin transaction read only;
select jsonb_build_object(
 'migration',(select jsonb_agg(jsonb_build_object('version',version,'name',name)) from supabase_migrations.schema_migrations where name='accounting_stock19_review'),
 'policies',(select count(*) from private.accounting_stock_policies),
 'reviews',(select count(*) from private.accounting_stock_reviews),
 'entries',(select count(*) from public.accounting_entries),
 'debit',(select sum(debit) from public.accounting_entry_lines),
 'credit',(select sum(credit) from public.accounting_entry_lines),
 'rls',(select jsonb_agg(jsonb_build_object('table',relname,'enabled',relrowsecurity)) from pg_class where oid in('private.accounting_stock_policies'::regclass,'private.accounting_stock_reviews'::regclass,'private.accounting_stock_review_entries'::regclass)),
 'acl',jsonb_build_object('anonymous_rpc',has_function_privilege('anon','public.gama_accounting_stock19(text,jsonb)','EXECUTE'),'authenticated_rpc',has_function_privilege('authenticated','public.gama_accounting_stock19(text,jsonb)','EXECUTE'),'authenticated_policies',has_table_privilege('authenticated','private.accounting_stock_policies','SELECT'),'authenticated_reviews',has_table_privilege('authenticated','private.accounting_stock_reviews','INSERT'),'anonymous_original_cost_engine',has_function_privilege('anon','private.erp_cost_post_before_standard(public.stock_movements)','EXECUTE')),
 'history',(select jsonb_agg(jsonb_build_object('table',h.table_name,'module',h.module_id,'capture_enabled',exists(select 1 from pg_trigger t where t.tgrelid=to_regclass(format('%I.%I',h.table_schema,h.table_name)) and t.tgname='coco_module_history' and t.tgenabled<>'D'))) from private.coco_history_tables h where h.table_name in('accounting_stock_policies','accounting_stock_reviews','stock_cost_books','stock_valuation_entries')),
 'rpc_is_invoker',(select not prosecdef from pg_proc where oid='public.gama_accounting_stock19(text,jsonb)'::regprocedure)
) as verification;
commit;
