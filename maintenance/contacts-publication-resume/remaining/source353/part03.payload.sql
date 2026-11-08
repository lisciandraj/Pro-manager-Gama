
grant execute on function private.coco_workhub_resolve_before_documents(text,uuid) to authenticated;
create or replace function private.coco_workhub_resolve(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$declare r jsonb;begin
 if not private.coco_workhub_allowed() then return null;end if;
 if p_kind='workspace_doc' then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(body,6000),'module','workhub','channel_id',channel_id,'version',version,'updated_at',updated_at) into r
   from private.coco_workhub_documents where id=p_id;return r;
 end if;
 return private.coco_workhub_resolve_before_documents(p_kind,p_id);
end $$;
do $$declare expression text;begin
 select pg_get_expr(conbin,conrelid) into expression from pg_constraint where conrelid='private.coco_workhub_links'::regclass and conname='coco_workhub_links_kind_check';
 if expression is null then raise exception 'WORKHUB_LINK_CONTRACT_CHANGED';end if;
 alter table private.coco_workhub_links drop constraint coco_workhub_links_kind_check;
 execute 'alter table private.coco_workhub_links add constraint coco_workhub_links_kind_check check(('||expression||') or kind=''workspace_doc'')';
end $$;

-- Extend the existing candidate query in place; keep its full pagination and
-- filters instead of merging two independently truncated result pages.
do $$declare d text;anchor text:='union all select ''task'',i.id,i.title,left(i.description,600),''projects'',null,i.project_id,i.updated_at';begin
 d:=pg_get_functiondef('public.coco_workhub(text,jsonb)'::regprocedure);
 if length(d)-length(replace(d,anchor,''))<>length(anchor) or position('kind in (''article'',''document'')' in d)=0 then raise exception 'WORKHUB_SEARCH_CONTRACT_CHANGED';end if;
 d:=replace(d,anchor,'union all select ''workspace_doc'',id,title,left(body,600),''workhub'',channel_id,null,updated_at from private.coco_workhub_documents where not archived and position(lower(term) in lower(title||'' ''||body))>0 '||anchor);
 d:=replace(d,'kind in (''article'',''document'')','kind in (''article'',''document'',''workspace_doc'')');
 execute d;
end $$;
notify pgrst,'reload schema';
