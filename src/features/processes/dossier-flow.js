/* Seguimiento de procesos: el proceso de venta (PDV) y el de compra (PDC),
   paso a paso, con el número único que comparten todos sus documentos. Es
   una lectura: cada acción se ejecuta en su módulo, con sus controles y su
   RLS. La identidad técnica del módulo sigue siendo «dossier-flow».

   El número del proceso es el del expediente: el pedido PED-00001246, su
   presupuesto COT-00001246 y su factura FAC-00001246 forman el PDV-00001246;
   el pedido de compra OCO-00001330, su factura FPR-00001330 y su pago
   PPR-00001330, el PDC-00001330. */
(function(){
'use strict';
const ID='dossier-flow', $=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const T=s=>window.GamaI18n?.t?.(s)||s;
const can=id=>!!window.gamaAccessAllowed?.(id);
/* Facturas y cobros se leen si se puede abrir «Facturas y cobros» (la pestaña de
   Presupuestos y facturas), como en el servidor. «billing» es el antiguo formulario
   de presupuestos: nada que ver, y puede estar apagado. */
const financeAllowed=()=>can('payments');
const money=v=>Number(v||0).toLocaleString(window.GamaI18n?.locale||'es-EC',{style:'currency',currency:'USD'});
const cents=v=>Math.round(Number(v||0)*100);
const n=v=>Number(v||0), sum=(a,key='quantity')=>a.reduce((s,x)=>s+n(x[key]),0);
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:(globalThis.window?.GamaCompany?.get()?.timezone||'America/Guayaquil'),year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
/* PDV-00001246: el acrónimo del proceso y el número de su expediente. */
const processNumber=(kind,number)=>Number(number)>0?kind+'-'+String(number).padStart(8,'0'):'';
const PROCESSES={PDV:{module:'dossier-flow',label:'PDV · Proceso de venta'},PDC:{module:'gamaPurchasesV14',label:'PDC · Proceso de compra'},PRC:{module:'returns',label:'PRC · Devolución de cliente',kind:'customer'},PRP:{module:'returns',label:'PRP · Devolución a proveedor',kind:'supplier'}};
let tab='PDV',records=[],purchases=[],suppliers=new Map(),generation=0,selected=null,summaries=new Map(),summaryToken=0,pageOffset=0,pageTotal=0,searchTimer=null;
const processRPC=(action,data)=>window.ArcData.rpc('gama_processes',{p_action:action,p_data:data});
const serverStates=new Map();
async function all(table,options={}){
 const result=[];
 for(let offset=0;;offset+=300){const r=await GamaCloud.list(table,{...options,order:({sales_reservation_links:'reservation_id',tms_proofs:'delivery_id',fulfillment_package_lines:'pick_line_id'}[table]||'id'),ascending:true,range:[offset,offset+299]});if(r.error)throw r.error;const a=r.data||[];result.push(...a);if(a.length<300)return result}
}
function group(orders,quotes,requests){
 const usedQ=new Set(),usedR=new Set(),out=[];
 const requestFor=q=>q&&requests.find(r=>r.invoice_id===q?.id);
 orders.forEach(o=>{const direct=requests.find(r=>r.id===o.source_request_id),q=quotes.find(q=>q.id===(o.source_quote_id||direct?.invoice_id)),r=direct||requestFor(q);if(q)usedQ.add(q.id);if(r)usedR.add(r.id);out.push({key:'o:'+o.id,o,q,r})});
 quotes.filter(q=>!usedQ.has(q.id)).forEach(q=>{const r=requestFor(q);if(r)usedR.add(r.id);out.push({key:'q:'+q.id,q,r})});
 requests.filter(r=>!usedR.has(r.id)).forEach(r=>out.push({key:'r:'+r.id,r}));
 return out.sort((a,b)=>String(b.o?.created_at||b.q?.created_at||b.r?.created_at||'').localeCompare(String(a.o?.created_at||a.q?.created_at||a.r?.created_at||'')));
}
function progress(d,x){
 const EPS=0.000001;let ordered=0,shipped=0,missing=0,delivered=0,proved=0;
 for(const l of x.lines){if(l.product_kind==='service'){const qty=n(l.quantity),done=Math.min(qty,sum((x.services||[]).filter(c=>c.order_line_id===l.id&&!c.cancelled_at)));ordered+=qty;shipped+=done;delivered+=done;proved+=done;continue}const qty=n(l.quantity),sl=x.shipLines.filter(s=>s.order_line_id===l.id),sent=sum(sl),reserved=sum(x.reservations.filter(r=>r.status==='active'&&x.links.some(k=>k.line_id===l.id&&k.reservation_id===r.id)));
 ordered+=qty;shipped+=Math.min(qty,sent);missing+=Math.max(0,qty-sent-reserved);
 const matches=(s,proof)=>{const ship=x.ships.find(a=>a.id===s.delivery_id),t=x.transport.find(a=>a.id===ship?.tms_delivery_id);return t?.status==='Entregada'&&(!proof||x.proofsUnavailable||x.proofs.some(p=>p.delivery_id===t.id&&p.signature))};
 delivered+=Math.min(qty,sum(sl.filter(s=>matches(s,false))));proved+=Math.min(qty,sum(sl.filter(s=>matches(s,true))));
 }
 const complete=ordered>0&&shipped>=ordered-EPS,done=ordered>0&&proved>=ordered-EPS;
 const active=x.preps.filter(p=>!['cancelled','shipped'].includes(p.status)),picks=x.picks.filter(p=>active.some(a=>a.id===p.preparation_id));
 const packed=sum(x.packageLines.filter(p=>x.packages.some(a=>a.id===p.package_id&&a.status==='active'&&active.some(b=>b.id===a.preparation_id))));
 return {ordered,shipped,missing,delivered,proved,complete,done,planned:sum(picks,'planned'),picked:sum(picks,'picked'),packed,active};
}
// Integer cents per invoice prevent offsets between unpaid and overpaid invoices.
function financialProgress(x,today){
 const active=x.invoices.filter(i=>!['cancelled','rejected'].includes(i.fiscal_status));
 const valid=active.filter(i=>i.document_kind==='internal'||i.fiscal_status==='authorized');
 let unbilled=0,remaining=0;
 for(const l of x.lines){const qty=Math.max(0,n(l.quantity)-sum(x.invoiceLines.filter(il=>il.order_line_id===l.id&&valid.some(i=>i.id===il.invoice_id))));remaining+=qty;unbilled+=cents(qty*n(l.unit_price)*(1+n(l.tax_rate)/100));}
 const rows=active.map(i=>{const paid=x.payments.filter(p=>p.invoice_id===i.id&&p.status==='confirmed').reduce((v,p)=>v+cents(p.amount),0),credit=(x.credits||[]).filter(c=>c.invoice_id===i.id).reduce((v,c)=>v+cents(c.amount),0),balance=Math.max(0,cents(i.total)-paid-credit);return {...i,paid,balance,overdue:balance>0&&!!i.due_date&&i.due_date<today};});
 const billed=valid.reduce((v,i)=>v+cents(i.total),0),paid=rows.reduce((v,i)=>v+i.paid,0),balance=rows.reduce((v,i)=>v+i.balance,0),overdue=rows.filter(i=>i.overdue).reduce((v,i)=>v+i.balance,0);
 const covered=x.lines.length>0&&remaining<0.000001&&valid.length>0;
 const externalPending=active.some(i=>i.document_kind==='internal'?(!i.external_number||i.external_status!=='authorized'):i.fiscal_status!=='authorized');
 const invoiced=covered;
 return {rows,billed,paid,balance,overdue,unbilled,covered,externalPending,invoiced,settled:invoiced&&balance===0};
}
const saleNumber=d=>processNumber('PDV',d.o?.dossier_number||d.q?.dossier_number||d.r?.dossier_number)||d.o?.number||d.q?.invoice_number||String(d.r?.id||d.q?.id||'').slice(0,8).toUpperCase();
const customer=d=>d.o?.customer_name||d.q?.quote_details?.client||d.r?.requester_name||'—';
const purchaseNumber=o=>processNumber('PDC',o.dossier_number)||o.order_number;
const supplierName=o=>suppliers.get(o.supplier_id)||'—';

function releaseReturns(){if(window.GamaReturns&&!window.GamaReturns.__arcLazy)window.GamaReturns.unmount?.()}
function shell(){
 let s=$(ID);if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 const tabs=Object.entries(PROCESSES).filter(([,p])=>can(p.module));
 if(!tabs.some(([k])=>k===tab))tab='PDV';
 window.ArcUI.render(s,GamaUI.header({title:'Seguimiento de procesos',lead:'Cada proceso paso a paso, con un solo número en todos sus documentos.'})
  +`<div class="gdfTabs" role="tablist" aria-label="${esc(T('Procesos'))}">${tabs.map(([k,p])=>`<button type="button" role="tab" class="gdfTab" id="gdfTab${k}" data-gdf-tab="${k}" aria-selected="${tab===k}" aria-controls="gdfPanel">${tr(p.label)}</button>`).join('')}</div>`
  +`<div id="gdfPanel" role="tabpanel" aria-labelledby="gdfTab${tab}"><div class="gdfTools"><input id="gdfSearch" aria-label="${esc(T('Buscar un proceso'))}" placeholder="${esc(T('Buscar un proceso'))}"><button class="arcButton secondary" id="gdfRefresh">${tr('Actualizar')}</button></div><div class="gdfLayout"><div id="gdfList" class="gdfList"></div><div id="gdfDetail" aria-live="polite"></div></div></div>`);
 GamaUI.bindBack(s);window.showTab?.(ID);
 $('gdfSearch').oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>{pageOffset=0;loadPage().catch(failure)},250)};$('gdfRefresh').onclick=()=>open(selected,{tab});
 s.querySelectorAll('[data-gdf-tab]').forEach(b=>b.onclick=()=>{if(b.dataset.gdfTab!==tab)open(null,{tab:b.dataset.gdfTab})});
}
/* La barra de cada tarjeta: las etapas hechas sobre el total, en verde mientras
   el proceso avanza y en rojo si algo lo bloquea, para verlo sin abrirlo. Ocupa
   el sitio del estado del documento («Pedido de venta», «Recibido»), que
   repetía lo que ya dice el número. Sale de las mismas etapas que el detalle:
   la tarjeta y el detalle no pueden contradecirse. */
