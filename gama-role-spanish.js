/* GAMA — Spanish labels + single TMS menu entry */
(function(){
'use strict';
const MAP={'Magasinier':'Almacenero','Commercial':'Comercial','Livraisons':'Entregas','Livraison':'Entrega'};
function translate(root=document.body){
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 const nodes=[];let n;while(n=walker.nextNode())nodes.push(n);
 nodes.forEach(x=>{let v=x.nodeValue;Object.keys(MAP).forEach(k=>{v=v.split(k).join(MAP[k])});if(v!==x.nodeValue)x.nodeValue=v});
}
function isTMS(card){
 const text=(card.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
 return text.includes('tms')||text.includes('entregas')||text.includes('livraisons')||text.includes('livraison');
}
function normalizeTMS(card){
 card.setAttribute('data-gama-tms-card','1');
 const title=card.querySelector('.gamaF2Title,.appTile b');
 if(title)title.textContent='Entregas / TMS';
 const small=card.querySelector('.appTile small');
 if(small)small.textContent='Rutas · seguimiento · POD';
}
function dedupeTMS(){
 const hosts=document.querySelectorAll('#mainmenu .appGrid,#mainmenu .gamaF2Grid');
 hosts.forEach(grid=>{
   const cards=[...grid.children].filter(el=>el.tagName==='BUTTON'&&isTMS(el));
   if(!cards.length)return;
   let keep=cards.find(c=>c.hasAttribute('data-gama-module')||c.hasAttribute('data-gama-tms-card'))||cards[0];
   normalizeTMS(keep);
   cards.forEach(c=>{if(c!==keep)c.remove()});
 });
}
function boot(){
 translate();
 dedupeTMS();
 const observer=new MutationObserver(()=>{translate();dedupeTMS()});
 observer.observe(document.body,{subtree:true,childList:true,characterData:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();