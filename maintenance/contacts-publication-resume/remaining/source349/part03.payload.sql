

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