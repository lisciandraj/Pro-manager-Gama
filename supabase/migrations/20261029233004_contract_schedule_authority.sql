-- Preserve original authorship while binding scheduled drafts to the person
-- who last authorized their current configuration. Historical, untouched
-- contracts continue to use their original recorded author.
alter table private.customer_contracts add column scheduled_by uuid references public.profiles(id);
create index customer_contracts_scheduled_by on private.customer_contracts(scheduled_by);
do $audit$
declare src text;before_text text;
begin
 src:=pg_get_functiondef('private.coco_contracts(text,jsonb)'::regprocedure);
 before_text:='elsif p_action=''save'' then';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:contract_save_authority';end if;
 src:=replace(src,before_text,before_text||$gate$
  if coalesce((p_data->>'automatic')::boolean,true) then perform private.business_require('sales-orders','create');end if;
 $gate$);
 before_text:='active,automatic,notes,created_by)';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:contract_schedule_column';end if;
 src:=replace(src,before_text,'active,automatic,notes,created_by,scheduled_by)');
 before_text:='coalesce(p_data->>''notes'',''''),auth.uid())';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:contract_schedule_actor';end if;
 src:=replace(src,before_text,'coalesce(p_data->>''notes'',''''),auth.uid(),auth.uid())');
 before_text:='automatic=excluded.automatic,notes=excluded.notes,';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:contract_schedule_update';end if;
 src:=replace(src,before_text,before_text||'scheduled_by=excluded.scheduled_by,');
 before_text:='update private.customer_contracts set active=not active,version=version+1';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:contract_schedule_resume';end if;
 execute replace(src,before_text,$gate$
  if not s.active and s.automatic then perform private.business_require('sales-orders','create');end if;
  update private.customer_contracts set scheduled_by=case when not active and automatic then auth.uid() else scheduled_by end,active=not active,version=version+1$gate$);
 src:=pg_get_functiondef('private.contract_tick()'::regprocedure);
 before_text:='s.created_by';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:contract_schedule_execution';end if;
 execute replace(src,before_text,'coalesce(s.scheduled_by,s.created_by)');
end $audit$;
notify pgrst,'reload schema';
