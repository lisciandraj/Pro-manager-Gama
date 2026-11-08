const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const source=name=>fs.readFileSync(path.join(__dirname,'../src/',name),'utf8');
function memoryStorage(entries={}){
 const values=new Map(Object.entries(entries));
 return {get length(){return values.size},key:i=>[...values.keys()][i]??null,getItem:key=>values.get(String(key))??null,setItem:(key,value)=>values.set(String(key),String(value)),removeItem:key=>values.delete(String(key)),clear:()=>values.clear()};
}
function boot({environment='development',configured=true,local={},session={},legacy=false}={}){
 const native={localStorage:memoryStorage(local),sessionStorage:memoryStorage(session)};
 const nodes=new Map(),listeners=new Map(),requests=[],creates=[];
 const state={session:{user:{id:'admin-uid'},access_token:'admin-token'},profile:{id:'admin-uid',role:'administrador',active:true},status:{environment,allowed:true,admin:true},statusHook:null,profileHook:null};
 let authChange,fetchTransport;
 const node=()=>({append(...children){this.children=children},setAttribute(){},remove(){nodes.delete(this.id)}});
 const context={console,URL,Headers,Request,Response,AbortController,setTimeout,clearTimeout,...native,
  location:{href:'https://example.test/coco/'+environment+'/',origin:'https://example.test'},
  document:{readyState:'complete',documentElement:{lang:'fr'},getElementById:id=>nodes.get(id)||null,createElement:node,head:{appendChild(){}},body:{appendChild(el){nodes.set(el.id,el)}}},
  CustomEvent:class{constructor(type,{detail}={}){this.type=type;this.detail=detail}},
  addEventListener(type,fn){if(!listeners.has(type))listeners.set(type,[]);listeners.get(type).push(fn)},
  dispatchEvent(event){for(const fn of listeners.get(event.type)||[])fn(event)},
  async fetch(input,options){
   const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);
   requests.push({url:url.href,method:options?.method||'GET'});
   let data=[];
   if(url.pathname==='/rest/v1/profiles'){if(state.profileHook)await state.profileHook();data=state.profile}
   if(url.pathname==='/rest/v1/rpc/coco_environment_status'){if(state.statusHook)await state.statusHook();data=state.status}
   return Response.json(data);
  }
 };
 context.window=context;
 if(!legacy)context.CocoEnvironmentConfig={environment,version:'1234567890abcdef1234567890abcdef12345678',supabaseUrl:configured?'https://fixtureproject.supabase.co':'',publishableKey:configured?'sb_publishable_fixture':'',productionUrl:'../production/',developmentUrl:'../development/'};
 function query(route,method='GET'){
  const q={};
  for(const name of ['select','eq','abortSignal','maybeSingle','single','order','range','limit'])q[name]=()=>q;
  q.then=(resolve,reject)=>fetchTransport('https://fixtureproject.supabase.co/rest/v1/'+route,{method,headers:{Authorization:'Bearer '+(state.session?.access_token||'')}}).then(async response=>response.ok?{data:await response.json(),error:null}:{data:null,error:await response.json()}).then(resolve,reject);
  return q;
 }
 const client={
  auth:{onAuthStateChange(fn){authChange=fn},getSession:async()=>({data:{session:state.session}}),async signOut(){state.session=null;authChange('SIGNED_OUT',null);return {error:null}}},
  from:table=>query(table),rpc:name=>query('rpc/'+name,'POST')
 };
 context.supabase={createClient(url,key,options){creates.push({url,key,options});fetchTransport=options?.global?.fetch||context.fetch;return client}};
 vm.createContext(context);vm.runInContext(source('app/environment.js'),context);
 return {context,native,nodes,state,requests,creates,load(){vm.runInContext(source('data/supabase.js'),context);return context.GamaCloudReady},auth(event,next=state.session){state.session=next;authChange(event,next)},fetch:(input,options)=>fetchTransport(input,options)};
}

test('production local and session storage never read or clear legacy development drafts',()=>{
 const x=boot({environment:'production',local:{gama_session_v1:'legacy login',draft:'development draft','coco:development:draft':'namespaced development'},session:{pending:'development pending'}});
 const {localStorage,sessionStorage}=x.context;
 assert.equal(localStorage.getItem('gama_session_v1'),null);
 assert.equal(localStorage.getItem('draft'),null);
 assert.equal(sessionStorage.getItem('pending'),null);
 localStorage.setItem('draft','production draft');sessionStorage.setItem('pending','production pending');
 assert.equal(x.native.localStorage.getItem('coco:production:draft'),'production draft');
 assert.equal(x.native.sessionStorage.getItem('coco:production:pending'),'production pending');
 assert.deepEqual(Object.keys(localStorage),['draft']);
 localStorage.clear();sessionStorage.clear();
 assert.equal(x.native.localStorage.getItem('draft'),'development draft');
 assert.equal(x.native.localStorage.getItem('coco:development:draft'),'namespaced development');
 assert.equal(x.native.sessionStorage.getItem('pending'),'development pending');
 assert.equal(x.native.localStorage.getItem('coco:production:draft'),null);
});

test('development imports existing browser records without copying or overwriting production records',()=>{
 const x=boot({local:{draft:'historical draft','coco:development:kept':'existing development','coco:production:invoice':'production invoice'},session:{draft:'historical session'}});
 assert.equal(x.context.localStorage.getItem('draft'),'historical draft');
 assert.equal(x.context.localStorage.getItem('kept'),'existing development');
 assert.equal(x.context.localStorage.getItem('invoice'),null);
 assert.equal(x.context.sessionStorage.getItem('draft'),'historical session');
 assert.equal(x.native.localStorage.getItem('draft'),'historical draft');
 assert.equal(x.native.localStorage.getItem('coco:production:invoice'),'production invoice');
});

