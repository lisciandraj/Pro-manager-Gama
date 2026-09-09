// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const hoy = () => new Date().toISOString().slice(0, 10);

// Un desbordamiento horizontal no se ve como un desbordamiento: el teléfono
// aleja el zoom para que quepa lo más ancho, y lo que el usuario nota es que
// la cabecera y las tarjetas salen encogidas, con el texto diminuto. Por eso
// se mide document.scrollWidth y no «se ve bien»: es el único síntoma fiable.
//
// El caso que dio origen a esta prueba: la rejilla de RRHH usaba «1fr», que es
// «minmax(auto,1fr)». Su mínimo automático es el del contenido, así que el
// min-width:560px de la tabla de empleados —puesto a propósito, porque la
// tabla se desplaza dentro de su caja— se escapaba a la columna y estiraba el
// documento a 598 px en cualquier teléfono.

const SEED = {
  products: [{ id: 'p1', name: 'Producto de prueba', reference: 'REF-1', category: 'General', sale_price: 10, purchase_price: 5, tax_rate: 15, stock: 8, active: true, created_at: hoy() }],
  suppliers: [{ id: 's1', name: 'Proveedor Uno', active: true }],
  customers: [{ id: 'c1', name: 'Cliente Uno', active: true, email: 'c@e.com', category: 'C' }],
  invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [],
  stock_movements: [], profiles: [],
  customer_special_prices: [{ id: 'sp1', customer_id: 'c1', product_id: 'p1', unit_price: 5 }],
  customer_requests: [], app_modules: [],
  hr_employees: [
    { id: 'e1', full_name: 'Ana Torres', position: 'Conductora', department: 'Logística', active: true },
    { id: 'e2', full_name: 'María Fernanda Pérez Vaca', position: 'Comercial', department: 'Ventas', active: true },
  ],
  hr_absences: [{ id: 'a1', employee_id: 'e1', kind: 'vacaciones', status: 'aprobada', start_date: hoy(), end_date: hoy(), days: 1 }],
  hr_employee_private: [], hr_absence_private: [],
  tms_drivers: [{ id: 'd1', name: 'Conductor 1', vehicle: 'Camión 1', max_weight: 1000, max_volume: 5, enabled: true, created_at: hoy() }],
  tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
};

async function bootTelefono(page, ancho = 390) {
  await page.setViewportSize({ width: ancho, height: 844 });
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Jimmy Lisciandra' }));
    localStorage.setItem('gama_tms_migrated_v1', '1');
    // @ts-ignore
    window.__DB = seed;
  }, SEED);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.route('**/nominatim.openstreetmap.org/**', route => route.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
}

/** Ancho del documento frente al de la pantalla, y quién sobresale si sobra. */
const medir = page => page.evaluate(() => {
  const vw = document.documentElement.clientWidth;
  const sw = document.documentElement.scrollWidth;
  let peor = '';
  if (sw > vw + 1) {
    let ancho = 0;
    document.querySelectorAll('section.active *').forEach(el => {
      const b = el.getBoundingClientRect();
      if (b.width > 0 && b.right > vw + 1 && b.right > ancho) {
        ancho = b.right;
        peor = el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
          (typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\s+/).slice(0, 3).join('.') : '') +
          ' → ' + Math.round(b.right);
      }
    });
  }
  return { vw, sw, peor, sec: (document.querySelector('section.active') || {}).id };
});

