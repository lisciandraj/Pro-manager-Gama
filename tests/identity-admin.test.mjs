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
 assert.equal((await handler(request({action:'invite',email:'customer@example.invalid',name:'Customer',role:'cliente'}))).status,400);
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
test('B2B invitation preflights the company and binds a portal-only customer using the caller JWT',async()=>{
 const calls=[],customer='00000000-0000-4000-8000-000000000003';
 const handler=createHandler({env,fetch:async(url,options)=>{calls.push({url,options});const body=options.body?JSON.parse(options.body):{};return Response.json(url.endsWith('/auth/v1/user')?{id:actor}:url.includes('/profiles?select=')?[{id:actor,role:'administrador',active:true}]:url.includes('/rpc/gama_identity_admin_allowed')?true:url.includes('/rpc/gama_b2b_admin')?(body.p_action==='invitation_context'?{allowed:true}:{saved:true}):url.includes('/auth/v1/invite?')?{id:invited}:[])}});
 const result=await handler(request({action:'invite_b2b',customer_id:customer,email:'client@example.invalid',name:'Client',role:'administrador'}));assert.equal(result.status,200);assert.equal((await result.json()).portal_access,true);
 const invite=calls.findIndex(c=>c.url.includes('/auth/v1/invite?'));assert.ok(calls.findIndex(c=>c.url.includes('/rpc/gama_b2b_admin'))<invite);
 assert.equal(JSON.parse(calls[invite].options.body).data.b2b_portal,true);
 assert.deepEqual(JSON.parse(calls.find(c=>c.options.method==='PATCH').options.body),{role:'cliente',full_name:'Client',active:false},'no ERP role or activation can be injected');
 const linked=calls.filter(c=>c.url.includes('/rpc/gama_b2b_admin')).at(-1);assert.equal(linked.options.headers.Authorization,'Bearer session');assert.deepEqual(JSON.parse(linked.options.body),{p_action:'member',p_data:{customer_id:customer,profile_id:invited,active:true,expected_customer_id:null}});
});
test('B2B invitation sends nothing before scope approval and reports a failed binding without resending',async()=>{
 const customer='00000000-0000-4000-8000-000000000003';let allowed=false,emails=0;
 const handler=createHandler({env,fetch:async(url,options)=>{const body=options.body?JSON.parse(options.body):{};if(url.includes('/auth/v1/invite?'))emails++;return Response.json(url.endsWith('/auth/v1/user')?{id:actor}:url.includes('/profiles?select=')?[{id:actor,role:'administrador',active:true}]:url.includes('/rpc/gama_identity_admin_allowed')?true:url.includes('/rpc/gama_b2b_admin')?(body.p_action==='invitation_context'?{allowed}:null):url.includes('/auth/v1/invite?')?{id:invited}:[])}});
 const body={action:'invite_b2b',customer_id:customer,email:'client@example.invalid',name:'Client'};
 assert.equal((await handler(request(body))).status,403);assert.equal(emails,0);allowed=true;const r=await handler(request(body));assert.equal(r.status,409);assert.equal((await r.json()).error,'INVITED_REVIEW_B2B');assert.equal(emails,1);
});