const PROCESS_STATUS={done:'Proceso completo',closed:'Proceso cerrado',blocked:'Proceso bloqueado',active:'Proceso en curso'};
function summarize(steps,closed){
 const blocked=steps.find(s=>s.state==='blocked'),current=steps.find(s=>['active','pending'].includes(s.state));
 // Lo que este perfil no puede comprobar (sin acceso) no cuenta como hecho.
 const done=steps.filter(s=>['done','skip'].includes(s.state)).length;
 return {done,total:steps.length,state:closed?'closed':blocked?'blocked':done===steps.length?'done':'active',step:closed?'':(blocked||current)?.title||''};
}
function bar(key){
 const s=summaries.get(key);
 if(!s?.total)return `<span class="gdfProgress" data-state="${s?'unknown':'loading'}" aria-hidden="true"><i></i></span><span class="arcSrOnly">${tr(s?'Avance no disponible':'Cargando…')}</span>`;
 const say=f=>`${f('Avance')} ${s.done}/${s.total} · ${f(PROCESS_STATUS[s.state])}${s.step?' · '+f(s.step):''}`;
 // El color no va solo: el texto lo leen los lectores de pantalla y el ratón lo ve al pasar.
 return `<span class="gdfProgress" data-state="${s.state}" title="${esc(say(T))}" aria-hidden="true"><i style="width:${Math.round(s.done/s.total*100)}%"></i></span><span class="arcSrOnly">${say(tr)}</span>`;
}
function renderList(){
 const list=$('gdfList');if(!list)return;
 const q=($('gdfSearch')?.value||'').trim().toLocaleLowerCase(),match=values=>values.some(v=>String(v||'').toLocaleLowerCase().includes(q));
 const rows=tab==='PDC'
  ?purchases.filter(o=>match([purchaseNumber(o),o.order_number,supplierName(o)])).map(o=>({key:'p:'+o.id,number:purchaseNumber(o),party:supplierName(o)}))
  :records.filter(d=>match([saleNumber(d),customer(d),d.q?.invoice_number,d.o?.number,d.o?.original_number,d.q?.original_number,d.r?.dossier_reference])).map(d=>({key:d.key,number:saleNumber(d),party:customer(d)}));
 // Las barras se repintan al llegar: la tarjeta en la que está el teclado conserva el foco.
 const focused=document.activeElement?.closest?.('#gdfList [data-record]')?.dataset.record;
 window.ArcUI.render(list,rows.map(r=>`<button class="arcButton gdfRecord" data-record="${esc(r.key)}" aria-pressed="${selected===r.key}"><b>${esc(r.number)}</b><small>${esc(r.party)}</small>${bar(r.key)}</button>`).join('')||tr(tab==='PDC'?'No hay procesos de compra.':'No hay procesos de venta.'));
 list.insertAdjacentHTML('beforeend',`<div class=arcToolbar><button type=button class="arcButton secondary" data-page-prev ${pageOffset===0?'disabled':''}>${tr('Anterior')}</button><span>${pageOffset+1}–${Math.min(pageOffset+25,pageTotal)} / ${pageTotal}</span><button type=button class="arcButton secondary" data-page-next ${pageOffset+25>=pageTotal?'disabled':''}>${tr('Siguiente')}</button></div>`);
 list.querySelector('[data-page-prev]').onclick=()=>{pageOffset=Math.max(0,pageOffset-25);loadPage().catch(failure)};list.querySelector('[data-page-next]').onclick=()=>{pageOffset+=25;loadPage().catch(failure)};
 list.querySelectorAll('[data-record]').forEach(b=>{b.onclick=()=>detail(b.dataset.record);if(b.dataset.record===focused)b.focus()});
}
/* Las barras de toda la lista, de una vez: los mismos datos que el detalle,
   pedidos por lotes y no proceso a proceso. */
