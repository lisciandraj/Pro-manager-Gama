# GAMA · Módulo CRM

Estado del módulo, para quien lo herede. Lo que sigue describe lo que hay, no
lo que se planeó.

## Qué es y qué NO es

El CRM es **un módulo nativo de GAMA**, no una aplicación aparte. Reutiliza la
base, la autenticación, los usuarios, los perfiles, los clientes, los productos
y los presupuestos que ya existían. No hay segunda tabla de clientes, ni
segundo login, ni segundo numerador de documentos.

Una sola tarjeta en el menú (`CRM`), y dentro siete pantallas.

## Las pantallas

| Pantalla | Archivo | Qué contesta |
|---|---|---|
| Cuadro de mando | `gama-crm-core.js` | ¿Cómo va el embudo hoy? |
| Prospectos | `gama-crm-leads.js` | ¿A quién todavía no le hemos vendido? |
| Oportunidades | `gama-crm-opportunities.js` | ¿Qué ventas hay en curso, y en qué etapa? |
| Actividades | `gama-crm-activities.js` | ¿Qué se ha hecho y qué falta por hacer? |
| Contactos | `gama-crm-contacts.js` | ¿Con quién se habla en cada empresa? |
| Informes | `gama-crm-reports.js` | ¿De dónde vienen las ventas y por qué se pierden? |
| Objetivos | `gama-crm-targets.js` | ¿Cuánto hay que vender, y cuánto se lleva? |

`gama-crm-scoring.js` no es una pantalla: es el motor de puntuación y el
enchufe de IA. Ver más abajo.

## El armazón

`gama-crm-core.js` es el núcleo. Tiene tres trabajos:

1. **La capa de datos.** Las columnas de cada tabla escritas UNA vez (`cols`),
   los referenciales cacheados por sesión, y los contadores del cuadro de
   mando. Dos reglas que hace cumplir:
   - Nunca se pide `*`. `products` guarda la foto en base64 y una lista que
     pide todo se trae el catálogo entero de fotos. Ya costó una regresión en
     Compras.
   - Nunca se cuenta trayéndose las filas. Los KPI usan `count:'exact'` con
     `head:true`.

2. **El registro de pantallas.** `CRM.registrar(id, etiqueta, abrir)`. La barra
   de navegación se pinta sola. Añadir la séptima pantalla es una línea.

3. **Las piezas compartidas** (`CRM.util`): formularios, fechas, textos sin
   acentos, avisos. Y la hoja de estilo de todas las listas, que vive aquí y no
   en la primera pantalla que la necesitó — si vive en una pantalla, abrir otra
   primero la deja sin estilo.

## Las reglas viven en la base

Las validaciones de pantalla existen para explicar en castellano lo que la base
va a rechazar, no para sustituirla. Dos pestañas abiertas se saltan cualquier
validación de formulario; no se saltan un CHECK.

| Regla en la base | Lo que hace la pantalla |
|---|---|
| `crm_leads_convertido_coherente` | «Convertido» no está en el desplegable de estado: se llega ahí sólo por el botón de convertir, que crea el cliente. |
| `crm_leads_con_nombre` | Se exige empresa, nombre o apellidos antes de enviar. |
| `crm_contacts_uno_u_otro` | Cambiar de tipo de ficha pone a `null` el enlace anterior. |
| `crm_contacts_principal_*_idx` | Marcar un principal se lo quita al anterior en el mismo gesto. |
| `crm_opp_uno_u_otro` | Igual que en contactos. |
| `crm_opp_perdida_con_motivo` | Mover a «Perdido» pregunta el motivo ANTES de mover. |
| `crm_opp_no_ganada_y_perdida` | Reabrir una cerrada limpia el sello anterior. |
| `crm_act_colgada_de_algo` | Se exige elegir la ficha de la que cuelga. |
| `crm_act_pendiente_con_fecha` | Una pendiente sin fecha se rechaza y se explica. |
| `crm_leads_score_check` | La puntuación se recorta a 100 y se dice. |
| `crm_targets_persona_idx` / `_empresa_idx` | Volver a fijar el objetivo de un periodo ya fijado lo CORRIGE, no crea un segundo. |

Dos cosas que el navegador **no calcula nunca**:

