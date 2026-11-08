

create function private.gama_invoice_deferrals_post(p_entry uuid,p_source text,p_invoice uuid) returns void
language plpgsql security definer set search_path='' as $$
declare items jsonb;x jsonb;k text;cfg private.accounting_invoice_deferral_settings;src uuid;cnt integer;max_net numeric;num text;result jsonb;p jsonb;
begin
 if p_entry is null or p_source not in('sales_invoice','supplier_invoice') then return;end if;
 if p_source='sales_invoice' then
  select document_snapshot->'lines',number into items,num from public.external_invoices where id=p_invoice;
  k:='deferred_revenue';
 else select deferral_lines,number into items,num from public.supplier_invoices where id=p_invoice;k:='deferred_expense';end if;
 if items is null or items='[]'::jsonb then return;end if;
 if p_source='sales_invoice' and not exists(select 1 from jsonb_array_elements(items)v where nullif(v->>'deferred_start','') is not null or nullif(v->>'deferred_end','') is not null) then return;end if;
 select count(*),min(l.id::text)::uuid,sum(abs(l.debit-l.credit)) into cnt,src,max_net from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id
 where l.entry_id=p_entry and a.type=case when k='deferred_expense' then 'expense' else 'income' end and case when k='deferred_expense' then l.debit>l.credit else l.credit>l.debit end;
 if cnt<>1 then raise exception 'INVOICE_DEFERRAL_SOURCE_INVALID';end if;
 items:=private.gama_invoice_deferral_lines(items,p_source='sales_invoice',max_net);
 select * into cfg from private.accounting_invoice_deferral_settings where kind=k and enabled for share;
 if not found then raise exception 'INVOICE_DEFERRAL_CONFIG_REQUIRED';end if;
 -- The existing APIs check the human's current module, MFA, create/validate
 -- permissions, lock dates and source capacity. No synthetic identity is used.
 for x in select value from jsonb_array_elements(items) loop
  p:=jsonb_build_object('kind',k,'name',left(num||' · '||(x->>'name'),160),'journal_id',cfg.journal_id,'source_line_id',src,
   'amount',x->>'amount','starts_on',x->>'deferred_start','ends_on',x->>'deferred_end','deferral_account_id',cfg.deferral_account_id,
   'computation',cfg.computation,'mode',cfg.mode,'automatic',cfg.mode='individual','request_key',gen_random_uuid());
  result:=private.gama_accounting_plans('save',p);
  update private.accounting_plans set invoice_id=case when p_source='sales_invoice' then p_invoice end,
   supplier_invoice_id=case when p_source='supplier_invoice' then p_invoice end,invoice_line_key=x->>'key' where id=(result->>'id')::uuid;
  perform private.gama_accounting_plans('activate',jsonb_build_object('id',result->>'id','request_key',gen_random_uuid()));
 end loop;
end $$;
revoke all on function private.gama_invoice_deferrals_post(uuid,text,uuid) from public,anon,authenticated,service_role;
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure),'FUNCTION private.gama_accounting_post(', 'FUNCTION private.gama_accounting_post_before_invoice_deferrals(');end $$;
revoke all on function private.gama_accounting_post_before_invoice_deferrals(text,uuid) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare eid uuid;begin
 if p_source_type not in('sales_invoice','supplier_invoice') then return private.gama_accounting_post_before_invoice_deferrals(p_source_type,p_source_id);end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-post:'||p_source_type||':'||p_source_id,0));
 select id into eid from public.accounting_entries where source_type=p_source_type and source_id=p_source_id and status<>'reversed';
 if eid is not null then return eid;end if;
 eid:=private.gama_accounting_post_before_invoice_deferrals(p_source_type,p_source_id);
 perform private.gama_invoice_deferrals_post(eid,p_source_type,p_source_id);return eid;
end $$;
revoke all on function private.gama_accounting_post(text,uuid) from public,anon,authenticated,service_role;

-- Carry dates through canonical creators before their atomic posting triggers.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure);
 anchor:='''sales_unit_label'',l.sales_unit_label,''sales_unit_factor'',l.sales_unit_factor';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_SALES_ANCHOR';end if;
 execute replace(s,anchor,anchor||',''deferred_start'',x->>''deferred_start'',''deferred_end'',x->>''deferred_end''');
 s:=pg_get_functiondef('private.gama_accounting_banking(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 anchor:='elsif p_action=''supplier_invoice_save'' then';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_BILL_ANCHOR';end if;
 s:=replace(s,anchor,anchor||E'\n  if key is not null then perform pg_advisory_xact_lock(hashtextextended(''invoice-deferral-bill:''||key,0));end if;\n  if exists(select 1 from public.supplier_invoices b where b.request_key=key and b.deferral_lines is distinct from private.gama_invoice_deferral_lines(coalesce(p_data->''deferral_lines'',''[]''::jsonb),false,(p_data->>''subtotal'')::numeric)) then raise exception ''REQUEST_KEY_CONFLICT'';end if;');
 anchor:='due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by)';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_BILL_COLUMNS';end if;
 s:=replace(s,anchor,'due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by,deferral_lines)');
 anchor:='nullif(p_data->>''project_id'','''')::uuid,p_data->>''notes'',key,u) returning id into eid;';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_BILL_VALUES';end if;
 execute replace(s,anchor,'nullif(p_data->>''project_id'','''')::uuid,p_data->>''notes'',key,u,coalesce(p_data->''deferral_lines'',''[]''::jsonb)) returning id into eid;');
 s:=pg_get_functiondef('private.gama_flow_finance(text,jsonb)'::regprocedure);
 anchor:='notes=p_data->>''notes'',source_reviewed=false,updated_at=now()';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_DRAFT_ANCHOR';end if;
 execute replace(s,anchor,'notes=p_data->>''notes'',deferral_lines=coalesce(p_data->''deferral_lines'',bill.deferral_lines),source_reviewed=false,updated_at=now()');
end $$;