import {readJsonBody,BodyError} from '../_shared/http.mjs';
import {verifyStripeSignature,validateSession,projectEvent,stripeForm,uuid,sessionId} from './stripe.mjs';
async function rawBytes(request,max){
 if(Number(request.headers.get('content-length'))>max)throw new BodyError('PAYLOAD_TOO_LARGE',413);const reader=request.body?.getReader();if(!reader)throw new BodyError('INVALID_JSON',400);let length=0,timer;
 const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new BodyError('PAYLOAD_TIMEOUT',408)),10000)}),chunks=[];
 try{for(;;){const {done,value}=await Promise.race([reader.read(),timeout]);if(done)break;length+=value.length;if(length>max)throw new BodyError('PAYLOAD_TOO_LARGE',413);chunks.push(value)}const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}return bytes}
 catch(e){reader.cancel().catch(()=>{});throw e}finally{clearTimeout(timer);reader.releaseLock()}
}
export function createHandler({env,fetch:fetcher,now=()=>Date.now()}){
 const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY'),origin=env('COCO_CHECKOUT_APP_ORIGIN')||'https://lisciandraj.github.io';
 return async request=>{
  const webhook=request.headers.has('stripe-signature')||new URL(request.url).searchParams.get('webhook')==='1';
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
   'Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Methods':'POST,OPTIONS','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
  const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
  if(!webhook&&request.headers.get('origin')&&request.headers.get('origin')!==origin)return reply({error:'ORIGIN_NOT_ALLOWED'},403);
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
  const machine=async(action,data)=>{const r=await fetcher(root+'/rest/v1/rpc/coco_checkout_payment_machine',{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error('CHECKOUT_PAYMENT_UNAVAILABLE');return r.json()};
  const stripe=async(path,key,options={})=>{const r=await fetcher('https://api.stripe.com/v1/'+path,{...options,headers:{Authorization:'Bearer '+key,'Stripe-Version':'2024-06-20',...(options.body?{'Content-Type':'application/x-www-form-urlencoded'}:{}),...options.headers},signal:AbortSignal.timeout(20000)});if(!r.ok)throw Error('STRIPE_UNAVAILABLE');return r.json()};
  try{
   if(webhook){
    const bytes=await rawBytes(request,131072),secret=env('STRIPE_WEBHOOK_SECRET');
    if(!await verifyStripeSignature(bytes,request.headers.get('stripe-signature'),secret,now()))return reply({error:'INVALID_SIGNATURE'},401);
    let event;try{event=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes))}catch{return reply({error:'INVALID_JSON'},400)}
    let projection=projectEvent(event);if(!projection)return reply({received:true,state:'ignored'});if(!projection.intent_id&&projection.payment_intent){const key=env('STRIPE_SECRET_KEY');if(!key||!(projection.livemode?/^sk_live_/:/^sk_test_/).test(key))return reply({error:'CHECKOUT_PROVIDER_NOT_CONFIGURED'},503);const pi=await stripe('payment_intents/'+encodeURIComponent(projection.payment_intent),key);if(pi.id!==projection.payment_intent||pi.livemode!==projection.livemode)throw Error('CHECKOUT_EVENT_INVALID');if(!uuid.test(pi.metadata?.coco_intent_id||''))return reply({received:true,state:'ignored'});projection={...projection,intent_id:pi.metadata.coco_intent_id}}if(!root||!service)return reply({error:'CHECKOUT_PAYMENT_UNAVAILABLE'},503);
    const result=await machine('event',projection);return reply({received:true,state:result.state});
   }
   const input=await readJsonBody(request,2048);if(input.action!=='create'||!/^[a-f0-9]{64}$/.test(input.token||'')||!uuid.test(input.request_key||'')||input.agree!==true||!/^[a-f0-9]{64}$/.test(input.pdf_sha256||''))return reply({error:'CHECKOUT_LINK_UNAVAILABLE'},400);
   if(!root||!anon||!service)return reply({error:'CHECKOUT_PAYMENT_UNAVAILABLE'},503);
   // This exact caller-bound RPC preserves the production/admin-preview gate.
   const checked=await fetcher(root+'/rest/v1/rpc/coco_checkout_public',{method:'POST',headers:{apikey:anon,Authorization:request.headers.get('authorization')||'Bearer '+anon,'Content-Type':'application/json'},body:JSON.stringify({p_action:'payment_prepare',p_data:{token:input.token,request_key:input.request_key,agree:true,pdf_sha256:input.pdf_sha256}}),signal:AbortSignal.timeout(15000)});
   if(!checked.ok)return reply({error:'CHECKOUT_PAYMENT_UNAVAILABLE'},403);const permitted=await checked.json();if(!uuid.test(permitted.id||''))return reply({error:'CHECKOUT_PAYMENT_UNAVAILABLE'},403);
   const intent=await machine('config',{intent_id:permitted.id});if(intent.id!==permitted.id||!Number.isSafeInteger(intent.amount_cents)||intent.amount_cents<=0||intent.amount_cents>99999999||typeof intent.livemode!=='boolean')throw Error('CHECKOUT_SESSION_MISMATCH');
   const key=env('STRIPE_SECRET_KEY'),publicUrl=env('COCO_CHECKOUT_PUBLIC_URL');if(!key||!publicUrl||!(intent.livemode?/^sk_live_/:/^sk_test_/).test(key))return reply({error:'CHECKOUT_PROVIDER_NOT_CONFIGURED'},503);
   let session;
   if(intent.stale){if(intent.session_id){if(!sessionId.test(intent.session_id))throw Error('CHECKOUT_SESSION_MISMATCH');session=await stripe('checkout/sessions/'+encodeURIComponent(intent.session_id),key);if(session.status==='open')session=await stripe('checkout/sessions/'+encodeURIComponent(intent.session_id)+'/expire',key,{method:'POST'});if(session.status!=='expired')return reply({error:'CHECKOUT_PAYMENT_PENDING'},409)}await machine('expire',{intent_id:intent.id,session_id:intent.session_id,provider_status:'expired'});return reply({error:'CHECKOUT_PAYMENT_CHANGED'},409)}
   if(intent.session_id){if(!sessionId.test(intent.session_id))throw Error('CHECKOUT_SESSION_MISMATCH');session=await stripe('checkout/sessions/'+encodeURIComponent(intent.session_id),key)}
   else session=await stripe('checkout/sessions',key,{method:'POST',headers:{'Idempotency-Key':'coco-'+intent.id},body:stripeForm(intent,publicUrl,input.language)});
   validateSession(session,intent);
   await machine('bind',{intent_id:intent.id,session_id:session.id,amount_cents:session.amount_total,currency:session.currency,livemode:session.livemode});
   return reply({id:intent.id,url:session.url,livemode:intent.livemode});
  }catch(e){const status=e?.status||(/INVALID|MISMATCH/.test(String(e?.message))?400:503);return reply({error:e instanceof BodyError?e.message:'CHECKOUT_PAYMENT_UNAVAILABLE'},status)}
 };
}
