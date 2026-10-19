begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
do $$begin
if md5(pg_get_functiondef('private.coco_agent(text,jsonb)'::regprocedure)) not in ('996966a1e1b944bbc13bc13365a8abda','1d8412a2959929041617ec35616255f8') then raise exception 'AUDIT_SECURITY_DEFINITION_CHANGED';end if;
if md5(pg_get_functiondef('private.erp_mfa_ok()'::regprocedure)) <> 'b427e2c008fc5f49c1be63dc00c1a4f6' then raise exception 'AUDIT_SECURITY_DEFINITION_CHANGED';end if;
end $$;
CREATE OR REPLACE FUNCTION private.coco_agent_executor(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 uid uuid:=auth.uid();cid text:=nullif(auth.jwt()->>'client_id','');cfg private.coco_agent_access;
 cmd private.coco_agent_commands;prod public.products;quant public.stock_quants;
 lines jsonb;line jsonb;payload jsonb;snap jsonb;answer jsonb;receipts jsonb:='[]';
 key uuid;lid uuid;target numeric;qty numeric;total_delta numeric;reason text;kind text;op text;
 all_stock boolean;hash text;err text;off integer;lot_id uuid;lot_qty numeric;cfg_ids text[];cfg_write_ids text[];
begin
 if uid is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_INPUT';end if;
 if p_action in ('settings','configure') then
  if cid is not null or not private.erp_module_allowed('assistant-ia',array['administrador'])
   or not private.erp_action_allowed('settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='configure' then
   if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'can_write') is distinct from 'boolean'
    or jsonb_typeof(p_data->'client_ids') is distinct from 'array' or jsonb_array_length(p_data->'client_ids')>10 then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_ids from jsonb_array_elements_text(p_data->'client_ids');
   if jsonb_typeof(coalesce(p_data->'write_client_ids','[]')) is distinct from 'array' then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_write_ids from jsonb_array_elements_text(coalesce(p_data->'write_client_ids','[]'));
   if not (cfg_write_ids <@ cfg_ids) or array_position(cfg_write_ids,null) is not null then raise exception 'INVALID_CLIENT_ID';end if;
   if exists(select 1 from unnest(cfg_ids) x where x is null or x!~'^[A-Za-z0-9_-]{3,200}$') then raise exception 'INVALID_CLIENT_ID';end if;
   insert into private.coco_agent_access(actor_id,enabled,can_write,client_ids,write_client_ids)
    values(uid,(p_data->>'enabled')::boolean,(p_data->>'can_write')::boolean,cfg_ids,cfg_write_ids)
    on conflict(actor_id) do update set enabled=excluded.enabled,can_write=excluded.can_write,
     client_ids=excluded.client_ids,write_client_ids=excluded.write_client_ids,revision=coco_agent_access.revision+1,updated_at=now();
   insert into private.coco_agent_events(actor_id,event,detail) values(uid,'access_changed',p_data);
  end if;
  select * into cfg from private.coco_agent_access where actor_id=uid;
  return jsonb_build_object('enabled',coalesce(cfg.enabled,false),'can_write',coalesce(cfg.can_write,false),
   'client_ids',coalesce(cfg.client_ids,'{}'),'write_client_ids',coalesce(cfg.write_client_ids,'{}'),'revision',cfg.revision,'actor_id',uid);
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
 elsif p_action='status' then
  select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid and client_id is not distinct from cid;
  if not found then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'reference',a.erp_reference,'status',a.status,'reason',a.reason,'movement_id',a.movement_id)),'[]') into receipts
   from public.stock_adjustment_requests a where a.id in (select (x->>'id')::uuid from jsonb_array_elements(coalesce(cmd.result->'adjustments','[]')) x);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'reference',m.erp_reference,'quantity',m.quantity,'reason',m.reason,'stock_before',m.stock_before,'stock_after',m.stock_after,'user_id',m.user_id,'created_at',m.created_at)),'[]') into lines
   from public.stock_movements m where m.id in (select (x->>'movement_id')::uuid from jsonb_array_elements(receipts) x);
  return jsonb_build_object('command_id',cmd.id,'original_receipt',cmd.result,'adjustments',receipts,'movements',lines,'as_of',now(),
   'status',case when cmd.state='prepared' then case when cmd.expires_at<=now() then 'expired' else 'prepared' end
    when cmd.state='failed' then 'rejected' when exists(select 1 from jsonb_array_elements(receipts) x where x->>'status'='pending') then 'pending_approval'
    when jsonb_array_length(receipts)>0 and jsonb_array_length(lines)=jsonb_array_length(receipts) then 'executed' else 'rejected' end,
   'stock_now',(select coalesce(sum(quantity),0) from public.stock_quants where product_id=(cmd.payload->>'product_id')::uuid));
 elsif p_action not in ('prepare','execute','plan_claim') then raise exception 'INVALID_ACTION';end if;
 if not cfg.can_write or (cid is not null and not(cid=any(cfg.write_client_ids))) or not private.erp_action_allowed('warehouses','create')
  or not private.erp_action_allowed('movement','create') then raise exception 'AGENT_WRITE_NOT_ALLOWED';end if;
 if p_action='plan_claim' then
  if cid is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-agent-planning:'||uid::text,0));
  if (select count(*) from private.coco_agent_events where actor_id=uid and event='planning' and created_at>now()-interval '1 minute')>=10 then raise exception 'AGENT_RATE_LIMIT';end if;
  insert into private.coco_agent_events(actor_id,event,detail) values(uid,'planning',jsonb_build_object('request_key',key));
  return jsonb_build_object('allowed',true);
 end if;
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
  if jsonb_array_length(lines)>1 and exists(select 1 from public.erp_policies where id and
   ((stock_adjustment_limit is not null and total_delta>stock_adjustment_limit) or
    (stock_adjustment_value_limit is not null and (prod.purchase_price<=0 or total_delta*prod.purchase_price>stock_adjustment_value_limit)))) then
   raise exception 'AGENT_GROUP_APPROVAL_USE_ERP';
  end if;
  if lot_id is not null then
   perform 1 from public.product_lots where id=lot_id and product_id=prod.id;
   if not found then raise exception 'INVALID_LOT';end if;
   select coalesce(sum(quantity),0) into lot_qty from public.stock_lot_balances b where b.lot_id=(p_data->>'lot_id')::uuid and b.location_id=lid;
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
   or prod.purchase_price is distinct from (cmd.snapshot->>'purchase_price')::numeric
   or prod.name is distinct from cmd.snapshot->>'name' or prod.reference is distinct from cmd.snapshot->>'reference'
   or prod.base_unit is distinct from cmd.snapshot->>'unit' then raise exception 'AGENT_PRODUCT_CHANGED';end if;
  if cmd.snapshot->'policies' is distinct from (select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r) then raise exception 'AGENT_POLICY_CHANGED';end if;
  perform 1 from public.stock_quants where product_id=prod.id order by location_id for update;
  if (cmd.snapshot->>'all_stock')::boolean and exists(select 1 from public.stock_quants q where q.product_id=prod.id and q.quantity>0 and
   not exists(select 1 from jsonb_array_elements(cmd.snapshot->'lines') x where (x->>'location_id')::uuid=q.location_id)) then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   lid:=(line->>'location_id')::uuid;
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   if coalesce(quant.quantity,0) is distinct from (line->>'expected_quantity')::numeric or coalesce(quant.reserved_quantity,0) is distinct from (line->>'reserved')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end loop;
  if nullif(cmd.payload->>'lot_id','') is not null then
   select coalesce(sum(b.quantity),0) into lot_qty from public.stock_lot_balances b where b.lot_id=(cmd.payload->>'lot_id')::uuid and b.location_id=(cmd.payload->>'location_id')::uuid;
   if lot_qty is distinct from (cmd.snapshot->>'lot_quantity')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end if;
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
end $function$
;
revoke all on function private.coco_agent_executor(text,jsonb) from public,anon,authenticated,service_role;
-- No existing administrator is locked out before enrollment and recovery setup.
create table private.mfa_enforcement (
 actor_id uuid primary key references public.profiles(id), activated_at timestamptz not null default now()
);
alter table private.mfa_enforcement enable row level security;
revoke all on private.mfa_enforcement from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.erp_mfa_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (
  auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (
   nullif(auth.jwt()->>'session_id','') is null
   or exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id'
    and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()))
  )
  and (coalesce(auth.jwt()->>'aal'='aal2',false)
   or (not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified') and not exists(select 1 from private.mfa_enforcement e where e.actor_id=auth.uid())))
 ) or private.automation_delegation_ok()
$function$
;
create function private.coco_security_enrollment(p_action text default 'status') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();adm boolean;verified boolean;
begin
 if uid is null or nullif(auth.jwt()->>'client_id','') is not null or not exists(
  select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=uid and p.active and p.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now())) then raise exception 'AUTH_REQUIRED';end if;
 select role='administrador' into adm from public.profiles where id=uid;
 select exists(select 1 from auth.mfa_factors where user_id=uid and status='verified') into verified;
 if p_action='activate' then
  if auth.jwt()->>'aal' is distinct from 'aal2' or not verified or not private.erp_mfa_ok() then raise exception 'MFA_VERIFICATION_REQUIRED';end if;
  insert into private.mfa_enforcement(actor_id) values(uid) on conflict do nothing;
 elsif p_action<>'status' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('administrator',adm,'verified_factor',verified,'enforced',exists(select 1 from private.mfa_enforcement where actor_id=uid));
