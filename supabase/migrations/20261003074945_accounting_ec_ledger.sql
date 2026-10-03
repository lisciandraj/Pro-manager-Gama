-- Additive accounting workbench. Fiscal facts are supplied by the taxpayer;
-- this migration never invents a RUC, tax regime, SRI authorization_number or tax rate.
create table public.accounting_ec_profile (
 id boolean primary key default true check(id), taxpayer_kind text not null default 'natural' check(taxpayer_kind in ('natural','company')),
 regime text not null default 'unconfigured' check(regime in ('unconfigured','general','rimpe_business','rimpe_popular','other')),
 accounting_required boolean, withholding_agent boolean, ats_required boolean,
 establishments integer check(establishments between 1 and 999), confirmed_on date, evidence text,
 payroll_expense_account_id uuid references public.accounting_accounts(id), payroll_payable_account_id uuid references public.accounting_accounts(id),
 payroll_deductions_account_id uuid references public.accounting_accounts(id), retained_earnings_account_id uuid references public.accounting_accounts(id),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
insert into public.accounting_ec_profile(id) values(true);
create table public.accounting_payment_terms (
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 lines jsonb not null check(jsonb_typeof(lines)='array'),active boolean not null default true,created_at timestamptz not null default now()
);
create table public.accounting_maturities (
 id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 term_id uuid references public.accounting_payment_terms(id),due_date date not null,amount numeric(18,2) not null check(amount>0),position integer not null,
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and invoice_id is null and supplier_invoice_id is not null))
);
create index maturity_customer on public.accounting_maturities(invoice_id,due_date,position);
create index maturity_supplier on public.accounting_maturities(supplier_invoice_id,due_date,position);
create table public.accounting_fiscal_documents (
 id uuid primary key default gen_random_uuid(),source_type text not null check(source_type in ('sales_invoice','supplier_invoice','expense')),
 source_id uuid not null,document_type text not null check(document_type ~ '^[0-9]{2}$'),document_number text not null check(document_number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$'),
 identification_type text not null check(identification_type in ('04','05','06','07','08')),
 identification text not null check(length(btrim(identification)) between 3 and 20),authorization_number text not null check(authorization_number ~ '^[0-9]{10,49}$'),
 support_code text check(support_code ~ '^[0-9]{2}$'),payment_codes jsonb not null check(jsonb_typeof(payment_codes)='array'),related_party boolean not null default false,
 base_zero numeric(18,2) not null default 0 check(base_zero>=0),base_taxed numeric(18,2) not null default 0 check(base_taxed>=0),
 base_exempt numeric(18,2) not null default 0 check(base_exempt>=0),base_non_taxable numeric(18,2) not null default 0 check(base_non_taxable>=0),
 ice numeric(18,2) not null default 0 check(ice>=0),vat numeric(18,2) not null default 0 check(vat>=0),
 evidence text not null check(length(btrim(evidence))>=3),reviewed_at timestamptz not null default now(),reviewed_by uuid not null references auth.users(id),
 unique(source_type,source_id)
);
create table public.accounting_adjustments (
 id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),kind text not null check(kind in ('credit','debit')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 issued_on date not null,reference text not null check(length(btrim(reference)) between 3 and 100),reason text not null check(length(btrim(reason))>=3),
 net numeric(18,2) not null check(net>=0),tax numeric(18,2) not null check(tax>=0),total numeric(18,2) not null check(total>0 and total=net+tax),
 status text not null default 'posted' check(status in ('posted','cancelled')),entry_id uuid references public.accounting_entries(id),
 fiscal_authorization text,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and invoice_id is null and supplier_invoice_id is not null))
);
create index adjustment_customer on public.accounting_adjustments(invoice_id,status);
create index adjustment_supplier on public.accounting_adjustments(supplier_invoice_id,status);
create table public.accounting_withholdings (
 id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 issued_on date not null,number text not null check(number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$'),authorization_number text not null check(authorization_number ~ '^[0-9]{10,49}$'),
 evidence text not null check(length(btrim(evidence))>=3),amount numeric(18,2) not null check(amount>0),lines jsonb not null check(jsonb_typeof(lines)='array'),
 status text not null default 'posted' check(status in ('posted','cancelled')),entry_id uuid references public.accounting_entries(id),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and invoice_id is null and supplier_invoice_id is not null))
);
create index withholding_customer on public.accounting_withholdings(invoice_id,status);
create index withholding_supplier on public.accounting_withholdings(supplier_invoice_id,status);
create unique index withholding_supplier_number on public.accounting_withholdings(number) where side='supplier';
create table public.accounting_assets (
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 3 and 160),acquired_on date not null,
 cost numeric(18,2) not null check(cost>0),residual numeric(18,2) not null default 0 check(residual>=0 and residual<cost),months integer not null check(months between 1 and 1200),
 first_depreciation date not null,asset_account_id uuid not null references public.accounting_accounts(id),
 depreciation_account_id uuid not null references public.accounting_accounts(id),expense_account_id uuid not null references public.accounting_accounts(id),
 acquisition_entry_id uuid not null references public.accounting_entries(id),project_id uuid references public.pm_projects(id),
 status text not null default 'active' check(status in ('active','disposed')),created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check(first_depreciation>=acquired_on)
);
create table public.accounting_depreciations (
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references public.accounting_assets(id),period date not null,
 amount numeric(18,2) not null check(amount>0),entry_id uuid not null references public.accounting_entries(id),unique(asset_id,period)
);
create index depreciation_entry on public.accounting_depreciations(entry_id);
create table public.accounting_source_links (
 source_type text not null,source_id text not null,entry_id uuid not null references public.accounting_entries(id),
 primary key(source_type,source_id)
);
create index accounting_source_link_entry on public.accounting_source_links(entry_id);
create table private.accounting_ec_commands (
 request_key uuid primary key,actor uuid not null,action text not null,payload jsonb not null,result jsonb not null
);
revoke all on private.accounting_ec_commands from public,anon,authenticated;
alter table public.hr_payroll_payments add column financial_account_id uuid references public.financial_accounts(id);
create index payroll_payment_financial_account on public.hr_payroll_payments(financial_account_id);
alter table public.accounting_taxes add column valid_to date;
alter table public.accounting_taxes add constraint tax_valid_dates check(valid_to is null or valid_from is null or valid_to>=valid_from);
alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
alter table public.accounting_entries add constraint accounting_entries_source_type_check check(source_type in (
 'manual','sales_invoice','customer_payment','supplier_invoice','supplier_payment','expense','reversal','opening',
 'return_credit','return_refund','supplier_credit','customer_receipt','adjustment','withholding','payroll','payroll_payment','depreciation','year_close','stock_valuation'));
create index accounting_lines_project on public.accounting_entry_lines(project_id,entry_id) where project_id is not null;
create index accounting_lines_partner on public.accounting_entry_lines(partner_type,partner_id,entry_id) where partner_id is not null;
do $$declare t text;begin
 foreach t in array array['accounting_ec_profile','accounting_payment_terms','accounting_maturities','accounting_fiscal_documents','accounting_adjustments','accounting_withholdings','accounting_assets','accounting_depreciations','accounting_source_links'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy accounting_ec_read on public.%I for select to authenticated using(private.erp_module_allowed(''accounting'',array[''administrador'',''comercial'']) and private.gama_accounting_may(''view'') and private.gama_accounting_rights()->>''scope''=''all'')',t);
  execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;
end $$;

create function private.gama_ec_offsets(p_side text,p_invoice uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(case when kind='credit' then total else -total end) from public.accounting_adjustments
 where status='posted' and side=p_side and coalesce(invoice_id,supplier_invoice_id)=p_invoice),0)
 +coalesce((select sum(amount) from public.accounting_withholdings where status='posted' and side=p_side and coalesce(invoice_id,supplier_invoice_id)=p_invoice),0)
$$;
revoke all on function private.gama_ec_offsets(text,uuid) from public,anon,authenticated;
-- Preserve the public contracts used by sales, payment allocation and follow-up.
alter view private.gama_receivables rename to gama_receivables_before_ec;
create view private.gama_receivables with(security_invoker=true) as
select r.id,r.order_id,r.number,r.external_number,r.document_kind,r.fiscal_status,r.issue_date,r.subtotal,r.tax,r.total,
 r.payment_terms_days,r.payment_delivery_date,r.due_date,r.order_number,r.customer_id,r.customer_name,r.identification,r.email,r.paid,
 greatest(0,r.total-r.paid-coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=r.id),0)-private.gama_ec_offsets('customer',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when r.total<=r.paid+coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=r.id),0)+private.gama_ec_offsets('customer',r.id) then 'paid'
 when r.payment_status='paid' then 'pending' else r.payment_status end payment_status
