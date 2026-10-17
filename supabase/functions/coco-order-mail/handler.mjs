import {readJsonBody,BodyError} from '../_shared/http.mjs';
import {GOOGLE_SCOPES,MICROSOFT_SCOPES,b64url,unb64,sha,MailError,validateAttachments,createProvider} from './provider.mjs';
const ORIGIN='https://lisciandraj.github.io',APP=ORIGIN+'/Pro-manager-Gama/';
const encoder=new TextEncoder(),decoder=new TextDecoder();
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function createHandler({env,fetch:fetcher}){
 const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 const provider=createProvider(fetcher),redirect=root+'/functions/v1/coco-order-mail/callback';
 const settings=name=>name==='google'?{id:env('COCO_GOOGLE_CLIENT_ID'),secret:env('COCO_GOOGLE_CLIENT_SECRET'),auth:'https://accounts.google.com/o/oauth2/v2/auth',token:'https://oauth2.googleapis.com/token',scope:GOOGLE_SCOPES}:{id:env('COCO_MICROSOFT_CLIENT_ID'),secret:env('COCO_MICROSOFT_CLIENT_SECRET'),auth:'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',token:'https://login.microsoftonline.com/common/oauth2/v2.0/token',scope:MICROSOFT_SCOPES};
 const configured=name=>!!(settings(name).id&&settings(name).secret&&env('COCO_MAIL_ENCRYPTION_KEY'));
 async function crypt(value,decrypt=false){
  let raw;try{raw=unb64(env('COCO_MAIL_ENCRYPTION_KEY')||'')}catch{throw new MailError('MAIL_NOT_CONFIGURED',503)}
  if(raw.length!==32)throw new MailError('MAIL_NOT_CONFIGURED',503);
  const key=await crypto.subtle.importKey('raw',raw,{name:'AES-GCM'},false,['encrypt','decrypt']);
  if(decrypt){const [iv,data]=value.split('.');return decoder.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(iv)},key,unb64(data)))}
  const iv=crypto.getRandomValues(new Uint8Array(12));return b64url(iv)+'.'+b64url(new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv},key,encoder.encode(value))));
 }
 async function db(action,data,token=null){
  const r=await fetcher(root+'/rest/v1/rpc/'+(token?'coco_order_followup':'coco_order_mail_service'),{method:'POST',headers:{apikey:token?anon:service,Authorization:token||'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(15000)});
  const d=await r.json().catch(()=>null);if(!r.ok)throw new MailError(/^(AUTH_OR_MFA_REQUIRED|ROLE_NOT_ALLOWED|MAILBOX_REQUIRED|MAILBOX_EMAIL_MISMATCH|OAUTH_EXPIRED|REQUEST_KEY_REUSED|REPLY_NOT_ALLOWED|INVALID_MESSAGE|ORDER_NOT_FOUND)$/.test(d?.message||'')?d.message:'MAIL_STORAGE_UNAVAILABLE',r.status===401?401:400);return d;
 }
 async function tokens(name,fields){
  const c=settings(name);let r;try{r=await fetcher(c.token,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:c.id,client_secret:c.secret,...fields}),signal:AbortSignal.timeout(20000),redirect:'error'})}catch{throw new MailError('MAIL_PROVIDER_UNAVAILABLE',503)}
  const d=await r.json();if(!r.ok||!d.access_token)throw new MailError('MAILBOX_RECONNECT');return {...d,expires_at:Date.now()+Number(d.expires_in||3600)*1000};
 }
 async function account(uid){
  const a=await db('account',{user_id:uid});if(!a)throw new MailError('MAILBOX_REQUIRED');if(!configured(a.provider))throw new MailError('MAIL_NOT_CONFIGURED',503);
  let t=JSON.parse(await crypt(a.credentials,true));if(t.expires_at<Date.now()+60000){
   if(!t.refresh_token)throw new MailError('MAILBOX_RECONNECT');
   const fresh=await tokens(a.provider,{grant_type:'refresh_token',refresh_token:t.refresh_token,...(a.provider==='microsoft'?{scope:MICROSOFT_SCOPES}:{})});t={...t,...fresh,refresh_token:fresh.refresh_token||t.refresh_token};
   await db('account_save',{user_id:uid,provider:a.provider,email:a.email,credentials:await crypt(JSON.stringify(t))});
  }return {...a,...t};
 }
 return async req=>{
  const cors={'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
  const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  const url=new URL(req.url);
  if(req.method==='GET'&&url.pathname.endsWith('/callback')){
   try{
    const raw=url.searchParams.get('state');if(!raw||raw.length>200)throw new MailError('OAUTH_EXPIRED');
    const s=await db('oauth_take',{state_hash:await sha(raw)});
    if(url.searchParams.has('error'))throw new MailError('OAUTH_CANCELLED');
    const code=url.searchParams.get('code');if(!code||code.length>4096||!configured(s.provider))throw new MailError('MAIL_NOT_CONFIGURED');
    const t=await tokens(s.provider,{grant_type:'authorization_code',code,redirect_uri:redirect,code_verifier:await crypt(s.verifier,true)});
    const address=await provider.identity(s.provider,t.access_token);
    if(address?.toLowerCase()!==s.email?.toLowerCase())throw new MailError('MAILBOX_EMAIL_MISMATCH');
    if(!t.refresh_token)throw new MailError('MAILBOX_RECONNECT');
    const required=settings(s.provider).scope.split(' ').filter(x=>x!=='offline_access');if(required.some(scope=>!(t.scope||'').toLowerCase().split(' ').some(x=>x===scope.toLowerCase()||x.endsWith('/'+scope.toLowerCase()))))throw new MailError('MAIL_SCOPE_REQUIRED');
    await db('account_save',{user_id:s.user_id,provider:s.provider,email:address,credentials:await crypt(JSON.stringify(t))});
    return Response.redirect(APP+'?coco_mail=connected',303);
   }catch(e){const code=e instanceof MailError?e.message:'MAIL_CONNECTION_FAILED';return Response.redirect(APP+'?coco_mail='+encodeURIComponent(code),303)}
  }
  if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
  if(req.headers.get('origin')&&req.headers.get('origin')!==ORIGIN)return reply({error:'ORIGIN_NOT_ALLOWED'},403);
  try{
   const token=req.headers.get('authorization');if(!token?.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
   const r=await fetcher(root+'/auth/v1/user',{headers:{apikey:anon,Authorization:token},signal:AbortSignal.timeout(15000)}),user=await r.json();
   if(!r.ok||!uuid.test(user?.id||''))return reply({error:'AUTH_REQUIRED'},401);
   const data=await readJsonBody(req,7500000),base={kind:data.kind,order_id:data.order_id};
   const context=await db('context',base,token);
   if(context.actor_id!==user.id||!context.can_mail)throw new MailError('ROLE_NOT_ALLOWED',403);
   if(data.action==='status')return reply({google:configured('google'),microsoft:configured('microsoft'),mailbox:context.mailbox,redirect_uri:redirect});
   if(data.action==='connect'){
    if(!['google','microsoft'].includes(data.provider)||!configured(data.provider))throw new MailError('MAIL_NOT_CONFIGURED',503);
    const s=b64url(crypto.getRandomValues(new Uint8Array(32))),verifier=b64url(crypto.getRandomValues(new Uint8Array(48))),c=settings(data.provider);
    await db('oauth_store',{user_id:user.id,provider:data.provider,state_hash:await sha(s),verifier:await crypt(verifier)});
    const q=new URLSearchParams({client_id:c.id,redirect_uri:redirect,response_type:'code',scope:c.scope,state:s,code_challenge:await sha(verifier),code_challenge_method:'S256',login_hint:context.account_email,...(data.provider==='google'?{access_type:'offline',prompt:'consent'}:{prompt:'select_account',response_mode:'query'})});
    return reply({url:c.auth+'?'+q});
   }
   const a=await account(user.id);
   if(data.action==='send'){
    const attachments=validateAttachments(data.attachments,a.provider);
    const claim=await db('mail_claim',{...base,request_key:data.request_key,to:data.to,subject:data.subject,body:data.body,reply_id:data.reply_id,attachments:attachments.map(({name,type,size})=>({name,type,size}))},token);
    if(!claim.claimed)return reply({id:claim.id,status:claim.status,duplicate:true});
    const saved=await db('message',{user_id:user.id,id:claim.id});
    try{
     // Authorize again immediately before the external side effect.
     const fresh=await db('context',base,token);if(!fresh.can_mail||fresh.account_email?.toLowerCase()!==a.email?.toLowerCase())throw new MailError('ROLE_NOT_ALLOWED',403);
     const sent=await provider.send(a,saved,attachments,refs=>db('message_status',{user_id:user.id,id:claim.id,...refs}));
     await db('message_status',{user_id:user.id,id:claim.id,...sent});return reply({id:claim.id,status:sent.status});
    }catch(e){
     const uncertain=!(e instanceof MailError)||['PROVIDER_UNCERTAIN','MAIL_STORAGE_UNAVAILABLE'].includes(e.message);
     await db('message_status',{user_id:user.id,id:claim.id,status:uncertain?'uncertain':'failed'}).catch(()=>{});
     return reply({id:claim.id,status:uncertain?'uncertain':'failed',error:uncertain?'MAIL_SEND_UNCERTAIN':e.message},uncertain?503:400);
    }
   }
   if(data.action==='sync'){
    const pending=await db('pending',{...base,user_id:user.id});
    for(const entry of pending.filter(e=>e.provider===a.provider)){
     const recovered=await provider.recover(a,entry);
     if(recovered)await db('message_status',{user_id:user.id,id:entry.id,...recovered});
    }
    const threads=await db('threads',{...base,user_id:user.id});let imported=0;
    for(const thread of threads.filter(t=>t.provider===a.provider)){
     const messages=await provider.thread(a,thread.thread_id);
     // Rights can change while provider requests are in progress.
     const fresh=await db('context',base,token);if(!fresh.can_mail)throw new MailError('ROLE_NOT_ALLOWED',403);
     for(const message of messages){const x=await db('import',{...base,...message,user_id:user.id,provider:a.provider});if(x.imported)imported++}
    }
    return reply({imported,synced_at:new Date().toISOString()});
   }
   throw new MailError('INVALID_ACTION');
  }catch(e){return reply({error:e instanceof MailError||e instanceof BodyError?e.message:'MAIL_UNAVAILABLE'},e instanceof MailError||e instanceof BodyError?e.status:503)}
 };
}
