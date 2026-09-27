-- Net balances must include credit notes in every consumer, without calling them cash receipts.
do $$declare s text;credit text;begin
 s:=pg_get_viewdef('private.gama_receivables'::regclass,true);
 credit:='COALESCE((select sum(k.amount) from public.return_credits k where k.invoice_id=i.id),0)';
 s:=replace(s,'i.total - COALESCE(p.paid, 0::numeric)','i.total - COALESCE(p.paid, 0::numeric) - '||credit);
 s:=replace(s,'i.total <= COALESCE(p.paid, 0::numeric)','i.total <= COALESCE(p.paid, 0::numeric) + '||credit);
 execute 'create or replace view private.gama_receivables as '||s;
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);
 -- The payables view already subtracts supplier credits in recent versions; only change missing implementations.
 if strpos(s,'return_credits')=0 then
  credit:='COALESCE((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=si.id),0)';
  s:=replace(s,'i.total - COALESCE(p.paid, 0::numeric)','i.total - COALESCE(p.paid, 0::numeric) - '||credit);
  s:=replace(s,'i.total <= COALESCE(p.paid, 0::numeric)','i.total <= COALESCE(p.paid, 0::numeric) + '||credit);
  execute 'create or replace view private.gama_payables as '||s;
 end if;
end $$;
create index if not exists process_sales_page on public.sales_orders(created_at desc,id);
create index if not exists process_purchase_page on public.purchase_orders(created_at desc,id);
create index if not exists process_followup_deadline on public.dossier_followups(due_date) where closed_at is null;
create index if not exists process_credit_invoice on public.return_credits(invoice_id);
create index if not exists process_credit_supplier_invoice on public.return_credits(supplier_invoice_id);

