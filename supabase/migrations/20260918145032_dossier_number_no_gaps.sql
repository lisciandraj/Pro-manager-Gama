create or replace function private.gama_register_document(t text, j jsonb) returns void
language plpgsql security definer set search_path='' as $fn$
declare id uuid:=coalesce((j->>'id')::uuid,(j->>'delivery_id')::uuid); edges jsonb:='[]'; e jsonb;
 cases bigint[]:='{}'; target bigint; p uuid;
begin
 if id is null then return;end if;
 perform pg_advisory_xact_lock(724613092);
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

 -- Mirar antes de pedir: el documento y sus enlaces, por si ya tienen casa.
 cases:=coalesce((select array_agg(dossier_number) from public.gama_document_references
   where table_name=t and document_id=id),'{}');
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   cases:=cases||coalesce((select array_agg(dossier_number) from public.gama_document_references
     where table_name=e->>0 and document_id=p),'{}');
  end if;
 end loop;
 select min(x) into target from unnest(cases) x;
 -- Y sólo aquí, cuando de verdad nace un expediente, se gasta un número.
 if target is null then target:=nextval('private.gama_dossier_sequence');end if;

 insert into public.gama_document_references(table_name,document_id,dossier_number)
  values(t,id,target) on conflict do nothing;
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   insert into public.gama_document_references(table_name,document_id,dossier_number)
    values(e->>0,p,target) on conflict do nothing;
  end if;
 end loop;

 update public.gama_document_references set dossier_number=target
  where dossier_number=any(cases) and dossier_number<>target;

 with numbered as (select table_name,document_id,row_number() over(partition by table_name order by node_index) rn from public.gama_document_references where dossier_number=target)
 update public.gama_document_references r set ordinal=z.rn,document_reference=(case r.table_name when 'customer_requests' then 'SOL' when 'invoices' then 'COT' when 'sales_orders' then 'PED' when 'fulfillment_preparations' then 'PREP' when 'fulfillment_packages' then 'PAQ' when 'sales_deliveries' then 'ENV' when 'tms_deliveries' then 'ENT' when 'tms_proofs' then 'PDE' when 'external_invoices' then 'FAC' when 'external_invoice_payments' then 'COB' when 'customer_returns' then 'DEV' end)||case when z.rn>1 then '-'||private.gama_reference_letters(z.rn) else '' end||'-'||lpad(target::text,8,'0')
 from numbered z where r.table_name=z.table_name and r.document_id=z.document_id;
end $fn$;

select setval('private.gama_dossier_sequence',
 (select max(dossier_number) from public.gama_document_references));