function remember(key,steps,closed){summaries.set(key,summarize(steps,closed));renderList()}
async function loadPage(key=null){const token=++generation;
 const result=await processRPC('list',{kind:tab,key,offset:pageOffset,search:$('gdfSearch')?.value||''});
 if(token!==generation||!can(ID))return;pageTotal=result.total;
 records=[];purchases=[];
 for(const row of result.items){serverStates.set(row.key,row.state);summaries.set(row.key,summarize(row.state.steps,row.state.closed||row.state.cancelled));if(tab==='PDC'){purchases.push(row.o);suppliers.set(row.o.supplier_id,row.party)}else records.push(row)}
 renderList();const first=result.items.find(x=>x.key===key)||result.items[0];if(first)await detail(first.key);else window.ArcUI.render($('gdfDetail'),tr('No hay procesos.'));
}
async function open(key=null,options={}){
 if(!can(ID))return;if(options.tab&&PROCESSES[options.tab])tab=options.tab;if(typeof key==='string'&&key.startsWith('p:'))tab='PDC';
 generation++;clearTimeout(searchTimer);releaseReturns();selected=key;pageOffset=0;shell();
 if(PROCESSES[tab].kind){window.ArcUI.render($('gdfPanel'),'<div id="gdfReturns"></div>');await window.GamaReturns.mount($('gdfReturns'),PROCESSES[tab].kind,options.returnId);return}
 window.ArcUI.render($('gdfDetail'),tr('Cargando…'));
 try{await window.GamaCloudReady;await loadPage(key)}catch(e){failure()}
}
function failure(){window.ArcUI.render($('gdfDetail'),`<p role="alert" class="gdfError">${tr('No se pudo cargar el proceso. Actualiza para reintentar; el avance no está confirmado.')}</p>`)}
const by=async(table,field,a,select='*',extra={})=>{const result=[];for(let i=0;i<a.length;i+=100)result.push(...await all(table,{...extra,select,in:{[field]:a.slice(i,i+100)}}));return result};
const ids=(a,k='id')=>a.map(x=>x[k]).filter(Boolean);
async function detail(key){
 if(!can(ID))return;selected=key;renderList();const token=++generation;window.ArcUI.render($('gdfDetail'),tr('Cargando…'));
 try{
  const shared=await processRPC('state',{key});if(token!==generation)return;serverStates.set(key,shared);
  if(key.startsWith('p:')){const o=purchases.find(x=>'p:'+x.id===key);if(!o)return;const x=(await purchaseDataFor([o])).get(o.id);if(token!==generation||!can(ID))return;renderPurchase(o,x);attachHistory($('gdfDetail'),key,()=>token===generation&&can(ID));return}
  const d=records.find(x=>x.key===key);if(!d)return;
  let data=emptySale();
  if(d.o){
   /* El flujo inverso sólo existe si de verdad ha vuelto algo. */
   const [read,returns]=await Promise.all([saleData([d.o],PROOF_DOC_COLUMNS),all('return_orders',{eq:{order_id:d.o.id}}).catch(()=>[])]);
   data=read.get(d.o.id);data.returns=returns;
  }
  /* Paso 1: la oportunidad del CRM de la que nace, por el pedido o por el presupuesto. */
  if(can('crm')){const opportunity=d.o?.source_opportunity_id?await all('crm_opportunities',{select:'id,reference,title,erp_reference',eq:{id:d.o.source_opportunity_id}}).catch(()=>[]):d.q?await all('crm_opportunities',{select:'id,reference,title,erp_reference',eq:{quote_invoice_id:d.q.id}}).catch(()=>[]):[];data.opportunity=opportunity[0]||null}
  if(token!==generation||!can(ID))return;renderSale(d,data);attachHistory($('gdfDetail'),key,()=>token===generation&&can(ID));
 }catch(e){if(token===generation)failure()}
}
/* Pruebas de entrega (vista tms_proofs_read): a la barra le basta saber si hay
   firma; el detalle enseña además la referencia y la fecha. */
const PROOF_COLUMNS='delivery_id,signature',PROOF_DOC_COLUMNS='delivery_id,captured_at,signature,erp_reference';
const INVOICE_COLUMNS='id,order_id,number,total,due_date,fiscal_status,document_kind,external_number,external_status';
const emptySale=()=>({lines:[],ships:[],shipLines:[],reservations:[],links:[],preps:[],picks:[],packages:[],packageLines:[],transport:[],proofs:[],invoices:[],invoiceLines:[],payments:[],returns:[],opportunity:null});
const only=(rows,key,values)=>rows.filter(r=>values.has(r[key]));
/* Lo que piden las etapas de venta, por lotes: vale igual para un proceso (el
   detalle) que para toda la lista (las barras). */
async function saleData(orders,proofColumns=PROOF_COLUMNS){
 const out=new Map(orders.map(o=>[o.id,emptySale()])),oid=[...out.keys()];
 if(!oid.length)return out;
 const [lines,ships,reservations,preps]=await Promise.all([by('sales_order_lines','order_id',oid),by('sales_deliveries','order_id',oid),by('stock_reservations','reference_id',oid,'*',{eq:{reference_type:'sales_order'}}),by('fulfillment_preparations','order_id',oid)]);
 const deliveries=ids(ships,'tms_delivery_id');
 const [links,shipLines,picks,packages,transport,proofs]=await Promise.all([by('sales_reservation_links','line_id',ids(lines)),by('sales_delivery_lines','delivery_id',ids(ships)),by('fulfillment_pick_lines','preparation_id',ids(preps)),by('fulfillment_packages','preparation_id',ids(preps)),by('tms_deliveries','id',deliveries),by('tms_proofs','delivery_id',deliveries,proofColumns).catch(()=>null)]);
 const packageLines=await by('fulfillment_package_lines','package_id',ids(packages));
 let invoices=[],invoiceLines=[],payments=[];
 if(financeAllowed()){invoices=await by('external_invoices','order_id',oid,INVOICE_COLUMNS);[invoiceLines,payments]=await Promise.all([by('external_invoice_lines','invoice_id',ids(invoices)),by('external_invoice_payments','invoice_id',ids(invoices))]);}
 for(const [id,x] of out){
  const own=new Set([id]);
  x.lines=only(lines,'order_id',own);x.ships=only(ships,'order_id',own);x.reservations=only(reservations,'reference_id',own);x.preps=only(preps,'order_id',own);
  const tms=new Set(ids(x.ships,'tms_delivery_id')),prepIds=new Set(ids(x.preps));
  x.links=only(links,'line_id',new Set(ids(x.lines)));x.shipLines=only(shipLines,'delivery_id',new Set(ids(x.ships)));
  x.picks=only(picks,'preparation_id',prepIds);x.packages=only(packages,'preparation_id',prepIds);x.packageLines=only(packageLines,'package_id',new Set(ids(x.packages)));
  x.transport=only(transport,'id',tms);
  /* Sin las pruebas el proceso se sigue viendo: una entrega «Entregada» ya exigió la firma en el TMS. */
  if(proofs===null)x.proofsUnavailable=true;else x.proofs=only(proofs,'delivery_id',tms);
  x.invoices=only(invoices,'order_id',own);const invoiceIds=new Set(ids(x.invoices));
  x.invoiceLines=only(invoiceLines,'invoice_id',invoiceIds);x.payments=only(payments,'invoice_id',invoiceIds);
 }
 return out;
}
/* Lo que piden las etapas de compra, por lotes igual. */
async function purchaseDataFor(list){
 const safe=p=>p.then(rows=>({rows,ok:true}),()=>({rows:[],ok:false}));
 const pid=ids(list),origins=ids(list.filter(o=>o.source_kind==='sales_order'),'source_order_id');
 const [lines,moves,invoices,sources]=await Promise.all([by('purchase_order_lines','purchase_order_id',pid),safe(by('stock_movements','reference_id',pid,'id,reference_id,quantity,erp_reference,created_at',{eq:{reference_type:'purchase_order'}})),safe(by('supplier_invoices','purchase_order_id',pid,'id,purchase_order_id,number,erp_reference,total,due_date,status')),safe(by('sales_orders','id',origins,'id,number'))]);
 const payments=invoices.ok&&invoices.rows.length?await safe(by('supplier_invoice_payments','supplier_invoice_id',ids(invoices.rows),'id,supplier_invoice_id,amount,status,erp_reference,paid_at')):{rows:[],ok:invoices.ok};
 return new Map(list.map(o=>{const own=invoices.rows.filter(i=>i.purchase_order_id===o.id),paidFor=new Set(ids(own));
  return [o.id,{lines:lines.filter(l=>l.purchase_order_id===o.id),moves:{ok:moves.ok,rows:moves.rows.filter(m=>m.reference_id===o.id)},invoices:{ok:invoices.ok,rows:own},payments:{ok:payments.ok,rows:payments.rows.filter(p=>paidFor.has(p.supplier_invoice_id))},source:o.source_kind==='sales_order'&&sources.rows.find(s=>s.id===o.source_order_id)||null}]}));
}
/* Un documento del proceso: su referencia —con el número del proceso— y cómo abrirlo. */
const doc=(ref,action,id,module)=>ref?{ref,action,id,module}:null;
function processDoc(row,ref,number,action,id,module){
 const common=window.GamaReferences?.processReference({...row,erp_reference:ref},number)||ref;
 return ref?{...doc(common,action,id,module),issuedReference:common!==ref?ref:null}:null;
}