from private.gama_receivables_before_ec r;
alter view private.gama_payables rename to gama_payables_before_ec;
create view private.gama_payables with(security_invoker=true) as
select r.id,r.number,r.supplier_id,r.supplier_name,r.purchase_order_id,r.issue_date,r.due_date,r.payment_terms_days,r.subtotal,r.tax,r.total,
 r.status,r.project_id,r.notes,r.paid,
 greatest(0,r.total-r.paid-coalesce((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=r.id),0)-private.gama_ec_offsets('supplier',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when r.total<=r.paid+coalesce((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=r.id),0)+private.gama_ec_offsets('supplier',r.id) then 'paid'
 when r.payment_status='paid' then 'pending' else r.payment_status end payment_status
from private.gama_payables_before_ec r;
revoke all on private.gama_receivables,private.gama_payables,private.gama_receivables_before_ec,private.gama_payables_before_ec from public,anon,authenticated;

-- Prevent a reversed source being posted again by an automatic resynchronization.
-- Serialize the source key; calls from an action and its trigger share one result.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
 if position('and status<>''reversed''' in s)=0 then raise exception 'POST_SOURCE_ANCHOR_MISSING';end if;
 s:=replace(s,'and status<>''reversed''','');
 s:=replace(s,' select id into eid from public.accounting_entries',
 ' perform pg_advisory_xact_lock(hashtextextended(p_source_type||p_source_id::text,0));'||E'\n'||' select id into eid from public.accounting_entries');
 execute s;
end $$;

create function private.gama_ec_account(p_id uuid,p_type text default null) returns uuid language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.accounting_accounts where id=p_id and active and (p_type is null or type=p_type)) then raise exception 'ACCOUNT_TYPE_REQUIRED:%',coalesce(p_type,'active');end if;
 return p_id;
end $$;
revoke all on function private.gama_ec_account(uuid,text) from public,anon,authenticated;

create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);
 d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);aid uuid:=nullif(p_data->>'account_id','')::uuid;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim integer:=least(2000,greatest(1,coalesce((p_data->>'limit')::integer,200)));
 snapshot_at timestamptz:=coalesce(nullif(p_data->>'snapshot_at','')::timestamptz,statement_timestamp());
 rows jsonb;cfg public.company_settings;prof public.accounting_ec_profile;blockers jsonb:='[]';n integer;begin
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 if p_action='context' then
 select * into cfg from public.company_settings where id;select * into prof from public.accounting_ec_profile where id;
 if coalesce(cfg.tax_id,'')!~'^[0-9]{13}$' then blockers:=blockers||jsonb_build_array('RUC_REQUIRED');end if;
 if prof.regime='unconfigured' or prof.confirmed_on is null then blockers:=blockers||jsonb_build_array('FISCAL_PROFILE_UNCONFIRMED');end if;
 if prof.accounting_required is null or prof.withholding_agent is null or prof.ats_required is null then blockers:=blockers||jsonb_build_array('OBLIGATIONS_UNCONFIRMED');end if;
 return jsonb_build_object('profile',to_jsonb(prof),'blockers',blockers,'currency',cfg.currency,
 'accounts',(select coalesce(jsonb_agg(to_jsonb(a) order by code),'[]') from public.accounting_accounts a where active),
 'journals',(select coalesce(jsonb_agg(to_jsonb(j) order by code),'[]') from public.accounting_journals j),
 'terms',(select coalesce(jsonb_agg(to_jsonb(t) order by name),'[]') from public.accounting_payment_terms t),
 'financial_accounts',(select coalesce(jsonb_agg(to_jsonb(f) order by name),'[]') from public.financial_accounts f where active),
 'projects',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.pm_projects),
 'partners',(select coalesce(jsonb_agg(to_jsonb(z) order by name),'[]') from (select id,name,'customer' side from public.customers union all select id,name,'supplier' side from public.suppliers)z),
 'taxes',(select coalesce(jsonb_agg(to_jsonb(t) order by code),'[]') from public.accounting_taxes t),
 'assets',(select coalesce(jsonb_agg(to_jsonb(a) order by name),'[]') from public.accounting_assets a),
 'unlinked_payroll',(select count(*) from public.hr_payroll p where status='validated' and not exists(select 1 from public.accounting_entries e where e.source_type='payroll' and e.source_id=p.id)),
 'payroll_payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'reference',p.reference,'paid_on',p.paid_on,'amount',p.amount)),'[]') from public.hr_payroll_payments p where status='confirmed' and financial_account_id is null),
 'valuations',(select coalesce(jsonb_agg(to_jsonb(z) order by sequence),'[]') from (select v.sequence,v.kind,v.value_delta,v.expense_delta,v.created_at,p.name from public.stock_valuation_entries v join public.products p on p.id=v.product_id where v.kind not in ('method','transfer') and not exists(select 1 from public.accounting_source_links l where l.source_type='stock_valuation' and l.source_id=v.sequence::text) order by v.sequence limit 250)z));
 elsif p_action='trial_balance' then
 with totals as(select a.id,a.code,a.name,a.type,
 coalesce(sum(l.debit-l.credit) filter(where e.entry_date<d1),0) opening,
 coalesce(sum(l.debit) filter(where e.entry_date between d1 and d2),0) debit,
 coalesce(sum(l.credit) filter(where e.entry_date between d1 and d2),0) credit
 from public.accounting_accounts a left join public.accounting_entry_lines l on l.account_id=a.id
 left join public.accounting_entries e on e.id=l.entry_id and e.status in ('posted','reversed') and e.entry_date<=d2
 group by a.id)
 select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('closing',opening+debit-credit) order by code),'[]') into rows from totals t;
 return jsonb_build_object('from',d1,'to',d2,'rows',rows,'debit',(select coalesce(sum((v->>'debit')::numeric),0) from jsonb_array_elements(rows)v),'credit',(select coalesce(sum((v->>'credit')::numeric),0) from jsonb_array_elements(rows)v));
 elsif p_action='general_ledger' or p_action='partner_ledger' then
 with movements as(select l.*,e.number,e.entry_date,e.reference,e.source_type,e.source_id,e.created_at,j.code journal_code,a.code,a.name account_name,
 coalesce((select sum(x.debit-x.credit) from public.accounting_entry_lines x join public.accounting_entries en on en.id=x.entry_id
 where x.account_id=l.account_id and en.status in ('posted','reversed') and en.entry_date<d1 and coalesce(en.posted_at,en.created_at)<=snapshot_at
 and (p_action<>'partner_ledger' or (x.partner_type=p_data->>'partner_type' and x.partner_id=(p_data->>'partner_id')::uuid))),0)
 +sum(l.debit-l.credit) over(partition by l.account_id order by e.entry_date,e.created_at,e.id,l.position,l.id) running_balance
 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id join public.accounting_journals j on j.id=e.journal_id
 where e.status in ('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date between d1 and d2 and (aid is null or l.account_id=aid)
 and (p_action<>'partner_ledger' or (l.partner_type=p_data->>'partner_type' and l.partner_id=(p_data->>'partner_id')::uuid)))
 select jsonb_build_object('from',d1,'to',d2,'offset',off,'limit',lim,'snapshot_at',snapshot_at,'total',(select count(*) from movements),
 'rows',coalesce((select jsonb_agg(to_jsonb(z) order by code,entry_date,created_at,entry_id,position,id) from (select * from movements order by code,entry_date,created_at,entry_id,position,id offset off limit lim)z),'[]')) into rows;
 return rows;
 elsif p_action='analytic' then
 return jsonb_build_object('from',d1,'to',d2,'rows',coalesce((select jsonb_agg(to_jsonb(z) order by name) from(
 select p.id,p.name,coalesce(sum(l.credit-l.debit) filter(where a.type='income'),0) revenue,
 coalesce(sum(l.debit-l.credit) filter(where a.type='expense'),0) expense
 from public.pm_projects p left join public.accounting_entry_lines l on l.project_id=p.id
 left join public.accounting_entries e on e.id=l.entry_id left join public.accounting_accounts a on a.id=l.account_id
 where e.status in ('posted','reversed') and e.entry_date between d1 and d2 group by p.id)z),'[]'));
 elsif p_action='maturities' then
 return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by due_date,position) from (
 select m.*,coalesce(r.number,s.number) number,coalesce(r.customer_name,s.supplier_name) partner_name,
 greatest(0,least(m.amount,coalesce(r.balance,s.balance)-coalesce(sum(m.amount) over(partition by m.side,coalesce(m.invoice_id,m.supplier_invoice_id) order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0))) balance
 from public.accounting_maturities m left join private.gama_receivables r on r.id=m.invoice_id left join private.gama_payables s on s.id=m.supplier_invoice_id
 where coalesce(r.payment_status,s.payment_status)<>'cancelled')z),'[]'));
 elsif p_action='adjustments' then
 return jsonb_build_object('adjustments',(select coalesce(jsonb_agg(to_jsonb(z) order by issued_on desc),'[]') from public.accounting_adjustments z),
 'withholdings',(select coalesce(jsonb_agg(to_jsonb(z) order by issued_on desc),'[]') from public.accounting_withholdings z));
 elsif p_action='fiscal_review' then
 select * into cfg from public.company_settings where id;select * into prof from public.accounting_ec_profile where id;
 if coalesce(cfg.tax_id,'')!~'^[0-9]{13}$' then blockers:=blockers||jsonb_build_array('RUC_REQUIRED');end if;
 if prof.confirmed_on is null or prof.ats_required is null then blockers:=blockers||jsonb_build_array('OBLIGATIONS_UNCONFIRMED');end if;
 return jsonb_build_object('from',d1,'to',d2,'profile',to_jsonb(prof),'company',jsonb_build_object('tax_id',cfg.tax_id,'legal_name',cfg.legal_name),
 'blockers',blockers,'documents',coalesce((select jsonb_agg(to_jsonb(z) order by issue_date,source_id) from (
 select 'sales_invoice' source_type,r.id source_id,r.number,r.issue_date,r.customer_name partner_name,r.identification partner_identification,r.subtotal,r.tax,r.total,f.id fiscal_id,to_jsonb(f) fiscal
 from private.gama_receivables r left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=r.id where r.issue_date between d1 and d2 and r.payment_status<>'cancelled'
 union all select 'supplier_invoice',r.id,r.number,r.issue_date,r.supplier_name,null,r.subtotal,r.tax,r.total,f.id,to_jsonb(f) from private.gama_payables r left join public.accounting_fiscal_documents f on f.source_type='supplier_invoice' and f.source_id=r.id where r.issue_date between d1 and d2 and r.status='posted'
 union all select 'expense',r.id,r.reference,r.expense_date,r.description,null,r.amount_untaxed,r.tax_amount,r.amount_total,f.id,to_jsonb(f) from public.expenses r left join public.accounting_fiscal_documents f on f.source_type='expense' and f.source_id=r.id where r.expense_date between d1 and d2 and r.status='posted')z),'[]'),
 'adjustments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.accounting_adjustments a where a.status='posted' and a.issued_on between d1 and d2),
 'withholdings',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.accounting_withholdings a where a.status='posted' and a.issued_on between d1 and d2),
 'return_credits',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.return_credits a where a.issued_on between d1 and d2),
 'cancelled_documents',(select count(*) from public.external_invoices where issue_date between d1 and d2 and fiscal_status in ('cancelled','rejected')));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;

