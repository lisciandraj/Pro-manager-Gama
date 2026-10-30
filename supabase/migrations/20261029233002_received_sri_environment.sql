-- A received withholding must use the environment of the matched invoice.
-- Existing externally recorded invoices without an electronic key are ordinary
-- production receivables; an explicit SRI issue/key always takes precedence.
create function private.sri_invoice_environment(invoice_id uuid) returns text
language sql stable security definer set search_path='' as $$
 select coalesce(s.environment,case
  when v.access_key ~ '^[0-9]{49}$' and substring(v.access_key,24,1)='1' then 'pruebas'
  else 'produccion' end)
 from public.external_invoices v left join public.sri_invoice_issues s on s.source_invoice_id=v.id
 where v.id=invoice_id
$$;
revoke all on function private.sri_invoice_environment(uuid) from public,anon,authenticated;

do $audit$
declare src text;before_text text;
begin
 src:=pg_get_functiondef('private.gama_ec_received_match(text,text)'::regprocedure);
 before_text:='''id'',v.id,''number'',v.number';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:received_invoice_environment';end if;
 execute replace(src,before_text,'''environment'',private.sri_invoice_environment(v.id),'||before_text);

 src:=pg_get_functiondef('private.gama_ec_received(text,jsonb)'::regprocedure);
 before_text:='if d.withholding_id is not null then';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:received_post_environment';end if;
 execute replace(src,before_text,$gate$
 if substring(d.access_key,24,1) is distinct from
   (case private.sri_invoice_environment(d.invoice_id) when 'pruebas' then '1' when 'produccion' then '2' end)
 then raise exception 'SRI_RECEIVED_ENVIRONMENT_MISMATCH';end if;
 $gate$||before_text);
end $audit$;
notify pgrst,'reload schema';
