-- Shared provider admission control. Technical usage contains no prompt,
-- answer, file bytes, bearer token or provider API key.
set local lock_timeout='3s';
set local statement_timeout='60s';
create table private.ai_provider_policy(
 id boolean primary key default true check(id),
 enabled boolean not null default true,
 daily_calls integer not null default 100 check(daily_calls between 1 and 10000),
 daily_budget_microusd bigint not null default 10000000 check(daily_budget_microusd between 1 and 100000000000),
 per_call_floor_microusd bigint not null default 250000 check(per_call_floor_microusd between 1 and 1000000000),
 max_concurrent integer not null default 3 check(max_concurrent between 1 and 20),
 max_input_tokens integer not null default 512000 check(max_input_tokens between 1000 and 2000000),
 max_output_tokens integer not null default 9000 check(max_output_tokens between 100 and 32000),
 lease_seconds integer not null default 120 check(lease_seconds between 90 and 600)
);
insert into private.ai_provider_policy(id) values(true);
create table private.ai_provider_models(
 model text primary key check(model ~ '^gpt-[a-z0-9.-]{1,70}$'),
 input_microusd_per_token numeric not null check(input_microusd_per_token>0 and input_microusd_per_token<=10000),
 output_microusd_per_token numeric not null check(output_microusd_per_token>0 and output_microusd_per_token<=10000),
 enabled boolean not null default true
);
-- Conservative price ceilings, not a claim about a provider tariff. Operators
-- must review them and add a model explicitly before selecting a new model.
insert into private.ai_provider_models(model,input_microusd_per_token,output_microusd_per_token)
 values('gpt-4.1-mini',1,4);
create table private.ai_provider_usage(
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references public.profiles(id) on delete set null,
 request_id uuid not null,
 operation text not null check(operation in('analysis','stock','ocr')),
 model text not null,
 state text not null default 'reserved' check(state in('reserved','complete','failed','expired')),
 reserved_input_tokens integer not null,
 reserved_output_tokens integer not null,
 input_microusd_per_token numeric not null,
 output_microusd_per_token numeric not null,
 reserved_microusd bigint not null,
 charged_microusd bigint not null,
 input_tokens integer,
 output_tokens integer,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null,
 completed_at timestamptz
);
create index ai_provider_usage_created on private.ai_provider_usage(created_at);
create index ai_provider_usage_active on private.ai_provider_usage(expires_at) where state='reserved';
create index ai_provider_usage_actor on private.ai_provider_usage(actor_id,created_at);
alter table private.ai_provider_policy enable row level security;
alter table private.ai_provider_models enable row level security;
alter table private.ai_provider_usage enable row level security;
revoke all on private.ai_provider_policy,private.ai_provider_models,private.ai_provider_usage from public,anon,authenticated,service_role;

