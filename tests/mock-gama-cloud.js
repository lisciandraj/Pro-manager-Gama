/* Minimal in-memory stand-in for gama-supabase.js's window.GamaCloud, used by
   tests to exercise real UI flows without touching the live Supabase backend.
   Loaded via page.route() fulfilling the request for gama-supabase.js. */
(function () {
  'use strict';
  // Como gama-supabase.js: el archivo llega dos veces (la etiqueta de index.html
  // y la copia que inyecta gama-access-control.js). La segunda no debe crear
  // otra capa de datos a mitad del arranque.
  if (window.GamaCloud && window.GamaCloudReady) return;
  window.__DB = window.__DB || {
    products: [], suppliers: [], customers: [],
    invoices: [], invoice_lines: [],
    purchase_orders: [], purchase_order_lines: [],
  };
  window.__DB._profile = window.__DB._profile || { id: 'test-admin-uid', full_name: 'Test Admin', role: 'administrador', active: true };
  let idc = 1;
  function nextId(table) { return table[0] + (idc++); }
  // catalog_products is a database view over products that deliberately omits
  // purchase_price, supplier_id and location: a "cliente" account may browse
  // the catalogue without seeing purchase costs, suppliers or warehouse locations.
  // Modelling it here keeps that boundary under test.
  const CATALOG_COLUMNS = ['id', 'name', 'reference', 'category', 'barcode', 'sale_price', 'tax_rate', 'stock', 'photo_data', 'active', 'created_at', 'has_photo'];
  function catalogRows() {
    // Mirrors the catalog_products view: the price shown is resolved for the
    // customer whose email matches the session — their negotiated price when
    // one exists for the product (categoría C), otherwise the price of their
    // category: B is the retail price, A (and a C with nothing pactado for the
    // product) the mayorista price on the product sheet.
    const email = String((window.__DB._profile || {}).email || '').toLowerCase();
    const me = (window.__DB.customers || []).find(c => c.active !== false && String(c.email || '').toLowerCase() === email && email);
    const items = (window.__DB.customer_special_prices || []).filter(i => me && i.customer_id === me.id);
    const category = (me && me.category) || 'A';
    return (window.__DB.products || [])
      .filter(p => p.active !== false)
      .map(p => {
        const o = {}; CATALOG_COLUMNS.forEach(c => { if (c in p) o[c] = p[c]; });
        o.has_photo = !!p.photo_data;
        const hit = items.find(i => i.product_id === p.id);
        o.base_price = p.sale_price;
        o.contract_price = !!hit;
        o.sale_price = hit ? hit.unit_price : (category === 'B' ? p.sale_price_b : p.sale_price);
        return o;
      });
  }
  // Espejo de las politicas de RRHH. Las tablas base las lee todo el personal
  // —el calendario del equipo las necesita—; lo sensible vive en las tablas
  // privadas, que solo devuelven la fila propia salvo al administrador. El
  // doble lo reproduce para que lo que comprueba una prueba en pantalla sea lo
  // mismo que devolveria Postgres.
  function hrRole() {
    try { return JSON.parse(localStorage.getItem('gama_session_v1') || '{}').role || ''; }
    catch (e) { return ''; }
  }
  // RRHH: el administrador y el perfil de base «Responsable RH» (private.hr_admin).
  function hrIsAdmin() { return ['admin', 'administrador', 'rh', 'rrhh'].includes(hrRole()); }
  function hrIsStaff() { return ['admin', 'administrador', 'commercial', 'comercial', 'magasinier', 'almacenero'].includes(hrRole()); }
  function hrMyProfile() { return (window.__DB._session || {}).profile_id || null; }
  // Espejo de private.hr_manager_guard: ni uno mismo, ni un círculo, ni un N+1 archivado.
  function hrManagerError(id, managerId) {
    const rows = window.__DB.hr_employees || [];
    if (managerId === id) return { message: 'HR_MANAGER_SELF' };
    if (!rows.some(e => e.id === managerId && e.active !== false)) return { message: 'HR_MANAGER_INACTIVE' };
    for (let at = managerId, n = 0; at && n < 1000; n++) { if (at === id) return { message: 'HR_MANAGER_CYCLE' }; at = (rows.find(e => e.id === at) || {}).manager_id; }
    return null;
  }
  function hrMyEmployeeIds() {
    const me = hrMyProfile();
    return (window.__DB.hr_employees || []).filter(e => !!me && e.profile_id === me).map(e => e.id);
  }
  function hrRows(table) {
    if (table === 'hr_employees' || table === 'hr_absences') {
      return hrIsStaff() || hrIsAdmin() ? (window.__DB[table] || []).slice() : [];
    }
    if (hrIsAdmin()) return (window.__DB[table] || []).slice();
    const mias = hrMyEmployeeIds();
    if (table === 'hr_employee_private') {
      return (window.__DB.hr_employee_private || []).filter(r => mias.includes(r.employee_id));
    }
    const abs = (window.__DB.hr_absences || []).filter(a => mias.includes(a.employee_id)).map(a => a.id);
    return (window.__DB.hr_absence_private || []).filter(r => abs.includes(r.absence_id));
  }
  // crm_team es una vista sobre profiles: los usuarios a los que el CRM puede
  // asignar algo. Existe porque profiles solo deja leer la fila propia, asi que
  // un comercial no podia poner nombre al responsable de un prospecto ajeno. La
  // vista expone cuatro columnas de los perfiles comerciales activos, y nada a
  // quien no sea administrador o comercial. El doble lo reproduce para que la
  // frontera que prueba una prueba sea la que aplica Postgres.
  function teamRows() {
    if (!['admin', 'administrador', 'commercial', 'comercial'].includes(hrRole())) return [];
    return (window.__DB.profiles || [])
      .filter(p => p.active !== false && ['administrador', 'comercial'].includes(String(p.role || '')))
      .map(p => ({ id: p.id, full_name: p.full_name, email: p.email, role: p.role }));
  }
  function rowsFor(table, options) {
    options = options || {};
    let rows = table === 'catalog_products' ? catalogRows()
      : table === 'crm_team' ? teamRows()
      : /^hr_(employees|absences|employee_private|absence_private)$/.test(table) ? hrRows(table)
      : (window.__DB[table] || []).slice();
    // products.has_photo es una columna generada en la base: se deriva aqui
    // para que una consulta estrecha pueda pedirla sin traerse la foto.
    if (table === 'products') rows = rows.map(r => ({ ...r, has_photo: !!r.photo_data }));
    if (options.eq) Object.keys(options.eq).forEach(k => { rows = rows.filter(r => r[k] === options.eq[k]); });
    if (options.search) {const {columns,value}=options.search;const term=String(value).toLowerCase();rows=rows.filter(r=>columns.some(k=>String(r[k]??'').toLowerCase().includes(term)));}
    if (options.in) Object.keys(options.in).forEach(k => { rows = rows.filter(r => (options.in[k] || []).includes(r[k])); });
    // gte/lte los usa el analisis de ventas para acotar el periodo. Sin ellos
    // el doble devolvia TODAS las facturas y una prueba de periodo no probaba
    // nada: pasaria igual aunque el filtro no se enviara.
    if (options.gte) Object.keys(options.gte).forEach(k => { rows = rows.filter(r => r[k] >= options.gte[k]); });
    if (options.lte) Object.keys(options.lte).forEach(k => { rows = rows.filter(r => r[k] <= options.lte[k]); });
    // lt/gt existen en el cliente real (list() de gama-supabase.js). El doble
    // los reproduce porque el CRM cuenta con ellos lo vencido, y un doble que
    // ignora un filtro haría pasar una prueba que en producción no filtra nada.
    if (options.lt) Object.keys(options.lt).forEach(k => { rows = rows.filter(r => r[k] < options.lt[k]); });
    if (options.gt) Object.keys(options.gt).forEach(k => { rows = rows.filter(r => r[k] > options.gt[k]); });
    if (options.order) rows.sort((a, b) => {
      const av = a[options.order], bv = b[options.order];
      const cmp = av > bv ? 1 : av < bv ? -1 : 0;
      return options.ascending !== false ? cmp : -cmp;
    });
    if (options.range) rows = rows.slice(options.range[0], options.range[1] + 1);
    else if (options.limit) rows = rows.slice(0, options.limit);
    // A narrow select() must not hand back columns the caller did not ask for —
    // that is the whole point of keeping POD photos out of the index query.
    if (options.select && options.select !== '*') {
      const cols = options.select.split(',').map(c => c.trim()).filter(Boolean);
      rows = rows.map(r => { const o = {}; cols.forEach(c => { o[c] = r[c]; }); return o; });
    }
    return rows;
  }
  // Mirrors the real gama_receive_purchase Postgres function closely enough
  // to catch the exact class of bug it once had: a role check comparing
  // current_user_role() (always a raw Spanish profiles.role value) against
  // a garbled list of French/English terms, which silently rejected every
  // admin's reception with FORBIDDEN.
  // ---- Inventario V2 -------------------------------------------------------
  // El doble reproduce las restricciones que Postgres impone de verdad: los
  // CHECK de stock_quants (ni negativo ni reservado por encima de lo que hay),
  // el bloqueo de rol y el invariante SUM(quants) = products.stock. Un doble
  // más permisivo que el backend no prueba nada: prueba el doble.
  function quantsDe(productId) {
    return (window.__DB.stock_quants || []).filter(q => q.product_id === productId);
  }
  function sincronizaStock(productId) {
    const total = quantsDe(productId).reduce((s, q) => s + Number(q.quantity || 0), 0);
    const p = (window.__DB.products || []).find(x => x.id === productId);
    if (p) p.stock = total;
    return total;
  }
  function quant(productId, locationId, crear) {
    window.__DB.stock_quants = window.__DB.stock_quants || [];
    let q = window.__DB.stock_quants.find(x => x.product_id === productId && x.location_id === locationId);
    if (!q && crear) {
      q = { id: nextId('stock_quants'), product_id: productId, location_id: locationId, quantity: 0, reserved_quantity: 0 };
      window.__DB.stock_quants.push(q);
    }
    return q;
  }
  // Espejo de private.gama_default_location(): la ubicación STOCK del almacén
  // PRINCIPAL, que la migración de la fase 1 siempre deja creada.
  function ubicacionPorDefecto() {
    const w = (window.__DB.warehouses || []).find(x => x.code === 'PRINCIPAL');
    if (!w) return null;
    const all = (window.__DB.warehouse_locations || []).filter(x => x.warehouse_id === w.id);
    const l = all.find(x => x.role === 'arrival') || all.find(x => x.code === 'STOCK');
    return l ? l.id : null;
  }
  function mueveStock(args) {
    const role = window.__DB._profile.role;
    if (!['administrador', 'almacenero'].includes(role)) return { data: null, error: { message: 'ROLE_NOT_ALLOWED' } };
    const qty = Number(args.p_quantity);
    if (!(qty > 0)) return { data: null, error: { message: 'INVALID_QUANTITY' } };
    if (args.p_source_location_id === args.p_destination_location_id) return { data: null, error: { message: 'SAME_LOCATION' } };
    const product = (window.__DB.products || []).find(p => p.id === args.p_product_id);
    if (!product) return { data: null, error: { message: 'PRODUCT_NOT_FOUND' } };

    // Se valida ANTES de crear nada. En Postgres el `raise exception` deshace
    // la transacción entera, así que un traslado rechazado no deja ni rastro;
    // si aquí se crearan los quants primero, el doble se quedaría con una fila
    // a cero que la base real nunca habría guardado.
    const origen = quant(args.p_product_id, args.p_source_location_id, false);
    const disponible = Number(origen ? origen.quantity : 0) - Number(origen ? origen.reserved_quantity : 0);
    // Lo reservado sigue comprometido donde está: no se puede mover.
    if (disponible < qty) return { data: null, error: { message: 'INSUFFICIENT_STOCK' } };
    const destino = quant(args.p_product_id, args.p_destination_location_id, true);

    const totalAntes = quantsDe(args.p_product_id).reduce((s, q) => s + Number(q.quantity || 0), 0);
    origen.quantity = Number(origen.quantity || 0) - qty;
    destino.quantity = Number(destino.quantity || 0) + qty;

    window.__DB.stock_movements = window.__DB.stock_movements || [];
    const mov = {
      id: nextId('stock_movements'), product_id: args.p_product_id, type: 'adjustment', quantity: qty,
      reason: args.p_reason || 'Transferencia interna', comment: args.p_comment || null,
      user_id: window.__DB._profile.id, created_at: new Date().toISOString(),
      // Una transferencia no cambia el total del producto, sólo dónde está.
      stock_before: totalAntes, stock_after: totalAntes,
      source_location_id: args.p_source_location_id, destination_location_id: args.p_destination_location_id,
      movement_type: 'internal_transfer',
    };
    window.__DB.stock_movements.push(mov);
    sincronizaStock(args.p_product_id);
    return { data: mov, error: null };
  }
  function reservaStock(args) {
    const role = window.__DB._profile.role;
    if (!['administrador', 'almacenero', 'comercial'].includes(role)) return { data: null, error: { message: 'ROLE_NOT_ALLOWED' } };
    const qty = Number(args.p_quantity);
    if (!(qty > 0)) return { data: null, error: { message: 'INVALID_QUANTITY' } };
    // Igual que en el traslado: si no hay para reservar, no queda nada creado.
    const q = quant(args.p_product_id, args.p_location_id, false);
    const disponible = Number(q ? q.quantity : 0) - Number(q ? q.reserved_quantity : 0);
    if (disponible < qty) return { data: null, error: { message: 'INSUFFICIENT_AVAILABLE' } };
    q.reserved_quantity = Number(q.reserved_quantity || 0) + qty;
    window.__DB.stock_reservations = window.__DB.stock_reservations || [];
    const r = {
      id: nextId('stock_reservations'), product_id: args.p_product_id, location_id: args.p_location_id,
      quantity: qty, reference_type: args.p_reference_type || null, reference_id: args.p_reference_id || null,
      status: 'active', created_by: window.__DB._profile.id, created_at: new Date().toISOString(), released_at: null,
    };
    window.__DB.stock_reservations.push(r);
    return { data: r, error: null };
  }
  function liberaReserva(args) {
    const r = (window.__DB.stock_reservations || []).find(x => x.id === args.p_reservation_id);
    if (!r) return { data: null, error: { message: 'RESERVATION_NOT_FOUND' } };
    // Soltar dos veces la misma reserva no resta dos veces.
    if (r.status !== 'active') return { data: r, error: null };
    const q = quant(r.product_id, r.location_id, true);
    q.reserved_quantity = Math.max(0, Number(q.reserved_quantity || 0) - Number(r.quantity || 0));
    r.status = args.p_consumed ? 'consumed' : 'released';
    r.released_at = new Date().toISOString();
    return { data: r, error: null };
  }

  // Conteos físicos. Lo que importa reproducir: el stock NO se mueve al
  // apuntar lo contado, sino al validar; y validar dos veces no ajusta dos
  // veces, porque el estado se comprueba antes de tocar nada.
  function generaLineas(args) {
    const role = window.__DB._profile.role;
    if (!['administrador', 'almacenero'].includes(role)) return { data: null, error: { message: 'ROLE_NOT_ALLOWED' } };
    const c = (window.__DB.inventory_counts || []).find(x => x.id === args.p_count_id);
    if (!c) return { data: null, error: { message: 'COUNT_NOT_FOUND' } };
    if (!['draft', 'in_progress'].includes(c.status)) return { data: null, error: { message: 'COUNT_NOT_EDITABLE' } };
    const ubis = (window.__DB.warehouse_locations || []).filter(l => l.warehouse_id === c.warehouse_id).map(l => l.id);
    window.__DB.inventory_count_lines = window.__DB.inventory_count_lines || [];
    let n = 0;
    (window.__DB.stock_quants || []).filter(q => ubis.includes(q.location_id)&&(!c.product_id||q.product_id===c.product_id)&&(!c.location_id||q.location_id===c.location_id)).forEach(q => {
      const ya = window.__DB.inventory_count_lines.find(l => l.count_id === c.id && l.product_id === q.product_id && l.location_id === q.location_id);
      if (ya) { if (ya.counted_quantity === null || ya.counted_quantity === undefined) ya.expected_quantity = q.quantity; return; }
      window.__DB.inventory_count_lines.push({
        id: nextId('inventory_count_lines'), count_id: c.id, product_id: q.product_id,
        location_id: q.location_id, expected_quantity: Number(q.quantity || 0),
        counted_quantity: null, validated: false,
      });
      n++;
    });
    c.status = 'in_progress';
    c.started_at = c.started_at || new Date().toISOString();
    return { data: n, error: null };
  }
  function validaConteo(args) {
    const role = window.__DB._profile.role;
    if (!['administrador', 'almacenero'].includes(role)) return { data: null, error: { message: 'ROLE_NOT_ALLOWED' } };
    const c = (window.__DB.inventory_counts || []).find(x => x.id === args.p_count_id);
    if (!c) return { data: null, error: { message: 'COUNT_NOT_FOUND' } };
    if (c.status === 'validated') return { data: null, error: { message: 'COUNT_ALREADY_VALIDATED' } };
    if (c.status === 'cancelled') return { data: null, error: { message: 'COUNT_CANCELLED' } };
    let ajustes = 0;
    (window.__DB.inventory_count_lines || [])
      .filter(l => l.count_id === c.id && l.counted_quantity !== null && l.counted_quantity !== undefined && !l.validated)
      .forEach(l => {
        const contado = Number(l.counted_quantity);
        if (contado !== Number(l.expected_quantity)) {
          const q = quant(l.product_id, l.location_id, true);
          const totalAntes = quantsDe(l.product_id).reduce((s, x) => s + Number(x.quantity || 0), 0);
          const delta = contado - Number(q.quantity || 0);
          q.quantity = contado;
          window.__DB.stock_movements = window.__DB.stock_movements || [];
          window.__DB.stock_movements.push({
            id: nextId('stock_movements'), product_id: l.product_id,
            type: delta > 0 ? 'in' : 'out', quantity: Math.abs(delta),
            reason: 'Inventario físico',
            comment: 'Conteo ' + c.reference + ' · esperado ' + l.expected_quantity + ', contado ' + contado,
            user_id: window.__DB._profile.id, created_at: new Date().toISOString(),
            stock_before: totalAntes, stock_after: totalAntes + delta,
            source_location_id: delta < 0 ? l.location_id : null,
            destination_location_id: delta > 0 ? l.location_id : null,
            movement_type: 'inventory_adjustment',
            reference_type: 'inventory_count', reference_id: c.id,
          });
          sincronizaStock(l.product_id);
          ajustes++;
        }
        l.validated = true;
      });
    c.status = 'validated';
    c.completed_at = new Date().toISOString();
    return { data: { count_id: c.id, adjustments: ajustes }, error: null };
  }

  // Receipt allocation mirrors the production trigger: oldest confirmed sales
  // order first, without ever reserving more than the newly available stock.
  function allocatePendingSales(productId) {
    const orderById = new Map((window.__DB.sales_orders || []).map(o => [o.id, o]));
    const pending = (window.__DB.sales_order_lines || [])
      .filter(l => l.product_id === productId && orderById.get(l.order_id)?.status === 'confirmed')
      .sort((a, b) => String(orderById.get(a.order_id)?.created_at || '').localeCompare(String(orderById.get(b.order_id)?.created_at || '')));
    for (const line of pending) {
      const shipped = (window.__DB.sales_delivery_lines || []).filter(x => x.order_line_id === line.id).reduce((s, x) => s + Number(x.quantity || 0), 0);
      const linked = new Set((window.__DB.sales_reservation_links || []).filter(x => x.line_id === line.id).map(x => x.reservation_id));
      const reserved = (window.__DB.stock_reservations || []).filter(x => linked.has(x.id) && x.status === 'active').reduce((s, x) => s + Number(x.quantity || 0), 0);
      let need = Number(line.quantity || 0) - shipped - reserved;
      for (const q of quantsDe(productId)) {
        if (need <= 0) break;
        const take = Math.min(need, Number(q.quantity || 0) - Number(q.reserved_quantity || 0));
        if (take <= 0) continue;
        q.reserved_quantity = Number(q.reserved_quantity || 0) + take;
        window.__DB.stock_reservations = window.__DB.stock_reservations || [];
        window.__DB.sales_reservation_links = window.__DB.sales_reservation_links || [];
        const r = { id: nextId('stock_reservations'), product_id: productId, location_id: q.location_id, quantity: take, reference_type: 'sales_order', reference_id: line.order_id, status: 'active', created_by: window.__DB._profile.id, created_at: new Date().toISOString(), released_at: null };
        window.__DB.stock_reservations.push(r);
        window.__DB.sales_reservation_links.push({ reservation_id: r.id, line_id: line.id });
        need -= take;
      }
    }
  }

  function rpcReceivePurchase(args) {
    const role = window.__DB._profile.role;
    if (!['administrador', 'almacenero'].includes(role)) return { data: null, error: { message: 'FORBIDDEN' } };
    const po = (window.__DB.purchase_orders || []).find(o => o.id === args.p_purchase_order_id);
    if (!po) return { data: null, error: { message: 'PURCHASE_ORDER_NOT_FOUND' } };
    if (po.status === 'cancelled') return { data: null, error: { message: 'PURCHASE_ORDER_CANCELLED' } };
    if (!['sent', 'partial'].includes(po.status)) return { data: null, error: { message: 'PURCHASE_ORDER_NOT_RECEIVABLE' } };
    for (const line of args.p_lines || []) {
      const pol = (window.__DB.purchase_order_lines || []).find(l => l.id === line.line_id && l.purchase_order_id === args.p_purchase_order_id);
      if (!pol) return { data: null, error: { message: 'PURCHASE_ORDER_LINE_NOT_FOUND' } };
      if (!(line.quantity > 0)) return { data: null, error: { message: 'INVALID_RECEIPT_QUANTITY' } };
      if ((pol.received_quantity || 0) + line.quantity > pol.quantity) return { data: null, error: { message: 'RECEIPT_EXCEEDS_ORDERED' } };
      const product = (window.__DB.products || []).find(p => p.id === pol.product_id);
      if (!product) return { data: null, error: { message: 'PRODUCT_NOT_FOUND' } };
      // Con la fase 1 aplicada la mercancía entra en una ubicación concreta y
      // products.stock pasa a ser la suma de los quants; sin ella la función
      // sigue siendo la de siempre. Las dos ramas existen de verdad: una base
      // sin migrar no tiene dónde poner un quant.
      const conUbicaciones = (window.__DB.warehouse_locations || []).length > 0;
      const destino = conUbicaciones ? (line.location_id || ubicacionPorDefecto()) : null;
      if (conUbicaciones && !destino) return { data: null, error: { message: 'LOCATION_NOT_FOUND' } };
      const before = conUbicaciones
        ? quantsDe(product.id).reduce((s, q) => s + Number(q.quantity || 0), 0)
        : Number(product.stock || 0);
      if (conUbicaciones) {
        const q = quant(product.id, destino, true);
        q.quantity = Number(q.quantity || 0) + line.quantity;
        sincronizaStock(product.id);
      } else {
        product.stock = before + line.quantity;
      }
      product.purchase_price = pol.unit_cost;
      pol.received_quantity = (pol.received_quantity || 0) + line.quantity;
      window.__DB.stock_movements = window.__DB.stock_movements || [];
      window.__DB.stock_movements.push(Object.assign({ id: nextId('stock_movements'), product_id: product.id, type: 'in', quantity: line.quantity, stock_before: before, stock_after: before + line.quantity, user_id: window.__DB._profile.id, created_at: new Date().toISOString() },
        conUbicaciones ? { destination_location_id: destino, movement_type: 'receipt', reference_type: 'purchase_order', reference_id: args.p_purchase_order_id } : {}));
      if (conUbicaciones) allocatePendingSales(product.id);
    }
    const allLines = (window.__DB.purchase_order_lines || []).filter(l => l.purchase_order_id === args.p_purchase_order_id);
    const allReceived = allLines.length > 0 && allLines.every(l => (l.received_quantity || 0) >= l.quantity);
    const anyReceived = allLines.some(l => (l.received_quantity || 0) > 0);
    po.status = allReceived ? 'received' : anyReceived ? 'partial' : po.status;
    return { data: { purchase_order_id: po.id, status: po.status }, error: null };
  }
  // Espejo de los indices unicos parciales crm_contacts_principal_cliente_idx y
  // crm_contacts_principal_lead_idx: UN solo contacto principal ACTIVO por
  // ficha. Sin esto el doble aceptaria dos, y una pantalla que se olvidara de
  // quitarle el puesto al anterior pasaria las pruebas para caerse en
  // produccion con una violacion de clave unica. Un doble mas permisivo que lo
  // real no prueba nada: prueba el doble.
  function chocaPrincipal(row, id) {
    const previa = (window.__DB.crm_contacts || []).find(r => r.id === id) || {};
    const fila = Object.assign({}, previa, row);
    if (!fila.is_primary || fila.active === false) return null;
    const col = fila.customer_id ? 'customer_id' : 'lead_id';
    const val = fila[col];
    if (!val) return null;
    const otro = (window.__DB.crm_contacts || []).find(r =>
      r.id !== id && r.is_primary && r.active !== false && r[col] === val);
    return otro ? { message: 'duplicate key value violates unique constraint "crm_contacts_principal_'
      + (fila.customer_id ? 'cliente' : 'lead') + '_idx"' } : null;
  }
  // Espejo de los CHECK de crm_opportunities. Sin ellos el doble aceptaria una
  // oportunidad colgada de un cliente Y de un prospecto, o perdida sin motivo,
  // o ganada y perdida a la vez: las tres cosas que Postgres rechaza y que una
  // pantalla puede escribir sin darse cuenta al reabrir algo ya cerrado.
  function chocaOportunidad(row, id) {
    const previa = (window.__DB.crm_opportunities || []).find(r => r.id === id) || {};
    const f = Object.assign({}, previa, row);
    const c = f.customer_id != null, l = f.lead_id != null;
    if (c === l) return { message: 'new row violates check constraint "crm_opp_uno_u_otro"' };
    if (f.lost_at != null && f.lost_reason_id == null)
      return { message: 'new row violates check constraint "crm_opp_perdida_con_motivo"' };
    if (f.won_at != null && f.lost_at != null)
      return { message: 'new row violates check constraint "crm_opp_no_ganada_y_perdida"' };
    return null;
  }
  // Espejo de los CHECK de crm_activities: una actividad cuelga de algo, y una
  // pendiente exige fecha. Sin esto el doble aceptaria una nota que no cuelga
  // de nadie —imposible de volver a encontrar— y una tarea sin fecha, que no
  // saldria en la agenda ni contaria como vencida en el cuadro de mando.
  function chocaActividad(row, id) {
    const previa = (window.__DB.crm_activities || []).find(r => r.id === id) || {};
    const f = Object.assign({}, previa, row);
    const anclas = ['lead_id', 'customer_id', 'contact_id', 'opportunity_id', 'invoice_id', 'customer_request_id'];
    if (!anclas.some(k => f[k] != null))
      return { message: 'new row violates check constraint "crm_act_colgada_de_algo"' };
    if (f.status === 'pendiente' && f.due_at == null)
      return { message: 'new row violates check constraint "crm_act_pendiente_con_fecha"' };
    return null;
  }
  // Espejo de crm_targets_persona_idx y crm_targets_empresa_idx: UN objetivo por
  // (quien, tipo, periodo), con la fila de empresa (profile_id nulo) en su
  // propio indice. Sin esto el doble aceptaria dos objetivos para el mismo mes
  // y la pantalla podria duplicar en vez de corregir.
  function chocaObjetivo(row, id) {
    const previa = (window.__DB.crm_targets || []).find(r => r.id === id) || {};
    const f = Object.assign({}, previa, row);
    const otro = (window.__DB.crm_targets || []).find(r =>
      r.id !== id && r.period_kind === f.period_kind && r.period_start === f.period_start &&
      String(r.profile_id || '') === String(f.profile_id || ''));
    return otro ? { message: 'duplicate key value violates unique constraint "crm_targets_'
      + (f.profile_id ? 'persona' : 'empresa') + '_idx"' } : null;
  }
  window.GamaCloud = {
    // hr_employees.profile_id apunta a profiles.id, que es el id del usuario
    // autenticado: una prueba que fija _session.profile_id tiene que verlo
    // tambien aqui, o la aplicacion no reconoceria al empleado como "yo".
    getSession: async () => ({ data: { session: { user: { id: (window.__DB._session || {}).profile_id || window.__DB._profile.id } } } }),
    getProfile: async () => ({ data: window.__DB._profile }),
    list: async (table, options) => {
      // Recorded so tests can assert on query shape (e.g. that the POD archive
      // index selects only its key columns and never the base64 payloads).
      window.__DB.__calls = window.__DB.__calls || [];
      window.__DB.__calls.push({ table, select: (options || {}).select || '*', options: JSON.parse(JSON.stringify(options || {})) });
      const o = options || {};
      const rows = rowsFor(table, options);
      // count/head como en PostgREST: el recuento se calcula ANTES del limit,
      // y con head:true no vuelve ni una fila. Si el doble devolviera las filas
      // igualmente, una pantalla podría contar sobre ellas y parecer correcta
      // mientras en producción recibe data:null.
      if (o.count) {
        const total = rowsFor(table, Object.assign({}, o, { limit: undefined, range: undefined })).length;
        return { data: o.head ? null : rows, count: total, error: null };
      }
      return { data: rows, error: null };
    },
    // Deliberadamente NO hay select(): el GamaCloud de verdad no lo tiene. El
    // doble sí lo ofrecía, y por eso una pantalla entera —Compras— pudo pasar
    // por las pruebas llamando a C().select() y caerse en producción con
    // «C().select is not a function». Un doble más permisivo que lo real no
    // prueba nada: prueba el doble.
    insert: async (table, row) => {
      if (table === 'crm_contacts') {
        const e = chocaPrincipal(row, null);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_opportunities') {
        const e = chocaOportunidad(row, null);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_activities') {
        const e = chocaActividad(row, null);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_targets') {
        const e = chocaObjetivo(row, null);
        if (e) return { data: null, error: e };
      }
      const withId = { id: nextId(table), created_at: new Date().toISOString(), ...row };
      window.__DB[table] = window.__DB[table] || [];
      window.__DB[table].push(withId);
      return { data: withId, error: null };
    },
    upsert: async (table, row, options) => {
      // onConflict may name a composite key, e.g. 'customer_id,product_id'.
      const keys = String((options && options.onConflict) || 'id').split(',').map(k => k.trim());
      window.__DB[table] = window.__DB[table] || [];
      const arr = window.__DB[table];
      const idx = arr.findIndex(r => keys.every(k => r[k] === row[k]));
      if (idx >= 0) { arr[idx] = { ...arr[idx], ...row }; return { data: arr[idx], error: null }; }
      const withId = { id: nextId(table), created_at: new Date().toISOString(), ...row };
      arr.push(withId);
      return { data: withId, error: null };
    },
    update: async (table, id, row) => {
      if (table === 'hr_employees' && row.manager_id) {
        const e = hrManagerError(id, row.manager_id);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_contacts') {
        const e = chocaPrincipal(row, id);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_opportunities') {
        const e = chocaOportunidad(row, id);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_activities') {
        const e = chocaActividad(row, id);
        if (e) return { data: null, error: e };
      }
      if (table === 'crm_targets') {
        const e = chocaObjetivo(row, id);
        if (e) return { data: null, error: e };
      }
      const arr = window.__DB[table] || [];
      const idx = arr.findIndex(r => r.id === id);
      if (idx >= 0) arr[idx] = { ...arr[idx], ...row };
      return { data: arr[idx], error: null };
    },
    remove: async (table, id) => {
      window.__DB[table] = (window.__DB[table] || []).filter(r => r.id !== id);
      return { data: {}, error: null };
    },
    subscribe: () => {},
    db: async () => ({
      auth:{mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:'aal1',nextLevel:'aal1'}}),listFactors:async()=>({data:{totp:[]}})}},
      from: table => {
        const filters = [],orders=[];
        let readMode=false,readRange=null,readCount=false;
        const chain = {
          select: (_columns,options={}) => {readMode=true;readCount=!!options.count;return chain},
          range: (from,to) => {readRange=[from,to];return chain},
          order:(col,opts={})=>{orders.push([col,opts.ascending!==false]);return chain},
          in: (col, vals) => {filters.push([col,vals,true]);return chain},
          delete: () => chain,
          eq: (col, val) => { filters.push([col, val]); return chain; },
          then: (resolve) => {
            if(readMode){
              const rows=(window.__DB[table]||[]).filter(r=>filters.every(([c,v,many])=>many?v.includes(r[c]):r[c]===v)).sort((a,b)=>{for(const [col,asc] of orders){const n=String(a[col]??'').localeCompare(String(b[col]??''));if(n)return asc?n:-n}return 0});
              const data=readRange?rows.slice(readRange[0],readRange[1]+1):rows;
              return Promise.resolve({data:JSON.parse(JSON.stringify(data)),...(readCount?{count:rows.length}:{}),error:null}).then(resolve);
            }
            const before = (window.__DB[table] || []).length;
            window.__DB[table] = (window.__DB[table] || []).filter(r => !filters.every(([c, v]) => r[c] === v));
            return Promise.resolve({ data: null, error: null, count: before - window.__DB[table].length }).then(resolve);
          },
        };
        return chain;
      },
      rpc: async (fn, args) => {
        if(fn==='gama_sales_invoice_balances')return {data:(window.__DB.external_invoices||[]).filter(i=>args.p_ids.includes(i.id)).map(i=>{const paid=(window.__DB.external_invoice_payments||[]).filter(p=>p.invoice_id===i.id&&p.status==='confirmed').reduce((a,p)=>a+Number(p.amount),0),credit=(window.__DB.return_credits||[]).filter(c=>c.invoice_id===i.id).reduce((a,c)=>a+Number(c.amount),0),withheld=(window.__DB.accounting_withholdings||[]).filter(w=>w.invoice_id===i.id&&w.status==='posted').reduce((a,w)=>a+Number(w.total),0),balance=i.fiscal_status==='cancelled'?0:Math.max(0,Number(i.total)-paid-credit-withheld);return {id:i.id,paid,balance,due_date:i.due_date,payment_status:i.fiscal_status==='cancelled'?'cancelled':balance===0?'paid':i.due_date&&i.due_date<new Date().toISOString().slice(0,10)?'overdue':balance<Number(i.total)?'partial':'pending'}})};
        if(fn==='gama_customer_credit_status')return {data:{customer_id:args.p_customer,credit_limit:null,hold_reason:null,receivable:0,commitment:0,exposure:0,overdue:[],blocked:false}};

        if(fn==='gama_contact_person_save'){const row={...args.p_data};if(row.is_primary)for(const c of window.__DB.crm_contacts)if((row.lead_id&&c.lead_id===row.lead_id)||(row.customer_id&&c.customer_id===row.customer_id))c.is_primary=false;let result=window.__DB.crm_contacts.find(c=>c.id===args.p_id);if(result)Object.assign(result,row);else{result={...row,id:nextId('crm_contacts'),active:true};window.__DB.crm_contacts.push(result)}return {data:result,error:null};}

        if(fn==='gama_action_allowed')return {data:true};
        // Prioridades de hoy: las prepara la prueba en window.__PRIO; por defecto, nada pendiente.
        if(fn==='gama_dashboard_priorities'){
          const role=JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role;
          if(['client','cliente'].includes(role))return {error:{message:'ROLE_NOT_ALLOWED'}};
          if(window.__PRIO_FAIL)return {error:{message:'NETWORK_TEST'}};
          const items=(window.__PRIO?.items||[]).filter(x=>!x.finance_only||!['magasinier','almacenero'].includes(role));
          const groups=['magasinier','almacenero'].includes(role)?[]:(window.__PRIO?.groups||[]),extra=tone=>groups.filter(g=>g.tone===tone).reduce((n,g)=>n+g.count,0);
          return {data:{generated_at:new Date().toISOString(),today:window.__PRIO?.today||new Date().toISOString().slice(0,10),counts:{danger:items.filter(x=>x.tone==='danger').length+extra('danger'),warning:items.filter(x=>x.tone==='warning').length+extra('warning')},groups,items}};
        }
        // Pista de auditoría: movimientos de stock y cobros del __DB, con los filtros del servidor.
        if(fn==='gama_audit_trail'){
          const role=JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role;
          if(!['admin','administrador'].includes(role))return {error:{message:'ROLE_NOT_ALLOWED'}};
          window.__auditCalls=(window.__auditCalls||[]).concat([args.p_filters]);
          const f=args.p_filters||{},names=Object.fromEntries((window.__DB.profiles||[]).map(p=>[p.id,p.full_name||p.email]));
          const product=id=>(window.__DB.products||[]).find(p=>p.id===id)?.name;
          const kinds={receipt:'Recepción de compra',delivery:'Salida por entrega',inventory_adjustment:'Ajuste de inventario'};
          let rows=[...(window.__DB.stock_movements||[]).map(m=>({kind:'stock',at:m.created_at,actor_id:m.user_id,label:kinds[m.movement_type]||(m.type==='in'?'Entrada de stock':'Salida de stock'),detail:[product(m.product_id),m.reason].filter(Boolean).join(' · '),reference:m.erp_reference||null,amount:null,quantity:m.type==='in'?m.quantity:-m.quantity})),
            ...(window.__DB.external_invoice_payments||[]).map(x=>({kind:'payment',at:x.created_at,actor_id:x.created_by,label:'Cobro de cliente',detail:x.method||'',reference:x.erp_reference||null,amount:x.amount,quantity:null})),
            ...(window.__DB.tms_events||[]).map(x=>({kind:'transfer',at:x.at,actor_id:x.user_id,label:({Creada:'Entrega creada',Entregada:'Entrega completada',SALIDA_VALIDADA:'Salida de entrega validada',INCIDENTE:'Incidente de entrega',REPROGRAMADA:'Entrega reprogramada'})[x.type]||'Entrega actualizada',detail:x.note||x.customer||'',reference:(window.__DB.tms_deliveries||[]).find(d=>d.id===x.delivery_id)?.erp_reference,amount:null,quantity:null}))];
          const to=f.to?new Date(new Date(f.to).getTime()+86400000).toISOString():null;
          rows=rows.filter(r=>(!f.kind||r.kind===f.kind)&&(!f.actor||r.actor_id===f.actor)&&(!f.from||r.at>=f.from)&&(!to||r.at<to)&&(!f.search||[r.label,r.detail,r.reference].join(' ').toLowerCase().includes(String(f.search).toLowerCase())))
            .sort((a,b)=>String(b.at).localeCompare(String(a.at))).map(r=>({...r,actor:names[r.actor_id]||null}));
          const offset=Number(f.offset||0),limit=Number(f.limit||50);
          return {data:{items:rows.slice(offset,offset+limit),has_more:rows.length>offset+limit,offset,limit}};
        }
        // Modelo del correo de invitación: una fila con versión, como en el servidor.
        if(fn==='gama_save_invitation_template'){
          const row=(window.__DB.access_invitation_template||[])[0];
          if(!row||row.version!==args.p_version)return {error:{message:'TEMPLATE_STALE'}};
          if(!String(args.p_subject||'').trim()||!String(args.p_message||'').trim())return {error:{message:'INVALID_TEMPLATE'}};
          Object.assign(row,{subject:args.p_subject.trim(),message:args.p_message.trim(),version:row.version+1});
          return {data:{...row}};
        }
        // Estanterías: la misma regla que el servidor, en memoria.
        if(fn==='gama_shelf_action'){
          const d=args.p_data||{},db=window.__DB;db.warehouse_shelves=db.warehouse_shelves||[];db.warehouse_locations=db.warehouse_locations||[];
          const two=n=>String(n).padStart(2,'0'),used=l=>(db.stock_quants||[]).some(q=>q.location_id===l.id&&Number(q.quantity)>0);
          if(args.p_action==='save'){
            const cc=Number(d.column_count),rc=Number(d.row_count);if(!(cc>=1&&cc<=99&&rc>=1&&rc<=99))return {error:{message:'SHELF_SIZE_INVALID'}};
            let sh=d.id?db.warehouse_shelves.find(x=>x.id===d.id):null;
            if(!sh){const code=String(d.code||'').toUpperCase();if(!/^[A-Z]{2}$/.test(code))return {error:{message:'SHELF_CODE_INVALID'}};if(db.warehouse_shelves.some(x=>x.warehouse_id===d.warehouse_id&&x.code===code))return {error:{message:'SHELF_CODE_TAKEN'}};sh={id:'shelf-'+code,warehouse_id:d.warehouse_id,code,version:1};db.warehouse_shelves.push(sh)}
            else if(sh.version!==d.version)return {error:{message:'SHELF_STALE'}};else sh.version++;
            const extra=db.warehouse_locations.filter(l=>l.shelf_id===sh.id&&!(Number(l.code.slice(2,4))<=cc&&Number(l.code.slice(5,7))<=rc));
            const busy=extra.filter(used).map(l=>l.code);if(busy.length)return {error:{message:'SHELF_SPACE_IN_USE:'+busy.join(', ')}};
            db.warehouse_locations=db.warehouse_locations.filter(l=>!extra.includes(l));
            Object.assign(sh,{name:d.name||'',column_count:cc,row_count:rc,parent_id:d.parent_id||null});let created=0;
            for(let c=1;c<=cc;c++)for(let r=1;r<=rc;r++){const code=sh.code+two(c)+'-'+two(r);if(!db.warehouse_locations.some(l=>l.warehouse_id===sh.warehouse_id&&l.code===code)){db.warehouse_locations.push({id:'loc-'+code,warehouse_id:sh.warehouse_id,parent_id:null,code,name:(sh.name||'Estantería '+sh.code)+' · columna '+two(c)+' · fila '+two(r),type:'bin',active:true,shelf_id:sh.id});created++}}
            return {data:{...sh,spaces:cc*rc,created,removed:{deleted:extra.length,archived:0}}};
          }
          if(args.p_action==='delete'){
            const sh=db.warehouse_shelves.find(x=>x.id===d.id);if(!sh)return {error:{message:'SHELF_NOT_FOUND'}};
            const mine=db.warehouse_locations.filter(l=>l.shelf_id===sh.id),busy=mine.filter(used).map(l=>l.code);if(busy.length)return {error:{message:'SHELF_NOT_EMPTY:'+busy.join(', ')}};
            db.warehouse_locations=db.warehouse_locations.filter(l=>l.shelf_id!==sh.id);db.warehouse_shelves=db.warehouse_shelves.filter(x=>x!==sh);
            return {data:{id:sh.id,code:sh.code,removed:{deleted:mine.length,archived:0}}};
          }
        }
        // Almacenes: crear (con su raíz y sus tres zonas) y modificar, con las reglas del servidor.
        if(fn==='gama_warehouse_action'){
          const d=args.p_data||{},db=window.__DB;db.warehouses=db.warehouses||[];db.warehouse_locations=db.warehouse_locations||[];
          const role=JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role;
          if(!['admin','administrador','magasinier','almacenero'].includes(role))return {error:{message:'ROLE_NOT_ALLOWED'}};
          if(args.p_action==='delete'){
            const w=db.warehouses.find(x=>x.id===d.id&&x.active!==false);if(!w)return {error:{message:'WAREHOUSE_NOT_FOUND'}};
            const ids=db.warehouse_locations.filter(l=>l.warehouse_id===w.id).map(l=>l.id);
            if((db.stock_quants||[]).some(q=>ids.includes(q.location_id)&&(Number(q.quantity)!==0||Number(q.reserved_quantity)!==0)))return {error:{message:'WAREHOUSE_NOT_EMPTY'}};
            db.warehouses=db.warehouses.filter(x=>x!==w);db.warehouse_locations=db.warehouse_locations.filter(l=>!ids.includes(l.id));db.warehouse_shelves=(db.warehouse_shelves||[]).filter(sh=>sh.warehouse_id!==w.id);
            return {data:{id:w.id,code:w.code,archived:false}};
          }
          if(args.p_action!=='save')return {error:{message:'INVALID_ACTION'}};
          const name=String(d.name||'').trim(),address=String(d.address||'').trim()||null,city=String(d.city||'').trim()||null;
          if(!name)return {error:{message:'WAREHOUSE_NAME_REQUIRED'}};
          if(d.id){
            const w=db.warehouses.find(x=>x.id===d.id);if(!w)return {error:{message:'WAREHOUSE_NOT_FOUND'}};
            if(String(d.code||'').trim()&&String(d.code).trim().toUpperCase()!==w.code)return {error:{message:'WAREHOUSE_CODE_IMMUTABLE'}};
            Object.assign(w,{name,address,city});return {data:{id:w.id,code:w.code,name,address,city}};
          }
          const code=String(d.code||'').trim().toUpperCase();
          if(!/^[A-Z0-9][A-Z0-9._-]{0,23}$/.test(code))return {error:{message:'WAREHOUSE_CODE_INVALID'}};
          if(db.warehouses.some(x=>x.code===code))return {error:{message:'WAREHOUSE_CODE_TAKEN'}};
          const id='wh-'+code,root={id:'loc-'+code+'-STOCK',warehouse_id:id,parent_id:null,code:'STOCK',name:'Existencias',type:'warehouse',active:true,role:null};
          db.warehouses.push({id,code,name,address,city,active:true});db.warehouse_locations.push(root);
          for(const [r,c,n] of [['arrival','LLEGADA','Zona de llegada'],['departure','SALIDA','Zona de salida'],['quarantine','CUARENTENA','Cuarentena']])
            db.warehouse_locations.push({id:'loc-'+code+'-'+c,warehouse_id:id,parent_id:root.id,code:c,name:n,type:'zone',role:r,active:true});
          return {data:{id,code,name,address,city,created:true}};
        }
        // Otras ubicaciones: crear, renombrar y quitar, con las reglas del servidor.
        if(fn==='gama_location_action'){
          const d=args.p_data||{},db=window.__DB;db.warehouse_locations=db.warehouse_locations||[];
          if(args.p_action==='save'){
            const name=String(d.name||'').trim();if(!name)return {error:{message:'LOCATION_NAME_REQUIRED'}};
            if(d.id){const l=db.warehouse_locations.find(x=>x.id===d.id);if(!l)return {error:{message:'LOCATION_NOT_FOUND'}};l.name=name;return {data:{id:l.id,code:l.code,name,role:l.role||null}}}
            const code=String(d.code||'').trim().toUpperCase();
            if(!/^[A-Z0-9][A-Z0-9._-]{0,23}$/.test(code))return {error:{message:'LOCATION_CODE_INVALID'}};
            if(/^[A-Z]{2}\d{2}-\d{2}$/.test(code))return {error:{message:'LOCATION_CODE_RESERVED'}};
            if(db.warehouse_locations.some(x=>x.warehouse_id===d.warehouse_id&&x.code===code))return {error:{message:'LOCATION_CODE_TAKEN'}};
            const root=db.warehouse_locations.find(x=>x.warehouse_id===d.warehouse_id&&x.type==='warehouse');
            const row={id:'loc-'+code,warehouse_id:d.warehouse_id,parent_id:root?.id||null,code,name,type:'zone',active:true,role:null};db.warehouse_locations.push(row);
            return {data:{id:row.id,code,name,role:null}};
          }
          if(args.p_action==='delete'){
            const l=db.warehouse_locations.find(x=>x.id===d.id);if(!l)return {error:{message:'LOCATION_NOT_FOUND'}};
            if(l.role)return {error:{message:'LOCATION_ROLE_REQUIRED'}};
            if((db.stock_quants||[]).some(q=>q.location_id===l.id&&Number(q.quantity)>0))return {error:{message:'LOCATION_NOT_EMPTY'}};
            db.warehouse_locations=db.warehouse_locations.filter(x=>x!==l);return {data:{deleted:1,archived:0,id:l.id,code:l.code}};
          }
        }
        if(fn==='gama_resolve_price'){
          const p=(window.__DB.products||[]).find(p=>p.id===args.p_product),c=(window.__DB.customers||[]).find(c=>c.id===args.p_customer),special=(window.__DB.customer_special_prices||[]).find(x=>x.customer_id===c?.id&&x.product_id===p?.id);
          return {data:{unit_price:c?.category==='C'&&special?special.unit_price:c?.category==='B'?p?.sale_price_b??p?.sale_price:p?.sale_price,label:special?'Contrato':'Categoría'}};
        }
        if(fn==='gama_catalog_command'){
          const data=args.p_data||{},lines=(data.lines||[]).map(l=>{const p=window.__DB.products.find(p=>p.id===l.product_id);return {...l,unit_price:p.sale_price,tax_rate:p.tax_rate||0}});
          if(args.p_action==='preview')return {data:lines};if(args.p_action==='history')return {data:[]};
          if(args.p_action==='submit'){const id=nextId('customer_requests'),total=lines.reduce((n,l)=>n+Math.round(l.quantity*l.unit_price*100)/100+Math.round(l.quantity*l.unit_price*l.tax_rate)/100,0);(window.__DB.customer_requests||=[]).push({id,total,notes:data.notes,requested_delivery_date:data.requested_delivery_date});(window.__DB.customer_request_lines||=[]).push(...lines.map(l=>({...l,request_id:id})));return {data:{id,total}}}
        }

        if(fn==='gama_legacy_quote_save'){
          const d=args.p_data,role=JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role;
          if(!['admin','commercial'].includes(role))return {error:{message:'ROLE_NOT_ALLOWED'}};
          const receipts=window.__DB._quoteReceipts||(window.__DB._quoteReceipts={});
          if(receipts[d.request_key])return {data:receipts[d.request_key]};
          if(!d.lines?.length||d.lines.some(l=>!window.__DB.products.some(p=>p.id===l.product_id)||l.quantity<=0||l.unit_price<0))return {error:{message:'INVALID_LINES'}};
          const id=nextId('invoices'),number='COT-'+String((window.__DB.invoices||[]).length+1).padStart(9,'0'),date=new Date().toISOString();
          const lines=d.lines.map(l=>{const net=Math.round(l.quantity*l.unit_price*100)/100;return {...l,id:nextId('invoice_lines'),invoice_id:id,line_total:net+Math.round(net*l.tax_rate)/100};});
          const subtotal=lines.reduce((s,l)=>s+Math.round(l.quantity*l.unit_price*100)/100,0),total=lines.reduce((s,l)=>s+l.line_total,0),tax=Math.round((total-subtotal)*100)/100;
          (window.__DB.invoices||=[]).push({id,invoice_number:number,customer_id:d.customer_id,issue_date:date,subtotal,tax,total,status:'issued',quote_state:'draft',quote_details:d.details,notes:d.notes});
          (window.__DB.invoice_lines||=[]).push(...lines);
          return {data:receipts[d.request_key]={id,number,date,subtotal,tax,total}};
        }
        if(fn==='gama_home_kpis'){
          const session=JSON.parse(localStorage.getItem('gama_session_v1')||'{}'),user=session.id||'test-admin-uid';
          if(window.__kpiError)return {error:{message:'TEST_UNAVAILABLE'}};
          const catalog=window.ArchitectKpiCatalog||[],role=session.role;
          const allowed=catalog.filter(x=>!['client','cliente'].includes(role)&&(!['magasinier','almacenero'].includes(role)||['stock','logistics','projects','purchasing'].includes(x.group)&&x.id!=='suppliers_active'||x.id==='orders')).map(x=>x.id);
          const key='mock:kpi:'+user,defaults=['invoiced','orders','late_deliveries','clients_active'];
          if(args?.p_selected){if(args.p_user!==user)return {error:{message:'AUTH_CHANGED'}};localStorage.setItem(key,JSON.stringify(args.p_selected))}
          const selected=[...new Set([...JSON.parse(localStorage.getItem(key)||JSON.stringify(defaults)),...allowed])].filter(x=>allowed.includes(x)).slice(0,4);
          const source={invoiced:1840,orders:7,late_deliveries:2,clients_active:(window.__DB.customers||[]).filter(x=>x.active!==false).length,...window.__kpiValues};
          return {data:{user_id:user,allowed,selected,values:Object.fromEntries(selected.map(id=>[id,Object.hasOwn(source,id)?source[id]:0])),unavailable:[],generated_at:new Date().toISOString()}};
        }
        if(fn==='gama_company_action'){
          const p=window.__DB.company_settings?.[0]||{},role=JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role;
          const profile={...window.GamaCompanyCore?.defaults,...p};
          if(args.p_action==='get')return {data:profile};
          if(!['admin','administrador'].includes(role))return {error:{message:'COMPANY_ADMIN_REQUIRED'}};
          if(args.p_action==='options')return {data:{ledger_empty:true,templates:[]}};
          if(args.p_action==='save'){
            if(args.p_data.company_version!==profile.company_version)return {error:{message:'COMPANY_STALE'}};
            const saved={...profile,...args.p_data,configured:true,company_version:profile.company_version+1};delete saved.install_localization;
            window.__DB.company_settings=[saved];return {data:saved};
          }
        }
        if(fn==='gama_hr_directory')return {data:hrIsAdmin()?(window.__DB.profiles||[]):[]};
        if(fn==='gama_hr_save_employee'){
          const id=args.p_id||nextId('hr_employees');
          if(args.p_employee?.manager_id){const e=hrManagerError(id,args.p_employee.manager_id);if(e)return {data:null,error:e}}
          const rows=window.__DB.hr_employees=window.__DB.hr_employees||[];
          const old=rows.find(r=>r.id===id);if(old)Object.assign(old,args.p_employee);else rows.push({id,active:true,...args.p_employee});
          const priv=window.__DB.hr_employee_private=window.__DB.hr_employee_private||[];
          const p=priv.find(r=>r.employee_id===id);if(p)Object.assign(p,args.p_private);else priv.push({employee_id:id,...args.p_private});
          return {data:id,error:null};
        }
        if(fn==='gama_refund_accounts')return {data:(window.__DB.financial_accounts||[]).filter(a=>a.active)};
        if(fn==='gama_tms_today_counts'){
          const db=window.__DB,day=args?.p_day||db.__today,ds=(db.tms_deliveries||[]).filter(d=>d.delivery_date===day&&!['Entregada','Cancelada'].includes(d.status));
          const shipped=d=>(db.sales_deliveries||[]).find(s=>s.tms_delivery_id===d.id)?.departed_at;
          return {data:{preparation:(db.sales_orders||[]).filter(o=>o.status==='confirmed'&&(db.sales_order_lines||[]).some(l=>l.order_id===o.id&&Number(l.quantity)>(db.sales_delivery_lines||[]).filter(x=>x.order_line_id===l.id).reduce((n,x)=>n+Number(x.quantity),0))).length,planning:ds.filter(d=>!d.route_id&&!shipped(d)).length,loading:ds.filter(d=>d.route_id&&!shipped(d)).length,proof:ds.filter(shipped).length,incidents:ds.filter(d=>d.status==='Excepción').length}};
        }
        if(fn==='gama_tms_save_gps'){
          const d=window.__DB.tms_deliveries.find(d=>d.id===args.p_data.delivery_id);if(!d)return {error:{message:'DELIVERY_NOT_FOUND'}};
          Object.assign(d,{lat:args.p_data.lat,lng:args.p_data.lng});const c=(window.__DB.customers||[]).find(c=>c.id===d.customer_id&&String(c.address||'').trim().toLowerCase()===String(d.address||'').trim().toLowerCase());
          if(c)Object.assign(c,{lat:d.lat,lng:d.lng,gps_address:c.address});return {data:{delivery_id:d.id,customer_saved:!!c}};
        }
        if(fn==='gama_tms_my_route'){
          const db=window.__DB,employee=(db.hr_employees||[]).find(h=>h.active!==false&&h.profile_id===db._profile.id),driver=(db.fleet_drivers||[]).find(f=>f.active!==false&&employee&&f.employee_id===employee.id);
          if(!driver)return {data:{driver:null,routes:[],deliveries:[]}};
          const routes=(db.tms_routes||[]).filter(r=>r.driver_id===driver.id&&(r.route_date===db.__today||['En ruta','En tránsito'].includes(r.status))&&r.status!=='Cancelada');
          const deliveries=(db.tms_deliveries||[]).filter(d=>d.driver_id===driver.id&&d.delivery_date<=db.__today&&routes.some(r=>r.id===d.route_id)&&d.status!=='Cancelada').map(d=>({...d,phone:(db.customers||[]).find(c=>c.id===d.customer_id)?.phone,...(db.sales_deliveries||[]).find(s=>s.tms_delivery_id===d.id),id:d.id}));
          return {data:{driver:{id:driver.id,name:driver.name},routes,deliveries}};
        }
        if(fn==='gama_tms_move_stop'){
          const db=window.__DB,p=args.p_data,d=db.tms_deliveries.find(d=>d.id===p.delivery_id),source=db.tms_routes.find(r=>r.id===d?.route_id),target=db.tms_routes.find(r=>r.id===p.target_route_id);
          if(!source||!target)return {error:{message:'ROUTE_NOT_FOUND'}};if((source.version||1)!==p.source_version||(target.version||1)!==p.target_version)return {error:{message:'ROUTE_STALE'}};
          if([source,target].some(r=>r.status!=='Planificada'))return {error:{message:'ROUTE_CLOSED'}};
          const changes=[...new Set([source,target])].map(r=>{const ids=r.stops.filter(id=>id!=='__depot'&&id!==d.id);if(r===target){const before=ids.indexOf(p.before_stop_id);ids.splice(before<0?ids.length:before,0,d.id)}const ds=ids.map(id=>db.tms_deliveries.find(d=>d.id===id)),vehicle=db.fleet_vehicles.find(v=>v.id===r.vehicle_id);return {r,ids,weight:ds.reduce((n,d)=>n+Number(d.weight||0),0),volume:ds.reduce((n,d)=>n+Number(d.volume||0),0),vehicle}});
          if(changes.some(c=>c.weight>c.vehicle.payload_kg||(c.vehicle.cargo_volume_m3&&c.volume>c.vehicle.cargo_volume_m3)))return {error:{message:'ROUTE_CAPACITY'}};
          for(const c of changes){const depot=c.r.stops[0]==='__depot',back=c.r.stops.at(-1)==='__depot';Object.assign(c.r,{stops:[...(depot?['__depot']:[]),...c.ids,...(back?['__depot']:[])],weight:c.weight,volume:c.volume,manual_override:true,version:(c.r.version||1)+1})}
          Object.assign(d,{route_id:target.id,driver_id:target.driver_id});return {data:{delivery_id:d.id,route_id:target.id}};
        }
        if(fn==='gama_tms_delivery_action'){
          const db=window.__DB,p=args.p_data,a=args.p_action,d=(db.tms_deliveries||[]).find(d=>d.id===p.delivery_id),s=(db.sales_deliveries||[]).find(s=>s.tms_delivery_id===d?.id);if(!d)return {error:{message:'DELIVERY_NOT_FOUND'}};
          db.__tmsOperationCalls=(db.__tmsOperationCalls||[]).concat([{action:a,data:p}]);
          if(a==='context')return {data:{delivery:{...d},phone:(db.customers||[]).find(c=>c.id===d.customer_id)?.phone,eta:d.eta_at,packages:(db.fulfillment_packages||[]).filter(x=>x.shipment_id===s?.id),invoices:(db.external_invoices||[]).filter(i=>i.order_id===s?.order_id).map(i=>({...i,reference:i.erp_reference||i.number,balance:Number(i.total)-(db.external_invoice_payments||[]).filter(x=>x.invoice_id===i.id).reduce((n,x)=>n+Number(x.amount),0)})),accounts:db.financial_accounts||[],returns:db.return_orders||[]}};
          db.__tmsReceipts=db.__tmsReceipts||{};if(db.__tmsReceipts[p.request_key])return {data:db.__tmsReceipts[p.request_key]};let result;
          if(a==='message'){d.eta_at=p.eta;result={eta:p.eta,token:'73000000-0000-4000-8000-000000000001'}}
          if(a==='incident'){if(!s?.departed_at)return {error:{message:'DEPARTURE_REQUIRED'}};d.status='Excepción';(db.tms_delivery_incidents=db.tms_delivery_incidents||[]).push({...p,created_at:new Date().toISOString(),driver_id:d.driver_id});result={delivery_id:d.id,status:d.status}}
          if(a==='reschedule'){if(d.status!=='Excepción')return {error:{message:'INCIDENT_REQUIRED'}};const date=new Date(db.__today+'T12:00:00Z');date.setUTCDate(date.getUTCDate()+1);d.delivery_date=date.toISOString().slice(0,10);d.eta_at=null;result={delivery_id:d.id,day:d.delivery_date}}
          if(a==='partial_return'){if(!p.package_ids?.length)return {error:{message:'PACKAGE_REQUIRED'}};for(const pk of db.fulfillment_packages||[])if(p.package_ids.includes(pk.id))pk.rejected=true;result={id:'ret-tms',number:'RET-00000001'};(db.return_orders=db.return_orders||[]).push(result)}
          if(a==='collect'){const i=(db.external_invoices||[]).find(i=>i.id===p.invoice_id),payments=db.external_invoice_payments=db.external_invoice_payments||[],paid=payments.filter(x=>x.invoice_id===i?.id).reduce((n,x)=>n+Number(x.amount),0);if(!i||p.amount<=0)return {error:{message:'INVALID_PAYMENT_AMOUNT'}};if(p.amount+paid>Number(i.total))return {error:{message:'PAYMENT_EXCEEDS_BALANCE'}};result={id:nextId('external_invoice_payments'),reference:'COB-00000001',amount:p.amount};payments.push({...p,...result,status:'confirmed'})}
          db.__tmsReceipts[p.request_key]=result;return {data:result};
        }
        if(fn==='gama_tms_metrics')return {data:{delivered:2,with_eta:2,on_time:1,days:[{day:window.__DB.__today,km:42,cost:10.5,missing_cost:0}],drivers:[{name:'Conductor 1',incidents:1}]}};
        if(fn==='gama_tms_capture'){
          if(window.__proofOffline)return {error:{message:'Network unavailable'}};
          const d=args.p_data,delivery=window.__DB.tms_deliveries.find(x=>x.id===d.delivery_id);
          let proof=window.__DB.tms_proofs.find(x=>x.delivery_id===d.delivery_id);
          if(!proof){proof={id:nextId('tms_proofs'),delivery_id:d.delivery_id};window.__DB.tms_proofs.push(proof)}
          if(d.photo)proof.photo=d.photo;if(d.signature)proof.signature=d.signature;proof.captured_at=d.captured_at;proof.received_at=new Date().toISOString();if(d.gps)Object.assign(proof,{gps_status:d.gps.status,latitude:d.gps.lat,longitude:d.gps.lng,gps_accuracy_m:d.gps.accuracy,gps_recorded_at:d.gps.at});
          if(d.complete)Object.assign(delivery,{status:'Entregada',actual_arrival:d.captured_at,delivered_at:d.captured_at});
          return {data:{delivery_id:delivery.id,complete:d.complete}};
        }
        if(fn==='gama_tms_plan_day'){
          if(window.__DB.__planError)return {error:{message:window.__DB.__planError}};
          window.__DB.__planCalls=(window.__DB.__planCalls||0)+1;
          const day=args?.p_day||new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
          const ds=window.__DB.tms_deliveries||[],rs=window.__DB.tms_routes||[],shipments=window.__DB.sales_deliveries||[];
          const ids=ds.filter(d=>d.delivery_date===day&&shipments.some(s=>s.tms_delivery_id===d.id)).map(d=>d.id);
          const locked=rs.filter(r=>r.manual_override||['En ruta','En tránsito','Terminada','Cancelada'].includes(r.status)||ds.some(d=>d.route_id===r.id&&(['En carga','En tránsito','En ruta','Entregada'].includes(d.status)||shipments.some(s=>s.tms_delivery_id===d.id&&s.departed_at))));
          const eligible=ds.filter(d=>ids.includes(d.id)&&['Pendiente de preparación','Planificada','Lista para envío','Excepción'].includes(d.status)&&!locked.some(r=>r.id===d.route_id));
          const settings=(window.__DB.tms_settings||[])[0]||{};
          const point=d=>d.lat!=null&&d.lng!=null&&Math.abs(+d.lat)<=85&&Math.abs(+d.lng)<=180;
          const fleet=window.__DB.fleet_drivers||[],vehicles=window.__DB.fleet_vehicles||[],assignments=window.__DB.fleet_assignments||[];
          const drivers=fleet.filter(d=>d.active!==false&&!locked.some(r=>r.driver_id===d.id)&&!(window.__DB.hr_absences||[]).some(a=>a.employee_id===d.employee_id&&a.status==='aprobada'&&a.start_date<=day&&a.end_date>=day)).map(d=>({d,v:vehicles.find(v=>v.id===assignments.find(a=>a.driver_id===d.id&&!a.ended_on)?.vehicle_id)})).filter(x=>x.v?.status==='in_service');
          const fingerprint=JSON.stringify([day,eligible.map(d=>[d.id,d.lat,d.lng,d.weight,d.volume,d.priority]),drivers,settings]);
          if(window.__DB.__planHash===fingerprint)return {data:{...window.__DB.__planSummary,changed:false,order_delivery_ids:ids}};
          window.__DB.tms_routes=rs.filter(r=>locked.includes(r)||r.route_date!==day);
          eligible.forEach(d=>{d.route_id=null;d.driver_id=null});let remaining=eligible.filter(point),planned=0;
          for(const {d,v} of drivers){let weight=0,volume=0;const chosen=[];if(!v.payload_kg)continue;
           remaining.forEach(s=>{if(weight+Number(s.weight||0)<=v.payload_kg&&(!v.cargo_volume_m3||volume+Number(s.volume||0)<=v.cargo_volume_m3)){chosen.push(s);weight+=Number(s.weight||0);volume+=Number(s.volume||0)}});
           if(!chosen.length)continue;const route={id:nextId('tms_routes'),route_date:day,driver_id:d.id,driver_name:d.name,vehicle_id:v.id,vehicle:v.plate,stops:chosen.map(s=>s.id),weight,volume,distance:5,status:'Planificada',version:1};
           if(settings.depot_lat!=null){route.stops.unshift('__depot');if(settings.return_depot!==false)route.stops.push('__depot')}
           window.__DB.tms_routes.push(route);chosen.forEach(s=>{s.route_id=route.id;s.driver_id=d.id;if(s.status!=='Lista para envío')s.status='Planificada'});planned+=chosen.length;remaining=remaining.filter(s=>!chosen.includes(s));
          }
          const missing=eligible.filter(d=>!point(d)).map(d=>d.id),summary={today:day,total:eligible.length,planned,changed:true,without_coordinates:missing.length,without_capacity:remaining.length,order_delivery_ids:ids,geocode_delivery_ids:missing,depot_missing:settings.depot_lat==null};
          window.__DB.__planHash=fingerprint;window.__DB.__planSummary=summary;return {data:summary};
        }
        if(fn==='gama_tms_resources'){
          const role=(JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role)||'';
          if(!['admin','administrador','magasinier','almacenero'].includes(role))
            return {error:{message:'ROLE_NOT_ALLOWED'}};
          const drivers=window.__DB.fleet_drivers||[],vehicles=window.__DB.fleet_vehicles||[],
                assigns=window.__DB.fleet_assignments||[],today=new Date().toISOString().slice(0,10);
          return {data:drivers.filter(d=>d.active!==false).map(d=>{
            const a=assigns.find(x=>x.driver_id===d.id&&!x.ended_on)||{};
            const v=vehicles.find(x=>x.id===a.vehicle_id&&x.active!==false)||{};
            return {driver_id:d.id,name:d.name,phone:d.phone||null,employee_id:d.employee_id||null,
              vehicle_id:v.id||null,plate:v.plate||null,brand:v.brand||null,model:v.model||null,
              kind:v.kind||null,vehicle_status:v.status||null,
              max_weight:Number(v.payload_kg||0),max_volume:Number(v.cargo_volume_m3||0),
              available:!!v.id&&v.status==='in_service',
              absent:(window.__DB.hr_absences||[]).some(x=>x.employee_id===d.employee_id
                &&x.status==='aprobada'&&x.start_date<=today&&x.end_date>=today)};
          })};
        }
        if(fn==='gama_hr_licences'){
          if(!hrIsAdmin())return {error:{message:'ROLE_NOT_ALLOWED'}};
          const drivers=window.__DB.fleet_drivers=window.__DB.fleet_drivers||[];
          const today=new Date().toISOString().slice(0,10);
          if(args.p_action==='save'){
            const d=args.p_data;let row=drivers.find(x=>x.employee_id===d.employee_id&&x.active!==false);
            if(!row){row={id:nextId('fleet_drivers'),employee_id:d.employee_id,active:true};drivers.push(row)}
            Object.assign(row,{licence_number:d.licence_number||null,licence_expiry:d.licence_expiry||null,
              phone:d.phone||row.phone||null,
              licence_categories:(d.licence_categories||[]).map(c=>String(c).toUpperCase())});
            return {data:{driver_id:row.id,employee_id:d.employee_id}};
          }
          const days=v=>v?Math.round((Date.parse(v+'T12:00:00Z')-Date.parse(today+'T12:00:00Z'))/86400000):null;
          return {data:{today,external:drivers.filter(d=>d.active!==false&&!d.employee_id).length,
            rows:(window.__DB.hr_employees||[]).filter(e=>e.active!==false).map(e=>{
              const d=drivers.find(x=>x.employee_id===e.id&&x.active!==false)||{};
              return {employee_id:e.id,full_name:e.full_name,position:e.position||null,
                department:e.department||null,driver_id:d.id||null,phone:d.phone||null,
                licence_number:d.licence_number||null,licence_categories:d.licence_categories||[],
                licence_expiry:d.licence_expiry||null,days_remaining:days(d.licence_expiry),
                vehicles:d.vehicles||[]}})}};
        }
        if(fn==='gama_quote_reservations')return {data:[]};
        if(fn==='gama_internal_invoice_action'){
          window.__internalCalls=window.__internalCalls||[];window.__internalCalls.push(args);
          if(window.__internalError)return {error:{message:window.__internalError}};
          if(args.p_action==='eligibility')return {data:args.p_data.quote_ids.map(quote_id=>({quote_id,ready:window.__deliveryValidated===true,invoice_id:(window.__DB.external_invoices||[]).find(i=>i.source_quote_id===quote_id&&i.fiscal_status!=='cancelled')?.id}))};
          if(args.p_action==='report')return {data:window.__financialInvoices||[]};
          if(args.p_action==='create')return {data:(window.__DB.external_invoices||[]).find(i=>i.source_quote_id===args.p_data.quote_id)};
          if(args.p_action==='link_external')return {data:(window.__DB.external_invoices||[]).find(i=>i.id===args.p_data.invoice_id)};
        }

        if(fn==='gama_inventory_snapshot'){
          const canBuy=['administrador','comercial'].includes(window.__DB._profile.role),ware=args.p_warehouse,until=args.p_until;
          const locations=(window.__DB.warehouse_locations||[]).filter(l=>!ware||l.warehouse_id===ware).map(l=>l.id);
          return {data:{rows:(window.__DB.products||[]).filter(p=>p.active!==false&&p.product_kind!=='service').map(p=>{
            const qs=(window.__DB.stock_quants||[]).filter(q=>q.product_id===p.id&&locations.includes(q.location_id));
            const physical=qs.reduce((s,q)=>s+Number(q.quantity||0),0),reserved=qs.reduce((s,q)=>s+Number(q.reserved_quantity||0),0);
            const incoming=canBuy?(window.__DB.purchase_order_lines||[]).filter(l=>l.product_id===p.id).reduce((s,l)=>{const o=(window.__DB.purchase_orders||[]).find(o=>o.id===l.purchase_order_id);return s+(o&&['sent','partial'].includes(o.status)&&(!ware||locations.includes(o.destination_location_id))&&(!until||(o.expected_date&&o.expected_date.slice(0,10)<=until))?Math.max(0,Number(l.quantity)-Number(l.received_quantity||0)):0)},0):null;
            return {id:p.id,physical,reserved,available:physical-reserved,incoming,projected:incoming===null?null:physical-reserved+incoming,current_cost_value:physical*Number(p.purchase_price||0)};
          })}};
        }
        if(fn==='gama_stock_insights'){
          const role=window.__DB._profile.role,canBuy=['administrador','comercial'].includes(role),canCount=['administrador','almacenero'].includes(role);
          if(!['administrador','comercial','almacenero'].includes(role))return {error:{message:'ROLE_NOT_ALLOWED'}};
          if(window.__stockInsightsError)return {error:{message:window.__stockInsightsError}};
          const today=new Date().toISOString().slice(0,10);
          const supplied=window.__stockInsights?.[args.p_view];
          const rows=supplied?.rows||(window.__DB.products||[]).filter(p=>p.active!==false&&p.product_kind!=='service').map(p=>{
            const qs=(window.__DB.stock_quants||[]).filter(q=>q.product_id===p.id),physical=qs.reduce((s,q)=>s+Number(q.quantity||0),0),reserved=qs.reduce((s,q)=>s+Number(q.reserved_quantity||0),0);
            const rule=(window.__DB.reorder_rules||[]).find(r=>r.product_id===p.id&&r.active!==false),min=Number(rule?.min_quantity??p.min_stock??0),max=Number(rule?.max_quantity??p.max_stock??0);
            let incoming=0,drafts=0;for(const l of (window.__DB.purchase_order_lines||[]).filter(l=>l.product_id===p.id)){const o=(window.__DB.purchase_orders||[]).find(o=>o.id===l.purchase_order_id);if(['sent','partial'].includes(o?.status))incoming+=Math.max(0,Number(l.quantity)-Number(l.received_quantity||0));if(o?.status==='draft')drafts+=Number(l.quantity)}
            const supplier=(window.__DB.suppliers||[]).find(s=>s.id===(rule?.supplier_id||p.supplier_id)&&s.active!==false),net=physical-reserved+incoming+drafts;
            return {id:p.id,name:p.name,reference:p.reference,on_hand:physical,reserved,available:physical-reserved,incoming:canBuy?incoming:null,draft_quantity:canBuy?drafts:null,projected:canBuy?net:null,min_quantity:min,max_quantity:max,target_min:min,target_max:Math.max(min,max),suggested_quantity:canBuy&&!p.replenishment_excluded&&net<min?Math.max(min,max)-net:0,supplier_id:canBuy?supplier?.id:null,supplier_name:canBuy?supplier?.name:null,lead_time_days:rule?.lead_time_days||7,lead_configured:!!rule?.lead_time_days,basis:'thresholds',value:physical*Number(p.purchase_price||0),importance:'C',days_without_out:100,last_out:null,repeated_discrepancies:0};
          });
          return {data:{today,as_of:new Date().toISOString(),can_buy:canBuy,can_count:canCount,rows,late_orders:[],adjustments:[],counts:canCount?window.__DB.inventory_counts||[]:[],people:canCount?(window.__DB.profiles||[]).map(p=>({id:p.id,name:p.full_name})):[],...supplied}};
        }
        if(fn==='gama_stock_replenish'){
          const d=args.p_data;window.__stockReplenishmentCalls=(window.__stockReplenishmentCalls||[]).concat(structuredClone(d));
          const receipts=window.__stockReplenishmentReceipts ||= {};if(receipts[d.request_key])return {data:receipts[d.request_key]};
          if(window.__stockReplenishError)return {error:{message:window.__stockReplenishError}};
          const orders=[];for(const sid of new Set(d.items.map(i=>i.supplier_id))){const items=d.items.filter(i=>i.supplier_id===sid),id=nextId('purchase_orders'),number='OC-STOCK-'+id;
            (window.__DB.purchase_orders ||= []).push({id,supplier_id:sid,status:'draft',order_number:number,source_kind:'low_stock',created_at:new Date().toISOString()});
            for(const i of items)(window.__DB.purchase_order_lines ||= []).push({id:nextId('purchase_order_lines'),purchase_order_id:id,product_id:i.product_id,quantity:i.quantity,received_quantity:0});
            orders.push({id,number,supplier_id:sid,lines:items.length});
          }
          const result={orders,products:d.items.length};receipts[d.request_key]=result;
          for(const view of Object.values(window.__stockInsights||{}))for(const r of view.rows||[])if(d.items.some(i=>i.product_id===r.id)){r.draft_quantity=Number(r.draft_quantity||0)+Number(r.suggested_quantity||0);r.suggested_quantity=0}
          return {data:result};
        }
        if(fn==='gama_purchase_save'){
          const d=args.p_data,id=nextId('purchase_orders'),row={...d,id,status:'draft',order_number:'OC-TEST',order_date:new Date().toISOString()};delete row.lines;
          (window.__DB.purchase_orders ||= []).push(row);
          for(const line of d.lines)(window.__DB.purchase_order_lines ||= []).push({...line,id:nextId('purchase_order_lines'),purchase_order_id:id,received_quantity:0});
          return {data:{purchase_id:id}};
        }
        if(fn==='gama_receive_purchase_once')return rpcReceivePurchase({p_purchase_order_id:args.p_data.purchase_order_id,p_lines:args.p_data.lines,p_comment:args.p_data.comment});
        if (fn === 'gama_receive_purchase') return rpcReceivePurchase(args || {});
        if (fn === 'gama_stock_transfer') return mueveStock(args || {});
        if (fn === 'gama_stock_reserve') return reservaStock(args || {});
        if (fn === 'gama_stock_unreserve') return liberaReserva(args || {});
        if(fn==='gama_count_create'){
          const row={...args.p_data,id:nextId('inventory_counts'),status:'draft',created_at:new Date().toISOString()};
          (window.__DB.inventory_counts ||= []).push(row);const result=generaLineas({p_count_id:row.id});
          return result.error?result:{data:row};
        }
        if(fn==='gama_import_batch'){
          const data=args.p_data;
          if(args.p_action==='prepare'){
            const batch={id:nextId('erp_import_batches'),kind:data.kind,filename:data.filename,status:'preview'},seen=new Set();
            const rows=data.rows.map((row,i)=>{
              const key=[row.name,row.address||''].map(x=>String(x).trim().toLowerCase()).join('|');
              const exists=(window.__DB.customers||[]).some(x=>[x.name,x.address||''].map(v=>String(v).trim().toLowerCase()).join('|')===key);
              const error=seen.has(key)?'DUPLICATE_IN_FILE':exists?'DUPLICATE_CONTACT':null;seen.add(key);
              return {row_number:i+2,data:row,status:error?'error':'ready',error};
            });window.__importBatch={batch,rows};
          }else if(args.p_action==='apply'){
            for(const row of window.__importBatch.rows)if(row.status==='ready'){
              window.__DB.customers.push({id:nextId('customers'),...row.data});row.status='imported';
            }
            window.__importBatch.batch.status='partial';
          }
          return {data:structuredClone(window.__importBatch)};
        }
        if (fn === 'gama_count_generate_lines') return generaLineas(args || {});
        if (fn === 'gama_count_validate') return validaConteo(args || {});
        return { data: null, error: null };
      },
    }),
  };
  window.GamaCloudReady = Promise.resolve(window.GamaCloud);
})();