create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings;prof public.accounting_ec_profile;r record;inv record;item jsonb;lines jsonb:='[]';eid uuid;rid uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 side text:=p_data->>'side';iid uuid:=nullif(p_data->>'invoice_id','')::uuid;partner uuid;balance numeric;total numeric;net numeric;tax numeric;amt numeric;rate numeric;base numeric;d date;position integer:=0;aid uuid;counter uuid;kind text;startdate date;enddate date;months integer;begin
 select * into cfg from public.company_settings where id;select * into prof from public.accounting_ec_profile where id;
 if p_action='profile_save' then
 if p_data->>'regime'<>'unconfigured' and (nullif(p_data->>'confirmed_on','') is null or length(btrim(coalesce(p_data->>'evidence','')))<3) then raise exception 'FISCAL_EVIDENCE_REQUIRED';end if;
 update public.accounting_ec_profile set taxpayer_kind=p_data->>'taxpayer_kind',regime=p_data->>'regime',accounting_required=(p_data->>'accounting_required')::boolean,
 withholding_agent=(p_data->>'withholding_agent')::boolean,ats_required=(p_data->>'ats_required')::boolean,establishments=nullif(p_data->>'establishments','')::integer,
 confirmed_on=nullif(p_data->>'confirmed_on','')::date,evidence=p_data->>'evidence',updated_at=now(),updated_by=auth.uid(),
 payroll_expense_account_id=nullif(p_data->>'payroll_expense_account_id','')::uuid,payroll_payable_account_id=nullif(p_data->>'payroll_payable_account_id','')::uuid,
 payroll_deductions_account_id=nullif(p_data->>'payroll_deductions_account_id','')::uuid,retained_earnings_account_id=nullif(p_data->>'retained_earnings_account_id','')::uuid where id;
 return jsonb_build_object('ok',true);
 elsif p_action='journal_save' then
 insert into public.accounting_journals(id,code,name,kind,active,financial_account_id) values(rid,upper(btrim(p_data->>'code')),btrim(p_data->>'name'),p_data->>'kind',coalesce((p_data->>'active')::boolean,true),nullif(p_data->>'financial_account_id','')::uuid)
 on conflict(id) do update set name=excluded.name,active=excluded.active,financial_account_id=excluded.financial_account_id;
 return jsonb_build_object('id',rid);
 elsif p_action='term_save' then
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 24 then raise exception 'INVALID_TERMS';end if;
 total:=0;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 rate:=(item->>'percent')::numeric;if rate is null or rate<=0 or rate>100 or (item->>'days')::integer not between 0 and 3650 then raise exception 'INVALID_TERMS';end if;
 total:=total+rate;
 end loop;
 if total<>100 then raise exception 'TERMS_MUST_TOTAL_100';end if;
 insert into public.accounting_payment_terms(id,name,lines,active) values(rid,btrim(p_data->>'name'),p_data->'lines',coalesce((p_data->>'active')::boolean,true))
 on conflict(id) do update set name=excluded.name,lines=excluded.lines,active=excluded.active;
 return jsonb_build_object('id',rid);
 elsif p_action='schedule_save' then
 if side='customer' then
 perform 1 from public.external_invoices where id=iid for update;
 select * into inv from private.gama_receivables where id=iid and payment_status<>'cancelled';d:=inv.payment_delivery_date;
 else
 perform 1 from public.supplier_invoices where id=iid for update;
 select * into inv from private.gama_payables where id=iid and status='posted';d:=inv.issue_date;
 end if;
 if inv.id is null then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 if d is null then raise exception 'DELIVERY_DATE_REQUIRED';end if;
 select * into r from public.accounting_payment_terms where id=(p_data->>'term_id')::uuid and active;if not found then raise exception 'TERM_REQUIRED';end if;
 delete from public.accounting_maturities where coalesce(invoice_id,supplier_invoice_id)=iid and accounting_maturities.side=p_data->>'side';
 total:=0;months:=jsonb_array_length(r.lines);
 for item in select value from jsonb_array_elements(r.lines) loop
 position:=position+1;amt:=case when position=months then inv.total-total else least(inv.total-total,round(inv.total*(item->>'percent')::numeric/100,2)) end;total:=total+amt;
 if amt>0 then insert into public.accounting_maturities(side,invoice_id,supplier_invoice_id,term_id,due_date,amount,position)
 values(side,case when side='customer' then iid end,case when side='supplier' then iid end,r.id,d+(item->>'days')::integer,amt,position);end if;
 end loop;
 return jsonb_build_object('total',total,'count',position);
 elsif p_action in ('adjustment_post','withholding_post') then
 if side='customer' then
 perform 1 from public.external_invoices where id=iid for update;select * into inv from private.gama_receivables where id=iid and payment_status<>'cancelled';partner:=inv.customer_id;
 else
 perform 1 from public.supplier_invoices where id=iid for update;select * into inv from private.gama_payables where id=iid and status='posted';partner:=inv.supplier_id;
 end if;
 if inv.id is null then raise exception 'INVOICE_NOT_AVAILABLE';end if;balance:=inv.balance;d:=(p_data->>'issued_on')::date;
 if d<inv.issue_date then raise exception 'DOCUMENT_DATE_BEFORE_INVOICE';end if;
 -- Ensure the original invoice is in the ledger before any offset is posted.
 perform private.gama_accounting_post(case when side='customer' then 'sales_invoice' else 'supplier_invoice' end,iid);
 aid:=private.gama_ec_account(case when side='customer' then cfg.receivable_account_id else cfg.payable_account_id end,case when side='customer' then 'asset' else 'liability' end);
 if p_action='adjustment_post' then
 net:=round((p_data->>'net')::numeric,2);tax:=round((p_data->>'tax')::numeric,2);total:=net+tax;kind:=p_data->>'kind';
 if total is null or total<=0 or net<0 or tax<0 or kind not in ('credit','debit') then raise exception 'INVALID_AMOUNT';end if;
 if kind='credit' and total>balance then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 counter:=private.gama_ec_account(case when side='customer' then cfg.sales_account_id else cfg.purchase_account_id end);
 lines:=jsonb_build_array(jsonb_build_object('account_id',aid,'partner_type',side,'partner_id',partner,
 'debit',case when (side='customer')=(kind='debit') then total else 0 end,'credit',case when (side='customer')=(kind='credit') then total else 0 end),
 jsonb_build_object('account_id',counter,'debit',case when (side='customer')=(kind='credit') then net else 0 end,'credit',case when (side='customer')=(kind='debit') then net else 0 end),
 jsonb_build_object('account_id',case when side='customer' then cfg.tax_collected_account_id else cfg.tax_deductible_account_id end,
 'debit',case when (side='customer')=(kind='credit') then tax else 0 end,'credit',case when (side='customer')=(kind='debit') then tax else 0 end));
 eid:=private.gama_accounting_book(case when side='customer' then 'VTA' else 'CMP' end,d,p_data->>'reference','adjustment',rid,p_data->>'reason',lines);
 insert into public.accounting_adjustments(id,side,kind,invoice_id,supplier_invoice_id,issued_on,reference,reason,net,tax,total,entry_id,fiscal_authorization,created_by)
 values(rid,side,kind,case when side='customer' then iid end,case when side='supplier' then iid end,d,p_data->>'reference',p_data->>'reason',net,tax,total,eid,nullif(p_data->>'fiscal_authorization',''),auth.uid());
 else
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 50 then raise exception 'INVALID_LINES';end if;
 total:=0;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 base:=(item->>'base')::numeric;rate:=(item->>'rate')::numeric;amt:=round(base*rate/100,2);
 if base is null or rate is null or base<=0 or rate<=0 or rate>100 or amt<=0 or item->>'tax_kind' not in ('vat','income') or coalesce(item->>'code','')!~'^[0-9]{1,5}$' then raise exception 'INVALID_WITHHOLDING';end if;
 if (item->>'tax_kind'='vat' and base>inv.tax) or (item->>'tax_kind'='income' and base>inv.subtotal) then raise exception 'WITHHOLDING_BASE_EXCEEDED';end if;
 counter:=private.gama_ec_account((item->>'account_id')::uuid,case when side='customer' then 'asset' else 'liability' end);
 total:=total+amt;lines:=lines||jsonb_build_array(jsonb_build_object('account_id',counter,'debit',case when side='customer' then amt else 0 end,'credit',case when side='supplier' then amt else 0 end));
 end loop;
 if total>balance then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',aid,'partner_type',side,'partner_id',partner,'debit',case when side='supplier' then total else 0 end,'credit',case when side='customer' then total else 0 end));
 eid:=private.gama_accounting_book('OD',d,p_data->>'number','withholding',rid,'Retención documentada',lines);
 insert into public.accounting_withholdings(id,side,invoice_id,supplier_invoice_id,issued_on,number,authorization_number,evidence,amount,lines,entry_id,created_by)
 values(rid,side,case when side='customer' then iid end,case when side='supplier' then iid end,d,p_data->>'number',p_data->>'authorization_number',p_data->>'evidence',total,p_data->'lines',eid,auth.uid());
 end if;
 return jsonb_build_object('id',rid,'entry_id',eid,'amount',total,'balance',balance-case when p_action='adjustment_post' and kind='debit' then -total else total end);
 elsif p_action in ('adjustment_cancel','withholding_cancel') then
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 if p_action='adjustment_cancel' then select * into r from public.accounting_adjustments where id=rid for update;
 else select * into r from public.accounting_withholdings where id=rid for update;end if;
 if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
 if r.status='cancelled' then return jsonb_build_object('id',rid);end if;
 eid:=private.gama_accounting_reverse(r.entry_id,p_data->>'reason');
 if p_action='adjustment_cancel' then update public.accounting_adjustments set status='cancelled' where id=rid;else update public.accounting_withholdings set status='cancelled' where id=rid;end if;
 return jsonb_build_object('id',rid,'entry_id',eid);
 elsif p_action='fiscal_save' then
 if p_data->>'source_type'='sales_invoice' then select f.subtotal,f.tax,f.total into inv from public.external_invoices f where f.id=(p_data->>'source_id')::uuid and fiscal_status not in ('cancelled','rejected');
 elsif p_data->>'source_type'='supplier_invoice' then select f.subtotal,f.tax,f.total into inv from public.supplier_invoices f where f.id=(p_data->>'source_id')::uuid and status='posted';
 elsif p_data->>'source_type'='expense' then select amount_untaxed subtotal,tax_amount tax,amount_total total into inv from public.expenses where id=(p_data->>'source_id')::uuid and status='posted';end if;
 if inv.total is null then raise exception 'DOCUMENT_NOT_FOUND';end if;
 total:=coalesce((p_data->>'base_zero')::numeric,0)+coalesce((p_data->>'base_taxed')::numeric,0)+coalesce((p_data->>'base_exempt')::numeric,0)+coalesce((p_data->>'base_non_taxable')::numeric,0);
 if total<>inv.subtotal or (p_data->>'vat')::numeric<>inv.tax or total+coalesce((p_data->>'ice')::numeric,0)+(p_data->>'vat')::numeric<>inv.total then raise exception 'FISCAL_TOTAL_MISMATCH';end if;
 if jsonb_typeof(p_data->'payment_codes') is distinct from 'array' or jsonb_array_length(p_data->'payment_codes')=0 then raise exception 'PAYMENT_CODE_REQUIRED';end if;
 for item in select value from jsonb_array_elements(p_data->'payment_codes') loop if item#>>'{}' not in ('01','15','16','17','18','19','20','21') then raise exception 'PAYMENT_CODE_REQUIRED';end if;end loop;
 if p_data->>'identification_type'='04' and coalesce(p_data->>'identification','')!~'^[0-9]{13}$' then raise exception 'RUC_REQUIRED';end if;
 insert into public.accounting_fiscal_documents(source_type,source_id,document_type,document_number,identification_type,identification,authorization_number,support_code,payment_codes,related_party,base_zero,base_taxed,base_exempt,base_non_taxable,ice,vat,evidence,reviewed_by)
 values(p_data->>'source_type',(p_data->>'source_id')::uuid,p_data->>'document_type',p_data->>'document_number',p_data->>'identification_type',p_data->>'identification',p_data->>'authorization_number',nullif(p_data->>'support_code',''),p_data->'payment_codes',coalesce((p_data->>'related_party')::boolean,false),coalesce((p_data->>'base_zero')::numeric,0),coalesce((p_data->>'base_taxed')::numeric,0),coalesce((p_data->>'base_exempt')::numeric,0),coalesce((p_data->>'base_non_taxable')::numeric,0),coalesce((p_data->>'ice')::numeric,0),(p_data->>'vat')::numeric,p_data->>'evidence',auth.uid())
 on conflict(source_type,source_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,identification_type=excluded.identification_type,identification=excluded.identification,authorization_number=excluded.authorization_number,support_code=excluded.support_code,payment_codes=excluded.payment_codes,related_party=excluded.related_party,base_zero=excluded.base_zero,base_taxed=excluded.base_taxed,base_exempt=excluded.base_exempt,base_non_taxable=excluded.base_non_taxable,ice=excluded.ice,vat=excluded.vat,evidence=excluded.evidence,reviewed_by=excluded.reviewed_by,reviewed_at=now() returning id into rid;
 return jsonb_build_object('id',rid);
 elsif p_action='opening_post' then
 select * into r from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active for update;
 if not found or r.currency<>cfg.currency or r.account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if exists(select 1 from public.accounting_entries where source_type='opening' and source_id=r.id) then raise exception 'OPENING_ALREADY_POSTED';end if;
 if r.opening_balance=0 then raise exception 'ENTRY_EMPTY';end if;
 counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,'equity');aid:=private.gama_ec_account(r.account_id,'asset');
 amt:=abs(r.opening_balance);
 eid:=private.gama_accounting_book('OD',(p_data->>'entry_date')::date,r.name,'opening',r.id,'Saldo inicial de tesorería',jsonb_build_array(
 jsonb_build_object('account_id',aid,'debit',case when r.opening_balance>0 then amt else 0 end,'credit',case when r.opening_balance<0 then amt else 0 end),
 jsonb_build_object('account_id',counter,'credit',case when r.opening_balance>0 then amt else 0 end,'debit',case when r.opening_balance<0 then amt else 0 end)));
 return jsonb_build_object('entry_id',eid);
 elsif p_action='year_close' then
 startdate:=(p_data->>'from')::date;enddate:=(p_data->>'to')::date;
 if startdate is null or enddate is null or startdate>=enddate or extract(month from startdate)<>cfg.fiscal_year_start_month or extract(day from startdate)<>1 or enddate<>(startdate+interval '1 year -1 day')::date then raise exception 'INVALID_FISCAL_YEAR';end if;
 if enddate>current_date then raise exception 'YEAR_NOT_FINISHED';end if;
 if exists(select 1 from public.accounting_entries where source_type='year_close' and entry_date=enddate) then raise exception 'YEAR_ALREADY_CLOSED';end if;
 if exists(select 1 from public.accounting_entries where entry_date between startdate and enddate and status='draft') then raise exception 'DRAFT_ENTRIES_REMAIN';end if;
 counter:=private.gama_ec_account(prof.retained_earnings_account_id,'equity');total:=0;
 for r in select a.id,sum(l.debit-l.credit) balance from public.accounting_accounts a join public.accounting_entry_lines l on l.account_id=a.id join public.accounting_entries e on e.id=l.entry_id
 where a.type in ('income','expense') and e.status in ('posted','reversed') and e.entry_date between startdate and enddate group by a.id having sum(l.debit-l.credit)<>0 loop
 total:=total+r.balance;lines:=lines||jsonb_build_array(jsonb_build_object('account_id',r.id,'debit',greatest(0,-r.balance),'credit',greatest(0,r.balance)));end loop;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',counter,'debit',greatest(0,total),'credit',greatest(0,-total)));
 eid:=private.gama_accounting_book('OD',enddate,'Cierre '||extract(year from enddate)::text,'year_close',rid,'Transferencia del resultado',lines);
 -- Lock every month, including months without transactions.
 for d in select generate_series(startdate,enddate,interval '1 month')::date loop perform private.gama_accounting_period(d);update public.accounting_periods set status='closed',closed_at=now(),closed_by=auth.uid() where period_start=d;end loop;
 return jsonb_build_object('entry_id',eid,'result',-total);
 elsif p_action='asset_save' then
 aid:=private.gama_ec_account((p_data->>'asset_account_id')::uuid,'asset');counter:=private.gama_ec_account((p_data->>'depreciation_account_id')::uuid,'asset');perform private.gama_ec_account((p_data->>'expense_account_id')::uuid,'expense');
 if aid=counter then raise exception 'ASSET_ACCOUNTS_DISTINCT';end if;
 eid:=(p_data->>'acquisition_entry_id')::uuid;
 if not exists(select 1 from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where e.id=eid and e.status='posted' and l.account_id=aid and l.debit>0) then raise exception 'ASSET_ACQUISITION_REQUIRED';end if;
 total:=(p_data->>'cost')::numeric;
 if total-coalesce((p_data->>'residual')::numeric,0)<(p_data->>'months')::integer*0.01 then raise exception 'ASSET_MONTHLY_AMOUNT_TOO_SMALL';end if;
 if total>(select coalesce(sum(debit-credit),0) from public.accounting_entry_lines where entry_id=eid and account_id=aid)-coalesce((select sum(cost) from public.accounting_assets where acquisition_entry_id=eid and asset_account_id=aid),0) then raise exception 'ASSET_COST_EXCEEDED';end if;
 insert into public.accounting_assets(id,name,acquired_on,cost,residual,months,first_depreciation,asset_account_id,depreciation_account_id,expense_account_id,acquisition_entry_id,project_id,created_by)
 values(rid,p_data->>'name',(p_data->>'acquired_on')::date,total,coalesce((p_data->>'residual')::numeric,0),(p_data->>'months')::integer,(p_data->>'first_depreciation')::date,aid,counter,(p_data->>'expense_account_id')::uuid,eid,nullif(p_data->>'project_id','')::uuid,auth.uid());
 return jsonb_build_object('id',rid);
 elsif p_action='depreciation_post' then
 select * into r from public.accounting_assets where id=rid and status='active' for update;if not found then raise exception 'ASSET_REQUIRED';end if;
 d:=(p_data->>'period')::date;months:=(extract(year from age(date_trunc('month',d),date_trunc('month',r.first_depreciation)))::integer*12+extract(month from age(date_trunc('month',d),date_trunc('month',r.first_depreciation)))::integer);
 if d is null or d<>(date_trunc('month',d)+interval '1 month -1 day')::date or months<0 or months>=r.months then raise exception 'INVALID_DEPRECIATION_PERIOD';end if;
 if exists(select 1 from public.accounting_depreciations where asset_id=rid and period=d) then raise exception 'DEPRECIATION_ALREADY_POSTED';end if;
 if (select count(*) from public.accounting_depreciations where asset_id=rid)<>months then raise exception 'DEPRECIATION_PREVIOUS_PERIOD_REQUIRED';end if;
 amt:=case when months=r.months-1 then r.cost-r.residual-coalesce((select sum(amount) from public.accounting_depreciations where asset_id=rid),0) else round((r.cost-r.residual)/r.months,2) end;
 eid:=private.gama_accounting_book('OD',d,r.name,'depreciation',gen_random_uuid(),'Amortización mensual',jsonb_build_array(jsonb_build_object('account_id',r.expense_account_id,'debit',amt,'project_id',r.project_id),jsonb_build_object('account_id',r.depreciation_account_id,'credit',amt,'project_id',r.project_id)));
 insert into public.accounting_depreciations(asset_id,period,amount,entry_id) values(rid,d,amt,eid);return jsonb_build_object('entry_id',eid,'amount',amt);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;

