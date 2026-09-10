/* GAMA V18 — central Supabase data layer */
(function(){'use strict';
/* Este archivo lo cargan dos sitios: index.html y gama-access-control.js (que
   lo inyecta cuando aún no está). Sin esta guarda el IIFE se ejecutaba dos
   veces: dos clientes Supabase, dos suscripciones onAuthStateChange y una
   segunda copia de cada módulo de GamaCloudReady. Una sola capa de datos. */
if(window.GamaCloud&&window.GamaCloudReady)return;
const SUPABASE_URL='https://mknsaibrewksgomuslev.supabase.co';
const SUPABASE_PUBLISHABLE_KEY='sb_publishable_4l0vZw61u5EbLkzmrqrf6Q_phOL1Be9';
const SUPABASE_ANON_KEY=window.GAMA_SUPABASE_ANON_KEY||SUPABASE_PUBLISHABLE_KEY;
let client=null,realtime=[];
function emit(name,detail){window.dispatchEvent(new CustomEvent(name,{detail:detail||{}}));}
function loadClient(){if(window.supabase&&window.supabase.createClient)return Promise.resolve(window.supabase);if(window.__gamaSupabaseLoader)return window.__gamaSupabaseLoader;window.__gamaSupabaseLoader=new Promise(function(resolve,reject){const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.115.0';s.integrity='sha384-EyR2P0dlmjnEGcm9xcjdAn0VedZpRHEwDLP9oSS6wYMvzHBHkUrvgonveazJ/sSx';s.crossOrigin='anonymous';s.async=true;s.onload=()=>window.supabase&&window.supabase.createClient?resolve(window.supabase):reject(Error('Supabase JS unavailable'));s.onerror=()=>reject(Error('Unable to load Supabase JS'));document.head.appendChild(s)});return window.__gamaSupabaseLoader;}
async function init(){if(!SUPABASE_ANON_KEY){emit('gama:cloud-status',{ready:false,configured:false});return null}if(client)return client;const sb=await loadClient();client=sb.createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});client.auth.onAuthStateChange((event,session)=>emit('gama:auth-change',{event,session}));emit('gama:cloud-status',{ready:true,configured:true,url:SUPABASE_URL});return client;}
async function db(){const c=await init();if(!c)throw Error('Supabase public key not configured');return c}
async function getSession(){return (await db()).auth.getSession()}
async function signIn(email,password){return (await db()).auth.signInWithPassword({email,password})}
async function signOut(){const c=await db();let r;try{r=await c.auth.signOut({scope:'local'})}catch(e){r={error:e}}try{Object.keys(localStorage).forEach(k=>{if(k.startsWith('sb-')&&k.includes('-auth-token'))localStorage.removeItem(k)})}catch(e){}return r}
async function getProfile(){const c=await db(),r=await c.auth.getSession(),u=r.data?.session?.user;if(!u)return {data:null,error:null};return c.from('profiles').select('*').eq('id',u.id).maybeSingle()}
/* list() acepta: select, count, head, order/ascending, eq, ilike, in, gte, lte,
   lt, gt, range, limit. Lo que no esté en esa lista se IGNORA en silencio, que
   es la trampa que ya costó una pantalla entera —Compras llamaba a un select()
   que no existía— y que aquí habría contado como «vencidas» todas las tareas
   abiertas. Si hace falta un filtro nuevo, se añade aquí; no se inventa en la
   pantalla que lo necesita.

   head:true va con count: pide a la nube el número sin traer ni una fila. Es
   la diferencia entre contar 50.000 filas y descargarlas. */
async function list(table,options){const c=await db();options=options||{};let q=c.from(table).select(options.select||'*',options.count?{count:options.count,head:!!options.head}:undefined);if(options.order)q=q.order(options.order,{ascending:options.ascending!==false});if(options.eq)Object.keys(options.eq).forEach(k=>q=q.eq(k,options.eq[k]));if(options.ilike)Object.keys(options.ilike).forEach(k=>q=q.ilike(k,options.ilike[k]));if(options.in)Object.keys(options.in).forEach(k=>q=q.in(k,options.in[k]));if(options.gte)Object.keys(options.gte).forEach(k=>q=q.gte(k,options.gte[k]));if(options.lte)Object.keys(options.lte).forEach(k=>q=q.lte(k,options.lte[k]));if(options.lt)Object.keys(options.lt).forEach(k=>q=q.lt(k,options.lt[k]));if(options.gt)Object.keys(options.gt).forEach(k=>q=q.gt(k,options.gt[k]));if(options.range)q=q.range(options.range[0],options.range[1]);else if(options.limit)q=q.limit(options.limit);return q}
async function insert(table,row){return (await db()).from(table).insert(row).select().single()}
/* upsert: para tablas cuya clave no es "id" (p. ej. tms_proofs.delivery_id) o de fila única (tms_settings). */
async function upsert(table,row,options){return (await db()).from(table).upsert(row,options||{}).select().single()}
async function update(table,id,row){return (await db()).from(table).update(row).eq('id',id).select().single()}
async function remove(table,id){return (await db()).from(table).delete().eq('id',id)}
async function subscribe(table,callback){const c=await db();const ch=c.channel('gama-'+table+'-'+Date.now()).on('postgres_changes',{event:'*',schema:'public',table},p=>{emit('gama:data-change',{table,payload:p});if(typeof callback==='function')callback(p)}).subscribe();realtime.push(ch);return ch}
function unsubscribeAll(){if(!client)return;realtime.forEach(ch=>{try{client.removeChannel(ch)}catch(e){}});realtime=[]}
window.GamaCloud={url:SUPABASE_URL,init,db,getSession,signIn,signOut,getProfile,list,insert,upsert,update,remove,subscribe,unsubscribeAll,tables:{profiles:'profiles',products:'products',suppliers:'suppliers',customers:'customers',stockMovements:'stock_movements',invoices:'invoices',invoiceLines:'invoice_lines',commercialMatrix:'commercial_matrix',tmsDrivers:'tms_drivers',tmsDeliveries:'tms_deliveries',tmsRoutes:'tms_routes',tmsProofs:'tms_proofs',tmsEvents:'tms_events',tmsSettings:'tms_settings'}};
window.GamaCloudReady=init().then(function(){['gama-cloud-products.js?v=19','gama-cloud-auth.js?v=19','gama-cloud-users.js?v=21','gama-purchases-supplier-bridge.js?v=5','gama-invoice-archive.js?v=6'].forEach(function(src){const s=document.createElement('script');s.src=src;s.async=true;document.head.appendChild(s)});return window.GamaCloud});
})();
