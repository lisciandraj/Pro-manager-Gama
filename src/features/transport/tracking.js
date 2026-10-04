/* Public token-based status: separate from the ERP's authenticated session. */
(function(){'use strict';
const $=id=>document.getElementById(id),token=new URLSearchParams(location.search).get('token');
const endpoint='https://mknsaibrewksgomuslev.supabase.co/rest/v1/rpc/gama_tms_tracking';
const key='sb_publishable_4l0vZw61u5EbLkzmrqrf6Q_phOL1Be9';
const date=v=>v?new Date(/^\d{4}-\d{2}-\d{2}$/.test(v)?v+'T12:00:00':v).toLocaleString('es-EC',{dateStyle:'medium',...(!/^\d{4}-\d{2}-\d{2}$/.test(v)?{timeStyle:'short'}:{})}):'Por confirmar';
let busy=false;
async function refresh(){
 if(busy)return;busy=true;$('trackingRefresh').disabled=true;$('trackingStatus').textContent='Consultando entrega…';
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
 try{
  if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(token||''))throw Error('INVALID_LINK');
  const r=await fetch(endpoint,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({p_token:token}),signal:controller.signal});if(!r.ok)throw Error('UNAVAILABLE');const d=await r.json();if(!d)throw Error('INVALID_LINK');
  $('trackingReference').textContent=d.reference||'';$('trackingState').textContent=d.status;$('trackingState').dataset.state=d.status;
  $('trackingDay').textContent=date(d.date);$('trackingEta').textContent=date(d.eta);$('trackingDelivered').textContent=d.delivered_at?date(d.delivered_at):'Pendiente';
  $('trackingContent').hidden=false;$('trackingStatus').textContent='';
 }catch(e){$('trackingContent').hidden=true;$('trackingStatus').textContent=e.message==='INVALID_LINK'?'Este enlace ha caducado o no está disponible.':'No se pudo consultar la entrega. Vuelve a intentarlo.'}
 finally{clearTimeout(timer);busy=false;$('trackingRefresh').disabled=false}
}
$('trackingRefresh').onclick=refresh;refresh();
})();
