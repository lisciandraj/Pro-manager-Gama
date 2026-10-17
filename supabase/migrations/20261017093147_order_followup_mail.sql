-- Additive order chatter. Mail credentials never enter an exposed table.
create table private.coco_mail_accounts(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 provider text not null check(provider in ('google','microsoft')), email text not null,
 credentials text not null, connected_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table private.coco_mail_oauth(
 state_hash text primary key, user_id uuid not null references public.profiles(id) on delete cascade,
 provider text not null check(provider in ('google','microsoft')), verifier text not null,
 expires_at timestamptz not null default now()+interval '10 minutes'
);
create index coco_mail_oauth_expiry on private.coco_mail_oauth(expires_at);
create table private.coco_order_entries(
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('sales','purchase')),
 order_id uuid not null, type text not null check(type in ('note','mail','action')),
 actor_id uuid references public.profiles(id) on delete set null, actor_name text not null,
 created_at timestamptz not null default now(), subject text not null default '', body text not null default '',
 direction text check(direction in ('in','out')), status text not null default 'recorded',
 from_email text, to_email text, request_key uuid,
 mail_owner uuid references public.profiles(id) on delete set null,
 provider text, provider_id text, thread_id text, internet_id text, reply_id uuid references private.coco_order_entries(id),
 attachments jsonb not null default '[]', detail jsonb not null default '{}',
 unique(actor_id,request_key), unique(mail_owner,provider,provider_id),
 check(length(subject)<=300 and length(body)<=100000 and jsonb_typeof(attachments)='array' and octet_length(attachments::text)<=20000),
 check(status in ('recorded','sending','sent','accepted','received','failed','uncertain'))
);
create index coco_order_entries_page on private.coco_order_entries(kind,order_id,created_at desc,id);
create index coco_order_entries_thread on private.coco_order_entries(mail_owner,kind,order_id,thread_id) where thread_id is not null;
create index coco_order_entries_actor on private.coco_order_entries(actor_id);
create index coco_order_entries_reply on private.coco_order_entries(reply_id);
alter table private.coco_mail_accounts enable row level security;
alter table private.coco_mail_oauth enable row level security;
alter table private.coco_order_entries enable row level security;
revoke all on private.coco_mail_accounts,private.coco_mail_oauth,private.coco_order_entries from public,anon,authenticated;

-- Reuse the existing redacted history and its financial-stage filtering. Only
-- its entry permission changes: the owning order module suffices here.
do $$declare source text;begin
 source:=pg_get_functiondef('private.gama_process_history(text,integer,integer)'::regprocedure);
 source:=replace(source,'private.gama_process_history(', 'private.coco_order_process_history(');
 if strpos(source,'model:=private.gama_processes(''state'',jsonb_build_object(''key'',p_key));')=0 then raise exception 'HISTORY_CONTRACT_CHANGED';end if;
 source:=replace(source, 'model:=private.gama_processes(''state'',jsonb_build_object(''key'',p_key));',
 'if k not in (''o'',''p'') or not private.erp_module_allowed(case when k=''o'' then ''sales-orders'' else ''gamaPurchasesV14'' end,array[''administrador'',''comercial'',''almacenero'']) then raise exception ''ROLE_NOT_ALLOWED'';end if; model:=private.gama_process_state(p_key);');
 if strpos(source,'private.gama_processes(''state''')>0 then raise exception 'HISTORY_CONTRACT_CHANGED';end if;
 execute source;
end $$;
revoke all on function private.coco_order_process_history(text,integer,integer) from public,anon,authenticated;

