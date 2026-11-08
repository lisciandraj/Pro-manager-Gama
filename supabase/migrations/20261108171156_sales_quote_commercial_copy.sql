-- A copied sale gets its own commercial components. Reward claims and approved
-- expense sources are intentionally requalified rather than consumed twice.
begin;
create table private.sales_quote_copy_sources(
 quote_id uuid primary key references public.invoices(id),source_quote_id uuid references public.invoices(id),source_order_id uuid references public.sales_orders(id),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),check((source_quote_id is null)<>(source_order_id is null)));
alter table private.sales_quote_copy_sources enable row level security;
revoke all on private.sales_quote_copy_sources from public,anon,authenticated,service_role;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('sales_quote_copy_sources','quotes','Origen del presupuesto copiado','private','quote_id');
create trigger coco_module_history after insert or update or delete on private.sales_quote_copy_sources for each row execute function private.coco_capture_module_event();

alter function private.gama_quote_action(text,jsonb) rename to gama_quote_action_before_commercial_copy;
revoke all on function private.gama_quote_action_before_commercial_copy(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_quote_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;source_quote uuid:=nullif(p_data->>'commercial_copy_from','')::uuid;source_order uuid:=nullif(p_data->>'commercial_copy_order','')::uuid;
 target uuid;existing boolean;policy private.sales_quote_discount_policies;freight record;rule private.sales_freight_rules;fee jsonb;amount numeric;revision integer;begin
 if p_action<>'save' or nullif(p_data->>'id','') is not null or (source_quote is null and source_order is null) then return private.gama_quote_action_before_commercial_copy(p_action,p_data);end if;
 if source_quote is not null and source_order is not null then raise exception 'INVALID_COPY_SOURCE';end if;
 perform private.coco_sales_commercial_require(source_quote,source_order,false);
 perform private.coco_sales_commercial_require(null,null,false);
 if not private.erp_action_allowed('quotes','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 if source_quote is not null then perform 1 from public.invoices where id=source_quote for share;
 else perform 1 from public.sales_orders where id=source_order for share;end if;
 select exists(select 1 from public.invoices where quote_request_key=nullif(p_data->>'request_key','')::uuid) into existing;
 -- The established quote receipt validates both actor and the entire payload.
 result:=private.gama_quote_action_before_commercial_copy(p_action,p_data);target:=(result->>'id')::uuid;
 if existing then return result;end if;
 insert into private.sales_quote_copy_sources(quote_id,source_quote_id,source_order_id,created_by) values(target,source_quote,source_order,auth.uid());
 if source_order is not null then select source_quote_id into source_quote from public.sales_orders where id=source_order;end if;
 for freight in
  select l.source_id rule_id,l.metadata from private.sales_quote_commercial_lines l where source_order is null and l.quote_id=source_quote and l.kind='freight'
  union all select nullif(l.commercial_metadata->>'rule_id','')::uuid,l.commercial_metadata from public.sales_order_lines l
   where l.order_id=source_order and l.line_kind='freight' loop
  select * into rule from private.sales_freight_rules where id=freight.rule_id and active;
  if not found then raise exception 'FREIGHT_RULE_NOT_FOUND';end if;
  fee:=private.coco_sales_freight_amount(rule.id,target,null,coalesce((freight.metadata->>'distance_km')::numeric,0));
  insert into private.sales_quote_commercial_lines(quote_id,kind,source_id,description,quantity,unit_price,tax_rate,tax_ids,metadata,updated_by)
   values(target,'freight',rule.id,rule.name,1,(fee->>'amount')::numeric,rule.tax_rate,rule.tax_ids,fee,auth.uid());
 end loop;
 select * into policy from private.sales_quote_discount_policies where quote_id=source_quote;
 if found then
  insert into private.sales_quote_discount_policies(quote_id,mode,amount,description,updated_by) values(target,policy.mode,policy.amount,policy.description,auth.uid()) returning * into policy;
  select case when policy.mode='percent' then round(sum(line_total)*policy.amount/100,2) else policy.amount end into amount from public.invoice_lines where invoice_id=target;
  result:=result||private.coco_sales_adjustment_apply(target,'discount',amount,policy.description,policy.source_id);
 else perform private.coco_sales_quote_retotal(target);update public.invoices set quote_revision=quote_revision+1,updated_at=now() where id=target;end if;
 select quote_revision into revision from public.invoices where id=target;
 result:=result||jsonb_build_object('revision',revision,'commercial_lines',private.coco_sales_quote_commercial_lines(target),
  'tax_calculation',(select tax_calculation from public.invoices where id=target),'commercial_copied',true);
 update private.sales_quote_command_receipts set response=result where request_key=(p_data->>'request_key')::uuid and actor_id=auth.uid();
 return result;
end $$;
revoke all on function private.gama_quote_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_quote_action(text,jsonb) to authenticated;
do $$begin
 execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
  'FUNCTION private.coco_history_record_visible(','FUNCTION private.coco_history_record_visible_before_commercial_copy(');
end $$;
revoke all on function private.coco_history_record_visible_before_commercial_copy(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_commercial_copy(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_quote_copy_sources' then return private.coco_module_allowed('quotes');end if;
 return private.coco_history_record_visible_before_commercial_copy(p_table,p_id,p_owner);
end $$;
commit;
