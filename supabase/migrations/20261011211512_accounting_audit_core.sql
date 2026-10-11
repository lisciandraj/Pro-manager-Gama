-- Accounting audit A01-A12: the ledger is the financial source of truth.
-- Existing posted amounts and closed periods are never rewritten by this migration.
alter table public.accounting_permissions add column can_read_all boolean not null default false;
alter table public.accounting_permissions add column can_pay boolean;
alter table public.accounting_entry_lines add column financial_account_id uuid references public.financial_accounts(id);
create index accounting_line_financial on public.accounting_entry_lines(financial_account_id) where financial_account_id is not null;
alter table public.accounting_accounts add column cashflow_class text not null default 'operating'
 check(cashflow_class in ('operating','investing','financing'));
update public.accounting_accounts set cashflow_class='financing' where type='equity';

create table private.accounting_bank_bindings(
 line_id uuid primary key references public.accounting_entry_lines(id),
 financial_account_id uuid not null references public.financial_accounts(id),
 assigned_at timestamptz not null default now(),assigned_by uuid references auth.users(id),reason text not null
);
create index accounting_binding_bank on private.accounting_bank_bindings(financial_account_id);
create table private.accounting_audit_commands(request_key uuid primary key,actor uuid not null,action text not null,payload jsonb not null,result jsonb not null);
create table private.accounting_closure_reviews(id uuid primary key default gen_random_uuid(),period_id uuid not null references public.accounting_periods(id),
 reviewed_at timestamptz not null default now(),reviewed_by uuid not null references auth.users(id),review jsonb not null,exceptions text);
create index accounting_closure_period on private.accounting_closure_reviews(period_id);
create table private.accounting_bank_statements(import_batch uuid primary key,financial_account_id uuid not null references public.financial_accounts(id),
 name text not null check(length(btrim(name)) between 1 and 180),date_from date not null,date_to date not null,
 opening_balance numeric(18,2) not null,closing_balance numeric(18,2) not null,evidence text not null check(length(btrim(evidence))>=3),
 updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id),check(date_to>=date_from));
create index accounting_statement_bank on private.accounting_bank_statements(financial_account_id);
revoke all on private.accounting_bank_bindings,private.accounting_audit_commands,private.accounting_closure_reviews,private.accounting_bank_statements from public,anon,authenticated;
alter table private.accounting_bank_bindings enable row level security;
alter table private.accounting_audit_commands enable row level security;
alter table private.accounting_closure_reviews enable row level security;
alter table private.accounting_bank_statements enable row level security;

create or replace function private.gama_accounting_rights() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text;p public.accounting_permissions;rights jsonb;begin
 if auth.uid() is null then return jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'pay',false,'scope','none');end if;
 r:=coalesce(private.current_user_role(),'');
 rights:=case when r='administrador' then jsonb_build_object('view',true,'create',true,'edit',true,'delete',true,'validate',true,'export',true,'close',true,'pay',true,'scope','all')
 when r='comercial' then jsonb_build_object('view',true,'create',false,'edit',false,'delete',false,'validate',false,'export',true,'close',false,'pay',false,'scope','commercial')
 else jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'pay',false,'scope','none') end;
 select * into p from public.accounting_permissions where profile_id=auth.uid();
 if found then
  rights:=rights||jsonb_build_object('view',p.can_view,'create',p.can_create,'edit',p.can_edit,'delete',p.can_delete,'validate',p.can_validate,'export',p.can_export,'close',p.can_close,'pay',coalesce(p.can_pay,p.can_create));
  if p.can_view and (p.can_read_all or p.can_create or p.can_validate or p.can_close) then rights:=rights||jsonb_build_object('scope','all');
  elsif p.can_view and rights->>'scope'='none' then rights:=rights||jsonb_build_object('scope','commercial');end if;
 end if;
 return rights;
end $$;

create function private.gama_accounting_currency_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended('accounting-base-currency',0));
 if tg_table_name='company_settings' then
  if new.currency is distinct from old.currency and exists(select 1 from public.accounting_entries where status in ('posted','reversed')) then raise exception 'BASE_CURRENCY_LOCKED';end if;
 end if;
 return new;
end $$;
create trigger accounting_currency_locked before update of currency on public.company_settings for each row execute function private.gama_accounting_currency_guard();
create trigger accounting_currency_post_lock before update of status on public.accounting_entries for each row when(new.status='posted') execute function private.gama_accounting_currency_guard();

create function private.gama_accounting_source_bank(p_entry uuid) returns uuid language sql stable security definer set search_path='' as $$
 select coalesce(case e.source_type
  when 'opening' then e.source_id
  when 'customer_payment' then (select financial_account_id from public.external_invoice_payments where id=e.source_id and receipt_id is null)
  when 'customer_receipt' then (select financial_account_id from public.customer_receipts where id=e.source_id)
  when 'supplier_payment' then (select financial_account_id from public.supplier_invoice_payments where id=e.source_id)
  when 'expense' then (select financial_account_id from public.expenses where id=e.source_id)
  when 'return_refund' then (select financial_account_id from public.return_refunds where id=e.source_id)
  when 'payroll_payment' then (select financial_account_id from public.hr_payroll_payments where id=e.source_id)
  end,j.financial_account_id)
 from public.accounting_entries x join public.accounting_entries e on e.id=coalesce(x.reversal_of,case when x.source_type='reversal' then x.source_id end,x.id)
 join public.accounting_journals j on j.id=e.journal_id where x.id=p_entry
$$;

create function private.gama_accounting_bind_line() returns trigger language plpgsql security definer set search_path='' as $$
declare fid uuid;cnt integer;begin
 fid:=coalesce(new.financial_account_id,private.gama_accounting_source_bank(new.entry_id));
 if fid is not null and not exists(select 1 from public.financial_accounts where id=fid and account_id=new.account_id) then
  if new.financial_account_id is not null then raise exception 'BANK_ACCOUNT_MISMATCH';end if;fid:=null;
 end if;
 if fid is null then
  select count(*),min(id::text)::uuid into cnt,fid from public.financial_accounts where account_id=new.account_id;
  if cnt>1 then raise exception 'LINE_FINANCIAL_ACCOUNT_REQUIRED';end if;
 end if;
 new.financial_account_id:=fid;return new;
