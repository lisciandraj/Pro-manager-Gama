/* GAMA V12 — central products + stock adapter */
(function(){'use strict';
  function boot(){
    if(!window.GamaCloud)return setTimeout(boot,250);
    const C=window.GamaCloud;
    if(typeof C.select!=='function'){
      C.select=function(table,columns){
        return C.db().then(function(client){return client.from(table).select(columns||'*');});
      };
    }
    const api={
      async listProducts(options){return C.list('products',options||{order:'name',ascending:true});},
      async getProduct(id){const c=await C.db();return c.from('products').select('*').eq('id',id).maybeSingle();},
      async getByBarcode(barcode){const c=await C.db();return c.from('products').select('*').eq('barcode',String(barcode).trim()).maybeSingle();},
      async createProduct(product){return C.insert('products',product);},
      async updateProduct(id,product){return C.update('products',id,product);},
      async deleteProduct(id){return C.remove('products',id);},
      async listMovements(options){return C.list('stock_movements',options||{order:'created_at',ascending:false});},
      async addMovement(movement){return C.insert('stock_movements',movement);},
      async startRealtime(){
        if(api._realtimeStarted)return;
        api._realtimeStarted=true;
        await C.subscribe('products',p=>window.dispatchEvent(new CustomEvent('gama:products-cloud-change',{detail:p})));
        await C.subscribe('stock_movements',p=>window.dispatchEvent(new CustomEvent('gama:stock-cloud-change',{detail:p})));
      }
    };
    window.GamaCloudProducts=api;
    C.getSession().then(r=>{if(r&&r.data&&r.data.session)api.startRealtime();});
    window.addEventListener('gama:auth-change',e=>{if(e.detail&&e.detail.session)api.startRealtime();});
    /* Always load the supplier bridge from a script that is already guaranteed to be loaded. */
    if(!document.getElementById('gamaSupplierBridgeLoader')){
      const s=document.createElement('script');s.id='gamaSupplierBridgeLoader';s.src='gama-purchases-supplier-bridge.js?v=3';s.async=true;document.head.appendChild(s);
    }
  }
  boot();
})();