create function private.coco_order_context(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare mod text; o jsonb; party text; recipient text; me text; comm boolean;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_kind not in ('sales','purchase') then raise exception 'INVALID_ORDER_KIND';end if;
 mod:=case when p_kind='sales' then 'sales-orders' else 'gamaPurchasesV14' end;
 if not private.erp_module_allowed(mod,array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 comm:=private.erp_module_allowed(mod,array['administrador','comercial']);
 if p_kind='sales' then
  select jsonb_build_object('id',s.id,'number',s.number,'status',s.status),s.customer_name,c.email into o,party,recipient from public.sales_orders s left join public.customers c on c.id=s.customer_id where s.id=p_id;
 else
  select jsonb_build_object('id',s.id,'number',s.order_number,'status',s.status),c.name,c.email into o,party,recipient from public.purchase_orders s left join public.suppliers c on c.id=s.supplier_id where s.id=p_id;
 end if;
 if o is null then raise exception 'ORDER_NOT_FOUND';end if;
 select email into me from auth.users where id=auth.uid();
 return o||jsonb_build_object('kind',p_kind,'party',party,'email',case when comm then recipient end,'actor_id',auth.uid(),'account_email',me,
 'can_mail',comm and private.erp_action_allowed(mod,'edit'),'can_note',private.erp_action_allowed(mod,'edit'),'commercial',comm,
 'mailbox',(select jsonb_build_object('provider',provider,'email',email,'connected_at',connected_at) from private.coco_mail_accounts where user_id=auth.uid() and lower(email)=lower(me)));
end $$;
revoke all on function private.coco_order_context(text,uuid) from public,anon,authenticated;

create function private.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'kind'; oid uuid:=(p_data->>'order_id')::uuid; ctx jsonb; items jsonb; history jsonb; off integer:=coalesce((p_data->>'offset')::integer,0); entry private.coco_order_entries; old private.coco_order_entries; key uuid; author text;
begin
 ctx:=private.coco_order_context(k,oid);
 if p_action='context' then return ctx;end if;
 if p_action='list' then
  if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
  history:=private.coco_order_process_history((case when k='sales' then 'o:' else 'p:' end)||oid::text,0,off);
  select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id),'[]') into items from (
   select e.created_at,e.id,(to_jsonb(e)-'mail_owner'-'provider_id'-'thread_id'-'internet_id'-'request_key'-'actor_id'-'detail')||
    jsonb_build_object('own_mailbox',e.mail_owner=auth.uid()) as data
   from private.coco_order_entries e where e.kind=k and e.order_id=oid
    and (e.type<>'mail' or (ctx->>'commercial')::boolean)
   order by e.created_at desc,e.id offset off limit 51
  ) x;
  return jsonb_build_object('context',ctx,'entries',items,'history',history->'items');
 end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 if p_action='purchase_mail_sent' then
  if k<>'purchase' or not (ctx->>'can_mail')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into entry from private.coco_order_entries where id=(p_data->>'message_id')::uuid and kind=k and order_id=oid and mail_owner=auth.uid() and direction='out' and status in ('sent','accepted');
  if entry.id is null then raise exception 'MESSAGE_NOT_SENT';end if;
  -- A concurrent receipt/cancellation must never be overwritten after a slow send.
  update public.purchase_orders set status='sent',updated_at=now() where id=oid and status='draft';
  return private.coco_order_context(k,oid);
 elsif p_action='purchase_manual_sent' then
  if k<>'purchase' or not (ctx->>'can_mail')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  if length(btrim(coalesce(p_data->>'body',''))) not between 3 and 1000 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform 1 from public.purchase_orders where id=oid for update;
  select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;
  if entry.id is not null then
   if entry.kind<>k or entry.order_id<>oid or entry.subject<>'purchase_manual_sent' or entry.body<>btrim(p_data->>'body') then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',entry.id);
  end if;
  update public.purchase_orders set status='sent',updated_at=now() where id=oid and status='draft';
  if not found then raise exception 'ORDER_STATE_CHANGED';end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,request_key)
   values(k,oid,'action',auth.uid(),author,'purchase_manual_sent',btrim(p_data->>'body'),key) returning * into entry;
  return jsonb_build_object('id',entry.id);
 elsif p_action='note' then
  if not (ctx->>'can_note')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  if length(btrim(coalesce(p_data->>'body',''))) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,body,request_key)
   values(k,oid,'note',auth.uid(),author,btrim(p_data->>'body'),key) on conflict(actor_id,request_key) do nothing returning * into entry;
  if entry.id is null then select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;end if;
  if entry.kind<>k or entry.order_id<>oid or entry.body<>btrim(p_data->>'body') or entry.type<>'note' then raise exception 'REQUEST_KEY_REUSED';end if;
  return jsonb_build_object('id',entry.id);
 elsif p_action='mail_claim' then
  if not (ctx->>'can_mail')::boolean or ctx->'mailbox'='null'::jsonb then raise exception 'MAILBOX_REQUIRED';end if;
  if length(btrim(coalesce(p_data->>'subject',''))) not between 1 and 300 or (p_data->>'subject')~E'[\r\n]' or length(btrim(coalesce(p_data->>'body',''))) not between 1 and 50000
   or coalesce(p_data->>'to','')!~'^[^\s@<>;,]+@[^\s@<>;,]+\.[^\s@<>;,]+$' or length(p_data->>'to')>254 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  if p_data->>'reply_id' is not null then
   select * into old from private.coco_order_entries where id=(p_data->>'reply_id')::uuid and kind=k and order_id=oid and mail_owner=auth.uid() and type='mail' and thread_id is not null and provider=ctx->'mailbox'->>'provider';
   if old.id is null then raise exception 'REPLY_NOT_ALLOWED';end if;
  end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,direction,status,from_email,to_email,request_key,mail_owner,provider,reply_id,attachments)
   values(k,oid,'mail',auth.uid(),author,btrim(p_data->>'subject'),p_data->>'body','out','sending',ctx->>'account_email',lower(btrim(p_data->>'to')),key,auth.uid(),ctx->'mailbox'->>'provider',old.id,coalesce(p_data->'attachments','[]'))
   on conflict(actor_id,request_key) do nothing returning * into entry;
  if entry.id is null then
   select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;
   if entry.kind<>k or entry.order_id<>oid or entry.subject<>btrim(p_data->>'subject') or entry.body<>p_data->>'body' or entry.to_email<>lower(btrim(p_data->>'to')) or entry.reply_id is distinct from old.id or entry.type<>'mail' then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('claimed',false,'id',entry.id,'status',entry.status);
  end if;
  return jsonb_build_object('claimed',true,'id',entry.id,'status',entry.status);
 elsif p_action='disconnect' then
  delete from private.coco_mail_accounts where user_id=auth.uid();
  delete from private.coco_mail_oauth where user_id=auth.uid();return jsonb_build_object('disconnected',true);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_order_followup(text,jsonb) from public,anon;
