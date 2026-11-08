do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>243
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261005004521_ec_payroll_calculation_and_employee_receipts.sql; SHA256 4eac045a83c5d0d57ffb10b0a65d897edeb1588367112add6b0a925be43781b5
-- Ecuador payroll: reviewed, versioned parameters; frozen server calculations.
do $$ declare s text;begin
 select pg_get_expr(conbin,conrelid) into s from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 if s is null then raise exception 'ACCOUNTING_SOURCE_TYPES_REQUIRED';end if;
 alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
 execute 'alter table public.accounting_entries add constraint accounting_entries_source_type_check check(('||s||') or source_type in (''ec_utilities'',''ec_benefit'',''ec_benefit_payment''))';
end $$;
create table public.hr_ec_parameters (
 id uuid primary key default gen_random_uuid(),year integer not null check(year between 2020 and 2100),
 parameters jsonb not null, evidence text not null, confirmed_by uuid references public.profiles(id),
 confirmed_at timestamptz,created_at timestamptz not null default clock_timestamp()
);
create index hr_ec_parameters_year on public.hr_ec_parameters(year,created_at desc,id);
create index hr_ec_parameters_actor on public.hr_ec_parameters(confirmed_by);
insert into public.hr_ec_parameters(year,parameters,evidence) values(2026,
 '{"sbu":482,"iess_personal_rate":9.45,"iess_employer_rate":11.15,"iess_health_min_rate":4.41,"reserve_rate":8.33,"additional_employer_rate":0,"util_work_rate":10,"util_family_rate":5}',
 'Propuesta para revisión: MDT SBU 2026; IESS sector privado; Código del Trabajo. Ver docs/modules/hr.md.');
create table public.hr_ec_employee_terms (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 effective_from date not null check(extract(day from effective_from)=1),
 decimo13_mode text not null check(decimo13_mode in ('monthly','accrued')),
 decimo14_mode text not null check(decimo14_mode in ('monthly','accrued')),
 reserve_mode text not null check(reserve_mode in ('direct','iess')),
 region text not null check(region in ('costa','sierra')),other_fulltime boolean not null default false,sectoral_minimum numeric(14,2) not null default 0 check(sectoral_minimum>=0),work_ratio numeric(8,4) not null check(work_ratio>0 and work_ratio<=1),
 bank_name text not null default '',bank_number text not null default '',bank_kind text not null default 'savings' check(bank_kind in ('savings','checking')),
 beneficiary_id text not null default '',evidence text not null,created_by uuid not null references public.profiles(id),created_at timestamptz not null default clock_timestamp()
);
create index hr_ec_employee_terms_employee on public.hr_ec_employee_terms(employee_id,effective_from desc,created_at desc,id);
create index hr_ec_employee_terms_actor on public.hr_ec_employee_terms(created_by);
alter table public.hr_payroll add column ec_calculation jsonb;
create table public.hr_ec_payroll_signatures (
 payroll_id uuid primary key references public.hr_payroll(id),employee_id uuid not null references public.hr_employees(id),
 signed_by uuid not null references public.profiles(id),signed_at timestamptz not null default clock_timestamp(),snapshot_hash text not null,
 signature_png text not null check(length(signature_png) between 100 and 200000)
);
create index hr_ec_signature_employee on public.hr_ec_payroll_signatures(employee_id);
create index hr_ec_signature_actor on public.hr_ec_payroll_signatures(signed_by);
create table public.hr_ec_utilities (
 id uuid primary key default gen_random_uuid(),year integer not null unique check(year between 2020 and 2100),
 request_key uuid not null unique,net_profit numeric(14,2) not null,calculation jsonb not null,evidence text not null,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default clock_timestamp(),entry_id uuid references public.accounting_entries(id)
);
create index hr_ec_utilities_actor on public.hr_ec_utilities(created_by);
create index hr_ec_utilities_entry on public.hr_ec_utilities(entry_id);
create table public.hr_ec_benefits (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),kind text not null check(kind in ('decimo13','decimo14','utilidades')),
 from_date date not null,to_date date not null check(to_date>=from_date),amount numeric(14,2) not null check(amount>0),
 source_id uuid references public.hr_ec_utilities(id),entry_id uuid references public.accounting_entries(id),
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default clock_timestamp(),
 unique(employee_id,kind,from_date,to_date)
);
create index hr_ec_benefits_employee on public.hr_ec_benefits(employee_id);
create index hr_ec_benefits_source on public.hr_ec_benefits(source_id);
create index hr_ec_benefits_entry on public.hr_ec_benefits(entry_id);
create index hr_ec_benefits_actor on public.hr_ec_benefits(created_by);
create table public.hr_ec_benefit_payments (
 id uuid primary key default gen_random_uuid(),benefit_id uuid not null references public.hr_ec_benefits(id),
 request_key uuid not null unique,amount numeric(14,2) not null check(amount>0),paid_on date not null,
 financial_account_id uuid not null references public.financial_accounts(id),reference text not null,entry_id uuid not null references public.accounting_entries(id),
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default clock_timestamp()
);
create index hr_ec_benefit_payments_benefit on public.hr_ec_benefit_payments(benefit_id);
create index hr_ec_benefit_payments_account on public.hr_ec_benefit_payments(financial_account_id);
create index hr_ec_benefit_payments_entry on public.hr_ec_benefit_payments(entry_id);
create index hr_ec_benefit_payments_actor on public.hr_ec_benefit_payments(created_by);
do $$ declare t text;begin
 foreach t in array array['hr_ec_parameters','hr_ec_employee_terms','hr_ec_payroll_signatures','hr_ec_utilities','hr_ec_benefits','hr_ec_benefit_payments'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy hr_ec_read on public.%I for select to authenticated using(private.erp_mfa_ok() and private.hr_admin())',t);
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;
end $$;
create policy hr_ec_terms_own on public.hr_ec_employee_terms for select to authenticated using(private.erp_mfa_ok() and private.hr_own(employee_id));
create policy hr_ec_signature_own on public.hr_ec_payroll_signatures for select to authenticated using(private.erp_mfa_ok() and private.hr_own(employee_id));
create policy hr_ec_benefits_own on public.hr_ec_benefits for select to authenticated using(private.erp_mfa_ok() and private.hr_own(employee_id));
create policy hr_ec_benefit_payments_own on public.hr_ec_benefit_payments for select to authenticated using(private.erp_mfa_ok() and exists(select 1 from public.hr_ec_benefits b where b.id=benefit_id and private.hr_own(b.employee_id)));
create policy hr_ec_benefit_payments_finance on public.hr_ec_benefit_payments for select to authenticated using(private.erp_mfa_ok() and private.erp_module_allowed('accounting',array['administrador','comercial']) and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false));

create function private.gama_hr_ec_number(p_data jsonb,p_key text,p_default numeric default 0,p_max numeric default 1000000000,p_scale integer default 2) returns numeric language plpgsql immutable set search_path='' as $$
declare n numeric;begin
 if p_data->p_key is null or p_data->p_key='null'::jsonb then return p_default;end if;
 if jsonb_typeof(p_data->p_key)<>'number' then raise exception 'PAYROLL_INVALID_AMOUNT';end if;
 n:=(p_data->>p_key)::numeric;if n::text in ('NaN','Infinity','-Infinity') or n<0 or n>p_max or n<>round(n,p_scale) then raise exception 'PAYROLL_INVALID_AMOUNT';end if;return n;
end $$;
-- Employment benefits use 30-day months / 360-day years (MDT-2023-140 general rule 5).
create function private.gama_hr_ec_days(p_from date,p_to date) returns integer language sql immutable set search_path='' as $$
 select case when p_to<p_from then 0 else ((extract(year from p_to)-extract(year from p_from))*12+extract(month from p_to)-extract(month from p_from))::integer*30+
 (case when p_to=(date_trunc('month',p_to)+interval '1 month -1 day')::date then 30 else least(30,extract(day from p_to)::integer) end)-least(30,extract(day from p_from)::integer)+1 end
$$;
create function private.gama_hr_ec_calculate(p_employee uuid,p_period date,p_inputs jsonb,p_parameters uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cfg public.company_settings;params public.hr_ec_parameters;terms public.hr_ec_employee_terms;person public.hr_employee_private;
 last_day date;cap integer;days numeric;eligible integer;reserve_days numeric;salary numeric;bonus numeric;gross numeric;personal numeric;patronal numeric;health numeric;minimum numeric;extra numeric;d13 numeric;d14 numeric;reserve numeric;ir numeric;deductions numeric;net numeric;cost numeric;x jsonb;settings jsonb;begin
 if p_period is null or extract(day from p_period)<>1 or p_period<'2020-01-01' or p_period>'2100-12-01' then raise exception 'INVALID_PERIOD';end if;
 select * into cfg from public.company_settings where id;if not cfg.configured or cfg.country<>'EC' or cfg.currency<>'USD' then raise exception 'EC_COMPANY_REQUIRED';end if;
 select * into params from public.hr_ec_parameters where year=extract(year from p_period) and (p_parameters is null or id=p_parameters) and confirmed_at is not null order by created_at desc,id desc limit 1;
 if not found then raise exception 'PAYROLL_PARAMETERS_REVIEW_REQUIRED';end if;
 select * into person from public.hr_employee_private where employee_id=p_employee;
 if not found or person.hire_date is null or person.salary is null or person.salary<=0 then raise exception 'PAYROLL_CONTRACT_REQUIRED';end if;
 select * into terms from public.hr_ec_employee_terms where employee_id=p_employee and effective_from<=p_period order by effective_from desc,created_at desc,id desc limit 1;
 if not found then raise exception 'PAYROLL_EMPLOYEE_CHOICES_REQUIRED';end if;
 last_day:=(p_period+interval '1 month -1 day')::date;cap:=private.gama_hr_ec_days(greatest(p_period,person.hire_date),least(last_day,coalesce(person.end_date,last_day)));
 days:=private.gama_hr_ec_number(p_inputs,'worked_days',cap,30,2);if days<=0 or days>cap then raise exception 'PAYROLL_WORKED_DAYS_INVALID';end if;
 eligible:=private.gama_hr_ec_days(greatest(p_period,(person.hire_date+interval '1 year')::date),least(last_day,coalesce(person.end_date,last_day)));
 if eligible>0 and eligible<cap and days<cap and p_inputs->'reserve_days' is null then raise exception 'PAYROLL_RESERVE_DAYS_REVIEW_REQUIRED';end if;
 reserve_days:=private.gama_hr_ec_number(p_inputs,'reserve_days',least(days,eligible),30,2);if reserve_days>least(days,eligible) then raise exception 'PAYROLL_RESERVE_DAYS_INVALID';end if;
 minimum:=greatest((params.parameters->>'sbu')::numeric,terms.sectoral_minimum);if person.salary<round(minimum*terms.work_ratio,2) then raise exception 'PAYROLL_MINIMUM_SALARY_REQUIRED';end if;
 salary:=round(person.salary*days/30,2);bonus:=private.gama_hr_ec_number(p_inputs,'bonus');gross:=salary+bonus;
 personal:=round(gross*(params.parameters->>'iess_personal_rate')::numeric/100,2);patronal:=round(gross*(params.parameters->>'iess_employer_rate')::numeric/100,2);extra:=round(gross*(params.parameters->>'additional_employer_rate')::numeric/100,2);
 health:=case when terms.work_ratio<1 and not terms.other_fulltime then round(greatest(0,minimum*days/30-gross)*(params.parameters->>'iess_health_min_rate')::numeric/100,2) else 0 end;
 d13:=round(gross/12,2);d14:=round((params.parameters->>'sbu')::numeric*terms.work_ratio*days/360,2);reserve:=round(gross*(params.parameters->>'reserve_rate')::numeric/100*reserve_days/days,2);
 ir:=private.gama_hr_ec_number(p_inputs,'income_tax');deductions:=private.gama_hr_ec_number(p_inputs,'other_deductions');
 net:=gross-personal-ir-deductions+case when terms.decimo13_mode='monthly' then d13 else 0 end+case when terms.decimo14_mode='monthly' then d14 else 0 end+case when terms.reserve_mode='direct' then reserve else 0 end;
 cost:=gross+patronal+health+extra+d13+d14+reserve;if net<0 or cost>999999999999.99 then raise exception 'PAYROLL_INVALID_AMOUNT';end if;
 x:=jsonb_build_object('worked_days',days,'reserve_days',reserve_days,'bonus',bonus,'income_tax',ir,'other_deductions',deductions);
 settings:=to_jsonb(terms)-'created_by'-'created_at'-'evidence';
 return jsonb_build_object('version',1,'parameters_id',params.id,'parameters',params.parameters,'terms',settings,'inputs',x,
 'contract',jsonb_build_object('salary',person.salary,'hire_date',person.hire_date,'end_date',person.end_date),'gross',gross,'salary',salary,'personal_iess',personal,'employer_iess',patronal,'health_complement',health,'additional_employer',extra,'decimo13',d13,'decimo14',d14,'reserve',reserve,'income_tax',ir,'other_deductions',deductions,'net',net,'employer_cost',cost,'contract_days',cap,'eligible_reserve_days',eligible);
end $$;
create function private.gama_hr_ec_payroll_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare calc jsonb;begin
 if new.ec_calculation is null then if tg_op='UPDATE' and old.ec_calculation is not null then raise exception 'PAYROLL_CALCULATION_REQUIRED';end if;return new;end if;
 if not private.hr_admin() or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if tg_op='UPDATE' and old.status<>'draft' then
 if new.status='cancelled' and exists(select 1 from public.hr_ec_benefits b where b.employee_id=old.employee_id and old.period between b.from_date and b.to_date and b.kind in ('decimo13','decimo14') and old.ec_calculation->'terms'->>(case when b.kind='decimo13' then 'decimo13_mode' else 'decimo14_mode' end)='accrued') then raise exception 'PAYROLL_ACCRUAL_ALREADY_RELEASED';end if;return new;end if;
 calc:=private.gama_hr_ec_calculate(new.employee_id,new.period,new.ec_calculation->'inputs',(new.ec_calculation->>'parameters_id')::uuid);
 if tg_op='UPDATE' and new.status='validated' and old.ec_calculation is distinct from calc then raise exception 'PAYROLL_RECALCULATE_REQUIRED';end if;
 new.ec_calculation:=calc;new.gross:=(calc->>'gross')::numeric;new.net:=(calc->>'net')::numeric;new.employer_cost:=(calc->>'employer_cost')::numeric;return new;
end $$;
create trigger ec_payroll_calculate_guard before insert or update on public.hr_payroll for each row execute function private.gama_hr_ec_payroll_guard();

create function private.gama_hr_ec_utility_calculation(p_year integer,p_profit numeric,p_people jsonb,p_zero_policy text default 'review') returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare params public.hr_ec_parameters;person record;x jsonb;people jsonb:='[]';count_seen integer:=0;d numeric;r numeric;deps numeric;cap integer;w numeric;tw numeric:=0;tf numeric:=0;pw numeric;pf numeric;out_rows jsonb;begin
 if p_year not between 2020 and 2100 or p_profit is null or p_profit::text in ('NaN','Infinity','-Infinity') or abs(p_profit)>999999999999.99 or p_profit<>round(p_profit,2) or jsonb_typeof(p_people) is distinct from 'array' or jsonb_array_length(p_people) not between 1 and 1000 then raise exception 'PAYROLL_UTILITIES_INPUT_INVALID';end if;
 select * into params from public.hr_ec_parameters where year=p_year and confirmed_at is not null order by created_at desc,id desc limit 1;if not found then raise exception 'PAYROLL_PARAMETERS_REVIEW_REQUIRED';end if;
 if exists(select 1 from public.hr_employees e left join public.hr_employee_private p on p.employee_id=e.id where p.hire_date is null) then raise exception 'PAYROLL_CONTRACT_REQUIRED';end if;
 if exists(select 1 from jsonb_array_elements(p_people) t group by t->>'employee_id' having count(*)>1) then raise exception 'PAYROLL_UTILITIES_DUPLICATE';end if;
 for person in select p.*,e.full_name from public.hr_employee_private p join public.hr_employees e on e.id=p.employee_id where p.hire_date<=make_date(p_year,12,31) and coalesce(p.end_date,make_date(p_year,12,31))>=make_date(p_year,1,1) order by p.employee_id loop
 select value into x from jsonb_array_elements(p_people) where value->>'employee_id'=person.employee_id::text;if x is null or length(btrim(coalesce(x->>'evidence','')))<5 then raise exception 'PAYROLL_UTILITIES_WORKFORCE_REVIEW_REQUIRED';end if;
 cap:=private.gama_hr_ec_days(greatest(person.hire_date,make_date(p_year,1,1)),least(coalesce(person.end_date,make_date(p_year,12,31)),make_date(p_year,12,31)));
 d:=private.gama_hr_ec_number(x,'worked_days',null,360,2);r:=private.gama_hr_ec_number(x,'work_ratio',null,1,4);deps:=private.gama_hr_ec_number(x,'dependents',null,30,0);
 if d is null or d>cap or r is null or r<=0 or deps is null then raise exception 'PAYROLL_UTILITIES_INPUT_INVALID';end if;
 w:=d*r;tw:=tw+w;tf:=tf+w*deps;count_seen:=count_seen+1;
 people:=people||jsonb_build_array(jsonb_build_object('employee_id',person.employee_id,'name',person.full_name,'worked_days',d,'work_ratio',r,'dependents',deps,'weight',w,'family_weight',w*deps,'evidence',x->>'evidence'));
 end loop;
 if count_seen<>jsonb_array_length(p_people) or tw<=0 then raise exception 'PAYROLL_UTILITIES_WORKFORCE_REVIEW_REQUIRED';end if;
 pw:=round(greatest(0,p_profit)*(params.parameters->>'util_work_rate')::numeric/100,2);pf:=round(greatest(0,p_profit)*(params.parameters->>'util_family_rate')::numeric/100,2);
 if tf=0 and pf>0 and p_zero_policy<>'by_days_reviewed' then raise exception 'PAYROLL_UTILITIES_ZERO_FAMILY_REVIEW_REQUIRED';end if;
 -- Largest remainder independently for both pools: exact cents, deterministic ties.
 with source as(select value x,(value->>'weight')::numeric w,(value->>'family_weight')::numeric f from jsonb_array_elements(people)),
 raw as(select x,pw*100*w/tw aw,pf*100*case when tf=0 then w/tw else f/tf end af from source),
 ranked as(select *,row_number() over(order by aw-floor(aw) desc,x->>'employee_id') rw,row_number() over(order by af-floor(af) desc,x->>'employee_id') rf,pw*100-sum(floor(aw)) over() remw,pf*100-sum(floor(af)) over() remf from raw),
 amounts as(select x,(floor(aw)+case when rw<=remw then 1 else 0 end)/100 a,(floor(af)+case when rf<=remf then 1 else 0 end)/100 b from ranked)
 select jsonb_agg(x||jsonb_build_object('work_amount',a,'family_amount',b,'amount',a+b) order by x->>'employee_id') into out_rows from amounts;
 return jsonb_build_object('year',p_year,'net_profit',p_profit,'parameters_id',params.id,'parameters',params.parameters,'work_pool',pw,'family_pool',pf,'total',pw+pf,'zero_family_policy',case when tf=0 then p_zero_policy else 'not_applicable' end,'people',out_rows);
end $$;

create function private.gama_hr_ec_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare eid uuid:=nullif(p_data->>'employee_id','')::uuid;pid uuid:=nullif(p_data->>'payroll_id','')::uuid;v_period date:=nullif(p_data->>'period','')::date;v_year integer:=coalesce((p_data->>'year')::integer,extract(year from (now() at time zone private.erp_timezone())::date)::integer);
 adm boolean:=private.hr_admin();today date:=(now() at time zone private.erp_timezone())::date;params jsonb;item jsonb;key uuid;calc jsonb;pay public.hr_payroll;term public.hr_ec_employee_terms;person public.hr_employee_private;sign public.hr_ec_payroll_signatures;run public.hr_ec_utilities;benefit public.hr_ec_benefits;payment public.hr_ec_benefit_payments;prof public.accounting_ec_profile;acc public.financial_accounts;entry uuid;amount numeric;out_rows jsonb;start_date date;end_date date;png bytea;evidence text:=btrim(coalesce(p_data->>'evidence',''));begin
 if auth.uid() is null or not private.erp_mfa_ok() or (not adm and not exists(select 1 from public.hr_employees where private.hr_own(id))) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then
 if v_period is null then v_period:=date_trunc('month',today)::date;end if;
 return jsonb_build_object('parameters',case when adm then (select to_jsonb(p) from public.hr_ec_parameters p where p.year=extract(year from v_period) order by created_at desc,id desc limit 1) end,
 'employees',coalesce((select jsonb_agg(jsonb_build_object('employee_id',e.id,'name',e.full_name,'active',e.active,'salary',p.salary,'hire_date',p.hire_date,'end_date',p.end_date,'terms',(select to_jsonb(t) from public.hr_ec_employee_terms t where t.employee_id=e.id and effective_from<=v_period order by effective_from desc,created_at desc,id desc limit 1)) order by e.full_name) from public.hr_employees e left join public.hr_employee_private p on p.employee_id=e.id where adm or private.hr_own(e.id)),'[]'),
 'accounts',case when adm then coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name,'kind',f.kind)) from public.financial_accounts f where f.active and f.currency='USD' and f.account_id is not null),'[]') end,
 'utilities',case when adm then coalesce((select jsonb_agg(to_jsonb(u) order by year desc) from public.hr_ec_utilities u where u.year between v_year-1 and v_year),'[]') end,
 'benefits',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('paid',coalesce((select sum(amount) from public.hr_ec_benefit_payments where benefit_id=b.id),0))) from public.hr_ec_benefits b where (adm or private.hr_own(b.employee_id)) and b.to_date>=make_date(v_year-1,1,1)),'[]'));
 end if;
 if p_action in ('slip','sign') then
 select * into pay from public.hr_payroll where id=pid for update;if not found or (not adm and not private.hr_own(pay.employee_id)) then raise exception 'PAYROLL_NOT_FOUND';end if;
 if p_action='sign' then
 if not private.hr_own(pay.employee_id) or pay.status<>'validated' then raise exception 'PAYROLL_EMPLOYEE_SIGNATURE_REQUIRED';end if;
 if coalesce(p_data->>'signature_png','') !~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' or length(p_data->>'signature_png') not between 100 and 200000 then raise exception 'SIGNATURE_REQUIRED';end if;
 png:=decode(split_part(p_data->>'signature_png',',',2),'base64');if length(png)<40 or substring(png from 1 for 8)<>decode('89504e470d0a1a0a','hex') or substring(png from 13 for 4)<>decode('49484452','hex') or get_byte(png,16)>0 or get_byte(png,17)>0 or get_byte(png,20)>0 or get_byte(png,21)>0 or get_byte(png,18)*256+get_byte(png,19) not between 1 and 2000 or get_byte(png,22)*256+get_byte(png,23) not between 1 and 1000 then raise exception 'SIGNATURE_REQUIRED';end if;
 select * into sign from public.hr_ec_payroll_signatures where payroll_id=pid;
 if not found then insert into public.hr_ec_payroll_signatures(payroll_id,employee_id,signed_by,snapshot_hash,signature_png) values(pid,pay.employee_id,auth.uid(),encode(sha256(convert_to(to_jsonb(pay)::text,'UTF8')),'hex'),p_data->>'signature_png') returning * into sign;end if;
 return to_jsonb(sign)-'signature_png';end if;
 select * into person from public.hr_employee_private where employee_id=pay.employee_id;select * into sign from public.hr_ec_payroll_signatures where payroll_id=pid;
 return jsonb_build_object('payroll',to_jsonb(pay),'employee',jsonb_build_object('name',(select full_name from public.hr_employees where id=pay.employee_id),'identification',person.identification),'company',(select to_jsonb(c)-'updated_by' from public.company_settings c where id),'paid',coalesce((select sum(amount) from public.hr_payroll_payments where payroll_id=pid and status='confirmed'),0),'signature',case when sign.payroll_id is not null then to_jsonb(sign) end,'can_sign',private.hr_own(pay.employee_id) and pay.status='validated' and sign.payroll_id is null);
 end if;
 if p_action='terms_save' then
 if not adm and not private.hr_own(eid) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if v_period is null or extract(day from v_period)<>1 or length(evidence) not between 10 and 2000 then raise exception 'PAYROLL_EMPLOYEE_CHOICES_REQUIRED';end if;
 select * into term from public.hr_ec_employee_terms where employee_id=eid and effective_from<=v_period order by effective_from desc,created_at desc,id desc limit 1;
 if not adm then
 select * into person from public.hr_employee_private where employee_id=eid;
 if v_period<>date_trunc('month',today)::date then raise exception 'PAYROLL_CHOICE_DATE_REVIEW_REQUIRED';end if;
 if (p_data->>'decimo13_mode' is distinct from coalesce(term.decimo13_mode,'monthly') or p_data->>'decimo14_mode' is distinct from coalesce(term.decimo14_mode,'monthly')) and not (extract(month from today)=1 and extract(day from today)<=15) and not (person.hire_date is not null and today between person.hire_date and person.hire_date+15) then raise exception 'PAYROLL_CHOICE_DATE_REVIEW_REQUIRED';end if;
 end if;
 if not adm then p_data:=p_data||jsonb_build_object('reserve_mode',coalesce(term.reserve_mode,'direct'),'region',coalesce(term.region,'costa'),'work_ratio',coalesce(term.work_ratio,1),'bank_name',coalesce(term.bank_name,''),'bank_number',coalesce(term.bank_number,''),'bank_kind',coalesce(term.bank_kind,'savings'),'beneficiary_id',coalesce(term.beneficiary_id,''),'sectoral_minimum',coalesce(term.sectoral_minimum,0),'other_fulltime',coalesce(term.other_fulltime,false));end if;
 if p_data->>'decimo13_mode' not in ('monthly','accrued') or p_data->>'decimo14_mode' not in ('monthly','accrued') or p_data->>'reserve_mode' not in ('direct','iess') or p_data->>'region' not in ('costa','sierra') or private.gama_hr_ec_number(p_data,'work_ratio',null,1,4)<=0 or p_data->>'bank_kind' not in ('savings','checking') or length(coalesce(p_data->>'bank_name',''))>120 or coalesce(p_data->>'bank_number','') !~ '^[0-9]{0,30}$' or length(coalesce(p_data->>'beneficiary_id',''))>30 then raise exception 'PAYROLL_EMPLOYEE_CHOICES_REQUIRED';end if;
 insert into public.hr_ec_employee_terms(employee_id,effective_from,decimo13_mode,decimo14_mode,reserve_mode,region,work_ratio,sectoral_minimum,other_fulltime,bank_name,bank_number,bank_kind,beneficiary_id,evidence,created_by) values(eid,v_period,p_data->>'decimo13_mode',p_data->>'decimo14_mode',p_data->>'reserve_mode',p_data->>'region',(p_data->>'work_ratio')::numeric,private.gama_hr_ec_number(p_data,'sectoral_minimum'),coalesce((p_data->>'other_fulltime')::boolean,false),coalesce(p_data->>'bank_name',''),coalesce(p_data->>'bank_number',''),p_data->>'bank_kind',coalesce(p_data->>'beneficiary_id',''),evidence,auth.uid()) returning * into term;return to_jsonb(term);
 end if;
 if not adm then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='parameters_save' then
 params:=p_data->'parameters';if v_year not between 2020 and 2100 or length(evidence) not between 10 and 2000 then raise exception 'PAYROLL_PARAMETERS_REVIEW_REQUIRED';end if;
 for item in select to_jsonb(k) from unnest(array['sbu','iess_personal_rate','iess_employer_rate','iess_health_min_rate','reserve_rate','additional_employer_rate','util_work_rate','util_family_rate']) k loop
 if private.gama_hr_ec_number(params,item#>>'{}',null,case when item#>>'{}'='sbu' then 100000 else 100 end,4) is null then raise exception 'PAYROLL_PARAMETERS_REVIEW_REQUIRED';end if;end loop;
 if (params->>'sbu')::numeric<=0 or (params->>'util_work_rate')::numeric+(params->>'util_family_rate')::numeric>100 then raise exception 'PAYROLL_PARAMETERS_REVIEW_REQUIRED';end if;
 insert into public.hr_ec_parameters(year,parameters,evidence,confirmed_by,confirmed_at) values(v_year,params,evidence,auth.uid(),now());return jsonb_build_object('ok',true);
 elsif p_action in ('preview','calculate') then
 perform pg_advisory_xact_lock(hashtextextended('ec-payroll:'||eid::text||':'||v_period::text,0));
 calc:=private.gama_hr_ec_calculate(eid,v_period,p_data->'inputs');if p_action='preview' then return calc;end if;
 if p_data->'expected_calculation' is not null and calc is distinct from p_data->'expected_calculation' then raise exception 'PAYROLL_RECALCULATE_REQUIRED';end if;
 select * into pay from public.hr_payroll where employee_id=eid and period=v_period for update;
 if found then
 if pay.status<>'draft' then raise exception 'PAYROLL_ALREADY_VALIDATED';end if;
 update public.hr_payroll set ec_calculation=calc,cost_center=left(coalesce(p_data->>'cost_center',''),200) where id=pay.id returning * into pay;
 else
 insert into public.hr_payroll(employee_id,period,source_ref,gross,net,employer_cost,cost_center,ec_calculation) values(eid,v_period,'EC-'||eid||'-'||v_period,0,0,0,left(coalesce(p_data->>'cost_center',''),200),calc) returning * into pay;end if;return to_jsonb(pay);
 elsif p_action in ('utilities_preview','utilities_confirm') then
 calc:=private.gama_hr_ec_utility_calculation(v_year,(p_data->>'net_profit')::numeric,p_data->'people',coalesce(p_data->>'zero_family_policy','review'));
 if p_action='utilities_preview' then return calc;end if;
 if length(evidence) not between 10 and 2000 or today<=make_date(v_year,12,31) then raise exception 'PAYROLL_UTILITIES_DECLARATION_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('ec-utilities:'||v_year::text,0));select * into run from public.hr_ec_utilities where year=v_year;
 if found then if run.calculation<>calc or run.evidence<>evidence then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(run);end if;
 select * into prof from public.accounting_ec_profile where id;perform private.gama_ec_account(prof.payroll_expense_account_id,'expense');perform private.gama_ec_account(prof.payroll_payable_account_id,'liability');
 insert into public.hr_ec_utilities(year,request_key,net_profit,calculation,evidence,created_by) values(v_year,key,(calc->>'net_profit')::numeric,calc,evidence,auth.uid()) returning * into run;
 if (calc->>'total')::numeric>0 then
 entry:=private.gama_accounting_book('OD',make_date(v_year,12,31),'Utilidades '||v_year,'ec_utilities',run.id,'Provisión de utilidades anual revisada',jsonb_build_array(jsonb_build_object('account_id',prof.payroll_expense_account_id,'debit',(calc->>'total')::numeric),jsonb_build_object('account_id',prof.payroll_payable_account_id,'credit',(calc->>'total')::numeric)));
 update public.hr_ec_utilities set entry_id=entry where id=run.id;
 for item in select value from jsonb_array_elements(calc->'people') where (value->>'amount')::numeric>0 loop insert into public.hr_ec_benefits(employee_id,kind,from_date,to_date,amount,source_id,entry_id,created_by) values((item->>'employee_id')::uuid,'utilidades',make_date(v_year,1,1),make_date(v_year,12,31),(item->>'amount')::numeric,run.id,entry,auth.uid());end loop;
 end if;return jsonb_build_object('id',run.id,'total',calc->'total','entry_id',entry);
 elsif p_action='accrued_release' then
 if p_data->>'kind' not in ('decimo13','decimo14') or length(evidence) not between 10 and 2000 then raise exception 'PAYROLL_ACCRUAL_REVIEW_REQUIRED';end if;
 select * into term from public.hr_ec_employee_terms where employee_id=eid and effective_from<=make_date(v_year,12,1) order by effective_from desc,created_at desc,id desc limit 1;if not found then raise exception 'PAYROLL_EMPLOYEE_CHOICES_REQUIRED';end if;
 if p_data->>'kind'='decimo13' then start_date:=make_date(v_year-1,12,1);end_date:=make_date(v_year,11,30);
 elsif term.region='costa' then start_date:=make_date(v_year-1,3,1);end_date:=(make_date(v_year,3,1)-1);else start_date:=make_date(v_year-1,8,1);end_date:=make_date(v_year,7,31);end if;
 select * into person from public.hr_employee_private where employee_id=eid;
 end_date:=least(end_date,coalesce(person.end_date,end_date));if today<end_date then raise exception 'PAYROLL_ACCRUAL_PERIOD_OPEN';end if;
 perform pg_advisory_xact_lock(hashtextextended('ec-benefit:'||eid::text||':'||(p_data->>'kind')||':'||v_year,0));
 select * into benefit from public.hr_ec_benefits where employee_id=eid and kind=p_data->>'kind' and from_date=start_date and to_date=end_date;if found then return to_jsonb(benefit);end if;
 if exists(select 1 from public.hr_payroll where employee_id=eid and period between start_date and end_date and status='validated' and ec_calculation is null) then raise exception 'PAYROLL_ACCRUAL_EXTERNAL_REVIEW_REQUIRED';end if;
 if exists(select 1 from generate_series(date_trunc('month',greatest(start_date,person.hire_date)),date_trunc('month',end_date),interval '1 month') m where not exists(select 1 from public.hr_payroll p where p.employee_id=eid and p.period=m::date and p.status='validated')) then raise exception 'PAYROLL_ACCRUAL_MONTHS_REQUIRED';end if;
 select coalesce(sum((ec_calculation->>(case when p_data->>'kind'='decimo13' then 'decimo13' else 'decimo14' end))::numeric),0) into amount from public.hr_payroll where employee_id=eid and period between start_date and end_date and status='validated' and ec_calculation->'terms'->>(case when p_data->>'kind'='decimo13' then 'decimo13_mode' else 'decimo14_mode' end)='accrued';
 if amount<=0 then raise exception 'PAYROLL_ACCRUAL_EMPTY';end if;
 select * into prof from public.accounting_ec_profile where id;perform private.gama_ec_account(prof.payroll_deductions_account_id,'liability');perform private.gama_ec_account(prof.payroll_payable_account_id,'liability');
 insert into public.hr_ec_benefits(employee_id,kind,from_date,to_date,amount,created_by) values(eid,p_data->>'kind',start_date,end_date,amount,auth.uid()) returning * into benefit;
 entry:=private.gama_accounting_book('OD',today,'Décimo acumulado '||v_year,'ec_benefit',benefit.id,evidence,jsonb_build_array(jsonb_build_object('account_id',prof.payroll_deductions_account_id,'debit',amount),jsonb_build_object('account_id',prof.payroll_payable_account_id,'credit',amount)));
 update public.hr_ec_benefits set entry_id=entry where id=benefit.id;return to_jsonb(benefit)||jsonb_build_object('entry_id',entry);
 elsif p_action='benefit_payment' then
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('ec-benefit-payment:'||key::text,0));select * into payment from public.hr_ec_benefit_payments where request_key=key;
 if found then if payment.benefit_id<>(p_data->>'benefit_id')::uuid or payment.amount<>(p_data->>'amount')::numeric or payment.financial_account_id<>(p_data->>'financial_account_id')::uuid or payment.paid_on is distinct from (p_data->>'paid_on')::date or payment.reference is distinct from p_data->>'reference' then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(payment);end if;
 select * into benefit from public.hr_ec_benefits where id=(p_data->>'benefit_id')::uuid for update;if not found then raise exception 'PAYROLL_NOT_FOUND';end if;
 amount:=private.gama_hr_ec_number(p_data,'amount');if amount<=0 or amount>benefit.amount-coalesce((select sum(amount) from public.hr_ec_benefit_payments where benefit_id=benefit.id),0) then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 if (p_data->>'paid_on')::date>today or nullif(btrim(p_data->>'reference'),'') is null then raise exception 'PAYROLL_PAYMENT_INVALID';end if;
 select * into acc from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and currency='USD';if acc.account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 select * into prof from public.accounting_ec_profile where id;perform private.gama_ec_account(prof.payroll_payable_account_id,'liability');pid:=gen_random_uuid();
 entry:=private.gama_accounting_book(case when acc.kind='cash' then 'CAJ' else 'BAN' end,(p_data->>'paid_on')::date,p_data->>'reference','ec_benefit_payment',pid,'Pago de beneficio laboral',jsonb_build_array(jsonb_build_object('account_id',prof.payroll_payable_account_id,'debit',amount),jsonb_build_object('account_id',acc.account_id,'credit',amount)));
 insert into public.hr_ec_benefit_payments(id,benefit_id,request_key,amount,paid_on,financial_account_id,reference,entry_id,created_by) values(pid,benefit.id,key,amount,(p_data->>'paid_on')::date,acc.id,p_data->>'reference',entry,auth.uid()) returning * into payment;return to_jsonb(payment);
 elsif p_action='bank_export' then
 if v_period is null then raise exception 'INVALID_PERIOD';end if;
 select coalesce(jsonb_agg(x order by x->>'name'),'[]') into out_rows from (
 select jsonb_build_object('employee_id',e.id,'name',e.full_name,'reference',coalesce(p.erp_reference,p.source_ref),'amount',p.net-coalesce((select sum(amount) from public.hr_payroll_payments where payroll_id=p.id and status='confirmed'),0),'bank',t.bank_name,'account',t.bank_number,'account_kind',t.bank_kind,'identification',t.beneficiary_id) x from public.hr_payroll p join public.hr_employees e on e.id=p.employee_id left join lateral(select * from public.hr_ec_employee_terms where employee_id=p.employee_id and effective_from<=date_trunc('month',today)::date order by effective_from desc,created_at desc,id desc limit 1)t on true where p.period=v_period and p.status='validated' and p.net>coalesce((select sum(amount) from public.hr_payroll_payments where payroll_id=p.id and status='confirmed'),0)
 union all select jsonb_build_object('employee_id',e.id,'name',e.full_name,'reference',b.kind||' '||b.to_date,'amount',b.amount-coalesce((select sum(amount) from public.hr_ec_benefit_payments where benefit_id=b.id),0),'bank',t.bank_name,'account',t.bank_number,'account_kind',t.bank_kind,'identification',t.beneficiary_id) from public.hr_ec_benefits b join public.hr_employees e on e.id=b.employee_id left join lateral(select * from public.hr_ec_employee_terms where employee_id=b.employee_id and effective_from<=v_period order by effective_from desc,created_at desc,id desc limit 1)t on true where p_data->>'include_benefits'='true' and b.to_date<=today and b.amount>coalesce((select sum(amount) from public.hr_ec_benefit_payments where benefit_id=b.id),0)
 ) s;
 if exists(select 1 from jsonb_array_elements(out_rows) x where nullif(x->>'bank','') is null or coalesce(x->>'account','') !~ '^[0-9]{5,30}$' or nullif(x->>'identification','') is null) then raise exception 'PAYROLL_BANK_DETAILS_REQUIRED';end if;
 return jsonb_build_object('period',v_period,'rows',out_rows,'total',(select coalesce(sum((x->>'amount')::numeric),0) from jsonb_array_elements(out_rows) x));
 end if;raise exception 'UNKNOWN_ACTION';
