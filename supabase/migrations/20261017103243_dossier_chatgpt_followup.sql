-- ChatGPT reads mail through its own connector. The ERP stores proposals, never
-- mailbox credentials. Existing notes, mail archives and business events survive.
alter table private.coco_order_entries drop constraint coco_order_entries_kind_check;
alter table private.coco_order_entries add constraint coco_order_entries_kind_check check(kind in ('sales','purchase','quote','tms'));
alter table private.coco_order_entries alter column order_id drop not null;
delete from private.coco_mail_oauth;
delete from private.coco_mail_accounts;
revoke all on function public.coco_order_mail_service(text,jsonb),private.coco_order_mail_service(text,jsonb) from public,anon,authenticated,service_role;

create table private.coco_mail_bridge_accounts(
 user_id uuid primary key references public.profiles(id),email text not null,
 enabled boolean not null default false,connected_at timestamptz not null default now(),last_received_at timestamptz,
 check(email=lower(btrim(email)))
);
create table private.coco_mail_proposals(
 id uuid primary key default gen_random_uuid(),mailbox_user uuid not null references public.profiles(id),
 message_id text not null,thread_id text,source_email text not null,source_subject text not null,
 received_at timestamptz not null,kind text not null check(kind in ('sales','purchase','tms')),
 target_kind text not null check(target_kind in ('sales','purchase','quote','tms')),target_id uuid,
 action text not null check(action in ('quote_draft','record_note')),summary text not null,payload jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),decided_at timestamptz,decided_by uuid references public.profiles(id),
 result jsonb,review jsonb,reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,review_hash text,
 entry_id uuid references private.coco_order_entries(id),unique(mailbox_user,message_id),
 check(length(message_id) between 1 and 300 and length(summary) between 1 and 10000 and octet_length(payload::text)<=60000)
);
create index coco_mail_proposals_pending on private.coco_mail_proposals(kind,status,created_at desc);
create index coco_mail_proposals_target on private.coco_mail_proposals(target_kind,target_id,created_at desc);
alter table private.coco_mail_bridge_accounts enable row level security;
alter table private.coco_mail_proposals enable row level security;
revoke all on private.coco_mail_bridge_accounts,private.coco_mail_proposals from public,anon,authenticated;