end $$;
create trigger accounting_bind_line before insert on public.accounting_entry_lines for each row execute function private.gama_accounting_bind_line();
-- Freeze only deterministic historical account associations, without updating a posted line.
insert into private.accounting_bank_bindings(line_id,financial_account_id,reason)
select l.id,f.id,'Deterministic association at accounting audit migration'
from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id
join public.financial_accounts f on f.account_id=l.account_id
where f.id=private.gama_accounting_source_bank(e.id) or
 (private.gama_accounting_source_bank(e.id) is null and (select count(*) from public.financial_accounts z where z.account_id=l.account_id)=1);

-- Preserve explicit bank metadata in manual posting and counter-entries.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 if position('project_id,position)' in s)=0 then raise exception 'BOOK_BANK_ANCHOR_MISSING';end if;
 s:=replace(s,'project_id,position)','project_id,position,financial_account_id)');
 s:=replace(s,'nullif(x->>''project_id'','''')::uuid,i);','nullif(x->>''project_id'','''')::uuid,i,nullif(x->>''financial_account_id'','''')::uuid);');execute s;
 s:=pg_get_functiondef('private.gama_accounting_reverse(uuid,text)'::regprocedure);
 s:=replace(s,'''tax_id'',l.tax_id,''project_id'',l.project_id)', '''tax_id'',l.tax_id,''project_id'',l.project_id,''financial_account_id'',coalesce(l.financial_account_id,(select financial_account_id from private.accounting_bank_bindings where line_id=l.id)))');execute s;
end $$;

create view private.gama_cash_ledger with(security_invoker=true) as
select l.id line_id,l.entry_id,l.account_id,coalesce(l.financial_account_id,b.financial_account_id) financial_account_id,
 e.entry_date,e.number,e.reference,e.memo,e.source_type,e.source_id,e.status,l.label,l.debit,l.credit,l.debit-l.credit amount
from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id
left join private.accounting_bank_bindings b on b.line_id=l.id
where e.status in ('posted','reversed') and exists(select 1 from public.financial_accounts f where f.account_id=l.account_id);
revoke all on private.gama_cash_ledger from public,anon,authenticated;
alter view private.gama_cash_position rename to gama_cash_operational;
create view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 coalesce((select sum(l.amount) from private.gama_cash_ledger l where l.financial_account_id=f.id),0) current_balance,
 (select count(*) from public.bank_transactions t where t.financial_account_id=f.id and t.status='unmatched') unmatched
from public.financial_accounts f;
revoke all on private.gama_cash_position,private.gama_cash_operational from public,anon,authenticated;

create view private.gama_accounting_eligible_sources with(security_invoker=true) as
select 'sales_invoice'::text source_type,i.id source_id,i.issue_date source_date,i.number reference,i.total amount from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
union all select 'customer_payment',id,paid_at,coalesce(reference,id::text),amount from public.external_invoice_payments where status='confirmed'
union all select 'supplier_invoice',id,issue_date,number,total from public.supplier_invoices where status='posted'
union all select 'supplier_payment',id,paid_at,coalesce(reference,id::text),amount from public.supplier_invoice_payments where status='confirmed'
union all select 'expense',id,expense_date,reference,amount_total from public.expenses where status='posted'
union all select case when o.kind='supplier' then 'supplier_credit' else 'return_credit' end,k.id,k.issued_on,k.number,k.amount from public.return_credits k join public.return_orders o on o.id=k.return_id
union all select 'return_refund',id,paid_at,coalesce(reference,id::text),amount from public.return_refunds where financial_account_id is not null
union all select 'customer_receipt',id,paid_at,coalesce(reference,id::text),amount from public.customer_receipts where status='confirmed'
union all select 'payroll',id,period,source_ref,employer_cost from public.hr_payroll where status='validated'
union all select 'payroll_payment',id,paid_on,coalesce(reference,id::text),amount from public.hr_payroll_payments where status='confirmed' and financial_account_id is not null;
revoke all on private.gama_accounting_eligible_sources from public,anon,authenticated;

