-- New document families have their own immutable snapshots and legal series.
-- The existing 01 workflow and every existing fiscal number remain unchanged.
create table private.sri_document_sequences (
 environment text not null, issuer_ruc text not null, establishment text not null,
 emission_point text not null, document_type text not null, last_value integer not null check(last_value between 1 and 999999999),
 primary key(environment,issuer_ruc,establishment,emission_point,document_type)
);
alter table private.sri_document_sequences enable row level security;
revoke all on private.sri_document_sequences from public,anon,authenticated;

create table public.sri_document_issues (
 id uuid primary key default gen_random_uuid(), document_type text not null check(document_type in ('03','04','06','07')),
 source_type text not null check(source_type in ('return_credit','supplier_invoice','tms_route')),source_id uuid not null,
 customer_id uuid references public.customers(id),supplier_id uuid references public.suppliers(id),route_id uuid references public.tms_routes(id),
 environment text not null check(environment in ('pruebas','produccion')),issuer_ruc text not null check(issuer_ruc ~ '^[0-9]{13}$'),
 establishment text not null check(establishment ~ '^[0-9]{3}$'),emission_point text not null check(emission_point ~ '^[0-9]{3}$'),
 sequential text not null check(sequential ~ '^[0-9]{9}$'),numeric_code text not null default lpad(floor(random()*100000000)::bigint::text,8,'0') check(numeric_code ~ '^[0-9]{8}$'),
 access_key text unique check(access_key ~ '^[0-9]{49}$'),status text not null default 'draft' check(status in ('draft','signed','received','processing','authorized','rejected','error')),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),receipt jsonb,authorization_response jsonb,
 signed_xml_path text,authorized_xml_path text,ride_path text,sent_at timestamptz,authorized_at timestamptz,delivered_at timestamptz,last_error text,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(source_type,source_id,document_type),unique(environment,issuer_ruc,establishment,emission_point,document_type,sequential),
 check((document_type='04' and source_type='return_credit' and customer_id is not null) or
       (document_type in ('03','07') and source_type='supplier_invoice' and supplier_id is not null) or
       (document_type='06' and source_type='tms_route' and route_id=source_id))
);
create index sri_document_pending on public.sri_document_issues(status,updated_at) where status in ('draft','signed','received','processing');
create index sri_document_customer on public.sri_document_issues(customer_id) where customer_id is not null;
create index sri_document_supplier on public.sri_document_issues(supplier_id) where supplier_id is not null;
create index sri_document_route on public.sri_document_issues(route_id) where route_id is not null;
create index sri_document_author on public.sri_document_issues(created_by);

