-- Online SRI verification is service-only. Browsers post only a verified receipt.
create table public.accounting_received_sri (
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.external_invoices(id),
 access_key text not null check(access_key ~ '^[0-9]{49}$'),issuer_ruc text not null check(issuer_ruc ~ '^[0-9]{13}$'),
 number text not null check(number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$'),issued_on date not null,
 amount numeric(18,2) not null check(amount>0),lines jsonb not null check(jsonb_typeof(lines)='array'),
 authorized_at timestamptz not null,xml_path text not null,xml_sha256 text not null check(xml_sha256 ~ '^[a-f0-9]{64}$'),
 verified_by uuid not null references public.profiles(id),verified_at timestamptz not null default now(),
 withholding_id uuid references public.accounting_withholdings(id),unique(access_key,invoice_id)
);
alter table public.accounting_received_sri enable row level security;
revoke all on public.accounting_received_sri from public,anon,authenticated;
grant select on public.accounting_received_sri to authenticated;
grant all on public.accounting_received_sri to service_role;
create policy received_sri_read on public.accounting_received_sri for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create index received_sri_invoice on public.accounting_received_sri(invoice_id);
create index received_sri_verifier on public.accounting_received_sri(verified_by);
create index received_sri_withholding on public.accounting_received_sri(withholding_id) where withholding_id is not null;

create function private.gama_ec_received(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare d public.accounting_received_sri;r record;lines jsonb:='[]';x jsonb;result jsonb;amount numeric:=0;base_ir numeric:=0;base_iva numeric:=0;expected numeric;account uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or private.current_user_role()<>'administrador' or not private.erp_module_allowed('accounting',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then return jsonb_build_object('rows',coalesce((select jsonb_agg(z) from (select d.id,d.invoice_id,d.access_key,d.issuer_ruc,d.number,d.issued_on,d.amount,d.withholding_id,v.number invoice_number from public.accounting_received_sri d join public.external_invoices v on v.id=d.invoice_id order by d.verified_at desc,d.id limit 100)z),'[]'));end if;
 if p_action<>'post' then raise exception 'UNKNOWN_ACTION';end if;
 if not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into d from public.accounting_received_sri where id=(p_data->>'id')::uuid for update;
 if d.id is null then raise exception 'SRI_RECEIVED_VERIFICATION_REQUIRED';end if;
 if d.withholding_id is not null then return jsonb_build_object('id',d.withholding_id,'amount',d.amount);end if;
 select * into r from private.gama_receivables where id=d.invoice_id and payment_status<>'cancelled';
 if r.id is null or r.identification<>d.issuer_ruc then raise exception 'SRI_RECEIVED_PARTY_MISMATCH';end if;
 if jsonb_array_length(d.lines) not between 1 and 50 then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 for x in select value from jsonb_array_elements(d.lines) loop
 if x->>'tax_kind' not in ('income','vat') or x->>'tax_kind' is null then raise exception 'SRI_RECEIVED_TAX_UNSUPPORTED';end if;
 if (x->>'base') is null or (x->>'rate') is null or (x->>'base')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'rate')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'base')::numeric<=0 or (x->>'rate')::numeric not between 0.001 and 100 or coalesce(x->>'code','') !~ '^[0-9]{1,5}$' then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 expected:=round((x->>'base')::numeric*(x->>'rate')::numeric/100,2);
 if expected is null or expected<=0 or expected is distinct from (x->>'amount')::numeric then raise exception 'SRI_WITHHOLDING_TOTAL_MISMATCH';end if;
 amount:=amount+expected;
 if x->>'tax_kind'='income' then base_ir:=base_ir+(x->>'base')::numeric;else base_iva:=base_iva+(x->>'base')::numeric;end if;
 account:=nullif(p_data->>(case when x->>'tax_kind'='income' then 'income_account_id' else 'vat_account_id' end),'')::uuid;
 perform private.gama_ec_account(account,'asset');
 lines:=lines||jsonb_build_array(jsonb_build_object('tax_kind',x->>'tax_kind','code',x->>'code','base',x->'base','rate',x->'rate','account_id',account));
 end loop;
 if amount<>d.amount or base_ir>r.subtotal or base_iva>r.tax then raise exception 'SRI_RECEIVED_INVOICE_MISMATCH';end if;
 result:=private.gama_accounting_ec('withholding_post',jsonb_build_object('request_key',d.id,'side','customer','invoice_id',d.invoice_id,'issued_on',d.issued_on,'number',d.number,'authorization_number',d.access_key,'evidence','XML recibido verificado en línea ante el SRI: '||d.access_key,'lines',lines));
 update public.accounting_received_sri set withholding_id=(result->>'id')::uuid where id=d.id;return result;
end $$;
revoke all on function private.gama_ec_received(text,jsonb) from public,anon;
grant execute on function private.gama_ec_received(text,jsonb) to authenticated;
create function public.gama_ec_received(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_ec_received(p_action,p_data)$$;
revoke all on function public.gama_ec_received(text,jsonb) from public,anon;
grant execute on function public.gama_ec_received(text,jsonb) to authenticated;

create function private.gama_ec_received_match(p_ruc text,p_number text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or private.current_user_role()<>'administrador' or not private.erp_module_allowed('accounting',array['administrador']) or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_ruc !~ '^[0-9]{13}$' or p_number !~ '^[0-9]{15}$' then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 select jsonb_agg(jsonb_build_object('id',v.id,'number',v.number,'fiscal_number',coalesce(v.external_number,f.document_number,v.number),'issuer_ruc',c.tax_id,'customer_identification',k.identification,'issue_date',coalesce(v.external_issue_date,v.issue_date),'subtotal',v.subtotal,'tax',v.tax)) into rows
 from public.external_invoices v join public.sales_orders o on o.id=v.order_id join public.customers k on k.id=o.customer_id cross join public.company_settings c
 left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=v.id
 where c.id and c.configured and c.country='EC' and k.identification=p_ruc and v.fiscal_status<>'cancelled'
 and replace(coalesce(v.external_number,f.document_number,v.number),'-','')=p_number;
 if rows is null then raise exception 'SRI_RECEIVED_INVOICE_NOT_FOUND';end if;
 if jsonb_array_length(rows)<>1 then raise exception 'SRI_RECEIVED_INVOICE_AMBIGUOUS';end if;
 return rows->0;end $$;
revoke all on function private.gama_ec_received_match(text,text) from public,anon;
grant execute on function private.gama_ec_received_match(text,text) to authenticated;
create function public.gama_ec_received_match(p_ruc text,p_number text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_ec_received_match(p_ruc,p_number)$$;
revoke all on function public.gama_ec_received_match(text,text) from public,anon;
grant execute on function public.gama_ec_received_match(text,text) to authenticated;

-- All invoices in one received XML are settled together or none are changed.
create function private.gama_ec_received_batch(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb;rows jsonb:='[]';begin
 if auth.uid() is null or jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids') not between 1 and 50 then raise exception 'SRI_RECEIVED_FIELDS_INVALID';end if;
 for x in select value from jsonb_array_elements(p_data->'ids') order by value::text loop
 rows:=rows||jsonb_build_array(private.gama_ec_received('post',p_data||jsonb_build_object('id',x#>>'{}')));end loop;
 return jsonb_build_object('rows',rows);end $$;
revoke all on function private.gama_ec_received_batch(jsonb) from public,anon;
grant execute on function private.gama_ec_received_batch(jsonb) to authenticated;
create function public.gama_ec_received_batch(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_ec_received_batch(p_data)$$;
revoke all on function public.gama_ec_received_batch(jsonb) from public,anon;
grant execute on function public.gama_ec_received_batch(jsonb) to authenticated;
