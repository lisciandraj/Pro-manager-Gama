import {readJsonBody} from '../_shared/http.mjs';
const publicHosts=new Set(['routing.openstreetmap.de','router.project-osrm.org']);
const sha=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),b=>b.toString(16).padStart(2,'0')).join('');
const point=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&Math.abs(p[0])<=180&&Math.abs(p[1])<=85;
export function configuration(env){
 const raw=env('TMS_OSRM_URL');if(!raw)return null;
 const url=new URL(raw);
 if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||publicHosts.has(url.hostname.replace(/\.$/,''))||url.hostname==='localhost'||url.hostname.endsWith('.localhost')||/^127\.|^169\.254\.|^0\.|^\[/.test(url.hostname))throw Error('ROAD_CONFIGURATION_INVALID');
 return {base:url.href.replace(/\/$/,''),token:env('TMS_OSRM_TOKEN'),version:env('TMS_ROAD_DATA_VERSION')||'1'};
}
// At most 80 coordinates / 1600 cells per OSRM request. A 100-stop day
// plus ten endpoints needs at most nine requests, never a public demo call.
export async function matrix(points,config,fetcher,signal){
 if(!Array.isArray(points)||points.length<2||points.length>128||!points.every(point))throw Error('ROAD_RESPONSE_INVALID');
 const n=points.length,distances=Array.from({length:n},()=>Array(n).fill(null)),durations=Array.from({length:n},()=>Array(n).fill(null));
 const tasks=[];for(let a=0;a<n;a+=40)for(let b=0;b<n;b+=40)tasks.push({a,b});
 let next=0;
 async function worker(){while(next<tasks.length){
  const {a,b}=tasks[next++],src=points.slice(a,a+40),dst=points.slice(b,b+40),same=a===b,loc=same?src:[...src,...dst];
  const query=new URLSearchParams({annotations:'distance,duration',sources:src.map((_,i)=>i).join(';'),destinations:dst.map((_,i)=>i+(same?0:src.length)).join(';'),radiuses:loc.map(()=>500).join(';'),generate_hints:'false'});
  const r=await fetcher(config.base+'/table/v1/driving/'+loc.map(p=>p.join(',')).join(';')+'?'+query,{signal,redirect:'error',credentials:'omit',headers:config.token?{Authorization:'Bearer '+config.token}:{}});
  if(!r.ok)throw Error('ROAD_PROVIDER_UNAVAILABLE');const data=await readJsonBody(r,2*1024*1024);
  if(data.code!=='Ok'||data.fallback_speed_cells?.length||!Array.isArray(data.distances)||!Array.isArray(data.durations)||data.distances.length!==src.length||data.durations.length!==src.length)throw Error('ROAD_RESPONSE_INVALID');
  // The server must not silently snap an address to a distant road.
  for(const waypoints of [data.sources,data.destinations])if(!Array.isArray(waypoints)||waypoints.some(p=>!Number.isFinite(p.distance)||p.distance>500||p.distance<0))throw Error('ROAD_RESPONSE_INVALID');
  if(data.sources.length!==src.length||data.destinations.length!==dst.length)throw Error('ROAD_RESPONSE_INVALID');
  for(let i=0;i<src.length;i++){
   if(!Array.isArray(data.distances[i])||!Array.isArray(data.durations[i])||data.distances[i].length!==dst.length||data.durations[i].length!==dst.length)throw Error('ROAD_RESPONSE_INVALID');
   for(let j=0;j<dst.length;j++){
    const meters=data.distances[i][j],seconds=data.durations[i][j];
    if(!(meters===null&&seconds===null)&&(!Number.isFinite(meters)||!Number.isFinite(seconds)||meters<0||meters>2e7||seconds<0||seconds>604800))throw Error('ROAD_RESPONSE_INVALID');
    if(a+i===b+j&&(meters!==0||seconds!==0))throw Error('ROAD_RESPONSE_INVALID');
    distances[a+i][b+j]=meters===null?null:meters/1000;durations[a+i][b+j]=seconds;
   }
  }
 }}
 await Promise.all([worker(),worker()]);return {distances,durations};
}
export function createHandler({env,fetch:fetcher}){
 return async req=>{
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':'https://lisciandraj.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS',Vary:'Origin'};
  const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
  if(req.headers.get('origin')&&req.headers.get('origin')!=='https://lisciandraj.github.io')return reply({error:'ORIGIN_NOT_ALLOWED'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
  const token=req.headers.get('authorization');if(!/^Bearer \S+$/i.test(token||''))return reply({error:'AUTH_REQUIRED'},401);
  const root=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),service=env('SUPABASE_SERVICE_ROLE_KEY');let claim;
  const rpc=async(name,args,elevated=false)=>{
   const key=elevated?service:anon;
   const r=await fetcher(root+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:elevated?'Bearer '+key:token,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(elevated?30000:15000),redirect:'error'});
   const body=await readJsonBody(r,1024*1024);if(!r.ok){const code=body.message||body.code;if(['ROAD_MATRIX_BUSY','ROAD_MATRIX_RATE_LIMIT','ROAD_MATRIX_LOCATION_LIMIT','ROAD_MATRIX_STALE'].includes(code))throw Error(code);throw Error('TMS_ACCESS_DENIED')}return body;
  };
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),45000);
  try{
   const body=await readJsonBody(req,1024);if(!/^\d{4}-\d{2}-\d{2}$/.test(body.day||''))return reply({error:'PLANNING_DATE_INVALID'},400);
   // Authorize before configuration/cache information or any elevated request.
   await rpc('gama_tms_routing',{p_action:'status',p_data:{day:body.day}});
   const config=configuration(env);if(!config)return reply({error:'ROAD_PROVIDER_NOT_CONFIGURED'},409);
   const scope=await sha(config.base+'|car|'+config.version);
   claim=await rpc('gama_tms_routing',{p_action:'claim',p_data:{day:body.day,scope}});
   if(claim.cached||claim.empty)return reply({cached:!!claim.cached,empty:!!claim.empty});
   const result=await matrix(claim.points,config,fetcher,controller.signal);
   const committed=await rpc('gama_tms_routing_commit',{p_data:{day:claim.day,lease:claim.lease,actor_id:claim.actor_id,...result}},true);
   return reply({stored:committed.stored,locations:committed.locations,expires_at:committed.expires_at});
  }catch(error){
   controller.abort();
   // Never return upstream bodies, URLs, tokens or customer coordinates.
   if(claim?.lease)try{await rpc('gama_tms_routing_commit',{p_data:{day:claim.day,lease:claim.lease,actor_id:claim.actor_id,error:'ROAD_PROVIDER_UNAVAILABLE'}},true)}catch{}
   const code=['TMS_ACCESS_DENIED','ROAD_MATRIX_BUSY','ROAD_MATRIX_RATE_LIMIT','ROAD_MATRIX_LOCATION_LIMIT','ROAD_MATRIX_STALE','ROAD_CONFIGURATION_INVALID'].includes(error.message)?error.message:'ROAD_PROVIDER_UNAVAILABLE';
   return reply({error:code},code==='TMS_ACCESS_DENIED'?403:code==='ROAD_MATRIX_RATE_LIMIT'?429:code==='ROAD_PROVIDER_UNAVAILABLE'?503:409);
  }finally{clearTimeout(timer)}
 };
}
