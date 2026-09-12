# Identidad de productos e importación de fotos

La creación y edición rechazan un nombre, código de barras o referencia que ya pertenezca a otro producto, incluso archivado. Se ignoran mayúsculas y espacios repetidos o en los extremos; no se eliminan los acentos ni la puntuación de los identificadores. Las referencias opcionales vacías no colisionan.

Los duplicados anteriores a la instalación se conservan con su historial. Se puede cambiar su precio, foto y demás datos, o corregir sus identificadores, pero no añadir otro producto al grupo duplicado. No hay fusiones ni eliminaciones automáticas. El control definitivo está en PostgreSQL y protege también importaciones y escrituras simultáneas. Un registro privado con clave única mantiene los identificadores y sus titulares históricos; el trigger se ejecuta en la misma transacción que el producto y no es invocable desde la API. Archivar conserva las claves; una eliminación física autorizada libera únicamente las claves que ya no tienen titulares.

## Importar fotos

En **Importar datos → Fotos de productos**, selecciona las imágenes y revisa la correspondencia antes de pulsar **Importar fotos**. Ejemplos para el producto `Tornillo hexagonal`, referencia `SKU-001`:

- `SKU-001.jpg`
- `Tornillo hexagonal.png`
- `SKU-001 Tornillo hexagonal frente.jpg`

Se reconocen mayúsculas, acentos y separadores habituales. Se comparan identificadores completos, no fragmentos de otro código (`SKU-0010` no es `SKU-001`). La referencia exacta o el nombre exacto únicos tienen prioridad; en títulos compuestos se cruzan referencia y nombre. Una coincidencia ambigua o contradictoria se rechaza. Añadir ambos datos puede distinguir productos históricos con referencia duplicada. Si dos archivos coinciden con un producto, sólo el primero se admite. La opción **Conservar las fotos que ya existen** evita reemplazarlas. Se consulta todo el catálogo por páginas, sin descargar las fotos existentes.

## Instalación y pruebas

Aplicar `supabase/migrations/20260911212417_product_identity_guard.sql` antes de publicar la interfaz. No modifica los productos existentes. Las pruebas de base `tests/sql/product-identity.sql` se ejecutan dentro de `BEGIN; … ROLLBACK;`; verifican creación, edición, archivo, liberación de claves, duplicados históricos, permisos y consistencia del registro.

Pruebas de interfaz: `npx playwright test tests/product-identity.spec.js tests/photo-import.spec.js tests/excel-import.spec.js tests/product-supplier.spec.js`. La importación Excel cuenta como omitidas las filas rechazadas por duplicado y muestra los errores de las primeras diez filas fallidas; sólo cuenta escrituras confirmadas como importadas.
