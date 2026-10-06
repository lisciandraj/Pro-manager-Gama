import {readJsonBody,BodyError} from '../../../supabase/functions/_shared/http.mjs';
import runtime from '../../../config/storefront-runtime.json' with {type:'json'};
export const actions=new Set(['bootstrap','catalog','product','photos','submit']);
const allowedErrors=new Set(['WEBSITE_INVALID_DATA','WEBSITE_PRODUCT_NOT_FOUND','WEBSITE_PUBLIC_PAUSED','WEBSITE_QUOTES_DISABLED','WEBSITE_CONTACT_REQUIRED','WEBSITE_INVALID_LINES','WEBSITE_INVALID_QUANTITY','WEBSITE_PACK_QUANTITY','WEBSITE_DUPLICATE_PRODUCT','WEBSITE_REQUEST_KEY_REUSED','WEBSITE_RATE_LIMIT']);
// Record only status/type codes, never request data, credentials or response bodies.
const upstreamFailure=(status,code)=>console.error(JSON.stringify({event:'storefront_upstream_failure',status,code:typeof code==='string'&&/^[A-Za-z0-9_-]{1,64}$/.test(code)?code:'UNKNOWN'}));
export async function dbRpc(action,data={},env={},fetcher=fetch){
 const headers={'Content-Type':'application/json',apikey:runtime.publishable_key};
 if(action==='submit')headers['x-coco-site-token']=env.COCO_SITE_TOKEN;
 // Manual mode keeps redirects visible and never forwards the server credential.
 let r;try{r=await fetcher(runtime.url+'/rest/v1/rpc/gama_storefront',{method:'POST',redirect:'manual',headers,body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(12000)})}catch(e){upstreamFailure(0,e?.name);throw Error('WEBSITE_UNAVAILABLE')}
 let body;try{body=await r.json()}catch(_){upstreamFailure(r.status,'INVALID_RESPONSE');throw Error('WEBSITE_UNAVAILABLE')}
 if(!r.ok){if(!allowedErrors.has(body.message))upstreamFailure(r.status,body?.code);throw Error(allowedErrors.has(body.message)?body.message:'WEBSITE_UNAVAILABLE')}return body;
}
const response=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export async function onRequest({request,env={},fetcher=fetch}){
 if(request.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405);
 if(!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))return response({error:'WEBSITE_INVALID_DATA'},415);
 try{
  const payload=await readJsonBody(request,28000);
  if(!payload||!actions.has(payload.p_action)||!payload.p_data||typeof payload.p_data!=='object'||Array.isArray(payload.p_data))return response({error:'WEBSITE_INVALID_DATA'},400);
  const data={...payload.p_data};delete data.visitor;
  if(payload.p_action==='submit'){
   const origin=new URL(request.url).origin;
   if(request.headers.get('Origin')!==origin)return response({error:'WEBSITE_INVALID_ORIGIN'},403);
   if(!/^[a-f0-9]{64}$/i.test(env.COCO_SITE_TOKEN||''))return response({error:'WEBSITE_CONNECTION_REQUIRED'},503);
   const visitor=request.headers.get('CF-Connecting-IP');if(!visitor)return response({error:'WEBSITE_CONNECTION_REQUIRED'},503);
   data.visitor=visitor;
  }
  return response(await dbRpc(payload.p_action,data,env,fetcher));
 }catch(e){if(e instanceof BodyError)return response({error:'WEBSITE_INVALID_DATA'},e.status);const code=allowedErrors.has(e?.message)?e.message:'WEBSITE_UNAVAILABLE';return response({error:code},code==='WEBSITE_RATE_LIMIT'?429:code==='WEBSITE_UNAVAILABLE'?503:400)}
}
