-- El precio que ve un cliente identificado:
--   1. su precio negociado para ese producto (tarifa especial),
--   2. si no, Categoría B -> precio al detalle,
--   3. si no, precio mayorista (Categoría A).
-- Sigue sin exponer purchase_price, supplier_id ni location.
create or replace view public.catalog_products as
 SELECT p.id,
    p.name,
    p.reference,
    p.category,
    p.barcode,
    COALESCE(csp.unit_price,
             CASE WHEN mine.category = 'B' THEN p.sale_price_b ELSE p.sale_price END) AS sale_price,
    p.sale_price AS base_price,
    csp.unit_price IS NOT NULL AS contract_price,
    p.tax_rate,
    p.stock,
    p.photo_data,
    p.active,
    p.created_at,
    p.has_photo
   FROM products p
     LEFT JOIN LATERAL ( SELECT c.id, c.category
           FROM customers c
          WHERE c.active AND c.email IS NOT NULL AND lower(c.email) = lower(COALESCE(auth.jwt() ->> 'email'::text, ''::text))
          ORDER BY c.created_at, c.id
         LIMIT 1) mine ON true
     LEFT JOIN customer_special_prices csp ON csp.product_id = p.id AND csp.customer_id = mine.id
  WHERE p.active IS TRUE AND private.current_user_role() IS NOT NULL;
