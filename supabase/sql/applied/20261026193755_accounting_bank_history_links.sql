-- Record-specific ledger links, preserving the existing invoker router.
create function private.coco_bank_posting_history_link(p_id text,p_reference text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();eid uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.coco_module_allowed('accounting') or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then return null;end if;
 select entry_id into eid from private.accounting_match_postings where id=p_id::uuid;
 if eid is null then return null;end if;
 return jsonb_build_object('module','accounting','id',eid,'reference',p_reference,'action','accounting_entry');
end $$;
revoke all on function private.coco_bank_posting_history_link(text,text) from public,anon,service_role;
grant execute on function private.coco_bank_posting_history_link(text,text) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_bank_links(');end $$;
revoke all on function private.coco_history_typed_link_before_bank_links(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_bank_links(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select case when p_table='accounting_match_postings' then private.coco_bank_posting_history_link(p_id,p_reference)
 else private.coco_history_typed_link_before_bank_links(p_module,p_table,p_id,p_reference) end
$$;
-- The history gate uses the same full-ledger scope as configuration and bank
-- matching. Owning or viewing an invoice does not expose treasury settings.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_bank_scope(');end $$;
revoke all on function private.coco_history_record_visible_before_bank_scope(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_bank_scope(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in('accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements','accounting_payment_preferences','accounting_match_postings') then
  return auth.uid() is not null and private.erp_mfa_ok() and private.coco_module_allowed('accounting') and coalesce(private.gama_accounting_rights()->>'scope','')='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false);
 end if;
 return private.coco_history_record_visible_before_bank_scope(p_table,p_id,p_owner);
end $$;
