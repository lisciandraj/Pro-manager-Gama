-- Access fixes and scoped application exports. No business rows are rewritten.
set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- Keep all parallel favorites reads under the same current product entitlement.
create or replace function private.gama_b2b_product_favorites(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 cid uuid:=private.gama_b2b_customer();
 pid uuid;
 off integer:=coalesce((p_data->>'offset')::integer,0);
 term text:=left(btrim(coalesce(p_data->>'search','')),100);
 wanted boolean;
 cnt integer;
 rows jsonb;
begin
 -- The resolver checks auth.uid(), MFA, verified account, current membership,
 -- active customer and the website module on EVERY read and write.
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 if p_action='ids' then
  return coalesce((select jsonb_agg(f.product_id order by f.product_id)
   from private.b2b_product_favorites f where f.customer_id=cid
    and private.commerce_product_allowed(cid,f.product_id)),'[]'::jsonb);
 end if;
 if p_action='list' then
  with filtered as (
   select p.id,p.name,p.reference,p.category,p.tax_rate,p.order_minimum,p.order_multiple,
    (p.active and p.product_kind='goods') active,
    (p.has_photo and p.active and p.product_kind='goods') has_photo,
    p.photo_is_illustrative,f.created_at
   from private.b2b_product_favorites f join public.products p on p.id=f.product_id
   where f.customer_id=cid and private.commerce_product_allowed(cid,p.id) and (term='' or p.name ilike '%'||term||'%'
    or p.reference ilike '%'||term||'%' or p.barcode ilike '%'||term||'%')
  ), limited as (select * from filtered order by created_at desc,id limit 30 offset off)
  select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
   'unit_price',case when l.active then private.erp_price_calculate(cid,l.id,
    ceil(greatest(1,l.order_minimum)/l.order_multiple)*l.order_multiple,null)->'unit_price' else null end
   ) order by l.created_at desc,l.id),'[]'::jsonb) into cnt,rows from limited l;
  return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='set' then
  pid:=nullif(p_data->>'product_id','')::uuid;
  if pid is null or jsonb_typeof(p_data->'favorite') is distinct from 'boolean' then raise exception 'INVALID_DATA';end if;
  wanted:=(p_data->>'favorite')::boolean;
  -- Serialize updates for one customer, including the bounded-list check.
  perform pg_advisory_xact_lock(hashtextextended('b2b-product-favorites:'||cid::text,0));
  if wanted then
   if not exists(select 1 from public.products p where p.id=pid and p.active and p.product_kind='goods'
    and private.commerce_product_allowed(cid,p.id)) then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not exists(select 1 from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid)
    and (select count(*) from private.b2b_product_favorites f where f.customer_id=cid)>=500 then raise exception 'B2B_PRODUCT_FAVORITE_LIMIT';end if;
   insert into private.b2b_product_favorites(customer_id,product_id) values(cid,pid) on conflict do nothing;
  else
   -- Unavailable products can still be removed. Retrying either state is safe.
   delete from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid;
  end if;
  return jsonb_build_object('product_id',pid,'favorite',wanted);
 end if;
 raise exception 'INVALID_ACTION';
end $$;

