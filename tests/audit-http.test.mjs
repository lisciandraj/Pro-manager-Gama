import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readJsonBody} from '../supabase/functions/_shared/http.mjs';
import {retiredSri} from '../supabase/functions/_shared/retired-sri.mjs';
import {createHandler} from '../supabase/functions/gama-admin-users/handler.mjs';
const env=k=>({SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'public-test',SUPABASE_SERVICE_ROLE_KEY:'private-test'})[k];
const actor='00000000-0000-4000-8000-000000000001',created='00000000-0000-4000-8000-000000000002';
const input={email:'staff@example.invalid',password:'strong-fixture-password',full_name:'Staff',role:'comercial'};
const req=(body=input,headers={})=>new Request('https://edge.invalid',{method:'POST',headers:{Authorization:'Bearer caller',Origin:'https://lisciandraj.github.io',...headers},body:JSON.stringify(body)});
test('streaming reader rejects oversized chunks without Content-Length and cancels the stream',async()=>{
 let cancelled=false;const stream=new ReadableStream({start(c){c.enqueue(new Uint8Array(4000))},cancel(){cancelled=true}});
 const r=new Request('https://edge.invalid',{method:'POST',duplex:'half',body:stream});
 await assert.rejects(readJsonBody(r,1000),e=>e.status===413);assert.equal(cancelled,true);
});
test('reader rejects invalid UTF-8 and non-object payloads but accepts bounded JSON',async()=>{
 for(const body of ['[1]','null','{"x":',new Uint8Array([0xff])])await assert.rejects(readJsonBody(new Request('https://edge.invalid',{method:'POST',body}),1000),e=>e.status===400);
 assert.deepEqual(await readJsonBody(req({x:'é'}),1000),{x:'é'});
});
test('retired fiscal endpoints never read submitted certificates or call a provider',async()=>{
 let read=false;const r=await retiredSri({method:'POST',headers:new Headers(),get body(){read=true;throw Error('must not read')}});
 assert.equal(r.status,410);assert.equal((await r.json()).replacement,'gama-sri');assert.equal(read,false);
});
function harness(options={}){
 const calls=[];let allowedCalls=0;const handler=createHandler({env,fetch:async(url,init)=>{
  calls.push({url,init});assert.equal(init.redirect,'error');
  if(url.endsWith('/auth/v1/user'))return Response.json(options.noAuth?{}:{id:actor});
  if(url.includes('profiles?select='))return Response.json([{role:options.role||'administrador',active:true}]);
  if(url.includes('gama_identity_admin_allowed'))return Response.json(++allowedCalls===2?options.allowedAfter!==false:options.allowed!==false);
  if(url.includes('/auth/v1/admin/users')&&init.method==='POST')return Response.json({id:created});
  if(url.includes('/profiles?on_conflict'))return Response.json({}, {status:options.profileFailure?409:200});
  return Response.json({});
 }});return {calls,handler};
}
test('legacy account creation requires the users module/action, before any service write',async()=>{
 for(const options of [{noAuth:true},{role:'comercial'},{allowed:false}]){
  const h=harness(options),r=await h.handler(req());assert.equal(r.status,options.noAuth?401:403);
  assert(!h.calls.some(c=>c.url.includes('/auth/v1/admin/users')));
 }
 const h=harness();assert.equal((await h.handler(req(input,{Origin:'https://evil.invalid'}))).status,403);assert.equal(h.calls.length,0);
});
test('account creation preserves role validation and rolls back a lost permission or failed profile',async()=>{
 for(const options of [{allowedAfter:false},{profileFailure:true}]){
  const h=harness(options);assert.equal((await h.handler(req())).status,options.profileFailure?409:403);
  assert(h.calls.some(c=>c.init.method==='DELETE'&&c.url.endsWith(created)));
 }
 const h=harness();assert.equal((await h.handler(req({...input,role:'cliente'}))).status,400);
 assert.equal((await h.handler(req({...input,password:'short'}))).status,400);
 assert.equal((await h.handler(req())).status,201);
 const body=JSON.parse(h.calls.find(c=>c.url.includes('/admin/users')&&c.init.method==='POST').init.body);
 assert.deepEqual(body.user_metadata,{full_name:'Staff'});
});