const STATES={done:'Completado',active:'En curso',blocked:'Bloqueado',pending:'Pendiente',skip:'Sin esta etapa',closed:'Cerrado',restricted:'Sin acceso a estos datos'};
const nextAction=(label,action,id,module)=>({label,action,id,module});
const fromDoc=(d,label)=>d&&nextAction(label,d.action,d.id,d.module);
function saleActions(d,x,steps){
 const order=d.o&&nextAction('Abrir el pedido','order',d.o.id,'sales-orders');
 const quote=d.q&&nextAction('Revisar el presupuesto','quote',d.q.id,'quotes');
 const request=d.r&&nextAction('Abrir la solicitud','request',d.r.id,'customer-requests');
 const source=quote||request||order;
 const preparation=d.o&&nextAction('Abrir la preparación','preparation',d.o.id,'tms');
 const goods=x.lines.some(l=>l.product_kind!=='service');
 const service=x.lines.some(l=>l.product_kind==='service')&&d.o&&nextAction('Registrar la realización del servicio','order',d.o.id,'sales-orders');
 const deliveries=x.transport.filter(t=>!['Entregada','Cancelada'].includes(t.status)).map(t=>({...nextAction('Cargar / entregar','delivery',t.id,'tms'),ref:t.erp_reference||t.dossier_reference}));
 const invoices=x.invoices.filter(i=>!['cancelled','rejected'].includes(i.fiscal_status));
 const shared=serverStates.get(d.key),missing=n(shared?.metrics?.missing??progress(d,x).missing);
 const closed=shared?.closed||shared?.cancelled;
 const actions=[
  [fromDoc(steps[0].docs?.find(Boolean),'Consultar el origen')||source],
  [quote||request||order],
  [order||source],
  d.o?.status!=='confirmed'?[order||source]:[
   missing>0&&nextAction('Revisar la reserva de stock','order',d.o.id,'sales-orders'),
   missing>0&&!closed&&nextAction('Preparar la reposición','replenish',d.o.id,'gamaPurchasesV14'),
   goods&&preparation,service],
  [...deliveries,goods&&!progress(d,x).complete&&preparation,service,...(!deliveries.length&&(!goods||progress(d,x).complete)?[order||source]:[])],
  invoices.length?invoices.map(i=>({...nextAction('Abrir la factura','payment',i.id,'payments'),ref:i.number})):[order||source],
  [d.o?nextAction('Abrir los cobros del pedido','order_payments',d.o.id,'payments'):source],
  [(x.returns||[]).filter(r=>!['closed','cancelled'].includes(r.status)).map(r=>({...nextAction('Resolver la devolución','returns',r.id,'returns'),ref:r.number})),nextAction('Revisar responsable y cierre','closure',d.key,ID)].flat()
 ];
 return steps.map((s,i)=>({...s,actions:actions[i].filter(Boolean)}));
}
function purchaseActions(o,x,steps){
 const purchase=nextAction('Abrir el pedido de compra','purchase',o.id,'gamaPurchasesV14');
 const bills=x.invoices.rows.filter(i=>i.status!=='cancelled');
 const invoices=bills.map(i=>({...nextAction('Revisar la factura del proveedor','supplier_invoice',i.id,'accounting'),ref:i.erp_reference||i.number}));
 const actions=[
  [x.source?nextAction('Consultar el pedido de origen','order',x.source.id,'sales-orders'):purchase],
  [purchase],
  [nextAction('Abrir la recepción','purchase',o.id,'gamaPurchasesV14')],
  [nextAction('Revisar el destino de recepción','purchase',o.id,'gamaPurchasesV14')],
  [...invoices,...(o.status!=='cancelled'&&(!bills.length||n(serverStates.get('p:'+o.id)?.metrics?.unbilled)>0)?[nextAction('Registrar la factura del proveedor','new_supplier_invoice',o.id,'accounting')]:[])],
  bills.length?bills.map(i=>({...nextAction('Revisar / registrar el pago','supplier_invoice',i.id,'accounting'),ref:i.erp_reference||i.number})):[o.status==='cancelled'?purchase:nextAction('Registrar la factura del proveedor','new_supplier_invoice',o.id,'accounting')],
  [nextAction('Revisar responsable y cierre','closure','p:'+o.id,ID)]
 ];
 return steps.map((s,i)=>({...s,actions:actions[i].filter(Boolean)}));
}

