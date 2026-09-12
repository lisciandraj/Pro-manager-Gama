# Control de carga de expediciones

Al validar una expedición en Pedidos de venta, el flujo existente crea su entrega TMS y descuenta el stock una sola vez. El enlace «Ver carga en TMS» abre las líneas de esa expedición. También están disponibles en TMS → Control de carga, incluidas las expediciones de fechas futuras.

El operario utiliza un lector USB/Bluetooth o la cámara y registra las unidades cargadas. Cada lectura propone una unidad; un lote puede indicar otra cantidad. El servidor compara el código guardado al crear la expedición y distribuye la cantidad entre las líneas del mismo producto y sus ubicaciones. Rechaza códigos ajenos y cantidades excesivas. Reintentar una petición no duplica el escaneo.

El acceso sigue los perfiles actuales del TMS: administrador y almacenero. Se registra quién escanea y se selecciona el conductor activo y su vehículo al confirmar la salida. No se crea un nuevo perfil de transportista. Los clientes siguen consultando sus entregas y pruebas desde su portal.

La salida requiere todas las cantidades verificadas y una versión vigente del manifiesto. Escanear no genera movimientos de stock adicionales. Las correcciones requieren un motivo y conservan el historial; después de salir, la carga queda cerrada. La optimización de rutas conserva las expediciones que ya salieron.

Los controles SQL también bloquean el cambio directo de estado, el inicio de una ruta y el registro de una prueba de entrega antes de confirmar la salida. Las entregas que ya estaban en tránsito o entregadas al instalar la migración conservan su historial sin exigir escaneos retroactivos. Las nuevas expediciones requieren un código de barras de producto.

## Verificación

- `tests/sql/tms-loading.sql`: fixtures transaccionales con ROLLBACK, enlace automático al TMS, cantidades por línea, reintentos, correcciones, permisos, salida, bloqueo de rutas y pruebas, conservación de stock.
- `tests/tms-loading.spec.js`: interfaz, errores, cámara, reintentos, conductor, correcciones y móvil.
- Regresión de pedidos de venta y del módulo TMS en Playwright.

Las pruebas de cámara y lector simulan la lectura; no sustituyen una prueba con el dispositivo físico.
