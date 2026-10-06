-- Persisted manual campaigns. Composer opening is recorded; delivery is never claimed.
create table private.marketing_campaigns (
 id uuid primary key default gen_random_uuid(), title text not null check(length(btrim(title)) between 1 and 180),
 channel text not null default 'email' check(channel in ('email','whatsapp')),
 subject text not null default '' check(length(subject)<=150), message text not null default '' check(length(message)<=1800),
 dialing_code text not null default '593' check(dialing_code ~ '^[1-9][0-9]{0,2}$'),
 state text not null default 'draft' check(state in ('draft','prepared','archived')), version integer not null default 1,
 prepared_payload jsonb, created_by uuid not null, updated_by uuid not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index marketing_campaigns_updated on private.marketing_campaigns(updated_at desc,id);
create table private.marketing_recipients (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references private.marketing_campaigns(id) on delete cascade,
 kind text not null check(kind in ('customer','contact','lead')), contact_id uuid not null,
 recipient_group text not null check(recipient_group in ('customer','lead')), label text not null,
 address text, subject text not null, message text not null,
 status text not null check(status in ('prepared','opened','missing_email','duplicate_email','missing_phone','duplicate_phone')),
 opened_at timestamptz, opened_by uuid, unique(campaign_id,kind,contact_id)
);
alter table private.marketing_campaigns enable row level security;
alter table private.marketing_recipients enable row level security;
revoke all on private.marketing_campaigns,private.marketing_recipients from public,anon,authenticated;

create function private.marketing_phone(p_phone text,p_code text) returns text
language plpgsql immutable set search_path='' as $$
declare raw text:=btrim(coalesce(p_phone,''));digits text;
begin
 if raw='' or raw !~ '^\+?[0-9 ().-]+$' or p_code !~ '^[1-9][0-9]{0,2}$' then return null;end if;
 digits:=regexp_replace(raw,'[^0-9]','','g');
 if raw like '+%' then null;
 elsif digits like '00%' then digits:=substr(digits,3);
 elsif digits like p_code||'%' and length(digits)>=11 then null;
 else digits:=p_code||regexp_replace(digits,'^0+','');end if;
 if digits !~ '^[1-9][0-9]{7,14}$' then return null;end if;return digits;
end $$;

-- CRM classification is stored independently of contact foreign keys, preserving access restrictions after deletion.
create function private.marketing_contacts() returns table(id uuid,kind text,recipient_group text,label text,email text,phone text)
language sql stable set search_path='' as $$
 select c.id,'customer','customer',c.name,coalesce(c.email,''),coalesce(c.phone,'') from public.customers c where c.active
 union all select c.id,'contact',case when c.customer_id is not null then 'customer' else 'lead' end,
 coalesce(nullif(btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),nullif(c.email,''),'—'),coalesce(c.email,''),coalesce(c.phone,'')
 from public.crm_contacts c where c.active and private.erp_module_allowed('crm',array['administrador','comercial'])
 and (exists(select 1 from public.customers a where a.id=c.customer_id and a.active) or c.customer_id is null and exists(select 1 from public.crm_leads l where l.id=c.lead_id and l.active and l.converted_customer_id is null))
 union all select l.id,'lead','lead',coalesce(nullif(l.company,''),nullif(btrim(coalesce(l.first_name,'')||' '||coalesce(l.last_name,'')),''),nullif(l.email,''),'—'),coalesce(l.email,''),coalesce(l.phone,'')
 from public.crm_leads l where l.active and l.converted_customer_id is null and private.erp_module_allowed('crm',array['administrador','comercial'])
$$;

create function private.gama_marketing(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();s private.marketing_campaigns;v_rec private.marketing_recipients;c record;
 sid uuid;items jsonb;total bigint;entry jsonb;payload jsonb;seen text[]:='{}';address text;status text;
 off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));term text:=left(coalesce(p_data->>'search',''),100);
 channel text:=coalesce(p_data->>'channel','email');code text:=coalesce(p_data->>'dialing_code','593');
