-- A disabled, untouched schema default is not imported merchant configuration.
-- Configured or previously edited payment settings still refuse an empty
-- production cutover, including when the provider has since been disabled.
do $$declare source text;needle text;begin
 source:=pg_get_functiondef('private.coco_assign_environment(text,text,integer,integer)'::regprocedure);
 needle:='''private.coco_environment'',''private.coco_bootstrap_sources''';
 if strpos(source,needle)=0 then raise exception 'CHECKOUT_FACTORY_DEFAULTS_ANCHOR';end if;
 source:=replace(source,needle,'''private.sales_checkout_payment_settings'','||needle);
 needle:='if p_environment=''production'' then';
 if strpos(source,needle)=0 then raise exception 'CHECKOUT_FACTORY_PRODUCTION_ANCHOR';end if;
 source:=replace(source,needle,needle||$guard$
  if exists(select 1 from private.sales_checkout_payment_settings where stripe_enabled or stripe_livemode or stripe_financial_account_id is not null
   or wire_enabled or wire_financial_account_id is not null or wire_instructions<>'' or version<>1 or updated_by is not null) then
   raise exception 'EMPTY_PRODUCTION_REQUIRED: private.sales_checkout_payment_settings';
  end if;
 $guard$);
 execute source;
end $$;
select private.coco_install_environment_policies();
