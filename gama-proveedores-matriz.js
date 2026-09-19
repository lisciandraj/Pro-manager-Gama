/* GAMA V10 - Módulos Proveedores + Matriz comercial */
(function(){
'use strict';
const SUP_KEY='gama_suppliers_v1', MAT_KEY='gama_matrix_v1';
/* La descripción de cada pantalla, en un solo sitio: section() sólo escribe la
   cabecera la primera vez, así que si el texto estuviera repetido ganaría el
   de quien llame antes — que es justo lo que pasaba con la matriz. */
const SUP_LEAD='El contacto y las condiciones de cada proveedor.';
const MAT_LEAD='Calcula el precio de venta según tu margen.';
const $=id=>document.getElementById(id);
function load(k,fallback=[]){try{const v=JSON.parse(localStorage.getItem(k)||'null');return Array.isArray(v)?v:fallback}catch(e){return fallback}}
function save(k,v){localStorage.setItem(k,JSON.stringify(v))}
function esc(v){return window.ArcUI.esc(v)}
function money(n){return window.GamaCurrency.format(n)}
function products(){return Array.isArray(window.db?.products)?window.db.products:[]}
function injectStyles(){ /* Styles are compiled in architect-components.css. */ }
/* La cabecera es la misma que la del resto de la aplicación; sólo cambian el
   título y las frases que explican la pantalla. */
function section(id,title,sub){let s=$(id);if(s)return s;s=document.createElement('section');s.id=id;window.ArcUI.render(s,window.GamaUI.header({title,lead:sub})+`<div id="${id}Content"></div>`);const wrap=document.querySelector('.wrap');(wrap||document.body).appendChild(s);window.GamaUI.bindBack(s);return s}
const CLOUD=()=>window.GamaCloud;
const SUP_FIELDS=['supName','supTax','supContact','supPhone','supEmail','supCity','supAddress','supNotes'];
const MIGRATED_KEY='gama_suppliers_migrated_v1';
let cloudSuppliers=[];
const supKey=v=>String(v??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'');
function supFromCloud(r){return window.ArcEntities.legacySupplier(r)}
async function fetchSuppliers(){if(!CLOUD())return [];const r=await window.ArcData.all('suppliers',{order:'name',ascending:true},true);if(r.error)throw r.error;return (r.data||[]).map(supFromCloud)}
/* The supplier directory used to live only in localStorage, disconnected from the
   central suppliers table that Compras and the product sheets already read. Copy
   anything that only exists locally into the cloud once, then never again. */
async function migrateLocalSuppliersOnce(existing){
 try{if(localStorage.getItem(MIGRATED_KEY))return 0}catch(e){return 0}
 const local=load(SUP_KEY);
 if(!Array.isArray(local)||!local.length){try{localStorage.setItem(MIGRATED_KEY,'1')}catch(e){}return 0}
 const have=new Set(existing.map(x=>supKey(x.name)));
 let moved=0;
 for(const s of local){
  if(!s||!s.name||have.has(supKey(s.name)))continue;
  const r=await CLOUD().insert('suppliers',{name:s.name,tax_id:s.tax||null,contact_name:s.contact||null,phone:s.phone||null,email:s.email||null,city:s.city||null,address:s.address||null,notes:s.notes||null,active:true});
  if(!r.error){have.add(supKey(s.name));moved++}
 }
 try{localStorage.setItem(MIGRATED_KEY,'1')}catch(e){}
 return moved;
}
function renderSuppliers(){section('suppliers','🏭 Proveedores',SUP_LEAD);const host=$('suppliersContent');if(!host)return;const cleanup=window.ArcDirectories.suppliers(host);migrateLocalSuppliersOnce(cloudSuppliers).then(moved=>{if(moved){window.ArcData.invalidate('suppliers');window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'suppliers'}}))}}).catch(console.error);return cleanup}

