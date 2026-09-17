# GAMA — Contabilidad para equipos pequeños

Producción: `lisciandraj/Pro-manager-Gama`, proyecto `mknsaibrewksgomuslev`.

El módulo responde a siete preguntas de dirección: cuánto vendemos, cuánto
gastamos, qué nos deben, qué debemos, cuánta tesorería hay, cuántos impuestos
hemos registrado y cuál es el resultado. No pretende sustituir al software
contable o de facturación electrónica que exija la ley de cada país.

## Acceso

**Administración → Contabilidad**. Trece secciones: Vista general, Ventas,
Compras, Gastos, Pagos, Banco y caja, Cuentas por cobrar, Cuentas por pagar,
Contabilidad, Impuestos, Informes, Cierres y Parámetros.

Por defecto el administrador tiene acceso completo, el comercial ve sólo su lado
—vista general sin tesorería ni impuestos, ventas, cuentas por cobrar e
informe de resultados— y ni logística ni cliente entran. Los siete permisos
(consultar, crear, modificar, eliminar, validar, exportar y cerrar) se ajustan
por usuario en **Contabilidad → Parámetros**, y una fila propia sustituye al
valor por defecto del perfil. Quien puede crear, validar o cerrar ve el libro
entero; quien sólo consulta se queda en el perímetro comercial.

## De dónde salen los datos

Nada se vuelve a teclear. El módulo lee la cadena que ya existe en GAMA:

    CRM → presupuesto → pedido → reserva → preparación → expedición →
    entrega → factura → cobro → contabilidad

Las facturas de venta y los cobros los siguen escribiendo Ventas y Pagos de
clientes. Contabilidad los recoge y genera su asiento: al abrir el módulo se
ejecuta una puesta al día idempotente, y el botón «Contabilizar ahora» del
libro la fuerza. Ninguna ruta de escritura de los módulos comerciales cambia.

Sólo se captura aquí lo que no tenía sitio en ninguna pantalla:

- **Gastos**, con categoría, proyecto, medio de pago y hasta cuatro
  justificantes (PDF, JPG, PNG o WebP de 2 MB).
- **Facturas de proveedor** y sus pagos. Los pedidos de compra siguen en
  Compras; la factura recibida es lo que crea la deuda y mueve la tesorería.
- **Cuentas de banco y caja**, con saldo inicial y saldo actual calculado.
- **Movimientos bancarios** importados en CSV, para conciliar.
- **Asientos manuales** para lo que no nace de un documento.

## Asientos automáticos

| Documento | Debe | Haber |
|---|---|---|
| Factura de venta | Clientes (total) | Ventas (neto) · Impuesto recaudado |
| Cobro de cliente | Banco o caja | Clientes |
| Factura de proveedor | Compras (neto) · Impuesto deducible | Proveedores |
| Pago a proveedor | Proveedores | Banco o caja |
| Gasto | Categoría (neto) · Impuesto deducible | Banco, caja o proveedores |

El lado neto se deriva del total menos el impuesto, nunca de una suma que
pudiera desviarse un céntimo: el asiento cuadra por construcción. Las cuentas
utilizadas son configurables en Parámetros; el plan contable que se entrega es
deliberadamente neutro y no impone ninguna numeración nacional.

## Integridad

- Cada operación financiera es una sola transacción: pago, saldo, asiento,
  cuenta bancaria y auditoría entran juntos o no entra ninguno.
- Un asiento contabilizado no se modifica ni se borra: se **contrapasa**, y los
  dos quedan en el libro. Un gasto en borrador sí puede eliminarse.
- `débito = crédito` se comprueba con un *constraint trigger* diferido: un
  asiento descuadrado no llega a existir.
- Un **periodo cerrado** rechaza cualquier asiento nuevo, modificado o
  eliminado en esas fechas. Reabrirlo exige el permiso de cierre y un motivo,
  y queda registrado con el verbo `REOPEN_PERIOD`.
- Las claves de idempotencia (`request_key`) hacen que reintentar un gasto, una
  factura o un pago no lo duplique.
