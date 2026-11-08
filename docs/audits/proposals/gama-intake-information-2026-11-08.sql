-- Pending isolated SQL validation and generation as an additive CLI migration.
-- Apply after gama-policies-2026-11-08.sql. Do not fabricate company information.
begin;
create function private.commerce_missing_public_information() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(k order by k),'[]'::jsonb)
 from unnest(array['legal_name','legal_tax_id','legal_address','privacy_email',
  'privacy_retention','privacy_recipients','privacy_rights_process']) k
 where not exists(select 1 from private.website_public_settings s
  where s.id and length(btrim(coalesce(s.config->>k,'')))>0)
$$;
revoke all on function private.commerce_missing_public_information() from public,anon,authenticated,service_role;
alter table private.website_public_inquiries add column policy_snapshot jsonb;

-- Guest checkout already validates its policy version; retain it when it calls
-- the shared quote intake instead of stripping the information it just checked.
do $checkout_policy$
declare body text;anchor text:='array[''billing'',''price_hash'',''terms_accepted'',''policy_version'']';
begin
 select pg_get_functiondef('storefront_api.gama_commerce_before_compliance(text,jsonb)'::regprocedure) into body;
 if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then raise exception 'COMPLIANCE_CHECKOUT_POLICY_ANCHOR';end if;
 execute replace(body,anchor,'array[''billing'',''price_hash'',''terms_accepted'']');
end $checkout_policy$;

-- Preserve the RPC OID and its existing ACLs; no predecessor becomes callable.
create or replace function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;bundle jsonb;is_new boolean:=false;key_id uuid;
begin
 if p_action='submit' then
  perform private.commerce_guest_guard();
  key_id:=nullif(p_data->>'request_key','')::uuid;
  if key_id is null then raise exception 'WEBSITE_INVALID_DATA';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||key_id,0));
  is_new:=not exists(select 1 from private.website_public_inquiries where request_key=key_id);
  if is_new then
   if jsonb_array_length(private.commerce_missing_public_information())>0 then raise exception 'WEBSITE_LEGAL_INFORMATION_REQUIRED';end if;
   bundle:=private.commerce_policy_bundle();
   if p_data->>'policy_version' is distinct from bundle->>'version' then raise exception 'COMMERCE_POLICY_CHANGED';end if;
  end if;
 end if;
 r:=storefront_api.gama_storefront_before_compliance(p_action,p_data);
 if p_action='submit' and is_new then
  update private.website_public_inquiries set policy_snapshot=bundle where request_key=key_id;
 end if;
 if p_action='bootstrap' then
  r:=r||jsonb_build_object('policies',private.commerce_policy_bundle(),
   'collection_ready',jsonb_array_length(private.commerce_missing_public_information())=0);
  if r->>'paused'='false' then r:=jsonb_set(r,'{settings}',private.commerce_config_defaults(r->'settings'));end if;
 end if;
 return r;
end $$;

-- Checkout calls the canonical storefront submit in the same transaction: the
-- guard above also applies to new guest orders and rolls back on failure.
-- Support/rights intake, existing receipts and existing idempotent retries are
-- deliberately accessible while company information is being completed.
notify pgrst,'reload schema';
commit;
