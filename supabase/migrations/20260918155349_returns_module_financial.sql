-- Corrección: la retención sólo hay que bloquearla, no volcarla en una
-- variable uuid.
do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_returns_action3(text,jsonb,jsonb,date)'::regprocedure);
 old:='  select * into resv from public.stock_reservations where id=l.hold_reservation_id for update;';
 if position(old in src)=0 then raise exception 'ANCHOR_RESV';end if;
 execute replace(src,old,'  perform 1 from public.stock_reservations where id=l.hold_reservation_id for update;');
end $patch$;

create or replace function private.gama_returns_action4(p_action text,p_data jsonb,rights jsonb,today date)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare
 o public.return_orders; u uuid:=auth.uid(); eid uuid;
 total numeric; already numeric; amount numeric; cap numeric; j jsonb;
begin
 if p_data ? 'id' then
  select * into o from public.return_orders where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  if o.status in ('closed','cancelled') and p_action<>'file_get' then raise exception 'RETURN_CLOSED';end if;
 end if;
 total:=private.gama_return_amount(o.id);

 -- Qué se hace con el dinero. Nada obliga a una acción: se puede desguazar y
 -- reembolsar, o reponer en stock y no devolver un céntimo.
 if p_action='financial_action' then
  if p_data->>'financial_action' not in ('none','credit','refund','store_credit')
   then raise exception 'INVALID_ACTION';end if;
  if (p_data->>'financial_action') in ('credit','refund','store_credit')
     and not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  update public.return_orders set financial_action=p_data->>'financial_action',updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'financial_action',p_data->>'financial_action');

 -- El importe lo calcula GAMA a partir de las líneas, que llevan el precio y
 -- el impuesto del documento original. El usuario autorizado puede ajustarlo,
 -- pero nunca por encima de lo que queda por abonar de esa factura.
 elsif p_action='credit_preview' then
  return jsonb_build_object('amount',total,
   'invoice_total',coalesce((select i.total from public.external_invoices i where i.id=o.invoice_id),0),
   'already',coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id),0));

 elsif p_action='credit' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  if o.invoice_id is null then raise exception 'INVOICE_REQUIRED';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  select i.total into cap from public.external_invoices i where i.id=o.invoice_id;
  already:=coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id),0);
  if amount+already>cap then raise exception 'CREDIT_EXCEEDS_INVOICE';end if;
  insert into public.return_credits(return_id,invoice_id,amount,issued_on,notes,created_by)
   values(o.id,o.invoice_id,amount,coalesce(nullif(p_data->>'issued_on','')::date,today),
     p_data->>'notes',u) returning id into eid;
  update public.return_orders set financial_action='credit',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,
   'number',(select number from public.return_credits where id=eid),'amount',amount);

 -- El abono que manda el proveedor: se registra, no se emite.
 elsif p_action='supplier_credit' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'supplier' then raise exception 'INVALID_ACTION';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  insert into public.return_credits(return_id,supplier_invoice_id,supplier_reference,amount,issued_on,
    notes,filename,mime_type,data_url,created_by)
   values(o.id,o.supplier_invoice_id,nullif(p_data->>'supplier_reference',''),amount,
     coalesce(nullif(p_data->>'issued_on','')::date,today),p_data->>'notes',
     nullif(p_data->>'filename',''),nullif(p_data->>'mime_type',''),nullif(p_data->>'data_url',''),u)
   returning id into eid;
  update public.return_orders set status='credited',financial_action='credit',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,'amount',amount);

 -- Reembolso al cliente. Nunca por encima del importe devuelto, y varios
 -- reembolsos sumados tampoco pueden pasarse.
 elsif p_action='refund' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  already:=coalesce((select sum(f.amount) from public.return_refunds f where f.return_id=o.id),0);
  if amount+already>total then raise exception 'REFUND_EXCEEDS_RETURN';end if;
  if length(coalesce(p_data->>'method',''))<2 then raise exception 'METHOD_REQUIRED';end if;
  insert into public.return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by)
   values(o.id,amount,coalesce(nullif(p_data->>'paid_at','')::date,today),p_data->>'method',
     nullif(p_data->>'reference',''),p_data->>'notes',
     nullif(p_data->>'request_key','')::uuid,u)
   on conflict(request_key) do nothing returning id into eid;
  if eid is null then
   select id into eid from public.return_refunds where request_key=(p_data->>'request_key')::uuid;
  end if;
  update public.return_orders set financial_action='refund',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,'amount',amount,
   'refunded',(select coalesce(sum(amount),0) from public.return_refunds where return_id=o.id),
   'outstanding',total-(select coalesce(sum(amount),0) from public.return_refunds where return_id=o.id));

 elsif p_action='close' then
  if not (rights->>'process')::boolean and not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind='customer' and o.status not in ('processed') then raise exception 'NOT_PROCESSED';end if;
  if o.kind='supplier' and o.status not in ('shipped','credited') then raise exception 'NOT_SHIPPED';end if;
  update public.return_orders set status='closed',closed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','closed');

 elsif p_action='cancel' then
  if not (rights->>'create')::boolean then raise exception 'NOT_ALLOWED';end if;
  -- Sólo mientras no se haya tocado la mercancía: después hay movimientos de
  -- stock detrás y anular en silencio los dejaría huérfanos.
  if o.status<>'to_process' then raise exception 'RETURN_ALREADY_STARTED';end if;
  update public.return_orders set status='cancelled',closed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','cancelled');

 elsif p_action='file_add' then
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  if (select count(*) from public.return_files where return_id=o.id)>=6 then raise exception 'TOO_MANY_FILES';end if;
  insert into public.return_files(return_id,filename,mime_type,data_url,created_by)
   values(o.id,left(coalesce(p_data->>'filename','archivo'),180),nullif(p_data->>'mime_type',''),
     p_data->>'data_url',u) returning id into eid;
  return jsonb_build_object('id',eid);

 elsif p_action='file_get' then
  select jsonb_build_object('filename',filename,'mime_type',mime_type,'data_url',data_url) into j
   from public.return_files where id=(p_data->>'file_id')::uuid;
  if j is null then raise exception 'FILE_NOT_FOUND';end if;
  return j;

 elsif p_action='file_delete' then
  delete from public.return_files where id=(p_data->>'file_id')::uuid and return_id=o.id returning id into eid;
  if eid is null then raise exception 'FILE_NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);

 elsif p_action='delete' then
  if not (rights->>'delete')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.status<>'to_process' then raise exception 'RETURN_ALREADY_STARTED';end if;
  delete from public.return_orders where id=o.id;
  return jsonb_build_object('id',o.id,'deleted',true);
 end if;
 raise exception 'INVALID_ACTION';
end $fn$;
revoke all on function private.gama_returns_action4(text,jsonb,jsonb,date) from public,anon,authenticated;

create or replace function public.gama_returns_action(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path=''
as $fn$select private.gama_returns_action(p_action,p_data)$fn$;
revoke all on function public.gama_returns_action(text,jsonb) from public,anon;
grant execute on function public.gama_returns_action(text,jsonb) to authenticated;
