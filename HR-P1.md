# GAMA HR P1

This release adds HR workflows without warehouse/delivery staff assignments.

## Access

Existing login roles remain unchanged. An administrator grants **HR manager** or **Team manager** under HR → HR permissions. HR can maintain employees, private files and payroll. Team managers manage shifts, approve absences and review attendance for their assigned employees, excluding self-approval. Employees see their own records, documents, payroll and clock controls. Salaries and documents are protected by database/storage policies, not only hidden buttons.

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

`supabase/tests/hr-p1.sql` is a database integration test body. Execute **inside BEGIN / ROLLBACK**, after applying the migration in that same transaction when testing an unapplied release. It creates ephemeral auth/profile fixtures and tests real authenticated RLS, role escalation denial, private documents, leave approval, overlap checks, server clocking, immutable payroll, duplicate imports, partial/overpayments and audit. Never commit the fixture transaction.
