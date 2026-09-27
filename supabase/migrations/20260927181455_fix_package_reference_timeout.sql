-- Package inserts timed out inside reference registration. A package used to
-- register twice on INSERT, then twice again when its weight was calculated.
-- Each registration also rewrote every already-numbered document in its dossier.
-- Keep immutable numbering and the existing lock order, but only write changes.
do $$
declare src text;old_tail text;new_tail text;
begin
 src:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 old_tail:=$old$ update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;$old$;
 new_tail:=$new$ -- Issue the dossier label once, then fill new references or merged labels.
 declare label text:=private.erp_issue_reference('dossier',target::text,target);
 begin
  update public.gama_document_references r set
   document_reference=case when r.document_reference='' then
    private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,target)
    else r.document_reference end,
   dossier_label=label
  where dossier_number=target and (document_reference='' or dossier_label is distinct from label);
 end;$new$;
 if strpos(src,old_tail)=0 then raise exception 'PACKAGE_REFERENCE_TAIL_MISSING';end if;
 execute replace(src,old_tail,new_tail);
end $$;

-- The BEFORE trigger already registers packages and fills their ERP reference.
-- A change to weight/status does not change the document's identity or parent.
do $$
declare src text;anchor text;
begin
 src:=pg_get_functiondef('private.erp_stamp_reference()'::regprocedure);
 anchor:=' select * into f from public.erp_reference_formats';
 if strpos(src,anchor)=0 then raise exception 'PACKAGE_STAMP_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,$patch$
 if tg_table_name='fulfillment_packages' and tg_op='UPDATE' then
  if new.id=old.id and new.preparation_id=old.preparation_id
     and old.erp_reference is not null and new.erp_reference=old.erp_reference then
   return new;
  end if;
 end if;
$patch$||anchor);
 execute src;
end $$;
drop trigger gama_document_reference on public.fulfillment_packages;