create function private.gama_accounting_controls(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare missing jsonb;openings jsonb;banks jsonb;stock jsonb;checks jsonb;drafts integer;unbalanced integer;unassigned integer;stock_missing integer;stock_difference numeric;begin
 select coalesce(jsonb_agg(to_jsonb(s) order by source_date,source_type,reference),'[]') into missing from private.gama_accounting_eligible_sources s
 where s.source_date<=p_to and not exists(select 1 from public.accounting_entries e where e.source_type=s.source_type and e.source_id=s.source_id);
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'amount',f.opening_balance)),'[]') into openings from public.financial_accounts f
 where f.opening_balance<>0 and f.created_at::date<=p_to and not exists(select 1 from public.accounting_entries where source_type='opening' and source_id=f.id);
 select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'ledger',g.current_balance,'operations',o.current_balance,'difference',g.current_balance-o.current_balance,'unmatched',g.unmatched)),'[]') into banks
 from private.gama_cash_position g join private.gama_cash_operational o on o.id=g.id where g.active;
 select count(*) into drafts from public.accounting_entries where status='draft' and entry_date between p_from and p_to;
 select count(*) into unbalanced from public.accounting_entries e where status in ('posted','reversed') and entry_date<=p_to
 and (select coalesce(sum(debit-credit),0) from public.accounting_entry_lines where entry_id=e.id)<>0;
 select count(*) into unassigned from private.gama_cash_ledger where financial_account_id is null and entry_date<=p_to;
 select count(*) into stock_missing from public.stock_valuation_entries v where v.kind not in ('method','transfer') and round(abs(v.value_delta)+abs(v.expense_delta),2)>0
 and (v.created_at at time zone private.erp_timezone())::date<=p_to and not exists(select 1 from public.accounting_source_links l where l.source_type='stock_valuation' and l.source_id=v.sequence::text);
 with amounts as(select b.stock_account_id aid,coalesce(sum(v.value_delta) filter(where (v.created_at at time zone private.erp_timezone())::date<=p_to),0) subledger
 from public.stock_cost_books b left join public.stock_valuation_entries v on v.product_id=b.product_id where b.stock_account_id is not null group by b.stock_account_id),
 totals as(select a.*,coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=a.aid and e.status in ('posted','reversed') and e.entry_date<=p_to),0) ledger from amounts a)
 select coalesce(jsonb_agg(jsonb_build_object('account_id',aid,'subledger',round(subledger,2),'ledger',ledger,'difference',round(subledger,2)-ledger)),'[]'),coalesce(sum(abs(round(subledger,2)-ledger)),0) into stock,stock_difference from totals;
 checks:=jsonb_build_array(
 jsonb_build_object('code','missing_sources','count',jsonb_array_length(missing),'blocking',true),
 jsonb_build_object('code','opening_balances','count',jsonb_array_length(openings),'blocking',true),
 jsonb_build_object('code','draft_entries','count',drafts,'blocking',true),
 jsonb_build_object('code','unbalanced_entries','count',unbalanced,'blocking',true),
 jsonb_build_object('code','unassigned_bank_lines','count',unassigned,'blocking',true),
 jsonb_build_object('code','unposted_stock','count',stock_missing,'blocking',true),
 jsonb_build_object('code','stock_difference','count',case when stock_difference<>0 then 1 else 0 end,'blocking',true),
 jsonb_build_object('code','unconfigured_stock','count',case when p_to>=(now() at time zone private.erp_timezone())::date then (select count(*) from public.products p where p.product_kind='goods' and p.active and exists(select 1 from public.stock_quants q where q.product_id=p.id and q.quantity<>0) and not exists(select 1 from public.stock_cost_books b where b.product_id=p.id)) else 0 end,'blocking',false),
 jsonb_build_object('code','unmatched_bank','count',(select count(*) from public.bank_transactions where status='unmatched' and value_date between p_from and p_to),'blocking',false));
 return jsonb_build_object('from',p_from,'to',p_to,'generated_at',statement_timestamp(),'checks',checks,'missing',missing,'openings',openings,'banks',banks,'stock',stock,
 'can_close',not exists(select 1 from jsonb_array_elements(checks)c where (c->>'blocking')::boolean and (c->>'count')::integer>0),
 'unassigned',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from private.gama_cash_ledger where financial_account_id is null and entry_date<=p_to order by entry_date limit 200)z),'[]'));
end $$;

-- Clone the source poster with an explicitly reviewed correction date. No source date is changed.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
 s:=replace(s,'private.gama_accounting_post(p_source_type text, p_source_id uuid)','private.gama_accounting_post_at(p_source_type text, p_source_id uuid, p_date date)');
 foreach s in array array[s] loop
 s:=replace(s,'inv.issue_date,inv.number','p_date,inv.number');s:=replace(s,'pay.paid_at,coalesce','p_date,coalesce');s:=replace(s,'si.issue_date,si.number','p_date,si.number');
 s:=replace(s,'sp.paid_at,coalesce','p_date,coalesce');s:=replace(s,'ex.expense_date,ex.reference','p_date,ex.reference');s:=replace(s,'rc.issued_on,','p_date,');s:=replace(s,'rc.paid_at,coalesce','p_date,coalesce');
 execute s;end loop;
end $$;

