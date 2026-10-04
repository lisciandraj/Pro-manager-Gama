-- Reviewed domestic ATS sources. No cancellation is inferred from a timeout,
-- rejection or management status; legal cancellation evidence is explicit.
alter table public.accounting_fiscal_documents drop constraint accounting_fiscal_documents_source_type_check;
alter table public.accounting_fiscal_documents add constraint accounting_fiscal_documents_source_type_check check(source_type in ('sales_invoice','supplier_invoice','expense','sales_credit','supplier_credit','customer_adjustment','supplier_adjustment'));
alter table public.accounting_fiscal_documents add column document_issued_on date;
alter table public.accounting_fiscal_documents add column modified_document_type text check(modified_document_type ~ '^[0-9]{2}$');
alter table public.accounting_fiscal_documents add column modified_number text check(modified_number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$');
alter table public.accounting_fiscal_documents add column modified_authorization text check(modified_authorization ~ '^[0-9]{10,49}$');
alter table public.accounting_ec_profile add column ats_establishments jsonb check(ats_establishments is null or jsonb_typeof(ats_establishments)='array');

create table public.accounting_fiscal_cancellations (
 id uuid primary key default gen_random_uuid(),source_invoice_id uuid references public.external_invoices(id),
 document_type text not null check(document_type in ('01','03','04','05','06','07','18')),
 establishment text not null check(establishment ~ '^[0-9]{3}$'),emission_point text not null check(emission_point ~ '^[0-9]{3}$'),
 sequential_start bigint not null check(sequential_start between 1 and 999999999),sequential_end bigint not null check(sequential_end between sequential_start and 999999999),
 authorization_number text not null check(authorization_number ~ '^[0-9]{3,49}$'),cancelled_on date not null,portal_deregistered boolean not null default false,
 evidence text not null check(length(btrim(evidence))>=10),reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default now(),
 unique(document_type,establishment,emission_point,sequential_start,sequential_end,authorization_number)
);
create index fiscal_cancellation_source on public.accounting_fiscal_cancellations(source_invoice_id) where source_invoice_id is not null;
create index fiscal_cancellation_reviewer on public.accounting_fiscal_cancellations(reviewed_by);
create index fiscal_cancellation_period on public.accounting_fiscal_cancellations(cancelled_on);
alter table public.accounting_fiscal_cancellations enable row level security;
revoke all on public.accounting_fiscal_cancellations from public,anon,authenticated;
grant select on public.accounting_fiscal_cancellations to authenticated;
create policy fiscal_cancellations_read on public.accounting_fiscal_cancellations for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create trigger erp_audit_capture after insert or update or delete on public.accounting_fiscal_cancellations for each row execute function private.erp_audit_capture();

create view private.gama_ec_fiscal_extra_sources as
 select case when k.invoice_id is not null then 'sales_credit' else 'supplier_credit' end source_type,k.id source_id,coalesce(k.erp_reference,k.number) number,k.issued_on issue_date,
 coalesce(c.name,s.name) partner_name,coalesce(c.identification,s.tax_id) partner_identification,x.net subtotal,x.tax,k.amount total,
 case when k.invoice_id is not null then 'customer' else 'supplier' end side,coalesce(k.invoice_id,k.supplier_invoice_id) invoice_id,'credit' kind
 from public.return_credits k join public.return_orders o on o.id=k.return_id left join public.customers c on c.id=o.customer_id left join public.suppliers s on s.id=o.supplier_id
 cross join lateral(select coalesce(sum(round(quantity*unit_price,2)),0) net,coalesce(sum(round(round(quantity*unit_price,2)*tax_rate/100,2)),0) tax from public.return_lines where return_id=k.return_id)x
 union all select case when a.side='customer' then 'customer_adjustment' else 'supplier_adjustment' end,a.id,a.reference,a.issued_on,coalesce(c.name,s.name),coalesce(c.identification,s.tax_id),a.net,a.tax,a.total,a.side,coalesce(a.invoice_id,a.supplier_invoice_id),a.kind
 from public.accounting_adjustments a left join public.external_invoices v on v.id=a.invoice_id left join public.sales_orders o on o.id=v.order_id left join public.customers c on c.id=o.customer_id
 left join public.supplier_invoices b on b.id=a.supplier_invoice_id left join public.suppliers s on s.id=b.supplier_id where a.status='posted';
revoke all on private.gama_ec_fiscal_extra_sources from public,anon,authenticated;

-- Extend the existing command receipt and permission dispatcher, preserving its
-- request-key checks, closed periods and every existing action.
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_before_ats;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;result jsonb;rid uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());total numeric;begin
 if p_action='cancellation_save' then
  if nullif(p_data->>'source_invoice_id','') is not null then
   select v.fiscal_status,coalesce(v.external_number,f.document_number,case when v.document_kind='external' then v.number end) fiscal_number,coalesce(v.access_key,f.authorization_number) fiscal_authorization into r from public.external_invoices v left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=v.id where v.id=(p_data->>'source_invoice_id')::uuid;
   if not found or r.fiscal_status<>'cancelled' or r.fiscal_number is null or split_part(r.fiscal_number,'-',1) is distinct from p_data->>'establishment' or split_part(r.fiscal_number,'-',2) is distinct from p_data->>'emission_point' or split_part(r.fiscal_number,'-',3)::bigint not between (p_data->>'sequential_start')::bigint and (p_data->>'sequential_end')::bigint or r.fiscal_authorization is distinct from p_data->>'authorization_number' then raise exception 'FISCAL_CANCELLATION_SOURCE_MISMATCH';end if;
  end if;
  insert into public.accounting_fiscal_cancellations(id,source_invoice_id,document_type,establishment,emission_point,sequential_start,sequential_end,authorization_number,cancelled_on,portal_deregistered,evidence,reviewed_by)
  values(rid,nullif(p_data->>'source_invoice_id','')::uuid,p_data->>'document_type',p_data->>'establishment',p_data->>'emission_point',(p_data->>'sequential_start')::bigint,(p_data->>'sequential_end')::bigint,p_data->>'authorization_number',(p_data->>'cancelled_on')::date,coalesce((p_data->>'portal_deregistered')::boolean,false),p_data->>'evidence',auth.uid())
  on conflict(document_type,establishment,emission_point,sequential_start,sequential_end,authorization_number) do update set cancelled_on=excluded.cancelled_on,portal_deregistered=excluded.portal_deregistered,evidence=excluded.evidence,reviewed_by=auth.uid(),reviewed_at=now() returning id into rid;
  return jsonb_build_object('id',rid);
 elsif p_action='fiscal_save' then
  if p_data->>'source_type' in ('sales_credit','supplier_credit','customer_adjustment','supplier_adjustment') then
   select * into r from private.gama_ec_fiscal_extra_sources where source_type=p_data->>'source_type' and source_id=(p_data->>'source_id')::uuid;
   if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
   if coalesce(r.partner_identification,'')<>'' and p_data->>'identification' is distinct from r.partner_identification then raise exception 'FISCAL_PARTNER_MISMATCH';end if;
   total:=coalesce((p_data->>'base_zero')::numeric,0)+coalesce((p_data->>'base_taxed')::numeric,0)+coalesce((p_data->>'base_exempt')::numeric,0)+coalesce((p_data->>'base_non_taxable')::numeric,0);
   if total is distinct from r.subtotal or (p_data->>'vat')::numeric is distinct from r.tax or total+coalesce((p_data->>'ice')::numeric,0)+(p_data->>'vat')::numeric is distinct from r.total then raise exception 'FISCAL_TOTAL_MISMATCH';end if;
   if p_data->>'document_type' is distinct from (case when r.kind='credit' then '04' else '05' end) then raise exception 'FISCAL_DOCUMENT_TYPE_MISMATCH';end if;
   if jsonb_typeof(p_data->'payment_codes') is distinct from 'array' or jsonb_array_length(p_data->'payment_codes')=0 then raise exception 'PAYMENT_CODE_REQUIRED';end if;
   insert into public.accounting_fiscal_documents(source_type,source_id,document_type,document_number,identification_type,identification,authorization_number,support_code,payment_codes,related_party,base_zero,base_taxed,base_exempt,base_non_taxable,ice,vat,evidence,reviewed_by)
   values(p_data->>'source_type',r.source_id,p_data->>'document_type',p_data->>'document_number',p_data->>'identification_type',p_data->>'identification',p_data->>'authorization_number',nullif(p_data->>'support_code',''),p_data->'payment_codes',coalesce((p_data->>'related_party')::boolean,false),coalesce((p_data->>'base_zero')::numeric,0),coalesce((p_data->>'base_taxed')::numeric,0),coalesce((p_data->>'base_exempt')::numeric,0),coalesce((p_data->>'base_non_taxable')::numeric,0),coalesce((p_data->>'ice')::numeric,0),(p_data->>'vat')::numeric,p_data->>'evidence',auth.uid())
   on conflict(source_type,source_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,identification_type=excluded.identification_type,identification=excluded.identification,authorization_number=excluded.authorization_number,support_code=excluded.support_code,payment_codes=excluded.payment_codes,related_party=excluded.related_party,base_zero=excluded.base_zero,base_taxed=excluded.base_taxed,base_exempt=excluded.base_exempt,base_non_taxable=excluded.base_non_taxable,ice=excluded.ice,vat=excluded.vat,evidence=excluded.evidence,reviewed_by=auth.uid(),reviewed_at=now() returning id into rid;
   result:=jsonb_build_object('id',rid);
  else result:=private.gama_accounting_ec_write_before_ats(p_action,p_data);end if;
  update public.accounting_fiscal_documents set document_issued_on=nullif(p_data->>'document_issued_on','')::date,modified_document_type=nullif(p_data->>'modified_document_type',''),modified_number=nullif(p_data->>'modified_number',''),modified_authorization=nullif(p_data->>'modified_authorization','') where source_type=p_data->>'source_type' and source_id=(p_data->>'source_id')::uuid;
  return result;
 elsif p_action='profile_save' then
  result:=private.gama_accounting_ec_write_before_ats(p_action,p_data);
  if p_data ? 'ats_establishments' then
   if jsonb_typeof(p_data->'ats_establishments') is distinct from 'array' or jsonb_array_length(p_data->'ats_establishments') not between 1 and 999 or exists(select 1 from jsonb_array_elements_text(p_data->'ats_establishments')x where x !~ '^[0-9]{3}$' or x='000') or (select count(distinct x) from jsonb_array_elements_text(p_data->'ats_establishments')x)<>jsonb_array_length(p_data->'ats_establishments') then raise exception 'ATS_ESTABLISHMENTS_INVALID';end if;
   update public.accounting_ec_profile set ats_establishments=p_data->'ats_establishments' where id;
  end if;
  return result;
 end if;
 return private.gama_accounting_ec_write_before_ats(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;

-- Authorized local SRI documents supply fiscal facts without manual retyping.
create function private.gama_ec_issue_fiscal(p_issue public.sri_document_issues) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('document_type',p_issue.document_type,'document_number',p_issue.establishment||'-'||p_issue.emission_point||'-'||p_issue.sequential,
 'identification_type',case when length(p_issue.snapshot->>'identification')=13 then '04' else '05' end,'identification',p_issue.snapshot->>'identification',
 'authorization_number',p_issue.access_key,'support_code','01','payment_codes',case when p_issue.document_type='03' then jsonb_build_array(p_issue.snapshot->>'payment_code') else coalesce(p_issue.snapshot->'payment_codes','[]'::jsonb) end,'related_party',false,
 'base_zero',coalesce((select sum((l->>'subtotal')::numeric) from jsonb_array_elements(p_issue.snapshot->'lines')l where (l->>'tax_rate')::numeric=0),0),
 'base_taxed',coalesce((select sum((l->>'subtotal')::numeric) from jsonb_array_elements(p_issue.snapshot->'lines')l where (l->>'tax_rate')::numeric>0),0),
 'base_exempt',0,'base_non_taxable',0,'vat',p_issue.snapshot->'tax','ice',0,'document_issued_on',p_issue.snapshot->>'issue_date',
 'modified_document_type',case when p_issue.document_type='04' then '01' end,'modified_number',p_issue.snapshot->>'support_number','modified_authorization',p_issue.snapshot->>'support_authorization');
$$;
revoke all on function private.gama_ec_issue_fiscal(public.sri_document_issues) from public,anon,authenticated;

alter function private.gama_accounting_ec_read(text,jsonb) rename to gama_accounting_ec_read_before_ats;
create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare result jsonb;d jsonb;docs jsonb:='[]';r record;s public.sri_document_issues;from_date date;to_date date;begin
 result:=private.gama_accounting_ec_read_before_ats(p_action,p_data);
 if p_action<>'fiscal_review' then return result;end if;
 from_date:=(result->>'from')::date;to_date:=(result->>'to')::date;
 for d in select value from jsonb_array_elements(result->'documents') loop
  select * into s from public.sri_document_issues where document_type='03' and source_id=(d->>'source_id')::uuid and d->>'source_type'='supplier_invoice' and status='authorized';
  if found then d:=d||jsonb_build_object('fiscal_id',s.id,'fiscal',private.gama_ec_issue_fiscal(s));end if;
  docs:=docs||jsonb_build_array(d);
 end loop;
 for r in select x.*,f.id fiscal_id,to_jsonb(f) fiscal from private.gama_ec_fiscal_extra_sources x left join public.accounting_fiscal_documents f on f.source_type=x.source_type and f.source_id=x.source_id where x.issue_date between from_date and to_date order by x.issue_date,x.source_id loop
  d:=to_jsonb(r);select * into s from public.sri_document_issues where document_type='04' and source_id=r.source_id and source_type='return_credit' and status='authorized';
  if found then d:=d||jsonb_build_object('fiscal_id',s.id,'fiscal',private.gama_ec_issue_fiscal(s));end if;
  docs:=docs||jsonb_build_array(d);
 end loop;
 return result||jsonb_build_object('documents',docs,'adjustments','[]'::jsonb,'return_credits','[]'::jsonb,
 'withholdings',coalesce((select jsonb_agg(to_jsonb(w)||jsonb_build_object('invoice_fiscal',to_jsonb(f),'partner_identification',coalesce(c.identification,s.tax_id),'invoice_number',coalesce(v.number,b.number))) from public.accounting_withholdings w
 left join public.external_invoices v on v.id=w.invoice_id left join public.sales_orders o on o.id=v.order_id left join public.customers c on c.id=o.customer_id left join public.supplier_invoices b on b.id=w.supplier_invoice_id left join public.suppliers s on s.id=b.supplier_id
 left join public.accounting_fiscal_documents f on f.source_type=case when w.side='customer' then 'sales_invoice' else 'supplier_invoice' end and f.source_id=coalesce(w.invoice_id,w.supplier_invoice_id)
 where w.status='posted' and w.issued_on between from_date and to_date),'[]'),
 'cancellations',coalesce((select jsonb_agg(to_jsonb(x) order by cancelled_on,establishment,emission_point,sequential_start) from public.accounting_fiscal_cancellations x where cancelled_on between from_date and to_date and not portal_deregistered),'[]'),
 'reviewed_cancellations',coalesce((select jsonb_agg(to_jsonb(x) order by cancelled_on,id) from public.accounting_fiscal_cancellations x where cancelled_on between from_date and to_date),'[]'),
 'cancelled_pending',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.number,'fiscal_number',coalesce(v.external_number,f.document_number),'authorization_number',coalesce(v.access_key,f.authorization_number))) from public.external_invoices v left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=v.id where v.fiscal_status='cancelled' and v.issue_date between from_date and to_date and (v.external_number is not null or f.id is not null) and not exists(select 1 from public.accounting_fiscal_cancellations x where x.source_invoice_id=v.id)),'[]'),
 'cancelled_documents',(select count(*) from public.external_invoices v where v.fiscal_status='cancelled' and v.issue_date between from_date and to_date and (v.external_number is not null or exists(select 1 from public.accounting_fiscal_documents f where f.source_type='sales_invoice' and f.source_id=v.id)) and not exists(select 1 from public.accounting_fiscal_cancellations x where x.source_invoice_id=v.id)));
