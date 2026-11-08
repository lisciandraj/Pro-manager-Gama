const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const source=file=>fs.readFileSync(path.join(__dirname,'../src/',file),'utf8');
const tick=()=>new Promise(setImmediate);
function deferred(){let resolve;const promise=new Promise(done=>resolve=done);return {promise,resolve}}
function storage(){const data=new Map();return {get length(){return data.size},key:i=>[...data.keys()][i]??null,getItem:key=>data.get(key)??null,setItem:(key,value)=>data.set(key,String(value)),removeItem:key=>data.delete(key)}}

// GoTrue, profile and environment responses are local doubles. The real
// environment transport and identity UI execute unchanged in this context.
async function boot(flow){
 const requests=[],dialogs=[],listeners=new Map(),nodes=new Map();
 const state={aal:'aal1',factorVerified:flow==='challenge',session:{user:{id:'admin-uid'},access_token:'aal1-fixture'},profile:{id:'admin-uid',role:'administrador',active:true},pause:null,profileError:null,marker:'development',challengeError:null,reloads:0,activations:0,closed:0};
 let authListener,transport;
 function authorized(){return state.session&&state.profile.active&&state.profile.role==='administrador'&&(state.aal==='aal2'||!state.factorVerified)}
 const context={console,URL,Headers,Request,Response,AbortController,setTimeout,clearTimeout,Element:class{},localStorage:storage(),sessionStorage:storage(),
  location:{href:'https://example.test/coco/development/',origin:'https://example.test',reload(){state.reloads++}},
  document:{readyState:'complete',documentElement:{lang:'fr'},getElementById:id=>nodes.get(id)||null,createElement:()=>({append(){},setAttribute(){},remove(){nodes.delete(this.id)}}),head:{appendChild(){}},body:{appendChild(node){nodes.set(node.id,node)}}},
  CustomEvent:class{constructor(type,{detail}={}){this.type=type;this.detail=detail}},
  addEventListener(type,fn){if(!listeners.has(type))listeners.set(type,[]);listeners.get(type).push(fn)},dispatchEvent(event){for(const fn of listeners.get(event.type)||[])fn(event)},
  FormData:class{constructor(form){this.entries=Object.entries(form.fields)}get(key){return this.entries.find(([name])=>name===key)?.[1]}[Symbol.iterator](){return this.entries[Symbol.iterator]()}},
  async fetch(input,options){
   const url=new URL(typeof input==='string'?input:input.url);requests.push(url.pathname);
   if(url.pathname.startsWith('/auth/v1/'))return Response.json({});
   if(url.pathname==='/rest/v1/profiles'){
    if(!authorized())return Response.json({code:'42501',message:'DEVELOPMENT_ADMIN_REQUIRED'},{status:403});
    if(state.pause)await state.pause.promise;
    if(state.profileError)return Response.json(state.profileError,{status:503});
    return Response.json(state.profile);
   }
   if(url.pathname==='/rest/v1/rpc/coco_environment_status')return Response.json({environment:state.marker,allowed:!!authorized(),admin:!!authorized()});
   if(url.pathname==='/rest/v1/rpc/coco_identity_login_status')return Response.json({authorized:true,administrator:true,policy_active:false,required:false,verified_factor:state.factorVerified});
   if(url.pathname==='/rest/v1/rpc/coco_security_enrollment'){
    const action=JSON.parse(options.body).p_action;
    if(action==='activate'){assert.equal(state.aal,'aal2');assert.equal(authorized(),true);state.activations++}
    return Response.json({enforced:state.activations>0,administrator:true,verified_factor:state.factorVerified});
   }
   throw Error('Unexpected fixture request '+url.pathname);
  }
 };
 context.window=context;context.CocoEnvironmentConfig={environment:'development',version:'1234567890abcdef1234567890abcdef12345678',supabaseUrl:'https://fixtureproject.supabase.co',publishableKey:'sb_publishable_fixture'};
 function query(route,data){
  const q={};for(const key of ['select','eq','abortSignal','maybeSingle'])q[key]=()=>q;
  q.then=(resolve,reject)=>transport('https://fixtureproject.supabase.co/rest/v1/'+route,{method:data?'POST':'GET',headers:{Authorization:'Bearer '+(state.session?.access_token||'')},...(data?{body:JSON.stringify(data)}:{})}).then(async response=>response.ok?{data:await response.json(),error:null}:{data:null,error:await response.json()}).then(resolve,reject);
  return q;
 }
 const client={from:name=>query(name),rpc:(name,data={})=>query('rpc/'+name,data),auth:{
  onAuthStateChange(fn){authListener=fn},getSession:async()=>({data:{session:state.session}}),async signOut(){state.session=null;authListener('SIGNED_OUT',null);return {error:null}},
  mfa:{
   getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:state.aal,nextLevel:state.factorVerified?'aal2':'aal1'}}),
   listFactors:async()=>({data:{totp:state.factorVerified?[{id:'fixture-factor',status:'verified'}]:[]}}),
   async enroll(){await transport('https://fixtureproject.supabase.co/auth/v1/factors',{method:'POST'});return {data:{id:'fixture-factor',totp:{qr_code:'data:image/svg+xml,fixture'}}}},
   async challengeAndVerify(){
    const response=await transport('https://fixtureproject.supabase.co/auth/v1/factors/fixture-factor/verify',{method:'POST'});assert.equal(response.status,200);
    if(state.challengeError)return {error:state.challengeError};
    state.aal='aal2';state.factorVerified=true;state.session={user:{id:'admin-uid'},access_token:'aal2-fixture'};authListener('MFA_CHALLENGE_VERIFIED',state.session);return {data:{}};
   }
  }
 }};
 context.supabase={createClient(_url,_key,options){transport=options.global.fetch;return client}};
 context.ArcUI={field:()=>'',esc:String,table:()=>'',dialog(options){
  const elements=new Map(),dialog={options,dataset:{},isConnected:true,append(){},addEventListener(){},querySelectorAll(){return []},close(){state.closed++},querySelector(selector){
   if(!elements.has(selector))elements.set(selector,selector==='form'?{fields:{factor:'fixture-factor',code:'123456'}}:{});return elements.get(selector);
  }};dialogs.push(dialog);return dialog;
 }};
 context.ArcData={rpc:async(name,data)=>{const response=await client.rpc(name,data);if(response.error)throw Object.assign(Error(response.error.message),response.error);return response.data}};
 context.ArcErrors={message:error=>error.message};
 vm.createContext(context);vm.runInContext(source('app/environment.js'),context);vm.runInContext(source('data/supabase.js'),context);await context.GamaCloudReady;
 vm.runInContext(source('features/access/identity.js'),context);
 let flowPromise,form;
 if(flow==='challenge'){
  flowPromise=context.ArchitectIdentity.ensureMFA();await tick();form=dialogs[0];
 }else{
  await context.ArchitectIdentity.security();const security=dialogs[0];await security.querySelector('[data-enroll]').onclick({target:{}});form=dialogs[1];
 }
 assert.ok(form,'MFA form remains reachable before verification');
 return {context,state,requests,dialogs,form,flowPromise,save:()=>form.options.onSave(form)};
}

