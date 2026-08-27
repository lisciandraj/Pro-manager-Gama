/* GAMA — Cabecera estándar + navegación robuste para todos los módulos */
(function(){
'use strict';
const STYLE='gamaStandardUIStyleV5';
const SKIP=new Set(['mainmenu','login','loginSection','auth','gamaPurchasesV14']);
const TITLES={products:['📦 Productos','Gestión de productos, precios y existencias'],clients:['👥 Clientes','Gestión de clientes y contactos'],suppliers:['🏭 Proveedores','Gestión de proveedores y condiciones de compra'],stock:['📊 Inventario','Control de existencias y movimientos'],movement:['🔄 Movimientos','Entradas, salidas y ajustes de inventario'],movements:['🔄 Movimientos','Entradas, salidas y ajustes de inventario'],billing:['🧾 Facturación','Facturas, ventas y cobros'],audit:['🔎 Auditoría','Historial de operaciones y trazabilidad'],excel:['📥 Importar Excel','Importación de productos, clientes y proveedores'],settings:['⚙️ Configuración','Configuración de GAMA Stock Manager'],backup:['💾 Copias de seguridad','Exportación y restauración de datos'],barcode:['🏷️ Códigos de barras','Generación e impresión de etiquetas']};
function menu(){
 document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.removeProperty('display');s.style.display='none'});
 const m=document.getElementById('mainmenu');if(m){m.removeAttribute('hidden');m.classList.add('active');m.style.setProperty('display','block','important')}
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
}
function addStyles(){if(document.getElementById(STYLE))return;const s=document.createElement('style');s.id=STYLE;s.textContent=`#globalBack{display:none!important}.gamaStdHeader{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:16px!important;margin:0 0 14px!important;padding:18px 20px!important;background:#fff!important;border:1px solid #E2E8EC!important;border-radius:15px!important;box-shadow:0 3px 16px #1732460d!important}.gamaStdKicker{font-size:10px!important;font-weight:850!important;letter-spacing:2px!important;color:#087C8B!important;text-transform:uppercase!important;margin-bottom:4px!important}.gamaStdHeader h2{margin:0!important;font-size:27px!important;line-height:1.15!important;color:#18324A!important;font-weight:800!important}.gamaStdHeader p{margin:6px 0 0!important;color:#71808A!important;font-size:15px!important;line-height:1.35!important}.gamaStdActions{display:flex!important;gap:8px!important;align-items:center!important;flex-shrink:0!important}.gamaStdBack{display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:6px!important;white-space:nowrap!important;background:#EEF3F4!important;color:#18324A!important;border:1px solid #DCE5E8!important;border-radius:10px!important;padding:11px 15px!important;font-weight:750!important;cursor:pointer!important;min-height:44px!important}@media(max-width:700px){.gamaStdHeader{align-items:stretch!important;flex-direction:column!important;padding:15px!important}.gamaStdHeader h2{font-size:23px!important}.gamaStdHeader p{font-size:13px!important}.gamaStdActions{width:100%!important}.gamaStdBack{width:100%!important}}`;document.head.appendChild(s)}
function titleFor(sec){const id=(sec.id||'').toLowerCase();if(TITLES[id])return TITLES[id];const h=sec.querySelector('h1,h2,h3');let title=h?.textContent?.trim()||'Módulo';title=title.replace(/^(Nuevo|Nueva|Gestionar|Gestión de)\s+/i,'');return[title,'Gestión de GAMA Stock Manager']}
function addStandardHeader(sec){if(SKIP.has(sec.id)||sec.querySelector(':scope > .gamaStdHeader, :scope > [data-gama-standard-header]'))return;const own=sec.querySelector(':scope > .gp14Head');if(own){if(!own.querySelector('.gamaStdBack')){const actions=own.querySelector('.gp14TopActions')||own;const b=document.createElement('button');b.type='button';b.className='gamaStdBack';b.textContent='← Volver al menú';b.setAttribute('aria-label','Volver al menú');b.onclick=menu;actions.appendChild(b)}return}if(!sec.firstElementChild)return;const title=titleFor(sec),header=document.createElement('div');header.className='gamaStdHeader';header.setAttribute('data-gama-standard-header','1');header.innerHTML='<div><div class="gamaStdKicker">GAMA STOCK MANAGER</div><h2>'+escapeHtml(title[0])+'</h2><p>'+escapeHtml(title[1])+'</p></div><div class="gamaStdActions"><button type="button" class="gamaStdBack" aria-label="Volver al menú">← Volver al menú</button></div>';header.querySelector('button').onclick=menu;sec.insertBefore(header,sec.firstChild)}
function standardize(){addStyles();const b=document.getElementById('globalBack');if(b)b.remove();document.querySelectorAll('section').forEach(addStandardHeader)}
function forceView(id){document.querySelectorAll('section').forEach(s=>{const active=s.id===id;s.classList.toggle('active',active);if(active){s.removeAttribute('hidden');s.style.setProperty('display','block','important')}else{s.style.setProperty('display','none','important')}});const target=document.getElementById(id);if(target){target.removeAttribute('hidden');target.style.setProperty('display','block','important');target.classList.add('active')}standardize()}
function patchShowTab(){
 const current=window.showTab;
 if(typeof current!=='function'||current.__gamaPatched)return false;
 if(current.__gamaWrapper)return true;
 const original=current;
 function fixedShowTab(id,btn){
   try{original.call(this,id,btn)}catch(e){console.warn('[GAMA navigation]',e)}
   forceView(id);
   setTimeout(()=>forceView(id),0);
   setTimeout(()=>forceView(id),80);
 }
 fixedShowTab.__gamaPatched=true;fixedShowTab.__gamaWrapper=true;fixedShowTab.__gamaOriginal=original;window.showTab=fixedShowTab;return true;
}
function ensureNavigation(){
 patchShowTab();
 /* On ne stoppe volontairement pas la surveillance : certains modules/scripts
    peuvent redéfinir showTab après le chargement initial. */
 setTimeout(ensureNavigation,500);
}
function boot(){standardize();ensureNavigation();new MutationObserver(()=>{standardize();patchShowTab()}).observe(document.body,{childList:true,subtree:true})}
function escapeHtml(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.gamaStandardBackToMenu=menu;
})();