-- Coco's native collaboration hub. Business data remains in its original tables.
insert into private.coco_history_modules(module_id,label,roles)
values('workhub','Espacio de trabajo',array['administrador','comercial','almacenero']);

-- Extend, rather than replace, the current list of module identifiers.
do $$declare d text;begin
 select pg_get_constraintdef(oid) into d from pg_constraint
 where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if d is null or strpos(d,'ARRAY[')=0 then raise exception 'WORKHUB_MODULE_CONTRACT_CHANGED';end if;
 d:=replace(d,'ARRAY[','ARRAY[''workhub''::text,');
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||d;
end $$;

create table private.coco_workhub_channels(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 100),
 description text not null default '' check(length(description)<=1000),
 owner_id uuid not null references public.profiles(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index coco_workhub_channel_owner on private.coco_workhub_channels(owner_id);
create index coco_workhub_channel_creator on private.coco_workhub_channels(created_by);
create table private.coco_workhub_members(
 channel_id uuid not null references private.coco_workhub_channels(id) on delete cascade,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(channel_id,profile_id)
);
create index coco_workhub_member_profile on private.coco_workhub_members(profile_id,channel_id);
create table private.coco_workhub_messages(
 id uuid primary key default gen_random_uuid(),
 channel_id uuid not null references private.coco_workhub_channels(id) on delete cascade,
 parent_id uuid references private.coco_workhub_messages(id) on delete restrict,
 body text not null check(length(btrim(body)) between 1 and 12000),
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index coco_workhub_message_channel on private.coco_workhub_messages(channel_id,created_at desc,id desc);
create index coco_workhub_message_parent on private.coco_workhub_messages(parent_id);
create index coco_workhub_message_creator on private.coco_workhub_messages(created_by);
create table private.coco_workhub_links(
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references private.coco_workhub_messages(id) on delete cascade,
 kind text not null check(kind in ('task','article','document','customer','opportunity','quote','order')),
 record_id uuid not null, created_at timestamptz not null default now(),
 unique(message_id,kind,record_id)
);
create index coco_workhub_links_target on private.coco_workhub_links(kind,record_id);
create table private.coco_workhub_states(
 user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('message','task','activity','proposal')),
 record_id uuid not null, status text not null default 'active' check(status in ('active','archived')),
 snoozed_until timestamptz, source_updated_at timestamptz not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 primary key(user_id,kind,record_id)
);
create index coco_workhub_states_snoozed on private.coco_workhub_states(user_id,snoozed_until);
create table private.coco_workhub_requests(
 user_id uuid not null references public.profiles(id) on delete cascade,
 request_key uuid not null, action text not null, payload jsonb not null,
 result jsonb, created_at timestamptz not null default now(),
 primary key(user_id,request_key)
);

create function private.coco_workhub_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('workhub',array['administrador','comercial','almacenero'])
$$;
create function private.coco_workhub_member(p_channel uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_workhub_allowed() and exists(select 1 from private.coco_workhub_members
 where channel_id=p_channel and profile_id=auth.uid())
$$;
create function private.coco_workhub_directory() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.coco_workhub_allowed() then
 (select coalesce(jsonb_agg(to_jsonb(p)),'[]') from
 (select id,full_name from public.profiles where active and deleted_at is null
 and role in ('administrador','comercial','almacenero') order by full_name,id limit 200) p)
 else '[]'::jsonb end
$$;
revoke all on function private.coco_workhub_allowed(),private.coco_workhub_member(uuid),private.coco_workhub_directory() from public,anon;
grant execute on function private.coco_workhub_allowed(),private.coco_workhub_member(uuid),private.coco_workhub_directory() to authenticated;

do $$declare t text;begin
 foreach t in array array['channels','members','messages','links','states','requests'] loop
  execute format('alter table private.coco_workhub_%I enable row level security',t);
  execute format('revoke all on private.coco_workhub_%I from public,anon,authenticated',t);
 end loop;
end $$;
grant select on private.coco_workhub_channels,private.coco_workhub_members,private.coco_workhub_messages,
 private.coco_workhub_links,private.coco_workhub_states to authenticated;
create policy workhub_channel_read on private.coco_workhub_channels for select to authenticated using(private.coco_workhub_member(id));
create policy workhub_member_read on private.coco_workhub_members for select to authenticated using(private.coco_workhub_member(channel_id));
create policy workhub_message_read on private.coco_workhub_messages for select to authenticated using(private.coco_workhub_member(channel_id));
create policy workhub_link_read on private.coco_workhub_links for select to authenticated using(exists(
 select 1 from private.coco_workhub_messages m where m.id=message_id));
create policy workhub_state_read on private.coco_workhub_states for select to authenticated using(user_id=auth.uid() and private.coco_workhub_allowed());

-- This resolver MUST remain invoker: original tables' RLS is the source of truth.
create function private.coco_workhub_resolve(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;begin
 if not private.coco_workhub_allowed() then return null;end if;
 if p_kind='task' and private.coco_module_allowed('projects') then
  select jsonb_build_object('id',i.id,'kind',p_kind,'title',i.title,'body',left(i.description,6000),
   'reference',i.reference,'module','projects','project_id',i.project_id,'version',i.version,'status',i.status,
   'due_at',i.due_date,'updated_at',i.updated_at)
  into r from public.pm_items i where i.id=p_id and i.kind='task';
 elsif p_kind='article' and private.coco_module_allowed('knowledge') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(body,6000),'module','knowledge',
   'reference',erp_reference,'updated_at',updated_at) into r from public.knowledge_articles where id=p_id;
 elsif p_kind='document' and private.coco_module_allowed('documents') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body','','module','documents',
   'updated_at',updated_at) into r from public.business_documents where id=p_id;
 elsif p_kind='customer' and private.coco_module_allowed('contacts') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',name,'body',coalesce(city,''),'module','contacts',
   'updated_at',updated_at) into r from public.customers where id=p_id;
 elsif p_kind='opportunity' and private.coco_module_allowed('crm') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(description,6000),'module','crm',
   'reference',reference,'updated_at',updated_at) into r from public.crm_opportunities where id=p_id;
 elsif p_kind='quote' and private.coco_module_allowed('quotes') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',coalesce(erp_reference,invoice_number),
   'body','','module','quotes','updated_at',updated_at) into r from public.invoices where id=p_id;
 elsif p_kind='order' and private.coco_module_allowed('sales-orders') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',coalesce(erp_reference,number::text),
   'body','','module','sales-orders','updated_at',updated_at) into r from public.sales_orders where id=p_id;
 end if;
 return r;
