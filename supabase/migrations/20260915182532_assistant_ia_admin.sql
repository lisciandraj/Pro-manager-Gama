-- GAMA Assistant IA: read-only business queries, live administrator checks,
-- private per-administrator answers and server-only provider configuration.
create table public.gama_ai_settings (
 id boolean primary key default true check(id),
 encrypted_key text not null,
 model text not null default 'gpt-4.1-mini',
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
alter table public.gama_ai_settings enable row level security;
revoke all on public.gama_ai_settings from public,anon,authenticated;
grant select,insert,update,delete on public.gama_ai_settings to service_role;
create index gama_ai_settings_updated_by_idx on public.gama_ai_settings(updated_by);

create table public.gama_ai_history (
 id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 question text not null check(length(question) between 1 and 4000),
 language text not null check(language in ('fr','es','en')),
 status text not null default 'pending' check(status in ('pending','complete','failed')),
 engine text,
 answer jsonb,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create index gama_ai_history_user_created_idx on public.gama_ai_history(user_id,created_at desc);
alter table public.gama_ai_history enable row level security;
revoke all on public.gama_ai_history from public,anon,authenticated;
grant select on public.gama_ai_history to authenticated;
grant select,insert,update,delete on public.gama_ai_history to service_role;
create policy gama_ai_history_owner on public.gama_ai_history for select to authenticated
 using(user_id=(select auth.uid()) and (select private.current_user_role())='administrador'
 and not exists(select 1 from public.app_modules where id='assistant-ia' and not enabled));

create function public.gama_ai_claim(p_user uuid,p_id uuid,p_question text,p_language text) returns boolean
language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_user and active and role='administrador')
 or exists(select 1 from public.app_modules where id='assistant-ia' and not enabled) then
  raise exception 'ADMIN_REQUIRED' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('gama-ai:'||p_user::text,0));
 if exists(select 1 from public.gama_ai_history where id=p_id) then return false;end if;
 if (select count(*) from public.gama_ai_history where user_id=p_user and created_at>now()-interval '1 minute')>=4
 or (select count(*) from public.gama_ai_history where user_id=p_user and created_at>now()-interval '1 hour')>=30
 or (select count(*) from public.gama_ai_history where user_id=p_user and created_at>now()-interval '1 day')>=100 then
  raise exception 'RATE_LIMIT' using errcode='54000';
 end if;
 insert into public.gama_ai_history(id,user_id,question,language) values(p_id,p_user,p_question,p_language);
 return true;
