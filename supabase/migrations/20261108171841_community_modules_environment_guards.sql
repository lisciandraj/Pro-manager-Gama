-- Apply the existing server-verified development/admin restriction to every
-- RLS table introduced by the sales/accounting extensions. This assigns no
-- environment, activates no provider and changes no business record.
select private.coco_install_environment_policies();
