import {test} from 'node:test';import assert from 'node:assert/strict';
import {configuration,matrix,createHandler} from '../supabase/functions/tms-routing/handler.mjs';
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
const config={base:'https://roads.example.invalid',version:'test'};
function provider(url){
 const u=new URL(url),coords=u.pathname.split('/').at(-1).split(';').map(p=>p.split(',').map(Number)),a=u.searchParams.get('sources').split(';').map(Number),b=u.searchParams.get('destinations').split(';').map(Number);
 return json({code:'Ok',sources:a.map(()=>({distance:0})),destinations:b.map(()=>({distance:0})),distances:a.map(i=>b.map(j=>i===j?0:Math.abs(coords[i][1]-coords[j][1])*10000+10)),durations:a.map(i=>b.map(j=>i===j?0:Math.abs(coords[i][1]-coords[j][1])*1000+20+(coords[j][1]>coords[i][1]?20:0)))});
}
test('only an explicitly configured HTTPS non-demo OSRM endpoint is allowed',()=>{
 assert.equal(configuration(()=>undefined),null);
 for(const url of ['http://roads.example.invalid','https://routing.openstreetmap.de/routed-car','https://router.project-osrm.org','https://router.project-osrm.org.','https://localhost','https://127.0.0.1','https://169.254.169.254','https://user:pass@roads.example.invalid','https://roads.example.invalid/?token=secret'])assert.throws(()=>configuration(k=>k==='TMS_OSRM_URL'?url:undefined));
 assert.equal(configuration(k=>k==='TMS_OSRM_URL'?config.base:undefined).base,config.base);
});
for(const n of [20,50,100])test('OSRM rectangular chunks preserve '+n+' directional locations and units',async()=>{
 let calls=0;const pts=Array.from({length:n},(_,i)=>[-78.5,-.3+i*.001]);
 const out=await matrix(pts,config,async(url,options)=>{calls++;assert.equal(options.redirect,'error');assert.equal(options.credentials,'omit');assert.ok(url.startsWith(config.base+'/table/'));assert.ok(!url.includes('customer'));return provider(url)},new AbortController().signal);
 assert.equal(calls,Math.ceil(n/40)**2);assert.equal(out.distances.length,n);assert.equal(out.distances[0][0],0);assert.equal(out.durations[n-1][n-1],0);assert.ok(out.durations[1][0]!==out.durations[0][1]);assert.ok(out.distances[0][n-1]<2);
});
test('null road pairs remain unreachable; malformed, fallback and distant snap responses are rejected',async()=>{
 const pts=[[-78.5,-.2],[-78.51,-.21]];
 const valid=await provider(config.base+'/table/v1/driving/-78.5,-0.2;-78.51,-0.21?sources=0;1&destinations=0;1').json();
 const body=structuredClone(valid);body.distances[0][1]=body.durations[0][1]=null;const out=await matrix(pts,config,async()=>json(body));assert.equal(out.distances[0][1],null);
 for(const edit of [v=>{v.durations[0][1]=-1},v=>{v.distances[0][0]=null},v=>{v.distances=[]},v=>{v.sources[0].distance=501},v=>{v.fallback_speed_cells=[[0,1]]}]){const bad=structuredClone(valid);edit(bad);await assert.rejects(matrix(pts,config,async()=>json(bad)),/ROAD_RESPONSE_INVALID/)}
 await assert.rejects(matrix(pts,config,async()=>json({},429)),/ROAD_PROVIDER_UNAVAILABLE/);
});
const environment=k=>({SUPABASE_URL:'https://project.example.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'server-secret',TMS_OSRM_URL:config.base})[k];
const request=()=>new Request('https://edge.example.invalid',{method:'POST',headers:{Authorization:'Bearer user-token',Origin:'https://lisciandraj.github.io'},body:JSON.stringify({day:'2026-10-30'})});
test('authorization precedes elevated requests, routing, and configuration disclosure',async()=>{
 const calls=[];const h=createHandler({env:environment,fetch:async(url,opt)=>{calls.push({url,opt});return json({message:'TMS_ACCESS_DENIED'},403)}});
 const res=await h(request());assert.equal(res.status,403);assert.equal(calls.length,1);assert.equal(calls[0].opt.headers.Authorization,'Bearer user-token');assert.ok(!JSON.stringify(calls).includes('server-secret'));
});
test('a cached matrix never contacts the provider; no provider is a clear configuration error',async()=>{
 const calls=[];const h=createHandler({env:environment,fetch:async(url,opt)=>{calls.push(url);return json(JSON.parse(opt.body).p_action==='claim'?{cached:true}:{mode:'road'})}});
 const res=await h(request());assert.equal(res.status,200);assert.equal((await res.json()).cached,true);assert.equal(calls.length,2);
 const missing=createHandler({env:k=>k==='TMS_OSRM_URL'?undefined:environment(k),fetch:async()=>json({mode:'estimated'})});assert.equal((await (await missing(request())).json()).error,'ROAD_PROVIDER_NOT_CONFIGURED');
});
test('provider failure is sanitized, commits a failed lease and never publishes partial distances',async()=>{
 const calls=[],lease={day:'2026-10-30',lease:'lease-id',actor_id:'actor-id',points:[[-78.5,-.2],[-78.51,-.21]]};
 const h=createHandler({env:environment,fetch:async(url,opt)=>{
  calls.push({url,opt});if(url.startsWith(config.base))throw Error('private customer coords and secret');
  const b=JSON.parse(opt.body);if(b.p_action==='status')return json({mode:'estimated'});if(b.p_action==='claim')return json(lease);return json({stored:false});
 }});
 const res=await h(request());assert.equal(res.status,503);assert.deepEqual(await res.json(),{error:'ROAD_PROVIDER_UNAVAILABLE'});
 const saved=JSON.parse(calls.at(-1).opt.body);assert.equal(saved.p_data.error,'ROAD_PROVIDER_UNAVAILABLE');assert.ok(!saved.p_data.distances);assert.equal(calls.at(-1).opt.headers.Authorization,'Bearer server-secret');
});
test('edge accepts only POST from the ERP origin',async()=>{
 const h=createHandler({env:environment,fetch:()=>{throw Error('unexpected')}});
 assert.equal((await h(new Request('https://edge.example.invalid',{headers:{Origin:'https://evil.example.invalid'}}))).status,403);
 assert.equal((await h(new Request('https://edge.example.invalid'))).status,405);
});
