import { createClient } from 'npm:@supabase/supabase-js@2.115.0';
const headers={'content-type':'application/json','access-control-allow-origin':'*'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async request=>{
 if(request.method==='OPTIONS')return new Response(null,{headers:{...headers,'access-control-allow-headers':'authorization,apikey,content-type,x-client-info','access-control-allow-methods':'POST'}});
 if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 const bearer=request.headers.get('Authorization')||'';
 if(!bearer.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
 const url=Deno.env.get('SUPABASE_URL')!,client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:bearer}}});
 const user=await client.auth.getUser(bearer.slice(7));if(user.error||!user.data.user)return reply({error:'AUTH_REQUIRED'},401);
 const access=await client.rpc('gama_sri_access');if(access.error||access.data?.validate!==true)return reply({error:'ROLE_NOT_ALLOWED'},403);
 let input:{xml_base64:string};try{input=await request.json()}catch{return reply({error:'INVALID_JSON'},400)}
 if(!input||typeof input.xml_base64!=='string'||input.xml_base64.length>1400000)return reply({error:'INVALID_REQUEST'},400);
 try{
 const endpoint=Deno.env.get('SRI_WORKER_URL')||'',secret=Deno.env.get('SRI_WORKER_SECRET')||'';let configured=false;
 try{const u=new URL(endpoint);configured=u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&Boolean(secret)}catch{}
 if(!configured)return reply({error:'SRI_WORKER_NOT_CONFIGURED'},503);
 const worker=async(action:string,extra:Record<string,unknown>={})=>{
  const body=JSON.stringify({action,xml_base64:input.xml_base64,...extra});
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);const signature=[...new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(body)))].map(v=>v.toString(16).padStart(2,'0')).join('');
  const response=await fetch(endpoint+'/execute',{method:'POST',redirect:'error',headers:{'content-type':'application/json','x-sri-signature':signature},body,signal:AbortSignal.timeout(45000)}),result=await response.json();
  if(!response.ok)throw Error(typeof result.detail==='string'&&/^[A-Z0-9_]{1,100}$/.test(result.detail)?result.detail:'SRI_RECEIVED_VERIFICATION_REQUIRED');return result;
 };
 // Source matching uses the SRI's authorized XML, never amounts supplied by a browser.
 const inspected=await worker('received_inspect');
 if(!/^[0-9]{13}$/.test(inspected.issuer_ruc)||!Array.isArray(inspected.sources)||inspected.sources.length<1||inspected.sources.length>50)throw Error('SRI_RECEIVED_FIELDS_INVALID');
 const invoices=[];
 for(const number of inspected.sources){const m=await client.rpc('gama_ec_received_match',{p_ruc:inspected.issuer_ruc,p_number:number});if(m.error)throw m.error;invoices.push(m.data)}
 const verified=await worker('verify_received_batch',{invoices});if(!Array.isArray(verified.rows)||verified.rows.length!==invoices.length||new Set(verified.rows.map((r:{invoice_id:string})=>r.invoice_id)).size!==invoices.length||verified.rows.some((r:{invoice_id:string})=>!invoices.some(i=>i.id===r.invoice_id)))throw Error('SRI_RECEIVED_FIELDS_INVALID');
 const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!),rows=[];
 for(const result of verified.rows){
  const invoice=invoices.find(i=>i.id===result.invoice_id);
  if(!invoice||!/^[0-9]{49}$/.test(result.access_key)||result.access_key!==inspected.access_key||result.issuer_ruc!==invoice.customer_identification||!Array.isArray(result.lines)||!result.authorized_at||typeof result.authorized_xml!=='string'||result.authorized_xml.length>1048576)throw Error('SRI_RECEIVED_FIELDS_INVALID');
  const raw=new TextEncoder().encode(result.authorized_xml),hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',raw))].map(v=>v.toString(16).padStart(2,'0')).join('');const path='received/'+result.access_key+'/'+hash+'.xml';
  const saved=await admin.storage.from('sri-documents').upload(path,raw,{contentType:'application/xml',upsert:false});if(saved.error&&!saved.error.message.includes('already exists'))throw Error('SRI_ARCHIVE_FAILED');
  const row={invoice_id:invoice.id,access_key:result.access_key,issuer_ruc:result.issuer_ruc,number:result.number,issued_on:result.issued_on,amount:result.amount,lines:result.lines,authorized_at:result.authorized_at,xml_path:path,xml_sha256:hash,verified_by:user.data.user.id};
  const written=await admin.from('accounting_received_sri').upsert(row,{onConflict:'access_key,invoice_id',ignoreDuplicates:true});if(written.error)throw Error('SRI_RECEIVED_ARCHIVE_FAILED');
  const r=await client.from('accounting_received_sri').select('id,amount,number,withholding_id,xml_sha256').eq('access_key',result.access_key).eq('invoice_id',invoice.id).single();if(r.error||r.data.xml_sha256!==hash)throw Error('SRI_RECEIVED_ARCHIVE_CONFLICT');
  rows.push({id:r.data.id,number:r.data.number,amount:r.data.amount,withholding_id:r.data.withholding_id,invoice_id:invoice.id,invoice_number:invoice.number});
 }
 return reply({rows});
 }catch(e){const code=e instanceof Error?e.message:(e as {message?:string})?.message||'';return reply({error:/^[A-Z0-9_]{1,100}$/.test(code)?code:'SRI_RECEIVED_VERIFICATION_FAILED'},422)}
});
