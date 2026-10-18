-- Disconnect audit projections only. Preserve business history, RLS and journals.
do $$declare src text;start_at integer;end_at integer;begin
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 start_at:=strpos(src,'with audit_rows as materialized (');
 end_at:=strpos(src,'visible as materialized(');
 if start_at=0 or end_at<=start_at then raise exception 'MODULE_HISTORY_AUDIT_DISCONNECT_MISMATCH';end if;
 src:=substr(src,1,start_at-1)||'with '||substr(src,end_at);
 src:=replace(src,'select * from combined e where module_id=m','select * from private.coco_module_events e where module_id=m');
 src:=replace(src,$text$or e.source_type='audit' or e.action='source_linked'$text$,$text$or e.action='source_linked'$text$);
 execute src;
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 if strpos(src,$text$'include_audit',true$text$)=0 then raise exception 'DOSSIER_AUDIT_DISCONNECT_MISMATCH';end if;
 src:=replace(src,$text$'annotations_only',true,'include_audit',true,'dossier_kind',p_data->>'kind'$text$,$text$'annotations_only',true$text$);
 src:=replace(src,$text$e->>'source_type'='audit' or e->>'action'='source_linked'$text$,$text$e->>'action'='source_linked'$text$);
 execute src;
end $$;
notify pgrst,'reload schema';
