-- gama_handle_new_user() es una función de disparador: sólo la llama el trigger
-- sobre auth.users. No tiene por qué estar expuesta como RPC en /rest/v1/rpc/.
revoke execute on function public.gama_handle_new_user() from anon, authenticated, public;

-- Misma higiene para el ayudante de rol: lo usan las políticas, no la API.
revoke execute on function private.is_staff() from anon, authenticated, public;