end $$;
revoke all on function private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;

create function private.gama_ec_tax_drafts(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();cfg public.company_settings;review jsonb;rows103 jsonb;vat_out numeric;vat_in numeric;received_vat numeric;retained_vat numeric;factor numeric:=coalesce((p_data->>'credit_factor')::numeric,1);previous_credit numeric:=coalesce((p_data->>'previous_credit')::numeric,0);d1 date:=(p_data->>'from')::date;d2 date:=(p_data->>'to')::date;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) or (coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false)) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if d1 is null or d2 is null or d1<>date_trunc('month',d1)::date or d2<>(date_trunc('month',d1)+interval '1 month -1 day')::date then raise exception 'FULL_MONTH_REQUIRED';end if;
 if factor::text in ('NaN','Infinity','-Infinity') or factor not between 0 and 1 or previous_credit::text in ('NaN','Infinity','-Infinity') or previous_credit<0 then raise exception 'INVALID_TAX_CREDIT';end if;
 select * into cfg from public.company_settings where id;review:=private.gama_accounting_ec_read('fiscal_review',p_data);
 select coalesce(sum(l.credit-l.debit) filter(where l.account_id=cfg.tax_collected_account_id),0),coalesce(sum(l.debit-l.credit) filter(where l.account_id=cfg.tax_deductible_account_id),0) into vat_out,vat_in
 from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where e.status in ('posted','reversed') and e.entry_date between d1 and d2 and e.source_type<>'withholding' and not exists(select 1 from public.accounting_entries original where original.id=e.reversal_of and original.source_type='withholding');
 select coalesce(sum(round((x->>'base')::numeric*(x->>'rate')::numeric/100,2)) filter(where w.side='customer' and x->>'tax_kind'='vat'),0),coalesce(sum(round((x->>'base')::numeric*(x->>'rate')::numeric/100,2)) filter(where w.side='supplier' and x->>'tax_kind'='vat'),0) into received_vat,retained_vat from public.accounting_withholdings w cross join lateral jsonb_array_elements(w.lines)x where w.status='posted' and w.issued_on between d1 and d2;
 select coalesce(jsonb_agg(to_jsonb(z) order by code),'[]') into rows103 from(select x->>'code' code,sum((x->>'base')::numeric) base,sum(round((x->>'base')::numeric*(x->>'rate')::numeric/100,2)) withheld,count(distinct w.id) documents from public.accounting_withholdings w cross join lateral jsonb_array_elements(w.lines)x where w.status='posted' and w.side='supplier' and x->>'tax_kind'='income' and w.issued_on between d1 and d2 group by x->>'code')z;
 return jsonb_build_object('from',d1,'to',d2,'status','draft_not_submitted','review',review,'form103',jsonb_build_object('rows',rows103,'total',coalesce((select sum((x->>'withheld')::numeric) from jsonb_array_elements(rows103)x),0)),
 'form104',jsonb_build_object('ledger_collected',vat_out,'ledger_deductible',vat_in,'credit_factor',factor,'deductible_credit',round(vat_in*factor,2),'received_vat',received_vat,'previous_credit',previous_credit,'own_vat_payable',greatest(vat_out-round(vat_in*factor,2)-received_vat-previous_credit,0),'credit_next_period',greatest(round(vat_in*factor,2)+received_vat+previous_credit-vat_out,0),'supplier_vat_withheld_payable',retained_vat));
end $$;
revoke all on function private.gama_ec_tax_drafts(jsonb) from public,anon;
grant execute on function private.gama_ec_tax_drafts(jsonb) to authenticated;
create function public.gama_ec_tax_drafts(p_data jsonb) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_ec_tax_drafts(p_data)$$;
revoke all on function public.gama_ec_tax_drafts(jsonb) from public,anon;
grant execute on function public.gama_ec_tax_drafts(jsonb) to authenticated;