create function private.coco_dossier_context(p_kind text,p_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare mod text;doc jsonb;commercial boolean;can_edit boolean;me text;oid uuid;qid uuid;model jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_kind not in ('sales','purchase','quote','tms') or p_kind is null then raise exception 'INVALID_ORDER_KIND';end if;
 mod:=case p_kind when 'sales' then 'sales-orders' when 'quote' then 'quotes' when 'purchase' then 'gamaPurchasesV14' else 'tms' end;
 if p_kind='tms' then
  perform private.tms_require(p_id,false,'read');
  if p_id is null and private.tms_scope()='driver' then raise exception 'TMS_ACCESS_DENIED';end if;
  commercial:=private.tms_scope() in ('dispatcher','manager');
 else
  if not private.erp_module_allowed(mod,array['administrador','comercial','almacenero']) and not
   (p_id is null and p_kind='sales' and private.erp_module_allowed('quotes',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
  commercial:=private.erp_module_allowed(mod,array['administrador','comercial']) or p_id is null and p_kind='sales' and private.erp_module_allowed('quotes',array['administrador','comercial']);
 end if;
 can_edit:=private.erp_action_allowed(mod,'edit');
 if p_id is null then doc:=jsonb_build_object('number',case p_kind when 'sales' then 'Ventas' when 'quote' then 'Ventas' when 'purchase' then 'Compras' else 'TMS' end,'status','inbox','party','ChatGPT');
 elsif p_kind='sales' then
  select jsonb_build_object('number',number,'status',status,'party',customer_name),id,source_quote_id into doc,oid,qid from public.sales_orders where id=p_id;
 elsif p_kind='quote' then
  select jsonb_build_object('number',q.invoice_number,'status',coalesce(q.quote_state,'draft'),'party',c.name),q.id into doc,qid from public.invoices q left join public.customers c on c.id=q.customer_id where q.id=p_id;
  select id into oid from public.sales_orders where source_quote_id=qid;
 elsif p_kind='purchase' then
  select jsonb_build_object('number',o.order_number,'status',o.status,'party',s.name) into doc from public.purchase_orders o left join public.suppliers s on s.id=o.supplier_id where o.id=p_id;
 else
  select jsonb_build_object('number',coalesce(d.erp_reference,s.number),'status',d.status,'party',d.customer),s.order_id,o.source_quote_id into doc,oid,qid
   from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id left join public.sales_orders o on o.id=s.order_id where d.id=p_id;
 end if;
 if doc is null then raise exception 'ORDER_NOT_FOUND';end if;
 if p_id is not null then
  if p_kind='purchase' then model:=private.gama_process_state('p:'||p_id);
  elsif oid is not null then model:=private.gama_process_state('o:'||oid);
  elsif qid is not null then model:=private.gama_process_state('q:'||qid);end if;
 end if;
 select email into me from auth.users where id=auth.uid();
 return doc||jsonb_build_object('kind',p_kind,'id',p_id,'actor_id',auth.uid(),'account_email',me,'can_note',can_edit,'commercial',commercial,
  'can_review',commercial and (can_edit or p_id is null and p_kind='sales' and private.erp_action_allowed('quotes','edit')) and (p_kind<>'tms' or private.tms_scope() in ('dispatcher','manager')),
  'sales_order_id',oid,'quote_id',qid,'stages',coalesce(model->'steps','[]'),
  'bridge',(select jsonb_build_object('enabled',a.enabled and lower(me)=a.email,'email',a.email,'last_received_at',a.last_received_at) from private.coco_mail_bridge_accounts a where a.user_id=auth.uid()));
end $$;
revoke all on function private.coco_dossier_context(text,uuid) from public,anon,authenticated;

-- Keep the established financial-stage redaction and add actor identifiers for
-- the scoped portrait projection. Quote views follow their eventual order.
do $$declare source text;begin
 source:=pg_get_functiondef('private.gama_process_history(text,integer,integer)'::regprocedure);
 source:=replace(source,'private.gama_process_history(', 'private.coco_dossier_process_history(');
 source:=replace(source,'model:=private.gama_processes(''state'',jsonb_build_object(''key'',p_key));',
  'perform private.coco_dossier_context(case k when ''o'' then ''sales'' when ''q'' then ''quote'' when ''p'' then ''purchase'' else ''invalid'' end,source); model:=private.gama_process_state(p_key);');
 source:=replace(source,'elsif k=''q'' then qid:=source;', 'elsif k=''q'' then qid:=source; select id,source_request_id into oid,rid from public.sales_orders where source_quote_id=qid; if rid is null then select id into rid from public.customer_requests where invoice_id=qid order by created_at,id limit 1;end if;');
 source:=replace(source,'''actor_name'',actor_name,', '''actor_name'',actor_name,''actor_id'',actor_id,');
 execute source;
end $$;
revoke all on function private.coco_dossier_process_history(text,integer,integer) from public,anon,authenticated;

create function private.coco_proposal_quote(p jsonb,p_key uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c public.customers;product public.products;line jsonb;ls jsonb:='[]';price jsonb;qty numeric;stamp date:=(now() at time zone private.erp_timezone())::date;seller text;
begin
 perform private.sales_access('quote');
 if not private.erp_action_allowed('quotes','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=nullif(p->>'customer_id','')::uuid and active;
 if c.id is null then raise exception 'CUSTOMER_REQUIRED';end if;
 if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines') not between 1 and 200 then raise exception 'INVALID_LINES';end if;
 for line in select value from jsonb_array_elements(p->'lines') loop
  select * into product from public.products where id=nullif(line->>'product_id','')::uuid and active;
  qty:=(line->>'quantity')::numeric;
  if product.id is null then raise exception 'PRODUCT_NOT_FOUND';end if;
  if qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_LINES';end if;
  price:=private.erp_price(c.id,product.id,qty,stamp);
  if nullif(price->>'unit_price','') is null then raise exception 'INVALID_LINES';end if;
  ls:=ls||jsonb_build_array(jsonb_build_object('product_id',product.id,'description',product.name,'quantity',qty,'list_price',(price->>'unit_price')::numeric,'discount',0,'tax_rate',coalesce(product.tax_rate,0),'price_mode','automatic'));
 end loop;
 select coalesce(nullif(full_name,''),'Coco ERP') into seller from public.profiles where id=auth.uid();
 return jsonb_build_object('request_key',p_key,'customer_id',c.id,'issue_date',stamp,'valid_until',stamp+30,'lines',ls,
  'details',jsonb_build_object('client',c.name,'clientEmail',c.email,'seller',seller,'delivery_address',coalesce(nullif(btrim(coalesce(p->>'delivery_address',p->'details'->>'delivery_address')),''),nullif(btrim(c.address),''),'')));
end $$;
revoke all on function private.coco_proposal_quote(jsonb,uuid) from public,anon,authenticated;

create function private.coco_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'kind';oid uuid:=nullif(p_data->>'order_id','')::uuid;ctx jsonb;off integer:=coalesce((p_data->>'offset')::integer,0);
 entries jsonb;hist jsonb:='[]';portraits jsonb;proposals jsonb;author text;entry private.coco_order_entries;prop private.coco_mail_proposals;v_review jsonb;v_result jsonb;key uuid;ids uuid[];qids uuid[];tids uuid[];
begin
 ctx:=private.coco_dossier_context(k,oid);
 if p_action='context' then return ctx;end if;
 if p_action='list' then
  if off not between 0 and 1000000 then raise exception 'INVALID_OFFSET';end if;
  ids:=array[]::uuid[];qids:=array[]::uuid[];tids:=array[]::uuid[];
  if oid is not null then
   if k in ('sales','quote') then
    if private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then ids:=array[nullif(ctx->>'sales_order_id','')::uuid];end if;
    if private.erp_module_allowed('quotes',array['administrador','comercial']) then qids:=array[nullif(ctx->>'quote_id','')::uuid];end if;
    if private.erp_module_allowed('tms',array['administrador','comercial','almacenero']) then select array_agg(s.tms_delivery_id) into tids from public.sales_deliveries s where s.order_id=any(ids);end if;
    hist:=private.coco_dossier_process_history((case when k='sales' then 'o:' else 'q:' end)||oid,0,off)->'items';
   elsif k='purchase' then hist:=private.coco_dossier_process_history('p:'||oid,0,off)->'items';
   elsif k='tms' then
    tids:=array[oid];ids:=array[]::uuid[];
    if private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) and ctx->>'sales_order_id' is not null then
     ids:=array[(ctx->>'sales_order_id')::uuid];
     if private.erp_module_allowed('quotes',array['administrador','comercial']) then qids:=array[(ctx->>'quote_id')::uuid];end if;
     hist:=private.coco_dossier_process_history('o:'||(ctx->>'sales_order_id'),0,off)->'items';
    else
     select coalesce(jsonb_agg(e),'[]') into hist from (
      select 'delivery:'||e.id id,e.at,e.user_id actor_id,coalesce(p.full_name,'AUTHOR_NOT_RECORDED') actor_name,'delivery_'||e.type action,e.note body,5 step,count(*) over() total
      from public.tms_events e left join public.profiles p on p.id=e.user_id where e.delivery_id=oid order by e.at desc,e.id offset off limit 50
     ) e;
    end if;
   end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x)-'created_at_sort' order by x.created_at_sort desc,x.id),'[]') into entries from (
   select e.id,e.kind,e.order_id,e.type,e.actor_id,e.actor_name,e.created_at,e.created_at created_at_sort,e.subject,e.body,e.status,e.from_email,e.to_email,e.attachments,e.detail->>'proposal_id' proposal_id,e.detail->>'source_email' source_email,e.detail->>'source_subject' source_subject
   from private.coco_order_entries e where
    ((oid is null and e.order_id is null and e.kind=case when k='quote' then 'sales' else k end) or
     (oid is not null and ((e.kind=k and e.order_id=oid) or (e.kind='sales' and e.order_id=any(ids)) or (e.kind='quote' and e.order_id=any(qids)) or (e.kind='tms' and e.order_id=any(tids)))))
    and (e.type<>'mail' or (ctx->>'commercial')::boolean) and (e.detail->>'proposal_id' is null or (ctx->>'can_review')::boolean)
   order by e.created_at desc,e.id offset off limit 51
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'kind',p.kind,'target_kind',p.target_kind,'target_id',p.target_id,'status',p.status,'action',p.action,'summary',p.summary,'payload',p.payload,'result',p.result,'source_email',p.source_email,'source_subject',p.source_subject,'message_id',p.message_id,'received_at',p.received_at)),'[]') into proposals
   from private.coco_mail_proposals p where (ctx->>'can_review')::boolean and p.entry_id in(select (v->>'id')::uuid from jsonb_array_elements(entries) v);
  select coalesce(jsonb_object_agg(h.profile_id::text,h.photo_data),'{}') into portraits from public.hr_employees h where h.active and h.photo_data is not null and length(h.photo_data)<=120000 and h.profile_id in
   (select nullif(v->>'actor_id','')::uuid from jsonb_array_elements(entries||coalesce(hist,'[]')) v);
  return jsonb_build_object('context',ctx,'entries',entries,'history',coalesce(hist,'[]'),'portraits',portraits,'proposals',proposals);
 end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 if p_action='note' then
  if not (ctx->>'can_note')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  if length(btrim(coalesce(p_data->>'body',''))) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,body,request_key)
   values(k,oid,'note',auth.uid(),author,btrim(p_data->>'body'),key) on conflict(actor_id,request_key) do nothing returning * into entry;
  if entry.id is null then select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;end if;
  if entry.kind<>k or entry.order_id is distinct from oid or entry.body<>btrim(p_data->>'body') or entry.type<>'note' then raise exception 'REQUEST_KEY_REUSED';end if;
  return jsonb_build_object('id',entry.id);
 elsif p_action in ('review_proposal','approve_proposal','reject_proposal') then
  if not (ctx->>'can_review')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into prop from private.coco_mail_proposals where id=(p_data->>'proposal_id')::uuid for update;
  if prop.id is null or prop.kind<>(case when k='quote' then 'sales' else k end) or prop.target_id is distinct from oid or (oid is not null and prop.target_kind<>k) then raise exception 'PROPOSAL_NOT_FOUND';end if;
  if not exists(select 1 from private.coco_mail_bridge_accounts a join auth.users u on u.id=a.user_id join public.profiles p on p.id=u.id where a.user_id=prop.mailbox_user and p.active and a.email=lower(u.email)) then raise exception 'BRIDGE_DISABLED';end if;
  if prop.status<>'pending' then
   if p_action='approve_proposal' and prop.status='approved' then return prop.result;end if;
   if p_action='reject_proposal' and prop.status='rejected' then return jsonb_build_object('status','rejected');end if;
   raise exception 'PROPOSAL_DECIDED';
  end if;
  if p_action='review_proposal' then
   if prop.action='quote_draft' then v_review:=private.coco_proposal_quote(coalesce(p_data->'payload',prop.payload),prop.id);
   else v_review:=jsonb_build_object('body',prop.summary,'kind',prop.target_kind,'order_id',prop.target_id);end if;
   update private.coco_mail_proposals set review=v_review,reviewed_by=auth.uid(),reviewed_at=now(),review_hash=md5(v_review::text) where id=prop.id;
   return jsonb_build_object('review',v_review,'hash',md5(v_review::text),'action',prop.action);
  elsif p_action='approve_proposal' then
   if prop.reviewed_by is distinct from auth.uid() or prop.reviewed_at<now()-interval '10 minutes' or prop.review_hash is distinct from p_data->>'hash' then raise exception 'PROPOSAL_CHANGED';end if;
   if prop.action='quote_draft' then
    v_review:=private.coco_proposal_quote(prop.review,prop.id);
    if md5(v_review::text)<>prop.review_hash then raise exception 'PROPOSAL_CHANGED';end if;
    v_result:=private.gama_quote_action('save',v_review)||jsonb_build_object('kind','quote');
    insert into private.coco_order_entries(kind,order_id,type,actor_name,subject,body,detail)
     values('quote',(v_result->>'id')::uuid,'note','ChatGPT','mail_analysis',prop.summary,jsonb_build_object('message_id',prop.message_id,'source_email',prop.source_email,'source_subject',prop.source_subject));
    insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body)
     values('quote',(v_result->>'id')::uuid,'note',auth.uid(),author,'proposal_approved',prop.summary);
   else v_result:=jsonb_build_object('status','approved','kind',prop.target_kind,'id',prop.target_id);end if;
  else v_result:=jsonb_build_object('status','rejected');end if;
  update private.coco_mail_proposals set status=case when p_action='reject_proposal' then 'rejected' else 'approved' end,decided_at=now(),decided_by=auth.uid(),result=v_result where id=prop.id;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,detail)
   values(case when k='quote' and oid is null then 'sales' else k end,oid,'note',auth.uid(),author,case when p_action='reject_proposal' then 'proposal_rejected' else 'proposal_approved' end,prop.summary,jsonb_build_object('proposal_id',prop.id));
  return v_result;
 elsif p_action='bridge_disable' then
  update private.coco_mail_bridge_accounts set enabled=false where user_id=auth.uid();return jsonb_build_object('enabled',false);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_dossier(text,jsonb) from public,anon;
