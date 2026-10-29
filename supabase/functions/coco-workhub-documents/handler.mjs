import {mergeDocument} from './crdt.mjs';
import {readJsonBody,BodyError} from '../_shared/http.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
class Failure extends Error{constructor(code,status=400){super(code);this.status=status;}}
export function createHandler({env,fetch:fetcher}){
 const origin='https://lisciandraj.github.io',root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,x-client-info,content-type','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store','Content-Type':'application/json'};
 async function rpc(name,args,token){
  const r=await fetcher(root+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:token===service?service:anon,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(15000)});
  const value=await r.json().catch(()=>null);
  if(!r.ok){const code=/^WORKHUB_[A-Z_]+$/.test(value?.message||'')?value.message:'WORKHUB_DOCUMENT_UNAVAILABLE';throw new Failure(code,code==='WORKHUB_FORBIDDEN'?403:code==='WORKHUB_DOCUMENT_RATE_LIMIT'?429:code==='WORKHUB_DOCUMENT_CONFLICT'?409:502);}
  return value;
 }
 return async req=>{
  const response=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405);
  if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return response({error:'ORIGIN_NOT_ALLOWED'},403);
  if(!root||!anon||!service)return response({error:'SERVER_CONFIGURATION'},503);
  try{
   const token=req.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];if(!token)throw new Failure('AUTH_REQUIRED',401);
   const auth=await fetcher(root+'/auth/v1/user',{headers:{apikey:anon,Authorization:'Bearer '+token},signal:AbortSignal.timeout(10000)});
   const user=auth.ok?await auth.json():null;if(!UUID.test(user?.id||''))throw new Failure('AUTH_REQUIRED',401);
   const input=await readJsonBody(req,410000);
   if(!UUID.test(input.document_id||'')||!UUID.test(input.request_key||'')||typeof input.update!=='string')throw new Failure('WORKHUB_DOCUMENT_INVALID_INPUT');
   const update_hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(input.update))),b=>b.toString(16).padStart(2,'0')).join('');
   for(let attempt=0;attempt<4;attempt++){
    // RLS, role, module and MFA checks happen under the actual caller's token.
    const current=await rpc('coco_workhub_documents',{p_action:'read',p_data:{id:input.document_id}},token);
    if(current.archived)throw new Failure('WORKHUB_DOCUMENT_ARCHIVED',409);
    let merged;try{merged=mergeDocument(current.state,input.update);}catch(e){throw new Failure(e.message,422);}
    const receipt=await rpc('coco_workhub_document_stage',{p_data:{actor_id:user.id,document_id:current.id,request_key:input.request_key,expected_version:current.version,update_hash,...merged}},service);
    try{
     const saved=await rpc('coco_workhub_documents',{p_action:'commit',p_data:{receipt_id:receipt}},token);
     return response(saved);
    }catch(e){if(e.message!=='WORKHUB_DOCUMENT_CONFLICT'||attempt===3)throw e;}
   }
  }catch(e){return response({error:e instanceof Failure||e instanceof BodyError?e.message:'WORKHUB_DOCUMENT_UNAVAILABLE'},e instanceof Failure||e instanceof BodyError?e.status:503);}
 };
}
