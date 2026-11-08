-- Keep the legacy RPC compatible while applying the current billing authority.
-- Full-order legacy invoices cannot rebill lines belonging to a grouped or
-- partial invoice; all invoice producers use the same sales transaction lock.
do $audit$
declare src text;before_text text;
begin
 src:=pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure);
 before_text:='if p_action=''eligibility'' then';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:legacy_invoice_authority';end if;
 src:=replace(src,before_text,$patch$
 perform private.sales_access(case when p_action='create' then 'invoice_create' else 'invoice_list' end);
 if p_action='link_external' and (not private.erp_action_allowed('sales-orders','edit')
  or not private.erp_action_allowed('payments','edit')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('create','link_external') then perform pg_advisory_xact_lock(741932,1);end if;
 if p_action='eligibility' then$patch$);
 before_text:='if exists(select 1 from public.external_invoices where order_id=o.id and fiscal_status not in (''cancelled'',''rejected'')) then raise exception ''ORDER_ALREADY_INVOICED'';end if;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:legacy_invoice_capacity';end if;
 src:=replace(src,before_text,$patch$
 if exists(select 1 from public.external_invoices f where f.fiscal_status not in ('cancelled','rejected')
  and (f.order_id=o.id or exists(select 1 from private.sales_invoice_orders x where x.invoice_id=f.id and x.order_id=o.id)
   or exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
    where il.invoice_id=f.id and ol.order_id=o.id))) then raise exception 'ORDER_ALREADY_INVOICED';end if;
 $patch$);
 before_text:='where f.source_quote_id=quote_row.id and f.document_kind=''internal''';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:legacy_invoice_eligibility';end if;
 src:=replace(src,before_text,'where (f.source_quote_id=quote_row.id or exists(select 1 from private.sales_invoice_orders x where x.invoice_id=f.id and x.order_id=order_row.id)) and f.document_kind=''internal''');
 execute src;
end $audit$;
notify pgrst,'reload schema';
