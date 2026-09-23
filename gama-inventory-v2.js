/* GAMA — Almacenes y existencias (Inventario V2).

   El Inventario de siempre responde «cuánto hay». Esta pantalla responde las
   otras cuatro preguntas que hacen falta para trabajar: dónde está, cuánto de
   eso ya está comprometido, cuánto viene de camino y con qué me voy a quedar.

   De dónde sale cada cifra:

     On hand    SUM(stock_quants.quantity)              — lo que hay físicamente
     Reservado  SUM(stock_quants.reserved_quantity)     — comprometido, no vendible
     Disponible on hand − reservado
     Entrante   SUM(quantity − received_quantity) de las líneas de compra
                de órdenes en 'sent' o 'partial'
     Previsto   disponible + entrante
     Valor      on hand × products.purchase_price

   Nada de esto se calcula aquí para escribirlo: esta pantalla sólo LEE. Mover
   existencias es cosa de las RPC (gama_stock_transfer, gama_stock_adjust…),
   que son las únicas que tocan quants, products.stock y el historial a la vez
   y dentro de una transacción.

   Si las tablas de la V2 todavía no existen —la migración se aplica a mano—
   la pantalla lo dice y no rompe nada: el Inventario de siempre sigue donde
   estaba. */
(function(){
'use strict';
if(window.GamaInventoryV2)return;

const C=()=>window.GamaCloud,$=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const num=v=>Number(v||0).toLocaleString('es-EC',{maximumFractionDigits:2});

let almacenes=[],ubicaciones=[],quants=[],productos=[],entrante=[];
let reglas=[],proveedores=[],conteos=[],lineas=[],conteoAbierto=null,estanterias=[],estanteriaVista=null;
const T=s=>window.GamaI18n?.t?.(s)||s,tr=s=>`<span data-gi-live>${esc(s)}</span>`;
let serverSnapshot=null,snapshotRequest=0;
async function refreshSnapshot(){const n=++snapshotRequest;const warehouse=$('ivAlmacen')?.value||null,until=$('ivUntil')?.value||null;serverSnapshot=null;try{const result=await window.ArcData.rpc('gama_inventory_snapshot',{p_warehouse:warehouse,p_until:until});if(n===snapshotRequest)serverSnapshot={warehouse,until,rows:new Map(result.rows.map(r=>[r.id,r]))}}catch(e){if(n===snapshotRequest)console.warn('[Stock snapshot]',e)}}
let pestana='existencias',disponibleV2=null,cargando=false;

/* ---------- datos ---------- */

/* Las fotos son base64 y pesan: un inventario de mil productos no tiene por
   qué arrastrarlas. Se piden sólo las columnas que la tabla enseña. */
const COLUMNAS_PRODUCTO='id,name,reference,barcode,category,min_stock,max_stock,purchase_price,stock,active,location';

async function cargar(){
 if(cargando)return;
 cargando=true;
 try{
  const [w,l,q,p]=await Promise.all([
   C().list('warehouses',{order:'code',ascending:true}),
   C().list('warehouse_locations',{order:'code',ascending:true}),
   window.ArcData.all('stock_quants',{}),
   window.ArcData.all('products',{select:COLUMNAS_PRODUCTO,order:'name',ascending:true})
  ]);
  /* Si falta la tabla, PostgREST responde con error en vez de con filas. Es
     la señal de que la migración aún no está aplicada. */
  if(w.error||l.error||q.error){disponibleV2=false;return}
  disponibleV2=true;
  almacenes=w.data||[];ubicaciones=l.data||[];quants=q.data||[];
  productos=(p.data||[]).filter(x=>x.active!==false);
  const [rr,sp,cc,sh]=await Promise.all([
   window.ArcData.all('reorder_rules',{}),
   window.ArcData.all('suppliers',{select:'id,name'}),
   C().list('inventory_counts',{order:'created_at',ascending:false,limit:20}),
   C().list('warehouse_shelves',{order:'code',ascending:true})
  ]);
  estanterias=sh.error?[]:(sh.data||[]);
  /* Las tablas de las fases 5 y 6 pueden no estar aplicadas todavía: si
     faltan, esas dos pestañas se quedan vacías y el resto sigue igual. */
  reglas=rr.error?[]:(rr.data||[]);
  proveedores=sp.error?[]:(sp.data||[]);
  conteos=cc.error?null:(cc.data||[]);
  await cargarEntrante();
 }catch(e){console.warn('[GAMA Inventario V2]',e);disponibleV2=false}
 finally{cargando=false}
}

/* Entrante = lo pedido y aún no recibido de las órdenes abiertas. Un almacenero
   no puede leer purchase_orders —así lo dice su RLS—, y entonces esta cifra se
   queda en blanco en vez de mentir con un cero. */
async function cargarEntrante(){
 entrante=[];
 try{
  const [po,pol]=await Promise.all([
   window.ArcData.all('purchase_orders',{select:'id,status,expected_date,destination_location_id'}),
   window.ArcData.all('purchase_order_lines',{select:'id,product_id,quantity,received_quantity,purchase_order_id'})
  ]);
  if(po.error||pol.error){entrante=null;return}
  const abiertas=new Set((po.data||[]).filter(o=>o.status==='sent'||o.status==='partial').map(o=>o.id));
  (pol.data||[]).forEach(l=>{
   if(!abiertas.has(l.purchase_order_id))return;
   const falta=Number(l.quantity||0)-Number(l.received_quantity||0);
   if(falta>0){const order=(po.data||[]).find(o=>o.id===l.purchase_order_id);entrante.push({product_id:l.product_id,quantity:falta,location_id:order.destination_location_id,expected_date:order.expected_date})}
  });
 }catch(_){entrante=null}
}

const ubicacion=id=>ubicaciones.find(u=>u.id===id);
const almacenDe=locId=>{const u=ubicacion(locId);return u?almacenes.find(a=>a.id===u.warehouse_id):null};

/* Un producto con sus cifras y el desglose por ubicación. */
function resumen(p,filtroAlmacen){
 const suyos=quants.filter(q=>q.product_id===p.id&&(!filtroAlmacen||(almacenDe(q.location_id)||{}).id===filtroAlmacen));
 const onHand=suyos.reduce((s,q)=>s+Number(q.quantity||0),0);
 const reservado=suyos.reduce((s,q)=>s+Number(q.reserved_quantity||0),0);
 const until=$('ivUntil')?.value;const entra=entrante?entrante.filter(x=>x.product_id===p.id&&(!filtroAlmacen||(almacenDe(x.location_id)||{}).id===filtroAlmacen)&&(!until||(x.expected_date&&x.expected_date.slice(0,10)<=until))).reduce((n,x)=>n+x.quantity,0):null;
 const disp=onHand-reservado;const server=serverSnapshot&&serverSnapshot.warehouse===(filtroAlmacen||null)&&serverSnapshot.until===($('ivUntil')?.value||null)?serverSnapshot.rows.get(p.id):null;
 if(server)return {producto:p,onHand:Number(server.physical),reservado:Number(server.reserved),disponible:Number(server.available),entrante:server.incoming===null?null:Number(server.incoming),previsto:server.projected===null?null:Number(server.projected),minimo:Number(p.min_stock||0),maximo:Number(p.max_stock||0),costo:Number(p.purchase_price||0),valor:Number(server.current_cost_value),lineas:suyos};
 return {
  producto:p,onHand,reservado,disponible:disp,
  entrante:entra,previsto:entra===null?null:disp+entra,
  minimo:Number(p.min_stock||0),maximo:Number(p.max_stock||0),
  costo:Number(p.purchase_price||0),valor:onHand*Number(p.purchase_price||0),
  lineas:suyos
 };
}

function estado(r){
 if(r.onHand<=0)return {clase:'agotado',texto:'Sin stock'};
 if(r.minimo>0&&r.disponible<=r.minimo)return {clase:'bajo',texto:'Stock bajo'};
 if(r.maximo>0&&r.onHand>r.maximo)return {clase:'sobre',texto:'Sobre stock'};
 if(r.reservado>0)return {clase:'reservado',texto:'Con reservas'};
 return {clase:'ok',texto:'Disponible'};
}

/* ---------- estilos ---------- */

function css(){ /* Styles are compiled in architect-components.css. */ }

/* ---------- pantalla ---------- */

function seccion(){
 let sec=$('warehouses');
 if(!sec){sec=document.createElement('section');sec.id='warehouses';(document.querySelector('.wrap')||document.body).appendChild(sec)}
 return sec;
}

function pintar(){
 css();
 const sec=seccion();
 window.ArcUI.render(sec,window.GamaUI.header({
  title:'🏬 Almacenes y existencias',
  lead:'Dónde está cada producto y cuánto queda disponible.'
 })+`<div class="ivTabs">
<button class="arcButton" type="button" data-iv-tab="existencias" data-gi=51d1f9fcef5a>Existencias</button>
<button class="arcButton" type="button" data-iv-tab="transferencias" data-gi=7964b01de247>Transferencias</button>
<button class="arcButton" type="button" data-iv-tab="reabastecimiento" data-gi=b8d29c42edf0>Reabastecimiento</button>
<button class="arcButton" type="button" data-iv-tab="conteos" data-gi=50b30c964d90>Inventario físico</button>
<button class="arcButton" type="button" data-iv-tab="ubicaciones" data-gi=f2f6d7256e7e>Ubicaciones</button>
</div><div id="ivCuerpo"></div>`);
 window.GamaUI.bindBack(sec);
 sec.querySelectorAll('[data-iv-tab]').forEach(b=>{
  b.classList.toggle('active',b.dataset.ivTab===pestana);
  b.onclick=()=>{pestana=b.dataset.ivTab;pintar()};
 });
 const cuerpo=$('ivCuerpo');
 if(disponibleV2===false){
  window.ArcUI.render(cuerpo,`<div class="ivCard"><div class="ivAviso"><b data-gi=382d7e0a2ad5>Inventario V2 todavía no está activo.</b><br data-gi=227cc70e0fe2>
Falta aplicar en Supabase la migración <code>supabase-migration-2026-09-inventory-v2-phase1.sql</code>.
Hasta entonces, el Inventario de siempre sigue funcionando con normalidad.</div></div>`);
  return;
 }
 if(disponibleV2===null){window.ArcUI.render(cuerpo,'<div class="ivCard muted"><span class="gamaSpin"></span>Cargando existencias…</div>');return}
 if(pestana==='existencias')pintarExistencias(cuerpo);
 else if(pestana==='transferencias')pintarTransferencias(cuerpo);
 else if(pestana==='reabastecimiento')pintarReabastecimiento(cuerpo);
 else if(pestana==='conteos')pintarConteos(cuerpo);
 else pintarUbicaciones(cuerpo);
}

/* ---------- existencias ---------- */

function pintarExistencias(host){
 const opcionesAlmacen=almacenes.map(a=>`<option value="${esc(a.id)}">${esc(a.name)}</option>`).join('');
 const categorias=[...new Set(productos.map(p=>(p.category||'').trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es'));
 window.ArcUI.render(host,`<div class="ivKpis" id="ivKpis"></div>
<div class="ivCard">
<div class="ivFiltros">
 <input id="ivBuscar" type="search" data-gi-placeholder=79a86fac0678 placeholder="Buscar por producto, referencia o código…" data-gi-aria-label=2cfb3269b4a0 aria-label="Buscar producto">
 <select id="ivAlmacen" data-gi-aria-label=9a91575b8e4b aria-label="Almacén"><option value="" data-gi=c27ceb62ad08>Todos los almacenes</option>${opcionesAlmacen}</select>
 <label data-gi=3c83e3558107>Hasta<input type="date" id="ivUntil"></label><select id="ivCategoria" data-gi-aria-label=558bb20a82ed aria-label="Categoría"><option value="" data-gi=425a839def0b>Todas las categorías</option>${categorias.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join('')}</select>
 <select id="ivEstadoFiltro" data-gi-aria-label=98e5acddb6c4 aria-label="Estado">
  <option value="" data-gi=ecda92faab01>Todos los estados</option>
  <option value="bajo" data-gi=9ae983d98529>Stock bajo</option>
  <option value="agotado" data-gi=f562218d7957>Sin stock</option>
  <option value="reservado" data-gi=cda5503e85c6>Con reservas</option>
  <option value="sobre" data-gi=fb2a936b096d>Sobre stock</option>
 </select>
</div>
<p class="muted">Las entradas sin destino o fecha no se asignan a un almacén o plazo. La previsión representa disponible + compras pendientes; no es una fecha prometida de entrega.</p><div id="ivTabla"></div>
</div>`);
 ['ivBuscar','ivAlmacen','ivCategoria','ivEstadoFiltro','ivUntil'].forEach(id=>{
  const el=$(id);if(!el)return;
  el[id==='ivBuscar'?'oninput':'onchange']=async()=>{window.GamaPage?.reset('invv2');if(['ivAlmacen','ivUntil'].includes(id))await refreshSnapshot();tabla()};
 });
 window.GamaPage?.register('invv2',tabla);
 tabla();refreshSnapshot().then(()=>{if($('ivTabla'))tabla()});
}

function filas(){
 const q=($('ivBuscar')?.value||'').toLowerCase().trim();
 const alm=$('ivAlmacen')?.value||'';
 const cat=$('ivCategoria')?.value||'';
 const est=$('ivEstadoFiltro')?.value||'';
 return productos
  .filter(p=>!q||[p.name,p.reference,p.barcode].some(v=>String(v||'').toLowerCase().includes(q)))
  .filter(p=>!cat||p.category===cat)
  .map(p=>resumen(p,alm))
  /* Con un almacén elegido, un producto que no tiene nada ahí no es una fila
     vacía que llenar: simplemente no está en ese almacén. */
  .filter(r=>!alm||r.lineas.length||r.entrante>0)
  .filter(r=>!est||estado(r).clase===est);
}

function tabla(){
 const host=$('ivTabla');if(!host)return;
 const rows=filas();
 pintarKpis(rows);
 if(!rows.length){window.ArcUI.render(host,'<div class="muted" data-gi=0c22de3a52d5>No hay existencias que coincidan.</div>');return}
 const pagina=window.GamaPage?window.GamaPage.slice('invv2',rows):rows;
 window.ArcUI.render(host,'<table class="arcTable"><tr>'
  +'<th data-gi=77b9238931ed>Producto</th><th data-gi=10ddff5fcc6f>Referencia</th><th data-gi=558bb20a82ed>Categoría</th><th data-gi=9a91575b8e4b>Almacén</th>'
  +'<th data-gi=9de5d84ed8e5>On hand</th><th data-gi=16434c0b6242>Reservado</th><th data-gi=f4e4f699637b>Disponible</th><th data-gi=ca24af224c4d>Entrante</th><th data-gi=9e0a0b5209ab>Previsto</th>'
  +'<th data-gi=5d61b4a122c0>Mínimo</th><th data-gi=994d51043f7d>Máximo</th><th data-gi=1fecb6bc9f3e>Costo</th><th data-gi=b2f530c46991>Valor</th><th data-gi=98e5acddb6c4>Estado</th></tr>'
  +pagina.map(r=>{
   const e=estado(r);
   const sitios=[...new Set(r.lineas.map(l=>(almacenDe(l.location_id)||{}).name).filter(Boolean))];
   const ubis=r.lineas.map(l=>(ubicacion(l.location_id)||{}).code).filter(Boolean);
   return `<tr>
<td><b>${esc(r.producto.name)}</b>${ubis.length?`<small class="ivSub">${esc(ubis.join(' · '))}</small>`:''}</td>
<td>${esc(r.producto.reference||'—')}</td>
<td>${esc(r.producto.category||'—')}</td>
<td>${esc(sitios.join(', ')||'—')}</td>
<td>${num(r.onHand)}</td>
<td>${r.reservado?num(r.reservado):'—'}</td>
<td><b>${num(r.disponible)}</b></td>
<td>${r.entrante===null?'—':num(r.entrante)}</td>
<td>${r.previsto===null?'—':num(r.previsto)}</td>
<td>${r.minimo?num(r.minimo):'—'}</td>
<td>${r.maximo?num(r.maximo):'—'}</td>
<td>${money(r.costo)}</td>
<td>${money(r.valor)}</td>
<td><span class="ivEstado ${e.clase}">${e.texto}</span></td>
</tr>`}).join('')
  +'</table>'+(window.GamaPage?window.GamaPage.controls('invv2',rows.length):''));
 if(window.GamaTable)window.GamaTable.scan();
}

function pintarKpis(rows){
 const host=$('ivKpis');if(!host)return;
 const valor=rows.reduce((s,r)=>s+r.valor,0);
 const bajo=rows.filter(r=>estado(r).clase==='bajo').length;
 const sin=rows.filter(r=>r.onHand<=0).length;
 const res=rows.reduce((s,r)=>s+r.reservado,0);
 window.ArcUI.render(host,`
<div class="ivKpi"><span data-gi=2b6191504cd7>Valor del stock</span><b>${money(valor)}</b></div>
<div class="ivKpi"><span data-gi=d8fa61c9be01>Productos bajo mínimo</span><b>${bajo}</b></div>
<div class="ivKpi"><span data-gi=be6038d25214>Sin existencias</span><b>${sin}</b></div>
<div class="ivKpi"><span data-gi=3cc912339414>Unidades reservadas</span><b>${num(res)}</b></div>`);
}

/* ---------- transferencias ---------- */

const rotuloUbicacion=u=>{const a=almacenes.find(x=>x.id===u.warehouse_id);return (a?a.name+' · ':'')+u.code+' — '+nombreUbicacion(u)};
function opcionesUbicacion(excepto){
 return ubicaciones.filter(u=>u.active!==false&&u.type!=='warehouse'&&u.id!==excepto).map(u=>`<option value="${esc(u.id)}">${esc(rotuloUbicacion(u))}</option>`).join('');
}
/* Desde dónde se puede mover un producto: sólo de las ubicaciones donde hay
   existencias suyas, con lo que hay y lo que está libre. */
function opcionesOrigen(pid){
 if(!pid)return `<option value="">${esc(T('Elija primero un producto…'))}</option>`;
 const con=quants.filter(q=>q.product_id===pid&&Number(q.quantity)>0).map(q=>({q,u:ubicaciones.find(x=>x.id===q.location_id)})).filter(x=>x.u)
  .sort((a,b)=>rotuloUbicacion(a.u).localeCompare(rotuloUbicacion(b.u)));
 if(!con.length)return `<option value="">${esc(T('Este producto no tiene existencias en ninguna ubicación.'))}</option>`;
 return `<option value="">${esc(T('Ubicación de origen…'))}</option>`+con.map(({q,u})=>{const libre=Number(q.quantity)-Number(q.reserved_quantity||0);
  return `<option value="${esc(u.id)}">${esc(rotuloUbicacion(u)+' · '+num(libre)+' '+T('disponibles'))}</option>`}).join('');
}

function pintarTransferencias(host){
 window.ArcUI.render(host,`<div class="ivCard">
<h3 style="margin:0 0 4px" data-gi=d9bf9cf48ea6>Mover existencias de una ubicación a otra</h3>
<p class="muted" style="margin:0 0 14px" data-gi=812c6c18a9e3>El traslado es de una sola pieza: o se mueve entero o no se mueve nada. Lo reservado no se puede mover.</p>
<div class="ivForm">
 <div><label for="ivtProducto" data-gi=77b9238931ed>Producto</label>
  <select id="ivtProducto"><option value="" data-gi=a48e47394441>Elija un producto…</option>${productos.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}${p.reference?' ('+esc(p.reference)+')':''}</option>`).join('')}</select></div>
 <div><label for="ivtOrigen" data-gi=8b4e93e928df>Desde</label><select id="ivtOrigen" disabled>${opcionesOrigen('')}</select></div>
 <div><label for="ivtDestino" data-gi=d40aa32cd30a>Hacia</label><select id="ivtDestino"><option value="" data-gi=3a32f837bea9>Ubicación de destino…</option>${opcionesUbicacion()}</select></div>
 <div><label for="ivtCantidad" data-gi=8930e00fcc39>Cantidad</label><input id="ivtCantidad" type="number" min="1" step="1" value="1"></div>
 <div style="grid-column:1/-1"><label for="ivtComentario" data-gi=53c367898434>Comentario</label><input id="ivtComentario" data-gi-placeholder=b697e5de1174 placeholder="Motivo del traslado (opcional)"></div>
</div>
<div class="ivSaldo" id="ivtSaldo"></div>
<button type="button" class="arcButton primary" id="ivtConfirmar" style="width:100%;margin-top:14px" data-gi=a32cd62ae09f>Confirmar transferencia</button>
</div>
<div class="ivCard"><h3 style="margin:0 0 10px" data-gi=32fca927bb3d>Últimos traslados</h3><div id="ivtHistorial" class="muted">—</div></div>`);
 // Al elegir el producto, el origen sólo ofrece donde lo hay; el destino, todo lo demás.
 $('ivtProducto').onchange=()=>{const o=$('ivtOrigen'),pid=$('ivtProducto').value;o.innerHTML=opcionesOrigen(pid);o.disabled=!pid||!o.querySelector('option[value]:not([value=""])');
  if(o.options.length===2){o.selectedIndex=1}o.onchange();};
 $('ivtOrigen').onchange=()=>{const d=$('ivtDestino'),keep=d.value,org=$('ivtOrigen').value;d.innerHTML=`<option value="">${esc(T('Ubicación de destino…'))}</option>`+opcionesUbicacion(org);if(keep&&keep!==org)d.value=keep;saldo()};
 $('ivtDestino').onchange=saldo;
 $('ivtConfirmar').onclick=transferir;
 saldo();
 historial();
}

function saldo(){
 const host=$('ivtSaldo');if(!host)return;
 const pid=$('ivtProducto')?.value,org=$('ivtOrigen')?.value,dst=$('ivtDestino')?.value;
 if(!pid||!org){window.ArcUI.render(host,'');return}
 const qO=quants.find(q=>q.product_id===pid&&q.location_id===org);
 const qD=dst?quants.find(q=>q.product_id===pid&&q.location_id===dst):null;
 const onO=Number(qO?.quantity||0),resO=Number(qO?.reserved_quantity||0);
 window.ArcUI.render(host,`<div data-gi=1e31d11b109e>Origen · <b>${num(onO)}</b> en existencia</div>
<div data-gi=1e31d11b109e>Origen · <b>${num(onO-resO)}</b> disponible${resO?` <span class="ivSub">(${num(resO)} reservado)</span>`:''}</div>
${dst?`<div data-gi=d3b6805b5841>Destino · <b>${num(Number(qD?.quantity||0))}</b> en existencia</div>`:''}`);
}

async function transferir(){
 const btn=$('ivtConfirmar');
 const pid=$('ivtProducto').value,org=$('ivtOrigen').value,dst=$('ivtDestino').value;
 const cant=Number($('ivtCantidad').value),com=$('ivtComentario').value.trim();
 if(!pid||!org||!dst)return window.gamaToast('Elija el producto y las dos ubicaciones.');
 if(org===dst)return window.gamaToast('El origen y el destino son la misma ubicación.');
 if(!Number.isFinite(cant)||cant<=0)return window.gamaToast('La cantidad no es válida.');
 const rotulo=btn.textContent;btn.disabled=true;btn.textContent='Transfiriendo…';
 try{
  const c=await C().db();
  const {error}=await window.ArcData.rawRpc('gama_stock_transfer',{
   p_product_id:pid,p_source_location_id:org,p_destination_location_id:dst,
   p_quantity:cant,p_reason:'Transferencia interna',p_comment:com||null});
  if(error)throw error;
  window.gamaToast('Transferencia registrada correctamente.');
  $('ivtCantidad').value='1';$('ivtComentario').value='';
  await cargar();pintar();
 }catch(e){
  console.warn('[GAMA transferencia]',e);
  window.gamaToast(mensaje(e));
 }finally{btn.disabled=false;btn.textContent=rotulo}
}

/* Los errores de las RPC llegan como códigos: se traducen a algo que se pueda
   leer sin saber qué es un raise exception. */
const ERRORES={
 INSUFFICIENT_STOCK:'No hay suficiente stock disponible en el origen.',
 SAME_LOCATION:'El origen y el destino son la misma ubicación.',
 INVALID_QUANTITY:'La cantidad no es válida.',
 ROLE_NOT_ALLOWED:'Su perfil no puede mover existencias.',
 AUTH_REQUIRED:'La sesión ha caducado. Vuelva a entrar.',
 PRODUCT_NOT_FOUND:'El producto no existe.',
 RESERVED_EXCEEDS_QUANTITY:'Quedaría menos stock del que hay reservado.',
 INSUFFICIENT_AVAILABLE:'No hay suficiente stock disponible para reservar.',
 COUNT_ALREADY_VALIDATED:'Este recuento ya estaba validado.',
 COUNT_NOT_EDITABLE:'Este recuento ya no admite cambios.',
 COUNT_CANCELLED:'Este recuento está cancelado.',
 COUNT_NOT_FOUND:'El recuento no existe.'
};
function mensaje(e){
 const t=String(e?.message||e||'');
 const clave=Object.keys(ERRORES).find(k=>t.includes(k));
 return clave?ERRORES[clave]:'No se pudo completar la operación: '+t;
}

async function historial(){
 const host=$('ivtHistorial');if(!host)return;
 try{
  const r=await C().list('stock_movements',{select:'id,product_id,quantity,created_at,source_location_id,destination_location_id,movement_type,comment',order:'created_at',ascending:false,limit:10});
  const rows=(r.data||[]).filter(m=>m.movement_type==='internal_transfer');
  if(!rows.length){window.ArcUI.render(host,'<div class="muted" data-gi=73e92889385c>Todavía no hay traslados registrados.</div>');return}
  window.ArcUI.render(host,'<table class="arcTable"><tr><th data-gi=93b2a9ef782c>Fecha</th><th data-gi=77b9238931ed>Producto</th><th data-gi=8b4e93e928df>Desde</th><th data-gi=d40aa32cd30a>Hacia</th><th data-gi=8930e00fcc39>Cantidad</th></tr>'
   +rows.map(m=>{
    const p=productos.find(x=>x.id===m.product_id);
    return `<tr><td>${esc(new Date(m.created_at).toLocaleString('es-EC'))}</td>
<td>${esc(p?p.name:'—')}</td>
<td>${esc((ubicacion(m.source_location_id)||{}).code||'—')}</td>
<td>${esc((ubicacion(m.destination_location_id)||{}).code||'—')}</td>
<td>${num(m.quantity)}</td></tr>`}).join('')+'</table>');
  if(window.GamaTable)window.GamaTable.scan();
 }catch(_){window.ArcUI.render(host,'<div class="muted" data-gi=006f539c9aa6>No se pudo leer el historial.</div>')}
}


/* ---------- reabastecimiento ---------- */

/* Los límites salen de la regla del producto si la hay, y si no de la ficha
   —min_stock/max_stock—, que es de donde salían hasta ahora. */
function limites(p){
 const r=reglas.find(x=>x.product_id===p.id&&x.active!==false);
 return {
  minimo:Number((r?r.min_quantity:p.min_stock)||0),
  maximo:Number((r?r.max_quantity:p.max_stock)||0),
  proveedor:(r&&r.supplier_id)||p.supplier_id||null,
  regla:!!r
 };
}

/* Se repone cuando lo previsto —lo disponible más lo que viene de camino— cae
   por debajo del mínimo. La cantidad sugerida sube hasta el máximo; si el
   producto no tiene máximo, lo único honesto es subir hasta el mínimo, y se
   dice cuál de los dos se usó. */
function sugerencia(r){
 const l=limites(r.producto);
 const previsto=r.previsto===null?r.disponible:r.previsto;
 if(!l.minimo||previsto>=l.minimo)return null;
 const objetivo=l.maximo>0?l.maximo:l.minimo;
 const cantidad=Math.max(0,objetivo-previsto);
 return cantidad>0?{cantidad,objetivo,hastaMaximo:l.maximo>0,limites:l,previsto}:null;
}

function pintarReabastecimiento(host){
 const filas=productos.map(p=>resumen(p)).map(r=>({r,s:sugerencia(r)})).filter(x=>x.s);
 const nombreProveedor=id=>{const s=proveedores.find(x=>x.id===id);return s?s.name:'—'};
 window.ArcUI.render(host,`<div class="ivCard">
<h3 style="margin:0 0 4px" data-gi=410609c8f18b>Productos que hay que reponer</h3>
<p class="muted" style="margin:0 0 12px" data-gi=cf0b3d08ddea>Se repone cuando lo previsto cae por debajo del mínimo. Previsto es lo disponible más lo que ya viene de camino, así que un producto con una compra en marcha no vuelve a pedirse.</p>
${filas.length?`<table class="arcTable"><tr><th data-gi=77b9238931ed>Producto</th><th data-gi=9de5d84ed8e5>On hand</th><th data-gi=16434c0b6242>Reservado</th><th data-gi=f4e4f699637b>Disponible</th><th data-gi=ca24af224c4d>Entrante</th><th data-gi=9e0a0b5209ab>Previsto</th><th data-gi=5d61b4a122c0>Mínimo</th><th data-gi=994d51043f7d>Máximo</th><th data-gi=53d6521cbfdb>Sugerido</th><th data-gi=e746643f4479>Proveedor</th></tr>`
+filas.map(({r,s})=>`<tr>
<td><b>${esc(r.producto.name)}</b>${s.limites.regla?'<small class="ivSub" data-gi=96f2fb0afade>regla propia</small>':''}</td>
<td>${num(r.onHand)}</td>
<td>${r.reservado?num(r.reservado):'—'}</td>
<td>${num(r.disponible)}</td>
<td>${r.entrante===null?'—':num(r.entrante)}</td>
<td><b>${num(s.previsto)}</b></td>
<td>${num(s.limites.minimo)}</td>
<td>${s.limites.maximo?num(s.limites.maximo):'—'}</td>
<td><b>${num(s.cantidad)}</b>${s.hastaMaximo?'':'<small class="ivSub" data-gi=b6ad26ff71fd>hasta el mínimo</small>'}</td>
<td>${esc(nombreProveedor(s.limites.proveedor))}</td>
</tr>`).join('')+'</table>'
:'<div class="muted" data-gi=6017a18207dd>Ningún producto está por debajo de su mínimo.</div>'}
<p class="muted" style="margin:12px 0 0" data-gi=74c8f187aa38>La sugerencia no crea ninguna orden de compra: pedir sigue siendo cosa del módulo de Compras.</p>
</div>`);
 if(window.GamaTable)window.GamaTable.scan();
}

/* ---------- inventario físico ---------- */

function pintarConteos(host){
 if(conteos===null){
  window.ArcUI.render(host,`<div class="ivCard"><div class="ivAviso"><b data-gi=66c1ec9818d7>El inventario físico todavía no está activo.</b><br data-gi=227cc70e0fe2>
Falta aplicar en Supabase la migración <code>supabase-migration-2026-09-inventory-v2-counts.sql</code>.</div></div>`);
  return;
 }
 if(conteoAbierto){pintarConteoAbierto(host);return}
 window.ArcUI.render(host,`<div class="ivCard">
<h3 style="margin:0 0 4px" data-gi=1f8440f32309>Nuevo recuento</h3>
<p class="muted" style="margin:0 0 12px" data-gi=9f7ced168427>Se prepara con lo que la base cree que hay, se cuenta, y sólo al validarlo se mueven existencias. Cada diferencia deja su ajuste en el Audit Trail.</p>
<div class="ivForm">
 <div><label for="ivcAlmacen" data-gi=9a91575b8e4b>Almacén</label><select id="ivcAlmacen">${almacenes.map(a=>`<option value="${esc(a.id)}">${esc(a.name)}</option>`).join('')}</select></div>
 <div><label>Ubicación (opcional)<select id="ivcLocation"><option value="" data-gi=aff4d19d6ee4>Todas</option>${ubicaciones.map(l=>`<option value="${esc(l.id)}">${esc(l.code)}</option>`).join('')}</select></label></div><div><label>Categoría (opcional)<input id="ivcCategory"></label></div><div><label>Repetir en días (opcional)<input id="ivcCycle" type="number" min="1" max="366"></label></div><div><label><input id="ivcBlind" type="checkbox" checked> Recuento ciego</label></div><div><label for="ivcReferencia" data-gi=10ddff5fcc6f>Referencia</label><input id="ivcReferencia" data-gi-placeholder=e9ac06f6fdc8 placeholder="Ej. Recuento septiembre"></div>
</div>
<button type="button" class="arcButton primary" id="ivcCrear" style="width:100%;margin-top:13px" data-gi=4fd8cf53fad5>Crear y generar líneas</button>
</div>
<div class="ivCard"><h3 style="margin:0 0 10px" data-gi=49c303591a2b>Recuentos</h3>${
 conteos.length?`<table class="arcTable"><tr><th data-gi=10ddff5fcc6f>Referencia</th><th data-gi=9a91575b8e4b>Almacén</th><th data-gi=98e5acddb6c4>Estado</th><th data-gi=1bba71a51144>Creado</th><th></th></tr>`
 +conteos.map(c=>{
   const a=almacenes.find(x=>x.id===c.warehouse_id);
   return `<tr><td><b>${esc(c.reference)}</b></td><td>${esc(a?a.name:'—')}</td>
<td><span class="ivEstado ${c.status==='validated'?'ok':c.status==='cancelled'?'sobre':'bajo'}">${esc(ESTADO_CONTEO[c.status]||c.status)}</span></td>
<td>${esc(new Date(c.created_at).toLocaleDateString('es-EC'))}${c.next_due?'<br>Próximo recuento: '+esc(c.next_due):''}</td>
<td><button type="button" class="arcButton secondary" data-ivc-abrir="${esc(c.id)}" data-gi=a01a5fce396e>Abrir</button></td></tr>`}).join('')+'</table>'
 :'<div class="muted" data-gi=379b33723552>Todavía no hay recuentos.</div>'}</div>`);
 $('ivcCrear').onclick=crearConteo;
 host.querySelectorAll('[data-ivc-abrir]').forEach(b=>b.onclick=()=>abrirConteo(b.dataset.ivcAbrir));
 if(window.GamaTable)window.GamaTable.scan();
}

const ESTADO_CONTEO={draft:'Borrador',in_progress:'En curso',validated:'Validado',cancelled:'Cancelado'};

async function crearConteo(){
 const btn=$('ivcCrear'),alm=$('ivcAlmacen').value,ref=$('ivcReferencia').value.trim();
 if(!alm)return window.gamaToast('Elija un almacén.');
 if(!ref)return window.gamaToast('Ponga una referencia al recuento.');
 const rotulo=btn.textContent;btn.disabled=true;btn.textContent='Creando…';
 try{
  const r={data:await window.ArcData.rpc('gama_count_create',{p_data:{request_key:btn.dataset.requestKey||(btn.dataset.requestKey=crypto.randomUUID()),warehouse_id:alm,reference:ref,location_id:$('ivcLocation').value||null,category:$('ivcCategory').value||null,cycle_days:$('ivcCycle').value||null,blind:$('ivcBlind').checked}})};
  window.gamaToast('Recuento creado con sus líneas.');
  await cargar();await abrirConteo(r.data.id);
 }catch(e){console.warn('[GAMA conteo]',e);window.gamaToast(mensaje(e))}
 finally{btn.disabled=false;btn.textContent=rotulo}
}

async function abrirConteo(id){
 try{
  const r=await window.ArcData.all('inventory_count_lines',{eq:{count_id:id},order:'id'});
  if(r.error)throw r.error;
  lineas=r.data||[];
  conteoAbierto=(conteos||[]).find(c=>c.id===id)||{id,reference:'',status:'in_progress'};
  pintar();
 }catch(e){window.gamaToast(mensaje(e))}
}

function pintarConteoAbierto(host){
 const c=conteoAbierto;
 const cerrado=c.status==='validated'||c.status==='cancelled';
 const blind=c.blind&&!cerrado&&lineas.some(l=>l.counted_quantity==null);
 const nombre=id=>{const p=productos.find(x=>x.id===id);return p?p.name:'—'};
 window.ArcUI.render(host,`<div class="ivCard">
<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap">
 <div><h3 style="margin:0 0 3px">${esc(c.reference||'Recuento')}</h3>
 <p class="muted" style="margin:0">${esc(ESTADO_CONTEO[c.status]||c.status)} · ${lineas.length} línea${lineas.length===1?'':'s'}</p></div>
 <button type="button" class="arcButton secondary" id="ivcVolver" data-gi=168ed65792a2>← Recuentos</button>
</div>
${cerrado?'<div class="ivAviso" style="margin-top:12px" data-gi=fa6448081c49>Este recuento ya está cerrado: sus líneas no se pueden cambiar.</div>':''}
<div style="margin-top:14px" id="ivcLineas"></div>
${cerrado?'':'<button type="button" class="arcButton primary" id="ivcValidar" style="width:100%;margin-top:14px" data-gi=9fe3da1b140d>Validar y ajustar existencias</button>'}
</div>`);
 $('ivcVolver').onclick=()=>{conteoAbierto=null;pintar()};
 const host2=$('ivcLineas');
 window.ArcUI.render(host2,lineas.length?'<table class="arcTable"><tr><th data-gi=77b9238931ed>Producto</th><th data-gi=73b9189b6c6e>Ubicación</th><th data-gi=bd091ce27ef6>Esperado</th><th data-gi=a57f17f4753d>Contado</th><th data-gi=e702db1e219e>Diferencia</th></tr>'
  +lineas.map(l=>{
   const dif=l.counted_quantity===null||l.counted_quantity===undefined?null:Number(l.counted_quantity)-Number(l.expected_quantity);
   return `<tr>
<td><b>${esc(nombre(l.product_id))}</b></td>
<td>${esc((ubicacion(l.location_id)||{}).code||'—')}</td>
<td>${blind?'—':num(l.expected_quantity)}</td>
<td>${cerrado?(l.counted_quantity===null?'—':num(l.counted_quantity)):`<input type="number" min="0" step="0.001" style="width:90px" value="${l.counted_quantity===null||l.counted_quantity===undefined?'':l.counted_quantity}" data-ivc-linea="${esc(l.id)}">`}</td>
<td>${blind||dif===null?'—':`<b class="${dif<0?'low':dif>0?'ok':''}">${dif>0?'+':''}${num(dif)}</b>`}${!cerrado&&!blind&&dif!==null&&dif!==0?`<br><button type="button" class="arcButton secondary" data-recount="${esc(l.id)}">Segundo recuento${l.recount_quantity!=null?' · '+num(l.recount_quantity):''}</button>`:''}</td>
</tr>`}).join('')+'</table>'
  :'<div class="muted" data-gi=edd267836bdc>Este recuento no tiene líneas: el almacén no tiene existencias registradas.</div>');
 host2.querySelectorAll('[data-recount]').forEach(b=>b.onclick=()=>window.ArcUI.dialog({title:'Segundo recuento · otra persona',body:window.ArcUI.field({key:'quantity',label:'Cantidad observada',type:'number',min:0,step:0.001,required:true}),onSave:async el=>{const n=Number(new FormData(el.querySelector('form')).get('quantity'));const r=await C().update('inventory_count_lines',b.dataset.recount,{recount_quantity:n});if(r.error)throw r.error;await abrirConteo(c.id)}}));
 host2.querySelectorAll('[data-ivc-linea]').forEach(i=>i.onchange=()=>apuntar(i.dataset.ivcLinea,i.value));
 if(!cerrado&&$('ivcValidar'))$('ivcValidar').onclick=validarConteo;
 if(window.GamaTable)window.GamaTable.scan();
}

/* Apuntar lo contado NO mueve existencias: sólo guarda la línea. El stock se
   mueve al validar, y por la puerta de siempre. */
async function apuntar(id,valor){
 const n=valor===''?null:Number(valor);
 if(n!==null&&(!Number.isFinite(n)||n<0))return window.gamaToast('La cantidad contada no es válida.');
 try{
  const r=await C().update('inventory_count_lines',id,{counted_quantity:n});
  if(r.error)throw r.error;
  const l=lineas.find(x=>x.id===id);if(l)l.counted_quantity=n;
  pintarConteoAbierto($('ivCuerpo'));
 }catch(e){window.gamaToast(mensaje(e))}
}

async function validarConteo(){
 const btn=$('ivcValidar');
 const rotulo=btn.textContent;btn.disabled=true;btn.textContent='Validando…';
 try{
  const c=await C().db();
  const {data,error}=await window.ArcData.rawRpc('gama_count_validate',{p_count_id:conteoAbierto.id});
  if(error)throw error;
  const n=(data&&data.adjustments)||0;
  window.gamaToast(n?`Recuento validado: ${n} ajuste${n===1?'':'s'} de existencias.`:'Recuento validado sin diferencias.');
  conteoAbierto=null;
  await cargar();pintar();
 }catch(e){console.warn('[GAMA conteo]',e);window.gamaToast(mensaje(e))}
 finally{btn.disabled=false;btn.textContent=rotulo}
}

/* ---------- ubicaciones ---------- */

/* Estanterías simuladas. Cada una tiene dos letras, columnas y filas; el
   servidor (gama_shelf_action) genera una ubicación por celda con la
   referencia AAXX-XX —estantería, columna, fila— y esas ubicaciones son las
   que ofrecen después todos los desplegables. Aquí se configuran, se ven como
   una estantería de verdad (la fila 01 abajo) y se borran si están vacías. */
const puedeEditar=()=>{try{return ['admin','administrador','magasinier','almacenero'].includes(JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role)}catch(_){return false}};
const dosCifras=n=>String(n).padStart(2,'0');
const espacio=(sh,c,r)=>sh.code+dosCifras(c)+'-'+dosCifras(r);
const espaciosDe=sh=>ubicaciones.filter(u=>u.shelf_id===sh.id&&u.active!==false);
const unidadesEn=id=>quants.filter(q=>q.location_id===id).reduce((s,q)=>s+Number(q.quantity||0),0);
const ERRORES_ESTANTERIA={SHELF_CODE_INVALID:'El código de la estantería son dos letras, de la A a la Z.',SHELF_CODE_TAKEN:'Ya hay una estantería con ese código en este almacén.',SHELF_SIZE_INVALID:'Columnas y filas van de 1 a 99.',SHELF_STALE:'Otra persona ha cambiado la estantería. Vuelve a abrirla.',SHELF_SPACE_IN_USE:'Estos espacios tienen existencias, reservas o una compra abierta y no se pueden quitar:',SHELF_NOT_EMPTY:'La estantería no está vacía. Vacía antes estos espacios:',SHELF_SPACE_TAKEN:'Otra ubicación ya usa esta referencia:',SHELF_PARENT_INVALID:'La zona elegida no es de este almacén.',ROLE_NOT_ALLOWED:'Tu perfil no puede configurar estanterías.'};
function errorEstanteria(e){const m=String(e?.message||e);const k=Object.keys(ERRORES_ESTANTERIA).find(x=>m.includes(x));if(!k)return window.ArcErrors?.message(e)||m;const detalle=m.split(k+':')[1];return T(ERRORES_ESTANTERIA[k])+(detalle?' '+detalle.trim():'')}
async function accionEstanteria(a,d){const r=await window.ArcData.rawRpc('gama_shelf_action',{p_action:a,p_data:d});if(r.error)throw r.error;return r.data}
async function recargarEstanterias(){window.ArcData.invalidate?.('warehouse_locations');await cargar();pintar();window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'warehouse_locations'}}))}

function rejilla(sh){
 const celdas=[];
 for(let r=sh.row_count;r>=1;r--)for(let c=1;c<=sh.column_count;c++){
  const code=espacio(sh,c,r),u=ubicaciones.find(x=>x.shelf_id===sh.id&&x.code===code),n=u?unidadesEn(u.id):0;
  const quien=u?quants.filter(q=>q.location_id===u.id&&Number(q.quantity)>0).map(q=>(productos.find(p=>p.id===q.product_id)||{}).name).filter(Boolean):[];
  celdas.push(`<div class="ivCelda${n>0?' lleno':''}" data-space="${esc(code)}" title="${esc(code+(quien.length?' · '+quien.join(', '):''))}"><b>${esc(code)}</b>${n>0?`<small>${num(n)} ${esc(T('uds.'))}</small>`:''}</div>`);
 }
 return `<div class="ivEstanteria" style="--iv-cols:${sh.column_count}" role="img" aria-label="${esc(T('Estantería')+' '+sh.code)}">${celdas.join('')}</div><p class="muted ivLeyenda">${tr('Fila 01 abajo, columna 01 a la izquierda. En color, los espacios con existencias.')}</p>`;
}
function tarjetaEstanteria(sh,a){
 const sus=espaciosDe(sh),uds=sus.reduce((s,u)=>s+unidadesEn(u.id),0),abierta=estanteriaVista===sh.id;
 return `<div class="ivShelf" data-shelf="${esc(sh.id)}"><div class="ivShelfHead"><div><b class="ivShelfCode">${esc(sh.code)}</b> ${esc(sh.name||'')}<div class="muted">${esc(espacio(sh,1,1))} → ${esc(espacio(sh,sh.column_count,sh.row_count))} · ${sh.column_count} × ${sh.row_count} = ${sus.length} ${esc(T('espacios'))}${uds?' · '+num(uds)+' '+esc(T('uds.')):''}</div></div>
<div class="ivShelfActions"><button type="button" class="arcButton secondary" data-shelf-view="${esc(sh.id)}" aria-expanded="${abierta}">${tr(abierta?'Ocultar':'Ver estantería')}</button>${puedeEditar()?`<button type="button" class="arcButton secondary" data-shelf-edit="${esc(sh.id)}">${tr('Configurar')}</button><button type="button" class="arcButton secondary" data-shelf-delete="${esc(sh.id)}">${tr('Eliminar')}</button>`:''}</div></div>${abierta?rejilla(sh):''}</div>`;
}
function pintarUbicaciones(host){
 if(!almacenes.length){window.ArcUI.render(host,'<div class="ivCard muted" data-gi=1c74217c5f89>No hay almacenes dados de alta.</div>');return}
 window.ArcUI.render(host,almacenes.map(a=>{
  // Otras ubicaciones: todo lo que no es la raíz del almacén ni un espacio de estantería.
  const otras=otrasUbicaciones(a.id);
  const sus=estanterias.filter(sh=>sh.warehouse_id===a.id);
  return `<div class="ivCard" data-warehouse="${esc(a.id)}"><div class="ivShelfHead"><div><h3 style="margin:0 0 4px">${esc(a.name)}</h3>
<p class="muted" style="margin:0">${esc(a.code)}${a.city?' · '+esc(a.city):''}</p></div>${puedeEditar()?`<button type="button" class="arcButton primary" data-shelf-new="${esc(a.id)}">${tr('＋ Nueva estantería')}</button>`:''}</div>
<h4 class="ivShelfTitle">${tr('Estanterías')}</h4>${sus.map(sh=>tarjetaEstanteria(sh,a)).join('')||`<p class="muted">${tr('Sin estanterías. Crea una para generar sus espacios AAXX-XX.')}</p>`}
<div class="ivShelfHead ivOtrasHead"><h4 class="ivShelfTitle">${tr('Otras ubicaciones')}</h4>${puedeEditar()?`<button type="button" class="arcButton secondary" data-loc-new="${esc(a.id)}">${tr('＋ Nueva ubicación')}</button>`:''}</div>
<ul class="ivOtras">${otras.map(u=>filaUbicacion(u)).join('')||`<li class="muted">${tr('Sin ubicaciones.')}</li>`}</ul></div>`;
 }).join(''));
 host.querySelectorAll('[data-shelf-new]').forEach(b=>b.onclick=()=>dialogoEstanteria(b.dataset.shelfNew,null));
 host.querySelectorAll('[data-shelf-edit]').forEach(b=>b.onclick=()=>{const sh=estanterias.find(x=>x.id===b.dataset.shelfEdit);if(sh)dialogoEstanteria(sh.warehouse_id,sh)});
 host.querySelectorAll('[data-shelf-view]').forEach(b=>b.onclick=()=>{estanteriaVista=estanteriaVista===b.dataset.shelfView?null:b.dataset.shelfView;pintarUbicaciones(host)});
 host.querySelectorAll('[data-shelf-delete]').forEach(b=>b.onclick=()=>borrarEstanteria(estanterias.find(x=>x.id===b.dataset.shelfDelete)));
 host.querySelectorAll('[data-loc-new]').forEach(b=>b.onclick=()=>dialogoUbicacion(b.dataset.locNew,null));
 host.querySelectorAll('[data-loc-edit]').forEach(b=>b.onclick=()=>{const u=ubicaciones.find(x=>x.id===b.dataset.locEdit);if(u)dialogoUbicacion(u.warehouse_id,u)});
 host.querySelectorAll('[data-loc-delete]').forEach(b=>b.onclick=()=>borrarUbicacion(ubicaciones.find(x=>x.id===b.dataset.locDelete)));
}
/* Otras ubicaciones, a medida. Cada almacén trae tres zonas con papel —la de
   llegada, donde entran las recepciones; la de salida, donde espera lo
   preparado; y la cuarentena de las devoluciones—, que se renombran pero no se
   quitan. Las demás las crea, renombra o quita quien gestiona el almacén
   (gama_location_action); sólo se quita lo vacío. */
const PAPEL={arrival:'Zona de llegada',departure:'Zona de salida',quarantine:'Cuarentena'};
const ORDEN_PAPEL={arrival:0,departure:1,quarantine:2};
// El nombre por defecto de una zona con papel se traduce; el que haya puesto alguien, no.
const nombreUbicacion=u=>u.role&&u.name===PAPEL[u.role]?T(u.name):u.name;
function otrasUbicaciones(almacenId){
 return ubicaciones.filter(u=>u.warehouse_id===almacenId&&!u.shelf_id&&u.active!==false&&u.type!=='warehouse')
  .sort((x,y)=>(ORDEN_PAPEL[x.role]??9)-(ORDEN_PAPEL[y.role]??9)||String(x.code).localeCompare(String(y.code)));
}
function filaUbicacion(u){
 const n=unidadesEn(u.id);
 return `<li data-location="${esc(u.id)}"><div><code>${esc(u.code)}</code> <b>${esc(nombreUbicacion(u))}</b>${u.role?` <span class="ivPapel" data-role="${esc(u.role)}">${tr('Por defecto')}</span>`:''}<div class="muted">${n?`${num(n)} ${esc(T('uds.'))}`:esc(T('Vacía'))}</div></div>`
  +(puedeEditar()?`<div class="ivShelfActions"><button type="button" class="arcButton secondary" data-loc-edit="${esc(u.id)}">${tr('Renombrar')}</button>${u.role?'':`<button type="button" class="arcButton secondary" data-loc-delete="${esc(u.id)}">${tr('Eliminar')}</button>`}</div>`:'')+'</li>';
}
const ERRORES_UBICACION={LOCATION_NAME_REQUIRED:'El nombre es obligatorio.',LOCATION_CODE_INVALID:'El código lleva letras, cifras, punto, guion o guion bajo (hasta 24).',LOCATION_CODE_RESERVED:'Los códigos AAXX-XX son de los espacios de estantería.',LOCATION_CODE_TAKEN:'Ya hay una ubicación con ese código en este almacén.',LOCATION_CODE_IMMUTABLE:'El código de una ubicación no cambia.',LOCATION_ROLE_REQUIRED:'Las zonas por defecto se renombran pero no se eliminan.',LOCATION_NOT_EMPTY:'La ubicación no está vacía: tiene existencias, reservas o una compra abierta.',LOCATION_HAS_CHILDREN:'Hay ubicaciones o estanterías dentro de esta ubicación.',LOCATION_IN_USE:'Una preparación en curso usa esta ubicación.',LOCATION_NOT_FOUND:'La ubicación ya no existe.',ROLE_NOT_ALLOWED:'Su perfil no puede cambiar las ubicaciones.'};
function errorUbicacion(e){const m=String(e?.message||e);const k=Object.keys(ERRORES_UBICACION).find(x=>m.includes(x));return k?T(ERRORES_UBICACION[k]):(window.ArcErrors?.message(e)||m)}
async function accionUbicacion(a,d){const r=await window.ArcData.rawRpc('gama_location_action',{p_action:a,p_data:d});if(r.error)throw r.error;return r.data}
function dialogoUbicacion(almacenId,u){
 const a=almacenes.find(x=>x.id===almacenId);if(!a)return;
 const F=window.ArcUI.field;
 const d=window.ArcUI.dialog({title:T(u?'Renombrar la ubicación':'Nueva ubicación')+(u?' '+u.code:''),saveLabel:T('Guardar'),
  body:`<p class="muted">${esc(a.name)}${u?.role?' · '+tr('Zona por defecto: se renombra, no se elimina.'):''}</p>`
   +F({key:'code',label:T('Código'),value:u?.code||'',required:true,maxLength:24,disabled:!!u,attrs:'autocapitalize="characters" autocomplete="off"'})
   +F({key:'name',label:T('Nombre'),value:u?nombreUbicacion(u):'',required:true,maxLength:120}),
  onSave:async el=>{
   const f=new FormData(el.querySelector('form'));
   try{await accionUbicacion('save',u?{id:u.id,name:f.get('name')}:{warehouse_id:almacenId,code:String(f.get('code')||'').toUpperCase(),name:f.get('name')})}
   catch(e){throw Error(errorUbicacion(e))}
   await recargarEstanterias();
   window.gamaToast?.(T('Ubicación guardada.'));
  }});
 const codigo=d.querySelector('[name=code]');codigo?.addEventListener('input',()=>{codigo.value=codigo.value.toUpperCase().replace(/\s+/g,'')});
}
async function borrarUbicacion(u){
 if(!u||!confirm(T('¿Eliminar la ubicación')+' '+u.code+'?'))return;
 try{await accionUbicacion('delete',{id:u.id});await recargarEstanterias();window.gamaToast?.(T('Ubicación eliminada.')+' '+u.code)}
 catch(e){const m=errorUbicacion(e);if(window.gamaToast)window.gamaToast(m);else alert(m)}
}
function dialogoEstanteria(almacenId,sh){
 const a=almacenes.find(x=>x.id===almacenId);if(!a)return;
 const zonas=ubicaciones.filter(u=>u.warehouse_id===almacenId&&!u.shelf_id&&u.active!==false&&u.type!=='bin');
 const F=window.ArcUI.field;
 const d=window.ArcUI.dialog({title:T(sh?'Configurar la estantería':'Nueva estantería')+(sh?' '+sh.code:''),saveLabel:T('Guardar'),
  body:`<p class="muted">${esc(a.name)} · ${tr('Cada celda es un espacio de almacenamiento AAXX-XX: estantería, columna, fila.')}</p>`
   +F({key:'code',label:T('Código de la estantería (2 letras)'),value:sh?.code||'',required:true,maxLength:2,disabled:!!sh,attrs:'autocapitalize="characters" pattern="[A-Za-z]{2}" autocomplete="off"'})
   +F({key:'name',label:T('Nombre (opcional)'),value:sh?.name||'',maxLength:120})
   +F({key:'column_count',label:T('Columnas'),type:'number',value:sh?.column_count||4,required:true,min:1,max:99,step:1})
   +F({key:'row_count',label:T('Filas'),type:'number',value:sh?.row_count||5,required:true,min:1,max:99,step:1})
   +F({key:'parent_id',label:T('Zona (opcional)'),type:'select',value:sh?.parent_id||'',options:zonas.map(z=>({id:z.id,name:z.code+' · '+z.name}))})
   +`<p class="gsHint" data-shelf-preview aria-live="polite"></p>`,
  onSave:async el=>{
   const f=new FormData(el.querySelector('form')),datos={name:f.get('name')||'',column_count:Number(f.get('column_count')),row_count:Number(f.get('row_count')),parent_id:f.get('parent_id')||''};
   try{await accionEstanteria('save',sh?{...datos,id:sh.id,version:sh.version}:{...datos,warehouse_id:almacenId,code:String(f.get('code')||'').toUpperCase()})}
   catch(e){throw Error(errorEstanteria(e))}
   await recargarEstanterias();
   window.gamaToast?.(T('Estantería guardada.'));
  }});
 const vista=()=>{const f=new FormData(d.querySelector('form')),code=String(sh?.code||f.get('code')||'').toUpperCase().replace(/[^A-Z]/g,'').slice(0,2),c=Math.min(99,Math.max(1,Number(f.get('column_count'))||1)),r=Math.min(99,Math.max(1,Number(f.get('row_count'))||1));
  d.querySelector('[data-shelf-preview]').textContent=code.length===2?`${T('Espacios')}: ${code}01-01 → ${code}${dosCifras(c)}-${dosCifras(r)} (${c*r})`:T('El código son dos letras, por ejemplo AB.')};
 const codigo=d.querySelector('[name=code]');codigo?.addEventListener('input',()=>{codigo.value=codigo.value.toUpperCase().replace(/[^A-Z]/g,'').slice(0,2)});
 d.querySelector('form').addEventListener('input',vista);vista();
}
async function borrarEstanteria(sh){
 if(!sh||!confirm(T('¿Eliminar la estantería')+' '+sh.code+'? '+T('Se quitan sus espacios; los que tienen historial se archivan.')))return;
 try{const r=await accionEstanteria('delete',{id:sh.id});if(estanteriaVista===sh.id)estanteriaVista=null;await recargarEstanterias();
  window.gamaToast?.(`${T('Estantería eliminada')} ${sh.code} · ${r.removed.deleted+r.removed.archived} ${T('espacios quitados')}`)}
 catch(e){const m=errorEstanteria(e);if(window.gamaToast)window.gamaToast(m);else alert(m)}
}

/* ---------- entrada ---------- */

async function abrir(){
 css();
 /* La sección se crea aquí, no está escrita en index.html. Hay que crearla y
    pintarla ANTES de pedir que se muestre: showTab recorre las secciones que
    encuentra en ese momento, y a una que todavía no existe no la enciende. */
 seccion();
 pintar();
 if(window.showTab)window.showTab('warehouses',null);
 else seccion().classList.add('active');
 if(disponibleV2===null)await cargar();
 pintar();
}

window.GamaOpenWarehouses=abrir;
window.GamaInventoryV2={openCount:async id=>{
 if(!window.gamaAccessAllowed?.('warehouses'))throw Error('Acceso no permitido.');
 await abrir();const r=await C().list('inventory_counts',{eq:{id}});if(r.error)throw r.error;if(!r.data?.[0])throw Error('Recuento no disponible.');
 conteos=(conteos||[]).filter(c=>c.id!==id).concat(r.data);pestana='conteos';await abrirConteo(id);
},abrir,cargar,resumen,estado,sugerencia,limites,get datos(){return{almacenes,ubicaciones,quants,productos,entrante,estanterias}}};
})();