create function private.gama_accounting_ec(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.accounting_ec_commands;result jsonb;permission text;begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('context','trial_balance','general_ledger','partner_ledger','analytic','maturities','adjustments','fiscal_review') then
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 return private.gama_accounting_ec_read(p_action,p_data);
 end if;
 permission:=case when p_action in ('profile_save','journal_save','term_save','schedule_save','fiscal_save','chart_import','tax_dates_save','allocation_save') then 'edit' when p_action='year_close' then 'close' else 'validate' end;
 if not coalesce((rights->>permission)::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting_ec:'||key::text,0));
 select * into receipt from private.accounting_ec_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 result:=private.gama_accounting_ec_write(p_action,p_data);
 insert into private.accounting_ec_commands values(key,auth.uid(),p_action,p_data,result);return result;
end $$;
revoke all on function private.gama_accounting_ec(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_ec(text,jsonb) to authenticated;
create function public.gama_accounting_ec(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_ec(p_action,p_data)$$;
revoke all on function public.gama_accounting_ec(text,jsonb) from public,anon;
grant execute on function public.gama_accounting_ec(text,jsonb) to authenticated;

-- Atomic source posting replaces the old dependency on opening Accounting.
-- Closed-period failures propagate and roll back the originating business action.
create function private.gama_ec_source_post() returns trigger language plpgsql security definer set search_path='' as $$
declare src text:=tg_argv[0];eligible boolean;oldeligible boolean:=false;e public.accounting_entries;j jsonb:=to_jsonb(new);o jsonb:=to_jsonb(old);guardkeys text[];begin
 if tg_table_name='external_invoices' then eligible:=new.fiscal_status not in ('cancelled','rejected');guardkeys:=array['subtotal','tax','total','issue_date','order_id'];
 elsif tg_table_name in ('external_invoice_payments','supplier_invoice_payments') then eligible:=new.status='confirmed';guardkeys:=array['invoice_id','supplier_invoice_id','amount','paid_at','receipt_id','financial_account_id'];
 elsif tg_table_name in ('expenses','supplier_invoices') then eligible:=new.status='posted';guardkeys:=array['subtotal','tax','total','amount_untaxed','tax_amount','amount_total','supplier_id','issue_date','expense_date','financial_account_id','category_id','project_id'];
 else eligible:=true;guardkeys:=array['amount','invoice_id','supplier_invoice_id','return_id','issued_on','paid_at','financial_account_id'];end if;
 if tg_table_name='return_credits' and exists(select 1 from public.return_orders where id=(j->>'return_id')::uuid and kind='supplier') then src:='supplier_credit';end if;
 select * into e from public.accounting_entries where source_type=src and source_id=new.id order by created_at limit 1;
 if tg_op='UPDATE' and e.id is not null then
 if eligible and exists(select 1 from unnest(guardkeys) k where j->k is distinct from o->k) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 if not eligible and e.status='posted' then perform private.gama_accounting_reverse(e.id,coalesce(nullif(j->>'cancellation_reason',''),'Anulación del documento de origen'));end if;
 else if eligible then perform private.gama_accounting_post(src,new.id);end if;end if;
 return new;
end $$;
revoke all on function private.gama_ec_source_post() from public,anon,authenticated;
create trigger ec_source_post after insert or update on public.external_invoices for each row execute function private.gama_ec_source_post('sales_invoice');
create trigger ec_source_post after insert or update on public.external_invoice_payments for each row execute function private.gama_ec_source_post('customer_payment');
create trigger ec_source_post after insert or update on public.supplier_invoices for each row execute function private.gama_ec_source_post('supplier_invoice');
create trigger ec_source_post after insert or update on public.supplier_invoice_payments for each row execute function private.gama_ec_source_post('supplier_payment');
create trigger ec_source_post after insert or update on public.expenses for each row execute function private.gama_ec_source_post('expense');
create trigger ec_source_post after insert or update on public.return_credits for each row execute function private.gama_ec_source_post('return_credit');
create trigger ec_source_post after insert or update on public.return_refunds for each row execute function private.gama_ec_source_post('return_refund');
-- Existing cancellation actions and the source trigger can request the same reversal.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reverse(uuid,text)'::regprocedure);
 s:=replace(s,'where id=p_entry;','where id=p_entry for update;');
 s:=replace(s,'if e.status<>''posted'' then','if e.status=''reversed'' then return (select id from public.accounting_entries where reversal_of=p_entry and status=''posted'' limit 1);end if; if e.status<>''posted'' then');execute s;
end $$;

create function private.gama_ec_payroll_post(p_id uuid,p_payment boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare prof public.accounting_ec_profile;r record;f public.financial_accounts;cfg public.company_settings;eid uuid;aid uuid;counter uuid;lines jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended('payroll:'||p_id::text,0));
 select id into eid from public.accounting_entries where source_type=case when p_payment then 'payroll_payment' else 'payroll' end and source_id=p_id;
 if found then return eid;end if;
 select * into prof from public.accounting_ec_profile where id;
 if prof.payroll_expense_account_id is null or prof.payroll_payable_account_id is null or prof.payroll_deductions_account_id is null then raise exception 'PAYROLL_ACCOUNTS_REQUIRED';end if;
 aid:=private.gama_ec_account(prof.payroll_payable_account_id,'liability');
 if p_payment then
 select * into r from public.hr_payroll_payments where id=p_id and status='confirmed';if not found then raise exception 'PAYROLL_PAYMENT_REQUIRED';end if;
 select * into cfg from public.company_settings where id;select * into f from public.financial_accounts where id=r.financial_account_id and active and currency=cfg.currency;
 if f.account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 perform private.gama_ec_payroll_post(r.payroll_id,false);
 eid:=private.gama_accounting_book(case when f.kind='cash' then 'CAJ' else 'BAN' end,r.paid_on,r.reference,'payroll_payment',r.id,'Pago de nómina',jsonb_build_array(jsonb_build_object('account_id',aid,'debit',r.amount),jsonb_build_object('account_id',f.account_id,'credit',r.amount)));
 else
 select * into r from public.hr_payroll where id=p_id and status='validated';if not found then raise exception 'PAYROLL_REQUIRED';end if;
 counter:=private.gama_ec_account(prof.payroll_deductions_account_id,'liability');perform private.gama_ec_account(prof.payroll_expense_account_id,'expense');
 if r.employer_cost=0 then raise exception 'ENTRY_EMPTY';end if;
 eid:=private.gama_accounting_book('OD',(r.period+interval '1 month -1 day')::date,r.source_ref,'payroll',r.id,'Nómina validada: coste, neto y obligaciones',jsonb_build_array(jsonb_build_object('account_id',prof.payroll_expense_account_id,'debit',r.employer_cost),jsonb_build_object('account_id',aid,'credit',r.net),jsonb_build_object('account_id',counter,'credit',r.employer_cost-r.net)));
 end if;return eid;
end $$;
revoke all on function private.gama_ec_payroll_post(uuid,boolean) from public,anon,authenticated;
create function private.gama_ec_payroll_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;prof public.accounting_ec_profile;eligible boolean;src text:=case when tg_table_name='hr_payroll' then 'payroll' else 'payroll_payment' end;begin
 select * into e from public.accounting_entries where source_type=src and source_id=new.id;
 eligible:=case when src='payroll' then new.status='validated' else new.status='confirmed' end;
 if e.id is not null then
 if tg_op='UPDATE' and eligible and (to_jsonb(new)-'status'-'reason') is distinct from (to_jsonb(old)-'status'-'reason') then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 if not eligible and e.status='posted' then perform private.gama_accounting_reverse(e.id,'Anulación de nómina');end if;
 else
 select * into prof from public.accounting_ec_profile where id;
 if eligible and prof.payroll_expense_account_id is not null and prof.payroll_payable_account_id is not null and prof.payroll_deductions_account_id is not null then
 if src='payroll' or new.financial_account_id is not null then perform private.gama_ec_payroll_post(new.id,src='payroll_payment');end if;
 end if;
 end if;return new;
end $$;
revoke all on function private.gama_ec_payroll_trigger() from public,anon,authenticated;
create trigger ec_payroll_post after insert or update on public.hr_payroll for each row execute function private.gama_ec_payroll_trigger();
create trigger ec_payroll_post after insert or update on public.hr_payroll_payments for each row execute function private.gama_ec_payroll_trigger();
-- Deferred composite row access must not touch payment-only fields on a payroll row.
-- Separate branch avoids PostgreSQL's eager field resolution on trigger records.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_ec_payroll_trigger()'::regprocedure);
 s:=replace(s,'if src=''payroll'' or new.financial_account_id is not null then perform private.gama_ec_payroll_post(new.id,src=''payroll_payment'');end if;',
 'if src=''payroll'' then perform private.gama_ec_payroll_post(new.id,false);elsif (to_jsonb(new)->>''financial_account_id'') is not null then perform private.gama_ec_payroll_post(new.id,true);end if;');execute s;
end $$;

-- Payroll outflows now participate in the existing cash position without
-- counting the payroll accrual as a cash expense.
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_cash_position'::regclass,true);
 if position(' AS current_balance' in s)=0 then raise exception 'CASH_POSITION_ANCHOR';end if;
 s:=replace(s,' AS current_balance',' - coalesce((select sum(hp.amount) from public.hr_payroll_payments hp where hp.financial_account_id=f.id and hp.status=''confirmed''),0) AS current_balance');
 execute 'create or replace view private.gama_cash_position with(security_invoker=true) as '||s;
end $$;

-- The integration commands share the same authorization/idempotency wrapper.
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_base;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;b public.stock_cost_books;eid uuid;counter uuid;stock uuid;expense uuid;v numeric;c numeric;lines jsonb:='[]';rid uuid;begin
 if p_action='payroll_sync' then
 for r in select id from public.hr_payroll where status='validated' order by period,id loop perform private.gama_ec_payroll_post(r.id,false);end loop;
 for r in select id from public.hr_payroll_payments where status='confirmed' and financial_account_id is not null order by paid_on,id loop perform private.gama_ec_payroll_post(r.id,true);end loop;
 return jsonb_build_object('ok',true);
 elsif p_action='payroll_payment_link' then
 update public.hr_payroll_payments set financial_account_id=(p_data->>'financial_account_id')::uuid where id=(p_data->>'id')::uuid and status='confirmed';
 if not found then raise exception 'PAYROLL_PAYMENT_REQUIRED';end if;
 eid:=private.gama_ec_payroll_post((p_data->>'id')::uuid,true);return jsonb_build_object('entry_id',eid);
 elsif p_action='valuation_post' then
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 select * into r from public.stock_valuation_entries where sequence=(p_data->>'sequence')::bigint for update;if not found then raise exception 'VALUATION_REQUIRED';end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_valuation' and source_id=r.sequence::text) then raise exception 'VALUATION_ALREADY_POSTED';end if;
 select * into b from public.stock_cost_books where product_id=r.product_id;
 stock:=private.gama_ec_account(b.stock_account_id,'asset');expense:=private.gama_ec_account(b.expense_account_id,'expense');
 v:=round(r.value_delta,2);c:=round(r.expense_delta,2);
 if r.kind in ('method','transfer') or (v=0 and c=0) then raise exception 'ENTRY_EMPTY';end if;
 if r.kind='out' then
 lines:=jsonb_build_array(jsonb_build_object('account_id',stock,'credit',-v),jsonb_build_object('account_id',expense,'debit',-v));
 else
 counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,case when r.kind='opening' then 'equity' else null end);
 if counter=stock or counter=expense then raise exception 'VALUATION_COUNTER_ACCOUNT_DISTINCT';end if;
 lines:=jsonb_build_array(jsonb_build_object('account_id',stock,'debit',greatest(v,0),'credit',greatest(-v,0)),jsonb_build_object('account_id',expense,'debit',greatest(c,0),'credit',greatest(-c,0)),jsonb_build_object('account_id',counter,'credit',greatest(v+c,0),'debit',greatest(-v-c,0)));
 end if;
 rid:=gen_random_uuid();eid:=private.gama_accounting_book('OD',(r.created_at at time zone private.erp_timezone())::date,'Valoración '||r.sequence::text,'stock_valuation',rid,p_data->>'reason',lines);
 insert into public.accounting_source_links(source_type,source_id,entry_id) values('stock_valuation',r.sequence::text,eid);
 return jsonb_build_object('entry_id',eid);
 end if;
 return private.gama_accounting_ec_write_base(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_write_base(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;

alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_integrations;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;n integer:=0;begin
 if p_action='chart_import' then
 if jsonb_typeof(p_data->'accounts') is distinct from 'array' or jsonb_array_length(p_data->'accounts') not between 1 and 1000 then raise exception 'INVALID_CHART';end if;
 for item in select value from jsonb_array_elements(p_data->'accounts') loop
 insert into public.accounting_accounts(code,name,type) values(item->>'code',item->>'name',item->>'type') on conflict(code) do nothing;
 if found then n:=n+1;end if;
 end loop;return jsonb_build_object('added',n,'skipped',jsonb_array_length(p_data->'accounts')-n);
 elsif p_action='tax_dates_save' then
 update public.accounting_taxes set valid_from=nullif(p_data->>'valid_from','')::date,valid_to=nullif(p_data->>'valid_to','')::date where id=(p_data->>'id')::uuid;
 if not found then raise exception 'TAX_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 return private.gama_accounting_ec_integrations(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_integrations(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;
-- Tax dates apply when a tax is explicitly assigned to a new posted line.
-- Existing data and reversal lines keep their original tax history.
create function private.gama_ec_line_tax_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;t public.accounting_taxes;begin
 if new.tax_id is null then return new;end if;
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='reversal' then return new;end if;
 select * into t from public.accounting_taxes where id=new.tax_id;
 if not t.active or (t.valid_from is not null and e.entry_date<t.valid_from) or (t.valid_to is not null and e.entry_date>t.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
 return new;
end $$;
revoke all on function private.gama_ec_line_tax_guard() from public,anon,authenticated;
create trigger ec_line_tax before insert or update on public.accounting_entry_lines for each row execute function private.gama_ec_line_tax_guard();
-- Keep the legacy tax-list shape while exposing dated rules through the new API.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 if position('jsonb_agg(to_jsonb(t) order by t.rate,t.code)' in s)=0 then raise exception 'TAX_LIST_ANCHOR';end if;
 s:=replace(s,'jsonb_agg(to_jsonb(t) order by t.rate,t.code)','jsonb_agg(to_jsonb(t)-''valid_to'' order by t.rate,t.code)');execute s;
end $$;

-- P&L excludes the technical result-transfer entry; the trial balance includes it.
-- Cashflow incorporates payroll payments, never payroll accruals.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure);
 s:=replace(s,'e.entry_date between d1 and d2','e.entry_date between d1 and d2 and e.source_type<>''year_close'' and not exists(select 1 from public.accounting_entries ce where ce.id=e.reversal_of and ce.source_type=''year_close'')');
 if position(') s group by m)' in s)=0 then raise exception 'CASHFLOW_PAYROLL_ANCHOR';end if;
 s:=replace(s,') s group by m)', ' union all select to_char(hp.paid_on,''YYYY-MM''),0,hp.amount from public.hr_payroll_payments hp where hp.status=''confirmed'' and hp.financial_account_id is not null and hp.paid_on between d1 and d2) s group by m)');execute s;
end $$;
-- Posted adjustments and withholdings can only be cancelled from their origin.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 s:=replace(s,'return jsonb_build_object(''id'',private.gama_accounting_reverse((p_data->>''id'')::uuid,reason));',
 'if exists(select 1 from public.accounting_entries where id=(p_data->>''id'')::uuid and source_type<>''manual'') then raise exception ''SOURCE_CANCELLATION_REQUIRED'';end if; return jsonb_build_object(''id'',private.gama_accounting_reverse((p_data->>''id'')::uuid,reason));');execute s;
end $$;

-- Existing VAT widgets use the ledger after source posting/offsets/reversals,
-- preserving their JSON contract instead of adding a disconnected second total.
alter function private.gama_accounting_action(text,jsonb) rename to gama_accounting_action_before_ec;
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;cfg public.company_settings;d1 date;d2 date;begin
 result:=private.gama_accounting_action_before_ec(p_action,p_data);
 if p_action='taxes' then
 select * into cfg from public.company_settings where id;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',(now() at time zone private.erp_timezone())::date)::date);d2:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 result:=jsonb_set(result,'{summary,collected}',to_jsonb(coalesce((select sum(l.credit-l.debit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where e.status in ('posted','reversed') and e.entry_date between d1 and d2 and l.account_id=cfg.tax_collected_account_id and e.source_type<>'withholding' and not exists(select 1 from public.accounting_entries we where we.id=e.reversal_of and we.source_type='withholding')),0)));
 result:=jsonb_set(result,'{summary,deductible}',to_jsonb(coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where e.status in ('posted','reversed') and e.entry_date between d1 and d2 and l.account_id=cfg.tax_deductible_account_id and e.source_type<>'withholding' and not exists(select 1 from public.accounting_entries we where we.id=e.reversal_of and we.source_type='withholding')),0)));
 end if;
 return result;
end $$;
revoke all on function private.gama_accounting_action_before_ec(text,jsonb) from public,anon,authenticated;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;
-- Serialize period posting with closing. Both paths take the same monthly row lock.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 s:=replace(s,'perform private.gama_accounting_period(p_date);','perform private.gama_accounting_period(p_date); perform 1 from public.accounting_periods where period_start=date_trunc(''month'',p_date)::date for update;');execute s;
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 s:=replace(s,'where period_start=date_trunc(''month'',(p_data->>''period_start'')::date)::date;', 'where period_start=date_trunc(''month'',(p_data->>''period_start'')::date)::date for update;');execute s;
end $$;

create function private.gama_ec_account_integrity() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.type<>new.type and exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=old.id and e.status in ('posted','reversed')) then raise exception 'ACCOUNT_TYPE_POSTED_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_ec_account_integrity() from public,anon,authenticated;
create trigger ec_account_integrity before update on public.accounting_accounts for each row execute function private.gama_ec_account_integrity();
create function private.gama_ec_financial_integrity() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (old.opening_balance,old.account_id,old.currency) is distinct from (new.opening_balance,new.account_id,new.currency)
 and exists(select 1 from public.accounting_entries where source_type='opening' and source_id=old.id) then raise exception 'OPENING_POSTED_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_ec_financial_integrity() from public,anon,authenticated;
create trigger ec_financial_integrity before update on public.financial_accounts for each row execute function private.gama_ec_financial_integrity();
-- Refuse inactive accounts on new entries; historical reversals stay possible.
create function private.gama_ec_active_line() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.accounting_accounts a join public.accounting_entries e on e.id=new.entry_id where a.id=new.account_id and not a.active and e.source_type<>'reversal') then raise exception 'ACCOUNT_INACTIVE';end if;return new;
end $$;
revoke all on function private.gama_ec_active_line() from public,anon,authenticated;
create trigger ec_active_line before insert or update on public.accounting_entry_lines for each row execute function private.gama_ec_active_line();

