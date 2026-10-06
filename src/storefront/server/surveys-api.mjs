import {readJsonBody,BodyError} from '../../../supabase/functions/_shared/http.mjs';
import runtime from '../../../config/storefront-runtime.json' with {type:'json'};
export const actions=new Set(['get','submit']);
const allowedErrors=new Set(['SURVEY_INVALID_DATA','SURVEY_INVALID_ANSWER','SURVEY_REQUIRED_ANSWER','SURVEY_UNAVAILABLE','SURVEY_ALREADY_ANSWERED','SURVEY_REQUEST_KEY_REUSED','SURVEY_RATE_LIMIT']);
export async function dbRpc(action,data={},env={},fetcher=fetch){
 const headers={'Content-Type':'application/json',apikey:runtime.publishable_key};
 if(action==='submit')headers['x-coco-site-token']=env.COCO_SITE_TOKEN;
 const r=await fetcher(runtime.url+'/rest/v1/rpc/gama_survey',{method:'POST',redirect:'error',headers,body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(12000)});
 let body;try{body=await r.json()}catch(_){throw Error('SURVEY_UNAVAILABLE')}
 if(!r.ok)throw Error(allowedErrors.has(body.message)?body.message:'SURVEY_UNAVAILABLE');return body;
}
const response=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export async function onRequest({request,env={},fetcher=fetch}){
 if(request.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405);
 if(!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))return response({error:'SURVEY_INVALID_DATA'},415);
 try{
  const payload=await readJsonBody(request,70000);
  if(!payload||!actions.has(payload.p_action)||!payload.p_data||typeof payload.p_data!=='object'||Array.isArray(payload.p_data))return response({error:'SURVEY_INVALID_DATA'},400);
  const data={...payload.p_data};delete data.visitor;
  if(payload.p_action==='submit'){
   const origin=new URL(request.url).origin;
   if(request.headers.get('Origin')!==origin)return response({error:'SURVEY_INVALID_ORIGIN'},403);
   if(!/^[a-f0-9]{64}$/i.test(env.COCO_SITE_TOKEN||''))return response({error:'SURVEY_CONNECTION_REQUIRED'},503);
   const visitor=request.headers.get('CF-Connecting-IP');if(!visitor)return response({error:'SURVEY_CONNECTION_REQUIRED'},503);
   data.visitor=visitor;
  }
  return response(await dbRpc(payload.p_action,data,env,fetcher));
 }catch(e){if(e instanceof BodyError)return response({error:'SURVEY_INVALID_DATA'},e.status);const code=allowedErrors.has(e?.message)?e.message:'SURVEY_UNAVAILABLE';return response({error:code},code==='SURVEY_RATE_LIMIT'?429:code==='SURVEY_UNAVAILABLE'?503:400)}
}
