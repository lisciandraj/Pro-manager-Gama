/* GAMA — Tarifas por año de contrato.
   Una tarifa agrupa a todos los clientes que firmaron el mismo año: se
   mantiene una rejilla, no una por cliente. Sólo se listan los productos cuyo
   precio difiere del precio base de la ficha; el resto cae en ese precio base,
   así una tarifa nueva no obliga a reescribir todo el catálogo. */
(function(){
'use strict';
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const num=v=>{const n=parseFloat(String(v).replace(',','.'));return Number.isFinite(n)&&n>=0?n:null};

let lists=[],items=[],products=[],customers=[],selected=null,busy=false;

function msg(t,err){const m=$('plMsg');if(!m)return;m.className='plMsg'+(err?' plErr':' plOk');m.textContent=t;if(!t)m.className='plMsg'}
function fail(e,what){console.warn('[GAMA Tarifas]',what,e);msg(what+' : '+(e&&(e.message||e.details)||e),true)}

async function load(){
 const api=C();if(!api){msg('La conexión con la nube de GAMA no está disponible.',true);return}
 try{
  const [l,p,c]=await Promise.all([
   api.list('price_lists',{order:'year',ascending:false}),
   api.list('products',{select:'id,name,sale_price,active',order:'name',ascending:true}),
   api.list('customers',{order:'name',ascending:true}),
  ]);
  if(l.error)throw l.error;
  lists=l.data||[];
  products=(p.data||[]).filter(x=>x.active!==false);
  customers=(c.data||[]).filter(x=>x.active!==false);
  if(selected&&!lists.some(x=>x.id===selected))selected=null;
  if(!selected&&lists.length)selected=lists[0].id;
  await loadItems();
  render();
 }catch(e){fail(e,'No se pudieron cargar las tarifas')}
}
async function loadItems(){
 items=[];
 if(!selected)return;
 const r=await C().list('price_list_items',{eq:{price_list_id:selected}});
 if(r.error)throw r.error;
 items=r.data||[];
}
function productName(id){const p=products.find(x=>x.id===id);return p?p.name:'(producto archivado)'}
function basePrice(id){const p=products.find(x=>x.id===id);return p?Number(p.sale_price||0):0}

/* ---- acciones ---- */
async function createList(){
 const name=$('plName').value.trim(),year=parseInt($('plYear').value,10);
 if(!name)return msg('Pon un nombre a la tarifa, por ejemplo «Tarifa 2024».',true);
 try{
  const r=await C().insert('price_lists',{name,year:Number.isFinite(year)?year:null,active:true});
  if(r.error)throw r.error;
  selected=r.data.id;$('plName').value='';$('plYear').value='';
  msg('Tarifa «'+name+'» creada.');
  await load();
 }catch(e){fail(e,'No se pudo crear la tarifa')}
}
async function selectList(id){selected=id;msg('');try{await loadItems();render()}catch(e){fail(e,'No se pudo abrir la tarifa')}}
async function archiveList(id){
 const l=lists.find(x=>x.id===id);if(!l)return;
 if(!confirm('¿Archivar la tarifa «'+l.name+'»?\n\nLos clientes que la tengan asignada volverán al precio base.'))return;
 try{const r=await C().update('price_lists',id,{active:false});if(r.error)throw r.error;await load()}
 catch(e){fail(e,'No se pudo archivar')}
}
async function restoreList(id){
 try{const r=await C().update('price_lists',id,{active:true});if(r.error)throw r.error;await load()}
 catch(e){fail(e,'No se pudo restaurar')}
}
/* Se usa upsert porque la clave es (tarifa, producto): volver a poner precio a
   un producto ya listado debe corregirlo, no fallar por duplicado. */
async function setItemPrice(productId,value){
 const price=num(value);
 if(price===null)return msg('Precio inválido.',true);
 try{
  const r=await C().upsert('price_list_items',{price_list_id:selected,product_id:productId,unit_price:price},{onConflict:'price_list_id,product_id'});
  if(r.error)throw r.error;
  await loadItems();render();msg('Precio actualizado.');
 }catch(e){fail(e,'No se pudo guardar el precio')}
}
async function addItem(){
 const pid=$('plProduct').value,price=num($('plPrice').value);
 if(!pid)return msg('Elige un producto.',true);
 if(price===null)return msg('Indica un precio válido.',true);
 await setItemPrice(pid,price);
 $('plPrice').value='';
}
async function removeItem(productId){
 try{
  const c=await C().db();
  const r=await c.from('price_list_items').delete().eq('price_list_id',selected).eq('product_id',productId);
  if(r.error)throw r.error;
  await loadItems();render();msg('Producto retirado de la tarifa: vuelve al precio base.');
 }catch(e){fail(e,'No se pudo retirar el producto')}
}
async function assignCustomer(id,listId){
 try{const r=await C().update('customers',id,{price_list_id:listId||null});if(r.error)throw r.error;await load()}
 catch(e){fail(e,'No se pudo asignar la tarifa')}
}

/* ---- pantalla ---- */
function section(){
 let s=$('price-lists');
 if(!s){s=document.createElement('section');s.id='price-lists';(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
function css(){
 if($('plCss'))return;
 const s=document.createElement('style');s.id='plCss';
 s.textContent=`#price-lists .plGrid{display:grid;grid-template-columns:320px 1fr;gap:12px;align-items:start}
#price-lists .card{background:#fff;border:1px solid var(--gama-line,#c9d6df);border-radius:14px;padding:16px;margin-bottom:12px}
.plList{background:#fff;border:1px solid #e4ebee;border-radius:11px;overflow:hidden;margin-bottom:12px}
.plItem{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:11px 12px;border-bottom:1px solid #edf1f2;cursor:pointer}
.plItem:last-child{border-bottom:0}
.plItem.on{background:#e8f5f6}
.plItem b{display:block;font-size:13px}
.plItem small{color:#7b8992;font-size:11px}
.plItem.off b{color:#8c99a3;text-decoration:line-through}
.plMsg{margin:10px 0;font-size:13px}
.plMsg.plOk{color:#138a69}.plMsg.plErr{color:#c94f45;font-weight:700}
.plRow{display:grid;grid-template-columns:1fr 120px auto;gap:8px;align-items:end}
.plTable{width:100%;border-collapse:collapse;margin-top:10px}
.plTable th,.plTable td{padding:9px;border-bottom:1px solid #edf1f2;text-align:left;font-size:12px}
.plTable th{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:#71808a;background:#f8fafb}
.plTable input{width:110px;padding:6px;text-align:right}
.plDelta{font-weight:800}.plDelta.up{color:#138a69}.plDelta.down{color:#c94f45}
.plEmpty{padding:20px;text-align:center;color:#81909a}
@media(max-width:900px){#price-lists .plGrid{grid-template-columns:1fr}.plRow{grid-template-columns:1fr}.plRow button{width:100%;margin-top:6px}}`;
 document.head.appendChild(s);
}
function render(){
 css();
 const s=section(),cur=lists.find(x=>x.id===selected)||null;
 const mine=cur?customers.filter(c=>c.price_list_id===cur.id):[];
 const listed=new Set(items.map(i=>i.product_id));
 s.innerHTML=`${window.GamaUI.header({title:'🏷️ Tarifas por año de contrato',lead:'Precios pactados por año de contrato.'})}
 <div id="plMsg" class="plMsg"></div>
 <div class="plGrid">
  <div>
   <div class="card">
    <h3>Nueva tarifa</h3>
    <label>Nombre</label><input id="plName" placeholder="Tarifa 2024">
    <label>Año de firma</label><input id="plYear" type="number" min="2000" max="2100" placeholder="2024">
    <button class="primary" id="plCreate" style="margin-top:10px;width:100%">＋ Crear tarifa</button>
   </div>
   <div class="plList">${lists.length?lists.map(l=>`<div class="plItem${l.id===selected?' on':''}${l.active===false?' off':''}" data-pick="${esc(l.id)}">
     <div><b>${esc(l.name)}</b><small>${l.year||'sin año'} · ${customers.filter(c=>c.price_list_id===l.id).length} cliente(s)</small></div>
     <button class="secondary" data-${l.active===false?'restore':'archive'}="${esc(l.id)}">${l.active===false?'♻️':'🗄️'}</button>
    </div>`).join(''):'<div class="plEmpty">Aún no hay tarifas.</div>'}</div>
  </div>
  <div>${cur?renderDetail(cur,mine,listed):'<div class="card"><div class="plEmpty">Crea o elige una tarifa a la izquierda.</div></div>'}</div>
 </div>`;
 bind();
}
function renderDetail(cur,mine,listed){
 const free=products.filter(p=>!listed.has(p.id));
 return `<div class="card">
  <h3>${esc(cur.name)} — precios</h3>
  <div class="plRow" style="margin-top:8px">
   <div><label>Producto</label><select id="plProduct">${free.length?free.map(p=>`<option value="${esc(p.id)}">${esc(p.name)} — base ${money(p.sale_price)}</option>`).join(''):'<option value="">Todos los productos ya tienen precio</option>'}</select></div>
   <div><label>Precio de esta tarifa</label><input id="plPrice" type="number" min="0" step="0.01" placeholder="0.00"></div>
   <div><button class="primary" id="plAdd">Añadir</button></div>
  </div>
  ${items.length?`<table class="plTable"><thead><tr><th>Producto</th><th>Precio base</th><th>Precio tarifa</th><th>Diferencia</th><th></th></tr></thead><tbody>
   ${items.slice().sort((a,b)=>productName(a.product_id).localeCompare(productName(b.product_id),'es')).map(i=>{
     const base=basePrice(i.product_id),d=Number(i.unit_price)-base;
     const pct=base>0?(d/base*100):0;
     return `<tr><td>${esc(productName(i.product_id))}</td><td>${money(base)}</td>
      <td><input type="number" min="0" step="0.01" value="${Number(i.unit_price)}" data-price="${esc(i.product_id)}"></td>
      <td class="plDelta ${d>0?'up':d<0?'down':''}">${d===0?'—':(d>0?'+':'')+money(d)+(base>0?` (${pct>0?'+':''}${pct.toFixed(1)}%)`:'')}</td>
      <td><button class="danger" data-drop="${esc(i.product_id)}">×</button></td></tr>`}).join('')}
   </tbody></table>`:'<div class="plEmpty">Ningún precio específico todavía: todo se factura al precio base.</div>'}
 </div>
 <div class="card">
  <h3>Clientes con esta tarifa <small class="muted">(${mine.length})</small></h3>
  <div class="plRow" style="margin-top:8px">
   <div><label>Añadir un cliente</label><select id="plCustomer"><option value="">Selecciona…</option>${customers.filter(c=>c.price_list_id!==cur.id).map(c=>`<option value="${esc(c.id)}">${esc(c.name)}${c.price_list_id?' — hoy en otra tarifa':''}</option>`).join('')}</select></div>
   <div></div><div><button class="primary" id="plAssign">Asignar</button></div>
  </div>
  ${mine.length?`<table class="plTable"><tbody>${mine.map(c=>`<tr><td>${esc(c.name)}<br><small class="muted">${esc(c.email||'sin correo')}</small></td><td style="text-align:right"><button class="secondary" data-unassign="${esc(c.id)}">Quitar</button></td></tr>`).join('')}</tbody></table>`:'<div class="plEmpty">Ningún cliente usa esta tarifa todavía.</div>'}
 </div>`;
}
function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
 s.querySelectorAll('[data-pick]').forEach(el=>el.onclick=e=>{if(e.target.closest('button'))return;selectList(el.dataset.pick)});
 s.querySelectorAll('[data-archive]').forEach(b=>b.onclick=e=>{e.stopPropagation();archiveList(b.dataset.archive)});
 s.querySelectorAll('[data-restore]').forEach(b=>b.onclick=e=>{e.stopPropagation();restoreList(b.dataset.restore)});
 const c=$('plCreate');if(c)c.onclick=createList;
 const a=$('plAdd');if(a)a.onclick=addItem;
 s.querySelectorAll('[data-price]').forEach(i=>i.onchange=()=>setItemPrice(i.dataset.price,i.value));
 s.querySelectorAll('[data-drop]').forEach(b=>b.onclick=()=>removeItem(b.dataset.drop));
 const as=$('plAssign');if(as)as.onclick=()=>{const v=$('plCustomer').value;if(!v)return msg('Elige un cliente.',true);assignCustomer(v,selected)};
 s.querySelectorAll('[data-unassign]').forEach(b=>b.onclick=()=>assignCustomer(b.dataset.unassign,null));
}
async function open(){
 css();
 const s=section();
 document.querySelectorAll('section').forEach(x=>{const on=x.id==='price-lists';x.classList.toggle('active',on);x.hidden=!on;x.style.display=on?'block':'none'});
 document.getElementById('mainmenu')?.setAttribute('hidden','');
 if(busy)return;busy=true;
 s.innerHTML='<div class="wrap"><div class="card"><div class="plEmpty">Cargando tarifas…</div></div></div>';
 try{await load()}finally{busy=false}
 window.scrollTo({top:0,behavior:'smooth'});
}
window.GamaOpenPriceLists=open;
window.gamaPriceLists={open};
})();
