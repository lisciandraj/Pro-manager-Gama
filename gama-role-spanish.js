/* GAMA V11 - Spanish access role labels + TMS menu integration */
(function(){
'use strict';
const MAP={'Magasinier':'Almacenero','Commercial':'Comercial'};
function translate(root=document.body){
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 const nodes=[];let n;while(n=walker.nextNode())nodes.push(n);
 nodes.forEach(x=>{let v=x.nodeValue;Object.keys(MAP).forEach(k=>{v=v.split(k).join(MAP[k])});if(v!==x.nodeValue)x.nodeValue=v});
}
function loadTMS(){
 if(document.getElementById('gamaTMSModuleLoader'))return;
 const s=document.createElement('script');
 s.id='gamaTMSModuleLoader';
 s.src='gama-tms-module.js?v=20260828-1';
 s.onload=()=>addTMSCard();
 s.onerror=()=>console.warn('[GAMA TMS] No se pudo cargar el módulo TMS');
 document.body.appendChild(s);
}
function addTMSCard(){
 const host=document.getElementById('mainmenu');
 const grid=host?.querySelector('.gamaF2Grid');
 if(!grid||!window.gamaTMS?.open)return false;
 if(grid.querySelector('[data-gama-tms-card]'))return true;
 const b=document.createElement('button');
 b.type='button';
 b.className='gamaF2Card';
 b.setAttribute('data-gama-tms-card','1');
 b.innerHTML='<span class="gamaF2Icon" style="background:#e8f5f6;color:#087c8b"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/></svg></span><span class="gamaF2Title">Entregas / TMS</span>';
 b.onclick=()=>window.gamaTMS.open('planning');
 grid.appendChild(b);
 return true;
}
function boot(){
 translate();
 loadTMS();
 addTMSCard();
 const observer=new MutationObserver(()=>{translate();addTMSCard()});
 observer.observe(document.body,{subtree:true,childList:true,characterData:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();