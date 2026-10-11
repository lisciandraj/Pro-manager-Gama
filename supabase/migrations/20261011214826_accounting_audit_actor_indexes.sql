-- Cover actor references on the new accounting audit tables.
create index accounting_asset_event_actor on private.accounting_asset_events(created_by);
create index accounting_binding_actor on private.accounting_bank_bindings(assigned_by);
create index accounting_statement_actor on private.accounting_bank_statements(updated_by);
create index accounting_budget_actor on private.accounting_budgets(updated_by);
create index accounting_closure_actor on private.accounting_closure_reviews(reviewed_by);
create index accounting_fx_document_actor on private.accounting_fx_documents(created_by);
create index accounting_fx_settlement_actor on private.accounting_fx_settlements(created_by);
create index accounting_dimension_actor on private.accounting_line_dimensions(assigned_by);
create index accounting_readiness_actor on private.accounting_readiness(verified_by);
