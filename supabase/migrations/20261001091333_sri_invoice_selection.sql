-- Invoker view: source invoices and fiscal records retain their existing RLS.
-- Pending means never sent; uncertain/rejected/error records require individual review.
create view public.sri_invoice_selection with (security_invoker=true) as
select v.id,v.number,v.order_id,v.issue_date,v.total,v.document_kind,v.fiscal_status,
 v.external_number,v.created_at,
 (v.document_kind='internal' and v.fiscal_status='unverified' and v.external_number is null
  and (i.id is null or i.status='draft')) as sri_selectable
from public.external_invoices v
left join public.sri_invoice_issues i on i.source_invoice_id=v.id
where v.document_kind='internal';
revoke all on public.sri_invoice_selection from public,anon;
grant select on public.sri_invoice_selection to authenticated;

alter table public.sri_settings add column accounting_obligation text
 check(accounting_obligation in ('SI','NO'));
alter table public.sri_settings add column trade_name text not null default '';
alter table public.sri_settings add column establishment_address text not null default '';

create function private.gama_sri_configure_profile(p_environment text,p_establishment text,
 p_emission_point text,p_provider_ruc text,p_accounting_obligation text,p_trade_name text,
 p_establishment_address text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 -- Existing identity, active-admin, action-right and MFA checks remain authoritative.
 result:=private.gama_sri_configure(p_environment,p_establishment,p_emission_point,p_provider_ruc);
 if p_accounting_obligation is null or p_accounting_obligation not in ('SI','NO')
 or p_trade_name is null or length(p_trade_name)>300
 or p_establishment_address is null or length(p_establishment_address)>500
 then raise exception 'SRI_CONFIGURATION_INVALID'; end if;
 update public.sri_settings set accounting_obligation=p_accounting_obligation,
 trade_name=btrim(p_trade_name),establishment_address=btrim(p_establishment_address)
 where user_id=auth.uid();
 return result;
end $$;
revoke all on function private.gama_sri_configure_profile(text,text,text,text,text,text,text) from public,anon;
grant execute on function private.gama_sri_configure_profile(text,text,text,text,text,text,text) to authenticated;
create function public.gama_sri_configure_profile(p_environment text,p_establishment text,
 p_emission_point text,p_provider_ruc text,p_accounting_obligation text,p_trade_name text,
 p_establishment_address text) returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_sri_configure_profile(p_environment,p_establishment,p_emission_point,p_provider_ruc,
 p_accounting_obligation,p_trade_name,p_establishment_address) $$;
revoke all on function public.gama_sri_configure_profile(text,text,text,text,text,text,text) from public,anon;
grant execute on function public.gama_sri_configure_profile(text,text,text,text,text,text,text) to authenticated;

create or replace function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare v public.external_invoices; o public.sales_orders; c public.customers;
 cfg public.company_settings; old_issue public.sri_invoice_issues; s public.sri_settings;
 lines jsonb; seq text; result public.sri_invoice_issues;
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
 if cfg.country<>'EC' or not cfg.configured or cfg.tax_id !~ '^[0-9]{13}$'
    or s.id is null or s.ruc<>cfg.tax_id or s.estab !~ '^[0-9]{3}$' or s.pto_emi !~ '^[0-9]{3}$'
    or length(btrim(coalesce(s.razon_social,'')))=0 or length(btrim(coalesce(s.dir_matriz,'')))=0
    or s.provider_ruc is null
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE'; end if;
 if c.identification is null or c.identification !~ '^([0-9]{10}|[0-9]{13})$'
   or length(btrim(c.name))=0 or length(btrim(coalesce(c.address,'')))=0
 then raise exception 'SRI_CUSTOMER_INCOMPLETE'; end if;
 select jsonb_agg(jsonb_build_object('code',ol.reference,'description',ol.product_name,
   'quantity',il.quantity,'unit_price',ol.unit_price,'tax_rate',ol.tax_rate,
   'subtotal',round(il.quantity*ol.unit_price,2)) order by il.id) into lines
 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
 where il.invoice_id=v.id;
 if lines is null then raise exception 'SRI_LINES_MISSING'; end if;
 if exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
   where il.invoice_id=v.id and ol.tax_rate not in (0,5,12,13,14,15)) then raise exception 'SRI_UNSUPPORTED_TAX_RATE'; end if;
 -- The legal 9-digit sequence is independent of Coco's internal FAC number.
 seq:=lpad(nextval('private.sri_invoice_sequence')::text,9,'0');
 insert into public.sri_invoice_issues(source_invoice_id,customer_id,environment,issuer_ruc,
   establishment,emission_point,sequential,created_by,snapshot)
 values(v.id,c.id,s.environment,s.ruc,s.estab,s.pto_emi,seq,auth.uid(),
  jsonb_build_object('issue_date',v.issue_date,'source_number',v.number,'issuer',s.razon_social,
    'accounting_obligation',s.accounting_obligation,'trade_name',s.trade_name,
    'establishment_address',s.establishment_address,
    'provider_ruc',s.provider_ruc,'payment_code',p_payment_code,
    'address',s.dir_matriz,'customer',c.name,'identification',c.identification,
    'customer_address',c.address,'customer_email',c.email,'subtotal',v.subtotal,
    'tax',v.tax,'total',v.total,'lines',lines)) returning * into result;
 return jsonb_build_object('id',result.id,'status',result.status);
end $$;
