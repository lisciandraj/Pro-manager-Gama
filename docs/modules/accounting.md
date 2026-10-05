> État relu le 30 septembre 2026. La comptabilité de gestion intègre aussi un onglet SRI. La préparation fiscale est séparée des écritures internes ; la disponibilité réelle du signataire privé et la validation SRI ne sont pas déduites de la présence du module.

# Coco ERP — Contabilidad para equipos pequeños

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

## Exportación

Cada pantalla exporta su propia lista en CSV, respetando el filtro activo y el
permiso de exportar del usuario.

La **copia de seguridad Excel** de Informes lleva además las quince tablas
contables completas, en su propia hoja «Contabilidad»: plan de cuentas,
diarios, asientos y sus líneas, periodos, permisos, impuestos, cuentas
financieras, movimientos de banco, conciliaciones, gastos y sus categorías,
facturas de proveedor y sus pagos. Los justificantes adjuntos quedan fuera,
como el resto de binarios de GAMA: una celda de Excel se corta a 32 767
caracteres y el libro anuncia ese límite en su resumen. Los parámetros de la
empresa —divisa, país, inicio del ejercicio y las cuentas por defecto— viajan
en la hoja «Configuración», que es donde vive `company_settings`.

## Alcance fiscal

La contabilidad de gestión no sustituye la validación fiscal. El apartado SRI implementa un flujo separado de emisión; su uso depende de la configuración del signatario privado y de los controles descritos en [SRI](sri.md). Un documento interno no se convierte en una factura fiscal autorizada por existir en el ERP.

## Mise à niveau Équateur du 2 octobre 2026

**Comptabilité → Comptabilité / Rapports / Impôts / Paramètres → Livres et outils pour l’Équateur** ouvre la balance, le grand livre, les tiers, l’analytique par projet, les échéances, les ajustements, les retenues documentées, la revue fiscale, les immobilisations et les liens avec paie et stock. L’onglet Facturation SRI reste distinct ; il y a actuellement quatorze sections.

Les nouvelles factures, règlements, dépenses et retours sont comptabilisés dans la transaction métier. La synchronisation à l’ouverture sert à la reprise des anciens documents et respecte les mois fermés. Le registre fiscal reçoit les données de justificatifs existants ; son enregistrement ne modifie pas l’état d’autorisation SRI.

La clôture annuelle transfère le résultat à la réserve configurée et ferme les douze mois. Les écritures provenant d’un document s’annulent depuis leur module d’origine, afin de conserver la cohérence du solde commercial et du livre. Les écritures manuelles peuvent être contrepassées.

Le [rapport de comparaison](../audits/2026-10-02-accounting-ecuador.md) décrit les fonctions existantes conservées, les ajouts, les contrôles et les limites restantes. Le [mode d’emploi](accounting-ecuador-guide.md) explique l’ordre des réglages. Ne pas confondre un brouillon ATS valide selon le XSD avec une déclaration déposée ou une validation fiscale complète.

## Retenciones recibidas, ATS y preparación 103/104

En **Libros y herramientas de Ecuador → Abonos y retenciones**, «Importar retención XML del cliente» consulta la clave ante el SRI. Solo el XML autorizado devuelto por el SRI aporta los importes. El RUC emisor y los números fiscales identifican las facturas; un comprobante con varias facturas se aplica en una transacción. El archivo se conserva en el depósito privado. Reimportarlo no duplica la retención. No se crea un ingreso bancario. Se necesitan el trabajador SRI privado configurado y cuentas de activo para IR e IVA recibidos. Se admiten comprobantes 07 versiones 1.0.0 y 2.0.0 nacionales contra facturas 01.

La revisión fiscal incorpora créditos y débitos de clientes y proveedores; las notas 04 y liquidaciones 03 autorizadas en GAMA completan sus datos desde el documento emitido. Los documentos externos requieren revisión, incluyendo el comprobante original modificado. El ATS incorpora retenciones IR, IVA 10/20/30/50/70/100, créditos y anulaciones documentadas. Una retención de cliente recibida este mes puede referir a una venta anterior, sin repetir su facturación. No se inventa una anulación por un rechazo, timeout o cancelación interna. Las bajas en el portal SRI quedan documentadas y excluidas del ATS. Los establecimientos activos se configuran por código, incluyendo los que no vendieron.

**Formularios 103 y 104** prepara los importes del mes desde las escrituras: IVA generado y deducible, IVA recibido de clientes, IVA retenido a proveedores y retenciones IR por concepto. El factor de crédito y el saldo del mes anterior se revisan antes de exportar. El IVA propio y el IVA retenido como agente se muestran separados. La preparación y el ATS son borradores; no presentan ni reemplazan la revisión del formulario vigente. Operaciones extranjeras y especiales requieren datos adicionales y permanecen señaladas para revisión.

Fuentes revisadas el 4 de octubre de 2026: [ATS y catálogos vigentes](https://www.sri.gob.ec/formularios-e-instructivos1), [formularios e instructivos](https://www.sri.gob.ec/web/intersri/formularios-e-instructivos). El XSD ATS descargado coincide con el fixture del repositorio. Pruebas: `tests/sri-received-db.test.cjs`, `tests/sri-received-edge.test.cjs`, `tests/test_sri_received.py` y `tests/accounting-ats.test.cjs`.

## Extractos bancarios y cobros revisados

Banco y caja importa CSV con cabeceras de fecha/fecha valor, referencia/documento,
descripción/detalle e importe/valor, o columnas débito/crédito. Admite comas,
punto y coma, tabuladores, BOM, comillas escapadas y descripciones multilínea.
La fecha valor tiene prioridad cuando está presente. Un selector decimal resuelve
importes ambiguos; los importes se validan en céntimos y las fechas inexistentes,
filas inválidas o más de 1000 movimientos bloquean la importación completa. No se
eliminan filas silenciosamente. Cada cuenta debe estar activa, tener cuenta
contable y utilizar la moneda de la empresa. La importación no registra dinero.

`gama_bank_invoice_action` propone cobros/pagos ya registrados y facturas con
saldo suficiente. Se puede buscar una factura por cliente o referencia. El
responsable revisa y confirma: para una factura crea un cobro real, lo aplica
contra la cartera canónica y concilia el recibo con el extracto en una sola
transacción. Reintentos y confirmaciones simultáneas sobre el mismo movimiento
conservan un recibo, una aplicación y una asociación. Un saldo cambiado o periodo
cerrado revierte toda la operación. El cliente nunca decide el importe del cobro:
se obtiene del movimiento bancario bloqueado.

Deshacer retira la asociación con el extracto y conserva el cobro/pago. Para
corregir el dinero se revisa y anula el documento original. Una aplicación de
anticipo nunca se propone como otro ingreso bancario. Los importes importados
no finitos se rechazan también por el endpoint compatible anterior.

Estas cabeceras cubren exportaciones comunes; no se declara un formato
propietario bancario certificado. Un extracto Excel/PDF necesita exportarse como
CSV. Los cargos negativos concilian con pagos/gastos existentes; no se inventa
un gasto ni una factura a partir de la descripción del banco.

Pruebas: `tests/bank-statement.test.cjs`, `tests/bank-invoice-db.test.cjs` y
`tests/accounting.spec.js`. El esquema completo se restaura en una base aislada;
los tests verifican caja y asientos reales, reversión por cierre, idempotencia,
filas inválidas, acceso y datos conservados tras un fallo de validación.
