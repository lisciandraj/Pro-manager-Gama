-- Read-only verification. Never inserts a plan, invoice, payment or entry.
begin transaction read only;
select jsonb_build_object(
 'entries',(select count(*) from public.accounting_entries),
 'lines',(select count(*) from public.accounting_entry_lines),
 'debit',(select sum(debit) from public.accounting_entry_lines),
 'credit',(select sum(credit) from public.accounting_entry_lines),
 'unbalanced_entries',(select count(*) from (
   select e.id from public.accounting_entries e left join public.accounting_entry_lines l on l.entry_id=e.id
   where e.status='posted' group by e.id having count(l.id)<2 or coalesce(sum(l.debit-l.credit),0)<>0
 ) x),
 'banks',(select jsonb_agg(x) from (select status,count(*) n,sum(amount) amount from public.bank_transactions group by status order by status)x),
 'customer_invoices',(select count(*) from public.external_invoices),
 'customer_payments',(select count(*) from public.external_invoice_payments),
 'supplier_invoices',(select count(*) from public.supplier_invoices),
 'supplier_payments',(select count(*) from public.supplier_invoice_payments),
 'receipts',(select count(*) from public.customer_receipts),
 'plans',(select count(*) from private.accounting_plans),
 'migration',(select jsonb_agg(jsonb_build_object('version',version,'name',name)) from supabase_migrations.schema_migrations where name='accounting_plans'),
 'scheduler',(select jsonb_agg(jsonb_build_object('schedule',schedule,'active',active)) from cron.job where jobname='coco-accounting-plans'),
 'rls',(select jsonb_agg(jsonb_build_object('table',relname,'enabled',relrowsecurity)) from pg_class where oid in ('private.accounting_plans'::regclass,'private.accounting_plan_items'::regclass,'private.accounting_plan_runs'::regclass)),
 'acl',jsonb_build_object(
   'anonymous_rpc',has_function_privilege('anon','public.gama_accounting_plans(text,jsonb)','EXECUTE'),
   'authenticated_rpc',has_function_privilege('authenticated','public.gama_accounting_plans(text,jsonb)','EXECUTE'),
   'authenticated_scheduler',has_function_privilege('authenticated','private.gama_accounting_plans_tick()','EXECUTE'),
   'authenticated_table',has_table_privilege('authenticated','private.accounting_plans','SELECT'),
   'service_scheduler',has_function_privilege('service_role','private.gama_accounting_plans_tick()','EXECUTE'))
) verification;
commit;
