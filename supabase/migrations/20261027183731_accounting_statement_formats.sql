-- Structured statements use the existing bank transaction and posting engine.
create table private.accounting_statement_sources (
 id uuid primary key references public.bank_transactions(id) on delete restrict,
 financial_account_id uuid not null references public.financial_accounts(id),
 format text not null check(format in('ofx','qif','camt','coda','xlsx')),
 source_account text not null check(length(source_account) between 1 and 100),
 source_uid text not null check(length(source_uid) between 1 and 180),
 source_row jsonb not null,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 unique(financial_account_id,format,source_account,source_uid)
);
create index accounting_statement_sources_actor on private.accounting_statement_sources(created_by);
alter table private.accounting_statement_sources enable row level security;
revoke all on private.accounting_statement_sources from public,anon,authenticated;
create function private.gama_bank_statement_import(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();fid uuid:=nullif(p_data->>'financial_account_id','')::uuid;fmt text:=p_data->>'format';acct text:=btrim(p_data->>'source_account');ccy text:=p_data->>'currency';
 key uuid:=nullif(p_data->>'request_key','')::uuid;x jsonb;normalized jsonb;existing private.accounting_statement_sources;receipt private.accounting_audit_commands;payload jsonb:=p_data-'request_key';pending jsonb:='[]';result jsonb;bid uuid;n integer:=0;skipped integer:=0;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) or not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 if fmt is null or fmt not in('ofx','qif','camt','coda','xlsx') or coalesce(length(acct),0) not between 1 and 100 then raise exception 'STATEMENT_FORMAT_INVALID';end if;
 if not exists(select 1 from public.financial_accounts f join public.company_settings c on c.id where f.id=fid and f.active and f.account_id is not null and f.kind in('bank','card') and f.currency=ccy and c.currency=ccy) then raise exception 'STATEMENT_CURRENCY_MISMATCH';end if;
 if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 1000 then raise exception 'BANK_IMPORT_LINES_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('statement-format-command:'||key::text,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'statement_import' or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-statement-import:'||key::text,0));
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||fid::text,0));
 for x in select value from jsonb_array_elements(p_data->'rows') loop
  if jsonb_typeof(x->'amount') is distinct from 'number' or coalesce(x->>'value_date','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(length(x->>'source_uid'),0) not between 1 and 180 or length(coalesce(x->>'reference',''))>180 or length(coalesce(x->>'description',''))>300 then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
  if (x->>'amount')::numeric=0 or abs((x->>'amount')::numeric)>999999999999.99 or (x->>'amount')::numeric<>round((x->>'amount')::numeric,2) or (x->>'value_date')::date>(now() at time zone private.erp_timezone())::date then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
  normalized:=jsonb_build_object('value_date',(x->>'value_date')::date,'amount',(x->>'amount')::numeric,'reference',coalesce(x->>'reference',''),'description',coalesce(x->>'description','—'),'source_uid',x->>'source_uid');
  if exists(select 1 from jsonb_array_elements(pending) p where p->>'source_uid'=x->>'source_uid') then raise exception 'STATEMENT_DUPLICATE_ID';end if;
  select * into existing from private.accounting_statement_sources where financial_account_id=fid and format=fmt and source_account=acct and source_uid=x->>'source_uid';
  if found then if existing.source_row is distinct from normalized then raise exception 'STATEMENT_SOURCE_CONFLICT';end if;skipped:=skipped+1;else pending:=pending||jsonb_build_array(normalized);end if;
 end loop;
 -- Different source identities may not silently collapse into the legacy natural key.
 if exists(select 1 from jsonb_array_elements(pending) p group by p->>'value_date',coalesce(p->>'reference',''),(p->>'amount')::numeric having count(*)>1) then raise exception 'STATEMENT_AMBIGUOUS_ROWS';end if;
 if jsonb_array_length(pending)>0 then
  for x in select value from jsonb_array_elements(pending) loop
   select b.id into bid from public.bank_transactions b where b.financial_account_id=fid and b.value_date=(x->>'value_date')::date and coalesce(b.reference,'')=coalesce(x->>'reference','') and b.amount=(x->>'amount')::numeric;
   if bid is not null and exists(select 1 from private.accounting_statement_sources where id=bid) then raise exception 'STATEMENT_AMBIGUOUS_ROWS';end if;
  end loop;
  result:=private.gama_bank_invoice_action('import',jsonb_build_object('request_key',key,'financial_account_id',fid,'rows',pending));n:=(result->>'imported')::integer;
  for x in select value from jsonb_array_elements(pending) loop
   select b.id into bid from public.bank_transactions b where b.financial_account_id=fid and b.value_date=(x->>'value_date')::date and coalesce(b.reference,'')=coalesce(x->>'reference','') and b.amount=(x->>'amount')::numeric;
   if bid is null then raise exception 'STATEMENT_IMPORT_INCOMPLETE';end if;
   insert into private.accounting_statement_sources(id,financial_account_id,format,source_account,source_uid,source_row,created_by) values(bid,fid,fmt,acct,x->>'source_uid',x,auth.uid());
  end loop;
 end if;
 result:=jsonb_build_object('imported',n,'reused',jsonb_array_length(p_data->'rows')-n,'batch',key);
 insert into private.accounting_audit_commands(request_key,actor,action,payload,result) values(key,auth.uid(),'statement_import',payload,result);return result;
end $$;
revoke all on function private.gama_bank_statement_import(jsonb) from public,anon;
grant execute on function private.gama_bank_statement_import(jsonb) to authenticated;
create function public.gama_bank_statement_import(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_bank_statement_import(p_data)$$;
revoke all on function public.gama_bank_statement_import(jsonb) from public,anon;
grant execute on function public.gama_bank_statement_import(jsonb) to authenticated;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_table,parent_column)
values('accounting_statement_sources','accounting','Origen del extracto bancario','private','id','bank_transactions','id');
create trigger coco_module_history after insert or update or delete on private.accounting_statement_sources for each row execute function private.coco_capture_module_event();
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);
 if strpos(s,'''accounting_bank_import_policies''')=0 then raise exception 'STATEMENT_HISTORY_ANCHOR_MISSING';end if;
 execute replace(s,'''accounting_bank_import_policies''','''accounting_bank_import_policies'',''accounting_statement_sources''');
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_statement_formats(');end $$;
revoke all on function private.coco_history_typed_link_before_statement_formats(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_statement_formats(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if p_table='accounting_statement_sources' then
  if not private.coco_history_record_visible(p_table,p_id,null) then return null;end if;
  return private.coco_history_typed_link_before_statement_formats('accounting','bank_transactions',p_id,p_reference);
 end if;return private.coco_history_typed_link_before_statement_formats(p_module,p_table,p_id,p_reference);
end $$;

-- Supply the actual selected bank currency to every import preview.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_statement_formats(');end $$;
revoke all on function private.gama_accounting_action_before_statement_formats(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_accounting_action_before_statement_formats(p_action,p_data);
 if p_action='bank_list' then r:=jsonb_set(r,'{accounts}',coalesce((select jsonb_agg(a||jsonb_build_object('currency',f.currency) order by ord) from jsonb_array_elements(r->'accounts') with ordinality x(a,ord) join public.financial_accounts f on f.id=(a->>'id')::uuid),'[]'));end if;return r;
end $$;