test('unconfigured production fails closed despite a legacy public key override',async()=>{
 const x=boot({environment:'production',configured:false});x.context.GAMA_SUPABASE_ANON_KEY='legacy-override';
 await x.load();
 assert.equal(x.context.GamaCloud.url,'');
 assert.equal(x.creates.length,0);assert.equal(x.requests.length,0);
 assert.ok(x.nodes.has('cocoEnvironmentError'));
 await assert.rejects(x.context.GamaCloud.db(),/not configured/);
 assert.equal(x.context.CocoEnvironment.backend.supabaseUrl,'');
 assert.equal(x.context.CocoEnvironment.backend.publishableKey,'');
});

test('a server environment mismatch never unlocks business requests',async()=>{
 const x=boot({environment:'production'});x.state.status.environment='development';await x.load();
 const profile=await x.context.GamaCloud.getProfile();
 assert.equal(profile.error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.context.GamaCloud.verifiedProfile,null);
 const business=await (await x.context.GamaCloud.db()).from('products');
 assert.equal(business.error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.requests.some(r=>r.url.endsWith('/products')),false);
 assert.ok(x.nodes.has('cocoEnvironmentError'));
});

test('nonadministrators in development cannot make business requests or reveal the development menu',async()=>{
 const x=boot();x.state.profile.role='comercial';x.state.status={environment:'development',allowed:false,admin:false};await x.load();
 assert.equal((await x.context.GamaCloud.getProfile()).error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 assert.equal((await (await x.context.GamaCloud.db()).rpc('business_mutation')).error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.requests.some(r=>r.url.includes('business_mutation')),false);
});

test('development requires the verified profile and the server administrator decision to agree',async()=>{
 const x=boot();x.state.profile.role='comercial';await x.load();
 assert.equal((await x.context.GamaCloud.getProfile()).error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error.code,'ENVIRONMENT_ACCESS_DENIED');
});

test('production admits an active authorized staff profile without granting development access',async()=>{
 const x=boot({environment:'production'});x.state.profile.role='comercial';x.state.status.admin=false;await x.load();
 assert.equal((await x.context.GamaCloud.getProfile()).error,null);
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error,null);
 const response=await x.fetch(new URL('https://fixtureproject.supabase.co/rest/v1/products'),{headers:{Authorization:'Bearer admin-token'}});
 assert.equal(response.status,200);
});

test('a matching active administrator and server marker unlock only the verified session token',async()=>{
 const x=boot();let release,ready=false;
 x.state.profileHook=()=>new Promise(resolve=>release=resolve);
 const initialization=x.load().then(()=>{ready=true});
 await new Promise(setImmediate);
 assert.equal(ready,false,'restored-session business modules wait for profile verification');
 const early=await (await x.context.GamaCloud.db()).from('products');assert.equal(early.error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.requests.some(r=>r.url.endsWith('/products')),false);
 release();await initialization;x.state.profileHook=null;
 assert.equal(ready,true);
 assert.equal(x.context.GamaCloud.verifiedProfile.id,'admin-uid');
 assert.equal(x.context.CocoEnvironment.canDevelop(),true);
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error,null);
 const wrong=await x.fetch('https://fixtureproject.supabase.co/rest/v1/products',{headers:{Authorization:'Bearer different-token'}});
 assert.equal(wrong.status,403);
 assert.equal(x.requests.filter(r=>r.url.endsWith('/products')).length,1);
 x.auth('TOKEN_REFRESHED',{user:{id:'admin-uid'},access_token:'refreshed-token'});
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error,null);
});

test('a profile read finishing after a session switch cannot authorize the new session',async()=>{
 const x=boot();await x.load();let release;
 x.state.statusHook=()=>new Promise(resolve=>release=resolve);
 const pending=x.context.GamaCloud.getProfile();await new Promise(setImmediate);
 x.state.session={user:{id:'other-uid'},access_token:'other-token'};release();
 assert.equal((await pending).error.code,'AUTH_CHANGED');
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error.code,'ENVIRONMENT_ACCESS_DENIED');
});

test('server access revocation and logout immediately remove verified environment access',async()=>{
 const x=boot();await x.load();await x.context.GamaCloud.getProfile();
 let notifications=0;x.context.addEventListener('coco:environment-access-change',()=>notifications++);
 x.state.status.allowed=false;
 assert.equal((await x.context.GamaCloud.getProfile()).error.code,'ENVIRONMENT_ACCESS_DENIED');
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 x.state.status.allowed=true;await x.context.GamaCloud.getProfile();
 await x.context.GamaCloud.signOut();
 assert.equal(x.context.GamaCloud.verifiedProfile,null);
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 assert.ok(notifications>=2,'the menu is notified of verification and revocation changes');
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error.code,'ENVIRONMENT_ACCESS_DENIED');
});

test('a refreshed token for a different account cannot inherit verified administrator access',async()=>{
 const x=boot();await x.load();await x.context.GamaCloud.getProfile();
 x.auth('TOKEN_REFRESHED',{user:{id:'other-uid'},access_token:'other-token'});
 assert.equal(x.context.CocoEnvironment.canDevelop(),false);
 assert.equal((await (await x.context.GamaCloud.db()).from('products')).error.code,'ENVIRONMENT_ACCESS_DENIED');
});
