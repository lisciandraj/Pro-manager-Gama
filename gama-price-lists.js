/* GAMA — Tarifas especiales.

   Dos mitades del mismo trato, cada una en su pestaña:

   · Clientes: lo que se le vende a UN cliente y UN producto por debajo o por
     encima de su categoría. Sólo los clientes de categoría C tienen precios
     pactados; los demás pagan el precio de la ficha.
   · Proveedores: lo que se le COMPRA a UN proveedor y UN producto según su
     contrato. Cuando el proveedor manda una tarifa nueva se vuelve a subir
     desde 📥 Importación Excel y aquí se corrige a mano lo que haga falta.

   En las dos, sólo se listan los productos cuyo precio se pactó aparte. Todo
   lo demás cae en el precio de la ficha, así que pactar un precio nunca obliga
   a reescribir el catálogo entero. */
(function(){
'use strict';
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const num=v=>{const n=parseFloat(String(v).replace(',','.'));return Number.isFinite(n)&&n>=0?n:null};

/* Lo único que cambia entre las dos pestañas está aquí: de quién es la lista,
   en qué tabla vive el precio pactado, y con qué precio de la ficha se compara.
   El resto de la pantalla es el mismo código para las dos. */
const MODOS={
 clientes:{
  parte:'customer_id', tabla:'customer_special_prices', precio:'unit_price',
  titulo:'Clientes de categoría C',
  ayuda:'Sólo un cliente de categoría C tiene precios negociados. La categoría se asigna en su ficha, en 👥 Clientes.',
  vacio:'Ningún cliente de categoría C todavía.',
  detalle:'precios negociados', colBase:'Precio mayorista', colPactado:'Precio negociado',
  fichaPrecio:p=>Number(p.sale_price||0),
  sinNada:'Ningún precio negociado todavía: todo se le factura al precio mayorista de la ficha.',
  retirado:'Precio especial retirado: el producto vuelve al precio mayorista.',
 },
 proveedores:{
  parte:'supplier_id', tabla:'supplier_contract_prices', precio:'unit_cost',
  titulo:'Proveedores',
  ayuda:'El precio de contrato manda sobre el precio de compra de la ficha. Se cargan de golpe desde 📥 Importación Excel y se corrigen aquí cuando el contrato cambia.',
  vacio:'Todavía no hay proveedores.',
  detalle:'precios de contrato', colBase:'Precio de compra', colPactado:'Precio de contrato',
  fichaPrecio:p=>Number(p.purchase_price||0),
  sinNada:'Ningún precio de contrato todavía: todo se compra al precio de la ficha.',
  retirado:'Precio de contrato retirado: el producto vuelve al precio de compra de la ficha.',
 },
};

let tab='clientes';
let customers=[],suppliers=[],products=[],items=[],busy=false;
let elegido={clientes:null,proveedores:null};

const modo=()=>MODOS[tab];
const parte=()=>tab==='clientes'?customers:suppliers;
const seleccionado=()=>elegido[tab];

function msg(t,err){const m=$('plMsg');if(!m)return;m.className='plMsg'+(err?' plErr':' plOk');m.textContent=t;if(!t)m.className='plMsg'}
function fail(e,what){console.warn('[GAMA Tarifas]',what,e);msg(what+' : '+(e&&(e.message||e.details)||e),true)}

async function load(){
 const api=C();if(!api){msg('La conexión con la nube de GAMA no está disponible.',true);return}
 try{
  const [c,s,p]=await Promise.all([
   api.list('customers',{order:'name',ascending:true}),
   api.list('suppliers',{select:'id,name,tax_id,active',order:'name',ascending:true}),
   /* purchase_price hace falta para la pestaña de proveedores: es el precio de
      la ficha contra el que se compara lo pactado. Las columnas se piden una a
      una porque products guarda además la foto en base64. */
   api.list('products',{select:'id,name,sale_price,sale_price_b,purchase_price,active',order:'name',ascending:true}),
  ]);
  if(c.error)throw c.error;
  if(p.error)throw p.error;
  customers=(c.data||[]).filter(x=>x.active!==false&&(x.category||'A')==='C');
  /* Un fallo al leer proveedores no puede tumbar la pestaña de clientes: son
     dos permisos distintos y la pantalla sirve para las dos cosas. */
  suppliers=s.error?[]:(s.data||[]).filter(x=>x.active!==false);
  products=(p.data||[]).filter(x=>x.active!==false);
  Object.keys(MODOS).forEach(k=>{
   const lista=k==='clientes'?customers:suppliers;
   if(elegido[k]&&!lista.some(x=>x.id===elegido[k]))elegido[k]=null;
  });
  await loadItems();
  render();
 }catch(e){fail(e,'No se pudieron cargar las tarifas especiales')}
}
async function loadItems(){
 items=[];
 const id=seleccionado();
 if(!id)return;
 const m=modo();
 const r=await C().list(m.tabla,{eq:{[m.parte]:id}});
 if(r.error)throw r.error;
 items=r.data||[];
}
function precioDe(i){return Number(i[modo().precio]||0)}
function productName(id){const p=products.find(x=>x.id===id);return p?p.name:'(producto archivado)'}
/* El precio de referencia es el que se aplicaría sin nada pactado: el de la
   ficha. Al vender, el mayorista —la categoría C cae ahí por defecto—; al
   comprar, el precio de compra. */
function basePrice(id){const p=products.find(x=>x.id===id);return p?modo().fichaPrecio(p):0}

/* ---- acciones ---- */
function selectTab(t){if(!MODOS[t]||t===tab)return;tab=t;msg('');(async()=>{try{await loadItems();render()}catch(e){fail(e,'No se pudo abrir la pestaña')}})()}
function selectParte(id){elegido[tab]=id;msg('');(async()=>{try{await loadItems();render()}catch(e){fail(e,'No se pudo abrir la ficha')}})()}
/* Se usa upsert porque la clave es (parte, producto): volver a poner precio a
   un producto ya pactado debe corregirlo, no fallar por duplicado. Es también
   lo que hace que volver a subir la tarifa del proveedor actualice en vez de
   duplicar. */
async function setItemPrice(productId,value){
 const price=num(value);
 if(price===null)return msg('Precio inválido.',true);
 const id=seleccionado();
 if(!id)return msg('Elige una ficha de la lista.',true);
 const m=modo();
 try{
  const fila={[m.parte]:id,product_id:productId,[m.precio]:price};
  const r=await C().upsert(m.tabla,fila,{onConflict:m.parte+',product_id'});
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
 const m=modo();
 try{
  const c=await C().db();
  const r=await c.from(m.tabla).delete().eq(m.parte,seleccionado()).eq('product_id',productId);
  if(r.error)throw r.error;
  await loadItems();render();msg(m.retirado);
 }catch(e){fail(e,'No se pudo retirar el precio')}
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
 s.textContent=`#price-lists .plGrid{display:grid;grid-template-columns:320px minmax(0,1fr);gap:12px;align-items:start}
#price-lists .card{background:#fff;border:1px solid var(--gama-line,#c9d6df);border-radius:14px;padding:16px;margin-bottom:12px}
.plTabs{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:14px}
.plTabs button{background:#fff;border:1px solid #c9d6df;color:#18324a;border-radius:999px;padding:10px 16px;font-weight:800;cursor:pointer;width:auto}
.plTabs button.on{background:#087c8b;border-color:#087c8b;color:#fff}
.plList{background:#fff;border:1px solid #e4ebee;border-radius:11px;overflow:hidden;margin-bottom:12px}
.plItem{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:11px 12px;border-bottom:1px solid #edf1f2;cursor:pointer}
.plItem:last-child{border-bottom:0}
.plItem.on{background:#e8f5f6}
.plItem b{display:block;font-size:13px}
.plItem small{color:#7b8992;font-size:11px}
.plMsg{margin:10px 0;font-size:13px}
.plMsg.plOk{color:#138a69}.plMsg.plErr{color:#c94f45;font-weight:700}
.plRow{display:grid;grid-template-columns:1fr 120px auto;gap:8px;align-items:end}
.plTableWrap{width:100%;overflow-x:auto;margin-top:10px}
/* min-width:min-content en vez de una anchura fija: con 520 px clavados, si
   las columnas pedían más, las celdas se salían por la derecha sin que el
   contenedor contara ese sobrante como algo que desplazar. */
.plTable{width:100%;min-width:min-content;border-collapse:collapse}
.plBtnTxt{display:none}
.plTable th,.plTable td{padding:9px;border-bottom:1px solid #edf1f2;text-align:left;font-size:12px}
.plTable th{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:#71808a;background:#f8fafb}
.plTable input{width:110px;padding:6px;text-align:right}
.plDelta{font-weight:800}.plDelta.up{color:#138a69}.plDelta.down{color:#c94f45}
.plContrato{display:block;color:#7b8992;font-size:10.5px}
.plEmpty{padding:20px;text-align:center;color:#81909a}
@media(max-width:900px){#price-lists .plGrid{grid-template-columns:minmax(0,1fr)}.plRow{grid-template-columns:1fr}.plRow button{width:100%;margin-top:6px}}
/* Las fichas del teléfono las pone gama-tables.js para todas las tablas de la
   aplicación. Aquí sólo queda lo propio: el ancho que necesita la etiqueta más
   larga —«PRECIO NEGOCIADO», que partida en dos se leía peor que el dato— y la
   palabra del botón de retirar, que en la tabla sobra porque su columna no
   tiene título y basta la ×. */
@media(max-width:760px){.plTable{--gamaCardsLabel:132px}
 .plBtnTxt{display:inline}
}`;
 document.head.appendChild(s);
}
function render(){
 css();
 const s=section(),m=modo(),lista=parte(),cur=lista.find(x=>x.id===seleccionado())||null;
 const listed=new Set(items.map(i=>i.product_id));
 s.innerHTML=`${window.GamaUI.header({title:'🏷️ Tarifas especiales',lead:'Precios pactados por cliente y por proveedor.'})}
 <div class="plTabs">
  <button type="button" class="${tab==='clientes'?'on':''}" data-tab="clientes">👥 Clientes</button>
  <button type="button" class="${tab==='proveedores'?'on':''}" data-tab="proveedores">🚚 Proveedores</button>
 </div>
 <div id="plMsg" class="plMsg"></div>
 <div class="plGrid">
  <div>
   <div class="card">
    <h3>${esc(m.titulo)}</h3>
    <p class="muted">${esc(m.ayuda)}</p>
   </div>
   <div class="plList">${lista.length?lista.map(x=>`<div class="plItem${x.id===seleccionado()?' on':''}" data-pick="${esc(x.id)}">
     <div><b>${esc(x.name)}</b><small>${esc(x.identification||x.tax_id||'sin identificación')}</small></div>
    </div>`).join(''):`<div class="plEmpty">${esc(m.vacio)}</div>`}</div>
  </div>
  <div>${cur?renderDetail(cur,listed,m):'<div class="card"><div class="plEmpty">Elige una ficha a la izquierda.</div></div>'}</div>
 </div>`;
 bind();
}
function renderDetail(cur,listed,m){
 const free=products.filter(p=>!listed.has(p.id));
 return `<div class="card">
  <h3>${esc(cur.name)} — ${esc(m.detalle)}</h3>
  <div class="plRow" style="margin-top:8px">
   <div><label>Producto</label><select id="plProduct">${free.length?free.map(p=>`<option value="${esc(p.id)}">${esc(p.name)} — ${esc(m.colBase.toLowerCase())} ${money(m.fichaPrecio(p))}</option>`).join(''):'<option value="">Todos los productos ya tienen precio pactado</option>'}</select></div>
   <div><label>${esc(m.colPactado)}</label><input id="plPrice" type="number" min="0" step="0.01" placeholder="0.00"></div>
   <div><button class="primary" id="plAdd">Añadir</button></div>
  </div>
  ${items.length?`<div class="plTableWrap"><table class="plTable"><thead><tr><th>Producto</th><th>${esc(m.colBase)}</th><th>${esc(m.colPactado)}</th><th>Diferencia</th><th></th></tr></thead><tbody>
   ${items.slice().sort((a,b)=>productName(a.product_id).localeCompare(productName(b.product_id),'es')).map(i=>{
     const base=basePrice(i.product_id),d=precioDe(i)-base;
     const pct=base>0?(d/base*100):0;
     return `<tr><td>${esc(productName(i.product_id))}${i.contract_ref?`<small class="plContrato">Contrato ${esc(i.contract_ref)}</small>`:''}</td><td>${money(base)}</td>
      <td><input type="number" min="0" step="0.01" value="${precioDe(i)}" data-price="${esc(i.product_id)}" aria-label="${esc(m.colPactado)} de ${esc(productName(i.product_id))}"></td>
      <td class="plDelta ${d>0?'up':d<0?'down':''}">${d===0?'—':(d>0?'+':'')+money(d)+(base>0?` (${pct>0?'+':''}${pct.toFixed(1)}%)`:'')}</td>
      <td><button class="danger" data-drop="${esc(i.product_id)}" title="Retirar el precio pactado"><span aria-hidden="true">×</span><span class="plBtnTxt"> Retirar</span></button></td></tr>`}).join('')}
   </tbody></table></div>`:`<div class="plEmpty">${esc(m.sinNada)}</div>`}
 </div>`;
}
function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
 s.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>selectTab(b.dataset.tab));
 s.querySelectorAll('[data-pick]').forEach(el=>el.onclick=e=>{if(e.target.closest('button'))return;selectParte(el.dataset.pick)});
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