alter function private.gama_accounting_action(text,jsonb) rename to gama_accounting_action_before_audit;
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare rights jsonb:=private.gama_accounting_rights();result jsonb;cfg public.company_settings;d1 date;d2 date;today date:=(now() at time zone private.erp_timezone())::date;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim integer:=least(2000,greatest(1,coalesce((p_data->>'limit')::integer,50)));search text:=left(btrim(coalesce(p_data->>'search','')),120);
 review jsonb;p public.accounting_periods;prev_from date;prev_to date;fy date;period_result jsonb;rec record;opening numeric;closing numeric;rows jsonb;categories jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_REQUEST';end if;
 if rights->>'scope'<>'all' then return private.gama_accounting_action_before_audit(p_action,p_data);end if;
 select * into cfg from public.company_settings where id;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);d2:=coalesce(nullif(p_data->>'to','')::date,today);if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action in ('supplier_payment','supplier_payment_cancel') and not coalesce((rights->>'pay')::boolean,false) then raise exception 'PAYMENT_NOT_ALLOWED';end if;
 if p_action='entry_reverse' and exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind='ledger_entry' and s.source_id=(p_data->>'id')::uuid and g.cancelled_at is null) then raise exception 'ENTRY_BANK_MATCHED';end if;
 if p_action='period_close' then
  if not coalesce((rights->>'close')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  p:=private.gama_accounting_period((p_data->>'period_start')::date);select * into p from public.accounting_periods where id=p.id for update;
  if p.status='closed' then return jsonb_build_object('id',p.id,'status','closed');end if;
  review:=private.gama_accounting_controls(p.period_start,p.period_end);
  if not (review->>'can_close')::boolean then raise exception 'CLOSURE_BLOCKED';end if;
  if exists(select 1 from jsonb_array_elements(review->'checks')c where not (c->>'blocking')::boolean and (c->>'count')::integer>0)
   and length(btrim(coalesce(p_data->>'exceptions','')))<3 then raise exception 'CLOSURE_EXCEPTION_REQUIRED';end if;
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  insert into private.accounting_closure_reviews(period_id,reviewed_by,review,exceptions) values(p.id,auth.uid(),review,nullif(p_data->>'exceptions',''));return result||jsonb_build_object('review',review);
 elsif p_action='permission_save' then
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  update public.accounting_permissions set can_read_all=coalesce((p_data->>'can_read_all')::boolean,false),can_pay=coalesce((p_data->>'can_pay')::boolean,false) where profile_id=(p_data->>'profile_id')::uuid;return result;
 elsif p_action='bank_list' then
  with filtered as(select t.*,f.name account_name from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id
   where (nullif(p_data->>'financial_account_id','') is null or t.financial_account_id=(p_data->>'financial_account_id')::uuid)
   and (nullif(p_data->>'status','') is null or p_data->>'status'='all' or t.status=p_data->>'status')
   and (nullif(p_data->>'import_batch','') is null or t.import_batch=(p_data->>'import_batch')::uuid)
   and (nullif(p_data->>'from','') is null or t.value_date>=d1) and (nullif(p_data->>'to','') is null or t.value_date<=d2)
   and (nullif(p_data->>'min_amount','') is null or t.amount>=(p_data->>'min_amount')::numeric)
   and (nullif(p_data->>'max_amount','') is null or t.amount<=(p_data->>'max_amount')::numeric)
   and (search='' or concat_ws(' ',t.reference,t.description,f.name,t.amount::text) ilike '%'||search||'%'))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from filtered order by value_date desc,id offset off limit lim)z),'[]'),
   'total',(select count(*) from filtered),'offset',off,'limit',lim,
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.financial_accounts where active),'[]'),
   'batches',coalesce((select jsonb_agg(to_jsonb(z)) from(select t.import_batch id,min(t.value_date) date_from,max(t.value_date) date_to,count(*) lines,f.name account_name from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id where t.import_batch is not null group by t.import_batch,f.name order by max(t.imported_at) desc)z),'[]')) into result;return result;
 elsif p_action='account_movements' then
  return coalesce((select jsonb_agg(jsonb_build_object('date',entry_date,'reference',reference,'label',coalesce(label,memo),'number',number,'entry_id',entry_id,'in',debit,'out',credit,'balance',balance) order by entry_date desc,number desc,line_id desc)
   from(select *,sum(amount) over(order by entry_date,number,line_id rows between unbounded preceding and current row) balance from private.gama_cash_ledger where financial_account_id=(p_data->>'id')::uuid and entry_date<=d2)z where entry_date>=d1),'[]');
 elsif p_action='report_balance' then
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  select coalesce(sum(v.value_delta),0) into closing from public.stock_valuation_entries v where (v.created_at at time zone private.erp_timezone())::date<=d2;
  return jsonb_set(result,'{stock}',to_jsonb(round(closing,2)))||jsonb_build_object('stock_basis','dated_valuation','stock_controls',private.gama_accounting_controls(d1,d2)->'stock',
   'stock_coverage',jsonb_build_object('configured',(select count(*) from public.stock_cost_books where started_at::date<=d2),
    'before_opening',(select count(*) from public.stock_cost_books where started_at::date>d2),
    'unconfigured',(select count(*) from public.products prod where prod.product_kind='goods' and prod.active and prod.created_at::date<=d2 and not exists(select 1 from public.stock_cost_books where product_id=prod.id)),
    'complete',not exists(select 1 from public.products prod left join public.stock_cost_books b on b.product_id=prod.id where prod.product_kind='goods' and prod.active and prod.created_at::date<=d2 and (b.product_id is null or b.started_at::date>d2))));
 elsif p_action='report_cashflow' then
  select coalesce(sum(amount) filter(where entry_date<d1),0),coalesce(sum(amount),0) into opening,closing from private.gama_cash_ledger where entry_date<=d2;
  with cash_entries as(select entry_id,sum(amount) amount from private.gama_cash_ledger where entry_date between d1 and d2 group by entry_id having sum(amount)<>0),
  classified as(select e.entry_date,case when exists(select 1 from public.accounting_assets where asset_account_id=l.account_id) then 'investing' else a.cashflow_class end category,
   l.credit-l.debit amount from cash_entries c join public.accounting_entries e on e.id=c.entry_id join public.accounting_entry_lines l on l.entry_id=e.id join public.accounting_accounts a on a.id=l.account_id
   where not exists(select 1 from public.financial_accounts f where f.account_id=l.account_id)),
  cash_monthly as(select to_char(e.entry_date,'YYYY-MM') period_month,sum(greatest(c.amount,0)) incoming,sum(greatest(-c.amount,0)) outgoing from cash_entries c join public.accounting_entries e on e.id=c.entry_id group by 1),
  monthly as(select to_char(entry_date,'YYYY-MM') as period_month,sum(amount) net,
   sum(amount) filter(where category='operating') operating,sum(amount) filter(where category='investing') investing,sum(amount) filter(where category='financing') financing from classified group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('month',m.period_month,'in',c.incoming,'out',c.outgoing,'net',m.net,'operating',coalesce(m.operating,0),'investing',coalesce(m.investing,0),'financing',coalesce(m.financing,0)) order by m.period_month),'[]') into rows from monthly m join cash_monthly c using(period_month);
  return jsonb_build_object('from',d1,'to',d2,'opening',opening,'balance',closing,'net',closing-opening,'rows',rows,'basis','ledger');
 elsif p_action='overview' then
  result:=private.gama_accounting_action_before_audit(p_action,p_data);
  prev_from:=(date_trunc('month',today)-interval '1 month')::date;
  prev_to:=least((date_trunc('month',today)-interval '1 day')::date,prev_from+extract(day from today)::integer-1);
  fy:=make_date(extract(year from today)::integer,cfg.fiscal_year_start_month,1);if fy>today then fy:=(fy-interval '1 year')::date;end if;
  select jsonb_build_object('month',coalesce(sum(l.credit-l.debit) filter(where a.type='income' and e.entry_date>=date_trunc('month',today)::date),0),
   'previous',coalesce(sum(l.credit-l.debit) filter(where a.type='income' and e.entry_date between prev_from and prev_to),0),'year',coalesce(sum(l.credit-l.debit) filter(where a.type='income' and e.entry_date>=fy),0)),
   jsonb_build_object('month',coalesce(sum(l.debit-l.credit) filter(where a.type='expense' and e.entry_date>=date_trunc('month',today)::date),0),
   'previous',coalesce(sum(l.debit-l.credit) filter(where a.type='expense' and e.entry_date between prev_from and prev_to),0),'year',coalesce(sum(l.debit-l.credit) filter(where a.type='expense' and e.entry_date>=fy),0))
   into period_result,review from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id where e.status in ('posted','reversed') and e.source_type<>'year_close' and e.entry_date<=today;
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into categories from(select a.name,sum(l.debit-l.credit) amount from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id join public.accounting_entries e on e.id=l.entry_id where a.type='expense' and e.status in ('posted','reversed') and e.source_type<>'year_close' and e.entry_date between fy and today group by a.name having sum(l.debit-l.credit)>0 order by sum(l.debit-l.credit) desc limit 6)z;
  result:=jsonb_set(result,'{revenue}',period_result);result:=jsonb_set(result,'{expense}',review||jsonb_build_object('categories',categories));
  result:=jsonb_set(result,'{taxes}',private.gama_accounting_action_before_audit('taxes',jsonb_build_object('from',date_trunc('month',today)::date,'to',today))->'summary');
  result:=jsonb_set(result,'{treasury}',jsonb_build_object('balance',(select coalesce(sum(current_balance),0) from private.gama_cash_position where active),
   'accounts',coalesce((select jsonb_agg(to_jsonb(c) order by name) from private.gama_cash_position c where active),'[]'),
   'inflow',(select coalesce(sum(debit),0) from private.gama_cash_ledger where entry_date between date_trunc('month',today)::date and today),
   'outflow',(select coalesce(sum(credit),0) from private.gama_cash_ledger where entry_date between date_trunc('month',today)::date and today)));
  return result||jsonb_build_object('generated_at',statement_timestamp(),'basis','ledger','previous_from',prev_from,'previous_to',prev_to,'fiscal_from',fy);
 end if;
 result:=private.gama_accounting_action_before_audit(p_action,p_data);
 if p_action='settings' then result:=result||jsonb_build_object('currency_locked',exists(select 1 from public.accounting_entries where status in ('posted','reversed')));end if;
 return result;