function renderMatrix(){section('matrix','📊 Matriz comercial',MAT_LEAD);const c=$('matrixContent');if(!c)return;const mats=load(MAT_KEY),ps=products(),sups=cloudSuppliers.filter(x=>x.active!==false);const totalPurchase=mats.reduce((a,x)=>a+Number(x.purchase||0),0),totalSale=mats.reduce((a,x)=>a+Number(x.sale||0),0);window.ArcUI.render(c,`<div class="gamaPMCards"><div class="arcPanel gamaPMStat"><small data-gi=54d18b2d0387>Referencias en matriz</small><strong>${mats.length}</strong></div><div class="arcPanel gamaPMStat"><small data-gi=0a6891f225a5>Compra total</small><strong>${money(totalPurchase)}</strong></div><div class="arcPanel gamaPMStat"><small data-gi=c4d142b84330>Venta total calculada</small><strong>${money(totalSale)}</strong></div></div><div class="arcPanel gamaPMForm" style="margin-bottom:12px"><h3 data-gi=13acf789cfc5>Agregar / recalcular una referencia</h3><div class="gamaPMMatrixInputs"><div><label data-gi=ae0e47ca14d2>Producto *</label><select id="matProduct"><option value="" data-gi=81ec4e39d9fd>Seleccionar producto</option>${ps.map(p=>`<option value="${esc(p.barcode||p.id||p.name)}">${esc(p.name)}${p.barcode?' · '+esc(p.barcode):''}</option>`).join('')}</select></div><div><label data-gi=e746643f4479>Proveedor</label><select id="matSupplier"><option value="" data-gi=480def1d15a8>Sin proveedor</option>${sups.map(x=>`<option value="${esc(x.id)}">${esc(x.name)}</option>`).join('')}</select></div><div><label data-gi=3d781e982503>Precio de compra unitario (USD) *</label><input id="matPurchase" type="number" min="0" step="0.01" placeholder="0.00"></div><div><label data-gi=cdde3b034f16>Margen comercial objetivo (%)</label><input id="matMargin" type="number" min="0" max="99.99" step="0.1" value="30"></div></div><div class="gamaPMFormula" data-gi=af596ccfaf2d>Precio de reventa automático = precio de compra ÷ (1 − margen objetivo). <strong id="matPreview">$0.00</strong></div><div class="gamaPMBtns"><button class="arcButton primary" id="matAdd" data-gi=d71f17194736>＋ Añadir a la matriz</button><button class="arcButton secondary" id="matClear" data-gi=4d1e6caec772>Reiniciar</button></div></div><div class="arcPanel gamaPMForm"><h3 data-gi=0268695d2aea>Matriz compra / reventa</h3><input class="gamaPMSearch" id="matSearch" data-gi-placeholder=6770b4cebf10 placeholder="Buscar un producto..."><div class="gamaPMTable"><table class="arcTable"><thead><tr><th data-gi=77b9238931ed>Producto</th><th data-gi=e746643f4479>Proveedor</th><th data-gi=46ca644978eb>Compra</th><th data-gi=935d3af1f44f>Margen</th><th data-gi=94a4bfa5bf4b>Reventa auto</th><th data-gi=688e329df559>Beneficio</th><th data-gi=fb89a30ba7f6>Acciones</th></tr></thead><tbody id="matRows"></tbody></table></div></div>`);const recalc=()=>{const p=Number($('matPurchase').value||0),m=Number($('matMargin').value||0),sale=m>=100?0:p/(1-m/100);$('matPreview').textContent=money(sale)};$('matPurchase').oninput=recalc;$('matMargin').oninput=recalc;recalc();const renderRows=()=>{const q=($('matSearch')?.value||'').toLowerCase();const data=load(MAT_KEY).filter(x=>x.name.toLowerCase().includes(q));window.ArcUI.render($('matRows'),data.length?GamaPage.slice('matrix',data).map(x=>{const profit=Number(x.sale)-Number(x.purchase);const supplier=sups.find(s=>s.id===x.supplierId);return `<tr><td><b>${esc(x.name)}</b><br><span class="muted">${esc(x.barcode||'')}</span></td><td>${esc(supplier?.name||'—')}</td><td>${money(x.purchase)}</td><td class="${Number(x.margin)>=0?'gamaPMGood':'gamaPMWarn'}">${Number(x.margin).toFixed(1)}%</td><td><b>${money(x.sale)}</b></td><td class="${profit>=0?'gamaPMGood':'gamaPMWarn'}">${money(profit)}</td><td><button class="arcButton danger gamaPMIconBtn" data-matdel="${x.id}" data-gi=c9894cf002f9>Eliminar</button></td></tr>`}).join('')+(GamaPage.controls('matrix',data.length)?`<tr><td colspan="7">${GamaPage.controls('matrix',data.length)}</td></tr>`:''):'<tr><td colspan="7"><div class="gamaPMEmpty" data-gi=818b53dca8b7>Ninguna referencia en la matriz.</div></td></tr>');document.querySelectorAll('[data-matdel]').forEach(b=>b.onclick=()=>{save(MAT_KEY,load(MAT_KEY).filter(x=>x.id!==b.dataset.matdel));renderMatrix()})};$('matAdd').onclick=()=>{const key=$('matProduct').value,p=ps.find(x=>String(x.barcode||x.id||x.name)===String(key)),purchase=Number($('matPurchase').value||0),margin=Number($('matMargin').value||0);if(!p||purchase<=0)return alert('Selecciona un producto y un precio de compra válido.');if(margin<0||margin>=100)return alert('El margen debe estar entre 0 y 99,9 %.');const sale=purchase/(1-margin/100);const a=load(MAT_KEY).filter(x=>x.barcode!==String(p.barcode||'')||x.name!==p.name);a.push({id:crypto.randomUUID?crypto.randomUUID():Date.now().toString(),barcode:p.barcode||'',name:p.name,purchase,margin,sale,supplierId:$('matSupplier').value});save(MAT_KEY,a);renderMatrix()};$('matClear').onclick=()=>{$('matProduct').value='';$('matSupplier').value='';$('matPurchase').value='';$('matMargin').value='30';recalc()};$('matSearch').oninput=()=>{GamaPage.reset('matrix');renderRows()};GamaPage.register('matrix',renderRows);renderRows()}
/* Aquí vivía patchMenu(): buscaba la tarjeta «Configuración» del menú, le
   cambiaba el nombre a «Matriz comercial» y le robaba el clic, con un
   MutationObserver que lo repetía en cada cambio del DOM por si el menú se
   repintaba. El efecto secundario era que Configuración no se podía abrir
   desde ninguna parte. Matriz comercial tiene ahora su propia entrada en
   gama-menu-final2.js, que es donde se declaran las demás. */
function hook(){injectStyles();section('matrix','📊 Matriz comercial',MAT_LEAD);fetchSuppliers().then(s=>{cloudSuppliers=s}).catch(()=>{});window.ArcRouter.onEnter('suppliers',renderSuppliers);window.ArcRouter.onEnter('matrix',renderMatrix)}

if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,50),{once:true});else setTimeout(hook,50);
})();