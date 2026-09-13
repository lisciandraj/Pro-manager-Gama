/* Read-only customer journey. Existing actions/RLS remain authoritative. */
(function(){
'use strict';
const ID='dossier-flow', $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const can=id=>!!window.gamaAccessAllowed?.(id);
const financeAllowed=()=>can('sales-orders')&&can('billing');
const money=v=>Number(v||0).toLocaleString(window.GamaI18n?.locale||'es-EC',{style:'currency',currency:'USD'});
const cents=v=>Math.round(Number(v||0)*100);
const n=v=>Number(v||0), sum=(a,key='quantity')=>a.reduce((s,x)=>s+n(x[key]),0);
let records=[],generation=0,selected=null;
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
const ref=d=>d.o?.dossier_label||d.q?.dossier_label||d.r?.dossier_label||d.o?.number||d.q?.invoice_number||String(d.r?.id||d.q?.id||'').slice(0,8).toUpperCase();
const customer=d=>d.o?.customer_name||d.q?.quote_details?.client||d.r?.requester_name||'—';
function shell(){
 if(!$('gdfStyle')){const s=document.createElement('style');s.id='gdfStyle';s.textContent=`#dossier-flow{display:none}#dossier-flow.active{display:block}.gdfTools{display:flex;flex-wrap:wrap;gap:10px;margin:15px 0}.gdfTools input{flex:1;min-width:180px}.gdfLayout{display:grid;grid-template-columns:minmax(220px,300px) minmax(0,1fr);gap:18px}.gdfList{max-height:75vh;overflow:auto}.gdfRecord{display:block;width:100%;text-align:left;margin-bottom:8px;padding:14px;border:1px solid #d4e2e6;background:white;color:#18324a;border-radius:12px;overflow-wrap:anywhere}.gdfRecord[aria-pressed=true]{border:2px solid #087c8b;background:#eef8f8}.gdfRecord small{display:block;margin-top:5px}.gdfFlow{list-style:none;padding:0;margin:0}.gdfStep{position:relative;background:#fff;border:1px solid #d9e4e8;border-left:5px solid #9aaab3;border-radius:12px;margin:0 0 28px;padding:18px;overflow-wrap:anywhere}.gdfStep:not(:last-child):after{content:'↓';position:absolute;bottom:-27px;left:22px;color:#087c8b;font-size:24px}.gdfStep.done{border-left-color:#168263}.gdfStep.blocked{border-left-color:#c14a37}.gdfStep.active{border-left-color:#db8a23}.gdfStep h3{margin:0 0 8px}.gdfBadge{display:inline-block;background:#eef3f4;padding:4px 9px;border-radius:20px;font-size:13px}.gdfStep ul{padding-left:20px}.gdfStep li{margin:7px 0}.gdfStats{display:flex;flex-wrap:wrap;gap:16px;margin:15px 0}.gdfError{color:#a93628}.gdfDelivery{border-top:1px solid #d9e4e8;padding:12px 0}@media(max-width:760px){.gdfLayout{grid-template-columns:1fr}.gdfList{max-height:240px}}`;document.head.appendChild(s)}
 let s=$(ID);if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 s.innerHTML=GamaUI.header({title:'Seguimiento de expedientes',lead:'De la solicitud del cliente al cobro: avance, necesidades y requisitos.'})+`<div class="gdfTools"><input id="gdfSearch" data-gi-aria-label=320b429c7b40 aria-label="Buscar expediente" data-gi-placeholder=320b429c7b40 placeholder="Buscar expediente" data-gi-live><button class="secondary" id="gdfRefresh">${tr('Actualizar')}</button></div><div class="gdfLayout"><div id="gdfList" class="gdfList"></div><div id="gdfDetail" aria-live="polite"></div></div>`;
 GamaUI.bindBack(s);window.showTab?.(ID);$('gdfSearch').oninput=renderList;$('gdfRefresh').onclick=()=>open(selected);
}
function renderList(){
 const q=$('gdfSearch').value.trim().toLocaleLowerCase();const a=records.filter(d=>[ref(d),customer(d),d.q?.invoice_number,d.r?.id,d.o?.number,d.o?.original_number,d.q?.original_number,d.r?.dossier_reference].some(v=>String(v||'').toLocaleLowerCase().includes(q)));
 $('gdfList').innerHTML=a.map(d=>`<button class="gdfRecord" data-record="${esc(d.key)}" aria-pressed="${selected===d.key}"><b>${esc(ref(d))}</b><small>${esc(customer(d))}</small><small>${tr(d.o?'Pedido de venta':d.q?'Presupuesto':'Solicitud de cliente')}</small></button>`).join('')||tr('No hay expedientes disponibles.');
 $('gdfList').querySelectorAll('[data-record]').forEach(b=>b.onclick=()=>detail(b.dataset.record));
}
async function open(key=null){
 if(!can(ID))return;selected=key;shell();const token=++generation;$('gdfDetail').innerHTML=tr('Cargando…');
 try{await window.GamaCloudReady;const [orders,quotes,requests]=await Promise.all([all('sales_orders',{select:'id,number,customer_name,delivery_address,status,source_quote_id,source_request_id,created_at'}),can('quotes')?all('invoices',{select:'id,invoice_number,quote_state,quote_details,quote_valid_until,created_at'}):[],can('customer-requests')?all('customer_requests',{select:'id,requester_name,status,invoice_id,created_at'}):[]]);
 if(token!==generation||!can(ID))return;records=group(orders,quotes,requests);renderList();if(records.length)await detail(records.find(d=>d.key===key)?.key||records[0].key);else $('gdfDetail').innerHTML=tr('Los expedientes aparecerán al registrar una solicitud, un presupuesto o un pedido.');
 }catch(e){if(token===generation)failure()}
}
function failure(){ $('gdfDetail').innerHTML=`<p role="alert" class="gdfError">${tr('No se pudo cargar el expediente. Actualiza para reintentar; el avance no está confirmado.')}</p>`; }
async function detail(key){
 if(!can(ID))return;const d=records.find(x=>x.key===key);if(!d)return;selected=key;renderList();const token=++generation;$('gdfDetail').innerHTML=tr('Cargando…');
 try{let data={lines:[],ships:[],shipLines:[],reservations:[],links:[],preps:[],picks:[],packages:[],packageLines:[],transport:[],proofs:[],invoices:[],invoiceLines:[],payments:[]};
 if(d.o){const id=d.o.id;[data.lines,data.ships,data.reservations,data.preps]=await Promise.all([all('sales_order_lines',{eq:{order_id:id}}),all('sales_deliveries',{eq:{order_id:id}}),all('stock_reservations',{eq:{reference_type:'sales_order',reference_id:id}}),all('fulfillment_preparations',{eq:{order_id:id}})]);
 const ids=(a,k='id')=>a.map(x=>x[k]).filter(Boolean);const by=async(table,field,a,select='*')=>{const result=[];for(let i=0;i<a.length;i+=100)result.push(...await all(table,{select,in:{[field]:a.slice(i,i+100)}}));return result};
 [data.links,data.shipLines,data.picks,data.packages,data.transport,data.proofs]=await Promise.all([by('sales_reservation_links','line_id',ids(data.lines)),by('sales_delivery_lines','delivery_id',ids(data.ships)),by('fulfillment_pick_lines','preparation_id',ids(data.preps)),by('fulfillment_packages','preparation_id',ids(data.preps)),by('tms_deliveries','id',ids(data.ships,'tms_delivery_id')),by('tms_proofs','delivery_id',ids(data.ships,'tms_delivery_id'),'delivery_id,captured_at,signature')]);
 if(financeAllowed()){data.invoices=await all('external_invoices',{select:'id,order_id,number,total,due_date,fiscal_status,document_kind,external_number,external_status',eq:{order_id:id}});[data.invoiceLines,data.payments]=await Promise.all([by('external_invoice_lines','invoice_id',ids(data.invoices)),by('external_invoice_payments','invoice_id',ids(data.invoices))]);}
 data.packageLines=(await Promise.all(data.packages.map(p=>all('fulfillment_package_lines',{eq:{package_id:p.id}})))).flat();
 }
 if(token!==generation||!can(ID))return;renderDetail(d,data);
 }catch(e){if(token===generation)failure()}
}
function progress(d,x){
 const EPS=0.000001;let ordered=0,shipped=0,missing=0,delivered=0,proved=0;
 for(const l of x.lines){const qty=n(l.quantity),sl=x.shipLines.filter(s=>s.order_line_id===l.id),sent=sum(sl),reserved=sum(x.reservations.filter(r=>r.status==='active'&&x.links.some(k=>k.line_id===l.id&&k.reservation_id===r.id)));
 ordered+=qty;shipped+=Math.min(qty,sent);missing+=Math.max(0,qty-sent-reserved);
 const matches=(s,proof)=>{const ship=x.ships.find(a=>a.id===s.delivery_id),t=x.transport.find(a=>a.id===ship?.tms_delivery_id);return t?.status==='Entregada'&&(!proof||x.proofs.some(p=>p.delivery_id===t.id&&p.signature))};
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
function renderDetail(d,x){
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const late=t=>t.delivery_date&&t.delivery_date<today&&!['Entregada','Cancelada'].includes(t.status);
 const p=progress(d,x),closed=d.o?.status==='cancelled'||(!d.o&&['cancelled','rejected'].includes(d.q?.quote_state||d.r?.status));
 const financial=financeAllowed(),f=financial?financialProgress(x,today):null;
 const states={done:'Completado',active:'En curso',blocked:'Bloqueado',pending:'Pendiente',skip:'Sin etapa previa registrada',closed:'Cerrado'};
 const btn=(label,kind,id,module)=>can(module)?`<button class="secondary" data-action="${kind}" data-id="${esc(id)}">${tr(label)}</button>`:'';
 const orderAction=d.o?btn('Abrir pedido y resolver requisitos','order',d.o.id,'sales-orders'):'';
 const step=(title,state,requirements,info='',action='')=>`<li class="gdfStep ${closed?'closed':state}"><h3>${tr(title)}</h3><span class="gdfBadge">${tr(closed?'Cerrado':states[state])}</span>${info?'<p>'+info+'</p>':''}<b>${tr('Requisitos para avanzar')}</b><ul>${requirements.map(s=>'<li>'+tr(s)+'</li>').join('')}</ul><div class="gdfTools">${action}</div></li>`;
 const pending=d.o?.status==='confirmed';
 const next=closed?'Expediente cerrado':p.done?(financial?(f.settled?'Expediente entregado, facturado y pagado':!f.covered?'Completar la facturación del pedido.':'Registrar los cobros pendientes o relanzar las facturas vencidas.'):'Entrega completa con prueba'):!d.o?(d.q?'Enviar o validar el presupuesto.':'Revisar la solicitud y crear el presupuesto o pedido.'):!pending?'Confirmar el pedido.':p.missing>0?'Resolver faltantes y acordar las entregas parciales.':!p.complete?'Completar preparación y expedición.':x.ships.some(s=>!s.departed_at)?'Completar carga y confirmar salida.':'Completar las entregas y registrar las pruebas firmadas.';
 const steps=[
 step('1. Solicitud del cliente',d.r?'done':d.o?.source_request_id?'done':'skip',['Identificar al cliente, los productos y las cantidades solicitadas.'],d.r?esc(d.r.dossier_reference||d.r.id):tr('Puede iniciarse directamente con un presupuesto o un pedido.'),d.r?btn('Ver solicitud','request',d.r.id,'customer-requests'):''),
 step('2. Presupuesto',d.q?(d.q.quote_state==='draft'?'active':'done'):d.o?.source_quote_id?'done':d.o?'skip':'pending',['Completar emisor, cliente, dirección, productos, precios y vigencia.','Enviar el presupuesto al cliente para su validación.'],esc(d.q?.invoice_number||d.o?.source_quote_reference||d.o?.source_quote_id||''),d.q?btn('Ver presupuesto','quote',d.q.id,'quotes'):''),
 step('3. Validación y pedido',pending?'done':d.q?.quote_state==='sent'?'active':'pending',['Registrar la aceptación del cliente o confirmar el pedido directo.','Para una aceptación externa, indicar el medio y la referencia del acuerdo.'],d.q?.quote_state==='sent'&&d.q.quote_valid_until&&d.q.quote_valid_until<new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())?tr('Presupuesto vencido: revisar la vigencia antes de aceptar.'):esc(d.o?.number||''),orderAction|| (d.q?btn('Registrar validación','quote',d.q.id,'quotes'):'')),
 step('4. Stock y reservas',!pending?'pending':p.missing>0?'blocked':p.ordered?'done':'blocked',['Reservar existencias para las cantidades pendientes.','Reponer faltantes o registrar un acuerdo de entrega parcial con el cliente.'],`${tr('Cantidad sin reservar')} : ${p.missing}`,orderAction),
 step('5. Preparación',p.complete?'done':p.active.length?'active':'pending',['Registrar las cantidades preparadas del lote reservado.','Enviar las cantidades preparadas al equipo de logística en TMS.','Una expedición parcial necesita el motivo y respetar el acuerdo del cliente.'],`${tr('Lote activo: previsto / preparado')} : ${p.planned} / ${p.picked}`,orderAction),
 step('6. Expedición y salida',p.complete&&x.ships.every(s=>s.departed_at)?'done':x.ships.length?'active':'pending',['Crear la expedición y controlar los bultos en TMS.','En TMS, embalar los productos con peso y dimensiones, escanear la carga y asignar conductor y vehículo antes de salir.'],`${tr('Expedido / pedido')} : ${p.shipped} / ${p.ordered}`,orderAction),
 step('7. Transporte al cliente',p.delivered>=p.ordered&&p.ordered?'done':x.transport.some(t=>t.status==='Excepción'||t.status==='Cancelada'||late(t))?'blocked':x.ships.some(s=>s.departed_at)?'active':'pending',['Planificar la ruta, la dirección y la fecha de entrega.','Resolver retrasos o incidencias de cada expedición.'],tr('Cada expedición se sigue por separado en la lista inferior.')),
 step('8. Entrega y prueba',p.done?'done':p.delivered>0?'active':'pending',['Registrar la recepción y la firma del cliente en la prueba de entrega.','Completar todas las cantidades del pedido; una entrega parcial no cierra el expediente.'],`${tr('Entregado / con prueba firmada / pedido')} : ${p.delivered} / ${p.proved} / ${p.ordered}`)
 ];
 const financeAction=d.o?btn('Ver facturas y registrar cobros','finance',d.o.id,'billing'):'';
 if(financial)steps.push(
 step('9. Facturación interna',f.invoiced?'done':f.rows.length?'active':'pending',['Crear la factura interna desde el presupuesto aceptado.','Cubrir todas las líneas del pedido. El número oficial externo es opcional.'],`${tr('Facturado')} : ${money(f.billed/100)} · ${tr('Pendiente de facturar')} : ${money(f.unbilled/100)}`,financeAction),
 step('10. Pago del cliente',f.overdue?'blocked':f.settled?'done':f.rows.length?'active':'pending',['Registrar cada pago con fecha, importe, medio y referencia.','Solo los cobros confirmados reducen el saldo; los pagos anulados se excluyen.','Saldar cada factura y completar la facturación antes de cerrar el expediente.'],`${tr('Cobrado')} : ${money(f.paid/100)} · ${tr('Saldo pendiente')} : ${money(f.balance/100)} · ${tr('Importe vencido')} : ${money(f.overdue/100)}`,financeAction)
 );
 const financePanel=financial?`<div class="card" id="gdfFinance"><h3>${tr('Facturas y pagos del expediente')}</h3><p>${tr('La facturación y los anticipos pueden registrarse antes de completar la entrega.')}</p>${f.rows.map(i=>`<div class="gdfDelivery"><b>${esc(i.number)}</b> · ${tr(i.document_kind==='internal'?'Factura interna':'Factura externa')}<p>${tr('Referencia externa')} : ${esc(i.external_number||(i.document_kind==='internal'?'—':i.number))}<br>${tr('Vencimiento')} : ${esc(i.due_date||'—')} ${i.overdue?tr('Vencida'):''}</p><p>${tr('Total')} : ${money(i.total)} · ${tr('Cobrado')} : ${money(i.paid/100)} · ${tr('Saldo pendiente')} : ${money(i.balance/100)}</p>${btn('Ver factura y cobros','payment',i.id,'billing')}</div>`).join('')||tr('Aún no hay facturas vinculadas.')}<div class="gdfTools">${financeAction}</div></div>`:'';
 $('gdfDetail').innerHTML=`<div class="card"><h2>${esc(ref(d))}</h2><p>${esc(customer(d))}</p><p>${esc(d.o?.delivery_address||'')}</p><b>${tr(closed?'Expediente cerrado':p.done?(financial?(f.settled?'Expediente entregado, facturado y pagado':'Entrega completa; seguimiento financiero pendiente'):'Entrega completa con prueba'):'Expediente en curso')}</b><p>${tr('El avance se calcula desde los documentos vinculados. Los controles se validan en cada módulo al ejecutar la acción.')}</p></div><div class="card"><b>${tr('Próxima acción')}</b><p>${tr(next)}</p>${d.o?`<details><summary>${tr('Cantidades por producto')}</summary>${x.lines.map(l=>{const shipped=sum(x.shipLines.filter(s=>s.order_line_id===l.id));const reserved=sum(x.reservations.filter(r=>r.status==='active'&&x.links.some(k=>k.line_id===l.id&&k.reservation_id===r.id)));return `<p><b>${esc(l.product_name)}</b><br>${tr('Pedido / expedido / reservado / faltante')} : ${n(l.quantity)} / ${shipped} / ${reserved} / ${Math.max(0,n(l.quantity)-shipped-reserved)}</p>`}).join('')}</details>`:''}</div><ol class="gdfFlow">${steps.join('')}</ol>${financePanel}<div class="card"><h3>${tr('Expediciones y entregas')}</h3>${x.ships.map(s=>{const t=x.transport.find(t=>t.id===s.tms_delivery_id);return `<div class="gdfDelivery"><b>${esc(s.number)}</b><p>${tr(t?.status||'Estado no disponible')} · ${esc(t?.delivery_date||'—')} ${t&&late(t)?tr('Entrega atrasada'):''}</p><div class="gdfTools">${btn('Ver en TMS','delivery',s.tms_delivery_id,'tms')}${btn('Ver prueba de entrega','proof',s.tms_delivery_id,'sales-orders')}</div></div>`}).join('')||tr('Aún no hay expediciones.')}</div>`;
 $('gdfDetail').querySelectorAll('[data-action]').forEach(b=>b.onclick=async()=>{if(!can(ID))return;try{const id=b.dataset.id;switch(b.dataset.action){case'finance':if(financeAllowed()){await GamaSales.openOrder(id);document.getElementById('gsLinkedInvoices')?.scrollIntoView({block:'start'});}break;case'payment':if(financeAllowed())await GamaOperations.dossier({target:'invoice',target_id:id});break;case'order':if(can('sales-orders'))await GamaSales.openOrder(id);break;case'quote':if(can('quotes')){await GamaQuotes.open();await GamaQuotes.view(id)}break;case'request':if(can('customer-requests'))await window.GamaOpenCustomerRequest(id);break;case'delivery':if(can('tms'))await gamaTMS.openDelivery(id);break;case'proof':if(can('sales-orders'))await GamaFulfillment.proof(id);break}}catch(e){window.gamaToast?.(GamaI18n.t('No se pudo abrir el documento.'))}});
}
window.GamaDossierFlow={open,group,progress,financialProgress};
window.addEventListener('gama:auth-change',()=>{generation++;records=[];selected=null;$(ID)?.replaceChildren()});
})();
