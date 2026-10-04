/* GAMA TMS V4 — gestión de transporte: planificación, conductores, POD, historial.
   Los datos viven en Supabase (tms_*), no en el navegador: una prueba de entrega
   es un documento probatorio y debe sobrevivir a un borrado de caché. */
(function(){
'use strict';
const LOCAL_KEY='gama-tms-v1', MIGRATED_KEY='gama_tms_migrated_v1';
const HISTORY_LIMIT=200, ARCHIVE_LIMIT=200, PHOTO_MAX_PX=1280, PHOTO_QUALITY=0.72;
const C=()=>window.GamaCloud;
const readLocal=(k,f)=>{try{return JSON.parse(localStorage.getItem(k)||JSON.stringify(f))}catch(e){return f}};
const esc=window.ArcUI.esc;
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:window.GamaCompany?.get?.()?.timezone||'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),now=()=>new Date().toISOString();
const T=v=>window.GamaI18n?.t?.(v)||v;
let db={deliveries:[],drivers:[],routes:[],history:[],archive:[],settings:{},employees:[],absences:[],customers:[]};
let proofViewVersion=0;
let proofArchiveId=null,proofCache={},loaded=false,currentTab='planning';
/* ---- mapeo cloud → forma interna (se conserva la del V3 para no tocar la UI) ---- */
/* Un recurso de reparto es un conductor de Flota con el vehículo que Flota le
   tiene asignado hoy. El TMS ya no guarda ni personas ni vehículos: los lee por
   gama_tms_resources, que devuelve sólo lo necesario para repartir. */
const drvFrom=r=>({id:r.driver_id,name:r.name,phone:r.phone||'',vehicle:r.plate||'',
 vehicleId:r.vehicle_id||null,vehicleStatus:r.vehicle_status||null,
 maxWeight:Number(r.max_weight||0),maxVolume:Number(r.max_volume||0),
 enabled:r.available===true,absent:r.absent===true,employeeId:r.employee_id||null});
const delFrom=r=>({id:r.id,reference:r.dossier_reference||'',customer:r.customer,address:r.address,customerId:r.customer_id||null,date:r.delivery_date,timeWindow:r.time_window||'',priority:r.priority||'Normal',weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Pendiente de preparación',lat:r.lat,lng:r.lng,routeId:r.route_id,driverId:r.driver_id,actualArrival:r.actual_arrival,deliveredAt:r.delivered_at,notes:r.notes||''});
const rtFrom=r=>({id:r.id,reference:r.erp_reference||'',date:r.route_date,driverId:r.driver_id,driver:r.driver_name||'',vehicle:r.vehicle||'',vehicleId:r.vehicle_id||null,stops:Array.isArray(r.stops)?r.stops:[],distance:Number(r.distance||0),weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Planificada',createdAt:r.created_at});
const evFrom=r=>({id:r.id,at:r.at,deliveryId:r.delivery_id,type:r.type,note:r.note||'',customer:r.customer||''});

function fail(e,what){const m=e&&(e.message||e.error_description||e.details)||'Error desconocido';console.warn('[GAMA TMS]',what,e);alert(what+' : '+(window.GamaLoading?.error(e)||m));}
function findDelivery(id){return db.deliveries.find(d=>d.id===id)||db.archive.find(d=>d.id===id)||null}

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
 const t=today();
 const [drv,rt,del,ev,st,pf,pending]=await Promise.all([
  (async()=>{const c=await api.db();const r=await window.ArcData.rawRpc('gama_tms_resources');return r.error?{data:[],error:r.error}:{data:r.data||[]}})(),
  api.list('tms_routes',{eq:{route_date:t},order:'created_at',ascending:true}),
  api.list('tms_deliveries',{eq:{delivery_date:t},order:'created_at',ascending:true}),
  api.list('tms_events',{order:'at',ascending:false,limit:HISTORY_LIMIT}),
  api.list('tms_settings',{limit:1}),
  // Sólo el índice: las fotos y firmas no viajan hasta que se abre una prueba.
  api.list('tms_proofs',{select:'delivery_id,captured_at',order:'captured_at',ascending:false,limit:ARCHIVE_LIMIT}),
  pendingDeliveries(api),
 ]);
 if(sessionVersion!==authEpoch)throw Error('Session changed');
 for(const result of [rt,del,st])if(result.error)throw result.error;
 db.drivers=(drv.data||[]).map(drvFrom);
 db.driversError=drv.error?String(drv.error.message||drv.error):null;
 db.routes=(rt.data||[]).map(rtFrom);
 db.deliveries=[...new Map([...(del.data||[]),...pending].map(d=>[d.id,d])).values()].map(delFrom);
 db.history=(ev.data||[]).map(evFrom);
 const s=(st.data||[])[0]||{};
 db.settings={depot:s.depot||'',returnDepot:s.return_depot!==false,depotPoint:(s.depot_lat!=null&&s.depot_lng!=null)?{id:'__depot',isDepot:true,address:s.depot||'Depósito',lat:s.depot_lat,lng:s.depot_lng}:null};
 const ids=(pf.data||[]).map(p=>p.delivery_id).filter(Boolean);
 if(ids.length){
  const arch=await api.list('tms_deliveries',{in:{id:ids},order:'delivered_at',ascending:false});
  db.archive=(arch.data||[]).map(delFrom);
 }else db.archive=[];
 await fetchHr(api,t);
 await fetchCustomers(api);
}
/* Los clientes van aparte y sin propagar el error, igual que RRHH: si el rol
   no puede leerlos el desplegable se queda vacío y el transporte sigue
   funcionando con los campos escritos a mano. */
async function fetchCustomers(api){
 try{
  const r=await api.list('customers',{select:'id,name,address,email,active',order:'name',ascending:true});
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
 const r=await C().list('tms_proofs',{eq:{delivery_id:id},limit:1});
 proofCache[id]=(r.data||[])[0]||null;
 return proofCache[id];
}

/* ---- migración única desde localStorage ---- */
async function migrateLocalOnce(){if(localStorage.getItem(MIGRATED_KEY))return;const old=readLocal(LOCAL_KEY,null);localStorage.setItem(MIGRATED_KEY,'1');if(old?.deliveries?.length)alert(tr('preserved'))}
async function ready(){
 if(loaded)return true;
 if(!C()){alert('El módulo de transporte necesita la conexión con la nube. Recarga la aplicación.');return false}
 try{
  await migrateLocalOnce();
  await fetchAll();
  loaded=true;return true;
 }catch(e){fail(e,'No se pudieron cargar los datos de transporte');return false}
}
async function reload(tab){try{await fetchAll()}catch(e){fail(e,'No se pudo actualizar')}render(tab||currentTab)}
async function log(delivery,type,note){
 try{await C().insert('tms_events',{delivery_id:delivery.id,at:now(),type,note:note||null,customer:delivery.customer||null})}
 catch(e){console.warn('[GAMA TMS] evento no registrado',e)}
}

function styles(){ /* Styles are compiled in architect-components.css. */ }
function section(){let x=document.getElementById('gama-tms-section');if(x)return x;x=document.createElement('section');x.id='gama-tms-section';x.style.display='none';(document.querySelector('.wrap')||document.body).appendChild(x);return x}
function showSection(){const x=section();window.ArcRouter.show('gama-tms-section');return x}

async function open(tab){
 planningEpoch++;
 proofViewVersion++;
 styles();
 const x=showSection();
 tab=tab==='tracking'?'history':(tab||'preparation');
 currentTab=tab;
 GamaPage.reset('tmsDeliveries');GamaPage.reset('tmsHistory');
 window.ArcUI.render(x,'<div class="tms"><div class="tmsEmpty" data-gi=84b789d07900>Cargando datos de transporte…</div></div>');
 window.scrollTo({top:0,behavior:'smooth'});
 const openEpoch=planningEpoch;
 if(!await ready()||openEpoch!==planningEpoch)return;
 if(tab==='proof'){const sel=defaultProofId();if(sel)await ensureProof(sel)}
 render(tab);
 if(tab==='planning')await autoPlanning(true);
}
function defaultProofId(){
 const delivered=archiveList();
 return proofArchiveId&&delivered.some(d=>d.id===proofArchiveId)?proofArchiveId:(delivered[0]?.id||'');
}
function archiveList(){return db.archive.filter(d=>d.status==='Entregada').sort((a,b)=>new Date(b.deliveredAt||0)-new Date(a.deliveredAt||0))}
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
const planningActive=()=>currentTab==='planning'&&section().classList.contains('active')&&!!window.gamaAccessAllowed?.('tms');
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
   const r=await window.ArcData.rawRpc('gama_tms_plan_day');if(r.error)throw r.error;plan=r.data;markOrigins();
   if(epoch!==planningEpoch||!planningActive())return;
   render('planning');let changed=false;
   if(!validPoint(db.settings.depotPoint)&&db.settings.depot){const p=await coordinates(db.settings.depot);if(p&&epoch===planningEpoch&&planningActive()){const u=await C().upsert('tms_settings',{id:true,depot_lat:p.lat,depot_lng:p.lng},{onConflict:'id'});if(u.error)throw u.error;changed=true}}
   for(const id of (plan.geocode_delivery_ids||[]).filter(id=>!geoAttempts.has(findDelivery(id)?.address)).slice(0,4)){
    if(epoch!==planningEpoch||!planningActive())return;
    const d=findDelivery(id),p=await coordinates(d?.address);
    if(p&&epoch===planningEpoch&&planningActive()){const u=await C().update('tms_deliveries',id,p);if(u.error)throw u.error;changed=true}
   }
   if(epoch!==planningEpoch||!planningActive())return;
   if(changed){const r=await window.ArcData.rawRpc('gama_tms_plan_day');if(r.error)throw r.error;plan=r.data}
   await fetchAll();markOrigins();
  }catch(e){console.warn('[TMS] automatic planning',e);if(epoch===planningEpoch)planError=tr('failed')+' '+(window.GamaLoading?.error(e)||e.message||'')}
  finally{if(epoch===planningEpoch&&planningActive())render('planning')}
 };
 planningJob=run();render('planning');try{await planningJob}finally{planningJob=null;if(planningActive()){if(epoch===planningEpoch)render('planning');else autoPlanning(true)}}
}
function planningBody(ds){
 const routes=db.routes.filter(r=>r.date===today());
 const missing=ds.filter(d=>d.fromOrder&&!['Entregada','Cancelada'].includes(d.status)&&!validPoint(d));
 return `<div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(tr('auto'))} · ${esc(plan?.today||today())}</b><button type="button" class="arcButton tmsBtn tmsLight" id="tRefresh"${planningJob?' disabled':''}>${esc(planningJob?tr('working'):tr('refresh'))}</button></div><p>${esc(tr('orders'))}</p><div role="status" id="tPlanStatus">${plan?`${esc(tr('planned'))}: ${plan.planned} / ${plan.total}`:''}</div>${planError?`<p role="alert" class="tmsAbsente">${esc(planError)}</p>`:''}${avisoAusencias()}${plan?.without_capacity?`<p class="tmsAbsente">${esc(tr('capacity'))}: ${plan.without_capacity}</p>`:''}${plan?.depot_missing?`<p class="tmsHint">${esc(tr('depot'))}</p>`:''}</div>
 <div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(tr('map'))}</b><div class="tmsMapTools"><select id="tMapRoute" aria-label="${esc(tr('all'))}"><option value="all">${esc(tr('all'))}</option>${routes.map(r=>`<option value="${esc(r.id)}"${mapRoute===r.id?' selected':''}>${esc(r.reference||r.driver||r.id)}</option>`).join('')}</select><button type="button" class="arcButton tmsBtn" id="tMapOut" aria-label="Zoom −">−</button><button type="button" class="arcButton tmsBtn" id="tMapIn" aria-label="Zoom +">+</button><button type="button" class="arcButton tmsBtn" id="tMapFit">↔</button></div></div><div id="tDayMap" class="tmsDayMap" aria-label="${esc(tr('map'))}"></div><p id="tMapError" class="tmsHint" hidden>${esc(tr('tiles'))}</p><small>© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a></small><p class="tmsHint">${esc(tr('approx'))}</p>${missing.length?`<p class="tmsAbsente">${esc(tr('missing'))}: ${missing.length}</p>`:''}</div>
 <div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b>${esc(T('Entregas de hoy'))}</b><small>${ds.length}</small></div><div class="tmsTableScroll"><table class="arcTable tmsTable"><thead><tr><th>${esc(T('Cliente'))}</th><th>${esc(T('Carga'))}</th><th>${esc(T('Estado'))}</th></tr></thead><tbody>${ds.map(d=>`<tr id="tms-delivery-${esc(d.id)}" tabindex="-1"><td><b>${esc(d.reference||'')} ${esc(d.customer)}</b><br><small>${esc(d.address)} · ${esc(d.timeWindow||'—')}</small></td><td>${d.weight} kg / ${d.volume} m³</td><td>${esc(status(d))}${d.fromOrder?`<br><button type="button" class="arcButton tmsBtn tmsLight" data-tms-coordinates="${esc(d.id)}"${planningJob?' disabled':''}>${esc(tr('fix'))}</button><br><button type="button" class="arcButton tmsBtn tmsLight" data-tms-loading="${esc(d.id)}">${esc(T('Salida de bultos'))}</button>`:`<br><small>${esc(tr('legacy'))}</small>`}</td></tr>`).join('')}</tbody></table></div></div>
 <div><div class="arcPanel tmsCard">${routes.map(r=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${[r.reference,r.driver,r.vehicle].filter(Boolean).map(esc).join(' · ')}</b><small>${r.distance.toFixed(1)} km · ${r.weight} kg · ${r.volume} m³</small></div><small>${esc(r.status)}</small><ol class="tmsStops">${routeStops(r).filter(d=>!d.isDepot).map(d=>`<li><b>${esc(d.customer)}</b> <small>${esc(d.address)}</small></li>`).join('')}</ol><a class="arcButton tmsBtn tmsLight" href="${esc(mapsUrl(r))}" target="_blank" rel="noopener noreferrer">Google Maps</a></div>`).join('')||`<div class="tmsEmpty">${esc(T('No hay rutas planificadas.'))}</div>`}</div>
 <details class="arcPanel tmsCard"><summary>${esc(T('Configuración avanzada del depósito'))}</summary><div class="tmsForm"><div class="full"><label>${esc(T('Dirección del depósito'))}</label><input id="tDepot" value="${esc(db.settings.depot||'')}"></div><div><label for="tDepotLat">${esc(tr('latitude'))}</label><input id="tDepotLat" type="number" step="any" min="-85" max="85" value="${esc(db.settings.depotPoint?.lat??'')}"></div><div><label for="tDepotLng">${esc(tr('longitude'))}</label><input id="tDepotLng" type="number" step="any" min="-180" max="180" value="${esc(db.settings.depotPoint?.lng??'')}"></div><div><label>${esc(T('Regreso al depósito'))}</label><select id="tReturn"><option value="1"${db.settings.returnDepot?' selected':''}>${esc(T('Sí'))}</option><option value="0"${!db.settings.returnDepot?' selected':''}>${esc(T('No'))}</option></select></div></div><button type="button" class="arcButton tmsBtn" id="tSaveDepot"${planningJob?' disabled':''}>${esc(tr('save'))}</button></details></div></div>`;
}
function drawDayMap(){
 const host=document.getElementById('tDayMap');if(!host)return;
 const routes=db.routes.filter(r=>r.date===today()&&(mapRoute==='all'||mapRoute===r.id));
 const selected=new Set(routes.flatMap(r=>r.stops));
 const points=db.deliveries.filter(d=>d.date===today()&&d.fromOrder&&validPoint(d)&&(mapRoute==='all'||selected.has(d.id)));
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
 host.querySelectorAll('image').forEach(img=>img.addEventListener('error',()=>{const e=document.getElementById('tMapError');if(e)e.hidden=false}));
 host.querySelectorAll('[data-map-delivery]').forEach(marker=>{const jump=()=>document.getElementById('tms-delivery-'+marker.dataset.mapDelivery)?.focus();marker.addEventListener('click',jump);marker.addEventListener('keydown',e=>{if(['Enter',' '].includes(e.key)){e.preventDefault();jump()}})});
}
function editCoordinates(id){
 const d=findDelivery(id);if(!d?.fromOrder)return;
 const dlg=document.createElement('dialog');dlg.className='tmsCoordinateDialog';
 dlg.innerHTML=`<form><h3>${esc(tr('fix'))}</h3><p>${esc(d.customer)} · ${esc(d.address)}</p><label>${esc(tr('latitude'))}<input name="lat" type="number" step="any" min="-85" max="85" required value="${esc(d.lat??'')}"></label><label>${esc(tr('longitude'))}<input name="lng" type="number" step="any" min="-180" max="180" required value="${esc(d.lng??'')}"></label><p role="alert"></p><button type="submit" class="arcButton">${esc(tr('save'))}</button><button type="button" class="arcButton" data-close>${esc(tr('cancel'))}</button></form>`;
 document.body.appendChild(dlg);dlg.showModal();dlg.addEventListener('close',()=>dlg.remove());dlg.querySelector('[data-close]').onclick=()=>dlg.close();
 dlg.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,p={lat:Number(f.elements.lat.value),lng:Number(f.elements.lng.value)};if(!validPoint(p)){f.querySelector('[role=alert]').textContent=tr('invalid');return}const b=f.querySelector('[type=submit]');b.disabled=true;try{const r=await C().update('tms_deliveries',id,p);if(r.error)throw r.error;await log(d,'COORDENADAS','Coordenadas corregidas');dlg.close();await autoPlanning(true)}catch(error){f.querySelector('[role=alert]').textContent=error.message;b.disabled=false}};
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
window.addEventListener('gama:data-change',()=>{if(planningActive()&&!planningJob)autoPlanning()});
window.addEventListener('gama:sales-change',()=>autoPlanning());
window.addEventListener('arc:route-leave',()=>{planningEpoch++;mapObserver?.disconnect()});
window.addEventListener('gama:auth-change',()=>{planningEpoch++;authEpoch++;currentTab="";loaded=false;proofCache={};proofArchiveId=null;plan=null;mapObserver?.disconnect();geoAttempts.clear();db={deliveries:[],drivers:[],routes:[],history:[],archive:[],settings:{},employees:[],absences:[],customers:[]}});

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
  const prev=proofCache[id],saved=await window.ArchitectOfflineProofs.capture({delivery_id:id,photo,captured_at:now(),complete:false,reference:db.deliveries.find(d=>d.id===id)?.customer||''});
  proofCache[id]={delivery_id:id,photo,signature:prev?.signature||null};
  if(saved.queued)alert(window.GamaI18n?.language==='fr'?'Photo conservée sur cet appareil, synchronisation en attente.':'Foto conservada en este dispositivo; sincronización pendiente.');
  const preview=document.getElementById('tProofPhotoPreview');if(preview&&document.getElementById('tPhoto')===file){preview.src=photo;preview.hidden=false}
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
  if(!pixels.some((v,i)=>i%4===3&&v>0)){alert(window.GamaI18n?.t('La firma del cliente es obligatoria.')||'La firma del cliente es obligatoria.');return}
  const signature=c.toDataURL('image/png'),stamp=now();button.disabled=true;
  try{
   const saved=await window.ArchitectOfflineProofs.capture({delivery_id:d.id,signature,captured_at:stamp,complete:true,reference:d.customer});
   if(saved.queued){alert(window.GamaI18n?.language==='fr'?'Signature conservée sur cet appareil. La livraison sera confirmée après synchronisation.':'Firma conservada en este dispositivo. La entrega se confirmará después de sincronizar.');return}
   proofCache[d.id]={delivery_id:d.id,photo:proofCache[d.id]?.photo||null,signature};
   window.dispatchEvent(new Event('gama:sales-change'));
   proofArchiveId=d.id;
   await reload('proof');
   alert('Prueba de entrega registrada.');
  }catch(e){fail(e,'No se pudo registrar la prueba de entrega')}finally{button.disabled=false}
 };
}
async function viewProofArchive(id){proofArchiveId=id;await ensureProof(id);render('proof')}
/* Informe de todas las pruebas archivadas. Las fotos y las firmas se piden a la
   base sólo cuando se miran, así que aquí hay que traer las que falten antes de
   armar el PDF: si no, saldrían entregas sin prueba. */
/* Comprobante de UNA entrega, para un litigio con un cliente concreto: fecha,
   lugar, firma y foto en la misma página. El informe completo sigue existiendo
   aparte, para cuando hace falta el conjunto. */
async function downloadProofCertificate(id){
 if(!window.GamaPdf)return alert('El generador de PDF no está disponible. Recarga la aplicación.');
 const d=archiveList().find(x=>x.id===id);
 if(!d)return alert('No se encontró la entrega.');
 const btn=section().querySelector('#tProofOne');
 const texto=btn?btn.textContent:'';
 if(btn){btn.disabled=true;btn.textContent='Preparando…'}
 try{
  const pr=await ensureProof(d.id);
  await window.GamaCompany?.load(true);await window.GamaPdf.ready();
  const doc=window.GamaPdf.proofCertificate({
   cliente:d.customer,direccion:d.address,fecha:d.deliveredAt||d.date,
   conductor:(db.drivers.find(x=>x.id===d.driverId)||{}).name||'',
   referencia:pr?.dossier_reference||d.reference||d.notes||'',
   firma:pr&&pr.signature||'',foto:pr&&pr.photo||''
  });
  const dia=new Date(d.deliveredAt||d.date||Date.now()).toISOString().slice(0,10);
  window.GamaPdf.save(doc,window.GamaPdf.fileName('entrega',dia+'-'+(d.customer||'')));
 }catch(e){console.error('[GAMA PDF comprobante]',e);alert('No se pudo generar el comprobante: '+(e&&e.message||e))}
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
 if(!window.GamaPdf||!window.GamaQuotePdf)return alert('El generador de PDF no está disponible. Recarga la aplicación.');
 const d=archiveList().find(x=>x.id===id);
 if(!d)return alert('No se encontró la entrega.');
 const btn=section().querySelector('#tProofMail');
 const texto=btn?btn.textContent:'';
 if(btn){btn.disabled=true;btn.textContent='Preparando…'}
 try{
  const pr=await ensureProof(d.id);
  const conductor=(db.drivers.find(x=>x.id===d.driverId)||{}).name||'';
  await window.GamaCompany?.load(true);await window.GamaPdf.ready();
  const doc=window.GamaPdf.proofCertificate({
   cliente:d.customer,direccion:d.address,fecha:d.deliveredAt||d.date,
   conductor,referencia:pr?.dossier_reference||d.reference||d.notes||'',
   firma:pr&&pr.signature||'',foto:pr&&pr.photo||''
  });
  const fecha=new Date(d.deliveredAt||d.date||Date.now());
  const dia=fecha.toISOString().slice(0,10),legible=fecha.toLocaleDateString('es-EC');
  const cliente=db.customers.find(c=>String(c.id)===String(d.customerId));
  const email=cliente&&cliente.email||'';
  if(!email)alert('Este cliente no tiene un correo registrado: complétalo manualmente al enviar.');
  await window.GamaQuotePdf.sendDocument({
   blob:doc.output('blob'),
   email,
   subject:'Comprobante de entrega — '+legible,
   body:'Estimado/a '+(d.customer||'cliente')+',\n\nAdjuntamos el comprobante de la entrega realizada el '+legible+' en '+(d.address||'')+'.'+(conductor?'\nTransportista: '+conductor+'.':'')+'\n\nQuedamos a su disposición para cualquier consulta.\n\nGAMA Enterprise Resource Planning',
   filename:window.GamaPdf.fileName('entrega',dia+'-'+(d.customer||''))
  });
 }catch(e){console.error('[GAMA PDF comprobante correo]',e);alert('No se pudo preparar el envío: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
async function downloadProofReport(){
 const btn=section().querySelector('#tProofPdf');
 if(!window.GamaPdf)return alert('El generador de PDF no está disponible. Recarga la aplicación.');
 const entregas=archiveList();
 if(!entregas.length)return alert('No hay ninguna prueba de entrega archivada.');
 const texto=btn?btn.textContent:'';
 if(btn){btn.disabled=true;btn.textContent='Preparando el informe…'}
 try{
  for(const d of entregas)await ensureProof(d.id);
  const filas=entregas.map(d=>{
   const pr=proofCache[d.id]||null;
   return {cliente:d.customer,direccion:d.address,fecha:d.deliveredAt||d.date,referencia:pr?.dossier_reference||d.reference||'',
    conductor:(db.drivers.find(x=>x.id===d.driverId)||{}).name||'',
    firma:pr&&pr.signature||'',foto:pr&&pr.photo||''};
  });
  await window.GamaCompany?.load(true);await window.GamaPdf.ready();
  const doc=window.GamaPdf.proofReport(filas,'Pruebas de entrega — Coco ERP');
  window.GamaPdf.save(doc,window.GamaPdf.fileName('pruebas-entrega',new Date().toISOString().slice(0,10)));
 }catch(e){console.error('[GAMA PDF pruebas]',e);alert('No se pudo generar el informe: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
async function saveDepot(){
 const x=section(),address=x.querySelector('#tDepot').value.trim(),lat=x.querySelector('#tDepotLat').value,lng=x.querySelector('#tDepotLng').value;
 if((lat!==''||lng!=='')&&(!lat||!lng||!validPoint({lat,lng})))return alert(tr('invalid'));
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
function render(tab){
 proofViewVersion++;
 currentTab=tab;
 const x=section(),ds=db.deliveries.filter(d=>d.date===today()),pending=ds.filter(d=>!['Entregada','Cancelada'].includes(d.status)).length,del=ds.filter(d=>d.status==='Entregada').length,exceptions=ds.filter(d=>d.status==='Excepción').length,planned=db.routes.filter(r=>r.date===today()&&r.status!=='Terminada').length;
 const tabs=[['preparation','Preparación'],['planning','Planificación'],['loading','Salida de bultos'],['proof','Prueba de entrega'],['history','Historial']];
 let body='';
if(tab==='preparation')body='<div id="gamaPreparationHost"></div>';
if(tab==='loading')body='<div id="gamaLoadingHost"></div>';
if(tab==='planning')body=planningBody(ds);
if(tab==='proof'){
 const toCapture=db.deliveries.filter(d=>!['Entregada','Cancelada'].includes(d.status)).sort((a,b)=>String(a.date).localeCompare(String(b.date))||a.id.localeCompare(b.id));
 const delivered=archiveList();
 const selId=defaultProofId();
 const sel=delivered.find(d=>d.id===selId);
 const pr=sel?proofCache[sel.id]:null;
 body=`<div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=ed806a52ba08>Entregas pendientes de prueba</b><small>${toCapture.length}</small></div>${toCapture.map(d=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(d.reference||'')} ${esc(d.customer)}</b><small>${esc(d.address)} · ${esc(d.date||'—')} · ${esc(status(d))}</small></div><button class="arcButton tmsBtn tmsPrimary" onclick="gamaTMS.openProof('${d.id}')" data-gi=5be1e4143d9a>Abrir prueba de entrega</button></div>`).join('')||'<div class="tmsEmpty" data-gi-live data-gi=ec126a95d652>No hay entregas pendientes de prueba.</div>'}</div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=c30fbfa7b5e2>Archivo de pruebas de entrega</b><small>${delivered.length}</small></div>${delivered.length?`<button class="arcButton tmsBtn tmsLight" id="tProofPdf" style="margin-bottom:8px" data-gi=630b7b1978bd>Descargar informe PDF</button>`:''}${delivered.length?`<label data-gi=fb249302b38a>Selecciona una entrega</label><select id="tProofSelect">${delivered.map(d=>`<option value="${d.id}" ${d.id===selId?'selected':''}>${new Date(d.deliveredAt||d.date).toLocaleDateString('es-ES')} — ${esc(d.customer)}</option>`).join('')}</select>${sel?`<div class="tmsProof" style="margin-top:12px"><div>${pr?.photo?`<img src="${pr.photo}">`:'<div class="tmsEmpty" data-gi=8b5d1f44a991>Sin foto</div>'}</div><div>${pr?.signature?`<img src="${pr.signature}">`:'<div class="tmsEmpty" data-gi=d0fb2d19ed9c>Sin firma</div>'}</div></div><p style="font-size:12px;color:var(--arc-text-muted);margin-top:8px"><span data-gi=f93545ab473d>Entregado: </span>${sel.deliveredAt?new Date(sel.deliveredAt).toLocaleString('es-ES'):'-'} · ${esc(sel.address)}${sel.notes?' · '+esc(sel.notes):''}</p><button class="arcButton tmsBtn tmsPrimary" id="tProofOne" style="width:100%" data-gi=1648a7947af6>Descargar comprobante de esta entrega</button><button class="arcButton tmsBtn tmsLight" id="tProofMail" style="width:100%;margin-top:8px" data-gi=6aded56dd465>Enviar el comprobante al cliente</button>`:''}`:'<div class="tmsEmpty" data-gi=bc5dccf97b1a>Aún no hay pruebas de entrega archivadas.</div>'}</div></div>`;
}
if(tab==='history')body=`<div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=55c4aa39dc01>Historial de rutas y entregas</b><small>${db.history.length} eventos</small></div>${db.history.length?`<table class="arcTable tmsTable" data-gama-sort-key="tmsHistory"><thead><tr><th data-gi=93b2a9ef782c>Fecha</th><th data-gi=f851d9a83ab0>Cliente</th><th data-gi=43f6698cdd81>Evento</th><th data-gi=426234e72a5b>Detalle</th></tr></thead><tbody>${GamaPage.slice('tmsHistory',db.history,{0:h=>h.at,1:h=>h.customer,2:h=>h.type,3:h=>h.note}).map(h=>`<tr><td>${new Date(h.at).toLocaleString('es-ES')}</td><td>${esc(h.customer)}</td><td><span class="tmsBadge">${esc(h.type)}</span></td><td data-gi-live>${esc(h.note)}</td></tr>`).join('')}</tbody></table>${GamaPage.controls('tmsHistory',db.history.length)}`:'<div class="tmsEmpty" data-gi=a0aee7bf5f53>No hay historial.</div>'}</div>`;
 window.ArcUI.render(x,`<div class="tms">${window.GamaUI.header({title:'TMS',lead:'Del pedido preparado a la prueba de entrega.'})}<div class="tmsKpis"><div class="tmsKpi"><span data-gi=9f818dbe915c>Entregas</span><strong>${ds.length}</strong></div><div class="tmsKpi"><span data-gi=bb6e430ce0a7>Pendientes</span><strong>${pending}</strong></div><div class="tmsKpi"><span data-gi=97ec218e28be>Entregadas</span><strong>${del}</strong></div><div class="tmsKpi"><span data-gi=b25f73c77641>Excepciones</span><strong>${exceptions}</strong></div><div class="tmsKpi"><span data-gi=2f6b91a34921>Rutas</span><strong>${planned}</strong></div><div class="tmsKpi"><span data-gi=98e5acddb6c4>Estado</span><strong>CLOUD</strong></div></div><div class="tmsTabs">${tabs.map(t=>`<button class="arcButton tmsTab ${tab===t[0]?'active':''}" onclick="gamaTMS.open('${t[0]}')" data-gi-live>${t[1]}</button>`).join('')}</div>${body}</div><div class="tmsPrint"><h2 data-gi=3daa927edb88>Coco ERP — hoja de ruta</h2>${db.routes.filter(r=>r.date===today()).map(r=>`<h3>${esc(r.reference||'')} · ${esc(r.driver)} · ${esc(r.vehicle)}</h3>${routeStops(r).filter(s=>!s.isDepot).map((d,i)=>`<p>${i+1}. <b>${esc(d.reference||'')} ${esc(d.customer)}</b> — ${esc(d.address)}</p>`).join('')}`).join('')}</div>`);
 window.GamaUI.bindBack(x);
 if(tab==='preparation')window.GamaPreparation?.mount(x.querySelector('#gamaPreparationHost'));
 if(tab==='loading')window.GamaLoading?.mount(x.querySelector('#gamaLoadingHost'));
 if(tab==='planning')bindPlanning(x);
 const ps=x.querySelector('#tProofSelect');if(ps)ps.onchange=()=>viewProofArchive(ps.value);
 const pp=x.querySelector('#tProofPdf');if(pp)pp.onclick=downloadProofReport;
 const po=x.querySelector('#tProofOne');if(po)po.onclick=()=>downloadProofCertificate(defaultProofId());
 const pm=x.querySelector('#tProofMail');if(pm)pm.onclick=()=>emailProofCertificate(defaultProofId());

 const sd=x.querySelector('#tSaveDepot');if(sd)sd.onclick=saveDepot;
}
function mapsUrl(r){const s=routeStops(r),valid=s.filter(x=>!x.isDepot||x.address);if(valid.length<2)return '#';const o=encodeURIComponent(valid[0].address),dest=encodeURIComponent(valid[valid.length-1].address),wp=valid.slice(1,-1).map(x=>encodeURIComponent(x.address)).join('|');return'https://www.google.com/maps/dir/?api=1&origin='+o+'&destination='+dest+(wp?'&waypoints='+wp:'')+'&travelmode=driving'}
async function openProof(id){
 if(!await ready())return;
 const d=findDelivery(id);if(!d)return;
 await ensureProof(id);
 await renderProofDetail(id);
}
async function renderProofDetail(id){
 planningEpoch++;currentTab="proof";
 const d=findDelivery(id);if(!d)return;
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
  try{await C().update('tms_deliveries',id,{notes});d.notes=notes;alert('Notas guardadas.')}
  catch(e){fail(e,'No se pudieron guardar las notas')}
 };
}
GamaPage.register('tmsDeliveries',()=>render('planning'));GamaPage.register('tmsHistory',()=>render('history'));
window.gamaTMS={openDelivery:async id=>{
 if(!window.gamaAccessAllowed?.('tms'))throw Error('Acceso no permitido.');
 await open('proof');const r=await C().list('tms_deliveries',{eq:{id}});if(r.error)throw r.error;if(!r.data?.[0])throw Error('Entrega no disponible.');
 db.deliveries=db.deliveries.filter(d=>d.id!==id).concat(r.data.map(delFrom));await ensureProof(id);await renderProofDetail(id);
},open,openProof,__drivers:()=>db.drivers,viewProofArchive,downloadProofReport,downloadProofCertificate};
})();
