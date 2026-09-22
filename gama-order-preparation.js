/* Preparación: pestaña del módulo Entrega. Cantidades previstas, escaneo y bulto «Lista para expedir». */
(function(){'use strict';
const S=()=>window.GamaSales,esc=window.ArcUI.esc;
const T=s=>window.GamaI18n?.t?.(s)||s,tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const STATES={queued:'Por preparar',picking:'En preparación',packed:'Lista para expedir'};
let page=0,generation=0,host=null,pendingId=null;
// La preparación vive dentro de Entrega (TMS): un solo permiso para toda la cadena.
const allowed=()=>window.gamaAccessAllowed?.('tms');
const alive=token=>token===generation&&!!host?.isConnected;
async function list(token){
 const orders=await S().rows('sales_orders',{eq:{status:'confirmed'},order:'created_at',ascending:false,range:[page*20,page*20+20]}),more=orders.length>20;orders.splice(20);
 const preps=orders.length?await S().rows('fulfillment_preparations',{in:{order_id:orders.map(o=>o.id)}}):[];
 if(!alive(token))return;
 const state=o=>preps.find(p=>p.order_id===o.id&&STATES[p.status])?.status||'queued';
 window.ArcUI.render(host,`<div class="arcPanel gsCard"><h3>${tr('Pedidos por preparar')}</h3><p class="gsHint">${tr('Abre un pedido y escanea sus productos: las cantidades ya están previstas y, con el último, el bulto queda «Lista para expedir».')}</p>`
  +(orders.map(o=>`<div class="gfItem" data-prep-state="${esc(state(o))}"><div class="gfRow"><b>${esc(o.number)} · ${esc(o.customer_name)}</b><span class="tmsBadge">${tr(STATES[state(o)])}</span></div><p>${esc(o.delivery_address)}</p><button class="arcButton primary" data-prep-order="${esc(o.id)}" data-gi-live data-gi=e5f4e7cc21f2>Abrir preparación</button></div>`).join('')||`<p class="gsHint">${tr('No hay pedidos confirmados por preparar.')}</p>`)
  +`<div class="gsActions"><button class="arcButton secondary" id="gpPrev" ${page?'':'disabled'} data-gi-live data-gi=e4ce7c09d51e>Anterior</button><span>${page+1}</span><button class="arcButton secondary" id="gpNext" ${more?'':'disabled'} data-gi-live data-gi=49683b71c6ac>Siguiente</button></div></div>`);
 host.querySelectorAll('[data-prep-order]').forEach(b=>b.onclick=()=>show(b.dataset.prepOrder));
 host.querySelector('#gpPrev').onclick=()=>{page--;show()};host.querySelector('#gpNext').onclick=()=>{page++;show()};
}
async function detail(id,token){
 const [orders,lines,shipments,reservations,locations]=await Promise.all([S().rows('sales_orders',{eq:{id}}),S().rows('sales_order_lines',{eq:{order_id:id}}),S().rows('sales_deliveries',{eq:{order_id:id}}),S().rows('stock_reservations',{eq:{reference_type:'sales_order',reference_id:id}}),S().refs('warehouse_locations','id,code,name,warehouse_id,active')]);if(!orders[0])throw Error('ORDER_NOT_FOUND');
 const [links,shipLines]=await Promise.all([lines.length?S().rows('sales_reservation_links',{in:{line_id:lines.map(x=>x.id)}}):[],shipments.length?S().rows('sales_delivery_lines',{in:{delivery_id:shipments.map(x=>x.id)}}):[]]);if(!alive(token))return;
 const d={order:orders[0],lines,shipments,reservations,locations,links,shipLines,invoices:[],invoiceLines:[],payments:[],preparationOnly:true,onDone:()=>show(id)};
 window.ArcUI.render(host,`<div class="gsTools"><button class="arcButton secondary" id="gpList" data-gi-live data-gi=046da3ced22e>Lista de pedidos</button></div><div class="arcPanel gsCard"><h3>${esc(d.order.number)} · ${esc(d.order.customer_name)}</h3><p>${esc(d.order.delivery_address)}</p></div><div id="gpPreparation"></div><div id="gpTransferred"></div>`);
 host.querySelector('#gpList').onclick=()=>show();
 await window.GamaFulfillment.mount(d,host.querySelector('#gpPreparation'));
 for(const s of shipments){if(!alive(token))return;const box=document.createElement('div');box.className='gsCard';host.querySelector('#gpTransferred').append(box);await window.GamaFulfillment.parcelPanel(s.id,box,()=>show(id),!!s.departed_at)}
}
async function show(id=null){
 if(!host)return;const token=++generation;host.textContent=T('Cargando…');
 try{await window.GamaCloudReady;if(id)await detail(id,token);else await list(token)}
 catch(e){if(alive(token))host.textContent=S().error(e)}
}
function mount(el){S().styles?.();host=el;const id=pendingId;pendingId=null;return show(id)}
async function open(id=null){if(!allowed())return;pendingId=id;await window.gamaTMS?.open('preparation')}
window.GamaPreparation={open,mount};
})();
