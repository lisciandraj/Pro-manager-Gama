import {readJsonBody,BodyError} from '../_shared/http.mjs';
const origin='https://lisciandraj.github.io';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function createHandler({env,fetch:fetcher}){
 const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 return async req=>{const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return reply({error:'ORIGIN_NOT_ALLOWED'},403);
 try{const token=req.headers.get('authorization');if(!token?.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
 const request=async(path,{method='GET',body,admin=false}={})=>{const r=await fetcher(root+path,{method,headers:{apikey:admin?service:anon,Authorization:admin?'Bearer '+service:token,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});const data=await r.json().catch(()=>null);return {ok:r.ok,status:r.status,data}};
 const user=await request('/auth/v1/user');if(!user.ok||!uuid.test(user.data?.id||''))return reply({error:'AUTH_REQUIRED'},401);
 const profile=await request('/rest/v1/profiles?select=id,role,active,access_profile&id=eq.'+user.data.id);
 if(!profile.ok||profile.data?.[0]?.role!=='administrador'||profile.data[0].active!==true)return reply({error:'ADMIN_OR_MFA_REQUIRED'},403);
 const mod=await request('/rest/v1/rpc/gama_identity_admin_allowed',{method:'POST',body:{}});if(!mod.ok||mod.data!==true)return reply({error:'MODULE_OR_ACTION_NOT_ALLOWED'},403);
 const data=await readJsonBody(req,12000);
 if(!['invite','invite_b2b'].includes(data.action))return reply({error:'INVALID_ACTION'},400);
 const b2b=data.action==='invite_b2b',email=String(data.email||'').trim().toLowerCase(),name=String(data.name||'').trim(),role=b2b?'cliente':data.role;
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||!name||name.length>200||(!b2b&&!['administrador','comercial','almacenero','rrhh'].includes(role))||(b2b&&!uuid.test(data.customer_id||'')))return reply({error:'INVALID_INVITATION'},400);
 // Check all portal and identity permissions before the explicit email action.
 if(b2b){const context=await request('/rest/v1/rpc/gama_b2b_admin',{method:'POST',body:{p_action:'invitation_context',p_data:{customer_id:data.customer_id}}});if(!context.ok||context.data?.allowed!==true)return reply({error:'B2B_INVITATION_NOT_ALLOWED'},403)}
 // The personalised subject and message travel as metadata; the Supabase invite template prints them ({{ .Data.invite_subject }}, {{ .Data.invite_message }}).
 const clean=(v,max)=>String(v??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,'').trim().slice(0,max);
 const subject=clean(data.subject,150),message=clean(data.message,4000),company=clean(data.company,200);
 if((data.subject!==undefined&&!subject)||(data.message!==undefined&&!message))return reply({error:'INVALID_INVITATION'},400);
 const meta={full_name:name};if(b2b)meta.b2b_portal=true;if(subject)meta.invite_subject=subject;if(message)meta.invite_message=message;if(company)meta.company_name=company;
 // Supabase sends the invitation only for this explicit user action. New accounts remain inactive.
 const invited=await request('/auth/v1/invite?redirect_to='+encodeURIComponent(origin+'/Pro-manager-Gama/?setup=password'),{method:'POST',admin:true,body:{email,data:meta}});
 if(!invited.ok)return reply({error:invited.status===429?'INVITATION_RATE_LIMIT':'INVITATION_FAILED'},invited.status===429?429:400);
 const id=invited.data?.id;if(!uuid.test(id||''))return reply({error:'INVITATION_RESULT_INVALID'},502);
 const saved=await request('/rest/v1/profiles?id=eq.'+id,{method:'PATCH',admin:true,body:{role,full_name:name,active:false}});
 if(!saved.ok)return reply({error:'INVITED_REVIEW_PROFILE',user_id:id},409);
 if(b2b){const linked=await request('/rest/v1/rpc/gama_b2b_admin',{method:'POST',body:{p_action:'member',p_data:{customer_id:data.customer_id,profile_id:id,active:true,expected_customer_id:null}}});if(!linked.ok||linked.data?.saved!==true)return reply({error:'INVITED_REVIEW_B2B',user_id:id},409)}
 return reply({invited:true,user_id:id,active:false,...(b2b?{portal_access:true}:{})});
 }catch(error){return reply({error:error instanceof BodyError?error.message:'IDENTITY_UNAVAILABLE'},error instanceof BodyError?error.status:503)}};
}
