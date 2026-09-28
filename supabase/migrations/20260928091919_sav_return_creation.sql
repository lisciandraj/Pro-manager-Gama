-- A SAV return is created and linked in one transaction. Existing return rules
-- still own quantity limits, prices, invoice validation and stock movements.
alter table public.return_orders add column service_ticket_id uuid references public.service_tickets(id);
create unique index return_orders_service_ticket on public.return_orders(service_ticket_id) where service_ticket_id is not null;

create function private.gama_service_return(p_action text,p_ticket_id uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ticket public.service_tickets; shipment public.sales_deliveries; result jsonb; rights jsonb;
begin
 if auth.uid() is null or not private.service_access('sav') or not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) or not private.erp_action_allowed('returns','create') or not private.erp_action_allowed('sav','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 rights:=private.gama_returns_rights();
 if not coalesce((rights->>'create')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 -- Same lock order as return creation, before locking the ticket. Serializes
 -- double clicks, separate tabs, and simultaneous return creation.
 if p_action='create' then perform pg_advisory_xact_lock(884412);end if;
 select * into ticket from public.service_tickets where id=p_ticket_id for update;
 if not found then raise exception 'SERVICE_NOT_FOUND';end if;
 if p_action not in ('context','source_lines','create') then raise exception 'INVALID_ACTION';end if;
 if ticket.return_id is not null then
  return (select jsonb_build_object('id',r.id,'number',r.number,'existing',true) from public.return_orders r where r.id=ticket.return_id);
 end if;
 if ticket.archived or ticket.status='closed' then raise exception 'SERVICE_CLOSED';end if;
 if ticket.customer_id is null then raise exception 'SERVICE_CUSTOMER_REQUIRED';end if;
 if p_action='context' then
  return jsonb_build_object('ticket_id',ticket.id,'version',ticket.version,'number',ticket.erp_reference,'subject',ticket.subject,'category',ticket.category,'rows',
   coalesce((select jsonb_agg(jsonb_build_object('id',sd.id,'number',sd.number,'order_number',o.number,'partner',o.customer_name) order by sd.dispatched_at desc,sd.id)
    from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
    where o.customer_id=ticket.customer_id
     and (ticket.sales_order_id is null or sd.order_id=ticket.sales_order_id)
     and (ticket.delivery_id is null or sd.tms_delivery_id=ticket.delivery_id)
     and exists(select 1 from public.sales_delivery_lines dl where dl.delivery_id=sd.id and dl.quantity>coalesce((select sum(rl.quantity) from public.return_lines rl join public.return_orders ro on ro.id=rl.return_id where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0))),'[]'::jsonb));
 end if;
 select sd.* into shipment from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
  where sd.id=nullif(p_data->>'source_id','')::uuid and o.customer_id=ticket.customer_id
   and (ticket.sales_order_id is null or sd.order_id=ticket.sales_order_id)
   and (ticket.delivery_id is null or sd.tms_delivery_id=ticket.delivery_id);
 if not found then raise exception 'SERVICE_SOURCE_MISMATCH';end if;
 if p_action='source_lines' then return private.gama_returns_action('source_lines',jsonb_build_object('kind','customer','source_id',shipment.id));end if;
 if ticket.version is distinct from (p_data->>'version')::integer then raise exception 'SERVICE_CONFLICT';end if;
 result:=private.gama_returns_action('create',(p_data-'version')||jsonb_build_object('kind','customer','source_id',shipment.id));
 update public.return_orders set service_ticket_id=ticket.id where id=(result->>'id')::uuid;
 update public.service_tickets set return_id=(result->>'id')::uuid where id=ticket.id;
 return result||jsonb_build_object('ticket_id',ticket.id);
end $$;
revoke all on function private.gama_service_return(text,uuid,jsonb) from public,anon;
grant execute on function private.gama_service_return(text,uuid,jsonb) to authenticated;
create function public.gama_service_return(p_action text,p_ticket_id uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.gama_service_return(p_action,p_ticket_id,p_data)$$;
revoke all on function public.gama_service_return(text,uuid,jsonb) from public,anon;
grant execute on function public.gama_service_return(text,uuid,jsonb) to authenticated;
