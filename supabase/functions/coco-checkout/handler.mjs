import {readJsonBody} from '../_shared/http.mjs';
const hex=bytes=>Array.from(new Uint8Array(bytes),n=>n.toString(16).padStart(2,'0')).join('');
const maxPdf=52428800;
async function limitedBytes(response){
 if(Number(response.headers.get('content-length'))>maxPdf)throw Error('PDF_TOO_LARGE');
 const reader=response.body?.getReader();if(!reader)throw Error('PDF_UNAVAILABLE');
 const chunks=[];let total=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;total+=value.byteLength;if(total>maxPdf)throw Error('PDF_TOO_LARGE');chunks.push(value)}}
 catch(e){await reader.cancel();throw e}finally{reader.releaseLock()}
 const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength}return bytes;
}
/** Caller-bound capability check always precedes the privileged storage read. */
export function createHandler({env,fetch:fetcher}){
 const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 const origin=env('COCO_CHECKOUT_APP_ORIGIN')||'https://lisciandraj.github.io';
 return async request=>{
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
   'Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Methods':'POST,OPTIONS','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
  const reply=(error,status)=>new Response(JSON.stringify({error}),{status,headers});
  if(request.headers.get('origin')&&request.headers.get('origin')!==origin)return reply('ORIGIN_NOT_ALLOWED',403);
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply('METHOD_NOT_ALLOWED',405);
  try{
   const input=await readJsonBody(request,1024);
   if(input.action!=='document'||!/^[a-f0-9]{64}$/.test(input.token||''))return reply('CHECKOUT_LINK_UNAVAILABLE',400);
   if(!root||!anon||!service)return reply('CHECKOUT_UNAVAILABLE',503);
   const authorization=request.headers.get('authorization')||'Bearer '+anon;
   const checked=await fetcher(root+'/rest/v1/rpc/coco_checkout_public',{method:'POST',headers:{apikey:anon,Authorization:authorization,'Content-Type':'application/json'},
    body:JSON.stringify({p_action:'view',p_data:{token:input.token}}),signal:AbortSignal.timeout(15000)});
   if(!checked.ok)return reply('CHECKOUT_LINK_UNAVAILABLE',403);
   const permitted=await checked.json();
   if(!/^[0-9a-f-]{36}$/i.test(permitted.id||'')||!/^[a-f0-9]{64}$/.test(permitted.pdf_sha256||''))return reply('CHECKOUT_LINK_UNAVAILABLE',403);
   const machine={apikey:service,Authorization:'Bearer '+service};
   const resolved=await fetcher(root+'/rest/v1/rpc/coco_checkout_document',{method:'POST',headers:{...machine,'Content-Type':'application/json'},
    body:JSON.stringify({p_id:permitted.id,p_pdf_sha256:permitted.pdf_sha256}),signal:AbortSignal.timeout(15000)});
   if(!resolved.ok)return reply('CHECKOUT_DOCUMENT_UNAVAILABLE',409);
   const file=await resolved.json();
   if(!/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.pdf$/i.test(file.path||'')||file.sha256!==permitted.pdf_sha256)return reply('CHECKOUT_DOCUMENT_UNAVAILABLE',409);
   const response=await fetcher(root+'/storage/v1/object/sales-checkout-documents/'+file.path,{headers:machine,signal:AbortSignal.timeout(30000)});
   if(!response.ok)return reply('CHECKOUT_DOCUMENT_UNAVAILABLE',503);
   const bytes=await limitedBytes(response);
   if(new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-'||hex(await crypto.subtle.digest('SHA-256',bytes))!==file.sha256)return reply('CHECKOUT_DOCUMENT_CHANGED',409);
   return new Response(bytes,{headers:{...headers,'Content-Type':'application/pdf','Content-Disposition':'inline; filename="Coco-quote.pdf"','Content-Security-Policy':"sandbox; default-src 'none'"}});
  }catch(e){return reply(e?.message==='PAYLOAD_TOO_LARGE'?'PAYLOAD_TOO_LARGE':'CHECKOUT_UNAVAILABLE',e?.status||503)}
 };
}
