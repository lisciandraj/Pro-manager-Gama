import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/architect-user-admin/handler.mjs';
const actor='00000000-0000-4000-8000-000000000001',invited='00000000-0000-4000-8000-000000000002';
const request=(body,headers={})=>new Request('https://example.invalid/invite',{method:'POST',headers:{authorization:'Bearer session',origin:'https://lisciandraj.github.io',...headers},body:JSON.stringify(body)});
const env=k=>({SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'anon-test',SUPABASE_SERVICE_ROLE_KEY:'service-test'})[k];
test('Invitation verifies the caller and keeps the invited profile inactive',async()=>{
 const calls=[];const handler=createHandler({env,fetch:async(url,options)=>{calls.push({url,options});const data=url.endsWith('/auth/v1/user')?{id:actor}:url.includes('/profiles?select=')?[{id:actor,role:'administrador',active:true}]:url.includes('/rpc/gama_identity_admin_allowed')?true:url.includes('/auth/v1/invite?')?{id:invited}:[];return Response.json(data)}});
 const r=await handler(request({action:'invite',email:'staff@example.invalid',name:'Staff',role:'comercial'}));assert.equal(r.status,200);assert.equal((await r.json()).active,false);
 const invite=calls.find(c=>c.url.includes('/auth/v1/invite?'));assert.equal(invite.options.headers.Authorization,'Bearer service-test');assert.equal(JSON.parse(invite.options.body).email,'staff@example.invalid');
 const patch=calls.find(c=>c.options.method==='PATCH');assert.deepEqual(JSON.parse(patch.options.body),{role:'comercial',full_name:'Staff',active:false});
});
// «Responsable RH» es un perfil de base: se invita como los demás; un rol inventado no.
test('Invitation accepts the HR base role and refuses unknown roles',async()=>{
 const calls=[];const handler=createHandler({env,fetch:async(url,options)=>{calls.push({url,options});const data=url.endsWith('/auth/v1/user')?{id:actor}:url.includes('/profiles?select=')?[{id:actor,role:'administrador',active:true}]:url.includes('/rpc/gama_identity_admin_allowed')?true:url.includes('/auth/v1/invite?')?{id:invited}:[];return Response.json(data)}});
 assert.equal((await handler(request({action:'invite',email:'rh@example.invalid',name:'RH',role:'rrhh'}))).status,200);
 assert.deepEqual(JSON.parse(calls.find(c=>c.options.method==='PATCH').options.body),{role:'rrhh',full_name:'RH',active:false});
 assert.equal((await handler(request({action:'invite',email:'x@example.invalid',name:'X',role:'hr'}))).status,400);
});
test('Invitation never calls the admin endpoint for a forbidden origin, missing session or non-admin',async()=>{
 let calls=0;const handler=createHandler({env,fetch:async url=>{calls++;assert.ok(!url.includes('/auth/v1/invite'));return Response.json(url.endsWith('/auth/v1/user')?{id:actor}:[{id:actor,role:'comercial',active:true}])}});
 assert.equal((await handler(request({action:'invite'},{origin:'https://attacker.invalid'}))).status,403);assert.equal(calls,0);
 assert.equal((await handler(request({action:'invite'},{authorization:''}))).status,401);assert.equal(calls,0);
 assert.equal((await handler(request({action:'invite',email:'staff@example.invalid',name:'Staff',role:'administrador'}))).status,403);assert.equal(calls,2);
});

test('Invitation is blocked by module/action restrictions before sending an email',async()=>{
 const calls=[];const handler=createHandler({env,fetch:async url=>{calls.push(url);return Response.json(url.endsWith('/auth/v1/user')?{id:actor}:url.includes('/profiles?select=')?[{id:actor,role:'administrador',active:true}]:false)}});
 const response=await handler(request({action:'invite',email:'staff@example.invalid',name:'Staff',role:'comercial'}));assert.equal(response.status,403);assert.ok(calls.every(url=>!url.includes('/auth/v1/invite')));
});

test('Invitation carries the personalised subject and message to the email template',async()=>{
 const calls=[];const handler=createHandler({env,fetch:async(url,options)=>{calls.push({url,options});const data=url.endsWith('/auth/v1/user')?{id:actor}:url.includes('/profiles?select=')?[{id:actor,role:'administrador',active:true}]:url.includes('/rpc/gama_identity_admin_allowed')?true:url.includes('/auth/v1/invite?')?{id:invited}:[];return Response.json(data)}});
 const r=await handler(request({action:'invite',email:'staff@example.invalid',name:'Staff',role:'comercial',company:'Ferretería Andina',subject:' Tu acceso a Ferretería Andina ',message:'Hola Staff:\n\nBienvenido.\u0007'}));assert.equal(r.status,200);
 const body=JSON.parse(calls.find(c=>c.url.includes('/auth/v1/invite?')).options.body);
 assert.deepEqual(body.data,{full_name:'Staff',invite_subject:'Tu acceso a Ferretería Andina',invite_message:'Hola Staff:\n\nBienvenido.',company_name:'Ferretería Andina'});
 const empty=await handler(request({action:'invite',email:'staff@example.invalid',name:'Staff',role:'comercial',subject:'  ',message:'x'}));assert.equal(empty.status,400);
 assert.equal(calls.filter(c=>c.url.includes('/auth/v1/invite?')).length,1,'an empty subject never sends');
});
