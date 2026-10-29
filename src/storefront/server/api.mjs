import {readJsonBody,BodyError} from '../../../supabase/functions/_shared/http.mjs';
import runtime from '../../../config/storefront-runtime.json' with {type:'json'};
const commerceActions=['preview','checkout','guest_order','guest_repeat','reviews','review_eligibility','review_save'];
export const actions=new Set(['bootstrap','catalog','product','photos','submit',...commerceActions.map(a=>'commerce_'+a)]);
const protectedActions=new Set(['submit','commerce_checkout','commerce_review_save']);
const serverActions=new Set([...protectedActions,'commerce_guest_order','commerce_guest_repeat','commerce_review_eligibility']);
const allowedErrors=new Set(['WEBSITE_INVALID_DATA','WEBSITE_PRODUCT_NOT_FOUND','WEBSITE_PUBLIC_PAUSED','WEBSITE_QUOTES_DISABLED','WEBSITE_CONTACT_REQUIRED','WEBSITE_INVALID_LINES','WEBSITE_INVALID_QUANTITY','WEBSITE_PACK_QUANTITY','WEBSITE_DUPLICATE_PRODUCT','WEBSITE_REQUEST_KEY_REUSED','WEBSITE_RATE_LIMIT']);
for(const code of ['COMMERCE_PRICE_REQUIRED','COMMERCE_BILLING_REQUIRED','COMMERCE_TERMS_REQUIRED','COMMERCE_PURCHASE_REQUIRED','CART_PRICE_CHANGED','NOT_FOUND','HUMAN_VERIFICATION_REQUIRED','HUMAN_VERIFICATION_UNAVAILABLE'])allowedErrors.add(code);
// Record only status/type codes, never request data, credentials or response bodies.
const upstreamFailure=(status,code)=>console.error(JSON.stringify({event:'storefront_upstream_failure',status,code:typeof code==='string'&&/^[A-Za-z0-9_-]{1,64}$/.test(code)?code:'UNKNOWN'}));
export async function dbRpc(action,data={},env={},fetcher=fetch){
 const headers={'Content-Type':'application/json',apikey:runtime.publishable_key};
 if(serverActions.has(action))headers['x-coco-site-token']=env.COCO_SITE_TOKEN;
 // Manual mode keeps redirects visible and never forwards the server credential.
 const commerce=action.startsWith('commerce_');
 let r;try{r=await fetcher(runtime.url+'/rest/v1/rpc/'+(commerce?'gama_commerce':'gama_storefront'),{method:'POST',redirect:'manual',headers,body:JSON.stringify({p_action:commerce?action.slice(9):action,p_data:data}),signal:AbortSignal.timeout(12000)})}catch(e){upstreamFailure(0,e?.name);throw Error('WEBSITE_UNAVAILABLE')}
 let body;try{body=await r.json()}catch(_){upstreamFailure(r.status,'INVALID_RESPONSE');throw Error('WEBSITE_UNAVAILABLE')}
 if(!r.ok){if(!allowedErrors.has(body.message))upstreamFailure(r.status,body?.code);throw Error(allowedErrors.has(body.message)?body.message:'WEBSITE_UNAVAILABLE')}
 if(action==='bootstrap')body.commerce={turnstile_sitekey:env.TURNSTILE_SITE_KEY||'',payment_enabled:false,policy_version:'2026-10-29'};
 return body;
}
export async function verifyHuman(token,request,env,fetcher){
 if(!env.TURNSTILE_SECRET_KEY||!env.TURNSTILE_SITE_KEY)throw Error('HUMAN_VERIFICATION_UNAVAILABLE');
 if(typeof token!=='string'||!token||token.length>2048)throw Error('HUMAN_VERIFICATION_REQUIRED');
 let result;
 try{const r=await fetcher('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',redirect:'error',headers:{'Content-Type':'application/json'},body:JSON.stringify({secret:env.TURNSTILE_SECRET_KEY,response:token,remoteip:request.headers.get('CF-Connecting-IP')}),signal:AbortSignal.timeout(8000)});if(!r.ok)throw Error();result=await r.json()}catch(_){throw Error('HUMAN_VERIFICATION_UNAVAILABLE')}
 if(result.success!==true||result.hostname!==new URL(request.url).hostname||result.action!=='gama_commerce')throw Error('HUMAN_VERIFICATION_REQUIRED');
}
const response=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export async function onRequest({request,env={},fetcher=fetch}){
 if(request.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405);
 if(!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))return response({error:'WEBSITE_INVALID_DATA'},415);
 try{
  const payload=await readJsonBody(request,28000);
  if(!payload||!actions.has(payload.p_action)||!payload.p_data||typeof payload.p_data!=='object'||Array.isArray(payload.p_data))return response({error:'WEBSITE_INVALID_DATA'},400);
  const data={...payload.p_data};const humanToken=data.human_token;delete data.visitor;delete data.human_token;
  if(serverActions.has(payload.p_action)){
   const origin=new URL(request.url).origin;
   if(request.headers.get('Origin')!==origin)return response({error:'WEBSITE_INVALID_ORIGIN'},403);
   if(!/^[a-f0-9]{64}$/i.test(env.COCO_SITE_TOKEN||''))return response({error:'WEBSITE_CONNECTION_REQUIRED'},503);
   const visitor=request.headers.get('CF-Connecting-IP');if(!visitor)return response({error:'WEBSITE_CONNECTION_REQUIRED'},503);
   data.visitor=visitor;
   if(protectedActions.has(payload.p_action))await verifyHuman(humanToken,request,env,fetcher);
  }
  return response(await dbRpc(payload.p_action,data,env,fetcher));
 }catch(e){if(e instanceof BodyError)return response({error:'WEBSITE_INVALID_DATA'},e.status);const code=allowedErrors.has(e?.message)?e.message:'WEBSITE_UNAVAILABLE';return response({error:code},code==='WEBSITE_RATE_LIMIT'?429:['WEBSITE_UNAVAILABLE','HUMAN_VERIFICATION_UNAVAILABLE'].includes(code)?503:400)}
}