create function private.gama_ec_next_due(p_side text,p_id uuid,p_balance numeric) returns date language sql stable security definer set search_path='' as $$
 select min(due_date) from(select m.due_date,m.amount,
 coalesce(sum(m.amount) over(order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0) later
 from public.accounting_maturities m where m.side=p_side and coalesce(m.invoice_id,m.supplier_invoice_id)=p_id) x
 where p_balance>later
$$;
revoke all on function private.gama_ec_next_due(text,uuid,numeric) from public,anon,authenticated;
-- Keep invoice lists compatible; their due date becomes the next unpaid maturity.
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_receivables'::regclass,true);
 s:=replace(s,'r.due_date,','coalesce(private.gama_ec_next_due(''customer'',r.id,r.balance-private.gama_ec_offsets(''customer'',r.id)),r.due_date) as due_date,');
 s:=replace(s,'r.days_remaining,','coalesce(private.gama_ec_next_due(''customer'',r.id,r.balance-private.gama_ec_offsets(''customer'',r.id)),r.due_date)-(now() at time zone private.erp_timezone())::date as days_remaining,');
 execute 'create or replace view private.gama_receivables with(security_invoker=true) as '||s;
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);
 s:=replace(s,'r.due_date,','coalesce(private.gama_ec_next_due(''supplier'',r.id,r.balance-private.gama_ec_offsets(''supplier'',r.id)),r.due_date) as due_date,');
 s:=replace(s,'r.days_remaining,','coalesce(private.gama_ec_next_due(''supplier'',r.id,r.balance-private.gama_ec_offsets(''supplier'',r.id)),r.due_date)-(now() at time zone private.erp_timezone())::date as days_remaining,');
 execute 'create or replace view private.gama_payables with(security_invoker=true) as '||s;
