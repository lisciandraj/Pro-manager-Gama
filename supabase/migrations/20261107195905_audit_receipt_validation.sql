-- Validate at the shared storage boundary, including legacy expense RPCs.
-- Existing historical receipts are neither rewritten nor removed.
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create function private.coco_receipt_content_valid(p_mime text,p_url text)
returns boolean language plpgsql immutable security invoker set search_path='' as $$
declare encoded text; raw bytea; prefix text;
begin
 if p_mime is null or p_mime not in ('application/pdf','image/png','image/jpeg','image/webp')
  or p_url is null or length(p_url)>2800000 then return false;end if;
 prefix:='data:'||p_mime||';base64,';
 if left(p_url,length(prefix))<>prefix then return false;end if;
 encoded:=substr(p_url,length(prefix)+1);
 if encoded='' or length(encoded)%4<>0 or encoded !~ '^[A-Za-z0-9+/]+={0,2}$' then return false;end if;
 begin raw:=decode(encoded,'base64');exception when others then return false;end;
 if octet_length(raw)>2000000 or replace(encode(raw,'base64'),E'\n','')<>encoded then return false;end if;
 return case p_mime
  when 'application/pdf' then substring(raw from 1 for 5)=convert_to('%PDF-','UTF8')
  when 'image/png' then substring(raw from 1 for 8)=decode('89504e470d0a1a0a','hex')
  when 'image/jpeg' then substring(raw from 1 for 3)=decode('ffd8ff','hex')
  when 'image/webp' then octet_length(raw)>=12 and substring(raw from 1 for 4)=convert_to('RIFF','UTF8') and substring(raw from 9 for 4)=convert_to('WEBP','UTF8')
  else false end;
end $$;
revoke all on function private.coco_receipt_content_valid(text,text) from public,anon,authenticated,service_role;

create function private.coco_expense_receipt_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.data_url is not distinct from old.data_url and new.mime_type is not distinct from old.mime_type then return new;end if;
 if not private.coco_receipt_content_valid(new.mime_type,new.data_url) then
  raise exception 'RECEIPT_CONTENT_INVALID' using errcode='22023';
 end if;
 return new;
end $$;
revoke all on function private.coco_expense_receipt_guard() from public,anon,authenticated,service_role;
create trigger coco_expense_receipt_content before insert or update of mime_type,data_url
on public.expense_receipts for each row execute function private.coco_expense_receipt_guard();
notify pgrst,'reload schema';