end $$;
create function public.gama_hr_ec_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select private.gama_hr_ec_action(p_action,p_data) $$;
revoke all on function private.gama_hr_ec_number(jsonb,text,numeric,numeric,integer),private.gama_hr_ec_days(date,date),private.gama_hr_ec_calculate(uuid,date,jsonb,uuid),private.gama_hr_ec_payroll_guard(),private.gama_hr_ec_utility_calculation(integer,numeric,jsonb,text),private.gama_hr_ec_action(text,jsonb),public.gama_hr_ec_action(text,jsonb) from public,anon,authenticated;
grant execute on function private.gama_hr_ec_action(text,jsonb),public.gama_hr_ec_action(text,jsonb) to authenticated;
-- Include actual benefit payments in bank/cash balances (allocations never count twice).
do $$ declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure);
 s:=replace(s,' AS current_balance',' - coalesce((select sum(hb.amount) from public.hr_ec_benefit_payments hb where hb.financial_account_id=f.id),0) AS current_balance');execute s;
 s:=pg_get_viewdef('private.gama_cash_position'::regclass,true);
 if position(' AS current_balance' in s)=0 then raise exception 'CASH_POSITION_ANCHOR';end if;
 s:=replace(s,' AS current_balance',' - coalesce((select sum(hb.amount) from public.hr_ec_benefit_payments hb where hb.financial_account_id=f.id),0) AS current_balance');
 execute 'create or replace view private.gama_cash_position with(security_invoker=true) as '||s;
end $$;

-- Actual IR withheld in posted employee payroll participates in draft 103.
alter function private.gama_ec_tax_drafts(jsonb) rename to gama_ec_tax_drafts_base_before_payroll;
create function private.gama_ec_tax_drafts(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;payroll jsonb;begin
 result:=private.gama_ec_tax_drafts_base_before_payroll(p_data);
 with components as(
 select e.entry_date,p.ec_calculation calc,1 sign from public.accounting_entries e join public.hr_payroll p on p.id=e.source_id where e.source_type='payroll' and e.status in ('posted','reversed') and p.ec_calculation is not null
 union all select e.entry_date,p.ec_calculation,-1 from public.accounting_entries e join public.accounting_entries original on original.id=e.reversal_of and original.source_type='payroll' join public.hr_payroll p on p.id=original.source_id where e.status='posted' and p.ec_calculation is not null
 ) select jsonb_build_object('base',coalesce(sum(((calc->>'gross')::numeric-(calc->>'personal_iess')::numeric)*sign),0),'withheld',coalesce(sum((calc->>'income_tax')::numeric*sign),0),'roles',count(*) filter(where sign=1)) into payroll from components where entry_date between (p_data->>'from')::date and (p_data->>'to')::date;
 return jsonb_set(result,'{form103}',(result->'form103')||jsonb_build_object('payroll',payroll,'total',(result->'form103'->>'total')::numeric+(payroll->>'withheld')::numeric));
end $$;
revoke all on function private.gama_ec_tax_drafts_base_before_payroll(jsonb),private.gama_ec_tax_drafts(jsonb) from public,anon,authenticated;
grant execute on function private.gama_ec_tax_drafts(jsonb) to authenticated;
-- Payroll benefits are cash expenses when paid, independently of the accrual date.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure);
 if position(') s group by m)' in s)=0 then raise exception 'CASHFLOW_BENEFIT_ANCHOR';end if;
 s:=replace(s,') s group by m)', ' union all select to_char(hb.paid_on,''YYYY-MM''),0,hb.amount from public.hr_ec_benefit_payments hb where hb.paid_on between d1 and d2) s group by m)');execute s;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005004521','ec_payroll_calculation_and_employee_receipts','4eac045a83c5d0d57ffb10b0a65d897edeb1588367112add6b0a925be43781b5','4eac045a83c5d0d57ffb10b0a65d897edeb1588367112add6b0a925be43781b5','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005013055_ec_stock_thresholds_and_supplier_score.sql; SHA256 7cf7378c791dae8ba6d1f0003987ecda73e29f4e3c57c26319f5ea107791c73a
-- Commercial dispatches only: internal moves, consumption and draft orders are not sales.
create function private.gama_stock_sales_threshold_rows() returns table(product_id uuid,data jsonb)
language sql stable security invoker set search_path='' as $$
 with demand as (
  select l.product_id,sum(d.quantity) quantity from public.sales_delivery_lines d
  join public.sales_deliveries h on h.id=d.delivery_id join public.sales_order_lines l on l.id=d.order_line_id
  where h.dispatched_at>=now()-interval '90 days' and h.dispatched_at<=now() group by l.product_id
 ), base as (
  select p.*,coalesce(d.quantity,0) sales90,r.rules,r.rule_id,r.minimum,r.maximum,
   greatest(1,coalesce(r.lead,7)) lead,r.lead is not null lead_configured,
   exists(select 1 from public.reorder_rules w where w.product_id=p.id and w.active and w.warehouse_id is not null) local_rules
  from public.products p join demand d on d.product_id=p.id
  left join lateral (select count(*) rules,(array_agg(g.id order by g.id))[1] rule_id,
   max(g.min_quantity) minimum,max(g.max_quantity) maximum,max(g.lead_time_days) lead
   from public.reorder_rules g where g.product_id=p.id and g.active and g.warehouse_id is null) r on true
  where p.active and p.product_kind='goods' and not p.replenishment_excluded
 ), proposals as (
  select b.*,ceil(sales90/90*lead*1.5) proposed_min,ceil(sales90/90*(lead*1.5+14)) proposed_max,
   coalesce(minimum,min_stock,0) current_min,coalesce(maximum,max_stock,0) current_max,
   rules<=1 and (rules=1 or not local_rules) can_apply
  from base b
 )
 select id,jsonb_build_object('id',id,'name',name,'reference',reference,'sales90',sales90,
  'daily',round(sales90/90,3),'lead_time_days',lead,'lead_configured',lead_configured,
  'current_min',current_min,'current_max',current_max,'proposed_min',proposed_min,'proposed_max',proposed_max,
  'can_apply',can_apply,'changed',current_min<>proposed_min or current_max<>proposed_max,
  'fingerprint',md5(jsonb_build_object('sales',sales90,'min',current_min,'max',current_max,'lead',lead,
   'rule',rule_id,'rules',rules,'local',local_rules,'product_min',min_stock,'product_max',max_stock)::text))
 from proposals
