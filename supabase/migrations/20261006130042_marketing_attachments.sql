-- Files are private binary payloads, loaded separately from campaign lists.
-- Duplicated campaigns share immutable bytes rather than copying large files.
create table private.marketing_attachment_files (
 id uuid primary key, filename text not null check(length(filename) between 1 and 200 and filename !~ '[[:cntrl:]/\\]'),
 mime_type text not null, content bytea not null check(octet_length(content) between 1 and 5242880),
 created_at timestamptz not null default now(), created_by uuid not null
);
create table private.marketing_campaign_attachments (
 campaign_id uuid not null references private.marketing_campaigns(id) on delete cascade,
 attachment_id uuid not null references private.marketing_attachment_files(id),
 primary key(campaign_id,attachment_id)
);
create index marketing_campaign_attachments_file on private.marketing_campaign_attachments(attachment_id);
alter table private.marketing_attachment_files enable row level security;
alter table private.marketing_campaign_attachments enable row level security;
revoke all on private.marketing_attachment_files,private.marketing_campaign_attachments from public,anon,authenticated;

create function private.marketing_attachment_list(p_campaign uuid) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'filename',f.filename,'mime_type',f.mime_type,'size',octet_length(f.content)) order by f.created_at,f.id),'[]')
 from private.marketing_campaign_attachments a join private.marketing_attachment_files f on f.id=a.attachment_id where a.campaign_id=p_campaign
$$;
revoke all on function private.marketing_attachment_list(uuid) from public,anon,authenticated;

