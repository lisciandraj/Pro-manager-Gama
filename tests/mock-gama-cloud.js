/* Minimal in-memory stand-in for gama-supabase.js's window.GamaCloud, used by
   tests to exercise real UI flows without touching the live Supabase backend.
   Loaded via page.route() fulfilling the request for gama-supabase.js. */
(function () {
  'use strict';
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
    // customer whose email matches the session — their contract price when the
    // product is in their tariff (categoría C), otherwise the price of their
    // category: B is the retail price, A (and a C with nothing pactado for the
    // product) the mayorista price on the product sheet.
    const email = String((window.__DB._profile || {}).email || '').toLowerCase();
    const me = (window.__DB.customers || []).find(c => c.active !== false && String(c.email || '').toLowerCase() === email && email);
    const items = (window.__DB.price_list_items || []).filter(i => me && i.price_list_id === me.price_list_id);
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
  function hrIsAdmin() { const r = hrRole(); return r === 'admin' || r === 'administrador'; }
  function hrIsStaff() { return ['admin', 'administrador', 'commercial', 'comercial', 'magasinier', 'almacenero'].includes(hrRole()); }
  function hrMyProfile() { return (window.__DB._session || {}).profile_id || null; }
  function hrMyEmployeeIds() {
    const me = hrMyProfile();
    return (window.__DB.hr_employees || []).filter(e => !!me && e.profile_id === me).map(e => e.id);
  }
  function hrRows(table) {
    if (table === 'hr_employees' || table === 'hr_absences') {
      return hrIsStaff() ? (window.__DB[table] || []).slice() : [];
    }
    if (hrIsAdmin()) return (window.__DB[table] || []).slice();
    const mias = hrMyEmployeeIds();
    if (table === 'hr_employee_private') {
      return (window.__DB.hr_employee_private || []).filter(r => mias.includes(r.employee_id));
    }
    const abs = (window.__DB.hr_absences || []).filter(a => mias.includes(a.employee_id)).map(a => a.id);
    return (window.__DB.hr_absence_private || []).filter(r => abs.includes(r.absence_id));
  }
  function rowsFor(table, options) {
    options = options || {};
    let rows = table === 'catalog_products' ? catalogRows()
      : /^hr_(employees|absences|employee_private|absence_private)$/.test(table) ? hrRows(table)
      : (window.__DB[table] || []).slice();
    // products.has_photo es una columna generada en la base: se deriva aqui
    // para que una consulta estrecha pueda pedirla sin traerse la foto.
    if (table === 'products') rows = rows.map(r => ({ ...r, has_photo: !!r.photo_data }));
    if (options.eq) Object.keys(options.eq).forEach(k => { rows = rows.filter(r => r[k] === options.eq[k]); });
    if (options.in) Object.keys(options.in).forEach(k => { rows = rows.filter(r => (options.in[k] || []).includes(r[k])); });
    // gte/lte los usa el analisis de ventas para acotar el periodo. Sin ellos
    // el doble devolvia TODAS las facturas y una prueba de periodo no probaba
    // nada: pasaria igual aunque el filtro no se enviara.
    if (options.gte) Object.keys(options.gte).forEach(k => { rows = rows.filter(r => r[k] >= options.gte[k]); });
    if (options.lte) Object.keys(options.lte).forEach(k => { rows = rows.filter(r => r[k] <= options.lte[k]); });
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
      const before = Number(product.stock || 0);
      product.stock = before + line.quantity;
      product.purchase_price = pol.unit_cost;
      pol.received_quantity = (pol.received_quantity || 0) + line.quantity;
      window.__DB.stock_movements = window.__DB.stock_movements || [];
      window.__DB.stock_movements.push({ id: nextId('stock_movements'), product_id: product.id, type: 'in', quantity: line.quantity, stock_before: before, stock_after: product.stock, user_id: window.__DB._profile.id, created_at: new Date().toISOString() });
    }
    const allLines = (window.__DB.purchase_order_lines || []).filter(l => l.purchase_order_id === args.p_purchase_order_id);
    const allReceived = allLines.length > 0 && allLines.every(l => (l.received_quantity || 0) >= l.quantity);
    const anyReceived = allLines.some(l => (l.received_quantity || 0) > 0);
    po.status = allReceived ? 'received' : anyReceived ? 'partial' : po.status;
    return { data: { purchase_order_id: po.id, status: po.status }, error: null };
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
      window.__DB.__calls.push({ table, select: (options || {}).select || '*' });
      return { data: rowsFor(table, options), error: null };
    },
    select: async (table) => ({ data: rowsFor(table, {}), error: null }),
    insert: async (table, row) => {
      const withId = { id: nextId(table), created_at: new Date().toISOString(), ...row };
      window.__DB[table] = window.__DB[table] || [];
      window.__DB[table].push(withId);
      return { data: withId, error: null };
    },
    upsert: async (table, row, options) => {
      // onConflict may name a composite key, e.g. 'price_list_id,product_id'.
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
      from: table => {
        const filters = [];
        const chain = {
          delete: () => chain,
          eq: (col, val) => { filters.push([col, val]); return chain; },
          then: (resolve) => {
            const before = (window.__DB[table] || []).length;
            window.__DB[table] = (window.__DB[table] || []).filter(r => !filters.every(([c, v]) => r[c] === v));
            return Promise.resolve({ data: null, error: null, count: before - window.__DB[table].length }).then(resolve);
          },
        };
        return chain;
      },
      rpc: async (fn, args) => {
        if (fn === 'gama_receive_purchase') return rpcReceivePurchase(args || {});
        return { data: null, error: null };
      },
    }),
  };
  window.GamaCloudReady = Promise.resolve(window.GamaCloud);
})();
