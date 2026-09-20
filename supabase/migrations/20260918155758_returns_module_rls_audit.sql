-- Toda escritura pasa por la RPC SECURITY DEFINER, así que authenticated sólo
-- necesita leer; y aun eso lo filtra la RLS. TRUNCATE se revoca de paso: no
-- pasa por las políticas y no tiene por qué estar concedido.
do $$ declare t text;
begin
 foreach t in array array['return_orders','return_lines','return_credits','return_refunds','return_files']
 loop
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.gama_audit_row()','ret_audit_'||t,t);
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select to authenticated using (coalesce(private.current_user_role(),'''') in (''administrador'',''comercial'',''almacenero''))','ret_read_'||t,t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;

-- El retorno entra en el seguimiento de expediente como un documento más de la
-- cadena: cuelga del pedido de venta y hereda su número de dossier.
do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_register_document'::regproc);
 if position('return_orders' in src)>0 then return;end if;
 old:='  when ''customer_returns'' then edges:=jsonb_build_array(jsonb_build_array(''sales_orders'',j->>''order_id''));';
 if position(old in src)=0 then raise exception 'ANCHOR_EDGES';end if;
 src:=replace(src,old,old||E'\n'||
  '  when ''return_orders'' then edges:=jsonb_build_array(jsonb_build_array(''sales_orders'',j->>''order_id''),jsonb_build_array(''external_invoices'',j->>''invoice_id''));');
 old:='when ''customer_returns'' then ''DEV''';
 if position(old in src)=0 then raise exception 'ANCHOR_PREFIX';end if;
 execute replace(src,old,old||' when ''return_orders'' then ''DEV''');
end $patch$;

create trigger gama_document_reference after insert or update on public.return_orders
 for each row execute function private.gama_document_reference_trigger();