revoke all on function private.gama_b2b_product_favorites(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_b2b_product_favorites(text,jsonb) to authenticated;

-- Module revocation is checked before project membership, direct-table and file ACLs.
create or replace function private.pm_internal() returns boolean
language sql stable security definer set search_path='' as $$
 select private.erp_module_allowed('projects',array['administrador','comercial','almacenero'])
$$;
revoke all on function private.pm_internal() from public,anon,service_role;
grant execute on function private.pm_internal() to authenticated;

-- Frozen business resource/column contract, not a scan that exports new tables.
-- New tables and columns are excluded until a reviewed migration admits them.
-- Security keys, OAuth/service credentials, authorization receipts and runtime
-- queues are deliberately absent. Public survey/guest capability columns are
-- omitted so a scoped restore generates fresh tokens using the schema defaults.
create function private.recovery_business_export_columns() returns jsonb
language sql immutable set search_path='' as $policy$
 select '{
  "private.accounting_asset_events": ["id","asset_id","kind","entry_date","amount","accumulated_account_id","entry_id","reason","created_by","proceeds_invoice_id"],
  "private.accounting_asset_schedules": ["asset_id","period","amount"],
  "private.accounting_bank_bindings": ["line_id","financial_account_id","assigned_at","assigned_by","reason"],
  "private.accounting_bank_import_policies": ["id","journal_id","suspense_account_id","start_date","enabled","created_by","created_at","updated_at"],
  "private.accounting_bank_import_postings": ["id","entry_id","financial_account_id","bank_account_id","suspense_account_id","amount","created_by","created_at"],
  "private.accounting_bank_statements": ["import_batch","financial_account_id","name","date_from","date_to","opening_balance","closing_balance","evidence","updated_at","updated_by"],
  "private.accounting_budgets": ["id","period_start","account_id","dimension_id","amount","updated_by","updated_at"],
  "private.accounting_closure_reviews": ["id","period_id","reviewed_at","reviewed_by","review","exceptions"],
  "private.accounting_date_adjustments": ["id","entry_id","requested_date","effective_date","lock_kinds","created_by","created_at"],
  "private.accounting_deferral_batch_plans": ["batch_id","plan_id"],
  "private.accounting_deferral_batches": ["id","kind","journal_id","as_of","status","revision","snapshot","reason","entry_id","reversal_entry_id","correction_id","reversal_correction_id","created_by","created_at","approved_by","approved_at","last_error"],
  "private.accounting_dimensions": ["id","kind","code","name","active"],
  "private.accounting_fx_documents": ["id","side","invoice_id","currency","foreign_amount","historical_rate","base_amount","rate_date","evidence","created_by"],
  "private.accounting_fx_settlements": ["id","document_id","paid_on","foreign_amount","rate","carrying_amount","bank_amount","payment_id","adjustment_entry_id","financial_account_id","evidence","created_by"],
  "private.accounting_groups": ["id","name","prefix_start","prefix_end","parent_id","created_by","created_at","updated_at"],
  "private.accounting_invoice_deferral_settings": ["id","kind","journal_id","deferral_account_id","computation","mode","enabled","version","created_at","updated_at","updated_by"],
  "private.accounting_line_dimensions": ["line_id","dimension_id","assigned_by","reason"],
  "private.accounting_lock_dates": ["id","kind","lock_date","version","reason","updated_by","updated_at"],
  "private.accounting_lock_exceptions": ["id","lock_id","lock_version","profile_id","after_date","expires_at","reason","revoked_at","revoked_by","created_by","created_at"],
  "private.accounting_match_allocations": ["group_id","bank_id","kind","source_id","amount","created_at"],
  "private.accounting_match_postings": ["id","group_id","bank_date","entry_id","reversal_entry_id","created_by","created_at"],
  "private.accounting_number_counters": ["journal_id","period_key","last_number"],
  "private.accounting_numbering": ["id","enabled","prefix","reset","padding","start_at","version","updated_by","updated_at"],
  "private.accounting_payment_methods": ["id","financial_account_id","method","direction","mode","outstanding_account_id","created_by","created_at","updated_at","name","active","is_default"],
  "private.accounting_payment_preferences": ["id","partner_type","partner_id","method_id","created_by","created_at","updated_at"],
  "private.accounting_payment_settlements": ["id","group_id","entry_id","created_by","created_at","reversal_entry_id"],
  "private.accounting_payment_treatments": ["id","source_type","source_id","method_id","financial_account_id","mode","bank_account_id","payment_account_id","partner_account_id","partner_type","partner_id","invoice_id","supplier_invoice_id","amount","paid_on","created_by","created_at","method_name"],
  "private.accounting_plan_items": ["id","plan_id","ordinal","due_on","kind","amount","principal","interest","lines","entry_id","reversal_entry_id"],
  "private.accounting_plans": ["id","name","kind","status","journal_id","source_line_id","amount","starts_on","ends_on","configuration","opening_entry_id","created_by","created_at","approved_by","approved_at","reason","version","invoice_id","supplier_invoice_id","invoice_line_key"],
  "private.accounting_readiness": ["code","applicable","verified","evidence","verified_at","verified_by"],
  "private.accounting_statement_sources": ["id","financial_account_id","format","source_account","source_uid","source_row","created_by","created_at"],
  "private.accounting_stock_policies": ["id","mode","standard","start_date","stock_account_id","variation_account_id","expense_account_id","journal_id","reason","created_by","created_at"],
  "private.accounting_stock_review_entries": ["review_id","entry_id","reversal_entry_id"],
  "private.accounting_stock_reviews": ["id","as_of","status","revision","snapshot","created_by","created_at","approved_by","approved_at","reason"],
  "private.agent_report_files": ["report_id","content"],
  "private.agent_reports": ["id","report_key","reference","title","report_date","period_from","period_to","languages","source_filename","sha256","file_size","created_at","imported_by"],
  "private.b2b_product_favorites": ["customer_id","product_id","created_at"],
  "private.cash_commitments": ["id","label","kind","direction","amount","due_date","repeat_monthly","end_date","active","version","created_by","updated_at"],
  "private.cash_scenarios": ["id","name","customer_delay","supplier_delay","collection_percent","minimum_balance","version","created_by","updated_at"],
  "private.coco_contact_entities": ["id","nature","language","website","industry","tags","parent_id","relation","version","created_at","updated_at","updated_by","details","alignment_conflicts","mobile","title","street2","company_registry","ref","image_url","salesperson_id"],
  "private.coco_history_modules": ["module_id","label","roles"],
  "private.coco_history_tables": ["table_name","module_id","label","parent_column","parent_table","table_schema","key_column"],
  "private.coco_module_events": ["id","module_id","record_table","record_id","record_owner","type","action","subject","body","reference","actor_id","actor_name","created_at","transaction_id","references_list","links","source_type","source_id","source_label","source_email","proposal_id","request_key"],
  "private.coco_module_proposals": ["id","account_id","module_id","action","source_type","source_id","source_label","source_email","received_at","summary","payload","status","created_at","review","reviewed_by","reviewed_at","review_hash","decided_at","decided_by","result"],
  "private.coco_order_entries": ["id","kind","order_id","type","actor_id","actor_name","created_at","subject","body","direction","status","from_email","to_email","request_key","mail_owner","provider","provider_id","thread_id","internet_id","reply_id","attachments","detail"],
  "private.coco_workhub_channels": ["id","name","description","owner_id","created_by","created_at","updated_at"],
  "private.coco_workhub_document_versions": ["document_id","version","title","body","created_by","created_at"],
  "private.coco_workhub_documents": ["id","channel_id","title","body","state","version","archived","created_by","updated_by","created_at","updated_at"],
  "private.coco_workhub_links": ["id","message_id","kind","record_id","created_at"],
  "private.coco_workhub_members": ["channel_id","profile_id","created_at"],
  "private.coco_workhub_messages": ["id","channel_id","parent_id","body","created_by","created_at","updated_at"],
  "private.coco_workhub_states": ["user_id","kind","record_id","status","snoozed_until","source_updated_at","created_at","updated_at"],
  "private.collection_holds": ["invoice_id","disputed","promise_date","promise_amount","suspend_until","reason","version","updated_by","updated_at"],
  "private.commerce_approvals": ["id","customer_id","created_by","request_key","original_payload","payload","cart","status","stage","version","request_id","decisions","created_at","updated_at"],
  "private.commerce_approvers": ["id","customer_id","requester_id","approver_id","stage","created_by","created_at"],
  "private.commerce_cases": ["id","reference","request_key","payload_hash","kind","right_kind","contact_name","email","order_reference","message","status","owner","identity_verified_at","identity_verified_by","resolution","target_at","target_basis","internal_notes","response_reference","received_at","updated_at","closed_at","legal_hold","redacted_at","version","policy_snapshot"],
  "private.commerce_catalog_products": ["id","customer_id","product_id","created_by"],
  "private.commerce_compliance_records": ["id","kind","title","owner","status","scope","details","evidence","next_review","verified_by","verified_at","version","created_by","updated_by","created_at","updated_at"],
  "private.commerce_guest_orders": ["id","request_key","request_id","billing","cart","policy_version","policy_snapshot","terms_accepted_at","created_at"],
  "private.commerce_policy_versions": ["version","documents","titles","created_at","created_by"],
  "private.commerce_retention_rule": ["id","enabled","closed_case_days","approval_reference","version","updated_by","updated_at"],
  "private.commerce_reviews": ["id","product_id","buyer_key","customer_id","created_by","order_id","rating","body","created_at","updated_at","hidden","moderation_reason","moderated_by","moderated_at"],
  "private.commercial_settings": ["id","minimum_margin"],
  "private.company_localization_templates": ["country","template"],
  "private.consultation_offers": ["id","consultation_id","supplier_id","reference","currency","valid_until","payment_terms_days","lead_days","freight","lines","notes","purchase_order_id","award_reason","version","created_by","updated_at"],
  "private.contract_occurrences": ["id","contract_id","due_date","order_id","status","created_by","created_at"],
  "private.customer_contracts": ["id","name","customer_id","delivery_address","lines","price_mode","frequency","interval_count","anchor_day","start_date","next_date","end_date","active","automatic","notes","last_error","version","created_by","updated_at"],
  "private.customer_message_preferences": ["customer_id","invoice_reminders","surveys","evidence","updated_by","updated_at"],
  "private.delivery_reference_repairs": ["delivery_id","old_reference","new_reference","old_registry","old_issued","repaired_at"],
  "private.erp_alert_state": ["alert_key","fingerprint","finance_only","warehouse_only","active","changed_at"],
  "private.erp_issued_references": ["kind","document_key","serial_number","reference","legacy_reference","issued_at"],
  "private.erp_reference_counters": ["kind","last_number"],
  "private.erp_reference_prefixes": ["prefix","kind"],
  "private.erp_stock_cost_epoch": ["id","observed_at"],
  "private.erp_stock_cost_opening": ["product_id","quantity","unit_cost","observed_at"],
  "private.expense_claims": ["id","employee_id","vehicle_id","paid_by","status","due_date","purpose","reason","ocr_id","liability_account_id","payment_entry_id","paid_on","payment_reference","approved_by","approved_at","created_by","request_fingerprint","version","updated_at"],
  "private.gama_alert_events": ["id","alert_key","fingerprint","action","note","actor","created_at"],
  "private.gama_alert_handling": ["alert_key","fingerprint","status","assigned_to","snoozed_until","note","updated_by","updated_at","next_action","due_at","root_cause"],
  "private.marketing_attachment_files": ["id","filename","mime_type","content","created_at","created_by"],
  "private.marketing_campaign_attachments": ["campaign_id","attachment_id"],
  "private.marketing_campaigns": ["id","title","channel","subject","message","dialing_code","state","version","prepared_payload","created_by","updated_by","created_at","updated_at"],
  "private.marketing_recipients": ["id","campaign_id","kind","contact_id","recipient_group","label","address","subject","message","status","opened_at","opened_by"],
  "private.order_cost_snapshots": ["line_id","unit_cost","captured_at"],
  "private.order_operating_costs": ["order_id","kind","amount","basis","evidence","version","updated_by","updated_at"],
  "private.product_dedup_archive": ["batch_id","removed_product_id","kept_product_id","removed_score","kept_score","removed_snapshot","kept_snapshot","removed_at"],
  "private.purchase_consultations": ["id","name","required_on","lines","status","version","created_by","updated_at"],
  "private.quote_process_reference_repairs": ["quote_id","old_reference","new_reference","old_row","old_registry","old_issued","repaired_at"],
  "private.recurring_occurrences": ["id","schedule_id","due_date","version","lines","state","request_id","confirmation","created_at","decided_at","approval_id"],
  "private.recurring_orders": ["id","customer_id","name","lines","frequency","interval_count","anchor_day","next_date","address_id","notes","active","version","created_by","updated_at"],
  "private.sales_activities": ["id","dossier_id","kind","title","owner_id","due_at","completed_at","created_by","created_at","request_key","payload"],
  "private.sales_customer_billing": ["customer_id","mode","updated_by","updated_at"],
  "private.sales_deposit_uses": ["deposit_invoice_id","tax_rate","invoice_id","subtotal","tax"],
  "private.sales_dossier_lines": ["id","dossier_id","quote_line_id","order_line_id","invoice_policy"],
  "private.sales_dossiers": ["id","quote_id","order_id","created_at","currency","payment_terms_days","terms_frozen_at","terms_origin"],
  "private.sales_down_payments": ["invoice_id","order_id","tax_rate","subtotal","tax","liability_account_id"],
  "private.sales_invoice_orders": ["invoice_id","order_id","subtotal","tax"],
  "private.sales_option_terms": ["option_id","order_fingerprint","pricing","price_mode","price_reason","shipped_at_agreement","preparation_days","transport_days","approved_by","approved_at","approval_reason","approval_fingerprint","created_by","created_at"],
  "private.sales_order_approvals": ["order_id","fingerprint","approved_by","approved_at","reason","requested_by","requested_at"],
  "private.sales_portal_acceptances": ["quote_id","revision","accepted_by","accepted_at","snapshot","processed_order_id"],
  "private.sales_product_billing": ["product_id","invoice_policy","updated_by","updated_at"],
  "private.sales_quote_credit_reviews": ["quote_id","fingerprint","revision","requested_by","requested_at","approved_by","approved_at","reason","exposure","order_amount"],
  "private.sales_quote_extras": ["quote_id","blocks","updated_by","updated_at"],
  "private.sales_quote_reviews": ["quote_id","revision","fingerprint","maximum_discount","margin","approved_by","approved_at","reason","requested_by","requested_at"],
  "private.sales_templates": ["id","name","customer_id","validity_days","details","lines","version","active","created_by","updated_at","offer_blocks"],
  "private.sales_workspace_settings": ["id","version","maximum_discount","minimum_margin","updated_by","updated_at","default_invoice_policy","deposit_account_id"],
  "private.sri_document_sequences": ["environment","issuer_ruc","establishment","emission_point","document_type","last_value"],
  "private.supplier_ocr_intakes": ["id","hash","filename","mime_type","content","state","extracted","reviewed","bill_id","error_code","created_by","created_at","updated_at"],
  "private.supplier_xml_intakes": ["id","hash","supplier_id","bill_id","xml_source","filename","created_by","created_at"],
  "private.survey_invitations": ["id","survey_id","customer_id","supplier_id","contact_id","label","revoked","created_at","created_by","lead_id","crm_recipient"],
  "private.survey_responses": ["id","survey_id","invitation_id","request_key","payload","answers","score","maximum","visitor_hash","created_at"],
  "private.survey_service_links": ["response_id","ticket_id","created_at"],
  "private.surveys": ["id","title","introduction","thanks","language","state","questions","quiz","pass_percent","invitation_only","closes_at","version","created_at","updated_at","created_by","updated_by"],
  "private.tms_attempt_media": ["proof_id","data_url"],
  "private.tms_cash_handovers": ["request_key","work_day","payments","expected","counted","note","received_by","created_at"],
  "private.tms_day_plans": ["day","fingerprint","output_hash","summary","planned_at"],
  "private.tms_dispatch_config": ["id","version","shift_start","shift_end","break_after","break_minutes","max_stops","require_guide","updated_at","updated_by"],
  "private.tms_leg_knowledge": ["origin","destination","road_km","drive_minutes","source","verified_at","verified_by"],
  "private.tms_plan_versions": ["id","day","fingerprint","output_hash","summary","planned_at"],
  "private.tms_pro_driver_rules": ["driver_id","version","skills","shift_start","shift_end","speed_factor","updated_at","updated_by","start_location","end_location","end_mode"],
  "private.tms_pro_feedback": ["delivery_id","rating","comment","created_at"],
  "private.tms_pro_order_rules": ["delivery_id","version","from_day","to_day","weekdays","windows","skills","features","driver_id","updated_at","updated_by","loads"],
  "private.tms_pro_positions": ["id","route_id","actor_id","lat","lng","accuracy","observed_at","received_at"],
  "private.tms_pro_settings": ["id","version","balance","updated_at","updated_by","dimensions"],
  "private.tms_pro_vehicle_rules": ["vehicle_id","version","features","updated_at","updated_by","capacities"],
  "private.tms_proof_files": ["proof_id","path","content_hash","sha256","verified_at"],
  "private.tms_rejected_packages": ["delivery_id","package_id","return_id"],
  "private.tms_route_expenses": ["route_id","version","driver_minutes","hourly_rate","tolls","vehicle_cost","source","updated_by","updated_at"],
  "private.tms_route_templates": ["id","name","driver_id","customer_ids","weekdays","active","updated_by","updated_at"],
  "private.tms_user_scopes": ["profile_id","role","active","updated_at","updated_by"],
  "private.website_inquiries": ["id","number","request_key","actor_id","payload","contact_name","email","phone","company","notes","lines","currency","total","is_test","status","created_at","updated_at"],
  "private.website_products": ["product_id","visible","featured","description","version","updated_at","updated_by","public_visible","public_featured","public_title","public_description","public_brand","public_badge","public_category_title"],
  "private.website_public_inquiries": ["id","number","request_key","payload","contact_name","email","phone","company","notes","lines","currency","total","visitor_hash","consent_at","status","internal_notes","created_at","reviewed_at","reviewed_by"],
  "private.website_public_settings": ["id","version","config","updated_at","updated_by"],
  "private.website_quote_intakes": ["request_id","quote_id","channel","created_at"],
  "private.website_settings": ["id","version","preview_enabled","show_prices","headline","introduction","phone","email","address","updated_at","updated_by"],
  "public.access_invitation_template": ["id","subject","message","version","updated_at","updated_by"],
  "public.accounting_accounts": ["id","code","name","type","active","is_system","created_at","updated_at","localization_country","localization_source_code","cashflow_class","account_type"],
  "public.accounting_adjustments": ["id","side","kind","invoice_id","supplier_invoice_id","issued_on","reference","reason","net","tax","total","status","entry_id","fiscal_authorization","created_by","created_at"],
  "public.accounting_analytic_allocations": ["line_id","project_id","percent","amount","created_at","created_by"],
  "public.accounting_assets": ["id","name","acquired_on","cost","residual","months","first_depreciation","asset_account_id","depreciation_account_id","expense_account_id","acquisition_entry_id","project_id","status","created_by","created_at","depreciation_method","declining_factor","depreciation_prorata"],
  "public.accounting_depreciations": ["id","asset_id","period","amount","entry_id"],
  "public.accounting_ec_profile": ["id","taxpayer_kind","regime","accounting_required","withholding_agent","ats_required","establishments","confirmed_on","evidence","payroll_expense_account_id","payroll_payable_account_id","payroll_deductions_account_id","retained_earnings_account_id","updated_at","updated_by","ats_establishments"],
  "public.accounting_entries": ["id","number","journal_id","entry_date","reference","source_type","source_id","status","reversal_of","memo","request_key","created_by","created_at","posted_at","posted_by","erp_reference"],
  "public.accounting_entry_lines": ["id","entry_id","account_id","label","debit","credit","partner_type","partner_id","tax_id","project_id","position","financial_account_id"],
  "public.accounting_fiscal_cancellations": ["id","source_invoice_id","document_type","establishment","emission_point","sequential_start","sequential_end","authorization_number","cancelled_on","portal_deregistered","evidence","reviewed_by","reviewed_at"],
  "public.accounting_fiscal_documents": ["id","source_type","source_id","document_type","document_number","identification_type","identification","authorization_number","support_code","payment_codes","related_party","base_zero","base_taxed","base_exempt","base_non_taxable","ice","vat","evidence","reviewed_at","reviewed_by","document_issued_on","modified_document_type","modified_number","modified_authorization"],
  "public.accounting_journals": ["id","code","name","kind","financial_account_id","active","created_at"],
  "public.accounting_maturities": ["id","side","invoice_id","supplier_invoice_id","term_id","due_date","amount","position"],
  "public.accounting_payment_terms": ["id","name","lines","active","created_at"],
  "public.accounting_periods": ["id","period_start","period_end","status","closed_at","closed_by","reopened_at","reopened_by","created_at"],
  "public.accounting_permissions": ["profile_id","can_view","can_create","can_edit","can_delete","can_validate","can_export","can_close","updated_at","updated_by","can_read_all","can_pay"],
  "public.accounting_received_sri": ["id","invoice_id","access_key","issuer_ruc","number","issued_on","amount","lines","authorized_at","xml_path","xml_sha256","verified_by","verified_at","withholding_id"],
  "public.accounting_source_links": ["source_type","source_id","entry_id"],
  "public.accounting_taxes": ["id","name","code","rate","kind","country","valid_from","collected_account_id","deductible_account_id","active","created_at","valid_to"],
  "public.accounting_withholdings": ["id","side","invoice_id","supplier_invoice_id","issued_on","number","authorization_number","evidence","amount","lines","status","entry_id","created_by","created_at"],
  "public.app_modules": ["id","enabled","updated_at","updated_by"],
  "public.b2b_customer_access": ["customer_id","enabled","updated_at","updated_by","restricted_catalog"],
  "public.b2b_memberships": ["profile_id","customer_id","active","updated_at","updated_by","purchasing_role"],
  "public.bank_invoice_settlements": ["bank_id","request_key","invoice_id","receipt_id","payment_id","match_group_id","created_by","created_at"],
  "public.bank_match_banks": ["group_id","bank_id","amount"],
  "public.bank_match_groups": ["id","request_key","financial_account_id","note","created_by","created_at","cancelled_at","cancellation_reason"],
  "public.bank_match_sources": ["group_id","kind","source_id","amount"],
  "public.bank_transactions": ["id","financial_account_id","value_date","reference","description","amount","status","import_batch","imported_at","created_by"],
  "public.business_document_approvals": ["id","document_id","fingerprint","status","requested_by","requested_at","reviewed_by","reviewed_at","reason"],
  "public.business_document_files": ["id","document_id","revision","storage_path","filename","mime_type","file_size","created_by","created_at"],
  "public.business_documents": ["id","title","folder","notes","visibility","customer_id","supplier_id","sales_order_id","ticket_id","expires_on","archived","version","created_by","updated_by","created_at","updated_at","category_id","employee_id","source_table","source_id","source_module","source_record_id","source_filename","source_bucket","source_path","source_created_by","source_deleted","erp_reference","owner_id","next_action"],
  "public.coco_inventory_intelligence": ["product_id","calculated_at","demand_30d","demand_60d","demand_90d","avg_daily_demand","physical_stock","reserved_stock","available_stock","incoming_stock","lead_time_days","safety_stock","recommended_min","recommended_max","recommended_order_qty","days_of_cover","confidence","calculation_version","draft_purchase_stock"],
  "public.coco_recommendations": ["id","module","entity_type","entity_id","recommendation_type","priority","title","confidence","current_value","recommended_value","reasoning","status","created_at","reviewed_at","reviewed_by"],
  "public.commercial_matrix": ["id","product_id","supplier_id","purchase_price","sale_price","margin","margin_percent","active","created_at","updated_at","scenario_name","additional_cost","target_margin","base_sale_price","created_by","applied_by","applied_at","request_key"],
  "public.company_settings": ["id","currency","country","fiscal_year_start_month","updated_at","updated_by","receivable_account_id","payable_account_id","sales_account_id","purchase_account_id","tax_collected_account_id","tax_deductible_account_id","legal_name","address","tax_id","phone","email","website","logo_data","document_primary","document_secondary","configured","company_version","localization_country","localization_version"],
  "public.crm_activities": ["id","kind","subject","body","status","priority","owner_id","due_at","done_at","remind_at","lead_id","customer_id","contact_id","opportunity_id","invoice_id","customer_request_id","created_by","created_at","updated_at","automation_key","supplier_id"],
  "public.crm_contacts": ["id","customer_id","lead_id","first_name","last_name","job_title","email","phone","linkedin","decision_role","is_primary","notes","active","created_by","created_at","updated_at","contact_entity_id","identification","identification_kind","phone2","address","city","province","postal_code","country","lat","lng","website","industry","language","address_mode"],
  "public.crm_leads": ["id","kind","first_name","last_name","company","job_title","email","phone","phone2","address","city","country","website","industry","company_size","source_id","owner_id","status","priority","score","last_interaction_at","next_followup_at","notes","converted_customer_id","converted_at","active","created_by","created_at","updated_at","province","postal_code","contact_entity_id","identification","identification_kind","language","lat","lng"],
  "public.crm_lost_reasons": ["id","name","sort_order","active","created_at","updated_at"],
  "public.crm_opportunities": ["id","reference","title","customer_id","lead_id","contact_id","owner_id","source_id","stage_id","amount","probability","expected_close_date","priority","description","competitors","lost_reason_id","quote_invoice_id","won_at","lost_at","active","created_by","created_at","updated_at","weighted_amount","erp_reference"],
  "public.crm_opportunity_lines": ["id","opportunity_id","product_id","quantity","unit_price","discount","position","created_at"],
  "public.crm_pipeline_stages": ["id","name","sort_order","default_probability","is_won","is_lost","active","created_at","updated_at"],
  "public.crm_scoring_rules": ["id","event_key","label","points","active","created_at","updated_at"],
  "public.crm_sources": ["id","name","sort_order","active","created_at","updated_at"],
  "public.crm_targets": ["id","profile_id","period_kind","period_start","amount_goal","notes","created_by","created_at","updated_at"],
  "public.customer_addresses": ["id","customer_id","label","purpose","contact_name","phone","email","address","city","notes","active","created_by","created_at","province","postal_code","country","lat","lng","time_window","unloading_minutes","is_default","version","updated_at"],
  "public.customer_receipts": ["id","request_key","customer_id","financial_account_id","amount","paid_at","method","reference","notes","status","created_by","created_at","cancelled_at","cancellation_reason","payment_method_id"],
  "public.customer_request_lines": ["id","request_id","product_id","quantity","unit_price","tax_rate","line_total","created_at"],
  "public.customer_requests": ["id","customer_id","created_by","status","notes","total","created_at","updated_at","invoice_id","converted_at","requester_name","requester_email","erp_reference","requested_delivery_date","source_website_id","website_reference","requester_phone","requester_company","delivery_address_id","delivery_address_snapshot"],
  "public.customer_special_prices": ["id","customer_id","product_id","unit_price","created_at","contract_ref"],
  "public.customers": ["id","name","identification","address","city","province","phone","email","notes","active","created_at","updated_at","category","owner_id","source_id","crm_score","payment_terms_days","credit_limit","credit_hold_reason","postal_code","country","lat","lng","gps_address","identification_kind","contact_entity_id","phone2","website","industry","language"],
  "public.document_categories": ["id","name","created_by","created_at"],
  "public.dossier_followups": ["id","dossier_key","owner_id","next_action","due_date","updated_at","updated_by","closed_at","closed_by","closure_fingerprint","closure_note"],
  "public.erp_access_reviews": ["id","reviewed_by","reviewed_at","next_review","note","snapshot"],
  "public.erp_action_permissions": ["role","module","allow_create","allow_edit","allow_delete","allow_validate","allow_export","updated_at","updated_by"],
  "public.erp_approvals": ["id","module","document_id","fingerprint","reason","status","requested_by","requested_at","reviewed_by","reviewed_at","decision_reason"],
  "public.erp_audit_events": ["id","created_at","actor_id","table_name","record_id","operation","reason"],
  "public.erp_handovers": ["id","source_id","target_id","actor_id","reason","impact","created_at"],
  "public.erp_import_batches": ["id","request_key","kind","filename","created_by","created_at","status","source_rows"],
  "public.erp_import_rows": ["id","batch_id","row_number","data","status","error","result_id","imported_at"],
  "public.erp_notification_preferences": ["user_id","hidden_kinds","only_mine","updated_at"],
  "public.erp_policies": ["id","timezone","purchase_approval_amount","quote_discount_limit","minimum_margin","stock_adjustment_limit","stale_opportunity_days","escalation_days","stock_visibility","version","updated_by","updated_at","stock_adjustment_value_limit","stock_adjustment_approval_kinds","allow_self_approval_exception","picking_scan_mode","picking_location_required","product_readiness_required"],
  "public.erp_price_book_customers": ["book_id","customer_id"],
  "public.erp_price_books": ["id","name","kind","category","valid_from","valid_to","priority","status","created_by","created_at","approved_by","approved_at"],
  "public.erp_price_tiers": ["id","book_id","product_id","min_quantity","unit_price","product_category","price_method","discount_percent","price_factor","surcharge","rounding_increment"],
  "public.erp_reference_formats": ["kind","module_id","label_es","prefix","default_prefix","source_table","number_column","kind_value","version","updated_at","updated_by"],
  "public.expense_categories": ["id","name","account_id","sort_order","active"],
  "public.expense_receipts": ["id","expense_id","filename","mime_type","data_url","created_at","created_by"],
  "public.expenses": ["id","reference","expense_date","supplier_id","category_id","description","amount_untaxed","tax_id","tax_amount","amount_total","currency","payment_method","financial_account_id","project_id","status","notes","request_key","created_by","created_at","updated_at","erp_reference","source_reviewed"],
  "public.external_invoice_deliveries": ["invoice_id","delivery_id","created_by","created_at"],
  "public.external_invoice_files": ["id","invoice_id","filename","mime_type","content_base64","created_at"],
  "public.external_invoice_lines": ["id","invoice_id","order_line_id","quantity"],
  "public.external_invoice_payments": ["id","request_key","invoice_id","amount","paid_at","method","reference","account","notes","status","cancellation_reason","cancelled_at","cancelled_by","created_by","created_at","financial_account_id","erp_reference","receipt_id","payment_method_id"],
  "public.external_invoices": ["id","request_key","order_id","number","issuer_ruc","access_key","software","issue_date","due_date","subtotal","tax","total","fiscal_status","notes","cancellation_reason","created_by","created_at","updated_at","document_kind","source_quote_id","document_snapshot","external_number","external_issue_date","external_status","payment_terms_days","payment_delivery_date","erp_reference"],
  "public.favorite_order_lines": ["id","favorite_order_id","product_id","quantity"],
  "public.favorite_orders": ["id","created_by","name","created_at"],
  "public.financial_accounts": ["id","name","kind","bank_name","currency","opening_balance","account_id","active","created_at","updated_at","created_by"],
  "public.fleet_alert_log": ["id","alert_key","kind","vehicle_id","driver_id","due_on","detail","notified_at"],
  "public.fleet_assignments": ["id","vehicle_id","driver_id","started_on","ended_on","notes","created_by","created_at"],
  "public.fleet_documents": ["id","vehicle_id","kind","reference","issued_on","expires_on","filename","mime_type","data_url","notes","created_by","created_at","updated_at"],
  "public.fleet_drivers": ["id","name","phone","employee_id","licence_number","licence_categories","licence_expiry","notes","active","created_by","created_at","updated_at","is_demo"],
  "public.fleet_fuel_logs": ["id","vehicle_id","driver_id","logged_on","odometer","litres","amount","station","full_tank","notes","request_key","created_by","created_at"],
  "public.fleet_maintenance": ["id","vehicle_id","performed_on","odometer","kind","garage","cost","notes","next_service_on","next_service_odometer","request_key","created_by","created_at"],
  "public.fleet_vehicles": ["id","reference","plate","brand","model","kind","energy","first_registration","odometer","status","gvwr_kg","payload_kg","photo","notes","active","created_by","created_at","updated_at","is_demo","cargo_volume_m3","erp_reference"],
  "public.fulfillment_incidents": ["id","preparation_id","pick_line_id","kind","quantity","reason","created_by","created_at"],
  "public.fulfillment_package_lines": ["package_id","pick_line_id","quantity"],
  "public.fulfillment_packages": ["id","preparation_id","barcode","weight_kg","length_cm","width_cm","height_cm","status","created_by","created_at","erp_reference"],
  "public.fulfillment_pick_lines": ["id","preparation_id","order_line_id","source_location_id","stage_location_id","planned","picked"],
  "public.fulfillment_preparations": ["id","order_id","number","status","assigned_to","shipment_id","partial_reason","created_at","updated_at","erp_reference"],
  "public.gama_ai_history": ["id","user_id","question","language","status","engine","answer","created_at","completed_at"],
  "public.gama_audit": ["id","table_name","row_id","action","actor_id","actor_role","changed_at","changed_fields"],
  "public.gama_document_references": ["table_name","document_id","node_index","dossier_number","ordinal","document_reference","dossier_label","legacy_reference","process_reference"],
  "public.hr_absence_decisions": ["id","absence_id","employee_id","status","reason","reviewed_by","created_at"],
  "public.hr_absence_private": ["absence_id","reason"],
  "public.hr_absences": ["id","employee_id","kind","start_date","end_date","days","status","created_at","start_fraction","end_fraction","decision_reason","reviewed_by","reviewed_at"],
  "public.hr_attendance": ["id","employee_id","started_at","ended_at","break_started_at","break_seconds","status","correction_reason","reviewed_by","reviewed_at"],
  "public.hr_audit": ["id","table_name","record_id","employee_id","actor_id","action","changed_at"],
  "public.hr_documents": ["id","employee_id","kind","title","effective_date","expires_on","storage_path","filename","created_by","created_at","supersedes_id","erp_reference"],
  "public.hr_ec_benefit_payments": ["id","benefit_id","request_key","amount","paid_on","financial_account_id","reference","entry_id","created_by","created_at"],
  "public.hr_ec_benefits": ["id","employee_id","kind","from_date","to_date","amount","source_id","entry_id","created_by","created_at"],
  "public.hr_ec_employee_terms": ["id","employee_id","effective_from","decimo13_mode","decimo14_mode","reserve_mode","region","other_fulltime","sectoral_minimum","work_ratio","bank_name","bank_number","bank_kind","beneficiary_id","evidence","created_by","created_at"],
  "public.hr_ec_parameters": ["id","year","parameters","evidence","confirmed_by","confirmed_at","created_at"],
  "public.hr_ec_payroll_signatures": ["payroll_id","employee_id","signed_by","signed_at","snapshot_hash","signature_png"],
  "public.hr_ec_utilities": ["id","year","request_key","net_profit","calculation","evidence","created_by","created_at","entry_id"],
  "public.hr_employee_private": ["employee_id","identification","email","phone","contract_type","hire_date","end_date","salary","annual_leave_days","notes"],
  "public.hr_employee_skills": ["id","employee_id","skill","level","valid_until","verified_on","notes"],
  "public.hr_employees": ["id","full_name","position","department","active","created_at","profile_id","manager_id","photo_data"],
  "public.hr_holidays": ["day","label"],
  "public.hr_leave_accounts": ["id","employee_id","year","entitlement","carryover","adjustment","accrual_mode","active_from","active_to","reason"],
  "public.hr_lifecycle_tasks": ["id","employee_id","kind","title","owner_id","due_date","completed_at","completed_by","note","created_at"],
  "public.hr_payroll": ["id","employee_id","period","source_ref","gross","net","employer_cost","cost_center","status","created_at","erp_reference","ec_calculation"],
  "public.hr_payroll_payments": ["id","payroll_id","paid_on","amount","reference","status","reason","created_at","financial_account_id"],
  "public.hr_shifts": ["id","employee_id","starts_at","ends_at","break_minutes","note"],
  "public.hr_staffing_rules": ["id","department","minimum","weekdays","updated_at"],
  "public.hr_work_patterns": ["id","employee_id","effective_from","weekdays","daily_hours"],
  "public.inventory_count_lines": ["id","count_id","product_id","location_id","expected_quantity","counted_quantity","variance","validated","counted_by","counted_at","recount_quantity","recounted_by","recounted_at"],
  "public.inventory_counts": ["id","warehouse_id","reference","status","created_by","started_at","completed_at","created_at","erp_reference","blind","cycle_days","next_due","scope_location_id","scope_category","request_key","assigned_to","due_date","priority","scope_product_id","repeat_of"],
  "public.invoice_lines": ["id","invoice_id","product_id","quantity","unit_price","tax_rate","line_total","quote_description","quote_list_price","quote_discount","sales_unit_id","sales_unit_label","sales_unit_factor","sales_quantity","price_source"],
  "public.invoices": ["id","invoice_number","customer_id","user_id","status","issue_date","subtotal","tax","total","notes","created_at","updated_at","archive_number","quote_state","quote_request_key","quote_revision","quote_details","quote_valid_until","quote_sent_at","quote_accepted_at","quote_accepted_by","quote_acceptance_channel","quote_acceptance_reference","erp_reference","accepted_snapshot"],
  "public.knowledge_articles": ["id","parent_id","slug","title","body","properties","version","created_by","updated_by","created_at","updated_at","erp_reference"],
  "public.pm_baselines": ["id","project_id","name","snapshot","created_by","created_at"],
  "public.pm_comments": ["id","project_id","item_id","body","created_by","created_at"],
  "public.pm_cost_entries": ["id","project_id","entry_date","kind","description","quantity","unit_cost","amount","source_reference","created_by","created_at","cancelled_at","cancellation_reason"],
  "public.pm_files": ["id","project_id","item_id","filename","storage_path","url","version","supersedes_id","created_by","created_at"],
  "public.pm_items": ["id","project_id","kind","reference","title","description","phase_id","work_package_id","deliverable_id","owner_id","approver_id","status","priority","start_date","due_date","forecast_date","progress","data","version","created_by","created_at","updated_at","erp_reference"],
  "public.pm_links": ["id","project_id","item_id","kind","target_id","currency","exchange_rate","created_by","created_at"],
  "public.pm_members": ["id","project_id","profile_id","role","capacity_hours"],
  "public.pm_projects": ["id","reference","name","description","manager_id","sponsor_id","customer_id","department","project_type","mode","status","priority","start_date","due_date","forecast_date","budget","currency","estimate_remaining","budget_tolerance","schedule_tolerance","business_case","scope","closure","version","created_by","created_at","updated_at","closed_at","erp_reference"],
  "public.pm_templates": ["id","name","code","definition","version","created_by","created_at","updated_at"],
  "public.product_lots": ["id","product_id","code","expires_on","created_at","created_by"],
  "public.product_price_history": ["sequence","id","product_id","changed_at","changed_by","before_prices","after_prices"],
  "public.product_units": ["id","product_id","label","factor","barcode","active"],
  "public.products": ["id","barcode","name","reference","category","location","supplier_id","min_stock","stock","sale_price","tax_rate","active","created_at","updated_at","photo_data","has_photo","description","family","lines","brand","presentation","qty_per_carton","weight_g","volume_cm3","max_stock","sale_price_b","purchase_price","order_minimum","order_multiple","base_unit","product_kind","lot_tracking","lot_tracking_since","replenishment_excluded","replenishment_exclusion_reason","photo_is_illustrative"],
  "public.profiles": ["id","full_name","role","active","created_at","updated_at","email","access_profile","deleted_at"],
  "public.project_time_entries": ["id","request_key","project_id","employee_id","worked_on","hours","description","status","hourly_cost","evidence","approved_by","approved_at","cost_entry_id","created_by","created_at","updated_at"],
  "public.purchase_order_lines": ["id","purchase_order_id","product_id","quantity","received_quantity","unit_cost","tax_rate","line_total","created_at"],
  "public.purchase_orders": ["id","supplier_id","order_number","order_date","expected_date","status","notes","subtotal","tax","total","created_by","created_at","updated_at","erp_reference","destination_location_id","source_kind","source_order_id"],
  "public.purchase_service_acceptances": ["id","purchase_line_id","quantity","evidence","created_at","created_by"],
  "public.quote_events": ["id","quote_id","revision","action","actor_id","at","detail"],
  "public.receivable_followups": ["id","invoice_id","kind","amount","due_date","owner_id","note","status","resolution","created_at","created_by"],
  "public.reconciliations": ["id","bank_transaction_id","match_type","match_id","amount","notes","matched_by","matched_at"],
  "public.reorder_rules": ["id","product_id","warehouse_id","min_quantity","max_quantity","reorder_quantity","supplier_id","lead_time_days","active","created_at"],
  "public.return_credits": ["id","number","return_id","invoice_id","supplier_invoice_id","supplier_reference","amount","issued_on","notes","filename","mime_type","data_url","created_by","created_at","erp_reference"],
  "public.return_files": ["id","return_id","filename","mime_type","data_url","created_by","created_at"],
  "public.return_lines": ["id","return_id","product_id","quantity","unit_price","tax_rate","delivery_line_id","purchase_order_line_id","disposition","quarantine_location_id","hold_reservation_id","processed_at","notes","created_at"],
  "public.return_orders": ["id","number","kind","status","customer_id","order_id","delivery_id","invoice_id","supplier_id","purchase_order_id","supplier_invoice_id","reason","notes","financial_action","carrier","tracking","shipped_on","received_at","processed_at","closed_at","created_by","created_at","updated_at","erp_reference","service_ticket_id"],
  "public.return_refunds": ["id","return_id","amount","paid_at","method","reference","notes","request_key","created_by","created_at","erp_reference","financial_account_id"],
  "public.role_module_access": ["role","disabled_modules","version","updated_at","updated_by","display_name","base_role","is_custom"],
  "public.sales_deliveries": ["id","number","order_id","request_key","tms_delivery_id","dispatched_at","created_by","notes","loading_required","loading_version","departed_at","departed_by","departure_driver_id","departure_vehicle","erp_reference"],
  "public.sales_delivery_lines": ["id","delivery_id","order_line_id","location_id","quantity","loading_barcode"],
  "public.sales_events": ["id","order_id","action","entity_id","actor_id","detail","created_at"],
  "public.sales_fulfillment_options": ["id","order_id","line_id","kind","quantity","replacement_product_id","unit_price","tax_rate","promised_date","notes","status","responded_by","responded_at","agreement_reference","created_by","created_at","customer_decision","customer_responded_by","customer_responded_at","customer_response_fingerprint","customer_response_snapshot"],
  "public.sales_order_lines": ["id","order_id","product_id","product_name","reference","quantity","unit_price","tax_rate","promised_date","next_dispatch_quantity","delivery_policy","product_kind","sales_unit_id","sales_unit_label","sales_unit_factor","sales_quantity","price_source"],
  "public.sales_orders": ["id","number","request_key","customer_id","customer_name","customer_identification","delivery_address","source_quote_id","source_request_id","status","notes","created_by","created_at","updated_at","source_opportunity_id","erp_reference"],
  "public.sales_reservation_links": ["reservation_id","line_id"],
  "public.sales_service_completions": ["id","order_line_id","quantity","performed_on","evidence","created_at","created_by","cancelled_at","cancelled_by","cancellation_reason"],
  "public.service_events": ["id","ticket_id","actor_id","created_at","changes"],
  "public.service_messages": ["id","ticket_id","body","created_by","created_at","visibility"],
  "public.service_sla_rules": ["priority","response_hours","resolution_hours"],
  "public.service_tickets": ["id","number","subject","description","customer_id","sales_order_id","assigned_to","status","priority","category","warranty_until","due_date","resolution","archived","version","created_by","updated_by","created_at","updated_at","resolved_at","erp_reference","delivery_id","return_id","replacement_order_id","root_cause","response_due_at","first_response_at","resolution_due_at","portal_request_key"],
  "public.sri_document_issues": ["id","document_type","source_type","source_id","customer_id","supplier_id","route_id","environment","issuer_ruc","establishment","emission_point","sequential","numeric_code","access_key","status","snapshot","receipt","authorization_response","signed_xml_path","authorized_xml_path","ride_path","sent_at","authorized_at","delivered_at","last_error","created_by","created_at","updated_at","withholding_id"],
  "public.sri_electronic_documents": ["id","user_id","invoice_id","cod_doc","ambiente","clave_acceso","secuencial","status","numero_autorizacion","fecha_autorizacion","messages","signed_xml","authorized_xml","created_at","updated_at"],
  "public.sri_invoice_issues": ["id","source_invoice_id","customer_id","environment","issuer_ruc","establishment","emission_point","sequential","numeric_code","access_key","status","snapshot","receipt","authorization_response","signed_xml_path","authorized_xml_path","ride_path","sent_at","authorized_at","delivered_at","last_error","created_by","created_at","updated_at"],
  "public.sri_purchase_queue": ["supplier_invoice_id","created_at","issue_id","last_error"],
  "public.sri_settings": ["id","user_id","environment","ruc","razon_social","estab","pto_emi","dir_matriz","email","created_at","updated_at","provider_ruc","accounting_obligation","trade_name","establishment_address"],
  "public.stock_adjustment_files": ["id","adjustment_id","filename","data_url","created_by","created_at"],
  "public.stock_adjustment_requests": ["id","request_key","product_id","location_id","expected_quantity","target_quantity","reason","status","requested_by","requested_at","reviewed_by","reviewed_at","decision_reason","movement_id","kind","submission_hash","approval_limit","lot_id","erp_reference","approval_value","approval_value_limit"],
  "public.stock_cost_books": ["product_id","method","quantity","value","started_at","created_by","stock_account_id","expense_account_id","auto_accounting","receipt_account_id","opening_counter_account_id","standard_unit_cost"],
  "public.stock_cost_layers": ["id","product_id","movement_id","quantity","remaining","unit_cost","created_at","opening"],
  "public.stock_integrity_cases": ["id","product_id","observed_at","catalogue_quantity","located_quantity","resolved_at","resolved_by","resolution"],
  "public.stock_landed_allocations": ["landed_cost_id","layer_id","amount","stock_value","consumed_value"],
  "public.stock_landed_costs": ["id","request_key","source_reference","amount","currency","allocation","reason","created_at","created_by"],
  "public.stock_lot_balances": ["lot_id","location_id","quantity"],
  "public.stock_lot_movements": ["id","movement_id","lot_id","source_location_id","destination_location_id","quantity","created_at","created_by"],
  "public.stock_movements": ["id","product_id","type","quantity","reason","comment","user_id","created_at","stock_before","stock_after","source_location_id","destination_location_id","movement_type","reference_type","reference_id","erp_reference","unit_cost_at_movement"],
  "public.stock_quants": ["id","product_id","location_id","quantity","reserved_quantity","updated_at"],
  "public.stock_reservations": ["id","product_id","location_id","quantity","reference_type","reference_id","status","created_by","created_at","released_at","erp_reference"],
  "public.stock_valuation_entries": ["sequence","product_id","movement_id","landed_cost_id","kind","quantity","value_delta","expense_delta","quantity_after","value_after","method","source","created_at","created_by","effective_on"],
  "public.supplier_invoice_match_lines": ["id","match_id","purchase_line_id","quantity","unit_cost","tax_rate"],
  "public.supplier_invoice_matches": ["id","invoice_id","purchase_order_id","variance_reason","approved_by","approved_at","lines"],
  "public.supplier_invoice_payments": ["id","supplier_invoice_id","financial_account_id","paid_at","amount","method","reference","status","cancellation_reason","notes","request_key","created_by","created_at","erp_reference","payment_method_id"],
  "public.supplier_invoices": ["id","number","supplier_id","purchase_order_id","issue_date","payment_terms_days","due_date","subtotal","tax","total","tax_id","status","project_id","notes","request_key","created_by","created_at","updated_at","erp_reference","match_required","source_reviewed","deferral_lines"],
  "public.supplier_product_offers": ["id","supplier_id","product_id","supplier_reference","unit_cost","currency","minimum_quantity","pack_quantity","lead_time_days","additional_unit_cost","valid_from","valid_to","active","created_by","created_at"],
  "public.supplier_withholding_policies": ["supplier_id","income_code","income_rate","income_account_id","vat_code","vat_rate","vat_account_id","valid_from","valid_to","evidence","reviewed_by","reviewed_at"],
  "public.suppliers": ["id","name","tax_id","address","city","province","postal_code","country","phone","email","contact_name","notes","active","created_at","updated_at","identification_kind","contact_entity_id","phone2","website","industry","language","lat","lng"],
  "public.tms_attempt_lines": ["attempt_id","delivery_line_id","quantity","accepted","refused","missing","deferred"],
  "public.tms_attempt_proofs": ["id","attempt_id","kind","object_path","content_hash","byte_size","created_at","created_by"],
  "public.tms_deliveries": ["id","customer","address","delivery_date","time_window","priority","weight","volume","status","lat","lng","route_id","driver_id","actual_arrival","delivered_at","notes","created_at","created_by","customer_id","erp_reference","service_minutes","eta_at","version","promised_from","promised_until","initial_promised_from","initial_promised_until","settled_at","settled_by","settlement_note","invoice_reviewed_at","cargo_verified_at","cargo_verified_by","eta_basis"],
  "public.tms_delivery_attempts": ["id","delivery_id","route_id","driver_id","attempt_no","request_key","result","receiver_name","reason","occurred_at","received_at","actor_id","base_version","gps","return_id"],
  "public.tms_delivery_incidents": ["id","delivery_id","driver_id","reason","note","created_at","created_by","rescheduled_for","attempt_id","resolved_at","resolved_by","resolution"],
  "public.tms_events": ["id","delivery_id","at","type","note","customer","user_id","attempt_id","detail"],
  "public.tms_loading_allocations": ["scan_id","delivery_line_id","quantity"],
  "public.tms_loading_scans": ["id","request_key","delivery_id","barcode","quantity","scanned_by","scanned_at","voided_at","voided_by","void_reason"],
  "public.tms_proofs": ["delivery_id","photo","signature","captured_at","captured_by","erp_reference","latitude","longitude","gps_accuracy_m","gps_recorded_at","gps_status","received_at"],
  "public.tms_route_schedules": ["id","route_id","starts_at","legs","road_source","road_km","duration_minutes","updated_by","updated_at","window_exceptions","needs_review"],
  "public.tms_routes": ["id","route_date","driver_id","driver_name","vehicle","stops","distance","weight","volume","status","created_at","vehicle_id","erp_reference","manual_override","version","cost_per_km","cost_basis","distance_basis","closed_at","closed_by","route_points"],
  "public.tms_settings": ["id","depot","depot_lat","depot_lng","return_depot","updated_at"],
  "public.user_home_preferences": ["user_id","module_order","updated_at","kpi_selected"],
  "public.warehouse_locations": ["id","warehouse_id","parent_id","code","name","type","barcode","picking_priority","active","created_at","shelf_id","role"],
  "public.warehouse_shelves": ["id","warehouse_id","code","name","column_count","row_count","parent_id","version","created_at","created_by","updated_at","updated_by"],
  "public.warehouses": ["id","code","name","address","city","active","created_at","updated_at"]
}'::jsonb
$policy$;
revoke all on function private.recovery_business_export_columns() from public,anon,authenticated,service_role;