end $$;
revoke all on function private.coco_workhub_resolve(text,uuid) from public,anon;
grant execute on function private.coco_workhub_resolve(text,uuid) to authenticated;

create function private.coco_workhub_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 mid uuid;pid uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;prior private.coco_workhub_requests;
 r jsonb;item jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if key is null then raise exception 'WORKHUB_REQUEST_REQUIRED';end if;
 if p_action in ('member_set','message_create','link_add') and not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
 -- Unique receipt + row lock serializes concurrent retries. Failures roll it back.
 insert into private.coco_workhub_requests(user_id,request_key,action,payload)
 values(u,key,p_action,p_data) on conflict do nothing;
 select * into prior from private.coco_workhub_requests where user_id=u and request_key=key for update;
 if prior.action<>p_action or prior.payload<>p_data then raise exception 'WORKHUB_REQUEST_REUSED';end if;
 if prior.result is not null then return prior.result;end if;
 if p_action='channel_create' then
  if jsonb_typeof(coalesce(p_data->'members','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'members','[]'))>100 then raise exception 'WORKHUB_INVALID_MEMBERS';end if;
  insert into private.coco_workhub_channels(name,description,owner_id,created_by)
  values(btrim(p_data->>'name'),coalesce(p_data->>'description',''),u,u) returning id into cid;
  insert into private.coco_workhub_members(channel_id,profile_id) values(cid,u);
  for item in select value from jsonb_array_elements(coalesce(p_data->'members','[]')) loop
   pid:=(item#>>'{}')::uuid;
   if not exists(select 1 from public.profiles where id=pid and active and deleted_at is null and role in ('administrador','comercial','almacenero')) then raise exception 'WORKHUB_INVALID_MEMBER';end if;
   insert into private.coco_workhub_members(channel_id,profile_id) values(cid,pid) on conflict do nothing;
  end loop;
  r:=jsonb_build_object('id',cid);
 elsif p_action='member_set' then
  if not private.coco_workhub_member(cid) or not exists(select 1 from private.coco_workhub_channels where id=cid and owner_id=u) then raise exception 'WORKHUB_FORBIDDEN';end if;
  pid:=(p_data->>'profile_id')::uuid;
  if pid=u then raise exception 'WORKHUB_OWNER_REQUIRED';end if;
  if coalesce((p_data->>'remove')::boolean,false) then
   delete from private.coco_workhub_members where channel_id=cid and profile_id=pid;
  else
   if not exists(select 1 from public.profiles where id=pid and active and deleted_at is null and role in ('administrador','comercial','almacenero')) then raise exception 'WORKHUB_INVALID_MEMBER';end if;
   insert into private.coco_workhub_members(channel_id,profile_id) values(cid,pid) on conflict do nothing;
  end if;
  r:=jsonb_build_object('id',cid);
 elsif p_action in ('message_create','link_add') then
  if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  if p_action='message_create' then
   pid:=nullif(p_data->>'parent_id','')::uuid;
   if pid is not null and not exists(select 1 from private.coco_workhub_messages where id=pid and channel_id=cid and parent_id is null) then raise exception 'WORKHUB_INVALID_THREAD';end if;
   insert into private.coco_workhub_messages(channel_id,parent_id,body,created_by)
   values(cid,pid,btrim(p_data->>'body'),u) returning id into mid;
  else
   mid:=(p_data->>'message_id')::uuid;
   if not exists(select 1 from private.coco_workhub_messages where id=mid and channel_id=cid) then raise exception 'WORKHUB_NOT_FOUND';end if;
  end if;
  if jsonb_typeof(coalesce(p_data->'links','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'links','[]'))>12 then raise exception 'WORKHUB_TOO_MANY_LINKS';end if;
  for item in select value from jsonb_array_elements(coalesce(p_data->'links','[]')) loop
   insert into private.coco_workhub_links(message_id,kind,record_id) values(mid,item->>'kind',(item->>'id')::uuid) on conflict do nothing;
  end loop;
  r:=jsonb_build_object('id',mid,'channel_id',cid);
 elsif p_action='item_state' then
  if (p_data->>'snoozed_until')::timestamptz>now()+interval '366 days' then raise exception 'WORKHUB_INVALID_DATE';end if;
  insert into private.coco_workhub_states(user_id,kind,record_id,status,snoozed_until,source_updated_at)
  values(u,p_data->>'kind',(p_data->>'id')::uuid,coalesce(p_data->>'status','active'),nullif(p_data->>'snoozed_until','')::timestamptz,(p_data->>'updated_at')::timestamptz)
  on conflict(user_id,kind,record_id) do update set status=excluded.status,snoozed_until=excluded.snoozed_until,
   source_updated_at=excluded.source_updated_at,updated_at=now();
  r:=jsonb_build_object('saved',true);
 else raise exception 'WORKHUB_UNKNOWN_ACTION';end if;
 update private.coco_workhub_requests set result=r where user_id=u and request_key=key;
 return r;
end $$;
revoke all on function private.coco_workhub_write(text,jsonb) from public,anon;
grant execute on function private.coco_workhub_write(text,jsonb) to authenticated;

-- All source queries below execute with the requesting user's original RLS.
create function public.coco_workhub(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 rid uuid:=nullif(p_data->>'id','')::uuid;lim int:=least(100,greatest(1,coalesce((p_data->>'limit')::int,40)));
 offst int:=least(10000,greatest(0,coalesce((p_data->>'offset')::int,0)));
 term text:=left(btrim(coalesce(p_data->>'query','')),160);r jsonb;resolved jsonb;item jsonb;
 msg private.coco_workhub_messages;proposals jsonb:='[]';task jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action='bootstrap' then
  return jsonb_build_object('user_id',u,'directory',private.coco_workhub_directory(),
   'capabilities',jsonb_build_object('projects',private.coco_module_allowed('projects'),'knowledge',private.coco_module_allowed('knowledge'),
    'documents',private.coco_module_allowed('documents'),'contacts',private.coco_module_allowed('contacts'),
    'crm',private.coco_module_allowed('crm'),'agent',private.coco_module_allowed('assistant-ia')),
   'channels',(select coalesce(jsonb_agg(to_jsonb(c) order by c.name,c.id),'[]') from
    (select id,name,description,owner_id,created_at from private.coco_workhub_channels order by name,id limit 200) c),
   'projects',case when private.coco_module_allowed('projects') then
    (select coalesce(jsonb_agg(to_jsonb(p)),'[]') from (select id,name from public.pm_projects
     where status not in ('completed','cancelled') order by name,id limit 100) p) else '[]'::jsonb end);
 elsif p_action='resolve' then return private.coco_workhub_resolve(p_data->>'kind',rid);
 elsif p_action='backlinks' then
  if private.coco_workhub_resolve(p_data->>'kind',rid) is null then raise exception 'WORKHUB_NOT_FOUND';end if;
  return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from
   (select m.id,m.channel_id,c.name as channel_name,left(m.body,600) as body,m.created_at
    from private.coco_workhub_links l join private.coco_workhub_messages m on m.id=l.message_id
    join private.coco_workhub_channels c on c.id=m.channel_id where l.kind=p_data->>'kind' and l.record_id=rid
    order by m.created_at desc,m.id desc limit lim offset offst) z));
 elsif p_action in ('channel','context') then
  if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  return jsonb_build_object('channel',(select to_jsonb(c) from private.coco_workhub_channels c where id=cid),
   'members',(select coalesce(jsonb_agg(profile_id),'[]') from private.coco_workhub_members where channel_id=cid),
   'rows',(select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at,z.id),'[]') from
    (select m.id,m.channel_id,m.parent_id,m.body,m.created_by,m.created_at,m.updated_at,
     (select coalesce(jsonb_agg(v),'[]') from private.coco_workhub_links l
      cross join lateral private.coco_workhub_resolve(l.kind,l.record_id) v where l.message_id=m.id and v is not null) links
    from private.coco_workhub_messages m where m.channel_id=cid
     and (nullif(p_data->>'before_at','') is null or (m.created_at,m.id)<((p_data->>'before_at')::timestamptz,(p_data->>'before_id')::uuid))
    order by m.created_at desc,m.id desc limit lim) z));
 elsif p_action in ('message_create','link_add') then
  for item in select value from jsonb_array_elements(coalesce(p_data->'links','[]')) loop
   if private.coco_workhub_resolve(item->>'kind',(item->>'id')::uuid) is null then raise exception 'WORKHUB_LINK_FORBIDDEN';end if;
  end loop;
  return private.coco_workhub_write(p_action,p_data);
 elsif p_action='task_create' then
  select * into msg from private.coco_workhub_messages where id=(p_data->>'message_id')::uuid;
  if not found or not private.coco_module_allowed('projects') then raise exception 'WORKHUB_FORBIDDEN';end if;
  task:=public.gama_projects_action('save_item',jsonb_build_object('project_id',p_data->>'project_id',
   'kind','task','title',p_data->>'title','description',msg.body,'owner_id',p_data->>'owner_id',
   'due_date',nullif(p_data->>'due_date',''),'priority',coalesce(p_data->>'priority','normal'),
   'request_key',p_data->>'request_key','data',jsonb_build_object('workhub_message_id',msg.id)));
  perform private.coco_workhub_write('link_add',jsonb_build_object('channel_id',msg.channel_id,'message_id',msg.id,
   'links',jsonb_build_array(jsonb_build_object('kind','task','id',task->>'id')),'request_key',p_data->>'request_key'));
  return task;
 elsif p_action in ('channel_create','member_set','item_state') then return private.coco_workhub_write(p_action,p_data);
 elsif p_action in ('search','library') then
  if p_action='search' and length(term)<2 then return jsonb_build_object('rows','[]'::jsonb,'total',0);end if;
  with candidates as (
   select 'message'::text kind,m.id,left(m.body,180) title,left(m.body,600) body,'workhub'::text module,m.channel_id,
    null::uuid project_id,m.updated_at from private.coco_workhub_messages m where position(lower(term) in lower(m.body))>0
   union all select 'task',i.id,i.title,left(i.description,600),'projects',null,i.project_id,i.updated_at
    from public.pm_items i where private.coco_module_allowed('projects') and i.kind='task' and position(lower(term) in lower(i.title||' '||i.description))>0
   union all select 'article',id,title,left(body,600),'knowledge',null,null,updated_at from public.knowledge_articles
    where private.coco_module_allowed('knowledge') and position(lower(term) in lower(title||' '||body))>0
   union all select 'document',id,title,''::text,'documents',null,null,updated_at from public.business_documents
    where private.coco_module_allowed('documents') and position(lower(term) in lower(title))>0
   union all select 'customer',id,name,coalesce(city,''),'contacts',null,null,updated_at from public.customers
    where private.coco_module_allowed('contacts') and position(lower(term) in lower(name))>0
   union all select 'quote',id,coalesce(erp_reference,invoice_number),coalesce(quote_details->>'client',''),'quotes',null,null,updated_at
    from public.invoices where private.coco_module_allowed('quotes') and position(lower(term) in lower(coalesce(erp_reference,'')||' '||coalesce(invoice_number,'')||' '||coalesce(quote_details->>'client','')))>0
   union all select 'order',id,coalesce(erp_reference,number::text),customer_name,'sales-orders',null,null,updated_at
    from public.sales_orders where private.coco_module_allowed('sales-orders') and position(lower(term) in lower(coalesce(erp_reference,'')||' '||number::text||' '||coalesce(customer_name,'')))>0
   union all select 'opportunity',id,title,left(description,600),'crm',null,null,updated_at from public.crm_opportunities
    where private.coco_module_allowed('crm') and position(lower(term) in lower(title||' '||description))>0
  ), scoped as(select * from candidates where
   (p_action='search' and coalesce(p_data->>'kind','')='' or kind=p_data->>'kind'
    or p_data->>'kind'='documents' and kind in ('article','document')
    or p_data->>'kind'='customers' and kind in ('customer','opportunity'))),
  page as(select * from scoped order by updated_at desc,id limit lim offset offst)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),
   'total',(select count(*) from scoped)) into r;
  return r;
 elsif p_action='inbox' then
  if private.coco_module_allowed('assistant-ia') then
   r:=public.coco_module_history('list',jsonb_build_object('module_id','assistant-ia','pending_only',true));
   proposals:=coalesce(r->'proposals','[]');
  end if;
  with items as (
   select 'message'::text kind,m.id,left(m.body,180) title,left(m.body,600) body,'workhub'::text module,m.channel_id,
    null::uuid project_id,'unread'::text status,null::text due_at,m.updated_at
   from private.coco_workhub_messages m where m.created_by<>u
   union all select 'task',i.id,i.title,left(i.description,600),'projects',null,i.project_id,i.status,i.due_date::text,i.updated_at
    from public.pm_items i where private.coco_module_allowed('projects') and i.kind='task' and i.owner_id=u and i.status not in ('done','cancelled')
   union all select 'activity',id,subject,left(body,600),'crm',null,null,status,due_at::text,updated_at
    from public.crm_activities where private.coco_module_allowed('crm') and owner_id=u and status not in ('done','cancelled')
   union all select 'proposal',(x->>'id')::uuid,coalesce(x->>'summary',x->>'action'),'',
    'assistant-ia',null,null,'pending',null,coalesce(nullif(x->>'created_at',''),nullif(x->>'received_at',''),now()::text)::timestamptz
    from jsonb_array_elements(proposals) x where x->>'status'='pending'
  ), scoped as (
   select i.*,coalesce(s.status='archived' and s.source_updated_at>=i.updated_at,false) archived,s.snoozed_until
   from items i left join private.coco_workhub_states s on s.user_id=u and s.kind=i.kind and s.record_id=i.id
   where (coalesce(p_data->>'kind','')='' or i.kind=p_data->>'kind')
    and (term='' or position(lower(term) in lower(i.title||' '||coalesce(i.body,'')))>0)
  ), filtered as (
   select * from scoped where case coalesce(p_data->>'view','active') when 'archived' then archived
    when 'snoozed' then not archived and snoozed_until>now() when 'all' then true
    else not archived and (snoozed_until is null or snoozed_until<=now()) end
  ), page as(select * from filtered order by case when kind='proposal' then 0 else 1 end,due_at nulls last,updated_at desc,id limit lim offset offst)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),'total',(select count(*) from filtered)) into r;
  return r;
 end if;
 raise exception 'WORKHUB_UNKNOWN_ACTION';
