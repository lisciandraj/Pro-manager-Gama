-- Payment readers and retries retain the current payments-module boundary.
do $audit$
declare signature text;src text;anchor text;
begin
 foreach signature in array array['private.gama_payment_action(text,jsonb)','private.gama_receipt_action(text,jsonb)'] loop
  src:=pg_get_functiondef(signature::regprocedure);
  if src !~* '\mbegin\M' then raise exception 'SECURITY_PATCH_ANCHOR:collection_authority:%',signature;end if;
  execute regexp_replace(src,'\mbegin\M',$patch$begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 $patch$,'i');
 end loop;

 -- This shared handler also links delivery documents. Only its collection
 -- actions require payments access; normal shipping keeps its existing gate.
 src:=pg_get_functiondef('private.gama_commercial_action(text,jsonb)'::regprocedure);
 anchor:='if v_role not in (''administrador'',''comercial'') then raise exception ''ROLE_NOT_ALLOWED''; end if;';
 if position(anchor in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:commercial_collection_authority';end if;
 src:=replace(src,anchor,anchor||$patch$
 if p_action in ('payment','cancel_payment') and not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 $patch$);
 -- The invoice row is already locked. Use the same current net residual as
 -- the collection UI, including credit/withholding offsets and pending money.
 anchor:='if v_paid + v_amount > v_invoice.total then raise exception ''PAYMENT_EXCEEDS_BALANCE''; end if;';
 if position(anchor in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:customer_payment_capacity';end if;
 src:=replace(src,anchor,$patch$
 if v_amount>coalesce((select greatest(0,r.balance-r.unposted_payment) from private.gama_receivables r where r.id=v_invoice.id),0) then raise exception 'PAYMENT_EXCEEDS_BALANCE';end if;
 $patch$);
 execute src;

 -- Advance allocation holds the same invoice lock and must reserve pending
 -- ordinary payments as well as the amount already posted to the receivable.
 src:=pg_get_functiondef('private.gama_receipt_action_before_payment_modes(text,jsonb)'::regprocedure);
 anchor:='amount>remaining or amount>inv.balance';
 if position(anchor in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:receipt_allocation_capacity';end if;
 execute replace(src,anchor,'amount>remaining or amount>greatest(0,inv.balance-inv.unposted_payment)');
end $audit$;

create policy security_collection_read on public.external_invoice_payments as restrictive
 for select to authenticated using(private.erp_module_allowed('payments',array['administrador','comercial']));
notify pgrst,'reload schema';
