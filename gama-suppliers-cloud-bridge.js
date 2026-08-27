/* GAMA — bridge fournisseurs legacy localStorage -> Supabase */
(function(){
  'use strict';
  const LOCAL_KEY='gama_suppliers_v1';
  const C=()=>window.GamaCloud;
  function readLocal(){try{const v=JSON.parse(localStorage.getItem(LOCAL_KEY)||'[]');return Array.isArray(v)?v:[]}catch(e){return[]}}
  async function sync(){
    if(!C())return;
    const local=readLocal();
    if(!local.length)return;
    try{
      const r=await C().list('suppliers',{order:'name',ascending:true});
      if(r.error)return;
      const cloud=r.data||[];
      for(const s of local){
        const name=String(s.name||'').trim();
        if(!name)continue;
        const tax=String(s.tax||'').trim();
        const exists=cloud.some(x=>(tax&&String(x.tax_id||'').trim()===tax)||String(x.name||'').trim().toLowerCase()===name.toLowerCase());
        if(exists)continue;
        const ins=await C().insert('suppliers',{
          name,
          tax_id:tax||null,
          address:String(s.address||'').trim()||null,
          city:String(s.city||'').trim()||null,
          country:'Ecuador',
          phone:String(s.phone||'').trim()||null,
          email:String(s.email||'').trim()||null,
          contact_name:String(s.contact||'').trim()||null,
          notes:String(s.notes||'').trim()||null,
          active:true
        });
        if(ins.data)cloud.push(ins.data);
      }
      window.dispatchEvent(new CustomEvent('gama:suppliers-cloud-change'));
      if(window.gamaShowPurchases && document.getElementById('gamaPurchasesV14')?.style.display!=='none'){
        setTimeout(()=>window.gamaShowPurchases(),100);
      }
    }catch(e){console.warn('[GAMA Suppliers Bridge]',e)}
  }
  function boot(){
    if(!C()||!window.GamaCloudReady)return setTimeout(boot,250);
    window.GamaCloudReady.then(sync).catch(()=>{});
    window.addEventListener('gama:auth-change',e=>{if(e.detail?.session)sync()});
    window.addEventListener('gama:suppliers-local-change',sync);
    setInterval(sync,3000);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
