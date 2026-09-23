-- Seguimiento de procesos lee la referencia del proceso que lleva la prueba de
-- entrega (erp_reference). Las pruebas se leen por tms_proofs_read, la vista
-- que sirve la foto; la vista es anterior a la columna y no la tenía, así que
-- toda venta con una entrega creada —justo después de la preparación— dejaba
-- de abrirse. La misma vista, con la columna al final.
create or replace view public.tms_proofs_read with(security_invoker=true) as
 select p.delivery_id,private.document_proof_photo(p.delivery_id) photo,p.signature,p.captured_at,p.captured_by,p.erp_reference
 from public.tms_proofs p;
revoke all on public.tms_proofs_read from anon,authenticated;
grant select on public.tms_proofs_read to authenticated;
