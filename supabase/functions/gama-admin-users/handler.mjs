import {readJsonBody,BodyError} from '../_shared/http.mjs';
const origin='https://lisciandraj.github.io',uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function createHandler({env,fetch:fetcher}){
 const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 return async request=>{
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
   'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info',
   'Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
  const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
  if(request.headers.get('origin')&&request.headers.get('origin')!==origin)return reply({error:'ORIGIN_NOT_ALLOWED'},403);
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
  const token=request.headers.get('authorization');
  if(!/^Bearer \S+$/i.test(token||''))return reply({error:'AUTH_REQUIRED'},401);
  const call=async(path,{method='GET',body,admin=false}={})=>{
   const r=await fetcher(root+path,{method,redirect:'error',headers:{apikey:admin?service:anon,Authorization:admin?'Bearer '+service:token,'Content-Type':'application/json',Prefer:'return=representation,resolution=merge-duplicates'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
   return {ok:r.ok,status:r.status,data:await r.json().catch(()=>null)};
  };
  try{
   const body=await readJsonBody(request,12000),user=await call('/auth/v1/user');
   if(!user.ok||!uuid.test(user.data?.id||''))return reply({error:'AUTH_REQUIRED'},401);
   const profile=await call('/rest/v1/profiles?select=role,active&id=eq.'+user.data.id);
   if(!profile.ok||profile.data?.[0]?.role!=='administrador'||profile.data[0].active!==true)return reply({error:'ROLE_NOT_ALLOWED'},403);
   const allowed=()=>call('/rest/v1/rpc/gama_identity_admin_allowed',{method:'POST',body:{}});
   const access=await allowed();if(!access.ok||access.data!==true)return reply({error:'MODULE_OR_ACTION_NOT_ALLOWED'},403);
   const email=typeof body.email==='string'?body.email.trim().toLowerCase():'',name=typeof body.full_name==='string'?body.full_name.trim():'',password=body.password,role=body.role;
   if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||!name||name.length>200||typeof password!=='string'||password.length<12||password.length>256||!['administrador','comercial','almacenero','rrhh'].includes(role))return reply({error:'INVALID_INPUT'},400);
   const created=await call('/auth/v1/admin/users',{method:'POST',admin:true,body:{email,password,email_confirm:true,user_metadata:{full_name:name}}});
   if(!created.ok||!uuid.test(created.data?.id||''))return reply({error:created.status===429?'USER_RATE_LIMIT':'USER_CREATE_FAILED'},created.status===429?429:400);
   const id=created.data.id,again=await allowed();
   if(!again.ok||again.data!==true){await call('/auth/v1/admin/users/'+id,{method:'DELETE',admin:true});return reply({error:'MODULE_OR_ACTION_NOT_ALLOWED'},403)}
   const saved=await call('/rest/v1/profiles?on_conflict=id',{method:'POST',admin:true,body:{id,full_name:name,role,active:true}});
   if(!saved.ok){await call('/auth/v1/admin/users/'+id,{method:'DELETE',admin:true});return reply({error:'USER_PROFILE_FAILED'},409)}
   return reply({id,email,full_name:name,role},201);
  }catch(error){return reply({error:error instanceof BodyError?error.message:'IDENTITY_UNAVAILABLE'},error instanceof BodyError?error.status:503)}
 };
}
