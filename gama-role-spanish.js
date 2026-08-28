/* GAMA — etiquetas de rol en español. Sin observadores ni cambios de navegación. */
(function(){
'use strict';
const MAP={'Magasinier':'Almacenero','Commercial':'Comercial','Livraisons':'Entregas','Livraison':'Entrega'};
function translate(){
 const root=document.body;if(!root)return;
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 const nodes=[];let n;while(n=walker.nextNode())nodes.push(n);
 nodes.forEach(x=>{let v=x.nodeValue;Object.keys(MAP).forEach(k=>{v=v.split(k).join(MAP[k])});if(v!==x.nodeValue)x.nodeValue=v});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',translate,{once:true});else translate();
})();
