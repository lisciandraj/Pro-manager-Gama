/* GAMA — module registry only. No DOM rewriting, no observers. */
(function(){
'use strict';
const modules={
  gamaTMS:{label:'Entregas / TMS',script:'gama-tms-module.js?v=20260828-4'}
};
window.gamaModules=modules;
window.gamaStandardUIReady=true;
})();
