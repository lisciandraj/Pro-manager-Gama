/* GAMA TMS V4 — gestión de transporte: flujo diario, pantalla del conductor y pruebas de entrega.
   Los datos viven en Supabase (tms_*), no en el navegador: una prueba de entrega
   es un documento probatorio y debe sobrevivir a un borrado de caché. */
(function(){
'use strict';
const LOCAL_KEY='gama-tms-v1', MIGRATED_KEY='gama_tms_migrated_v1';
const ARCHIVE_LIMIT=200, PHOTO_MAX_PX=1280, PHOTO_QUALITY=0.72;
const C=()=>window.GamaCloud;
const readLocal=(k,f)=>{try{return JSON.parse(localStorage.getItem(k)||JSON.stringify(f))}catch(e){return f}};
const esc=window.ArcUI.esc;
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:window.GamaCompany?.get?.()?.timezone||'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),now=()=>new Date().toISOString();
let planningDate=today();const day=()=>planningDate;
const T=v=>window.GamaI18n?.t?.(v)||v;
let db={deliveries:[],drivers:[],routes:[],archive:[],proofIndex:[],proofDocuments:{},counts:{},settings:{},employees:[],absences:[],customers:[]};
let proofViewVersion=0;const gpsRequests=new Map();
function proofGps(id){if(!gpsRequests.has(id))gpsRequests.set(id,new Promise(resolve=>{if(!navigator.geolocation)return resolve({status:'unavailable'});navigator.geolocation.getCurrentPosition(p=>resolve({status:'captured',lat:p.coords.latitude,lng:p.coords.longitude,accuracy:p.coords.accuracy,at:new Date(p.timestamp).toISOString()}),e=>resolve({status:e.code===1?'denied':e.code===3?'timeout':'unavailable'}),{enableHighAccuracy:true,timeout:6000,maximumAge:0})}));return gpsRequests.get(id)}
let proofArchiveId=null,proofCache={},loaded=false,currentTab='today',selectedStage='planning',driverView=null,moveBusy=false,proofMetadataReady=false;
/* ---- mapeo cloud → forma interna (se conserva la del V3 para no tocar la UI) ---- */
/* Un recurso de reparto es un conductor de Flota con el vehículo que Flota le
   tiene asignado hoy. El TMS ya no guarda ni personas ni vehículos: los lee por
   gama_tms_resources, que devuelve sólo lo necesario para repartir. */
const drvFrom=r=>({id:r.driver_id,name:r.name,phone:r.phone||'',vehicle:r.plate||'',
 vehicleId:r.vehicle_id||null,vehicleStatus:r.vehicle_status||null,
 maxWeight:Number(r.max_weight||0),maxVolume:Number(r.max_volume||0),
 enabled:r.available===true,absent:r.absent===true,employeeId:r.employee_id||null});
const delFrom=r=>({id:r.id,reference:r.dossier_reference||r.erp_reference||'',customer:r.customer,address:r.address,customerId:r.customer_id||null,phone:r.phone||'',date:r.delivery_date,timeWindow:r.time_window||'',priority:r.priority||'Normal',weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Pendiente de preparación',lat:r.lat,lng:r.lng,routeId:r.route_id,driverId:r.driver_id,actualArrival:r.actual_arrival,deliveredAt:r.delivered_at,notes:r.notes||''});
const rtFrom=r=>({id:r.id,reference:r.erp_reference||'',date:r.route_date,driverId:r.driver_id,driver:r.driver_name||'',vehicle:r.vehicle||'',vehicleId:r.vehicle_id||null,stops:Array.isArray(r.stops)?r.stops:[],distance:Number(r.distance||0),weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Planificada',createdAt:r.created_at,version:r.version||1,costPerKm:r.cost_per_km??null,manual:r.manual_override===true});
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
async function pendingDeliveries(api){
 const data=[];
 for(let offset=0;;offset+=300){
  const r=await api.list('tms_deliveries',{in:{status:['Pendiente de preparación','Planificada','En carga','Lista para envío','En tránsito','En ruta','Excepción']},order:'id',ascending:true,range:[offset,offset+299]});
  if(r.error)throw r.error;
  const rows=r.data||[];data.push(...rows);if(rows.length<300)return data;
 }
}
async function fetchAll(){
 const sessionVersion=authEpoch;
 const api=C();if(!api)return;
 const t=day();
 const [drv,rt,del,st,pf,pending,counts]=await Promise.all([
  (async()=>{const c=await api.db();const r=await window.ArcData.rawRpc('gama_tms_resources');return r.error?{data:[],error:r.error}:{data:r.data||[]}})(),
  api.list('tms_routes',{eq:{route_date:t},order:'created_at',ascending:true}),
  api.list('tms_deliveries',{eq:{delivery_date:t},order:'created_at',ascending:true}),
  api.list('tms_settings',{limit:1}),
  // Sólo el índice: las fotos y firmas no viajan hasta que se abre una prueba.
  api.list('tms_proofs',{select:'delivery_id,captured_at,erp_reference',order:'captured_at',ascending:false,limit:ARCHIVE_LIMIT}),
  pendingDeliveries(api),
  window.ArcData.rawRpc('gama_tms_today_counts',{p_day:day()}),
 ]);
 if(sessionVersion!==authEpoch)throw Error('Session changed');
 for(const result of [rt,del,st])if(result.error)throw result.error;
 db.drivers=(drv.data||[]).map(drvFrom);
 db.driversError=drv.error?String(drv.error.message||drv.error):null;
 db.routes=(rt.data||[]).map(rtFrom);
 const routeIds=[...new Set(pending.filter(d=>d.delivery_date===t&&d.route_id&&!db.routes.some(r=>r.id===d.route_id)).map(d=>d.route_id))];if(routeIds.length){const extra=await api.list('tms_routes',{in:{id:routeIds}});if(extra.error)throw extra.error;db.routes.push(...(extra.data||[]).map(rtFrom))}
 db.deliveries=[...new Map([...(del.data||[]),...pending].map(d=>[d.id,d])).values()].map(delFrom);
 db.counts=counts.data||{};db.proofIndex=pf.data||[];proofMetadataReady=false;
 const s=(st.data||[])[0]||{};
 db.settings={depot:s.depot||'',returnDepot:s.return_depot!==false,depotPoint:(s.depot_lat!=null&&s.depot_lng!=null)?{id:'__depot',isDepot:true,address:s.depot||'Depósito',lat:s.depot_lat,lng:s.depot_lng}:null};
 const ids=(pf.data||[]).map(p=>p.delivery_id).filter(Boolean);
 if(ids.length){
  const arch=await api.list('tms_deliveries',{in:{id:ids},order:'delivered_at',ascending:false});
  db.archive=(arch.data||[]).map(delFrom);
 }else db.archive=[];
 await Promise.all([fetchHr(api,t),fetchCustomers(api)]);
}
/* Los clientes van aparte y sin propagar el error, igual que RRHH: si el rol
   no puede leerlos el desplegable se queda vacío y el transporte sigue
   funcionando con los campos escritos a mano. */
async function fetchCustomers(api){
 try{
  const r=await api.list('customers',{select:'id,name,address,email,phone,lat,lng,gps_address,active',order:'name',ascending:true});
  db.customers=r.error?[]:(r.data||[]).filter(c=>c.active!==false);
 }catch(e){db.customers=[]}
}
/* Fichas de empleado y ausencias que todavía no han terminado (las pasadas ya
   no afectan a ninguna ruta). Va aparte y sin propagar el error: si el rol no
   puede leer RRHH la lista vuelve vacía y el transporte sigue funcionando como
   antes, sin bloquear a nadie. */
async function fetchHr(api,t){
 try{
  const [emp,abs]=await Promise.all([
   api.list('hr_employees',{order:'full_name',ascending:true}),
   api.list('hr_absences',{gte:{end_date:t},order:'start_date',ascending:true}),
  ]);
  db.employees=emp.error?[]:(emp.data||[]);
  db.absences=abs.error?[]:(abs.data||[]);
 }catch(e){console.warn('[GAMA TMS] RRHH no disponible',e);db.employees=[];db.absences=[]}
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
 if(loaded)return true;
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
 const epoch=++planningEpoch;++proofViewVersion;styles();const x=showSection();
 window.ArcUI.render(x,'<div class="tms"><div class="tmsEmpty" role="status">'+esc(T('Cargando datos de transporte…'))+'</div></div>');
 if(tab==='driver'||(driverView&&tab==='proof')||(!tab&&window.matchMedia('(max-width: 767px)').matches)){
  try{const r=await window.ArcData.rawRpc('gama_tms_my_route');if(r.error)throw r.error;if(epoch!==planningEpoch)return;
   if(r.data?.driver||tab==='driver'){driverView={...r.data,routes:(r.data?.routes||[]).map(rtFrom),deliveries:(r.data?.deliveries||[]).map(delFrom)};currentTab='driver';renderDriver();return}
  }catch(e){if(tab==='driver'){fail(e,'No se pudo cargar la ruta');return}}
 }
 driverView=null;currentTab='today';selectedStage=['preparation','planning','loading','proof'].includes(tab)?tab:'planning';
 GamaPage.reset('tmsProofs');
 if(!await ready()||epoch!==planningEpoch)return;
 if(selectedStage==='proof')await proofMetadata();
 render('today');
 if(selectedStage==='planning')await autoPlanning(true);
}
function defaultProofId(){return archiveList().some(d=>d.id===proofArchiveId)?proofArchiveId:''}
function archiveList(){return db.archive.filter(d=>d.status==='Entregada').sort((a,b)=>String(b.deliveredAt||b.date).localeCompare(String(a.deliveredAt||a.date)))}
async function proofMetadata(){
 if(proofMetadataReady)return;const epoch=authEpoch,ids=db.proofIndex.map(p=>p.delivery_id);const docs={};
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
function routeStops(r){return(r.stops||[]).map(id=>id==='__depot'?{id:'__depot',customer:'Depósito',address:db.settings?.depot||'Depósito',isDepot:true,...(db.settings.depotPoint||{})}:db.deliveries.find(d=>d.id===id)).filter(Boolean)}
function status(d){return d.status||'Pendiente de preparación'}
/* Daily planning is one atomic, idempotent server operation. */
const WORDS={
 auto:['Planification automatique','Planificación automática','Automatic planning'],orders:['Les livraisons proviennent exclusivement des commandes.','Las entregas proceden exclusivamente de pedidos.','Deliveries come exclusively from orders.'],
 map:['Carte des livraisons du jour','Mapa de entregas del día','Today’s delivery map'],all:['Toutes les tournées','Todas las rutas','All routes'],refresh:['Actualiser','Actualizar','Refresh'],working:['Planification en cours…','Planificando…','Planning…'],
 missing:['Coordonnées manquantes','Coordenadas pendientes','Missing coordinates'],capacity:['Capacité ou conducteurs insuffisants','Capacidad o conductores insuficientes','Insufficient capacity or drivers'],fix:['Corriger les coordonnées','Corregir coordenadas','Correct coordinates'],
 legacy:['Historique sans commande liée','Histórico sin pedido enlazado','History without a linked order'],depot:['Coordonnées du dépôt manquantes : départ depuis la première livraison.','Sin coordenadas del depósito: salida desde la primera entrega.','Depot coordinates missing: start at first delivery.'],
 approx:['Ordre optimisé par proximité, priorité et capacité. Traits et distances à vol d’oiseau ; horaires à vérifier.','Orden por cercanía, prioridad y capacidad. Trazos y distancias en línea recta; verificar horarios.','Ordered by proximity, priority and capacity. Straight-line paths and distances; check time windows.'],
 none:['Aucune livraison géolocalisée.','No hay entregas geolocalizadas.','No geolocated deliveries.'],tiles:['Fond de carte indisponible. Les positions restent visibles.','Mapa de fondo no disponible. Las posiciones siguen visibles.','Map background unavailable. Positions remain visible.'],
 failed:['La planification a échoué. Réessayez.','La planificación falló. Reintenta.','Planning failed. Retry.'],invalid:['Coordonnées invalides.','Coordenadas inválidas.','Invalid coordinates.'],preserved:['L’historique local est conservé sur cet appareil et n’est pas importé sans commande liée.','El histórico local se conserva en este dispositivo y no se ha importado sin pedido enlazado.','Local history is retained on this device and is not imported without a linked order.'],
 planned:['Livraisons planifiées','Entregas planificadas','Planned deliveries'],save:['Enregistrer','Guardar','Save'],cancel:['Annuler','Cancelar','Cancel'],latitude:['Latitude','Latitud','Latitude'],longitude:['Longitude','Longitud','Longitude']};
const tr=k=>WORDS[k]?.[{fr:0,es:1,en:2}[window.GamaI18n?.language]??1]||k;
const validPoint=d=>d?.lat!=null&&d?.lng!=null&&Number.isFinite(+d.lat)&&Number.isFinite(+d.lng)&&Math.abs(+d.lat)<=85&&Math.abs(+d.lng)<=180;
let plan=null,planError='',planningJob=null,planningEpoch=0,lastPlanning=0,mapRoute='all',mapZoom=0,mapObserver=null,authEpoch=0;
const geoAttempts=new Set();let lastGeo=0;
const planningActive=()=>currentTab==='today'&&selectedStage==='planning'&&section().classList.contains('active')&&!!window.gamaAccessAllowed?.('tms');
async function coordinates(address){
 if(!address||geoAttempts.has(address))return null;
 geoAttempts.add(address);
 await new Promise(resolve=>setTimeout(resolve,Math.max(0,1100-(Date.now()-lastGeo))));lastGeo=Date.now();
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),4000);
 try{const r=await fetch('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=ec&q='+encodeURIComponent(address),{headers:{Accept:'application/json'},signal:controller.signal});if(!r.ok)return null;const results=await r.json(),p=results?.[0]?{lat:+results[0].lat,lng:+results[0].lon}:null;return validPoint(p)?p:null}catch(e){return null}finally{clearTimeout(timer)}
}
function markOrigins(){const ids=new Set(plan?.order_delivery_ids||[]);db.deliveries.forEach(d=>d.fromOrder=ids.has(d.id))}
async function autoPlanning(force=false){
 if(!planningActive()||planningJob||(!force&&Date.now()-lastPlanning<10000))return;
 const epoch=planningEpoch;lastPlanning=Date.now();planError='';
 const run=async()=>{
  try{
   await fetchAll();if(epoch!==planningEpoch||!planningActive())return;
   const r=await window.ArcData.rawRpc('gama_tms_plan_day',{p_day:day()});if(r.error)throw r.error;plan=r.data;markOrigins();
   if(epoch!==planningEpoch||!planningActive())return;
   render('today');let changed=false;
   if(!validPoint(db.settings.depotPoint)&&db.settings.depot){const p=await coordinates(db.settings.depot);if(p&&epoch===planningEpoch&&planningActive()){const u=await C().upsert('tms_settings',{id:true,depot_lat:p.lat,depot_lng:p.lng},{onConflict:'id'});if(u.error)throw u.error;changed=true}}
   for(const id of (plan.geocode_delivery_ids||[]).filter(id=>!geoAttempts.has(findDelivery(id)?.address)).slice(0,4)){
    if(epoch!==planningEpoch||!planningActive())return;
    const d=findDelivery(id),p=await coordinates(d?.address);
    if(p&&epoch===planningEpoch&&planningActive()){const u=await window.ArcData.rawRpc('gama_tms_save_gps',{p_data:{delivery_id:id,...p}});if(u.error)throw u.error;changed=true}
   }
   if(epoch!==planningEpoch||!planningActive())return;
   if(changed){const r=await window.ArcData.rawRpc('gama_tms_plan_day',{p_day:day()});if(r.error)throw r.error;plan=r.data}
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
 return `<div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(tr('auto'))} · ${esc(plan?.today||day())}</b><button type="button" class="arcButton tmsBtn tmsLight" id="tRefresh"${planningJob?' disabled':''}>${esc(planningJob?tr('working'):tr('refresh'))}</button></div><p>${esc(tr('orders'))}</p><div role="status" id="tPlanStatus">${plan?`${esc(tr('planned'))}: ${plan.planned} / ${plan.total}`:''}</div>${planError?`<p role="alert" class="tmsAbsente">${esc(planError)}</p>`:''}${avisoAusencias()}${plan?.without_capacity?`<p class="tmsAbsente">${esc(tr('capacity'))}: ${plan.without_capacity}</p>`:''}${plan?.depot_missing?`<p class="tmsHint">${esc(tr('depot'))}</p>`:''}</div>
 <div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(tr('map'))}</b><div class="tmsMapTools"><select id="tMapRoute" aria-label="${esc(tr('all'))}"><option value="all">${esc(tr('all'))}</option>${routes.map(r=>`<option value="${esc(r.id)}"${mapRoute===r.id?' selected':''}>${esc(r.reference||r.driver||r.id)}</option>`).join('')}</select><button type="button" class="arcButton tmsBtn" id="tMapOut" aria-label="Zoom −">−</button><button type="button" class="arcButton tmsBtn" id="tMapIn" aria-label="Zoom +">+</button><button type="button" class="arcButton tmsBtn" id="tMapFit">↔</button></div></div><div id="tDayMap" class="tmsDayMap" aria-label="${esc(tr('map'))}"></div><p id="tMapError" class="tmsHint" hidden>${esc(tr('tiles'))}</p><small>© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a></small><p class="tmsHint">${esc(tr('approx'))}</p>${missing.length?`<p class="tmsAbsente">${esc(tr('missing'))}: ${missing.length}</p>`:''}</div>
 <div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(T('Entregas de hoy'))}</b><small>${ds.length}</small></div><div class="tmsTableScroll"><table class="arcTable tmsTable"><thead><tr><th>${esc(T('Cliente'))}</th><th>${esc(T('Carga'))}</th><th>${esc(T('Estado'))}</th></tr></thead><tbody>${ds.map(d=>`<tr id="tms-delivery-${esc(d.id)}" tabindex="-1"><td><b>${esc(d.reference||'')} ${esc(d.customer)}</b><br><small>${esc(d.address)} · ${esc(d.timeWindow||'—')}</small></td><td>${d.weight} kg / ${d.volume} m³</td><td>${badge(d)}<br><button type="button" class="arcButton secondary" data-tms-operate="${esc(d.id)}">${esc(T('Gestionar entrega'))}</button>${d.fromOrder?`<br><button type="button" class="arcButton tmsBtn tmsLight" data-tms-coordinates="${esc(d.id)}"${planningJob?' disabled':''}>${esc(tr('fix'))}</button><br><button type="button" class="arcButton tmsBtn tmsLight" data-tms-loading="${esc(d.id)}">${esc(T('Salida de bultos'))}</button>`:`<br><small>${esc(tr('legacy'))}</small>`}</td></tr>`).join('')}</tbody></table></div></div>
 <div><div class="arcPanel tmsCard">${routes.map(routeCard).join('')||`<div class="tmsEmpty">${esc(T('No hay rutas planificadas.'))}</div>`}</div>
 <details class="arcPanel tmsCard"><summary>${esc(T('Configuración avanzada del depósito'))}</summary><div class="tmsForm"><div class="full"><label>${esc(T('Dirección del depósito'))}</label><input id="tDepot" value="${esc(db.settings.depot||'')}"></div><div><label for="tDepotLat">${esc(tr('latitude'))}</label><input id="tDepotLat" type="number" step="any" min="-85" max="85" value="${esc(db.settings.depotPoint?.lat??'')}"></div><div><label for="tDepotLng">${esc(tr('longitude'))}</label><input id="tDepotLng" type="number" step="any" min="-180" max="180" value="${esc(db.settings.depotPoint?.lng??'')}"></div><div><label>${esc(T('Regreso al depósito'))}</label><select id="tReturn"><option value="1"${db.settings.returnDepot?' selected':''}>${esc(T('Sí'))}</option><option value="0"${!db.settings.returnDepot?' selected':''}>${esc(T('No'))}</option></select></div></div><button type="button" class="arcButton tmsBtn" id="tSaveDepot"${planningJob?' disabled':''}>${esc(tr('save'))}</button></details></div></div>`;
}
function drawDayMap(){
 const host=document.getElementById('tDayMap');if(!host)return;
 const routes=routesForDay().filter(r=>mapRoute==='all'||mapRoute===r.id);
 const selected=new Set(routes.flatMap(r=>r.stops));
 const points=db.deliveries.filter(d=>d.date===day()&&d.fromOrder&&validPoint(d)&&(mapRoute==='all'||selected.has(d.id)));
 const depot=db.settings.depotPoint;if(validPoint(depot))points.push({...depot,isDepot:true,customer:db.settings.depot});
 if(!points.length){host.innerHTML=`<p class="tmsEmpty">${esc(tr('none'))}</p>`;return}
 const width=Math.max(240,host.clientWidth),height=380;
 const project=(d,z)=>{const n=256*2**z,s=Math.sin(+d.lat*Math.PI/180);return{x:(+d.lng+180)/360*n,y:(.5-Math.log((1+s)/(1-s))/(4*Math.PI))*n}};
 let base=14;
 for(;base>2;base--){const p=points.map(d=>project(d,base));if(Math.max(...p.map(v=>v.x))-Math.min(...p.map(v=>v.x))<width-80&&Math.max(...p.map(v=>v.y))-Math.min(...p.map(v=>v.y))<height-80)break}
 const z=Math.max(2,Math.min(18,base+mapZoom)),p=points.map(d=>project(d,z));
 const left=(Math.min(...p.map(v=>v.x))+Math.max(...p.map(v=>v.x)))/2-width/2,top=(Math.min(...p.map(v=>v.y))+Math.max(...p.map(v=>v.y)))/2-height/2;
 const pos=d=>{const v=project(d,z);return{x:v.x-left,y:v.y-top}};let tiles='';
 for(let x=Math.floor(left/256);x<=Math.floor((left+width)/256);x++)for(let y=Math.floor(top/256);y<=Math.floor((top+height)/256);y++)if(x>=0&&y>=0&&x<2**z&&y<2**z)tiles+=`<image x="${x*256-left}" y="${y*256-top}" width="256" height="256" href="https://tile.openstreetmap.org/${z}/${x}/${y}.png"/>`;
 const colors=['#0f766e','#2563eb','#c2410c','#7c3aed'];
 const lines=routes.map((r,i)=>{const s=routeStops(r).filter(validPoint);return `<polyline points="${s.map(d=>{const v=pos(d);return v.x+','+v.y}).join(' ')}" fill="none" stroke="${colors[i%colors.length]}" stroke-width="4" opacity=".8"/>`}).join('');
 const markers=points.map(d=>{const v=pos(d),r=routes.find(r=>r.stops.includes(d.id)),index=r?r.stops.filter(id=>id!=='__depot').indexOf(d.id)+1:'•';return `<g transform="translate(${v.x},${v.y})"${d.isDepot?'':` role="button" tabindex="0" data-map-delivery="${esc(d.id)}" aria-label="${esc(d.customer)}"`}><title>${esc(d.customer||'Depósito')} · ${esc(d.address||'')}</title><circle r="13" fill="${d.isDepot?'#334155':r?colors[routes.indexOf(r)%colors.length]:'#b45309'}" stroke="white" stroke-width="2"/><text text-anchor="middle" y="4" fill="white" font-size="12" font-weight="700">${d.isDepot?'D':index}</text></g>`}).join('');
 host.innerHTML=`<svg viewBox="0 0 ${width} ${height}" role="group" aria-label="${esc(tr('map'))}">${tiles}${lines}${markers}</svg>`;
 host.querySelectorAll('image').forEach(img=>img.addEventListener('error',()=>{img.remove();const e=document.getElementById('tMapError');if(e)e.hidden=false}));
 host.querySelectorAll('[data-map-delivery]').forEach(marker=>{const jump=()=>document.getElementById('tms-delivery-'+marker.dataset.mapDelivery)?.focus();marker.addEventListener('click',jump);marker.addEventListener('keydown',e=>{if(['Enter',' '].includes(e.key)){e.preventDefault();jump()}})});
}
function editCoordinates(id){
 const d=findDelivery(id);if(!d?.fromOrder)return;
 const dlg=document.createElement('dialog');dlg.className='tmsCoordinateDialog';
 dlg.innerHTML=`<form><h3>${esc(tr('fix'))}</h3><p>${esc(d.customer)} · ${esc(d.address)}</p><label>${esc(tr('latitude'))}<input name="lat" type="number" step="any" min="-85" max="85" required value="${esc(d.lat??'')}"></label><label>${esc(tr('longitude'))}<input name="lng" type="number" step="any" min="-180" max="180" required value="${esc(d.lng??'')}"></label><p role="alert"></p><button type="submit" class="arcButton">${esc(tr('save'))}</button><button type="button" class="arcButton" data-close>${esc(tr('cancel'))}</button></form>`;
 document.body.appendChild(dlg);dlg.showModal();dlg.addEventListener('close',()=>dlg.remove());dlg.querySelector('[data-close]').onclick=()=>dlg.close();
 dlg.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,p={lat:Number(f.elements.lat.value),lng:Number(f.elements.lng.value)};if(!validPoint(p)){f.querySelector('[role=alert]').textContent=tr('invalid');return}const b=f.querySelector('[type=submit]');b.disabled=true;try{const r=await window.ArcData.rawRpc('gama_tms_save_gps',{p_data:{delivery_id:id,...p}});if(r.error)throw r.error;dlg.close();notify(r.data?.customer_saved?'GPS guardado en la ficha del cliente.':'GPS guardado para esta entrega.','exito');await autoPlanning(true)}catch(error){f.querySelector('[role=alert]').textContent=T(tmsError(error));b.disabled=false}};
}
function bindPlanning(x){
 x.querySelector('#tRefresh').onclick=()=>{geoAttempts.clear();autoPlanning(true)};
 x.querySelector('#tMapRoute').onchange=e=>{mapRoute=e.target.value;mapZoom=0;drawDayMap()};
 x.querySelector('#tMapIn').onclick=()=>{mapZoom=Math.min(4,mapZoom+1);drawDayMap()};x.querySelector('#tMapOut').onclick=()=>{mapZoom=Math.max(-4,mapZoom-1);drawDayMap()};x.querySelector('#tMapFit').onclick=()=>{mapZoom=0;drawDayMap()};
 x.querySelectorAll('[data-tms-coordinates]').forEach(b=>b.onclick=()=>editCoordinates(b.dataset.tmsCoordinates));
 x.querySelectorAll('[data-tms-loading]').forEach(b=>b.onclick=()=>window.GamaLoading.open(b.dataset.tmsLoading));
 drawDayMap();mapObserver?.disconnect();let width=x.querySelector('#tDayMap').clientWidth;
 if(window.ResizeObserver){mapObserver=new ResizeObserver(entries=>{if(entries[0].contentRect.width!==width){width=entries[0].contentRect.width;drawDayMap()}});mapObserver.observe(x.querySelector('#tDayMap'))}
}
setInterval(()=>{if(document.visibilityState==='visible')autoPlanning()},45000);
window.addEventListener('focus',()=>autoPlanning());
window.addEventListener('gama:language-change',()=>{if(currentTab==='driver')renderDriver();else if(currentTab==='today')render('today')});
window.addEventListener('gama:data-change',()=>{if(planningActive()&&!planningJob)autoPlanning()});
window.addEventListener('gama:sales-change',()=>autoPlanning());
window.addEventListener('arc:route-leave',()=>{planningEpoch++;mapObserver?.disconnect()});
window.addEventListener('gama:auth-change',()=>{planningEpoch++;authEpoch++;currentTab="";loaded=false;proofCache={};gpsRequests.clear();proofArchiveId=null;driverView=null;proofMetadataReady=false;plan=null;mapObserver?.disconnect();geoAttempts.clear();db={deliveries:[],drivers:[],routes:[],archive:[],proofIndex:[],proofDocuments:{},counts:{},settings:{},employees:[],absences:[],customers:[]}});

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
   body:'Estimado/a '+(d.customer||'cliente')+',\n\nAdjuntamos el comprobante de la entrega realizada el '+legible+' en '+(d.address||'')+'.'+(conductor?'\nTransportista: '+conductor+'.':'')+'\n\nQuedamos a su disposición para cualquier consulta.\n\nGAMA Enterprise Resource Planning',
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
  const doc=window.GamaPdf.proofReport(filas,'Pruebas de entrega — Coco ERP');
  window.GamaPdf.save(doc,window.GamaPdf.fileName('pruebas-entrega',new Date().toISOString().slice(0,10)));
 }catch(e){console.error('[GAMA PDF pruebas]',e);notify('No se pudo generar el informe: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
async function saveDepot(){
 const x=section(),address=x.querySelector('#tDepot').value.trim(),lat=x.querySelector('#tDepotLat').value,lng=x.querySelector('#tDepotLng').value;
 if((lat!==''||lng!=='')&&(!lat||!lng||!validPoint({lat,lng})))return notify(tr('invalid'));
 try{const r=await C().upsert('tms_settings',{id:true,depot:address||null,depot_lat:lat===''?null:Number(lat),depot_lng:lng===''?null:Number(lng),return_depot:x.querySelector('#tReturn').value==='1',updated_at:now()},{onConflict:'id'});if(r.error)throw r.error;geoAttempts.delete(address);await autoPlanning(true)}catch(e){fail(e,'No se pudieron guardar los parámetros')}
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
 return `<div class="tmsRoute" data-route-drop="${esc(r.id)}"><div class="tmsRouteHead"><b>${[r.reference,r.driver,r.vehicle].filter(Boolean).map(esc).join(' · ')}</b><small>${r.distance.toFixed(1)} km · ${r.weight} kg · ${r.volume} m³</small></div><p>${esc(T(r.status))}${r.manual?` · <span class="tmsBadge tmsStatus-planned">${esc(T('Ajustada manualmente'))}</span>`:''}</p>
 <ol class="tmsStops">${stops.map((d,i)=>`<li data-route-stop="${esc(d.id)}" data-route-id="${esc(r.id)}" draggable="${editable}" class="tmsEditableStop"><div><b>${esc(d.reference)} ${esc(d.customer)}</b><small>${esc(d.address)}</small>${badge(d)}</div>${editable?`<div class="tmsStopTools"><button class="arcButton secondary" data-stop-up="${esc(d.id)}" aria-label="${esc(T('Subir parada'))}"${i?'':' disabled'}>↑</button><button class="arcButton secondary" data-stop-down="${esc(d.id)}" aria-label="${esc(T('Bajar parada'))}"${i<stops.length-1?'':' disabled'}>↓</button><select data-stop-target="${esc(d.id)}" aria-label="${esc(T('Mover a otra ruta'))}"><option value="">${esc(T('Mover a otra ruta'))}</option>${db.routes.filter(x=>x.id!==r.id&&editableRoute(x)&&x.date===r.date).map(x=>`<option value="${esc(x.id)}">${esc(x.reference||x.driver)}</option>`).join('')}</select></div>`:''}</li>`).join('')}</ol><a class="arcButton tmsBtn tmsLight" href="${esc(mapsUrl(r))}" target="_blank" rel="noopener noreferrer">Google Maps</a></div>`;
}
async function moveStop(id,targetId,beforeId=null){
 if(moveBusy||planningJob)return;const d=findDelivery(id),source=db.routes.find(r=>r.id===d?.routeId),target=db.routes.find(r=>r.id===targetId);if(!source||!target)return;
 moveBusy=true;render();try{const r=await window.ArcData.rawRpc('gama_tms_move_stop',{p_data:{delivery_id:id,target_route_id:targetId,before_stop_id:beforeId,source_version:source.version,target_version:target.version,day:day()}});if(r.error)throw r.error;await fetchAll();markOrigins();notify('Ruta actualizada.','exito')}
 catch(e){notify(tmsError(e),'error');await fetchAll()}finally{moveBusy=false;render()}
}
function bindRouteMoves(x){
 x.querySelectorAll('[data-stop-up],[data-stop-down]').forEach(b=>b.onclick=()=>{const id=b.dataset.stopUp||b.dataset.stopDown,d=findDelivery(id),r=db.routes.find(r=>r.id===d?.routeId),ids=routeStops(r).filter(d=>!d.isDepot).map(d=>d.id),i=ids.indexOf(id);moveStop(id,r.id,b.dataset.stopUp?ids[i-1]:ids[i+2]||null)});
 x.querySelectorAll('[data-stop-target]').forEach(s=>s.onchange=()=>{if(s.value)moveStop(s.dataset.stopTarget,s.value)});
 x.querySelectorAll('[data-route-stop]').forEach(li=>li.ondragstart=e=>{if(li.draggable)e.dataTransfer.setData('text/plain',li.dataset.routeStop)});
 x.querySelectorAll('[data-route-drop]').forEach(host=>{host.ondragover=e=>{const r=db.routes.find(r=>r.id===host.dataset.routeDrop);if(editableRoute(r)&&!planningJob&&!moveBusy){e.preventDefault();e.dataTransfer.dropEffect='move'}};host.ondrop=e=>{e.preventDefault();const id=e.dataTransfer.getData('text/plain'),before=e.target.closest('[data-route-stop]')?.dataset.routeStop;if(id&&id!==before)moveStop(id,host.dataset.routeDrop,before||null)}});
}
function renderDriver(){
 currentTab='driver';const x=section(),data=driverView||{routes:[],deliveries:[]},lookup=id=>data.deliveries.find(d=>d.id===id);
 window.ArcUI.render(x,`<div class="tms tmsDriver">${window.GamaUI.header({title:'Mi ruta',lead:data.driver?.name||'No hay un conductor vinculado a tu cuenta.'})}<p>${esc(window.ArcFormat.date(today()))}</p><button class="arcButton secondary" id="tDriverRefresh">${esc(T('Actualizar'))}</button>
 ${data.routes.map(r=>`<div class="arcPanel tmsCard"><h2>${esc(r.reference||T('Ruta'))} · ${esc(r.vehicle)}</h2><ol class="tmsDriverStops">${r.stops.map(lookup).filter(Boolean).map(d=>`<li><div class="tmsDriverStop"><div class="tmsRouteHead"><b>${esc(d.reference)} ${esc(d.customer)}</b>${badge(d)}</div><p>${esc(d.address)}</p><div class="tmsDriverActions"><a class="arcButton secondary" href="https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(validPoint(d)?d.lat+','+d.lng:d.address)}&travelmode=driving" target="_blank" rel="noopener noreferrer">${esc(T('Navegar'))}</a>${d.phone?`<a class="arcButton secondary" href="tel:${esc(d.phone.replace(/[^+0-9]/g,''))}">${esc(T('Llamar'))}</a>`:`<button class="arcButton secondary" disabled>${esc(T('Sin teléfono'))}</button>`}<button class="arcButton primary" data-driver-delivered="${esc(d.id)}"${d.status==='Entregada'?' disabled':''}>${esc(T(d.status==='Entregada'?'Entregada':'Entregado'))}</button></div>${d.status==='Entregada'?'':`<button class="arcButton secondary tmsDriverMore" data-tms-operate="${esc(d.id)}">${esc(T('Aviso, incidencia o cobro'))}</button>`}</div></li>`).join('')}</ol></div>`).join('')||`<p class="tmsEmpty">${esc(T('No tienes una ruta asignada.'))}</p>`}</div>`);
 window.GamaUI.bindBack(x);x.querySelector('#tDriverRefresh').onclick=()=>open('driver');
 x.querySelectorAll('[data-driver-delivered]').forEach(b=>b.onclick=()=>openProof(b.dataset.driverDelivered,true).catch(e=>fail(e,'No se pudo abrir la entrega')));
 window.GamaTmsOperations?.bind(x,()=>open('driver'));
}

function proofBody(){
 const rows=[...new Map([...db.deliveries.filter(d=>!['Entregada','Cancelada'].includes(d.status)),...archiveList()].map(d=>[d.id,d])).values()]
  .sort((a,b)=>String(b.deliveredAt||b.date).localeCompare(String(a.deliveredAt||a.date))||a.id.localeCompare(b.id));
 const keys={date:d=>d.deliveredAt||db.proofIndex.find(p=>p.delivery_id===d.id)?.captured_at||d.date,partner:proofPartner,reference:proofReference,status:status};
 const selected=archiveList().find(d=>d.id===defaultProofId()),pr=selected?proofCache[selected.id]:null;
 return `<div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(T('Pruebas de entrega'))}</b><small>${rows.length}</small>${archiveList().length?`<button class="arcButton secondary" id="tProofPdf">${esc(T('Descargar informe PDF'))}</button>`:''}</div>
 <div class="tmsTableScroll"><table class="arcTable tmsTable" id="tProofTable" data-gama-sort-key="tmsProofs"><thead><tr>${GamaSort.th('tmsProofs','date',T('Fecha'))}${GamaSort.th('tmsProofs','partner',T('Cliente / proveedor'))}${GamaSort.th('tmsProofs','reference',T('Referencia'))}${GamaSort.th('tmsProofs','status',T('Estado'))}<th>${esc(T('Acciones'))}</th></tr></thead><tbody>${GamaPage.slice('tmsProofs',rows,keys).map(d=>`<tr data-proof-row="${esc(d.id)}"><td>${esc(window.ArcFormat.date(keys.date(d)))}</td><td><b>${esc(proofPartner(d))}</b><br><small>${esc(d.address)}</small></td><td>${esc(proofReference(d))}</td><td>${badge(d)}</td><td><div class="tmsProofActions">${status(d)==='Entregada'?`<button class="arcButton secondary" data-proof-view="${esc(d.id)}">${esc(T('Ver'))}</button><button class="arcButton primary" data-proof-download="${esc(d.id)}">${esc(T('Descargar'))}</button><button class="arcButton secondary" data-proof-mail="${esc(d.id)}">${esc(T('Enviar'))}</button>`:`<button class="arcButton primary" data-proof-capture="${esc(d.id)}">${esc(T('Abrir prueba de entrega'))}</button>`}</div></td></tr>`).join('')||`<tr><td colspan="5">${esc(T('No hay entregas.'))}</td></tr>`}</tbody></table></div>${GamaPage.controls('tmsProofs',rows.length)}
 ${selected&&pr?`<div id="tProofPreview"><h3>${esc(proofReference(selected))} · ${esc(selected.customer)}</h3><div class="tmsProof">${pr.photo?`<img alt="${esc(T('Foto de entrega'))}" src="${esc(pr.photo)}">`:''}${pr.signature?`<img alt="${esc(T('Firma del cliente'))}" src="${esc(pr.signature)}">`:''}</div><p>${esc(selected.notes||'')}</p><button class="arcButton primary" id="tProofOne">${esc(T('Descargar comprobante de esta entrega'))}</button> <button class="arcButton secondary" id="tProofMail">${esc(T('Enviar el comprobante al cliente'))}</button></div>`:''}</div>`;
}
const STAGES=[['preparation','Preparar','por preparar'],['planning','Planificar','por planificar'],['loading','Cargar','por cargar'],['proof','Entregar','por entregar']];
async function selectStage(key){selectedStage=key;currentTab='today';++proofViewVersion;render('today');if(key==='proof'){await proofMetadata();if(selectedStage===key)render('today')}if(key==='planning')await autoPlanning(true);document.getElementById('tms-stage-'+key)?.scrollIntoView({block:'start',behavior:'smooth'})}
function render(){
 if(driverView&&currentTab==='driver')return renderDriver();
 ++proofViewVersion;currentTab='today';const x=section(),ds=db.deliveries.filter(d=>d.date===day());
 window.ArcUI.render(x,`<div class="tms">${window.GamaUI.header({title:day()===today()?'TMS · Hoy':'TMS · Planificación',lead:'Preparar → Planificar → Cargar → Entregar'})}
 <div class="tmsTodayBar"><p>${esc(window.ArcFormat.date(day()))} · ${ds.filter(d=>d.status==='Entregada').length} ${esc(T('entregadas'))}${db.counts.incidents?` · <span class="tmsBadge tmsStatus-incident">${db.counts.incidents} ${esc(T('incidentes'))}</span>`:''}</p><button type="button" class="arcButton secondary" id="tMyRoute">${esc(T('Mi ruta'))}</button><label>${esc(T('Fecha de planificación'))}<input id="tPlanningDay" type="date" min="${today()}" value="${esc(day())}"></label><button class="arcButton secondary" id="tMetrics">${esc(T('Indicadores'))}</button></div>
 <nav class="tmsFlow" aria-label="${esc(T('Flujo de entregas'))}">${STAGES.map(([id,label,hint],i)=>`<button type="button" class="tmsFlowStep ${selectedStage===id?'active':''}" data-tms-stage="${id}" aria-expanded="${selectedStage===id}" aria-controls="tms-stage-${id}"><span>${i+1}. ${esc(T(label))}</span><strong>${Number(db.counts[id]||0)}</strong><small>${esc(T(hint))}</small></button>`).join('')}</nav>
 ${STAGES.map(([id,label])=>`<section class="tmsStage" id="tms-stage-${id}"${selectedStage===id?'':' hidden'} aria-label="${esc(T(label))}">${id==='planning'?planningBody(ds):id==='proof'?proofBody():`<div id="${id==='preparation'?'gamaPreparationHost':'gamaLoadingHost'}"></div>`}</section>`).join('')}</div>`);
 window.GamaUI.bindBack(x);x.querySelector('#tMyRoute').onclick=()=>open('driver');x.querySelector('#tPlanningDay').onchange=async e=>{const value=e.target.value;if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||value<today())return;planningDate=value;loaded=false;plan=null;geoAttempts.clear();await open('planning')};x.querySelector('#tMetrics').onclick=()=>window.GamaTmsOperations?.metrics();
 x.querySelectorAll('[data-tms-stage]').forEach(b=>b.onclick=()=>selectStage(b.dataset.tmsStage).catch(e=>fail(e,'No se pudo cargar la etapa')));
 if(selectedStage==='preparation')window.GamaPreparation?.mount(x.querySelector('#gamaPreparationHost'));
 if(selectedStage==='loading')window.GamaLoading?.mount(x.querySelector('#gamaLoadingHost'));
 if(selectedStage==='planning'){bindPlanning(x);bindRouteMoves(x);window.GamaTmsOperations?.costs(routesForDay(),x);window.GamaTmsOperations?.bind(x,()=>reload('today'))}
 x.querySelectorAll('[data-proof-view]').forEach(b=>b.onclick=()=>viewProofArchive(b.dataset.proofView));
 x.querySelectorAll('[data-proof-capture]').forEach(b=>b.onclick=()=>openProof(b.dataset.proofCapture));
 x.querySelectorAll('[data-proof-download]').forEach(b=>b.onclick=()=>downloadProofCertificate(b.dataset.proofDownload));
 x.querySelectorAll('[data-proof-mail]').forEach(b=>b.onclick=()=>emailProofCertificate(b.dataset.proofMail));
 const pp=x.querySelector('#tProofPdf');if(pp)pp.onclick=downloadProofReport;
 const po=x.querySelector('#tProofOne');if(po)po.onclick=()=>downloadProofCertificate(defaultProofId());
 const pm=x.querySelector('#tProofMail');if(pm)pm.onclick=()=>emailProofCertificate(defaultProofId());
 const sd=x.querySelector('#tSaveDepot');if(sd)sd.onclick=saveDepot;
}
function mapsUrl(r){const s=routeStops(r),valid=s.filter(x=>!x.isDepot||x.address);if(valid.length<2)return '#';const o=encodeURIComponent(valid[0].address),dest=encodeURIComponent(valid[valid.length-1].address),wp=valid.slice(1,-1).map(x=>encodeURIComponent(x.address)).join('|');return'https://www.google.com/maps/dir/?api=1&origin='+o+'&destination='+dest+(wp?'&waypoints='+wp:'')+'&travelmode=driving'}
async function openProof(id,camera=false){
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
 window.ArcUI.render(x,`<div class="tms"><div class="gamaStdHeader" data-gama-standard-header="1"><div class="gamaStdText"><div class="gamaStdKicker" data-gi=24d49b8597db>Entrega</div><h2><span data-gi=57e84386354a>Prueba de entrega · </span>${esc(shipment?.number||'TMS')}</h2><p>${esc(d.customer)} · ${esc(d.address)}</p></div><div class="gamaStdActions"><button type="button" class="arcButton gamaStdAction" onclick="gamaTMS.open('proof')" data-gi=800d9ff7ca06>Volver a entregas</button></div></div><div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=48e238e6251d>Foto de entrega</b><small data-gi=27ecb8e519f0>Cámara del teléfono</small></div><input id="tPhoto" type="file" accept="image/*" capture="environment"><p class="muted" style="font-size:11px;margin:6px 0 0" data-gi=862e83493184>La foto se guarda automáticamente en la nube al tomarla o seleccionarla.</p><img id="tProofPhotoPreview" ${pr?.photo?'src="'+esc(pr.photo)+'"':'hidden'} style="max-width:100%;margin-top:10px;border-radius:8px"></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=0577d0e06a8e>Firma del cliente</b><small data-gi=c8e04813a369>Firma manuscrita</small></div><canvas id="tSig" class="tmsSig" width="700" height="300"></canvas><div style="margin-top:8px"><button class="arcButton tmsBtn tmsLight" id="tSigClear" data-gi=d50a3d446835>Borrar</button> <button class="arcButton tmsBtn tmsPrimary" id="tSigSave" data-gi=4133223d0626>Validar entrega</button></div></div></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=14f2e157ec34>Información de entrega</b></div><div class="tmsForm"><div><label data-gi=d740ee3e7961>Hora real de llegada</label><input value="${d.actualArrival?new Date(d.actualArrival).toLocaleString('es-ES'):'Se registrará al validar'}" disabled></div><div><label data-gi=756ac0b9183a>Hora de entrega</label><input value="${d.deliveredAt?new Date(d.deliveredAt).toLocaleString('es-ES'):'Por confirmar'}" disabled></div><div class="full"><label data-gi=59a5e76017bb>Notas del conductor</label><textarea id="tNotes" rows="3" data-gi-placeholder=f1a7364d9867 placeholder="Reserva, ausencia, observación…">${esc(d.notes||'')}</textarea></div></div><button class="arcButton tmsBtn tmsLight" id="tNotesSave" data-gi=8ef3a65da8e0>Guardar notas</button></div></div>`);
 setupSignature(document.getElementById('tSig'),d);
 document.getElementById('tPhoto').onchange=()=>captureProof(id);
 document.getElementById('tNotesSave').onclick=async()=>{
  const notes=document.getElementById('tNotes').value;
  try{await C().update('tms_deliveries',id,{notes});d.notes=notes;notify('Notas guardadas.')}
  catch(e){fail(e,'No se pudieron guardar las notas')}
 };
}
GamaPage.register('tmsProofs',()=>render('today'));
window.gamaTMS={openDelivery:async id=>{
 if(!window.gamaAccessAllowed?.('tms'))throw Error('Acceso no permitido.');
 await open('proof');const r=await C().list('tms_deliveries',{eq:{id}});if(r.error)throw r.error;if(!r.data?.[0])throw Error('Entrega no disponible.');
 db.deliveries=db.deliveries.filter(d=>d.id!==id).concat(r.data.map(delFrom));await ensureProof(id);await renderProofDetail(id);if(camera)document.getElementById('tPhoto')?.click();
},open,openProof,openDriver:()=>open('driver'),__drivers:()=>db.drivers,viewProofArchive,downloadProofReport,downloadProofCertificate};
})();
