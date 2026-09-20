-- El precio que ve un cliente identificado se resuelve por categoría:
--   1. el precio pactado en su tarifa, si el producto figura en ella (Cat. C),
--   2. si no, Categoría B -> precio al detalle,
--   3. si no, precio grossiste (Categoría A).
-- Sigue sin exponer price_a, price_b, supplier_id ni location.
create or replace view public.catalog_products as
 SELECT p.id,
    p.name,
    p.reference,
    p.category,
    p.barcode,
    COALESCE(pli.unit_price,
             CASE WHEN mine.category = 'B' THEN p.sale_price_b ELSE p.sale_price END) AS sale_price,
    p.sale_price AS base_price,
    pli.unit_price IS NOT NULL AS contract_price,
    p.tax_rate,
    p.stock,
    p.photo_data,
    p.active,
    p.created_at,
    p.has_photo
   FROM products p
     LEFT JOIN LATERAL ( SELECT c.price_list_id, c.category
           FROM customers c
          WHERE c.active AND c.email IS NOT NULL AND lower(c.email) = lower(COALESCE(auth.jwt() ->> 'email'::text, ''::text))
          ORDER BY c.created_at, c.id
         LIMIT 1) mine ON true
     LEFT JOIN price_list_items pli ON pli.product_id = p.id AND pli.price_list_id = mine.price_list_id
  WHERE p.active IS TRUE AND private.current_user_role() IS NOT NULL;
