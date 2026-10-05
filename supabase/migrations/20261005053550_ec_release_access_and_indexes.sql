-- Cover the references added by supplier withholding configuration.
create index supplier_withholding_income_account on public.supplier_withholding_policies(income_account_id);
create index supplier_withholding_vat_account on public.supplier_withholding_policies(vat_account_id);
create index supplier_withholding_reviewer on public.supplier_withholding_policies(reviewed_by);

-- One SELECT policy per table retains the existing HR/employee/finance scopes.
-- User-wide checks are evaluated once; ownership still depends on each row.
drop policy hr_ec_terms_own on public.hr_ec_employee_terms;
alter policy hr_ec_read on public.hr_ec_employee_terms using(
 (select private.erp_mfa_ok()) and ((select private.hr_admin()) or private.hr_own(employee_id))
);
drop policy hr_ec_signature_own on public.hr_ec_payroll_signatures;
alter policy hr_ec_read on public.hr_ec_payroll_signatures using(
 (select private.erp_mfa_ok()) and ((select private.hr_admin()) or private.hr_own(employee_id))
);
drop policy hr_ec_benefits_own on public.hr_ec_benefits;
alter policy hr_ec_read on public.hr_ec_benefits using(
 (select private.erp_mfa_ok()) and ((select private.hr_admin()) or private.hr_own(employee_id))
);
drop policy hr_ec_benefit_payments_own on public.hr_ec_benefit_payments;
drop policy hr_ec_benefit_payments_finance on public.hr_ec_benefit_payments;
alter policy hr_ec_read on public.hr_ec_benefit_payments using(
 (select private.erp_mfa_ok()) and (
  (select private.hr_admin())
  or exists(select 1 from public.hr_ec_benefits b where b.id=benefit_id and private.hr_own(b.employee_id))
  or (private.erp_module_allowed('accounting',array['administrador','comercial'])
   and private.gama_accounting_rights()->>'scope'='all'
   and coalesce((private.gama_accounting_rights()->>'view')::boolean,false))
 )
);
