import { createClient } from 'npm:@supabase/supabase-js@2.115.0';

const headers = { 'content-type': 'application/json', 'access-control-allow-origin': '*' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const bytes = (data: string) => Uint8Array.from(atob(data), c => c.charCodeAt(0));

function matchesIssue(key: string, issue: { environment: string; issuer_ruc: string; establishment: string; emission_point: string; sequential: string; document_type?: string; snapshot: {issue_date: string} }): boolean {
  if (!/^[0-9]{49}$/.test(key)) return false;
  const day = issue.snapshot.issue_date.split('-').reverse().join('');
  const body = day + (issue.document_type || '01') + issue.issuer_ruc + (issue.environment === 'pruebas' ? '1' : '2') + issue.establishment + issue.emission_point + issue.sequential + key.slice(39,47) + '1';
  if (!/^[0-9]{48}$/.test(body)) return false;
  const check = 11 - [...body].reverse().reduce((total, value, i) => total + Number(value) * (i % 6 + 2), 0) % 11;
  return key === body + (check === 11 ? 0 : check === 10 ? 1 : check);
}

async function handle(request: Request, scheduled = false): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, { headers: { ...headers, 'access-control-allow-headers': 'authorization,apikey,content-type,x-client-info', 'access-control-allow-methods': 'POST' } });
  if (request.method !== 'POST') return reply({ error: 'METHOD_NOT_ALLOWED' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const publishable = Deno.env.get('SUPABASE_ANON_KEY')!;
  const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const workerUrl = Deno.env.get('SRI_WORKER_URL');
  const workerSecret = Deno.env.get('SRI_WORKER_SECRET');
  const provider = Deno.env.get('SRI_PROVIDER') || 'private_worker';
  let configured = false;
  try { const endpoint = new URL(workerUrl || '');
    configured = endpoint.protocol === 'https:' && !endpoint.username && !endpoint.password && !endpoint.search && !endpoint.hash && Boolean(workerSecret) && ['private_worker','openapi'].includes(provider);
  } catch { /* Configuration is reported safely by the status action. */ }
  const enabled = configured && Deno.env.get('SRI_EMISSION_ENABLED') === 'true';
  const bearer = request.headers.get('Authorization') || '';
  if (!bearer.startsWith('Bearer ')) return reply({ error: 'AUTH_REQUIRED' }, 401);
  const machine = bearer === 'Bearer ' + secret;
  const client = createClient(url, machine ? secret : publishable, { global: { headers: { Authorization: bearer } } });
  const { data: auth, error: authError } = machine ? {data: {user: {id: 'scheduler'}}, error: null} : await client.auth.getUser(bearer.slice(7));
  if (authError || !auth.user) return reply({ error: 'AUTH_REQUIRED' }, 401);
  const { data: profile } = machine ? {data: {role: 'administrador', active: true}} : await client.from('profiles').select('role,active').eq('id', auth.user.id).maybeSingle();
  const admin = createClient(url, secret);
  let input: { action: string; id: string; kind?: string; document_type?: string };
  try { input = await request.json(); } catch { return reply({ error: 'INVALID_JSON' }, 400); }
  if (!input || typeof input.action !== 'string') return reply({ error: 'INVALID_REQUEST' }, 400);
  // Retired ERP customer policies hide profiles. The narrow portal RPC verifies
  // the live login, MFA, membership and document ownership using the caller's JWT.
  if (!profile || profile.role === 'cliente') {
    if (input.action !== 'download' || (input.document_type || '01') !== '01' || !/^[a-f0-9-]{36}$/i.test(input.id || '') || !['xml','ride'].includes(input.kind || '')) return reply({error:'ROLE_NOT_ALLOWED'},403);
    const owned = await client.rpc('gama_b2b_action', {p_action:'sri_document',p_data:{id:input.id,kind:input.kind}});
    if (owned.error || !owned.data?.path) return reply({error:'NOT_FOUND'},404);
    const link = await admin.storage.from('sri-documents').createSignedUrl(owned.data.path,60);
    if (link.error || !link.data?.signedUrl) return reply({error:'SRI_ARCHIVE_MISSING'},404);
    return reply({url:link.data.signedUrl,filename:owned.data.filename});
  }
  if (!profile.active) return reply({ error: 'ROLE_NOT_ALLOWED' }, 403);
  // Server schedules only consult already claimed documents; they never emit or notify.
  if (machine && !scheduled) {
    if (input.action !== 'refresh_pending') return reply({error: 'ROLE_NOT_ALLOWED'},403);
    if (!configured) return reply({error: 'SRI_WORKER_NOT_CONFIGURED'},503);
    const candidates = await Promise.all(['sri_invoice_issues','sri_document_issues'].map(async table => {
      const r=await admin.from(table).select(table === 'sri_invoice_issues' ? 'id,updated_at' : 'id,document_type,updated_at').in('status',['signed','received','processing']).order('updated_at',{ascending:true}).limit(1);
      if(r.error) throw r.error;return (r.data||[]).map(d=>({...d,table}));
    }));
    const d=candidates.flat().sort((a,b)=>a.updated_at.localeCompare(b.updated_at))[0];
    if(!d)return reply({consulted:0});
    const response=await handle(new Request(request.url,{method:'POST',headers:{Authorization:bearer,'Content-Type':'application/json'},body:JSON.stringify({action:'refresh',id:d.id,document_type:d.document_type||'01'})}),true);
    const result=await response.json();
    await admin.from(d.table).update({updated_at:new Date().toISOString(),...(result.error?{last_error:result.error}:{})}).eq('id',d.id).in('status',['signed','received','processing']);
    return reply({consulted:1,id:d.id,status:result.status||'pending',error:result.error||null});
  }
  if (machine && (!scheduled || input.action !== 'refresh')) return reply({error: 'ROLE_NOT_ALLOWED'},403);
  const documentType = input.document_type || '01';
  if (!['01','03','04','06','07'].includes(documentType)) return reply({ error: 'SRI_DOCUMENT_TYPE_UNSUPPORTED' }, 400);
  const table = documentType === '01' ? 'sri_invoice_issues' : 'sri_document_issues';
  if (profile.role !== 'administrador' && input.action !== 'download') return reply({ error: 'ROLE_NOT_ALLOWED' }, 403);
  const access = machine ? {data: {validate: true, export: false}, error: null} : documentType === '01' ? await client.rpc('gama_sri_access') : await client.rpc('gama_sri_document_access', {p_id: input.id, p_action: input.action});
  if (access.error || !access.data) return reply({ error: 'ROLE_NOT_ALLOWED' }, 403);
  const call = async (action: string, issue: unknown, extra: Record<string, unknown> = {}) => {
    const body = JSON.stringify({ action, issue, ...extra });
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(workerSecret!), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signature = Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body)))).map(x => x.toString(16).padStart(2,'0')).join('');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), action === 'status' ? 5000 : 45000);
    try {
      const response = await fetch(workerUrl + '/execute', { method: 'POST', redirect: 'error', headers: { 'content-type': 'application/json', 'x-sri-signature': signature }, body, signal: controller.signal });
      const result = await response.json();
      if (!response.ok) throw Error(typeof result.detail === 'string' && /^[A-Z0-9_]{1,100}$/.test(result.detail) ? result.detail : 'SRI_WORKER_FAILED');
      return result;
    } finally { clearTimeout(timeout); }
  };
  if (input.action === 'status') {
    let worker: { configured?: boolean; provider?: string; environment?: string; document_types?: string[] } = {};
    let reachable = false;
    let diagnostic = configured ? 'SRI_EMISSION_DISABLED' : 'SRI_WORKER_NOT_CONFIGURED';
    if (configured) { try {
      const result = await call('status', null);
      if (!result || typeof result !== 'object' || Array.isArray(result)) throw Error('SRI_WORKER_INVALID_STATUS');
      worker = result; reachable = true;
    }
      catch { diagnostic = 'SRI_WORKER_UNREACHABLE'; } }
    const workerReady = worker.configured === true && worker.provider === provider;
    const ready = enabled && workerReady && access.data.validate === true;
    if (reachable) {
      if (worker.provider !== provider) diagnostic = 'SRI_WORKER_PROVIDER_MISMATCH';
      else if (!workerReady) diagnostic = 'SRI_WORKER_CONFIGURATION_INCOMPLETE';
      else if (!enabled) diagnostic = 'SRI_EMISSION_DISABLED';
      else if (access.data.validate !== true) diagnostic = 'SRI_VALIDATION_NOT_ALLOWED';
    }
    return reply({ configured, provider, ready, worker_ready: reachable && workerReady, can_refresh: configured && access.data.validate === true,
      can_export: access.data.export === true, environment: worker.environment || null,
      diagnostic: ready ? 'SRI_READY_FOR_SUPERVISED_TESTS' : diagnostic,
      document_types: Array.isArray(worker.document_types) ? worker.document_types.filter(t => ['01','03','04','06','07'].includes(t)) : ['01'] });
  }
  // A kill switch stops NEW emissions, not reconciliation of an uncertain POST.
  if ((!configured && input.action !== 'download') || (!enabled && ['submit','retry','notify'].includes(input.action)))
    return reply({ error: configured ? 'SRI_CERTIFICATION_PENDING' : 'SRI_WORKER_NOT_CONFIGURED' }, 503);
  if (input.action === 'download' ? !access.data.export : !access.data.validate) return reply({ error: 'ROLE_NOT_ALLOWED' }, 403);
  if (!['submit','refresh','notify','download','retry'].includes(input.action) || !/^[a-f0-9-]{36}$/i.test(input.id)) return reply({ error: 'INVALID_REQUEST' }, 400);
  // Check the authenticated caller's RLS view as well as the admin profile.
  const { data: visible, error: viewError } = await client.from(table).select('id').eq('id', input.id).maybeSingle();
  if (viewError || !visible) return reply({ error: 'NOT_FOUND' }, 404);
  const fetchIssue = async () => {
    const { data, error } = await admin.from(table).select('*').eq('id', input.id).single();
    if (error) throw error;
    if ((data.document_type || '01') !== documentType) throw Error('SRI_DOCUMENT_TYPE_MISMATCH');
    return data;
  };
  const save = async (status: string, patch: Record<string, unknown>, expected: string) => {
    const { data, error } = await admin.from(table).update({ ...patch, status, updated_at: new Date().toISOString() }).eq('id', input.id).eq('status', expected).select('*').maybeSingle();
    if (error || !data) throw Error('SRI_STATUS_CHANGED');
    return data;
  };
  const upload = async (issue: { id: string }, name: string, content: string, mime: string) => {
    const path = issue.id + '/' + name;
    if (typeof content !== 'string' || content.length > 1400000) throw Error('SRI_ARCHIVE_TOO_LARGE');
    const raw = bytes(content);
    if (raw.length > 1048576) throw Error('SRI_ARCHIVE_TOO_LARGE');
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
  const settleWithholding = async (id: string) => {
    const result = await client.rpc('gama_sri_documents', {p_action: 'settle', p_data: {id}});
    await admin.from(table).update({last_error: result.error ? 'SRI_WITHHOLDING_SETTLEMENT_REQUIRED' : null}).eq('id', id).eq('status', 'authorized');
    if (result.error) throw Error('SRI_WITHHOLDING_SETTLEMENT_REQUIRED');
    return result.data;
  };
  try {
    let issue = await fetchIssue();
    if (input.action === 'refresh' && issue.status === 'authorized' && documentType === '07') {
      const settled = await settleWithholding(issue.id);
      return reply({id: issue.id, status: issue.status, withholding_id: settled.id});
    }
    if (input.action === 'retry') {
      if (issue.receipt?.provider === 'openapi' || issue.access_key || !['error','processing'].includes(issue.status)) return reply({ error: 'SRI_RETRY_REQUIRES_REVIEW' }, 409);
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
    const issueProvider = issue.receipt?.provider || 'private_worker';
    if ((input.action === 'submit' && provider === 'openapi' && documentType !== '03') || (input.action === 'refresh' && issueProvider === 'openapi')) {
      if (input.action === 'submit') {
        if (issue.status !== 'draft') return reply({ error: 'SRI_ALREADY_SUBMITTED', status: issue.status }, 409);
        // This preview cannot emit. Only claim after configuration/DTO validation.
        await call('openapi_preflight', issue);
        issue = await save('processing', { receipt: { provider: 'openapi' }, last_error: null }, 'draft');
        try {
          const result = await call('openapi_submit', issue);
          if (result.access_key && !matchesIssue(result.access_key, issue)) throw Error('SRI_INVALID_ACCESS_KEY');
          const patch: Record<string, unknown> = {
            receipt: { provider: 'openapi', status: result.provider_status || 'UNKNOWN', review_required: result.review_required === true },
            sent_at: new Date().toISOString()
          };
          if (result.access_key) { patch.access_key = result.access_key; patch.numeric_code = result.access_key.slice(39,47); }
          issue = await save(result.status === 'rejected' ? 'rejected' : 'processing', patch, 'processing');
          return reply({ id: issue.id, status: issue.status, access_key: issue.access_key, review_required: result.review_required === true }, 202);
        } catch {
          // Upstream may already have sent to the SRI. NEVER reset to draft.
          await admin.from(table).update({ last_error: 'SRI_OPENAPI_RECONCILIATION_REQUIRED' }).eq('id', issue.id).eq('status', 'processing');
          return reply({ id: issue.id, status: 'processing', review_required: true, message: 'SRI_OPENAPI_RECONCILIATION_REQUIRED' }, 202);
        }
      }
      if (!['processing','signed','received','rejected'].includes(issue.status)) return reply({ error: 'SRI_NOT_PENDING' }, 409);
      const result = await call('openapi_refresh', issue);
      if (result.access_key) {
        if (!matchesIssue(result.access_key, issue) || (issue.access_key && result.access_key !== issue.access_key)) throw Error('SRI_ACCESS_KEY_MISMATCH');
        // A pending lookup must not erase a previously recorded rejection.
        issue = await save(issue.status === 'rejected' ? 'rejected' : 'processing', { access_key: result.access_key, numeric_code: result.access_key.slice(39,47),
          receipt: { provider: 'openapi', status: result.provider_status, review_required: result.review_required === true }, last_error: null }, issue.status);
      }
      if (result.status === 'authorized') {
        if (!issue.access_key || result.authorization !== issue.access_key || !result.authorized_at) throw Error('SRI_INVALID_AUTHORIZATION');
        const signedPath = await upload(issue, 'signed.xml', result.signed_xml, 'application/xml');
        const xmlPath = await upload(issue, 'authorized.xml', result.authorized_xml, 'application/xml');
        // RIDE rendering timestamps can change between calls; content addressing
        // preserves immutable archives and allows recovery after a partial upload.
        const pdfHash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes(result.ride_pdf)))).map(v => v.toString(16).padStart(2,'0')).join('');
        const ridePath = await upload(issue, 'RIDE-' + pdfHash + '.pdf', result.ride_pdf, 'application/pdf');
        const linked = documentType === '01' ? await admin.from('external_invoices').update({
          external_number: [issue.establishment,issue.emission_point,issue.sequential].join('-'),
          issuer_ruc: issue.issuer_ruc, software: 'Coco ERP / Open API SRI',
          external_issue_date: issue.snapshot.issue_date, external_status: 'authorized', access_key: issue.access_key
        }).eq('id', issue.source_invoice_id).eq('document_kind','internal').select('id').single() : {error: null};
        if (linked.error) throw linked.error;
        issue = await save('authorized', { signed_xml_path: signedPath, authorized_xml_path: xmlPath, ride_path: ridePath,
          authorized_at: result.authorized_at, authorization_response: { status: 'authorized', authorization: result.authorization, provider: 'openapi' },
          last_error: null }, issue.status);
      } else if (result.status === 'rejected') {
        issue = await save('rejected', { authorization_response: { status: 'rejected', provider: 'openapi', message: result.provider_status } }, issue.status);
      }
      if (!machine && issue.status === 'authorized' && documentType === '07') await settleWithholding(issue.id);
      return reply({ id: issue.id, status: issue.status, access_key: issue.access_key, review_required: result.review_required === true });
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
      if (!matchesIssue(signed.access_key, issue) || (issue.access_key && issue.access_key !== signed.access_key)) throw Error('SRI_INVALID_ACCESS_KEY');
      const signedPath = await upload(issue, 'signed.xml', signed.signed_xml, 'application/xml');
      issue = await save('signed', { access_key: signed.access_key, signed_xml_path: signedPath }, 'processing');
      // Network failure leaves the same signed document available for a lookup.
      const receipt = await call('receive', issue, { signed_xml: signed.signed_xml });
      issue = await save(receipt.status === 'received' ? 'received' : 'rejected',
        { receipt, sent_at: new Date().toISOString() }, 'signed');
      return reply({ id: issue.id, status: issue.status, access_key: issue.access_key });
    }
    if (input.action === 'refresh') {
      if (!['signed','received','processing','rejected'].includes(issue.status) || !issue.access_key) return reply({ error: 'SRI_NOT_PENDING' }, 409);
      const prior = issue.status;
      const result = await call('authorize', issue);
      if (result.status === 'authorized') {
        if (result.authorization !== issue.access_key || !result.authorized_at) throw Error('SRI_INVALID_AUTHORIZATION');
        const xmlPath = await upload(issue, 'authorized.xml', result.authorized_xml, 'application/xml');
        const ridePath = await upload(issue, 'RIDE.pdf', result.ride_pdf, 'application/pdf');
        // A verified SRI result updates the management invoice's external reference.
        const linked = documentType === '01' ? await admin.from('external_invoices').update({ external_number: [issue.establishment,issue.emission_point,issue.sequential].join('-'),
          issuer_ruc: issue.issuer_ruc, software: 'Coco ERP / SRI', external_issue_date: issue.snapshot.issue_date,
          external_status: 'authorized', access_key: issue.access_key }).eq('id', issue.source_invoice_id).eq('document_kind','internal').select('id').single() : {error: null};
        if (linked.error) throw linked.error;
        issue = await save('authorized', { authorization_response: { status: 'authorized', authorization: result.authorization }, authorized_xml_path: xmlPath,
          ride_path: ridePath, authorized_at: result.authorized_at || new Date().toISOString() }, prior);
      } else if (result.status === 'rejected') issue = await save('rejected', { authorization_response: result }, prior);
      if (!machine && issue.status === 'authorized' && documentType === '07') await settleWithholding(issue.id);
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
    await admin.from(table).update({ delivered_at: new Date().toISOString() }).eq('id', issue.id).is('delivered_at', null);
    return reply({ id: issue.id, delivered: true });
  } catch (error) {
    const code = error instanceof Error ? error.message : '';
    return reply({ error: /^[A-Z0-9_]{1,100}$/.test(code) ? code : 'SRI_OPERATION_FAILED' }, 422);
  }
}
Deno.serve(handle);
