/* GAMA — compatibility layer for Compras */
(function(){
  'use strict';
  function install(){
    if(!window.GamaCloud || typeof window.GamaCloud.db!=='function') return false;
    if(typeof window.GamaCloud.select!=='function'){
      window.GamaCloud.select=function(table,columns){
        return window.GamaCloud.db().then(function(c){
          return c.from(table).select(columns||'*');
        });
      };
    }
    return true;
  }
  if(install()) return;
  var timer=setInterval(function(){if(install()) clearInterval(timer)},100);
  setTimeout(function(){clearInterval(timer)},15000);
})();