-- One read model supplies cards, details, closure checks and process alerts.
create function private.gama_process_state(k text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 source uuid:=split_part(k,':',2)::uuid;kind text:=split_part(k,':',1);o public.sales_orders;po public.purchase_orders;q public.invoices;r public.customer_requests;
 totalqty numeric:=0;performed numeric:=0;sent numeric:=0;missing numeric:=0;received numeric:=0;unbilled numeric:=0;balance numeric:=0;overdue numeric:=0;credits numeric:=0;paid numeric:=0;goods numeric:=0;stocked numeric:=0;
 returns_count bigint:=0;external_pending bigint:=0;invoice_count bigint:=0;fin boolean;cancelled boolean:=false;confirmed boolean:=false;complete boolean:=false;
 states text[];titles text[];steps jsonb;checks jsonb;f public.dossier_followups;fp text;closed boolean;late_receipt boolean:=false;info text[];
begin
 if kind='o' then
  select * into o from public.sales_orders where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  select * into q from public.invoices where id=o.source_quote_id;
  select * into r from public.customer_requests where id=o.source_request_id;
  fin:=private.erp_module_allowed('payments',array['administrador','comercial']);cancelled:=o.status='cancelled';confirmed:=o.status='confirmed';
  select coalesce(sum(l.quantity),0),coalesce(sum(least(l.quantity,private.gama_line_performed(l.id,true))),0),coalesce(sum(least(l.quantity,private.gama_line_performed(l.id,false))),0),
   coalesce(sum(case when l.product_kind='goods' then greatest(0,l.quantity-private.gama_line_performed(l.id,false)-coalesce((select sum(s.quantity) from public.stock_reservations s join public.sales_reservation_links x on x.reservation_id=s.id where x.line_id=l.id and s.status='active'),0)) else 0 end),0),
   coalesce(sum(greatest(0,l.quantity-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('rejected','cancelled') and (i.document_kind='internal' or i.fiscal_status='authorized')),0))),0)
   into totalqty,performed,sent,missing,unbilled from public.sales_order_lines l where l.order_id=source;
  select coalesce(sum(a.balance),0),coalesce(sum(a.balance) filter(where a.due_date<(now() at time zone private.erp_timezone())::date),0),coalesce(sum(a.paid),0),count(*)
   into balance,overdue,paid,invoice_count from private.gama_receivables a where a.order_id=source and a.payment_status<>'cancelled';
  select coalesce(sum(c.amount),0) into credits from public.return_credits c join public.external_invoices i on i.id=c.invoice_id where i.order_id=source and i.fiscal_status not in ('cancelled','rejected');
  select count(*) into returns_count from public.return_orders where order_id=source and status not in ('closed','cancelled');
  select count(*) into external_pending from public.external_invoices where order_id=source and fiscal_status not in ('cancelled','rejected') and
   (case when document_kind='internal' then external_number is null or external_status is distinct from 'authorized' else fiscal_status<>'authorized' end);
  titles:=array['Origen de la demanda','Presupuesto','Pedido','Reserva de stock y preparación','Expedición y recepción','Facturación','Seguimiento del pago','Cierre del proceso de venta'];
  complete:=confirmed and totalqty>0 and performed>=totalqty and unbilled=0 and invoice_count>0 and balance<=0.005 and returns_count=0;
  states:=array[case when r.id is not null or o.source_opportunity_id is not null then 'done' else 'skip' end,case when q.id is null then 'skip' when confirmed or q.quote_state in ('accepted','converted') then 'done' else 'active' end,
   case when confirmed then 'done' else 'active' end,case when not confirmed then 'pending' when missing>0 then 'blocked' when sent>=totalqty and totalqty>0 then 'done' else 'active' end,
   case when totalqty>0 and performed>=totalqty then 'done' when sent>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when unbilled=0 and invoice_count>0 then 'done' when invoice_count>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when overdue>0.005 then 'blocked' when unbilled=0 and invoice_count>0 and balance<=0.005 then 'done' when invoice_count>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when returns_count>0 then 'blocked' when complete then 'done' else 'pending' end];
  info:=array['','','','Sin reservar: '||missing,'Entregas firmadas / servicios ejecutados: '||performed||' / '||totalqty,'Cantidad sin facturar: '||unbilled,'Cobros: '||paid||' · Abonos: '||credits||' · Saldo: '||balance,'Devoluciones abiertas: '||returns_count];
 elsif kind='p' then
  select * into po from public.purchase_orders where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  fin:=private.erp_module_allowed('accounting',array['administrador','comercial']) and coalesce((private.gama_accounting_rights()->>'view')::boolean,false) and private.gama_accounting_rights()->>'scope'='all';cancelled:=po.status='cancelled';confirmed:=po.status in ('sent','partial','received');
  select coalesce(sum(l.quantity),0),coalesce(sum(l.received_quantity),0),coalesce(sum(l.received_quantity) filter(where p.product_kind='goods'),0),
   coalesce(sum(greatest(0,l.received_quantity-coalesce((select sum(ml.quantity) from public.supplier_invoice_match_lines ml join public.supplier_invoice_matches m on m.id=ml.match_id join public.supplier_invoices i on i.id=m.invoice_id where ml.purchase_line_id=l.id and i.status='posted' and m.approved_at is not null),0))),0)
   into totalqty,received,goods,unbilled from public.purchase_order_lines l join public.products p on p.id=l.product_id where l.purchase_order_id=source;
  select coalesce(sum(m.quantity),0) into stocked from public.stock_movements m where reference_type='purchase_order' and reference_id=source and m.destination_location_id is not null and m.source_location_id is null;
  select coalesce(sum(greatest(0,i.total-coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.supplier_invoice_id=i.id and p.status='confirmed'),0)-coalesce((select sum(c.amount) from public.return_credits c where c.supplier_invoice_id=i.id),0))),0),count(*)
   into balance,invoice_count from public.supplier_invoices i where i.status='posted' and (i.purchase_order_id=source or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=source));
  select coalesce(sum(greatest(0,i.total-coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.supplier_invoice_id=i.id and p.status='confirmed'),0)-coalesce((select sum(c.amount) from public.return_credits c where c.supplier_invoice_id=i.id),0))),0)
   into overdue from public.supplier_invoices i where i.status='posted' and i.due_date<(now() at time zone private.erp_timezone())::date and (i.purchase_order_id=source or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=source));
  select count(*) into returns_count from public.return_orders where purchase_order_id=source and status not in ('closed','cancelled');
  late_receipt:=po.expected_date<now() and received<totalqty and confirmed;
  performed:=received;complete:=confirmed and totalqty>0 and received>=totalqty and stocked>=goods and unbilled=0 and invoice_count>0 and balance<=0.005 and returns_count=0;
  titles:=array['Origen de la demanda','Pedido de compra','Recepción y control','Puesta en stock','Factura del proveedor','Seguimiento del pago','Cierre del proceso de compra'];
  states:=array['done',case when confirmed then 'done' else 'active' end,
   case when totalqty>0 and received>=totalqty then 'done' when late_receipt then 'blocked' when received>0 then 'active' else 'pending' end,
   case when goods=0 and received>0 then 'skip' when stocked>=goods and goods>0 then 'done' else 'pending' end,
   case when not fin then 'restricted' when unbilled=0 and invoice_count>0 and received>=totalqty then 'done' when unbilled>0 then 'blocked' else 'pending' end,
   case when not fin then 'restricted' when overdue>0.005 then 'blocked' when invoice_count>0 and balance<=0.005 then 'done' when invoice_count>0 then 'active' else 'pending' end,
   case when not fin then 'restricted' when returns_count>0 then 'blocked' when complete then 'done' else 'pending' end];
  info:=array['','','Recibido / aceptado: '||received||' / '||totalqty,'Mercancía ubicada: '||stocked||' / '||goods,'Recepción sin factura conciliada: '||unbilled,'Saldo neto de abonos: '||balance,'Devoluciones abiertas: '||returns_count];
 elsif kind in ('q','r') then
  if kind='q' then select * into q from public.invoices where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  else select * into r from public.customer_requests where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;select * into q from public.invoices where id=r.invoice_id;end if;
  fin:=false;cancelled:=coalesce(q.quote_state in ('cancelled','rejected'),false) or coalesce(r.status in ('cancelled','rejected'),false);
  titles:=array['Origen de la demanda','Presupuesto','Pedido','Reserva de stock y preparación','Expedición y recepción','Facturación','Seguimiento del pago','Cierre del proceso de venta'];
  states:=array[case when r.id is null then 'skip' else 'done' end,case when q.id is null then 'pending' when q.quote_state in ('accepted','converted') then 'done' when q.quote_state='sent' and q.quote_valid_until<(now() at time zone private.erp_timezone())::date then 'blocked' else 'active' end,'pending','pending','pending','pending','pending','pending'];
 else raise exception 'DOSSIER_NOT_FOUND';end if;
 checks:=jsonb_build_object('delivery_remainder',greatest(0,totalqty-performed),'unbilled_quantity',unbilled,'unpaid_amount',balance,'open_returns',returns_count,'empty_order',totalqty=0,'order_confirmed',confirmed,'stock_not_located',greatest(0,goods-stocked),'order_required',kind in ('q','r'));
 fp:=md5(checks::text||cancelled::text);select * into f from public.dossier_followups where dossier_key=k;
 closed:=coalesce(f.closed_at is not null and f.closure_fingerprint=fp,false);
 select jsonb_agg(jsonb_build_object('title',titles[i],'state',case when cancelled then 'closed' else states[i] end,'info',case when states[i]='restricted' then '' else coalesce(info[i],'') end) order by i) into steps from generate_subscripts(titles,1) i;
 if not fin then checks:=checks-'unbilled_quantity'-'unpaid_amount';complete:=false;end if;
 return jsonb_build_object('key',k,'metrics',jsonb_build_object('ordered',totalqty,'performed',performed,'shipped',sent,'missing',missing,'received',received,'goods',goods,'stocked',stocked,'unbilled',case when fin then unbilled else null end,'balance',case when fin then balance else null end,'paid',case when fin then paid else null end,'credits',case when fin then credits else null end,'open_returns',returns_count),'steps',steps,'checks',checks,'fingerprint',fp,'followup',case when f.id is null then null else to_jsonb(f) end,'operational_complete',complete,'external_complete',case when fin and kind='o' then external_pending=0 and invoice_count>0 else null end,'external_pending',case when fin then external_pending else null end,'closed',closed,'cancelled',cancelled,'reopened',coalesce(f.closed_at is not null and not closed,false),'unbilled_received',case when fin and kind='p' then unbilled else null end,'financial_access',fin);