end $$;
create function private.gama_ec_schedule() returns table(side text,document_id uuid,number text,partner_name text,due_date date,amount numeric,balance numeric,"position" integer)
 language sql stable security definer set search_path='' as $$
 with docs as(select 'customer'::text side,id,number,customer_name partner_name,due_date,total,balance from private.gama_receivables where payment_status<>'cancelled'
 union all select 'supplier',id,number,supplier_name,due_date,total,balance from private.gama_payables where payment_status<>'cancelled'),
 scheduled as(select d.side,d.id document_id,d.number,d.partner_name,m.due_date,m.amount,
 greatest(0,least(m.amount,d.balance-coalesce(sum(m.amount) over(partition by d.side,d.id order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0)))
 +case when row_number() over(partition by d.side,d.id order by m.due_date desc,m.position desc)=1 then greatest(0,d.balance-sum(m.amount) over(partition by d.side,d.id)) else 0 end balance,m.position
 from docs d join public.accounting_maturities m on m.side=d.side and coalesce(m.invoice_id,m.supplier_invoice_id)=d.id)
 select * from scheduled union all select d.side,d.id,d.number,d.partner_name,d.due_date,d.total,d.balance,1 from docs d
 where not exists(select 1 from public.accounting_maturities m where m.side=d.side and coalesce(m.invoice_id,m.supplier_invoice_id)=d.id)
$$;
revoke all on function private.gama_ec_schedule() from public,anon,authenticated;
alter function private.gama_accounting_ec_read(text,jsonb) rename to gama_accounting_ec_read_base;
create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action='maturities' then return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(z) order by due_date,position,document_id),'[]') from private.gama_ec_schedule()z));end if;
 return private.gama_accounting_ec_read_base(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_read_base(text,jsonb),private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;
create or replace function private.gama_accounting_aging(p_kind text) returns jsonb language sql stable security definer set search_path='' as $$
 with rows as(select balance amount,due_date-(now() at time zone private.erp_timezone())::date days_remaining from private.gama_ec_schedule() where side=case when p_kind='receivable' then 'customer' else 'supplier' end)
 select jsonb_build_object('current',coalesce(sum(amount) filter(where days_remaining is null or days_remaining>=0),0),
 'd30',coalesce(sum(amount) filter(where days_remaining between -30 and -1),0),'d60',coalesce(sum(amount) filter(where days_remaining between -60 and -31),0),
 'd90',coalesce(sum(amount) filter(where days_remaining between -90 and -61),0),'older',coalesce(sum(amount) filter(where days_remaining<-90),0),'total',coalesce(sum(amount),0)) from rows
$$;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure);
 s:=replace(s,'from private.gama_receivables r'||E'\n'||'       where r.payment_status not in (''paid'',''cancelled'')','from private.gama_ec_schedule() r'||E'\n'||'       where r.side=''customer''');
 s:=replace(s,'from private.gama_payables p'||E'\n'||'       where p.payment_status not in (''paid'',''cancelled'')','from private.gama_ec_schedule() p'||E'\n'||'       where p.side=''supplier''');execute s;
