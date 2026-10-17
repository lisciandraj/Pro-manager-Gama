/* Coco ERP authenticated data transport. Historical GamaCloud API is retained. */
(function(){'use strict';
/* Este archivo lo cargan dos sitios: index.html y gama-access-control.js (que
   lo inyecta cuando aún no está). Sin esta guarda el IIFE se ejecutaba dos
   veces: dos clientes Supabase, dos suscripciones onAuthStateChange y una
   segunda copia de cada módulo de GamaCloudReady. Una sola capa de datos. */
if(window.GamaCloud&&window.GamaCloudReady)return;
const SUPABASE_URL='https://mknsaibrewksgomuslev.supabase.co';
const SUPABASE_PUBLISHABLE_KEY='sb_publishable_4l0vZw61u5EbLkzmrqrf6Q_phOL1Be9';
const SUPABASE_ANON_KEY=window.GAMA_SUPABASE_ANON_KEY||SUPABASE_PUBLISHABLE_KEY;
let client=null,initializing=null,realtime=[],profileRequest=null;
const reads=new Set();
/* Only reads use deadlines. Never retry or abort an in-flight business write. */
async function read(make,options={}){
 const controller=new AbortController(),signal=options.signal;
 const timeout=Math.min(60000,Math.max(1000,Number(options.timeoutMs)||15000));
 const abort=()=>controller.abort();let timer;
 reads.add(controller);signal?.addEventListener('abort',abort,{once:true});
 try{
  if(signal?.aborted)controller.abort();
  return await Promise.race([
   Promise.resolve().then(()=>{if(controller.signal.aborted)throw Error('READ_CANCELLED');return make(controller.signal)}),
   new Promise((_,reject)=>{timer=setTimeout(()=>{reject(Object.assign(Error('TIMEOUT'),{code:'TIMEOUT'}));controller.abort()},timeout);controller.signal.addEventListener('abort',()=>reject(Object.assign(Error('READ_CANCELLED'),{code:'READ_CANCELLED'})),{once:true})})
  ]);
 }finally{clearTimeout(timer);reads.delete(controller);signal?.removeEventListener('abort',abort)}
}
function emit(name,detail){window.dispatchEvent(new CustomEvent(name,{detail:detail||{}}));}
function loadClient(){if(window.supabase&&window.supabase.createClient)return Promise.resolve(window.supabase);if(window.__gamaSupabaseLoader)return window.__gamaSupabaseLoader;window.__gamaSupabaseLoader=new Promise(function(resolve,reject){const s=document.createElement('script');s.src='assets/vendor/supabase-2.115.0.js';s.integrity='sha384-CLZeq1dk8+Uzrs7TVvBUdlFoV5F0DMqgRoeHa8g5wJcuPe5SkVfEvdxB0ZuzlnBQ';s.crossOrigin='anonymous';s.async=true;s.onload=()=>window.supabase&&window.supabase.createClient?resolve(window.supabase):reject(Error('Supabase JS unavailable'));s.onerror=()=>reject(Error('Unable to load Supabase JS'));document.head.appendChild(s)});return window.__gamaSupabaseLoader;}
async function init(){
 if(!SUPABASE_ANON_KEY){emit('gama:cloud-status',{ready:false,configured:false});return null}
 if(client)return client;if(initializing)return initializing;
 initializing=(async()=>{const sb=await loadClient();client=sb.createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});client.auth.onAuthStateChange((event,session)=>{if(event!=='TOKEN_REFRESHED')for(const controller of reads)controller.abort();emit('gama:auth-change',{event,session})});emit('gama:cloud-status',{ready:true,configured:true,url:SUPABASE_URL});return client})();
 try{return await initializing}finally{initializing=null}
}
async function db(){const c=await init();if(!c)throw Error('Supabase public key not configured');return c}
async function getSession(){return (await db()).auth.getSession()}
async function signIn(email,password){return (await db()).auth.signInWithPassword({email,password})}
async function signOut(){const c=await db();let r;try{r=await c.auth.signOut({scope:'local'})}catch(e){r={error:e}}try{Object.keys(localStorage).forEach(k=>{if(k.startsWith('sb-')&&k.includes('-auth-token'))localStorage.removeItem(k)})}catch(e){}return r}
async function getProfile(){
 const c=await db(),r=await c.auth.getSession(),s=r.data?.session,u=s?.user;
 if(!u)return {data:null,error:null};
 // Share only concurrent reads for the exact authenticated session. Never
 // cache permissions across refreshes, account changes or later requests.
 const key=u.id+':'+s.access_token;
 if(profileRequest?.key===key)return profileRequest.promise;
 const job={key,promise:read(signal=>c.from('profiles').select('*').eq('id',u.id).abortSignal(signal).maybeSingle()).catch(error=>({data:null,error}))};
 profileRequest=job;
 try{return await job.promise}finally{if(profileRequest===job)profileRequest=null}
}
/* List options are validated below. Unsupported filters fail explicitly.
   head:true + count:'exact' requests a total without downloading rows.
   Complete primary-key ordering keeps pagination stable when sort values tie. */
