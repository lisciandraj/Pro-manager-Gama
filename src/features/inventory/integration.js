/* Keep the established Stock entry point; fetch its workspace on first use. */
(function(){
 'use strict';
 window.GamaOpenWarehouses=(...args)=>window.GamaInventoryV2.abrir(...args);
 // A mutation in another module must not download an unopened Stock workspace.
 const api=window.GamaInventoryV2;
 if(api?.__arcLazy)api.cargar=async()=>{};
})();