function saleSteps(d,x){
 const day=today(),late=t=>t.delivery_date&&t.delivery_date<day&&!['Entregada','Cancelada'].includes(t.status);
 const processId=d.o?.dossier_number||d.q?.dossier_number||d.r?.dossier_number;
 const stage=(row,ref,action,id,module)=>processDoc(row,ref,processId,action,id,module);
 const p=progress(d,x),fin=financeAllowed(),f=fin?financialProgress(x,day):null;
 const cancelled=d.o?.status==='cancelled'||(!d.o&&['cancelled','rejected'].includes(d.q?.quote_state||d.r?.status));
 const confirmed=d.o?.status==='confirmed';
 const quoteExpired=d.q?.quote_state==='sent'&&d.q.quote_valid_until&&d.q.quote_valid_until<day;
 const steps=[
  {title:'Origen de la demanda',state:x.opportunity||d.r?'done':d.q||d.o?'skip':'pending',
   docs:[x.opportunity&&doc(x.opportunity.erp_reference||x.opportunity.reference,'opportunity',x.opportunity.id,'crm'),d.r&&stage(d.r,d.r.erp_reference||d.r.dossier_reference||String(d.r.id).slice(0,8).toUpperCase(),'request',d.r.id,'customer-requests')],
   info:x.opportunity?T('Oportunidad del CRM')+' · '+esc(x.opportunity.title||''):d.r?tr('Solicitud del cliente'):tr('Pedido o presupuesto directo, sin solicitud ni oportunidad previa.'),
   need:'Registrar la oportunidad en el CRM o la solicitud del cliente, con sus productos y cantidades.'},
  {title:'Presupuesto',state:d.q?(confirmed||['accepted','converted'].includes(d.q.quote_state)?'done':['rejected','cancelled'].includes(d.q.quote_state)?'closed':quoteExpired?'blocked':'active'):d.o?'skip':'pending',
   docs:[d.q&&stage(d.q,d.q.invoice_number,'quote',d.q.id,'quotes')],info:quoteExpired?tr('Presupuesto vencido: revisar la vigencia antes de aceptar.'):'',
   need:'Completar cliente, productos, precios y vigencia; enviarlo y registrar la aceptación del cliente.'},
  {title:'Pedido',state:d.o?(confirmed?'done':d.o.status==='cancelled'?'closed':'active'):'pending',
   docs:[d.o&&stage(d.o,d.o.number,'order',d.o.id,'sales-orders')],need:'Confirmar el pedido: reserva el stock disponible y abre la preparación.'},
  {title:'Reserva de stock y preparación',state:!confirmed?'pending':p.missing>0?'blocked':(p.complete||(p.ordered>0&&p.packed>=p.ordered))?'done':(x.reservations.length||x.preps.length)?'active':'pending',
   docs:[...x.reservations.map(r=>stage(r,r.erp_reference||r.dossier_reference,'order',d.o?.id,'sales-orders')),...x.preps.map(r=>stage(r,r.number,'preparation',d.o?.id,'tms')),...x.packages.map(r=>stage(r,r.erp_reference||r.dossier_reference,'preparation',d.o?.id,'tms'))],
   info:d.o?`${tr('Sin reservar')} : ${p.missing} · ${tr('Preparado / previsto')} : ${p.picked} / ${p.planned}`:'',
   need:p.missing>0?'Reservar las cantidades que faltan o reponerlas con una compra.':'Preparar y escanear cada producto: el bulto queda listo para expedir.'},
  {title:'Expedición y recepción',state:p.done?'done':x.transport.some(t=>t.status==='Excepción'||late(t))?'blocked':x.ships.length?'active':'pending',
   docs:[...x.ships.map(s=>stage(s,s.number,'delivery',s.tms_delivery_id,'tms')),...x.transport.map(t=>stage(t,t.erp_reference||t.dossier_reference,'delivery',t.id,'tms')),...x.proofs.map(r=>stage(r,r.erp_reference||r.dossier_reference,'proof',r.delivery_id,'sales-orders'))],
   info:d.o?`${tr('Expedido / pedido')} : ${p.shipped} / ${p.ordered} · ${tr('Entregado con prueba firmada')} : ${p.proved} / ${p.ordered}`:'',
   need:'Cargar y confirmar la salida; registrar la entrega con la firma del cliente.'},
  {title:'Facturación',state:!fin?'restricted':f.covered?'done':f.rows.length?'active':'pending',
   docs:fin?f.rows.map(i=>stage(i,i.number,'payment',i.id,'payments')):[],info:fin?`${tr('Facturado')} : ${money(f.billed/100)} · ${tr('Pendiente de facturar')} : ${money(f.unbilled/100)}`:'',
   need:'La factura se genera al validar la última entrega firmada; debe cubrir todas las líneas del pedido.'},
  {title:'Seguimiento del pago',state:!fin?'restricted':f.overdue?'blocked':f.settled?'done':f.rows.length?'active':'pending',
   docs:fin?x.payments.filter(p=>p.status==='confirmed').map(p=>stage(p,p.erp_reference||p.dossier_reference,'payment',p.invoice_id,'payments')):[],
   info:fin?`${tr('Cobrado')} : ${money(f.paid/100)} · ${tr('Saldo pendiente')} : ${money(f.balance/100)}${f.overdue?' · '+tr('Importe vencido')+' : '+money(f.overdue/100):''}`:'',
   need:f?.overdue?'Relanzar las facturas vencidas y registrar los cobros.':'Registrar cada cobro con fecha, importe y medio.'},
  /* Sólo se cierra lo que se ha podido comprobar: sin ver la facturación, entregado no es cerrado. */
  {title:'Cierre del proceso de venta',state:cancelled?'closed':p.done&&fin&&f.settled&&!x.returns?.some(r=>!['closed','cancelled'].includes(r.status))?'done':p.done&&!fin?'restricted':'pending',
   info:tr(cancelled?'Proceso anulado.':p.done&&fin&&f.settled?'Entregado, facturado y cobrado.':p.done&&!fin?'Entregado. La facturación y el cobro no se pueden comprobar con este perfil.':'Se cierra al quedar entregado, facturado y cobrado.'),need:'Completar las etapas anteriores.'}
 ];
 const shared=serverStates.get(d.key);return shared?{steps:shared.steps.map((step,i)=>({...steps[i],...step,info:sharedInfo(shared,i,step.info)})),closed:shared.closed||shared.cancelled}:{steps,closed:cancelled};
}
function renderSale(d,x){
 const {steps:base,closed}=saleSteps(d,x),steps=saleActions(d,x,base);
 const returns=(x.returns||[]).length?`<div class="arcPanel card gdfAside"><h3>${tr('Devoluciones de este proceso')}</h3><p>${tr('Se siguen en Devoluciones, en su propio proceso de retorno.')}</p><ul class="gdfDocs">${x.returns.map(r=>docButton(doc(r.number,'returns',r.id,'returns'))).join('')}</ul></div>`:'';
 remember(d.key,steps,closed);
 renderProcess({number:saleNumber(d),party:customer(d),address:d.o?.delivery_address||'',steps,closed,after:returns+externalStatus(serverStates.get(d.key))});
 window.ArchitectProjectControls?.mountDossier(d.key,$('gdfDetail'));
}

