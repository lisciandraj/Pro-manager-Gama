ALTER TABLE public.customer_requests ADD COLUMN IF NOT EXISTS requester_name text;
ALTER TABLE public.customer_requests ADD COLUMN IF NOT EXISTS requester_email text;

UPDATE public.customer_requests cr
SET requester_name = p.full_name,
    requester_email = u.email
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
WHERE cr.created_by = p.id
  AND cr.requester_name IS NULL;
