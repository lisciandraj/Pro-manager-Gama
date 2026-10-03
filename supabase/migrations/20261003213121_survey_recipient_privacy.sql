-- Preserve CRM visibility after the foreign key is cleared by a deleted prospect/person.
alter table private.survey_invitations add column crm_recipient boolean not null default false;
update private.survey_invitations set crm_recipient=true where contact_id is not null or lead_id is not null;
create function private.survey_recipient_privacy() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 new.crm_recipient:=new.crm_recipient or new.contact_id is not null or new.lead_id is not null;
 if tg_op='UPDATE' then new.crm_recipient:=new.crm_recipient or old.crm_recipient;end if;
 return new;
end $$;
revoke all on function private.survey_recipient_privacy() from public,anon,authenticated;
create trigger survey_recipient_privacy before insert or update on private.survey_invitations for each row execute function private.survey_recipient_privacy();
do $$declare definition text;begin
 definition:=pg_get_functiondef('private.gama_surveys(text,jsonb)'::regprocedure);
 if strpos(definition,'inv.contact_id is null and inv.lead_id is null or')=0 or strpos(definition,'contact_id is null and lead_id is null or')=0 then raise exception 'SURVEY_PRIVACY_ANCHOR_MISSING';end if;
 definition:=replace(definition,'inv.contact_id is null and inv.lead_id is null or','not inv.crm_recipient or');
 definition:=replace(definition,'contact_id is null and lead_id is null or','not crm_recipient or');
 execute definition;
end $$;
notify pgrst,'reload schema';
