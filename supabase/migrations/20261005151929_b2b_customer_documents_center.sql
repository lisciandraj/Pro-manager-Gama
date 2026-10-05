-- One customer documents page; each download still rechecks membership/ownership.
-- No inline proof images, private notes, product costs or Storage paths in lists.
alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_documents;
revoke all on function private.gama_b2b_action_before_documents(text,jsonb) from public,anon,authenticated;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare cid uuid:=private.gama_b2b_customer();off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));
 term text:=left(btrim(coalesce(p_data->>'search','')),100);filter text:=coalesce(p_data->>'kind','');result jsonb;begin
 if p_action='documents' then
  if filter not in ('','invoice','delivery_proof','quote') then raise exception 'INVALID_DATA';end if;
  with owned as(
   select 'invoice' kind,i.id,coalesce(i.erp_reference,i.number) reference,i.issue_date document_date,
    coalesce(i.external_number,i.number) fiscal_number,i.total amount,i.fiscal_status status,
    (select s.id from public.sri_invoice_issues s where s.source_invoice_id=i.id and s.customer_id=cid and s.status='authorized' order by s.created_at desc limit 1) sri_id,
    coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'mime_type',f.mime_type) order by f.id) from public.external_invoice_files f where f.invoice_id=i.id),'[]') files
   from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=cid and i.fiscal_status not in ('cancelled','rejected')
   union all
   select 'delivery_proof',d.id,d.erp_reference,d.delivery_date,null,null,d.status,null,'[]'::jsonb
   from public.tms_deliveries d where d.customer_id=cid and exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)
    and exists(select 1 from public.sales_deliveries s join public.sales_orders o on o.id=s.order_id where s.tms_delivery_id=d.id and o.customer_id=cid)
   union all
   select 'quote',q.id,coalesce(q.erp_reference,q.invoice_number),q.issue_date::date,null,q.total,q.quote_state,null,'[]'::jsonb
   from public.invoices q where q.customer_id=cid and q.quote_state in ('sent','accepted','rejected') and q.status not in ('cancelled','rejected')
  ),filtered as(select * from owned where (filter='' or kind=filter) and (term='' or concat_ws(' ',reference,fiscal_number) ilike '%'||term||'%')),
  limited as(select * from filtered order by document_date desc,kind,id limit 30 offset off)
  select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce(jsonb_agg(to_jsonb(limited) order by document_date desc,kind,id),'[]'),'as_of',now()) into result from limited;
  return result;
 elsif p_action='quote_document' then
  select jsonb_build_object('reference',coalesce(q.erp_reference,q.invoice_number),'date',q.issue_date::date,'valid_until',q.quote_valid_until,'status',q.quote_state,'subtotal',q.subtotal,'tax',q.tax,'total',q.total,
   'customer',(select jsonb_build_object('name',name,'identification',identification) from public.customers where id=cid),
   'address',q.quote_details->>'delivery_address','lines',(select coalesce(jsonb_agg(jsonb_build_object('description',coalesce(l.quote_description,p.name),'reference',p.reference,'quantity',l.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate,'line_total',l.line_total) order by l.id),'[]') from public.invoice_lines l left join public.products p on p.id=l.product_id where l.invoice_id=q.id),
   'company',(select jsonb_build_object('legal_name',legal_name,'tax_id',tax_id,'address',address,'phone',phone,'email',email,'country',country,'currency',currency,'logo_data',logo_data) from public.company_settings where id)) into result
   from public.invoices q where q.id=(p_data->>'id')::uuid and q.customer_id=cid and q.quote_state in ('sent','accepted','rejected') and q.status not in ('cancelled','rejected');
  if result is null then raise exception 'NOT_FOUND';end if;return result;
 end if;
 return private.gama_b2b_action_before_documents(p_action,p_data);
end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

-- Per-customer account management from Contacts, with the same rights as the
-- website administration; no guessed email binding and no profile activation.
create function private.gama_b2b_customer_accounts(p_customer uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('website',array['administrador']) or not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return jsonb_build_object('customer',(select jsonb_build_object('id',c.id,'name',c.name,'email',c.email,'enabled',coalesce(a.enabled,false)) from public.customers c left join public.b2b_customer_access a on a.customer_id=c.id where c.id=p_customer and c.active),
  'members',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'email',u.email,'active',m.active,'verified',u.email_confirmed_at is not null) order by p.full_name,p.id),'[]') from public.b2b_memberships m join public.profiles p on p.id=m.profile_id join auth.users u on u.id=p.id where m.customer_id=p_customer and p.deleted_at is null),
  'available',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'email',p.email) order by p.full_name,p.id),'[]') from (select p.id,p.full_name,u.email from public.profiles p join auth.users u on u.id=p.id where p.role='cliente' and p.deleted_at is null and not exists(select 1 from public.b2b_memberships m where m.profile_id=p.id) order by p.full_name,p.id limit 100)p));
end $$;
create function public.gama_b2b_customer_accounts(p_customer uuid) returns jsonb language sql security invoker set search_path='' as $$select private.gama_b2b_customer_accounts(p_customer)$$;
revoke all on function public.gama_b2b_customer_accounts(uuid),private.gama_b2b_customer_accounts(uuid) from public,anon,service_role;
grant execute on function public.gama_b2b_customer_accounts(uuid),private.gama_b2b_customer_accounts(uuid) to authenticated;
