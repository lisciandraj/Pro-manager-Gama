-- Freeze the client comment in new internal invoices, including older linked quotes.
do $$ declare src text;needle text:='jsonb_build_object(''details'',q.quote_details,';replacement text;begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 if position(needle in src)=0 then raise exception 'Unexpected invoice snapshot function';end if;
 replacement:=$r$jsonb_build_object('details',q.quote_details||jsonb_build_object('customer_comment',coalesce(q.quote_details->>'customer_comment',(select cr.notes from public.customer_requests cr where cr.invoice_id=q.id order by cr.created_at,cr.id limit 1),'')),$r$;
 execute replace(src,needle,replacement);
end $$;
