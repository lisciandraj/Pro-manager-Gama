-- Agent Coco: additive schema. No stock fixture, user account or business mutation.
-- Generate the versioned migration with `supabase migration new agent_coco_gateway`.
create table if not exists private.coco_agent_access (
 actor_id uuid primary key references public.profiles(id),
 enabled boolean not null default false, can_write boolean not null default false,
 client_ids text[] not null default '{}', revision bigint not null default 1,
 updated_at timestamptz not null default now()
);
create table if not exists private.coco_agent_commands (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 client_id text, request_key uuid not null, payload jsonb not null, snapshot jsonb not null,
 digest text not null, access_revision bigint not null,
 state text not null default 'prepared' check(state in ('prepared','submitted','failed')),
 result jsonb, created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '10 minutes',
 unique(actor_id,request_key)
);
create table if not exists private.coco_agent_events (
 id bigint generated always as identity primary key, actor_id uuid not null,
 command_id uuid, client_id text, event text not null, detail jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index if not exists coco_agent_commands_actor_date on private.coco_agent_commands(actor_id,created_at desc);
create index if not exists coco_agent_events_actor_date on private.coco_agent_events(actor_id,created_at desc);
alter table private.coco_agent_access enable row level security;
alter table private.coco_agent_commands enable row level security;
alter table private.coco_agent_events enable row level security;
revoke all on private.coco_agent_access,private.coco_agent_commands,private.coco_agent_events from public,anon,authenticated;

-- A delegated OAuth token can only enter the audited gateway through PostgREST.
-- This does NOT change ordinary ERP sessions, MFA, roles or existing approval rules.
create or replace function public.coco_agent_request_guard() returns void
language plpgsql security invoker set search_path='' as $$
begin
 if nullif(auth.jwt()->>'client_id','') is not null
 and coalesce(current_setting('request.path',true),'')<>'/rpc/coco_agent' then
  raise exception 'AGENT_ENDPOINT_NOT_ALLOWED' using errcode='42501';
 end if;
end $$;
revoke all on function public.coco_agent_request_guard() from public;
grant execute on function public.coco_agent_request_guard() to anon,authenticated,service_role;

-- Fail rather than replacing an unrelated pre-request hook.
do $$ declare hook text;r record;begin
 if exists(select 1 from pg_roles where rolname='authenticator') then
  select substring(v from length('pgrst.db_pre_request=')+1) into hook
  from pg_roles cross join lateral unnest(rolconfig) v
  where rolname='authenticator' and v like 'pgrst.db_pre_request=%';
  if hook is not null and hook<>'' and hook<>'public.coco_agent_request_guard' then
   raise exception 'AGENT_EXISTING_PRE_REQUEST_HOOK_REQUIRES_REVIEW';
  end if;
  execute 'alter role authenticator set pgrst.db_pre_request=''public.coco_agent_request_guard''';
 end if;
 -- Restrictive policies prevent bypass through Realtime or Storage. The gateway
 -- uses guarded private functions; ordinary authenticated users keep their policies.
 for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p') and c.relrowsecurity and
  (n.nspname='public' or (n.nspname='storage' and c.relname='objects') or (n.nspname='realtime' and c.relname='messages')) loop
  execute format('drop policy if exists coco_agent_no_direct_oauth on %I.%I',r.nspname,r.relname);
  execute format('create policy coco_agent_no_direct_oauth on %I.%I as restrictive for all to authenticated using (nullif(auth.jwt()->>''client_id'','''') is null) with check (nullif(auth.jwt()->>''client_id'','''') is null)',r.nspname,r.relname);
 end loop;
end $$;

create or replace function private.coco_agent(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();cid text:=nullif(auth.jwt()->>'client_id','');cfg private.coco_agent_access;
 cmd private.coco_agent_commands;prod public.products;quant public.stock_quants;
 lines jsonb;line jsonb;payload jsonb;snap jsonb;answer jsonb;receipts jsonb:='[]';
 key uuid;lid uuid;target numeric;qty numeric;total_delta numeric;reason text;kind text;op text;
 all_stock boolean;hash text;err text;off integer;lot_id uuid;lot_qty numeric;cfg_ids text[];
begin
 if uid is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_INPUT';end if;
 if p_action in ('settings','configure') then
  if cid is not null or not private.erp_module_allowed('assistant-ia',array['administrador'])
   or not private.erp_action_allowed('settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='configure' then
   if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'can_write') is distinct from 'boolean'
    or jsonb_typeof(p_data->'client_ids') is distinct from 'array' or jsonb_array_length(p_data->'client_ids')>10 then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_ids from jsonb_array_elements_text(p_data->'client_ids');
   if exists(select 1 from unnest(cfg_ids) x where x is null or x!~'^[A-Za-z0-9_-]{3,200}$') then raise exception 'INVALID_CLIENT_ID';end if;
   insert into private.coco_agent_access(actor_id,enabled,can_write,client_ids)
    values(uid,(p_data->>'enabled')::boolean,(p_data->>'can_write')::boolean,cfg_ids)
    on conflict(actor_id) do update set enabled=excluded.enabled,can_write=excluded.can_write,
     client_ids=excluded.client_ids,revision=coco_agent_access.revision+1,updated_at=now();
   insert into private.coco_agent_events(actor_id,event,detail) values(uid,'access_changed',p_data);
  end if;
  select * into cfg from private.coco_agent_access where actor_id=uid;
  return jsonb_build_object('enabled',coalesce(cfg.enabled,false),'can_write',coalesce(cfg.can_write,false),
   'client_ids',coalesce(cfg.client_ids,'{}'),'revision',cfg.revision,'actor_id',uid);
 end if;
 select * into cfg from private.coco_agent_access where actor_id=uid for share;
 if not found or not cfg.enabled then raise exception 'AGENT_ACCESS_DISABLED';end if;
 if cid is not null and not (cid=any(cfg.client_ids)) then raise exception 'AGENT_CLIENT_NOT_ALLOWED';end if;
 if p_action='search' then
  reason:=btrim(coalesce(p_data->>'query',''));
  if length(reason)<2 or length(reason)>200 then raise exception 'SEARCH_QUERY_REQUIRED';end if;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into answer from (
   select p.id,p.name,p.reference,p.base_unit,p.stock,p.lot_tracking
   from public.products p where p.active and p.product_kind='goods' and
    (strpos(lower(p.name),lower(reason))>0 or lower(p.reference)=lower(reason) or p.barcode=reason)
   order by case when lower(p.reference)=lower(reason) then 0 else 1 end,p.name,p.id limit 25) r;
  return jsonb_build_object('items',answer,'limit',25,'as_of',now());
 elsif p_action='stock' then
  select * into prod from public.products where id=(p_data->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('location_id',q.location_id,'location',l.code,'warehouse',w.name,
   'quantity',q.quantity,'reserved',q.reserved_quantity,'available',q.quantity-q.reserved_quantity) order by l.code),'[]') into answer
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id where q.product_id=prod.id;
  return jsonb_build_object('product_id',prod.id,'name',prod.name,'reference',prod.reference,'unit',prod.base_unit,
   'lot_tracking',prod.lot_tracking,'locations',answer,'as_of',now());
 elsif p_action='history' then
  off:=greatest(0,least(100000,coalesce((p_data->>'offset')::integer,0)));
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into answer from (
   select c.id,c.created_at,c.expires_at,c.state,c.payload,c.result,
    case when c.client_id is null then 'Coco ERP' else 'ChatGPT / OAuth' end as channel,
    p.full_name as actor_name
   from private.coco_agent_commands c join public.profiles p on p.id=c.actor_id where c.actor_id=uid
   order by c.created_at desc,c.id desc limit 25 offset off) r;
  return jsonb_build_object('items',answer,'offset',off);
 elsif p_action not in ('prepare','execute') then raise exception 'INVALID_ACTION';end if;
 if not cfg.can_write or not private.erp_action_allowed('warehouses','create')
  or not private.erp_action_allowed('movement','create') then raise exception 'AGENT_WRITE_NOT_ALLOWED';end if;
 if p_action='prepare' then
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-agent:'||uid::text||key::text,0));
  select * into cmd from private.coco_agent_commands where actor_id=uid and request_key=key;
  if found then
   if cmd.payload<>p_data or cmd.client_id is distinct from cid then raise exception 'REQUEST_KEY_REUSED';end if;
   return to_jsonb(cmd)-'actor_id'-'client_id'-'access_revision';
  end if;
  if (select count(*) from private.coco_agent_commands where actor_id=uid and created_at>now()-interval '1 minute')>=30 then raise exception 'AGENT_RATE_LIMIT';end if;
  reason:=btrim(coalesce(p_data->>'reason',''));op:=p_data->>'operation';kind:=coalesce(p_data->>'kind','inventory_difference');
  if length(reason)<3 or length(reason)>2000 or op not in ('out','in','adjust') or op is null then raise exception 'INVALID_INPUT';end if;
  if kind not in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening') then raise exception 'INVALID_ADJUSTMENT_KIND';end if;
  if op<>'out' and kind not in ('inventory_difference','opening') then raise exception 'EXCEPTION_OUT_ONLY';end if;
  all_stock:=coalesce((p_data->>'all_stock')::boolean,false);lid:=nullif(p_data->>'location_id','')::uuid;lot_id:=nullif(p_data->>'lot_id','')::uuid;
  if all_stock and (op<>'out' or lid is not null or p_data ? 'quantity' or p_data ? 'target_quantity') then raise exception 'INVALID_INPUT';end if;
  select * into prod from public.products where id=(p_data->>'product_id')::uuid and active for share;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if prod.product_kind<>'goods' then raise exception 'STOCK_GOODS_ONLY';end if;
  if prod.lot_tracking and (all_stock or lot_id is null) then raise exception 'AGENT_EXPLICIT_LOT_REQUIRED';end if;
  if not prod.lot_tracking and lot_id is not null then raise exception 'INVALID_LOT';end if;
  if not all_stock and lid is null then raise exception 'LOCATION_REQUIRED';end if;
  if all_stock then
   select coalesce(jsonb_agg(jsonb_build_object('location_id',q.location_id,'location',l.code,'expected_quantity',q.quantity,
    'reserved',q.reserved_quantity,'target_quantity',0) order by q.location_id),'[]') into lines
   from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id
   where q.product_id=prod.id and q.quantity>0;
  else
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   qty:=(p_data->>'quantity')::numeric;
   if op in ('out','in') and (qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty<>round(qty,3)) then raise exception 'INVALID_QUANTITY';end if;
   if (op='adjust' and p_data ? 'quantity') or (op<>'adjust' and p_data ? 'target_quantity') then raise exception 'INVALID_INPUT';end if;
   target:=case op when 'out' then coalesce(quant.quantity,0)-qty when 'in' then coalesce(quant.quantity,0)+qty else (p_data->>'target_quantity')::numeric end;
   lines:=jsonb_build_array(jsonb_build_object('location_id',lid,'expected_quantity',coalesce(quant.quantity,0),'reserved',coalesce(quant.reserved_quantity,0),'target_quantity',target));
  end if;
  if jsonb_array_length(lines)=0 then raise exception 'NO_CHANGE';end if;
  if jsonb_array_length(lines)>25 then raise exception 'AGENT_TOO_MANY_LOCATIONS';end if;
  total_delta:=0;
  for line in select value from jsonb_array_elements(lines) loop
   target:=(line->>'target_quantity')::numeric;
   if target is null or target::text in ('NaN','Infinity','-Infinity') or target<0 or target>999999999 or target<>round(target,3) then raise exception 'INVALID_QUANTITY';end if;
   if target<(line->>'reserved')::numeric then raise exception 'RESERVED_EXCEEDS_QUANTITY';end if;
   if target=(line->>'expected_quantity')::numeric then raise exception 'NO_CHANGE';end if;
   perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
    where l.id=(line->>'location_id')::uuid and l.active and w.active;
   if not found then raise exception 'LOCATION_NOT_FOUND';end if;
   total_delta:=total_delta+abs(target-(line->>'expected_quantity')::numeric);
  end loop;
  -- Never split a large operation across locations to avoid an approval threshold.
  if jsonb_array_length(lines)>1 and exists(select 1 from public.erp_policies where id and
   ((stock_adjustment_limit is not null and total_delta>stock_adjustment_limit) or
    (stock_adjustment_value_limit is not null and (prod.purchase_price<=0 or total_delta*prod.purchase_price>stock_adjustment_value_limit)))) then
   raise exception 'AGENT_GROUP_APPROVAL_USE_ERP';
  end if;
  if lot_id is not null then
   perform 1 from public.product_lots where id=lot_id and product_id=prod.id;
   if not found then raise exception 'INVALID_LOT';end if;
   select coalesce(sum(quantity),0) into lot_qty from public.stock_lot_balances where lot_id=private.coco_agent.lot_id and location_id=lid;
   if op='out' and lot_qty<qty then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  end if;
  snap:=jsonb_build_object('product_id',prod.id,'name',prod.name,'reference',prod.reference,'unit',prod.base_unit,'purchase_price',prod.purchase_price,
   'lot_tracking',prod.lot_tracking,'lot_quantity',lot_qty,'lines',lines,'quantity_changed',total_delta,
   'reason',reason,'kind',kind,'operation',op,'all_stock',all_stock,'policies',(select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r));
  hash:=encode(sha256(convert_to(jsonb_build_object('payload',p_data,'snapshot',snap,'actor',uid,'client',cid,'revision',cfg.revision)::text,'UTF8')),'hex');
  insert into private.coco_agent_commands(actor_id,client_id,request_key,payload,snapshot,digest,access_revision)
   values(uid,cid,key,p_data,snap,hash,cfg.revision) returning * into cmd;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event) values(uid,cmd.id,cid,'prepared');
  return to_jsonb(cmd)-'actor_id'-'client_id'-'access_revision';
 end if;
 select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid for update;
 if not found or cmd.client_id is distinct from cid then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb or p_data->>'digest' is distinct from cmd.digest then raise exception 'AGENT_CONFIRMATION_REQUIRED';end if;
 if cmd.state='submitted' then return cmd.result;end if;
 if cmd.state<>'prepared' then raise exception 'AGENT_COMMAND_CLOSED';end if;
 begin
  if cmd.expires_at<=now() then raise exception 'AGENT_PROPOSAL_EXPIRED';end if;
  if cfg.revision<>cmd.access_revision then raise exception 'AGENT_ACCESS_CHANGED';end if;
  select * into prod from public.products where id=(cmd.payload->>'product_id')::uuid for update;
  if not found or not prod.active or prod.product_kind<>'goods' or prod.lot_tracking is distinct from (cmd.snapshot->>'lot_tracking')::boolean
   or prod.purchase_price is distinct from (cmd.snapshot->>'purchase_price')::numeric then raise exception 'AGENT_PRODUCT_CHANGED';end if;
  if cmd.snapshot->'policies' is distinct from (select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r) then raise exception 'AGENT_POLICY_CHANGED';end if;
  perform 1 from public.stock_quants where product_id=prod.id order by location_id for update;
  if (cmd.snapshot->>'all_stock')::boolean and exists(select 1 from public.stock_quants q where q.product_id=prod.id and q.quantity>0 and
   not exists(select 1 from jsonb_array_elements(cmd.snapshot->'lines') x where (x->>'location_id')::uuid=q.location_id)) then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   lid:=(line->>'location_id')::uuid;
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   if coalesce(quant.quantity,0) is distinct from (line->>'expected_quantity')::numeric or coalesce(quant.reserved_quantity,0) is distinct from (line->>'reserved')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end loop;
  -- The existing ERP API checks lots, locations, reservations, approvals and MFA.
  -- All lines and the receipt commit in one transaction, including retries.
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   payload:=jsonb_build_object('request_key',gen_random_uuid(),'product_id',prod.id,'location_id',line->'location_id',
    'expected_quantity',line->'expected_quantity','target_quantity',line->'target_quantity',
    'reason',cmd.snapshot->>'reason','kind',cmd.snapshot->>'kind');
   if nullif(cmd.payload->>'lot_id','') is not null then payload:=payload||jsonb_build_object('lot_id',cmd.payload->>'lot_id');end if;
   answer:=public.gama_adjustment_request('submit',payload);
   receipts:=receipts||jsonb_build_array(answer);
  end loop;
  answer:=jsonb_build_object('command_id',cmd.id,'status',case when exists(select 1 from jsonb_array_elements(receipts) x where x->>'status'='pending') then 'pending_approval' else 'executed' end,
   'adjustments',receipts,'stock_after',(select coalesce(sum(quantity),0) from public.stock_quants where product_id=prod.id),
   'actor_id',uid,'agent','Agent Coco','completed_at',now());
  update private.coco_agent_commands set state='submitted',result=answer where id=cmd.id;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event,detail) values(uid,cmd.id,cid,'submitted',answer);
  return answer;
 exception when others then
  get stacked diagnostics err=message_text;
  if err !~ '^[A-Z][A-Z0-9_]{2,100}$' then err:='AGENT_EXECUTION_FAILED';end if;
  answer:=jsonb_build_object('command_id',cmd.id,'status','rejected','error',err);
  update private.coco_agent_commands set state='failed',result=answer where id=cmd.id;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event,detail) values(uid,cmd.id,cid,'rejected',answer);
  return answer;
 end;
end $$;
revoke all on function private.coco_agent(text,jsonb) from public,anon;
grant execute on function private.coco_agent(text,jsonb) to authenticated;
create or replace function public.coco_agent(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_agent(p_action,p_data)$$;
revoke all on function public.coco_agent(text,jsonb) from public,anon;
grant execute on function public.coco_agent(text,jsonb) to authenticated;
notify pgrst,'reload config';
notify pgrst,'reload schema';