end $$;
revoke all on function private.gama_accounting_action_before_audit(text,jsonb) from public,anon,authenticated;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

-- Private helpers can only be reached through the checked public facade below.
revoke all on function private.gama_accounting_currency_guard(),private.gama_accounting_source_bank(uuid),private.gama_accounting_bind_line(),private.gama_accounting_controls(date,date),private.gama_accounting_post_at(text,uuid,date) from public,anon,authenticated;

-- Reviewed manual entries can be reconciled like business payments.
alter table public.bank_match_sources drop constraint bank_match_sources_kind_check;
alter table public.bank_match_sources add constraint bank_match_sources_kind_check check(kind in ('customer_payment','customer_receipt','supplier_payment','expense','ledger_entry'));
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_bank_match_core(text,jsonb)'::regprocedure);
 if position('else raise exception ''MATCH_SOURCE_INVALID'';' in s)=0 then raise exception 'BANK_LEDGER_ANCHOR_MISSING';end if;
 s:=replace(s,'else raise exception ''MATCH_SOURCE_INVALID'';',
 'elsif x->>''kind''=''ledger_entry'' then select sum(amount) amount,min(financial_account_id::text)::uuid financial_account_id,''confirmed''::text status into source from private.gama_cash_ledger where entry_id=(x->>''id'')::uuid and financial_account_id=acc having count(distinct financial_account_id)=1 and sum(amount)<>0; else raise exception ''MATCH_SOURCE_INVALID'';');execute s;
end $$;

-- Undo removes an association, not its payment or cash entry. Reuse the existing source.
create function private.gama_bank_existing_posting(p_bank uuid) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.bank_match_banks b join public.bank_match_sources s on s.group_id=b.group_id where b.bank_id=p_bank and (
 (s.kind='ledger_entry' and exists(select 1 from public.accounting_entries e where e.id=s.source_id and e.status='posted')) or
 (s.kind='customer_receipt' and exists(select 1 from public.customer_receipts r where r.id=s.source_id and r.status='confirmed')) or
 (s.kind='customer_payment' and exists(select 1 from public.external_invoice_payments r where r.id=s.source_id and r.status='confirmed')) or
 (s.kind='supplier_payment' and exists(select 1 from public.supplier_invoice_payments r where r.id=s.source_id and r.status='confirmed')) or
 (s.kind='expense' and exists(select 1 from public.expenses r where r.id=s.source_id and r.status='posted'))));
$$;
revoke all on function private.gama_bank_existing_posting(uuid) from public,anon,authenticated;

