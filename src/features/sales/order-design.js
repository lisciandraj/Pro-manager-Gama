/* Order presentation is lazy; domain actions and permissions stay in GamaSales. */
(function(){'use strict';
const T=s=>window.GamaI18n?.t?.(s)||s,E=window.ArcUI.esc;
function mount(d,{counts,money,num,sell,balanceFor}){
 const root=document.getElementById('gsMain');if(!root||root.querySelector('.gsOrderWorkspace'))return;
 const o=d.order,card=root.firstElementChild;if(!card?.classList.contains('gsCard'))return;
 const actions=card.querySelector('.gsActions'),history=root.lastElementChild;
 const events=d.events||[],lastPreparation=events.find(e=>['fulfillment_finish','fulfillment_cancel_preparation','preparation_cancelled','fulfillment_start','fulfillment_pick','fulfillment_package','fulfillment_void_package'].includes(e.action)),prepared=lastPreparation?.action==='fulfillment_finish',physical=d.lines.filter(l=>l.product_kind!=='service');
 const shipped=physical.length>0&&physical.every(l=>counts(l).shipped>=Number(l.quantity));
 const reserved=physical.length>0&&physical.every(l=>counts(l).reserved+counts(l).shipped>=Number(l.quantity));
 const invoices=d.invoices.filter(i=>!['cancelled','rejected'].includes(i.fiscal_status));
 const paid=sell&&invoices.length>0&&invoices.every(i=>balanceFor(i)<0.01);
 const states=[
  ['Presupuesto',o.source_quote_id?'done':'skipped',o.source_quote_id?'Documento de origen':'Pedido directo'],
  ['Pedido de venta',o.status==='draft'?'current':o.status==='cancelled'?'skipped':'done',T(label(o.status))],
  ['Reserva',reserved?'done':o.status==='confirmed'?'current':'pending',reserved?'Cantidades reservadas':'Pendiente'],
  ['Preparación',shipped||prepared?'done':reserved?'current':'pending',prepared?'Embalaje validado':'Pendiente'],
  ['Expedición',shipped?'done':d.shipments.length?'current':'pending',shipped?'Expedido':d.shipments.length?'Parcial':'Pendiente'],
  ['Prueba de entrega','pending',d.shipments.length?'Consultar la prueba':'Pendiente'],
  ['Factura',sell?(invoices.length?'done':'pending'):'skipped',sell?(invoices.length?'Vinculada':'Pendiente'):'Acceso restringido'],
  ['Pago',sell?(paid?'done':invoices.length?'current':'pending'):'skipped',sell?(paid?'Pagada':'Pendiente'):'Acceso restringido']
 ];
 const head=document.createElement('div');head.className='gsOrderHead';head.innerHTML=`<h2>${E(T('Pedido de venta'))} ${E(o.number)}</h2><span class="cocoStatus" data-tone="${o.status==='confirmed'?'success':o.status==='cancelled'?'muted':'warning'}">${E(T(label(o.status)))}</span>`;
 const back=actions.querySelector('#gsBack');if(back){back.classList.add('gsOrderBack');head.prepend(back)}
 const more=document.createElement('details');more.className='gsOrderMore';more.innerHTML=`<summary>${E(T('Acciones y detalles operativos'))}</summary>`;
 const workspace=document.createElement('div');workspace.className='gsOrderWorkspace';
 const main=document.createElement('article');main.className='arcPanel gsCard gsOrderMain';
 const subtotal=d.lines.reduce((n,l)=>n+Number(l.quantity)*Number(l.unit_price),0),tax=d.lines.reduce((n,l)=>n+Number(l.quantity)*Number(l.unit_price)*Number(l.tax_rate)/100,0);
 main.innerHTML=`<div class="gsCustomerCard"><b>${E(o.customer_name)}</b><p>${E(o.customer_identification||'—')}</p><p>${E(T('Dirección de entrega'))}: ${E(o.delivery_address||'—')}</p></div><h3>${E(T('Líneas del pedido'))}</h3>${window.ArcUI.table({columns:[{key:'product_name',label:T('Producto'),html:l=>`${E(l.product_name)}<small class="ivSub">${E(l.reference||'—')}</small>`},{key:'quantity',label:T('Cantidad'),value:l=>num(l.quantity),numeric:true},...(sell?[{key:'unit_price',label:T('Precio unitario sin IVA'),value:l=>money(l.unit_price),numeric:true},{key:'total',label:T('Total'),value:l=>money(Number(l.quantity)*Number(l.unit_price)*(1+Number(l.tax_rate)/100)),numeric:true}]:[])],items:d.lines})}${sell?`<dl class="cocoKeyValues gsOrderTotal"><div><dt>${E(T('Subtotal'))}</dt><dd>${E(money(subtotal))}</dd></div><div><dt>${E(T('IVA'))}</dt><dd>${E(money(tax))}</dd></div><div><dt>${E(T('Total'))}</dt><dd><strong>${E(money(subtotal+tax))}</strong></dd></div></dl>`:''}`;
 const aside=document.createElement('aside');aside.className='gsOrderAside';
 const next=document.createElement('article');next.className='gsOrderNext';
 const primary=o.status==='draft'?actions.querySelector('#gsConfirm'):!shipped?actions.querySelector('#gsShip'):root.querySelector('[data-gs-payment]'),nextLabel=primary?.textContent.trim()||T(o.status==='cancelled'?'Pedido cancelado':shipped?'Revisar entrega y facturación':'Revisar el pedido');
 next.innerHTML=`<h3>${E(T('Próxima acción'))}</h3><b>${E(T(nextLabel))}</b><p>${E(T(o.status==='draft'?'Revisa el cliente y las cantidades antes de confirmar.':shipped?'Consulta las expediciones, las pruebas y las facturas vinculadas.':'Comprueba las reservas y los faltantes antes de preparar.'))}</p>`;
 if(primary)next.append(primary);else{const button=document.createElement('button');button.type='button';button.className='arcButton secondary';button.textContent=T('Ver detalles');button.onclick=()=>{more.open=true;more.scrollIntoView({behavior:'smooth',block:'start'})};next.append(button)}
 const milestones=document.createElement('ol');milestones.className='gsMilestones';milestones.setAttribute('aria-label',T('Etapas del pedido'));milestones.innerHTML=states.map(([title,state,help],i)=>`<li data-state="${state}"><span class="gsMilestoneDot" aria-hidden="true">${state==='done'?'✓':i+1}</span><span><strong>${E(T(title))}</strong><small>${E(T(help))}</small></span></li>`).join('');
 aside.append(next);
 if(history&&history!==card){history.classList.add('gsOrderHistory');const paragraphs=[...history.querySelectorAll(':scope>p')];const timeline=document.createElement('ol');timeline.className='gsHistoryList';for(const p of paragraphs){const li=document.createElement('li'),event=events[paragraphs.indexOf(p)],text=p.textContent.split(' · ').slice(1).join(' · ');li.innerHTML=`<time>${E(new Date(event.created_at).toLocaleString(window.GamaI18n?.locale||'fr-FR'))}</time><strong>${E(T(text.split(' · ')[0]))}</strong>${event.detail?.reason?E(event.detail.reason):''}`;timeline.append(li);p.remove()}history.append(timeline);aside.append(history)}
 card.querySelector('.gsSummary')?.remove();card.classList.add('gsOperationalDetail');
 more.append(card);for(const node of [...root.children])if(node!==history&&node!==card)more.append(node);
 workspace.append(main,aside);root.replaceChildren(head,milestones,workspace,more);
 // A secondary copy invokes the same prepared action, with no duplicate ID.
 if(primary){const shortcut=document.createElement('button');shortcut.type='button';shortcut.className='arcButton primary';shortcut.textContent=primary.textContent;shortcut.onclick=()=>primary.click();head.append(shortcut)}
 window.ArcUI.mount(root);
}
const label=s=>({draft:'Borrador',confirmed:'Confirmado',cancelled:'Cancelado'})[s]||s;
window.CocoOrderDesign={mount};
})();
