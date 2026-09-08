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
function esc(v){return String(v??'').replace(/[&<>\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\\':'&#92;','"':'&quot;'}[c]))}
function money(n){return '$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2})}
function products(){return Array.isArray(window.db?.products)?window.db.products:[]}
function injectStyles(){if($('gamaPMStyle'))return;const s=document.createElement('style');s.id='gamaPMStyle';s.textContent=`#gamaMatrix section,#gamaMatrixCard{scroll-margin-top:90px}.gamaPMGrid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.gamaPMForm{background:#fff;border:1px solid var(--gama-line,#E4EBEE);border-radius:15px;padding:16px}.gamaPMForm h3{margin:0 0 10px}.gamaPMBtns{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}.gamaPMTable{width:100%;overflow:auto}.gamaPMTable table{width:100%;min-width:850px;border-collapse:collapse}.gamaPMTable th,.gamaPMTable td{padding:10px;border-bottom:1px solid #edf1f2;text-align:left;font-size:12px}.gamaPMTable th{color:#71808a;background:#f7f9fa}.gamaPMGood{color:#128C68;font-weight:800}.gamaPMWarn{color:#C94F45;font-weight:800}.gamaPMCards{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:12px}.gamaPMStat{background:#fff;border:1px solid var(--gama-line,#E4EBEE);border-radius:14px;padding:14px}.gamaPMStat small{display:block;color:#71808a}.gamaPMStat strong{display:block;font-size:22px;margin-top:5px}.gamaPMEmpty{padding:24px;text-align:center;color:#71808a}.gamaPMSearch{margin-bottom:10px}.gamaPMIconBtn{padding:7px 9px}.gamaPMMatrixInputs{display:grid;grid-template-columns:1fr 1fr;gap:10px}.gamaPMFormula{background:#fff6ef;border-left:4px solid var(--gama-orange,#F47A2A);padding:12px;border-radius:8px;margin-top:10px}.gamaPMFormula strong{font-size:18px}@media(max-width:700px){.gamaPMGrid,.gamaPMMatrixInputs{grid-template-columns:1fr}.gamaPMCards{grid-template-columns:1fr 1fr}}`;document.head.appendChild(s)}
/* La cabecera es la misma que la del resto de la aplicación; sólo cambian el
   título y las frases que explican la pantalla. */
function section(id,title,sub){let s=$(id);if(s)return s;s=document.createElement('section');s.id=id;s.innerHTML=window.GamaUI.header({title,lead:sub})+`<div id="${id}Content"></div>`;const wrap=document.querySelector('.wrap');(wrap||document.body).appendChild(s);window.GamaUI.bindBack(s);return s}
const CLOUD=()=>window.GamaCloud;
const SUP_FIELDS=['supName','supTax','supContact','supPhone','supEmail','supCity','supAddress','supNotes'];
const MIGRATED_KEY='gama_suppliers_migrated_v1';
let cloudSuppliers=[];
const supKey=v=>String(v??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'');
/* Categor\u00eda del proveedor: A = grossiste, B = compra al detalle, C = precio
   especial por contrato (gestionado en el m\u00f3dulo Tarifas). Un proveedor C sin
   precio especial pactado para un producto factura al precio de la categor\u00eda A. */
const SUP_CATEGORY_LABEL={A:'A \u00b7 Grossiste',B:'B \u00b7 Detalle',C:'C \u00b7 Precio especial'};
function supFromCloud(r){return {id:r.id,name:r.name||'',tax:r.tax_id||'',contact:r.contact_name||'',phone:r.phone||'',email:r.email||'',city:r.city||'',address:r.address||'',notes:r.notes||'',category:r.category||'A',active:r.active!==false}}
async function fetchSuppliers(){if(!CLOUD())return [];const r=await CLOUD().list('suppliers',{order:'name',ascending:true});if(r.error)throw r.error;return (r.data||[]).map(supFromCloud)}
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
  const r=await CLOUD().insert('suppliers',{name:s.name,tax_id:s.tax||null,contact_name:s.contact||null,phone:s.phone||null,email:s.email||null,city:s.city||null,address:s.address||null,notes:s.notes||null,category:s.category||'A',active:true});
  if(!r.error){have.add(supKey(s.name));moved++}
 }
 try{localStorage.setItem(MIGRATED_KEY,'1')}catch(e){}
 return moved;
}
function supMsg(t,err){const m=$('supMsg');if(!m)return;m.textContent=t||'';m.style.color=err?'#C94F45':'#71808A'}
async function loadSuppliers(){
 const host=$('supList');if(!host)return;
 if(!CLOUD()){host.innerHTML='<div class="gamaPMEmpty">Conéctate a la nube para ver los proveedores.</div>';return}
 try{
  cloudSuppliers=await fetchSuppliers();
  const moved=await migrateLocalSuppliersOnce(cloudSuppliers);
  if(moved){cloudSuppliers=await fetchSuppliers();supMsg(moved+' proveedor(es) local(es) migrado(s) a la base central.')}
  listSuppliers();
  if($('matRows'))renderMatrix();
 }catch(e){console.error('[GAMA Proveedores]',e);host.innerHTML='<div class="gamaPMEmpty">No se pudieron cargar los proveedores: '+esc(e.message||e)+'</div>'}
}
function listSuppliers(){
 const host=$('supList');if(!host)return;
 const q=($('supSearch')?.value||'').toLowerCase();
 const arch=GamaArchive.mode('suppliersDir')==='archived';
 const pool=cloudSuppliers.filter(x=>arch?x.active===false:x.active!==false);
 const nAct=cloudSuppliers.filter(x=>x.active!==false).length,nArc=cloudSuppliers.filter(x=>x.active===false).length;
 const data=pool.filter(x=>[x.name,x.city,x.contact,x.email,x.phone,x.tax].join(' ').toLowerCase().includes(q));
 const bar=GamaArchive.tabs('suppliersDir',nAct,nArc)+(arch?'<div class="gamaArcNote">Estos proveedores no aparecen en las listas ni en Compras. Puedes restaurarlos cuando quieras.</div>':'');
 host.innerHTML=bar+(data.length?GamaPage.slice('suppliersDir',data).map(x=>`<div style="padding:12px 0;border-bottom:1px solid #edf1f2"><div style="display:flex;justify-content:space-between;gap:8px"><b>${esc(x.name)} <span class="muted">· ${esc(SUP_CATEGORY_LABEL[x.category]||SUP_CATEGORY_LABEL.A)}</span></b>${arch?`<span><button class="secondary gamaPMIconBtn" data-restore="${esc(x.id)}">♻️ Restaurar</button> <button class="danger gamaPMIconBtn" data-purge="${esc(x.id)}">🗑️ Borrar</button></span>`:`<button class="danger gamaPMIconBtn" data-del="${esc(x.id)}">🗄️ Archivar</button>`}</div><div class="muted">${esc(x.tax||'Sin RUC')} · ${esc(x.city||'Sin ciudad')}</div><div style="margin-top:5px">${esc(x.contact||'')} ${x.phone?'· '+esc(x.phone):''}</div><div class="muted">${esc(x.email||'')}</div><div style="margin-top:5px">📍 ${esc(x.address||'Sin dirección')}</div>${x.notes?`<div class="notice" style="margin-top:7px">${esc(x.notes)}</div>`:''}</div>`).join('')+GamaPage.controls('suppliersDir',data.length):(arch?'<div class="gamaArcEmpty">No hay proveedores archivados.</div>':'<div class="gamaPMEmpty">No hay proveedores registrados.</div>'));
 host.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>deleteSupplier(b.dataset.del));
 host.querySelectorAll('[data-restore]').forEach(b=>b.onclick=()=>restoreSupplier(b.dataset.restore));
 host.querySelectorAll('[data-purge]').forEach(b=>b.onclick=()=>purgeSupplier(b.dataset.purge));
}
async function saveSupplier(){
 const name=$('supName').value.trim();
 if(!name)return alert('El nombre del proveedor es obligatorio.');
 if(!CLOUD())return alert('La conexión con la nube de GAMA no está disponible.');
 const dup=cloudSuppliers.find(x=>supKey(x.name)===supKey(name));
 if(dup&&!confirm((dup.active===false?'Ya existe un proveedor ARCHIVADO con ese nombre. ':'')+'Ya existe un proveedor llamado «'+dup.name+'». ¿Guardarlo de todas formas?'))return;
 const r=await CLOUD().insert('suppliers',{name,tax_id:$('supTax').value.trim()||null,contact_name:$('supContact').value.trim()||null,phone:$('supPhone').value.trim()||null,email:$('supEmail').value.trim()||null,city:$('supCity').value.trim()||null,address:$('supAddress').value.trim()||null,notes:$('supNotes').value.trim()||null,category:$('supCategory').value||'A',active:true});
 if(r.error)return supMsg('No se pudo guardar: '+(r.error.message||r.error),true);
 SUP_FIELDS.forEach(id=>{const el=$(id);if(el)el.value=''});
 $('supCategory').value='A';
 supMsg('Proveedor guardado en la base central.');
 await loadSuppliers();
}
/* Archivar, no borrar: un proveedor con productos o pedidos no puede
   eliminarse sin romper la trazabilidad. Queda en la pestaña Archivados. */
async function deleteSupplier(id){
 const s=cloudSuppliers.find(x=>String(x.id)===String(id));
 if(!s||!confirm('¿Archivar al proveedor «'+s.name+'»?\n\nDejará de aparecer en las listas y en Compras, pero se conserva y puedes restaurarlo.'))return;
 const r=await CLOUD().update('suppliers',id,{active:false});
 if(r.error)return supMsg('No se pudo archivar: '+GamaArchive.friendlyError(r.error,'supplier'),true);
 await loadSuppliers();
}
async function restoreSupplier(id){
 const r=await CLOUD().update('suppliers',id,{active:true});
 if(r.error)return supMsg('No se pudo restaurar: '+String(r.error.message||r.error),true);
 await loadSuppliers();
}
async function purgeSupplier(id){
 const s=cloudSuppliers.find(x=>String(x.id)===String(id));
 if(!s||!confirm('¿Borrar definitivamente a «'+s.name+'»?\n\nEsta accion no se puede deshacer. Solo es posible si no tiene productos ni pedidos asociados.'))return;
 const r=await CLOUD().remove('suppliers',id);
 if(r.error)return supMsg(GamaArchive.friendlyError(r.error,'supplier'),true);
 await loadSuppliers();
}
function renderSuppliers(){section('suppliers','🏭 Proveedores',SUP_LEAD);const c=$('suppliersContent');if(!c)return;c.innerHTML=`<div class="gamaPMGrid"><div class="gamaPMForm"><h3>Nuevo proveedor</h3><div class="row"><div><label>Nombre / razón social *</label><input id="supName" placeholder="Ej. Proveedor ABC"></div><div><label>RUC / identificación</label><input id="supTax" placeholder="RUC"></div></div><div class="row"><div><label>Persona de contacto</label><input id="supContact" placeholder="Nombre"></div><div><label>Teléfono</label><input id="supPhone" placeholder="+593..."></div></div><div class="row"><div><label>Email</label><input id="supEmail" type="email" placeholder="compras@empresa.com"></div><div><label>Ciudad / país</label><input id="supCity" placeholder="Quito, Ecuador"></div></div><label>Categoría de precios</label><select id="supCategory"><option value="A">A · Grossiste (por defecto)</option><option value="B">B · Compra al detalle</option><option value="C">C · Precio especial por contrato</option></select><label>Dirección</label><input id="supAddress" placeholder="Dirección completa"><label>Información clave</label><textarea id="supNotes" placeholder="Condiciones de pago, plazos, productos, observaciones..."></textarea><div class="gamaPMBtns"><button class="primary" id="supSave">＋ Guardar proveedor</button><button class="secondary" id="supClear">Limpiar</button></div><div id="supMsg" class="muted" style="margin-top:8px"></div></div><div class="gamaPMForm"><h3>Proveedores registrados</h3><input class="gamaPMSearch" id="supSearch" placeholder="Buscar por nombre, ciudad, contacto..."><div id="supList" class="gamaPMEmpty">Cargando proveedores…</div></div></div>`;$('supSave').onclick=saveSupplier;$('supClear').onclick=()=>{SUP_FIELDS.forEach(id=>{const el=$(id);if(el)el.value=''});$('supCategory').value='A'};$('supSearch').oninput=()=>{GamaPage.reset('suppliersDir');listSuppliers()};GamaArchive.register('suppliersDir',listSuppliers);GamaPage.register('suppliersDir',listSuppliers);loadSuppliers()}
function renderMatrix(){section('matrix','📊 Matriz comercial',MAT_LEAD);const c=$('matrixContent');if(!c)return;const mats=load(MAT_KEY),ps=products(),sups=cloudSuppliers.filter(x=>x.active!==false);const totalPurchase=mats.reduce((a,x)=>a+Number(x.purchase||0),0),totalSale=mats.reduce((a,x)=>a+Number(x.sale||0),0);c.innerHTML=`<div class="gamaPMCards"><div class="gamaPMStat"><small>Referencias en matriz</small><strong>${mats.length}</strong></div><div class="gamaPMStat"><small>Compra total</small><strong>${money(totalPurchase)}</strong></div><div class="gamaPMStat"><small>Venta total calculada</small><strong>${money(totalSale)}</strong></div></div><div class="gamaPMForm" style="margin-bottom:12px"><h3>Agregar / recalcular una referencia</h3><div class="gamaPMMatrixInputs"><div><label>Producto *</label><select id="matProduct"><option value="">Seleccionar producto</option>${ps.map(p=>`<option value="${esc(p.barcode||p.id||p.name)}">${esc(p.name)}${p.barcode?' · '+esc(p.barcode):''}</option>`).join('')}</select></div><div><label>Proveedor</label><select id="matSupplier"><option value="">Sin proveedor</option>${sups.map(x=>`<option value="${esc(x.id)}">${esc(x.name)}</option>`).join('')}</select></div><div><label>Precio de compra unitario (USD) *</label><input id="matPurchase" type="number" min="0" step="0.01" placeholder="0.00"></div><div><label>Margen comercial objetivo (%)</label><input id="matMargin" type="number" min="0" max="99.99" step="0.1" value="30"></div></div><div class="gamaPMFormula">Precio de reventa automático = precio de compra ÷ (1 − margen objetivo). <strong id="matPreview">$0.00</strong></div><div class="gamaPMBtns"><button class="primary" id="matAdd">＋ Añadir a la matriz</button><button class="secondary" id="matClear">Reiniciar</button></div></div><div class="gamaPMForm"><h3>Matriz compra / reventa</h3><input class="gamaPMSearch" id="matSearch" placeholder="Buscar un producto..."><div class="gamaPMTable"><table><thead><tr><th>Producto</th><th>Proveedor</th><th>Compra</th><th>Margen</th><th>Reventa auto</th><th>Beneficio</th><th>Acciones</th></tr></thead><tbody id="matRows"></tbody></table></div></div>`;const recalc=()=>{const p=Number($('matPurchase').value||0),m=Number($('matMargin').value||0),sale=m>=100?0:p/(1-m/100);$('matPreview').textContent=money(sale)};$('matPurchase').oninput=recalc;$('matMargin').oninput=recalc;recalc();const renderRows=()=>{const q=($('matSearch')?.value||'').toLowerCase();const data=load(MAT_KEY).filter(x=>x.name.toLowerCase().includes(q));$('matRows').innerHTML=data.length?GamaPage.slice('matrix',data).map(x=>{const profit=Number(x.sale)-Number(x.purchase);const supplier=sups.find(s=>s.id===x.supplierId);return `<tr><td><b>${esc(x.name)}</b><br><span class="muted">${esc(x.barcode||'')}</span></td><td>${esc(supplier?.name||'—')}</td><td>${money(x.purchase)}</td><td class="${Number(x.margin)>=0?'gamaPMGood':'gamaPMWarn'}">${Number(x.margin).toFixed(1)}%</td><td><b>${money(x.sale)}</b></td><td class="${profit>=0?'gamaPMGood':'gamaPMWarn'}">${money(profit)}</td><td><button class="danger gamaPMIconBtn" data-matdel="${x.id}">Eliminar</button></td></tr>`}).join('')+(GamaPage.controls('matrix',data.length)?`<tr><td colspan="7">${GamaPage.controls('matrix',data.length)}</td></tr>`:''):'<tr><td colspan="7"><div class="gamaPMEmpty">Ninguna referencia en la matriz.</div></td></tr>';document.querySelectorAll('[data-matdel]').forEach(b=>b.onclick=()=>{save(MAT_KEY,load(MAT_KEY).filter(x=>x.id!==b.dataset.matdel));renderMatrix()})};$('matAdd').onclick=()=>{const key=$('matProduct').value,p=ps.find(x=>String(x.barcode||x.id||x.name)===String(key)),purchase=Number($('matPurchase').value||0),margin=Number($('matMargin').value||0);if(!p||purchase<=0)return alert('Selecciona un producto y un precio de compra válido.');if(margin<0||margin>=100)return alert('El margen debe estar entre 0 y 99,9 %.');const sale=purchase/(1-margin/100);const a=load(MAT_KEY).filter(x=>x.barcode!==String(p.barcode||'')||x.name!==p.name);a.push({id:crypto.randomUUID?crypto.randomUUID():Date.now().toString(),barcode:p.barcode||'',name:p.name,purchase,margin,sale,supplierId:$('matSupplier').value});save(MAT_KEY,a);renderMatrix()};$('matClear').onclick=()=>{$('matProduct').value='';$('matSupplier').value='';$('matPurchase').value='';$('matMargin').value='30';recalc()};$('matSearch').oninput=()=>{GamaPage.reset('matrix');renderRows()};GamaPage.register('matrix',renderRows);renderRows()}
/* Aquí vivía patchMenu(): buscaba la tarjeta «Configuración» del menú, le
   cambiaba el nombre a «Matriz comercial» y le robaba el clic, con un
   MutationObserver que lo repetía en cada cambio del DOM por si el menú se
   repintaba. El efecto secundario era que Configuración no se podía abrir
   desde ninguna parte. Matriz comercial tiene ahora su propia entrada en
   gama-menu-final2.js, que es donde se declaran las demás. */
function hook(){injectStyles();section('matrix','📊 Matriz comercial',MAT_LEAD);fetchSuppliers().then(s=>{cloudSuppliers=s}).catch(()=>{});const old=window.showTab;if(old&&!old.__gamaPM){window.showTab=function(id,el){if(id==='suppliers')renderSuppliers();if(id==='matrix')renderMatrix();return old.apply(this,arguments)};window.showTab.__gamaPM=true}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,50),{once:true});else setTimeout(hook,50);
})();