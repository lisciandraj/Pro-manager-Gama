import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {configuration,matrix} from '../supabase/functions/tms-routing/handler.mjs';

// Public sample locations, never customer records. Production checks are read-only.
export const publicSamples=[[-78.5091,-.2192],[-78.501,-.2],[-78.486,-.18],[-78.511,-.16]];
export function checkConfiguration(env,loopback=false,raw=false){
 const base=env.TMS_OSRM_URL;
 if(!base)throw Error('ROAD_PROVIDER_NOT_CONFIGURED');
 const url=new URL(base);
 if(loopback){
  if(url.protocol!=='http:'||url.hostname!=='127.0.0.1'||!url.port||url.pathname!=='/'||url.username||url.password||url.search||url.hash)throw Error('LOOPBACK_REQUIRED');
 }else if(raw)throw Error('RAW_OSRM_REQUIRES_LOOPBACK');
 const config=loopback?{base:url.origin,token:env.TMS_OSRM_TOKEN,version:env.TMS_ROAD_DATA_VERSION}:configuration(k=>env[k]);
 if(!raw&&(!/^[a-f0-9]{64}$/.test(config.token||'')||!config.version))throw Error('PRIVATE_ROUTING_CONFIGURATION_REQUIRED');
 return config;
}
export async function checkService({env=process.env,loopback=false,raw=false,points=publicSamples,sizes=[points.length],fetcher=fetch}){
 const config=checkConfiguration(env,loopback,raw);
 if(!Array.isArray(points)||points.length<2||points.length>128||points.some(p=>!Array.isArray(p)||p.length!==2||!p.every(Number.isFinite)||Math.abs(p[0])>180||Math.abs(p[1])>85))throw Error('POINTS_INVALID');
 if(!sizes.length||sizes.some(n=>!Number.isInteger(n)||n<2||n>points.length))throw Error('SIZES_INVALID');
 const deadline=AbortSignal.timeout(45000),headers=config.token?{Authorization:'Bearer '+config.token}:{};
 if(!raw){
  // Neither anonymous users nor holders of the token may open other OSRM APIs.
  const sample=points.slice(0,2).map(p=>p.join(',')).join(';');
  const wrongToken=(config.token[0]==='0'?'1':'0')+config.token.slice(1);
  for(const [path,auth] of [['/table/v1/driving/'+sample,{}],['/table/v1/driving/'+sample,{Authorization:'Bearer '+wrongToken}],['/route/v1/driving/'+sample,headers]]){
   const r=await fetcher(config.base+path,{headers:auth,redirect:'error',signal:deadline});
   await r.body?.cancel();if(![401,403,404].includes(r.status))throw Error('ROAD_PROXY_NOT_CLOSED');
  }
 }
 const results=[];
 for(const n of sizes){
  let requests=0;const start=performance.now();
  const measured=await matrix(points.slice(0,n),config,async(url,options)=>{
   requests++;const r=await fetcher(url,options);
   if(!raw&&r.headers.get('x-coco-road-version')!==config.version){await r.body?.cancel();throw Error('ROAD_VERSION_MISMATCH')}
   return r;
  },deadline);
  if(measured.durations.some(row=>row.some(v=>v===null)))throw Error('SAMPLE_ROAD_UNREACHABLE');
  results.push({locations:n,cells:n*n,requests,milliseconds:Math.round(performance.now()-start),unreachable:0});
 }
 return {ok:true,mode:raw?'isolated-osrm':'authenticated-private-proxy',version:config.version||null,results};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try{
  const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);return i<0?undefined:args[i+1]};
  const file=option('--points'),points=file?JSON.parse(await readFile(file,'utf8')):publicSamples;
  const sizes=option('--sizes')?.split(',').map(Number)||[points.length];
  console.log(JSON.stringify(await checkService({loopback:args.includes('--loopback'),raw:args.includes('--raw-osrm'),points,sizes})));
 }catch(error){
  // Fetch errors often embed request URLs, and therefore coordinates. Never print them.
  const allowed=new Set(['ROAD_PROVIDER_NOT_CONFIGURED','LOOPBACK_REQUIRED','RAW_OSRM_REQUIRES_LOOPBACK','PRIVATE_ROUTING_CONFIGURATION_REQUIRED','POINTS_INVALID','SIZES_INVALID','ROAD_PROXY_NOT_CLOSED','ROAD_VERSION_MISMATCH','SAMPLE_ROAD_UNREACHABLE']);
  console.error(JSON.stringify({ok:false,error:allowed.has(error.message)?error.message:'ROAD_SERVICE_CHECK_FAILED'}));process.exitCode=1;
 }
}