end $$;
revoke all on function public.coco_workhub(text,jsonb) from public,anon;
grant execute on function public.coco_workhub(text,jsonb) to authenticated;

-- History contains action references, never copies of discussion bodies.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
values('coco_workhub_channels','workhub','Canal de trabajo','private','id'),
 ('coco_workhub_messages','workhub','Mensaje del equipo','private','id'),
 ('coco_workhub_members','workhub','Miembros del canal','private','channel_id'),
 ('coco_workhub_links','workhub','Referencia vinculada','private','id');
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_channels
 for each row execute function private.coco_capture_module_event();
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_messages
 for each row execute function private.coco_capture_module_event();

create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_members
 for each row execute function private.coco_capture_module_event();
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_links
 for each row execute function private.coco_capture_module_event();

alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_workhub;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table='coco_workhub_members' then return exists(select 1 from private.coco_workhub_members where channel_id::text=p_id);
 elsif p_table='coco_workhub_links' then return exists(select 1 from private.coco_workhub_links where id::text=p_id);
 elsif p_table='coco_workhub_channels' then return exists(select 1 from private.coco_workhub_channels where id::text=p_id);
 elsif p_table='coco_workhub_messages' then return exists(select 1 from private.coco_workhub_messages where id::text=p_id);
 end if;
 return private.coco_history_record_visible_before_workhub(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
-- Rebind the policy to the new invoker wrapper (renames keep original OIDs).
alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and case when record_table is not null then
 private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid() else true end);
notify pgrst,'reload schema';
