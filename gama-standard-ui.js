/* GAMA — registre de modules simple et stable */
(function(){
'use strict';
const MODULE={
 id:'gamaTMS',
 label:'Entregas / TMS',
 icon:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
 script:'gama-tms-module.js?v=20260828-4'
};
function loadTMS(){return new Promise((resolve,reject)=>{if(window.gamaTMS){resolve();return}if(document.getElementById('gamaTMSLoader')){let n=0,t=setInterval(()=>{if(window.gamaTMS){clearInterval(t);resolve()}else if(++n>60){clearInterval(t);reject(new Error('No se pudo cargar Entregas / TMS'))}},100);return}const s=document.createElement('script');s.id='gamaTMSLoader';s.src=MODULE.script;s.onload=()=>window.gamaTMS?resolve():reject(new Error('Entregas / TMS no está disponible'));s.onerror=()=>reject(new Error('No se pudo cargar Entregas / TMS'));document.body.appendChild(s)})}
function isTMS(card){const text=(card.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();return text.includes('tms')||text.includes('entregas')||text.includes('livraisons')||text.includes('livraison')}
function removeTMSCards(){document.querySelectorAll('#mainmenu .appGrid > button,#mainmenu .gamaF2Grid > button').forEach(card=>{if(isTMS(card))card.remove()})}
function addTMSCard(){const grid=document.querySelector('#mainmenu .appGrid, #mainmenu .gamaF2Grid');if(!grid||grid.querySelector('[data-gama-module="gamaTMS"]'))return;const b=document.createElement('button');b.type='button';b.className=grid.classList.contains('gamaF2Grid')?'gamaF2Card appTile gamaModuleCard':'appTile gamaModuleCard';b.dataset.gamaModule=MODULE.id;b.innerHTML='<span class="appIcon teal"><svg viewBox="0 0 24 24">'+MODULE.icon+'</svg></span><b>'+MODULE.label+'</b><small>Rutas · seguimiento · POD</small>';b.onclick=()=>loadTMS().then(()=>window.gamaTMS.open('planning')).catch(e=>alert(e.message));grid.appendChild(b)}
function boot(){removeTMSCards();addTMSCard();window.gamaStandardUIReady=true;window.gamaModules=[MODULE]}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
