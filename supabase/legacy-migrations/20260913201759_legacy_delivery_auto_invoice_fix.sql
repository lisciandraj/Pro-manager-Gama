-- Legacy quotes predate quote_state. The confirmed sales order and signed full
-- delivery authorize their internal invoice; never fabricate quote acceptance.
do $migration$
declare src text;anchor text;
begin
 select pg_get_functiondef('private.gama_delivery_invoice_create(text,jsonb)'::regprocedure) into src;
 anchor:='if not found or q.quote_state is distinct from ''accepted'' then raise exception ''QUOTE_NOT_ACCEPTED'';end if;';
 if strpos(src,anchor)=0 then raise exception 'LEGACY_QUOTE_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,'if not found or (q.quote_state is not null and q.quote_state<>''accepted'') then raise exception ''QUOTE_NOT_ACCEPTED'';end if;');
 execute src;
 -- Isolate billing errors from the already validated physical delivery.
 select pg_get_functiondef('private.gama_invoice_on_signed_delivery()'::regprocedure) into src;
 anchor:=' inv:=private.gama_delivery_invoice_create';
 if strpos(src,anchor)=0 then raise exception 'AUTO_INVOICE_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,' begin'||chr(10)||anchor);
 anchor:=' return new;'||chr(10)||'end ';
 if strpos(src,anchor)=0 then raise exception 'TRIGGER_END_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,$patch$
 exception when others then
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
  values(oid,'invoice_auto_failed',tid,auth.uid(),jsonb_build_object(
   'delivery_id',tid,'reason','Entrega registrada; revisar la facturación automática.',
   'error_code',sqlstate,'error',sqlerrm));
 end;
 return new;
end $patch$);
 execute src;
end $migration$;
