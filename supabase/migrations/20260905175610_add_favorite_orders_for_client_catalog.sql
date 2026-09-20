CREATE TABLE public.favorite_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.favorite_order_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  favorite_order_id uuid NOT NULL REFERENCES public.favorite_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id),
  quantity numeric NOT NULL CHECK (quantity > 0)
);

ALTER TABLE public.favorite_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorite_order_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY favorite_orders_select ON public.favorite_orders
  FOR SELECT USING (created_by = (SELECT auth.uid()));
CREATE POLICY favorite_orders_insert ON public.favorite_orders
  FOR INSERT WITH CHECK (created_by = (SELECT auth.uid()));
CREATE POLICY favorite_orders_delete ON public.favorite_orders
  FOR DELETE USING (created_by = (SELECT auth.uid()));

CREATE POLICY favorite_order_lines_select ON public.favorite_order_lines
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.favorite_orders f WHERE f.id = favorite_order_lines.favorite_order_id AND f.created_by = (SELECT auth.uid())));
CREATE POLICY favorite_order_lines_insert ON public.favorite_order_lines
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM public.favorite_orders f WHERE f.id = favorite_order_lines.favorite_order_id AND f.created_by = (SELECT auth.uid())));
CREATE POLICY favorite_order_lines_delete ON public.favorite_order_lines
  FOR DELETE USING (EXISTS (SELECT 1 FROM public.favorite_orders f WHERE f.id = favorite_order_lines.favorite_order_id AND f.created_by = (SELECT auth.uid())));