- La auditoría usa el histórico compartido `gama_audit`, ampliado con los verbos
  `VALIDATE`, `CANCEL`, `PAYMENT`, `RECONCILIATION`, `CLOSE_PERIOD` y
  `REOPEN_PERIOD` para los hechos que no son un cambio de fila.

## Conciliación bancaria

El CSV admite separador `;` o `,`, fecha `AAAA-MM-DD` o `DD/MM/AAAA`, y decimal
con coma o punto. Una línea ya importada no se duplica. GAMA **propone**
correspondencias puntuadas por importe, fecha y nombre; nunca concilia solo.

## Divisa

`gama-currency.js` es el único formateador de importes de toda la aplicación.
Lee `company_settings.currency`, lo cachea en el navegador y emite
`gama:currency-change` al cambiar. Ningún módulo escribe ya un símbolo a mano:
Pagos, RRHH, Operaciones, Matriz, Informe de ventas, Archivo de facturas,
Compras, Preparación y los tres generadores de PDF pasan por `formatCurrency`.
Si la empresa es USD se ve `$2.500,00`; si pasa a EUR, `€2.500,00`, sin tocar
ningún importe guardado.

## Integraciones

- **Centro de acción**: factura de proveedor vencida, gasto sin justificante,
  movimiento bancario sin conciliar y asiento descuadrado entran en el flujo de
  alertas existente en vez de abrir un segundo buzón.
- **Búsqueda global**: gastos, facturas de proveedor, movimientos bancarios y
  asientos, con los permisos del usuario.
- **Asistente IA**: las tablas del módulo están en su catálogo, bajo las mismas
  reglas de acceso.
- **Proyectos**: `private.gama_accounting_project_pl` devuelve presupuesto,
  gasto comprometido, gasto real, ingresos y margen de un proyecto.

## Verificación

- `tests/accounting.spec.js`: panel y formato de divisa, cambio a euros,
  antigüedad de saldos, estados de pago (no pagada / parcial / pagada), captura
  de un gasto con total calculado, asiento manual bloqueado mientras no cuadra,
  previsión etiquetada como previsión, avisos fiscales, cloisonnement del perfil
  comercial, mensaje de error legible, importación CSV, francés e inglés, y las
  cuatro anchuras (móvil, tableta vertical y horizontal, escritorio).
- Comprobaciones SQL ejecutadas contra la base dentro de `BEGIN; … ROLLBACK;`:
  factura de proveedor con pago parcial y completo, rechazo del sobrepago,
  gasto contabilizado, `débito = crédito` en todo el libro, saldo de caja,
  asiento descuadrado rechazado, contrapaso, importación bancaria idempotente,
  sugerencia y conciliación, bloqueo del periodo cerrado, reapertura auditada,
  y el perímetro de los perfiles comercial y almacenero.

## Despliegue

Migración aditiva `20260917150000_accounting_module.sql`. No modifica ninguna
tabla, importe ni flujo existente; sólo añade `financial_account_id` a
`external_invoice_payments` para poder atribuir un cobro a una cuenta, y amplía
el `CHECK` de `gama_audit.action`. En producción se aplicó por partes
(`accounting_module`, `…_api`, `…_api2`, `…_api3`, `…_integrations` y los
correctivos `alias_shadowing`, `revenue_report_grouping`, `audit_business_actions`,
`period_audit_verbs`, `permissions_audit_key`); el archivo del repositorio ya
incorpora esos correctivos, de modo que una instalación nueva llega al mismo
estado en un solo paso.

Recuperación: corregir hacia delante. Nunca borrar un asiento contabilizado ni
un pago para «arreglar» un saldo; contrapasar y volver a registrar.

## Lo que este módulo no es

No emite documentos fiscales, no presenta declaraciones y no sustituye a un
software de facturación electrónica ni a la contabilidad legal allí donde la
normativa exige un sistema homologado. Las cifras de impuestos y el balance son
estimaciones internas de gestión, y las pantallas lo dicen.
