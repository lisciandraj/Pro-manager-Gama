/* GAMA — Devoluciones: lo que vuelve del cliente y lo que se devuelve al
   proveedor, en una sola pantalla.

   El módulo se sostiene sobre tres preguntas y nada más:
     1. ¿Qué vuelve?        producto + cantidad + motivo
     2. ¿Qué se hace con ello?  stock / rebut / al proveedor
     3. ¿Y con el dinero?   nada / abono / reembolso / crédito

   Todo lo demás lo pone GAMA. Se elige una salida o una recepción y de ahí
   salen el cliente o el proveedor, los productos, los precios, los impuestos y
   los documentos ligados: aquí no se vuelve a teclear nada que ya exista.

   Los límites de verdad —cuánto puede volver, cuánto se puede abonar— viven en
   el servidor. Esta pantalla los enseña para que no haya sorpresas, pero no es
   ella quien los hace cumplir. */
(function(){
'use strict';
if(window.GamaReturns)return;
const ID='returns',$=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const T=s=>window.GamaI18n?.t?.(s)||s;
const money=v=>window.GamaCurrency.format(v);
const num=(v,d)=>window.GamaCurrency.number(v,d??0);
const allowed=()=>!!window.gamaAccessAllowed?.(ID);
const day=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());

const TABS=[['customer','Devoluciones de clientes'],['supplier','Devoluciones a proveedores']];
const REASON={defective:'Producto defectuoso',damaged:'Producto dañado',wrong_product:'Producto equivocado',
 wrong_quantity:'Cantidad equivocada',order_error:'Error de pedido',commercial:'Devolución comercial',other:'Otro'};
const STATUS={to_process:'Por tratar',received:'Recibida',processed:'Tratada',shipped:'Expedida',
 credited:'Abono recibido',closed:'Cerrada',cancelled:'Anulada'};
const DISPOSITION={restocked:'Reponer en stock',scrapped:'Al rebut',to_supplier:'Devolver al proveedor'};
const FINANCIAL={none:'Sin reembolso',credit:'Emitir un abono',refund:'Reembolsar al cliente',store_credit:'Crédito para el cliente'};

const ERRORS={
 ROLE_NOT_ALLOWED:'Tu perfil no tiene acceso a las devoluciones.',
 AUTH_REQUIRED:'Vuelve a iniciar sesión para continuar.',
 NOT_ALLOWED:'Tu perfil no puede hacer esta operación.',
 RETURN_NOT_FOUND:'Esa devolución ya no existe. Actualiza la lista.',
 RETURN_CLOSED:'La devolución está cerrada o anulada: ya no se modifica.',
 RETURN_ALREADY_STARTED:'La mercancía ya se ha movido: la devolución no se puede anular ni borrar.',
 SOURCE_NOT_FOUND:'Ese documento de origen ya no existe.',
 NO_LINES:'Indica al menos una cantidad a devolver.',
 INVALID_LINE:'Esa línea no pertenece al documento elegido.',
 RETURN_EXCEEDS_DELIVERED:'No se puede devolver más de lo entregado menos lo ya devuelto.',
 RETURN_EXCEEDS_RECEIVED:'No se puede devolver más de lo recibido menos lo ya devuelto.',
 ALREADY_RECEIVED:'Esta devolución ya se había recibido.',
 ALREADY_SHIPPED:'Esta devolución ya se había expedido.',
 NOT_RECEIVED:'Primero registra la recepción de la mercancía.',
 LINE_ALREADY_PROCESSED:'Esa línea ya se trató: no se trata dos veces.',
 INVALID_DISPOSITION:'Elige qué hacer con el producto.',
 RETURN_HOLD_MISSING:'La retención de la mercancía ha cambiado. Actualiza la ficha.',
 LOCATION_NOT_FOUND:'Elige una ubicación de destino válida.',
 INSUFFICIENT_STOCK:'No hay bastante stock disponible en esa ubicación.',
 INVOICE_REQUIRED:'Para emitir un abono, la devolución tiene que venir de una factura.',
 CREDIT_EXCEEDS_INVOICE:'Los abonos superarían el importe de la factura.',
 REFUND_EXCEEDS_RETURN:'El reembolso superaría el importe de la devolución.',
 METHOD_REQUIRED:'Indica el medio de pago.',
 INVALID_AMOUNT:'El importe tiene que ser mayor que cero.',
 NOT_PROCESSED:'Trata todas las líneas antes de cerrar.',
 NOT_SHIPPED:'Expide la devolución antes de cerrarla.',
 FILE_TOO_LARGE:'El archivo pesa demasiado. El máximo son 2,5 MB.',
 TOO_MANY_FILES:'Ya hay seis archivos en esta devolución.',
 FILE_NOT_FOUND:'Ese archivo ya no existe.',
 INVALID_PERIOD:'La fecha de fin es anterior a la de inicio.',
 INVALID_ACTION:'Esa operación no existe en este módulo.'};
function err(e){
 const s=String(e?.message||e);
 for(const[k,v]of Object.entries(ERRORS)){if(s.includes(k))return T(v);if(s===T(v))return T(v)}
 return T('No se pudo completar la operación. Inténtalo de nuevo.');
}
/* El diálogo compartido traduce los errores que conoce; los de este módulo
   viajan ya traducidos para que no los envuelva en el mensaje genérico. */
function reject(code){return Object.assign(Error(code),{gamaMessage:err(code)})}

let tab='customer',state={},detailId=null,generation=0;
let filters={status:'',partner:'',from:'',to:'',search:'',all_dates:true};

async function rpc(action,data={}){
 if(!allowed())throw Error('ROLE_NOT_ALLOWED');
 await window.GamaCloudReady;
 const c=await GamaCloud.db();
 const r=await c.rpc('gama_returns_action',{p_action:action,p_data:data});
 if(r.error)throw Object.assign(Error(String(r.error?.message||r.error)),{gamaMessage:err(r.error)});
 if(r.data==null)throw reject('EMPTY');
 return r.data;
}
async function mutate(action,data){
 const r=await rpc(action,data);
 window.dispatchEvent(new CustomEvent('gama:stock-cloud-change'));
 window.dispatchEvent(new CustomEvent('gama:returns-change'));
 return r;
}

function css(){
 if($('grStyle'))return;const s=document.createElement('style');s.id='grStyle';
 /* Los mismos radios, grises y verde azulado que el resto de GAMA. Los campos
    van a 16 px y 42 px de alto: por debajo de eso el móvil hace zoom al
    tocarlos, y una devolución se registra a menudo de pie en el almacén. */
 s.textContent=`#returns{display:none}#returns.active{display:block}
.grNav{display:flex;gap:6px;overflow:auto;margin:14px 0;padding-bottom:4px}
.grNav button{border:1px solid var(--arc-line-strong);background:#fff;color:var(--arc-text);border-radius:999px;padding:9px 14px;font-weight:800;white-space:nowrap;cursor:pointer;min-height:42px}
.grNav button.on{background:var(--arc-accent-600);border-color:var(--arc-accent-600);color:#fff}
.grCard{background:#fff;border:1px solid var(--arc-line-strong);border-radius:13px;padding:17px;margin:12px 0;overflow-wrap:anywhere}
.grCard h3{margin:0 0 10px;font-size:16px;color:var(--arc-text)}
.grKpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(165px,1fr));gap:12px;margin:14px 0}
.grKpis .grCard{margin:0}
.grKpis small{display:block;color:var(--arc-text-muted);font-size:12px;font-weight:700}
.grKpis strong{display:block;font-size:24px;margin-top:7px;color:var(--arc-text)}
.grTools{display:flex;gap:10px;flex-wrap:wrap;align-items:end;margin:12px 0}
.grTools label{flex:1;min-width:150px;font-size:13px;color:var(--arc-text);font-weight:700}
.grTools input,.grTools select{width:100%;font-size:16px;min-height:42px;border:1px solid var(--arc-line-strong);border-radius:9px;padding:9px;background:#fff;color:var(--arc-text)}
.grScroll{overflow:auto}
.grTable{width:100%;border-collapse:collapse;min-width:640px}
.grTable th,.grTable td{text-align:left;padding:11px;border-bottom:1px solid var(--arc-line-strong);vertical-align:top;font-size:13px}
.grTable th{font-size:12px;color:var(--arc-navy-700);font-weight:800}
.grTable tbody tr:nth-child(even){background:var(--arc-surface-3)}
.grTable td.grNum,.grTable th.grNum{text-align:right;white-space:nowrap}
.grBadge{display:inline-block;border-radius:18px;padding:4px 10px;background:var(--arc-surface-3);color:var(--arc-navy-700);font-weight:700;font-size:12px}
.grBadge[data-s=to_process]{background:var(--arc-danger-bg);color:var(--arc-danger)}
.grBadge[data-s=received]{background:var(--arc-warning-bg);color:var(--arc-warning)}
.grBadge[data-s=shipped]{background:var(--arc-warning-bg);color:var(--arc-warning)}
.grBadge[data-s=processed]{background:var(--arc-accent-100);color:var(--arc-navy-600)}
.grBadge[data-s=credited]{background:var(--arc-accent-100);color:var(--arc-navy-600)}
.grBadge[data-s=closed]{background:var(--arc-success-bg);color:var(--arc-success)}
.grBadge[data-s=cancelled]{background:var(--arc-surface-3);color:var(--arc-text-muted)}
.grBadge[data-s=customer]{background:var(--arc-accent-100);color:var(--arc-navy-600)}
.grBadge[data-s=supplier]{background:var(--arc-fam-sales-bg);color:var(--arc-fam-sales)}
.grActions{display:flex;gap:9px;flex-wrap:wrap;margin-top:11px}
.grActions button{min-height:44px}
.grBig{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin:12px 0}
.grBig button{min-height:86px;font-size:16px;font-weight:800;border-radius:13px;padding:14px}
.grHint{font-size:13px;color:var(--arc-text-muted);margin:7px 0}
.grError{color:var(--arc-danger);font-weight:700}
.grGrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:11px}
.grGrid label,.grField{font-size:13px;color:var(--arc-text);font-weight:700;display:block}
.grField{margin-top:11px}
.grGrid input,.grGrid select,.grGrid textarea,.grField input,.grField select,.grField textarea{width:100%;box-sizing:border-box;font-size:16px;min-height:42px;border:1px solid var(--arc-line-strong);border-radius:9px;padding:9px;background:#fff;color:var(--arc-text)}
.grGrid[hidden],.grCard[hidden],.grField[hidden]{display:none}
.grDocs{display:flex;gap:9px;flex-wrap:wrap}
.grDocs button{min-height:40px}
.grSteps{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px;font-size:12px;color:var(--arc-text-muted);font-weight:700}
.grSteps span[aria-current=step]{color:var(--arc-accent-600)}
.grDl{display:grid;grid-template-columns:auto 1fr;gap:5px 14px;margin:0;font-size:13px}
.grDl dt{color:var(--arc-text-muted);font-weight:700}
.grDl dd{margin:0;color:var(--arc-text)}
.grLine{border-top:1px solid var(--arc-line);padding:12px 0}
.grLine:first-child{border-top:0}
@media(max-width:700px){.grKpis{grid-template-columns:1fr 1fr}.grKpis strong{font-size:20px}
 .grTable{min-width:560px}.grTools label{min-width:130px}.grBig{grid-template-columns:1fr}}
@media(max-width:430px){.grKpis{grid-template-columns:1fr}.grDl{grid-template-columns:1fr}
 .grDl dd{margin-bottom:6px}}`;
 document.head.appendChild(s);
}

function shell(){
 css();let s=$(ID);
 if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 s.innerHTML=GamaUI.header({title:'↩️ Devoluciones',lead:'Lo que vuelve del cliente y lo que se devuelve al proveedor.'})
  +'<nav class="grNav" id="grNav"></nav><div id="grMain" aria-live="polite"></div>';
 GamaUI.bindBack(s);window.showTab?.(ID);
 return s;
}
function nav(){
 const host=$('grNav');if(!host)return;
 host.innerHTML=TABS.map(([k,label])=>`<button type="button" data-gi-live data-gr-tab="${k}" class="${tab===k&&!detailId?'on':''}" aria-current="${tab===k&&!detailId?'page':'false'}">${esc(label)}</button>`).join('');
 host.querySelectorAll('[data-gr-tab]').forEach(b=>b.onclick=()=>{detailId=null;tab=b.dataset.grTab;filters.partner='';go()});
}
function busy(){$('grMain').innerHTML=`<p class="grCard">${tr('Cargando…')}</p>`}
function fail(e,retry){
 $('grMain').innerHTML=`<div class="grCard"><p class="grError" role="alert">${esc(err(e))}</p>
 <button class="secondary" id="grRetry">${tr('Actualizar')}</button></div>`;
 $('grRetry').onclick=retry;
}
function badge(map,v){return `<span class="grBadge" data-s="${esc(v)}">${tr(map[v]||v)}</span>`}
function kpi(label,value){return `<div class="grCard"><small>${tr(label)}</small><strong>${esc(value)}</strong></div>`}
const val=(el,id)=>el.querySelector('#'+id)?.value||'';
const numval=(el,id)=>Number(String(val(el,id)).replace(',','.'));
function options(map,selected){
 return Object.entries(map).map(([k,v])=>`<option value="${k}" ${selected===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('');
}
function locationOptions(){
 return (state.overview?.locations||[]).map(l=>`<option value="${esc(l.id)}">${esc(l.code)} · ${esc(l.name)}</option>`).join('');
}
function rights(){return state.overview?.rights||{}}

/* ------------------------------------------------------------------ lista */
async function go(){
 const token=++generation;
 if(!$(ID)?.isConnected||!$('grMain'))shell();
 nav();busy();
 try{
  const d=await rpc('overview',{kind:tab,all_dates:filters.all_dates,
   status:filters.status||null,from:filters.from||null,to:filters.to||null,search:filters.search,
   ...(tab==='customer'?{customer_id:filters.partner||null}:{supplier_id:filters.partner||null})});
  if(token!==generation)return;
  state.overview=d;
  if(detailId){await detail(detailId);return}
  list(d);
 }catch(e){if(token===generation)fail(e,go)}
}
function list(d){
 const partners=tab==='customer'?d.customers:d.suppliers;
 $('grMain').innerHTML=`
 <div class="grKpis">
  ${kpi('Devoluciones abiertas',num(d.kpis.open))}
  ${kpi('Por tratar',num(d.kpis.to_process))}
  ${kpi('Abonos o reembolsos pendientes',num(d.kpis.financial_pending))}
  ${kpi('Cerradas este mes',num(d.kpis.closed_month))}
 </div>
 <div class="grTools">
  <label data-gi-live>${tab==='customer'?esc(T('Cliente')):esc(T('Proveedor'))}
   <select id="grPartner"><option value="" data-gi-live data-gi=bd02b9a7d71d>Todos</option>${partners.map(p=>`<option value="${esc(p.id)}" ${filters.partner===p.id?'selected':''}>${esc(p.name)}</option>`).join('')}</select></label>
  <label data-gi-live data-gi=98e5acddb6c4>Estado<select id="grStatus"><option value="" data-gi-live data-gi=bd02b9a7d71d>Todos</option>${options(STATUS,filters.status)}</select></label>
  <label data-gi-live data-gi=8b4e93e928df>Desde<input id="grFrom" type="date" value="${esc(filters.from)}"></label>
  <label data-gi-live data-gi=3c83e3558107>Hasta<input id="grTo" type="date" value="${esc(filters.to)}"></label>
  <label data-gi-live data-gi=5f55edf90089>Buscar<input id="grSearch" type="search" value="${esc(filters.search)}" placeholder="RET-000014"></label>
 </div>
 ${rights().create?`<div class="grActions"><button class="primary" id="grNew">${tr('+ Nueva devolución')}</button></div>`:''}
 <div class="grCard"><h3 data-gi-live data-gi=6c97bc52f46d>Análisis</h3><div id="grStats"><button class="secondary" id="grStatsLoad">${tr('Ver las cifras del periodo')}</button></div></div>
 <div class="grCard grScroll">
  <table class="grTable"><thead><tr>
   <th data-gi-live data-gi=10ddff5fcc6f>Referencia</th><th data-gi-live data-gi=3868d2843d59>Tipo</th>
   <th data-gi-live>${tab==='customer'?esc(T('Cliente')):esc(T('Proveedor'))}</th>
   <th data-gi-live data-gi=93b2a9ef782c>Fecha</th><th class="grNum" data-gi-live data-gi=572a3acfd983>Importe</th>
   <th data-gi-live data-gi=98e5acddb6c4>Estado</th><th data-gi-live data-gi=212e06c386ff>Acción</th></tr></thead>
  <tbody>${d.rows.length?d.rows.map(r=>`<tr>
   <td><b>${esc(r.number)}</b></td>
   <td>${badge({customer:'Cliente',supplier:'Proveedor'},r.kind)}</td>
   <td>${esc(r.partner||'—')}</td>
   <td>${esc(r.created_on)}</td>
   <td class="grNum">${esc(money(r.amount))}</td>
   <td>${badge(STATUS,r.status)}</td>
   <td><button class="secondary" data-gr-open="${esc(r.id)}">${tr('Abrir')}</button></td>
  </tr>`).join(''):`<tr><td colspan="7">${tr('Todavía no hay ninguna devolución con estos filtros.')}</td></tr>`}</tbody></table>
 </div>`;
 const reload=()=>{filters.partner=val(document,'grPartner');filters.status=val(document,'grStatus');
  filters.from=val(document,'grFrom');filters.to=val(document,'grTo');
  filters.all_dates=!filters.from&&!filters.to;go()};
 ['grPartner','grStatus','grFrom','grTo'].forEach(id=>{const el=$(id);if(el)el.onchange=reload});
 let timer;const search=$('grSearch');
 if(search)search.oninput=()=>{clearTimeout(timer);timer=setTimeout(()=>{filters.search=search.value;go()},350)};
 $('grStatsLoad')?.addEventListener('click',()=>stats());
 $('grNew')?.addEventListener('click',()=>wizardKind());
 $('grMain').querySelectorAll('[data-gr-open]').forEach(b=>b.onclick=()=>{detailId=b.dataset.grOpen;go()});
}

/* Las cifras del pliego: cuántas, cuánto valen, qué proporción de lo expedido,
   por qué vuelven, qué vuelve más y de qué proveedores. */
async function stats(){
 const host=$('grStats');if(!host)return;
 host.innerHTML=`<p>${tr('Cargando…')}</p>`;
 try{
  const d=await rpc('stats',{from:filters.from||null,to:filters.to||null});
  const listOf=(rows,label,value)=>rows.length
   ?`<ul>${rows.map(r=>`<li>${esc(label(r))} · ${esc(value(r))}</li>`).join('')}</ul>`
   :`<p class="grHint">${tr('Sin datos todavía.')}</p>`;
  host.innerHTML=`
   <div class="grKpis">
    ${kpi('Devoluciones este mes',num(d.month_count))}
    ${kpi('Valor devuelto este mes',money(d.month_value))}
    ${kpi('Tasa de devolución',num(d.return_rate,2)+' %')}
   </div>
   <p><b>${tr('Motivos más frecuentes')}</b></p>
   ${listOf(d.reasons,r=>T(REASON[r.reason]||r.reason),r=>num(r.n))}
   <p><b>${tr('Productos más devueltos')}</b></p>
   ${listOf(d.products,r=>r.product,r=>num(r.quantity,3))}
   <p><b>${tr('Proveedores con devoluciones')}</b></p>
   ${listOf(d.suppliers,r=>r.supplier,r=>num(r.n))}`;
 }catch(e){host.innerHTML=`<p class="grError" role="alert">${esc(err(e))}</p>`}
}

/* ------------------------------------------------- crear en tres pantallas */
/* Paso 1: qué clase de devolución. Dos botones grandes y nada más. */
function wizardKind(){
 const el=window.GamaSales.modal(T('Nueva devolución'),
  `<p class="grSteps"><span aria-current="step">${tr('1 · Tipo')}</span><span>${tr('2 · Documento')}</span><span>${tr('3 · Productos')}</span></p>
   <div class="grBig">
    <button type="button" class="secondary" data-gr-kind="customer">${tr('↩️ Devolución de un cliente')}</button>
    <button type="button" class="secondary" data-gr-kind="supplier">${tr('📦 Devolución a un proveedor')}</button>
   </div>`,T('Volver'),async()=>{});
 /* No hay nada que guardar en este paso: la elección es el botón. */
 el.querySelector('#gsSave').remove();
 el.querySelectorAll('[data-gr-kind]').forEach(b=>b.onclick=()=>{el.remove();wizardSource(b.dataset.grKind)});
}
/* Paso 2: de qué documento viene. La lista trae lo que hace falta para
   reconocerlo —número, quién y cuántas líneas—, nada más. */
async function wizardSource(kind){
 let el;
 try{
  const d=await rpc('sources',{kind});
  el=window.GamaSales.modal(T(kind==='customer'?'¿De qué entrega vuelve?':'¿De qué recepción vuelve?'),
   `<p class="grSteps"><span>${tr('1 · Tipo')}</span><span aria-current="step">${tr('2 · Documento')}</span><span>${tr('3 · Productos')}</span></p>
    <label class="grField" data-gi-live data-gi=5f55edf90089>Buscar<input id="grSrcSearch" type="search" placeholder="${esc(T('Número o nombre'))}"></label>
    <div id="grSrcList" class="grScroll"></div>`,T('Volver'),async()=>{});
  el.querySelector('#gsSave').remove();
  const draw=q=>{
   const rows=d.rows.filter(r=>!q||`${r.number} ${r.partner}`.toLowerCase().includes(q.toLowerCase()));
   el.querySelector('#grSrcList').innerHTML=rows.length?`<table class="grTable"><tbody>${rows.slice(0,60).map(r=>`<tr>
     <td><b>${esc(r.number)}</b><br>${esc(r.partner)}</td>
     <td>${esc(String(r.dispatched_at||r.order_date||'').slice(0,10))}</td>
     <td><button class="secondary" data-gr-src="${esc(r.id)}">${tr('Elegir')}</button></td></tr>`).join('')}</tbody></table>`
    :`<p class="grHint">${tr('No hay ningún documento con mercancía que se pueda devolver.')}</p>`;
   el.querySelectorAll('[data-gr-src]').forEach(b=>b.onclick=()=>{el.remove();wizardLines(kind,b.dataset.grSrc)});
  };
  draw('');
  el.querySelector('#grSrcSearch').oninput=e=>draw(e.target.value);
 }catch(e){window.gamaToast?.(err(e))}
}
/* Paso 3: cuánto vuelve y por qué. El usuario sólo teclea cantidades: el
   producto, el precio, el impuesto y la factura ya vienen del documento. */
async function wizardLines(kind,sourceId){
 try{
  const d=await rpc('source_lines',{kind,source_id:sourceId});
  const rows=d.rows.filter(r=>Number(r.max_return)>0);
  if(!rows.length){window.gamaToast?.(T('Ya se ha devuelto todo lo de ese documento.'));return}
  const el=window.GamaSales.modal(T('¿Qué vuelve?'),
   `<p class="grSteps"><span>${tr('1 · Tipo')}</span><span>${tr('2 · Documento')}</span><span aria-current="step">${tr('3 · Productos')}</span></p>
    <dl class="grDl">
     <dt data-gi-live>${kind==='customer'?esc(T('Cliente')):esc(T('Proveedor'))}</dt><dd>${esc(d.partner)}</dd>
     <dt data-gi-live data-gi=cf4279e00d07>Documento</dt><dd>${esc(d.number)}</dd>
     ${d.order_number?`<dt data-gi-live data-gi=9e9ea5774a2d>Pedido</dt><dd>${esc(d.order_number)}</dd>`:''}
    </dl>
    <div class="grScroll"><table class="grTable"><thead><tr>
     <th data-gi-live data-gi=77b9238931ed>Producto</th><th class="grNum" data-gi-live>${kind==='customer'?esc(T('Entregado')):esc(T('Recibido'))}</th>
     <th class="grNum" data-gi-live data-gi=5bf06abda5a9>Ya devuelto</th><th class="grNum" data-gi-live data-gi=beeb6864c175>A devolver</th></tr></thead>
     <tbody>${rows.map(r=>`<tr>
      <td><b>${esc(r.product)}</b><br><span class="grHint">${esc(r.reference||'')}</span></td>
      <td class="grNum">${esc(num(r.moved,3))}</td>
      <td class="grNum">${esc(num(r.returned,3))}</td>
      <td class="grNum"><input data-gr-qty="${esc(r.line_id)}" type="number" inputmode="decimal" min="0" step="0.001"
        max="${esc(r.max_return)}" value="0" style="width:96px;min-height:42px;font-size:16px;text-align:right"></td>
     </tr>`).join('')}</tbody></table></div>
    <label class="grField" data-gi-live data-gi=c7b288b1c0bb>Motivo<select id="grReason">${options(REASON,'defective')}</select></label>
    <label class="grField" id="grNotesBox" hidden data-gi-live data-gi=53c367898434>Comentario<textarea id="grNotes" rows="2" maxlength="600"></textarea></label>
    <label class="grField" data-gi-live data-gi=436b1e704da4>Foto o documento (opcional)<input id="grFile" type="file" accept="image/png,image/jpeg,image/webp,application/pdf"></label>`,
   T('Crear la devolución'),
   async el=>{
    const lines=[...el.querySelectorAll('[data-gr-qty]')]
     .map(i=>({line_id:i.dataset.grQty,quantity:Number(String(i.value).replace(',','.'))}))
     .filter(l=>l.quantity>0);
    if(!lines.length)throw reject('NO_LINES');
    const r=await mutate('create',{kind,source_id:sourceId,invoice_id:d.invoice_id||null,
     reason:val(el,'grReason'),notes:val(el,'grNotes'),lines});
    const file=el.querySelector('#grFile').files[0];
    if(file)await attach(r.id,file);
    detailId=r.id;await go();
    window.gamaToast?.(T('Devolución creada')+' · '+r.number);
   });
  const reason=el.querySelector('#grReason');
  reason.onchange=()=>{el.querySelector('#grNotesBox').hidden=reason.value!=='other'};
 }catch(e){window.gamaToast?.(err(e))}
}
/* Los adjuntos viajan como data URL: GAMA no tiene bucket de archivos y una
   foto de móvil reducida cabe de sobra en el límite del servidor. */
async function attach(id,file){
 if(file.size>2500000){window.gamaToast?.(T('El archivo pesa demasiado. El máximo son 2,5 MB.'));return}
 const data=await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(r.result);r.onerror=rej;r.readAsDataURL(file)});
 await mutate('file_add',{id,filename:file.name,mime_type:file.type,data_url:data});
}

/* ------------------------------------------------------------------ ficha */
async function detail(id){
 const token=generation;
 try{
  const d=await rpc('detail',{id});
  if(token!==generation)return;
  state.detail=d;
  const r=rights(),customer=d.kind==='customer';
  const pending=d.lines.filter(l=>!l.processed_at).length;
  const open=!['closed','cancelled'].includes(d.status);
  const outstanding=Math.max(0,Number(d.amount)-Number(d.refunded||0));
  $('grMain').innerHTML=`
  <div class="grActions"><button class="secondary" id="grBack">${tr('← Volver a la lista')}</button></div>
  <div class="grCard">
   <h3>${esc(d.number)} · ${badge(STATUS,d.status)}</h3>
   <dl class="grDl">
    <dt data-gi-live>${customer?esc(T('Cliente')):esc(T('Proveedor'))}</dt><dd>${esc(d.partner||'—')}</dd>
    <dt data-gi-live data-gi=c7b288b1c0bb>Motivo</dt><dd>${tr(REASON[d.reason]||d.reason)}</dd>
    <dt data-gi-live data-gi=572a3acfd983>Importe</dt><dd>${esc(money(d.amount))}</dd>
    ${d.notes?`<dt data-gi-live data-gi=53c367898434>Comentario</dt><dd>${esc(d.notes)}</dd>`:''}
    ${d.carrier?`<dt data-gi-live data-gi=42b1efe4956b>Transportista</dt><dd>${esc(d.carrier)}</dd>`:''}
    ${d.tracking?`<dt data-gi-live data-gi=9d890b826ee8>Número de seguimiento</dt><dd>${esc(d.tracking)}</dd>`:''}
    ${d.shipped_on?`<dt data-gi-live data-gi=20b759731550>Expedida el</dt><dd>${esc(d.shipped_on)}</dd>`:''}
   </dl>
   ${documents(d)}
  </div>

  <div class="grCard">
   <h3 data-gi-live>${customer?esc(T('1 · Qué vuelve y qué se hace con ello')):esc(T('1 · Qué se devuelve'))}</h3>
   ${d.lines.map(l=>`<div class="grLine">
     <b>${esc(l.product)}</b> · ${esc(num(l.quantity,3))} × ${esc(money(l.unit_price))} = ${esc(money(l.amount))}
     <p class="grHint">${l.processed_at?tr(DISPOSITION[l.disposition]||l.disposition):tr('Pendiente de decidir')}${l.notes?' · '+esc(l.notes):''}</p>
     ${customer&&open&&r.process&&d.status==='received'&&!l.processed_at
       ?`<div class="grActions"><button class="primary" data-gr-process="${esc(l.id)}">${tr('Decidir qué se hace')}</button></div>`:''}
    </div>`).join('')}
   <div class="grActions">
    ${customer&&open&&r.process&&d.status==='to_process'?`<button class="primary" id="grReceive">${tr('📥 Registrar la recepción')}</button>`:''}
    ${!customer&&open&&r.process&&d.status==='to_process'?`<button class="primary" id="grShip">${tr('🚚 Registrar la expedición')}</button>`:''}
   </div>
   ${customer&&d.status==='received'&&pending?`<p class="grHint">${tr('La mercancía está retenida: no cuenta como disponible hasta que decidas.')}</p>`:''}
  </div>

  <div class="grCard">
   <h3 data-gi-live data-gi=57897bf4c575>2 · Qué se hace con el dinero</h3>
   <dl class="grDl">
    <dt data-gi-live data-gi=0caa6150f308>Decisión</dt><dd>${tr(FINANCIAL[d.financial_action]||d.financial_action)}</dd>
    ${customer?`<dt data-gi-live data-gi=9ceadf9e7265>Reembolsado</dt><dd>${esc(money(d.refunded))} · ${tr('pendiente')} ${esc(money(outstanding))}</dd>`:''}
   </dl>
   ${d.credits.map(c=>`<p>${tr('Abono')} <b>${esc(c.number)}</b> · ${esc(money(c.amount))} · ${esc(c.issued_on)}${c.supplier_reference?' · '+esc(c.supplier_reference):''}</p>`).join('')}
   ${d.refunds.map(f=>`<p>${tr('Reembolso')} ${esc(money(f.amount))} · ${esc(f.paid_at)} · ${esc(f.method)}${f.reference?' · '+esc(f.reference):''}</p>`).join('')}
   <div class="grActions">
    ${open&&r.refund&&customer?`<button class="secondary" id="grFinancial">${tr('Elegir la acción financiera')}</button>`:''}
    ${open&&r.refund&&customer&&d.invoice_id?`<button class="secondary" id="grCredit">${tr('🧾 Emitir un abono')}</button>`:''}
    ${open&&r.refund&&customer&&outstanding>0?`<button class="secondary" id="grRefund">${tr('💸 Reembolsar')}</button>`:''}
    ${open&&r.refund&&!customer?`<button class="secondary" id="grSupplierCredit">${tr('🧾 Registrar el abono del proveedor')}</button>`:''}
   </div>
   ${customer&&!d.invoice_id?`<p class="grHint">${tr('Esta devolución no viene de una factura: no se puede emitir un abono, sólo reembolsar.')}</p>`:''}
  </div>

  <div class="grCard">
   <h3 data-gi-live data-gi=0c2c1cf33c6e>Fotos y documentos</h3>
   ${d.files.length?`<div class="grDocs">${d.files.map(f=>`<button class="secondary" data-gr-file="${esc(f.id)}">${esc(f.filename)}</button>`).join('')}</div>`
     :`<p class="grHint">${tr('Todavía no hay ningún archivo.')}</p>`}
   ${open?`<label class="grField" data-gi-live data-gi=590f37027486>Añadir una foto o un documento<input id="grAddFile" type="file" accept="image/png,image/jpeg,image/webp,application/pdf"></label>`:''}
  </div>

  <div class="grActions">
   ${open&&(r.process||r.refund)&&(customer?d.status==='processed':['shipped','credited'].includes(d.status))
     ?`<button class="primary" id="grClose">${tr('✅ Cerrar la devolución')}</button>`:''}
   ${open&&r.create&&d.status==='to_process'?`<button class="secondary" id="grCancel">${tr('Anular')}</button>`:''}
   ${open&&r.delete&&d.status==='to_process'?`<button class="secondary" id="grDelete">${tr('Borrar')}</button>`:''}
  </div>`;
  bindDetail(d);
 }catch(e){if(token===generation)fail(e,()=>detail(id))}
}
/* Documentos ligados: se enlazan, nunca se copian. El rótulo y su destino
   salen de la misma lista para que no puedan descolgarse. */
function docLinks(d){
 const x=d.documents||{},out=[];
 if(x.order)out.push({label:T('Pedido'),number:x.order.number,open:()=>window.GamaSales?.openOrder?.(x.order.id)});
 if(x.delivery)out.push({label:T('Entrega'),number:x.delivery.number,open:()=>window.GamaSales?.openOrder?.(d.order_id)});
 if(x.invoice)out.push({label:T('Factura'),number:x.invoice.number,open:()=>window.GamaQuotes?.view?.(x.invoice.id)});
 if(x.purchase_order)out.push({label:T('Pedido de compra'),number:x.purchase_order.number,open:null});
 if(x.supplier_invoice)out.push({label:T('Factura del proveedor'),number:x.supplier_invoice.number,open:null});
 for(const c of d.credits)out.push({label:T('Abono'),number:c.number,open:null});
 return out;
}
function documents(d){
 const items=docLinks(d);
 if(!items.length)return '';
 return `<p class="grHint" data-gi-live data-gi=223e7a13aaf9>Documentos ligados</p><div class="grDocs">${items.map((x,i)=>
  `<button class="secondary" data-gr-doc="${i}">${esc(x.label)} · ${esc(x.number)}</button>`).join('')}</div>`;
}

function bindDetail(d){
 const id=d.id,main=$('grMain');
 $('grBack').onclick=()=>{detailId=null;go()};
 const docs=docLinks(d);
 main.querySelectorAll('[data-gr-doc]').forEach(b=>b.onclick=()=>{
  const link=docs[Number(b.dataset.grDoc)];
  if(link?.open)link.open();else window.gamaToast?.(T('Ese documento se consulta en su propio módulo.'));
 });
 main.querySelectorAll('[data-gr-process]').forEach(b=>b.onclick=()=>processLine(id,b.dataset.grProcess));
 main.querySelectorAll('[data-gr-file]').forEach(b=>b.onclick=()=>openFile(b.dataset.grFile));
 $('grAddFile')?.addEventListener('change',async e=>{
  const f=e.target.files[0];if(!f)return;
  try{await attach(id,f);await go()}catch(x){window.gamaToast?.(err(x))}
 });
 $('grReceive')?.addEventListener('click',()=>receiveForm(id));
 $('grShip')?.addEventListener('click',()=>shipForm(id));
 $('grFinancial')?.addEventListener('click',()=>financialForm(d));
 $('grCredit')?.addEventListener('click',()=>creditForm(d));
 $('grRefund')?.addEventListener('click',()=>refundForm(d));
 $('grSupplierCredit')?.addEventListener('click',()=>supplierCreditForm(d));
 $('grClose')?.addEventListener('click',()=>confirmAction('Cerrar la devolución',
  'Después de cerrarla ya no se modifica.',()=>mutate('close',{id})));
 $('grCancel')?.addEventListener('click',()=>confirmAction('Anular la devolución',
  'La devolución quedará anulada y las cantidades vuelven a poder devolverse.',()=>mutate('cancel',{id})));
 $('grDelete')?.addEventListener('click',()=>confirmAction('Borrar la devolución',
  'Se borra del todo. La auditoría conserva quién la borró y cuándo.',
  async()=>{await mutate('delete',{id});detailId=null}));
}

function confirmAction(title,text,run){
 window.GamaSales.modal(T(title),`<p>${tr(text)}</p>`,T('Confirmar'),async()=>{await run();await go()});
}
async function openFile(fileId){
 try{
  const f=await rpc('file_get',{id:detailId,file_id:fileId});
  if(!/^data:(image\/(png|jpeg|webp)|application\/pdf);base64,[A-Za-z0-9+/=\s]+$/.test(f.data_url||''))
   throw Error(T('El archivo no es válido.'));
  const body=f.mime_type==='application/pdf'
   ?`<p><a href="${esc(f.data_url)}" download="${esc(f.filename)}">${esc(T('Descargar'))} ${esc(f.filename)}</a></p>`
   :`<img alt="${esc(f.filename)}" src="${esc(f.data_url)}" style="max-width:100%;max-height:62vh">`;
  const el=window.GamaSales.modal(f.filename,body,T('Volver'),async()=>{});
  el.querySelector('#gsSave').remove();
 }catch(e){window.gamaToast?.(err(e))}
}
/* ------------------------------------------------------------- 1 · mercancía */
function receiveForm(id){
 window.GamaSales.modal(T('Registrar la recepción'),
  `<p>${tr('Confirma que la mercancía ha vuelto. Entra retenida en el almacén: el stock disponible no se mueve hasta que decidas qué hacer con ella.')}</p>
   <label class="grField" data-gi-live data-gi=9a91575b8e4b>Almacén<select id="grLoc" required>${locationOptions()}</select></label>`,
  T('Confirmar la recepción'),
  async el=>{await mutate('receive',{id,location_id:val(el,'grLoc')});await go()});
}
function processLine(id,lineId){
 const el=window.GamaSales.modal(T('¿Qué se hace con el producto?'),
  `<div class="grBig">
    <button type="button" class="secondary" data-gr-disp="restocked">${tr('📦 Reponer en stock')}</button>
    <button type="button" class="secondary" data-gr-disp="scrapped">${tr('🗑️ Al rebut')}</button>
    <button type="button" class="secondary" data-gr-disp="to_supplier">${tr('↪️ Devolver al proveedor')}</button>
   </div>
   <label class="grField" id="grLocBox" data-gi-live data-gi=bd3b914791dc>Almacén de destino<select id="grLoc">${locationOptions()}</select></label>
   <label class="grField" data-gi-live data-gi=53c367898434>Comentario<textarea id="grLineNotes" rows="2" maxlength="600"></textarea></label>`,
  T('Confirmar'),
  async el=>{
   const disp=el.dataset.disp;
   if(!disp)throw reject('INVALID_DISPOSITION');
   await mutate('process_line',{id,line_id:lineId,disposition:disp,
    location_id:disp==='restocked'?val(el,'grLoc'):null,notes:val(el,'grLineNotes')});
   await go();
  });
 el.querySelectorAll('[data-gr-disp]').forEach(b=>b.onclick=()=>{
  el.dataset.disp=b.dataset.grDisp;
  el.querySelectorAll('[data-gr-disp]').forEach(x=>x.className=x===b?'primary':'secondary');
  el.querySelector('#grLocBox').hidden=b.dataset.grDisp!=='restocked';
 });
}
function shipForm(id){
 window.GamaSales.modal(T('Registrar la expedición'),
  `<p>${tr('Al expedirla, la cantidad sale del stock disponible del almacén elegido.')}</p>
   <div class="grGrid">
    <label data-gi-live data-gi=a20a626a3155>Almacén de salida<select id="grLoc" required>${locationOptions()}</select></label>
    <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="grShipDate" type="date" required value="${esc(day())}"></label>
    <label data-gi-live data-gi=0b57c4a35ba5>Transportista (opcional)<input id="grCarrier" maxlength="80"></label>
    <label data-gi-live data-gi=5eb8c0f8aebb>Número de seguimiento (opcional)<input id="grTracking" maxlength="80"></label>
   </div>`,
  T('Confirmar la expedición'),
  async el=>{await mutate('ship',{id,location_id:val(el,'grLoc'),shipped_on:val(el,'grShipDate'),
   carrier:val(el,'grCarrier'),tracking:val(el,'grTracking')});await go()});
}
/* ---------------------------------------------------------------- 2 · dinero */
function financialForm(d){
 window.GamaSales.modal(T('¿Qué se hace con el dinero?'),
  `<p>${tr('Nada obliga a una decisión: un producto al rebut puede acabar reembolsado, y una devolución comercial puede no mover un céntimo.')}</p>
   <label class="grField" data-gi-live data-gi=212e06c386ff>Acción<select id="grFin">${options(FINANCIAL,d.financial_action)}</select></label>`,
  T('Guardar'),
  async el=>{await mutate('financial_action',{id:d.id,financial_action:val(el,'grFin')});await go()});
}
async function creditForm(d){
 try{
  const p=await rpc('credit_preview',{id:d.id});
  window.GamaSales.modal(T('Emitir un abono'),
   `<p>${tr('Architect calcula el importe con los precios e impuestos de la factura de origen. Puedes ajustarlo antes de validar.')}</p>
    <dl class="grDl">
     <dt data-gi-live data-gi=52c5bbc8a4eb>Factura</dt><dd>${esc(d.documents?.invoice?.number||'—')}</dd>
     <dt data-gi-live data-gi=42adf2f63a2c>Total de la factura</dt><dd>${esc(money(p.invoice_total))}</dd>
     <dt data-gi-live data-gi=238158b8a2fc>Ya abonado</dt><dd>${esc(money(p.already))}</dd>
    </dl>
    <div class="grGrid">
     <label data-gi-live data-gi=572a3acfd983>Importe<input id="grCreditAmount" type="number" inputmode="decimal" min="0.01" step="0.01" required value="${esc(p.amount)}"></label>
     <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="grCreditDate" type="date" required value="${esc(day())}"></label>
    </div>
    <label class="grField" data-gi-live data-gi=53c367898434>Comentario<textarea id="grCreditNotes" rows="2" maxlength="600"></textarea></label>`,
   T('Emitir el abono'),
   async el=>{const r=await mutate('credit',{id:d.id,amount:numval(el,'grCreditAmount'),
    issued_on:val(el,'grCreditDate'),notes:val(el,'grCreditNotes')});
    await go();window.gamaToast?.(T('Abono emitido')+' · '+r.number)});
 }catch(e){window.gamaToast?.(err(e))}
}
function refundForm(d){
 const outstanding=Math.max(0,Number(d.amount)-Number(d.refunded||0));
 const key=crypto.randomUUID();
 window.GamaSales.modal(T('Reembolsar al cliente'),
  `<div class="grGrid">
    <label data-gi-live data-gi=572a3acfd983>Importe<input id="grRefundAmount" type="number" inputmode="decimal" min="0.01" step="0.01" max="${esc(outstanding)}" required value="${esc(outstanding)}"></label>
    <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="grRefundDate" type="date" required value="${esc(day())}"></label>
    <label data-gi-live data-gi=25ec5eda3d03>Medio de pago<input id="grRefundMethod" required maxlength="60" placeholder="${esc(T('Transferencia'))}"></label>
    <label data-gi-live data-gi=f9403c06f4cb>Referencia (opcional)<input id="grRefundRef" maxlength="80"></label>
   </div>`,
  T('Registrar el reembolso'),
  async el=>{await mutate('refund',{id:d.id,request_key:key,amount:numval(el,'grRefundAmount'),
   paid_at:val(el,'grRefundDate'),method:val(el,'grRefundMethod'),reference:val(el,'grRefundRef')});await go()});
}
function supplierCreditForm(d){
 window.GamaSales.modal(T('Registrar el abono del proveedor'),
  `<p>${tr('Este abono lo emite el proveedor: aquí sólo se registra lo que ha mandado.')}</p>
   <div class="grGrid">
    <label data-gi-live data-gi=693a35ea5e01>Referencia del proveedor<input id="grScRef" maxlength="80"></label>
    <label data-gi-live data-gi=572a3acfd983>Importe<input id="grScAmount" type="number" inputmode="decimal" min="0.01" step="0.01" required value="${esc(d.amount)}"></label>
    <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="grScDate" type="date" required value="${esc(day())}"></label>
   </div>
   <label class="grField" data-gi-live data-gi=007788edb9bb>Documento (opcional)<input id="grScFile" type="file" accept="image/png,image/jpeg,image/webp,application/pdf"></label>`,
  T('Validar'),
  async el=>{
   const file=el.querySelector('#grScFile').files[0];
   let payload={id:d.id,supplier_reference:val(el,'grScRef'),amount:numval(el,'grScAmount'),issued_on:val(el,'grScDate')};
   if(file){
    if(file.size>2500000)throw reject('FILE_TOO_LARGE');
    payload.filename=file.name;payload.mime_type=file.type;
    payload.data_url=await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(r.result);r.onerror=rej;r.readAsDataURL(file)});
   }
   await mutate('supplier_credit',payload);await go();
  });
}

/* ----------------------------------------------------------------- entradas */
function open(which){
 if(!allowed()){window.gamaToast?.(T('Tu perfil no tiene acceso a las devoluciones.'));return}
 if(which==='customer'||which==='supplier')tab=which;
 detailId=null;shell();go();
}
/* Desde una entrega o una recepción: el botón «Crear una devolución» llega
   aquí con el documento ya elegido y el usuario sólo teclea cantidades. */
function createFrom(kind,sourceId){
 if(!allowed()){window.gamaToast?.(T('Tu perfil no tiene acceso a las devoluciones.'));return}
 tab=kind;detailId=null;shell();
 rpc('overview',{kind,all_dates:true}).then(d=>{state.overview=d;nav();list(d);wizardLines(kind,sourceId)})
  .catch(e=>fail(e,()=>go()));
}
function openReturn(id){
 if(!allowed())return;
 detailId=id;shell();go();
}
window.addEventListener('gama:currency-change',()=>{if($(ID)?.classList.contains('active'))go()});
window.GamaReturns={open,openReturn,createFrom,rpc,REASON,STATUS,DISPOSITION,FINANCIAL};
})();
