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
  function rowsFor(table, options) {
    options = options || {};
    let rows = (window.__DB[table] || []).slice();
    if (options.eq) Object.keys(options.eq).forEach(k => { rows = rows.filter(r => r[k] === options.eq[k]); });
    if (options.order) rows.sort((a, b) => {
      const av = a[options.order], bv = b[options.order];
      const cmp = av > bv ? 1 : av < bv ? -1 : 0;
      return options.ascending !== false ? cmp : -cmp;
    });
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
    getSession: async () => ({ data: { session: { user: { id: window.__DB._profile.id } } } }),
    getProfile: async () => ({ data: window.__DB._profile }),
    list: async (table, options) => ({ data: rowsFor(table, options), error: null }),
    select: async (table) => ({ data: rowsFor(table, {}), error: null }),
    insert: async (table, row) => {
      const withId = { id: nextId(table), created_at: new Date().toISOString(), ...row };
      window.__DB[table] = window.__DB[table] || [];
      window.__DB[table].push(withId);
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
      rpc: async (fn, args) => {
        if (fn === 'gama_receive_purchase') return rpcReceivePurchase(args || {});
        return { data: null, error: null };
      },
    }),
  };
  window.GamaCloudReady = Promise.resolve(window.GamaCloud);
})();