function purchaseSteps(o,x){
 const stage=(row,ref,action,id,module)=>processDoc(row,ref,o.dossier_number,action,id,module);
 const day=today(),cancelled=o.status==='cancelled';
 const ordered=sum(x.lines),received=sum(x.lines,'received_quantity'),stocked=x.moves.ok?sum(x.moves.rows.filter(m=>n(m.quantity)>0)):0;
 const lateReceipt=['sent','partial'].includes(o.status)&&o.expected_date&&String(o.expected_date).slice(0,10)<day&&received<ordered;
 const invoices=x.invoices.rows.filter(i=>i.status!=='cancelled'),posted=invoices.filter(i=>i.status==='posted');
 const invoiced=posted.reduce((v,i)=>v+cents(i.total),0),paid=x.payments.rows.filter(p=>p.status==='confirmed').reduce((v,p)=>v+cents(p.amount),0);
 const balance=Math.max(0,invoiced-paid),overdue=posted.some(i=>i.due_date&&i.due_date<day)&&balance>0;
 const fullyInvoiced=posted.length>0&&invoiced>=cents(o.total)-1,settled=fullyInvoiced&&balance===0;
 const gaps=x.lines.filter(l=>n(l.received_quantity)>0&&n(l.received_quantity)!==n(l.quantity));
 const origin={low_stock:'Alerta de stock bajo el mínimo',sales_order:'Pedido de cliente superior al stock disponible',manual:'Creado en el módulo Compras'}[o.source_kind||'manual'];
 const steps=[
  {title:'Origen de la demanda',state:'done',docs:[x.source&&doc(x.source.number,'order',x.source.id,'sales-orders')],info:tr(origin),need:''},
  {title:'Pedido de compra',state:cancelled?'closed':o.status==='draft'?'active':'done',docs:[stage(o,o.order_number,'purchase',o.id,'gamaPurchasesV14')],
   info:`${tr('Total')} : ${money(o.total)}${o.expected_date?' · '+tr('Recepción prevista')+' : '+esc(String(o.expected_date).slice(0,10)):''}`,need:'Revisar cantidades y precios y enviar el pedido al proveedor.'},
  {title:'Recepción y control',state:cancelled?'closed':ordered>0&&received>=ordered?'done':lateReceipt?'blocked':received>0?'active':'pending',
   docs:[],info:`${tr('Recibido / pedido')} : ${received} / ${ordered}${gaps.length?' · '+tr('Líneas con diferencia')+' : '+gaps.length:''}`,
   need:lateReceipt?'La recepción prevista ya pasó: reclamar al proveedor o reprogramarla.':'Recibir la mercancía y contrastar cantidades con el pedido.'},
  {title:'Puesta en stock',state:!x.moves.ok?'restricted':received>0&&stocked>=received?'done':stocked>0?'active':'pending',
   docs:x.moves.rows.slice(0,6).map(m=>stage(m,m.erp_reference,'purchase',o.id,'gamaPurchasesV14')),info:`${tr('En stock / recibido')} : ${stocked} / ${received}`,need:'Ubicar lo recibido en su almacén: cada entrada queda como movimiento de stock.'},
  {title:'Factura del proveedor',state:!x.invoices.ok?'restricted':fullyInvoiced?'done':invoices.length?'active':'pending',
   docs:invoices.map(i=>stage(i,i.erp_reference||i.number,'supplier_invoice',i.id,'accounting')),info:x.invoices.ok?`${tr('Facturado')} : ${money(invoiced/100)} / ${money(o.total)}`:'',need:invoices.length?'Registrar la factura del proveedor contra este pedido.':'Registrar la factura recibida: el pedido de compra no genera una factura automáticamente.'},
  {title:'Seguimiento del pago',state:!x.payments.ok?'restricted':overdue?'blocked':settled?'done':paid>0||invoices.length?'active':'pending',
   docs:x.payments.rows.filter(p=>p.status==='confirmed').map(p=>stage(p,p.erp_reference,'supplier_payment',p.id,'accounting')),
   info:x.payments.ok?`${tr('Pagado')} : ${money(paid/100)} · ${tr('Saldo pendiente')} : ${money(balance/100)}`:'',need:overdue?'Pagar las facturas vencidas del proveedor.':'Registrar cada pago al proveedor.'},
  {title:'Cierre del proceso de compra',state:cancelled?'closed':ordered>0&&received>=ordered&&settled?'done':'pending',
   info:tr(cancelled?'Proceso anulado.':ordered>0&&received>=ordered&&settled?'Recibido, en stock, facturado y pagado.':'Se cierra al quedar recibido, facturado y pagado.'),need:'Completar las etapas anteriores.'}
 ];
 const shared=serverStates.get('p:'+o.id);return shared?{steps:shared.steps.map((step,i)=>({...steps[i],...step,info:sharedInfo(shared,i,step.info)})),closed:shared.closed||shared.cancelled}:{steps,closed:cancelled};
}
function renderPurchase(o,x){
 const {steps:base,closed}=purchaseSteps(o,x),steps=purchaseActions(o,x,base);
 remember('p:'+o.id,steps,closed);
 renderProcess({number:purchaseNumber(o),party:supplierName(o),address:'',steps,closed,after:''});
 window.ArchitectProjectControls?.mountDossier('p:'+o.id,$('gdfDetail'));
}

function sharedInfo(s,i,fallback){const m=s.metrics;if(!m)return esc(fallback);const fr=window.GamaI18n?.language==='fr',en=window.GamaI18n?.language==='en',tr=(es,f,e)=>fr?f:en?e:es;
 if(s.steps[i]?.state==='restricted')return tr('La facturación y el cobro no se pueden comprobar con este perfil.','La facturation et les paiements ne sont pas accessibles avec ce profil.','This profile cannot verify billing and payments.');
 let value='';if(s.key.startsWith('p:')){value=({2:tr('Recibido / aceptado','Reçu / accepté','Received / accepted')+`: ${m.received} / ${m.ordered}`,3:tr('Mercancía ubicada','Marchandises localisées','Located goods')+`: ${m.stocked} / ${m.goods}`,4:tr('Recepción sin factura conciliada','Réception sans facture rapprochée','Unmatched received quantity')+`: ${m.unbilled}`,5:tr('Saldo neto de abonos','Solde net des avoirs','Balance after credits')+`: ${money(m.balance)}`,6:tr('Devoluciones abiertas','Retours ouverts','Open returns')+`: ${m.open_returns}`})[i]||''}
 else value=({3:T('Sin reservar')+`: ${m.missing}`,4:T('Expedido / pedido')+`: ${m.shipped} / ${m.ordered} · `+tr('Entregas firmadas / servicios ejecutados','Livraisons signées / services exécutés','Signed deliveries / completed services')+`: ${m.performed} / ${m.ordered}`,5:tr('Cantidad sin facturar','Quantité non facturée','Unbilled quantity')+`: ${m.unbilled}`,6:T('Cobrado')+`: ${money(m.paid)} · `+tr('Abonos','Avoirs','Credits')+`: ${money(m.credits)} · `+T('Saldo pendiente')+`: ${money(m.balance)}`,7:tr('Devoluciones abiertas','Retours ouverts','Open returns')+`: ${m.open_returns}`})[i]||'';return esc(value)}