create function private.gama_accounting_audit_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);
 result jsonb;batch uuid:=nullif(p_data->>'import_batch','')::uuid;b public.bank_transactions;context jsonb;search text:=left(btrim(coalesce(p_data->>'search','')),120);begin
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 if p_action='controls' then return private.gama_accounting_controls(d1,d2);
 elsif p_action='context' then return private.gama_accounting_ec_read('context',p_data)||jsonb_build_object('closures',coalesce((select jsonb_agg(to_jsonb(z)) from(select id,period_id,reviewed_at,reviewed_by,exceptions from private.accounting_closure_reviews order by reviewed_at desc limit 36)z),'[]'));
 elsif p_action='statements' then
  with batches as(select t.import_batch,t.financial_account_id,f.name account_name,min(t.value_date) first_date,max(t.value_date) last_date,sum(t.amount) net,
   count(*) lines,count(*) filter(where t.status='matched') matched,count(*) filter(where t.status='unmatched') unmatched,count(*) filter(where t.status='ignored') ignored
   from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id where t.import_batch is not null
   and (batch is null or t.import_batch=batch) group by t.import_batch,t.financial_account_id,f.name),
  reviewed as(select bt.*,s.name,coalesce(s.date_from,bt.first_date) date_from,coalesce(s.date_to,bt.last_date) date_to,s.opening_balance,s.closing_balance,s.evidence,s.updated_at,
   coalesce((select sum(l.amount) from private.gama_cash_ledger l where l.financial_account_id=bt.financial_account_id and l.entry_date<=coalesce(s.date_to,bt.last_date)),0) ledger_balance
   from batches bt left join private.accounting_bank_statements s on s.import_batch=bt.import_batch)
  select jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('arithmetic_difference',closing_balance-opening_balance-net,'ledger_difference',closing_balance-ledger_balance) order by date_to desc),'[]')) into result from reviewed r;return result;
 elsif p_action='bank_choices' then
  select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
  context:=private.gama_bank_match('context',jsonb_build_object('account_id',b.financial_account_id));
  select coalesce(jsonb_agg(x),'[]') into result from jsonb_array_elements(context->'sources')x where ((x->>'amount')::numeric>0)=(b.amount>0) and (search='' or concat_ws(' ',x->>'label',x->>'id',x->>'date') ilike '%'||search||'%');
  return jsonb_build_object('bank',to_jsonb(b),'sources',result,'has_posting',private.gama_bank_existing_posting(b.id),
   'invoice_total',case when b.amount>0 then (select count(*) from private.gama_receivables r where r.balance>0 and r.payment_status<>'cancelled' and (search='' or concat_ws(' ',r.number,r.customer_name) ilike '%'||search||'%')) else (select count(*) from private.gama_payables r where r.balance>0 and r.status='posted' and (search='' or concat_ws(' ',r.number,r.supplier_name) ilike '%'||search||'%')) end,
   'invoices',case when b.amount>0 then coalesce((select jsonb_agg(to_jsonb(z)) from(select id,number,customer_name partner_name,customer_id partner_id,balance,issue_date from private.gama_receivables r where balance>0 and payment_status<>'cancelled' and (search='' or concat_ws(' ',r.number,r.customer_name) ilike '%'||search||'%') order by issue_date,id limit 500)z),'[]')
   else coalesce((select jsonb_agg(to_jsonb(z)) from(select id,number,supplier_name partner_name,supplier_id partner_id,balance,issue_date from private.gama_payables r where balance>0 and status='posted' and (search='' or concat_ws(' ',r.number,r.supplier_name) ilike '%'||search||'%') order by issue_date,id limit 500)z),'[]') end,
   'ledger',coalesce((select jsonb_agg(to_jsonb(z)) from(select entry_id id,max(coalesce(reference,number)) label,max(entry_date) date,sum(amount) amount from private.gama_cash_ledger l
    where financial_account_id=b.financial_account_id and source_type='manual' and (search='' or concat_ws(' ',l.reference,l.number,l.memo) ilike '%'||search||'%') and not exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind='ledger_entry' and s.source_id=l.entry_id and g.cancelled_at is null)
    group by entry_id having (sum(amount)>0)=(b.amount>0) and sum(amount)<>0 order by max(entry_date) desc limit 100)z),'[]'));
 elsif p_action='package' then
  return jsonb_build_object('from',d1,'to',d2,'generated_at',statement_timestamp(),'currency',(select currency from public.company_settings where id),
   'revision',md5(jsonb_build_object('entries',(select jsonb_agg(jsonb_build_array(e.id,e.status,e.entry_date,e.posted_at) order by e.id) from public.accounting_entries e),
    'customers',(select jsonb_agg(jsonb_build_array(r.id,r.total,r.paid,r.balance) order by r.id) from private.gama_receivables r),
    'suppliers',(select jsonb_agg(jsonb_build_array(r.id,r.total,r.paid,r.balance) order by r.id) from private.gama_payables r),
    'stock',(select max(sequence) from public.stock_valuation_entries),'banks',(select jsonb_agg(jsonb_build_array(t.id,t.amount,t.status) order by t.id) from public.bank_transactions t))::text),
   'pl',private.gama_accounting_action('report_pl',p_data),'previous_pl',private.gama_accounting_action('report_pl',jsonb_build_object('from',(d1-interval '1 year')::date,'to',(d2-interval '1 year')::date)),
   'balance',private.gama_accounting_action('report_balance',p_data),'cashflow',private.gama_accounting_action('report_cashflow',p_data),
   'trial',private.gama_accounting_ec_read('trial_balance',p_data),'controls',private.gama_accounting_controls(d1,d2),
   'customers',private.gama_accounting_action('receivables',p_data||jsonb_build_object('limit',2000)),
   'suppliers',private.gama_accounting_action('payables',p_data||jsonb_build_object('limit',2000)));
 end if;
 raise exception 'INVALID_ACTION';
end $$;