$$;
revoke all on function private.gama_stock_sales_threshold_rows() from public,anon,authenticated;
create function private.gama_stock_sales_thresholds(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid;item jsonb;fresh jsonb;rows jsonb;key uuid;payload jsonb:=p_data-'request_key';receipt private.command_receipts;rule uuid;result jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then
 select coalesce(jsonb_agg(r.data order by r.data->>'name'),'[]') into rows from private.gama_stock_sales_threshold_rows() r;
 return jsonb_build_object('rows',rows,'as_of',now(),'can_apply',private.erp_module_allowed('products',array['administrador','comercial']) and private.erp_action_allowed('products','edit') and private.erp_action_allowed('warehouses','validate'));
 end if;
 if p_action<>'apply' then raise exception 'INVALID_ACTION';end if;
 if not private.erp_module_allowed('products',array['administrador','comercial']) or not private.erp_action_allowed('products','edit') or not private.erp_action_allowed('warehouses','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('sales-threshold-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='sales-thresholds' and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items') not between 1 and 3000 or (select count(distinct v->>'id') from jsonb_array_elements(p_data->'items') v)<>jsonb_array_length(p_data->'items') then raise exception 'INVALID_LINES';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-sales-thresholds',0));
 for v_id in select (v->>'id')::uuid from jsonb_array_elements(p_data->'items') v order by v->>'id' loop
  perform 1 from public.products p where p.id=v_id for update;
  perform 1 from public.reorder_rules r where r.product_id=v_id order by r.id for update;
 end loop;
 for item in select value from jsonb_array_elements(p_data->'items') loop
  select r.data into fresh from private.gama_stock_sales_threshold_rows() r where r.product_id=(item->>'id')::uuid;
  if fresh is null or not (fresh->>'can_apply')::boolean or fresh->>'fingerprint' is distinct from item->>'fingerprint' then raise exception 'STOCK_THRESHOLDS_CHANGED';end if;
  update public.products p set min_stock=(fresh->>'proposed_min')::numeric,max_stock=(fresh->>'proposed_max')::numeric where p.id=(item->>'id')::uuid;
  select r.id into rule from public.reorder_rules r where r.product_id=(item->>'id')::uuid and r.active and r.warehouse_id is null;
  if rule is null then insert into public.reorder_rules(product_id,min_quantity,max_quantity,lead_time_days,supplier_id)
   select p.id,(fresh->>'proposed_min')::numeric,(fresh->>'proposed_max')::numeric,(fresh->>'lead_time_days')::integer,p.supplier_id from public.products p where p.id=(item->>'id')::uuid;
  else update public.reorder_rules set min_quantity=(fresh->>'proposed_min')::numeric,max_quantity=(fresh->>'proposed_max')::numeric where reorder_rules.id=rule;end if;
 end loop;
 result:=jsonb_build_object('updated',jsonb_array_length(p_data->'items'),'as_of',now());
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('sales-thresholds',key,auth.uid(),payload,result);return result;
end $$;
create function public.gama_stock_sales_thresholds(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_stock_sales_thresholds(p_action,p_data)$$;
revoke all on function private.gama_stock_sales_thresholds(text,jsonb),public.gama_stock_sales_thresholds(text,jsonb) from public,anon;
grant execute on function private.gama_stock_sales_thresholds(text,jsonb),public.gama_stock_sales_thresholds(text,jsonb) to authenticated;

-- A split first receipt is an incomplete delivery even if the order is later completed.
create or replace function public.gama_supplier_performance(p_id uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;begin
 if not private.erp_module_allowed('suppliers',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 with receipts as (
  select m.reference_id order_id,min(m.created_at) first_receipt,max(m.created_at) last_receipt
  from public.stock_movements m where m.reference_type='purchase_order' and m.movement_type='receipt' and m.type='in' group by m.reference_id
 ), orders as (
  select o.*,r.first_receipt,r.last_receipt,
   case when r.first_receipt is not null then exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id group by l.product_id
    having sum(l.quantity)>coalesce((select sum(m.quantity) from public.stock_movements m where m.reference_id=o.id and m.reference_type='purchase_order' and m.movement_type='receipt' and m.type='in' and m.product_id=l.product_id and m.created_at=r.first_receipt),0)) end first_incomplete,
   case when o.status='received' and o.expected_date is not null and r.last_receipt is not null then (r.last_receipt at time zone private.erp_timezone())::date<=(o.expected_date at time zone private.erp_timezone())::date end on_time
  from public.purchase_orders o left join receipts r on r.order_id=o.id where o.supplier_id=p_id and o.status<>'cancelled'
 ) select jsonb_build_object('orders',count(*),'received',count(*) filter(where status='received'),'measured',count(on_time),'on_time',count(*) filter(where on_time),
  'on_time_percent',round(100.0*count(*) filter(where on_time)/nullif(count(on_time),0),1),
  'average_lead_days',round(avg((last_receipt at time zone private.erp_timezone())::date-(order_date at time zone private.erp_timezone())::date) filter(where status='received' and last_receipt is not null),1),
  'promised_lead_days',round(avg((expected_date at time zone private.erp_timezone())::date-(order_date at time zone private.erp_timezone())::date) filter(where status='received' and last_receipt is not null and expected_date is not null),1),
  'average_delay_days',round(avg((last_receipt at time zone private.erp_timezone())::date-(expected_date at time zone private.erp_timezone())::date) filter(where status='received' and last_receipt is not null and expected_date is not null),1),
  'receipts_measured',count(first_incomplete),'first_incomplete',count(*) filter(where first_incomplete),'incomplete_percent',round(100.0*count(*) filter(where first_incomplete)/nullif(count(first_incomplete),0),1),
  'late_open',count(*) filter(where status in ('sent','partial') and (expected_date at time zone private.erp_timezone())::date<(now() at time zone private.erp_timezone())::date),
  'returns',(select count(*) from public.return_orders where supplier_id=p_id and status<>'cancelled'),'generated_at',now()) into result from orders;return result;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005013055','ec_stock_thresholds_and_supplier_score','7cf7378c791dae8ba6d1f0003987ecda73e29f4e3c57c26319f5ea107791c73a','7cf7378c791dae8ba6d1f0003987ecda73e29f4e3c57c26319f5ea107791c73a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005013608_ec_direction_and_actionable_intelligence.sql; SHA256 76d07ff189903944a6903ede2d6c70f037cd2ae2c8d2e35a76a8824065276a0b
-- One bounded read for management. Each figure retains its source module's authorization.
create function private.gama_management_overview(p_context text default 'dashboard') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;month_start date;metrics jsonb:='{}';clients jsonb:='[]';purchase jsonb:='[]';client_count integer:=0;purchase_count integer:=0;value jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(p_context,array['administrador']) or p_context not in ('dashboard','assistant-ia') then raise exception 'ROLE_NOT_ALLOWED';end if;
 month_start:=date_trunc('month',today)::date;
 if private.erp_module_allowed('payments',array['administrador']) then
  with valid as(select i.* from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')),
  reductions as(select coalesce(sum(c.amount*i.subtotal/nullif(i.total,0)),0) net from public.return_credits c join valid i on i.id=c.invoice_id where c.issued_on between month_start and today),
  movement_cost as(select m.reference_id delivery_id,m.product_id,sum(m.quantity*m.unit_cost_at_movement)/nullif(sum(m.quantity),0) cost,bool_and(m.unit_cost_at_movement is not null) complete
   from public.stock_movements m where m.type='out' and m.movement_type='delivery' and m.reference_type='sales_delivery' group by m.reference_id,m.product_id),
  cost_by_line as(select l.id,sum(d.quantity*c.cost)/nullif(sum(d.quantity),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.sales_order_lines l join public.sales_delivery_lines d on d.order_line_id=l.id left join movement_cost c on c.delivery_id=d.delivery_id and c.product_id=l.product_id group by l.id),
  invoice_cost as(select x.invoice_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x left join cost_by_line c on c.id=x.order_line_id group by x.invoice_id),
  restored as(select coalesce(sum(l.quantity*c.cost),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.return_lines l join public.return_orders r on r.id=l.return_id join public.sales_delivery_lines d on d.id=l.delivery_line_id left join cost_by_line c on c.id=d.order_line_id
   where l.disposition='restocked' and l.processed_at is not null and exists(select 1 from public.return_credits n where n.return_id=r.id and n.invoice_id is not null and n.issued_on between month_start and today)),
  totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost,count(*) missing
   from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today and not coalesce(c.complete,false)),
  full_totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today)
  select jsonb_build_object('sales_month',round(f.net-r.net,2),'margin_month',case when t.missing=0 and coalesce(s.complete,true) then round(f.net-r.net-f.cost+s.cost,2) end,'margin_missing_invoices',t.missing,'margin_basis','historical_dispatch_cost',
   'overdue',coalesce((select sum(balance) from private.gama_customer_dues() where coalesce(due_date,issue_date)<today),0)) into value from full_totals f cross join reductions r cross join totals t cross join restored s;
  if not private.erp_module_allowed('accounting',array['administrador']) then value:=value-'margin_month'-'margin_missing_invoices'-'margin_basis';end if;
  metrics:=metrics||value;
  with grouped as(select customer_id id,customer_name name,sum(balance) balance,min(coalesce(due_date,issue_date)) oldest_due from private.gama_customer_dues() where coalesce(due_date,issue_date)<today group by customer_id,customer_name),
  limited as(select * from grouped order by balance desc,oldest_due,id limit 10)
  select (select count(*) from grouped),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('days_late',today-l.oldest_due) order by l.balance desc,l.oldest_due,l.id),'[]') into client_count,clients from limited l;
 end if;
 if private.erp_module_allowed('warehouses',array['administrador']) then
  select jsonb_build_object('stockouts',count(*) filter(where (r.data->>'available')::numeric<=0),'dormant_stock_value',coalesce(sum((r.data->>'value')::numeric) filter(where (r.data->>'on_hand')::numeric>0 and (r.data->>'days_without_out')::integer>=90),0)) into value from private.stock_insight_rows(false) r;metrics:=metrics||value;
  if private.erp_module_allowed('gamaPurchasesV14',array['administrador']) then
   with all_rows as(select data from private.stock_insight_rows(true) where (data->>'suggested_quantity')::numeric>0),limited as(select data from all_rows order by (data->>'available')::numeric,data->>'name' limit 20)
   select (select count(*) from all_rows),coalesce(jsonb_agg(data),'[]') into purchase_count,purchase from limited;
  end if;
 end if;
 if private.erp_module_allowed('tms',array['administrador']) then
  select jsonb_build_object('late_deliveries',count(*) filter(where status not in ('Entregada','Cancelada') and (delivery_date<today or (delivery_date=today and eta_at<now())))) into value from public.tms_deliveries;metrics:=metrics||value;
 end if;
 return jsonb_build_object('today',today,'month_start',month_start,'generated_at',now(),'metrics',metrics,'clients',clients,'client_count',client_count,'purchases',purchase,'purchase_count',purchase_count);
end $$;
create function public.gama_management_overview(p_context text default 'dashboard') returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_management_overview(p_context)$$;
revoke all on function private.gama_management_overview(text),public.gama_management_overview(text) from public,anon;
grant execute on function private.gama_management_overview(text),public.gama_management_overview(text) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005013608','ec_direction_and_actionable_intelligence','76d07ff189903944a6903ede2d6c70f037cd2ae2c8d2e35a76a8824065276a0b','76d07ff189903944a6903ede2d6c70f037cd2ae2c8d2e35a76a8824065276a0b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005014142_ec_b2b_customer_portal.sql; SHA256 f8c54b25e9cbec8da37e97c9ea23384f42d2b4196e5205d71ae8706e219b5837
-- B2B access is separate from price categories A/B/C and never inferred from an email.
-- Retired cliente profiles stay inactive in the ERP. Only these explicit memberships
-- grant the standalone portal; the ERP's restrictive customer policies remain intact.
create table public.b2b_customer_access(customer_id uuid primary key references public.customers(id),enabled boolean not null default false,updated_at timestamptz not null default now(),updated_by uuid not null references public.profiles(id));
create table public.b2b_memberships(profile_id uuid primary key references public.profiles(id),customer_id uuid not null references public.customers(id),active boolean not null default true,updated_at timestamptz not null default now(),updated_by uuid not null references public.profiles(id));
create index b2b_memberships_customer on public.b2b_memberships(customer_id);
create index b2b_memberships_actor on public.b2b_memberships(updated_by);
create index b2b_customer_access_actor on public.b2b_customer_access(updated_by);
do $$declare t text;begin foreach t in array array['b2b_customer_access','b2b_memberships'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 execute format('create policy b2b_admin_read on public.%I for select to authenticated using(private.erp_module_allowed(''website'',array[''administrador'']) and private.erp_mfa_ok())',t);
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
end loop;end $$;
alter table public.customer_requests add column delivery_address_id uuid references public.customer_addresses(id),add column delivery_address_snapshot text;
create index customer_requests_delivery_address on public.customer_requests(delivery_address_id) where delivery_address_id is not null;

create function private.gama_b2b_customer() returns uuid language plpgsql stable security definer set search_path='' as $$
declare cid uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 select m.customer_id into cid from public.b2b_memberships m join public.b2b_customer_access a on a.customer_id=m.customer_id
 join public.profiles p on p.id=m.profile_id join auth.users u on u.id=p.id join public.customers c on c.id=m.customer_id
 where m.profile_id=auth.uid() and m.active and a.enabled and c.active and p.role='cliente' and p.deleted_at is null
 and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now());
 if cid is null or exists(select 1 from public.app_modules where id='website' and not enabled) then raise exception 'B2B_ACCESS_REQUIRED';end if;return cid;
end $$;
revoke all on function private.gama_b2b_customer() from public,anon,authenticated;

create function private.gama_b2b_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=nullif(p_data->>'customer_id','')::uuid;uid uuid:=nullif(p_data->>'profile_id','')::uuid;search text:=left(coalesce(p_data->>'search',''),100);old_member public.b2b_memberships;begin
 if not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then return jsonb_build_object('customers',coalesce((select jsonb_agg(to_jsonb(z)) from(select c.id,c.name,c.identification,c.category,coalesce(a.enabled,false) enabled from public.customers c left join public.b2b_customer_access a on a.customer_id=c.id where c.active and c.name ilike '%'||search||'%' order by c.name,c.id limit 100) z),'[]'),
 'accounts',case when private.erp_module_allowed('users',array['administrador']) then coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.full_name,u.email,(u.email_confirmed_at is not null) verified,m.customer_id linked_customer_id,c.name linked_customer_name from public.profiles p join auth.users u on u.id=p.id left join public.b2b_memberships m on m.profile_id=p.id left join public.customers c on c.id=m.customer_id where p.deleted_at is null and p.role='cliente' and (coalesce(u.email,'') ilike '%'||left(coalesce(p_data->>'account_search',''),100)||'%' or p.full_name ilike '%'||left(coalesce(p_data->>'account_search',''),100)||'%') order by p.full_name,p.id limit 100) z),'[]') else '[]'::jsonb end,
 'memberships',coalesce((select jsonb_agg(jsonb_build_object('profile_id',m.profile_id,'customer_id',m.customer_id,'active',m.active,'name',p.full_name)) from public.b2b_memberships m join public.profiles p on p.id=m.profile_id where m.customer_id in(select c.id from public.customers c where c.active and c.name ilike '%'||search||'%' order by c.name,c.id limit 100)),'[]'));
 end if;
 if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('clients',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.customers where id=cid and active for update;if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 if p_action='invitation_context' then
 if not private.gama_identity_admin_allowed() or not private.erp_action_allowed('users','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from public.b2b_customer_access where customer_id=cid and enabled) then raise exception 'B2B_ACCESS_REQUIRED';end if;
 return jsonb_build_object('allowed',true,'customer_name',(select name from public.customers where id=cid));
 end if;
 if p_action='access' then
 if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'INVALID_DATA';end if;
 insert into public.b2b_customer_access(customer_id,enabled,updated_by) values(cid,(p_data->>'enabled')::boolean,auth.uid()) on conflict(customer_id) do update set enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;
 if p_action='member' then
 if not private.erp_module_allowed('users',array['administrador']) or not private.erp_action_allowed('users','edit') or jsonb_typeof(p_data->'active') is distinct from 'boolean' then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.profiles p join auth.users u on u.id=p.id where p.id=uid and p.deleted_at is null and p.role='cliente' for update of p;if not found then raise exception 'B2B_CLIENT_ACCOUNT_REQUIRED';end if;
 select * into old_member from public.b2b_memberships where profile_id=uid for update;
 if old_member.customer_id=cid and old_member.active=(p_data->>'active')::boolean then return jsonb_build_object('saved',true);end if;
 if old_member.customer_id is distinct from nullif(p_data->>'expected_customer_id','')::uuid then raise exception 'B2B_MEMBERSHIP_CHANGED';end if;
 insert into public.b2b_memberships(profile_id,customer_id,active,updated_by) values(uid,cid,(p_data->>'active')::boolean,auth.uid()) on conflict(profile_id) do update set customer_id=excluded.customer_id,active=excluded.active,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_b2b_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_b2b_admin(p_action,p_data)$$;

-- One price calculation for staff and the scoped portal; this pure helper is
-- inaccessible to authenticated callers. Existing staff resolver guards remain.
create function private.erp_price_calculate(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.customers;p public.products;r record;special numeric;today date;begin
 select * into c from public.customers where id=p_customer and active;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select * into p from public.products where id=p_product and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'INVALID_QUANTITY';end if;
 today:=coalesce(p_date,(now() at time zone (select timezone from public.erp_policies where id))::date);
 select b.name,b.kind,t.unit_price into r from public.erp_price_tiers t join public.erp_price_books b on b.id=t.book_id
 where t.product_id=p_product and t.min_quantity<=p_quantity and b.status='approved' and today>=b.valid_from and (b.valid_to is null or today<=b.valid_to)
  and (b.category is null or b.category=c.category)
  and (exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id and bc.customer_id=c.id)
       or (b.kind<>'contract' and not exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id)))
 order by case b.kind when 'contract' then 3 when 'promotion' then 2 else 1 end desc,b.priority desc,t.min_quantity desc,b.valid_from desc,b.id limit 1;
 select unit_price into special from public.customer_special_prices where customer_id=c.id and product_id=p.id;
 if r.kind='contract' then return jsonb_build_object('unit_price',r.unit_price,'source','contract','label',r.name,'date',today,'quantity',p_quantity);end if;
 if c.category='C' and special is not null then return jsonb_build_object('unit_price',special,'source','customer_contract','label','Contrato cliente','date',today,'quantity',p_quantity);end if;
 if r.kind is not null then return jsonb_build_object('unit_price',r.unit_price,'source',r.kind,'label',r.name,'date',today,'quantity',p_quantity);end if;
 return jsonb_build_object('unit_price',case when c.category='B' then p.sale_price_b else p.sale_price end,'source','category','label','Categoría '||c.category,'date',today,'quantity',p_quantity);
end $$;
revoke all on function private.erp_price_calculate(uuid,uuid,numeric,date) from public,anon,authenticated;
create or replace function private.erp_price(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.customers;begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=p_customer and active;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 if private.current_user_role()='cliente' and not exists(select 1 from auth.users u where u.id=auth.uid() and lower(u.email)=lower(c.email)) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return private.erp_price_calculate(p_customer,p_product,p_quantity,p_date);
end $$;

create function private.gama_b2b_cart(p_customer uuid,p_lines jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare line jsonb;p public.products;price jsonb;qty numeric;net numeric;tax numeric;items jsonb:='[]';total numeric:=0;begin
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 100 or (select count(distinct x->>'product_id') from jsonb_array_elements(p_lines) x)<>jsonb_array_length(p_lines) then raise exception 'B2B_INVALID_LINES';end if;
 for line in select value from jsonb_array_elements(p_lines) order by value->>'product_id' loop
 select * into p from public.products where id=(line->>'product_id')::uuid and active and product_kind='goods';if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 qty:=(line->>'quantity')::numeric;if qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
 if qty<p.order_minimum or mod(qty,p.order_multiple)<>0 then raise exception 'PACK_QUANTITY_REQUIRED';end if;
 price:=private.erp_price_calculate(p_customer,p.id,qty,null);net:=round(qty*(price->>'unit_price')::numeric,2);tax:=round(net*p.tax_rate/100,2);total:=total+net+tax;
 items:=items||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'reference',p.reference,'quantity',qty,'unit_price',(price->>'unit_price')::numeric,'tax_rate',p.tax_rate,'net',net,'tax',tax,'total',net+tax,'price_source',price->>'label'));
 end loop;return jsonb_build_object('lines',items,'total',total,'price_hash',md5(items::text));end $$;
revoke all on function private.gama_b2b_cart(uuid,jsonb) from public,anon,authenticated;

create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.gama_b2b_customer();off integer:=coalesce((p_data->>'offset')::integer,0);v_id uuid:=nullif(p_data->>'id','')::uuid;
 today date:=(now() at time zone private.erp_timezone())::date;customer public.customers;invoice public.external_invoices;f public.external_invoice_files;sri public.sri_invoice_issues;adr public.customer_addresses;key uuid;receipt private.command_receipts;payload jsonb:=p_data-'request_key';cart jsonb;line jsonb;rid uuid;reference text;rows jsonb;cnt integer;result jsonb;balance numeric;overdue numeric;begin
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 select * into customer from public.customers where customers.id=cid;
 if p_action='bootstrap' then
 select coalesce(sum(d.balance),0),coalesce(sum(d.balance) filter(where coalesce(d.due_date,d.issue_date)<today),0) into balance,overdue from private.gama_customer_dues(cid) d;
 return jsonb_build_object('customer',jsonb_build_object('name',customer.name,'identification',customer.identification,'category',customer.category),'today',today,'currency',(select currency from public.company_settings where company_settings.id),
 'total',balance,'overdue',overdue,'addresses',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'label',a.label,'address',a.address,'city',a.city) order by a.label) from public.customer_addresses a where a.customer_id=cid and a.active and a.purpose in ('delivery','order')),'[]'));
 end if;
 if p_action='catalog' then
 with filtered as(select p.id,p.name,p.reference,p.category,p.description,p.has_photo,p.order_minimum,p.order_multiple,p.tax_rate
  from public.products p where p.active and p.product_kind='goods' and (p.name ilike '%'||left(coalesce(p_data->>'search',''),100)||'%' or p.reference ilike '%'||left(coalesce(p_data->>'search',''),100)||'%')),
 limited as(select * from filtered order by name,id limit 30 offset off)
 select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('unit_price',private.erp_price_calculate(cid,l.id,greatest(1,l.order_minimum),null)->'unit_price') order by name,id),'[]') into cnt,rows from limited l;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='photo' then
 if not exists(select 1 from public.products p where p.id=v_id and p.active and p.product_kind='goods') then raise exception 'PRODUCT_NOT_FOUND';end if;
 return jsonb_build_object('photo',(select ph.photo from public.product_photos ph where ph.product_id=v_id));
 end if;
 if p_action='preview' then return private.gama_b2b_cart(cid,p_data->'lines');end if;
 if p_action='favorites' then return coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'lines',coalesce((select jsonb_agg(jsonb_build_object('product_id',l.product_id,'quantity',l.quantity,'name',p.name,'active',p.active) order by p.name) from public.favorite_order_lines l join public.products p on p.id=l.product_id where l.favorite_order_id=o.id),'[]')) order by o.created_at desc,o.id) from public.favorite_orders o where o.created_by=auth.uid()),'[]');end if;
 if p_action='favorite_delete' then delete from public.favorite_orders where favorite_orders.id=v_id and created_by=auth.uid();if not found then raise exception 'NOT_FOUND';end if;return jsonb_build_object('deleted',true);end if;
 if p_action in ('submit','favorite_save') then
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('b2b-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='b2b-'||p_action and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if (select count(*) from private.command_receipts where actor_id=auth.uid() and domain='b2b-'||p_action and created_at>now()-interval '1 hour')>=60 then raise exception 'B2B_RATE_LIMIT';end if;
 cart:=private.gama_b2b_cart(cid,p_data->'lines');
 if p_action='favorite_save' then
 if length(btrim(coalesce(p_data->>'name',''))) not between 1 and 80 or (select count(*) from public.favorite_orders where created_by=auth.uid())>=30 then raise exception 'B2B_FAVORITE_LIMIT';end if;
 insert into public.favorite_orders(created_by,name) values(auth.uid(),btrim(p_data->>'name')) returning favorite_orders.id into rid;
 for line in select value from jsonb_array_elements(cart->'lines') loop insert into public.favorite_order_lines(favorite_order_id,product_id,quantity) values(rid,(line->>'product_id')::uuid,(line->>'quantity')::numeric);end loop;result:=jsonb_build_object('id',rid);
 else
 if cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
 if length(coalesce(p_data->>'notes',''))>2000 or (nullif(p_data->>'requested_delivery_date','')::date is not null and nullif(p_data->>'requested_delivery_date','')::date<today) then raise exception 'INVALID_DATA';end if;
 if nullif(p_data->>'address_id','') is not null then select * into adr from public.customer_addresses where customer_addresses.id=(p_data->>'address_id')::uuid and customer_id=cid and active and purpose in ('delivery','order');if not found then raise exception 'B2B_ADDRESS_NOT_FOUND';end if;end if;
 insert into public.customer_requests(customer_id,created_by,status,requester_name,requester_email,notes,total,requested_delivery_date,delivery_address_id,delivery_address_snapshot)
 values(cid,auth.uid(),'pending',customer.name,customer.email,coalesce(p_data->>'notes',''),(cart->>'total')::numeric,nullif(p_data->>'requested_delivery_date','')::date,adr.id,case when adr.id is not null then concat_ws(', ',adr.address,adr.city) else customer.address end) returning customer_requests.id,erp_reference into rid,reference;
 for line in select value from jsonb_array_elements(cart->'lines') loop insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total) values(rid,(line->>'product_id')::uuid,(line->>'quantity')::numeric,(line->>'unit_price')::numeric,(line->>'tax_rate')::numeric,(line->>'net')::numeric);end loop;
 result:=jsonb_build_object('id',rid,'reference',reference,'total',cart->'total');
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('b2b-'||p_action,key,auth.uid(),payload,result);return result;
 end if;
 if p_action='requests' then return coalesce((select jsonb_agg(to_jsonb(z)) from(select r.erp_reference reference,r.status,r.total,r.created_at,r.requested_delivery_date,r.delivery_address_snapshot from public.customer_requests r where r.customer_id=cid order by r.created_at desc,r.id limit 30 offset off) z),'[]');end if;
 if p_action='invoices' then
 with owned as(select i.* from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected')),
 limited as(select * from owned order by issue_date desc,id limit 30 offset off)
 select (select count(*) from owned),coalesce(jsonb_agg(jsonb_build_object('id',i.id,'reference',coalesce(i.erp_reference,i.number),'fiscal_number',coalesce(i.external_number,i.number),'issue_date',i.issue_date,'due_date',i.due_date,'total',i.total,'status',case when i.document_kind='internal' then coalesce(i.external_status,i.fiscal_status) else i.fiscal_status end,
 'balance',coalesce((select sum(d.balance) from private.gama_customer_dues(cid,array[i.id]) d),0),
 'sri_id',(select s.id from public.sri_invoice_issues s where s.source_invoice_id=i.id and s.status='authorized'),
 'files',coalesce((select jsonb_agg(jsonb_build_object('id',fl.id,'mime_type',fl.mime_type)) from public.external_invoice_files fl where fl.invoice_id=i.id),'[]')) order by i.issue_date desc,i.id),'[]') into cnt,rows from limited i;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='invoice_file' then
 select x.* into f from public.external_invoice_files x join public.external_invoices i on i.id=x.invoice_id join public.sales_orders o on o.id=i.order_id where x.id=v_id and o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected');if not found then raise exception 'NOT_FOUND';end if;
 select coalesce(i.erp_reference,i.number) into reference from public.external_invoices i where i.id=f.invoice_id;
 return jsonb_build_object('content_base64',f.content_base64,'mime_type',f.mime_type,'filename',reference||case when f.mime_type='application/pdf' then '.pdf' else '.xml' end);
 end if;
 if p_action='sri_document' then
 select x.* into sri from public.sri_invoice_issues x join public.external_invoices i on i.id=x.source_invoice_id join public.sales_orders o on o.id=i.order_id where x.id=v_id and x.customer_id=cid and o.customer_id=cid and x.status='authorized' and i.fiscal_status not in ('cancelled','rejected');if not found then raise exception 'NOT_FOUND';end if;
 if p_data->>'kind' not in ('xml','ride') then raise exception 'INVALID_DATA';end if;
 select coalesce(i.erp_reference,i.number) into reference from public.external_invoices i where i.id=sri.source_invoice_id;
 return jsonb_build_object('path',case when p_data->>'kind'='xml' then sri.authorized_xml_path else sri.ride_path end,'filename',reference||case when p_data->>'kind'='xml' then '.xml' else '.pdf' end);
 end if;
 if p_action='deliveries' then
 with owned as(select d.* from public.tms_deliveries d where d.customer_id=cid and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid)),limited as(select * from owned order by delivery_date desc,id limit 30 offset off)
 select (select count(*) from owned),coalesce(jsonb_agg(jsonb_build_object('id',d.id,'reference',d.erp_reference,'date',d.delivery_date,'address',d.address,'status',d.status,'delivered_at',d.delivered_at,'has_proof',exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)) order by d.delivery_date desc,d.id),'[]') into cnt,rows from limited d;return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='proof' then
 select jsonb_build_object('reference',d.erp_reference,'customer',customer.name,'address',d.address,'date',d.delivery_date,'delivered_at',d.delivered_at,'photo',p.photo,'signature',p.signature,'captured_at',p.captured_at,'latitude',p.latitude,'longitude',p.longitude,'accuracy',p.gps_accuracy_m)
 into result from public.tms_deliveries d join public.tms_proofs p on p.delivery_id=d.id where d.id=v_id and d.customer_id=cid and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid);if result is null then raise exception 'NOT_FOUND';end if;return result;
 end if;
 if p_action='statement' then
 select count(*),coalesce(sum(d.balance),0),coalesce(sum(d.balance) filter(where coalesce(d.due_date,d.issue_date)<today),0) into cnt,balance,overdue from private.gama_customer_dues(cid) d;
 if coalesce((p_data->>'export')::boolean,false) and cnt>10000 then raise exception 'B2B_STATEMENT_EXPORT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(d) order by coalesce(d.due_date,d.issue_date),d.number,d.position),'[]') into rows from(select d.number,d.issue_date,d.due_date,d.amount,d.balance,d.position from private.gama_customer_dues(cid) d order by coalesce(d.due_date,d.issue_date),d.number,d.position limit case when coalesce((p_data->>'export')::boolean,false) then 10000 else 30 end offset off) d;
 return jsonb_build_object('customer',jsonb_build_object('name',customer.name,'identification',customer.identification),'today',today,'total',balance,'overdue',overdue,'count',cnt,'rows',rows,
 'company',(select jsonb_build_object('legal_name',c.legal_name,'tax_id',c.tax_id,'address',c.address,'phone',c.phone,'email',c.email,'currency',c.currency,'country',c.country,'logo_data',c.logo_data,'website',c.website,'document_primary',c.document_primary,'document_secondary',c.document_secondary) from public.company_settings c where c.id));
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_b2b_action(p_action,p_data)$$;
revoke all on function private.gama_b2b_admin(text,jsonb),public.gama_b2b_admin(text,jsonb),private.gama_b2b_action(text,jsonb),public.gama_b2b_action(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_admin(text,jsonb),public.gama_b2b_admin(text,jsonb),private.gama_b2b_action(text,jsonb),public.gama_b2b_action(text,jsonb) to authenticated;

-- Preserve the reviewed delivery address through request → quote → confirmed order → TMS.
alter function private.gama_quote_from_request(uuid,jsonb) rename to gama_quote_from_request_before_b2b;
create function private.gama_quote_from_request(p_request_id uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.customer_requests;d jsonb;begin
 if auth.uid() is null or not private.erp_module_allowed('customer-requests',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into r from public.customer_requests where id=p_request_id for update;
 d:=p_data;
 if r.delivery_address_id is not null then
 if r.customer_id is distinct from nullif(p_data->>'customer_id','')::uuid then raise exception 'B2B_ADDRESS_CUSTOMER_CHANGED';end if;
 d:=jsonb_set(d,'{details}',coalesce(d->'details','{}')||jsonb_build_object('delivery_address',r.delivery_address_snapshot));
 end if;
 return private.gama_quote_from_request_before_b2b(p_request_id,d);
end $$;
revoke all on function private.gama_quote_from_request_before_b2b(uuid,jsonb) from public,anon,authenticated;
revoke all on function private.gama_quote_from_request(uuid,jsonb) from public,anon;
grant execute on function private.gama_quote_from_request(uuid,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005014142','ec_b2b_customer_portal','f8c54b25e9cbec8da37e97c9ea23384f42d2b4196e5205d71ae8706e219b5837','f8c54b25e9cbec8da37e97c9ea23384f42d2b4196e5205d71ae8706e219b5837','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005022907_ec_returns_service_workspace.sql; SHA256 5ed7816b20e2ade77d992ad2bf6461dd658d1d554ed51637364fb9e0bc887416
-- One navigation workspace; preserve the public IDs and each tab's base roles.
create or replace function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard'
  when 'sales-orders' then 'quotes' when 'payments' then 'quotes' when 'sav' then 'returns' end
$$;
create or replace function private.service_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select module_id in ('sav','documents') and private.erp_module_allowed(module_id,
  case when module_id='documents' then array['administrador','comercial','almacenero'] else array['administrador','comercial'] end)
$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005022907','ec_returns_service_workspace','5ed7816b20e2ade77d992ad2bf6461dd658d1d554ed51637364fb9e0bc887416','5ed7816b20e2ade77d992ad2bf6461dd658d1d554ed51637364fb9e0bc887416','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005053550_ec_release_access_and_indexes.sql; SHA256 799453c4e5313dd379e8788063bb8521a4d95b3b5ec5c0cc2bfb792f5f5ec85a
-- Cover the references added by supplier withholding configuration.
create index supplier_withholding_income_account on public.supplier_withholding_policies(income_account_id);
create index supplier_withholding_vat_account on public.supplier_withholding_policies(vat_account_id);
create index supplier_withholding_reviewer on public.supplier_withholding_policies(reviewed_by);

-- One SELECT policy per table retains the existing HR/employee/finance scopes.
-- User-wide checks are evaluated once; ownership still depends on each row.
drop policy hr_ec_terms_own on public.hr_ec_employee_terms;
alter policy hr_ec_read on public.hr_ec_employee_terms using(
 (select private.erp_mfa_ok()) and ((select private.hr_admin()) or private.hr_own(employee_id))
);
drop policy hr_ec_signature_own on public.hr_ec_payroll_signatures;
alter policy hr_ec_read on public.hr_ec_payroll_signatures using(
 (select private.erp_mfa_ok()) and ((select private.hr_admin()) or private.hr_own(employee_id))
);
drop policy hr_ec_benefits_own on public.hr_ec_benefits;
alter policy hr_ec_read on public.hr_ec_benefits using(
 (select private.erp_mfa_ok()) and ((select private.hr_admin()) or private.hr_own(employee_id))
);
drop policy hr_ec_benefit_payments_own on public.hr_ec_benefit_payments;
drop policy hr_ec_benefit_payments_finance on public.hr_ec_benefit_payments;
alter policy hr_ec_read on public.hr_ec_benefit_payments using(
 (select private.erp_mfa_ok()) and (
  (select private.hr_admin())
  or exists(select 1 from public.hr_ec_benefits b where b.id=benefit_id and private.hr_own(b.employee_id))
  or (private.erp_module_allowed('accounting',array['administrador','comercial'])
   and private.gama_accounting_rights()->>'scope'='all'
   and coalesce((private.gama_accounting_rights()->>'view')::boolean,false))
 )
);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005053550','ec_release_access_and_indexes','799453c4e5313dd379e8788063bb8521a4d95b3b5ec5c0cc2bfb792f5f5ec85a','799453c4e5313dd379e8788063bb8521a4d95b3b5ec5c0cc2bfb792f5f5ec85a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005062552_ec_purchase_retention_completion.sql; SHA256 9e9ab25ee3e93f27e568801ffb3481c88f4b0f7b4e5bdead960afdc9508e0f00
-- Prepare a reviewed retention regardless of the order in which the invoice,
-- fiscal review and supplier policy become available. Never emit from a trigger.
create function private.gama_sri_try_purchase(p_invoice uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.sri_purchase_queue q
  join public.supplier_invoices v on v.id=q.supplier_invoice_id
  where q.supplier_invoice_id=p_invoice and q.issue_id is null and v.status='posted')
  or not exists(select 1 from public.company_settings c
   join public.accounting_ec_profile p on p.id=c.id
   where c.country='EC' and p.withholding_agent and p.confirmed_on is not null)
 then return;end if;
 begin
  perform private.gama_sri_purchase_document(p_invoice,'07','{}');
 exception when others then
  update public.sri_purchase_queue
  set last_error=case when sqlerrm ~ '^[A-Z0-9_]{1,100}$' then sqlerrm else 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED' end
  where supplier_invoice_id=p_invoice and issue_id is null;
 end;
end $$;
revoke all on function private.gama_sri_try_purchase(uuid) from public,anon,authenticated;

create or replace function private.gama_sri_purchase_queued() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='posted' and (tg_op='INSERT' or old.status is distinct from new.status)
  and exists(select 1 from public.company_settings c join public.accounting_ec_profile p on p.id=c.id
   where c.country='EC' and p.withholding_agent and p.confirmed_on is not null)
 then
  insert into public.sri_purchase_queue(supplier_invoice_id) values(new.id) on conflict do nothing;
  perform private.gama_sri_try_purchase(new.id);
 end if;
 return new;
end $$;
revoke all on function private.gama_sri_purchase_queued() from public,anon,authenticated;

create or replace function private.gama_sri_purchase_reviewed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.source_type='supplier_invoice' then perform private.gama_sri_try_purchase(new.source_id);end if;
 return new;
end $$;
revoke all on function private.gama_sri_purchase_reviewed() from public,anon,authenticated;

create function private.gama_sri_supplier_policy_reviewed() returns trigger
language plpgsql security definer set search_path='' as $$
declare invoice uuid;
begin
 -- Keep a policy save bounded; the existing preparation list handles a larger
 -- historical backlog. Every subsequent invoice/fiscal review is handled alone.
 for invoice in select q.supplier_invoice_id from public.sri_purchase_queue q
  join public.supplier_invoices v on v.id=q.supplier_invoice_id
  where v.supplier_id=new.supplier_id and v.status='posted' and q.issue_id is null
  order by q.created_at,q.supplier_invoice_id limit 50
 loop perform private.gama_sri_try_purchase(invoice);end loop;
 return new;
end $$;
revoke all on function private.gama_sri_supplier_policy_reviewed() from public,anon,authenticated;
create trigger sri_supplier_policy_reviewed after insert or update on public.supplier_withholding_policies
for each row execute function private.gama_sri_supplier_policy_reviewed();
create index sri_purchase_waiting on public.sri_purchase_queue(created_at,supplier_invoice_id) where issue_id is null;
notify pgrst, 'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005062552','ec_purchase_retention_completion','9e9ab25ee3e93f27e568801ffb3481c88f4b0f7b4e5bdead960afdc9508e0f00','9e9ab25ee3e93f27e568801ffb3481c88f4b0f7b4e5bdead960afdc9508e0f00','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005065015_ec_delivery_cost_per_customer.sql; SHA256 6faece06de70966cffbc9b44a6e7c529b8c73863faa7b481e3c8d45918c315c3
-- Read-only route-cost attribution. The rounded route amount is allocated in
-- cents so repeated customers and odd stop counts never create/lose money.
create function private.gama_tms_customer_costs(p_from date,p_to date,p_data jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; q text; lim integer; off integer;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>8192 then raise exception 'INVALID_REQUEST';end if;
 q:=btrim(coalesce(p_data->>'search',''));
 if length(q)>100 or coalesce(p_data->>'limit','30') !~ '^[0-9]{1,3}$' or coalesce(p_data->>'offset','0') !~ '^[0-9]{1,9}$' then raise exception 'INVALID_REQUEST';end if;
 lim:=greatest(1,least(100,coalesce(p_data->>'limit','30')::integer));
 off:=coalesce(p_data->>'offset','0')::integer;
 with routes as materialized (
  select r.id,coalesce(s.road_km,r.distance) km,s.road_km is null estimated,r.cost_per_km,
   round(coalesce(s.road_km,r.distance)*r.cost_per_km*100) cents,
   case when jsonb_typeof(r.stops)='array' then r.stops else '[]'::jsonb end stops
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id
  where r.route_date between p_from and p_to
 ), stops as materialized (
  select r.id,stop.id stop_id,r.km,r.estimated,r.cost_per_km,r.cents,
   count(*) over(partition by r.id) n,row_number() over(partition by r.id order by stop.id collate "C") pos
  from routes r cross join lateral (select distinct value id from jsonb_array_elements_text(r.stops) where value<>'__depot') stop
 ), allocated as (
  select x.id route_id,c.id customer_id,case when c.id is null then 'Cliente no identificado' else c.name end customer,
   x.km/x.n km,x.estimated,x.cost_per_km is null missing_cost,c.id is null unknown_customer,
   case when x.cents is null then null else floor(x.cents/x.n)+case when x.pos<=mod(x.cents,x.n) then 1 else 0 end end cents
  from stops x left join public.tms_deliveries d on d.id=case when x.stop_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then x.stop_id::uuid end
  left join public.customers c on c.id=d.customer_id
 ), grouped as materialized (
  select customer_id,customer,count(*) deliveries,count(distinct route_id) routes,sum(km) km,sum(cents)/100 cost,
   count(*) filter(where missing_cost) missing_cost,count(*) filter(where estimated) estimated_stops,count(*) filter(where unknown_customer) unknown_stops
  from allocated group by customer_id,customer
 ), matching as materialized (
  select * from grouped where q='' or position(lower(q) in lower(customer))>0
 ), page as (
  select * from matching order by customer collate "C",customer_id nulls last limit lim offset off
 )
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.customer collate "C",p.customer_id nulls last) from page p),'[]'::jsonb),
  'total',(select count(*) from matching),'offset',off,'limit',lim,
  'unassigned_routes',(select count(*) from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_cost',(select sum(r.cents)/100 from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_missing_cost',(select count(*) from routes r where r.cost_per_km is null and not exists(select 1 from stops x where x.id=r.id))) into result;
 return result;
end $$;
revoke all on function private.gama_tms_customer_costs(date,date,jsonb) from public,anon;
grant execute on function private.gama_tms_customer_costs(date,date,jsonb) to authenticated;
create function public.gama_tms_customer_costs(p_from date,p_to date,p_data jsonb default '{}') returns jsonb
language sql stable security invoker set search_path='' as $$select private.gama_tms_customer_costs(p_from,p_to,p_data)$$;
revoke all on function public.gama_tms_customer_costs(date,date,jsonb) from public,anon;
grant execute on function public.gama_tms_customer_costs(date,date,jsonb) to authenticated;

-- The period scan reuses tms_routes_date_idx; schedule and delivery lookups use
-- their existing unique/primary-key indexes.
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005065015','ec_delivery_cost_per_customer','6faece06de70966cffbc9b44a6e7c529b8c73863faa7b481e3c8d45918c315c3','6faece06de70966cffbc9b44a6e7c529b8c73863faa7b481e3c8d45918c315c3','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005145609_automation_jobs_and_rules.sql; SHA256 c37d6248aaff2b904c4c61bced53a59f9c65fd3bffad0ff9dc00c8857a3a8cae
-- Durable, bounded background work. Public callers never choose an executor,
-- a SQL statement or an RPC to execute. Business transactions remain canonical.
create table private.automation_catalog(
 kind text primary key,module text not null,title text not null,
 interval_minutes integer not null check(interval_minutes between 1 and 10080),
 delegated boolean not null default true
);
insert into private.automation_catalog(kind,module,title,interval_minutes,delegated) values
 ('operating_checks','notifications','Controles y excepciones',10,false),
 ('finance_checks','accounting','Controles financieros diarios',1440,false),
 ('replenishment','gamaPurchasesV14','Borradores de reposición',1440,true),
 ('cycle_counts','warehouses','Inventarios cíclicos',1440,true),
 ('tms_planning','tms','Planificación diaria de entregas',15,true),
 ('crm_followup','crm','Próxima actividad comercial',60,true),
 ('request_quote','quotes','Solicitud a presupuesto',60,true),
 ('accepted_order','sales-orders','Presupuesto aceptado a pedido',60,true),
 ('receipt_bill','accounting','Recepción a factura borrador',60,true),
 ('fleet_expense','accounting','Flota a gasto borrador',60,true),
 ('project_hours','projects','Horas aprobadas a coste de proyecto',60,true),
 ('service_followup','sav','Seguimiento SAV',60,true),
 ('survey_followup','surveys','Encuesta después del servicio',60,true),
 ('reminders','payments','Recordatorios pendientes',1440,true),
 ('sri_consult','sri','Consulta fiscal pendiente',15,true);
create table private.automation_rules(
 kind text not null references private.automation_catalog(kind),version integer not null,
 enabled boolean not null,config jsonb not null default '{}' check(jsonb_typeof(config)='object'),
 executor uuid references public.profiles(id),approved_until timestamptz,
 approved_by uuid references public.profiles(id),created_at timestamptz not null default now(),
 primary key(kind,version),check(version>0),check(octet_length(config::text)<=16000)
);
insert into private.automation_rules(kind,version,enabled,config)
 select kind,1,not delegated,jsonb_build_object('interval_minutes',interval_minutes) from private.automation_catalog;
create table private.automation_jobs(
 id uuid primary key default gen_random_uuid(),kind text not null,rule_version integer not null,
 dedupe_key text not null unique check(length(dedupe_key) between 1 and 300),
 source_type text,source_id uuid,actor uuid references public.profiles(id),
 payload jsonb not null default '{}' check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=64000),
 state text not null default 'queued' check(state in ('queued','running','retry','blocked','succeeded','cancelled','dead')),
 attempts integer not null default 0,failures integer not null default 0,max_attempts integer not null default 5 check(max_attempts between 1 and 10),
 available_at timestamptz not null default now(),lease_until timestamptz,lease_token uuid,
 result jsonb,error_code text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(kind,rule_version) references private.automation_rules(kind,version)
);
create index automation_jobs_ready on private.automation_jobs(available_at,created_at,id) where state in ('queued','retry');
create index automation_jobs_source on private.automation_jobs(source_type,source_id);
create index automation_jobs_failures on private.automation_jobs(updated_at desc,id) where state in ('blocked','dead');
create index automation_jobs_lease on private.automation_jobs(lease_until) where state='running';
create table private.automation_attempts(
 id bigint generated always as identity primary key,job_id uuid not null references private.automation_jobs(id),
 attempt integer not null,started_at timestamptz not null default now(),finished_at timestamptz,
 outcome text,error_code text,milliseconds integer,unique(job_id,attempt)
);
create table private.automation_exceptions(
 key text primary key,kind text not null,module text not null,source_type text,source_id uuid,
 reference text not null default '',reason text not null,active boolean not null default true,
 assigned_to uuid references public.profiles(id),next_action text not null default '',due_at timestamptz,
 job_id uuid references private.automation_jobs(id),opened_at timestamptz not null default now(),updated_at timestamptz not null default now(),resolved_at timestamptz,
 check(length(reason)<=1000 and length(next_action)<=1000)
);
create index automation_exceptions_active on private.automation_exceptions(module,updated_at desc,key) where active;
create index automation_exceptions_assignee on private.automation_exceptions(assigned_to) where active;
create table private.automation_execution_context(
 backend integer not null,transaction bigint not null,job_id uuid not null references private.automation_jobs(id),
 actor uuid not null references public.profiles(id),primary key(backend,transaction)
);
do $$declare t text;begin foreach t in array array['automation_catalog','automation_rules','automation_jobs','automation_attempts','automation_exceptions','automation_execution_context'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

-- Delegation is explicit, limited to an immutable rule and expires. This closed
-- transaction context is inserted only by the scheduler; a forged JWT/GUC cannot
-- grant it. Fresh profile/module/action checks still run inside existing RPCs.
create function private.automation_delegation_ok() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.automation_execution_context x
 join private.automation_jobs j on j.id=x.job_id
 join private.automation_rules r on r.kind=j.kind and r.version=j.rule_version
 join public.profiles p on p.id=x.actor join auth.users u on u.id=p.id
 where x.backend=pg_backend_pid() and x.transaction=txid_current() and x.actor=auth.uid()
 and j.state='running' and r.enabled and r.executor=x.actor and r.approved_until>now()
 and p.active and p.deleted_at is null and p.role='administrador'
 and not exists(select 1 from private.automation_rules newer where newer.kind=r.kind and newer.version>r.version))
$$;
create or replace function private.erp_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select (auth.uid() is not null and exists(select 1 from auth.users where id=auth.uid())
  and (coalesce(auth.jwt()->>'aal'='aal2',false) or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified')))
  or private.automation_delegation_ok()
$$;
revoke all on function private.erp_mfa_ok() from public,anon;
grant execute on function private.erp_mfa_ok() to authenticated;

create function private.automation_visible(p_module text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and
 private.erp_module_allowed(p_module,array['administrador','comercial','almacenero']) and
 (p_module<>'accounting' or (coalesce((private.gama_accounting_rights()->>'view')::boolean,false) and private.gama_accounting_rights()->>'scope'='all'))
$$;
create function private.automation_exception(p_key text,p_kind text,p_module text,p_source_type text,p_source_id uuid,p_reason text,p_job uuid default null,p_reference text default '') returns void
 language plpgsql security definer set search_path='' as $$begin
 insert into private.automation_exceptions(key,kind,module,source_type,source_id,reason,job_id,reference)
 values(p_key,p_kind,p_module,p_source_type,p_source_id,left(p_reason,1000),p_job,left(coalesce(p_reference,''),150))
 on conflict(key) do update set reason=excluded.reason,job_id=coalesce(excluded.job_id,automation_exceptions.job_id),active=true,resolved_at=null,updated_at=now();
end $$;
create function private.automation_enqueue(p_kind text,p_key text,p_payload jsonb default '{}',p_source_type text default null,p_source_id uuid default null) returns uuid
 language plpgsql security definer set search_path='' as $$declare rule private.automation_rules;job uuid;prior private.automation_jobs;begin
 select * into rule from private.automation_rules where kind=p_kind order by version desc limit 1;
 if not found or not rule.enabled then return null;end if;
 insert into private.automation_jobs(kind,rule_version,dedupe_key,payload,source_type,source_id,actor)
 values(p_kind,rule.version,p_key,p_payload,p_source_type,p_source_id,rule.executor)
 on conflict(dedupe_key) do nothing returning id into job;
 if job is null then select * into prior from private.automation_jobs where dedupe_key=p_key;
  if prior.kind<>p_kind or prior.payload is distinct from p_payload or prior.source_type is distinct from p_source_type or prior.source_id is distinct from p_source_id then raise exception 'REQUEST_KEY_REUSED';end if;
  job:=prior.id;
 end if;
 return job;
end $$;

-- Handlers are extended in subsequent migrations; never dynamic SQL or a caller-
-- supplied method. Checks record exceptions only and do not post journal entries.
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare v_alert record;counted integer:=0;begin
 if p_job.kind='operating_checks' then
  update private.automation_exceptions e set active=false,resolved_at=now(),updated_at=now()
   where e.kind='operating_check' and e.active and not exists(select 1 from private.gama_live_alerts a where a.alert_key=e.key);
  for v_alert in select * from private.gama_live_alerts order by priority desc,alert_key limit 2000 loop
   perform private.automation_exception(v_alert.alert_key,'operating_check',case when v_alert.finance_only then 'accounting' when v_alert.warehouse_only then 'warehouses' else 'notifications' end,v_alert.target,v_alert.target_id,v_alert.title||': '||coalesce(v_alert.detail,''),null,v_alert.reference);
   counted:=counted+1;
  end loop;
  return jsonb_build_object('checked',counted,'as_of',now());
 end if;
 return jsonb_build_object('blocked',true,'reason','HANDLER_NOT_CONFIGURED');
end $$;

create function private.automation_run(p_limit integer default 12) returns jsonb language plpgsql security definer set search_path='' as $$
 declare j private.automation_jobs;r private.automation_rules;c private.automation_catalog;answer jsonb;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);
 started timestamptz;failure text;handled integer:=0;
 begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-automation-runner',0)) then return jsonb_build_object('busy',true);end if;
 update private.automation_jobs set state=case when failures+1>=max_attempts then 'dead' else 'retry' end,failures=failures+1,
  error_code='LEASE_EXPIRED',lease_until=null,lease_token=null,available_at=now(),updated_at=now() where state='running' and lease_until<now();
 for j in select * from private.automation_jobs where state in ('queued','retry') and available_at<=now()
  order by available_at,created_at,id limit greatest(1,least(p_limit,30)) for update skip locked loop
  started:=clock_timestamp();failure:=null;answer:=null;
  select * into r from private.automation_rules where kind=j.kind order by version desc limit 1;
  select * into c from private.automation_catalog where kind=j.kind;
  if not r.enabled or r.version<>j.rule_version then
   update private.automation_jobs set state='cancelled',error_code='RULE_CHANGED',updated_at=now() where id=j.id;continue;
  end if;
  if c.delegated and (r.executor is null or r.approved_until<=now() or not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=r.executor and p.active and p.deleted_at is null and p.role='administrador')) then
   update private.automation_jobs set state='blocked',error_code='DELEGATION_REQUIRED',updated_at=now() where id=j.id;
   perform private.automation_exception('job:'||j.id,j.kind,c.module,j.source_type,j.source_id,'DELEGATION_REQUIRED',j.id);continue;
  end if;
  update private.automation_jobs set state='running',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes',updated_at=now() where id=j.id returning * into j;
  insert into private.automation_attempts(job_id,attempt) values(j.id,j.attempts);
  begin
   if c.delegated then
    perform set_config('request.jwt.claim.sub',r.executor::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',r.executor,'role','authenticated')::text,true);
    insert into private.automation_execution_context(backend,transaction,job_id,actor) values(pg_backend_pid(),txid_current(),j.id,r.executor);
    if not private.automation_visible(c.module) then raise exception 'DELEGATION_ACCESS_REVOKED';end if;
   end if;
   answer:=private.automation_dispatch(j,r.config);
   delete from private.automation_execution_context where backend=pg_backend_pid() and transaction=txid_current();
  exception when others then
   -- The subtransaction rolls back every partial business write, including its
   -- receipt. Store a bounded error code; do not persist SQL/PII/credentials.
   failure:=case when sqlerrm ~ '^[A-Z][A-Z0-9_: -]{0,150}$' then sqlerrm else sqlstate end;
  end;
  perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);
  perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
  update private.automation_jobs set
   state=case when failure is not null then case when failures+1>=max_attempts then 'dead' else 'retry' end when coalesce((answer->>'blocked')::boolean,false) then 'blocked' else 'succeeded' end,
   failures=failures+case when failure is not null then 1 else 0 end,
   result=answer,error_code=coalesce(failure,answer->>'reason'),lease_until=null,lease_token=null,
   available_at=now()+make_interval(secs=>least(3600,30*power(2,least(failures+1,7))::integer)),updated_at=now()
   where id=j.id returning * into j;
  update private.automation_attempts set finished_at=now(),outcome=j.state,error_code=j.error_code,
   milliseconds=least(2147483647,extract(epoch from clock_timestamp()-started)*1000)::integer where job_id=j.id and attempt=j.attempts;
  if j.state in ('blocked','dead') then perform private.automation_exception('job:'||j.id,j.kind,c.module,j.source_type,j.source_id,coalesce(j.error_code,'REVIEW_REQUIRED'),j.id);
  elsif j.state='succeeded' then update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='job:'||j.id;end if;
  handled:=handled+1;
 end loop;
 return jsonb_build_object('handled',handled,'as_of',now());
 end $$;
create function private.automation_tick() returns jsonb language plpgsql security definer set search_path='' as $$declare r record;slot bigint;begin
 for r in select distinct on (rule_row.kind) rule_row.*,catalog_row.interval_minutes from private.automation_rules rule_row join private.automation_catalog catalog_row using(kind) order by rule_row.kind,rule_row.version desc loop
  if r.enabled then
   slot:=floor(extract(epoch from now())/(60*greatest(1,least(coalesce((r.config->>'interval_minutes')::integer,r.interval_minutes),10080))))::bigint;
   perform private.automation_enqueue(r.kind,'schedule:'||r.kind||':'||r.version||':'||slot);
  end if;
 end loop;
 return private.automation_run(12);
end $$;

create function private.gama_automation(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare admin boolean:=private.erp_module_allowed('access-settings',array['administrador']);r private.automation_rules;c private.automation_catalog;
 j private.automation_jobs;e private.automation_exceptions;off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 rows jsonb;rules jsonb;exceptions jsonb;key uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not admin and not private.erp_module_allowed('notifications',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='rule_save' then
  if not admin or not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into c from private.automation_catalog where kind=p_data->>'kind';if not found then raise exception 'RULE_NOT_FOUND';end if;
  perform pg_advisory_xact_lock(hashtextextended('automation-rule:'||c.kind,0));
  select * into r from private.automation_rules where kind=c.kind order by version desc limit 1;
  if r.version is distinct from (p_data->>'expected_version')::integer then raise exception 'RULE_CHANGED';end if;
  if jsonb_typeof(p_data->'config') is distinct from 'object' then raise exception 'INVALID_CONFIG';end if;
  if coalesce((p_data->'config'->>'interval_minutes')::integer,c.interval_minutes) not between 1 and 10080 then raise exception 'INVALID_INTERVAL';end if;
  if coalesce((p_data->>'enabled')::boolean,false) and not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into private.automation_rules(kind,version,enabled,config,executor,approved_until,approved_by)
   values(c.kind,r.version+1,coalesce((p_data->>'enabled')::boolean,false),p_data->'config',case when c.delegated then auth.uid() end,
    case when c.delegated then now()+make_interval(days=>greatest(1,least(coalesce((p_data->>'delegation_days')::integer,90),90))) end,auth.uid()) returning * into r;
  return to_jsonb(r);
 elsif p_action='run_once' then
  if not admin then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  key:=private.automation_enqueue(p_data->>'kind','manual:'||key::text,coalesce(p_data->'payload','{}'));
  if key is null then raise exception 'RULE_DISABLED';end if;
  return jsonb_build_object('id',key,'state','queued');
 elsif p_action in ('retry','cancel') then
  select * into j from private.automation_jobs where id=(p_data->>'id')::uuid for update;
  select * into c from private.automation_catalog where kind=j.kind;
  if not found or not admin or not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if j.state not in ('blocked','dead','retry','queued') then raise exception 'JOB_NOT_RETRYABLE';end if;
  select * into r from private.automation_rules where kind=j.kind order by version desc limit 1;
  if p_action='retry' and not r.enabled then raise exception 'RULE_DISABLED';end if;
  update private.automation_jobs set state=case when p_action='retry' then 'queued' else 'cancelled' end,rule_version=r.version,actor=r.executor,
   failures=case when p_action='retry' then 0 else failures end,available_at=now(),updated_at=now(),error_code=null where id=j.id;
  if p_action='cancel' then update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where job_id=j.id;end if;
  return jsonb_build_object('id',j.id,'state',case when p_action='retry' then 'queued' else 'cancelled' end);
 elsif p_action='assign' then
  select * into e from private.automation_exceptions where key=p_data->>'key' for update;
  if not found or not private.automation_visible(e.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=coalesce(nullif(p_data->>'assigned_to','')::uuid,auth.uid());
  if not exists(select 1 from public.profiles p where p.id=key and p.active and (p.id=auth.uid() or admin)) then raise exception 'ASSIGNEE_INVALID';end if;
  if length(btrim(coalesce(p_data->>'next_action','')))<3 then raise exception 'NEXT_ACTION_REQUIRED';end if;
  update private.automation_exceptions set assigned_to=key,next_action=p_data->>'next_action',due_at=nullif(p_data->>'due_at','')::timestamptz,updated_at=now() where automation_exceptions.key=e.key;
  return jsonb_build_object('key',e.key);
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from(select job_row.id,job_row.kind,catalog_row.title,catalog_row.module,job_row.source_type,job_row.source_id,job_row.state,job_row.attempts,job_row.created_at,job_row.updated_at,job_row.available_at,job_row.result,job_row.error_code,
  (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc),'[]') from private.automation_attempts a where a.job_id=job_row.id) attempts_log
  from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module)
  and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state') order by job_row.created_at desc,job_row.id limit 50 offset off)x;
 if admin then select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rules from(select distinct on(rule_row.kind) rule_row.*,catalog_row.module,catalog_row.title,catalog_row.delegated from private.automation_rules rule_row join private.automation_catalog catalog_row using(kind) order by rule_row.kind,rule_row.version desc)x;else rules:='[]';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into exceptions from(select exception_row.*,p.full_name assigned_name from private.automation_exceptions exception_row left join public.profiles p on p.id=exception_row.assigned_to
  where exception_row.active and private.automation_visible(exception_row.module) order by exception_row.opened_at,exception_row.key limit 100)x;
 return jsonb_build_object('as_of',now(),'admin',admin,'rules',rules,'jobs',rows,'exceptions',exceptions,'offset',off,
  'total',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state')),
  'pending',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and job_row.state in ('queued','retry','blocked','dead')));
end $$;
create function public.gama_automation(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_automation(p_action,p_data)$$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'automation_%' or p.proname='gama_automation') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
grant execute on function private.gama_automation(text,jsonb) to authenticated;
revoke all on function public.gama_automation(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_automation(text,jsonb) to authenticated;
select cron.schedule('coco-automation','* * * * *',$cron$select private.automation_tick();$cron$);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005145609','automation_jobs_and_rules','c37d6248aaff2b904c4c61bced53a59f9c65fd3bffad0ff9dc00c8857a3a8cae','c37d6248aaff2b904c4c61bced53a59f9c65fd3bffad0ff9dc00c8857a3a8cae','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005150601_automation_business_flows.sql; SHA256 c77d99407fa75bc00ca373902ae6cfa4a6fbdcd86f5694be9ad2ee59d1e76bee
-- Source-to-target links supplement existing receipts; they do not replace any
-- stock/payment/accounting transaction, nor fill in customer/supplier/products.
create table private.automation_links(
 source_type text not null,source_id uuid not null,target_type text not null,target_id uuid not null,
 fingerprint text,created_at timestamptz not null default now(),primary key(source_type,source_id,target_type)
);
alter table private.automation_links enable row level security;
revoke all on private.automation_links from public,anon,authenticated,service_role;
create index automation_links_target on private.automation_links(target_type,target_id);
create function private.automation_key(p_key text) returns uuid language sql immutable set search_path='' as $$select md5('coco-automation:'||p_key)::uuid$$;
create table private.tms_plan_versions(
 id bigint generated always as identity primary key,day date not null,fingerprint text not null,output_hash text not null,
 summary jsonb not null,planned_at timestamptz not null,unique(day,output_hash)
);
alter table private.tms_plan_versions enable row level security;revoke all on private.tms_plan_versions from public,anon,authenticated,service_role;
create function private.tms_plan_version_capture() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into private.tms_plan_versions(day,fingerprint,output_hash,summary,planned_at) values(new.day,new.fingerprint,new.output_hash,new.summary,new.planned_at) on conflict(day,output_hash) do nothing;return new;
end $$;
create trigger tms_plan_version_capture after insert or update on private.tms_day_plans for each row execute function private.tms_plan_version_capture();

alter table public.crm_activities add column automation_key text;
create unique index crm_activities_automation on public.crm_activities(automation_key) where automation_key is not null;
create index crm_activities_pending_opportunity on public.crm_activities(opportunity_id,due_at) where status in ('pendiente','en_curso');
create index crm_activities_pending_invoice on public.crm_activities(invoice_id,due_at) where status in ('pendiente','en_curso');
create index customer_requests_pending_flow on public.customer_requests(created_at,id) where invoice_id is null and status in ('pending','accepted');

-- Missing source fields create an exception. A background job cannot mark a
-- legally unknown tax treatment as reviewed, or pay/post a provisional draft.
alter table public.expenses add column source_reviewed boolean not null default true;
alter table public.supplier_invoices add column source_reviewed boolean not null default true;
create function private.automation_finance_draft_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='posted' and not new.source_reviewed then raise exception 'SOURCE_REVIEW_REQUIRED';end if;
 return new;
end $$;
create trigger automation_finance_draft_guard before insert or update on public.expenses for each row execute function private.automation_finance_draft_guard();
create trigger automation_finance_draft_guard before insert or update on public.supplier_invoices for each row execute function private.automation_finance_draft_guard();
create function private.automation_supplier_payment_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and not exists(select 1 from public.supplier_invoices b where b.id=new.supplier_invoice_id and b.status='posted' and b.source_reviewed) then raise exception 'POSTED_SUPPLIER_INVOICE_REQUIRED';end if;return new;
end $$;
create trigger automation_supplier_payment_guard before insert or update on public.supplier_invoice_payments for each row execute function private.automation_supplier_payment_guard();

create function private.automation_finance_checks() returns jsonb language plpgsql security definer set search_path='' as $$
 declare item record;checked integer:=0;begin
 for item in select e.id,e.number from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id
  where e.status='posted' group by e.id having abs(sum(l.debit-l.credit))>.005 loop
  perform private.automation_exception('ledger-balance:'||item.id,'finance_check','accounting','entry',item.id,'LEDGER_UNBALANCED',null,item.number);checked:=checked+1;
 end loop;
 update private.automation_exceptions x set active=false,resolved_at=now(),updated_at=now() where x.kind='finance_check' and x.key like 'ledger-balance:%' and x.active
  and not exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where e.id=x.source_id and e.status='posted' group by e.id having abs(sum(l.debit-l.credit))>.005);
 for item in select i.id,i.number from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
  and not exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status='posted') loop
  perform private.automation_exception('invoice-ledger:'||item.id,'finance_check','accounting','invoice',item.id,'SOURCE_NOT_POSTED',null,item.number);checked:=checked+1;
 end loop;
 update private.automation_exceptions x set active=false,resolved_at=now(),updated_at=now() where x.kind='finance_check' and x.key like 'invoice-ledger:%' and x.active
  and (exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=x.source_id and e.status='posted') or not exists(select 1 from public.external_invoices i where i.id=x.source_id and i.fiscal_status not in ('cancelled','rejected')));
 for item in select q.product_id from public.stock_quants q where q.quantity<0 or q.reserved_quantity<0 or q.reserved_quantity>q.quantity group by q.product_id loop
  perform private.automation_exception('stock-quant:'||item.product_id,'finance_check','warehouses','product',item.product_id,'STOCK_QUANT_INVALID');checked:=checked+1;
 end loop;
 update private.automation_exceptions x set active=false,resolved_at=now(),updated_at=now() where x.kind='finance_check' and x.key like 'stock-quant:%' and x.active
  and not exists(select 1 from public.stock_quants q where q.product_id=x.source_id and (q.quantity<0 or q.reserved_quantity<0 or q.reserved_quantity>q.quantity));
 return jsonb_build_object('exceptions_checked',checked,'as_of',now());