create or replace function private.gama_recovery_export() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t record;rows jsonb;names text;allowed jsonb:=private.recovery_business_export_columns();
 tables jsonb:='{}';counts jsonb:='{}';meta jsonb:='{}';excluded_tables jsonb;excluded_columns jsonb;
begin
 if auth.uid() is null or not private.erp_module_allowed('backup',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not private.erp_action_allowed('backup','export') then raise exception 'EXPORT_NOT_ALLOWED';end if;
 for t in select n.nspname schema_name,c.relname table_name,n.nspname||'.'||c.relname qualified
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and n.nspname in('public','private')
   and allowed ? (n.nspname||'.'||c.relname) order by n.nspname,c.relname
 loop
  select string_agg(format('%I',column_name),',' order by ordinal_position),
   jsonb_agg(jsonb_build_object('name',column_name,'generated',is_generated,'identity',is_identity) order by ordinal_position)
   into names,rows from information_schema.columns
   where table_schema=t.schema_name and table_name=t.table_name
    and (allowed->t.qualified) ? column_name;
  if names is null then raise exception 'EXPORT_SCHEMA_CHANGED';end if;
  meta:=meta||jsonb_build_object(t.qualified,rows);
  execute format('select coalesce(jsonb_agg(to_jsonb(export_row)),''[]''::jsonb) from (select %s from %I.%I) export_row',names,t.schema_name,t.table_name) into rows;
  tables:=tables||jsonb_build_object(t.qualified,rows);
  counts:=counts||jsonb_build_object(t.qualified,jsonb_array_length(rows));
 end loop;
 select coalesce(jsonb_agg(n.nspname||'.'||c.relname order by n.nspname,c.relname),'[]'::jsonb)
 into excluded_tables from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind='r' and n.nspname in('public','private') and not (allowed ? (n.nspname||'.'||c.relname));
 select coalesce(jsonb_object_agg(qualified,columns),'{}'::jsonb) into excluded_columns from (
  select table_schema||'.'||table_name qualified,jsonb_agg(column_name order by ordinal_position) columns
  from information_schema.columns where allowed ? (table_schema||'.'||table_name)
   and not ((allowed->(table_schema||'.'||table_name)) ? column_name)
  group by table_schema,table_name
 ) omitted;
 return jsonb_build_object('format','architect-application-export','version',1,'created_at',now(),'created_by',auth.uid(),
  'scope','business_data_and_files',
  'coverage',jsonb_build_object('mode','business-allowlist','policy_version','2026-11-07','policy_hash',md5(allowed::text),
   'full_backup',false,'tables',(select jsonb_agg(k order by k) from jsonb_object_keys(tables) as keys(k)),
   'excluded_tables',excluded_tables,'excluded_columns',excluded_columns,
   'storage_buckets',jsonb_build_array('business-documents','hr-documents','pm-documents','sri-documents','tms-attempt-proofs')),
  'excludes',jsonb_build_array('authentication_secrets','infrastructure_configuration','physical_database_backup',
   'service_and_oauth_credentials','offline_encryption_keys','runtime_authorization_and_queues','existing_public_access_tokens','raw_audit_row_copies'),
  'tables',tables,'counts',counts,'columns',meta,
  'identities',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'email',u.email)),'[]') from auth.users u),
  'storage_objects',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'bucket',o.bucket_id,'path',o.name)),'[]') from storage.objects o
   where o.bucket_id in('business-documents','hr-documents','pm-documents','sri-documents','tms-attempt-proofs')),
  'storage_buckets',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'public',false,
   'file_size_limit',b.file_size_limit,'allowed_mime_types',b.allowed_mime_types)),'[]') from storage.buckets b
   where b.id in('business-documents','hr-documents','pm-documents','sri-documents','tms-attempt-proofs')));
end $$;
revoke all on function private.gama_recovery_export() from public,anon,service_role;
grant execute on function private.gama_recovery_export() to authenticated;
notify pgrst,'reload schema';
