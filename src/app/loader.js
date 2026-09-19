/** Optional workspaces load on first use; direct cross-module links share the same loader. */
const pending=new Map();
export const lazyModules={
 accounting:{global:'GamaAccounting',file:'gama-accounting.js',methods:['open','rpc']},
 fleet:{global:'GamaFleet',file:'gama-fleet.js',methods:['open','openVehicle','openDriver','rpc']},
 returns:{global:'GamaReturns',file:'gama-returns.js',methods:['open','openReturn','createFrom','rpc']}
};
export function loadModule(id) {
 const entry=lazyModules[id];if(!entry)return Promise.resolve();
 if(window[entry.global]&&!window[entry.global].__arcLazy)return Promise.resolve(window[entry.global]);
 if(pending.has(id))return pending.get(id);
 const promise=new Promise((resolve,reject)=>{
  const script=document.createElement('script');script.src=window.ArcAssets?.[entry.file]||entry.file;script.dataset.arcModule=id;
  script.onload=()=>{const api=window[entry.global];if(api&&!api.__arcLazy)resolve(api);else{script.remove();pending.delete(id);reject(Error('MODULE_LOAD_FAILED'));}};
  script.onerror=()=>{script.remove();pending.delete(id);reject(Error('MODULE_LOAD_FAILED'));};
  document.head.appendChild(script);
 });pending.set(id,promise);return promise;
}
export function installLazyModules() {
 for(const [id,entry] of Object.entries(lazyModules)){
  if(window[entry.global])continue;
  window[entry.global]={__arcLazy:true,...Object.fromEntries(entry.methods.map(method=>[method,async(...args)=>{
   try{return (await loadModule(id))[method](...args);}catch(e){window.gamaToast?.(window.ArcErrors?.message(e)||e.message);throw e;}
  }]))};
 }
}
