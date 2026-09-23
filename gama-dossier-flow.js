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
const PROCESSES={PDV:{module:'dossier-flow',label:'PDV · Proceso de venta'},PDC:{module:'gamaPurchasesV14',label:'PDC · Proceso de compra'}};
let tab='PDV',records=[],purchases=[],suppliers=new Map(),generation=0,selected=null,summaries=new Map(),summaryToken=0;
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
 for(const l of x.lines){const qty=n(l.quantity),sl=x.shipLines.filter(s=>s.order_line_id===l.id),sent=sum(sl),reserved=sum(x.reservations.filter(r=>r.status==='active'&&x.links.some(k=>k.line_id===l.id&&k.reservation_id===r.id)));
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
 const rows=active.map(i=>{const paid=x.payments.filter(p=>p.invoice_id===i.id&&p.status==='confirmed').reduce((v,p)=>v+cents(p.amount),0),balance=Math.max(0,cents(i.total)-paid);return {...i,paid,balance,overdue:balance>0&&!!i.due_date&&i.due_date<today};});
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

function shell(){
 let s=$(ID);if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 const tabs=Object.entries(PROCESSES).filter(([,p])=>can(p.module));
 if(!tabs.some(([k])=>k===tab))tab='PDV';
 window.ArcUI.render(s,GamaUI.header({title:'Seguimiento de procesos',lead:'Cada proceso paso a paso, con un solo número en todos sus documentos.'})
  +`<div class="gdfTabs" role="tablist" aria-label="${esc(T('Procesos'))}">${tabs.map(([k,p])=>`<button type="button" role="tab" class="gdfTab" id="gdfTab${k}" data-gdf-tab="${k}" aria-selected="${tab===k}" aria-controls="gdfPanel">${tr(p.label)}</button>`).join('')}</div>`
  +`<div id="gdfPanel" role="tabpanel" aria-labelledby="gdfTab${tab}"><div class="gdfTools"><input id="gdfSearch" aria-label="${esc(T('Buscar un proceso'))}" placeholder="${esc(T('Buscar un proceso'))}"><button class="arcButton secondary" id="gdfRefresh">${tr('Actualizar')}</button></div><div class="gdfLayout"><div id="gdfList" class="gdfList"></div><div id="gdfDetail" aria-live="polite"></div></div></div>`);
 GamaUI.bindBack(s);window.showTab?.(ID);
 $('gdfSearch').oninput=renderList;$('gdfRefresh').onclick=()=>open(selected,{tab});
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
 list.querySelectorAll('[data-record]').forEach(b=>{b.onclick=()=>detail(b.dataset.record);if(b.dataset.record===focused)b.focus()});
}
/* Las barras de toda la lista, de una vez: los mismos datos que el detalle,
   pedidos por lotes y no proceso a proceso. */
async function loadSummaries(){
 const token=++summaryToken,kind=tab,list=kind==='PDC'?purchases.slice():records.slice();
 let next;
 try{
  if(kind==='PDC'){const data=await purchaseDataFor(list);next=list.map(o=>['p:'+o.id,purchaseSteps(o,data.get(o.id))])}
  else{const data=await saleData(list.filter(d=>d.o).map(d=>d.o));next=list.map(d=>[d.key,saleSteps(d,d.o?data.get(d.o.id):emptySale())])}
  next=next.map(([key,{steps,closed}])=>[key,summarize(steps,closed)]);
 }catch(e){next=list.map(x=>[kind==='PDC'?'p:'+x.id:x.key,{state:'unknown'}])}
 if(token!==summaryToken)return;
 next.forEach(([key,value])=>summaries.set(key,value));renderList();
}
/* El detalle recién leído pone al día la barra de su tarjeta. */
function remember(key,steps,closed){summaries.set(key,summarize(steps,closed));renderList()}
async function open(key=null,options={}){
 if(!can(ID))return;
 if(options.tab&&PROCESSES[options.tab])tab=options.tab;
 if(typeof key==='string'&&key.startsWith('p:'))tab='PDC';
 selected=key;shell();const token=++generation;window.ArcUI.render($('gdfDetail'),tr('Cargando…'));
 try{await window.GamaCloudReady;
  if(tab==='PDC'){
   const [orders,list]=await Promise.all([all('purchase_orders',{select:'id,order_number,supplier_id,status,source_kind,source_order_id,expected_date,total,created_at'}),all('suppliers',{select:'id,name'})]);
   if(token!==generation||!can(ID))return;
   suppliers=new Map(list.map(s=>[s.id,s.name]));
   purchases=orders.sort((a,b)=>String(b.created_at||'').localeCompare(String(a.created_at||'')));
   renderList();loadSummaries();
   if(purchases.length)await detail(purchases.find(o=>'p:'+o.id===key)?'p:'+purchases.find(o=>'p:'+o.id===key).id:'p:'+purchases[0].id);
   else window.ArcUI.render($('gdfDetail'),tr('Los procesos de compra aparecerán al crear un pedido a un proveedor.'));
   return;
  }
  const [orders,quotes,requests]=await Promise.all([all('sales_orders',{select:'id,number,customer_name,delivery_address,status,source_quote_id,source_request_id,source_opportunity_id,created_at'}),can('quotes')?all('invoices',{select:'id,invoice_number,quote_state,quote_details,quote_valid_until,created_at'}):[],can('customer-requests')?all('customer_requests',{select:'id,requester_name,status,invoice_id,created_at'}):[]]);
  if(token!==generation||!can(ID))return;records=group(orders,quotes,requests);renderList();loadSummaries();
  if(records.length)await detail(records.find(d=>d.key===key)?.key||records[0].key);
  else window.ArcUI.render($('gdfDetail'),tr('Los procesos de venta aparecerán al registrar una solicitud, un presupuesto o un pedido.'));
 }catch(e){if(token===generation)failure()}
}
function failure(){window.ArcUI.render($('gdfDetail'),`<p role="alert" class="gdfError">${tr('No se pudo cargar el proceso. Actualiza para reintentar; el avance no está confirmado.')}</p>`)}
const by=async(table,field,a,select='*',extra={})=>{const result=[];for(let i=0;i<a.length;i+=100)result.push(...await all(table,{...extra,select,in:{[field]:a.slice(i,i+100)}}));return result};
const ids=(a,k='id')=>a.map(x=>x[k]).filter(Boolean);
async function detail(key){
 if(!can(ID))return;selected=key;renderList();const token=++generation;window.ArcUI.render($('gdfDetail'),tr('Cargando…'));
 try{
  if(key.startsWith('p:')){const o=purchases.find(x=>'p:'+x.id===key);if(!o)return;const x=(await purchaseDataFor([o])).get(o.id);if(token!==generation||!can(ID))return;renderPurchase(o,x);return}
  const d=records.find(x=>x.key===key);if(!d)return;
  let data=emptySale();
  if(d.o){
   /* El flujo inverso sólo existe si de verdad ha vuelto algo. */
   const [read,returns]=await Promise.all([saleData([d.o],PROOF_DOC_COLUMNS),all('return_orders',{eq:{order_id:d.o.id}}).catch(()=>[])]);
   data=read.get(d.o.id);data.returns=returns;
  }
  /* Paso 1: la oportunidad del CRM de la que nace, por el pedido o por el presupuesto. */
  if(can('crm')){const opportunity=d.o?.source_opportunity_id?await all('crm_opportunities',{select:'id,reference,title,erp_reference',eq:{id:d.o.source_opportunity_id}}).catch(()=>[]):d.q?await all('crm_opportunities',{select:'id,reference,title,erp_reference',eq:{quote_invoice_id:d.q.id}}).catch(()=>[]):[];data.opportunity=opportunity[0]||null}
  if(token!==generation||!can(ID))return;renderSale(d,data);
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
const STATES={done:'Completado',active:'En curso',blocked:'Bloqueado',pending:'Pendiente',skip:'Sin esta etapa',closed:'Cerrado',restricted:'Sin acceso a estos datos'};

function saleSteps(d,x){
 const day=today(),late=t=>t.delivery_date&&t.delivery_date<day&&!['Entregada','Cancelada'].includes(t.status);
 const p=progress(d,x),fin=financeAllowed(),f=fin?financialProgress(x,day):null;
 const cancelled=d.o?.status==='cancelled'||(!d.o&&['cancelled','rejected'].includes(d.q?.quote_state||d.r?.status));
 const confirmed=d.o?.status==='confirmed';
 const quoteExpired=d.q?.quote_state==='sent'&&d.q.quote_valid_until&&d.q.quote_valid_until<day;
 const steps=[
  {title:'Origen de la demanda',state:x.opportunity||d.r?'done':d.q||d.o?'skip':'pending',
   docs:[x.opportunity&&doc(x.opportunity.erp_reference||x.opportunity.reference,'opportunity',x.opportunity.id,'crm'),d.r&&doc(d.r.erp_reference||d.r.dossier_reference||String(d.r.id).slice(0,8).toUpperCase(),'request',d.r.id,'customer-requests')],
   info:x.opportunity?T('Oportunidad del CRM')+' · '+esc(x.opportunity.title||''):d.r?tr('Solicitud del cliente'):tr('Pedido o presupuesto directo, sin solicitud ni oportunidad previa.'),
   need:'Registrar la oportunidad en el CRM o la solicitud del cliente, con sus productos y cantidades.'},
  {title:'Presupuesto',state:d.q?(confirmed||['accepted','converted'].includes(d.q.quote_state)?'done':['rejected','cancelled'].includes(d.q.quote_state)?'closed':quoteExpired?'blocked':'active'):d.o?'skip':'pending',
   docs:[d.q&&doc(d.q.invoice_number,'quote',d.q.id,'quotes')],info:quoteExpired?tr('Presupuesto vencido: revisar la vigencia antes de aceptar.'):'',
   need:'Completar cliente, productos, precios y vigencia; enviarlo y registrar la aceptación del cliente.'},
  {title:'Pedido',state:d.o?(confirmed?'done':d.o.status==='cancelled'?'closed':'active'):'pending',
   docs:[d.o&&doc(d.o.number,'order',d.o.id,'sales-orders')],need:'Confirmar el pedido: reserva el stock disponible y abre la preparación.'},
  {title:'Reserva de stock y preparación',state:!confirmed?'pending':p.missing>0?'blocked':(p.complete||(p.ordered>0&&p.packed>=p.ordered))?'done':(x.reservations.length||x.preps.length)?'active':'pending',
   docs:[...x.reservations.map(r=>doc(r.erp_reference||r.dossier_reference,'order',d.o?.id,'sales-orders')),...x.preps.map(r=>doc(r.number,'preparation',d.o?.id,'tms')),...x.packages.map(r=>doc(r.erp_reference||r.dossier_reference,'preparation',d.o?.id,'tms'))],
   info:d.o?`${tr('Sin reservar')} : ${p.missing} · ${tr('Preparado / previsto')} : ${p.picked} / ${p.planned}`:'',
   need:p.missing>0?'Reservar las cantidades que faltan o reponerlas con una compra.':'Preparar y escanear cada producto: el bulto queda listo para expedir.'},
  {title:'Expedición y recepción',state:p.done?'done':x.transport.some(t=>t.status==='Excepción'||late(t))?'blocked':x.ships.length?'active':'pending',
   docs:[...x.ships.map(s=>doc(s.number,'delivery',s.tms_delivery_id,'tms')),...x.transport.map(t=>doc(t.erp_reference||t.dossier_reference,'delivery',t.id,'tms')),...x.proofs.map(r=>doc(r.erp_reference||r.dossier_reference,'proof',r.delivery_id,'sales-orders'))],
   info:d.o?`${tr('Expedido / pedido')} : ${p.shipped} / ${p.ordered} · ${tr('Entregado con prueba firmada')} : ${p.proved} / ${p.ordered}`:'',
   need:'Cargar y confirmar la salida; registrar la entrega con la firma del cliente.'},
  {title:'Facturación',state:!fin?'restricted':f.covered?'done':f.rows.length?'active':'pending',
   docs:fin?f.rows.map(i=>doc(i.number,'payment',i.id,'payments')):[],info:fin?`${tr('Facturado')} : ${money(f.billed/100)} · ${tr('Pendiente de facturar')} : ${money(f.unbilled/100)}`:'',
   need:'La factura se genera al validar la última entrega firmada; debe cubrir todas las líneas del pedido.'},
  {title:'Seguimiento del pago',state:!fin?'restricted':f.overdue?'blocked':f.settled?'done':f.rows.length?'active':'pending',
   docs:fin?x.payments.filter(p=>p.status==='confirmed').map(p=>doc(p.erp_reference||p.dossier_reference,'payment',p.invoice_id,'payments')):[],
   info:fin?`${tr('Cobrado')} : ${money(f.paid/100)} · ${tr('Saldo pendiente')} : ${money(f.balance/100)}${f.overdue?' · '+tr('Importe vencido')+' : '+money(f.overdue/100):''}`:'',
   need:f?.overdue?'Relanzar las facturas vencidas y registrar los cobros.':'Registrar cada cobro con fecha, importe y medio.'},
  /* Sólo se cierra lo que se ha podido comprobar: sin ver la facturación, entregado no es cerrado. */
  {title:'Cierre del proceso de venta',state:cancelled?'closed':p.done&&fin&&f.settled?'done':p.done&&!fin?'restricted':'pending',
   info:tr(cancelled?'Proceso anulado.':p.done&&fin&&f.settled?'Entregado, facturado y cobrado.':p.done&&!fin?'Entregado. La facturación y el cobro no se pueden comprobar con este perfil.':'Se cierra al quedar entregado, facturado y cobrado.'),need:'Completar las etapas anteriores.'}
 ];
 return {steps,closed:cancelled};
}
function renderSale(d,x){
 const {steps,closed}=saleSteps(d,x);
 const returns=(x.returns||[]).length?`<div class="arcPanel card gdfAside"><h3>${tr('Devoluciones de este proceso')}</h3><p>${tr('Se siguen en Devoluciones, en su propio proceso de retorno.')}</p><ul class="gdfDocs">${x.returns.map(r=>docButton(doc(r.number,'returns',r.id,'returns'))).join('')}</ul></div>`:'';
 remember(d.key,steps,closed);
 renderProcess({number:saleNumber(d),party:customer(d),address:d.o?.delivery_address||'',steps,closed,after:returns});
 window.ArchitectProjectControls?.mountDossier(d.key,$('gdfDetail'));
}

function purchaseSteps(o,x){
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
  {title:'Pedido de compra',state:cancelled?'closed':o.status==='draft'?'active':'done',docs:[doc(o.order_number,'purchase',o.id,'gamaPurchasesV14')],
   info:`${tr('Total')} : ${money(o.total)}${o.expected_date?' · '+tr('Recepción prevista')+' : '+esc(String(o.expected_date).slice(0,10)):''}`,need:'Revisar cantidades y precios y enviar el pedido al proveedor.'},
  {title:'Recepción y control',state:cancelled?'closed':ordered>0&&received>=ordered?'done':lateReceipt?'blocked':received>0?'active':'pending',
   docs:[],info:`${tr('Recibido / pedido')} : ${received} / ${ordered}${gaps.length?' · '+tr('Líneas con diferencia')+' : '+gaps.length:''}`,
   need:lateReceipt?'La recepción prevista ya pasó: reclamar al proveedor o reprogramarla.':'Recibir la mercancía y contrastar cantidades con el pedido.'},
  {title:'Puesta en stock',state:!x.moves.ok?'restricted':received>0&&stocked>=received?'done':stocked>0?'active':'pending',
   docs:x.moves.rows.slice(0,6).map(m=>doc(m.erp_reference,'movement',m.id,'movement')),info:`${tr('En stock / recibido')} : ${stocked} / ${received}`,need:'Ubicar lo recibido en su almacén: cada entrada queda como movimiento de stock.'},
  {title:'Factura del proveedor',state:!x.invoices.ok?'restricted':fullyInvoiced?'done':invoices.length?'active':'pending',
   docs:invoices.map(i=>doc(i.erp_reference||i.number,'supplier_invoice',i.id,'accounting')),info:x.invoices.ok?`${tr('Facturado')} : ${money(invoiced/100)} / ${money(o.total)}`:'',need:'Registrar la factura del proveedor contra este pedido.'},
  {title:'Seguimiento del pago',state:!x.payments.ok?'restricted':overdue?'blocked':settled?'done':paid>0||invoices.length?'active':'pending',
   docs:x.payments.rows.filter(p=>p.status==='confirmed').map(p=>doc(p.erp_reference,'supplier_payment',p.id,'accounting')),
   info:x.payments.ok?`${tr('Pagado')} : ${money(paid/100)} · ${tr('Saldo pendiente')} : ${money(balance/100)}`:'',need:overdue?'Pagar las facturas vencidas del proveedor.':'Registrar cada pago al proveedor.'},
  {title:'Cierre del proceso de compra',state:cancelled?'closed':ordered>0&&received>=ordered&&settled?'done':'pending',
   info:tr(cancelled?'Proceso anulado.':ordered>0&&received>=ordered&&settled?'Recibido, en stock, facturado y pagado.':'Se cierra al quedar recibido, facturado y pagado.'),need:'Completar las etapas anteriores.'}
 ];
 return {steps,closed:cancelled};
}
function renderPurchase(o,x){
 const {steps,closed}=purchaseSteps(o,x);
 remember('p:'+o.id,steps,closed);
 renderProcess({number:purchaseNumber(o),party:supplierName(o),address:'',steps,closed,after:''});
}

function docButton(x){return `<li><button type="button" class="gdfDoc" data-action="${esc(x.action)}" data-id="${esc(x.id||'')}" ${x.module&&!can(x.module)?'disabled':''}>${esc(x.ref)}</button></li>`}
function renderProcess({number,party,address,steps,closed,after}){
 const current=steps.findIndex(s=>['active','blocked','pending'].includes(s.state)),summary=summarize(steps,closed);
 /* Lo que este perfil no puede comprobar no se da por hecho: el proceso no está completo para él. */
 const next=closed?'Proceso cerrado.':summary.state==='done'?'Proceso completo.':current<0?'Las etapas siguientes no se pueden comprobar con este perfil.':steps[current].need||'Completar las etapas anteriores.';
 const stepper=`<ol class="gdfStepper" aria-label="${esc(T('Etapas del proceso'))}">${steps.map((s,i)=>`<li data-state="${closed&&s.state!=='done'?'closed':s.state}"${i===current?' aria-current="step"':''}><span class="gdfDot">${i+1}</span><span class="gdfStepName">${tr(s.title)}</span></li>`).join('')}</ol>`;
 const cards=steps.map((s,i)=>{const docs=(s.docs||[]).filter(Boolean),state=closed&&s.state!=='done'?'closed':s.state;
  return `<li class="arcPanel gdfStep ${state}" data-step="${i+1}"><div class="gdfStepHead"><span class="gdfNum" aria-hidden="true">${i+1}</span><h3>${tr(s.title)}</h3><span class="gdfBadge">${tr(STATES[state])}</span></div>${docs.length?`<ul class="gdfDocs" aria-label="${esc(T('Documentos'))}">${docs.map(docButton).join('')}</ul>`:''}${s.info?`<p>${s.info}</p>`:''}${['active','blocked','pending'].includes(state)&&s.need?`<p class="gdfNeed"><b>${tr('Para avanzar')}</b> ${tr(s.need)}</p>`:''}</li>`}).join('');
 window.ArcUI.render($('gdfDetail'),`<div class="arcPanel card gdfSummary"><div class="gdfSummaryHead"><h2>${esc(number)}</h2><span class="gdfBadge" data-status="${summary.state}">${tr(PROCESS_STATUS[summary.state])}</span></div><p>${esc(party)}</p>${address?`<p>${esc(address)}</p>`:''}<p class="gdfNext"><b>${tr('Próxima acción')}</b> ${tr(next)}</p></div>${stepper}<ol class="gdfFlow">${cards}</ol>${after||''}`);
 $('gdfDetail').querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>act(b.dataset.action,b.dataset.id));
}
async function act(action,id){
 if(!can(ID))return;
 try{switch(action){
  case'opportunity':if(can('crm')){window.GamaOpenCRM?.();window.ArcRouter?.show('crm')}break;
  case'request':if(can('customer-requests'))await window.GamaOpenCustomerRequest(id);break;
  case'quote':if(can('quotes')){await GamaQuotes.open();await GamaQuotes.view(id)}break;
  case'order':if(can('sales-orders'))await GamaSales.openOrder(id);break;
  case'preparation':if(can('tms'))await GamaPreparation.open(id);break;
  case'delivery':if(can('tms'))await gamaTMS.openDelivery(id);break;
  case'proof':if(can('sales-orders'))await GamaFulfillment.proof(id);break;
  case'payment':if(can('payments'))await GamaPayments.open({invoiceId:id});break;
  case'returns':if(can('returns'))await window.GamaReturns?.openReturn(id);break;
  case'purchase':if(can('gamaPurchasesV14'))await window.gamaOpenPurchaseDossier(id);break;
  case'movement':if(can('movement'))await window.ArcRouter.open('movement');break;
  case'supplier_invoice':case'supplier_payment':if(can('accounting'))await window.GamaAccounting.open({section:'payables'});break;
 }}catch(e){window.gamaToast?.(T('No se pudo abrir el documento.'))}
}
window.GamaDossierFlow={open,group,progress,financialProgress,summarize};
window.addEventListener('gama:sales-change',()=>{if(can(ID)&&$(ID)?.classList.contains('active'))open(selected,{tab})});
window.addEventListener('gama:auth-change',()=>{generation++;summaryToken++;records=[];purchases=[];summaries=new Map();selected=null;tab='PDV';$(ID)?.replaceChildren()});
})();