create function private.gama_sri_own_route(p_route uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and private.erp_module_allowed('tms',array['administrador','almacenero']) and exists(
 select 1 from public.tms_routes r join public.fleet_drivers f on f.id=r.driver_id join public.hr_employees e on e.id=f.employee_id
 where r.id=p_route and f.active and e.active and e.profile_id=auth.uid())
$$;
revoke all on function private.gama_sri_own_route(uuid) from public,anon;
grant execute on function private.gama_sri_own_route(uuid) to authenticated;
alter table public.sri_document_issues enable row level security;
revoke all on public.sri_document_issues from public,anon,authenticated;
grant select on public.sri_document_issues to authenticated;
grant all on public.sri_document_issues to service_role;
create policy sri_document_read on public.sri_document_issues for select to authenticated using(
 private.erp_module_allowed('accounting',array['administrador']) or
 (document_type='06' and (private.gama_sri_own_route(route_id) or
 (private.current_user_role()='administrador' and private.erp_module_allowed('tms',array['administrador'])))));

create function private.gama_sri_document_access(p_id uuid,p_action text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.sri_document_issues;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into d from public.sri_document_issues where id=p_id;if not found then raise exception 'NOT_FOUND';end if;
 if private.current_user_role()='administrador' and private.erp_module_allowed('accounting',array['administrador']) then
 return jsonb_build_object('validate',private.erp_action_allowed('accounting','validate'),'export',private.erp_action_allowed('accounting','export'));
 end if;
 if d.document_type='06' and private.current_user_role()='administrador' and private.erp_module_allowed('tms',array['administrador']) then
 return jsonb_build_object('validate',private.erp_action_allowed('tms','validate'),'export',private.erp_action_allowed('tms','export'));end if;
 if p_action='download' and d.document_type='06' and d.status='authorized' and private.gama_sri_own_route(d.route_id) then
 return jsonb_build_object('validate',false,'export',true);end if;
 raise exception 'ROLE_NOT_ALLOWED';end $$;
revoke all on function private.gama_sri_document_access(uuid,text) from public,anon;
grant execute on function private.gama_sri_document_access(uuid,text) to authenticated;
create function public.gama_sri_document_access(p_id uuid,p_action text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_sri_document_access(p_id,p_action)$$;
revoke all on function public.gama_sri_document_access(uuid,text) from public,anon;
grant execute on function public.gama_sri_document_access(uuid,text) to authenticated;

-- Internal helper: a browser cannot supply an issuer, fiscal sequence, status or authorization.
create function private.gama_sri_new_document(p_type text,p_source text,p_id uuid,p_snapshot jsonb,p_customer uuid default null,p_supplier uuid default null,p_route uuid default null)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings;s public.sri_settings;d public.sri_document_issues;n integer;begin
 select * into cfg from public.company_settings where id;
 select * into s from public.sri_settings where user_id=auth.uid();
 if not coalesce(cfg.configured,false) or cfg.country<>'EC' or s.id is null or s.ruc<>cfg.tax_id or s.accounting_obligation is null
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE';end if;
 perform pg_advisory_xact_lock(hashtextextended('sri-source:'||p_source||':'||p_id||':'||p_type,0));
 select * into d from public.sri_document_issues where source_type=p_source and source_id=p_id and document_type=p_type;
 if found then return jsonb_build_object('id',d.id,'status',d.status,'document_type',d.document_type);end if;
 insert into private.sri_document_sequences(environment,issuer_ruc,establishment,emission_point,document_type,last_value)
 values(s.environment,s.ruc,s.estab,s.pto_emi,p_type,1)
 on conflict(environment,issuer_ruc,establishment,emission_point,document_type) do update set last_value=private.sri_document_sequences.last_value+1
 returning last_value into n;
 insert into public.sri_document_issues(document_type,source_type,source_id,customer_id,supplier_id,route_id,environment,issuer_ruc,establishment,emission_point,sequential,created_by,snapshot)
 values(p_type,p_source,p_id,p_customer,p_supplier,p_route,s.environment,s.ruc,s.estab,s.pto_emi,lpad(n::text,9,'0'),auth.uid(),
 p_snapshot||jsonb_build_object('issuer',s.razon_social,'address',s.dir_matriz,'provider_ruc',s.provider_ruc,
 'accounting_obligation',s.accounting_obligation,'trade_name',s.trade_name,'establishment_address',s.establishment_address)) returning * into d;
 return jsonb_build_object('id',d.id,'status',d.status,'document_type',d.document_type);
end $$;
revoke all on function private.gama_sri_new_document(text,text,uuid,jsonb,uuid,uuid,uuid) from public,anon,authenticated;


create function private.gama_sri_authorized_invoice(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.external_invoices v where v.id=p_id and v.fiscal_status<>'cancelled' and
 ((v.document_kind='external' and v.fiscal_status='authorized') or
 (v.document_kind='internal' and v.external_status='authorized' and exists(select 1 from public.sri_invoice_issues z where z.source_invoice_id=v.id and z.status='authorized' and z.access_key=v.access_key))))
$$;
revoke all on function private.gama_sri_authorized_invoice(uuid) from public,anon,authenticated;

create function private.gama_sri_credit_note(p_credit uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.return_credits;r public.return_orders;v public.external_invoices;k public.customers;f public.accounting_fiscal_documents;
 lines jsonb;net numeric;tax numeric;number text;issued date;begin
 select * into c from public.return_credits where id=p_credit for update;
 select * into r from public.return_orders where id=c.return_id;
 select * into v from public.external_invoices where id=c.invoice_id;
 select * into k from public.customers where id=r.customer_id;
 select * into f from public.accounting_fiscal_documents where source_type='sales_invoice' and source_id=v.id;
 number:=coalesce(v.external_number,case when v.document_kind='external' then v.number end,f.document_number);issued:=coalesce(v.external_issue_date,v.issue_date);
 if c.id is null or r.kind<>'customer' or r.status in ('cancelled','to_process') or not private.gama_sri_authorized_invoice(v.id)
 or number !~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$' or number is null then raise exception 'SRI_AUTHORIZED_INVOICE_REQUIRED';end if;
 if k.identification !~ '^([0-9]{10}|[0-9]{13})$' or k.identification is null then raise exception 'SRI_CUSTOMER_INCOMPLETE';end if;
 select jsonb_agg(jsonb_build_object('code',p.reference,'description',p.name,'quantity',l.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate,'subtotal',round(l.quantity*l.unit_price,2)) order by l.id),
 sum(round(l.quantity*l.unit_price,2)),sum(round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) into lines,net,tax
 from public.return_lines l join public.products p on p.id=l.product_id where l.return_id=r.id;
 if lines is null or net+tax<>c.amount then raise exception 'SRI_CREDIT_LINES_MISMATCH';end if;
 if exists(select 1 from public.return_credits where return_id=r.id and id<>c.id) then raise exception 'SRI_CREDIT_ALREADY_EXISTS';end if;
 return private.gama_sri_new_document('04','return_credit',c.id,jsonb_build_object('issue_date',c.issued_on,'source_number',coalesce(c.erp_reference,c.number),
 'customer',k.name,'identification',k.identification,'customer_address',k.address,'customer_email',k.email,
 'support_number',number,'support_date',issued,'support_authorization',v.access_key,'reason',coalesce(nullif(c.notes,''),r.reason,'Devolución de mercadería'),
 'subtotal',net,'tax',tax,'total',c.amount,'lines',lines),k.id);
end $$;
revoke all on function private.gama_sri_credit_note(uuid) from public,anon,authenticated;

create table public.supplier_withholding_policies (
 supplier_id uuid primary key references public.suppliers(id),income_code text check(income_code ~ '^[0-9]{1,5}$'),
 income_rate numeric(7,4) not null check(income_rate between 0 and 100),income_account_id uuid references public.accounting_accounts(id),
 vat_code text check(vat_code ~ '^[0-9]{1,5}$'),vat_rate numeric(7,4) not null check(vat_rate between 0 and 100),vat_account_id uuid references public.accounting_accounts(id),
 valid_from date not null,valid_to date,evidence text not null check(length(btrim(evidence))>=10),
 reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default now(),
 check(valid_to is null or valid_to>=valid_from),check(income_rate=0 or (income_code is not null and income_account_id is not null)),
 check(vat_rate=0 or (vat_code is not null and vat_account_id is not null))
);
alter table public.supplier_withholding_policies enable row level security;
revoke all on public.supplier_withholding_policies from public,anon,authenticated;
grant select on public.supplier_withholding_policies to authenticated;
create policy supplier_withholding_read on public.supplier_withholding_policies for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create table public.sri_purchase_queue (
 supplier_invoice_id uuid primary key references public.supplier_invoices(id),created_at timestamptz not null default now(),
 issue_id uuid references public.sri_document_issues(id),last_error text
);
alter table public.sri_purchase_queue enable row level security;
revoke all on public.sri_purchase_queue from public,anon,authenticated;
grant select on public.sri_purchase_queue to authenticated;
create policy sri_purchase_queue_read on public.sri_purchase_queue for select to authenticated using(private.erp_module_allowed('accounting',array['administrador']));
create index sri_purchase_queue_issue on public.sri_purchase_queue(issue_id) where issue_id is not null;

create function private.gama_sri_purchase_queued() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='posted' and (tg_op='INSERT' or old.status is distinct from new.status)
 and exists(select 1 from public.company_settings c join public.accounting_ec_profile p on p.id=c.id where c.country='EC' and p.withholding_agent and p.confirmed_on is not null)
 then insert into public.sri_purchase_queue(supplier_invoice_id) values(new.id) on conflict do nothing;end if;
 return new;end $$;
revoke all on function private.gama_sri_purchase_queued() from public,anon,authenticated;
create trigger sri_purchase_queued after insert or update of status on public.supplier_invoices for each row execute function private.gama_sri_purchase_queued();

create function private.gama_sri_purchase_document(p_invoice uuid,p_type text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.supplier_invoices;k public.suppliers;f public.accounting_fiscal_documents;p public.supplier_withholding_policies;prof public.accounting_ec_profile;
 snapshot jsonb;lines jsonb:='[]';withheld jsonb:='[]';net numeric:=0;tax numeric:=0;rate numeric;total numeric:=0;row jsonb;issued date:=coalesce(nullif(p_data->>'issue_date','')::date,(now() at time zone private.erp_timezone())::date);result jsonb;
begin
 select * into v from public.supplier_invoices where id=p_invoice for update;
 select * into k from public.suppliers where id=v.supplier_id;
 if v.id is null or v.status<>'posted' or k.tax_id is null or k.tax_id !~ '^([0-9]{10}|[0-9]{13})$' or coalesce(btrim(k.address),'')='' then raise exception 'SRI_SUPPLIER_INCOMPLETE';end if;
 if issued<v.issue_date then raise exception 'SRI_INVALID_DATE';end if;
 if p_type='07' then
 select * into prof from public.accounting_ec_profile where id;
 if prof.withholding_agent is distinct from true or prof.confirmed_on is null then raise exception 'SRI_WITHHOLDING_AGENT_REQUIRED';end if;
 select * into p from public.supplier_withholding_policies where supplier_id=k.id and valid_from<=v.issue_date and (valid_to is null or valid_to>=v.issue_date);
 if p.supplier_id is null then raise exception 'SRI_SUPPLIER_POLICY_REQUIRED';end if;
 select * into f from public.accounting_fiscal_documents where source_type='supplier_invoice' and source_id=v.id;
 if f.id is null or f.identification<>k.tax_id or f.base_zero+f.base_taxed<>v.subtotal or f.vat<>v.tax or f.base_exempt<>0 or f.base_non_taxable<>0 or f.ice<>0 or f.related_party
 then raise exception 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED';end if;
 if f.base_zero>0 then lines:=lines||jsonb_build_array(jsonb_build_object('code','BASE-0','description','Base IVA 0 de la factura proveedor','quantity',1,'unit_price',f.base_zero,'tax_rate',0,'subtotal',f.base_zero));end if;
 if f.base_taxed>0 then
 select t.rate into rate from public.accounting_taxes t where t.id=v.tax_id and t.active;
 if rate is null or rate not in (5,12,13,14,15) or round(f.base_taxed*rate/100,2)<>f.vat then raise exception 'SRI_PURCHASE_TAX_RATE_REQUIRED';end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('code','BASE-IVA','description','Base IVA de la factura proveedor','quantity',1,'unit_price',f.base_taxed,'tax_rate',rate,'subtotal',f.base_taxed));end if;
 if p.income_rate>0 and v.subtotal>0 then
 total:=round(v.subtotal*p.income_rate/100,2);
 withheld:=withheld||jsonb_build_array(jsonb_build_object('tax_kind','IR','code',p.income_code,'base',v.subtotal,'rate',p.income_rate,'amount',total,'account_id',p.income_account_id));end if;
 if p.vat_rate>0 and v.tax>0 then
 total:=total+round(v.tax*p.vat_rate/100,2);
 withheld:=withheld||jsonb_build_array(jsonb_build_object('tax_kind','IVA','code',p.vat_code,'base',v.tax,'rate',p.vat_rate,'amount',round(v.tax*p.vat_rate/100,2),'account_id',p.vat_account_id));end if;
 if total<=0 then raise exception 'SRI_WITHHOLDING_NOT_APPLICABLE';end if;
 snapshot:=jsonb_build_object('support_number',f.document_number,'support_date',v.issue_date,'support_authorization',f.authorization_number,
 'support_code',f.support_code,'support_document_type',f.document_type,'related_party',false,'withholdings',withheld,'withheld_total',total,
 'payment_code',f.payment_codes->>0,'policy_evidence',p.evidence,'policy_reviewed_at',p.reviewed_at);
 else
 if p_type<>'03' or length(k.tax_id)<>10 then raise exception 'SRI_LIQUIDATION_REQUIRES_NO_RUC';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 200 then raise exception 'SRI_LINES_MISSING';end if;
 for row in select value from jsonb_array_elements(p_data->'lines') loop
 if row->>'quantity' is null or row->>'unit_price' is null or row->>'tax_rate' is null or coalesce(btrim(row->>'code'),'')='' or (row->>'quantity')::numeric<=0 or (row->>'unit_price')::numeric<0 or (row->>'tax_rate')::numeric not in (0,5,12,13,14,15) or coalesce(btrim(row->>'description'),'')='' then raise exception 'SRI_INVALID_LINES';end if;
 net:=net+round((row->>'quantity')::numeric*(row->>'unit_price')::numeric,2);
 tax:=tax+round(round((row->>'quantity')::numeric*(row->>'unit_price')::numeric,2)*(row->>'tax_rate')::numeric/100,2);
 lines:=lines||jsonb_build_array(jsonb_build_object('code',row->>'code','description',row->>'description','quantity',(row->>'quantity')::numeric,'unit_price',(row->>'unit_price')::numeric,'tax_rate',(row->>'tax_rate')::numeric));end loop;
 if net<>v.subtotal or tax<>v.tax then raise exception 'SRI_TOTAL_MISMATCH';end if;
 if p_data->>'payment_code' not in ('01','16','19','20') or p_data->>'payment_code' is null then raise exception 'SRI_PAYMENT_CODE_REQUIRED';end if;
 snapshot:=jsonb_build_object('payment_code',p_data->>'payment_code');
 end if;
 result:=private.gama_sri_new_document(p_type,'supplier_invoice',v.id,snapshot||jsonb_build_object('issue_date',issued,'source_number',v.number,
 'customer',k.name,'identification',k.tax_id,'customer_address',k.address,'customer_email',k.email,'subtotal',v.subtotal,'tax',v.tax,'total',v.total,'lines',lines),null,k.id);
 if p_type='07' then update public.sri_purchase_queue set issue_id=(result->>'id')::uuid,last_error=null where supplier_invoice_id=v.id;end if;
 return result;
end $$;
revoke all on function private.gama_sri_purchase_document(uuid,text,jsonb) from public,anon,authenticated;

create function private.gama_sri_route_guide(p_route uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;f public.fleet_drivers;h public.hr_employees;v public.fleet_vehicles;
 d public.tms_deliveries;k public.customers;s public.sales_deliveries;i public.external_invoices;
 stop text;lines jsonb;recipients jsonb:='[]';snapshot jsonb;carrier text;finish date;
begin
 select * into r from public.tms_routes where id=p_route for update;
 if r.id is null or r.status in ('Cancelada','Terminada','En ruta','En tránsito') then raise exception 'SRI_ROUTE_MUST_BE_PREPARED';end if;
 select * into f from public.fleet_drivers where id=r.driver_id and active;
 select * into h from public.hr_employees where id=f.employee_id and active;
 select * into v from public.fleet_vehicles where id=r.vehicle_id;
 carrier:=coalesce(nullif(p_data->>'carrier_identification',''),(select identification from public.hr_employee_private where employee_id=h.id));
 finish:=coalesce(nullif(p_data->>'transport_end','')::date,r.route_date);
 if carrier is null or carrier !~ '^([0-9]{10}|[0-9]{13})$' or f.id is null or v.id is null or coalesce(v.plate,'')='' or finish<r.route_date
 or coalesce(btrim(p_data->>'departure_address'),'')='' then raise exception 'SRI_ROUTE_FISCAL_DATA_REQUIRED';end if;
 for stop in select value from jsonb_array_elements_text(r.stops) loop
 if stop='__depot' then continue;end if;
 select * into d from public.tms_deliveries where id=stop::uuid and route_id=r.id and status<>'Cancelada';
 select * into k from public.customers where id=d.customer_id;
 select * into s from public.sales_deliveries where tms_delivery_id=d.id;
 if d.id is null or s.id is null or k.identification is null or k.identification !~ '^([0-9]{10}|[0-9]{13})$' then raise exception 'SRI_ROUTE_RECIPIENT_INCOMPLETE';end if;
 select jsonb_agg(jsonb_build_object('code',ol.reference,'description',ol.product_name,'quantity',l.quantity) order by l.id) into lines
 from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id where l.delivery_id=s.id;
 if lines is null then raise exception 'SRI_LINES_MISSING';end if;
 snapshot:=jsonb_build_object('identification',k.identification,'customer',k.name,'address',d.address,'reason','Venta de mercadería','lines',lines);
 select * into i from public.external_invoices where order_id=s.order_id and private.gama_sri_authorized_invoice(id) and coalesce(external_number,case when document_kind='external' then number end) ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$' order by issue_date desc limit 1;
 if i.id is not null then snapshot:=snapshot||jsonb_build_object('support_number',coalesce(i.external_number,i.number),'support_date',coalesce(i.external_issue_date,i.issue_date),'support_authorization',i.access_key);end if;
 recipients:=recipients||jsonb_build_array(snapshot);
 end loop;
 if jsonb_array_length(recipients)=0 then raise exception 'SRI_ROUTE_EMPTY';end if;
 update public.tms_routes set manual_override=true where id=r.id;
 return private.gama_sri_new_document('06','tms_route',r.id,jsonb_build_object('issue_date',r.route_date,'source_number','Ruta '||r.route_date||' / '||v.plate,
 'transport_start',r.route_date,'transport_end',finish,'carrier_name',f.name,'carrier_identification',carrier,'plate',v.plate,
 'departure_address',p_data->>'departure_address','route_version',r.version,'recipients',recipients),null,null,r.id);
end $$;
revoke all on function private.gama_sri_route_guide(uuid,jsonb) from public,anon,authenticated;

alter table public.sri_document_issues add column withholding_id uuid references public.accounting_withholdings(id);
create index sri_document_withholding on public.sri_document_issues(withholding_id) where withholding_id is not null;
create function private.gama_sri_documents(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare d public.sri_document_issues;p public.supplier_withholding_policies;row record;result jsonb;items jsonb:='[]';lines jsonb;
 kind text:=p_data->>'document_type';source uuid:=nullif(p_data->>'source_id','')::uuid;today date:=(now() at time zone private.erp_timezone())::date;
 r public.return_orders;credit public.return_credits;line record;rights jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or private.current_user_role()<>'administrador' or not private.erp_module_allowed('accounting',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action not in ('context','list') and not private.erp_action_allowed('accounting',case when p_action='settle' then 'validate' else 'create' end) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object(
 'policies',coalesce((select jsonb_agg(x) from (select p.*,s.name supplier from public.supplier_withholding_policies p join public.suppliers s on s.id=p.supplier_id order by s.name,p.supplier_id limit 200)x),'[]'),
 'suppliers',coalesce((select jsonb_agg(x) from (select s.id,s.name,s.tax_id identification from public.suppliers s where s.active and (coalesce(p_data->>'search','')='' or s.name ilike '%'||(p_data->>'search')||'%') order by s.name,s.id limit 200)x),'[]'),
 'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name)) from public.accounting_accounts a where a.active and a.type='liability'),'[]'),
 'credits',coalesce((select jsonb_agg(x) from (select c.id,c.erp_reference number,c.amount,k.name customer from public.return_credits c join public.return_orders r on r.id=c.return_id join public.customers k on k.id=r.customer_id where r.kind='customer' and not exists(select 1 from public.sri_document_issues d where d.source_type='return_credit' and d.source_id=c.id) order by c.created_at desc,c.id limit 100)x),'[]'),
 'purchases',coalesce((select jsonb_agg(x) from (select v.id,v.number,v.total amount,s.name supplier,s.tax_id identification from public.supplier_invoices v join public.suppliers s on s.id=v.supplier_id where v.status='posted' and (coalesce(p_data->>'search','')='' or concat_ws(' ',v.number,s.name) ilike '%'||(p_data->>'search')||'%') order by v.issue_date desc,v.id limit 100)x),'[]'),
 'routes',coalesce((select jsonb_agg(x) from (select r.id,r.route_date date,r.driver_name driver,r.vehicle from public.tms_routes r where r.route_date>=today and r.status not in ('En ruta','En tránsito','Cancelada','Terminada') order by r.route_date,r.id limit 100)x),'[]'),
 'purchase_queue',coalesce((select jsonb_agg(x) from (select q.*,v.number,s.name supplier from public.sri_purchase_queue q join public.supplier_invoices v on v.id=q.supplier_invoice_id join public.suppliers s on s.id=v.supplier_id where q.issue_id is null and v.status='posted' order by q.created_at,q.supplier_invoice_id limit 100)x),'[]'));
 elsif p_action='list' then return jsonb_build_object('rows',coalesce((select jsonb_agg(x) from(
 select d.id,d.document_type,d.source_type,d.source_id,d.status,d.access_key,d.last_error,d.created_at,d.authorized_at,d.withholding_id,
 d.establishment||'-'||d.emission_point||'-'||d.sequential fiscal_number,d.snapshot->>'source_number' erp_reference,
 coalesce(d.snapshot->>'customer',d.snapshot->>'carrier_name') partner,d.snapshot->>'issue_date' issue_date
 from public.sri_document_issues d where kind is null or d.document_type=kind order by d.created_at desc,d.id
 limit least(100,greatest(1,coalesce((p_data->>'limit')::int,50))) offset greatest(0,coalesce((p_data->>'offset')::int,0)))x),'[]'),
 'total',(select count(*) from public.sri_document_issues d where kind is null or d.document_type=kind));
 elsif p_action='policy_save' then
 if (p_data->>'income_rate')::numeric>0 then perform private.gama_ec_account((p_data->>'income_account_id')::uuid,'liability');end if;
 if (p_data->>'vat_rate')::numeric>0 then perform private.gama_ec_account((p_data->>'vat_account_id')::uuid,'liability');end if;
 insert into public.supplier_withholding_policies(supplier_id,income_code,income_rate,income_account_id,vat_code,vat_rate,vat_account_id,valid_from,valid_to,evidence,reviewed_by)
 values((p_data->>'supplier_id')::uuid,nullif(p_data->>'income_code',''),(p_data->>'income_rate')::numeric,nullif(p_data->>'income_account_id','')::uuid,
 nullif(p_data->>'vat_code',''),(p_data->>'vat_rate')::numeric,nullif(p_data->>'vat_account_id','')::uuid,(p_data->>'valid_from')::date,nullif(p_data->>'valid_to','')::date,p_data->>'evidence',auth.uid())
 on conflict(supplier_id) do update set income_code=excluded.income_code,income_rate=excluded.income_rate,income_account_id=excluded.income_account_id,
 vat_code=excluded.vat_code,vat_rate=excluded.vat_rate,vat_account_id=excluded.vat_account_id,valid_from=excluded.valid_from,valid_to=excluded.valid_to,evidence=excluded.evidence,reviewed_by=excluded.reviewed_by,reviewed_at=now();
 return jsonb_build_object('supplier_id',p_data->>'supplier_id');
 elsif p_action='discard_guide' then
 select * into d from public.sri_document_issues where id=(p_data->>'id')::uuid for update;
 if d.id is null or d.document_type<>'06' or d.status<>'draft' or d.access_key is not null or d.signed_xml_path is not null then raise exception 'SRI_DRAFT_GUIDE_REQUIRED';end if;
 delete from public.sri_document_issues where id=d.id;
 return jsonb_build_object('discarded',true);
 elsif p_action='prepare' then
 if kind='04' then return private.gama_sri_credit_note(source);
 elsif kind in ('03','07') then return private.gama_sri_purchase_document(source,kind,p_data);
 elsif kind='06' then return private.gama_sri_route_guide(source,p_data);end if;
 raise exception 'SRI_DOCUMENT_TYPE_UNSUPPORTED';
 elsif p_action='prepare_purchases' then
 for row in select q.supplier_invoice_id from public.sri_purchase_queue q join public.supplier_invoices v on v.id=q.supplier_invoice_id where q.issue_id is null and v.status='posted' order by q.created_at limit 50 loop
 begin result:=private.gama_sri_purchase_document(row.supplier_invoice_id,'07','{}');items:=items||jsonb_build_array(result);
 exception when others then update public.sri_purchase_queue set last_error=case when sqlerrm ~ '^[A-Z0-9_]{1,100}$' then sqlerrm else 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED' end where supplier_invoice_id=row.supplier_invoice_id;end;
 end loop;return jsonb_build_object('prepared',items);
 elsif p_action='return_complete' then
 if not private.erp_module_allowed('returns',array['administrador']) or not private.erp_action_allowed('returns','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.return_orders where id=source for update;
 if r.id is null or r.kind<>'customer' or r.status in ('closed','cancelled','to_process') then raise exception 'RETURN_NOT_RECEIVED';end if;
 select * into credit from public.return_credits where return_id=r.id;
 if credit.id is not null and exists(select 1 from public.sri_document_issues where source_type='return_credit' and source_id=credit.id) then return (select jsonb_build_object('id',id,'status',status,'document_type',document_type) from public.sri_document_issues where source_type='return_credit' and source_id=credit.id);end if;
 rights:=private.gama_returns_rights();
 if exists(select 1 from public.return_lines where return_id=r.id and processed_at is null) then
 if p_data->>'inspected' is distinct from 'true' then raise exception 'RETURN_INSPECTION_REQUIRED';end if;
 for line in select id from public.return_lines where return_id=r.id and processed_at is null order by product_id,id loop
 perform private.gama_returns_action('process_line',jsonb_build_object('id',r.id,'line_id',line.id,'disposition','restocked','location_id',p_data->>'location_id'));
 end loop;end if;
 if credit.id is null then result:=private.gama_returns_action('credit',jsonb_build_object('id',r.id,'issued_on',today,'notes',p_data->>'notes'));source:=(result->>'id')::uuid;else source:=credit.id;end if;
 return private.gama_sri_credit_note(source);
 elsif p_action='settle' then
 select * into d from public.sri_document_issues where id=(p_data->>'id')::uuid for update;
 if d.id is null or d.document_type<>'07' or d.status<>'authorized' or d.access_key is null or d.access_key is distinct from d.authorization_response->>'authorization' then raise exception 'SRI_NOT_AUTHORIZED';end if;
 if d.withholding_id is not null then return jsonb_build_object('id',d.withholding_id);end if;
 select jsonb_agg(jsonb_build_object('tax_kind',case when x->>'tax_kind'='IR' then 'income' else 'vat' end,'code',x->>'code','base',x->'base','rate',x->'rate','account_id',x->>'account_id')) into lines from jsonb_array_elements(d.snapshot->'withholdings')x;
 result:=private.gama_accounting_ec('withholding_post',jsonb_build_object('request_key',d.id,'side','supplier','invoice_id',d.source_id,'issued_on',d.snapshot->>'issue_date',
 'number',d.establishment||'-'||d.emission_point||'-'||d.sequential,'authorization_number',d.access_key,'evidence','Comprobante de retención SRI autorizado: '||d.access_key,'lines',lines));
 update public.sri_document_issues set withholding_id=(result->>'id')::uuid where id=d.id;return result;
 end if;raise exception 'UNKNOWN_ACTION';end $$;
revoke all on function private.gama_sri_documents(text,jsonb) from public,anon;
grant execute on function private.gama_sri_documents(text,jsonb) to authenticated;
create function public.gama_sri_documents(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_sri_documents(p_action,p_data)$$;
revoke all on function public.gama_sri_documents(text,jsonb) from public,anon;
grant execute on function public.gama_sri_documents(text,jsonb) to authenticated;

-- A frozen guide must retain its stop order and goods while transport proceeds.
create function private.gama_sri_route_locked() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (new.stops is distinct from old.stops or new.route_date is distinct from old.route_date or new.driver_id is distinct from old.driver_id or new.vehicle_id is distinct from old.vehicle_id) and exists(select 1 from public.sri_document_issues d where d.route_id=old.id and d.status<>'rejected') then raise exception 'SRI_ROUTE_GUIDE_LOCKED';end if;
 return new;end $$;
revoke all on function private.gama_sri_route_locked() from public,anon,authenticated;
create trigger sri_route_locked before update of stops,route_date,driver_id,vehicle_id on public.tms_routes for each row execute function private.gama_sri_route_locked();

create function private.gama_sri_purchase_reviewed() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.source_type='supplier_invoice' and exists(select 1 from public.sri_purchase_queue where supplier_invoice_id=new.source_id and issue_id is null) then
 begin perform private.gama_sri_purchase_document(new.source_id,'07','{}');
 exception when others then update public.sri_purchase_queue set last_error=case when sqlerrm ~ '^[A-Z0-9_]{1,100}$' then sqlerrm else 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED' end where supplier_invoice_id=new.source_id;end;
 end if;return new;end $$;
revoke all on function private.gama_sri_purchase_reviewed() from public,anon,authenticated;
create trigger sri_purchase_reviewed after insert or update on public.accounting_fiscal_documents for each row execute function private.gama_sri_purchase_reviewed();

-- Route managers prepare guides in TMS; drivers read only their own authorized guide.
create function private.gama_tms_guide(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r uuid:=nullif(p_data->>'route_id','')::uuid;d public.sri_document_issues;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if private.current_user_role()<>'administrador' and not private.gama_sri_own_route(r) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action='get' then
 select * into d from public.sri_document_issues where route_id=r;
 return case when d.id is null then null else jsonb_build_object('id',d.id,'document_type','06','status',d.status,'number',d.establishment||'-'||d.emission_point||'-'||d.sequential,'has_pdf',d.ride_path is not null) end;
 end if;
 if private.current_user_role()<>'administrador' or not private.erp_action_allowed('tms','create') then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action='prepare' then return private.gama_sri_route_guide(r,p_data);end if;
 if p_action='discard' then
 select * into d from public.sri_document_issues where route_id=r for update;
 if d.id is null or d.status<>'draft' or d.access_key is not null or d.signed_xml_path is not null then raise exception 'SRI_DRAFT_GUIDE_REQUIRED';end if;
 delete from public.sri_document_issues where id=d.id;return jsonb_build_object('discarded',true);
 end if;raise exception 'UNKNOWN_ACTION';end $$;
revoke all on function private.gama_tms_guide(text,jsonb) from public,anon;
grant execute on function private.gama_tms_guide(text,jsonb) to authenticated;
create function public.gama_tms_guide(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_guide(p_action,p_data)$$;
revoke all on function public.gama_tms_guide(text,jsonb) from public,anon;
grant execute on function public.gama_tms_guide(text,jsonb) to authenticated;
grant all on public.supplier_withholding_policies,public.sri_purchase_queue to service_role;

create function private.gama_sri_goods_locked() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.sales_deliveries s join public.sri_document_issues d on d.route_id=(select route_id from public.tms_deliveries where id=s.tms_delivery_id) where s.id=old.delivery_id and d.status<>'rejected')
 and (tg_op='DELETE' or new.quantity is distinct from old.quantity or new.order_line_id is distinct from old.order_line_id or new.delivery_id is distinct from old.delivery_id) then raise exception 'SRI_ROUTE_GUIDE_LOCKED';end if;
 return case when tg_op='DELETE' then old else new end;end $$;
revoke all on function private.gama_sri_goods_locked() from public,anon,authenticated;
create trigger sri_goods_locked before update or delete on public.sales_delivery_lines for each row execute function private.gama_sri_goods_locked();