end $$;

create function private.automation_replenish(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare row record;item jsonb;items jsonb:='[]';result jsonb;grouped record;cap numeric:=coalesce((p_config->>'max_order_total')::numeric,1000);begin
 if cap<=0 or cap>1000000 then return jsonb_build_object('blocked',true,'reason','PURCHASE_LIMIT_REQUIRED');end if;
 if not private.erp_action_allowed('gamaPurchasesV14','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 for row in select x.product_id,x.data from private.stock_insight_rows(true) x where (x.data->>'suggested_quantity')::numeric>0 order by x.product_id limit 3000 loop
  item:=row.data;
  if nullif(item->>'supplier_id','') is null or coalesce((item->>'unit_cost')::numeric,0)<=0 or not coalesce((item->>'lead_configured')::boolean,false) then
   perform private.automation_exception('replenish:'||row.product_id,'replenishment','gamaPurchasesV14','product',row.product_id,'SUPPLIER_COST_OR_LEAD_TIME_REQUIRED',p_job.id,item->>'reference');
  else items:=items||jsonb_build_array(jsonb_build_object('product_id',row.product_id,'supplier_id',item->>'supplier_id','quantity',(item->>'suggested_quantity')::numeric,'unit_cost',(item->>'unit_cost')::numeric));
   update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='replenish:'||row.product_id;
  end if;
 end loop;
 for grouped in select x->>'supplier_id' supplier,sum((x->>'quantity')::numeric*(x->>'unit_cost')::numeric*(1+p.tax_rate/100)) total,count(*) lines
  from jsonb_array_elements(items) x join public.products p on p.id=(x->>'product_id')::uuid group by x->>'supplier_id' loop
  if grouped.total>cap or grouped.lines>500 then
   perform private.automation_exception('replenish-limit:'||grouped.supplier,'replenishment','gamaPurchasesV14','supplier',grouped.supplier::uuid,'PURCHASE_LIMIT_EXCEEDED',p_job.id);
   select coalesce(jsonb_agg(x),'[]') into items from jsonb_array_elements(items) x where x->>'supplier_id'<>grouped.supplier;
  end if;
 end loop;
 if jsonb_array_length(items)=0 then return jsonb_build_object('orders','[]'::jsonb,'products',0,'as_of',now());end if;
 select jsonb_agg(x-'unit_cost') into items from jsonb_array_elements(items) x;
 result:=private.gama_stock_replenish(jsonb_build_object('request_key',p_job.id,'destination_location_id',p_config->>'destination_location_id','items',items));
 return result;
end $$;

create function private.automation_counts(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare row record;parent public.inventory_counts;created jsonb:='[]';r jsonb;w uuid:=nullif(p_config->>'warehouse_id','')::uuid;days integer;today date:=(now() at time zone private.erp_timezone())::date;begin
 if not private.erp_action_allowed('warehouses','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if w is null or not exists(select 1 from public.warehouses where id=w and active) then return jsonb_build_object('blocked',true,'reason','WAREHOUSE_REQUIRED');end if;
 for parent in select * from public.inventory_counts c where c.warehouse_id=w and c.status='validated' and c.next_due<=today
  and not exists(select 1 from public.inventory_counts n where n.repeat_of=c.id and n.status<>'cancelled') order by next_due,id limit 5 loop
  r:=private.gama_count_create_core(jsonb_build_object('request_key',private.automation_key('repeat-count:'||parent.id),'warehouse_id',w,'repeat_of',parent.id,'assigned_to',parent.assigned_to,'due_date',today,'blind',true,'cycle_days',parent.cycle_days,'product_id',parent.scope_product_id,'location_id',parent.scope_location_id,'category',parent.scope_category,'priority',parent.priority,'reference','Ciclo · '||parent.reference));created:=created||jsonb_build_array(r->'id');
 end loop;
 for row in select x.product_id,x.data from private.stock_insight_rows(false) x
  where (x.data->>'on_hand')::numeric>0 and exists(select 1 from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id where q.product_id=x.product_id and q.quantity>0 and l.warehouse_id=w and l.active)
  and not exists(select 1 from public.inventory_counts c where c.warehouse_id=w and c.status in ('draft','in_progress') and (c.scope_product_id=x.product_id or c.scope_product_id is null))
  and not exists(select 1 from public.inventory_count_lines l join public.inventory_counts c on c.id=l.count_id where l.product_id=x.product_id and c.warehouse_id=w and c.status='validated' and c.completed_at>now()-make_interval(days=>case x.data->>'importance' when 'A' then 30 when 'B' then 90 else 180 end))
  order by case x.data->>'importance' when 'A' then 0 when 'B' then 1 else 2 end,x.product_id limit 5 loop
  days:=case row.data->>'importance' when 'A' then 30 when 'B' then 90 else 180 end;
  r:=private.gama_count_create_core(jsonb_build_object('request_key',private.automation_key('abc-count:'||w||':'||row.product_id||':'||today),'warehouse_id',w,'due_date',today+7,'blind',true,'cycle_days',days,'product_id',row.product_id,'priority',case when row.data->>'importance'='A' then 'high' else 'normal' end,'reference','ABC '||(row.data->>'importance')||' · '||(row.data->>'reference')));created:=created||jsonb_build_array(r->'id');
 end loop;
 return jsonb_build_object('counts',created);
end $$;

create function private.automation_crm(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
 declare o public.crm_opportunities;key text;created integer:=0;owner uuid;begin
 if not private.erp_action_allowed('crm','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 for o in select * from public.crm_opportunities o where o.active and o.won_at is null and o.lost_at is null
  and not exists(select 1 from public.crm_activities a where a.opportunity_id=o.id and a.status in ('pendiente','en_curso')) order by o.updated_at,o.id limit 100 loop
  owner:=o.owner_id;if owner is null or not exists(select 1 from public.profiles where id=owner and active and role in ('administrador','comercial')) then
   perform private.automation_exception('crm-owner:'||o.id,'crm_followup','crm','opportunity',o.id,'OWNER_REQUIRED',p_job.id,o.reference);continue;
  end if;
  key:='opportunity:'||o.id||':'||coalesce((select max(a.done_at)::text from public.crm_activities a where a.opportunity_id=o.id),o.created_at::text);
  insert into public.crm_activities(kind,subject,status,owner_id,due_at,customer_id,lead_id,opportunity_id,created_by,automation_key)
   values('seguimiento','Seguimiento · '||o.reference,'pendiente',owner,now()+make_interval(days=>greatest(1,least(coalesce((p_config->>'followup_days')::integer,3),90))),o.customer_id,o.lead_id,o.id,auth.uid(),key) on conflict(automation_key) where automation_key is not null do nothing;
  if found then created:=created+1;end if;
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='crm-owner:'||o.id;
 end loop;
 return jsonb_build_object('activities',created);
end $$;

create function private.automation_request_quote(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare req public.customer_requests;c public.customers;p public.products;l public.customer_request_lines;resolved jsonb;lines jsonb:='[]';total numeric:=0;cap numeric:=coalesce((p_config->>'max_quote_total')::numeric,1000);details jsonb;begin
 if not private.erp_action_allowed('quotes','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for req in select * from public.customer_requests where invoice_id is null and status in ('pending','accepted') order by created_at,id limit 100 loop
   perform private.automation_enqueue('request_quote','request-quote:'||req.id,jsonb_build_object('request_id',req.id),'request',req.id);
  end loop;
  return jsonb_build_object('scanned',true);
 end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into req from public.customer_requests where id=p_job.source_id for update;
 if not found or req.status in ('cancelled','rejected') then return jsonb_build_object('skipped','REQUEST_CLOSED');end if;
 if req.invoice_id is not null then return jsonb_build_object('id',req.invoice_id,'existing',true);end if;
 select * into c from public.customers where id=req.customer_id and active;
 if not found or nullif(btrim(c.identification),'') is null or nullif(btrim(coalesce(req.delivery_address_snapshot,c.address)),'') is null then return jsonb_build_object('blocked',true,'reason','CUSTOMER_OR_DELIVERY_DETAILS_REQUIRED');end if;
 for l in select * from public.customer_request_lines where request_id=req.id order by product_id loop
  select * into p from public.products where id=l.product_id and active;
  if not found or p.purchase_price<=0 then return jsonb_build_object('blocked',true,'reason','PRODUCT_COST_REQUIRED');end if;
  resolved:=private.erp_price(c.id,p.id,l.quantity,current_date);
  if (resolved->>'unit_price')::numeric<=0 then return jsonb_build_object('blocked',true,'reason','PRICE_REQUIRED');end if;
  total:=total+round(l.quantity*(resolved->>'unit_price')::numeric,2)+round(round(l.quantity*(resolved->>'unit_price')::numeric,2)*p.tax_rate/100,2);
  lines:=lines||jsonb_build_array(jsonb_build_object('product_id',p.id,'quantity',l.quantity,'list_price',(resolved->>'unit_price')::numeric,'discount',0,'tax_rate',p.tax_rate,'description',p.name));
 end loop;
 if jsonb_array_length(lines)=0 or jsonb_array_length(lines)>200 then return jsonb_build_object('blocked',true,'reason','INVALID_LINES');end if;
 if cap<=0 or total>cap then return jsonb_build_object('blocked',true,'reason','QUOTE_LIMIT_EXCEEDED');end if;
 details:=jsonb_build_object('client',c.name,'clientId',c.identification,'seller',(select full_name from public.profiles where id=auth.uid()),'delivery_address',coalesce(req.delivery_address_snapshot,c.address),'notes',req.notes);
 return private.gama_quote_from_request(req.id,jsonb_build_object('customer_id',c.id,'issue_date',current_date,'valid_until',current_date+30,'details',details,'lines',lines));
end $$;

create function private.automation_business_event() returns trigger language plpgsql security definer set search_path='' as $$declare source uuid;begin
 if tg_table_name='customer_requests' then
  if new.invoice_id is null and new.status in ('pending','accepted') then perform private.automation_enqueue('request_quote','request-quote:'||new.id,jsonb_build_object('request_id',new.id),'request',new.id);end if;
 elsif tg_table_name='purchase_order_lines' then
  if new.received_quantity>0 and (tg_op='INSERT' or new.received_quantity is distinct from old.received_quantity) then
   source:=new.purchase_order_id;perform private.automation_enqueue('receipt_bill','receipt-bill:'||source||':'||txid_current(),jsonb_build_object('purchase_order_id',source),'purchase',source);
  end if;
 elsif tg_table_name in ('fleet_fuel_logs','fleet_maintenance') then
  perform private.automation_enqueue('fleet_expense','fleet-expense:'||tg_table_name||':'||new.id||':'||md5(to_jsonb(new)::text),jsonb_build_object('table',tg_table_name),tg_table_name,new.id);
 elsif tg_table_name='tms_deliveries' then
  perform private.automation_enqueue('tms_planning','tms-plan:'||new.delivery_date||':'||txid_current(),jsonb_build_object('day',new.delivery_date),'delivery',new.id);
 end if;
 return new;
end $$;
create trigger automation_business_event after insert or update on public.customer_requests for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update of received_quantity on public.purchase_order_lines for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update on public.fleet_fuel_logs for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update on public.fleet_maintenance for each row execute function private.automation_business_event();
create trigger automation_business_event after insert or update of delivery_date,address,priority on public.tms_deliveries for each row execute function private.automation_business_event();

alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_checks;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;day date;begin
 case p_job.kind
 when 'finance_checks' then return private.automation_finance_checks();
 when 'replenishment' then return private.automation_replenish(p_job,p_config);
 when 'cycle_counts' then return private.automation_counts(p_job,p_config);
 when 'tms_planning' then
  day:=coalesce(nullif(p_job.payload->>'day','')::date,(now() at time zone private.erp_timezone())::date);
  if day<(now() at time zone private.erp_timezone())::date then return jsonb_build_object('skipped','PLANNING_DATE_PAST');end if;
  result:=private.gama_tms_plan_day(day);
  if (result->>'without_coordinates')::integer>0 then perform private.automation_exception('tms-gps:'||day,'tms_planning','tms',null,null,'DELIVERY_COORDINATES_REQUIRED',p_job.id,day::text);
  else update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='tms-gps:'||day;end if;
  return result;
 when 'crm_followup' then return private.automation_crm(p_job,p_config);
 when 'request_quote' then return private.automation_request_quote(p_job,p_config);
 when 'accepted_order' then return jsonb_build_object('existing_flow','Accepted quotes already create their confirmed order transactionally.');
 else return private.automation_dispatch_checks(p_job,p_config);
 end case;
end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'automation_%' or p.proname in ('tms_plan_version_capture')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005150601','automation_business_flows','c77d99407fa75bc00ca373902ae6cfa4a6fbdcd86f5694be9ad2ee59d1e76bee','c77d99407fa75bc00ca373902ae6cfa4a6fbdcd86f5694be9ad2ee59d1e76bee','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005151336_finance_project_flow_bridges.sql; SHA256 f75747fd2893d757e6680aa3e0246f6a65339e5075efdf30f4138463fd0937fc
create function private.automation_receipt_bill(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare po public.purchase_orders;bill public.supplier_invoices;linked private.automation_links;net numeric;taxes numeric;lines jsonb;begin
 if not private.erp_action_allowed('accounting','create') or private.gama_accounting_rights()->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for po in select o.* from public.purchase_orders o where o.status in ('partial','received') and exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id and l.received_quantity>0)
   order by o.updated_at,o.id limit 100 loop
   perform private.automation_enqueue('receipt_bill','receipt-bill-scan:'||po.id||':'||md5((select jsonb_agg(jsonb_build_array(l.id,l.received_quantity) order by l.id)::text from public.purchase_order_lines l where l.purchase_order_id=po.id)),jsonb_build_object('purchase_order_id',po.id),'purchase',po.id);
  end loop;return jsonb_build_object('scanned',true);
 end if;
 select * into po from public.purchase_orders where id=p_job.source_id for update;
 if not found or po.status='cancelled' then return jsonb_build_object('skipped','PURCHASE_CLOSED');end if;
 select coalesce(sum(round(z.quantity*z.unit_cost,2)),0),coalesce(sum(round(round(z.quantity*z.unit_cost,2)*z.tax_rate/100,2)),0),coalesce(jsonb_agg(to_jsonb(z) order by z.line_id),'[]') into net,taxes,lines
 from(select l.id line_id,l.unit_cost,l.tax_rate,greatest(0,l.received_quantity-coalesce((select sum(ml.quantity) from public.supplier_invoice_match_lines ml join public.supplier_invoice_matches m on m.id=ml.match_id join public.supplier_invoices b on b.id=m.invoice_id where ml.purchase_line_id=l.id and b.status='posted'),0)) quantity
  from public.purchase_order_lines l where l.purchase_order_id=po.id)z where z.quantity>0;
 if net+taxes<=0 then return jsonb_build_object('skipped','NO_UNBILLED_RECEIPT');end if;
 select * into linked from private.automation_links where source_type='purchase_receipt' and source_id=po.id and target_type='supplier_invoice';
 if linked.target_id is not null then
  select * into bill from public.supplier_invoices where id=linked.target_id for update;
  if bill.status='posted' then
   -- A subsequent partial receipt uses a new draft; never revise a posted bill.
   delete from private.automation_links where source_type='purchase_receipt' and source_id=po.id and target_type='supplier_invoice';bill.id:=null;
  elsif bill.status='cancelled' then return jsonb_build_object('blocked',true,'reason','CANCELLED_DRAFT_REVIEW_REQUIRED');
  elsif bill.source_reviewed then return jsonb_build_object('blocked',true,'reason','RECEIPT_CHANGED_AFTER_REVIEW');end if;
 end if;
 if bill.id is null then
  insert into public.supplier_invoices(number,supplier_id,purchase_order_id,issue_date,subtotal,tax,total,status,notes,request_key,created_by,source_reviewed)
   values('BOR-'||po.order_number,po.supplier_id,po.id,current_date,net,taxes,net+taxes,'draft','Preparado desde cantidades recibidas. Verificar número, fecha y fiscalidad con el documento del proveedor.',p_job.id,auth.uid(),false) returning * into bill;
  insert into private.automation_links(source_type,source_id,target_type,target_id,fingerprint) values('purchase_receipt',po.id,'supplier_invoice',bill.id,md5(lines::text));
 else update public.supplier_invoices set subtotal=net,tax=taxes,total=net+taxes,updated_at=now() where id=bill.id returning * into bill;
  update private.automation_links set fingerprint=md5(lines::text) where source_type='purchase_receipt' and source_id=po.id and target_type='supplier_invoice';
 end if;
 perform private.automation_exception('supplier-draft:'||bill.id,'receipt_bill','accounting','supplier_invoice',bill.id,'SUPPLIER_DOCUMENT_REVIEW_REQUIRED',p_job.id,bill.erp_reference);
 return jsonb_build_object('id',bill.id,'status','draft','lines',lines);
end $$;

create function private.automation_fleet_expense(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare src record;expense public.expenses;linked private.automation_links;answer jsonb;begin
 if not private.erp_module_allowed('fleet',array['administrador']) or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for src in select 'fleet_fuel_logs' source,id,md5(to_jsonb(f)::text) hash from public.fleet_fuel_logs f where f.logged_on>=current_date-90
   union all select 'fleet_maintenance',id,md5(to_jsonb(m)::text) from public.fleet_maintenance m where m.performed_on>=current_date-90 limit 200 loop
   perform private.automation_enqueue('fleet_expense','fleet-expense:'||src.source||':'||src.id||':'||src.hash,jsonb_build_object('table',src.source),src.source,src.id);
  end loop;return jsonb_build_object('scanned',true);
 end if;
 if p_job.source_type='fleet_fuel_logs' then select f.id,f.vehicle_id,f.logged_on source_day,f.amount amount,'Combustible · '||v.plate description,md5(to_jsonb(f)::text) hash into src from public.fleet_fuel_logs f join public.fleet_vehicles v on v.id=f.vehicle_id where f.id=p_job.source_id for update of f;
 elsif p_job.source_type='fleet_maintenance' then select m.id,m.vehicle_id,m.performed_on source_day,m.cost amount,'Mantenimiento · '||v.plate||' · '||m.kind description,md5(to_jsonb(m)::text) hash into src from public.fleet_maintenance m join public.fleet_vehicles v on v.id=m.vehicle_id where m.id=p_job.source_id for update of m;
 else raise exception 'INVALID_SOURCE';end if;
 if src.id is null or src.amount<=0 then return jsonb_build_object('skipped','NO_COST');end if;
 select * into linked from private.automation_links where source_type=p_job.source_type and source_id=src.id and target_type='expense';
 if linked.target_id is not null then select * into expense from public.expenses where id=linked.target_id for update;
  if linked.fingerprint=src.hash then return jsonb_build_object('id',expense.id,'existing',true);end if;
  if expense.status<>'draft' or expense.source_reviewed then return jsonb_build_object('blocked',true,'reason','FLEET_COST_CHANGED_AFTER_REVIEW');end if;
 end if;
 answer:=private.gama_accounting_action('expense_save',jsonb_build_object('id',expense.id,'request_key',case when expense.id is null then private.automation_key(p_job.source_type||':'||src.id) end,'expense_date',src.source_day,'description',src.description,'amount_untaxed',src.amount,'tax_amount',0,'amount_total',src.amount,'notes','Preparado desde Flota. Revisar justificante, IVA y medio de pago antes de contabilizar.'));
 update public.expenses set source_reviewed=false where id=(answer->>'id')::uuid and status='draft';
 insert into private.automation_links(source_type,source_id,target_type,target_id,fingerprint) values(p_job.source_type,src.id,'expense',(answer->>'id')::uuid,src.hash)
  on conflict(source_type,source_id,target_type) do update set fingerprint=excluded.fingerprint;
 perform private.automation_exception('expense-draft:'||(answer->>'id'),'fleet_expense','accounting','expense',(answer->>'id')::uuid,'RECEIPT_TAX_AND_PAYMENT_REVIEW_REQUIRED',p_job.id);
 return answer||jsonb_build_object('status','draft');
end $$;

create table private.finance_flow_receipts(request_key uuid primary key,actor uuid not null references public.profiles(id),payload jsonb not null,result jsonb not null,created_at timestamptz not null default now());
alter table private.finance_flow_receipts enable row level security;
revoke all on private.finance_flow_receipts from public,anon,authenticated,service_role;
create index finance_flow_receipt_actor on private.finance_flow_receipts(actor);
create function private.gama_flow_finance(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare rights jsonb:=private.gama_accounting_rights();bill public.supplier_invoices;result jsonb;receipt private.finance_flow_receipts;request uuid;net numeric;taxes numeric;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='drafts' then return jsonb_build_object('bills',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select b.*,s.name supplier_name from public.supplier_invoices b join public.suppliers s on s.id=b.supplier_id where b.status='draft' order by b.updated_at,b.id limit 100)z));end if;
 if p_action='expense_review' then
  if not (rights->>'edit')::boolean or not private.erp_action_allowed('accounting','edit') or not coalesce((p_data->>'reviewed')::boolean,false) then raise exception 'SOURCE_REVIEW_REQUIRED';end if;
  update public.expenses set source_reviewed=true,updated_at=now() where id=(p_data->>'id')::uuid and status='draft';if not found then raise exception 'EXPENSE_NOT_FOUND';end if;
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='expense-draft:'||(p_data->>'id');return jsonb_build_object('reviewed',true);
 end if;
 if p_action='post' then
  if not (rights->>'validate')::boolean or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
  request:=nullif(p_data->>'request_key','')::uuid;if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('finance-flow:'||request,0));
  select * into receipt from private.finance_flow_receipts where request_key=request;
  if found then if receipt.actor<>auth.uid() or receipt.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 end if;
 select * into bill from public.supplier_invoices where id=(p_data->>'id')::uuid for update;if not found then raise exception 'INVOICE_NOT_FOUND';end if;
 if p_action='context' then return jsonb_build_object('bill',to_jsonb(bill),'matching',case when bill.purchase_order_id is not null then private.gama_supplier_match('preview',p_data) else null end);end if;
 if bill.status<>'draft' then raise exception 'DRAFT_REQUIRED';end if;
 if bill.updated_at is distinct from nullif(p_data->>'expected_updated_at','')::timestamptz then raise exception 'DOCUMENT_CHANGED';end if;
 if p_action='save' then
  if not (rights->>'edit')::boolean or not private.erp_action_allowed('accounting','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  net:=round((p_data->>'subtotal')::numeric,2);taxes:=round((p_data->>'tax')::numeric,2);
  if net is null or taxes is null or net<0 or taxes<0 or net+taxes<=0 or net+taxes>1000000000 then raise exception 'INVALID_TOTAL';end if;
  if nullif(btrim(p_data->>'number'),'') is null or length(p_data->>'number')>100 then raise exception 'NUMBER_REQUIRED';end if;
  update public.supplier_invoices set number=btrim(p_data->>'number'),issue_date=(p_data->>'issue_date')::date,payment_terms_days=coalesce((p_data->>'payment_terms_days')::integer,0),due_date=(p_data->>'issue_date')::date+coalesce((p_data->>'payment_terms_days')::integer,0),subtotal=net,tax=taxes,total=net+taxes,notes=p_data->>'notes',source_reviewed=false,updated_at=now() where id=bill.id returning * into bill;return to_jsonb(bill);
 elsif p_action='post' then
  if not (rights->>'validate')::boolean or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not coalesce((p_data->>'reviewed')::boolean,false) or bill.number like 'BOR-%' then raise exception 'SUPPLIER_DOCUMENT_REVIEW_REQUIRED';end if;
  if exists(select 1 from public.supplier_invoices b where b.id<>bill.id and b.supplier_id=bill.supplier_id and b.number=bill.number and b.status<>'cancelled') then raise exception 'SUPPLIER_INVOICE_DUPLICATE';end if;
  if not private.gama_accounting_period_open(bill.issue_date) then raise exception 'PERIOD_CLOSED';end if;
  update public.supplier_invoices set source_reviewed=true,status='posted',updated_at=now() where id=bill.id;
  if bill.match_required and bill.purchase_order_id is not null then perform private.gama_supplier_match('approve',jsonb_build_object('id',bill.id,'lines',p_data->'lines','reason',p_data->>'reason'));end if;
  result:=jsonb_build_object('id',bill.id,'entry',private.gama_accounting_post('supplier_invoice',bill.id),'status','posted');
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='supplier-draft:'||bill.id;
  insert into private.finance_flow_receipts(request_key,actor,payload,result) values(request,auth.uid(),p_data,result);return result;
 elsif p_action='cancel' then
  if not (rights->>'edit')::boolean or not private.erp_action_allowed('accounting','edit') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'ROLE_NOT_ALLOWED';end if;
  update public.supplier_invoices set status='cancelled',notes=concat_ws(E'\n',notes,p_data->>'reason'),updated_at=now() where id=bill.id;
  update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='supplier-draft:'||bill.id;return jsonb_build_object('id',bill.id,'status','cancelled');
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_flow_finance(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_flow_finance(p_action,p_data)$$;

create table public.project_time_entries(
 id uuid primary key default gen_random_uuid(),request_key uuid not null unique,project_id uuid not null references public.pm_projects(id),employee_id uuid not null references public.hr_employees(id),
 worked_on date not null,hours numeric(8,3) not null check(hours>0 and hours<=24),description text not null check(length(btrim(description)) between 3 and 1000),
 status text not null default 'submitted' check(status in ('submitted','approved','transferred','cancelled')),
 hourly_cost numeric(14,4) check(hourly_cost>0),evidence text,approved_by uuid references public.profiles(id),approved_at timestamptz,
 cost_entry_id uuid references public.pm_cost_entries(id),created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(status not in ('approved','transferred') or (approved_by is not null and approved_at is not null and hourly_cost>0 and length(btrim(evidence))>=3))
);
alter table public.project_time_entries enable row level security;
revoke all on public.project_time_entries from public,anon,authenticated;grant select on public.project_time_entries to authenticated;
create policy project_time_read on public.project_time_entries for select to authenticated using((select private.erp_mfa_ok()) and private.pm_manage(project_id) and private.hr_manage(employee_id));
create index project_time_project on public.project_time_entries(project_id,worked_on,id);
create index project_time_employee on public.project_time_entries(employee_id,worked_on);
create index project_time_approver on public.project_time_entries(approved_by);
create index project_time_creator on public.project_time_entries(created_by);
create index project_time_cost on public.project_time_entries(cost_entry_id);
create index project_time_pending on public.project_time_entries(updated_at,id) where status='approved';
create trigger erp_audit_capture after insert or update or delete on public.project_time_entries for each row execute function private.erp_audit_capture();
create function private.gama_project_time(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare pid uuid:=(p_data->>'project_id')::uuid;entry public.project_time_entries;employee uuid;key uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('projects',array['administrador','comercial','almacenero']) or not private.pm_manage(pid) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select t.*,e.full_name employee_name from public.project_time_entries t join public.hr_employees e on e.id=t.employee_id where t.project_id=pid and private.hr_manage(e.id) order by t.worked_on desc,t.id limit 200)z),
  'employees',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name),'[]') from public.hr_employees where active and private.hr_manage(id)));end if;
 if p_action='submit' then
  if not private.erp_action_allowed('projects','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
  employee:=(p_data->>'employee_id')::uuid;if not private.hr_manage(employee) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if (p_data->>'worked_on')::date>current_date then raise exception 'WORK_DATE_FUTURE';end if;
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  select * into entry from public.project_time_entries where request_key=key;if found then
   if entry.project_id<>pid or entry.employee_id<>employee or entry.created_by<>auth.uid() or entry.worked_on<>(p_data->>'worked_on')::date or entry.hours<>(p_data->>'hours')::numeric or entry.description<>p_data->>'description' then raise exception 'REQUEST_KEY_REUSED';end if;return to_jsonb(entry);
  end if;
  if exists(select 1 from public.pm_projects where id=pid and status in ('completed','cancelled')) then raise exception 'PROJECT_CLOSED';end if;
  insert into public.project_time_entries(request_key,project_id,employee_id,worked_on,hours,description) values(key,pid,employee,(p_data->>'worked_on')::date,(p_data->>'hours')::numeric,p_data->>'description') returning * into entry;return to_jsonb(entry);
 end if;
 select * into entry from public.project_time_entries where id=(p_data->>'id')::uuid and project_id=pid for update;
 if not found or not private.hr_manage(entry.employee_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='approve' then
  if entry.status<>'submitted' then raise exception 'TIME_ENTRY_CHANGED';end if;
  if not private.erp_action_allowed('projects','validate') or not private.erp_module_allowed('hr',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  update public.project_time_entries set status='approved',hourly_cost=(p_data->>'hourly_cost')::numeric,evidence=p_data->>'evidence',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=entry.id returning * into entry;
  perform private.automation_enqueue('project_hours','project-time:'||entry.id,jsonb_build_object('time_entry_id',entry.id),'project_time',entry.id);
 elsif p_action='cancel' then
  if not private.erp_action_allowed('projects','edit') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if entry.cost_entry_id is not null then perform private.gama_project_finance('cancel_cost',jsonb_build_object('id',entry.cost_entry_id,'project_id',pid,'reason',p_data->>'reason'));end if;
  update public.project_time_entries set status='cancelled',updated_at=now() where id=entry.id returning * into entry;
 else raise exception 'INVALID_ACTION';end if;
 return to_jsonb(entry);
end $$;
create function public.gama_project_time(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_project_time(p_action,p_data)$$;
create function private.automation_project_hours(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare entry public.project_time_entries;cid uuid;result jsonb;begin
 if not private.erp_action_allowed('projects','create') or not private.erp_module_allowed('hr',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_job.source_id is null then
  for entry in select * from public.project_time_entries where status='approved' and cost_entry_id is null order by worked_on,id limit 100 loop
   perform private.automation_enqueue('project_hours','project-time:'||entry.id,jsonb_build_object('time_entry_id',entry.id),'project_time',entry.id);
  end loop;return jsonb_build_object('scanned',true);
 end if;
 select * into entry from public.project_time_entries where id=p_job.source_id for update;
 if not found or entry.status='cancelled' then return jsonb_build_object('skipped','TIME_ENTRY_CLOSED');end if;
 if entry.cost_entry_id is not null then return jsonb_build_object('id',entry.cost_entry_id,'existing',true);end if;
 if entry.status<>'approved' or not private.hr_manage(entry.employee_id) then return jsonb_build_object('blocked',true,'reason','TIME_APPROVAL_REQUIRED');end if;
 cid:=private.automation_key('project-time:'||entry.id);
 result:=private.gama_project_finance('cost',jsonb_build_object('id',cid,'project_id',entry.project_id,'entry_date',entry.worked_on,'kind','labor','description',entry.description,'quantity',entry.hours,'unit_cost',entry.hourly_cost,'source_reference','hr-time:'||entry.id));
 update public.project_time_entries set status='transferred',cost_entry_id=cid,updated_at=now() where id=entry.id;
 insert into private.automation_links(source_type,source_id,target_type,target_id) values('project_time',entry.id,'pm_cost_entry',cid) on conflict do nothing;
 return jsonb_build_object('id',cid,'hours',entry.hours);
end $$;

alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_business;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 case p_job.kind when 'receipt_bill' then return private.automation_receipt_bill(p_job,p_config);
 when 'fleet_expense' then return private.automation_fleet_expense(p_job,p_config);
 when 'project_hours' then return private.automation_project_hours(p_job,p_config);
 else return private.automation_dispatch_business(p_job,p_config);end case;
end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and (p.proname like 'automation_%' or p.proname in ('gama_flow_finance','gama_project_time')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
grant execute on function public.gama_flow_finance(text,jsonb),private.gama_flow_finance(text,jsonb),public.gama_project_time(text,jsonb),private.gama_project_time(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005151336','finance_project_flow_bridges','f75747fd2893d757e6680aa3e0246f6a65339e5075efdf30f4138463fd0937fc','f75747fd2893d757e6680aa3e0246f6a65339e5075efdf30f4138463fd0937fc','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005151929_b2b_customer_documents_center.sql; SHA256 3d97153b50d067ab951ec8e14e903d320f67dc0440810097605e60fea7ee2aed
-- One customer documents page; each download still rechecks membership/ownership.
-- No inline proof images, private notes, product costs or Storage paths in lists.
alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_documents;
revoke all on function private.gama_b2b_action_before_documents(text,jsonb) from public,anon,authenticated;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare cid uuid:=private.gama_b2b_customer();off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));
 term text:=left(btrim(coalesce(p_data->>'search','')),100);filter text:=coalesce(p_data->>'kind','');result jsonb;begin
 if p_action='documents' then
  if filter not in ('','invoice','delivery_proof','quote') then raise exception 'INVALID_DATA';end if;
  with owned as(
   select 'invoice' kind,i.id,coalesce(i.erp_reference,i.number) reference,i.issue_date document_date,
    coalesce(i.external_number,i.number) fiscal_number,i.total amount,i.fiscal_status status,
    (select s.id from public.sri_invoice_issues s where s.source_invoice_id=i.id and s.customer_id=cid and s.status='authorized' order by s.created_at desc limit 1) sri_id,
    coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'mime_type',f.mime_type) order by f.id) from public.external_invoice_files f where f.invoice_id=i.id),'[]') files
   from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected')
   union all
   select 'delivery_proof',d.id,d.erp_reference,d.delivery_date,null,null,d.status,null,'[]'::jsonb
   from public.tms_deliveries d where d.customer_id=cid and exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)
    and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid)
   union all
   select 'quote',q.id,coalesce(q.erp_reference,q.invoice_number),q.issue_date::date,null,q.total,q.quote_state,null,'[]'::jsonb
   from public.invoices q where q.customer_id=cid and q.quote_state in ('sent','accepted','rejected') and q.status not in ('cancelled','rejected')
  ),filtered as(select * from owned where (filter='' or kind=filter) and (term='' or concat_ws(' ',reference,fiscal_number) ilike '%'||term||'%')),
  limited as(select * from filtered order by document_date desc,kind,id limit 30 offset off)
  select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce(jsonb_agg(to_jsonb(limited) order by document_date desc,kind,id),'[]'),'as_of',now()) into result from limited;
  return result;
 elsif p_action='quote_document' then
  select jsonb_build_object('reference',coalesce(q.erp_reference,q.invoice_number),'date',q.issue_date::date,'valid_until',q.quote_valid_until,'status',q.quote_state,'subtotal',q.subtotal,'tax',q.tax,'total',q.total,
   'customer',(select jsonb_build_object('name',name,'identification',identification) from public.customers where id=cid),
   'address',q.quote_details->>'delivery_address','lines',(select coalesce(jsonb_agg(jsonb_build_object('description',coalesce(l.quote_description,p.name),'reference',p.reference,'quantity',l.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate,'line_total',l.line_total) order by l.id),'[]') from public.invoice_lines l left join public.products p on p.id=l.product_id where l.invoice_id=q.id),
   'company',(select jsonb_build_object('legal_name',legal_name,'tax_id',tax_id,'address',address,'phone',phone,'email',email,'country',country,'currency',currency,'logo_data',logo_data) from public.company_settings where id)) into result
   from public.invoices q where q.id=(p_data->>'id')::uuid and q.customer_id=cid and q.quote_state in ('sent','accepted','rejected') and q.status not in ('cancelled','rejected');
  if result is null then raise exception 'NOT_FOUND';end if;return result;
 end if;
 return private.gama_b2b_action_before_documents(p_action,p_data);
end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

-- Per-customer account management from Contacts, with the same rights as the
-- website administration; no guessed email binding and no profile activation.
create function private.gama_b2b_customer_accounts(p_customer uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('website',array['administrador']) or not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return jsonb_build_object('customer',(select jsonb_build_object('id',c.id,'name',c.name,'email',c.email,'enabled',coalesce(a.enabled,false)) from public.customers c left join public.b2b_customer_access a on a.customer_id=c.id where c.id=p_customer and c.active),
  'members',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'email',u.email,'active',m.active,'verified',u.email_confirmed_at is not null) order by p.full_name,p.id),'[]') from public.b2b_memberships m join public.profiles p on p.id=m.profile_id join auth.users u on u.id=p.id where m.customer_id=p_customer and p.deleted_at is null),
  'available',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'email',p.email) order by p.full_name,p.id),'[]') from (select p.id,p.full_name,u.email from public.profiles p join auth.users u on u.id=p.id where p.role='cliente' and p.deleted_at is null and not exists(select 1 from public.b2b_memberships m where m.profile_id=p.id) order by p.full_name,p.id limit 100)p));
