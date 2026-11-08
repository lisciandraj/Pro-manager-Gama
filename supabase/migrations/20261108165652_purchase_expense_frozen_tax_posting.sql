-- Post immutable purchase/expense calculations without collapsing their taxes or
-- product/category accounts. Keep the existing outer stock/deferral lifecycle.
begin;
create function private.coco_purchase_expense_frozen_post(p_source text,p_id uuid,p_date date default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare bill public.supplier_invoices;expense public.expenses;claim private.expense_claims;cfg public.company_settings;bank public.financial_accounts;
 calc jsonb;items jsonb:='[]';line jsonb;eid uuid;counter uuid;effective_date date;ref text;label text;journal text;
 total numeric;net numeric;tax numeric;amount numeric;project uuid;partner uuid;counter_partner uuid;counter_kind text;begin
 if p_source not in ('supplier_invoice','expense') then raise exception 'FROZEN_PURCHASE_SOURCE_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('frozen-purchase:'||p_source||':'||p_id::text,0));
 select id into eid from public.accounting_entries where source_type=p_source and source_id=p_id and status<>'reversed';if eid is not null then return eid;end if;
 select * into cfg from public.company_settings where id;
 if p_source='supplier_invoice' then
  select * into bill from public.supplier_invoices where id=p_id for update;if not found or bill.status<>'posted' then return null;end if;
  calc:=bill.tax_calculation;effective_date:=coalesce(p_date,bill.issue_date);ref:=bill.number;label:=(select name from public.suppliers where id=bill.supplier_id);
  journal:='CMP';total:=bill.total;net:=bill.subtotal;tax:=bill.tax;project:=bill.project_id;partner:=bill.supplier_id;
  counter:=private.gama_partner_account('supplier',bill.supplier_id,bill.id);counter_kind:='supplier';counter_partner:=bill.supplier_id;
 else
  select * into expense from public.expenses where id=p_id for update;if not found or expense.status<>'posted' then return null;end if;
  select * into claim from private.expense_claims where id=expense.id;
  calc:=expense.tax_calculation;effective_date:=coalesce(p_date,expense.expense_date);ref:=expense.reference;label:=expense.description;
  journal:=case when expense.payment_method='cash' then 'CAJ' else 'BAN' end;total:=expense.amount_total;net:=expense.amount_untaxed;tax:=expense.tax_amount;project:=expense.project_id;partner:=expense.supplier_id;
  if claim.paid_by='employee' then
   if claim.status not in ('approved','paid') or claim.liability_account_id is null then raise exception 'APPROVED_EXPENSE_REQUIRED';end if;counter:=claim.liability_account_id;
  elsif expense.financial_account_id is not null then
   select * into bank from public.financial_accounts where id=expense.financial_account_id and active and currency=expense.currency;
   if bank.id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;counter:=bank.account_id;
  else counter:=cfg.payable_account_id;end if;
 end if;
 if calc->>'schema' is distinct from 'coco.tax.v1' or jsonb_typeof(calc->'lines') is distinct from 'array' or jsonb_typeof(calc->'taxes') is distinct from 'array'
  or (calc->>'subtotal')::numeric is distinct from net or (calc->>'tax')::numeric is distinct from tax or (calc->>'total')::numeric is distinct from total
  or (select coalesce(sum((x->>'subtotal')::numeric),0) from jsonb_array_elements(calc->'lines')x) is distinct from net
  or (select coalesce(sum((x->>'amount')::numeric),0) from jsonb_array_elements(calc->'taxes')x) is distinct from tax then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 for line in select value from jsonb_array_elements(calc->'lines') loop
  amount:=(line->>'subtotal')::numeric;
  if amount<>0 then items:=items||jsonb_build_array(jsonb_build_object('account_id',(line->>'account_id')::uuid,'label',coalesce(nullif(line->>'description',''),label),
   'debit',greatest(amount,0),'credit',greatest(-amount,0),'project_id',project,
   'partner_type',case when partner is not null then 'supplier' end,'partner_id',partner));end if;
 end loop;
 for line in select value from jsonb_array_elements(calc->'taxes') loop
  amount:=(line->>'amount')::numeric;
  if amount<>0 then items:=items||jsonb_build_array(jsonb_build_object('account_id',(line->>'account_id')::uuid,'label',coalesce(line->>'code','Impuesto deducible'),
   'debit',greatest(amount,0),'credit',greatest(-amount,0),'tax_id',nullif(line->>'id','')::uuid));end if;
 end loop;
 items:=jsonb_build_array(jsonb_build_object('account_id',counter,'label',label,'credit',total,'financial_account_id',bank.id,
  'partner_type',counter_kind,'partner_id',counter_partner,'partner_account_fixed',p_source='supplier_invoice'))||items;
 return private.gama_accounting_book(journal,effective_date,ref,p_source,p_id,label,items);
end $$;
revoke all on function private.coco_purchase_expense_frozen_post(text,uuid,date) from public,anon,authenticated,service_role;

-- Patch the legacy branches rather than bypassing wrappers which perform stock
-- clearing, deferrals, source locks and reviewed correction-date handling.
do $$declare r record;src text;needle text:='select * into cfg from public.company_settings where id;';replacement text;n integer:=0;begin
 for r in select p.oid,p.pronargs from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='private'
  and p.proname like 'gama_accounting_post%' and p.prosrc like '%elsif p_source_type=''supplier_invoice'' then%'
  and p.prosrc like '%elsif p_source_type=''expense'' then%' loop
  src:=pg_get_functiondef(r.oid);if strpos(src,needle)=0 then raise exception 'FROZEN_PURCHASE_POST_ANCHOR';end if;
  replacement:=needle||E'\n if (p_source_type=''supplier_invoice'' and exists(select 1 from public.supplier_invoices where id=p_source_id and tax_calculation->>''schema''=''coco.tax.v1''))'
   ||E'\n or (p_source_type=''expense'' and exists(select 1 from public.expenses where id=p_source_id and tax_calculation->>''schema''=''coco.tax.v1'')) then return private.coco_purchase_expense_frozen_post(p_source_type,p_source_id,'
   ||case when r.pronargs=3 then 'p_date' else 'null' end||');end if;';
  execute replace(src,needle,replacement);n:=n+1;
 end loop;if n=0 then raise exception 'FROZEN_PURCHASE_POST_FUNCTION_MISSING';end if;
end $$;

create function private.coco_purchase_frozen_reclass_lines(p_calculation jsonb,p_counter uuid,p_net numeric,p_legacy uuid) returns jsonb
language plpgsql immutable set search_path='' as $$declare lines jsonb;begin
 if p_calculation->>'schema' is distinct from 'coco.tax.v1' then return jsonb_build_array(jsonb_build_object('account_id',p_counter,'debit',p_net),jsonb_build_object('account_id',p_legacy,'credit',p_net));end if;
 if (p_calculation->>'subtotal')::numeric is distinct from p_net then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 select jsonb_agg(jsonb_build_object('account_id',account_id,'credit',greatest(amount,0),'debit',greatest(-amount,0)) order by account_id) into lines
 from(select (l->>'account_id')::uuid account_id,sum((l->>'subtotal')::numeric) amount from jsonb_array_elements(p_calculation->'lines')l group by l->>'account_id')x;
 return jsonb_build_array(jsonb_build_object('account_id',p_counter,'debit',p_net))||coalesce(lines,'[]');
end $$;
revoke all on function private.coco_purchase_frozen_reclass_lines(jsonb,uuid,numeric,uuid) from public,anon,authenticated,service_role;
do $$declare src text;needle text:=$a$jsonb_build_array(jsonb_build_object('account_id',counter,'debit',net),jsonb_build_object('account_id',cfg.purchase_account_id,'credit',net))$a$;begin
 src:=pg_get_functiondef('private.gama_stock_invoice_reclass(uuid)'::regprocedure);
 if strpos(src,needle)=0 then raise exception 'FROZEN_PURCHASE_STOCK_CLEARING_ANCHOR';end if;
 execute replace(src,needle,'private.coco_purchase_frozen_reclass_lines(b.tax_calculation,counter,net,cfg.purchase_account_id)');
end $$;
commit;