for(const flow of ['challenge','enrollment']){
 test(flow+': protected activation waits for the newly verified profile and environment',async()=>{
  const x=await boot(flow);x.state.pause=deferred();
  const pending=x.save();await tick();
  assert.ok(x.requests.includes('/auth/v1/factors/fixture-factor/verify'),'GoTrue verification is permitted before the business gate');
  assert.equal(x.state.aal,'aal2');assert.equal(x.state.activations,0);
  assert.equal(x.context.GamaCloud.verifiedProfile,null);
  x.state.pause.resolve();await pending;await x.flowPromise;
  assert.equal(x.state.activations,1);
  assert.equal(x.context.GamaCloud.verifiedProfile.id,'admin-uid');
  const paths=x.requests.slice(x.requests.lastIndexOf('/auth/v1/factors/fixture-factor/verify'));
  assert.deepEqual(paths,['/auth/v1/factors/fixture-factor/verify','/rest/v1/profiles','/rest/v1/rpc/coco_environment_status','/rest/v1/rpc/coco_security_enrollment']);
  if(flow==='enrollment')assert.equal(x.state.reloads,1);
  const count=x.requests.length;await x.context.ArchitectIdentity.ensureMFA();assert.deepEqual(x.requests.slice(count),['/rest/v1/rpc/coco_identity_login_status'],'an existing AAL2 session reads only its policy status');
 });

 test(flow+': a refused environment marker cannot activate enrollment',async()=>{
  const x=await boot(flow);x.state.marker='production';
  await assert.rejects(x.save(),error=>error.code==='ENVIRONMENT_ACCESS_DENIED');
  assert.equal(x.state.activations,0);assert.equal(x.context.GamaCloud.verifiedProfile,null);
 });

 test(flow+': an invalid MFA challenge performs no subsequent profile or enrollment request',async()=>{
  const x=await boot(flow);const before=x.requests.filter(route=>route==='/rest/v1/profiles').length;
  x.state.challengeError={code:'mfa_verification_failed',message:'Invalid fixture code'};
  await assert.rejects(x.save(),error=>error.code==='mfa_verification_failed');
  assert.equal(x.requests.filter(route=>route==='/rest/v1/profiles').length,before);assert.equal(x.state.activations,0);
 });

 test(flow+': an unavailable post-MFA profile cannot activate enrollment',async()=>{
  const x=await boot(flow);const before=x.state.activations;
  x.state.profileError={code:'PROFILE_UNAVAILABLE',message:'Profile read unavailable'};
  await assert.rejects(x.save(),error=>error.code==='PROFILE_UNAVAILABLE');
  assert.equal(x.state.activations,before);assert.equal(x.context.GamaCloud.verifiedProfile,null);
  assert.equal(x.requests.filter(route=>route==='/rest/v1/rpc/coco_security_enrollment').length,flow==='enrollment'?1:0);
 });

 test(flow+': a session changed during profile verification cannot activate enrollment',async()=>{
  const x=await boot(flow);x.state.pause=deferred();
  const pending=x.save();await tick();x.state.session={user:{id:'another-uid'},access_token:'another-fixture'};
  x.state.pause.resolve();await assert.rejects(pending,error=>error.code==='AUTH_CHANGED');
  assert.equal(x.state.activations,0);assert.equal(x.context.GamaCloud.verifiedProfile,null);
 });
}