grant execute on function private.coco_order_followup(text,jsonb) to authenticated;
create function public.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_order_followup(p_action,p_data)$$;
revoke all on function public.coco_order_followup(text,jsonb) from public,anon;
grant execute on function public.coco_order_followup(text,jsonb) to authenticated;

-- Only the authenticated Edge handler can call this service-role facade.
create function private.coco_order_mail_service(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=(p_data->>'user_id')::uuid; me text; entry private.coco_order_entries; account private.coco_mail_accounts; state private.coco_mail_oauth; result jsonb;
begin
 if p_action='oauth_take' then
  delete from private.coco_mail_oauth where state_hash=p_data->>'state_hash' and expires_at>now() returning * into state;
  if state.user_id is null then raise exception 'OAUTH_EXPIRED';end if;uid:=state.user_id;
 end if;
 select u.email into me from auth.users u join public.profiles p on p.id=u.id where u.id=uid and p.active and p.role in ('administrador','comercial') and (u.banned_until is null or u.banned_until<now());
 if me is null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='oauth_take' then return to_jsonb(state)||jsonb_build_object('email',me);end if;
 if p_action='oauth_store' then
  delete from private.coco_mail_oauth where user_id=uid or expires_at<now();
  insert into private.coco_mail_oauth(state_hash,user_id,provider,verifier) values(p_data->>'state_hash',uid,p_data->>'provider',p_data->>'verifier');return '{}';
 elsif p_action='account_save' then
  if lower(p_data->>'email') is distinct from lower(me) then raise exception 'MAILBOX_EMAIL_MISMATCH';end if;
  insert into private.coco_mail_accounts(user_id,provider,email,credentials) values(uid,p_data->>'provider',lower(me),p_data->>'credentials')
  on conflict(user_id) do update set provider=excluded.provider,email=excluded.email,credentials=excluded.credentials,updated_at=now();return '{}';
 elsif p_action='account' then
  select * into account from private.coco_mail_accounts where user_id=uid and lower(email)=lower(me);return to_jsonb(account);
 elsif p_action='message' then
  select * into entry from private.coco_order_entries where id=(p_data->>'id')::uuid and mail_owner=uid and type='mail';
  if entry.id is null then raise exception 'MESSAGE_NOT_FOUND';end if;
  return to_jsonb(entry)||jsonb_build_object('reply',(select to_jsonb(r) from private.coco_order_entries r where r.id=entry.reply_id and r.mail_owner=uid));
 elsif p_action='message_status' then
  select * into entry from private.coco_order_entries where id=(p_data->>'id')::uuid and mail_owner=uid and direction='out' for update;
  if entry.id is null then raise exception 'MESSAGE_NOT_FOUND';end if;
  if p_data->>'thread_id' is not null then
   perform pg_advisory_xact_lock(hashtextextended(uid::text||entry.provider||(p_data->>'thread_id'),0));
   if exists(select 1 from private.coco_order_entries e where e.mail_owner=uid and e.provider=entry.provider and e.thread_id=p_data->>'thread_id' and (e.kind<>entry.kind or e.order_id<>entry.order_id)) then raise exception 'THREAD_LINKED_ELSEWHERE';end if;
  end if;
  update private.coco_order_entries set status=coalesce(p_data->>'status',status),provider_id=coalesce(p_data->>'provider_id',provider_id),thread_id=coalesce(p_data->>'thread_id',thread_id),internet_id=coalesce(p_data->>'internet_id',internet_id)
   where id=(p_data->>'id')::uuid and mail_owner=uid and direction='out' returning * into entry;
  if entry.id is null then raise exception 'MESSAGE_NOT_FOUND';end if;
  return jsonb_build_object('id',entry.id,'status',entry.status);
 elsif p_action='pending' then
  select coalesce(jsonb_agg(t),'[]') into result from (select id,provider,internet_id from private.coco_order_entries where mail_owner=uid and kind=p_data->>'kind' and order_id=(p_data->>'order_id')::uuid and direction='out' and status in ('sending','uncertain') and thread_id is null and created_at<now()-interval '90 seconds' order by created_at limit 20) t;return result;
 elsif p_action='threads' then
  select coalesce(jsonb_agg(t),'[]') into result from (select thread_id,provider,max(created_at) at from private.coco_order_entries where mail_owner=uid and kind=p_data->>'kind' and order_id=(p_data->>'order_id')::uuid and thread_id is not null group by thread_id,provider order by max(created_at) desc limit 100) t;return result;
 elsif p_action='import' then
  -- The handler fetches only an already linked thread in this user's mailbox.
  if not exists(select 1 from private.coco_order_entries e where e.mail_owner=uid and e.kind=p_data->>'kind' and e.order_id=(p_data->>'order_id')::uuid and e.provider=p_data->>'provider' and e.thread_id=p_data->>'thread_id') then raise exception 'THREAD_NOT_LINKED';end if;
  if lower(p_data->>'from_email')=lower(me) then
   update private.coco_order_entries set status='sent',provider_id=coalesce(provider_id,p_data->>'provider_id'),internet_id=coalesce(internet_id,p_data->>'internet_id') where mail_owner=uid and provider=p_data->>'provider' and (provider_id=p_data->>'provider_id' or internet_id=p_data->>'internet_id') and direction='out';
  end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,created_at,subject,body,direction,status,from_email,to_email,mail_owner,provider,provider_id,thread_id,internet_id,attachments)
   values(p_data->>'kind',(p_data->>'order_id')::uuid,'mail',case when lower(p_data->>'from_email')=lower(me) then uid end,
    case when lower(p_data->>'from_email')=lower(me) then (select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') from public.profiles where id=uid) else left(coalesce(p_data->>'sender',p_data->>'from_email',''),300) end,
    (p_data->>'created_at')::timestamptz,left(coalesce(p_data->>'subject',''),300),left(coalesce(p_data->>'body',''),100000),case when lower(p_data->>'from_email')=lower(me) then 'out' else 'in' end,
    case when lower(p_data->>'from_email')=lower(me) then 'sent' else 'received' end,p_data->>'from_email',p_data->>'to_email',uid,p_data->>'provider',p_data->>'provider_id',p_data->>'thread_id',p_data->>'internet_id',coalesce(p_data->'attachments','[]'))
   on conflict(mail_owner,provider,provider_id) do nothing returning to_jsonb(id) into result;
  return jsonb_build_object('imported',result is not null);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_order_mail_service(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_order_mail_service(text,jsonb) to service_role;
create function public.coco_order_mail_service(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.coco_order_mail_service(p_action,p_data)$$;
revoke all on function public.coco_order_mail_service(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_order_mail_service(text,jsonb) to service_role;

-- Extra edits not already represented by status/receipt events are recorded at
-- the database boundary, including changes made outside the current browser.
create function private.coco_order_edit_event() returns trigger language plpgsql security definer set search_path='' as $$
declare n jsonb:=to_jsonb(new);o jsonb:=to_jsonb(old);fields jsonb;kind text:=tg_argv[0];oid uuid;author text;
begin
 select jsonb_agg(key order by key) into fields from jsonb_each(n) where key=any(array['notes','expected_date','supplier_reference','delivery_address','customer_id','supplier_id','quantity','unit_price','unit_cost','tax_rate']) and value is distinct from o->key;
 if fields is null then return new;end if;
 oid:=case when tg_table_name in ('sales_orders','purchase_orders') then new.id else coalesce(n->>'order_id',n->>'purchase_order_id')::uuid end;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body)
 values(kind,oid,'action',auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),'order_updated',fields::text);
 return new;
end $$;
revoke all on function private.coco_order_edit_event() from public,anon,authenticated;
create trigger coco_order_edit_event after update on public.sales_orders for each row execute function private.coco_order_edit_event('sales');
create trigger coco_order_edit_event after update on public.sales_order_lines for each row execute function private.coco_order_edit_event('sales');
create trigger coco_order_edit_event after update on public.purchase_orders for each row execute function private.coco_order_edit_event('purchase');
create trigger coco_order_edit_event after update on public.purchase_order_lines for each row execute function private.coco_order_edit_event('purchase');
notify pgrst,'reload schema';
