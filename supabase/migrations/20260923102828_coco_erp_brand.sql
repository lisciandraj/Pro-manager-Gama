-- La aplicación se llama ahora Coco ERP. El modelo del correo de invitación
-- guarda su texto en la base: si todavía nombra Architect ERP (el texto por
-- defecto), se cambia el nombre; un texto redactado por la empresa sin esa
-- mención no se toca.
update public.access_invitation_template
   set subject=replace(subject,'Architect ERP','Coco ERP'),
       message=replace(message,'Architect ERP','Coco ERP'),
       version=version+1,updated_at=now()
 where subject like '%Architect ERP%' or message like '%Architect ERP%';
