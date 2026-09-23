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
if(window.GamaReturns&&!window.GamaReturns.__arcLazy)return;
const ID='returns',$=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const T=s=>window.GamaI18n?.t?.(s)||s;
const money=v=>window.GamaCurrency.format(v);
const num=(v,d)=>window.GamaCurrency.number(v,d??0);
const allowed=()=>!!window.gamaAccessAllowed?.(ID);
const day=()=>new Intl.DateTimeFormat('en-CA',{timeZone:(globalThis.window?.GamaCompany?.get()?.timezone||'America/Guayaquil'),year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());

/* Dos procesos, como la venta (PDV) y la compra (PDC): la devolución de un
   cliente (PRC) y la devolución a un proveedor (PRP). Cada devolución lleva un
   número que comparten todos sus documentos —DEV, abono NCR, reembolso REE—, y
   se sigue en etapas numeradas. */
const TABS=[['customer','PRC · Devolución de cliente'],['supplier','PRP · Devolución a proveedor']];
const processNumber=(kind,ref)=>{const m=String(ref||'').match(/(\d{1,8})$/);return m?(kind==='supplier'?'PRP':'PRC')+'-'+m[1].padStart(8,'0'):String(ref||'')};
const STEP_STATES={done:'Completado',active:'En curso',blocked:'Bloqueado',pending:'Pendiente',closed:'Cerrado'};
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
 const r=await window.ArcData.rawRpc('gama_returns_action',{p_action:action,p_data:data});
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

function css(){ /* Styles are compiled in architect-components.css. */ }

function shell(){
 css();let s=$(ID);
 if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 window.ArcUI.render(s,GamaUI.header({title:'↩️ Devoluciones',lead:'Lo que vuelve del cliente y lo que se devuelve al proveedor.'})
  +'<nav class="grNav" id="grNav"></nav><div id="grMain" aria-live="polite"></div>');
 GamaUI.bindBack(s);window.showTab?.(ID);
 return s;
}
function nav(){
 const host=$('grNav');if(!host)return;
 window.ArcUI.render(host,TABS.map(([k,label])=>`<button type="button" data-gi-live data-gr-tab="${k}" class="arcButton ${tab===k&&!detailId?'on':''}" aria-current="${tab===k&&!detailId?'page':'false'}">${esc(label)}</button>`).join(''));
 host.querySelectorAll('[data-gr-tab]').forEach(b=>b.onclick=()=>{detailId=null;tab=b.dataset.grTab;filters.partner='';go()});
}
function busy(){window.ArcUI.render($('grMain'),`<p class="arcPanel grCard">${tr('Cargando…')}</p>`)}
function fail(e,retry){
 window.ArcUI.render($('grMain'),`<div class="arcPanel grCard"><p class="grError" role="alert">${esc(err(e))}</p>
 <button class="arcButton secondary" id="grRetry">${tr('Actualizar')}</button></div>`);
 $('grRetry').onclick=retry;
}
function badge(map,v){return `<span class="arcStatusBadge grBadge" data-s="${esc(v)}">${tr(map[v]||v)}</span>`}
function kpi(label,value){return `<div class="arcPanel grCard"><small>${tr(label)}</small><strong>${esc(value)}</strong></div>`}
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
 window.ArcUI.render($('grMain'),`
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
 ${rights().create?`<div class="grActions"><button class="arcButton primary" id="grNew">${tr('+ Nueva devolución')}</button></div>`:''}
 <div class="arcPanel grCard"><h3 data-gi-live data-gi=6c97bc52f46d>Análisis</h3><div id="grStats"><button class="arcButton secondary" id="grStatsLoad">${tr('Ver las cifras del periodo')}</button></div></div>
 <div class="arcPanel grCard grScroll">
  <table class="arcTable grTable"><thead><tr>
   <th data-gi-live data-gi=10ddff5fcc6f>Referencia</th><th data-gi-live data-gi=3868d2843d59>Tipo</th>
   <th data-gi-live>${tab==='customer'?esc(T('Cliente')):esc(T('Proveedor'))}</th>
   <th data-gi-live data-gi=93b2a9ef782c>Fecha</th><th class="grNum" data-gi-live data-gi=572a3acfd983>Importe</th>
   <th data-gi-live data-gi=98e5acddb6c4>Estado</th><th data-gi-live data-gi=212e06c386ff>Acción</th></tr></thead>
  <tbody>${d.rows.length?d.rows.map(r=>`<tr>
   <td><b>${esc(processNumber(r.kind||tab,r.number))}</b><small class="grRef">${esc(r.number)}</small></td>
   <td>${badge({customer:'Cliente',supplier:'Proveedor'},r.kind)}</td>
   <td>${esc(r.partner||'—')}</td>
   <td>${esc(r.created_on)}</td>
   <td class="grNum">${esc(money(r.amount))}</td>
   <td>${badge(STATUS,r.status)}</td>
   <td><button class="arcButton secondary" data-gr-open="${esc(r.id)}">${tr('Abrir')}</button></td>
  </tr>`).join(''):`<tr><td colspan="7">${tr('Todavía no hay ninguna devolución con estos filtros.')}</td></tr>`}</tbody></table>
 </div>`);
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
 window.ArcUI.render(host,`<p>${tr('Cargando…')}</p>`);
 try{
  const d=await rpc('stats',{from:filters.from||null,to:filters.to||null});
  const listOf=(rows,label,value)=>rows.length
   ?`<ul>${rows.map(r=>`<li>${esc(label(r))} · ${esc(value(r))}</li>`).join('')}</ul>`
   :`<p class="grHint">${tr('Sin datos todavía.')}</p>`;
  window.ArcUI.render(host,`
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
   ${listOf(d.suppliers,r=>r.supplier,r=>num(r.n))}`);
 }catch(e){window.ArcUI.render(host,`<p class="grError" role="alert">${esc(err(e))}</p>`)}
}

