# GAMA HR P1

This release adds HR workflows without warehouse/delivery staff assignments.

## Access

**Responsable RH** is a base role, like Comercial or Almacenero (`profiles.role = 'rrhh'`, `rh` in the app): it is chosen in Users or in the invitation, not granted as an extra right. It opens Human resources and Settings only; it is not sales or warehouse staff (`private.is_staff()` is unchanged), so it reads no products, stock or customers. Administrators and Responsable RH maintain employees, private files and payroll (`private.hr_admin()`). Invitations (`supabase/functions/architect-user-admin`) and the older account panel (`supabase/functions/gama-admin-users`, now versioned here) accept the `rrhh` role.

Each employee has an **N+1**: another employee (`hr_employees.manager_id`), with or without an account. Being someone's N+1 is what makes a team manager: an N+1 with an active staff account manages shifts, approves absences and reviews attendance for their direct reports, never their own (`private.hr_manage()`). A trigger refuses an N+1 that is the employee, an archived employee or someone of the employee's own team (a loop). Employees see their own records, documents, payroll and clock controls. Salaries and documents are protected by database/storage policies, not only hidden buttons.

## Org chart

HR → **Organigrama** replaces the former «Permisos RH» tab. It draws each team under its N+1 (a top-down chart on a computer, an indented list on a phone) and lists apart the employees with neither N+1 nor team, so HR sees who still needs one. HR picks a person in the chart or in the list and changes their N+1 there; the employee file has the same field. Everyone else reads the chart, their own card marked. The N+1 inherited the previous «responsible» account through that account's employee file (migration `hr_base_role_org_chart`); `hr_retire_legacy_rights` then removes the unused `hr_permissions` table and `manager_profile_id` column once this screen is published.

## Leave

Under Leave rules, create effective-dated weekday/hour patterns, public holidays and employee/year accounts. Defaults retain existing Monday–Friday and annual entitlements until configured. Opening accounts support employment-date prorating, confirmed manual carryover, adjustments with reasons, and annual or completed-month accrual. Monthly acquisition uses prorated days through the last completed month; it is configurable business logic, not a jurisdiction-specific legal entitlement engine.

First/last half-days are supported. For a one-day request, the first fraction applies. Approved leave is allocated to each calendar year separately. Holidays and employee patterns apply to both UI and server approvals. Approval rejects insufficient available entitlement and overlapping approved leave (including two half-day requests on one date: combine them into one request). Changes to calendars/accounts can legitimately recalculate historic balances and are audited. Approved absence dates cannot be edited: cancel with reason and replace. Cancellation retains history.

## Time

Employees use server-timed clock-in, break, resume and clock-out; only one open session per employee. Managers schedule non-overlapping shifts and correct attendance with a reason. Overtime is calculated across daily sessions against planned net shift hours, or the employee's daily work pattern. Displayed dates use the viewer's timezone; daily overtime groups in America/Guayaquil. Review includes worked hours and overtime together. Payroll remains externally calculated.

## Documents

HR uploads PDFs/JPEGs/PNGs up to 10 MB to a private storage bucket. Metadata records employee, type, effective/expiry dates and optional preceding document. Previous versions remain available. Open uses a 60-second signed link. Failed metadata saves attempt to remove the unregistered upload; registered files cannot be deleted through this policy. Changes to employee/private salary fields, leave, patterns, schedules, payroll and permissions have server-generated audit entries.

## Payroll and finance

Create drafts manually or download the CSV template. Columns: `employee_id,period,source_ref,gross,net,employer_cost,cost_center`. Period is `YYYY-MM-01`, amounts use decimal dots, UTF-8 comma/semicolon CSV is supported. Preview and confirmation precede a single atomic batch insert (1–500 rows). Employee/month and source reference uniqueness are also enforced by PostgreSQL. A cancelled employee/month record remains reserved to prevent accidental reimport; correct a draft before validation.

Validate imported payroll before it contributes to costs. Validated monetary fields are immutable. Payments have unique references, may be partial and cannot exceed remaining net pay. Cancel payments with a reason before cancelling their payroll. Only validated employer cost counts as expense; payments reduce net outstanding and are not added as a second cost. HR/admin can see monthly costs and dated payments in the commercial/logistics dashboard. No fiscal payroll calculation or automatic bank transfer is performed.

## Verification

`tests/hr-p1.spec.js` covers workflows and translations; `tests/modules-hr.spec.js`, `tests/i18n.spec.js`, `tests/operations.spec.js`, and `tests/security-boundaries.spec.js` cover regressions. Run with Playwright.

`supabase/tests/hr-p1.sql` is a database integration test body, also run on PGlite by `tests/hr-p1-sql-db.test.cjs`; `tests/hr-org-chart-db.test.cjs` covers the base role, the N+1 rights, the loop guard and the migration of the former rights. Execute **inside BEGIN / ROLLBACK**, after applying the migration in that same transaction when testing an unapplied release. It creates ephemeral auth/profile fixtures and tests real authenticated RLS, role escalation denial, private documents, leave approval, overlap checks, server clocking, immutable payroll, duplicate imports, partial/overpayments and audit. Never commit the fixture transaction.
