-- Keep the anonymous token resolver outside the exposed public schema.
create schema private_tracking;
revoke all on schema private_tracking from public;
grant usage on schema private_tracking to anon,authenticated;
create function private_tracking.resolve(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',d.eta_at,'delivered_at',d.delivered_at)
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private_tracking.resolve(uuid) from public;
grant execute on function private_tracking.resolve(uuid) to anon,authenticated;
create or replace function public.gama_tms_tracking(p_token uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private_tracking.resolve(p_token)$$;
drop function private.gama_tms_tracking(uuid);
notify pgrst,'reload schema';