- `crm_opportunities.reference` — la pone una secuencia de Postgres. Compras la
  calcula con `max()+1` en el cliente y dos pestañas dan el mismo número.
- `crm_opportunities.weighted_amount` — columna calculada. Se cambia la
  probabilidad y la base recalcula.

## Permisos

RLS sobre el par `('administrador','comercial')`, el mismo que ya usaba
`customer_special_prices`. No se inventaron perfiles nuevos, así que ninguna
política existente se tocó.

La única excepción es `crm_team`: una vista de solo lectura sobre `profiles`,
porque `profiles_self_read` sólo deja leer la fila propia y un comercial no
podía poner nombre al responsable de un prospecto ajeno. Ver
`supabase-migration-2026-09-crm-team.sql` — incluye por qué se concede `SELECT`
y nada más.

## Objetivos

`crm_targets` guarda cuánto tiene que vender cada comercial —o la empresa
entera, con `profile_id` nulo— en un mes, un trimestre o un año. Lo conseguido
se cuenta con la MISMA definición que en Informes: por fecha de **cierre** de
la oportunidad ganada. Si las dos pantallas contaran distinto, dirección y
comercial acabarían discutiendo sobre dos números que se llaman igual.

El formulario sólo se le enseña al administrador. Eso es una **comodidad de
pantalla, no una frontera de seguridad**: la política RLS de `crm_targets`
admite escribir a los dos perfiles comerciales, como en el resto del CRM. Si
los objetivos tienen que ser sólo del administrador de verdad, es una migración
que cambia la política, no un `if` en el navegador.

Aquí sí se borra, y es lo correcto: un objetivo es una decisión, no un hecho
ocurrido. Retirarlo no pierde trazabilidad de nada — lo vendido sigue en las
oportunidades.

## El ciclo, de punta a punta

```
Prospecto  --convertir-->  Cliente (customers, la tabla de siempre)
    |                          |
    +--> Oportunidad <---------+
             |
             +--> Productos (crm_opportunity_lines) --> mandan sobre el importe
             |
             +--> Presupuesto (invoices + invoice_lines, las de siempre)
```

El presupuesto se escribe con el mismo `GAMA_META` en las notas que usa
Solicitudes de clientes, así que se sabe de dónde salió cada documento.
`line_total` va SIN IVA, para que la suma de las líneas sea exactamente el
subtotal: es como lo leen el archivo, el PDF y el informe de ventas.

## Puntuación e IA

**La puntuación es real y determinista.** Las reglas viven en
`crm_scoring_rules` y se aplican contando lo que GAMA sabe de verdad. La
pantalla enseña de dónde sale cada punto: un número que nadie puede explicar no
se usa para decidir a quién llamar.

Tres de las cinco reglas sembradas se pueden contar hoy (`reunion`,
`solicitud_presupuesto`, `pedido`). Las otras dos (`correo_abierto`,
`correo_click`) **no**, porque GAMA envía los correos desde el programa de
correo del usuario, sin píxel de seguimiento ni enlaces marcados. La pantalla
lo dice en vez de inventar el número. El día que el envío lleve seguimiento,
esas reglas contarán solas: ya están en la tabla y el cálculo las recogerá.

**El enchufe de IA no hace nada, a propósito.** `GamaCRM.ia` es un registro
vacío: mientras nadie registre un proveedor, `hay()` es `false` y ninguna
pantalla enseña nada. `sugerir()` FALLA en vez de devolver un texto plausible,
porque devolver algo plausible sería exactamente la IA de mentira que el
encargo prohíbe. Un proveedor es `{nombre, sugerir(peticion) -> Promise}`.

## Pruebas

`tests/crm-*.spec.js`. Dos disciplinas que conviene mantener:

- **El doble no puede ser más permisivo que Postgres.** `tests/mock-gama-cloud.js`
  reproduce los CHECK y los índices únicos del CRM. Un doble que acepta lo que
  la base rechaza no prueba nada: prueba el doble. (Esto ya costó una caída en
  producción: el doble ofrecía un `select()` que `GamaCloud` no tiene.)
- **Toda prueba nueva se comprueba al revés.** Se quita la guardia, se
  comprueba que la prueba falla, y se vuelve a poner. Una prueba que pasa con y
  sin el arreglo no protege nada.
