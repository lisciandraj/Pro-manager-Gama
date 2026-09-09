/* GAMA — Tarifas especiales.
   Un precio negociado vale para UN cliente y UN producto: no hay rejillas
   compartidas ni años de contrato. Sólo se listan aquí los productos cuyo
   precio se pactó aparte; todo lo demás cae en el precio de la ficha según la
   categoría del cliente, así que pactar un precio nunca obliga a reescribir el
   catálogo entero. Sólo los clientes de categoría C tienen precios especiales. */
(function(){
'use strict';
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const num=v=>{const n=parseFloat(String(v).replace(',','.'));return Number.isFinite(n)&&n>=0?n:null};

let customers=[],products=[],items=[],selected=null,busy=false;

function msg(t,err){const m=$('plMsg');if(!m)return;m.className='plMsg'+(err?' plErr':' plOk');m.textContent=t;if(!t)m.className='plMsg'}
function fail(e,what){console.warn('[GAMA Tarifas]',what,e);msg(what+' : '+(e&&(e.message||e.details)||e),true)}

async function load(){
 const api=C();if(!api){msg('La conexión con la nube de GAMA no está disponible.',true);return}
 try{
  const [c,p]=await Promise.all([
   api.list('customers',{order:'name',ascending:true}),
   api.list('products',{select:'id,name,sale_price,sale_price_b,active',order:'name',ascending:true}),
  ]);
  if(c.error)throw c.error;
  if(p.error)throw p.error;
  customers=(c.data||[]).filter(x=>x.active!==false&&(x.category||'A')==='C');
  products=(p.data||[]).filter(x=>x.active!==false);
  if(selected&&!customers.some(x=>x.id===selected))selected=null;
  await loadItems();
  render();
 }catch(e){fail(e,'No se pudieron cargar las tarifas especiales')}
}
async function loadItems(){
 items=[];
 if(!selected)return;
 const r=await C().list('customer_special_prices',{eq:{customer_id:selected}});
 if(r.error)throw r.error;
 items=r.data||[];
}
function productName(id){const p=products.find(x=>x.id===id);return p?p.name:'(producto archivado)'}
/* El precio de referencia es el que pagaría ese cliente sin nada pactado: el
   mayorista de la ficha, porque la categoría C cae ahí por defecto. */
function basePrice(id){const p=products.find(x=>x.id===id);return p?Number(p.sale_price||0):0}

/* ---- acciones ---- */
function selectCustomer(id){selected=id;msg('');(async()=>{try{await loadItems();render()}catch(e){fail(e,'No se pudo abrir el cliente')}})()}
/* Se usa upsert porque la clave es (cliente, producto): volver a poner precio
   a un producto ya pactado debe corregirlo, no fallar por duplicado. */
async function setItemPrice(productId,value){
 const price=num(value);
 if(price===null)return msg('Precio inválido.',true);
 if(!selected)return msg('Elige un cliente.',true);
 try{
  const r=await C().upsert('customer_special_prices',{customer_id:selected,product_id:productId,unit_price:price},{onConflict:'customer_id,product_id'});
  if(r.error)throw r.error;
  await loadItems();render();msg('Precio especial actualizado.');
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
  const r=await c.from('customer_special_prices').delete().eq('customer_id',selected).eq('product_id',productId);
  if(r.error)throw r.error;
  await loadItems();render();msg('Precio especial retirado: el producto vuelve al precio mayorista.');
 }catch(e){fail(e,'No se pudo retirar el precio especial')}
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
 const s=section(),cur=customers.find(x=>x.id===selected)||null;
 const listed=new Set(items.map(i=>i.product_id));
 s.innerHTML=`${window.GamaUI.header({title:'🏷️ Tarifas especiales',lead:'Precios negociados por cliente y producto.'})}
 <div id="plMsg" class="plMsg"></div>
 <div class="plGrid">
  <div>
   <div class="card">
    <h3>Clientes de categoría C</h3>
    <p class="muted">Sólo un cliente de categoría C tiene precios negociados. La categoría se asigna en su ficha, en 👥 Clientes.</p>
   </div>
   <div class="plList">${customers.length?customers.map(c=>`<div class="plItem${c.id===selected?' on':''}" data-pick="${esc(c.id)}">
     <div><b>${esc(c.name)}</b><small>${esc(c.identification||'sin identificación')}</small></div>
    </div>`).join(''):'<div class="plEmpty">Ningún cliente de categoría C todavía.</div>'}</div>
  </div>
  <div>${cur?renderDetail(cur,listed):'<div class="card"><div class="plEmpty">Elige un cliente a la izquierda.</div></div>'}</div>
 </div>`;
 bind();
}
function renderDetail(cur,listed){
 const free=products.filter(p=>!listed.has(p.id));
 return `<div class="card">
  <h3>${esc(cur.name)} — precios negociados</h3>
  <div class="plRow" style="margin-top:8px">
   <div><label>Producto</label><select id="plProduct">${free.length?free.map(p=>`<option value="${esc(p.id)}">${esc(p.name)} — mayorista ${money(p.sale_price)}</option>`).join(''):'<option value="">Todos los productos ya tienen precio pactado</option>'}</select></div>
   <div><label>Precio negociado</label><input id="plPrice" type="number" min="0" step="0.01" placeholder="0.00"></div>
   <div><button class="primary" id="plAdd">Añadir</button></div>
  </div>
  ${items.length?`<table class="plTable"><thead><tr><th>Producto</th><th>Precio mayorista</th><th>Precio negociado</th><th>Diferencia</th><th></th></tr></thead><tbody>
   ${items.slice().sort((a,b)=>productName(a.product_id).localeCompare(productName(b.product_id),'es')).map(i=>{
     const base=basePrice(i.product_id),d=Number(i.unit_price)-base;
     const pct=base>0?(d/base*100):0;
     return `<tr><td>${esc(productName(i.product_id))}</td><td>${money(base)}</td>
      <td><input type="number" min="0" step="0.01" value="${Number(i.unit_price)}" data-price="${esc(i.product_id)}"></td>
      <td class="plDelta ${d>0?'up':d<0?'down':''}">${d===0?'—':(d>0?'+':'')+money(d)+(base>0?` (${pct>0?'+':''}${pct.toFixed(1)}%)`:'')}</td>
      <td><button class="danger" data-drop="${esc(i.product_id)}">×</button></td></tr>`}).join('')}
   </tbody></table>`:'<div class="plEmpty">Ningún precio negociado todavía: todo se le factura al precio mayorista de la ficha.</div>'}
 </div>`;
}
function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
 s.querySelectorAll('[data-pick]').forEach(el=>el.onclick=e=>{if(e.target.closest('button'))return;selectCustomer(el.dataset.pick)});
 const a=$('plAdd');if(a)a.onclick=addItem;
 s.querySelectorAll('[data-price]').forEach(i=>i.onchange=()=>setItemPrice(i.dataset.price,i.value));
 s.querySelectorAll('[data-drop]').forEach(b=>b.onclick=()=>removeItem(b.dataset.drop));
}
async function open(){
 css();
 const s=section();
 document.querySelectorAll('section').forEach(x=>{const on=x.id==='price-lists';x.classList.toggle('active',on);x.hidden=!on;x.style.display=on?'block':'none'});
 document.getElementById('mainmenu')?.setAttribute('hidden','');
 if(busy)return;busy=true;
 s.innerHTML='<div class="wrap"><div class="card"><div class="plEmpty">Cargando tarifas especiales…</div></div></div>';
 try{await load()}finally{busy=false}
 window.scrollTo({top:0,behavior:'smooth'});
}
window.GamaOpenPriceLists=open;
window.gamaPriceLists={open};
})();
