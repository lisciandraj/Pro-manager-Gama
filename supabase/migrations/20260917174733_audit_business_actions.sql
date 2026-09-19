-- The audit trail recorded only the three row operations. Financial events that are
-- decisions rather than row changes — validating, cancelling, reconciling, closing or
-- reopening a period — need their own verb, with the reason that motivated them.
-- Additive: every existing row keeps its value.
alter table public.gama_audit drop constraint gama_audit_action_check;
alter table public.gama_audit add constraint gama_audit_action_check
 check(action = any(array['INSERT','UPDATE','DELETE','VALIDATE','CANCEL','PAYMENT','RECONCILIATION','CLOSE_PERIOD','REOPEN_PERIOD']));
select 'audit-verbs' as status;
