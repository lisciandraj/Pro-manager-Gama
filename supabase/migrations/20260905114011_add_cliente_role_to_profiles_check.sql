ALTER TABLE public.profiles DROP CONSTRAINT profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role = ANY (ARRAY['administrador'::text, 'comercial'::text, 'almacenero'::text, 'cliente'::text]));
