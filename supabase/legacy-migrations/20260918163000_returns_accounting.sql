-- El pliego pide que el abono y el reembolso lleguen a Contabilidad. Llegan
-- por donde llegan los demás documentos: gama_accounting_post los convierte en
-- asiento y gama_accounting_sync los recoge, sin motor nuevo ni pantalla nueva.
alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
alter table public.accounting_entries add constraint accounting_entries_source_type_check
 check(source_type in ('manual','sales_invoice','customer_payment','supplier_invoice',
  'supplier_payment','expense','reversal','opening','return_credit','supplier_credit','return_refund'));

-- El impuesto no se guarda en el abono: se reparte con la proporción de las
-- líneas de la devolución, para que un importe ajustado a mano siga cuadrando.
create or replace function private.gama_return_split(p_return uuid,p_amount numeric)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('net',net,'tax',round(p_amount-net,2)) from (
  select round(p_amount*case when gross>0 then base/gross else 1 end,2) net from (
   select coalesce(sum(l.quantity*l.unit_price),0) base,
          coalesce(sum(l.quantity*l.unit_price*(1+l.tax_rate/100)),0) gross
   from public.return_lines l where l.return_id=p_return) z) y
$$;

do $mig$
declare src text:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
begin
 if position('return_credit' in src)>0 then raise exception 'ALREADY_APPLIED';end if;
 if position(' end if;'||E'\n'||' return null;' in src)=0 then raise exception 'ANCHOR_POST_TAIL';end if;
 src:=replace(src,'declare cfg public.company_settings;eid uuid;inv record;pay record;si record;sp record;ex record;',
  'declare cfg public.company_settings;eid uuid;inv record;pay record;si record;sp record;ex record;'||E'\n'||
  ' rc record;split jsonb;');
 src:=replace(src,' end if;'||E'\n'||' return null;',
 $body$ elsif p_source_type in ('return_credit','supplier_credit') then
  -- Un abono al cliente deshace la venta; el del proveedor deshace la compra.
  select k.*,o.kind,o.customer_id,o.supplier_id,c.name customer_name,s.name supplier_name into rc
   from public.return_credits k join public.return_orders o on o.id=k.return_id
   left join public.customers c on c.id=o.customer_id
   left join public.suppliers s on s.id=o.supplier_id where k.id=p_source_id;
  if not found then return null;end if;
  split:=private.gama_return_split(rc.return_id,rc.amount);
  if rc.kind='customer' then
   return private.gama_accounting_book('VTA',rc.issued_on,rc.number,'return_credit',rc.id,rc.customer_name,
    jsonb_build_array(
     jsonb_build_object('account_id',cfg.sales_account_id,'label',rc.number,'debit',(split->>'net')::numeric),
     jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','debit',(split->>'tax')::numeric),
     jsonb_build_object('account_id',cfg.receivable_account_id,'label',rc.customer_name,'credit',rc.amount,'partner_type','customer','partner_id',rc.customer_id)));
  end if;
  return private.gama_accounting_book('CMP',rc.issued_on,coalesce(rc.supplier_reference,rc.number),'supplier_credit',rc.id,rc.supplier_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.payable_account_id,'label',rc.supplier_name,'debit',rc.amount,'partner_type','supplier','partner_id',rc.supplier_id),
    jsonb_build_object('account_id',cfg.purchase_account_id,'label',rc.number,'credit',(split->>'net')::numeric),
    jsonb_build_object('account_id',cfg.tax_deductible_account_id,'label','Impuesto deducible','credit',(split->>'tax')::numeric)));

 elsif p_source_type='return_refund' then
  -- Dinero que sale: salda lo que el abono dejó a favor del cliente.
  select f.*,o.customer_id,c.name customer_name,o.number return_number into rc
   from public.return_refunds f join public.return_orders o on o.id=f.return_id
   left join public.customers c on c.id=o.customer_id where f.id=p_source_id;
  if not found then return null;end if;
  bank:=(select id from public.accounting_accounts where code='1000');
  return private.gama_accounting_book(
   case when rc.method ~* '(efectivo|cash|caja)' then 'CAJ' else 'BAN' end,
   rc.paid_at,coalesce(rc.reference,rc.return_number),'return_refund',rc.id,rc.customer_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.receivable_account_id,'label',rc.return_number,'debit',rc.amount,'partner_type','customer','partner_id',rc.customer_id),
    jsonb_build_object('account_id',bank,'label',rc.return_number,'credit',rc.amount)));
 end if;
 return null;$body$);
 execute src;
end $mig$;

do $mig$
declare src text:=pg_get_functiondef('private.gama_accounting_sync(integer)'::regprocedure);
begin
 if position('return_credit' in src)>0 then raise exception 'ALREADY_APPLIED';end if;
 if position(' return jsonb_build_object(''posted'',n);' in src)=0 then raise exception 'ANCHOR_SYNC_TAIL';end if;
 src:=replace(src,' return jsonb_build_object(''posted'',n);',
 $body$ for r in select k.id,o.kind from public.return_credits k
  join public.return_orders o on o.id=k.return_id
  where private.gama_accounting_period_open(k.issued_on)
  and not exists(select 1 from public.accounting_entries e
   where e.source_type in ('return_credit','supplier_credit') and e.source_id=k.id and e.status<>'reversed')
  order by k.issued_on limit p_limit
 loop if private.gama_accounting_post(case when r.kind='customer' then 'return_credit' else 'supplier_credit' end,r.id) is not null then n:=n+1;end if;end loop;
 for r in select f.id from public.return_refunds f
  where private.gama_accounting_period_open(f.paid_at)
  and not exists(select 1 from public.accounting_entries e
   where e.source_type='return_refund' and e.source_id=f.id and e.status<>'reversed')
  order by f.paid_at limit p_limit
 loop if private.gama_accounting_post('return_refund',r.id) is not null then n:=n+1;end if;end loop;
 return jsonb_build_object('posted',n);$body$);
 execute src;
end $mig$;