end $$;
create function public.gama_b2b_customer_accounts(p_customer uuid) returns jsonb language sql security invoker set search_path='' as $$select private.gama_b2b_customer_accounts(p_customer)$$;
revoke all on function public.gama_b2b_customer_accounts(uuid),private.gama_b2b_customer_accounts(uuid) from public,anon,service_role;
grant execute on function public.gama_b2b_customer_accounts(uuid),private.gama_b2b_customer_accounts(uuid) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005151929','b2b_customer_documents_center','3d97153b50d067ab951ec8e14e903d320f67dc0440810097605e60fea7ee2aed','3d97153b50d067ab951ec8e14e903d320f67dc0440810097605e60fea7ee2aed','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005154518_operational_metrics.sql; SHA256 3e1ca43abbb53c2ea92b6914936c1d5570ba849d31624f7f543c677da5470f68
-- Bounded first-party operational measurements; never store form data, document
-- identifiers, tokens, URL queries, error text or network payloads.
create table private.operational_metrics(id bigint generated always as identity primary key,actor uuid not null references public.profiles(id),recorded_at timestamptz not null default now(),metric text not null check(metric in ('rpc','navigation','action')),module text not null,operation text not null,duration_ms integer not null check(duration_ms between 0 and 300000),success boolean not null,device text not null check(device in ('mobile','desktop')),network text not null check(network in ('slow','normal','unknown')));
alter table private.operational_metrics enable row level security;
revoke all on private.operational_metrics from public,anon,authenticated,service_role;
create index operational_metrics_actor_time on private.operational_metrics(actor,recorded_at);
create index operational_metrics_time on private.operational_metrics(recorded_at,module,metric);
create function private.gama_operational_metrics(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;n integer;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.deleted_at is null and p.role in ('administrador','comercial','almacenero')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='record' then
  if jsonb_typeof(p_data->'samples') is distinct from 'array' or jsonb_array_length(p_data->'samples') not between 1 and 50 then raise exception 'INVALID_DATA';end if;
  perform pg_advisory_xact_lock(hashtextextended('metrics:'||auth.uid(),0));
  select count(*) into n from private.operational_metrics where actor=auth.uid() and recorded_at>=now()-interval '1 minute';if n>=1000 then return jsonb_build_object('accepted',0,'limited',true);end if;
  for item in select value from jsonb_array_elements(p_data->'samples') loop
   if item->>'module' !~ '^[a-zA-Z0-9_-]{1,64}$' or item->>'operation' !~ '^[a-zA-Z0-9_-]{0,64}$' then raise exception 'INVALID_DATA';end if;
   insert into private.operational_metrics(actor,metric,module,operation,duration_ms,success,device,network) values(auth.uid(),item->>'metric',item->>'module',item->>'operation',(item->>'duration_ms')::integer,(item->>'success')::boolean,item->>'device',item->>'network');
  end loop;return jsonb_build_object('accepted',jsonb_array_length(p_data->'samples'));
 elsif p_action='report' then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  return jsonb_build_object('as_of',now(),'window_days',7,'rows',(select coalesce(jsonb_agg(to_jsonb(z) order by z.p95_ms desc),'[]') from(select metric,module,operation,device,network,count(*) samples,round((percentile_cont(.95) within group(order by duration_ms))::numeric) p95_ms,round(avg(duration_ms)) average_ms,count(*) filter(where not success) errors from private.operational_metrics where recorded_at>=now()-interval '7 days' group by metric,module,operation,device,network order by count(*) desc limit 200)z));
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_operational_metrics(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_operational_metrics(p_action,p_data)$$;
revoke all on function public.gama_operational_metrics(text,jsonb),private.gama_operational_metrics(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_operational_metrics(text,jsonb),private.gama_operational_metrics(text,jsonb) to authenticated;
create function private.operational_metrics_cleanup() returns void language sql security definer set search_path='' as $$delete from private.operational_metrics where recorded_at<now()-interval '14 days'$$;
revoke all on function private.operational_metrics_cleanup() from public,anon,authenticated,service_role;
select cron.schedule('coco-metrics-retention','25 3 * * *','select private.operational_metrics_cleanup()');

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005154518','operational_metrics','3e1ca43abbb53c2ea92b6914936c1d5570ba849d31624f7f543c677da5470f68','3e1ca43abbb53c2ea92b6914936c1d5570ba849d31624f7f543c677da5470f68','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005154521_supplier_xml_intake.sql; SHA256 77c1462ab942f6394e89ac5bf2113970c450bd34e39a2727d5608e0f8f0d9735
create table private.supplier_xml_intakes(id uuid primary key default gen_random_uuid(),hash text not null unique,supplier_id uuid not null references public.suppliers(id),bill_id uuid not null references public.supplier_invoices(id),xml_source text not null,filename text not null,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
alter table private.supplier_xml_intakes enable row level security;
revoke all on private.supplier_xml_intakes from public,anon,authenticated,service_role;
create index supplier_xml_supplier on private.supplier_xml_intakes(supplier_id);
create index supplier_xml_bill on private.supplier_xml_intakes(bill_id);
create index supplier_xml_actor on private.supplier_xml_intakes(created_by);
create function private.xml_value(p_doc xml,p_path text) returns text language sql immutable security definer set search_path='' as $$select (xpath(p_path,p_doc)::text[])[1]$$;
revoke all on function private.xml_value(xml,text) from public,anon,authenticated,service_role;
create function private.gama_supplier_xml(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare rights jsonb:=private.gama_accounting_rights();raw text:=p_data->>'xml';doc xml;hash text;prior private.supplier_xml_intakes;vendor uuid;purchase uuid:=nullif(p_data->>'purchase_order_id','')::uuid;bill public.supplier_invoices;ruc text;buyer text;number text;day_text text;issued date;net numeric;tax numeric;total numeric;counted integer;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if raw is null or octet_length(raw)>2097152 or raw~* '<!DOCTYPE|<!ENTITY' then raise exception 'INVALID_XML';end if;
 hash:=encode(sha256(convert_to(raw,'UTF8')),'hex');perform pg_advisory_xact_lock(hashtextextended('supplier-xml:'||hash,0));
 select * into prior from private.supplier_xml_intakes where supplier_xml_intakes.hash=hash;
 if found then select * into bill from public.supplier_invoices where id=prior.bill_id;if bill.purchase_order_id is distinct from purchase then raise exception 'XML_PURCHASE_CHANGED';end if;return jsonb_build_object('id',bill.id,'existing',true,'status',bill.status);end if;
 doc:=xmlparse(document raw);
 if xpath_exists('/autorizacion',doc) then raw:=private.xml_value(doc,'/autorizacion/comprobante/text()');if raw is null or raw~* '<!DOCTYPE|<!ENTITY' then raise exception 'INVALID_XML';end if;doc:=xmlparse(document raw);end if;
 if not xpath_exists('/factura/infoTributaria',doc) then raise exception 'SUPPLIER_INVOICE_XML_REQUIRED';end if;
 ruc:=private.xml_value(doc,'/factura/infoTributaria/ruc/text()');buyer:=private.xml_value(doc,'/factura/infoFactura/identificacionComprador/text()');
 if ruc is null or ruc!~ '^[0-9]{13}$' then raise exception 'ISSUER_RUC_REQUIRED';end if;
 if exists(select 1 from public.company_settings c where c.id and nullif(c.tax_id,'') is not null and c.tax_id is distinct from buyer) then raise exception 'XML_BUYER_MISMATCH';end if;
 select count(*),(array_agg(id))[1] into counted,vendor from public.suppliers where active and regexp_replace(coalesce(tax_id,''),'[^0-9]','','g')=ruc;
 if counted<>1 then raise exception 'SUPPLIER_MATCH_REQUIRED';end if;
 number:=private.xml_value(doc,'/factura/infoTributaria/estab/text()')||'-'||private.xml_value(doc,'/factura/infoTributaria/ptoEmi/text()')||'-'||private.xml_value(doc,'/factura/infoTributaria/secuencial/text()');
 if number is null or number!~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$' then raise exception 'NUMBER_REQUIRED';end if;
 day_text:=private.xml_value(doc,'/factura/infoFactura/fechaEmision/text()');issued:=to_date(day_text,'DD/MM/YYYY');if to_char(issued,'DD/MM/YYYY') is distinct from day_text then raise exception 'INVALID_DATE';end if;
 net:=private.xml_value(doc,'/factura/infoFactura/totalSinImpuestos/text()')::numeric;total:=private.xml_value(doc,'/factura/infoFactura/importeTotal/text()')::numeric;
 if xpath_exists('/factura/infoFactura/totalConImpuestos/totalImpuesto[codigo != "2"]',doc) or coalesce(private.xml_value(doc,'/factura/infoFactura/propina/text()')::numeric,0)<>0 then raise exception 'XML_TAX_REVIEW_REQUIRED';end if;
 select coalesce(sum(x::text::numeric),0) into tax from unnest(xpath('/factura/infoFactura/totalConImpuestos/totalImpuesto/valor/text()',doc))x;
 if net is null or total is null or net<0 or total<=0 or total>1000000000 or round(net+tax,2)<>total or total<>round(total,2) or coalesce(private.xml_value(doc,'/factura/infoFactura/moneda/text()'),'DOLAR') not in ('DOLAR','USD') then raise exception 'XML_TOTAL_OR_CURRENCY_INVALID';end if;
 if purchase is not null and not exists(select 1 from public.purchase_orders o where o.id=purchase and o.supplier_id=vendor and o.status<>'cancelled') then raise exception 'SUPPLIER_MISMATCH';end if;
 if exists(select 1 from public.supplier_invoices b where b.supplier_id=vendor and b.number=number and b.status<>'cancelled') then raise exception 'SUPPLIER_INVOICE_DUPLICATE';end if;
 if purchase is not null then select * into bill from public.supplier_invoices b where b.purchase_order_id=purchase and b.status='draft' and not b.source_reviewed order by created_at,id limit 1 for update;end if;
 if bill.id is null then insert into public.supplier_invoices(supplier_id,purchase_order_id,number,issue_date,subtotal,tax,total,status,source_reviewed,request_key,created_by,notes) values(vendor,purchase,number,issued,net,tax,total,'draft',false,gen_random_uuid(),auth.uid(),'Importado desde XML. La firma y autorización no han sido verificadas; requiere revisión fiscal y recepción.') returning * into bill;
 else update public.supplier_invoices set number=number,issue_date=issued,subtotal=net,tax=tax,total=total,source_reviewed=false,updated_at=now() where id=bill.id returning * into bill;end if;
 insert into private.supplier_xml_intakes(hash,supplier_id,bill_id,xml_source,filename,created_by) values(hash,vendor,bill.id,p_data->>'xml',left(coalesce(p_data->>'filename','factura.xml'),200),auth.uid());
 perform private.automation_exception('supplier-draft:'||bill.id,'receipt_bill','accounting','supplier_invoice',bill.id,'XML_FISCAL_AND_RECEIPT_REVIEW_REQUIRED',null,bill.erp_reference);
 return jsonb_build_object('id',bill.id,'status','draft','hash',hash,'fiscal_verification','pending');
end $$;
create function public.gama_supplier_xml(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_supplier_xml(p_data)$$;
revoke all on function public.gama_supplier_xml(jsonb),private.gama_supplier_xml(jsonb) from public,anon,service_role;
grant execute on function public.gama_supplier_xml(jsonb),private.gama_supplier_xml(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005154521','supplier_xml_intake','77c1462ab942f6394e89ac5bf2113970c450bd34e39a2727d5608e0f8f0d9735','77c1462ab942f6394e89ac5bf2113970c450bd34e39a2727d5608e0f8f0d9735','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005155700_customer_followup_flows.sql; SHA256 8cc9b41a22bb99e68f9081854c089df0477054bd2d30395764a44b7a0834b68f
-- Real email dispatch is opt-in and requires a verified provider/domain. Until
-- configured, jobs expose a setup exception. Private sources are never guessed.
create extension if not exists pg_net with schema extensions;
create table private.customer_message_preferences(customer_id uuid primary key references public.customers(id),invoice_reminders boolean not null default false,surveys boolean not null default false,evidence text not null,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index customer_message_preference_actor on private.customer_message_preferences(updated_by);
create table private.message_provider(id boolean primary key default true check(id),enabled boolean not null default false,sender text not null,secret_id uuid not null,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index message_provider_actor on private.message_provider(updated_by);
create table private.message_outbox(id uuid primary key default gen_random_uuid(),key text not null unique,kind text not null check(kind in ('invoice_reminder','survey')),customer_id uuid not null references public.customers(id),source_id uuid not null,job_id uuid not null references private.automation_jobs(id),actor uuid not null references public.profiles(id),rule_version integer not null,recipient text not null,source_amount numeric,subject text not null,body text not null,state text not null default 'queued' check(state in ('queued','dispatching','accepted','delivered','bounced','complained','failed','cancelled','uncertain')),request_id bigint,provider_id text,attempts integer not null default 0,first_sent_at timestamptz,next_poll_at timestamptz,lease_until timestamptz,error_code text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index message_outbox_customer on private.message_outbox(customer_id);
create index message_outbox_job on private.message_outbox(job_id);
create index message_outbox_actor on private.message_outbox(actor);
create index message_outbox_due on private.message_outbox(state,next_poll_at,created_at);
create index message_outbox_source on private.message_outbox(kind,source_id);
do $$declare t text;begin foreach t in array array['customer_message_preferences','message_provider','message_outbox'] loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end $$;

create function private.gama_messages(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare customer uuid:=(p_data->>'customer_id')::uuid;secret uuid;conf private.message_provider;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object('provider',(select jsonb_build_object('enabled',enabled,'sender',sender,'configured',true) from private.message_provider where id),'outbox',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select id,kind,customer_id,source_id,state,subject,attempts,error_code,created_at,updated_at from private.message_outbox order by created_at desc,id limit 100)z));
 elsif p_action='configure' then
  if not private.erp_action_allowed('access-settings','edit') or p_data->>'sender' !~ '^[^\r\n<>]+@[^\r\n<>]+\.[^\r\n<>]+$' or length(coalesce(p_data->>'api_key','')) not between 10 and 300 then raise exception 'PROVIDER_CONFIG_REQUIRED';end if;
  select * into conf from private.message_provider where id for update;
  if conf.secret_id is null then secret:=vault.create_secret(p_data->>'api_key','coco_email_provider');else secret:=conf.secret_id;perform vault.update_secret(secret,p_data->>'api_key');end if;
  insert into private.message_provider(id,sender,secret_id,enabled,updated_by) values(true,p_data->>'sender',secret,coalesce((p_data->>'enabled')::boolean,false),auth.uid()) on conflict(id) do update set sender=excluded.sender,secret_id=excluded.secret_id,enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('configured',true);
 elsif p_action='preferences' then return coalesce((select jsonb_build_object('invoice_reminders',invoice_reminders,'surveys',surveys) from private.customer_message_preferences where customer_id=customer),'{"invoice_reminders":false,"surveys":false}'::jsonb);
 elsif p_action='preferences_save' then
  if not private.erp_action_allowed('access-settings','edit') or length(btrim(coalesce(p_data->>'evidence','')))<3 or not exists(select 1 from public.customers where id=customer and active) then raise exception 'PREFERENCE_EVIDENCE_REQUIRED';end if;
  insert into private.customer_message_preferences(customer_id,invoice_reminders,surveys,evidence,updated_by) values(customer,coalesce((p_data->>'invoice_reminders')::boolean,false),coalesce((p_data->>'surveys')::boolean,false),p_data->>'evidence',auth.uid()) on conflict(customer_id) do update set invoice_reminders=excluded.invoice_reminders,surveys=excluded.surveys,evidence=excluded.evidence,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_messages(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_messages(p_action,p_data)$$;
revoke all on function public.gama_messages(text,jsonb),private.gama_messages(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_messages(text,jsonb),private.gama_messages(text,jsonb) to authenticated;

create function private.automation_reminders(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row record;days integer:=greatest(1,least(coalesce((p_config->>'interval_days')::integer,7),90));n integer:=0;slot bigint:=floor(extract(epoch from now())/(86400*days));begin
 if not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 for row in select r.*,c.email outbound_email from private.gama_receivables r join public.customers c on c.id=r.customer_id join private.customer_message_preferences p on p.customer_id=c.id and p.invoice_reminders where c.active and r.balance>0 and r.due_date<current_date and c.email~'^[^\s@]+@[^\s@]+\.[^\s@]+$' order by r.due_date,r.id limit 100 loop
  insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,source_amount,subject,body) values('invoice:'||row.id||':'||slot,'invoice_reminder',row.customer_id,row.id,p_job.id,auth.uid(),p_job.rule_version,row.outbound_email,row.balance,'GAMA · saldo pendiente '||row.number,'Hola '||row.customer_name||E',\nLa factura '||row.number||' tiene un saldo pendiente de USD '||row.balance||E'.\nSi ya has pagado, envíanos el comprobante para actualizar el registro.\nPuedes consultar tus documentos en https://gama-coco.pages.dev/b2b.html') on conflict(key) do nothing;n:=n+1;
 end loop;return jsonb_build_object('prepared',n);end $$;
create function private.automation_service_followup(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare ticket public.service_tickets;n integer:=0;begin
 if not private.service_access('sav') then raise exception 'ROLE_NOT_ALLOWED';end if;
 update private.automation_exceptions e set active=false,resolved_at=now(),updated_at=now() where e.kind='service_followup' and e.active and not exists(select 1 from public.service_tickets s where s.id=e.source_id and not s.archived and s.status not in ('resolved','closed') and coalesce(s.resolution_due_at,s.due_date::timestamptz)<now());
 for ticket in select * from public.service_tickets where not archived and status not in ('resolved','closed') and coalesce(resolution_due_at,due_date::timestamptz)<now() order by created_at,id limit 200 loop
  perform private.automation_exception('service-followup:'||ticket.id,'service_followup','returns','service_ticket',ticket.id,'SERVICE_SLA_OVERDUE',p_job.id,ticket.erp_reference);
  update private.automation_exceptions set assigned_to=coalesce(assigned_to,ticket.assigned_to),next_action=coalesce(nullif(next_action,''),'Revisar SLA, recepción y resolución del caso') where key='service-followup:'||ticket.id;n:=n+1;
 end loop;return jsonb_build_object('followups',n);end $$;
create function private.automation_surveys(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid:=nullif(p_config->>'survey_id','')::uuid;s private.surveys;row record;inv jsonb;n integer:=0;begin
 if not private.erp_action_allowed('surveys','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into s from private.surveys where id=sid and state='open' and (closes_at is null or closes_at>now());if not found then return jsonb_build_object('blocked',true,'reason','PUBLISHED_SURVEY_REQUIRED');end if;
 if not exists(select 1 from private.message_provider where id and enabled) then return jsonb_build_object('blocked',true,'reason','EMAIL_PROVIDER_CONFIG_REQUIRED');end if;
 for row in select distinct c.id,c.email from public.customers c join private.customer_message_preferences pref on pref.customer_id=c.id and pref.surveys where c.active and c.email~'^[^\s@]+@[^\s@]+\.[^\s@]+$' and (exists(select 1 from public.tms_deliveries d where d.customer_id=c.id and d.status='Entregada' and d.delivery_date>=current_date-30) or exists(select 1 from public.service_tickets t where t.customer_id=c.id and t.status in ('resolved','closed') and t.resolved_at>=now()-interval '30 days')) order by c.id limit 100 loop
  inv:=private.gama_surveys('invite',jsonb_build_object('id',sid,'kind','customer','contact_id',row.id));
  if not exists(select 1 from private.survey_responses where invitation_id=(inv->>'id')::uuid) then
   insert into private.message_outbox(key,kind,customer_id,source_id,job_id,actor,rule_version,recipient,subject,body) values('survey:'||(inv->>'id'),'survey',row.id,(inv->>'id')::uuid,p_job.id,auth.uid(),p_job.rule_version,row.email,'GAMA · '||s.title,E'Gracias por confiar en GAMA. Puedes compartir tu experiencia aquí:\nhttps://gama-coco.pages.dev/surveys.html#'||(inv->>'token')) on conflict(key) do nothing;n:=n+1;
  end if;
 end loop;return jsonb_build_object('prepared',n);end $$;

create function private.message_dispatch() returns jsonb language plpgsql security definer set search_path='' as $$
declare message private.message_outbox;provider private.message_provider;rule private.automation_rules;job private.automation_jobs;response record;key text;response_payload jsonb;valid boolean;status text;n integer:=0;request bigint;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-message-dispatch',0)) then return jsonb_build_object('busy',true);end if;
 select * into provider from private.message_provider where id and enabled;if not found then return jsonb_build_object('configured',false);end if;
 select decrypted_secret into key from vault.decrypted_secrets where id=provider.secret_id;if nullif(key,'') is null then return jsonb_build_object('configured',false);end if;
 for message in select * from private.message_outbox where state in ('queued','dispatching','accepted') and coalesce(next_poll_at,created_at)<=now() order by created_at,id limit 25 for update skip locked loop
  if message.state='dispatching' then
   select * into response from net._http_response where id=message.request_id;
   if not found and message.lease_until>now() then continue;end if;
   if found and response.status_code=200 then
    response_payload:=response.content::jsonb;if coalesce(response_payload->>'id','')~'^[0-9a-f-]{36}$' then update private.message_outbox set state='accepted',provider_id=response_payload->>'id',request_id=null,next_poll_at=now()+interval '10 minutes',lease_until=null,updated_at=now() where id=message.id;continue;end if;
   end if;
   if message.attempts>=5 or message.first_sent_at<now()-interval '23 hours' then update private.message_outbox set state='uncertain',error_code='PROVIDER_CONFIRMATION_REQUIRED',lease_until=null,updated_at=now() where id=message.id;continue;end if;
   update private.message_outbox set state='queued',request_id=null,lease_until=null,next_poll_at=now()+interval '5 minutes',error_code='PROVIDER_RETRY',updated_at=now() where id=message.id;continue;
  elsif message.state='accepted' then
   if message.request_id is not null then
    select * into response from net._http_response where id=message.request_id;
    if found and response.status_code=200 then
     response_payload:=response.content::jsonb;status:=response_payload->>'last_event';
     if status in ('delivered','bounced','complained','failed') then update private.message_outbox set state=status,request_id=null,lease_until=null,updated_at=now() where id=message.id;continue;end if;
    elsif not found and message.lease_until>now() then continue;end if;
   end if;
   if message.first_sent_at<now()-interval '7 days' then update private.message_outbox set state='uncertain',error_code='DELIVERY_STATUS_UNCONFIRMED',request_id=null,updated_at=now() where id=message.id;continue;end if;
   request:=net.http_get(url:='https://api.resend.com/emails/'||message.provider_id,headers:=jsonb_build_object('Authorization','Bearer '||key),timeout_milliseconds:=10000);
   update private.message_outbox set request_id=request,lease_until=now()+interval '2 minutes',next_poll_at=now()+interval '10 minutes',updated_at=now() where id=message.id;continue;
  end if;
  -- Check the current rule, actor, rights, customer preference, source balance
  -- and recipient immediately before dispatch; a changed email requires review.
  select * into job from private.automation_jobs where id=message.job_id for update;select * into rule from private.automation_rules where kind=job.kind order by version desc limit 1;
  valid:=rule.enabled and rule.version=message.rule_version and rule.executor=message.actor and rule.approved_until>now() and exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=message.actor and p.active and p.deleted_at is null and p.role='administrador' and (u.banned_until is null or u.banned_until<=now()));
  valid:=coalesce(valid,false) and exists(select 1 from public.customers c join private.customer_message_preferences pref on pref.customer_id=c.id where c.id=message.customer_id and c.active and c.email=message.recipient and case message.kind when 'survey' then pref.surveys else pref.invoice_reminders end);
  if message.kind='invoice_reminder' then valid:=valid and exists(select 1 from private.gama_receivables r where r.id=message.source_id and r.customer_id=message.customer_id and r.balance>0 and r.balance=message.source_amount and r.due_date<current_date);
  else valid:=valid and exists(select 1 from private.survey_invitations i join private.surveys s on s.id=i.survey_id where i.id=message.source_id and not i.revoked and s.state='open' and (s.closes_at is null or s.closes_at>now()) and not exists(select 1 from private.survey_responses r where r.invitation_id=i.id));end if;
  if not valid then update private.message_outbox set state='cancelled',error_code='SOURCE_OR_PERMISSION_CHANGED',updated_at=now() where id=message.id;continue;end if;
  begin
   update private.automation_jobs set state='running' where id=job.id;
   perform set_config('request.jwt.claim.sub',message.actor::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',message.actor,'role','authenticated')::text,true);
   insert into private.automation_execution_context(backend,transaction,job_id,actor) values(pg_backend_pid(),txid_current(),job.id,message.actor);
   if not private.erp_mfa_ok() or not private.automation_visible(case message.kind when 'survey' then 'surveys' else 'payments' end) or not private.erp_action_allowed(case message.kind when 'survey' then 'surveys' else 'payments' end,case message.kind when 'survey' then 'edit' else 'create' end) then raise exception 'DELEGATION_ACCESS_REVOKED';end if;
   response_payload:=jsonb_build_object('from',provider.sender,'to',jsonb_build_array(message.recipient),'subject',message.subject,'text',message.body);
   request:=net.http_post(url:='https://api.resend.com/emails',body:=response_payload,headers:=jsonb_build_object('Authorization','Bearer '||key,'Content-Type','application/json','Idempotency-Key','coco-'||message.id),timeout_milliseconds:=10000);
   update private.message_outbox set state='dispatching',request_id=request,attempts=attempts+1,first_sent_at=coalesce(first_sent_at,now()),lease_until=now()+interval '2 minutes',next_poll_at=now()+interval '1 minute',updated_at=now() where id=message.id;
   delete from private.automation_execution_context where backend=pg_backend_pid() and transaction=txid_current();update private.automation_jobs set state=job.state where id=job.id;n:=n+1;
  exception when others then update private.message_outbox set state='failed',error_code='DISPATCH_ACCESS_OR_REQUEST_FAILED',updated_at=now() where id=message.id;
  end;
  perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
 end loop;return jsonb_build_object('dispatched',n);end $$;
revoke all on function private.message_dispatch() from public,anon,authenticated,service_role;
select cron.schedule('coco-message-dispatch','* * * * *','select private.message_dispatch()');

alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_customer_followup;
revoke all on function private.automation_dispatch_before_customer_followup(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 case p_job.kind when 'reminders' then return private.automation_reminders(p_job,p_config);when 'service_followup' then return private.automation_service_followup(p_job,p_config);when 'survey_followup' then return private.automation_surveys(p_job,p_config);else return private.automation_dispatch_before_customer_followup(p_job,p_config);end case;end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'automation_%' loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);end loop;end $$;
-- The asynchronous networking schema is scheduler-only, never exposed to
-- anonymous visitors, staff SQL calls or browser service-role credentials.
revoke all on schema net from public,anon,authenticated,service_role;

alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_preferences;
revoke all on function private.gama_b2b_action_before_preferences(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare cid uuid:=private.gama_b2b_customer();begin
 if p_action='preferences' then return coalesce((select jsonb_build_object('invoice_reminders',invoice_reminders,'surveys',surveys) from private.customer_message_preferences where customer_id=cid),'{"invoice_reminders":false,"surveys":false}'::jsonb);
 elsif p_action='preferences_save' then
  insert into private.customer_message_preferences(customer_id,invoice_reminders,surveys,evidence,updated_by) values(cid,coalesce((p_data->>'invoice_reminders')::boolean,false),coalesce((p_data->>'surveys')::boolean,false),'Solicitud del titular desde el portal B2B',auth.uid()) on conflict(customer_id) do update set invoice_reminders=excluded.invoice_reminders,surveys=excluded.surveys,evidence=excluded.evidence,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('saved',true);
 end if;return private.gama_b2b_action_before_preferences(p_action,p_data);end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005155700','customer_followup_flows','8cc9b41a22bb99e68f9081854c089df0477054bd2d30395764a44b7a0834b68f','8cc9b41a22bb99e68f9081854c089df0477054bd2d30395764a44b7a0834b68f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005161024_background_import_application.sql; SHA256 16215fbb06a310b1a2de9c3082511e6deb446f7d61828690e4f264bbd406359e
-- File preview and user confirmation remain explicit. Only confirmed batches
-- are queued; a periodic tick never discovers and applies unconfirmed previews.
insert into private.automation_catalog(kind,module,title,interval_minutes,delegated) values('import_apply','reports','Importaciones confirmadas en segundo plano',1440,true);
insert into private.automation_rules(kind,version,enabled) values('import_apply',1,false);
create function private.gama_import_background(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.erp_import_batches;rule private.automation_rules;job uuid;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('reports',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into batch from public.erp_import_batches where id=(p_data->>'id')::uuid;if not found then raise exception 'IMPORT_NOT_FOUND';end if;
 if p_action='queue' then
  select * into rule from private.automation_rules where kind='import_apply' order by version desc limit 1;
  if not rule.enabled or rule.executor is distinct from auth.uid() or rule.approved_until<=now() then raise exception 'IMPORT_DELEGATION_REQUIRED';end if;
  job:=private.automation_enqueue('import_apply','import-confirmed:'||batch.id||':'||rule.version,jsonb_build_object('source_hash',md5(batch.source_rows::text)),'import_batch',batch.id);
  return jsonb_build_object('id',job,'state','queued','batch_id',batch.id);
 elsif p_action='status' then return jsonb_build_object('batch',to_jsonb(batch),'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'state',j.state,'attempts',j.attempts,'result',j.result,'error_code',j.error_code) order by created_at desc),'[]') from private.automation_jobs j where j.kind='import_apply' and source_id=batch.id));
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_import_background(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_import_background(p_action,p_data)$$;
revoke all on function public.gama_import_background(text,jsonb),private.gama_import_background(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_import_background(text,jsonb),private.gama_import_background(text,jsonb) to authenticated;
create function private.automation_import_apply(p_job private.automation_jobs) returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.erp_import_batches;result jsonb;done integer;failed integer;begin
 if p_job.source_id is null then return jsonb_build_object('scanned',0);end if;
 select * into batch from public.erp_import_batches where id=p_job.source_id for update;if not found or md5(batch.source_rows::text) is distinct from p_job.payload->>'source_hash' then return jsonb_build_object('blocked',true,'reason','IMPORT_SOURCE_CHANGED');end if;
 result:=private.gama_import_batch('apply',jsonb_build_object('id',batch.id));
 select count(*) filter(where status='imported'),count(*) filter(where status='error') into done,failed from public.erp_import_rows where batch_id=batch.id;
 return jsonb_build_object('batch_id',batch.id,'imported',done,'errors',failed,'blocked',failed>0,'reason',case when failed>0 then 'IMPORT_ROWS_REQUIRE_REVIEW' end);end $$;
alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_imports;
revoke all on function private.automation_dispatch_before_imports(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_job.kind='import_apply' then return private.automation_import_apply(p_job);end if;return private.automation_dispatch_before_imports(p_job,p_config);end $$;
revoke all on function private.automation_import_apply(private.automation_jobs),private.automation_dispatch(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005161024','background_import_application','16215fbb06a310b1a2de9c3082511e6deb446f7d61828690e4f264bbd406359e','16215fbb06a310b1a2de9c3082511e6deb446f7d61828690e4f264bbd406359e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005163650_survey_feedback_cases.sql; SHA256 77400a283e54d1ed521ca016d7158571bd5df75c8d1bfc9db3f9ccc016924fd6
-- A rating is only a satisfaction signal when an administrator explicitly
-- selects that rating question. Quiz scores and anonymous replies are excluded.
insert into private.automation_catalog(kind,module,title,interval_minutes,delegated) values('survey_feedback','surveys','Satisfacción negativa a reclamación SAV',60,true);
insert into private.automation_rules(kind,version,enabled,config) values('survey_feedback',1,false,'{}');
create table private.survey_service_links(response_id uuid primary key references private.survey_responses(id),ticket_id uuid not null unique references public.service_tickets(id),created_at timestamptz not null default now());
alter table private.survey_service_links enable row level security;
revoke all on private.survey_service_links from public,anon,authenticated,service_role;
create function private.automation_survey_feedback(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid:=nullif(p_config->>'survey_id','')::uuid;qid text:=p_config->>'rating_question_id';question jsonb;row record;ticket uuid;n integer:=0;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('surveys',array['administrador']) or not private.erp_action_allowed('surveys','edit') or not private.service_access('sav') or not private.erp_action_allowed('sav','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select q into question from private.surveys s cross join jsonb_array_elements(s.questions) q where s.id=sid and not s.quiz and q->>'id'=qid and q->>'type'='rating';
 if question is null then return jsonb_build_object('blocked',true,'reason','SATISFACTION_RATING_QUESTION_REQUIRED');end if;
 for row in select r.id,r.answers->>qid rating,i.customer_id,c.name from private.survey_responses r join private.survey_invitations i on i.id=r.invitation_id and i.survey_id=r.survey_id join public.customers c on c.id=i.customer_id and c.active where r.survey_id=sid and r.answers->>qid in ('1','2') and not exists(select 1 from private.survey_service_links l where l.response_id=r.id) order by r.created_at,r.id limit 50 for update of r skip locked loop
  ticket:=private.automation_key('survey-feedback:'||row.id);
  insert into public.service_tickets(id,subject,description,customer_id,priority,category,created_by) values(ticket,'Seguimiento de satisfacción · '||row.name,'Respuesta a la pregunta '||(question->>'title')||': '||row.rating||'/5. Contactar al cliente, confirmar el motivo y acordar una resolución.',row.customer_id,'high','other',auth.uid());
  insert into private.survey_service_links(response_id,ticket_id) values(row.id,ticket);
  perform private.automation_exception('survey-feedback:'||row.id,'survey_feedback','sav','service_ticket',ticket,'CUSTOMER_SATISFACTION_FOLLOWUP',p_job.id,(select erp_reference from public.service_tickets where id=ticket));
  n:=n+1;
 end loop;return jsonb_build_object('cases_created',n);end $$;
-- Source events only enqueue when this specific versioned rule is enabled.
create function private.survey_feedback_event() returns trigger language plpgsql security definer set search_path='' as $$begin perform private.automation_enqueue('survey_feedback','survey-response:'||new.id,jsonb_build_object('response_id',new.id),'survey_response',new.id);return new;end $$;
create trigger survey_feedback_event after insert on private.survey_responses for each row execute function private.survey_feedback_event();
alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_feedback;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin if p_job.kind='survey_feedback' then return private.automation_survey_feedback(p_job,p_config);end if;return private.automation_dispatch_before_feedback(p_job,p_config);end $$;
revoke all on function private.automation_dispatch(private.automation_jobs,jsonb),private.automation_dispatch_before_feedback(private.automation_jobs,jsonb),private.automation_survey_feedback(private.automation_jobs,jsonb),private.survey_feedback_event() from public,anon,authenticated,service_role;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005163650','survey_feedback_cases','77400a283e54d1ed521ca016d7158571bd5df75c8d1bfc9db3f9ccc016924fd6','77400a283e54d1ed521ca016d7158571bd5df75c8d1bfc9db3f9ccc016924fd6','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261005164021_road_matrix_and_time_windows.sql; SHA256 ae3ba50110cdd38b05554b58f4cfaf6f5c8693861eb82be2d70ab8472ab28f7b
-- Optional fixed-endpoint ORS adapter. Until explicitly configured, planning
-- remains labelled as a straight-line estimate; it never invents road times.
create table private.tms_road_provider(id boolean primary key default true check(id),enabled boolean not null default false,profile text not null check(profile in ('driving-car','driving-hgv')),secret_id uuid not null,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index tms_road_provider_actor on private.tms_road_provider(updated_by);
create table private.tms_road_requests(id uuid primary key default gen_random_uuid(),day date not null,profile text not null,locations jsonb not null,fingerprint text not null unique,request_id bigint not null,state text not null default 'pending' check(state in ('pending','ready','failed')),error_code text,created_at timestamptz not null default now(),completed_at timestamptz);
create index tms_road_requests_pending on private.tms_road_requests(created_at) where state='pending';
create table private.tms_road_pairs(profile text not null,a_lat numeric not null,a_lng numeric not null,b_lat numeric not null,b_lng numeric not null,km double precision not null check(km>=0 and km<=20000),seconds double precision not null check(seconds>=0 and seconds<=604800),measured_at timestamptz not null default now(),primary key(profile,a_lat,a_lng,b_lat,b_lng));
do $$declare t text;begin foreach t in array array['tms_road_provider','tms_road_requests','tms_road_pairs'] loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end $$;
create function private.tms_road_metric(a double precision,b double precision,c double precision,d double precision) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('km',p.km,'seconds',p.seconds,'measured_at',p.measured_at,'profile',p.profile) from private.tms_road_pairs p join private.tms_road_provider conf on conf.id and conf.enabled and conf.profile=p.profile where p.a_lat=round(a::numeric,6) and p.a_lng=round(b::numeric,6) and p.b_lat=round(c::numeric,6) and p.b_lng=round(d::numeric,6) and p.measured_at>now()-interval '14 days'$$;
create function private.tms_air_distance(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable set search_path='' as $$select 6371*2*asin(least(1.0,sqrt(power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))$$;
create or replace function private.tms_distance(a double precision,b double precision,c double precision,d double precision) returns double precision language sql stable security definer set search_path='' as $$select coalesce((private.tms_road_metric(a,b,c,d)->>'km')::double precision,private.tms_air_distance(a,b,c,d))$$;
create function private.tms_road_prepare(p_day date) returns jsonb language plpgsql security definer set search_path='' as $$
declare conf private.tms_road_provider;loc jsonb;count integer;hash text;key text;req bigint;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_day is null or p_day<(now() at time zone private.erp_timezone())::date or p_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 select * into conf from private.tms_road_provider where id and enabled;if not found then return jsonb_build_object('configured',false);end if;
 select coalesce(jsonb_agg(jsonb_build_array(lng,lat) order by lat,lng),'[]') into loc from(select distinct round(lat::numeric,6) lat,round(lng::numeric,6) lng from(select d.lat,d.lng from public.tms_deliveries d where d.delivery_date=p_day and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') union all select depot_lat,depot_lng from public.tms_settings) z where lat between -85 and 85 and lng between -180 and 180)z;
 count:=jsonb_array_length(loc);if count<2 then return jsonb_build_object('locations',count);end if;
 if count>50 then return jsonb_build_object('blocked',true,'reason','ROAD_MATRIX_LOCATION_LIMIT','locations',count);end if;
 hash:=md5(jsonb_build_array(conf.profile,loc,(now() at time zone private.erp_timezone())::date::text)::text);
 -- The daily fingerprint bounds provider costs and repeated screen/job requests.
 if exists(select 1 from private.tms_road_requests where fingerprint=hash) then return jsonb_build_object('existing',true,'locations',count);end if;
 if exists(select 1 from private.tms_road_requests where created_at>now()-interval '1 minute') then return jsonb_build_object('rate_limited',true);end if;
 select decrypted_secret into key from vault.decrypted_secrets where id=conf.secret_id;if nullif(key,'') is null then return jsonb_build_object('configured',false);end if;
 req:=net.http_post(url:='https://api.openrouteservice.org/v2/matrix/'||conf.profile,headers:=jsonb_build_object('Authorization',key,'Content-Type','application/json'),body:=jsonb_build_object('locations',loc,'metrics',jsonb_build_array('distance','duration'),'units','km'),timeout_milliseconds:=20000);
 insert into private.tms_road_requests(day,profile,locations,fingerprint,request_id) values(p_day,conf.profile,loc,hash,req);return jsonb_build_object('queued',true,'locations',count);end $$;
create function private.tms_road_poll() returns jsonb language plpgsql security definer set search_path='' as $$
declare req private.tms_road_requests;response record;payload jsonb;size integer;i integer;j integer;km double precision;seconds double precision;n integer:=0;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-road-matrix',0)) then return jsonb_build_object('busy',true);end if;
 for req in select * from private.tms_road_requests where state='pending' order by created_at,id limit 3 for update skip locked loop
  select * into response from net._http_response where id=req.request_id;
  if not found and req.created_at>now()-interval '5 minutes' then continue;end if;
  begin
   if not found or response.status_code<>200 or response.timed_out then raise exception 'ROAD_PROVIDER_UNAVAILABLE';end if;
   if octet_length(response.content)>2097152 then raise exception 'ROAD_RESPONSE_INVALID';end if;
   payload:=response.content::jsonb;size:=jsonb_array_length(req.locations);
   if jsonb_typeof(payload->'distances') is distinct from 'array' or jsonb_typeof(payload->'durations') is distinct from 'array' or jsonb_array_length(payload->'distances')<>size or jsonb_array_length(payload->'durations')<>size then raise exception 'ROAD_RESPONSE_INVALID';end if;
   for i in 0..size-1 loop
    if jsonb_typeof(payload->'distances'->i) is distinct from 'array' or jsonb_typeof(payload->'durations'->i) is distinct from 'array' or jsonb_array_length(payload->'distances'->i)<>size or jsonb_array_length(payload->'durations'->i)<>size then raise exception 'ROAD_RESPONSE_INVALID';end if;
    for j in 0..size-1 loop
     if payload->'distances'->i->j='null'::jsonb or payload->'durations'->i->j='null'::jsonb then continue;end if;
     if jsonb_typeof(payload->'distances'->i->j)<>'number' or jsonb_typeof(payload->'durations'->i->j)<>'number' then raise exception 'ROAD_RESPONSE_INVALID';end if;
     km:=(payload->'distances'->i->>j)::double precision;seconds:=(payload->'durations'->i->>j)::double precision;
     if km not between 0 and 20000 or seconds not between 0 and 604800 then raise exception 'ROAD_RESPONSE_INVALID';end if;
     insert into private.tms_road_pairs(profile,a_lat,a_lng,b_lat,b_lng,km,seconds) values(req.profile,(req.locations->i->>1)::numeric,(req.locations->i->>0)::numeric,(req.locations->j->>1)::numeric,(req.locations->j->>0)::numeric,km,seconds) on conflict(profile,a_lat,a_lng,b_lat,b_lng) do update set km=excluded.km,seconds=excluded.seconds,measured_at=now();
    end loop;
   end loop;
   update private.tms_road_requests set state='ready',completed_at=now() where id=req.id;
   delete from private.tms_day_plans where day=req.day;n:=n+1;
  exception when others then update private.tms_road_requests set state='failed',error_code=case when sqlerrm='ROAD_PROVIDER_UNAVAILABLE' then sqlerrm else 'ROAD_RESPONSE_INVALID' end,completed_at=now() where id=req.id;end;
 end loop;return jsonb_build_object('matrices_ready',n);end $$;
create function private.gama_tms_roads(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare conf private.tms_road_provider;secret uuid;route public.tms_routes;stop_id text;lat double precision;lng double precision;prev_lat double precision;prev_lng double precision;metric jsonb;legs jsonb:='[]';service integer;missing integer:=0;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('configure','disable','context') then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='context' then return jsonb_build_object('provider',(select jsonb_build_object('enabled',enabled,'profile',profile,'configured',true) from private.tms_road_provider where id),'requests',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from(select day,profile,state,error_code,created_at,completed_at from private.tms_road_requests order by created_at desc limit 30)r));end if;
  if not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='disable' then update private.tms_road_provider set enabled=false,updated_by=auth.uid(),updated_at=now();return jsonb_build_object('enabled',false);end if;
  if coalesce(p_data->>'profile','') not in ('driving-car','driving-hgv') or length(coalesce(p_data->>'api_key','')) not between 10 and 300 then raise exception 'ROAD_PROVIDER_CONFIG_REQUIRED';end if;
  select * into conf from private.tms_road_provider where id for update;if conf.secret_id is null then secret:=vault.create_secret(p_data->>'api_key','coco_road_provider');else secret:=conf.secret_id;perform vault.update_secret(secret,p_data->>'api_key');end if;
  insert into private.tms_road_provider(id,enabled,profile,secret_id,updated_by) values(true,coalesce((p_data->>'enabled')::boolean,false),p_data->>'profile',secret,auth.uid()) on conflict(id) do update set enabled=excluded.enabled,profile=excluded.profile,secret_id=excluded.secret_id,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('configured',true);
 elsif p_action='prepare' then return private.tms_road_prepare((p_data->>'day')::date);
 elsif p_action='route' then
  select * into route from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
  for stop_id in select jsonb_array_elements_text(route.stops) loop
   service:=0;if stop_id='__depot' then select depot_lat,depot_lng into lat,lng from public.tms_settings limit 1;else select d.lat,d.lng,d.service_minutes into lat,lng,service from public.tms_deliveries d where d.id::text=stop_id and d.route_id=route.id;end if;
   if prev_lat is null and legs='[]' and stop_id='__depot' then metric:=jsonb_build_object('km',0,'seconds',0);else metric:=private.tms_road_metric(prev_lat,prev_lng,lat,lng);end if;
   if metric is null then missing:=missing+1;end if;
   legs:=legs||jsonb_build_array(jsonb_build_object('id',stop_id,'road_km',metric->'km','drive_minutes',ceil((metric->>'seconds')::numeric/60),'service_minutes',coalesce(service,0),'source','openrouteservice','measured_at',metric->'measured_at'));prev_lat:=lat;prev_lng:=lng;
  end loop;return jsonb_build_object('legs',legs,'missing',missing,'source','openrouteservice');
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_tms_roads(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_roads(p_action,p_data)$$;
revoke all on function public.gama_tms_roads(text,jsonb),private.gama_tms_roads(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_tms_roads(text,jsonb),private.gama_tms_roads(text,jsonb) to authenticated;
alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_roads;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if p_job.kind='tms_planning' then perform private.tms_road_poll();result:=private.tms_road_prepare(coalesce(nullif(p_job.payload->>'day','')::date,(now() at time zone private.erp_timezone())::date));end if;
 return private.automation_dispatch_before_roads(p_job,p_config)||case when result is null then '{}'::jsonb else jsonb_build_object('road_matrix',result) end;end $$;
select cron.schedule('coco-road-matrix','* * * * *','select private.tms_road_poll()');
do $$declare fn record;begin for fn in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'tms_road_%' or p.proname in ('tms_air_distance','tms_distance','automation_dispatch','automation_dispatch_before_roads')) loop execute format('revoke all on function %s from public,anon,authenticated,service_role',fn.sig);end loop;end $$;

alter table public.tms_routes add column distance_basis text not null default 'air' check(distance_basis in ('air','mixed','road','road_verified'));
alter table public.tms_route_schedules add column window_exceptions jsonb not null default '[]';
-- Scheduling accounts for waiting, service and a delivery's requested window.
-- A late/ambiguous window needs a recorded human decision; departure stays manual.
create or replace function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes integer:=0;km numeric:=0;n integer:=0;travel integer;service integer;waiting integer;arrival timestamptz;start_window timestamptz;end_window timestamptz;delivery public.tms_deliveries;match text[];warnings jsonb:='[]';row public.tms_route_schedules;reason text:=btrim(coalesce(p_data->>'window_exception_reason',''));begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.route_id=r.id order by d.id for update;
 select * into r from public.tms_routes where id=r.id for update;
 if r.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id and s.departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
 if stamp is null or (stamp at time zone private.erp_timezone())::date<>r.route_date or jsonb_typeof(p_data->'legs') is distinct from 'array' or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 if length(btrim(coalesce(p_data->>'road_source','')))<3 then raise exception 'ROAD_SOURCE_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
  if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
  travel:=(x->>'drive_minutes')::integer;service:=(x->>'service_minutes')::integer;
  if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric not between 0 and 20000 then raise exception 'ROUTE_TIME_REQUIRED';end if;
  minutes:=minutes+travel;km:=km+(x->>'road_km')::numeric;arrival:=stamp+make_interval(mins=>minutes);waiting:=0;
  if x->>'id'<>'__depot' then
   select * into delivery from public.tms_deliveries where id::text=x->>'id' and route_id=r.id;if not found then raise exception 'ROUTE_LEGS_CHANGED';end if;
   if nullif(btrim(delivery.time_window),'') is not null then
    match:=regexp_match(delivery.time_window,'^\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*[-–]\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*$');
    if match is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_REVIEW_REQUIRED','window',delivery.time_window));
    else
     start_window:=(r.route_date+match[1]::time) at time zone private.erp_timezone();end_window:=(r.route_date+match[2]::time) at time zone private.erp_timezone();if end_window<start_window then end_window:=end_window+interval '1 day';end if;
     if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::integer;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
     if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
    end if;
   end if;
   update public.tms_deliveries set eta_at=arrival,service_minutes=service where id=delivery.id;
  end if;
  legs:=legs||jsonb_build_array(x||jsonb_build_object('waiting_minutes',waiting,'arrival_at',arrival,'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;
 end loop;
 if warnings<>'[]' and length(reason)<3 then raise exception 'TIME_WINDOW_EXCEPTION_REASON_REQUIRED';end if;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes,window_exceptions) values(r.id,stamp,legs,p_data->>'road_source',km,minutes,jsonb_build_object('warnings',warnings,'review_reason',reason)) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,window_exceptions=excluded.window_exceptions,updated_by=auth.uid(),updated_at=now() returning * into row;
 update public.tms_routes set distance=km,distance_basis='road_verified' where id=r.id;
 return to_jsonb(row);end $$;
revoke all on function private.gama_route_schedule(jsonb) from public,anon,service_role;
grant execute on function private.gama_route_schedule(jsonb) to authenticated;

-- Same canonical planner and departure locks; only its metric and provenance change.
CREATE OR REPLACE FUNCTION private.gama_tms_plan_day(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 planning_day date:=p_day;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 road_count integer;leg_count integer;road_metric jsonb;depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if planning_day is null or planning_day<(now() at time zone private.erp_timezone())::date or planning_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(planning_day-date '2000-01-01')::integer);
 -- Same row-lock order as departure: shipment, delivery, route.
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=planning_day order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.delivery_date=planning_day order by d.id for update;
 perform r.id from public.tms_routes r where r.route_date=planning_day order by r.id for update;
 update public.tms_deliveries d set lat=c.lat,lng=c.lng from public.customers c where d.customer_id=c.id and d.delivery_date=planning_day and d.lat is null and d.lng is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and c.lat is not null and lower(btrim(d.address))=lower(btrim(c.gps_address));
 select coalesce(array_agg(r.id),'{}') into locked from public.tms_routes r where
 r.manual_override or r.status in ('En ruta','En tránsito','Terminada','Cancelada')
 or exists(select 1 from public.tms_route_schedules ts where ts.route_id=r.id)
 or exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not exists(select 1 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id where d.id::text=sid and d.delivery_date=planning_day and o.status='confirmed' and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')))
 or exists(select 1 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id
  where (d.route_id=r.id or r.stops ? d.id::text) and (s.departed_at is not null or d.status in ('En carga','En tránsito','En ruta','Entregada')));
 select coalesce(jsonb_agg(d.id order by d.id),'[]') into origin_ids from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=planning_day;
 select coalesce(array_agg(d.id order by d.id),'{}') into eligible
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id
 where d.delivery_date=planning_day and o.status='confirmed' and s.departed_at is null
 and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and not(coalesce(d.route_id,'00000000-0000-0000-0000-000000000000')=any(locked));
 select * into settings from public.tms_settings limit 1;
 depot_ok:=coalesce(settings.depot_lat between -85 and 85 and settings.depot_lng between -180 and 180,false);
 resources:=private.gama_tms_resources();
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings),'roads',(select max(measured_at) from private.tms_road_pairs),'road_provider',(select jsonb_build_array(enabled,profile) from private.tms_road_provider where id))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180);
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  w:=0;v:=0;km:=0;road_count:=0;leg_count:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and (coalesce((dr->>'max_volume')::numeric,0)<=0 or v+d.volume<=(dr->>'max_volume')::numeric)
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);leg_count:=leg_count+1;road_metric:=private.tms_road_metric(cur_lat,cur_lng,stop.lat,stop.lng);if road_metric is not null then road_count:=road_count+1;end if;end if;
   cur_lat:=stop.lat;cur_lng:=stop.lng;w:=w+stop.weight;v:=v+stop.volume;
   stops:=stops||jsonb_build_array(stop.id);remaining:=array_remove(remaining,stop.id);
  end loop;
  if jsonb_array_length(stops)>(case when depot_ok then 1 else 0 end) then
   if depot_ok and settings.return_depot then km:=km+private.tms_distance(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng);leg_count:=leg_count+1;if private.tms_road_metric(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng) is not null then road_count:=road_count+1;end if;stops:=stops||jsonb_build_array('__depot');end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)
    values(planning_day,(dr->>'driver_id')::uuid,dr->>'name',dr->>'plate',(dr->>'vehicle_id')::uuid,stops,km,w,v,'Planificada',case when road_count=0 then 'air' when road_count=leg_count and depot_ok then 'road' else 'mixed' end) returning id into route_uuid;
   update public.tms_deliveries d set route_id=route_uuid,driver_id=(dr->>'driver_id')::uuid,status=case when d.status='Lista para envío' then d.status else 'Planificada' end
    where stops ? d.id::text;
   planned_count:=planned_count+jsonb_array_length(stops)-(case when depot_ok then 1 else 0 end)-(case when depot_ok and settings.return_depot then 1 else 0 end);
   route_count:=route_count+1;vehicle_ids:=array_append(vehicle_ids,(dr->>'vehicle_id')::uuid);
  end if;
 end loop;
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 summary:=jsonb_build_object('today',planning_day,'changed',true,'routes',route_count,'total',cardinality(eligible),'planned',planned_count,
  'unplanned',cardinality(eligible)-planned_count,'without_coordinates',jsonb_array_length(geocode_ids),'without_capacity',cardinality(remaining),
  'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $function$
;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261005164021','road_matrix_and_time_windows','ae3ba50110cdd38b05554b58f4cfaf6f5c8693861eb82be2d70ab8472ab28f7b','ae3ba50110cdd38b05554b58f4cfaf6f5c8693861eb82be2d70ab8472ab28f7b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
