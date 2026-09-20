-- Evaluate actor/module permissions once per statement when listing or creating categories.
alter policy document_categories_read on public.document_categories using ((select private.service_access('documents')) or (select private.service_access('sav')));
alter policy document_categories_create on public.document_categories with check (((select private.service_access('documents')) or (select private.service_access('sav'))) and created_by=(select auth.uid()));
