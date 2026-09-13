/* Read-only customer journey. Existing actions/RLS remain authoritative. */
(function(){
'use strict';
const ID='dossier-flow', $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const can=id=>!!window.gamaAccessAllowed?.(id);
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
const ref=d=>d.o?.number||d.q?.invoice_number||String(d.r?.id||d.q?.id||'').slice(0,8).toUpperCase();
const customer=d=>d.o?.customer_name||d.q?.quote_details?.client||d.r?.requester_name||'—';
function shell(){
 if(!$('gdfStyle')){const s=document.createElement('style');s.id='gdfStyle';s.textContent=`#dossier-flow{display:none}#dossier-flow.active{display:block}.gdfTools{display:flex;flex-wrap:wrap;gap:10px;margin:15px 0}.gdfTools input{flex:1;min-width:180px}.gdfLayout{display:grid;grid-template-columns:minmax(220px,300px) minmax(0,1fr);gap:18px}.gdfList{max-height:75vh;overflow:auto}.gdfRecord{display:block;width:100%;text-align:left;margin-bottom:8px;padding:14px;border:1px solid #d4e2e6;background:white;color:#18324a;border-radius:12px;overflow-wrap:anywhere}.gdfRecord[aria-pressed=true]{border:2px solid #087c8b;background:#eef8f8}.gdfRecord small{display:block;margin-top:5px}.gdfFlow{list-style:none;padding:0;margin:0}.gdfStep{position:relative;background:#fff;border:1px solid #d9e4e8;border-left:5px solid #9aaab3;border-radius:12px;margin:0 0 28px;padding:18px;overflow-wrap:anywhere}.gdfStep:not(:last-child):after{content:'↓';position:absolute;bottom:-27px;left:22px;color:#087c8b;font-size:24px}.gdfStep.done{border-left-color:#168263}.gdfStep.blocked{border-left-color:#c14a37}.gdfStep.active{border-left-color:#db8a23}.gdfStep h3{margin:0 0 8px}.gdfBadge{display:inline-block;background:#eef3f4;padding:4px 9px;border-radius:20px;font-size:13px}.gdfStep ul{padding-left:20px}.gdfStep li{margin:7px 0}.gdfStats{display:flex;flex-wrap:wrap;gap:16px;margin:15px 0}.gdfError{color:#a93628}.gdfDelivery{border-top:1px solid #d9e4e8;padding:12px 0}@media(max-width:760px){.gdfLayout{grid-template-columns:1fr}.gdfList{max-height:240px}}`;document.head.appendChild(s)}
 let s=$(ID);if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 s.innerHTML=GamaUI.header({title:'Seguimiento de expedientes',lead:'De la solicitud del cliente a la entrega: avance, necesidades y requisitos.'})+`<div class="gdfTools"><input id="gdfSearch" data-gi-aria-label=320b429c7b40 aria-label="Buscar expediente" data-gi-placeholder=320b429c7b40 placeholder="Buscar expediente" data-gi-live><button class="secondary" id="gdfRefresh">${tr('Actualizar')}</button></div><div class="gdfLayout"><div id="gdfList" class="gdfList"></div><div id="gdfDetail" aria-live="polite"></div></div>`;
 GamaUI.bindBack(s);window.showTab?.(ID);$('gdfSearch').oninput=renderList;$('gdfRefresh').onclick=()=>open(selected);
}
function renderList(){
 const q=$('gdfSearch').value.trim().toLocaleLowerCase();const a=records.filter(d=>[ref(d),customer(d),d.q?.invoice_number,d.r?.id].some(v=>String(v||'').toLocaleLowerCase().includes(q)));
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
 try{let data={lines:[],ships:[],shipLines:[],reservations:[],links:[],preps:[],picks:[],packages:[],packageLines:[],transport:[],proofs:[]};
 if(d.o){const id=d.o.id;[data.lines,data.ships,data.reservations,data.preps]=await Promise.all([all('sales_order_lines',{eq:{order_id:id}}),all('sales_deliveries',{eq:{order_id:id}}),all('stock_reservations',{eq:{reference_type:'sales_order',reference_id:id}}),all('fulfillment_preparations',{eq:{order_id:id}})]);
 const ids=(a,k='id')=>a.map(x=>x[k]).filter(Boolean);const by=async(table,field,a,select='*')=>{const result=[];for(let i=0;i<a.length;i+=100)result.push(...await all(table,{select,in:{[field]:a.slice(i,i+100)}}));return result};
 [data.links,data.shipLines,data.picks,data.packages,data.transport,data.proofs]=await Promise.all([by('sales_reservation_links','line_id',ids(data.lines)),by('sales_delivery_lines','delivery_id',ids(data.ships)),by('fulfillment_pick_lines','preparation_id',ids(data.preps)),by('fulfillment_packages','preparation_id',ids(data.preps)),by('tms_deliveries','id',ids(data.ships,'tms_delivery_id')),by('tms_proofs','delivery_id',ids(data.ships,'tms_delivery_id'),'delivery_id,captured_at,signature')]);
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
function renderDetail(d,x){
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const late=t=>t.delivery_date&&t.delivery_date<today&&!['Entregada','Cancelada'].includes(t.status);
 const p=progress(d,x),closed=d.o?.status==='cancelled'||(!d.o&&['cancelled','rejected'].includes(d.q?.quote_state||d.r?.status));
 const states={done:'Completado',active:'En curso',blocked:'Bloqueado',pending:'Pendiente',skip:'Sin etapa previa registrada',closed:'Cerrado'};
 const btn=(label,kind,id,module)=>can(module)?`<button class="secondary" data-action="${kind}" data-id="${esc(id)}">${tr(label)}</button>`:'';
 const orderAction=d.o?btn('Abrir pedido y resolver requisitos','order',d.o.id,'sales-orders'):'';
 const step=(title,state,requirements,info='',action='')=>`<li class="gdfStep ${closed?'closed':state}"><h3>${tr(title)}</h3><span class="gdfBadge">${tr(closed?'Cerrado':states[state])}</span>${info?'<p>'+info+'</p>':''}<b>${tr('Requisitos para avanzar')}</b><ul>${requirements.map(s=>'<li>'+tr(s)+'</li>').join('')}</ul><div class="gdfTools">${action}</div></li>`;
 const pending=d.o?.status==='confirmed';
 const next=closed?'Expediente cerrado':p.done?'Entrega completa con prueba':!d.o?(d.q?'Enviar o validar el presupuesto.':'Revisar la solicitud y crear el presupuesto o pedido.'):!pending?'Confirmar el pedido.':p.missing>0?'Resolver faltantes y acordar las entregas parciales.':!p.complete?'Completar preparación y expedición.':x.ships.some(s=>!s.departed_at)?'Completar carga y confirmar salida.':'Completar las entregas y registrar las pruebas firmadas.';
 const steps=[
 step('1. Solicitud del cliente',d.r?'done':d.o?.source_request_id?'done':'skip',['Identificar al cliente, los productos y las cantidades solicitadas.'],d.r?esc(d.r.id):tr('Puede iniciarse directamente con un presupuesto o un pedido.'),d.r?btn('Ver solicitud','request',d.r.id,'customer-requests'):''),
 step('2. Presupuesto',d.q?(d.q.quote_state==='draft'?'active':'done'):d.o?.source_quote_id?'done':d.o?'skip':'pending',['Completar emisor, cliente, dirección, productos, precios y vigencia.','Enviar el presupuesto al cliente para su validación.'],esc(d.q?.invoice_number||d.o?.source_quote_id||''),d.q?btn('Ver presupuesto','quote',d.q.id,'quotes'):''),
 step('3. Validación y pedido',pending?'done':d.q?.quote_state==='sent'?'active':'pending',['Registrar la aceptación del cliente o confirmar el pedido directo.','Para una aceptación externa, indicar el medio y la referencia del acuerdo.'],d.q?.quote_state==='sent'&&d.q.quote_valid_until&&d.q.quote_valid_until<new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())?tr('Presupuesto vencido: revisar la vigencia antes de aceptar.'):esc(d.o?.number||''),orderAction|| (d.q?btn('Registrar validación','quote',d.q.id,'quotes'):'')),
 step('4. Stock y reservas',!pending?'pending':p.missing>0?'blocked':p.ordered?'done':'blocked',['Reservar existencias para las cantidades pendientes.','Reponer faltantes o registrar un acuerdo de entrega parcial con el cliente.'],`${tr('Cantidad sin reservar')} : ${p.missing}`,orderAction),
 step('5. Preparación y embalaje',p.complete?'done':p.active.length?'active':'pending',['Recoger y escanear los productos del lote reservado.','Embalar todas las cantidades recogidas en bultos con peso y dimensiones.','Una expedición parcial necesita el motivo y respetar el acuerdo del cliente.'],`${tr('Lote activo: previsto / recogido / embalado')} : ${p.planned} / ${p.picked} / ${p.packed}`,orderAction),
 step('6. Expedición y salida',p.complete&&x.ships.every(s=>s.departed_at)?'done':x.ships.length?'active':'pending',['Crear la expedición con los bultos completos.','Escanear todas las cantidades de carga y asignar conductor y vehículo antes de confirmar la salida.'],`${tr('Expedido / pedido')} : ${p.shipped} / ${p.ordered}`,orderAction),
 step('7. Transporte al cliente',p.delivered>=p.ordered&&p.ordered?'done':x.transport.some(t=>t.status==='Excepción'||t.status==='Cancelada'||late(t))?'blocked':x.ships.some(s=>s.departed_at)?'active':'pending',['Planificar la ruta, la dirección y la fecha de entrega.','Resolver retrasos o incidencias de cada expedición.'],tr('Cada expedición se sigue por separado en la lista inferior.')),
 step('8. Entrega y prueba',p.done?'done':p.delivered>0?'active':'pending',['Registrar la recepción y la firma del cliente en la prueba de entrega.','Completar todas las cantidades del pedido; una entrega parcial no cierra el expediente.'],`${tr('Entregado / con prueba firmada / pedido')} : ${p.delivered} / ${p.proved} / ${p.ordered}`)
 ];
 $('gdfDetail').innerHTML=`<div class="card"><h2>${esc(ref(d))}</h2><p>${esc(customer(d))}</p><p>${esc(d.o?.delivery_address||'')}</p><b>${tr(closed?'Expediente cerrado':p.done?'Entrega completa con prueba':'Expediente en curso')}</b><p>${tr('El avance se calcula desde los documentos vinculados. Los controles se validan en cada módulo al ejecutar la acción.')}</p></div><div class="card"><b>${tr('Próxima acción')}</b><p>${tr(next)}</p>${d.o?`<details><summary>${tr('Cantidades por producto')}</summary>${x.lines.map(l=>{const shipped=sum(x.shipLines.filter(s=>s.order_line_id===l.id));const reserved=sum(x.reservations.filter(r=>r.status==='active'&&x.links.some(k=>k.line_id===l.id&&k.reservation_id===r.id)));return `<p><b>${esc(l.product_name)}</b><br>${tr('Pedido / expedido / reservado / faltante')} : ${n(l.quantity)} / ${shipped} / ${reserved} / ${Math.max(0,n(l.quantity)-shipped-reserved)}</p>`}).join('')}</details>`:''}</div><ol class="gdfFlow">${steps.join('')}</ol><div class="card"><h3>${tr('Expediciones y entregas')}</h3>${x.ships.map(s=>{const t=x.transport.find(t=>t.id===s.tms_delivery_id);return `<div class="gdfDelivery"><b>${esc(s.number)}</b><p>${tr(t?.status||'Estado no disponible')} · ${esc(t?.delivery_date||'—')} ${t&&late(t)?tr('Entrega atrasada'):''}</p><div class="gdfTools">${btn('Ver en TMS','delivery',s.tms_delivery_id,'tms')}${btn('Ver prueba de entrega','proof',s.tms_delivery_id,'sales-orders')}</div></div>`}).join('')||tr('Aún no hay expediciones.')}</div>`;
 $('gdfDetail').querySelectorAll('[data-action]').forEach(b=>b.onclick=async()=>{if(!can(ID))return;try{const id=b.dataset.id;switch(b.dataset.action){case'order':if(can('sales-orders'))await GamaSales.openOrder(id);break;case'quote':if(can('quotes')){await GamaQuotes.open();await GamaQuotes.view(id)}break;case'request':if(can('customer-requests'))await window.GamaOpenCustomerRequest(id);break;case'delivery':if(can('tms'))await gamaTMS.openDelivery(id);break;case'proof':if(can('sales-orders'))await GamaFulfillment.proof(id);break}}catch(e){window.gamaToast?.(GamaI18n.t('No se pudo abrir el documento.'))}});
}
window.GamaDossierFlow={open,group,progress};
window.addEventListener('gama:auth-change',()=>{generation++;records=[];selected=null;$(ID)?.replaceChildren()});
})();
