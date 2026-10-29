-- Read-only checks after accounting_configuration_parity. No test business writes.
select jsonb_build_object(
 'checked_at',now(),
 'currency',(select currency from public.company_settings where id),
 'entries',(select count(*) from public.accounting_entries),
 'lines',(select count(*) from public.accounting_entry_lines),
 'debit',(select sum(debit) from public.accounting_entry_lines),
 'credit',(select sum(credit) from public.accounting_entry_lines),
 'unbalanced_entries',(select count(*) from (
  select e.id from public.accounting_entries e left join public.accounting_entry_lines l on l.entry_id=e.id
  where e.status in ('posted','reversed') group by e.id having count(l.id)<2 or coalesce(sum(l.debit-l.credit),0)<>0
 )x),
 'accounts',(select count(*) from public.accounting_accounts),
 'classified_accounts',(select count(*) from public.accounting_accounts where account_type is not null),
 'banks',(select jsonb_agg(x) from (select status,count(*) n,sum(amount) amount from public.bank_transactions group by status order by status)x),
 'customer_invoices',(select count(*) from public.external_invoices),
 'customer_payments',(select count(*) from public.external_invoice_payments),
 'supplier_invoices',(select count(*) from public.supplier_invoices),
 'supplier_payments',(select count(*) from public.supplier_invoice_payments),
 'receipts',(select count(*) from public.customer_receipts),
 'configuration',jsonb_build_object(
  'groups',(select count(*) from private.accounting_groups),
  'numbering',(select count(*) from private.accounting_numbering),
  'counters',(select count(*) from private.accounting_number_counters),
  'locks',(select count(*) from private.accounting_lock_dates),
  'exceptions',(select count(*) from private.accounting_lock_exceptions),
  'adjustments',(select count(*) from private.accounting_date_adjustments)),
 'migration',(select jsonb_agg(jsonb_build_object('version',version,'name',name,'statement_count',cardinality(statements),
  'bytes',octet_length(statements[1]),'sha256',encode(sha256(convert_to(statements[1],'UTF8')),'hex')))
  from supabase_migrations.schema_migrations where name='accounting_configuration_parity'),
 'tables',(select jsonb_agg(jsonb_build_object('table',relname,'rls',relrowsecurity,
  'anon',has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE'),
  'authenticated',has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE'),
  'service_role',has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE')) order by relname)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and
  relname in ('accounting_groups','accounting_numbering','accounting_number_counters','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments')),
 'rpc',jsonb_build_object(
  'anonymous',has_function_privilege('anon','public.gama_accounting_configuration(text,jsonb)','EXECUTE'),
  'authenticated',has_function_privilege('authenticated','public.gama_accounting_configuration(text,jsonb)','EXECUTE'),
  'public_invoker',(select not prosecdef from pg_proc where oid='public.gama_accounting_configuration(text,jsonb)'::regprocedure),
  'private_definer',(select prosecdef from pg_proc where oid='private.gama_accounting_configuration(text,jsonb)'::regprocedure),
  'empty_search_path',(select bool_and(proconfig@>array['search_path=""']) from pg_proc where oid in
   ('public.gama_accounting_configuration(text,jsonb)'::regprocedure,'private.gama_accounting_configuration(text,jsonb)'::regprocedure)),
  'authenticated_post_trigger',has_function_privilege('authenticated','private.gama_accounting_configuration_post()','EXECUTE')),
 'posting_trigger',(select tgenabled from pg_trigger where tgrelid='public.accounting_entries'::regclass and tgname='zzz_accounting_configuration_post'),
 'history_tables',(select count(*) from private.coco_history_tables where table_schema='private' and module_id='accounting' and
  table_name in ('accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments')),
 'history_capture_triggers',(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='private' and c.relname in ('accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments')
  and t.tgname='coco_module_history' and t.tgenabled='O')
) verification;
