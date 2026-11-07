/* Environment identity is supplied by the release packager, never by a URL parameter. */
(function(){
'use strict';
const supplied=window.CocoEnvironmentConfig;
const enforced=!!supplied;
const name=supplied?.environment||'development';
if(!['development','production'].includes(name))throw Error('INVALID_ENVIRONMENT');
const defaults={supabaseUrl:'https://mknsaibrewksgomuslev.supabase.co',publishableKey:'sb_publishable_4l0vZw61u5EbLkzmrqrf6Q_phOL1Be9'};
const backend=enforced?{supabaseUrl:supplied.supabaseUrl||'',publishableKey:supplied.publishableKey||''}:defaults;
if(backend.supabaseUrl&&!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(backend.supabaseUrl))throw Error('INVALID_ENVIRONMENT_BACKEND');
const prefix='coco:'+name+':';
// Historical local preferences and drafts belong to development. Copy once;
// never delete the originals or make production fall back to their values.
function partitionStorage(kind){
 const native=window[kind];if(!native)return;
 if(name==='development'&&!native.getItem(prefix+'__imported_v1')){
  const entries=[];
  for(let i=0;i<native.length;i++){const key=native.key(i);if(key&&!key.startsWith('coco:development:')&&!key.startsWith('coco:production:'))entries.push([key,native.getItem(key)]);}
  for(const [key,value] of entries)if(native.getItem(prefix+key)===null)native.setItem(prefix+key,value);
  native.setItem(prefix+'__imported_v1','1');
 }
 const keys=()=>{const list=[];for(let i=0;i<native.length;i++){const key=native.key(i);if(key?.startsWith(prefix)&&key!==prefix+'__imported_v1')list.push(key.slice(prefix.length));}return list;};
 const api={getItem:key=>native.getItem(prefix+key),setItem:(key,value)=>native.setItem(prefix+key,String(value)),removeItem:key=>native.removeItem(prefix+key),clear:()=>keys().forEach(key=>native.removeItem(prefix+key)),key:i=>keys()[i]??null};
 Object.defineProperty(api,'length',{get:()=>keys().length,configurable:true});
 const facade=new Proxy(api,{get:(target,key)=>typeof key==='symbol'||key in target?target[key]:api.getItem(key),set:(_,key,value)=>{api.setItem(key,value);return true},deleteProperty:(_,key)=>{api.removeItem(key);return true},ownKeys:keys,getOwnPropertyDescriptor:(_,key)=>keys().includes(key)?{configurable:true,enumerable:true,value:api.getItem(key),writable:true}:undefined});
 Object.defineProperty(window,kind,{value:facade,configurable:true});
}
if(enforced){partitionStorage('localStorage');partitionStorage('sessionStorage');}
function url(environment){
 if(!['production','development'].includes(environment))throw Error('INVALID_ENVIRONMENT');
 const relative=/\/(?:production|development)\//.test(location.pathname)?'../':'./';
 const target=new URL((environment==='production'?supplied?.productionUrl:supplied?.developmentUrl)||(relative+environment+'/'),location.href);
 if(target.origin!==location.origin)throw Error('INVALID_ENVIRONMENT_URL');
 return target.href;
}
const canDevelop=()=>{const profile=window.GamaCloud?.verifiedProfile;return !!profile&&profile.active===true&&profile.role==='administrador';};
window.CocoEnvironment=Object.freeze({name,enforced,version:supplied?.version||'unknown',backend:Object.freeze(backend),url,canDevelop,storageName:key=>name==='production'?'coco:production:'+key:key});
})();
