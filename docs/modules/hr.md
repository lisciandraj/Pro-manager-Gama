> État relu le 30 septembre 2026. RH comprend employés, organigramme, absences, documents et paie. Le pointage n’est plus présenté comme une fonction du menu. Les photos des employés peuvent alimenter l’avatar de la session ; les initiales restent le repli.

# Coco ERP — HR P1

This release adds HR workflows without warehouse/delivery staff assignments.

## Access

**Responsable RH** is a base role, like Comercial or Almacenero (`profiles.role = 'rrhh'`, `rh` in the app): it is chosen in Users or in the invitation, not granted as an extra right. It opens Human resources and Settings only; it is not sales or warehouse staff (`private.is_staff()` is unchanged), so it reads no products, stock or customers. Administrators and Responsable RH maintain employees, private files and payroll (`private.hr_admin()`). Invitations (`supabase/functions/architect-user-admin`) and the older account panel (`supabase/functions/gama-admin-users`, now versioned here) accept the `rrhh` role.

Each employee has an **N+1**: another employee (`hr_employees.manager_id`), with or without an account. Being someone's N+1 is what makes a team manager: an N+1 with an active staff account manages shifts, approves absences and reviews attendance for their direct reports, never their own (`private.hr_manage()`). A trigger refuses an N+1 that is the employee, an archived employee or someone of the employee's own team (a loop). Employees see their own records, documents, payroll and clock controls. Salaries and documents are protected by database/storage policies, not only hidden buttons.

## Org chart

HR → **Organigrama** replaces the former «Permisos RH» tab. It draws each team under its N+1 (a top-down chart on a computer, an indented list on a phone) and lists apart the employees with neither N+1 nor team, so HR sees who still needs one. HR picks a person in the chart or in the list and changes their N+1 there; the employee file has the same field. Everyone else reads the chart, their own card marked. The N+1 inherited the previous «responsible» account through that account's employee file (migration `hr_base_role_org_chart`); `hr_retire_legacy_rights` then removes the unused `hr_permissions` table and `manager_profile_id` column once this screen is published.

## Leave

Under Leave rules, create effective-dated weekday/hour patterns, public holidays and employee/year accounts. Defaults retain existing Monday–Friday and annual entitlements until configured. Opening accounts support employment-date prorating, confirmed manual carryover, adjustments with reasons, and annual or completed-month accrual. Monthly acquisition uses prorated days through the last completed month; it is configurable business logic, not a jurisdiction-specific legal entitlement engine.

First/last half-days are supported. For a one-day request, the first fraction applies. Approved leave is allocated to each calendar year separately. Holidays and employee patterns apply to both UI and server approvals. Approval rejects insufficient available entitlement and overlapping approved leave (including two half-day requests on one date: combine them into one request). Changes to calendars/accounts can legitimately recalculate historic balances and are audited. Approved absence dates cannot be edited: cancel with reason and replace. Cancellation retains history.

## Attendance compatibility

Attendance tables and server commands remain for compatibility with historical records. Clocking is not an exposed workflow in the current HR menu. Do not infer UI availability from the presence of those database functions.

## Documents

HR uploads PDFs/JPEGs/PNGs up to 10 MB to a private storage bucket. Metadata records employee, type, effective/expiry dates and optional preceding document. Previous versions remain available. Open uses a 60-second signed link. Failed metadata saves attempt to remove the unregistered upload; registered files cannot be deleted through this policy. Changes to employee/private salary fields, leave, patterns, schedules, payroll and permissions have server-generated audit entries.

## Payroll and finance

Create drafts manually or download the CSV template. Columns: `employee_id,period,source_ref,gross,net,employer_cost,cost_center`. Period is `YYYY-MM-01`, amounts use decimal dots, UTF-8 comma/semicolon CSV is supported. Preview and confirmation precede a single atomic batch insert (1–500 rows). Employee/month and source reference uniqueness are also enforced by PostgreSQL. A cancelled employee/month record remains reserved to prevent accidental reimport; correct a draft before validation.

