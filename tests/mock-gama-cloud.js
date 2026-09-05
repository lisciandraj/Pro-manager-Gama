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
  window.GamaCloud = {
    getSession: async () => ({ data: { session: { user: { id: 'test-admin-uid' } } } }),
    getProfile: async () => ({ data: { id: 'test-admin-uid', full_name: 'Test Admin', role: 'administrador', active: true } }),
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
    db: async () => ({ rpc: async () => ({ data: null, error: null }) }),
  };
  window.GamaCloudReady = Promise.resolve(window.GamaCloud);
})();
