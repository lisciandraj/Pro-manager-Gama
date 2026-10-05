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
