/* Public token-based status: separate from the ERP's authenticated session. */
(function(){'use strict';
const $=id=>document.getElementById(id),token=new URLSearchParams(location.search).get('token');
const endpoint='https://mknsaibrewksgomuslev.supabase.co/rest/v1/rpc/gama_tms_tracking';
const key='sb_publishable_4l0vZw61u5EbLkzmrqrf6Q_phOL1Be9';
const date=v=>v?new Date(/^\d{4}-\d{2}-\d{2}$/.test(v)?v+'T12:00:00':v).toLocaleString(document.documentElement.lang,{dateStyle:'medium',...(!/^\d{4}-\d{2}-\d{2}$/.test(v)?{timeStyle:'short'}:{})}):t('Por confirmar','À confirmer','To be confirmed');
let busy=false;
const t=(es,fr,en)=>({fr,en}[new URLSearchParams(location.search).get('lang')||'es']||es);
document.documentElement.lang=t('es','fr','en');
document.querySelector('h1').textContent=t('Seguimiento de entrega','Suivi de livraison','Delivery tracking');
document.querySelector('.eyebrow').textContent=t('Tu entrega, paso a paso','Votre livraison, étape par étape','Your delivery, step by step');
document.querySelector('.hint').textContent=t('La hora de llegada es una estimación y puede cambiar durante la ruta.','L’heure d’arrivée est une estimation qui peut changer pendant la tournée.','The arrival time is an estimate and may change during the route.');
document.querySelectorAll('dt').forEach((el,i)=>el.textContent=[t('Fecha de entrega','Date de livraison','Delivery date'),t('Llegada estimada','Arrivée estimée','Estimated arrival'),t('Entrega completada','Livraison terminée','Delivery completed')][i]);
$('trackingRefresh').textContent=t('Actualizar seguimiento','Actualiser le suivi','Refresh tracking');
const state=v=>({'Entregada':t('Entregada','Livrée','Delivered'),'Cancelada':t('Cancelada','Annulée','Cancelled'),'En ruta':t('En ruta','En tournée','On route'),'En tránsito':t('En tránsito','En transit','In transit'),'En carga':t('En carga','Chargement','Loading'),'Planificada':t('Planificada','Planifiée','Planned'),'Excepción':t('Incidencia','Incident','Incident'),'Entrega parcial':t('Entrega parcial','Livraison partielle','Partial delivery'),'Lista para envío':t('Lista para envío','Prête à expédier','Ready to ship'),'Pendiente de preparación':t('Pendiente de preparación','En attente de préparation','Awaiting preparation')}[v]||v);
const feedback=$('trackingFeedback');
if(feedback){
 $('feedbackTitle').textContent=t('¿Cómo fue tu entrega?','Comment s’est passée votre livraison ?','How was your delivery?');
 $('feedbackRatingLabel').textContent=t('Tu valoración','Votre note','Your rating');
 $('feedbackCommentLabel').textContent=t('Comentario (opcional)','Commentaire (facultatif)','Comment (optional)');
 $('feedbackSend').textContent=t('Enviar opinión','Envoyer l’avis','Submit feedback');
 feedback.onsubmit=async e=>{e.preventDefault();if(!feedback.reportValidity())return;$('feedbackSend').disabled=true;
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
  try{const r=await fetch(endpoint.replace('gama_tms_tracking','gama_tms_feedback'),{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({p_token:token,p_rating:Number($('feedbackRating').value),p_comment:$('feedbackComment').value}),signal:controller.signal});if(!r.ok)throw Error('FAILED');feedback.hidden=true;$('feedbackMessage').textContent=t('Gracias por tu opinión.','Merci pour votre avis.','Thank you for your feedback.');await refresh()}
  catch(error){$('feedbackMessage').textContent=t('No se pudo guardar. Vuelve a intentarlo.','L’avis n’a pas pu être enregistré. Réessayez.','Feedback could not be saved. Please retry.')}
  finally{clearTimeout(timer);$('feedbackSend').disabled=false}
 };
}
async function refresh(){
 if(busy)return;busy=true;$('trackingRefresh').disabled=true;$('trackingStatus').textContent=t('Consultando entrega…','Consultation de la livraison…','Checking delivery…');
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
 try{
  if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(token||''))throw Error('INVALID_LINK');
  const r=await fetch(endpoint,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({p_token:token}),signal:controller.signal});if(!r.ok)throw Error('UNAVAILABLE');const d=await r.json();if(!d)throw Error('INVALID_LINK');
  $('trackingReference').textContent=d.reference||'';$('trackingState').textContent=state(d.status);$('trackingState').dataset.state=d.status;
  $('trackingDay').textContent=date(d.date);$('trackingEta').textContent=date(d.eta);$('trackingDelivered').textContent=d.delivered_at?date(d.delivered_at):t('Pendiente','En attente','Pending');
  if(feedback){feedback.hidden=!d.feedback_available;if(d.feedback_submitted)$('feedbackMessage').textContent=t('Gracias por tu opinión.','Merci pour votre avis.','Thank you for your feedback.')}
  $('trackingContent').hidden=false;$('trackingStatus').textContent='';
 }catch(e){$('trackingContent').hidden=true;$('trackingStatus').textContent=e.message==='INVALID_LINK'?t('Este enlace ha caducado o no está disponible.','Ce lien a expiré ou n’est pas disponible.','This link has expired or is unavailable.'):t('No se pudo consultar la entrega. Vuelve a intentarlo.','La livraison n’a pas pu être consultée. Réessayez.','Delivery could not be checked. Please retry.')}
 finally{clearTimeout(timer);busy=false;$('trackingRefresh').disabled=false}
}
$('trackingRefresh').onclick=refresh;refresh();
setInterval(()=>{if(!document.hidden&&(!feedback||feedback.hidden))refresh()},30000);
})();
