-- Older quotes have no managed quote_state. Only their actual draft status
-- belongs to requests; issued archives retain COT and are never reclassified.
do $$declare body text;anchor text;begin
 select pg_get_functiondef('private.sales_draft_request_reference()'::regprocedure) into body;
 anchor:='if new.quote_state=''draft''';
 if strpos(body,anchor)=0 then raise exception 'LEGACY_DRAFT_TRIGGER_ANCHOR';end if;
 execute replace(body,anchor,'if (new.quote_state=''draft'' or (new.quote_state is null and new.status=''draft''))');
 select pg_get_functiondef('private.sales_unified_quote_list(jsonb)'::regprocedure) into body;
 anchor:='case when q.quote_state=''draft'' then';
 if strpos(body,anchor)=0 then raise exception 'LEGACY_DRAFT_DISPLAY_ANCHOR';end if;
 body:=replace(body,anchor,'case when (q.quote_state=''draft'' or (q.quote_state is null and q.status=''draft'')) then');
 anchor:='q.archive_number,q.quote_state,q.quote_valid_until';
 if strpos(body,anchor)=0 then raise exception 'LEGACY_DRAFT_STATE_ANCHOR';end if;
 body:=replace(body,anchor,'q.archive_number,coalesce(q.quote_state,case when q.status=''draft'' then ''draft'' else ''legacy'' end) quote_state,q.quote_valid_until');
 body:=replace(body,'coalesce(d.quote_state,''draft'')=p_data->>''status''','d.quote_state=p_data->>''status''');
 execute body;
end $$;
drop trigger sales_draft_request_reference on public.invoices;
create trigger sales_draft_request_reference after insert or update of quote_state,status on public.invoices
 for each row execute function private.sales_draft_request_reference();
do $$declare q record;begin
 for q in select i.id from public.invoices i where i.quote_state is null and i.status='draft'
  and not exists(select 1 from public.customer_requests r where r.invoice_id=i.id or r.id=i.quote_request_key)
  order by i.created_at,i.id loop
  perform private.erp_issue_reference('request','draft/invoices/'||q.id);
 end loop;
end $$;
notify pgrst,'reload schema';