test.describe('Móvil — ninguna pantalla es más ancha que el teléfono', () => {
  test('los tres paneles de Recursos humanos caben en una pantalla de 390 px', async ({ page }) => {
    await bootTelefono(page, 390);
    await page.click('#mainmenu .gamaF2Card:has-text("Recursos humanos")');
    await page.waitForTimeout(900);

    for (const pestana of ['Empleados', 'Ausencias', 'Planificación']) {
      await page.click(`#hr .hrTabs button:has-text("${pestana}")`);
      await page.waitForTimeout(600);
      const m = await medir(page);
      expect(m.sw, `«${pestana}» estira la página: ${m.peor}`).toBeLessThanOrEqual(m.vw + 1);
    }

    // La plantilla no estira la página, pero tampoco se la ha aplastado ni le
    // faltan columnas: en el teléfono cada empleado se apila en una ficha con
    // sus seis datos y ya no queda nada que arrastrar de lado. (Antes esta
    // comprobación exigía justo lo contrario —que la tabla se desplazara
    // dentro de su caja— porque ésa era entonces la única salida al problema
    // de que la página se ensanchara.)
    await page.click('#hr .hrTabs button:has-text("Empleados")');
    await page.waitForTimeout(600);
    expect(await page.evaluate(() => {
      const t = document.querySelector('#hr .hrTable');
      const fila = t && t.querySelector('tbody tr');
      return t && fila ? { arrastre: t.scrollWidth - t.clientWidth, celdas: fila.cells.length } : null;
    }), 'la plantilla ya no se lee entera sin arrastrarla').toEqual({ arrastre: 0, celdas: 6 });
  });

  test('las tres pestañas de RRHH caben en una fila y no se cortan a 360 px', async ({ page }) => {
    await bootTelefono(page, 360);
    await page.click('#mainmenu .gamaF2Card:has-text("Recursos humanos")');
    await page.waitForTimeout(900);
    const r = await page.evaluate(() => {
      const b = [...document.querySelectorAll('#hr .hrTabs button')];
      return {
        filas: new Set(b.map(x => Math.round(x.getBoundingClientRect().top))).size,
        cortadas: b.filter(x => x.scrollWidth > x.clientWidth + 1).map(x => x.textContent.trim()),
      };
    });
    expect(r.filas, 'las pestañas se parten en varias filas').toBe(1);
    expect(r.cortadas, 'hay pestañas con el texto cortado').toEqual([]);
  });

  // La pantalla de Tarifas sólo pinta su tabla tras elegir un cliente, así que
  // el barrido del menú la veía siempre vacía: el desbordamiento vivía en la
  // tabla de precios negociados y ninguna prueba llegaba a ella.
  test('los precios negociados de un cliente caben en una pantalla de 390 px', async ({ page }) => {
    await bootTelefono(page, 390);
    await page.click('#mainmenu .gamaF2Card:has-text("Tarifas")');
    await page.waitForTimeout(900);
    await page.click('[data-pick="c1"]');
    await page.waitForTimeout(600);

    await expect(page.locator('.plTable')).toBeVisible();
    const m = await medir(page);
    expect(m.sw, `la tabla de precios negociados estira la página: ${m.peor}`).toBeLessThanOrEqual(m.vw + 1);

    // Acotar la columna no puede haber aplastado la tabla: sigue teniendo su
    // propio desplazamiento dentro de la tarjeta.
    expect(await page.evaluate(() => {
      const t = document.querySelector('#price-lists .plTableWrap');
      return t ? t.scrollWidth > t.clientWidth : false;
    }), 'la tabla de precios ya no se desplaza dentro de su caja').toBe(true);
  });

  test('ningún módulo del menú desborda a lo ancho en un teléfono de 390 px', async ({ page }) => {
    test.slow();
    await bootTelefono(page, 390);
    const nombres = await page.evaluate(() =>
      [...document.querySelectorAll('#mainmenu .gamaF2Card')]
        .map(c => ((c.querySelector('h3,b,strong') || c).textContent || '').trim().split('\n')[0].slice(0, 34))
        .filter(Boolean)
    );
    expect(nombres.length, 'el menú no se pintó').toBeGreaterThan(10);

    const malos = [];
    for (const n of nombres) {
      await page.evaluate(() => window.GamaUI.backToMenu());
      await page.waitForTimeout(200);
      await page.click(`#mainmenu .gamaF2Card:has-text(${JSON.stringify(n)})`);
      await page.waitForTimeout(800);
      const m = await medir(page);
      if (m.sw > m.vw + 1) malos.push(`${n} [#${m.sec}] doc=${m.sw} vs ${m.vw} — ${m.peor}`);
    }
    expect(malos, 'módulos más anchos que la pantalla').toEqual([]);
  });
});
