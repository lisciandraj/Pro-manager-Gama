/* GAMA — menu principal simple et stable */
(function(){
'use strict';
const MODULE={id:'gamaTMS',label:'Entregas / TMS',icon:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',script:'gama-tms-module.js?v=20260828-5'};
const ALLOWED=['Facturación','Inventario','Auditoría','Proveedores','Compras','Matriz comercial','Copias de seguridad','Usuarios','Códigos de barras'];
function text(card){return(card.textContent||'').replace(/\s+/g,' ').trim()}
function isTMS(card){const t=text(card).toLowerCase();return t.includes('tms')||t.includes('entregas')||t.includes('livraisons')||t.includes('livraison')}
function cleanMenu(){
 const grids=document.querySelectorAll('#mainmenu .appGrid,#mainmenu .gamaF2Grid');
 grids.forEach(grid=>{
  const seen=new Set();
  [...grid.children].forEach(card=>{
   if(card.tagName!=='BUTTON')return;
   const t=text(card);
   if(isTMS(card)){card.remove();return}
   const keep=ALLOWED.some(label=>t===label||t.startsWith(label+' '));
   if(!keep||seen.has(t))card.remove();else seen.add(t);
  });
 });
}
function loadTMS(){return new Promise((resolve,reject)=>{
 if(window.gamaTMS){resolve();return}
 const old=document.getElementById('gamaTMSLoader');
 if(old){let n=0,t=setInterval(()=>{if(window.gamaTMS){clearInterval(t);resolve()}else if(++n>60){clearInterval(t);reject(new Error('No se pudo cargar Entregas / TMS'))}},100);return}
 const s=document.createElement('script');s.id='gamaTMSLoader';s.src=MODULE.script;s.onload=()=>window.gamaTMS?resolve():reject(new Error('Entregas / TMS no está disponible'));s.onerror=()=>reject(new Error('No se pudo cargar Entregas / TMS'));document.body.appendChild(s);
})}
function addTMS(){
 const grid=document.querySelector('#mainmenu .appGrid,#mainmenu .gamaF2Grid');if(!grid)return;
 if(grid.querySelector('[data-gama-module="gamaTMS"]'))return;
 const b=document.createElement('button');b.type='button';b.className='appTile gamaModuleCard';b.dataset.gamaModule=MODULE.id;
 b.innerHTML='<span class="appIcon teal"><svg viewBox="0 0 24 24">'+MODULE.icon+'</svg></span><b>Entregas / TMS</b><small>Rutas · seguimiento · POD</small>';
 b.onclick=()=>loadTMS().then(()=>window.gamaTMS.open('planning')).catch(e=>alert(e.message));
 grid.appendChild(b);
}
function boot(){cleanMenu();addTMS();window.gamaStandardUIReady=true;window.gamaModules=[MODULE]}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