Validate imported payroll before it contributes to costs. Validated monetary fields are immutable. Payments have unique references, may be partial and cannot exceed remaining net pay. Cancel payments with a reason before cancelling their payroll. Only validated employer cost counts as expense; payments reduce net outstanding and are not added as a second cost. HR/admin can see monthly costs and dated payments in the commercial/logistics dashboard. External payroll imports remain compatible. Ecuador payroll is calculated through the workflow below; bank exports require human review and do not send transfers.

## Verification

`tests/hr-p1.spec.js` covers workflows and translations; `tests/modules-hr.spec.js`, `tests/i18n.spec.js`, `tests/operations.spec.js`, and `tests/security-boundaries.spec.js` cover regressions. Run with Playwright.

`supabase/tests/hr-p1.sql` is a database integration test body, also run on PGlite by `tests/hr-p1-sql-db.test.cjs`; `tests/hr-org-chart-db.test.cjs` covers the base role, the N+1 rights, the loop guard and the migration of the former rights. Execute **inside BEGIN / ROLLBACK**, after applying the migration in that same transaction when testing an unapplied release. It creates ephemeral auth/profile fixtures and tests real authenticated RLS, role escalation denial, private documents, leave approval, overlap checks, server clocking, immutable payroll, duplicate imports, partial/overpayments and audit. Never commit the fixture transaction.

## Ecuador calculation and payslips

**Nómina y costes → Nómina calculada para Ecuador** loads on demand. The server uses the actual monthly contract salary and employment dates, versioned confirmed parameters for the year, and effective employee choices. A proposed 2026 parameter set is seeded **unconfirmed**: SBU USD 482, private-sector IESS personal 9.45%, employer 11.15%, part-time minimum health premium 4.41%, reserve 8.33%, and profit-sharing pools 10% / 5%. Review sectoral minimums and additional employer contributions (for example contributions applicable to the employer) before confirming; no rate is embedded in the calculation function. Changing parameters records a new version. Other countries/currencies and missing contract/choice/year data block the calculation.

Payroll inputs are remunerated days within the contract, additional remuneration, reviewed employee IR and authorized other deductions. The IR field records the manager’s actual calculation; it is not an annual personal-income-tax projection engine. Contract salary is already the employee’s monthly contracted amount; it is not multiplied by the part-time fraction a second time. Remunerated days and benefit service periods use 30-day months / 360-day years. Sectoral minimums may exceed SBU. Part-time health complements the minimum base unless full-time coverage with another employer has been verified. The fraction of working time prorates the fourth salary.

The thirteenth salary accrues from remuneration / 12; the fourth from annual SBU, time fraction and remunerated days / 360. Monthly choices increase net pay; accumulated choices remain liabilities while still counting in employer cost. Reserve entitlement starts after one year with the employer, using eligible days in the anniversary month. Reduced worked days in that boundary month require reviewed eligible reserve days. Direct reserve payments increase net; deposits with IESS remain liabilities. Net deducts personal IESS, actual IR and authorized deductions. Cost includes remuneration, employer IESS, minimum health complement, additional contributions, both benefits and reserve. Draft totals are recalculated on the server, even after a direct attempted totals change. Validation rejects stale contract/choice data, freezes the calculation, and books employer cost, net payable and obligations once using configured payroll accounts.

HR records effective choices and verified bank details with the written request/review. Employees may submit their own benefit choice within the current month and the statutory request window (or new-hire window); HR reviews requests outside that window. Employees cannot change the part-time ratio, sectoral minimum, other-employer coverage or bank review through this own-choice command. A validated payroll cannot be recalculated. External records remain explicitly identified as external; computed payroll displays the ERP reference.

