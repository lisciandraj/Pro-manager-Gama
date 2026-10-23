/* On-demand forecast; stock allocation and customer decisions stay server-side. */
(function(){'use strict';
const U=window.ArcUI,E=U.esc,T=s=>window.GamaI18n?.t?.(s)||s;
let epoch=0;const dialogs=new Set();
const error=e=>window.GamaFulfillment?.error(e)||window.CocoSalesDossier.error(e);
const number=n=>Number(n||0).toLocaleString(window.GamaI18n?.getLanguage?.()||'es',{maximumFractionDigits:3});
async function open({order=null,detail=null,lines=[],isCurrent=()=>true}={}){
 const version=epoch;let serial=0;
 const dialog=U.dialog({title:T('Disponibilidad y acuerdos'),saveLabel:T('Volver'),onSave:async()=>{},body:`<p>${E(T('La previsión descuenta los compromisos anteriores. No reserva existencias ni envía mensajes al cliente.'))}</p><div class="cocoSalesTools"><label>${E(T('Preparación · días calendario'))}<input name="preparation_days" type="number" min="0" max="60" step="1" value="0"></label><label>${E(T('Transporte · días calendario'))}<input name="transport_days" type="number" min="0" max="60" step="1" value="0"></label><button type="button" class="arcButton secondary" data-forecast-refresh>${E(T('Actualizar previsión'))}</button></div><div data-forecast-body aria-live="polite"></div><p data-forecast-error role="alert"></p>`});
 dialog.dataset.salesCommitments='';dialogs.add(dialog);dialog.addEventListener('close',()=>dialogs.delete(dialog),{once:true});
 const current=()=>version===epoch&&dialog.open&&isCurrent();
 const host=dialog.querySelector('[data-forecast-body]'),message=dialog.querySelector('[data-forecast-error]');
 async function load(){
  const token=++serial;message.textContent='';host.textContent=T('Cargando…');
  try{
   if(!current())throw Error(T('El documento cambió. Vuelve a abrir la previsión.'));
   const preparation_days=Number(dialog.querySelector('[name=preparation_days]').value),transport_days=Number(dialog.querySelector('[name=transport_days]').value);
   if(!Number.isInteger(preparation_days)||!Number.isInteger(transport_days)||preparation_days<0||preparation_days>60||transport_days<0||transport_days>60)throw Error(T('Revisa los días de preparación y transporte.'));
   const data=await window.CocoSalesDossier.rpc('availability',{...(order?{order_id:order.id}:{lines}),preparation_days,transport_days});
   if(token!==serial||!current())return;
   U.render(host,U.table({columns:[{key:'name',label:T('Producto')},{key:'quantity',label:T('Pendiente'),value:r=>number(r.quantity),numeric:true},{label:T('Reservado para este pedido'),value:r=>number(r.reserved_for_order),numeric:true},{label:T('Compromisos anteriores'),value:r=>number(r.prior_unreserved),numeric:true},{label:T('Disponible desde'),value:r=>r.service?T('Servicio · fecha a coordinar'):r.available_date||T('Sin fecha fiable')},{label:T('Entrega posible desde'),value:r=>r.delivery_date||'—'},{label:T('Fecha acordada'),value:r=>r.promised_date||'—'},{label:T('Acciones'),actions:true,html:r=>detail&&data.confirmed&&Number(r.quantity)>0&&['admin','administrador','commercial','comercial'].includes(window.GamaSales?.role?.()||JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role)?`<button type="button" class="arcButton secondary" data-forecast-propose="${E(r.line_id)}">${E(T('Proponer entrega / sustitución'))}</button>`:''}],items:data.rows}).replace('<table ','<table data-coco-mobile-cards ')+
    data.rows.filter(r=>r.late_incoming>0||r.undated_incoming>0).map(r=>`<p class="gqError">${E(r.name)} · ${E(T('Arribos atrasados o sin fecha excluidos de la promesa'))}: ${number(Number(r.late_incoming||0)+Number(r.undated_incoming||0))}</p>`).join('')+
    `<p>${E(T('Confirma los días de preparación y transporte antes de acordar una fecha. La disponibilidad futura depende de que lleguen las compras previstas.'))}</p>`);
   host.querySelectorAll('[data-forecast-propose]').forEach(button=>button.onclick=()=>{const line=detail.lines.find(l=>l.id===button.dataset.forecastPropose);if(!line||!current())return;dialog.close();window.GamaFulfillment.proposal(detail,line,{preparation_days,transport_days,forecast:data})});
  }catch(e){if(token===serial&&dialog.open){host.replaceChildren();message.textContent=T(error(e))}}
 }
 dialog.querySelector('[data-forecast-refresh]').onclick=load;
 dialog.querySelectorAll('input').forEach(input=>input.oninput=()=>{serial++;host.replaceChildren();message.textContent=T('Actualiza la previsión después de cambiar los plazos.');});
 await load();return dialog;
}
window.CocoSalesCommitments={open};
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;for(const d of dialogs)d.close()});
window.addEventListener('arc:route-change',()=>{for(const d of dialogs)d.close()});
})();
