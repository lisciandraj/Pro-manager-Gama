/* Foreground-only, explicitly enabled GPS. Nothing is collected on page load. */
(function(){'use strict';
const E=window.ArcUI.esc,t=(es,fr,en)=>({fr,en}[window.GamaI18n?.language||window.GamaI18n?.locale?.slice(0,2)]||es);
let tracker=null,epoch=0;
function label(message){const el=document.querySelector('[data-driver-gps-status]');if(el)el.textContent=message}
function stop(message=t('GPS detenido','GPS arrêté','GPS stopped')){if(tracker){navigator.geolocation?.clearWatch(tracker.watch);clearInterval(tracker.timer);tracker=null}epoch++;label(message);const b=document.querySelector('[data-driver-gps]');if(b)b.textContent=t('Compartir GPS','Partager le GPS','Share GPS')}
async function send(){
 const state=tracker;if(!state)return;if(!state.root.isConnected||!state.root.getClientRects().length){stop();return}if(state.busy||!state.point||!navigator.onLine||document.hidden||Date.now()-(state.lastAttempt||0)<29000)return;
 state.busy=true;state.lastAttempt=Date.now();const token=epoch;
 try{
  const point=state.pending||{...state.point,request_key:crypto.randomUUID()};state.pending=point;
  if(Date.now()-Date.parse(point.observed_at)>15*60000){state.pending=null;return}
  await window.ArcData.rpc('gama_tms_pro',{p_action:'position',p_data:{...point,route_id:state.route}});
  if(token!==epoch||tracker!==state)return;state.pending=null;label(t('GPS compartido · ','GPS partagé · ','GPS shared · ')+new Date().toLocaleTimeString());
 }catch(e){if(token!==epoch)return;
  if(/TMS_ACCESS_DENIED|AUTH|JWT|session|ACTION_NOT_ALLOWED/i.test(e?.message||'')){stop(t('GPS detenido: revisa tu sesión y asignación.','GPS arrêté : vérifiez la session et l’affectation.','GPS stopped: check your session and assignment.'));return}
  label(t('GPS pendiente de conexión','GPS en attente de connexion','GPS waiting for connection'));
 }finally{state.busy=false}
}
function mount(root,data){
 const actions=root.querySelector('.tmsDriverActions');if(!actions)return;
 const route=data.routes.find(r=>['En ruta','En tránsito'].includes(r.status));
 if(tracker&&(tracker.actor!==data.actor_id||tracker.route!==route?.id))stop();
 const area=document.createElement('div');area.className='tmsGpsControls';area.innerHTML=`<button type="button" class="arcButton secondary" data-driver-gps${route&&navigator.onLine?'':' disabled'}>${E(tracker?t('Detener GPS','Arrêter le GPS','Stop GPS'):t('Compartir GPS','Partager le GPS','Share GPS'))}</button><p role="status" data-driver-gps-status>${E(t('Comparte tu posición cada 30 s con el despacho mientras esta pantalla está visible. Se detiene al ocultarla.','Partagez votre position toutes les 30 s avec le dispatch lorsque cet écran est visible. Le partage s’arrête quand il est masqué.','Share your position every 30 s with dispatch while this screen is visible. Sharing stops when it is hidden.'))}</p>`;actions.after(area);
 area.querySelector('button').onclick=()=>{
  if(tracker){stop();return}
  if(!navigator.geolocation){label(t('GPS no disponible','GPS indisponible','GPS unavailable'));return}
  if(!route||!navigator.onLine)return;const token=++epoch;
  tracker={root,route:route.id,actor:data.actor_id,watch:null,timer:null,point:null,pending:null,busy:false};
  label(t('Esperando permiso de ubicación…','En attente de l’autorisation de localisation…','Waiting for location permission…'));
  area.querySelector('button').textContent=t('Detener GPS','Arrêter le GPS','Stop GPS');
  tracker.watch=navigator.geolocation.watchPosition(p=>{if(token!==epoch||!tracker)return;tracker.point={lat:p.coords.latitude,lng:p.coords.longitude,accuracy:p.coords.accuracy,observed_at:new Date(p.timestamp).toISOString()};if(!tracker.pending)send()},error=>{if(token===epoch)stop(error.code===1?t('Permiso GPS denegado','Autorisation GPS refusée','GPS permission denied'):t('Posición GPS no disponible','Position GPS indisponible','GPS position unavailable'))},{enableHighAccuracy:true,maximumAge:10000,timeout:20000});
  if(tracker)tracker.timer=setInterval(send,30000);
 };
}
document.addEventListener('visibilitychange',()=>{if(document.hidden)stop()});window.addEventListener('pagehide',()=>stop());
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event!=='TOKEN_REFRESHED')stop()});
window.CocoTmsGps={mount,stop};
})();
