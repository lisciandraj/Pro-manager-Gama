-- Canonical ERP references, separate from original and fiscal document numbers.
create sequence private.gama_dossier_sequence;
revoke all on sequence private.gama_dossier_sequence from public,anon,authenticated;
create function private.gama_reference_letters(n bigint) returns text language plpgsql immutable strict set search_path='' as $$
declare result text:='';begin while n>0 loop n:=n-1;result:=chr(65+(n%26)::integer)||result;n:=n/26;end loop;return result;end $$;
revoke all on function private.gama_reference_letters(bigint) from public,anon,authenticated;
create table public.gama_document_references (
 table_name text not null check(table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','customer_returns')),
 document_id uuid not null,
 node_index bigint generated always as identity unique,
 dossier_number bigint not null,
 ordinal bigint not null default 1,
 document_reference text not null default '',
 primary key(table_name,document_id)
);
create index gama_document_references_dossier on public.gama_document_references(dossier_number,table_name);
alter table public.gama_document_references enable row level security;
revoke all on public.gama_document_references from public,anon,authenticated;
grant select on public.gama_document_references to authenticated;
-- Each EXISTS runs under the caller's original document RLS, including customers.
create policy dossier_reference_read on public.gama_document_references for select to authenticated using (
 case table_name
 when 'customer_requests' then exists(select 1 from public.customer_requests x where x.id=document_id)
 when 'invoices' then exists(select 1 from public.invoices x where x.id=document_id)
 when 'sales_orders' then exists(select 1 from public.sales_orders x where x.id=document_id)
 when 'fulfillment_preparations' then exists(select 1 from public.fulfillment_preparations x where x.id=document_id)
 when 'fulfillment_packages' then exists(select 1 from public.fulfillment_packages x where x.id=document_id)
 when 'sales_deliveries' then exists(select 1 from public.sales_deliveries x where x.id=document_id)
 when 'tms_deliveries' then exists(select 1 from public.tms_deliveries x where x.id=document_id)
 when 'tms_proofs' then exists(select 1 from public.tms_proofs x where x.delivery_id=document_id)
 when 'external_invoices' then exists(select 1 from public.external_invoices x where x.id=document_id)
 when 'external_invoice_payments' then exists(select 1 from public.external_invoice_payments x where x.id=document_id)
 when 'customer_returns' then exists(select 1 from public.customer_returns x where x.id=document_id)
 else false end
);
-- Trigger-only writer. No client has EXECUTE or DML rights on the registry.
create function private.gama_register_document(t text,j jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare id uuid:=coalesce((j->>'id')::uuid,(j->>'delivery_id')::uuid); edges jsonb:='[]'; e jsonb; cases bigint[]; target bigint; p uuid;
begin
 if id is null then return;end if;
 perform pg_advisory_xact_lock(724613092);
 insert into public.gama_document_references(table_name,document_id,dossier_number) values(t,id,nextval('private.gama_dossier_sequence')) on conflict do nothing;
 case t
 when 'customer_requests' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'invoice_id'));
 when 'sales_orders' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'source_quote_id'),jsonb_build_array('customer_requests',j->>'source_request_id'));
 when 'fulfillment_preparations' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('sales_deliveries',j->>'shipment_id'));
 when 'fulfillment_packages' then edges:=jsonb_build_array(jsonb_build_array('fulfillment_preparations',j->>'preparation_id'));
 when 'sales_deliveries' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('tms_deliveries',j->>'tms_delivery_id'));
 when 'tms_proofs' then edges:=jsonb_build_array(jsonb_build_array('tms_deliveries',j->>'delivery_id'));
 when 'external_invoices' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('invoices',j->>'source_quote_id'));
 when 'external_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('external_invoices',j->>'invoice_id'));
 when 'customer_returns' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'));
 else null;end case;
 select array[dossier_number] into cases from public.gama_document_references where table_name=t and document_id=id;
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   insert into public.gama_document_references(table_name,document_id,dossier_number) values(e->>0,p,nextval('private.gama_dossier_sequence')) on conflict do nothing;
   cases:=cases||array(select dossier_number from public.gama_document_references where table_name=e->>0 and document_id=p);
  end if;
 end loop;
 select min(x) into target from unnest(cases) x;
 update public.gama_document_references set dossier_number=target where dossier_number=any(cases) and dossier_number<>target;
 with numbered as (select table_name,document_id,row_number() over(partition by table_name order by node_index) rn from public.gama_document_references where dossier_number=target)
 update public.gama_document_references r set ordinal=z.rn,document_reference=(case r.table_name when 'customer_requests' then 'DEM' when 'invoices' then 'DEV' when 'sales_orders' then 'CMD' when 'fulfillment_preparations' then 'PREP' when 'fulfillment_packages' then 'COL' when 'sales_deliveries' then 'EXP' when 'tms_deliveries' then 'LIV' when 'tms_proofs' then 'POD' when 'external_invoices' then 'FAC' when 'external_invoice_payments' then 'PAY' when 'customer_returns' then 'RET' end)||case when z.rn>1 then '-'||private.gama_reference_letters(z.rn) else '' end||'-'||lpad(target::text,8,'0')
 from numbered z where r.table_name=z.table_name and r.document_id=z.document_id;
end $$;
revoke all on function private.gama_register_document(text,jsonb) from public,anon,authenticated;
create function private.gama_document_reference_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.gama_register_document(TG_TABLE_NAME,to_jsonb(new));return new;end $$;
revoke all on function private.gama_document_reference_trigger() from public,anon,authenticated;
do $$ declare t text;j jsonb;begin
 foreach t in array array['customer_requests','invoices','sales_orders','tms_deliveries','sales_deliveries','fulfillment_preparations','fulfillment_packages','external_invoices','external_invoice_payments','tms_proofs','customer_returns'] loop
  execute format('create trigger gama_document_reference after insert or update on public.%I for each row execute function private.gama_document_reference_trigger()',t);
  for j in execute format('select to_jsonb(x) from public.%I x order by %I',t,case when t='tms_proofs' then 'delivery_id' else 'id' end) loop perform private.gama_register_document(t,j);end loop;
 end loop;
end $$;
-- Retain the existing customer authorization checks and expose the same refs in
-- the client delivery projection, which deliberately does not expose TMS rows.
do $$ declare src text;begin
 select pg_get_functiondef('private.gama_client_deliveries(uuid,integer)'::regprocedure) into src;
 if position('''shipment_number'',s.number,''order_number'',o.number' in src)=0 then raise exception 'Unexpected delivery projection';end if;
 src:=replace(src,'''shipment_number'',s.number,''order_number'',o.number',
 '''shipment_number'',coalesce((select document_reference from public.gama_document_references where table_name=''sales_deliveries'' and document_id=s.id),s.number),''order_number'',coalesce((select document_reference from public.gama_document_references where table_name=''sales_orders'' and document_id=o.id),o.number),''delivery_reference'',(select document_reference from public.gama_document_references where table_name=''tms_deliveries'' and document_id=d.id)');
 execute src;
end $$;
