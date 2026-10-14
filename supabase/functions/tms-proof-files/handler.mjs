import {readJsonBody} from '../_shared/http.mjs';
const hex=bytes=>Array.from(new Uint8Array(bytes),n=>n.toString(16).padStart(2,'0')).join('');
const digest=bytes=>crypto.subtle.digest('SHA-256',bytes).then(hex);
export function createHandler({env,fetch:fetcher}){
 const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 return async req=>{
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':'https://lisciandraj.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
  const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
  if(req.headers.get('origin')&&req.headers.get('origin')!=='https://lisciandraj.github.io')return reply({error:'ORIGIN_NOT_ALLOWED'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
  const token=req.headers.get('authorization');if(!/^Bearer \S+$/i.test(token||''))return reply({error:'AUTH_REQUIRED'},401);
  try{
   const {proof_id}=await readJsonBody(req,1024);if(!/^[0-9a-f-]{36}$/i.test(proof_id||''))return reply({error:'INVALID_PROOF'},400);
   // Read through the caller's MFA/module/assignment checked RPC. No elevated
   // request is made until that server check has succeeded.
   const checked=await fetcher(root+'/rest/v1/rpc/gama_tms_proof_file',{method:'POST',headers:{apikey:anon,Authorization:token,'Content-Type':'application/json'},body:JSON.stringify({p_id:proof_id}),signal:AbortSignal.timeout(15000)});
   if(!checked.ok)return reply({error:'TMS_ACCESS_DENIED'},403);const proof=await checked.json();if(proof.file)return reply({stored:true,path:proof.file});
   const match=/^data:(image\/(?:png|jpeg));base64,([A-Za-z0-9+/=]+)$/.exec(proof.data_url||'');if(!match||match[2].length>14000000)return reply({error:'PROOF_FORMAT_INVALID'},409);
   const bytes=Uint8Array.from(atob(match[2]),c=>c.charCodeAt(0)),sha=await digest(bytes),path=proof_id+'-'+proof.content_hash+(match[1]==='image/png'?'.png':'.jpg');
   const storage=root+'/storage/v1/object/tms-attempt-proofs/'+path,auth={apikey:service,Authorization:'Bearer '+service};
   const upload=await fetcher(storage,{method:'POST',headers:{...auth,'Content-Type':match[1],'x-upsert':'false'},body:bytes,signal:AbortSignal.timeout(20000)});
   if(!upload.ok&&!([400,409].includes(upload.status)))return reply({error:'PROOF_STORAGE_UNAVAILABLE'},503);
   // Re-read and verify the actual stored bytes, including on an idempotent retry.
   const read=await fetcher(storage,{headers:auth,signal:AbortSignal.timeout(20000)});
   if(!read.ok||await digest(await read.arrayBuffer())!==sha)return reply({error:'PROOF_FILE_MISMATCH'},409);
   const commit=await fetcher(root+'/rest/v1/rpc/gama_tms_proof_file_commit',{method:'POST',headers:{...auth,'Content-Type':'application/json'},body:JSON.stringify({p_id:proof_id,p_hash:proof.content_hash,p_path:path,p_sha256:sha}),signal:AbortSignal.timeout(15000)});
   if(!commit.ok)return reply({error:'PROOF_STORAGE_UNAVAILABLE'},503);return reply(await commit.json());
  }catch{return reply({error:'PROOF_STORAGE_UNAVAILABLE'},503)}
 };
}
