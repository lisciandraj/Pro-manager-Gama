# Architect ERP — sistema de diseño

Producción: `lisciandraj/Pro-manager-Gama`, proyecto `mknsaibrewksgomuslev`.

Refonte gráfica completa de la aplicación. **No es una reconstrucción
funcional**: no se ha quitado ninguna pantalla, ninguna ruta, ningún permiso,
ninguna llamada a la base de datos ni ninguna clave de traducción. Lo que
cambia es cómo se ve y cómo se navega.

## La regla que lo ordena todo

`architect-ui.css` **no inventa nombres de clase: viste los que la aplicación
ya usa.** `.card`, `.gsCard`, `.gpCard`, `.gaCard`, `.tmsCard`, `.gamaF2Card`,
`button.primary`, `.gsDialog`… siguen llamándose igual. Por eso trece módulos
escritos por separado cambian de aspecto a la vez sin tocar su código, y por
eso las pruebas que buscan `.gamaF2Card` o `#gamaSpotlight` siguen pasando.

La consecuencia práctica: **para cambiar el aspecto de algo no se edita el
módulo, se edita la hoja**. Y para que una pantalla nueva encaje sola, basta
con que use los nombres que ya existen.

## Los tres archivos

| Archivo | Qué es |
| --- | --- |
| `architect-tokens.css` | El color, el espacio, el radio, la sombra y la tipografía. Ningún módulo debería volver a escribir un `#RRGGBB`: si un tono no está aquí, es que falta aquí. |
| `architect-ui.css` | El sistema: tarjetas, botones, campos, tablas, diálogos, avisos, insignias, estados vacíos. Viste las clases existentes, sin `!important`. |
| `architect-shell.js` | El armazón: barra lateral de navegación, barra superior con buscador y usuario, y el cajón del teléfono. Es estructural: **mueve** el chip de sesión que pinta el control de acceso, no lo rehace. |

Se cargan al final de `<head>` (las hojas) y antes de `</body>` (el guion),
después de los cinco bloques `<style>` históricos de `index.html`. Ese orden
es el que hace que Architect gane sin `!important`.

## Paleta

Azul marino para lo que estructura —navegación, cabeceras—, azul acero para
lo secundario, blanco para las superficies de trabajo, un gris azulado muy
claro para el lienzo, y azul para lo que se puede pulsar.

```
--arc-navy-900 .. 600     barra lateral, cabeceras
--arc-steel-600 .. 300    secundario
--arc-accent-700 .. 50    acción, enlace, foco
--arc-canvas / surface / surface-2 / surface-3
--arc-line / line-strong
--arc-text / text-muted / text-subtle / text-invert / text-on-navy
--arc-success / warning / danger / info   (+ -bg y -line de cada uno)
--arc-fam-*               una familia por grupo de módulos
--arc-viz-1 .. 6          series de gráfico
```

Cada grupo del menú lleva su acento —análisis, ventas, logística, compras,
finanzas, personas, sistema— y el resto de la tarjeta es idéntico, así el
conjunto no se convierte en un arcoíris.

Ninguna descripción de tarjeta puede contener el rótulo de otro módulo: las
pruebas de punta a punta abren la tarjeta por su texto y se llevarían la
primera que coincida. Lo comprueba `tests/menu-cards.spec.js`.

El naranja histórico de GAMA era el acento de marca, no un aviso: numeraba
documentos, resaltaba cifras y vestía el botón de escanear. En Architect el
acento de marca es el azul, y los alias antiguos (`--gama-orange`,
`--gama-teal`, `--gama-line`…) apuntan a los tokens nuevos para que el código
que aún los use siga siendo coherente.

## Navegación

Antes: una rejilla de tarjetas para todo, una barra lateral que sólo aparecía
por encima de 1400px, una cabecera con tres iconos y una fila de pestañas
abajo. Ahora hay **un solo sitio donde está todo**:

- **≥1321px** — barra lateral completa: marca, «Inicio», los grupos del menú
  con sus módulos, idioma y versión al pie.
- **861–1320px** — la misma barra reducida a iconos (72px). Los rótulos se
  esconden; el destino no cambia. El corte está en 1320 y no más abajo porque
  en un portátil de 1280px no caben 248px de barra y además una tabla de
  tarifas.