**Liquidar décimos acumulados** uses December–November for the thirteenth salary, March–February for Coast/Insular fourth salary, and August–July for Highlands/Amazon fourth salary. Complete validated payroll for the service period is required. Employment termination closes a partial cycle. External payroll requires a separate review, rather than inferring its provisions. Release moves the existing provision to the benefit payable account without creating a second expense; it is retry-safe. Payroll supporting a released benefit cannot be cancelled through the original payroll status command.

**Calcular provisión de utilidades** reviews all employees and former employees whose contracts overlap the year. Missing contract dates block a complete workforce calculation. Remunerated days, working-time fraction and accredited dependent counts must be reviewed with the annual tax declaration. The 10% pool uses proportional worked time; the 5% pool uses proportional worked time multiplied by dependent counts. Salary is not a distribution weight. Each pool uses a largest-remainder allocation to reconcile exact cents. Negative profit creates no pool. The zero-dependent case requires an explicitly reviewed distribution criterion; it is never divided by zero or silently omitted. The definitive annual provision requires a finished year and a reviewed declaration, posts once on December 31, and creates individual benefits payable. Partial benefit payments post through an actual active financial account and reduce both the liability and cash balance once. Closed periods roll the entire operation back.

**Rol de pagos** opens own-only for the employee, or for HR/admin. The PDF uses the shared corporate template and contains components, benefit modes, paid/balance amounts, and the ERP reference. Only the linked active employee can acknowledge a validated role: the server stores the PNG, account, server timestamp and SHA-256 of the frozen payroll record. This is an authenticated receipt acknowledgment, not a qualified certificate-based PDF signature. Managers see no other employees’ salaries or signatures. Sign-out closes private dialogs; token refresh preserves forms.

**Exportar nómina para depósito bancario** exports the actual outstanding amounts of validated monthly payroll, optionally including released benefits, using the latest effective reviewed bank details. Missing beneficiary details block the whole export. The semicolon UTF-8 CSV includes name, identification, bank, account type, account number, USD amount and ERP reference. Names and descriptions are protected against CSV formula execution; account numbers retain their original leading zeros in the file. Import those columns as text in a spreadsheet. This is a reviewable interchange file, not a certified proprietary Pichincha/Produbanco/Guayaquil format. Downloading never records a payment or sends a transfer.

Actual employee IR in posted payroll joins monthly draft form 103; source reversals follow the ledger reversal month. Annual utility provisions never count as cash expenses until paid.

Primary sources reviewed on 2026-10-05:

- [IESS employee/employer contribution rates](https://www.iess.gob.ec/web/afiliado/servicios-y-prestaciones).
- [IESS employer obligations and part-time minimum health base](https://www.iess.gob.ec/es/web/empleador/obligaciones).
- [IESS C.D. 404, part-time minimum health contribution](https://www.iess.gob.ec/documents/10162/33703/C.D.%2B404): historical annual SBU values are not used.
- [2026 SBU ministerial publication](https://www.trabajo.gob.ec/wp-content/plugins/download-monitor/download.php?force=1&id=4933).
- [Ministry labor agreements](https://www.trabajo.gob.ec/acuerdos-ministeriales/), MDT-2023-140: articles 9–10 and 15–16, general rules 4–6; [the ministerial document](https://www.fielweb.com/App_Themes/InformacionInteres/mdt23140.pdf) defines periods, excluded contribution bases, 30/360 days, annual distribution and accredited dependents.
- [Current Labor Code supplied by the Ministry](https://www.trabajo.gob.ec/wp-content/plugins/download-monitor/download.php?force=1&id=1628), articles 97, 111–114 and reserve entitlement. Do not restore the unconstitutional old 24-SBU utility cap.

`tests/ec-payroll-db.test.cjs` runs the real schema in an isolated database: unreviewed rates, minimums/part-time health, gross/net/cost, reserve entitlement, forged totals, stale validation, own-only receipt/hash, annual pools/ex-employees/rounding, one-time provisions, partial payment limits, cash balance and draft 103. `tests/hr-p1.spec.js` checks review/save and the mobile signature/PDF path. Existing HR, accounting and access regressions remain required.
