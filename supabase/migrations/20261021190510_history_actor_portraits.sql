-- Resolve portraits only for authors on the already-authorised history page.
-- Keep the invoker and the existing HR row policies: no employee directory or
-- private HR fields are added to the history response.
do $$
declare src text; needle text;
begin
 src:=pg_get_functiondef('public.coco_module_history(text,jsonb)'::regprocedure);
 needle:=E'\n return r;\nend';
 if strpos(src,needle)=0 then raise exception 'HISTORY_PORTRAITS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$patch$
 if p_action='list' then
  r:=jsonb_set(r,'{portraits}',coalesce(r->'portraits','{}'::jsonb)||coalesce((
   select jsonb_object_agg(h.profile_id::text,h.photo_data)
   from public.hr_employees h
   where h.active and h.photo_data is not null and length(h.photo_data)<=120000
    and h.photo_data ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$'
    and h.profile_id::text in (
     select e->>'actor_id' from jsonb_array_elements(coalesce(r->'history','[]'::jsonb)) e
     union select e->>'actor_id' from jsonb_array_elements(coalesce(r->'entries','[]'::jsonb)) e
    )
  ),'{}'::jsonb));
 end if;
 return r;
end$patch$);
 execute src;

 -- Dossier annotations are merged from module history; keep their portraits too.
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 needle:=E'\n return r;\nend';
 if strpos(src,needle)=0 then raise exception 'DOSSIER_PORTRAITS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$patch$
 r:=jsonb_set(r,'{portraits}',coalesce(r->'portraits','{}'::jsonb)||coalesce(extra->'portraits','{}'::jsonb));
 return r;
end$patch$);
 execute src;
end $$;
notify pgrst,'reload schema';