function externalStatus(s){if(!s||s.external_complete===null)return '';return `<div class="arcPanel card"><h3>${tr('Formalidades externas')}</h3><p>${tr(s.external_complete?'Documentos externos completos.':'Documentos externos por completar.')} ${s.external_pending||0}</p><p>${tr('Este estado se muestra por separado del cierre operativo.')}</p></div>`}
function docButton(x){return `<li><button type="button" class="gdfDoc" data-action="${esc(x.action)}" data-id="${esc(x.id||'')}" ${x.module&&!can(x.module)?'disabled':''}>${esc(x.ref)}</button>${x.issuedReference?`<small class="sdMuted">${esc(T('Documento'))} : ${esc(x.issuedReference)}</small>`:''}</li>`}
function renderProcess({number,party,address,steps,closed,after}){
 const links=[];
 const actions=s=>s?.state==='restricted'?[]:(s?.actions||[]).filter(a=>a.id&&can(a.module));
 const actionLinks=s=>actions(s).map(a=>{const key=links.push(a)-1;return `<button type="button" class="arcButton secondary gdfAction" data-gdf-next="${key}">${tr(a.label)}${a.ref?` <span>${esc(a.ref)}</span>`:''}</button>`}).join('');
 const current=steps.findIndex(s=>['active','blocked','pending'].includes(s.state)),summary=summarize(steps,closed);
 /* Lo que este perfil no puede comprobar no se da por hecho: el proceso no está completo para él. */
 const next=closed?'Proceso cerrado.':summary.state==='done'?'Proceso completo.':current<0?'Las etapas siguientes no se pueden comprobar con este perfil.':steps[current].need||'Completar las etapas anteriores.';
 const stepper=`<ol class="gdfStepper" aria-label="${esc(T('Etapas del proceso'))}">${steps.map((s,i)=>`<li data-state="${closed&&s.state!=='done'?'closed':s.state}"${i===current?' aria-current="step"':''}><span class="gdfDot">${i+1}</span><span class="gdfStepName">${tr(s.title)}</span></li>`).join('')}</ol>`;
 const cards=steps.map((s,i)=>{const docs=(s.docs||[]).filter(Boolean),state=closed&&s.state!=='done'?'closed':s.state;
  return `<li class="arcPanel gdfStep ${state}" data-step="${i+1}"><div class="gdfStepHead"><span class="gdfNum" aria-hidden="true">${i+1}</span><h3>${tr(s.title)}</h3><span class="gdfBadge">${tr(STATES[state])}</span></div>${docs.length?`<ul class="gdfDocs" aria-label="${esc(T('Documentos'))}">${docs.map(docButton).join('')}</ul>`:''}${s.info?`<p>${s.info}</p>`:''}${['active','blocked','pending'].includes(state)&&s.need?`<p class="gdfNeed"><b>${tr('Para avanzar')}</b> ${tr(s.need)}</p>`:''}<div class="gdfActions">${actionLinks(s)}</div></li>`}).join('');
 window.ArcUI.render($('gdfDetail'),`<div class="arcPanel card gdfSummary"><div class="gdfSummaryHead"><h2>${esc(number)}</h2><span class="gdfBadge" data-status="${summary.state}">${tr(PROCESS_STATUS[summary.state])}</span></div><p>${esc(party)}</p>${address?`<p>${esc(address)}</p>`:''}<p class="gdfNext"><b>${tr('Próxima acción')}</b> ${tr(next)}</p>${!closed&&current>=0?`<div class="gdfActions">${actionLinks(steps[current])}</div>`:''}</div>${stepper}<ol class="gdfFlow">${cards}</ol>${after||''}`);
 $('gdfDetail').querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>act(b.dataset.action,b.dataset.id));
 $('gdfDetail').querySelectorAll('[data-gdf-next]').forEach(b=>b.onclick=async()=>{const a=links[Number(b.dataset.gdfNext)];if(!a||!can(ID)||!can(a.module))return;b.disabled=true;try{await act(a.action,a.id)}finally{b.disabled=false}});
}
/* Only minimal, server-scoped action metadata is displayed. */
const historyWords={history:['Historial de acciones','Historique des actions','Action history'],loading:['Cargando historial…','Chargement de l’historique…','Loading history…'],unknown:['Autor no registrado','Auteur non enregistré','Author not recorded'],unavailable:['Usuario no disponible','Utilisateur indisponible','User unavailable'],empty:['No hay acciones registradas para esta etapa.','Aucune action enregistrée pour cette étape.','No actions recorded for this step.'],old:['Etapa completada; no hay una validación con autor registrada.','Étape terminée ; aucune validation avec auteur n’est enregistrée.','Step complete; no validation with an author was recorded.'],failed:['No se pudo cargar el historial.','Impossible de charger l’historique.','Could not load history.'],retry:['Reintentar','Réessayer','Retry'],more:['Ver acciones anteriores','Voir les actions précédentes','Load earlier actions'],request:['Solicitud actualizada','Demande mise à jour','Request updated'],request_created:['Solicitud creada','Demande créée','Request created'],purchase_created:['Origen del pedido registrado','Origine de l’achat enregistrée','Purchase origin recorded'],purchase:['Pedido de compra actualizado','Commande d’achat mise à jour','Purchase order updated'],receipt:['Recepción registrada','Réception enregistrée','Receipt recorded'],stock:['Movimiento de stock','Mouvement de stock','Stock movement'],invoice:['Factura registrada / actualizada','Facture enregistrée / mise à jour','Invoice recorded / updated'],supplier_invoice:['Factura del proveedor registrada / actualizada','Facture fournisseur enregistrée / mise à jour','Supplier invoice recorded / updated'],invoice_match:['Conciliación de factura','Rapprochement de facture','Invoice matching'],payment:['Cobro registrado / actualizado','Encaissement enregistré / mis à jour','Payment recorded / updated'],supplier_payment:['Pago registrado / actualizado','Paiement enregistré / mis à jour','Supplier payment recorded / updated'],closure:['Cierre del proceso actualizado','Clôture du processus mise à jour','Process closure updated'],created:['Pedido creado','Commande créée','Order created'],confirm:['Pedido confirmado','Commande confirmée','Order confirmed'],cancel:['Anulación registrada','Annulation enregistrée','Cancellation recorded'],update:['Pedido actualizado','Commande mise à jour','Order updated'],dispatch:['Expedición registrada','Expédition enregistrée','Dispatch recorded'],shipment:['Expedición registrada','Expédition enregistrée','Dispatch recorded'],return_created:['Devolución creada','Retour créé','Return created'],return_request:['Solicitud de devolución actualizada','Demande de retour mise à jour','Return request updated'],return_treatment:['Tratamiento del producto registrado','Traitement du produit enregistré','Product treatment recorded'],credit:['Abono registrado','Avoir enregistré','Credit recorded'],refund:['Reembolso registrado','Remboursement enregistré','Refund recorded'],financial_decision:['Decisión financiera registrada','Décision financière enregistrée','Financial decision recorded'],quote_save:['Presupuesto guardado','Devis enregistré','Quote saved'],quote_send:['Presupuesto enviado','Devis envoyé','Quote sent'],quote_accept:['Presupuesto aceptado','Devis accepté','Quote accepted'],quote_accepted:['Presupuesto aceptado','Devis accepté','Quote accepted'],quote_reopen:['Presupuesto reabierto','Devis rouvert','Quote reopened'],quote_cancel:['Presupuesto anulado','Devis annulé','Quote cancelled'],quote_reject:['Presupuesto rechazado','Devis refusé','Quote rejected'],internal_invoice:['Factura interna creada','Facture interne créée','Internal invoice created'],internal_external_link:['Factura externa vinculada','Facture externe liée','External invoice linked'],internal_external_number:['Número fiscal registrado','Numéro fiscal enregistré','Fiscal number recorded'],service_complete:['Servicio ejecutado','Service exécuté','Service completed'],service_cancel:['Ejecución de servicio anulada','Exécution du service annulée','Service completion cancelled'],preparation_cancelled:['Preparación anulada','Préparation annulée','Preparation cancelled'],fulfillment:['Acción de preparación','Action de préparation','Preparation action'],delivery:['Acción de entrega','Action de livraison','Delivery action']};
Object.assign(historyWords,{opportunity:['Opportunidad actualizada','Opportunité mise à jour','Opportunity updated'],opportunity_created:['Opportunidad creada','Opportunité créée','Opportunity created'],proof:['Prueba de entrega registrada','Preuve de livraison enregistrée','Delivery proof recorded'],reserve:['Stock reservado','Stock réservé','Stock reserved'],receipt_auto_reserved:['Stock recibido y reservado','Stock reçu et réservé','Stock received and reserved'],ship:['Expedición registrada','Expédition enregistrée','Dispatch recorded'],invoice_auto_delivery:['Factura creada tras entrega','Facture créée après livraison','Invoice created after delivery'],fulfillment_start:['Preparación iniciada','Préparation commencée','Preparation started'],fulfillment_pick:['Productos preparados','Produits préparés','Products picked'],fulfillment_finish:['Preparación terminada','Préparation terminée','Preparation finished'],fulfillment_package:['Bulto registrado','Colis enregistré','Package recorded'],fulfillment_void_package:['Bulto anulado','Colis annulé','Package cancelled'],fulfillment_incident:['Incidencia registrada','Incident enregistré','Incident recorded'],fulfillment_cancel_preparation:['Preparación anulada','Préparation annulée','Preparation cancelled'],fulfillment_propose_option:['Opción propuesta','Option proposée','Option proposed'],fulfillment_respond_option:['Respuesta del cliente registrada','Réponse du client enregistrée','Customer response recorded']});
function historyText(k){const i={es:0,fr:1,en:2}[window.GamaI18n?.language]??0;return historyWords[k]?.[i]||k}
async function attachHistory(host,key,valid=()=>host.isConnected){
 const cards=[...host.querySelectorAll('.gdfStep:not(.restricted):not(.skip)')];
 const hosts=new Map(cards.map(card=>{const box=document.createElement('div');box.className='gdfHistory';box.textContent=historyText('loading');card.appendChild(box);return [Number(card.dataset.step),{box,card,rows:[]}]}));
 const read=(step=0,offset=0)=>window.ArcData.rpc('gama_process_history',{p_key:key,p_step:step,p_offset:offset});
 function draw(step){const h=hosts.get(step);if(!h||!valid()||!h.box.isConnected)return;const {box,card,rows}=h;const total=Number(rows[0]?.total||rows.length);
  const item=e=>{const name=e.actor_name==='AUTHOR_NOT_RECORDED'?historyText('unknown'):e.actor_name==='USER_UNAVAILABLE'?historyText('unavailable'):e.actor_name||historyText('unknown'),date=new Date(e.at);const label=historyWords[e.action]?historyText(e.action):e.action?.startsWith('fulfillment_')?historyText('fulfillment')+' · '+e.action.slice(12):e.action?.startsWith('delivery_')?historyText('delivery')+' · '+e.action.slice(9):e.action;return `<li><strong>${esc(label)}</strong><span>${esc(name)} · <time datetime="${esc(e.at)}">${esc(Number.isNaN(date.getTime())?'—':date.toLocaleString())}</time></span>${e.reference?`<small>${esc(e.reference)}</small>`:''}${e.status?`<small>${esc(e.status)}</small>`:''}</li>`};
  box.innerHTML=rows.length?`<p class="gdfHistoryLatest">${esc(historyText('history'))} · <b>${esc(rows[0].actor_name==='AUTHOR_NOT_RECORDED'?historyText('unknown'):rows[0].actor_name==='USER_UNAVAILABLE'?historyText('unavailable'):rows[0].actor_name)}</b> · ${esc(new Date(rows[0].at).toLocaleString())}</p><details><summary>${esc(historyText('history'))} (${rows.length} / ${total})</summary><ol>${rows.map(item).join('')}</ol>${rows.length<total?`<button type="button" class="arcButton secondary" data-history-more>${esc(historyText('more'))}</button>`:''}</details>`:`<p>${esc(historyText(card.classList.contains('done')?'old':'empty'))}</p>`;
  box.querySelector('[data-history-more]')?.addEventListener('click',async e=>{const b=e.currentTarget;b.disabled=true;try{const r=await read(step,rows.length);if(!valid())return;h.rows.push(...r.items);draw(step);box.querySelector('details').open=true}catch(_){if(valid())b.textContent=historyText('retry')}finally{b.disabled=false}});
 }
 try{const result=await read();if(!valid())return;if(!Array.isArray(result?.items))throw Error('HISTORY_UNAVAILABLE');for(const e of result.items)hosts.get(e.step)?.rows.push(e);for(const step of hosts.keys())draw(step)}catch(_){if(!valid())return;for(const {box} of hosts.values()){box.innerHTML=`<p>${esc(historyText('failed'))}</p><button type="button" class="arcButton secondary">${esc(historyText('retry'))}</button>`;box.querySelector('button').onclick=()=>{for(const {box:b} of hosts.values())b.remove();attachHistory(host,key,valid)}}}
}
async function act(action,id){
 if(!can(ID))return;
 try{switch(action){
  case'opportunity':if(can('crm'))await window.GamaCRMOpportunities.openRecord(id);break;
  case'request':if(can('customer-requests'))await window.GamaOpenCustomerRequest(id);break;
  case'quote':if(can('quotes')){await GamaQuotes.open();await GamaQuotes.view(id)}break;
  case'order':if(can('sales-orders'))await GamaSales.openOrder(id);break;
  case'preparation':if(can('tms'))await GamaPreparation.open(id);break;
  case'delivery':if(can('tms'))await gamaTMS.openDelivery(id);break;
  case'proof':if(can('sales-orders'))await GamaFulfillment.proof(id);break;
  case'payment':if(can('payments'))await GamaPayments.open({invoiceId:id});break;
  case'order_payments':if(can('payments'))await GamaPayments.open({orderId:id,status:'all'});break;
  case'replenish':if(can('gamaPurchasesV14'))await window.gamaPrepareActionPurchase({order_id:id});break;
  case'closure':await window.ArchitectProjectControls.dossier(id);break;
  case'returns':if(can('returns'))await window.GamaReturns?.openReturn(id);break;
  case'purchase':if(can('gamaPurchasesV14'))await window.gamaOpenPurchaseDossier(id);break;
  case'supplier_invoice':if(can('accounting'))await window.GamaAccounting.open({section:'purchases',invoiceId:id});break;
  case'supplier_payment':if(can('accounting')){const r=await GamaCloud.list('supplier_invoice_payments',{select:'supplier_invoice_id',eq:{id},limit:1});if(r.error||!r.data?.[0])throw r.error||Error('DOCUMENT_NOT_FOUND');if(can('accounting')&&can(ID))await window.GamaAccounting.open({section:'purchases',invoiceId:r.data[0].supplier_invoice_id})}break;
  case'new_supplier_invoice':if(can('accounting'))await window.GamaAccounting.open({section:'purchases',purchaseOrderId:id,newBill:true});break;
 }}catch(e){window.gamaToast?.(T('No se pudo abrir el documento.'))}
}
window.GamaDossierFlow={open,group,progress,financialProgress,summarize,attachHistory};
window.addEventListener('arc:route-leave',e=>{if(e.detail?.id===ID){generation++;clearTimeout(searchTimer);releaseReturns()}});
window.addEventListener('gama:modules-change',()=>{if($(ID)?.classList.contains('active')){if(can(ID))open(null,{tab});else releaseReturns()}});
window.addEventListener('gama:process-change',()=>{if(can(ID)&&$(ID)?.classList.contains('active'))open(selected,{tab})});
window.addEventListener('gama:sales-change',()=>{if(can(ID)&&$(ID)?.classList.contains('active'))open(selected,{tab})});
window.addEventListener('gama:auth-change',()=>{generation++;clearTimeout(searchTimer);releaseReturns();summaryToken++;records=[];purchases=[];summaries=new Map();serverStates.clear();selected=null;tab='PDV';$(ID)?.replaceChildren()});
})();