create function private.gama_marketing_attachments(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();s private.marketing_campaigns;f private.marketing_attachment_files;
 sid uuid;fid uuid;bytes bytea;mime text;ext text;filename text;linked boolean;amount bigint;count_files bigint;
begin
 if actor is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>7050000 then raise exception 'MARKETING_FILE_LIMIT';end if;
 sid:=(p_data->>'id')::uuid;select * into s from private.marketing_campaigns where id=sid for update;
 if not found then raise exception 'MARKETING_NOT_FOUND';end if;
 if p_action='list' then return jsonb_build_object('attachments',private.marketing_attachment_list(sid));end if;
 fid:=(p_data->>'attachment_id')::uuid;
 select * into f from private.marketing_attachment_files af where af.id=fid;
 select exists(select 1 from private.marketing_campaign_attachments a where a.campaign_id=sid and a.attachment_id=fid) into linked;
 if p_action='file' then
  if not linked then raise exception 'MARKETING_FILE_UNAVAILABLE';end if;
  return jsonb_build_object('id',f.id,'filename',f.filename,'mime_type',f.mime_type,'size',octet_length(f.content),'content_base64',encode(f.content,'base64'));
 end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if s.state<>'draft' then raise exception 'MARKETING_LOCKED';end if;
 if s.channel<>'email' then raise exception 'MARKETING_ATTACHMENTS_EMAIL_ONLY';end if;
 if p_action='add' then
  filename:=p_data->>'filename';ext:=lower(substring(filename from '\.([^.]+)$'));
  mime:=case ext when 'pdf' then 'application/pdf' when 'jpg' then 'image/jpeg' when 'jpeg' then 'image/jpeg' when 'png' then 'image/png' when 'webp' then 'image/webp'
   when 'txt' then 'text/plain' when 'csv' then 'text/csv' when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
   when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' when 'pptx' then 'application/vnd.openxmlformats-officedocument.presentationml.presentation' end;
  if fid is null or coalesce(length(filename),0) not between 1 and 200 or filename ~ '[[:cntrl:]/\\]' or mime is null or coalesce(p_data->>'content_base64','') !~ '^[A-Za-z0-9+/]+={0,2}$' then raise exception 'MARKETING_FILE_FORMAT';end if;
  begin bytes:=decode(p_data->>'content_base64','base64');exception when others then raise exception 'MARKETING_FILE_FORMAT';end;
  if octet_length(bytes) not between 1 and 5242880 then raise exception 'MARKETING_FILE_LIMIT';end if;
  if f.id is not null then
   if not linked or f.filename<>filename or f.mime_type<>mime or f.content<>bytes then raise exception 'MARKETING_FILE_CHANGED';end if;
   -- Same upload identity may safely retry after the original response was lost.
   return private.gama_marketing('get',jsonb_build_object('id',sid))||jsonb_build_object('attachments',private.marketing_attachment_list(sid));
  end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
  select count(*),coalesce(sum(octet_length(af.content)),0) into count_files,amount from private.marketing_campaign_attachments a join private.marketing_attachment_files af on af.id=a.attachment_id where a.campaign_id=sid;
  if count_files>=5 or amount+octet_length(bytes)>15728640 then raise exception 'MARKETING_FILE_LIMIT';end if;
  insert into private.marketing_attachment_files(id,filename,mime_type,content,created_by) values(fid,filename,mime,bytes,actor);
  insert into private.marketing_campaign_attachments(campaign_id,attachment_id) values(sid,fid);
 elsif p_action='remove' then
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
  if not linked then raise exception 'MARKETING_FILE_UNAVAILABLE';end if;
  delete from private.marketing_campaign_attachments where campaign_id=sid and attachment_id=fid;
  delete from private.marketing_attachment_files af where af.id=fid and not exists(select 1 from private.marketing_campaign_attachments a where a.attachment_id=fid);
 else raise exception 'MARKETING_INVALID_ACTION';end if;
 update private.marketing_campaigns set version=version+1,updated_at=now(),updated_by=actor where id=sid;
 return private.gama_marketing('get',jsonb_build_object('id',sid))||jsonb_build_object('attachments',private.marketing_attachment_list(sid));
end $$;

-- Extend the existing contract without replacing its recipient and authorization logic.
create function private.gama_marketing_with_attachments(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;sid uuid;source_id uuid;
begin
 if auth.uid() is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>30000 then raise exception 'MARKETING_INVALID_DATA';end if;
 if p_action='save' and p_data->>'channel'='whatsapp' and nullif(p_data->>'id','') is not null then
  -- Serialize channel changes with attachment writes and preparation.
  source_id:=(p_data->>'id')::uuid;perform 1 from private.marketing_campaigns where id=source_id for update;
  if exists(select 1 from private.marketing_campaign_attachments a where a.campaign_id=source_id) then raise exception 'MARKETING_ATTACHMENTS_EMAIL_ONLY';end if;
 end if;
 result:=private.gama_marketing(p_action,p_data);
 if p_action='duplicate' then
  source_id:=(p_data->>'id')::uuid;sid:=(result->'campaign'->>'id')::uuid;
  insert into private.marketing_campaign_attachments(campaign_id,attachment_id) select sid,a.attachment_id from private.marketing_campaign_attachments a where a.campaign_id=source_id;
 end if;
 if result ? 'campaign' then
  sid:=(result->'campaign'->>'id')::uuid;return result||jsonb_build_object('attachments',private.marketing_attachment_list(sid));
 elsif p_action='draft' then
  return result||jsonb_build_object('attachments',private.marketing_attachment_list((p_data->>'id')::uuid));
 end if;
 return result;
end $$;
create or replace function public.gama_marketing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_marketing_with_attachments(p_action,p_data)$$;
create function public.gama_marketing_attachments(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_marketing_attachments(p_action,p_data)$$;
revoke all on function private.gama_marketing_with_attachments(text,jsonb),private.gama_marketing_attachments(text,jsonb),public.gama_marketing_attachments(text,jsonb) from public,anon,authenticated;
grant execute on function private.gama_marketing_with_attachments(text,jsonb),private.gama_marketing_attachments(text,jsonb),public.gama_marketing_attachments(text,jsonb) to authenticated;
notify pgrst,'reload schema';
