-- Run after the two additive migrations. Read-only: no statement or policy is created.
select jsonb_build_object(
 'checked_at',now(),
 'tables',(select jsonb_agg(jsonb_build_object('name',c.relname,'rls',c.relrowsecurity,
   'anon',has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE'),
   'authenticated',has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'),
   'service_role',has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')) order by c.relname)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private'
   and c.relname in('accounting_bank_import_policies','accounting_bank_import_postings')),
 'new_rows',jsonb_build_object('policies',(select count(*) from private.accounting_bank_import_policies),
   'postings',(select count(*) from private.accounting_bank_import_postings)),
 'facades',(select jsonb_agg(jsonb_build_object('name',p.proname,'invoker',not p.prosecdef,
   'anon',has_function_privilege('anon',p.oid,'EXECUTE'),
   'authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),
   'service_role',has_function_privilege('service_role',p.oid,'EXECUTE'),
   'empty_search_path',p.proconfig@>array['search_path=""']) order by p.proname)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
   and p.proname in('gama_accounting_bank_import','gama_accounting_journals')),
 'helpers',(select jsonb_agg(jsonb_build_object('name',p.proname,
   'client_can_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),
   'anon_can_execute',has_function_privilege('anon',p.oid,'EXECUTE')) order by p.proname)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'
   and p.proname in('gama_bank_import_post','gama_bank_import_capture','gama_payment_mode_settle_before_import','gama_accounting_action_before_import_ledger')),
 'bank_triggers',(select jsonb_agg(jsonb_build_object('name',tgname,'enabled',tgenabled='O') order by tgname)
   from pg_trigger where tgrelid='public.bank_transactions'::regclass and tgname in('zz_bank_import_capture','aa_bank_import_immutable')),
 'history',(select jsonb_agg(jsonb_build_object('name',h.table_name,'parent',h.parent_table,'parent_column',h.parent_column,
   'capture',exists(select 1 from pg_trigger t where t.tgrelid=to_regclass(h.table_schema||'.'||h.table_name) and t.tgname='coco_module_history' and t.tgenabled='O')) order by h.table_name)
   from private.coco_history_tables h where h.table_name in('accounting_bank_import_policies','accounting_bank_import_postings')),
 'allocation_fk_index',(select pg_get_indexdef(indexrelid) from pg_index where indexrelid=to_regclass('private.accounting_match_allocation_group_source')),
 'migrations',(select jsonb_agg(jsonb_build_object('version',version,'name',name,'statement_count',cardinality(statements),
   'bytes',octet_length(statements[1]),'sha256',encode(sha256(convert_to(statements[1],'UTF8')),'hex')) order by version)
   from supabase_migrations.schema_migrations where name in('accounting_bank_import_ledger','accounting_journal_dashboard'))
) verification;
