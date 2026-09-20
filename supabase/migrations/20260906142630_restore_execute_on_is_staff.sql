-- Las políticas RLS se evalúan con los privilegios de quien consulta: si
-- authenticated no puede ejecutar private.is_staff(), toda lectura de products
-- y stock_movements falla con "permission denied for function". El esquema
-- private no está expuesto por PostgREST, así que este GRANT no crea ninguna
-- superficie de API: es exactamente lo que ya ocurre con
-- private.current_user_role().
grant execute on function private.is_staff() to authenticated;