create function private.coco_ai_provider_budget(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare
 policy private.ai_provider_policy;
 pricing private.ai_provider_models;
 usage private.ai_provider_usage;
 actor uuid;
 key uuid;
 req uuid;
 operation text;
 model text;
 inp integer;
 outp integer;
 cost bigint;
 total bigint;
 calls integer;
 instant timestamptz:=clock_timestamp();
 day_start timestamptz:=(date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC');
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>2000 then raise exception 'AI_BUDGET_INVALID_REQUEST';end if;
 -- A single fixed transaction lock makes quota admission atomic across all
 -- callers and model rounds, not only per administrator or per Edge instance.
 perform pg_advisory_xact_lock(hashtextextended('coco-ai-provider-global-budget',0));
 select * into policy from private.ai_provider_policy where id for update;
 if not found then raise exception 'AI_BUDGET_CONFIGURATION_REQUIRED';end if;
 update private.ai_provider_usage set state='expired',completed_at=instant where state='reserved' and expires_at<=instant;
 -- Expired and failed calls remain charged: a timeout can follow a billed call.
 if p_action='reserve' then
  if not policy.enabled then raise exception 'AI_BUDGET_DISABLED';end if;
  actor:=(p_data->>'actor_id')::uuid;req:=(p_data->>'request_id')::uuid;
  operation:=p_data->>'operation';model:=p_data->>'model';
  inp:=(p_data->>'input_tokens')::integer;outp:=(p_data->>'output_tokens')::integer;
  if actor is null or req is null or operation is null or operation not in('analysis','stock','ocr')
   or inp is null or outp is null or inp<1 or inp>policy.max_input_tokens or outp<1 or outp>policy.max_output_tokens then raise exception 'AI_BUDGET_INVALID_REQUEST';end if;
  if not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=actor and p.active and p.deleted_at is null and (u.banned_until is null or u.banned_until<=instant)) then raise exception 'AI_BUDGET_ACTOR_INACTIVE';end if;
  select * into pricing from private.ai_provider_models p where p.model=model and enabled;
  if not found then raise exception 'AI_MODEL_NOT_BUDGETED';end if;
  cost:=greatest(policy.per_call_floor_microusd,ceil(inp*pricing.input_microusd_per_token+outp*pricing.output_microusd_per_token)::bigint);
  select count(*),coalesce(sum(charged_microusd),0) into calls,total from private.ai_provider_usage where created_at>=day_start;
  if calls>=policy.daily_calls or total+cost>policy.daily_budget_microusd then raise exception 'AI_BUDGET_DAILY_LIMIT';end if;
  if (select count(*) from private.ai_provider_usage where state='reserved')>=policy.max_concurrent then raise exception 'AI_BUDGET_CONCURRENCY_LIMIT';end if;
  insert into private.ai_provider_usage(actor_id,request_id,operation,model,reserved_input_tokens,reserved_output_tokens,input_microusd_per_token,output_microusd_per_token,reserved_microusd,charged_microusd,expires_at)
   values(actor,req,operation,model,inp,outp,pricing.input_microusd_per_token,pricing.output_microusd_per_token,cost,cost,instant+make_interval(secs=>policy.lease_seconds)) returning * into usage;
  return jsonb_build_object('id',usage.id,'expires_at',usage.expires_at);
 elsif p_action='finish' then
  key:=(p_data->>'id')::uuid;
  select * into usage from private.ai_provider_usage where id=key for update;
  if not found then raise exception 'AI_BUDGET_RESERVATION_NOT_FOUND';end if;
  if usage.state in('complete','failed') then return jsonb_build_object('finished',true);end if;
  inp:=(p_data->>'input_tokens')::integer;outp:=(p_data->>'output_tokens')::integer;
  if inp is not null and (inp<0 or inp>10000000) or outp is not null and (outp<0 or outp>1000000) then raise exception 'AI_BUDGET_INVALID_USAGE';end if;
  cost:=case when inp is not null and outp is not null then ceil(inp*usage.input_microusd_per_token+outp*usage.output_microusd_per_token)::bigint else usage.reserved_microusd end;
  update private.ai_provider_usage set state=case when p_data->>'success'='true' then 'complete' else 'failed' end,
   completed_at=instant,input_tokens=inp,output_tokens=outp,charged_microusd=greatest(reserved_microusd,cost) where id=key;
  return jsonb_build_object('finished',true);
 end if;
 raise exception 'AI_BUDGET_INVALID_ACTION';
end $$;
revoke all on function private.coco_ai_provider_budget(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_ai_provider_budget(text,jsonb) to service_role;
create function public.coco_ai_provider_budget(p_action text,p_data jsonb default '{}') returns jsonb
 language sql security invoker set search_path='' as $$select private.coco_ai_provider_budget(p_action,p_data)$$;
revoke all on function public.coco_ai_provider_budget(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_ai_provider_budget(text,jsonb) to service_role;

-- Bounded retention of technical counters; no business document is removed.
create function private.coco_ai_provider_usage_purge() returns integer
language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
 delete from private.ai_provider_usage where id in(select id from private.ai_provider_usage where created_at<now()-interval '90 days' and state<>'reserved' order by created_at limit 10000);
 get diagnostics removed=row_count;return removed;
end $$;
revoke all on function private.coco_ai_provider_usage_purge() from public,anon,authenticated,service_role;
do $$begin
 if exists(select 1 from pg_namespace where nspname='cron') then
  perform cron.schedule('coco-ai-provider-usage-purge','17 3 * * *','select private.coco_ai_provider_usage_purge()');
 end if;
end $$;
notify pgrst,'reload schema';