- **≤860px** — cajón fuera de pantalla. Lo abre el botón de la barra superior
  y lo cierran el velo, un enlace o la tecla `Esc`.

La barra la construye `architect-shell.js` leyendo `window.GamaMenu`
(`{items, groups, icons, open, render}`), que es la misma fuente que pinta el
menú principal: **no hay dos listas de módulos**. El enlace activo se marca
con `aria-current="page"` a partir de `section.active`, y los permisos los
sigue decidiendo `window.gamaAccessAllowed()` — la barra sólo aplica
`.aclHidden` y esconde el grupo que se queda vacío.

La cabecera, las pestañas y la barra lateral históricas siguen en el DOM —hay
pruebas y atajos que las consultan— pero no pintan nada.

## Menú principal

Cada tarjeta lleva ahora icono con el color de su familia, título, **una línea
que dice para qué sirve el módulo** y una flecha. Arriba, hasta tres
indicadores que leen datos reales (`gama_operations_action`, acción
`snapshot`): cartera en curso, pedidos en curso y avisos que requieren acción.
Si el dato no está disponible todavía, **la fila no se pinta**: nunca se
enseñan cifras de ejemplo.

## Responsive

Probado en 1920, 1440, 1024, 768, 430 y 390px, en el menú y dentro de los
módulos. `tests/architect-shell.spec.js` mide el desbordamiento horizontal en
los seis anchos y en cinco pantallas de módulo, y nombra al elemento culpable
cuando falla — así fue como se encontró que la barra lateral histórica
empujaba `.wrap` 248px a la derecha por encima de 1400px.

## Accesibilidad

- Contraste AA (4.5:1) en **todos** los tonos de texto sobre **todas** las
  superficies del sistema —blanco, lienzo, superficie-2 y superficie-3—, no
  sólo sobre blanco: el texto principal llega a 15.5:1, el secundario a 6.5:1
  y el sutil a 5.4:1 sobre blanco, y ninguno baja de 4.5:1 sobre el lienzo.
- El lienzo es un gris de verdad (`#E6EBF2`) y no un blanco roto: con el
  anterior la tarjeta blanca daba 1.07:1 contra el fondo y su borde no se
  percibía. Lo vigila `tests/menu-contrast.spec.js`.
- Foco de teclado visible en todo lo que se puede enfocar, con
  `:focus-visible` y un anillo de 3px.
- Zona táctil de 44px como mínimo en la barra superior, la navegación y el
  selector de idioma.
- Todo botón que sólo enseña un icono trae `aria-label`.
- **El color nunca informa solo**: cada estado lleva además su texto o su
  icono, y las series de gráfico van siempre con su etiqueta y su cifra.
- `prefers-reduced-motion` apaga las transiciones.

## Traducciones

Todo el texto visible que introduce la refonte —las descripciones de los
módulos, los rótulos del armazón, los indicadores— está en
`locales/catalog.tsv` en español, francés e inglés, y se compila con
`python3 scripts/build-i18n.py`. Las cifras van siempre fuera de la cadena
traducida, y el dinero lo formatea `GamaCurrency`: no hay un solo `€` ni un
solo `$` escrito a mano.

El nombre visible de la aplicación pasa de GAMA a Architect ERP en pantallas,
manifiesto y documentos. **No cambian** los identificadores técnicos: nombres
de archivo `gama-*.js`, `window.Gama*`, las funciones `gama_*` de la base de
datos, las clases CSS, las claves de almacenamiento ni el marcador
`GAMA_META` que el CRM escribe en las notas. Tampoco cambia el nombre del
emisor que sale en presupuestos y facturas: eso es un dato de la empresa, no
el nombre del programa.

## Qué hacer al añadir una pantalla

1. Pedir la cabecera a `GamaUI.header({title, lead})` y engancharla con
   `GamaUI.bindBack()`.
2. Usar los nombres de clase que ya existen (`card`, `primary`, `secondary`,
   `num`…). No hace falta CSS propio para que se vea como el resto.
3. Si hace falta un color, **cogerlo de `architect-tokens.css`**. Si no está,
   añadirlo ahí y no en el módulo.
4. Meter el texto en `locales/catalog.tsv` y recompilar.
5. Dar de alta el módulo en `gama-menu-final2.js` (`ITEMS` y `DESC`): la barra
   lateral lo recoge sola.