/* ------------------------------------------------- crear en tres pantallas */
/* Paso 1: qué clase de devolución. Dos botones grandes y nada más. */
function wizardKind(){
 const el=window.GamaSales.modal(T('Nueva devolución'),
  `<p class="grSteps"><span aria-current="step">${tr('1 · Tipo')}</span><span>${tr('2 · Documento')}</span><span>${tr('3 · Productos')}</span></p>
   <div class="grBig">
    <button type="button" class="arcButton secondary" data-gr-kind="customer">${tr('↩️ Devolución de un cliente')}</button>
    <button type="button" class="arcButton secondary" data-gr-kind="supplier">${tr('📦 Devolución a un proveedor')}</button>
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
   window.ArcUI.render(el.querySelector('#grSrcList'),rows.length?`<table class="arcTable grTable"><tbody>${rows.slice(0,60).map(r=>`<tr>
     <td><b>${esc(r.number)}</b><br>${esc(r.partner)}</td>
     <td>${esc(String(r.dispatched_at||r.order_date||'').slice(0,10))}</td>
     <td><button class="arcButton secondary" data-gr-src="${esc(r.id)}">${tr('Elegir')}</button></td></tr>`).join('')}</tbody></table>`
    :`<p class="grHint">${tr('No hay ningún documento con mercancía que se pueda devolver.')}</p>`);
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
    <div class="grScroll"><table class="arcTable grTable"><thead><tr>
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
  window.ArcUI.render($('grMain'),processView(d));
  bindDetail(d);
 }catch(e){if(token===generation)fail(e,()=>detail(id))}
}
/* La ficha como proceso: un resumen, una franja con las etapas y cada etapa
   con sus documentos y sus botones. Los botones son los de siempre, con los
   mismos permisos: sólo cambia dónde aparecen. */
function processView(d){
 const r=rights(),customer=d.kind==='customer';
 const pending=d.lines.filter(l=>!l.processed_at).length;
 const open=!['closed','cancelled'].includes(d.status),cancelled=d.status==='cancelled';
 const outstanding=Math.max(0,Number(d.amount)-Number(d.refunded||0));
 const links=docLinks(d),origin=links.map((x,i)=>[x,i]).filter(([x])=>x.kind!=='credit');
 const docButton=([x,i])=>`<li><button type="button" class="gdfDoc" data-gr-doc="${i}">${esc(x.number)}</button></li>`;
 const docs=list=>list.length?`<ul class="gdfDocs">${list.join('')}</ul>`:'';
 const creditDocs=links.map((x,i)=>[x,i]).filter(([x])=>x.kind==='credit').map(docButton);
 // Las líneas se leen en la solicitud; se deciden en el tratamiento.
 const lines=`<div class="grLines">${d.lines.map(l=>`<div class="grLine"><b>${esc(l.product)}</b> · ${esc(num(l.quantity,3))} × ${esc(money(l.unit_price))} = ${esc(money(l.amount))}</div>`).join('')}</div>`;
 const decisions=`<div class="grLines">${d.lines.map(l=>`<div class="grLine">
     <b>${esc(l.product)}</b> · ${esc(num(l.quantity,3))}
     <p class="grHint">${l.processed_at?tr(DISPOSITION[l.disposition]||l.disposition):tr('Pendiente de decidir')}${l.notes?' · '+esc(l.notes):''}</p>
     ${open&&r.process&&d.status==='received'&&!l.processed_at
       ?`<div class="grActions"><button class="arcButton primary" data-gr-process="${esc(l.id)}">${tr('Decidir qué se hace')}</button></div>`:''}
    </div>`).join('')}</div>`;
 const files=`<p class="grHint"><b>${tr('Fotos y documentos')}</b></p>${d.files.length?`<div class="grDocs">${d.files.map(f=>`<button class="arcButton secondary" data-gr-file="${esc(f.id)}">${esc(f.filename)}</button>`).join('')}</div>`:`<p class="grHint">${tr('Todavía no hay ningún archivo.')}</p>`}${open?`<label class="grField">${tr('Añadir una foto o un documento')}<input id="grAddFile" type="file" accept="image/png,image/jpeg,image/webp,application/pdf"></label>`:''}`;
 const money_=`<dl class="grDl"><dt>${tr('Decisión')}</dt><dd>${tr(FINANCIAL[d.financial_action]||d.financial_action)}</dd>${customer?`<dt>${tr('Reembolsado')}</dt><dd>${esc(money(d.refunded))} · ${tr('pendiente')} ${esc(money(outstanding))}</dd>`:''}</dl>
   ${d.credits.map(c=>`<p>${tr('Abono')} <b>${esc(c.number)}</b> · ${esc(money(c.amount))} · ${esc(c.issued_on)}${c.supplier_reference?' · '+esc(c.supplier_reference):''}</p>`).join('')}
   ${d.refunds.map(f=>`<p>${tr('Reembolso')} ${f.erp_reference?'<b>'+esc(f.erp_reference)+'</b> · ':''}${esc(money(f.amount))} · ${esc(f.paid_at)} · ${esc(f.method)}${f.reference?' · '+esc(f.reference):''}</p>`).join('')}`;
 const financialDone=d.financial_action==='none'?['processed','closed'].includes(d.status):d.financial_action==='refund'?outstanding<=0:d.credits.length>0;
 const steps=customer?[
  {title:'Origen de la devolución',state:'done',body:docs(origin.map(docButton))+`<p>${tr('Motivo')} : ${tr(REASON[d.reason]||d.reason)}</p>`},
  {title:'Solicitud de devolución',state:cancelled?'closed':'done',body:docs([`<li><span class="gdfDoc">${esc(d.number)}</span></li>`])+lines+files},
  {title:'Recepción',state:d.status==='to_process'?'active':'done',need:'Registrar la llegada de la mercancía: entra retenida y no cuenta como disponible.',
   body:d.status==='to_process'&&open&&r.process?`<div class="grActions"><button class="arcButton primary" id="grReceive">${tr('📥 Registrar la recepción')}</button></div>`:''},
  {title:'Tratamiento',state:d.status==='to_process'?'pending':d.status==='received'?'active':'done',need:'Decidir producto por producto: stock, rebut o devolución al proveedor.',
   body:(d.status==='to_process'?'':decisions)+(d.status==='received'&&pending?`<p class="grHint">${tr('La mercancía está retenida: no cuenta como disponible hasta que decidas.')}</p>`:'')},
  {title:'Acción financiera',state:financialDone?'done':['processed','received'].includes(d.status)?'active':'pending',need:'Elegir la acción financiera —ninguna, abono, reembolso o crédito— y ejecutarla.',
   body:money_+docs(creditDocs)+`<div class="grActions">${open&&r.refund?`<button class="arcButton secondary" id="grFinancial">${tr('Elegir la acción financiera')}</button>`:''}${open&&r.refund&&d.invoice_id?`<button class="arcButton secondary" id="grCredit">${tr('🧾 Emitir un abono')}</button>`:''}${open&&r.refund&&outstanding>0?`<button class="arcButton secondary" id="grRefund">${tr('💸 Reembolsar')}</button>`:''}</div>${!d.invoice_id?`<p class="grHint">${tr('Esta devolución no viene de una factura: no se puede emitir un abono, sólo reembolsar.')}</p>`:''}`},
  {title:'Cierre del proceso de devolución',state:d.status==='closed'?'done':d.status==='processed'?'active':'pending',need:'Cerrar la devolución cuando todo esté tratado.',
   body:open&&(r.process||r.refund)&&d.status==='processed'?`<div class="grActions"><button class="arcButton primary" id="grClose">${tr('✅ Cerrar la devolución')}</button></div>`:''}
 ]:[
  {title:'Origen de la devolución',state:'done',body:docs(origin.map(docButton))+`<p>${tr('Motivo')} : ${tr(REASON[d.reason]||d.reason)}</p>`},
  {title:'Solicitud de devolución',state:cancelled?'closed':'done',body:docs([`<li><span class="gdfDoc">${esc(d.number)}</span></li>`])+lines+files},
  {title:'Expedición al proveedor',state:d.status==='to_process'?'active':'done',need:'Registrar la salida de la mercancía hacia el proveedor.',
   body:`${d.carrier||d.tracking||d.shipped_on?`<dl class="grDl">${d.carrier?`<dt>${tr('Transportista')}</dt><dd>${esc(d.carrier)}</dd>`:''}${d.tracking?`<dt>${tr('Número de seguimiento')}</dt><dd>${esc(d.tracking)}</dd>`:''}${d.shipped_on?`<dt>${tr('Expedida el')}</dt><dd>${esc(d.shipped_on)}</dd>`:''}</dl>`:''}${d.status==='to_process'&&open&&r.process?`<div class="grActions"><button class="arcButton primary" id="grShip">${tr('🚚 Registrar la expedición')}</button></div>`:''}`},
  {title:'Abono del proveedor',state:d.credits.length||d.status==='credited'?'done':d.status==='shipped'?'active':'pending',need:'Registrar el abono que envía el proveedor.',
   body:money_+docs(creditDocs)+(open&&r.refund?`<div class="grActions"><button class="arcButton secondary" id="grSupplierCredit">${tr('🧾 Registrar el abono del proveedor')}</button></div>`:'')},
  {title:'Cierre del proceso de devolución',state:d.status==='closed'?'done':['shipped','credited'].includes(d.status)?'active':'pending',need:'Cerrar la devolución cuando el proveedor la haya abonado.',
   body:open&&(r.process||r.refund)&&['shipped','credited'].includes(d.status)?`<div class="grActions"><button class="arcButton primary" id="grClose">${tr('✅ Cerrar la devolución')}</button></div>`:''}
 ];
 const current=steps.findIndex(x=>['active','pending','blocked'].includes(x.state));
 const next=cancelled?'Devolución anulada.':current<0?'Proceso completo.':steps[current].need||'';
 const stateOf=x=>cancelled&&x.state!=='done'?'closed':x.state;
 return `<div class="grActions"><button class="arcButton secondary" id="grBack">${tr('← Volver a la lista')}</button></div>
  <div class="arcPanel grCard grSummary"><div class="gdfSummaryHead"><h3>${esc(processNumber(d.kind,d.number))}</h3>${badge(STATUS,d.status)}</div>
   <dl class="grDl"><dt>${customer?tr('Cliente'):tr('Proveedor')}</dt><dd>${esc(d.partner||'—')}</dd><dt>${tr('Importe')}</dt><dd>${esc(money(d.amount))}</dd>${d.notes?`<dt>${tr('Comentario')}</dt><dd>${esc(d.notes)}</dd>`:''}</dl>
   ${next?`<p class="gdfNext"><b>${tr('Próxima acción')}</b> ${tr(next)}</p>`:''}</div>
  <ol class="gdfStepper" aria-label="${esc(T('Etapas del proceso'))}">${steps.map((x,i)=>`<li data-state="${stateOf(x)}"${i===current?' aria-current="step"':''}><span class="gdfDot">${i+1}</span><span class="gdfStepName">${tr(x.title)}</span></li>`).join('')}</ol>
  <ol class="gdfFlow">${steps.map((x,i)=>`<li class="arcPanel gdfStep ${stateOf(x)}" data-step="${i+1}"><div class="gdfStepHead"><span class="gdfNum" aria-hidden="true">${i+1}</span><h3>${tr(x.title)}</h3><span class="gdfBadge">${tr(STEP_STATES[stateOf(x)])}</span></div>${x.body||''}${['active','pending'].includes(stateOf(x))&&x.need?`<p class="gdfNeed"><b>${tr('Para avanzar')}</b> ${tr(x.need)}</p>`:''}</li>`).join('')}</ol>
  <div class="grActions">
   ${open&&r.create&&d.status==='to_process'?`<button class="arcButton secondary" id="grCancel">${tr('Anular')}</button>`:''}
   ${open&&r.delete&&d.status==='to_process'?`<button class="arcButton secondary" id="grDelete">${tr('Borrar')}</button>`:''}
  </div>`;
}
/* Documentos ligados: se enlazan, nunca se copian. El rótulo y su destino
   salen de la misma lista para que no puedan descolgarse. */
function docLinks(d){
 const x=d.documents||{},out=[];
 if(x.order)out.push({label:T('Pedido'),number:x.order.number,open:()=>window.GamaSales?.openOrder?.(x.order.id)});
 if(x.delivery)out.push({label:T('Entrega'),number:x.delivery.number,open:()=>window.GamaSales?.openOrder?.(d.order_id)});
 if(x.invoice)out.push({label:T('Factura'),number:x.invoice.number,open:()=>window.GamaQuotes?.view?.(x.invoice.id)});
 if(x.purchase_order)out.push({label:T('Pedido de compra'),number:x.purchase_order.number,open:x.purchase_order.id&&window.gamaOpenPurchaseDossier?()=>window.gamaOpenPurchaseDossier(x.purchase_order.id):null});
 if(x.supplier_invoice)out.push({label:T('Factura del proveedor'),number:x.supplier_invoice.number,open:null});
 for(const c of d.credits)out.push({label:T('Abono'),number:c.number,open:null,kind:'credit'});
 return out;
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
    <button type="button" class="arcButton secondary" data-gr-disp="restocked">${tr('📦 Reponer en stock')}</button>
    <button type="button" class="arcButton secondary" data-gr-disp="scrapped">${tr('🗑️ Al rebut')}</button>
    <button type="button" class="arcButton secondary" data-gr-disp="to_supplier">${tr('↪️ Devolver al proveedor')}</button>
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
   `<p>${tr('Coco ERP calcula el importe con los precios e impuestos de la factura de origen. Puedes ajustarlo antes de validar.')}</p>
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
async function refundForm(d){
 let accounts;try{accounts=await window.ArcData.rpc('gama_refund_accounts')}catch(e){return window.gamaToast?.(err(e))}
 if(!accounts.length)return window.gamaToast?.(T('Configura una cuenta bancaria o caja activa en Contabilidad.'));
 const outstanding=Math.max(0,Number(d.amount)-Number(d.refunded||0));
 const key=crypto.randomUUID();
 window.GamaSales.modal(T('Reembolsar al cliente'),
  `<div class="grGrid">
    <label data-gi-live data-gi=572a3acfd983>Importe<input id="grRefundAmount" type="number" inputmode="decimal" min="0.01" step="0.01" max="${esc(outstanding)}" required value="${esc(outstanding)}"></label>
    <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="grRefundDate" type="date" required value="${esc(day())}"></label>
    <label>Cuenta bancaria / caja<select id="grRefundAccount" required><option value="">—</option>${accounts.map(a=>`<option value="${esc(a.id)}">${esc(a.name)} · ${esc(a.currency)}</option>`).join('')}</select></label><label data-gi-live data-gi=25ec5eda3d03>Medio de pago<input id="grRefundMethod" required maxlength="60" placeholder="${esc(T('Transferencia'))}"></label>
    <label data-gi-live data-gi=f9403c06f4cb>Referencia (opcional)<input id="grRefundRef" maxlength="80"></label>
   </div>`,
  T('Registrar el reembolso'),
  async el=>{await mutate('refund',{id:d.id,request_key:key,amount:numval(el,'grRefundAmount'),
   financial_account_id:val(el,'grRefundAccount'),paid_at:val(el,'grRefundDate'),method:val(el,'grRefundMethod'),reference:val(el,'grRefundRef')});await go()});
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
