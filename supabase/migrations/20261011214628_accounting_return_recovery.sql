-- Direct refunds reverse sales/tax; refunds following a credit clear that credit.
-- Original source dates and posted journals are retained during recovery.
create function private.gama_accounting_refund_post(p_id uuid,p_date date) returns uuid
language plpgsql security definer set search_path='' as $$
declare r record;cfg public.company_settings;eid uuid;bank uuid;credited numeric;prior numeric;covered numeric;direct numeric;split jsonb;lines jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended('return_refund'||p_id::text,0));
 select id into eid from public.accounting_entries where source_type='return_refund' and source_id=p_id;
 if eid is not null then return eid;end if;
 select f.*,o.customer_id,o.number return_number,c.name customer_name into r from public.return_refunds f join public.return_orders o on o.id=f.return_id left join public.customers c on c.id=o.customer_id where f.id=p_id;
 if not found then return null;end if;
 perform 1 from public.return_orders where id=r.return_id for update;
 select account_id into bank from public.financial_accounts where id=r.financial_account_id;
 if bank is null then return null;end if;
 select * into cfg from public.company_settings where id;
 select coalesce(sum(amount),0) into credited from public.return_credits where return_id=r.return_id;
 select coalesce(sum(amount),0) into prior from public.return_refunds where return_id=r.return_id and (created_at,id)<(r.created_at,r.id);
 covered:=least(r.amount,greatest(credited-prior,0));direct:=r.amount-covered;
 if covered>0 and exists(select 1 from public.return_credits k where k.return_id=r.return_id and not exists(select 1 from public.accounting_entries e where e.source_type='return_credit' and e.source_id=k.id and e.status in ('posted','reversed'))) then raise exception 'REFUND_CREDIT_UNPOSTED';end if;
 lines:=jsonb_build_array(jsonb_build_object('account_id',bank,'financial_account_id',r.financial_account_id,'label',r.return_number,'credit',r.amount));
 if covered>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.receivable_account_id,'label',r.return_number,'debit',covered,'partner_type','customer','partner_id',r.customer_id));end if;
 if direct>0 then
  split:=private.gama_return_split(r.return_id,direct);
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.sales_account_id,'label',r.return_number,'debit',(split->>'net')::numeric),jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','debit',(split->>'tax')::numeric));
 end if;
 return private.gama_accounting_book(case when r.method ~* '(efectivo|cash|caja)' then 'CAJ' else 'BAN' end,p_date,coalesce(r.reference,r.return_number),'return_refund',r.id,r.customer_name,lines);
end $$;

create function private.gama_accounting_credit_refund_guard(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare rid uuid;begin
 select return_id into rid from public.return_credits where id=p_id;
 perform 1 from public.return_orders where id=rid for update;
 if exists(select 1 from public.return_refunds f join public.accounting_entries e on e.source_type='return_refund' and e.source_id=f.id join public.accounting_entry_lines l on l.entry_id=e.id join public.accounting_accounts a on a.id=l.account_id where f.return_id=rid and e.status in ('posted','reversed') and a.type='income' and l.debit>0) then raise exception 'RETURN_REFUND_ALREADY_REVERSED_SALE';end if;
end $$;

alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_refund_fix;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$begin
 if p_source_type='return_refund' then return private.gama_accounting_refund_post(p_source_id,(select paid_at from public.return_refunds where id=p_source_id));end if;
 if p_source_type='return_credit' and not exists(select 1 from public.accounting_entries where source_type=p_source_type and source_id=p_source_id) then perform private.gama_accounting_credit_refund_guard(p_source_id);end if;
 return private.gama_accounting_post_before_refund_fix(p_source_type,p_source_id);
end $$;
alter function private.gama_accounting_post_at(text,uuid,date) rename to gama_accounting_post_at_before_refund_fix;
create function private.gama_accounting_post_at(p_source_type text,p_source_id uuid,p_date date) returns uuid
language plpgsql security definer set search_path='' as $$begin
 if p_source_type='return_refund' then return private.gama_accounting_refund_post(p_source_id,p_date);end if;
 if p_source_type='return_credit' and not exists(select 1 from public.accounting_entries where source_type=p_source_type and source_id=p_source_id) then perform private.gama_accounting_credit_refund_guard(p_source_id);end if;
 return private.gama_accounting_post_at_before_refund_fix(p_source_type,p_source_id,p_date);
end $$;

-- Search the complete goods catalogue without an inaccessible 1000-product cap.
alter function private.gama_accounting_audit_read(text,jsonb) rename to gama_accounting_audit_read_before_product_search;
create function private.gama_accounting_audit_read(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;search text:=btrim(coalesce(p_data->>'stock_search',''));off integer:=greatest(coalesce((p_data->>'stock_offset')::integer,0),0);begin
 result:=private.gama_accounting_audit_read_before_product_search(p_action,p_data);
 if p_action='context' then result:=result||jsonb_build_object(
  'stock_product_total',(select count(*) from public.products where product_kind='goods' and (search='' or concat_ws(' ',name,reference) ilike '%'||search||'%')),
  'stock_products',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,purchase_price from public.products where product_kind='goods' and (search='' or concat_ws(' ',name,reference) ilike '%'||search||'%') order by name,id limit 100 offset off)x),'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_accounting_refund_post(uuid,date),private.gama_accounting_credit_refund_guard(uuid),private.gama_accounting_post_before_refund_fix(text,uuid),private.gama_accounting_post(text,uuid),private.gama_accounting_post_at_before_refund_fix(text,uuid,date),private.gama_accounting_post_at(text,uuid,date),private.gama_accounting_audit_read_before_product_search(text,jsonb),private.gama_accounting_audit_read(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
