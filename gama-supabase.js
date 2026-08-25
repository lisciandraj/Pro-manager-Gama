/* GAMA V10 — central Supabase data layer
 * The browser must use the project's public anon/publishable key only.
 * NEVER put a service_role key in this file.
 */
(function () {
  'use strict';

  const SUPABASE_URL = 'https://mknsaibrewksgomuslev.supabase.co';
  const SUPABASE_ANON_KEY = window.GAMA_SUPABASE_ANON_KEY || '';
  let client = null;
  let realtime = [];

  function emit(name, detail) {
    window.dispatchEvent(new CustomEvent(name, { detail: detail || {} }));
  }

  async function loadClient() {
    if (window.supabase && window.supabase.createClient) return window.supabase;
    if (window.__gamaSupabaseLoader) return window.__gamaSupabaseLoader;
    window.__gamaSupabaseLoader = new Promise(function (resolve, reject) {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
      s.async = true;
      s.onload = function () {
        if (window.supabase && window.supabase.createClient) resolve(window.supabase);
        else reject(new Error('Supabase JS unavailable'));
      };
      s.onerror = function () { reject(new Error('Unable to load Supabase JS')); };
      document.head.appendChild(s);
    });
    return window.__gamaSupabaseLoader;
  }

  async function init() {
    if (!SUPABASE_ANON_KEY) {
      emit('gama:cloud-status', { ready: false, configured: false, reason: 'missing_public_key' });
      console.warn('[GAMA] Supabase is ready in code but the public anon/publishable key is missing.');
      return null;
    }

    if (client) return client;
    const sb = await loadClient();
    client = sb.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });

    client.auth.onAuthStateChange(function (event, session) {
      emit('gama:auth-change', { event: event, session: session });
    });

    emit('gama:cloud-status', { ready: true, configured: true, url: SUPABASE_URL });
    return client;
  }

  async function db() {
    const c = await init();
    if (!c) throw new Error('Supabase public key not configured');
    return c;
  }

  async function getSession() {
    const c = await db();
    return c.auth.getSession();
  }

  async function signIn(email, password) {
    const c = await db();
    return c.auth.signInWithPassword({ email: email, password: password });
  }

  async function signOut() {
    const c = await db();
    return c.auth.signOut();
  }

  async function getProfile() {
    const c = await db();
    const sessionResult = await c.auth.getSession();
    const user = sessionResult.data && sessionResult.data.session && sessionResult.data.session.user;
    if (!user) return { data: null, error: null };
    return c.from('profiles').select('*').eq('id', user.id).maybeSingle();
  }

  async function list(table, options) {
    const c = await db();
    options = options || {};
    let q = c.from(table).select(options.select || '*');
    if (options.order) q = q.order(options.order, { ascending: options.ascending !== false });
    if (options.limit) q = q.limit(options.limit);
    if (options.eq) Object.keys(options.eq).forEach(function (key) { q = q.eq(key, options.eq[key]); });
    return q;
  }

  async function insert(table, row) {
    const c = await db();
    return c.from(table).insert(row).select().single();
  }

  async function update(table, id, row) {
    const c = await db();
    return c.from(table).update(row).eq('id', id).select().single();
  }

  async function remove(table, id) {
    const c = await db();
    return c.from(table).delete().eq('id', id);
  }

  async function subscribe(table, callback) {
    const c = await db();
    const channel = c.channel('gama-' + table + '-' + Date.now())
      .on('postgres_changes', { event: '*', schema: 'public', table: table }, function (payload) {
        emit('gama:data-change', { table: table, payload: payload });
        if (typeof callback === 'function') callback(payload);
      })
      .subscribe();
    realtime.push(channel);
    return channel;
  }

  function unsubscribeAll() {
    if (!client) return;
    realtime.forEach(function (channel) { try { client.removeChannel(channel); } catch (e) {} });
    realtime = [];
  }

  window.GamaCloud = {
    url: SUPABASE_URL,
    init: init,
    db: db,
    getSession: getSession,
    signIn: signIn,
    signOut: signOut,
    getProfile: getProfile,
    list: list,
    insert: insert,
    update: update,
    remove: remove,
    subscribe: subscribe,
    unsubscribeAll: unsubscribeAll,
    tables: {
      profiles: 'profiles', products: 'products', suppliers: 'suppliers', customers: 'customers',
      stockMovements: 'stock_movements', invoices: 'invoices', invoiceLines: 'invoice_lines',
      commercialMatrix: 'commercial_matrix'
    }
  };

  window.GamaCloudReady = init();
})();
