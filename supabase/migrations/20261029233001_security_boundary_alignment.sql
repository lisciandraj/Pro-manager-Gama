-- Align alternate read and command paths with the current account/module policy.
-- Technical migration only: this changes authorization, not business records.
create or replace function private.erp_internal_account() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p
  where p.id=auth.uid() and p.active and p.deleted_at is null
  and p.role in ('administrador','comercial','almacenero'))
$$;

-- Preserve live SQL implementations and their existing signatures/grants.
-- A changed anchor aborts the migration rather than silently omitting a gate.
do $audit$
declare src text;before_text text;after_text text;
begin
 src:=pg_get_functiondef('private.automation_delegation_ok()'::regprocedure);
 before_text:='and p.active and p.deleted_at is null and p.role=''administrador''';
 after_text:=before_text||' and (u.banned_until is null or u.banned_until<=now())';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:delegation';end if;
 execute replace(src,before_text,after_text);
 src:=pg_get_functiondef('private.automation_run(integer)'::regprocedure);
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:runner';end if;
 execute replace(src,before_text,after_text);

 src:=pg_get_functiondef('private.api_gama_stock_reserve(uuid,uuid,numeric,text,uuid)'::regprocedure);
 before_text:='private.current_user_role() not in';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:reserve';end if;
 execute replace(src,before_text,'coalesce(private.current_user_role(),'''') not in');

 src:=pg_get_functiondef('private.api_gama_register_stock_movement(uuid,text,numeric,text,text)'::regprocedure);
 before_text:='select coalesce(sum(quantity),0) into v_total_before from public.stock_quants where product_id=p_product_id;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:manual_movement';end if;
 execute replace(src,before_text,$gate$
 if exists(select 1 from public.erp_policies policy join public.products product on product.id=p_product_id where policy.id and
  ((policy.stock_adjustment_value_limit is not null and
    (coalesce(product.purchase_price,0)<=0 or abs(v_delta)*product.purchase_price>policy.stock_adjustment_value_limit))
   or cardinality(policy.stock_adjustment_approval_kinds)>0)) then
  -- This legacy contract has no structured adjustment kind. Use the approval
  -- workflow whenever it cannot establish the configured policy exception.
  raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';
 end if;
 $gate$||before_text);

 src:=pg_get_functiondef('private.gama_receive_purchase(uuid,jsonb,text)'::regprocedure);
 if src!~* '\mbegin\M' then raise exception 'SECURITY_PATCH_ANCHOR:purchase_receipt';end if;
 execute regexp_replace(src,'\mbegin\M',$gate$begin
  if not private.erp_action_allowed('gamaPurchasesV14','validate') then raise exception 'ACTION_NOT_ALLOWED:gamaPurchasesV14:validate';end if;
 $gate$,'i');

 src:=pg_get_functiondef('private.dashboard_access(text)'::regprocedure);
 before_text:='not coalesce(module_id=any(a.disabled_modules),false)';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:dashboard_role';end if;
 src:=replace(src,before_text,'not coalesce(a.disabled_modules && array[module_id,private.erp_module_parent(module_id)],false)');
 before_text:='m.id=module_id and not m.enabled';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:dashboard_company';end if;
 execute replace(src,before_text,'m.id in (module_id,private.erp_module_parent(module_id)) and not m.enabled');

 src:=pg_get_functiondef('private.document_original_access(public.business_documents)'::regprocedure);
 before_text:='when ''tms_proofs'' then return private.current_user_role() in (''administrador'',''almacenero'');';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:document_proof';end if;
 src:=replace(src,before_text,'when ''tms_proofs'' then return private.tms_can_read(d.source_id);');
 before_text:='when ''expense_receipts'' then return private.gama_accounting_may(''view'');';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:document_expense';end if;
 execute replace(src,before_text,'when ''expense_receipts'' then return private.gama_accounting_may(''view'') and private.gama_accounting_rights()->>''scope''=''all'';');
end $audit$;

create or replace function private.gama_accounting_rights() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r text;p public.accounting_permissions;rights jsonb;permission text;
 none jsonb:=jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'pay',false,'scope','none');
begin
 r:=coalesce(private.current_user_role(),'');
 if auth.uid() is null or r='' then return none;end if;
 rights:=case when r='administrador' then jsonb_build_object('view',true,'create',true,'edit',true,'delete',true,'validate',true,'export',true,'close',true,'pay',true,'scope','all')
 when r='comercial' then jsonb_build_object('view',true,'create',false,'edit',false,'delete',false,'validate',false,'export',true,'close',false,'pay',false,'scope','commercial') else none end;
 select * into p from public.accounting_permissions where profile_id=auth.uid();
 if found then
  rights:=rights||jsonb_build_object('view',p.can_view,'create',p.can_create,'edit',p.can_edit,'delete',p.can_delete,'validate',p.can_validate,'export',p.can_export,'close',p.can_close,'pay',coalesce(p.can_pay,p.can_create));
  if p.can_view and (p.can_read_all or p.can_create or p.can_validate or p.can_close) then rights:=rights||jsonb_build_object('scope','all');
  elsif p.can_view and rights->>'scope'='none' then rights:=rights||jsonb_build_object('scope','commercial');end if;
 end if;
 foreach permission in array array['create','edit','delete','validate','export'] loop
  rights:=jsonb_set(rights,array[permission],to_jsonb(coalesce((rights->>permission)::boolean,false) and private.erp_action_allowed('accounting',permission)));
 end loop;
 rights:=rights||jsonb_build_object(
  'close',coalesce((rights->>'close')::boolean,false) and private.erp_action_allowed('accounting','validate'),
  'pay',coalesce((rights->>'pay')::boolean,false) and private.erp_action_allowed('accounting','create') and private.erp_action_allowed('accounting','validate'));
 return rights;
end $$;

-- Commercial summaries remain available through scoped invoker/RPC projections.
-- Raw ledger, banking, supplier and expense tables require full financial scope.
do $$declare t text;begin
 foreach t in array array['accounting_accounts','accounting_journals','accounting_periods','accounting_entries',
  'accounting_entry_lines','financial_accounts','bank_transactions','reconciliations','expenses',
  'expense_categories','expense_receipts','supplier_invoices','supplier_invoice_payments','accounting_taxes'] loop
  execute format('create policy security_financial_scope on public.%I as restrictive for select to authenticated using (private.erp_module_allowed(''accounting'',array[''administrador'',''comercial'']) and private.gama_accounting_may(''view'') and private.gama_accounting_rights()->>''scope''=''all'')',t);
 end loop;
end $$;

do $audit$
declare src text;before_text text;
begin
 -- All configured stages remain required when an individual approver is inactive.
 src:=pg_get_functiondef('private.gama_b2b_action(text,jsonb)'::regprocedure);
 before_text:='select min(c.stage) into next_stage from private.commerce_approvers c join public.b2b_memberships m on m.profile_id=c.approver_id and m.customer_id=cid and m.active and m.purchasing_role=''approver'' where c.customer_id=cid and c.requester_id=auth.uid();';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:approval_stage';end if;
 execute replace(src,before_text,'select min(c.stage) into next_stage from private.commerce_approvers c where c.customer_id=cid and c.requester_id=auth.uid();');

 src:=pg_get_functiondef('private.gama_b2b_product_favorites(text,jsonb)'::regprocedure);
 before_text:='from private.b2b_product_favorites f where f.customer_id=cid)';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:favorite_ids';end if;
 src:=replace(src,before_text,'from private.b2b_product_favorites f where f.customer_id=cid and private.commerce_product_allowed(cid,f.product_id))');
 before_text:='where f.customer_id=cid and (term=';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:favorite_list';end if;
 src:=replace(src,before_text,'where f.customer_id=cid and private.commerce_product_allowed(cid,f.product_id) and (term=');
 before_text:='if wanted then';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:favorite_set';end if;
 execute replace(src,before_text,'if wanted then if not private.commerce_product_allowed(cid,pid) then raise exception ''COMMERCE_CATALOG_RESTRICTED'';end if;');

 src:=pg_get_functiondef('private.gama_b2b_fulfillment(text,jsonb)'::regprocedure);
 -- Check after taking the membership lock, so concurrent revocation is observed.
 before_text:=E'  cid:=private.gama_b2b_customer();\n end if;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:fulfillment_role';end if;
 src:=replace(src,before_text,$gate$  cid:=private.gama_b2b_customer();
  if not exists(select 1 from public.b2b_memberships m where m.profile_id=auth.uid() and m.customer_id=cid and m.active and m.purchasing_role in ('buyer','approver')) then raise exception 'COMMERCE_APPROVAL_REQUIRED';end if;
 end if;$gate$);
 before_text:='''can_respond'',f.status=';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:fulfillment_display';end if;
 execute replace(src,before_text,'''can_respond'',exists(select 1 from public.b2b_memberships m where m.profile_id=auth.uid() and m.customer_id=cid and m.active and m.purchasing_role in (''buyer'',''approver'')) and f.status=');

 -- Only independently geocoded coordinates may cross unrelated contact records.
 src:=pg_get_functiondef('private.contact_geocode_enqueue(text,uuid)'::regprocedure);
 before_text:='where address_key=key and not conflicted';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:geocode_source';end if;
 execute replace(src,before_text,before_text||' and source=''Photon / OpenStreetMap contributors''');

 -- Reuse the existing intake lock before checking the shared email/day budgets.
 src:=pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure);
 before_text:='perform pg_advisory_xact_lock(hashtextextended(''public-web-visitor:''||visitor,0));';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:public_budget';end if;
 execute replace(src,before_text,'perform pg_advisory_xact_lock(741932,1);'||before_text);

 -- The human approval must display every stock target that the digest authorizes.
 src:=pg_get_functiondef('private.coco_agent_executor(text,jsonb)'::regprocedure);
 before_text:='''lot_tracking'',prod.lot_tracking,''lot_quantity'',lot_qty';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:approval_lot';end if;
 src:=replace(src,before_text,'''lot_tracking'',prod.lot_tracking,''lot_id'',lot_id,''lot_code'',(select pl.code from public.product_lots pl where pl.id=lot_id and pl.product_id=prod.id),''lot_quantity'',lot_qty');
 before_text:='if cmd.state<>''prepared'' then raise exception ''AGENT_COMMAND_CLOSED'';end if;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:execution_lot';end if;
 src:=replace(src,before_text,before_text||$gate$
 if coalesce((cmd.snapshot->>'lot_tracking')::boolean,false) and
  (nullif(cmd.snapshot->>'lot_id','') is null or cmd.snapshot->>'lot_id' is distinct from cmd.payload->>'lot_id') then raise exception 'AGENT_REPREPARE_REQUIRED';end if;
 $gate$);
 execute src;
 src:=pg_get_functiondef('private.coco_agent(text,jsonb)'::regprocedure);
 before_text:='if cmd.state<>''prepared'' or cmd.expires_at<=now() then raise exception ''AGENT_PROPOSAL_EXPIRED'';end if;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:human_lot';end if;
 execute replace(src,before_text,before_text||$gate$
 if coalesce((cmd.snapshot->>'lot_tracking')::boolean,false) and nullif(cmd.snapshot->>'lot_id','') is null then raise exception 'AGENT_REPREPARE_REQUIRED';end if;
 $gate$);
end $audit$;

notify pgrst,'reload schema';
