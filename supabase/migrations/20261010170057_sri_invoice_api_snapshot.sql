-- Provider-neutral invoice preparation. No historical invoice or SRI record is rewritten.
-- Existing private helper authorization, atomic claim and public RPC remain compatible.
create or replace function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare v public.external_invoices; o public.sales_orders; c public.customers;
 cfg public.company_settings; old_issue public.sri_invoice_issues; s public.sri_settings;
 lines jsonb; seq text; result public.sri_invoice_issues; saved jsonb; item jsonb;
 qty numeric; price numeric; rate numeric; base numeric; vat numeric; net numeric:=0; taxes numeric:=0;
begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador'])
   or private.current_user_role() is distinct from 'administrador'
   or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_payment_code is null or p_payment_code not in ('01','16','19','20') then raise exception 'SRI_PAYMENT_CODE_REQUIRED'; end if;
 select * into v from public.external_invoices where id=p_invoice_id for update;
 if not found or v.document_kind<>'internal' or v.fiscal_status<>'unverified'
    or v.external_number is not null then raise exception 'SRI_SOURCE_INVOICE_INVALID'; end if;
 select * into old_issue from public.sri_invoice_issues where source_invoice_id=p_invoice_id;
 if found then return jsonb_build_object('id',old_issue.id,'status',old_issue.status); end if;
 select * into o from public.sales_orders where id=v.order_id;
 select * into c from public.customers where id=o.customer_id;
 select * into cfg from public.company_settings where id=true;
 select * into s from public.sri_settings where user_id=auth.uid();
 if cfg.country is distinct from 'EC' or cfg.currency is distinct from 'USD' or not coalesce(cfg.configured,false) or coalesce(cfg.tax_id,'') !~ '^[0-9]{13}$'
    or s.id is null or s.ruc<>cfg.tax_id or s.estab !~ '^[0-9]{3}$' or s.pto_emi !~ '^[0-9]{3}$'
    or length(btrim(coalesce(s.razon_social,'')))=0 or length(btrim(coalesce(s.dir_matriz,'')))=0
    or s.provider_ruc is null or s.accounting_obligation is null or s.accounting_obligation not in ('SI','NO')
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE'; end if;
 -- Commercial identity and prices come exclusively from the immutable invoice.
 -- Missing historical data requires an explicit audited correction, never a live fallback.
 saved:=v.document_snapshot;
 if coalesce(saved->>'customer_identification','') !~ '^([0-9]{10}|[0-9]{13})$'
   or saved->>'customer_identification'='9999999999999'
   or nullif(btrim(saved->>'customer'),'') is null
   or nullif(btrim(saved#>>'{details,clientAddress}'),'') is null
 then raise exception 'SRI_CUSTOMER_INCOMPLETE'; end if;
 if jsonb_typeof(saved->'lines') is distinct from 'array' then raise exception 'SRI_LINES_MISSING'; end if;
 if jsonb_array_length(saved->'lines') not between 1 and 1000 then raise exception 'SRI_LINES_MISSING'; end if;
 lines:='[]'::jsonb;
 for item in select value from jsonb_array_elements(saved->'lines') loop
  if coalesce(item->>'qty','') !~ '^[0-9]+([.][0-9]{1,6})?$'
    or coalesce(item->>'price','') !~ '^[0-9]+([.][0-9]{1,6})?$'
    or coalesce(item->>'taxRate','') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or coalesce(item->>'subtotal','') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or coalesce(item->>'tax','') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or nullif(btrim(item->>'reference'),'') is null or length(item->>'reference')>25
    or nullif(btrim(item->>'name'),'') is null or length(item->>'name')>300
  then raise exception 'SRI_LINES_INVALID'; end if;
  qty:=(item->>'qty')::numeric;price:=(item->>'price')::numeric;rate:=(item->>'taxRate')::numeric;
  if qty<=0 or price<0 then raise exception 'SRI_LINES_INVALID'; end if;
  if rate not in (0,5,12,13,14,15) then raise exception 'SRI_UNSUPPORTED_TAX_RATE'; end if;
  base:=round(qty*price,2);vat:=round(base*rate/100,2);
  if base<>(item->>'subtotal')::numeric or vat<>(item->>'tax')::numeric then raise exception 'SRI_TOTAL_MISMATCH'; end if;
  net:=net+base;taxes:=taxes+vat;
  lines:=lines||jsonb_build_array(jsonb_build_object('source_line_id',item->>'line_id','product_id',item->>'product_id',
   'code',item->>'reference','description',item->>'name','quantity',qty,'unit_price',price,
   'list_price',item->'listPrice','discount_percent',item->'discount','tax_rate',rate,'subtotal',base,'tax',vat));
 end loop;
 if net is distinct from v.subtotal or taxes is distinct from v.tax or net+taxes is distinct from v.total then raise exception 'SRI_TOTAL_MISMATCH'; end if;
 -- The legal 9-digit sequence is independent of Coco's internal FAC number.
 seq:=lpad(nextval('private.sri_invoice_sequence')::text,9,'0');
 insert into public.sri_invoice_issues(source_invoice_id,customer_id,environment,issuer_ruc,
   establishment,emission_point,sequential,created_by,snapshot)
 values(v.id,c.id,s.environment,s.ruc,s.estab,s.pto_emi,seq,auth.uid(),
  jsonb_build_object('schema_version','coco.sri.invoice.v1','currency','USD','pricing_basis','net_unit_price',
    'source_order_id',v.order_id,'source_quote_id',v.source_quote_id,'due_date',v.due_date,
    'issue_date',v.issue_date,'source_number',v.number,'issuer',s.razon_social,
    'accounting_obligation',s.accounting_obligation,'trade_name',s.trade_name,
    'establishment_address',s.establishment_address,
    'provider_ruc',s.provider_ruc,'payment_code',p_payment_code,
    'address',s.dir_matriz,'customer',saved->>'customer','identification',saved->>'customer_identification',
    'customer_address',saved#>>'{details,clientAddress}','customer_email',saved#>>'{details,clientEmail}','subtotal',v.subtotal,
    'tax',v.tax,'total',v.total,'lines',lines)) returning * into result;
 return jsonb_build_object('id',result.id,'status',result.status);
end $$;

create function private.sri_invoice_snapshot_immutable() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if (new.source_invoice_id,new.customer_id,new.environment,new.issuer_ruc,new.establishment,new.emission_point,new.sequential,new.snapshot)
    is distinct from
    (old.source_invoice_id,old.customer_id,old.environment,old.issuer_ruc,old.establishment,old.emission_point,old.sequential,old.snapshot)
 then raise exception 'SRI_SNAPSHOT_IMMUTABLE'; end if;
 return new;
end $$;
revoke all on function private.sri_invoice_snapshot_immutable() from public,anon,authenticated;
create trigger sri_invoice_snapshot_immutable before update on public.sri_invoice_issues
for each row execute function private.sri_invoice_snapshot_immutable();
