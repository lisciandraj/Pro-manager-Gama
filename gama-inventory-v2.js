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
const esc=v=>window.GamaUI?window.GamaUI.esc(v):String(v??'');
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const num=v=>Number(v||0).toLocaleString('es-EC',{maximumFractionDigits:2});

let almacenes=[],ubicaciones=[],quants=[],productos=[],entrante=new Map();
let reglas=[],proveedores=[],conteos=[],lineas=[],conteoAbierto=null;
let pestana='existencias',disponibleV2=null,cargando=false;

/* ---------- datos ---------- */

/* Las fotos son base64 y pesan: un inventario de mil productos no tiene por
   qué arrastrarlas. Se piden sólo las columnas que la tabla enseña. */
const COLUMNAS_PRODUCTO='id,name,reference,category,min_stock,max_stock,purchase_price,stock,active,location';

async function cargar(){
 if(cargando)return;
 cargando=true;
 try{
  const [w,l,q,p]=await Promise.all([
   C().list('warehouses',{order:'code',ascending:true}),
   C().list('warehouse_locations',{order:'code',ascending:true}),
   C().list('stock_quants',{}),
   C().list('products',{select:COLUMNAS_PRODUCTO,order:'name',ascending:true})
  ]);
  /* Si falta la tabla, PostgREST responde con error en vez de con filas. Es
     la señal de que la migración aún no está aplicada. */
  if(w.error||l.error||q.error){disponibleV2=false;return}
  disponibleV2=true;
  almacenes=w.data||[];ubicaciones=l.data||[];quants=q.data||[];
  productos=(p.data||[]).filter(x=>x.active!==false);
  const [rr,sp,cc]=await Promise.all([
   C().list('reorder_rules',{}),
   C().list('suppliers',{select:'id,name'}),
   C().list('inventory_counts',{order:'created_at',ascending:false,limit:20})
  ]);
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
 entrante=new Map();
 try{
  const [po,pol]=await Promise.all([
   C().list('purchase_orders',{select:'id,status'}),
   C().list('purchase_order_lines',{select:'product_id,quantity,received_quantity,purchase_order_id'})
  ]);
  if(po.error||pol.error){entrante=null;return}
  const abiertas=new Set((po.data||[]).filter(o=>o.status==='sent'||o.status==='partial').map(o=>o.id));
  (pol.data||[]).forEach(l=>{
   if(!abiertas.has(l.purchase_order_id))return;
   const falta=Number(l.quantity||0)-Number(l.received_quantity||0);
   if(falta>0)entrante.set(l.product_id,(entrante.get(l.product_id)||0)+falta);
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
 const entra=entrante?Number(entrante.get(p.id)||0):null;
 const disp=onHand-reservado;
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

function css(){
 if($('gamaInvV2Css'))return;
 const s=document.createElement('style');s.id='gamaInvV2Css';
 s.textContent=`
#warehouses{display:none}#warehouses.active{display:block}
.ivTabs{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 14px}
.ivTabs button{background:#EEF3F4;color:#18324A;border:1px solid #DCE5E8;border-radius:10px;padding:10px 15px;font-weight:750;font-size:13.5px}
.ivTabs button.active{background:#087C8B;color:#fff;border-color:#087C8B}
.ivCard{background:#fff;border:1px solid #E2E8EC;border-radius:15px;padding:16px;margin-bottom:14px;box-shadow:0 1px 2px #1732460a}
.ivKpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-bottom:14px}
.ivKpi{background:#fff;border:1px solid #E2E8EC;border-radius:13px;padding:13px 15px}
.ivKpi span{display:block;font-size:11.5px;font-weight:750;color:#71808A}
.ivKpi b{display:block;font-size:21px;font-weight:900;color:#173246;margin-top:5px;letter-spacing:-.4px}
.ivFiltros{display:flex;gap:9px;flex-wrap:wrap;align-items:center;margin-bottom:12px}
.ivFiltros input{flex:1 1 240px;min-width:0;width:auto}
.ivFiltros select{flex:0 0 auto;width:200px;min-width:0;padding:11px;border-radius:10px;border:1px solid #d4e0e4}
.ivEstado{display:inline-block;font-size:11px;font-weight:800;border-radius:999px;padding:3px 9px;background:#E7F6F0;color:#0F7A5B;white-space:nowrap}
.ivEstado.bajo{background:#FFF3E6;color:#9E5B14}
.ivEstado.agotado{background:#FFF0EC;color:#C94F45}
.ivEstado.sobre{background:#EEF3F4;color:#5C6B76}
.ivEstado.reservado{background:#E8F5F6;color:#087C8B}
.ivSub{color:#71808A;font-size:11.5px}
.ivForm{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}
.ivForm label{margin-top:0}
.ivAviso{background:#FFF6EF;border-left:4px solid #F47A2A;padding:12px 13px;border-radius:8px;font-size:13px;line-height:1.5}
.ivSaldo{display:flex;gap:16px;flex-wrap:wrap;margin:10px 0 0;font-size:13px;color:#4E5F6B}
.ivSaldo b{color:#173246}
.ivArbol{list-style:none;margin:0;padding:0;font-size:13.5px}
.ivArbol ul{list-style:none;margin:0;padding:0 0 0 20px;border-left:1px solid #E2E8EC}
.ivArbol li{padding:5px 0}
.ivArbol code{background:#F1F4F6;border-radius:5px;padding:1px 6px;font-size:12px;color:#5C6B76}
@media(max-width:560px){.ivFiltros input,.ivFiltros select{flex:0 0 auto;width:100%}}`;
 (document.head||document.documentElement).appendChild(s);
}

/* ---------- pantalla ---------- */

function seccion(){
 let sec=$('warehouses');
 if(!sec){sec=document.createElement('section');sec.id='warehouses';(document.querySelector('.wrap')||document.body).appendChild(sec)}
 return sec;
}

function pintar(){
 css();
 const sec=seccion();
 sec.innerHTML=window.GamaUI.header({
  title:'🏬 Almacenes y existencias',
  lead:'Dónde está cada producto y cuánto queda disponible.'
 })+`<div class="ivTabs">
<button type="button" data-iv-tab="existencias">Existencias</button>
<button type="button" data-iv-tab="transferencias">Transferencias</button>
<button type="button" data-iv-tab="reabastecimiento">Reabastecimiento</button>
<button type="button" data-iv-tab="conteos">Inventario físico</button>
<button type="button" data-iv-tab="ubicaciones">Ubicaciones</button>
</div><div id="ivCuerpo"></div>`;
 window.GamaUI.bindBack(sec);
 sec.querySelectorAll('[data-iv-tab]').forEach(b=>{
  b.classList.toggle('active',b.dataset.ivTab===pestana);
  b.onclick=()=>{pestana=b.dataset.ivTab;pintar()};
 });
 const cuerpo=$('ivCuerpo');
 if(disponibleV2===false){
  cuerpo.innerHTML=`<div class="ivCard"><div class="ivAviso"><b>Inventario V2 todavía no está activo.</b><br>
Falta aplicar en Supabase la migración <code>supabase-migration-2026-09-inventory-v2-phase1.sql</code>.
Hasta entonces, el Inventario de siempre sigue funcionando con normalidad.</div></div>`;
  return;
 }
 if(disponibleV2===null){cuerpo.innerHTML='<div class="ivCard muted"><span class="gamaSpin"></span>Cargando existencias…</div>';return}
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
 host.innerHTML=`<div class="ivKpis" id="ivKpis"></div>
<div class="ivCard">
<div class="ivFiltros">
 <input id="ivBuscar" type="search" placeholder="Buscar por producto o referencia…" aria-label="Buscar producto">
 <select id="ivAlmacen" aria-label="Almacén"><option value="">Todos los almacenes</option>${opcionesAlmacen}</select>
 <select id="ivCategoria" aria-label="Categoría"><option value="">Todas las categorías</option>${categorias.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join('')}</select>
 <select id="ivEstadoFiltro" aria-label="Estado">
  <option value="">Todos los estados</option>
  <option value="bajo">Stock bajo</option>
  <option value="agotado">Sin stock</option>
  <option value="reservado">Con reservas</option>
  <option value="sobre">Sobre stock</option>
 </select>
</div>
<div id="ivTabla"></div>
</div>`;
 ['ivBuscar','ivAlmacen','ivCategoria','ivEstadoFiltro'].forEach(id=>{
  const el=$(id);if(!el)return;
  el[id==='ivBuscar'?'oninput':'onchange']=()=>{window.GamaPage?.reset('invv2');tabla()};
 });
 window.GamaPage?.register('invv2',tabla);
 tabla();
}

function filas(){
 const q=($('ivBuscar')?.value||'').toLowerCase().trim();
 const alm=$('ivAlmacen')?.value||'';
 const cat=$('ivCategoria')?.value||'';
 const est=$('ivEstadoFiltro')?.value||'';
 return productos
  .filter(p=>!q||[p.name,p.reference].some(v=>String(v||'').toLowerCase().includes(q)))
  .filter(p=>!cat||p.category===cat)
  .map(p=>resumen(p,alm))
  /* Con un almacén elegido, un producto que no tiene nada ahí no es una fila
     vacía que llenar: simplemente no está en ese almacén. */
  .filter(r=>!alm||r.lineas.length)
  .filter(r=>!est||estado(r).clase===est);
}

function tabla(){
 const host=$('ivTabla');if(!host)return;
 const rows=filas();
 pintarKpis(rows);
 if(!rows.length){host.innerHTML='<div class="muted">No hay existencias que coincidan.</div>';return}
 const pagina=window.GamaPage?window.GamaPage.slice('invv2',rows):rows;
 host.innerHTML='<table><tr>'
  +'<th>Producto</th><th>Referencia</th><th>Categoría</th><th>Almacén</th>'
  +'<th>On hand</th><th>Reservado</th><th>Disponible</th><th>Entrante</th><th>Previsto</th>'
  +'<th>Mínimo</th><th>Máximo</th><th>Costo</th><th>Valor</th><th>Estado</th></tr>'
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
  +'</table>'+(window.GamaPage?window.GamaPage.controls('invv2',rows.length):'');
 if(window.GamaTable)window.GamaTable.scan();
}

function pintarKpis(rows){
 const host=$('ivKpis');if(!host)return;
 const valor=rows.reduce((s,r)=>s+r.valor,0);
 const bajo=rows.filter(r=>estado(r).clase==='bajo').length;
 const sin=rows.filter(r=>r.onHand<=0).length;
 const res=rows.reduce((s,r)=>s+r.reservado,0);
 host.innerHTML=`
<div class="ivKpi"><span>Valor del stock</span><b>${money(valor)}</b></div>
<div class="ivKpi"><span>Productos bajo mínimo</span><b>${bajo}</b></div>
<div class="ivKpi"><span>Sin existencias</span><b>${sin}</b></div>
<div class="ivKpi"><span>Unidades reservadas</span><b>${num(res)}</b></div>`;
}

/* ---------- transferencias ---------- */

function opcionesUbicacion(){
 return ubicaciones.filter(u=>u.active!==false).map(u=>{
  const a=almacenes.find(x=>x.id===u.warehouse_id);
  return `<option value="${esc(u.id)}">${esc((a?a.name+' · ':'')+u.code+' — '+u.name)}</option>`;
 }).join('');
}

function pintarTransferencias(host){
 host.innerHTML=`<div class="ivCard">
<h3 style="margin:0 0 4px">Mover existencias de una ubicación a otra</h3>
<p class="muted" style="margin:0 0 14px">El traslado es de una sola pieza: o se mueve entero o no se mueve nada. Lo reservado no se puede mover.</p>
<div class="ivForm">
 <div><label for="ivtProducto">Producto</label>
  <select id="ivtProducto"><option value="">Elija un producto…</option>${productos.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}${p.reference?' ('+esc(p.reference)+')':''}</option>`).join('')}</select></div>
 <div><label for="ivtOrigen">Desde</label><select id="ivtOrigen"><option value="">Ubicación de origen…</option>${opcionesUbicacion()}</select></div>
 <div><label for="ivtDestino">Hacia</label><select id="ivtDestino"><option value="">Ubicación de destino…</option>${opcionesUbicacion()}</select></div>
 <div><label for="ivtCantidad">Cantidad</label><input id="ivtCantidad" type="number" min="1" step="1" value="1"></div>
 <div style="grid-column:1/-1"><label for="ivtComentario">Comentario</label><input id="ivtComentario" placeholder="Motivo del traslado (opcional)"></div>
</div>
<div class="ivSaldo" id="ivtSaldo"></div>
<button type="button" class="primary" id="ivtConfirmar" style="width:100%;margin-top:14px">Confirmar transferencia</button>
</div>
<div class="ivCard"><h3 style="margin:0 0 10px">Últimos traslados</h3><div id="ivtHistorial" class="muted">—</div></div>`;
 ['ivtProducto','ivtOrigen','ivtDestino'].forEach(id=>{const el=$(id);if(el)el.onchange=saldo});
 $('ivtConfirmar').onclick=transferir;
 saldo();
 historial();
}

function saldo(){
 const host=$('ivtSaldo');if(!host)return;
 const pid=$('ivtProducto')?.value,org=$('ivtOrigen')?.value,dst=$('ivtDestino')?.value;
 if(!pid||!org){host.innerHTML='';return}
 const qO=quants.find(q=>q.product_id===pid&&q.location_id===org);
 const qD=dst?quants.find(q=>q.product_id===pid&&q.location_id===dst):null;
 const onO=Number(qO?.quantity||0),resO=Number(qO?.reserved_quantity||0);
 host.innerHTML=`<div>Origen · <b>${num(onO)}</b> en existencia</div>
<div>Origen · <b>${num(onO-resO)}</b> disponible${resO?` <span class="ivSub">(${num(resO)} reservado)</span>`:''}</div>
${dst?`<div>Destino · <b>${num(Number(qD?.quantity||0))}</b> en existencia</div>`:''}`;
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
  const {error}=await c.rpc('gama_stock_transfer',{
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
  if(!rows.length){host.innerHTML='<div class="muted">Todavía no hay traslados registrados.</div>';return}
  host.innerHTML='<table><tr><th>Fecha</th><th>Producto</th><th>Desde</th><th>Hacia</th><th>Cantidad</th></tr>'
   +rows.map(m=>{
    const p=productos.find(x=>x.id===m.product_id);
    return `<tr><td>${esc(new Date(m.created_at).toLocaleString('es-EC'))}</td>
<td>${esc(p?p.name:'—')}</td>
<td>${esc((ubicacion(m.source_location_id)||{}).code||'—')}</td>
<td>${esc((ubicacion(m.destination_location_id)||{}).code||'—')}</td>
<td>${num(m.quantity)}</td></tr>`}).join('')+'</table>';
  if(window.GamaTable)window.GamaTable.scan();
 }catch(_){host.innerHTML='<div class="muted">No se pudo leer el historial.</div>'}
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
 host.innerHTML=`<div class="ivCard">
<h3 style="margin:0 0 4px">Productos que hay que reponer</h3>
<p class="muted" style="margin:0 0 12px">Se repone cuando lo previsto cae por debajo del mínimo. Previsto es lo disponible más lo que ya viene de camino, así que un producto con una compra en marcha no vuelve a pedirse.</p>
${filas.length?`<table><tr><th>Producto</th><th>On hand</th><th>Reservado</th><th>Disponible</th><th>Entrante</th><th>Previsto</th><th>Mínimo</th><th>Máximo</th><th>Sugerido</th><th>Proveedor</th></tr>`
+filas.map(({r,s})=>`<tr>
<td><b>${esc(r.producto.name)}</b>${s.limites.regla?'<small class="ivSub">regla propia</small>':''}</td>
<td>${num(r.onHand)}</td>
<td>${r.reservado?num(r.reservado):'—'}</td>
<td>${num(r.disponible)}</td>
<td>${r.entrante===null?'—':num(r.entrante)}</td>
<td><b>${num(s.previsto)}</b></td>
<td>${num(s.limites.minimo)}</td>
<td>${s.limites.maximo?num(s.limites.maximo):'—'}</td>
<td><b>${num(s.cantidad)}</b>${s.hastaMaximo?'':'<small class="ivSub">hasta el mínimo</small>'}</td>
<td>${esc(nombreProveedor(s.limites.proveedor))}</td>
</tr>`).join('')+'</table>'
:'<div class="muted">Ningún producto está por debajo de su mínimo.</div>'}
<p class="muted" style="margin:12px 0 0">La sugerencia no crea ninguna orden de compra: pedir sigue siendo cosa del módulo de Compras.</p>
</div>`;
 if(window.GamaTable)window.GamaTable.scan();
}

/* ---------- inventario físico ---------- */

function pintarConteos(host){
 if(conteos===null){
  host.innerHTML=`<div class="ivCard"><div class="ivAviso"><b>El inventario físico todavía no está activo.</b><br>
Falta aplicar en Supabase la migración <code>supabase-migration-2026-09-inventory-v2-counts.sql</code>.</div></div>`;
  return;
 }
 if(conteoAbierto){pintarConteoAbierto(host);return}
 host.innerHTML=`<div class="ivCard">
<h3 style="margin:0 0 4px">Nuevo recuento</h3>
<p class="muted" style="margin:0 0 12px">Se prepara con lo que la base cree que hay, se cuenta, y sólo al validarlo se mueven existencias. Cada diferencia deja su ajuste en el Audit Trail.</p>
<div class="ivForm">
 <div><label for="ivcAlmacen">Almacén</label><select id="ivcAlmacen">${almacenes.map(a=>`<option value="${esc(a.id)}">${esc(a.name)}</option>`).join('')}</select></div>
 <div><label for="ivcReferencia">Referencia</label><input id="ivcReferencia" placeholder="Ej. Recuento septiembre"></div>
</div>
<button type="button" class="primary" id="ivcCrear" style="width:100%;margin-top:13px">Crear y generar líneas</button>
</div>
<div class="ivCard"><h3 style="margin:0 0 10px">Recuentos</h3>${
 conteos.length?`<table><tr><th>Referencia</th><th>Almacén</th><th>Estado</th><th>Creado</th><th></th></tr>`
 +conteos.map(c=>{
   const a=almacenes.find(x=>x.id===c.warehouse_id);
   return `<tr><td><b>${esc(c.reference)}</b></td><td>${esc(a?a.name:'—')}</td>
<td><span class="ivEstado ${c.status==='validated'?'ok':c.status==='cancelled'?'sobre':'bajo'}">${esc(ESTADO_CONTEO[c.status]||c.status)}</span></td>
<td>${esc(new Date(c.created_at).toLocaleDateString('es-EC'))}</td>
<td><button type="button" class="secondary" data-ivc-abrir="${esc(c.id)}">Abrir</button></td></tr>`}).join('')+'</table>'
 :'<div class="muted">Todavía no hay recuentos.</div>'}</div>`;
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
  const r=await C().insert('inventory_counts',{warehouse_id:alm,reference:ref,status:'draft'});
  if(r.error)throw r.error;
  const c=await C().db();
  const {error}=await c.rpc('gama_count_generate_lines',{p_count_id:r.data.id});
  if(error)throw error;
  window.gamaToast('Recuento creado con sus líneas.');
  await cargar();await abrirConteo(r.data.id);
 }catch(e){console.warn('[GAMA conteo]',e);window.gamaToast(mensaje(e))}
 finally{btn.disabled=false;btn.textContent=rotulo}
}

async function abrirConteo(id){
 try{
  const r=await C().list('inventory_count_lines',{eq:{count_id:id}});
  if(r.error)throw r.error;
  lineas=r.data||[];
  conteoAbierto=(conteos||[]).find(c=>c.id===id)||{id,reference:'',status:'in_progress'};
  pintar();
 }catch(e){window.gamaToast(mensaje(e))}
}

function pintarConteoAbierto(host){
 const c=conteoAbierto;
 const cerrado=c.status==='validated'||c.status==='cancelled';
 const nombre=id=>{const p=productos.find(x=>x.id===id);return p?p.name:'—'};
 host.innerHTML=`<div class="ivCard">
<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap">
 <div><h3 style="margin:0 0 3px">${esc(c.reference||'Recuento')}</h3>
 <p class="muted" style="margin:0">${esc(ESTADO_CONTEO[c.status]||c.status)} · ${lineas.length} línea${lineas.length===1?'':'s'}</p></div>
 <button type="button" class="secondary" id="ivcVolver">← Recuentos</button>
</div>
${cerrado?'<div class="ivAviso" style="margin-top:12px">Este recuento ya está cerrado: sus líneas no se pueden cambiar.</div>':''}
<div style="margin-top:14px" id="ivcLineas"></div>
${cerrado?'':'<button type="button" class="primary" id="ivcValidar" style="width:100%;margin-top:14px">Validar y ajustar existencias</button>'}
</div>`;
 $('ivcVolver').onclick=()=>{conteoAbierto=null;pintar()};
 const host2=$('ivcLineas');
 host2.innerHTML=lineas.length?'<table><tr><th>Producto</th><th>Ubicación</th><th>Esperado</th><th>Contado</th><th>Diferencia</th></tr>'
  +lineas.map(l=>{
   const dif=l.counted_quantity===null||l.counted_quantity===undefined?null:Number(l.counted_quantity)-Number(l.expected_quantity);
   return `<tr>
<td><b>${esc(nombre(l.product_id))}</b></td>
<td>${esc((ubicacion(l.location_id)||{}).code||'—')}</td>
<td>${num(l.expected_quantity)}</td>
<td>${cerrado?(l.counted_quantity===null?'—':num(l.counted_quantity)):`<input type="number" min="0" step="1" style="width:90px" value="${l.counted_quantity===null||l.counted_quantity===undefined?'':l.counted_quantity}" data-ivc-linea="${esc(l.id)}">`}</td>
<td>${dif===null?'—':`<b class="${dif<0?'low':dif>0?'ok':''}">${dif>0?'+':''}${num(dif)}</b>`}</td>
</tr>`}).join('')+'</table>'
  :'<div class="muted">Este recuento no tiene líneas: el almacén no tiene existencias registradas.</div>';
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
  const {data,error}=await c.rpc('gama_count_validate',{p_count_id:conteoAbierto.id});
  if(error)throw error;
  const n=(data&&data.adjustments)||0;
  window.gamaToast(n?`Recuento validado: ${n} ajuste${n===1?'':'s'} de existencias.`:'Recuento validado sin diferencias.');
  conteoAbierto=null;
  await cargar();pintar();
 }catch(e){console.warn('[GAMA conteo]',e);window.gamaToast(mensaje(e))}
 finally{btn.disabled=false;btn.textContent=rotulo}
}

/* ---------- ubicaciones ---------- */

function pintarUbicaciones(host){
 if(!almacenes.length){host.innerHTML='<div class="ivCard muted">No hay almacenes dados de alta.</div>';return}
 host.innerHTML=almacenes.map(a=>{
  const suyas=ubicaciones.filter(u=>u.warehouse_id===a.id);
  const hijas=pid=>suyas.filter(u=>(u.parent_id||null)===pid);
  const rama=pid=>{
   const l=hijas(pid);
   if(!l.length)return '';
   return '<ul>'+l.map(u=>{
    const dentro=quants.filter(q=>q.location_id===u.id).reduce((s,q)=>s+Number(q.quantity||0),0);
    return `<li><code>${esc(u.code)}</code> ${esc(u.name)} <span class="ivSub">· ${esc(u.type)}${dentro?` · ${num(dentro)} unidades`:''}</span>${rama(u.id)}</li>`;
   }).join('')+'</ul>';
  };
  return `<div class="ivCard"><h3 style="margin:0 0 4px">${esc(a.name)}</h3>
<p class="muted" style="margin:0 0 10px">${esc(a.code)}${a.city?' · '+esc(a.city):''}</p>
<ul class="ivArbol">${rama(null)||'<li class="muted">Sin ubicaciones.</li>'}</ul></div>`;
 }).join('');
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
},abrir,cargar,resumen,estado,sugerencia,limites,get datos(){return{almacenes,ubicaciones,quants,productos,entrante}}};
})();
