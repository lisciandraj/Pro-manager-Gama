/* GAMA TMS V4 — gestión de transporte: flujo diario, pantalla del conductor y pruebas de entrega.
   Los datos viven en Supabase (tms_*), no en el navegador: una prueba de entrega
   es un documento probatorio y debe sobrevivir a un borrado de caché. */
(function(){
'use strict';
const LOCAL_KEY='gama-tms-v1', MIGRATED_KEY='gama_tms_migrated_v1';
const ARCHIVE_LIMIT=50, PHOTO_MAX_PX=1280, PHOTO_QUALITY=0.72;
const C=()=>window.GamaCloud;
const readLocal=(k,f)=>{try{return JSON.parse(localStorage.getItem(k)||JSON.stringify(f))}catch(e){return f}};
const esc=window.ArcUI.esc;
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:window.GamaCompany?.get?.()?.timezone||'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),now=()=>new Date().toISOString();
let planningDate=today();const day=()=>planningDate;
const T=v=>window.GamaI18n?.t?.(v)||v;
let db={deliveries:[],drivers:[],routes:[],archive:[],proofIndex:[],proofDocuments:{},counts:{},settings:{},employees:[],absences:[],customers:[]};
let fetchedAt=0,auxAt=0,auxDay='',auxPending=null;
let proofViewVersion=0;const gpsRequests=new Map();
function proofGps(id){if(!gpsRequests.has(id))gpsRequests.set(id,new Promise(resolve=>{if(!navigator.geolocation)return resolve({status:'unavailable'});navigator.geolocation.getCurrentPosition(p=>resolve({status:'captured',lat:p.coords.latitude,lng:p.coords.longitude,accuracy:p.coords.accuracy,at:new Date(p.timestamp).toISOString()}),e=>resolve({status:e.code===1?'denied':e.code===3?'timeout':'unavailable'}),{enableHighAccuracy:true,timeout:6000,maximumAge:0})}));return gpsRequests.get(id)}
let followDeliveryId=null;
let proofArchiveId=null,proofCache={},loaded=false,currentTab='today',selectedStage='planning',driverView=null,moveBusy=false,proofMetadataReady=false;
/* ---- mapeo cloud → forma interna (se conserva la del V3 para no tocar la UI) ---- */
/* Un recurso de reparto es un conductor de Flota con el vehículo que Flota le
   tiene asignado hoy. El TMS ya no guarda ni personas ni vehículos: los lee por
   gama_tms_resources, que devuelve sólo lo necesario para repartir. */
const drvFrom=r=>({id:r.driver_id,name:r.name,phone:r.phone||'',vehicle:r.plate||'',
 vehicleId:r.vehicle_id||null,vehicleStatus:r.vehicle_status||null,
 maxWeight:Number(r.max_weight||0),maxVolume:Number(r.max_volume||0),
 enabled:r.available===true,absent:r.absent===true,employeeId:r.employee_id||null});
const delFrom=r=>({id:r.id,reference:r.dossier_reference||r.erp_reference||'',customer:r.customer,address:r.address,customerId:r.customer_id||null,phone:r.phone||'',date:r.delivery_date,timeWindow:r.time_window||'',priority:r.priority||'Normal',weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Pendiente de preparación',lat:r.lat,lng:r.lng,routeId:r.route_id,driverId:r.driver_id,actualArrival:r.actual_arrival,etaAt:r.eta_at,etaBasis:r.eta_basis,deliveredAt:r.delivered_at,notes:r.notes||'',execution:r.execution||null,version:r.version||1});
const rtFrom=r=>({id:r.id,reference:r.erp_reference||'',date:r.route_date,driverId:r.driver_id,driver:r.driver_name||'',vehicle:r.vehicle||'',vehicleId:r.vehicle_id||null,stops:Array.isArray(r.stops)?r.stops:[],routePoints:r.route_points||{},distance:Number(r.distance||0),distanceBasis:r.distance_basis||'air',weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Planificada',createdAt:r.created_at,version:r.version||1,costPerKm:r.cost_per_km??null,manual:r.manual_override===true});
const notify=(message,type)=>window.gamaToast?.(T(message),type?{tipo:type}:undefined);
const tmsError=e=>({ROUTE_STALE:'La ruta cambió. Actualiza y vuelve a intentarlo.',ROUTE_CLOSED:'La ruta ya está en carga o ha salido.',ROUTE_CAPACITY:'La carga supera la capacidad del vehículo.',GPS_INVALID:'Coordenadas inválidas.',TMS_ACCESS_DENIED:'Tu perfil no puede realizar esta operación.'}[String(e?.message||e)]||window.GamaLoading?.error(e)||e?.message||String(e));

function fail(e,what){const m=e&&(e.message||e.error_description||e.details)||'Error desconocido';console.warn('[GAMA TMS]',what,e);notify(what+' : '+(window.GamaLoading?.error(e)||m));}
function findDelivery(id){return driverView?.deliveries?.find(d=>d.id===id)||db.deliveries.find(d=>d.id===id)||db.archive.find(d=>d.id===id)||null}

/* ---- enlace con RRHH ----
   Un conductor puede estar enlazado a la ficha de un empleado. Cuando ese
   empleado tiene una ausencia aprobada que cubre el día, el conductor no sale
   de ruta: el reparto no cuenta con él y la ficha lo avisa.
   Sólo cuentan las ausencias APROBADAS. Una solicitud pendiente todavía no
   está concedida y no puede dejar sin conductor a las entregas del día. */
const ABS_ETIQUETA={vacaciones:'Vacaciones',enfermedad:'Baja por enfermedad',permiso:'Permiso',formacion:'Formación',otro:'Ausencia'};
const absLabel=a=>ABS_ETIQUETA[a&&a.kind]||'Ausencia';
function empName(id){const e=db.employees.find(x=>x.id===id);return e?(e.full_name||''):''}
/* El servidor ya dice si el conductor está ausente hoy —es quien ve RRHH—;
   esta función sólo sirve para poner nombre a la ausencia cuando el módulo ha
   podido cargar las ausencias del equipo. */
function driverAbsence(d,date){
 if(!d||!d.employeeId)return null;
 const day=date||today();
 return db.absences.find(a=>a.employee_id===d.employeeId&&a.status==='aprobada'&&String(a.start_date)<=day&&String(a.end_date)>=day)||null;
}

/* ---- carga ---- */
async function fetchAll(){
 const sessionVersion=authEpoch;
 const api=C();if(!api)return;
 const t=day();
 const [drv,rt,del,st,pending,counts]=await Promise.all([
  (async()=>{const r=await window.ArcData.rawRpc('gama_tms_resources',{p_day:t},{read:true});return r.error?{data:[],error:r.error}:{data:r.data||[]}})(),
  api.list('tms_routes',{eq:{route_date:t},order:'created_at',ascending:true,limit:500}),
  api.list('tms_deliveries',{eq:{delivery_date:t},order:'created_at',ascending:true,limit:1000}),
  api.list('tms_settings',{limit:1}),
  Promise.resolve([]),
  window.ArcData.rawRpc('gama_tms_today_counts',{p_day:t},{read:true}),
 ]);
 if(sessionVersion!==authEpoch||t!==day())throw Error('Session or day changed');
 for(const result of [rt,del,st])if(result.error)throw result.error;
 db.drivers=(drv.data||[]).map(drvFrom);
 db.driversError=drv.error?String(drv.error.message||drv.error):null;
 db.routes=(rt.data||[]).map(rtFrom);
 const routeIds=[...new Set(pending.filter(d=>d.delivery_date===t&&d.route_id&&!db.routes.some(r=>r.id===d.route_id)).map(d=>d.route_id))];if(routeIds.length){const extra=await api.list('tms_routes',{in:{id:routeIds}});if(extra.error)throw extra.error;db.routes.push(...(extra.data||[]).map(rtFrom))}
 const related=db.routes.length?await api.list('tms_deliveries',{in:{route_id:db.routes.map(r=>r.id)},limit:1000}):{data:[]};if(related.error)throw related.error;if(sessionVersion!==authEpoch||t!==day())throw Error('Session or day changed');
 db.deliveries=[...new Map([...(del.data||[]),...(related.data||[]),...pending].map(d=>[d.id,d])).values()].map(delFrom);
 db.counts=counts.data||{};proofMetadataReady=false;
 const s=(st.data||[])[0]||{};
 db.settings={depot:s.depot||'',returnDepot:s.return_depot!==false,depotPoint:(s.depot_lat!=null&&s.depot_lng!=null)?{id:'__depot',isDepot:true,address:s.depot||'Depósito',lat:s.depot_lat,lng:s.depot_lng}:null};
 fetchedAt=Date.now();
}
async function fetchAux(){
 if(auxPending)return auxPending;
 const epoch=authEpoch,t=day();if(auxDay===t&&Date.now()-auxAt<60000)return;
 const pending=Promise.all([fetchHr(C(),t),fetchCustomers(C())]).then(()=>{if(epoch===authEpoch){auxAt=Date.now();auxDay=t}}).finally(()=>{if(auxPending===pending)auxPending=null});
 auxPending=pending;return pending;
}

/* Los clientes van aparte y sin propagar el error, igual que RRHH: si el rol
   no puede leerlos el desplegable se queda vacío y el transporte sigue
   funcionando con los campos escritos a mano. */
async function fetchCustomers(api){
 const epoch=authEpoch;try{
  const r=await api.list('customers',{select:'id,name,address,email,phone,lat,lng,gps_address,active',order:'name',ascending:true});
  if(epoch!==authEpoch)return;db.customers=r.error?[]:(r.data||[]).filter(c=>c.active!==false);
 }catch(e){if(epoch===authEpoch)db.customers=[]}
}
/* Fichas de empleado y ausencias que todavía no han terminado (las pasadas ya
   no afectan a ninguna ruta). Va aparte y sin propagar el error: si el rol no
   puede leer RRHH la lista vuelve vacía y el transporte sigue funcionando como
   antes, sin bloquear a nadie. */
async function fetchHr(api,t){
 const epoch=authEpoch;try{
  const [emp,abs]=await Promise.all([
   api.list('hr_employees',{order:'full_name',ascending:true}),
   api.list('hr_absences',{gte:{end_date:t},order:'start_date',ascending:true}),
  ]);
  if(epoch!==authEpoch)return;db.employees=emp.error?[]:(emp.data||[]);
  db.absences=abs.error?[]:(abs.data||[]);
 }catch(e){console.warn('[GAMA TMS] RRHH no disponible',e);if(epoch===authEpoch){db.employees=[];db.absences=[]}}
}
async function ensureProof(id){
 if(!id||proofCache[id]!==undefined)return proofCache[id];
 const epoch=authEpoch,r=await C().list('tms_proofs',{eq:{delivery_id:id},limit:1});
 if(r.error)throw r.error;if(epoch!==authEpoch)throw Error('Session changed');
 proofCache[id]=(r.data||[])[0]||null;
 return proofCache[id];
}

/* ---- migración única desde localStorage ---- */
async function migrateLocalOnce(){if(localStorage.getItem(MIGRATED_KEY))return;const old=readLocal(LOCAL_KEY,null);localStorage.setItem(MIGRATED_KEY,'1');if(old?.deliveries?.length)notify(tr('preserved'))}
async function ready(){
 if(loaded&&Date.now()-fetchedAt<30000)return true;
 if(!C()){notify('El módulo de transporte necesita la conexión con la nube. Recarga la aplicación.');return false}
 try{
  await migrateLocalOnce();
  await fetchAll();
  loaded=true;return true;
 }catch(e){fail(e,'No se pudieron cargar los datos de transporte');return false}
}
async function reload(tab){if(driverView)return open('driver');try{await fetchAll();if(selectedStage==='proof')await proofMetadata()}catch(e){fail(e,'No se pudo actualizar')}render('today')}
async function log(delivery,type,note){
 try{await C().insert('tms_events',{delivery_id:delivery.id,at:now(),type,note:note||null,customer:delivery.customer||null})}
 catch(e){console.warn('[GAMA TMS] evento no registrado',e)}
}

function styles(){ /* Styles are compiled in architect-components.css. */ }
function section(){let x=document.getElementById('gama-tms-section');if(x)return x;x=document.createElement('section');x.id='gama-tms-section';x.style.display='none';(document.querySelector('.wrap')||document.body).appendChild(x);return x}
function showSection(){const x=section();window.ArcRouter.show('gama-tms-section');return x}

async function open(tab){
 if(['history','tracking'].includes(tab)&&window.gamaAccessAllowed?.('audit'))return window.ArchitectAudit.open('transfer');
 stopLiveMap();
 const started=performance.now(),epoch=++planningEpoch;++proofViewVersion;styles();const x=showSection();
 window.ArcUI.render(x,'<div class="tms"><div class="tmsEmpty" role="status">'+esc(T('Cargando datos de transporte…'))+'</div></div>');
 if(!tab||tab==='driver'||(driverView&&tab==='proof')||!navigator.onLine){
  try{const r={data:await window.ArchitectOfflineProofs.bundle()};if(epoch!==planningEpoch)return;
   if(r.data?.scope==='driver'||tab==='driver'||!navigator.onLine||r.data?.driver&&window.matchMedia('(max-width: 767px)').matches){driverView={...r.data,routes:(r.data?.routes||[]).map(rtFrom),deliveries:(r.data?.deliveries||[]).map(delFrom)};currentTab='driver';renderDriver();window.ArchitectPerformance?.contentReady('tms',started);return}
  }catch(e){if(tab==='driver'){fail(e,'No se pudo cargar la ruta');return}}
 }
 driverView=null;currentTab='today';selectedStage=['preparation','planning','loading','proof'].includes(tab)?tab:'planning';
 GamaPage.reset('tmsProofs');
 if(!await ready()||epoch!==planningEpoch)return;
 if(selectedStage==='proof')await proofMetadata();
 render('today');window.ArchitectPerformance?.contentReady('tms',started);
 await fetchAux();if(epoch!==planningEpoch)return;
 if(selectedStage==='planning')await autoPlanning();
}
function defaultProofId(){return archiveList().some(d=>d.id===proofArchiveId)?proofArchiveId:''}
function archiveList(){return db.archive.filter(d=>d.status==='Entregada').sort((a,b)=>String(b.deliveredAt||b.date).localeCompare(String(a.deliveredAt||a.date)))}
async function proofMetadata(){
 if(proofMetadataReady)return;const epoch=authEpoch;
 const pf=await C().list('tms_proofs',{select:'delivery_id,captured_at,erp_reference',order:'captured_at',ascending:false,limit:ARCHIVE_LIMIT});if(pf.error)throw pf.error;
 const ids=(pf.data||[]).map(p=>p.delivery_id),docs={};
 const archive=ids.length?await C().list('tms_deliveries',{in:{id:ids},order:'delivered_at',ascending:false}):{data:[]};if(archive.error)throw archive.error;if(epoch!==authEpoch)return;db.proofIndex=pf.data||[];db.archive=(archive.data||[]).map(delFrom);
 if(ids.length)try{const r=await C().list('business_documents',{select:'source_id,erp_reference,supplier_id',eq:{source_table:'tms_proofs'},in:{source_id:ids}});if(r.error)throw r.error;
  const supplierIds=[...new Set((r.data||[]).map(d=>d.supplier_id).filter(Boolean))];let suppliers=[];
  if(supplierIds.length){const sr=await C().list('suppliers',{select:'id,name',in:{id:supplierIds}});if(!sr.error)suppliers=sr.data||[]}
  for(const d of r.data||[])docs[d.source_id]={reference:d.erp_reference,partner:suppliers.find(s=>s.id===d.supplier_id)?.name||''};
 }catch(e){console.warn('[TMS] proof references',e)}
 if(epoch===authEpoch){db.proofDocuments=docs;proofMetadataReady=true}
}
const proofReference=d=>db.proofDocuments[d.id]?.reference||db.proofIndex.find(p=>p.delivery_id===d.id)?.erp_reference||d.reference||'—';
const proofPartner=d=>db.proofDocuments[d.id]?.partner||d.customer||'';
const color=d=>status(d)==='Excepción'?'incident':status(d)==='Entregada'?'delivered':['En tránsito','En ruta','En carga'].includes(status(d))?'transit':['Planificada','Lista para envío'].includes(status(d))?'planned':'pending';
const badge=d=>`<span class="tmsBadge tmsStatus-${color(d)}">${esc(T(status(d)))}</span>`;
function routeStops(r){return(r.stops||[]).map((id,i)=>{if(id!=='__depot')return db.deliveries.find(d=>d.id===id);const key=i===0?'start':'end',point=r.routePoints?.[key],legacy=!Object.hasOwn(r.routePoints||{},'start');return {customer:point?.label||T('Depósito'),address:point?.label||db.settings?.depot||T('Depósito'),isDepot:true,...(legacy?db.settings.depotPoint||{}:point||{}),id:legacy?'__depot':r.id+':'+(key==='end'&&point?.lat===r.routePoints.start?.lat&&point?.lng===r.routePoints.start?.lng?'start':key)}}).filter(Boolean)}
function status(d){return d.status||'Pendiente de preparación'}
/* Daily planning is one atomic, idempotent server operation. */
const WORDS={
 auto:['Planification automatique','Planificación automática','Automatic planning'],orders:['Les livraisons proviennent exclusivement des commandes.','Las entregas proceden exclusivamente de pedidos.','Deliveries come exclusively from orders.'],
 map:['Carte des livraisons du jour','Mapa de entregas del día','Today’s delivery map'],all:['Toutes les tournées','Todas las rutas','All routes'],refresh:['Actualiser','Actualizar','Refresh'],working:['Planification en cours…','Planificando…','Planning…'],
 missing:['Coordonnées manquantes','Coordenadas pendientes','Missing coordinates'],capacity:['Capacité ou conducteurs insuffisants','Capacidad o conductores insuficientes','Insufficient capacity or drivers'],fix:['Corriger les coordonnées','Corregir coordenadas','Correct coordinates'],
 legacy:['Historique sans commande liée','Histórico sin pedido enlazado','History without a linked order'],depot:['Coordonnées du dépôt manquantes : départ depuis la première livraison.','Sin coordenadas del depósito: salida desde la primera entrega.','Depot coordinates missing: start at first delivery.'],
 approx:['Arrêts organisés par proximité, priorité et capacité. Les distances de Coco restent estimées ; Waze fournit la navigation et le trafic.','Paradas organizadas por cercanía, prioridad y capacidad. Las distancias de Coco siguen estimadas; Waze ofrece navegación y tráfico.','Stops organized by proximity, priority and capacity. Coco distances remain estimates; Waze provides navigation and traffic.'],
 none:['Aucune livraison géolocalisée.','No hay entregas geolocalizadas.','No geolocated deliveries.'],mapQuito:['Quito · vue initiale','Quito · vista inicial','Quito · initial view'],
 mapPoint:['Centrer sur une livraison','Centrar en una entrega','Focus a delivery'],mapArea:['Zone de toutes les livraisons','Zona de todas las entregas','Area of all deliveries'],mapFit:['Cadrer la zone des livraisons','Encuadrar la zona de entregas','Fit the delivery area'],mapPin:['Tous les points sont affichés. Déplacez la carte ou utilisez les boutons de zoom.','Todos los puntos se muestran juntos. Arrastra el mapa o usa los botones de zoom.','All delivery points are shown. Drag the map or use the zoom buttons.'],mapOutside:['Ouvrir la carte Waze','Abrir el mapa Waze','Open the Waze map'],mapLoading:['Chargement de Waze…','Cargando Waze…','Loading Waze…'],
 failed:['La planification a échoué. Réessayez.','La planificación falló. Reintenta.','Planning failed. Retry.'],invalid:['Coordonnées invalides.','Coordenadas inválidas.','Invalid coordinates.'],preserved:['L’historique local est conservé sur cet appareil et n’est pas importé sans commande liée.','El histórico local se conserva en este dispositivo y no se ha importado sin pedido enlazado.','Local history is retained on this device and is not imported without a linked order.'],
 planned:['Livraisons planifiées','Entregas planificadas','Planned deliveries'],save:['Enregistrer','Guardar','Save'],cancel:['Annuler','Cancelar','Cancel'],latitude:['Latitude','Latitud','Latitude'],longitude:['Longitude','Longitud','Longitude']};
const tr=k=>WORDS[k]?.[{fr:0,es:1,en:2}[window.GamaI18n?.language]??1]||k;
Object.assign(WORDS,{
 mapLoading:['Chargement de la carte…','Cargando mapa…','Loading map…'],mapFailed:['La carte n’a pas pu se charger.','No se pudo cargar el mapa.','The map could not load.'],retry:['Réessayer','Reintentar','Retry'],
 mapEmpty:['Aucune livraison prévue à cette date.','No hay entregas previstas para esta fecha.','No deliveries scheduled for this date.'],
 mapSync:['Actualisation toutes les 15 s','Actualización cada 15 s','Updates every 15 s'],mapStale:['Connexion interrompue · dernières données conservées','Conexión interrumpida · últimos datos conservados','Connection interrupted · keeping last data'],
 mapGps:['Véhicules avec GPS récent','Vehículos con GPS reciente','Vehicles with recent GPS'],mapGpsUnavailable:['Suivi GPS indisponible','Seguimiento GPS no disponible','GPS tracking unavailable'],
 mapOrder:['Pointillés : ordre des arrêts optimisé par Coco, distances estimées.','Línea discontinua: orden de paradas optimizado por Coco, distancias estimadas.','Dashed lines: stop order optimized by Coco, estimated distances.'],
 mapRoad:['Afficher les trajets routiers','Mostrar recorridos por carretera','Show road routes'],mapRoadPrivacy:['Cette option transmet uniquement les coordonnées des arrêts à FOSSGIS (OSRM/OpenStreetMap). Aucun nom ni GPS chauffeur n’est envoyé.','Esta opción envía solo las coordenadas de las paradas a FOSSGIS (OSRM/OpenStreetMap). No envía nombres ni GPS del conductor.','This option sends only stop coordinates to FOSSGIS (OSRM/OpenStreetMap). No names or driver GPS are sent.'],
 mapRoadLoading:['Calcul des trajets routiers…','Calculando recorridos por carretera…','Calculating road routes…'],mapRoadFailed:['Tracé routier indisponible pour certaines tournées : ordre indicatif en pointillés.','Recorrido por carretera no disponible para algunas rutas: orden indicativo en línea discontinua.','Road routes unavailable for some tours: indicative order shown as dashed lines.'],
 mapRoadReady:['Traits pleins : trajets routiers selon l’ordre Coco, sans trafic en direct ni restrictions poids lourds.','Línea continua: recorridos por carretera en el orden Coco, sin tráfico en directo ni restricciones de camiones.','Solid lines: road routes in Coco stop order, without live traffic or truck restrictions.']
});
const validPoint=d=>d?.lat!=null&&d?.lng!=null&&d.lat!==''&&d.lng!==''&&Number.isFinite(+d.lat)&&Number.isFinite(+d.lng)&&Math.abs(+d.lat)<=85&&Math.abs(+d.lng)<=180;
const QUITO={lat:-0.1807,lng:-78.4678,zoom:12};
let plan=null,planError='',planningJob=null,planningEpoch=0,lastPlanning=0,mapRoute='all',mapPoint='all',mapZoom=null,mapView=null,mapObserver=null,authEpoch=0;
let liveTimer=0,liveDebounce=0,liveEpoch=0,liveStarted=false,liveJob=null,liveChannels=[],liveClient=null,liveRoutes=[],liveAt=0,liveError=false,liveGpsError=false,mapLoading=null;
let roadEnabled=false,roadEpoch=0,roadKey='',roadResults=new Map(),roadState='';
let renderedDayKey='';const dayState=()=>JSON.stringify([db.deliveries,db.routes,db.counts,db.settings]);
const planningActive=()=>currentTab==='today'&&selectedStage==='planning'&&section().classList.contains('active')&&!!window.gamaAccessAllowed?.('tms');
function mapStatus(){
 const el=document.getElementById('tMapSync');if(!el)return;
 el.textContent=!navigator.onLine||liveError?tr('mapStale'):tr('mapSync')+(liveAt?' · '+new Date(liveAt).toLocaleTimeString(window.GamaI18n?.language||'es'):'');
 el.dataset.state=!navigator.onLine||liveError?'stale':'live';
 const gps=document.getElementById('tMapGps');if(gps)gps.textContent=liveGpsError?tr('mapGpsUnavailable'):tr('mapGps')+': '+liveVehicles().length;
 const road=document.getElementById('tMapRoadStatus');if(road)road.textContent=tr(roadEnabled?(roadState||'mapRoadReady'):'mapOrder');
}
function liveVehicles(){return liveRoutes.filter(r=>r.route_date===day()&&(mapRoute==='all'||r.id===mapRoute)&&validPoint(r.position)&&Date.now()-Date.parse(r.position.observed_at)>=-60000&&Date.now()-Date.parse(r.position.observed_at)<=5*60000).map((r,i)=>({id:r.id,lat:r.position.lat,lng:r.position.lng,customer:r.driver_name,observedAt:r.position.observed_at,label:String(i+1),color:window.CocoDeliveryMap?.routeColor(r,Math.max(0,routesForDay().findIndex(x=>x.id===r.id)))}))}
function stopLiveMap(){
 liveEpoch++;liveStarted=false;clearTimeout(liveTimer);clearTimeout(liveDebounce);liveJob=null;
 for(const channel of liveChannels)Promise.resolve(liveClient?.removeChannel(channel)).catch(()=>{});liveChannels=[];liveClient=null;
 roadEpoch++;roadKey='';window.CocoTmsRoadMap?.clear();
}
async function refreshLiveMap(){
 if(!planningActive()||document.hidden||planningJob||liveJob)return;
 if(!navigator.onLine){drawDayMap();mapStatus();return}
 const token=liveEpoch,stamp=day(),session=authEpoch;
 const active=()=>token===liveEpoch&&session===authEpoch&&stamp===day()&&planningActive();
 const job=(async()=>{
  try{
   await fetchAll();if(!active())return;markOrigins();
   if(db.routes.length){
    try{const r=await window.ArcData.rawRpc('gama_tms_pro',{p_action:'live',p_data:{from:stamp,to:stamp}},{read:true});if(!active())return;if(r.error)throw r.error;liveRoutes=r.data?.routes||[];liveGpsError=false}
    catch(e){if(!active())return;liveRoutes=[];liveGpsError=true}
   }else{liveRoutes=[];liveGpsError=false}
   if(!active())return;liveAt=Date.now();liveError=false;
   // GPS-only updates retain the SVG; business changes update the lists too.
   // A replacement map restores its viewport through the controller snapshot.
   const changed=renderedDayKey!==dayState();
   const editing=document.querySelector('dialog[open]')||section().querySelector('input:focus,select:focus,textarea:focus,[draggable=true]:focus');
   if(changed&&!editing)render('today');else drawDayMap();updateMapRoutes();
   const count=document.getElementById('tMapDayCount');if(count)count.textContent=String(db.deliveries.filter(d=>d.date===day()).length);
  }catch(e){if(active()){liveError=true;drawDayMap();mapStatus()}}
 })();liveJob=job;try{await job}finally{if(liveJob===job)liveJob=null}
}
function queueMapRefresh(){clearTimeout(liveDebounce);liveDebounce=setTimeout(()=>refreshLiveMap(),400)}
function startLiveMap(){
 if(liveStarted||!planningActive())return;liveStarted=true;const token=liveEpoch;
 const tick=async()=>{if(token!==liveEpoch||!planningActive())return;await refreshLiveMap();if(token===liveEpoch&&planningActive())liveTimer=setTimeout(tick,15000)};
 liveTimer=setTimeout(tick,500);
 // The polling fallback also covers installations without a Realtime publication.
 C().db().then(client=>{if(token!==liveEpoch||!planningActive())return;liveClient=client;if(!client.channel)return;
  for(const table of ['tms_deliveries','tms_routes'])liveChannels.push(client.channel('coco-tms-map-'+table+'-'+token+'-'+Date.now()).on('postgres_changes',{event:'*',schema:'public',table},queueMapRefresh).subscribe());
 }).catch(()=>{});
}
function updateMapRoutes(){
 const selector=document.getElementById('tMapRoute');if(!selector)return;
 selector.innerHTML=`<option value="all">${esc(tr('all'))}</option>`+routesForDay().map(r=>`<option value="${esc(r.id)}">${esc(r.reference||r.driver||r.id)}</option>`).join('');selector.value=mapRoute;
}
function mapRoutes(){return routesForDay().filter(r=>mapRoute==='all'||mapRoute===r.id).map((r,i)=>{
 const stops=[...r.stops],depot=db.settings.depotPoint;
 if(!Object.hasOwn(r.routePoints||{},'start')){if(validPoint(depot)&&stops[0]!=='__depot')stops.unshift('__depot');if(validPoint(depot)&&db.settings.returnDepot&&stops.at(-1)!=='__depot')stops.push('__depot')}
 return {...r,stops,color:window.CocoDeliveryMap?.routeColor(r,routesForDay().findIndex(x=>x.id===r.id)),geometry:roadEnabled?roadResults.get(r.id)?.geometry:null};
})}
async function loadRoadRoutes(){
 if(!roadEnabled||!planningActive()||document.hidden||!navigator.onLine)return;
 const routes=mapRoutes();
 const inputs=routes.map(r=>({id:r.id,points:routeStops(r).map(p=>validPoint(p)?[+Number(p.lng).toFixed(6),+Number(p.lat).toFixed(6)]:null)}));
 const key=JSON.stringify({day:day(),inputs});if(roadKey===key)return;roadKey=key;const token=++roadEpoch;
 roadResults.clear();roadState='mapRoadLoading';mapStatus();let failed=false;
 try{
  await window.ArcLoadScript('coco-tms-road-map.js',{validate:()=>!!window.CocoTmsRoadMap});
  for(const input of inputs){
   if(token!==roadEpoch||!planningActive())return;if(input.points.length<2)continue;
   try{const result=await window.CocoTmsRoadMap.route(input.points);if(token!==roadEpoch||!planningActive())return;roadResults.set(input.id,result)}catch(e){failed=true}
  }
 }catch(e){failed=true}
 if(token!==roadEpoch||!planningActive())return;roadState=failed?'mapRoadFailed':'mapRoadReady';drawDayMap();mapStatus();
}
function markOrigins(){const ids=new Set(plan?.order_delivery_ids||[]);db.deliveries.forEach(d=>d.fromOrder=ids.has(d.id))}
async function autoPlanning(force=false){
 if(!planningActive()||planningJob||(!force&&Date.now()-lastPlanning<10000))return;
 if(!force&&document.getElementById('tDayMap')?.contains(document.activeElement))return;
 const epoch=planningEpoch;lastPlanning=Date.now();planError='';
 const run=async()=>{
  try{
   if(Date.now()-fetchedAt>=30000)await fetchAll();await fetchAux();if(epoch!==planningEpoch||!planningActive())return;
   if(day()>=today()){const state=await window.CocoTmsDispatch.rpc('settings');if(force||!state.automation?.valid){const r=await window.ArcData.rawRpc('gama_tms_plan_day',{p_day:day()});if(r.error)throw r.error;plan=r.data;}else{const r=await window.CocoTmsDispatch.rpc('planning_status',{day:day()});plan=r.summary;}markOrigins();}
   if(epoch!==planningEpoch||!planningActive())return;
   await fetchAll();markOrigins();
  }catch(e){console.warn('[TMS] automatic planning',e);if(epoch===planningEpoch)planError=tr('failed')+' '+(window.GamaLoading?.error(e)||e.message||'')}
  finally{if(epoch===planningEpoch&&planningActive())render('today')}
 };
 planningJob=run();render('today');try{await planningJob}finally{planningJob=null;if(planningActive()){if(epoch===planningEpoch)render('today');else autoPlanning(true)}}
}
function routesForDay(){return db.routes.filter(r=>r.date===day()||r.stops.some(id=>db.deliveries.some(d=>d.id===id&&d.date===day()&&!['Entregada','Cancelada'].includes(d.status))))}
function planningBody(ds){
 const routes=routesForDay();
 const missing=ds.filter(d=>d.fromOrder&&!['Entregada','Cancelada'].includes(d.status)&&!validPoint(d));
 return `<div class="tmsDayWorkspace"><div class="arcPanel tmsCard tmsPlanningCard"><div class="tmsTitle"><b>${esc(tr('auto'))} · ${esc(plan?.today||day())}</b><button type="button" class="arcButton tmsBtn tmsLight" id="tRefresh"${planningJob?' disabled':''}>${esc(planningJob?tr('working'):tr('refresh'))}</button></div><p>${esc(tr('orders'))}</p><div role="status" id="tPlanStatus">${plan?`${esc(tr('planned'))}: ${plan.planned} / ${plan.total}`:''}</div>${planError?`<p role="alert" class="tmsAbsente">${esc(planError)}</p>`:''}${avisoAusencias()}${plan?.without_cargo?`<p class="tmsAbsente">Carga sin verificar: ${plan.without_cargo}. Abre «Ventana y carga».</p>`:''}${plan?.without_capacity?`<p class="tmsAbsente">${esc(T('Pendientes de planificación'))}: ${plan.without_capacity}</p>`:''}${plan?.depot_missing?`<p class="tmsHint">${esc(tr('depot'))}</p>`:''}</div>
 <div class="arcPanel tmsCard tmsMapCard"><div class="tmsTitle"><b>${esc(tr('map'))} · Coco</b><div class="tmsMapTools"><select id="tMapRoute" aria-label="${esc(tr('all'))}"><option value="all">${esc(tr('all'))}</option>${routes.map(r=>`<option value="${esc(r.id)}"${mapRoute===r.id?' selected':''}>${esc(r.reference||r.driver||r.id)}</option>`).join('')}</select><button type="button" class="arcButton tmsBtn" id="tMapOut" aria-label="Zoom −" disabled>−</button><button type="button" class="arcButton tmsBtn" id="tMapIn" aria-label="Zoom +" disabled>+</button><button type="button" class="arcButton tmsBtn" id="tMapFit" aria-label="${esc(tr('mapFit'))}" disabled>↔</button></div></div>
 <div class="tmsMapSummary"><span id="tMapSync"></span><span id="tMapGps"></span><span>${esc(T('Entregas de hoy'))}: <b id="tMapDayCount">${ds.length}</b></span></div>
 <label for="tMapPoint" class="tmsMapLabel">${esc(tr('mapPoint'))}</label><select id="tMapPoint" class="tmsMapPoint" aria-label="${esc(tr('mapPoint'))}"></select><div id="tDayMap" class="tmsDayMap" aria-label="${esc(tr('map'))}"><p role="status" class="tmsEmpty">${esc(tr('mapLoading'))}</p></div>
 <p id="tMapEmpty" class="tmsHint"${ds.length?' hidden':''}>${esc(tr('mapEmpty'))}</p><div id="tMapLegend" class="tmsMapLegend"></div><div id="tMapPoints" class="tmsMapPoints"></div><a id="tMapOutside" class="arcButton secondary" target="_blank" rel="noopener noreferrer" hidden>${esc(tr('mapOutside'))}</a>
 <label class="tmsMapRoadToggle"><input type="checkbox" id="tMapRoads"${roadEnabled?' checked':''} aria-describedby="tMapRoadPrivacy">${esc(tr('mapRoad'))}</label><p class="tmsHint" id="tMapRoadPrivacy">${esc(tr('mapRoadPrivacy'))}</p><p class="tmsHint" id="tMapRoadStatus" role="status"></p>
 <p class="tmsHint" id="tMapRoadAttribution"${roadEnabled?'':' hidden'}>© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> · <a href="https://routing.openstreetmap.de/about.html" target="_blank" rel="noopener noreferrer">FOSSGIS / OSRM</a> · <a href="https://www.openstreetmap.org/fixthemap" target="_blank" rel="noopener noreferrer">Fix the map</a></p>${missing.length?`<p class="tmsAbsente">${esc(tr('missing'))}: ${missing.length}</p>`:''}</div>
 <div class="tmsGrid tmsDayStops"><div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(T('Entregas de hoy'))}</b><small>${ds.length}</small></div><div class="tmsTableScroll"><table class="arcTable tmsTable"><thead><tr><th>${esc(T('Cliente'))}</th><th>${esc(T('Carga'))}</th><th>${esc(T('Estado'))}</th></tr></thead><tbody>${ds.map(d=>`<tr id="tms-delivery-${esc(d.id)}" tabindex="-1"><td><b>${esc(d.reference||'')} ${esc(d.customer)}</b><br><small>${esc(d.address)} · ${esc(d.timeWindow||'—')}</small></td><td>${d.weight} kg / ${d.volume} m³</td><td>${badge(d)}<br>${['En tránsito','En ruta','Excepción','Entrega parcial'].includes(d.status)?`<button type="button" class="arcButton secondary" data-tms-operate="${esc(d.id)}">${esc(T('Gestionar entrega'))}</button><br>`:''}<button type="button" class="arcButton secondary" data-tms-configure="${esc(d.id)}" data-gi=3a8c9340143c>Ventana y carga</button>${d.customerId&&window.gamaAccessAllowed?.('contacts')?`<br><button type="button" class="arcButton secondary" data-tms-addresses="${esc(d.id)}">${esc(T('Direcciones de entrega'))}</button>`:''}${d.fromOrder?`<br><button type="button" class="arcButton tmsBtn tmsLight" data-tms-coordinates="${esc(d.id)}"${planningJob?' disabled':''}>${esc(tr('fix'))}</button><br><button type="button" class="arcButton tmsBtn tmsLight" data-tms-loading="${esc(d.id)}">${esc(T('Salida de bultos'))}</button>`:`<br><small>${esc(tr('legacy'))}</small>`}</td></tr>`).join('')}</tbody></table></div></div>
 <div><div class="arcPanel tmsCard">${routes.map(routeCard).join('')||`<div class="tmsEmpty">${esc(T('No hay rutas planificadas.'))}</div>`}</div>
</div></div></div>`;
}
function drawDayMap(){
 const host=document.getElementById('tDayMap');if(!host||!planningActive())return;
 if(!window.CocoDeliveryMap?.create||!window.CocoMapData){
  if(!mapLoading){const epoch=authEpoch;mapLoading=Promise.all([window.ArcLoadScript('gama-tms-map-data.js',{validate:()=>!!window.CocoMapData}),window.ArcLoadScript('gama-tms-local-map.js',{validate:()=>!!window.CocoDeliveryMap?.create})]).then(()=>{if(epoch===authEpoch&&host.isConnected)drawDayMap()}).catch(()=>{if(epoch===authEpoch&&host.isConnected)mapFailure(host)}).finally(()=>{mapLoading=null})}return;
 }
 if(!routesForDay().some(r=>r.id===mapRoute))mapRoute='all';
 loadRoadRoutes();const routes=mapRoutes(),selected=new Set(routes.flatMap(r=>r.stops));
 const points=db.deliveries.filter(d=>d.date===day()&&validPoint(d)&&(mapRoute==='all'||selected.has(d.id)));
 for(const r of routes)for(const p of routeStops(r).filter(p=>p.isDepot&&validPoint(p)))if(!points.some(x=>x.id===p.id))points.push(p);
 const depot=db.settings.depotPoint;if(validPoint(depot)&&!points.some(p=>p.id==='__depot'))points.push({...depot,customer:db.settings.depot});
 const renderRoutes=routes.map(r=>({...r,stops:routeStops(r).map(p=>p.id)}));
 const selector=document.getElementById('tMapPoint'),list=document.getElementById('tMapPoints'),outside=document.getElementById('tMapOutside');
 if(!['all','__quito'].includes(mapPoint)&&!points.some(d=>d.id===mapPoint))mapPoint='all';
 selector.innerHTML=`<option value="all">${esc(tr('mapArea'))}</option><option value="__quito">${esc(tr('mapQuito'))}</option>${points.map(d=>`<option value="${esc(d.id)}">${esc(d.isDepot?(d.customer||T('Depósito')):[d.reference,d.customer].filter(Boolean).join(' · '))}</option>`).join('')}`;selector.value=mapPoint;
 list.innerHTML=points.filter(d=>!d.isDepot).map((d,i)=>{const r=routes.find(r=>r.stops.includes(d.id)),number=r?r.stops.filter(id=>id!=='__depot').indexOf(d.id)+1:i+1;return `<button type="button" class="arcButton secondary" data-map-delivery="${esc(d.id)}" aria-pressed="${mapPoint===d.id}">${number}. ${esc([d.reference,d.customer,T(d.status)].filter(Boolean).join(' · '))}</button>`}).join('');
 const select=id=>{mapPoint=id;selector.value=id;list.querySelectorAll('[data-map-delivery]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mapDelivery===id)));const d=points.find(p=>p.id===id);outside.href=d?wazeUrl(d):'https://www.waze.com/ul?ll=-0.1807%2C-78.4678';document.getElementById('tms-delivery-'+id)?.focus({preventScroll:true})};
 try{
  const data={points,routes:renderRoutes,vehicles:liveVehicles(),onSelect:select};
  if(host.querySelector('svg')&&mapView?.update)mapView.update(data);
  else{const view=mapView?.snapshot?.();mapView?.destroy?.();mapView=window.CocoDeliveryMap.create(host,{...data,view});if(!view&&mapPoint!=='all')mapView.focus(mapPoint)}
 }catch(e){console.warn('[TMS] map rendering',e);mapFailure(host);return}
 list.querySelectorAll('[data-map-delivery]').forEach(b=>b.onclick=()=>{select(b.dataset.mapDelivery);mapView.focus(mapPoint)});
 ['tMapOut','tMapIn','tMapFit'].forEach(id=>document.getElementById(id).disabled=false);
 const focused=points.find(p=>p.id===mapPoint);outside.href=focused?wazeUrl(focused):'https://www.waze.com/ul?ll=-0.1807%2C-78.4678';outside.hidden=false;
 const legend=document.getElementById('tMapLegend');if(legend)legend.innerHTML=routes.map(r=>`<span><i style="background:${esc(r.color)}" aria-hidden="true"></i>${esc(r.reference||r.driver||r.vehicle||r.id)} · ${r.stops.filter(id=>id!=='__depot').length}</span>`).join('');
 const empty=document.getElementById('tMapEmpty');if(empty)empty.hidden=db.deliveries.some(d=>d.date===day());mapStatus();
}
function mapFailure(host){
 mapView?.destroy?.();mapView=null;host.innerHTML=`<div class="tmsEmpty" role="alert"><p>${esc(tr('mapFailed'))}</p><button type="button" class="arcButton secondary" data-map-retry>${esc(tr('retry'))}</button></div>`;
 host.querySelector('[data-map-retry]').onclick=()=>drawDayMap();
}

function editCoordinates(id){
 const d=findDelivery(id);if(!d?.fromOrder)return;
 const dlg=document.createElement('dialog');dlg.className='tmsCoordinateDialog';
 dlg.innerHTML=`<form><h3>${esc(tr('fix'))}</h3><p>${esc(d.customer)} · ${esc(d.address)}</p><label>${esc(tr('latitude'))}<input name="lat" type="number" step="any" min="-85" max="85" required value="${esc(d.lat??'')}"></label><label>${esc(tr('longitude'))}<input name="lng" type="number" step="any" min="-180" max="180" required value="${esc(d.lng??'')}"></label><p role="alert"></p><button type="submit" class="arcButton">${esc(tr('save'))}</button><button type="button" class="arcButton" data-close>${esc(tr('cancel'))}</button></form>`;
 document.body.appendChild(dlg);dlg.showModal();dlg.addEventListener('close',()=>dlg.remove());dlg.querySelector('[data-close]').onclick=()=>dlg.close();
 dlg.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,p={lat:Number(f.elements.lat.value),lng:Number(f.elements.lng.value)};if(!validPoint(p)){f.querySelector('[role=alert]').textContent=tr('invalid');return}const b=f.querySelector('[type=submit]');b.disabled=true;try{const r=await window.ArcData.rawRpc('gama_tms_save_gps',{p_data:{delivery_id:id,...p}});if(r.error)throw r.error;dlg.close();notify(r.data?.customer_saved?'GPS guardado en la ficha del cliente.':'GPS guardado para esta entrega.','exito');await autoPlanning(true)}catch(error){f.querySelector('[role=alert]').textContent=T(tmsError(error));b.disabled=false}};
}
function bindPlanning(x){
 x.querySelector('#tRefresh').onclick=()=>autoPlanning(true);
 x.querySelector('#tMapRoute').onchange=e=>{mapRoute=e.target.value;mapPoint='all';mapZoom=null;mapView?.destroy?.();mapView=null;drawDayMap()};
 x.querySelector('#tMapRoads').onchange=e=>{roadEnabled=e.target.checked;roadEpoch++;roadKey='';roadResults.clear();if(!roadEnabled)window.CocoTmsRoadMap?.clear();x.querySelector('#tMapRoadAttribution').hidden=!roadEnabled;drawDayMap()};
 x.querySelector('#tMapPoint').onchange=e=>{mapPoint=e.target.value;mapView?.focus(mapPoint);const d=findDelivery(mapPoint)||routesForDay().flatMap(routeStops).find(p=>p.id===mapPoint)||(mapPoint==='__depot'?db.settings.depotPoint:null);x.querySelector('#tMapOutside').href=d?wazeUrl(d):'https://www.waze.com/ul?ll=-0.1807%2C-78.4678'};
 x.querySelector('#tMapIn').onclick=()=>mapView?.zoom(1);x.querySelector('#tMapOut').onclick=()=>mapView?.zoom(-1);x.querySelector('#tMapFit').onclick=()=>{mapPoint='all';x.querySelector('#tMapPoint').value='all';mapView?.fit()};
 x.querySelectorAll('[data-tms-addresses]').forEach(b=>b.onclick=async()=>{const d=findDelivery(b.dataset.tmsAddresses);if(!d?.customerId)return;b.disabled=true;try{await window.ArcLoadScript('coco-contact-hub.js');await window.CocoContactHub.open('clients',d.customerId,{tab:'relations'})}catch(e){fail(e,'Planificación')}finally{b.disabled=false}});
 x.querySelectorAll('[data-tms-configure]').forEach(b=>b.onclick=()=>window.CocoTmsExecution.configure(b.dataset.tmsConfigure,()=>autoPlanning(true)).catch(e=>fail(e,'Planificación')));
 x.querySelectorAll('[data-tms-coordinates]').forEach(b=>b.onclick=()=>editCoordinates(b.dataset.tmsCoordinates));
 x.querySelectorAll('[data-tms-loading]').forEach(b=>b.onclick=()=>window.GamaLoading.open(b.dataset.tmsLoading));
 drawDayMap();mapObserver?.disconnect();let width=x.querySelector('#tDayMap').clientWidth;
 if(window.ResizeObserver){mapObserver=new ResizeObserver(entries=>{if(entries[0].contentRect.width!==width){width=entries[0].contentRect.width;mapView?.resize()}});mapObserver.observe(x.querySelector('#tDayMap'))}
 startLiveMap();
}
setInterval(()=>{if(document.visibilityState==='visible')autoPlanning()},180000);
window.addEventListener('focus',()=>refreshLiveMap());
document.addEventListener('visibilitychange',()=>{if(document.hidden)stopLiveMap();else if(planningActive()){startLiveMap();refreshLiveMap()}});
window.addEventListener('offline',()=>{liveError=true;mapStatus()});window.addEventListener('online',()=>{if(planningActive()){startLiveMap();refreshLiveMap()}});
window.addEventListener('gama:language-change',()=>{if(currentTab==='driver')renderDriver();else if(currentTab==='today')render('today')});
window.addEventListener('gama:data-change',e=>{if(planningActive()&&(!e.detail?.table||['tms_deliveries','tms_routes','tms_settings','sales_deliveries'].includes(e.detail.table)))queueMapRefresh()});
window.addEventListener('gama:sales-change',()=>autoPlanning());
window.addEventListener('gama:tms-config-change',()=>autoPlanning(true));
window.addEventListener('gama:tms-change',()=>{if(currentTab==='today')reload('today').catch(e=>fail(e,'TMS'))});
window.addEventListener('arc:route-leave',e=>{if(!['tms','gama-tms-section'].includes(e.detail?.id))return;planningEpoch++;stopLiveMap();mapObserver?.disconnect()});
window.addEventListener('pagehide',stopLiveMap);
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;stopLiveMap();liveRoutes=[];liveAt=0;liveError=false;liveGpsError=false;roadEnabled=false;roadResults.clear();mapView?.destroy?.()});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;followDeliveryId=null;fetchedAt=0;auxAt=0;auxPending=null;planningEpoch++;authEpoch++;currentTab="";loaded=false;proofCache={};gpsRequests.clear();proofArchiveId=null;driverView=null;proofMetadataReady=false;plan=null;mapPoint='all';mapRoute='all';mapZoom=null;mapView=null;mapObserver?.disconnect();document.getElementById('tDayMap')?.replaceChildren();document.getElementById('tMapPoints')?.replaceChildren();document.getElementById('tMapPoint')?.replaceChildren();const outside=document.getElementById('tMapOutside');if(outside){outside.removeAttribute('href');outside.hidden=true}db={deliveries:[],drivers:[],routes:[],archive:[],proofIndex:[],proofDocuments:{},counts:{},settings:{},employees:[],absences:[],customers:[]}});

function downscale(file){
 return new Promise(resolve=>{
  const fr=new FileReader();
  fr.onerror=()=>resolve(null);
  fr.onload=()=>{
   const src=fr.result,img=new Image();
   img.onerror=()=>resolve(src);
   img.onload=()=>{
    try{
     let w=img.naturalWidth||img.width,h=img.naturalHeight||img.height;
     const scale=Math.min(1,PHOTO_MAX_PX/Math.max(w,h||1));
     w=Math.max(1,Math.round(w*scale));h=Math.max(1,Math.round(h*scale));
     const c=document.createElement('canvas');c.width=w;c.height=h;
     c.getContext('2d').drawImage(img,0,0,w,h);
     const out=c.toDataURL('image/jpeg',PHOTO_QUALITY);
     resolve(out&&out.length<src.length?out:src);
    }catch(e){resolve(src)}
   };
   img.src=src;
  };
  fr.readAsDataURL(file);
 });
}
async function captureProof(id){
 const file=document.getElementById('tPhoto');
 if(!file?.files?.[0])return;
 const photo=await downscale(file.files[0]);
 if(!photo)return;
 try{
  const prev=proofCache[id],saved=await window.ArchitectOfflineProofs.capture({delivery_id:id,photo,gps:await proofGps(id),captured_at:now(),complete:false,reference:db.deliveries.find(d=>d.id===id)?.customer||''});
  proofCache[id]={delivery_id:id,photo,signature:prev?.signature||null};
  if(saved.queued)notify(window.GamaI18n?.language==='fr'?'Photo conservée sur cet appareil, synchronisation en attente.':'Foto conservada en este dispositivo; sincronización pendiente.');
  const preview=document.getElementById('tProofPhotoPreview');if(preview&&document.getElementById('tPhoto')===file){preview.src=photo;preview.hidden=false;document.getElementById('tSig')?.scrollIntoView({block:'center',behavior:'smooth'})}
 }catch(e){fail(e,'No se pudo guardar la foto')}
}
function setupSignature(canvas,d){
 const c=canvas,ctx=c.getContext('2d');let drawing=false;
 const pos=e=>{const r=c.getBoundingClientRect(),p=e.touches?e.touches[0]:e;return{x:(p.clientX-r.left)*c.width/r.width,y:(p.clientY-r.top)*c.height/r.height}};
 const start=e=>{drawing=true;const p=pos(e);ctx.beginPath();ctx.moveTo(p.x,p.y);e.preventDefault()};
 const move=e=>{if(!drawing)return;const p=pos(e);ctx.lineTo(p.x,p.y);ctx.stroke();e.preventDefault()};
 const end=()=>drawing=false;
 c.onmousedown=start;c.onmousemove=move;c.onmouseup=end;c.onmouseleave=end;c.ontouchstart=start;c.ontouchmove=move;c.ontouchend=end;
 document.getElementById('tSigClear').onclick=()=>ctx.clearRect(0,0,c.width,c.height);
 document.getElementById('tSigSave').onclick=async(event)=>{
  const button=event.currentTarget;if(button.disabled)return;
  const pixels=ctx.getImageData(0,0,c.width,c.height).data;
  if(!pixels.some((v,i)=>i%4===3&&v>0)){notify(window.GamaI18n?.t('La firma del cliente es obligatoria.')||'La firma del cliente es obligatoria.');return}
  const signature=c.toDataURL('image/png'),stamp=now();button.disabled=true;
  try{
   const saved=await window.ArchitectOfflineProofs.capture({delivery_id:d.id,signature,gps:await proofGps(d.id),captured_at:stamp,complete:true,reference:d.customer});
   if(saved.queued){notify(window.GamaI18n?.language==='fr'?'Signature conservée sur cet appareil. La livraison sera confirmée après synchronisation.':'Firma conservada en este dispositivo. La entrega se confirmará después de sincronizar.');return}
   delete proofCache[d.id];
   window.dispatchEvent(new Event('gama:sales-change'));
   proofArchiveId=d.id;
   await reload('today');
   notify('Prueba de entrega registrada.');
  }catch(e){fail(e,'No se pudo registrar la prueba de entrega')}finally{button.disabled=false}
 };
}
async function viewProofArchive(id){try{proofArchiveId=id;await ensureProof(id);render('today')}catch(e){fail(e,'No se pudo cargar la prueba')}}
/* Informe de todas las pruebas archivadas. Las fotos y las firmas se piden a la
   base sólo cuando se miran, así que aquí hay que traer las que falten antes de
   armar el PDF: si no, saldrían entregas sin prueba. */
/* Comprobante de UNA entrega, para un litigio con un cliente concreto: fecha,
   lugar, firma y foto en la misma página. El informe completo sigue existiendo
   aparte, para cuando hace falta el conjunto. */
async function downloadProofCertificate(id){
 if(!window.GamaPdf)return notify('El generador de PDF no está disponible. Recarga la aplicación.');
 const d=archiveList().find(x=>x.id===id);
 if(!d)return notify('No se encontró la entrega.');
 const btn=section().querySelector('#tProofOne');
 const texto=btn?btn.textContent:'';
 if(btn){btn.disabled=true;btn.textContent='Preparando…'}
 try{
  const pr=await ensureProof(d.id);
  await window.GamaCompany?.load(true);await window.GamaPdf.ready();
  const doc=window.GamaPdf.proofCertificate({
   cliente:d.customer,direccion:d.address,fecha:d.deliveredAt||d.date,
   conductor:(db.drivers.find(x=>x.id===d.driverId)||{}).name||'',
   referencia:proofReference(d),
   firma:pr&&pr.signature||'',foto:pr&&pr.photo||'',gps:pr&&pr.latitude!=null?{lat:pr.latitude,lng:pr.longitude,accuracy:pr.gps_accuracy_m,at:pr.gps_recorded_at}:null,receivedAt:pr?.received_at||null
  });
  const dia=new Date(d.deliveredAt||d.date||Date.now()).toISOString().slice(0,10);
  window.GamaPdf.save(doc,window.GamaPdf.fileName(proofReference(d)==='—'?'entrega':proofReference(d),dia));
 }catch(e){console.error('[GAMA PDF comprobante]',e);notify('No se pudo generar el comprobante: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
/* La ficha del cliente rellena la empresa y la dirección de la entrega. Los
   dos campos quedan editables a propósito: una entrega puntual a otra
   dirección es corriente, y el enlace con la ficha se conserva igual, que es
   lo que luego permite mandarle el comprobante a su correo. */

/* El mismo comprobante que se descarga, pero con el correo del cliente y el
   mensaje ya escritos. En el móvil se comparte el PDF directamente; en el
   escritorio se descarga y se abre el compositor. Si la entrega se escribió a
   mano o el cliente no tiene correo en su ficha, se avisa y se abre igual: el
   asunto y el cuerpo ya están puestos y sólo falta teclear la dirección. */
async function emailProofCertificate(id){
 if(!window.GamaPdf||!window.GamaQuotePdf)return notify('El generador de PDF no está disponible. Recarga la aplicación.');
 const d=archiveList().find(x=>x.id===id);
 if(!d)return notify('No se encontró la entrega.');
 const btn=section().querySelector('#tProofMail');
 const texto=btn?btn.textContent:'';
 if(btn){btn.disabled=true;btn.textContent='Preparando…'}
 try{
  const pr=await ensureProof(d.id);
  const conductor=(db.drivers.find(x=>x.id===d.driverId)||{}).name||'';
  await window.GamaCompany?.load(true);await window.GamaPdf.ready();
  const doc=window.GamaPdf.proofCertificate({
   cliente:d.customer,direccion:d.address,fecha:d.deliveredAt||d.date,
   conductor,referencia:proofReference(d),
   firma:pr&&pr.signature||'',foto:pr&&pr.photo||'',gps:pr&&pr.latitude!=null?{lat:pr.latitude,lng:pr.longitude,accuracy:pr.gps_accuracy_m,at:pr.gps_recorded_at}:null,receivedAt:pr?.received_at||null
  });
  const fecha=new Date(d.deliveredAt||d.date||Date.now());
  const dia=fecha.toISOString().slice(0,10),legible=fecha.toLocaleDateString('es-EC');
  const cliente=db.customers.find(c=>String(c.id)===String(d.customerId));
  const email=cliente&&cliente.email||'';
  if(!email)notify('Este cliente no tiene un correo registrado: complétalo manualmente al enviar.');
  await window.GamaQuotePdf.sendDocument({
   blob:doc.output('blob'),
   email,
   subject:'Comprobante de entrega — '+legible,
   body:'Estimado/a '+(d.customer||'cliente')+',\n\nAdjuntamos el comprobante de la entrega realizada el '+legible+' en '+(d.address||'')+'.'+(conductor?'\nTransportista: '+conductor+'.':'')+'\n\nQuedamos a su disposición para cualquier consulta.\n\nGAMA Entreprise Resource Planning',
   filename:window.GamaPdf.fileName(proofReference(d)==='—'?'entrega':proofReference(d),dia)
  });
 }catch(e){console.error('[GAMA PDF comprobante correo]',e);notify('No se pudo preparar el envío: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
async function downloadProofReport(){
 const btn=section().querySelector('#tProofPdf');
 if(!window.GamaPdf)return notify('El generador de PDF no está disponible. Recarga la aplicación.');
 const entregas=archiveList();
 if(!entregas.length)return notify('No hay ninguna prueba de entrega archivada.');
 const texto=btn?btn.textContent:'';
 if(btn){btn.disabled=true;btn.textContent='Preparando el informe…'}
 try{
  for(const d of entregas)await ensureProof(d.id);
  const filas=entregas.map(d=>{
   const pr=proofCache[d.id]||null;
   return {cliente:d.customer,direccion:d.address,fecha:d.deliveredAt||d.date,referencia:proofReference(d),
    conductor:(db.drivers.find(x=>x.id===d.driverId)||{}).name||'',
    firma:pr&&pr.signature||'',foto:pr&&pr.photo||'',gps:pr&&pr.latitude!=null?{lat:pr.latitude,lng:pr.longitude,accuracy:pr.gps_accuracy_m,at:pr.gps_recorded_at}:null,receivedAt:pr?.received_at||null};
  });
  await window.GamaCompany?.load(true);await window.GamaPdf.ready();
  const doc=window.GamaPdf.proofReport(filas,'Pruebas de entrega — GAMA Entreprise Resource Planning');
  window.GamaPdf.save(doc,window.GamaPdf.fileName('pruebas-entrega',new Date().toISOString().slice(0,10)));
 }catch(e){console.error('[GAMA PDF pruebas]',e);notify('No se pudo generar el informe: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
async function saveDepot(){
 const x=section(),address=x.querySelector('#tDepot').value.trim(),lat=x.querySelector('#tDepotLat').value,lng=x.querySelector('#tDepotLng').value;
 if((lat!==''||lng!=='')&&(!lat||!lng||!validPoint({lat,lng})))return notify(tr('invalid'));
 try{const r=await C().upsert('tms_settings',{id:true,depot:address||null,depot_lat:lat===''?null:Number(lat),depot_lng:lng===''?null:Number(lng),return_depot:x.querySelector('#tReturn').value==='1',updated_at:now()},{onConflict:'id'});if(r.error)throw r.error;await autoPlanning(true)}catch(e){fail(e,'No se pudieron guardar los parámetros')}
}

const fechaCorta=s=>{const [y,m,d]=String(s||'').split('-');return d?d+'/'+m+'/'+y:String(s||'')};
/* Aviso en la planificación: quién no sale hoy y por qué. Se ve antes de pulsar
   «Optimizar», que es cuando importa. */
function avisoAusencias(){
 const fuera=db.drivers.filter(d=>d.absent);
 /* Sin recursos no hay reparto posible, y el sitio donde arreglarlo no es
    este: la persona se da de alta en RRHH, el vehículo en Flota, y los dos se
    emparejan en Flota. Decirlo aquí evita buscar un botón que ya no existe. */
 /* Si la puerta de reparto no respondió, decirlo: una lista vacía por un
    error de lectura no es lo mismo que una lista vacía de verdad, y mandar a
    dar de alta a alguien que ya existe hace perder el tiempo. */
 if(db.driversError)return `<p class="tmsAbsente" data-gi-live>${esc(T('No se pudieron leer los conductores disponibles.'))}</p>`;
 const sinRecursos=!db.drivers.length
  ? `<p class="tmsAbsente" data-gi-live>${esc(T('No hay conductores con vehículo asignado. Se dan de alta en RRHH y se emparejan con un vehículo en Gestión de flota.'))}</p>`
  : !db.drivers.some(d=>d.enabled)
   ? `<p class="tmsAbsente" data-gi-live>${esc(T('Ningún conductor tiene hoy un vehículo en servicio. Revisa las afectaciones en Gestión de flota.'))}</p>`
   : '';
 if(!fuera.length)return sinRecursos;
 return sinRecursos+`<p class="tmsAbsente">${esc(T('Hoy no reparten:'))} ${fuera.map(d=>{
  const a=driverAbsence(d,today());
  return esc(d.name)+(a?' ('+esc(absLabel(a).toLowerCase())+')':'')}).join(', ')}.</p>`;
}
function editableRoute(r){return !!r&&!['En ruta','En tránsito','Terminada','Cancelada'].includes(r.status)&&routeStops(r).every(d=>d.isDepot||!['En carga','En tránsito','En ruta','Entregada','Cancelada'].includes(d.status))}
function routeCard(r){
 const stops=routeStops(r).filter(d=>!d.isDepot),editable=editableRoute(r)&&!planningJob&&!moveBusy;
 return `<div class="tmsRoute" data-route-drop="${esc(r.id)}"><div class="tmsRouteHead"><b>${[r.reference,r.driver,r.vehicle].filter(Boolean).map(esc).join(' · ')}</b><small>${r.distance.toFixed(1)} km (${esc(r.distanceBasis==='road'||r.distanceBasis==='road_verified'?T('Carretera'):r.distanceBasis==='mixed'?T('Mixta'):T('Estimada'))}) · ${r.weight} kg · ${r.volume} m³</small></div><p>${esc(T(r.status))}${r.manual?` · <span class="tmsBadge tmsStatus-planned">${esc(T('Ajustada manualmente'))}</span>`:''}</p>
 ${window.CocoTmsDispatch.routeActions(r)}<ol class="tmsStops">${stops.map((d,i)=>`<li data-route-stop="${esc(d.id)}" data-route-id="${esc(r.id)}" draggable="${editable}" class="tmsEditableStop"><div><b>${esc(d.reference)} ${esc(d.customer)}</b><small>${esc(d.address)}</small>${d.etaAt?`<small>${esc(window.CocoTmsDispatch.t(d.etaBasis==='verified'?'Horario verificado':'Llegada estimada',d.etaBasis==='verified'?'Horaire vérifié':'Arrivée estimée',d.etaBasis==='verified'?'Verified schedule':'Estimated arrival'))}: ${esc(new Date(d.etaAt).toLocaleTimeString(window.GamaI18n?.locale||'es-EC',{timeZone:'America/Guayaquil',hour:'2-digit',minute:'2-digit'}))}</small>`:''}${badge(d)}</div>${editable?`<div class="tmsStopTools"><button class="arcButton secondary" data-stop-up="${esc(d.id)}" aria-label="${esc(T('Subir parada'))}"${i?'':' disabled'}>↑</button><button class="arcButton secondary" data-stop-down="${esc(d.id)}" aria-label="${esc(T('Bajar parada'))}"${i<stops.length-1?'':' disabled'}>↓</button><select data-stop-target="${esc(d.id)}" aria-label="${esc(T('Mover a otra ruta'))}"><option value="">${esc(T('Mover a otra ruta'))}</option>${db.routes.filter(x=>x.id!==r.id&&editableRoute(x)&&x.date===r.date).map(x=>`<option value="${esc(x.id)}">${esc(x.reference||x.driver)}</option>`).join('')}</select></div>`:''}</li>`).join('')}</ol><a class="arcButton tmsBtn tmsLight" href="${esc(mapsUrl(r))}" target="_blank" rel="noopener noreferrer">Waze</a></div>`;
}
async function moveStop(id,targetId,beforeId=null){
 if(moveBusy||planningJob)return;const d=findDelivery(id),source=db.routes.find(r=>r.id===d?.routeId),target=db.routes.find(r=>r.id===targetId);if(!source||!target)return;
 moveBusy=true;render();try{const r=await window.ArcData.rawRpc('gama_tms_move_stop',{p_data:{delivery_id:id,target_route_id:targetId,before_stop_id:beforeId,source_version:source.version,target_version:target.version,day:day()}});if(r.error)throw r.error;await fetchAll();markOrigins();notify('Ruta actualizada.','exito')}
 catch(e){notify(tmsError(e),'error');await fetchAll()}finally{moveBusy=false;render()}
}
function bindRouteMoves(x){
 x.querySelectorAll('[data-tms-manifest]').forEach(b=>b.onclick=()=>window.CocoTmsExecution.manifest(b.dataset.tmsManifest).catch(e=>fail(e,'Manifiesto')));
 x.querySelectorAll('[data-tms-schedule]').forEach(b=>b.onclick=()=>window.CocoTmsExecution.schedule(b.dataset.tmsSchedule).catch(e=>fail(e,'Horario')));
 x.querySelectorAll('[data-tms-guide]').forEach(b=>b.onclick=()=>window.GamaSriDocuments.guide(b.dataset.tmsGuide,true).catch(e=>fail(e,'Guía de remisión')));
 x.querySelectorAll('[data-stop-up],[data-stop-down]').forEach(b=>b.onclick=()=>{const id=b.dataset.stopUp||b.dataset.stopDown,d=findDelivery(id),r=db.routes.find(r=>r.id===d?.routeId),ids=routeStops(r).filter(d=>!d.isDepot).map(d=>d.id),i=ids.indexOf(id);moveStop(id,r.id,b.dataset.stopUp?ids[i-1]:ids[i+2]||null)});
 x.querySelectorAll('[data-stop-target]').forEach(s=>s.onchange=()=>{if(s.value)moveStop(s.dataset.stopTarget,s.value)});
 x.querySelectorAll('[data-route-stop]').forEach(li=>li.ondragstart=e=>{if(li.draggable)e.dataTransfer.setData('text/plain',li.dataset.routeStop)});
 x.querySelectorAll('[data-route-drop]').forEach(host=>{host.ondragover=e=>{const r=db.routes.find(r=>r.id===host.dataset.routeDrop);if(editableRoute(r)&&!planningJob&&!moveBusy){e.preventDefault();e.dataTransfer.dropEffect='move'}};host.ondrop=e=>{e.preventDefault();const id=e.dataTransfer.getData('text/plain'),before=e.target.closest('[data-route-stop]')?.dataset.routeStop;if(id&&id!==before)moveStop(id,host.dataset.routeDrop,before||null)}});
}
function renderDriver(){currentTab='driver';return window.CocoTmsDriverUI.mount(section(),driverView,()=>open('driver'),{receive:id=>openProof(id,true)}).catch(e=>fail(e,'Mi ruta'))}

function proofBody(){
 const rows=[...new Map([...db.deliveries.filter(d=>!['Entregada','Cancelada'].includes(d.status)),...archiveList()].map(d=>[d.id,d])).values()]
  .sort((a,b)=>String(b.deliveredAt||b.date).localeCompare(String(a.deliveredAt||a.date))||a.id.localeCompare(b.id));
 const keys={date:d=>d.deliveredAt||db.proofIndex.find(p=>p.delivery_id===d.id)?.captured_at||d.date,partner:proofPartner,reference:proofReference,status:status};
 const selected=archiveList().find(d=>d.id===defaultProofId()),pr=selected?proofCache[selected.id]:null;
 return `<div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(T('Pruebas de entrega'))}</b><small>${rows.length}</small><p class="tmsHint">${esc(window.CocoTmsDispatch.t('Últimas 50 pruebas. Usa «Todo el historial» para buscar sin límite de antigüedad.','50 dernières preuves. Utilisez «Tout l’historique» pour rechercher sans limite d’ancienneté.','Latest 50 proofs. Use Full history to search all dates.'))}</p>${archiveList().length?`<button class="arcButton secondary" id="tProofPdf">${esc(window.CocoTmsDispatch.t('PDF de la selección','PDF de la sélection','Selection PDF'))}</button>`:''}</div>
 <div class="tmsTableScroll"><table class="arcTable tmsTable" id="tProofTable" data-gama-sort-key="tmsProofs"><thead><tr>${GamaSort.th('tmsProofs','date',T('Fecha'))}${GamaSort.th('tmsProofs','partner',T('Cliente / proveedor'))}${GamaSort.th('tmsProofs','reference',T('Referencia'))}${GamaSort.th('tmsProofs','status',T('Estado'))}<th>${esc(T('Acciones'))}</th></tr></thead><tbody>${GamaPage.slice('tmsProofs',rows,keys).map(d=>`<tr data-proof-row="${esc(d.id)}"><td>${esc(window.ArcFormat.date(keys.date(d)))}</td><td><b>${esc(proofPartner(d))}</b><br><small>${esc(d.address)}</small></td><td>${esc(proofReference(d))}</td><td>${badge(d)}</td><td><div class="tmsProofActions">${status(d)==='Entregada'?`<button class="arcButton secondary" data-proof-view="${esc(d.id)}">${esc(T('Ver'))}</button><button class="arcButton primary" data-proof-download="${esc(d.id)}">${esc(T('Descargar'))}</button><button class="arcButton secondary" data-proof-mail="${esc(d.id)}">${esc(T('Enviar'))}</button>`:`<button class="arcButton primary" data-proof-capture="${esc(d.id)}">${esc(T('Abrir prueba de entrega'))}</button>`}</div></td></tr>`).join('')||`<tr><td colspan="5">${esc(T('No hay entregas.'))}</td></tr>`}</tbody></table></div>${GamaPage.controls('tmsProofs',rows.length)}
 ${selected&&pr?`<div id="tProofPreview"><h3>${esc(proofReference(selected))} · ${esc(selected.customer)}</h3><div class="tmsProof">${pr.photo?`<img alt="${esc(T('Foto de entrega'))}" src="${esc(pr.photo)}">`:''}${pr.signature?`<img alt="${esc(T('Firma del cliente'))}" src="${esc(pr.signature)}">`:''}</div><p>${esc(selected.notes||'')}</p><button class="arcButton primary" id="tProofOne">${esc(T('Descargar comprobante de esta entrega'))}</button> <button class="arcButton secondary" id="tProofMail">${esc(T('Enviar el comprobante al cliente'))}</button></div>`:''}</div>`;
}
const STAGES=[['preparation','Preparar','por preparar'],['planning','Planificar','por planificar'],['loading','Cargar','por cargar'],['proof','Entregar','por entregar']];
async function selectStage(key){if(key!=='planning')stopLiveMap();selectedStage=key;currentTab='today';++proofViewVersion;render('today');if(key==='proof'){await proofMetadata();if(selectedStage===key)render('today')}if(key==='planning')await autoPlanning();document.getElementById('tms-stage-'+key)?.scrollIntoView({block:'start',behavior:'smooth'})}
function render(){
 if(driverView&&currentTab==='driver')return renderDriver();
 renderedDayKey=dayState();
 ++proofViewVersion;currentTab='today';const x=section(),ds=db.deliveries.filter(d=>d.date===day());
 window.ArcUI.render(x,`<div class="tms"><div class="cocoDossierWorkspace"><div class="cocoDossierMain">${window.GamaUI.header({title:day()===today()?'TMS · Hoy':'TMS · Planificación',lead:'Preparar → Planificar → Cargar → Entregar'})}
 ${db.deliveries.length>=1000||db.routes.length>=500?`<p class="tmsHint">${esc(window.CocoTmsDispatch.t('Vista limitada. Abre la lista completa paginada.','Vue limitée. Ouvrez la liste complète paginée.','Limited view. Open the full paged list.'))}<button class="arcButton secondary" id="tDayMore">${esc(T('Ver'))}</button></p>`:''}<div class="tmsTodayBar"><p>${esc(window.ArcFormat.date(day()))} · ${ds.filter(d=>d.status==='Entregada').length} ${esc(T('entregadas'))}${db.counts.incidents?` · <span class="tmsBadge tmsStatus-incident">${db.counts.incidents} ${esc(T('incidentes'))}</span>`:''}</p><button type="button" class="arcButton secondary" id="tMyRoute">${esc(T('Mi ruta'))}</button><label>${esc(T('Fecha de planificación'))}<input id="tPlanningDay" type="date" value="${esc(day())}"></label><button class="arcButton secondary" id="tDayClose" data-gi=ce2e1bc81094>Cierre de jornada</button>${window.CocoTmsDispatch.toolbar()}<button class="arcButton secondary" id="tMetrics">${esc(T('Indicadores'))}</button></div>
 <nav class="tmsFlow" aria-label="${esc(T('Flujo de entregas'))}">${STAGES.map(([id,label,hint],i)=>`<button type="button" class="tmsFlowStep ${selectedStage===id?'active':''}" data-tms-stage="${id}" aria-expanded="${selectedStage===id}" aria-controls="tms-stage-${id}"><span>${i+1}. ${esc(T(label))}</span><strong>${Number(db.counts[id]||0)}</strong><small>${esc(T(hint))}</small></button>`).join('')}</nav>
 ${STAGES.map(([id,label])=>`<div role="region" class="tmsStage" id="tms-stage-${id}"${selectedStage===id?'':' hidden'} aria-label="${esc(T(label))}">${id==='planning'?planningBody(ds):id==='proof'?proofBody():`${id==='loading'&&selectedStage==='loading'?`<div class="tmsLoadingRoutes">${routesForDay().filter(r=>!['Terminada','Cancelada'].includes(r.status)).map(r=>`<div class="arcPanel tmsCard"><b>${esc(r.reference||r.driver)} · ${esc(r.vehicle)}</b>${window.CocoTmsDispatch.routeActions(r)}</div>`).join('')}</div>`:''}<div id="${id==='preparation'?'gamaPreparationHost':'gamaLoadingHost'}"></div>`}</div>`).join('')}</div><aside></aside></div></div>`);
 window.GamaUI.bindBack(x);x.querySelector('#tMyRoute').onclick=()=>{stopLiveMap();open('driver')};x.querySelector('#tPlanningDay').onchange=async e=>{const value=e.target.value;if(!/^\d{4}-\d{2}-\d{2}$/.test(value))return;stopLiveMap();liveRoutes=[];liveAt=0;mapView?.destroy?.();mapView=null;planningDate=value;lastPlanning=0;loaded=false;plan=null;mapPoint='all';mapRoute='all';mapZoom=null;await open('planning')};x.querySelector('#tMetrics').onclick=()=>window.GamaTmsOperations?.metrics();x.querySelector('#tDayClose').onclick=()=>window.CocoTmsExecution.closure(day(),routesForDay(),()=>reload('today')).catch(e=>fail(e,'Cierre'));x.querySelector('#tAccess')?.addEventListener('click',()=>window.CocoTmsExecution.access().catch(e=>fail(e,'Roles TMS')));
 x.querySelectorAll('[data-tms-stage]').forEach(b=>b.onclick=()=>selectStage(b.dataset.tmsStage).catch(e=>fail(e,'No se pudo cargar la etapa')));
 if(selectedStage==='preparation')window.GamaPreparation?.mount(x.querySelector('#gamaPreparationHost'));
 if(selectedStage==='loading'){window.GamaLoading?.mount(x.querySelector('#gamaLoadingHost'));bindRouteMoves(x)}
 window.CocoTmsDispatch.bind(x,day(),routesForDay(),()=>reload('today'));
 if(selectedStage==='planning'){bindPlanning(x);bindRouteMoves(x);window.GamaTmsOperations?.costs(routesForDay(),x);window.GamaTmsOperations?.bind(x,()=>reload('today'))}
 x.querySelectorAll('[data-proof-view]').forEach(b=>b.onclick=()=>viewProofArchive(b.dataset.proofView));
 x.querySelectorAll('[data-proof-capture]').forEach(b=>b.onclick=()=>openProof(b.dataset.proofCapture));
 x.querySelectorAll('[data-proof-download]').forEach(b=>b.onclick=()=>downloadProofCertificate(b.dataset.proofDownload));
 x.querySelectorAll('[data-proof-mail]').forEach(b=>b.onclick=()=>emailProofCertificate(b.dataset.proofMail));
 const pp=x.querySelector('#tProofPdf');if(pp)pp.onclick=downloadProofReport;
 const po=x.querySelector('#tProofOne');if(po)po.onclick=()=>downloadProofCertificate(defaultProofId());
 const pm=x.querySelector('#tProofMail');if(pm)pm.onclick=()=>emailProofCertificate(defaultProofId());
 const sd=x.querySelector('#tSaveDepot');if(sd)sd.onclick=saveDepot;
 mountDiscussion(x,followDeliveryId);
}

async function mountDiscussion(root,id=null){
 const content=root.querySelector('.tms');if(!content)return;const first=content.firstElementChild;
 try{await window.ArcLoadScript('coco-order-followup.js');if(!content.isConnected||content.firstElementChild!==first)return;
  await window.CocoFollowup.wrap(content,{kind:'tms',order_id:id});const aside=content.querySelector(':scope>.cocoDossierWorkspace>aside');if(!aside)return;
  const label=document.createElement('label');label.className='cocoTmsDossierSelect';label.textContent=window.CocoTmsDispatch.t('Expediente','Dossier','Dossier');
  const select=document.createElement('select');select.setAttribute('aria-label',label.textContent);const options=[...new Map([...db.deliveries,...db.archive].map(d=>[d.id,d])).values()];
  select.innerHTML='<option value="">'+esc(window.CocoTmsDispatch.t('Propuestas del módulo','Propositions du module','Module proposals'))+'</option>'+options.map(d=>`<option value="${esc(d.id)}">${esc(d.reference||d.date)} · ${esc(d.customer)}</option>`).join('');select.value=id||'';
  select.onchange=async()=>{followDeliveryId=select.value||null;await window.CocoFollowup.mount(aside,{kind:'tms',order_id:followDeliveryId});aside.querySelector('.cocoFollowupBody')?.prepend(label)};label.append(select);aside.querySelector('.cocoFollowupBody')?.prepend(label);
 }catch(e){console.warn('[Coco dossier]',e)}
}
function wazeUrl(stop){if(!validPoint(stop)&&!String(stop?.address||'').trim())return '';const q=new URLSearchParams({navigate:'yes',utm_source:'coco_erp'});if(validPoint(stop))q.set('ll',Number(stop.lat)+','+Number(stop.lng));else q.set('q',stop.address.trim());return 'https://www.waze.com/ul?'+q}
function mapsUrl(r){const stops=routeStops(r),next=stops.find(d=>!d.isDepot&&!['Entregada','Cancelada'].includes(d.status))||stops.findLast(d=>d.isDepot);return next?wazeUrl(next):''}
async function openProof(id,camera=false){
 if(navigator.onLine){const ctx=await window.ArcData.rpc('gama_tms_execution',{p_action:'context',p_data:{delivery_id:id}});if(!ctx.lines.length||ctx.shipment?.loading_required&&!ctx.shipment.departed_at)return openLegacyProof(id,camera)}
 return window.CocoTmsExecution.open(id,{context:findDelivery(id)?.execution,onDone:()=>reload()});
}
async function openLegacyProof(id,camera=false){
 if(!driverView&&!await ready())return;
 const d=findDelivery(id);if(!d)return;
 await ensureProof(id);
 await renderProofDetail(id);if(camera)document.getElementById('tPhoto')?.click();
}
async function renderProofDetail(id){
 planningEpoch++;currentTab="capture";
 const d=findDelivery(id);if(!d)return;
 if(driverView&&!driverView.deliveries.some(d=>d.id===id))return;
 const pr=proofCache[id]||null;
 const x=section(),token=++proofViewVersion;
 window.ArcUI.render(x,'<div class="tms"><div class="arcPanel tmsCard" data-gi=35e67f1f9a74>Comprobando expedición y salida…</div></div>');
 let shipment;
 try{const r=await C().list('sales_deliveries',{select:'id,number,loading_required,departed_at',eq:{tms_delivery_id:id}});if(r.error)throw r.error;shipment=r.data?.[0]}
 catch(e){if(token!==proofViewVersion)return;window.ArcUI.render(x,'<div class="tms"><div class="arcPanel tmsCard"><p data-gi=4e84cc1d9091>No se pudo comprobar la salida. Reintenta antes de capturar la prueba.</p><button class="arcButton tmsBtn tmsPrimary" id="tProofRetry" data-gi=a9254c5f8128>Reintentar</button></div></div>');document.getElementById('tProofRetry').onclick=()=>renderProofDetail(id);return}
 if(token!==proofViewVersion)return;
 if(d.status==='Cancelada'||(shipment?.loading_required&&!shipment.departed_at)){
  window.ArcUI.render(x,`<div class="tms"><div class="arcPanel tmsCard"><h2><span data-gi=57e84386354a>Prueba de entrega · </span>${esc(shipment?.number||'TMS')}</h2><p>${esc(d.customer)} · ${esc(d.address)}</p><p>${esc(d.date)} · ${esc(d.status)}</p><p role="alert">${d.status==='Cancelada'?'Esta entrega está cancelada.':'La expedición todavía no tiene una salida validada. Completa el control de carga y confirma la salida antes de registrar la prueba de entrega.'}</p>${d.status!=='Cancelada'?'<button class="arcButton tmsBtn tmsPrimary" id="tProofLoading" data-gi=b248849c5097>Ir al control de carga</button>':''}<button class="arcButton tmsBtn tmsLight" id="tProofBack" data-gi=800d9ff7ca06>Volver a entregas</button><button class="arcButton tmsBtn tmsLight" id="tProofRetry" data-gi=a703a0bd6e25>Comprobar de nuevo</button></div></div>`);
  document.getElementById('tProofLoading')?.addEventListener('click',()=>window.GamaLoading.open(id));document.getElementById('tProofBack').onclick=()=>open('proof');document.getElementById('tProofRetry').onclick=()=>renderProofDetail(id);return;
 }
 window.ArcUI.render(x,`<div class="tms"><div class="gamaStdHeader" data-gama-standard-header="1"><div class="gamaStdText"><div class="gamaStdKicker" data-gi=24d49b8597db>Entrega</div><h2><span data-gi=57e84386354a>Prueba de entrega · </span>${esc(shipment?.number||'TMS')}</h2><p>${esc(d.customer)} · ${esc(d.address)}</p></div><div class="gamaStdActions"><button type="button" class="arcButton gamaStdAction" data-coco-click="tms-proof" data-gi=800d9ff7ca06>Volver a entregas</button></div></div><div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=48e238e6251d>Foto de entrega</b><small data-gi=27ecb8e519f0>Cámara del teléfono</small></div><input id="tPhoto" type="file" accept="image/*" capture="environment"><p class="muted" style="font-size:11px;margin:6px 0 0" data-gi=862e83493184>La foto se guarda automáticamente en la nube al tomarla o seleccionarla.</p><img id="tProofPhotoPreview" ${pr?.photo?'src="'+esc(pr.photo)+'"':'hidden'} style="max-width:100%;margin-top:10px;border-radius:8px"></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=0577d0e06a8e>Firma del cliente</b><small data-gi=c8e04813a369>Firma manuscrita</small></div><canvas id="tSig" class="tmsSig" width="700" height="300"></canvas><div style="margin-top:8px"><button class="arcButton tmsBtn tmsLight" id="tSigClear" data-gi=d50a3d446835>Borrar</button> <button class="arcButton tmsBtn tmsPrimary" id="tSigSave" data-gi=4133223d0626>Validar entrega</button></div></div></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=14f2e157ec34>Información de entrega</b></div><div class="tmsForm"><div><label data-gi=d740ee3e7961>Hora real de llegada</label><input value="${d.actualArrival?new Date(d.actualArrival).toLocaleString('es-ES'):'Se registrará al validar'}" disabled></div><div><label data-gi=756ac0b9183a>Hora de entrega</label><input value="${d.deliveredAt?new Date(d.deliveredAt).toLocaleString('es-ES'):'Por confirmar'}" disabled></div><div class="full"><label data-gi=59a5e76017bb>Notas del conductor</label><textarea id="tNotes" rows="3" data-gi-placeholder=f1a7364d9867 placeholder="Reserva, ausencia, observación…">${esc(d.notes||'')}</textarea></div></div><button class="arcButton tmsBtn tmsLight" id="tNotesSave" data-gi=8ef3a65da8e0>Guardar notas</button></div></div>`);
 setupSignature(document.getElementById('tSig'),d);
 document.getElementById('tPhoto').onchange=()=>captureProof(id);
 document.getElementById('tNotesSave').onclick=async()=>{
  const notes=document.getElementById('tNotes').value;
  try{await C().update('tms_deliveries',id,{notes});d.notes=notes;notify('Notas guardadas.')}
  catch(e){fail(e,'No se pudieron guardar las notas')}
 };
}
GamaPage.register('tmsProofs',()=>render('today'));
window.gamaTMS={coordinates:editCoordinates,navigationUrl:wazeUrl,openDelivery:async id=>{
 if(!window.gamaAccessAllowed?.('tms'))throw Error('Acceso no permitido.');
 await open('proof');const r=await C().list('tms_deliveries',{eq:{id}});if(r.error)throw r.error;if(!r.data?.[0])throw Error('Entrega no disponible.');
 db.deliveries=db.deliveries.filter(d=>d.id!==id).concat(r.data.map(delFrom));await openProof(id);
},open,openProof,openDriver:()=>open('driver'),__drivers:()=>db.drivers,viewProofArchive,downloadProofReport,downloadProofCertificate};
})();