end $$;
revoke all on function private.gama_process_state(text) from public,anon,authenticated;

create or replace function private.gama_dossier_followup(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'key';r jsonb;source uuid;kind text;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('dossier-flow',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 kind:=split_part(k,':',1);source:=split_part(k,':',2)::uuid;
 if kind='p' then
  if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  perform 1 from public.purchase_orders where id=source for update;
 elsif kind='o' then perform 1 from public.sales_orders where id=source for update;end if;
 r:=private.gama_process_state(k);
 if p_action='save' then
  if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
  insert into public.dossier_followups(dossier_key,owner_id,next_action,due_date) values(k,(p_data->>'owner_id')::uuid,p_data->>'next_action',(p_data->>'due_date')::date)
   on conflict(dossier_key) do update set owner_id=excluded.owner_id,next_action=excluded.next_action,due_date=excluded.due_date,updated_by=auth.uid(),updated_at=now();
 elsif p_action='close' then
  if r->'followup'='null'::jsonb then raise exception 'FOLLOWUP_REQUIRED';end if;
  if not coalesce((r->>'operational_complete')::boolean,false) then raise exception 'DOSSIER_INCOMPLETE';end if;
  if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'CLOSURE_NOTE_REQUIRED';end if;
  update public.dossier_followups set closed_at=now(),closed_by=auth.uid(),closure_note=p_data->>'note',closure_fingerprint=r->>'fingerprint' where dossier_key=k;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return private.gama_process_state(k)-'fingerprint';
end $$;

create function private.gama_processes(p_action text,p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;k text:=p_data->>'key';purchase boolean:=p_data->>'kind'='PDC';off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));search text:=btrim(coalesce(p_data->>'search',''));
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('dossier-flow',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if (purchase or k like 'p:%') and not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='state' then return private.gama_process_state(k)-'fingerprint';end if;
 if p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 with candidates as (
  select 'p:'||p.id key,p.created_at,(to_jsonb(p)||jsonb_build_object('dossier_number',dr.dossier_number)) o,null::jsonb q,null::jsonb r,s.name party,'PDC-'||lpad(dr.dossier_number::text,8,'0') number
   from public.purchase_orders p left join public.gama_document_references dr on dr.table_name='purchase_orders' and dr.document_id=p.id left join public.suppliers s on s.id=p.supplier_id where purchase
  union all
  select 'o:'||o.id,o.created_at,to_jsonb(o)||jsonb_build_object('dossier_number',dr.dossier_number),case when private.erp_module_allowed('quotes',array['administrador','comercial']) then to_jsonb(q)-'accepted_snapshot' end,case when private.erp_module_allowed('customer-requests',array['administrador','comercial']) then to_jsonb(r) end,o.customer_name,'PDV-'||lpad(dr.dossier_number::text,8,'0') from public.sales_orders o left join public.gama_document_references dr on dr.table_name='sales_orders' and dr.document_id=o.id
   left join public.customer_requests r on r.id=o.source_request_id left join public.invoices q on q.id=coalesce(o.source_quote_id,r.invoice_id) where not purchase
  union all
  select 'q:'||q.id,q.created_at,null,(to_jsonb(q)-'accepted_snapshot')||jsonb_build_object('dossier_number',dr.dossier_number),to_jsonb(r),q.quote_details->>'client','PDV-'||lpad(dr.dossier_number::text,8,'0') from public.invoices q left join public.gama_document_references dr on dr.table_name='invoices' and dr.document_id=q.id
   left join public.customer_requests r on r.invoice_id=q.id where not purchase and private.erp_module_allowed('quotes',array['administrador','comercial']) and not exists(select 1 from public.sales_orders o where o.source_quote_id=q.id or o.source_request_id=r.id)
  union all
  select 'r:'||r.id,r.created_at,null,null,to_jsonb(r)||jsonb_build_object('dossier_number',dr.dossier_number),r.requester_name,'PDV-'||lpad(dr.dossier_number::text,8,'0') from public.customer_requests r left join public.gama_document_references dr on dr.table_name='customer_requests' and dr.document_id=r.id where not purchase and private.erp_module_allowed('customer-requests',array['administrador','comercial']) and r.invoice_id is null and not exists(select 1 from public.sales_orders o where o.source_request_id=r.id)
 ), filtered as (select * from candidates where (k is null or candidates.key=k) and (search='' or concat_ws(' ',number,party,o->>'number',o->>'order_number',q->>'invoice_number') ilike '%'||search||'%')), page as(select * from filtered order by created_at desc,key limit 25 offset off)
 select jsonb_build_object('total',(select count(*) from filtered),'offset',off,'items',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('state',private.gama_process_state(p.key)-'fingerprint')) from page p),'[]')) into result;
 return result;
end $$;
create function public.gama_processes(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_processes(p_action,p_data)$$;
revoke all on function private.gama_processes(text,jsonb),public.gama_processes(text,jsonb) from public,anon;
grant execute on function private.gama_processes(text,jsonb),public.gama_processes(text,jsonb) to authenticated;