grant execute on function private.coco_dossier(text,jsonb) to authenticated;
create function public.coco_dossier(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_dossier(p_action,p_data)$$;
revoke all on function public.coco_dossier(text,jsonb) from public,anon;
grant execute on function public.coco_dossier(text,jsonb) to authenticated;

-- This narrow service entry accepts connector-verified mail facts and creates
-- only pending proposals. It never executes an ERP business action or sets JWTs.
create function private.coco_mail_bridge(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid;mailbox text:=lower(btrim(p_data->>'mailbox_email'));sender text:=lower(btrim(p_data->>'source_email'));prop private.coco_mail_proposals;new_entry uuid;payload jsonb;target uuid;kind text;target_kind text;matches jsonb;
begin
 select u.id into uid from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=mailbox and p.active and p.role in ('administrador','comercial') and (u.banned_until is null or u.banned_until<now());
 if uid is null then raise exception 'MAILBOX_ACCOUNT_NOT_FOUND';end if;
 if p_action='enable' then
  insert into private.coco_mail_bridge_accounts(user_id,email,enabled) values(uid,mailbox,true) on conflict(user_id) do update set enabled=true,email=excluded.email;
  return jsonb_build_object('enabled',true,'email',mailbox);
 end if;
 if not exists(select 1 from private.coco_mail_bridge_accounts where user_id=uid and enabled and coco_mail_bridge_accounts.email=mailbox) then raise exception 'BRIDGE_DISABLED';end if;
 if p_action='context' then
  select coalesce(jsonb_agg(jsonb_build_object('kind','customer','id',id,'name',name,'address',address)),'[]') into matches from public.customers where active and lower(btrim(customers.email))=sender;
  select matches||coalesce(jsonb_agg(jsonb_build_object('kind','supplier','id',id,'name',name)),'[]') into matches from public.suppliers where active and lower(btrim(suppliers.email))=sender;
  return jsonb_build_object('contacts',matches,'products',(select coalesce(jsonb_agg(x),'[]') from (select id,name,reference,base_unit from public.products where active and length(coalesce(p_data->>'search',''))>=2 and (name ilike '%'||(p_data->>'search')||'%' or reference ilike '%'||(p_data->>'search')||'%') order by name,id limit 25) x),'existing',(select jsonb_build_object('id',id,'status',status) from private.coco_mail_proposals where mailbox_user=uid and message_id=p_data->>'message_id'));
 elsif p_action='propose' then
  if coalesce(p_data->>'message_id','')='' or sender!~'^[^\s@<>;,]+@[^\s@<>;,]+\.[^\s@<>;,]+$' or length(coalesce(p_data->>'summary','')) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  kind:=p_data->>'kind';target_kind:=coalesce(p_data->>'target_kind',kind);target:=nullif(p_data->>'target_id','')::uuid;payload:=coalesce(p_data->'payload','{}');
  if kind not in ('sales','purchase','tms') or target_kind not in ('sales','purchase','quote','tms') then raise exception 'INVALID_ORDER_KIND';end if;
  if jsonb_typeof(payload) is distinct from 'object' or (kind='sales' and target_kind not in ('sales','quote')) or (kind in ('purchase','tms') and kind<>target_kind) then raise exception 'INVALID_PROPOSAL';end if;
  if (p_data->>'action')='quote_draft' and (kind<>'sales' or target is not null) then raise exception 'INVALID_PROPOSAL';end if;
  if target is not null and not (case target_kind when 'sales' then exists(select 1 from public.sales_orders where id=target) when 'quote' then exists(select 1 from public.invoices where id=target) when 'purchase' then exists(select 1 from public.purchase_orders where id=target) when 'tms' then exists(select 1 from public.tms_deliveries where id=target) else false end) then raise exception 'ORDER_NOT_FOUND';end if;
  insert into private.coco_mail_proposals(mailbox_user,message_id,thread_id,source_email,source_subject,received_at,kind,target_kind,target_id,action,summary,payload)
   values(uid,p_data->>'message_id',p_data->>'thread_id',sender,left(coalesce(p_data->>'subject',''),300),(p_data->>'received_at')::timestamptz,kind,target_kind,target,p_data->>'action',p_data->>'summary',payload)
   on conflict(mailbox_user,message_id) do nothing returning * into prop;
  if prop.id is null then select * into prop from private.coco_mail_proposals where mailbox_user=uid and message_id=p_data->>'message_id';return jsonb_build_object('id',prop.id,'status',prop.status,'duplicate',true);end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_name,subject,body,detail)
   values(case when target is null then kind else target_kind end,target,'note','ChatGPT','mail_analysis',prop.summary,jsonb_build_object('proposal_id',prop.id)) returning id into new_entry;
  update private.coco_mail_proposals set entry_id=new_entry where id=prop.id;
  update private.coco_mail_bridge_accounts set last_received_at=now() where user_id=uid;
  return jsonb_build_object('id',prop.id,'status','pending');
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_mail_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_mail_bridge(text,jsonb) to service_role;
create function public.coco_mail_bridge(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.coco_mail_bridge(p_action,p_data)$$;
revoke all on function public.coco_mail_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_mail_bridge(text,jsonb) to service_role;

-- Capture ordinary transport edits too, including edits made outside this UI.
create function private.coco_transport_discussion_event() returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;after_row jsonb:=to_jsonb(new);changed jsonb;author text;
begin
 select jsonb_agg(key order by key) into changed from jsonb_each(after_row) where key=any(array['status','delivery_date','route_id','driver_id','address','notes','promised_from','promised_until','settled_at']) and value is distinct from before_row->key;
 if tg_op='UPDATE' and changed is null then return new;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body)
  values('tms',new.id,'action',auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),case when tg_op='INSERT' then 'delivery_created' else 'delivery_updated' end,coalesce(changed::text,''));
 return new;
end $$;
revoke all on function private.coco_transport_discussion_event() from public,anon,authenticated;
create trigger coco_transport_discussion_event after insert or update on public.tms_deliveries for each row execute function private.coco_transport_discussion_event();

alter function private.coco_order_followup(text,jsonb) rename to coco_order_followup_before_discussion;
revoke all on function private.coco_order_followup_before_discussion(text,jsonb) from public,anon,authenticated;
create function private.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action in ('context','list','note') then return private.coco_dossier(p_action,p_data);end if;
 if p_action='purchase_manual_sent' then return private.coco_order_followup_before_discussion(p_action,p_data);end if;
 raise exception 'MAIL_CONNECTOR_REMOVED';
end $$;
create or replace function public.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_order_followup(p_action,p_data)$$;
revoke all on function private.coco_order_followup(text,jsonb) from public,anon;
grant execute on function private.coco_order_followup(text,jsonb) to authenticated;
notify pgrst,'reload schema';
