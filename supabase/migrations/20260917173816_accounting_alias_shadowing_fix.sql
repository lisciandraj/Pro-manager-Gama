-- A table alias that matches a declared record shadows it in plpgsql, so the
-- query reads an unassigned record instead of the row. Rename the aliases.
do $patch$
declare src text;old text;
begin
 select pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure) into src;
 old:='  select si.*,s.name supplier_name into si from public.supplier_invoices si
   join public.suppliers s on s.id=si.supplier_id where si.id=p_source_id;';
 if position(old in src)=0 then raise exception 'Unexpected supplier invoice lookup';end if;
 src:=replace(src,old,'  select b.*,s.name supplier_name into si from public.supplier_invoices b
   join public.suppliers s on s.id=b.supplier_id where b.id=p_source_id;');
 old:='  select p.*,si.number invoice_number,si.supplier_id,s.name supplier_name into sp
   from public.supplier_invoice_payments p join public.supplier_invoices si on si.id=p.supplier_invoice_id
   join public.suppliers s on s.id=si.supplier_id where p.id=p_source_id;';
 if position(old in src)=0 then raise exception 'Unexpected supplier payment lookup';end if;
 src:=replace(src,old,'  select p.*,b.number invoice_number,b.supplier_id,s.name supplier_name into sp
   from public.supplier_invoice_payments p join public.supplier_invoices b on b.id=p.supplier_invoice_id
   join public.suppliers s on s.id=b.supplier_id where p.id=p_source_id;');
 execute src;
end $patch$;

do $patch$
declare src text;old text;
begin
 select pg_get_functiondef('private.gama_accounting_action2(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure) into src;
 old:='  with f as (select * from private.gama_receivables r
   where (coalesce(p_data->>''status'',''open'')=''all''
    or (coalesce(p_data->>''status'',''open'')=''open'' and r.payment_status not in (''paid'',''cancelled''))
    or r.payment_status=p_data->>''status'')
   and (nullif(p_data->>''customer_id'','''') is null or r.customer_id=(p_data->>''customer_id'')::uuid)
   and (search='''' or concat_ws('' '',r.number,r.external_number,r.customer_name) ilike ''%''||search||''%''))';
 if position(old in src)=0 then raise exception 'Unexpected receivables query';end if;
 src:=replace(src,old,'  with f as (select * from private.gama_receivables q
   where (coalesce(p_data->>''status'',''open'')=''all''
    or (coalesce(p_data->>''status'',''open'')=''open'' and q.payment_status not in (''paid'',''cancelled''))
    or q.payment_status=p_data->>''status'')
   and (nullif(p_data->>''customer_id'','''') is null or q.customer_id=(p_data->>''customer_id'')::uuid)
   and (search='''' or concat_ws('' '',q.number,q.external_number,q.customer_name) ilike ''%''||search||''%''))');
 execute src;
end $patch$;

do $patch$
declare src text;old text;
begin
 select pg_get_functiondef('private.gama_accounting_action4(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure) into src;
 old:='  return coalesce((select jsonb_agg(to_jsonb(c) order by c.sort_order,c.name) from public.expense_categories c),''[]''::jsonb);';
 if position(old in src)=0 then raise exception 'Unexpected categories query';end if;
 src:=replace(src,old,'  return coalesce((select jsonb_agg(to_jsonb(k) order by k.sort_order,k.name) from public.expense_categories k),''[]''::jsonb);');
 execute src;
end $patch$;
select 'alias-fix' as status;
