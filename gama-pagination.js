/* GAMA — paginación compartida para todas las listas (20 elementos por página).
   Cada lista se identifica con una clave y registra su función de repintado:
     GamaPage.register('products',()=>renderProducts(...))
   y luego reparte sus filas y añade los controles:
     GamaPage.slice('products',rows)  ->  las filas de la página actual
     GamaPage.controls('products',rows.length)  ->  el HTML de « Anterior / Siguiente » */
(function(){
'use strict';
const SIZE=20;
const pages={},renderers={};
const pageCount=t=>Math.max(1,Math.ceil((Number(t)||0)/SIZE));
function clamp(key,total){const p=Math.min(Math.max(0,pages[key]||0),pageCount(total)-1);pages[key]=p;return p}
function slice(key,rows){const r=Array.isArray(rows)?rows:[];const p=clamp(key,r.length);return r.slice(p*SIZE,p*SIZE+SIZE)}
function controls(key,total){
 total=Number(total)||0;
 if(total<=SIZE)return '';
 const last=pageCount(total),p=clamp(key,total),from=p*SIZE+1,to=Math.min(total,(p+1)*SIZE);
 return `<div class="gamaPager" data-pager="${key}"><button type="button" class="gamaPagerBtn" data-page-prev ${p<=0?'disabled':''} onclick="GamaPage.go('${key}',-1)">‹ Anterior</button><span class="gamaPagerInfo">${from}–${to} de ${total} · página ${p+1} de ${last}</span><button type="button" class="gamaPagerBtn" data-page-next ${p>=last-1?'disabled':''} onclick="GamaPage.go('${key}',1)">Siguiente ›</button></div>`;
}
function go(key,delta){pages[key]=Math.max(0,(pages[key]||0)+(Number(delta)||0));const fn=renderers[key];if(typeof fn==='function')fn();}
function register(key,fn){renderers[key]=fn}
function reset(key){pages[key]=0}
function styles(){
 if(document.getElementById('gamaPagerCss'))return;
 const s=document.createElement('style');s.id='gamaPagerCss';
 s.textContent='.gamaPager{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;margin-top:12px;padding-top:10px;border-top:1px solid #E2E8EC}.gamaPagerInfo{color:#71808A;font-size:12px;font-weight:700}.gamaPagerBtn{background:#EEF3F4;color:#18324A;border:1px solid #DCE5E8;border-radius:9px;padding:9px 14px;font-weight:800;cursor:pointer;min-height:40px;white-space:nowrap}.gamaPagerBtn[disabled]{opacity:.45;cursor:default}@media(max-width:560px){.gamaPager{justify-content:center}.gamaPagerInfo{order:-1;width:100%;text-align:center}}';
 document.head.appendChild(s);
}
window.GamaPage={SIZE,slice,controls,go,register,reset,pageCount,page:k=>pages[k]||0};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',styles,{once:true});else styles();
})();