end $$;
create function public.coco_security_enrollment(p_action text default 'status') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_security_enrollment(p_action)$$;
revoke all on function public.coco_security_enrollment(text),private.coco_security_enrollment(text) from public,anon,service_role;
grant execute on function public.coco_security_enrollment(text),private.coco_security_enrollment(text) to authenticated;

-- The key is only released to its current authenticated owner. It is never
-- persisted alongside the encrypted IndexedDB payload or included in telemetry.
create table private.offline_proof_keys (
 actor_id uuid primary key references public.profiles(id),
 key_material text not null default encode(sha256(convert_to(gen_random_uuid()::text||gen_random_uuid()::text,'UTF8')),'hex'),
 created_at timestamptz not null default now()
);
alter table private.offline_proof_keys enable row level security;
revoke all on private.offline_proof_keys from public,anon,authenticated,service_role;
create function private.coco_offline_key() returns jsonb language plpgsql security definer set search_path='' as $$
declare material text;
begin
 if auth.uid() is null or nullif(auth.jwt()->>'client_id','') is not null or not private.erp_mfa_ok()
  or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 insert into private.offline_proof_keys(actor_id) values(auth.uid()) on conflict do nothing;
 select key_material into material from private.offline_proof_keys where actor_id=auth.uid();
 return jsonb_build_object('actor_id',auth.uid(),'key',material);