create function private.gama_accounting_audit_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare key uuid:=(p_data->>'request_key')::uuid;fid uuid:=nullif(p_data->>'financial_account_id','')::uuid;eid uuid;aid uuid;counter uuid;rid uuid;
 amt numeric;total numeric;cfg public.company_settings;b public.bank_transactions;allocation jsonb;src record;r record;receipt jsonb;payment jsonb;sources jsonb:='[]';
 lines jsonb;date date:=(p_data->>'entry_date')::date;reason text:=btrim(coalesce(p_data->>'reason',''));begin
 select * into cfg from public.company_settings where id;
 if p_action in ('recovery_post','cash_operation','bank_adjustment','line_bank_assign') and length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
 if p_action='opening_post' then return private.gama_accounting_ec('opening_post',p_data);
 elsif p_action='recovery_post' then
  select * into src from private.gama_accounting_eligible_sources where source_type=p_data->>'source_type' and source_id=(p_data->>'source_id')::uuid;
  if not found then raise exception 'SOURCE_UNAVAILABLE';end if;
  if exists(select 1 from public.accounting_entries where source_type=src.source_type and source_id=src.source_id) then raise exception 'SOURCE_ALREADY_POSTED';end if;
  if date<src.source_date then raise exception 'DOCUMENT_DATE_BEFORE_INVOICE';end if;
  if src.source_type in ('payroll','payroll_payment') then
   if date<>src.source_date then raise exception 'RECOVERY_PAYROLL_ORIGINAL_DATE_REQUIRED';end if;
   eid:=private.gama_ec_payroll_post(src.source_id,src.source_type='payroll_payment');
  elsif src.source_type='customer_receipt' then
   select * into r from public.customer_receipts where id=src.source_id and status='confirmed' for update;
   aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=r.financial_account_id),'asset');counter:=private.gama_ec_account((select id from public.accounting_accounts where code='2090' and active),'liability');
   eid:=private.gama_accounting_book(case when r.method='cash' then 'CAJ' else 'BAN' end,date,r.reference,'customer_receipt',r.id,reason,jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',r.financial_account_id,'debit',r.amount),jsonb_build_object('account_id',counter,'credit',r.amount,'partner_type','customer','partner_id',r.customer_id)));
  else eid:=private.gama_accounting_post_at(src.source_type,src.source_id,date);end if;
  if eid is null then raise exception 'SOURCE_UNAVAILABLE';end if;
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data) values('accounting_entries',eid::text,'VALIDATE',auth.uid(),private.current_user_role(),jsonb_build_object('action','recovery','source_type',src.source_type,'source_id',src.source_id,'original_date',src.source_date,'correction_date',date,'reason',reason));
  return jsonb_build_object('entry_id',eid,'original_date',src.source_date,'correction_date',date);
 elsif p_action='line_bank_assign' then
  select * into src from private.gama_cash_ledger where line_id=(p_data->>'line_id')::uuid and financial_account_id is null;
  if not found or not exists(select 1 from public.financial_accounts where id=fid and account_id=src.account_id) then raise exception 'BANK_ACCOUNT_MISMATCH';end if;
  insert into private.accounting_bank_bindings(line_id,financial_account_id,assigned_by,reason) values(src.line_id,fid,auth.uid(),reason);return jsonb_build_object('id',src.line_id);
 elsif p_action='statement_save' then
  select min(financial_account_id::text)::uuid bank_id,count(distinct financial_account_id) bank_count,coalesce(sum(amount),0) net,min(value_date) first_date,max(value_date) last_date into src from public.bank_transactions where import_batch=(p_data->>'import_batch')::uuid;
  if src.bank_count<>1 then raise exception 'STATEMENT_NOT_FOUND';end if;
  if (p_data->>'closing_balance')::numeric-(p_data->>'opening_balance')::numeric<>src.net then raise exception 'STATEMENT_UNBALANCED';end if;
  if (p_data->>'date_from')::date>src.first_date or (p_data->>'date_to')::date<src.last_date then raise exception 'STATEMENT_DATES_INVALID';end if;
  insert into private.accounting_bank_statements(import_batch,financial_account_id,name,date_from,date_to,opening_balance,closing_balance,evidence,updated_by)
  values((p_data->>'import_batch')::uuid,src.bank_id,p_data->>'name',(p_data->>'date_from')::date,(p_data->>'date_to')::date,(p_data->>'opening_balance')::numeric,(p_data->>'closing_balance')::numeric,p_data->>'evidence',auth.uid())
  on conflict(import_batch) do update set name=excluded.name,date_from=excluded.date_from,date_to=excluded.date_to,opening_balance=excluded.opening_balance,closing_balance=excluded.closing_balance,evidence=excluded.evidence,updated_at=now(),updated_by=auth.uid();
  return jsonb_build_object('id',p_data->>'import_batch');
 elsif p_action='cash_operation' then
  aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=fid and active and currency=cfg.currency),'asset');
  amt:=(p_data->>'amount')::numeric;if amt<=0 or amt<>round(amt,2) or amt::text in ('NaN','Infinity','-Infinity') then raise exception 'INVALID_AMOUNT';end if;
  if p_data->>'kind'='transfer' then
   counter:=private.gama_ec_account((select account_id from public.financial_accounts where id=(p_data->>'destination_id')::uuid and active and currency=cfg.currency),'asset');
   if fid=(p_data->>'destination_id')::uuid then raise exception 'TRANSFER_SAME_ACCOUNT';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'credit',amt),jsonb_build_object('account_id',counter,'financial_account_id',p_data->>'destination_id','debit',amt));
  else
   counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,case when p_data->>'kind'='contribution' then 'equity' end);
   if exists(select 1 from public.financial_accounts where account_id=counter) then raise exception 'USE_TRANSFER_OPERATION';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'debit',case when p_data->>'direction'='out' then 0 else amt end,'credit',case when p_data->>'direction'='out' then amt else 0 end),jsonb_build_object('account_id',counter,'credit',case when p_data->>'direction'='out' then 0 else amt end,'debit',case when p_data->>'direction'='out' then amt else 0 end));
  end if;
  eid:=private.gama_accounting_book('BAN',date,p_data->>'reference','manual',null,reason,lines);return jsonb_build_object('entry_id',eid);
 elsif p_action in ('bank_group','bank_settle','bank_adjustment') then
  select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
  perform pg_advisory_xact_lock(hashtextextended('bank-match:'||b.financial_account_id::text,0));select * into b from public.bank_transactions where id=b.id for update;
  if b.status<>'unmatched' then raise exception 'BANK_ALREADY_MATCHED';end if;
  if p_action='bank_group' then return private.gama_bank_match('apply',jsonb_build_object('request_key',key,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',p_data->'sources','note',p_data->>'note'));end if;
  if private.gama_bank_existing_posting(b.id) then raise exception 'BANK_EXISTING_POSTING_USE_GROUP';end if;
  if not private.gama_accounting_may('create') or not private.gama_accounting_may('pay') then raise exception 'PAYMENT_NOT_ALLOWED';end if;
  if p_action='bank_adjustment' then
   aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=b.financial_account_id),'asset');counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,case when b.amount>0 then 'income' else 'expense' end);
   eid:=private.gama_accounting_book('BAN',b.value_date,coalesce(b.reference,'Ajuste bancario'),'manual',null,reason,jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',b.financial_account_id,'debit',greatest(b.amount,0),'credit',greatest(-b.amount,0)),jsonb_build_object('account_id',counter,'credit',greatest(b.amount,0),'debit',greatest(-b.amount,0))));
   sources:=jsonb_build_array(jsonb_build_object('kind','ledger_entry','id',eid));
  else
   if jsonb_typeof(p_data->'allocations') is distinct from 'array' or jsonb_array_length(p_data->'allocations') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
   select sum((x->>'amount')::numeric) into total from jsonb_array_elements(p_data->'allocations')x;
   if total<>abs(b.amount) or exists(select 1 from jsonb_array_elements(p_data->'allocations')x where (x->>'amount')::numeric<=0 or (x->>'amount')::numeric<>round((x->>'amount')::numeric,2)) then raise exception 'MATCH_DIFFERENCE';end if;
   if (select count(distinct x->>'invoice_id') from jsonb_array_elements(p_data->'allocations')x)<>jsonb_array_length(p_data->'allocations') then raise exception 'DUPLICATE_INVOICE';end if;
   if b.amount>0 then
    if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
    select count(distinct customer_id),min(customer_id::text)::uuid into src from private.gama_receivables where id in(select (x->>'invoice_id')::uuid from jsonb_array_elements(p_data->'allocations')x);
    if src.count<>1 then raise exception 'ONE_CUSTOMER_REQUIRED';end if;
    perform 1 from public.customers where id=src.min for update;
    receipt:=private.gama_receipt_action('receive',jsonb_build_object('request_key',key,'customer_id',src.min,'financial_account_id',b.financial_account_id,'amount',b.amount,'paid_at',b.value_date,'method','transfer','reference',coalesce(nullif(b.reference,''),nullif(b.description,''),b.id::text),'notes','Cobro revisado desde extracto'));
    for allocation in select value from jsonb_array_elements(p_data->'allocations') order by value->>'invoice_id' loop
     perform private.gama_receipt_action('allocate',jsonb_build_object('request_key',md5(key::text||(allocation->>'invoice_id'))::uuid,'id',receipt->>'id','invoice_id',allocation->>'invoice_id','amount',allocation->>'amount'));
    end loop;sources:=jsonb_build_array(jsonb_build_object('kind','customer_receipt','id',receipt->>'id'));
   else
    perform 1 from public.supplier_invoices where id in(select (x->>'invoice_id')::uuid from jsonb_array_elements(p_data->'allocations')x) order by id for update;
    for allocation in select value from jsonb_array_elements(p_data->'allocations') order by value->>'invoice_id' loop
     payment:=private.gama_accounting_action('supplier_payment',jsonb_build_object('request_key',md5(key::text||(allocation->>'invoice_id'))::uuid,'supplier_invoice_id',allocation->>'invoice_id','financial_account_id',b.financial_account_id,'amount',allocation->>'amount','paid_at',b.value_date,'method','transfer','reference',b.reference));
     sources:=sources||jsonb_build_array(jsonb_build_object('kind','supplier_payment','id',payment->>'id'));
    end loop;
   end if;
  end if;
  return private.gama_bank_match('apply',jsonb_build_object('request_key',md5('audit-match:'||key::text)::uuid,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',sources,'note',coalesce(p_data->>'note',reason)));
 elsif p_action='cashflow_class_save' then
  update public.accounting_accounts set cashflow_class=p_data->>'cashflow_class' where id=(p_data->>'account_id')::uuid;if not found then raise exception 'ACCOUNT_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 raise exception 'INVALID_ACTION';
end $$;

create function private.gama_accounting_audit(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.accounting_audit_commands;result jsonb;permission text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'INVALID_REQUEST';end if;
 if p_action in ('controls','context','statements','bank_choices','package','readiness','management','fx','assets') then
  if (p_action='package' or coalesce((p_data->>'export')::boolean,false)) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  return private.gama_accounting_audit_read(p_action,p_data);
 end if;
 permission:=case when p_action in ('statement_save','cashflow_class_save','dimension_save','budget_save','stock_accounting_save','readiness_save','line_dimensions_save','asset_policy_save') then 'edit' else 'validate' end;
 if not coalesce((rights->>permission)::boolean,false) or not private.erp_action_allowed('accounting',permission) then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting_audit:'||key::text,0));select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 result:=private.gama_accounting_audit_write(p_action,p_data);
 insert into private.accounting_audit_commands values(key,auth.uid(),p_action,p_data,result);
 insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data) values('accounting_audit',coalesce(result->>'entry_id',result->>'id',key::text),case when permission='validate' then 'VALIDATE' else 'UPDATE' end,auth.uid(),private.current_user_role(),jsonb_build_object('action',p_action,'request',p_data,'result',result));return result;
end $$;
create function public.gama_accounting_audit(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_audit(p_action,p_data)$$;
revoke all on function public.gama_accounting_audit(text,jsonb),private.gama_accounting_audit(text,jsonb) from public,anon;
grant execute on function public.gama_accounting_audit(text,jsonb),private.gama_accounting_audit(text,jsonb) to authenticated;
revoke all on function private.gama_accounting_audit_read(text,jsonb),private.gama_accounting_audit_write(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
