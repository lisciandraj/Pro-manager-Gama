/* GAMA V11 - Spanish access role labels */
(function(){
'use strict';
const MAP={'Magasinier':'Almacenero','Commercial':'Comercial'};
function translate(root=document.body){
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 const nodes=[];let n;while(n=walker.nextNode())nodes.push(n);
 nodes.forEach(x=>{let v=x.nodeValue;Object.keys(MAP).forEach(k=>{v=v.split(k).join(MAP[k])});if(v!==x.nodeValue)x.nodeValue=v});
}
function boot(){translate();new MutationObserver(()=>translate()).observe(document.body,{subtree:true,childList:true,characterData:true})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