end $$;
revoke all on function public.gama_ai_claim(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.gama_ai_claim(uuid,uuid,text,text) to service_role;

create function public.gama_ai_catalog() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador'
 or exists(select 1 from public.app_modules where id='assistant-ia' and not enabled) then
  raise exception 'ADMIN_REQUIRED' using errcode='42501';
 end if;
 return $catalog$[{"table":"app_modules","columns":["id","enabled","updated_at","updated_by"],"pk":["id"],"module":"settings"},{"table":"commercial_matrix","columns":["id","product_id","supplier_id","purchase_price","sale_price","margin","margin_percent","active","created_at","updated_at"],"pk":["id"],"module":"matrix"},{"table":"crm_activities","columns":["id","kind","subject","body","status","priority","owner_id","due_at","done_at","remind_at","lead_id","customer_id","contact_id","opportunity_id","invoice_id","customer_request_id","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_contacts","columns":["id","customer_id","lead_id","first_name","last_name","job_title","email","phone","linkedin","decision_role","is_primary","notes","active","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_leads","columns":["id","kind","first_name","last_name","company","job_title","email","phone","phone2","address","city","country","website","industry","company_size","source_id","owner_id","status","priority","score","last_interaction_at","next_followup_at","notes","converted_customer_id","converted_at","active","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_lost_reasons","columns":["id","name","sort_order","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_opportunities","columns":["id","reference","title","customer_id","lead_id","contact_id","owner_id","source_id","stage_id","amount","probability","expected_close_date","priority","description","competitors","lost_reason_id","quote_invoice_id","won_at","lost_at","active","created_by","created_at","updated_at","weighted_amount"],"pk":["id"],"module":"crm"},{"table":"crm_opportunity_lines","columns":["id","opportunity_id","product_id","quantity","unit_price","discount","position","created_at"],"pk":["id"],"module":"crm"},{"table":"crm_pipeline_stages","columns":["id","name","sort_order","default_probability","is_won","is_lost","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_scoring_rules","columns":["id","event_key","label","points","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_sources","columns":["id","name","sort_order","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_targets","columns":["id","profile_id","period_kind","period_start","amount_goal","notes","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"customer_request_lines","columns":["id","request_id","product_id","quantity","unit_price","tax_rate","line_total","created_at"],"pk":["id"],"module":"quotes"},{"table":"customer_requests","columns":["id","customer_id","created_by","status","notes","total","created_at","updated_at","invoice_id","converted_at","requester_name","requester_email"],"pk":["id"],"module":"quotes"},{"table":"customer_return_credits","columns":["id","return_id","invoice_id","number","amount","notes","created_by","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"customer_return_photos","columns":["id","return_id","filename","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"customer_returns","columns":["id","number","order_id","delivery_line_id","quantity","reason","status","quarantine_location_id","hold_reservation_id","replacement_order_id","inspection_notes","received_at","closed_at","created_by","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"customer_special_prices","columns":["id","customer_id","product_id","unit_price","created_at","contract_ref"],"pk":["id"],"module":"price-lists"},{"table":"customers","columns":["id","name","identification","address","city","province","phone","email","notes","active","created_at","updated_at","category","owner_id","source_id","crm_score","payment_terms_days"],"pk":["id"],"module":"clients"},{"table":"external_invoice_deliveries","columns":["invoice_id","delivery_id","created_by","created_at"],"pk":["invoice_id","delivery_id"],"module":"quotes"},{"table":"external_invoice_files","columns":["id","invoice_id","filename","mime_type","created_at"],"pk":["id"],"module":"quotes"},{"table":"external_invoice_lines","columns":["id","invoice_id","order_line_id","quantity"],"pk":["id"],"module":"quotes"},{"table":"external_invoice_payments","columns":["id","request_key","invoice_id","amount","paid_at","method","reference","account","notes","status","cancellation_reason","cancelled_at","cancelled_by","created_by","created_at"],"pk":["id"],"module":"payments"},{"table":"external_invoices","columns":["id","request_key","order_id","number","issuer_ruc","software","issue_date","due_date","subtotal","tax","total","fiscal_status","notes","cancellation_reason","created_by","created_at","updated_at","document_kind","source_quote_id","external_number","external_issue_date","external_status","payment_terms_days","payment_delivery_date"],"pk":["id"],"module":"quotes"},{"table":"favorite_order_lines","columns":["id","favorite_order_id","product_id","quantity"],"pk":["id"],"module":"quotes"},{"table":"favorite_orders","columns":["id","created_by","name","created_at"],"pk":["id"],"module":"quotes"},{"table":"fulfillment_incidents","columns":["id","preparation_id","pick_line_id","kind","quantity","reason","created_by","created_at"],"pk":["id"],"module":"order-preparation"},{"table":"fulfillment_package_lines","columns":["package_id","pick_line_id","quantity"],"pk":["package_id","pick_line_id"],"module":"order-preparation"},{"table":"fulfillment_packages","columns":["id","preparation_id","barcode","weight_kg","length_cm","width_cm","height_cm","status","created_by","created_at"],"pk":["id"],"module":"order-preparation"},{"table":"fulfillment_pick_lines","columns":["id","preparation_id","order_line_id","source_location_id","stage_location_id","planned","picked"],"pk":["id"],"module":"order-preparation"},{"table":"fulfillment_preparations","columns":["id","order_id","number","status","assigned_to","shipment_id","partial_reason","created_at","updated_at"],"pk":["id"],"module":"order-preparation"},{"table":"gama_audit","columns":["id","table_name","row_id","action","actor_id","actor_role","changed_at","changed_fields"],"pk":["id"],"module":"audit"},{"table":"gama_document_references","columns":["table_name","document_id","node_index","dossier_number","ordinal","document_reference"],"pk":["table_name","document_id"],"module":"settings"},{"table":"hr_absence_decisions","columns":["id","absence_id","employee_id","status","reason","reviewed_by","created_at"],"pk":["id"],"module":"hr"},{"table":"hr_absence_private","columns":["absence_id","reason"],"pk":["absence_id"],"module":"hr"},{"table":"hr_absences","columns":["id","employee_id","kind","start_date","end_date","days","status","created_at","start_fraction","end_fraction","decision_reason","reviewed_by","reviewed_at"],"pk":["id"],"module":"hr"},{"table":"hr_attendance","columns":["id","employee_id","started_at","ended_at","break_started_at","break_seconds","status","correction_reason","reviewed_by","reviewed_at"],"pk":["id"],"module":"hr"},{"table":"hr_audit","columns":["id","table_name","record_id","employee_id","actor_id","action","changed_at"],"pk":["id"],"module":"hr"},{"table":"hr_documents","columns":["id","employee_id","kind","title","effective_date","expires_on","filename","created_by","created_at","supersedes_id"],"pk":["id"],"module":"hr"},{"table":"hr_employee_private","columns":["employee_id","identification","email","phone","contract_type","hire_date","end_date","salary","annual_leave_days","notes"],"pk":["employee_id"],"module":"hr"},{"table":"hr_employees","columns":["id","full_name","position","department","active","created_at","profile_id","manager_profile_id"],"pk":["id"],"module":"hr"},{"table":"hr_holidays","columns":["day","label"],"pk":["day"],"module":"hr"},{"table":"hr_leave_accounts","columns":["id","employee_id","year","entitlement","carryover","adjustment","accrual_mode","active_from","active_to","reason"],"pk":["id"],"module":"hr"},{"table":"hr_payroll","columns":["id","employee_id","period","source_ref","gross","net","employer_cost","cost_center","status","created_at"],"pk":["id"],"module":"hr"},{"table":"hr_payroll_payments","columns":["id","payroll_id","paid_on","amount","reference","status","reason","created_at"],"pk":["id"],"module":"hr"},{"table":"hr_permissions","columns":["profile_id","role"],"pk":["profile_id"],"module":"hr"},{"table":"hr_shifts","columns":["id","employee_id","starts_at","ends_at","break_minutes","note"],"pk":["id"],"module":"hr"},{"table":"hr_work_patterns","columns":["id","employee_id","effective_from","weekdays","daily_hours"],"pk":["id"],"module":"hr"},{"table":"inventory_count_lines","columns":["id","count_id","product_id","location_id","expected_quantity","counted_quantity","variance","validated"],"pk":["id"],"module":"warehouses"},{"table":"inventory_counts","columns":["id","warehouse_id","reference","status","created_by","started_at","completed_at","created_at"],"pk":["id"],"module":"warehouses"},{"table":"invoice_lines","columns":["id","invoice_id","product_id","quantity","unit_price","tax_rate","line_total","quote_description","quote_list_price","quote_discount"],"pk":["id"],"module":"quotes"},{"table":"invoices","columns":["id","invoice_number","customer_id","user_id","status","issue_date","subtotal","tax","total","notes","created_at","updated_at","archive_number","quote_state","quote_request_key","quote_revision","quote_details","quote_valid_until","quote_sent_at","quote_accepted_at","quote_accepted_by","quote_acceptance_channel","quote_acceptance_reference"],"pk":["id"],"module":"quotes"},{"table":"knowledge_articles","columns":["id","parent_id","slug","title","body","properties","version","created_by","updated_by","created_at","updated_at"],"pk":["id"],"module":"knowledge"},{"table":"products","columns":["id","barcode","name","reference","category","location","supplier_id","min_stock","stock","sale_price","tax_rate","active","created_at","updated_at","has_photo","description","family","lines","brand","presentation","qty_per_carton","weight_g","volume_cm3","max_stock","sale_price_b","purchase_price"],"pk":["id"],"module":"products"},{"table":"profiles","columns":["id","full_name","role","active","created_at","updated_at","email"],"pk":["id"],"module":"settings"},{"table":"purchase_order_lines","columns":["id","purchase_order_id","product_id","quantity","received_quantity","unit_cost","tax_rate","line_total","created_at"],"pk":["id"],"module":"gamaPurchasesV14"},{"table":"purchase_orders","columns":["id","supplier_id","order_number","order_date","expected_date","status","notes","subtotal","tax","total","created_by","created_at","updated_at"],"pk":["id"],"module":"gamaPurchasesV14"},{"table":"quote_events","columns":["id","quote_id","revision","action","actor_id","at","detail"],"pk":["id"],"module":"quotes"},{"table":"reorder_rules","columns":["id","product_id","warehouse_id","min_quantity","max_quantity","reorder_quantity","supplier_id","lead_time_days","active","created_at"],"pk":["id"],"module":"gamaPurchasesV14"},{"table":"sales_deliveries","columns":["id","number","order_id","request_key","tms_delivery_id","dispatched_at","created_by","notes","loading_required","loading_version","departed_at","departed_by","departure_driver_id","departure_vehicle"],"pk":["id"],"module":"sales-orders"},{"table":"sales_delivery_lines","columns":["id","delivery_id","order_line_id","location_id","quantity","loading_barcode"],"pk":["id"],"module":"sales-orders"},{"table":"sales_events","columns":["id","order_id","action","entity_id","actor_id","detail","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"sales_fulfillment_options","columns":["id","order_id","line_id","kind","quantity","replacement_product_id","unit_price","tax_rate","promised_date","notes","status","responded_by","responded_at","agreement_reference","created_by","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"sales_order_lines","columns":["id","order_id","product_id","product_name","reference","quantity","unit_price","tax_rate","promised_date","next_dispatch_quantity","delivery_policy"],"pk":["id"],"module":"sales-orders"},{"table":"sales_orders","columns":["id","number","request_key","customer_id","customer_name","customer_identification","delivery_address","source_quote_id","source_request_id","status","notes","created_by","created_at","updated_at","source_opportunity_id"],"pk":["id"],"module":"sales-orders"},{"table":"sales_reservation_links","columns":["reservation_id","line_id"],"pk":["reservation_id"],"module":"sales-orders"},{"table":"sri_electronic_documents","columns":["id","user_id","invoice_id","cod_doc","ambiente","secuencial","status","numero_autorizacion","fecha_autorizacion","messages","created_at","updated_at"],"pk":["id"],"module":"quotes"},{"table":"sri_settings","columns":["id","user_id","environment","ruc","razon_social","estab","pto_emi","dir_matriz","email","created_at","updated_at"],"pk":["id"],"module":"quotes"},{"table":"stock_movements","columns":["id","product_id","type","quantity","reason","comment","user_id","created_at","stock_before","stock_after","source_location_id","destination_location_id","movement_type","reference_type","reference_id"],"pk":["id"],"module":"warehouses"},{"table":"stock_quants","columns":["id","product_id","location_id","quantity","reserved_quantity","updated_at"],"pk":["id"],"module":"warehouses"},{"table":"stock_reservations","columns":["id","product_id","location_id","quantity","reference_type","reference_id","status","created_by","created_at","released_at"],"pk":["id"],"module":"warehouses"},{"table":"suppliers","columns":["id","name","tax_id","address","city","province","postal_code","country","phone","email","contact_name","notes","active","created_at","updated_at"],"pk":["id"],"module":"suppliers"},{"table":"tms_deliveries","columns":["id","customer","address","delivery_date","time_window","priority","weight","volume","status","lat","lng","route_id","driver_id","actual_arrival","delivered_at","notes","created_at","created_by","customer_id"],"pk":["id"],"module":"tms"},{"table":"tms_drivers","columns":["id","name","phone","vehicle","max_weight","max_volume","enabled","created_at","employee_id"],"pk":["id"],"module":"tms"},{"table":"tms_events","columns":["id","delivery_id","at","type","note","customer","user_id"],"pk":["id"],"module":"tms"},{"table":"tms_loading_allocations","columns":["scan_id","delivery_line_id","quantity"],"pk":["scan_id","delivery_line_id"],"module":"tms"},{"table":"tms_loading_scans","columns":["id","request_key","delivery_id","barcode","quantity","scanned_by","scanned_at","voided_at","voided_by","void_reason"],"pk":["id"],"module":"tms"},{"table":"tms_proofs","columns":["delivery_id","captured_at","captured_by"],"pk":["delivery_id"],"module":"tms"},{"table":"tms_routes","columns":["id","route_date","driver_id","driver_name","vehicle","stops","distance","weight","volume","status","created_at"],"pk":["id"],"module":"tms"},{"table":"tms_settings","columns":["id","depot","depot_lat","depot_lng","return_depot","updated_at"],"pk":["id"],"module":"tms"},{"table":"warehouse_locations","columns":["id","warehouse_id","parent_id","code","name","type","barcode","picking_priority","active","created_at"],"pk":["id"],"module":"warehouses"},{"table":"warehouses","columns":["id","code","name","address","city","active","created_at","updated_at"],"pk":["id"],"module":"warehouses"}]$catalog$::jsonb;
end $$;
revoke all on function public.gama_ai_catalog() from public,anon;
grant execute on function public.gama_ai_catalog() to authenticated;

-- This endpoint accepts a constrained query description, never executable SQL.
-- Identifiers are checked against the committed business-field allowlist and
-- quoted with %I. Values are separately quoted with %L and cast to real types.
create function public.gama_ai_query(p_query jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' set statement_timeout='8s' as $$
declare catalog jsonb:=public.gama_ai_catalog(); spec jsonb; col text; typ text;
 tbl text:=p_query->>'table'; op text:=coalesce(p_query->>'operation','rows');
 fields text:=''; groups text:=''; wh text:='true'; ord text; predicate text;
 f jsonb; cols text[]; group_cols text[]; agg_col text; cmp text; v text;
 lim integer:=least(200,greatest(1,coalesce((p_query->>'limit')::integer,50)));
 off integer:=least(100000,greatest(0,coalesce((p_query->>'offset')::integer,0)));
 n bigint; result jsonb;
begin
 if jsonb_typeof(p_query) is distinct from 'object' or length(p_query::text)>16000 then raise exception 'INVALID_QUERY';end if;
 select x into spec from jsonb_array_elements(catalog) x where x->>'table'=tbl;
 if spec is null then raise exception 'TABLE_NOT_ALLOWED' using errcode='42501';end if;
 if op not in ('rows','count','sum','avg','min','max') then raise exception 'READ_ONLY_OPERATION';end if;
 if jsonb_typeof(coalesce(p_query->'filters','[]'))<>'array' or jsonb_array_length(coalesce(p_query->'filters','[]'))>12 then raise exception 'INVALID_FILTERS';end if;
 for f in select value from jsonb_array_elements(coalesce(p_query->'filters','[]')) loop
  col:=f->>'column';cmp:=f->>'operator';v:=f->>'value';
  if not (spec->'columns' ? col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
  select format_type(a.atttypid,a.atttypmod) into typ from pg_attribute a
    where a.attrelid=to_regclass(format('public.%I',tbl)) and a.attname=col and a.attnum>0;
  if cmp in ('eq','neq','gt','gte','lt','lte') then
   if v is null then raise exception 'USE_IS_NULL';end if;
   predicate:=format('t.%I %s %L::%s',col,case cmp when 'eq' then '=' when 'neq' then '<>' when 'gt' then '>' when 'gte' then '>=' when 'lt' then '<' else '<=' end,v,typ);
  elsif cmp='contains' then
   if v is null or length(v)>300 then raise exception 'INVALID_SEARCH';end if;
   predicate:=format('strpos(lower(t.%I::text),lower(%L))>0',col,v);
  elsif cmp='is_null' then predicate:=format('t.%I is null',col);
  elsif cmp='not_null' then predicate:=format('t.%I is not null',col);
  else raise exception 'OPERATOR_NOT_ALLOWED';end if;
  wh:=wh||' and '||predicate;
 end loop;
 execute format('select count(*) from public.%I t where %s',tbl,wh) into n;
 if op='count' then return jsonb_build_object('table',tbl,'operation',op,'matched_rows',n,'value',n,'truncated',false);end if;
 if op='rows' then
  if p_query ? 'columns' and jsonb_array_length(p_query->'columns')>0 then
   select array_agg(value) into cols from jsonb_array_elements_text(p_query->'columns');
  else select array_agg(value) into cols from jsonb_array_elements_text(spec->'columns');end if;
  if array_length(cols,1)>100 then raise exception 'TOO_MANY_COLUMNS';end if;
  foreach col in array cols loop
   if not(spec->'columns' ? col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
   fields:=fields||case when fields='' then '' else ',' end||format('t.%I',col);
  end loop;
  ord:=coalesce(nullif(p_query->>'order_by',''),spec->'pk'->>0);
  if not(spec->'columns' ? ord) then raise exception 'ORDER_NOT_ALLOWED';end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) from (select %s from public.%I t where %s order by t.%I %s nulls last,%s limit %s offset %s) r',
   fields,tbl,wh,ord,case when p_query->>'direction'='desc' then 'desc' else 'asc' end,
   (select string_agg(format('t.%I',value),',') from jsonb_array_elements_text(spec->'pk')),lim,off) into result;
 else
  agg_col:=p_query->>'column';
  if not(spec->'columns' ? agg_col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
  if op in ('sum','avg') and not exists(select 1 from information_schema.columns where table_schema='public' and table_name=tbl and column_name=agg_col and data_type in ('smallint','integer','bigint','numeric','real','double precision')) then raise exception 'NUMERIC_COLUMN_REQUIRED';end if;
  select array_agg(value) into group_cols from jsonb_array_elements_text(coalesce(p_query->'group_by','[]'));
  if coalesce(array_length(group_cols,1),0)>2 then raise exception 'TOO_MANY_GROUPS';end if;
  foreach col in array coalesce(group_cols,'{}'::text[]) loop
   if not(spec->'columns' ? col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
   groups:=groups||case when groups='' then '' else ',' end||format('t.%I',col);
  end loop;
  fields:=case when groups='' then '' else groups||',' end||format('%s(t.%I) as value,count(*) as records',op,agg_col);
  execute format('select coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) from (select %s from public.%I t where %s %s order by value desc nulls last limit %s offset %s) r',
   fields,tbl,wh,case when groups='' then '' else 'group by '||groups end,lim+1,off) into result;
 end if;
 return jsonb_build_object('table',tbl,'operation',op,'matched_rows',n,'offset',off,
  'truncated',case when op='rows' then off+jsonb_array_length(result)<n else jsonb_array_length(result)>lim end,
  'rows',(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(result) with ordinality r(value,i) where i<=lim));
end $$;
revoke all on function public.gama_ai_query(jsonb) from public,anon;
grant execute on function public.gama_ai_query(jsonb) to authenticated;

create function public.gama_ai_overview(p_from date default null,p_to date default null) returns jsonb
language plpgsql stable security invoker set search_path='' set statement_timeout='12s' as $$
declare catalog jsonb:=public.gama_ai_catalog(); counts jsonb:='[]';spec jsonb;n bigint;stock jsonb;finance jsonb;
 today date:=(now() at time zone 'America/Guayaquil')::date;date_from date:=coalesce(p_from,date_trunc('month',now() at time zone 'America/Guayaquil')::date);date_to date:=coalesce(p_to,today);
begin
 if date_from>date_to then raise exception 'INVALID_PERIOD';end if;
 for spec in select value from jsonb_array_elements(catalog) loop
  execute format('select count(*) from public.%I',spec->>'table') into n;
  counts:=counts||jsonb_build_array(jsonb_build_object('table',spec->>'table','module',spec->>'module','rows',n));
 end loop;
 with reserved as(select product_id,sum(quantity) qty from public.stock_reservations where status='active' group by product_id),
 s as(select p.id,p.name,p.reference,p.stock,p.min_stock,p.purchase_price,p.stock-coalesce(r.qty,0) available,
 greatest(0,p.min_stock-(p.stock-coalesce(r.qty,0))) shortage from public.products p left join reserved r on r.product_id=p.id where p.active)
 select jsonb_build_object('active_products',count(*),'low_products',count(*) filter(where available<=min_stock),
 'stock_cost',coalesce(sum(stock*purchase_price),0),'missing_costs',count(*) filter(where purchase_price is null),
 'low_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,stock,min_stock,available,shortage from s where available<=min_stock order by shortage desc,name limit 20)x),'[]'::jsonb)) into stock from s;
 finance:=public.gama_payment_action('list','{"status":"all"}'::jsonb);
 return jsonb_build_object('as_of',clock_timestamp(),'today',today,'currency','USD','timezone','America/Guayaquil',
 'period',jsonb_build_object('from',date_from,'to',date_to),'coverage',counts,'stock',stock,
 'receivables',finance,
 'sales',jsonb_build_object('registered_subtotal',coalesce((select sum(subtotal) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'registered_total',coalesce((select sum(total) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'invoice_count',(select count(*) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),
 'receipts',coalesce((select sum(amount) from public.external_invoice_payments where status='confirmed' and paid_at between date_from and date_to),0),
 'orders',(select count(*) from public.sales_orders where status<>'cancelled' and (created_at at time zone 'America/Guayaquil')::date between date_from and date_to),
 'quotes_to_follow',(select count(*) from public.invoices where quote_state='sent' and quote_sent_at<now()-interval '7 days')),
 'purchases',jsonb_build_object('late_count',(select count(*) from public.purchase_orders where status not in ('received','cancelled') and expected_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,order_number,supplier_id,expected_date,status,total from public.purchase_orders where status not in ('received','cancelled') and expected_date<today order by expected_date,id limit 20)x),'[]'::jsonb)),
 'logistics',jsonb_build_object('late_count',(select count(*) from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,customer,delivery_date,status from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today order by delivery_date,id limit 20)x),'[]'::jsonb)),
 'crm',jsonb_build_object('open_opportunities',(select count(*) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),
 'weighted_pipeline',coalesce((select sum(o.weighted_amount) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),0),
 'late_activities',(select count(*) from public.crm_activities where status not in ('done','cancelled') and due_at<now())),
 'hr',jsonb_build_object('active_employees',(select count(*) from public.hr_employees where active),'pending_absences',(select count(*) from public.hr_absences where status='pending')),
 'knowledge',jsonb_build_object('articles',(select count(*) from public.knowledge_articles)));
end $$;
revoke all on function public.gama_ai_overview(date,date) from public,anon;
grant execute on function public.gama_ai_overview(date,date) to authenticated;