end $$;
create function public.coco_offline_key() returns jsonb language sql security invoker set search_path='' as $$select private.coco_offline_key()$$;
revoke all on function public.coco_offline_key(),private.coco_offline_key() from public,anon,service_role;
grant execute on function public.coco_offline_key(),private.coco_offline_key() to authenticated;

create table private.coco_agent_approvals (
 command_id uuid primary key references private.coco_agent_commands(id),
 receipt uuid not null default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 digest text not null, session_id text not null, mfa_timestamp bigint not null,
 approved_at timestamptz not null default now(), expires_at timestamptz not null,
 unique(actor_id,session_id,mfa_timestamp)
);
alter table private.coco_agent_approvals enable row level security;
revoke all on private.coco_agent_approvals from public,anon,authenticated,service_role;
-- All legacy execution checks, locks and immutable receipts remain in the
-- inaccessible executor. Only this approval gate can call it.
create or replace function private.coco_agent(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();cid text:=nullif(auth.jwt()->>'client_id','');cmd private.coco_agent_commands;
 cfg private.coco_agent_access; approval private.coco_agent_approvals; stamp bigint;sid text:=nullif(auth.jwt()->>'session_id','');
begin
 if p_action not in ('approvals','approve','execute') then return private.coco_agent_executor(p_action,p_data);end if;
 if uid is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_INPUT';end if;
 select * into cfg from private.coco_agent_access where actor_id=uid for share;
 if not found or not cfg.enabled then raise exception 'AGENT_ACCESS_DISABLED';end if;
 if p_action='approvals' then
  if cid is not null then raise exception 'AGENT_HUMAN_APPROVAL_REQUIRED';end if;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(
   select c.id,c.digest,c.snapshot,c.created_at,c.expires_at,c.client_id,exists(select 1 from private.coco_agent_approvals a where a.command_id=c.id) approved
   from private.coco_agent_commands c where c.actor_id=uid and c.state='prepared' and c.expires_at>now() order by c.created_at desc limit 50)x));
 end if;
 select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid for update;
 if not found then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
 if p_data->>'digest' is distinct from cmd.digest or (p_action='execute' and p_data->'confirmed' is distinct from 'true'::jsonb) then raise exception 'AGENT_CONFIRMATION_REQUIRED';end if;
 if p_action='execute' then
  -- A submitted receipt remains readable on retry, even after approval expiry.
  if cmd.state<>'submitted' and not exists(select 1 from private.coco_agent_approvals a where a.command_id=cmd.id and a.actor_id=uid and a.digest=cmd.digest and a.expires_at>now()) then raise exception 'AGENT_HUMAN_APPROVAL_REQUIRED';end if;
  return private.coco_agent_executor(p_action,p_data);
 end if;
 if cid is not null or auth.jwt()->>'aal' is distinct from 'aal2' or sid is null then raise exception 'AGENT_HUMAN_APPROVAL_REQUIRED';end if;
 if not cfg.can_write or cfg.revision<>cmd.access_revision then raise exception 'AGENT_ACCESS_CHANGED';end if;
 if cmd.state<>'prepared' or cmd.expires_at<=now() then raise exception 'AGENT_PROPOSAL_EXPIRED';end if;
 select * into approval from private.coco_agent_approvals where command_id=cmd.id;
 if found then return jsonb_build_object('receipt',approval.receipt,'expires_at',approval.expires_at);end if;
 select max((a->>'timestamp')::bigint) into stamp from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]')) a
  where a->>'method'='totp' and a->>'timestamp'~'^[0-9]{1,12}$';
 -- One fresh, post-proposal TOTP verification may approve exactly one digest.
 if stamp is null or stamp<=floor(extract(epoch from cmd.created_at)) or stamp<extract(epoch from now())-300 or stamp>extract(epoch from now())+5 then raise exception 'AGENT_FRESH_MFA_REQUIRED';end if;
 insert into private.coco_agent_approvals(command_id,actor_id,digest,session_id,mfa_timestamp,expires_at)
  values(cmd.id,uid,cmd.digest,sid,stamp,cmd.expires_at) returning * into approval;
 insert into private.coco_agent_events(actor_id,command_id,event,detail) values(uid,cmd.id,'human_approved',jsonb_build_object('receipt',approval.receipt,'digest',cmd.digest));
 return jsonb_build_object('receipt',approval.receipt,'expires_at',approval.expires_at);
end $$;
notify pgrst,'reload schema';

commit;