end $$;
create function private.gama_ec_delivery_schedule() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.payment_delivery_date is distinct from old.payment_delivery_date and exists(select 1 from public.accounting_maturities where invoice_id=new.id) then
 if new.payment_delivery_date is null or old.payment_delivery_date is null then raise exception 'SCHEDULE_DELIVERY_REQUIRED';end if;
 update public.accounting_maturities set due_date=due_date+(new.payment_delivery_date-old.payment_delivery_date) where invoice_id=new.id;
 end if;return new;
end $$;
revoke all on function private.gama_ec_delivery_schedule() from public,anon,authenticated;
create trigger ec_delivery_schedule after update of payment_delivery_date on public.external_invoices for each row execute function private.gama_ec_delivery_schedule();
-- A accounted source is retained even after cancellation for its audit trail.
create function private.gama_ec_source_delete() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.accounting_entries where source_id=old.id and status in ('posted','reversed')) then raise exception 'ACCOUNTED_SOURCE_DELETE_REJECTED';end if;return old;
end $$;
revoke all on function private.gama_ec_source_delete() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['external_invoices','external_invoice_payments','supplier_invoices','supplier_invoice_payments','expenses','return_credits','return_refunds'] loop
 execute format('create trigger ec_source_delete before delete on public.%I for each row execute function private.gama_ec_source_delete()',t);end loop;end $$;