begin
 if actor is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>30000 then raise exception 'MARKETING_INVALID_DATA';end if;
 if p_action='list' then
  select count(*) into total from private.marketing_campaigns where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state');
  select coalesce(jsonb_agg(x),'[]') into items from (select m.id,m.title,m.channel,m.state,m.version,m.updated_at,
   (select count(*) from private.marketing_recipients r where r.campaign_id=m.id and r.status in ('prepared','opened')) prepared,
   (select count(*) from private.marketing_recipients r where r.campaign_id=m.id and r.status='opened') opened
   from private.marketing_campaigns m where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state') order by updated_at desc,id limit 30 offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='search' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'MARKETING_ACCESS_DENIED';end if;
  if channel not in ('email','whatsapp') or code !~ '^[1-9][0-9]{0,2}$' or coalesce(p_data->>'kind','customer') not in ('customer','lead') then raise exception 'MARKETING_INVALID_DATA';end if;
  with filtered as (select * from private.marketing_contacts() where recipient_group=coalesce(p_data->>'kind','customer') and (label ilike '%'||term||'%' or email ilike '%'||term||'%' or phone ilike '%'||term||'%'))
  select (select count(*) from filtered),(select coalesce(jsonb_agg(x),'[]') from (select id,kind,recipient_group as "group",label,email,phone,
   case when channel='whatsapp' then private.marketing_phone(phone,code) is not null else btrim(email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and length(btrim(email))<=254 end selectable
   from filtered order by label,id,kind limit 30 offset off) x) into total,items;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='save' and nullif(p_data->>'id','') is null then
  if not private.erp_action_allowed('surveys','create') then raise exception 'MARKETING_ACCESS_DENIED';end if;
  insert into private.marketing_campaigns(title,channel,subject,message,dialing_code,created_by,updated_by)
   values(btrim(p_data->>'title'),channel,coalesce(p_data->>'subject',''),coalesce(p_data->>'message',''),code,actor,actor) returning * into s;
  return jsonb_build_object('campaign',to_jsonb(s)-'prepared_payload','items','[]'::jsonb);
 end if;
 sid:=(p_data->>'id')::uuid;select * into s from private.marketing_campaigns where id=sid for update;
 if not found then raise exception 'MARKETING_NOT_FOUND';end if;
 if p_action='get' then
  select coalesce(jsonb_agg(x order by x.label,x.id),'[]') into items from (
   select r.id,r.kind,r.contact_id,r.recipient_group as "group",r.label,r.address,r.subject,r.message,r.status,r.opened_at,
    s.state='prepared' and r.status in ('prepared','opened') and exists(select 1 from private.marketing_contacts() mc where mc.id=r.contact_id and mc.kind=r.kind and r.address=case when s.channel='whatsapp' then private.marketing_phone(mc.phone,s.dialing_code) else lower(btrim(mc.email)) end) available
   from private.marketing_recipients r where r.campaign_id=sid and private.erp_module_allowed('contacts',array['administrador','comercial']) and (r.kind='customer' or private.erp_module_allowed('crm',array['administrador','comercial']))
  ) x;
  return jsonb_build_object('campaign',to_jsonb(s)-'prepared_payload','items',items);
 elsif p_action='duplicate' then
  if not private.erp_action_allowed('surveys','create') then raise exception 'MARKETING_ACCESS_DENIED';end if;
  insert into private.marketing_campaigns(title,channel,subject,message,dialing_code,created_by,updated_by)
   values(left(s.title,170)||' (copy)',s.channel,s.subject,s.message,s.dialing_code,actor,actor) returning * into s;
  return jsonb_build_object('campaign',to_jsonb(s)-'prepared_payload','items','[]'::jsonb);
 end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if p_action in ('draft','opened','prepare') and not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'MARKETING_ACCESS_DENIED';end if;
 if p_action in ('draft','opened') then
  select * into v_rec from private.marketing_recipients where id=(p_data->>'recipient_id')::uuid and campaign_id=sid;
  if not found or v_rec.kind<>'customer' and not private.erp_module_allowed('crm',array['administrador','comercial']) then raise exception 'MARKETING_ACCESS_DENIED';end if;
  if s.state<>'prepared' or v_rec.status not in ('prepared','opened') then raise exception 'MARKETING_LOCKED';end if;
  select * into c from private.marketing_contacts() mc where mc.id=v_rec.contact_id and mc.kind=v_rec.kind;
  if not found or v_rec.address is distinct from (case when s.channel='whatsapp' then private.marketing_phone(c.phone,s.dialing_code) else lower(btrim(c.email)) end) then raise exception 'MARKETING_CONTACT_CHANGED';end if;
  if p_action='opened' then update private.marketing_recipients set status='opened',opened_at=coalesce(opened_at,now()),opened_by=coalesce(opened_by,actor) where id=v_rec.id returning * into v_rec;end if;
  return jsonb_build_object('id',v_rec.id,'address',v_rec.address,'subject',v_rec.subject,'message',v_rec.message,'status',v_rec.status,'channel',s.channel);
 elsif p_action='prepare' then
  if jsonb_typeof(p_data->'recipients') is distinct from 'array' or jsonb_array_length(p_data->'recipients') not between 1 and 50 then raise exception 'MARKETING_INVALID_DATA';end if;
  select jsonb_agg(x order by x->>'kind',x->>'id') into payload from (select distinct jsonb_build_object('kind',value->>'kind','id',value->>'id') x from jsonb_array_elements(p_data->'recipients')) a;
  if s.state='prepared' and s.prepared_payload=payload then return private.gama_marketing('get',jsonb_build_object('id',sid));end if;
  if s.state<>'draft' then raise exception 'MARKETING_LOCKED';end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
  if btrim(s.message)='' or s.channel='email' and btrim(s.subject)='' then raise exception 'MARKETING_INVALID_DATA';end if;
  for entry in select value from jsonb_array_elements(payload) loop
   if coalesce(entry->>'kind','') not in ('customer','lead','contact') then raise exception 'MARKETING_INVALID_CONTACT';end if;
   select * into c from private.marketing_contacts() mc where mc.id=(entry->>'id')::uuid and mc.kind=entry->>'kind';
   if not found then raise exception 'MARKETING_INVALID_CONTACT';end if;
   address:=case when s.channel='whatsapp' then private.marketing_phone(c.phone,s.dialing_code) else lower(btrim(c.email)) end;
   if address is null or s.channel='email' and (address !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(address)>254) then status:=case when s.channel='whatsapp' then 'missing_phone' else 'missing_email' end;
   elsif address=any(seen) then status:=case when s.channel='whatsapp' then 'duplicate_phone' else 'duplicate_email' end;
   else status:='prepared';seen:=array_append(seen,address);end if;
   insert into private.marketing_recipients(campaign_id,kind,contact_id,recipient_group,label,address,subject,message,status)
    values(sid,c.kind,c.id,c.recipient_group,c.label,address,replace(replace(s.subject,'{campaign}',s.title),'{name}',c.label),replace(replace(s.message,'{campaign}',s.title),'{name}',c.label),status);
  end loop;
  update private.marketing_campaigns set state='prepared',prepared_payload=payload,version=version+1,updated_by=actor,updated_at=now() where id=sid;
  return private.gama_marketing('get',jsonb_build_object('id',sid));
 end if;
 if s.version is distinct from (p_data->>'version')::integer then raise exception 'MARKETING_CHANGED';end if;
 if p_action='save' then
  if s.state<>'draft' then raise exception 'MARKETING_LOCKED';end if;
  update private.marketing_campaigns set title=btrim(p_data->>'title'),channel=coalesce(p_data->>'channel','email'),subject=coalesce(p_data->>'subject',''),message=coalesce(p_data->>'message',''),dialing_code=code,version=version+1,updated_by=actor,updated_at=now() where id=sid returning * into s;
 elsif p_action='archive' then
  if s.state='archived' then raise exception 'MARKETING_LOCKED';end if;
  update private.marketing_campaigns set state='archived',version=version+1,updated_by=actor,updated_at=now() where id=sid returning * into s;
 else raise exception 'MARKETING_INVALID_ACTION';end if;
 return private.gama_marketing('get',jsonb_build_object('id',sid));
end $$;
create function public.gama_marketing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_marketing(p_action,p_data)$$;
revoke all on function private.marketing_phone(text,text),private.marketing_contacts(),private.gama_marketing(text,jsonb),public.gama_marketing(text,jsonb) from public,anon,authenticated;
grant execute on function private.gama_marketing(text,jsonb),public.gama_marketing(text,jsonb) to authenticated;
notify pgrst,'reload schema';