const LIST_KEYS={
 erp_notification_preferences:['user_id'],
 erp_price_book_customers:['book_id','customer_id'],
 accounting_permissions:['profile_id'],external_invoice_deliveries:['invoice_id','delivery_id'],
 fulfillment_package_lines:['package_id','pick_line_id'],gama_document_references:['table_name','document_id'],
 hr_absence_private:['absence_id'],hr_employee_private:['employee_id'],hr_holidays:['day'],
 sales_reservation_links:['reservation_id'],tms_loading_allocations:['scan_id','delivery_line_id'],
 tms_proofs:['delivery_id'],user_home_preferences:['user_id'],role_module_access:['role'],erp_action_permissions:['role','module'],service_sla_rules:['priority']
};
async function list(table,options={}){
 const supported=new Set(['select','count','head','order','ascending','eq','ilike','in','gte','lte','lt','gt','neq','is','range','limit','search','signal','timeoutMs']);
 for(const key of Object.keys(options))if(!supported.has(key))throw Error('Unsupported list option: '+key);
 const c=await db();let q=c.from(table==='tms_proofs'?'tms_proofs_read':table).select(options.select||'*',options.count?{count:options.count,head:!!options.head}:undefined);
 if(options.order){
  const keys=LIST_KEYS[table]||['id'],first=options.order==='id'?keys[0]:options.order;
  q=q.order(first,{ascending:options.ascending!==false});
  for(const key of keys)if(key!==first)q=q.order(key,{ascending:true});
 }
 for(const method of ['eq','ilike','in','gte','lte','lt','gt','neq','is'])if(options[method])for(const [key,value] of Object.entries(options[method]))q=q[method](key,value);
 if(options.search){
  const {columns,value}=options.search;
  if(!Array.isArray(columns)||!columns.length||columns.some(k=>!/^[_a-z][_a-z0-9]*$/.test(k)))throw Error('INVALID_SEARCH_COLUMNS');
  const pattern='%'+String(value).replace(/[\\%_]/g,'\\$&')+'%';
  const quoted='"'+pattern.replace(/\\/g,'\\\\').replace(/"/g,'\\"')+'"';
  q=q.or(columns.map(k=>k+'.ilike.'+quoted).join(','));
 }
 if(options.range)q=q.range(options.range[0],options.range[1]);else if(options.limit)q=q.limit(options.limit);
 try{return await read(async signal=>{if(q.abortSignal)q=q.abortSignal(signal);const r=await q;return window.GamaReferences?window.GamaReferences.attach(table,r,c):r},options)}catch(error){return {data:null,error}}
}
async function insert(table,row){const c=await db(),r=await c.from(table).insert(row).select().single();if(!r.error)emit('gama:data-change',{table});return window.GamaReferences?window.GamaReferences.attach(table,r,c):r}
/* upsert: para tablas cuya clave no es "id" (p. ej. tms_proofs.delivery_id) o de fila única (tms_settings). */
async function upsert(table,row,options){const c=await db(),r=await c.from(table).upsert(row,options||{}).select(table==='tms_proofs'?'delivery_id,signature,captured_at,captured_by':'*').single();if(!r.error)emit('gama:data-change',{table});return window.GamaReferences?window.GamaReferences.attach(table,r,c):r}
async function update(table,id,row){const r=await (await db()).from(table).update(row).eq('id',id).select().single();if(!r.error)emit('gama:data-change',{table});return r}
async function remove(table,id){const r=await (await db()).from(table).delete().eq('id',id);if(!r.error)emit('gama:data-change',{table});return r}
async function subscribe(table,callback){const c=await db();const ch=c.channel('gama-'+table+'-'+Date.now()).on('postgres_changes',{event:'*',schema:'public',table},p=>{emit('gama:data-change',{table,payload:p});if(typeof callback==='function')callback(p)}).subscribe();realtime.push(ch);return ch}
function unsubscribeAll(){if(!client)return;realtime.forEach(ch=>{try{client.removeChannel(ch)}catch(e){}});realtime=[]}
window.GamaCloud={url:SUPABASE_URL,init,db,read,getSession,signIn,signOut,getProfile,list,insert,upsert,update,remove,subscribe,unsubscribeAll,tables:{profiles:'profiles',products:'products',suppliers:'suppliers',customers:'customers',stockMovements:'stock_movements',invoices:'invoices',invoiceLines:'invoice_lines',commercialMatrix:'commercial_matrix',tmsDeliveries:'tms_deliveries',tmsRoutes:'tms_routes',tmsProofs:'tms_proofs',tmsEvents:'tms_events',tmsSettings:'tms_settings'}};
window.GamaCloudReady=init().then(function(){if(window.GAMA_STANDALONE_WEBSITE)return window.GamaCloud;['gama-cloud-products.js?v=20260913-i18n1','gama-cloud-auth.js?v=20260918-architect1','gama-cloud-users.js?v=20260918-architect1','gama-purchases-supplier-bridge.js?v=20260913-i18n1','gama-invoice-archive.js?v=20260918-architect1'].forEach(function(src){const s=document.createElement('script');s.src=window.ArcAssets?.[src.split('?')[0]]||src;s.async=true;document.head.appendChild(s)});return window.GamaCloud});
})();
