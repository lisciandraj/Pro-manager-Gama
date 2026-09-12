# GAMA — dossier, preparación, embalaje, acuerdos y retornos

Producción: `lisciandraj/Pro-manager-Gama`, proyecto `mknsaibrewksgomuslev`.

## Acceso y uso

**Ventas → Pedidos de venta → Ver pedido** contiene el dossier completo, con la
siguiente acción, responsable, vínculos a solicitud/presupuesto, reservas,
preparaciones, bultos, expediciones, pruebas, facturas externas y cobros.
Los almaceneros siguen ejerciendo también como conductores. No se añade un rol.

1. Aceptar un presupuesto o confirmar un pedido crea automáticamente una
   preparación pendiente. «Iniciar preparación» asigna un operario y toma una
   instantánea de las reservas disponibles por ubicación. También se puede
   iniciar una nueva preparación después de una cancelación.
2. «Escanear recogida» exige el código de ubicación y el código del producto.
   Admite lector USB/Bluetooth o cámara. La recogida traslada físicamente la
   cantidad a una zona PR de ese almacén, conservando su reserva. Los totales de
   stock no cambian. Los faltantes/daños quedan registrados con motivo; requieren
   revisión de inventario, no se convierten silenciosamente en ajustes.
3. «Crear bulto» vuelve a verificar el producto e incorpora cantidades,
   peso y dimensiones. Un pedido puede tener varios bultos, cada uno con etiqueta
   Code 39 PK imprimible y contenido exacto. Antes de validar se puede anular un
   bulto con motivo y volver a embalar sus cantidades.
4. «Validar embalaje» exige que todo lo recogido esté embalado. Una salida
   parcial requiere motivo y respeta los acuerdos del cliente. «Preparar /
   expedir» despacha exactamente el contenido validado, sin cantidades libres.
   La salida de stock sigue ocurriendo al validar esa expedición. El TMS exige
   después escanear **los productos** cargados y confirmar el conductor/vehículo.
   Las etiquetas PK identifican bultos; no sustituyen los escaneos de producto TMS.
5. El reliquat permanece en el pedido y genera otra preparación. Cancelar una
   preparación devuelve sus productos a las ubicaciones originales y conserva
   las reservas del pedido. Cancelar el pedido también libera esas reservas,
   siempre sujeto a los controles existentes de documentos ya emitidos.

## Faltantes y acuerdos

El dossier distingue cantidades pedidas, reservadas y faltantes, compras entrantes
compartidas y fecha acordada. Una fecha de compra es indicativa, no una promesa.

El comercial propone espera completa, entrega parcial o sustitución. El cliente
responde en **Presupuestos → Opciones de entrega**. Admin/comercial también puede
registrar la respuesta externa, con referencia obligatoria. Aceptar una opción
retira las otras propuestas pendientes de la misma línea.

La cantidad de una entrega parcial limita el próximo envío; una vez consumida,
el resto sigue pendiente. Espera completa impide validar una preparación parcial.
La sustitución requiere stock todavía no reservado, una línea no facturada y
ninguna recogida activa: evita invalidar mercancía preparada. Conserva el original
a cantidad cero cuando se reemplaza íntegramente, registra el precio/IVA aceptado
y reserva el reemplazo disponible. El presupuesto aceptado permanece inmutable.

## Retornos

Registrar retorno/rechazo no cambia stock. Cada registro se vincula a una línea
expedida y la suma de retornos no puede superar su cantidad. Para distintas
condiciones físicas, dividir la cantidad entre varios registros.

«Recibir en cuarentena» confirma el retorno físico y bloquea toda la cantidad
para venta. Tras inspección: reintegrar en una ubicación vendible, dar de baja o
crear un pedido de cambio del mismo producto/cantidad sin cobro, reintegrando
la mercancía conforme o dando de baja la no conforme.
El pedido de cambio queda vinculado y sigue el picking/packing/TMS normal.
Un reemplazo comercial diferente se acuerda en un pedido/devis separado.
Se conservan motivos e historial.

Hasta cuatro fotos de 2 MB por retorno, descargadas solo al abrirlas. Los abonos
emitidos externamente se vinculan con factura, número e importe; no emiten
comprobantes fiscales ni alteran cobros bancarios o asientos contables.

## Integridad

Migración aditiva `20260912145342_fulfillment_p1.sql`. Ejecutarla antes de publicar
los loaders nuevos. No cambia cantidades ni reservas de documentos existentes;
crea preparaciones pendientes para los pedidos confirmados con cantidades abiertas.

Las operaciones comparten el bloqueo transaccional comercial, verifican perfiles
en servidor y guardan claves de idempotencia con huella SHA-256 del payload.
Las tablas expuestas tienen RLS y SELECT; los cambios pasan por RPC públicas
invoker e implementaciones privadas. Un cliente solo consulta/responde a sus
propias propuestas, mediante la identidad verificada ya usada por el portal.
El API antiguo de expedición también exige embalaje. La liberación genérica de
reservas no permite abrir cuarentena ni mercancía ya recogida.

## Verificación y recuperación

- `tests/fulfillment.spec.js`: escaneos, reintentos, embalaje, salida controlada,
  propuesta, recepción/inspección, portal y móvil.
- `tests/sql/fulfillment-p1.sql`: reservas, doble clic, staging, límites, acuerdos,
  sustitución autorizada, cuarentena, inspección, cambio, baja, cancelación y RLS.
- Suites SQL de ventas, cadena comercial y TMS: cargar primero
  `tests/sql/fulfillment-test-helpers.sql` en la misma transacción. Ese helper crea
  la preparación por las API públicas; solo existe durante la prueba.
- Ejecutar cada suite dentro de `BEGIN; … ROLLBACK;`. Si se concatenan suites,
  limpiar entre ellas `request.jwt.claim.sub` y `request.jwt.claims`, además de
  `RESET ROLE`. No se conservan fixtures; las secuencias existentes pueden avanzar.
- Tests de interfaz: `npm test`. Los escaneos/cámara se simulan: la validación con
  lector físico y cámara de iPhone debe hacerse con los dispositivos del almacén.

Recuperación: conservar tablas e historial y corregir hacia delante. No volver a
un frontend que despacha sin preparar: el nuevo servidor rechazará esas llamadas.
Nunca eliminar reservas o retornar mercancía como atajo de rollback técnico.

Los avisos de seguridad previos relativos a vistas catálogo/equipo, funciones
legacy de inventario y protección de contraseñas no son introducidos por este
módulo. La nueva API no concede ejecución anónima.
