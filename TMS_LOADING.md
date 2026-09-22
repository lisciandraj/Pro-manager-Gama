# Control de carga de expediciones

Al validar una expedición en Pedidos de venta, el flujo existente crea su entrega TMS y descuenta el stock una sola vez. El enlace «Ver carga en TMS» abre las líneas de esa expedición. También están disponibles en Entrega → Salida de bultos, incluidas las expediciones de fechas futuras.

El operario utiliza un lector USB/Bluetooth o la cámara y registra las unidades cargadas. Cada lectura propone una unidad; un lote puede indicar otra cantidad. El servidor compara el código guardado al crear la expedición y distribuye la cantidad entre las líneas del mismo producto y sus ubicaciones. Rechaza códigos ajenos y cantidades excesivas. Reintentar una petición no duplica el escaneo.

El peso y el volumen de la entrega los calcula el servidor al validar la expedición, a partir de `products.weight_g` y `products.volume_cm3` de las líneas expedidas. No proceden de lo que teclee un operario en la preparación; completar la ficha del producto es lo que corrige una carga sin peso o sin volumen.

El acceso sigue los perfiles actuales del TMS: administrador y almacenero. Se registra quién escanea y se selecciona el conductor al confirmar la salida. No se crea un nuevo perfil de transportista. Los clientes siguen consultando sus entregas y pruebas desde su portal.

El conductor y su vehículo **ya no se dan de alta aquí**: la persona vive en RRHH, el vehículo en Gestión de flota, y el emparejamiento de los dos en las afectaciones de Flota. El desplegable de salida lee `public.gama_tms_resources`, que devuelve sólo lo necesario para repartir —nombre, matrícula y capacidad— y está abierta a administración y almacén; el módulo de Flota sigue siendo únicamente del administrador. Un conductor sin vehículo asignado no aparece, y confirmar una salida sin él se rechaza con `DRIVER_REQUIRED`: el vehículo se asigna en Flota, no aquí.

La salida requiere todas las cantidades verificadas y una versión vigente del manifiesto. Escanear no genera movimientos de stock adicionales. Las correcciones requieren un motivo y conservan el historial; después de salir, la carga queda cerrada. La optimización de rutas conserva las expediciones que ya salieron.

Los controles SQL también bloquean el cambio directo de estado, el inicio de una ruta y el registro de una prueba de entrega antes de confirmar la salida. Las entregas que ya estaban en tránsito o entregadas al instalar la migración conservan su historial sin exigir escaneos retroactivos. Las nuevas expediciones requieren un código de barras de producto.

## Verificación

- `tests/sql/tms-loading.sql`: fixtures transaccionales con ROLLBACK, enlace automático al TMS, cantidades por línea, reintentos, correcciones, permisos, salida, bloqueo de rutas y pruebas, conservación de stock.
- `tests/tms-loading.spec.js`: interfaz, errores, cámara, reintentos, conductor, correcciones y móvil.
- Regresión de pedidos de venta y del módulo TMS en Playwright.

Las pruebas de cámara y lector simulan la lectura; no sustituyen una prueba con el dispositivo físico.

Si una expedición anterior no tenía código, completar el código en la ficha del producto y actualizar el control de carga. Se completan únicamente los códigos ausentes de expediciones pendientes; los códigos ya guardados no se sustituyen.
