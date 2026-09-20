-- Complete the user-facing access review and prevent stale policy writes.
create function private.gama_save_action_permissions(p_role text,p_rows jsonb,p_expected jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_rows jsonb;item jsonb;begin
 if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.role_module_access where role=p_role for update;if not found then raise exception 'PROFILE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(a) order by a.module),'[]') into current_rows from public.erp_action_permissions a where role=p_role;
 if current_rows is distinct from (select coalesce(jsonb_agg(v order by v->>'module'),'[]') from jsonb_array_elements(p_expected)v) then raise exception 'ACCESS_SETTINGS_CHANGED';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>100 then raise exception 'INVALID_PERMISSIONS';end if;
 for item in select value from jsonb_array_elements(p_rows) loop
 if coalesce(item->>'module','') not in ('mainmenu','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing','sav','documents') then raise exception 'MODULE_NOT_FOUND';end if;
 insert into public.erp_action_permissions(role,module,allow_create,allow_edit,allow_delete,allow_validate,allow_export,updated_at,updated_by)
 values(p_role,item->>'module',(item->>'allow_create')::boolean,(item->>'allow_edit')::boolean,(item->>'allow_delete')::boolean,(item->>'allow_validate')::boolean,(item->>'allow_export')::boolean,now(),auth.uid())
 on conflict(role,module) do update set allow_create=excluded.allow_create,allow_edit=excluded.allow_edit,allow_delete=excluded.allow_delete,allow_validate=excluded.allow_validate,allow_export=excluded.allow_export,updated_at=now(),updated_by=auth.uid();
 end loop;return jsonb_build_object('saved',true);
end $$;
revoke all on function private.gama_save_action_permissions(text,jsonb,jsonb) from public,anon;grant execute on function private.gama_save_action_permissions(text,jsonb,jsonb) to authenticated;
create function public.gama_save_action_permissions(p_role text,p_rows jsonb,p_expected jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_save_action_permissions(p_role,p_rows,p_expected)$$;
revoke all on function public.gama_save_action_permissions(text,jsonb,jsonb) from public,anon;grant execute on function public.gama_save_action_permissions(text,jsonb,jsonb) to authenticated;
-- RPC only: a table upsert cannot bypass the version check.
revoke insert,update on public.erp_action_permissions from authenticated;

do $$declare src text;begin
 select pg_get_functiondef('private.gama_access_review(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'''modules'',(select', '''actions'',(select coalesce(jsonb_agg(to_jsonb(a) order by a.role,a.module),''[]'') from public.erp_action_permissions a),''modules'',(select');
 
 src:=replace(src,'elsif p_action=''confirm'' then','elsif p_action=''confirm'' then if p_data->''expected'' is distinct from result then raise exception ''ACCESS_SETTINGS_CHANGED'';end if;');
 execute src;
end $$;
create function private.gama_customer_credit_save(p_id uuid,p_limit numeric,p_hold text,p_expected jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare c public.customers;begin
 if not private.erp_module_allowed('clients',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=p_id for update;if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 if jsonb_build_object('credit_limit',c.credit_limit,'credit_hold_reason',c.credit_hold_reason) is distinct from p_expected then raise exception 'CUSTOMER_CHANGED';end if;
 update public.customers set credit_limit=p_limit,credit_hold_reason=nullif(btrim(p_hold),'') where id=p_id returning * into c;return to_jsonb(c);
end $$;
revoke all on function private.gama_customer_credit_save(uuid,numeric,text,jsonb) from public,anon;grant execute on function private.gama_customer_credit_save(uuid,numeric,text,jsonb) to authenticated;
create function public.gama_customer_credit_save(p_id uuid,p_limit numeric,p_hold text,p_expected jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_customer_credit_save(p_id,p_limit,p_hold,p_expected)$$;
revoke all on function public.gama_customer_credit_save(uuid,numeric,text,jsonb) from public,anon;grant execute on function public.gama_customer_credit_save(uuid,numeric,text,jsonb) to authenticated;

-- Cache only committed results; the key binds the actor and the whole command.
-- Read and cancellation calls still run their normal authorization on every call.
do $$declare r record;declaration text;core_call text;key_expr text;predicate text;extra text;begin
 for r in select * from (values
 ('gama_count_create','jsonb','p_data jsonb','count-create','warehouses','array[''administrador'',''almacenero'']','true','nullif(p_data->>''request_key'','''')::uuid'),
 ('gama_project_finance','text,jsonb','p_action text,p_data jsonb','project-finance','projects','array[''administrador'',''comercial'',''almacenero'']','p_action in (''cost'',''baseline'')','nullif(p_data->>''id'','''')::uuid'),
 ('gama_bank_match','text,jsonb','p_action text,p_data jsonb','bank-match','accounting','array[''administrador'',''comercial'']','p_action=''apply''','nullif(p_data->>''request_key'','''')::uuid'),
 ('gama_receipt_action','text,jsonb','p_action text,p_data jsonb','receipt-followup','payments','array[''administrador'',''comercial'']','p_action=''followup'' and nullif(p_data->>''id'','''') is null','nullif(p_data->>''request_key'','''')::uuid')
 )x(fn,signature,args,domain,module,roles,predicate,key_expression) loop
 execute format('alter function private.%I(%s) rename to %I',r.fn,r.signature,r.fn||'_core');
 execute format('revoke all on function private.%I(%s) from public,anon,authenticated',r.fn||'_core',r.signature);
 core_call:=format('private.%I(%s)',r.fn||'_core',case when r.signature='jsonb' then 'p_data' else 'p_action,p_data' end);
 extra:=case when r.fn='gama_project_finance' then 'if not private.pm_manage((p_data->>''project_id'')::uuid) then raise exception ''ROLE_NOT_ALLOWED'';end if;' when r.fn='gama_bank_match' then 'if private.gama_accounting_rights()->>''scope''<>''all'' or not coalesce((private.gama_accounting_rights()->>''validate'')::boolean,false) then raise exception ''ROLE_NOT_ALLOWED'';end if;' else '' end;
 execute format($fn$create function private.%I(%s) returns jsonb language plpgsql security definer set search_path='' as $body$
 declare k uuid;prior private.command_receipts;result jsonb;payload jsonb;begin
 if not private.erp_module_allowed(%L,%s) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not(%s) then return %s;end if;
 %s
 k:=%s;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 payload:=p_data%s;
 perform pg_advisory_xact_lock(hashtextextended(%L||k::text,0));
 select * into prior from private.command_receipts where domain=%L and request_key=k;
 if found then if prior.actor_id<>auth.uid() or prior.payload is distinct from payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 result:=%s;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values(%L,k,auth.uid(),payload,result);return result;
 end $body$ $fn$,r.fn,r.args,r.module,r.roles,r.predicate,core_call,extra,r.key_expression,case when r.signature='jsonb' then '' else '||jsonb_build_object(''_action'',p_action)' end,r.domain,r.domain,core_call,r.domain);
 execute format('revoke all on function private.%I(%s) from public,anon;grant execute on function private.%I(%s) to authenticated',r.fn,r.signature,r.fn,r.signature);
 -- Recompile SQL wrappers after the rename so their cached function OID is current.
 execute format('create or replace function public.%I(%s) returns jsonb language sql security invoker set search_path='''' as %L',r.fn,replace(r.args,'p_data jsonb','p_data jsonb default ''{}'''),format('select private.%I(%s)',r.fn,case when r.signature='jsonb' then 'p_data' else 'p_action,p_data' end));
 end loop;
end $$;

-- New direct customer payments must identify the actual active financial account.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_commercial_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by)', 'request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by,financial_account_id)');
 src:=replace(src,'coalesce(p_data->>''notes'',''''),v_uid)', 'coalesce(p_data->>''notes'',''''),v_uid,nullif(p_data->>''financial_account_id'','''')::uuid)');
 src:=replace(src,'if p_action = ''payment'' then', 'if p_action = ''payment'' then
 if not exists(select 1 from public.financial_accounts f join public.company_settings c on c.id where f.id=nullif(p_data->>''financial_account_id'','''')::uuid and f.active and f.account_id is not null and f.currency=c.currency) then raise exception ''FINANCIAL_ACCOUNT_REQUIRED'';end if;');
 src:=replace(src,'if v_payment.invoice_id <> v_invoice.id or v_payment.amount <> (p_data->>''amount'')::numeric then', 'if v_payment.invoice_id <> v_invoice.id or v_payment.amount <> (p_data->>''amount'')::numeric or v_payment.financial_account_id is distinct from nullif(p_data->>''financial_account_id'','''')::uuid or v_payment.created_by<>auth.uid() or v_payment.method is distinct from p_data->>''method'' or v_payment.paid_at is distinct from coalesce(nullif(p_data->>''paid_at'','''')::date,current_date) or v_payment.reference is distinct from coalesce(p_data->>''reference'','''') then');
 execute src;
end $$;

-- Legacy single-line matching enforces the same amount, source and account invariants.
create or replace function private.erp_reconcile_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare bank public.bank_transactions;source record;begin
 select * into bank from public.bank_transactions where id=new.bank_transaction_id for update;
 if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 if new.match_type='customer_payment' then select amount,financial_account_id,status into source from public.external_invoice_payments where id=new.match_id and receipt_id is null for update;
 elsif new.match_type='supplier_payment' then select -amount amount,financial_account_id,status into source from public.supplier_invoice_payments where id=new.match_id for update;
 elsif new.match_type='expense' then select -amount_total amount,financial_account_id,case when status='posted' then 'confirmed' else status end status into source from public.expenses where id=new.match_id for update;
 else raise exception 'INVALID_MATCH_TYPE';end if;
 if not found or source.status<>'confirmed' or source.financial_account_id is distinct from bank.financial_account_id or source.amount is distinct from bank.amount or new.amount is distinct from bank.amount then raise exception 'MATCH_AMOUNT_OR_ACCOUNT_MISMATCH';end if;
 if exists(select 1 from public.reconciliations r where r.match_type=new.match_type and r.match_id=new.match_id and r.bank_transaction_id<>new.bank_transaction_id) then raise exception 'SOURCE_ALREADY_MATCHED';end if;
 if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.bank_transaction_id and g.cancelled_at is null) or exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind=new.match_type and s.source_id=new.match_id and g.cancelled_at is null) then raise exception 'ALREADY_GROUPED';end if;
 return new;end $$;
revoke all on function private.erp_reconcile_guard() from public,anon,authenticated;

-- Reversed entries remain part of the ledger alongside their reversal; excluding
-- the original would count the reversal twice in balance and profit reports.
do $$declare r record;src text;begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('gama_accounting_reports','gama_accounting_project_pl') loop
 src:=pg_get_functiondef(r.oid);src:=replace(src,'e.status=''posted'' and e.entry_date','e.status in (''posted'',''reversed'') and e.entry_date');src:=replace(src,'en.status=''posted''','en.status in (''posted'',''reversed'')');execute src;end loop;
end $$;
-- Cash reporting recognizes deposits on receipt, not again on invoice allocation.
do $$declare r record;src text;before text;after text;begin
 for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('gama_accounting_reports','gama_accounting_action','gama_company_dashboard') loop
 src:=pg_get_functiondef(r.oid);
 if r.proname='gama_accounting_reports' then
 before:=$old$select to_char(p.paid_at,'YYYY-MM') m,p.amount cin,0::numeric cout from public.external_invoice_payments p
      where p.status='confirmed' and p.paid_at between d1 and d2$old$;
 after:=$new$select to_char(p.paid_at,'YYYY-MM') m,p.amount cin,0::numeric cout from public.external_invoice_payments p
      where p.status='confirmed' and p.receipt_id is null and p.paid_at between d1 and d2
     union all select to_char(r.paid_at,'YYYY-MM'),r.amount,0 from public.customer_receipts r where r.status='confirmed' and r.paid_at between d1 and d2$new$;
 src:=replace(src,before,after);
 elsif r.proname='gama_company_dashboard' then
 before:=$old$select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today$old$;
 after:=$new$select sum(p.amount) from (select amount,financial_account_id,status,paid_at from public.external_invoice_payments where receipt_id is null union all select amount,financial_account_id,status,paid_at from public.customer_receipts)p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today$new$;
 src:=replace(src,before,after);
 elsif r.proname='gama_accounting_action' then
 before:=$old$from public.external_invoice_payments
      where status='confirmed' and paid_at between date_trunc('month',today)::date and today$old$;
 after:=$new$from (select amount,status,paid_at from public.external_invoice_payments where receipt_id is null union all select amount,status,paid_at from public.customer_receipts)cash_receipts
      where status='confirmed' and paid_at between date_trunc('month',today)::date and today$new$;
 src:=replace(src,before,after);
 end if;execute src;
 end loop;
end $$;
