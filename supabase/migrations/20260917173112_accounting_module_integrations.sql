-- Financial alerts join the existing live feed instead of opening a second inbox.
do $patch$
declare src text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 if position('payable_overdue' in src)>0 then return;end if;
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'payable_overdue:'||p.id,'payable_overdue',p.id,'supplier_invoice',p.number,p.supplier_name,
  'Factura de proveedor vencida','Vencimiento: '||p.due_date||' · saldo: '||round(p.balance,2),
  p.due_date::timestamp at time zone 'America/Guayaquil',3,true,false
 from private.gama_payables p where p.payment_status='overdue'
 union all
 select 'expense_no_receipt:'||e.id,'expense_no_receipt',e.id,'expense',e.reference,coalesce(s.name,'—'),
  'Gasto sin justificante','Importe: '||round(e.amount_total,2)||' · '||e.description,
  e.created_at,1,true,false
 from public.expenses e left join public.suppliers s on s.id=e.supplier_id
 where e.status='posted' and not exists(select 1 from public.expense_receipts x where x.expense_id=e.id)
 union all
 select 'bank_unmatched:'||t.id,'bank_unmatched',t.id,'bank_transaction',coalesce(t.reference,t.description),f.name,
  'Movimiento bancario sin conciliar','Importe: '||round(t.amount,2)||' · '||t.value_date,
  t.imported_at,1,true,false
 from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id
 where t.status='unmatched'
 union all
 select 'entry_unbalanced:'||e.id,'entry_unbalanced',e.id,'accounting_entry',e.number,coalesce(e.memo,'—'),
  'Asiento contable descuadrado','Diferencia: '||round((select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0)
   from public.accounting_entry_lines l where l.entry_id=e.id),2),
  e.created_at,3,true,false
 from public.accounting_entries e where e.status='posted'
 and (select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0) from public.accounting_entry_lines l where l.entry_id=e.id)<>0
 $extra$;
end $patch$;

-- The assistant answers from the same tables, under the same permissions.
do $patch$
declare src text;marker text:='$catalog$::jsonb;';
begin
 select pg_get_functiondef('public.gama_ai_catalog()'::regprocedure) into src;
 if position(marker in src)=0 then raise exception 'Unexpected assistant catalogue';end if;
 if position('accounting_entries' in src)>0 then return;end if;
 execute replace(src,marker,'$catalog$::jsonb||'||quote_literal($j$[
 {"table":"accounting_accounts","columns":["id","code","name","type","active","is_system"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_journals","columns":["id","code","name","kind","active"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_entries","columns":["id","number","journal_id","entry_date","reference","source_type","source_id","status","memo","created_at"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_entry_lines","columns":["id","entry_id","account_id","label","debit","credit","partner_type","partner_id","project_id"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_periods","columns":["id","period_start","period_end","status","closed_at"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_taxes","columns":["id","name","code","rate","kind","country","active"],"pk":["id"],"module":"accounting"},
 {"table":"financial_accounts","columns":["id","name","kind","bank_name","currency","opening_balance","active"],"pk":["id"],"module":"accounting"},
 {"table":"bank_transactions","columns":["id","financial_account_id","value_date","reference","description","amount","status"],"pk":["id"],"module":"accounting"},
 {"table":"reconciliations","columns":["id","bank_transaction_id","match_type","match_id","amount","matched_at"],"pk":["id"],"module":"accounting"},
 {"table":"expenses","columns":["id","reference","expense_date","supplier_id","category_id","description","amount_untaxed","tax_amount","amount_total","currency","payment_method","financial_account_id","project_id","status"],"pk":["id"],"module":"accounting"},
 {"table":"expense_categories","columns":["id","name","account_id","active"],"pk":["id"],"module":"accounting"},
 {"table":"supplier_invoices","columns":["id","number","supplier_id","purchase_order_id","issue_date","due_date","subtotal","tax","total","status","project_id"],"pk":["id"],"module":"accounting"},
 {"table":"supplier_invoice_payments","columns":["id","supplier_invoice_id","financial_account_id","paid_at","amount","method","reference","status"],"pk":["id"],"module":"accounting"},
 {"table":"company_settings","columns":["id","currency","country","fiscal_year_start_month"],"pk":["id"],"module":"accounting"}
]$j$)||'::jsonb;');
end $patch$;
select 'integrations' as status;
