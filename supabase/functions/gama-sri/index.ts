import { createClient } from 'npm:@supabase/supabase-js@2.115.0';

const headers = { 'content-type': 'application/json', 'access-control-allow-origin': '*' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const bytes = (data: string) => Uint8Array.from(atob(data), c => c.charCodeAt(0));

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { headers: { ...headers, 'access-control-allow-headers': 'authorization,apikey,content-type', 'access-control-allow-methods': 'POST' } });
  if (request.method !== 'POST') return reply({ error: 'METHOD_NOT_ALLOWED' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const publishable = Deno.env.get('SUPABASE_ANON_KEY')!;
  const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const workerUrl = Deno.env.get('SRI_WORKER_URL');
  const workerSecret = Deno.env.get('SRI_WORKER_SECRET');
  if (!workerUrl || !workerSecret || !workerUrl.startsWith('https://')) return reply({ error: 'SRI_WORKER_NOT_CONFIGURED' }, 503);
  const bearer = request.headers.get('Authorization') || '';
  if (!bearer.startsWith('Bearer ')) return reply({ error: 'AUTH_REQUIRED' }, 401);
  const client = createClient(url, publishable, { global: { headers: { Authorization: bearer } } });
  const { data: auth, error: authError } = await client.auth.getUser(bearer.slice(7));
  if (authError || !auth.user) return reply({ error: 'AUTH_REQUIRED' }, 401);
  const { data: profile } = await client.from('profiles').select('role,active').eq('id', auth.user.id).maybeSingle();
  if (profile?.role !== 'administrador' || !profile.active) return reply({ error: 'ROLE_NOT_ALLOWED' }, 403);
  const admin = createClient(url, secret);
  let input: { action: string; id: string; kind?: string };
  try { input = await request.json(); } catch { return reply({ error: 'INVALID_JSON' }, 400); }
  if (!['submit','refresh','notify','download','retry'].includes(input.action) || !/^[a-f0-9-]{36}$/i.test(input.id)) return reply({ error: 'INVALID_REQUEST' }, 400);
  // Check the authenticated caller's RLS view as well as the admin profile.
  const { data: visible, error: viewError } = await client.from('sri_invoice_issues').select('id').eq('id', input.id).maybeSingle();
  if (viewError || !visible) return reply({ error: 'NOT_FOUND' }, 404);
  const fetchIssue = async () => {
    const { data, error } = await admin.from('sri_invoice_issues').select('*').eq('id', input.id).single();
    if (error) throw error;
    return data;
  };
  const save = async (status: string, patch: Record<string, unknown>, expected: string) => {
    const { data, error } = await admin.from('sri_invoice_issues').update({ ...patch, status, updated_at: new Date().toISOString() }).eq('id', input.id).eq('status', expected).select('*').maybeSingle();
    if (error || !data) throw Error('SRI_STATUS_CHANGED');
    return data;
  };
  const call = async (action: string, issue: unknown, extra: Record<string, unknown> = {}) => {
    const body = JSON.stringify({ action, issue, ...extra });
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(workerSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signature = Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body)))).map(x => x.toString(16).padStart(2,'0')).join('');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 45000);
    try {
      const response = await fetch(workerUrl + '/execute', { method: 'POST', headers: { 'content-type': 'application/json', 'x-sri-signature': signature }, body, signal: controller.signal });
      const result = await response.json();
      if (!response.ok) throw Error(typeof result.detail === 'string' ? result.detail : 'SRI_WORKER_FAILED');
      return result;
    } finally { clearTimeout(timeout); }
  };
  const upload = async (issue: { id: string }, name: string, content: string, mime: string) => {
    const path = issue.id + '/' + name;
    const raw = bytes(content);
    const { error } = await admin.storage.from('sri-documents').upload(path, raw, { contentType: mime, upsert: false });
    if (error) {
      if (!error.message.includes('already exists')) throw error;
      const existing = await admin.storage.from('sri-documents').download(path);
      if (existing.error) throw existing.error;
      const prior = new Uint8Array(await existing.data.arrayBuffer());
      if (prior.length !== raw.length || prior.some((value, index) => value !== raw[index])) throw Error('SRI_ARCHIVE_CONFLICT');
    }
    return path;
  };
  try {
    let issue = await fetchIssue();
    if (input.action === 'retry') {
      if (issue.access_key || !['error','processing'].includes(issue.status)) return reply({ error: 'SRI_RETRY_REQUIRES_REVIEW' }, 409);
      issue = await save('draft', { last_error: null }, issue.status);
      return reply({ id: issue.id, status: issue.status });
    }
    if (input.action === 'download') {
      if (issue.status !== 'authorized' || !['xml','ride'].includes(input.kind || '')) return reply({ error: 'SRI_NOT_AUTHORIZED' }, 409);
      const path = input.kind === 'xml' ? issue.authorized_xml_path : issue.ride_path;
      if (!path) return reply({ error: 'SRI_ARCHIVE_MISSING' }, 404);
      const { data, error } = await admin.storage.from('sri-documents').createSignedUrl(path, 60);
      if (error) throw error;
      return reply({ url: data.signedUrl });
    }
    if (input.action === 'submit') {
      if (issue.status !== 'draft') return reply({ error: 'SRI_ALREADY_SUBMITTED', status: issue.status }, 409);
      // Claim once. A timeout is not a reason to produce a second access key.
      issue = await save('processing', {}, 'draft');
      let signed;
      try { signed = await call('sign', issue); }
      catch (error) {
        await save('error', { last_error: String(error).slice(0,500) }, 'processing');
        throw error;
      }
      if (!/^[0-9]{49}$/.test(signed.access_key)) throw Error('SRI_INVALID_ACCESS_KEY');
      const signedPath = await upload(issue, 'signed.xml', signed.signed_xml, 'application/xml');
      issue = await save('signed', { access_key: signed.access_key, signed_xml_path: signedPath }, 'processing');
      // Network failure leaves the same signed document available for a lookup.
      const receipt = await call('receive', issue, { signed_xml: signed.signed_xml });
      issue = await save(receipt.status === 'received' ? 'received' : 'rejected',
        { receipt, sent_at: new Date().toISOString() }, 'signed');
      return reply({ id: issue.id, status: issue.status, access_key: issue.access_key });
    }
    if (input.action === 'refresh') {
      if (!['signed','received','processing'].includes(issue.status) || !issue.access_key) return reply({ error: 'SRI_NOT_PENDING' }, 409);
      const prior = issue.status;
      const result = await call('authorize', issue);
      if (result.status === 'authorized') {
        const xmlPath = await upload(issue, 'authorized.xml', result.authorized_xml, 'application/xml');
        const ridePath = await upload(issue, 'RIDE.pdf', result.ride_pdf, 'application/pdf');
        // A verified SRI result updates the management invoice's external reference.
        const linked = await admin.from('external_invoices').update({ external_number: [issue.establishment,issue.emission_point,issue.sequential].join('-'),
          issuer_ruc: issue.issuer_ruc, software: 'Coco ERP / SRI', external_issue_date: issue.snapshot.issue_date,
          external_status: 'authorized', access_key: issue.access_key }).eq('id', issue.source_invoice_id).eq('document_kind','internal').select('id').single();
        if (linked.error) throw linked.error;
        issue = await save('authorized', { authorization_response: { status: 'authorized', authorization: result.authorization }, authorized_xml_path: xmlPath,
          ride_path: ridePath, authorized_at: result.authorized_at || new Date().toISOString() }, prior);
      } else if (result.status === 'rejected') issue = await save('rejected', { authorization_response: result }, prior);
      return reply({ id: issue.id, status: issue.status, access_key: issue.access_key });
    }
    if (issue.status !== 'authorized' || !issue.authorized_xml_path || !issue.ride_path) return reply({ error: 'SRI_NOT_AUTHORIZED' }, 409);
    if (issue.delivered_at) return reply({ id: issue.id, delivered: true });
    const signed = await admin.storage.from('sri-documents').download(issue.authorized_xml_path);
    const pdf = await admin.storage.from('sri-documents').download(issue.ride_path);
    if (signed.error || pdf.error) throw Error('SRI_ARCHIVE_MISSING');
    const encode = async (blob: Blob) => {
      const data = new Uint8Array(await blob.arrayBuffer());
      let binary = '';
      for (let i = 0; i < data.length; i += 8192) binary += String.fromCharCode(...data.subarray(i, i + 8192));
      return btoa(binary);
    };
    await call('notify', { ...issue, authorization: issue.access_key }, { authorized_xml: await encode(signed.data), ride_pdf: await encode(pdf.data) });
    await admin.from('sri_invoice_issues').update({ delivered_at: new Date().toISOString() }).eq('id', issue.id).is('delivered_at', null);
    return reply({ id: issue.id, delivered: true });
  } catch (error) {
    return reply({ error: String(error instanceof Error ? error.message : error).slice(0,500) }, 422);
  }
});
