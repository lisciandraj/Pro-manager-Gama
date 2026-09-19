-- One transaction for a request-derived, editable quote and its source link.
create or replace function private.gama_quote_from_request(p_request_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req public.customer_requests; result jsonb; quote_id uuid; details jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 -- Match the sales/quote lock order, including simultaneous and retried requests.
 perform pg_advisory_xact_lock(741932,1);
 select * into req from public.customer_requests where id=p_request_id for update;
 if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
 if req.invoice_id is not null then
  return jsonb_build_object('id',req.invoice_id,'request_id',req.id,'existing',true);
 end if;
 if req.status not in ('pending','accepted') then raise exception 'REQUEST_CLOSED'; end if;
 if exists(select 1 from public.sales_orders where source_request_id=req.id) then raise exception 'REQUEST_HAS_ORDER'; end if;
 details:=p_data->'details';
 if jsonb_typeof(details) is distinct from 'object' then raise exception 'INVALID_DETAILS'; end if;
 details:=details||jsonb_build_object('customer_comment',coalesce(req.notes,''));
 -- Never accept an existing quote id or a caller-supplied idempotency key here.
 result:=private.gama_quote_action('save',(p_data-'id'-'request_key'-'revision')||
  jsonb_build_object('request_key',req.id,'revision',0,'details',details));
 quote_id:=(result->>'id')::uuid;
 update public.customer_requests set invoice_id=quote_id,status='invoiced',converted_at=now(),
  customer_id=(p_data->>'customer_id')::uuid,updated_at=now() where id=req.id;
 -- Keep the requested quantities and total intact: the quote may contain an offer.
 return result||jsonb_build_object('request_id',req.id,'existing',false);
end $$;
revoke all on function private.gama_quote_from_request(uuid,jsonb) from public,anon;
grant execute on function private.gama_quote_from_request(uuid,jsonb) to authenticated;
create or replace function public.gama_quote_from_request(p_request_id uuid,p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_quote_from_request(p_request_id,p_data);
$$;
revoke all on function public.gama_quote_from_request(uuid,jsonb) from public,anon;
grant execute on function public.gama_quote_from_request(uuid,jsonb) to authenticated;