-- Backlog counts must not treat a reversed source as a fresh unposted document.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_sync(integer)'::regprocedure);s:=replace(s,'and e.status<>''reversed''','');execute s;
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 s:=replace(s,'and e.status<>''reversed''','');execute s;
end $$;

-- A unique existing project link can be attached when the invoice is posted.
-- Multiple linked projects need an explicit distribution, never an arbitrary pick.
create function private.gama_ec_project_line() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;n integer;pid uuid;begin
 if new.project_id is not null then return new;end if;
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='sales_invoice' then
 select count(distinct p.project_id),min(p.project_id::text)::uuid into n,pid from public.pm_links p join public.external_invoices i on i.id=e.source_id join public.sales_orders o on o.id=i.order_id
 where (p.kind='order' and p.target_id=o.id) or (p.kind='quote' and p.target_id=o.source_quote_id);
 if n=1 then new.project_id:=pid;end if;
 end if;return new;
end $$;
revoke all on function private.gama_ec_project_line() from public,anon,authenticated;
create trigger ec_project_line before insert on public.accounting_entry_lines for each row execute function private.gama_ec_project_line();
create table public.accounting_analytic_allocations (
 line_id uuid not null references public.accounting_entry_lines(id),project_id uuid not null references public.pm_projects(id),
 percent numeric(9,4) not null check(percent>0 and percent<=100),amount numeric(18,2) not null,
 created_at timestamptz not null default now(),created_by uuid references auth.users(id),primary key(line_id,project_id)
);
create index analytic_project on public.accounting_analytic_allocations(project_id,line_id);
alter table public.accounting_analytic_allocations enable row level security;
revoke all on public.accounting_analytic_allocations from public,anon,authenticated;grant select on public.accounting_analytic_allocations to authenticated;
create policy analytic_read on public.accounting_analytic_allocations for select to authenticated using(private.erp_module_allowed('accounting',array['administrador','comercial']) and private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all');
create trigger erp_audit_capture after insert or update or delete on public.accounting_analytic_allocations for each row execute function private.erp_audit_capture();
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_before_analytic;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.accounting_entry_lines;e public.accounting_entries;item jsonb;total numeric:=0;allocated numeric:=0;part numeric;i integer:=0;n integer;begin
 if p_action<>'allocation_save' then return private.gama_accounting_ec_write_before_analytic(p_action,p_data);end if;
 select * into l from public.accounting_entry_lines where id=(p_data->>'line_id')::uuid for update;
 if not found then raise exception 'LINE_REQUIRED';end if;select * into e from public.accounting_entries where id=l.entry_id;
 if e.status<>'posted' or e.source_type in ('year_close','reversal') then raise exception 'ENTRY_NOT_POSTED';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
 n:=jsonb_array_length(p_data->'lines');
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 if (item->>'percent')::numeric is null or (item->>'percent')::numeric<=0 or (item->>'percent')::numeric>100 or nullif(item->>'project_id','') is null then raise exception 'INVALID_PERCENT';end if;total:=total+(item->>'percent')::numeric;
 end loop;
 if total<>100 then raise exception 'TERMS_MUST_TOTAL_100';end if;
 delete from public.accounting_analytic_allocations where line_id=l.id;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 i:=i+1;part:=case when i=n then l.debit-l.credit-allocated else round((l.debit-l.credit)*(item->>'percent')::numeric/100,2) end;allocated:=allocated+part;
 insert into public.accounting_analytic_allocations(line_id,project_id,percent,amount,created_by) values(l.id,(item->>'project_id')::uuid,(item->>'percent')::numeric,part,auth.uid());
 end loop;
 return jsonb_build_object('amount',allocated,'count',n);
end $$;
revoke all on function private.gama_accounting_ec_write_before_analytic(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;
alter function private.gama_accounting_ec_read(text,jsonb) rename to gama_accounting_ec_read_before_analytic;
create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);begin
 if p_action<>'analytic' then return private.gama_accounting_ec_read_before_analytic(p_action,p_data);end if;
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 return jsonb_build_object('from',d1,'to',d2,'rows',(
 with parts as(select x.project_id,a.type,x.amount from public.accounting_analytic_allocations x join public.accounting_entry_lines l on l.id=x.line_id join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id where e.status in ('posted','reversed') and e.entry_date between d1 and d2
 union all select l.project_id,a.type,l.debit-l.credit from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id where l.project_id is not null and e.status in ('posted','reversed') and e.entry_date between d1 and d2 and not exists(select 1 from public.accounting_analytic_allocations x where x.line_id=l.id))
 select coalesce(jsonb_agg(to_jsonb(z) order by name),'[]') from(select p.id,p.name,coalesce(-sum(amount) filter(where type='income'),0) revenue,coalesce(sum(amount) filter(where type='expense'),0) expense from public.pm_projects p left join parts on parts.project_id=p.id group by p.id)z));
end $$;
revoke all on function private.gama_accounting_ec_read_before_analytic(text,jsonb),private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;
create function private.gama_ec_reverse_analytic() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;lid uuid;begin
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='reversal' then
 select id into lid from public.accounting_entry_lines where entry_id=e.source_id order by position,id offset (new.position-1) limit 1;
 insert into public.accounting_analytic_allocations(line_id,project_id,percent,amount,created_by) select new.id,project_id,percent,-amount,auth.uid() from public.accounting_analytic_allocations where line_id=lid;
 end if;return new;
end $$;
revoke all on function private.gama_ec_reverse_analytic() from public,anon,authenticated;
create trigger ec_reverse_analytic after insert on public.accounting_entry_lines for each row execute function private.gama_ec_reverse_analytic();
