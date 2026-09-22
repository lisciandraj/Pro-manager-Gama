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
const today=()=>new Date().toISOString().slice(0,10),now=()=>new Date().toISOString();
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
async function migrateLocalOnce(){
 if(localStorage.getItem(MIGRATED_KEY))return;
 const old=readLocal(LOCAL_KEY,null);
 const api=C();
 if(!old||!api){localStorage.setItem(MIGRATED_KEY,'1');return}
 const hasData=(old.drivers||[]).length||(old.deliveries||[]).length||(old.routes||[]).length;
 if(!hasData){localStorage.setItem(MIGRATED_KEY,'1');return}
 // No duplicar si otro navegador ya subió los datos. La comprobación mira
 // entregas y eventos: son lo que sólo puede venir de este histórico.
 const [exDel,exEv]=await Promise.all([api.list('tms_deliveries',{limit:1}),api.list('tms_events',{limit:1})]);
 if((exDel.data||[]).length||(exEv.data||[]).length){
  localStorage.setItem(MIGRATED_KEY,'1');
  // Nunca se borra gama-tms-v1: los datos siguen en este navegador.
  alert('El transporte ya tiene datos en la nube, subidos desde otro equipo.\n\nEl histórico guardado en este navegador no se ha importado para no duplicarlo. Sigue disponible aquí; contacta con el administrador si hay que recuperarlo.');
  return;
 }
 /* Los conductores de aquel navegador no se suben: hoy las personas viven en
    RRHH y los vehículos en Flota, y un registro paralelo es justo lo que este
    cambio ha venido a quitar. Las entregas y las rutas sí se conservan, sin
    conductor asignado; se les vuelve a asignar desde la planificación. */
 const drvMap={},delMap={};
 for(const d of old.deliveries||[]){
  const r=await api.insert('tms_deliveries',{customer:d.customer||'—',address:d.address||'—',delivery_date:d.date||today(),time_window:d.timeWindow||null,priority:d.priority||'Normal',weight:Number(d.weight||0),volume:Number(d.volume||0),status:d.status||'Pendiente de preparación',lat:d.lat??null,lng:d.lng??null,driver_id:drvMap[d.driverId]||null,actual_arrival:d.actualArrival||null,delivered_at:d.deliveredAt||null,notes:d.notes||null});
  if(!r.data)continue;
  delMap[d.id]=r.data.id;
  if(d.proof&&(d.proof.photo||d.proof.signature))
   await api.upsert('tms_proofs',{delivery_id:r.data.id,photo:d.proof.photo||null,signature:d.proof.signature||null,captured_at:d.deliveredAt||now()},{onConflict:'delivery_id'});
 }
 for(const r of old.routes||[]){
  const created=await api.insert('tms_routes',{route_date:r.date||today(),driver_id:drvMap[r.driverId]||null,driver_name:r.driver||'',vehicle:r.vehicle||'',stops:(r.stops||[]).map(s=>s==='__depot'?'__depot':(delMap[s]||null)).filter(Boolean),distance:Number(r.distance||0),weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Planificada'});
  if(created.data)for(const sid of (r.stops||[]))if(delMap[sid])await api.update('tms_deliveries',delMap[sid],{route_id:created.data.id});
 }
 for(const h of (old.history||[]).slice().reverse())
  await api.insert('tms_events',{delivery_id:delMap[h.deliveryId]||null,at:h.at||now(),type:h.type||'Evento',note:h.note||null,customer:h.customer||null});
 if(old.settings&&(old.settings.depot||old.settings.returnDepot!=null))
  await api.upsert('tms_settings',{id:true,depot:old.settings.depot||null,return_depot:old.settings.returnDepot!==false,updated_at:now()},{onConflict:'id'});
 localStorage.setItem(MIGRATED_KEY,'1');
}
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
 proofViewVersion++;
 styles();
 const x=showSection();
 tab=tab==='tracking'?'history':(tab||'preparation');
 currentTab=tab;
 GamaPage.reset('tmsDeliveries');GamaPage.reset('tmsHistory');
 window.ArcUI.render(x,'<div class="tms"><div class="tmsEmpty" data-gi=84b789d07900>Cargando datos de transporte…</div></div>');
 window.scrollTo({top:0,behavior:'smooth'});
 if(!await ready())return;
 if(tab==='proof'){const sel=defaultProofId();if(sel)await ensureProof(sel)}
 render(tab);
}
function defaultProofId(){
 const delivered=archiveList();
 return proofArchiveId&&delivered.some(d=>d.id===proofArchiveId)?proofArchiveId:(delivered[0]?.id||'');
}
function archiveList(){return db.archive.filter(d=>d.status==='Entregada').sort((a,b)=>new Date(b.deliveredAt||0)-new Date(a.deliveredAt||0))}
function routeStops(r){return(r.stops||[]).map(id=>id==='__depot'?{id:'__depot',customer:'Depósito',address:db.settings?.depot||'Depósito',isDepot:true}:db.deliveries.find(d=>d.id===id)).filter(Boolean)}
function status(d){return d.status||'Pendiente de preparación'}
function geoDist(a,b){if(a.lat==null||b.lat==null)return 999999;const R=6371,la=(b.lat-a.lat)*Math.PI/180,lo=(b.lng-a.lng)*Math.PI/180,x=Math.sin(la/2)**2+Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(lo/2)**2;return 2*R*Math.asin(Math.sqrt(x))}
async function geocode(d){if(d.lat!=null&&d.lng!=null)return true;const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),5000);try{const r=await fetch('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q='+encodeURIComponent(d.address),{headers:{Accept:'application/json'},signal:controller.signal}),a=await r.json();if(a&&a[0]){d.lat=+a[0].lat;d.lng=+a[0].lon;await C().update('tms_deliveries',d.id,{lat:d.lat,lng:d.lng});return true}}catch(e){}finally{clearTimeout(timeout)}return false}
function routeFor(stops,driver){const depot=db.settings?.depotPoint||null;let cur=depot||stops[0],left=stops.slice(),out=[];let w=0,v=0;if(depot)out.push(depot);while(left.length){let best=-1,bd=Infinity;left.forEach((p,i)=>{if(w+Number(p.weight||0)>Number(driver.maxWeight||999999)||v+Number(p.volume||0)>Number(driver.maxVolume||999999))return;const dist=geoDist(cur,p),prio=p.priority==='Urgente'?3:p.priority==='Alta'?2:1,score=dist*10-prio*3;if(score<bd){bd=score;best=i}});if(best<0)break;const p=left.splice(best,1)[0];out.push(p);w+=Number(p.weight||0);v+=Number(p.volume||0);cur=p}if(db.settings?.returnDepot&&depot)out.push(depot);return{stops:out,remaining:left,weight:w,volume:v,distance:out.reduce((a,p,i)=>i?a+geoDist(out[i-1],p):0,0)}}

async function optimize(){
 const api=C();
 const lockedRoutes=new Set(db.routes.filter(r=>routeStops(r).some(d=>['En tránsito','En ruta','Entregada'].includes(d.status))).map(r=>r.id));
 const busyDrivers=new Set(db.deliveries.filter(d=>['En tránsito','En ruta'].includes(d.status)).map(d=>d.driverId));
 const pending=db.deliveries.filter(d=>d.date===today()&&!['Entregada','Cancelada','En tránsito','En ruta'].includes(d.status)&&!lockedRoutes.has(d.routeId));
 if(!pending.length){alert('No hay entregas para optimizar hoy.');return}
 const activos=db.drivers.filter(x=>x.enabled);
 // Los que hoy están de vacaciones o de baja no entran en el reparto.
 const ausentes=activos.filter(x=>x.absent);
 const drivers=activos.filter(x=>!x.absent&&!busyDrivers.has(x.id));
 if(!drivers.length){
  alert(ausentes.length
   ?'Ningún conductor disponible hoy: '+ausentes.map(x=>x.name+' ('+absLabel(driverAbsence(x,today())).toLowerCase()+')').join(', ')+'.'
   :T('No hay conductores con vehículo asignado. Se dan de alta en RRHH y se emparejan con un vehículo en Gestión de flota.'));
  return;
 }
 for(const d of pending)await geocode(d);
 try{
  // Se rehacen las rutas del día que aún no están terminadas.
  for(const r of db.routes.filter(r=>r.date===today()&&r.status!=='Terminada'&&!lockedRoutes.has(r.id))){const removed=await api.remove('tms_routes',r.id);if(removed.error)throw removed.error}
  let rem=pending.slice(),created=0;
  for(const dr of drivers){
   if(!rem.length)break;
   const r=routeFor(rem,dr);
   const stops=r.stops.filter(x=>x.id&&!x.isDepot);
   if(!stops.length)continue;
   const route=await api.insert('tms_routes',{route_date:today(),driver_id:dr.id,driver_name:dr.name,vehicle:dr.vehicle,vehicle_id:dr.vehicleId,stops:r.stops.map(x=>x.isDepot?'__depot':x.id),distance:r.distance,weight:r.weight,volume:r.volume,status:'Planificada'});
   if(!route.data)continue;
   created++;
   for(const s of stops){const updated=await api.update('tms_deliveries',s.id,{route_id:route.data.id,driver_id:dr.id,status:'Planificada'});if(updated.error)throw updated.error}
   const used=new Set(stops.map(x=>x.id));
   rem=rem.filter(x=>!used.has(x.id));
  }
  for(const d of rem){await api.update('tms_deliveries',d.id,{status:'Excepción'});await log(d,'CAPACIDAD','No hay capacidad disponible para esta entrega')}
  await reload('planning');
  alert(created+' ruta(s) creada(s).'
   +(rem.length?' '+rem.length+' entrega(s) en excepción.':'')
   +(ausentes.length?' '+ausentes.length+' conductor(es) ausente(s) hoy, fuera del reparto.':''));
 }catch(e){fail(e,'No se pudieron crear las rutas')}
}
async function addDelivery(){
 const f=id=>document.getElementById(id);
 const customer=f('tCustomer').value.trim(),address=f('tAddress').value.trim();
 const customerId=f('tCustomerPick')?.value||null;
 if(!customer||!address){alert('El cliente y la dirección son obligatorios.');return}
 try{
  const r=await C().insert('tms_deliveries',{customer,address,customer_id:customerId,delivery_date:f('tDate').value||today(),time_window:f('tWindow')?.value.trim()||null,priority:f('tPriority')?.value||'Normal',weight:+(f('tWeight')?.value)||0,volume:+(f('tVolume')?.value)||0,status:'Pendiente de preparación'});
  if(r.data)await log(delFrom(r.data),'Creada');
  await reload('planning');
 }catch(e){fail(e,'No se pudo crear la entrega')}
}
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
  await window.GamaCompany?.load(true);
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
function fillFromCustomer(x,id){
 const c=db.customers.find(y=>String(y.id)===String(id));
 if(!c)return;
 const nombre=x.querySelector('#tCustomer'),direccion=x.querySelector('#tAddress');
 if(nombre)nombre.value=c.name||'';
 if(direccion)direccion.value=c.address||'';
}
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
  await window.GamaCompany?.load(true);
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
  await window.GamaCompany?.load(true);
  const doc=window.GamaPdf.proofReport(filas,'Pruebas de entrega — Architect ERP');
  window.GamaPdf.save(doc,window.GamaPdf.fileName('pruebas-entrega',new Date().toISOString().slice(0,10)));
 }catch(e){console.error('[GAMA PDF pruebas]',e);alert('No se pudo generar el informe: '+(e&&e.message||e))}
 finally{if(btn){btn.disabled=false;btn.textContent=texto}}
}
async function saveDepot(){
 const x=section();
 try{
  await C().upsert('tms_settings',{id:true,depot:x.querySelector('#tDepot').value.trim()||null,return_depot:x.querySelector('#tReturn').value==='1',updated_at:now()},{onConflict:'id'});
  await fetchAll();
  alert('Parámetros guardados.');
 }catch(e){fail(e,'No se pudieron guardar los parámetros')}
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
 return sinRecursos+`<p class="tmsAbsente">🚫 ${esc(T('Hoy no reparten:'))} ${fuera.map(d=>{
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
if(tab==='planning')body=`<div class="tmsGrid"><div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=6e5a7739380f>Nueva entrega</b><small data-gi=bea7f86d738e>Pedidos / preparación</small></div><div class="tmsForm"><div class="full"><label data-gi=ae79a0eaa53e>Cliente registrado</label><select id="tCustomerPick"><option value="" data-gi=2aa0d0a80307>— Escribir a mano —</option>${db.customers.map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('')}</select></div><div><label data-gi=f851d9a83ab0>Cliente</label><input id="tCustomer" data-gi-placeholder=9abe245bde43 placeholder="Nombre del cliente"></div><div><label data-gi=93b2a9ef782c>Fecha</label><input id="tDate" type="date" value="${today()}"></div><div class="full"><label data-gi=2af66cb65da8>Dirección</label><input id="tAddress" data-gi-placeholder=481de1cd2e03 placeholder="Calle, número, CP, ciudad, país"></div></div><details style="margin-top:8px"><summary data-gi=f98554559230>Detalles opcionales (franja horaria, prioridad, carga)</summary><div class="tmsForm" style="margin-top:8px"><div><label data-gi=d812904bd5cd>Franja horaria</label><input id="tWindow" placeholder="08:00–10:00"></div><div><label data-gi=dbae0b2a1a74>Prioridad</label><select id="tPriority"><option data-gi=a7248eeb45eb>Normal</option><option data-gi=42719229fd62>Alta</option><option data-gi=9dc81c64f153>Urgente</option></select></div><div><label data-gi=f7b86f38025c>Peso (kg)</label><input id="tWeight" type="number" min="0"></div><div><label data-gi=215d13883a34>Volumen (m³)</label><input id="tVolume" type="number" min="0" step="0.01"></div></div></details><button class="arcButton tmsBtn tmsPrimary" id="tAdd" style="margin-top:10px" data-gi=2beb81266a5c>Añadir entrega</button></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=20bb0eb7349d>Entregas de hoy</b><small>${ds.length} en total</small></div>${ds.length?`<table class="arcTable tmsTable"><thead><tr><th data-gi=f851d9a83ab0>Cliente</th><th data-gi=756b45a47270>Franja</th><th data-gi=5f52e2cbc055>Carga</th><th data-gi=98e5acddb6c4>Estado</th></tr></thead><tbody>${GamaPage.slice('tmsDeliveries',ds).map(d=>`<tr><td><b>${esc(d.reference||'')} ${esc(d.customer)}</b><br><small>${esc(d.address)}</small></td><td>${esc(d.timeWindow||'—')}</td><td>${d.weight||0} kg / ${d.volume||0} m³</td><td><span class="tmsBadge ${d.status==='Entregada'?'ok':d.status==='Excepción'?'red':'warn'}">${esc(status(d))}</span><br><button class="arcButton tmsBtn tmsLight" onclick="GamaLoading.open('${d.id}')" data-gi-live data-gi=dabf9898be06>Salida de bultos</button></td></tr>`).join('')}</tbody></table>${GamaPage.controls('tmsDeliveries',ds.length)}`:'<div class="tmsEmpty" data-gi=e641256e4dac>No hay entregas hoy.</div>'}</div></div><div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=906ba2eec66b>Optimizar rutas de hoy</b><span class="tmsLive"><i></i> Sincronizado en la nube</span></div><p style="font-size:12px;color:var(--arc-text-muted)" data-gi=d7b3a2fbcc7f>Reparte las entregas de hoy entre tus conductores según capacidad y cercanía, con un clic. Los conductores de vacaciones o de baja en RRHH quedan fuera del reparto.</p>${avisoAusencias()}<button class="arcButton tmsBtn tmsOrange" id="tOptimize" data-gi=2bcc48c075e0>Optimizar todas las rutas</button><div style="margin-top:10px">${db.routes.filter(r=>r.date===today()).map(r=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(r.reference||'')} · ${esc(r.driver)} · ${esc(r.vehicle)}</b><small>${r.distance.toFixed(1)} km · ${r.weight||0} kg</small></div><p style="font-size:10px;color:var(--arc-text-subtle)">${routeStops(r).filter(s=>!s.isDepot).length} paradas · ${esc(r.status)}</p><button class="arcButton tmsBtn tmsLight" onclick="window.open('${mapsUrl(r)}','_blank')">Google Maps</button></div>`).join('')||'<div class="tmsEmpty" data-gi=80bc4d66c557>No hay rutas planificadas.</div>'}</div></div><details class="arcPanel tmsCard"><summary data-gi=ea2166dfd22e>⚙️ Configuración avanzada del depósito</summary><div class="tmsForm" style="margin-top:10px"><div class="full"><label data-gi=be405f1a9fc7>Dirección del depósito</label><input id="tDepot" value="${esc(db.settings?.depot||'')}" data-gi-placeholder=28d13886c9e2 placeholder="Dirección de salida / regreso"></div><div><label data-gi=e5c7d7cbd42a>Regreso al depósito</label><select id="tReturn"><option value="1"${db.settings?.returnDepot!==false?' selected':''} data-gi=739215889580>Sí</option><option value="0"${db.settings?.returnDepot===false?' selected':''} data-gi=1ea442a134b2>No</option></select></div></div><button class="arcButton tmsBtn tmsLight" id="tSaveDepot" style="margin-top:8px" data-gi=13e51a210f45>Guardar</button></details></div></div>`;
if(tab==='proof'){
 const toCapture=db.deliveries.filter(d=>!['Entregada','Cancelada'].includes(d.status)).sort((a,b)=>String(a.date).localeCompare(String(b.date))||a.id.localeCompare(b.id));
 const delivered=archiveList();
 const selId=defaultProofId();
 const sel=delivered.find(d=>d.id===selId);
 const pr=sel?proofCache[sel.id]:null;
 body=`<div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=ed806a52ba08>Entregas pendientes de prueba</b><small>${toCapture.length}</small></div>${toCapture.map(d=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(d.reference||'')} ${esc(d.customer)}</b><small>${esc(d.address)} · ${esc(d.date||'—')} · ${esc(status(d))}</small></div><button class="arcButton tmsBtn tmsPrimary" onclick="gamaTMS.openProof('${d.id}')" data-gi=5be1e4143d9a>Abrir prueba de entrega</button></div>`).join('')||'<div class="tmsEmpty" data-gi-live data-gi=ec126a95d652>No hay entregas pendientes de prueba.</div>'}</div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=c30fbfa7b5e2>Archivo de pruebas de entrega</b><small>${delivered.length}</small></div>${delivered.length?`<button class="arcButton tmsBtn tmsLight" id="tProofPdf" style="margin-bottom:8px" data-gi=3437cf41946f>📄 Descargar informe PDF</button>`:''}${delivered.length?`<label data-gi=fb249302b38a>Selecciona una entrega</label><select id="tProofSelect">${delivered.map(d=>`<option value="${d.id}" ${d.id===selId?'selected':''}>${new Date(d.deliveredAt||d.date).toLocaleDateString('es-ES')} — ${esc(d.customer)}</option>`).join('')}</select>${sel?`<div class="tmsProof" style="margin-top:12px"><div>${pr?.photo?`<img src="${pr.photo}">`:'<div class="tmsEmpty" data-gi=8b5d1f44a991>Sin foto</div>'}</div><div>${pr?.signature?`<img src="${pr.signature}">`:'<div class="tmsEmpty" data-gi=d0fb2d19ed9c>Sin firma</div>'}</div></div><p style="font-size:12px;color:var(--arc-text-muted);margin-top:8px"><span data-gi=f93545ab473d>Entregado: </span>${sel.deliveredAt?new Date(sel.deliveredAt).toLocaleString('es-ES'):'-'} · ${esc(sel.address)}${sel.notes?' · '+esc(sel.notes):''}</p><button class="arcButton tmsBtn tmsPrimary" id="tProofOne" style="width:100%" data-gi=f677f95298dc>📄 Descargar comprobante de esta entrega</button><button class="arcButton tmsBtn tmsLight" id="tProofMail" style="width:100%;margin-top:8px" data-gi=125b300d1d7c>✉️ Enviar el comprobante al cliente</button>`:''}`:'<div class="tmsEmpty" data-gi=bc5dccf97b1a>Aún no hay pruebas de entrega archivadas.</div>'}</div></div>`;
}
if(tab==='history')body=`<div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=55c4aa39dc01>Historial de rutas y entregas</b><small>${db.history.length} eventos</small></div>${db.history.length?`<table class="arcTable tmsTable"><thead><tr><th data-gi=93b2a9ef782c>Fecha</th><th data-gi=f851d9a83ab0>Cliente</th><th data-gi=43f6698cdd81>Evento</th><th data-gi=426234e72a5b>Detalle</th></tr></thead><tbody>${GamaPage.slice('tmsHistory',db.history).map(h=>`<tr><td>${new Date(h.at).toLocaleString('es-ES')}</td><td>${esc(h.customer)}</td><td><span class="tmsBadge">${esc(h.type)}</span></td><td>${esc(h.note)}</td></tr>`).join('')}</tbody></table>${GamaPage.controls('tmsHistory',db.history.length)}`:'<div class="tmsEmpty" data-gi=a0aee7bf5f53>No hay historial.</div>'}</div>`;
 window.ArcUI.render(x,`<div class="tms">${window.GamaUI.header({title:'Entrega',lead:'Del pedido preparado a la prueba de entrega.'})}<div class="tmsKpis"><div class="tmsKpi"><span data-gi=9f818dbe915c>Entregas</span><strong>${ds.length}</strong></div><div class="tmsKpi"><span data-gi=bb6e430ce0a7>Pendientes</span><strong>${pending}</strong></div><div class="tmsKpi"><span data-gi=97ec218e28be>Entregadas</span><strong>${del}</strong></div><div class="tmsKpi"><span data-gi=b25f73c77641>Excepciones</span><strong>${exceptions}</strong></div><div class="tmsKpi"><span data-gi=2f6b91a34921>Rutas</span><strong>${planned}</strong></div><div class="tmsKpi"><span data-gi=98e5acddb6c4>Estado</span><strong>CLOUD</strong></div></div><div class="tmsTabs">${tabs.map(t=>`<button class="arcButton tmsTab ${tab===t[0]?'active':''}" onclick="gamaTMS.open('${t[0]}')" data-gi-live>${t[1]}</button>`).join('')}</div>${body}</div><div class="tmsPrint"><h2 data-gi=b99979da546d>Architect TMS — hoja de ruta</h2>${db.routes.filter(r=>r.date===today()).map(r=>`<h3>${esc(r.reference||'')} · ${esc(r.driver)} · ${esc(r.vehicle)}</h3>${routeStops(r).filter(s=>!s.isDepot).map((d,i)=>`<p>${i+1}. <b>${esc(d.reference||'')} ${esc(d.customer)}</b> — ${esc(d.address)}</p>`).join('')}`).join('')}</div>`);
 window.GamaUI.bindBack(x);
 if(tab==='preparation')window.GamaPreparation?.mount(x.querySelector('#gamaPreparationHost'));
 if(tab==='loading')window.GamaLoading?.mount(x.querySelector('#gamaLoadingHost'));
 const add=x.querySelector('#tAdd');if(add)add.onclick=addDelivery;
 const opt=x.querySelector('#tOptimize');if(opt)opt.onclick=optimize;
 const ps=x.querySelector('#tProofSelect');if(ps)ps.onchange=()=>viewProofArchive(ps.value);
 const pp=x.querySelector('#tProofPdf');if(pp)pp.onclick=downloadProofReport;
 const po=x.querySelector('#tProofOne');if(po)po.onclick=()=>downloadProofCertificate(defaultProofId());
 const pm=x.querySelector('#tProofMail');if(pm)pm.onclick=()=>emailProofCertificate(defaultProofId());
 const cp=x.querySelector('#tCustomerPick');if(cp)cp.onchange=()=>fillFromCustomer(x,cp.value);
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
 window.ArcUI.render(x,`<div class="tms"><div class="gamaStdHeader" data-gama-standard-header="1"><div class="gamaStdText"><div class="gamaStdKicker" data-gi=24d49b8597db>Entrega</div><h2><span data-gi=ba1ff22c28f2>📦 Prueba de entrega · </span>${esc(shipment?.number||'TMS')}</h2><p>${esc(d.customer)} · ${esc(d.address)}</p></div><div class="gamaStdActions"><button type="button" class="arcButton gamaStdAction" onclick="gamaTMS.open('proof')" data-gi=800d9ff7ca06>Volver a entregas</button></div></div><div class="tmsGrid"><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=48e238e6251d>Foto de entrega</b><small data-gi=27ecb8e519f0>Cámara del teléfono</small></div><input id="tPhoto" type="file" accept="image/*" capture="environment"><p class="muted" style="font-size:11px;margin:6px 0 0" data-gi=862e83493184>La foto se guarda automáticamente en la nube al tomarla o seleccionarla.</p><img id="tProofPhotoPreview" ${pr?.photo?'src="'+esc(pr.photo)+'"':'hidden'} style="max-width:100%;margin-top:10px;border-radius:8px"></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=0577d0e06a8e>Firma del cliente</b><small data-gi=c8e04813a369>Firma manuscrita</small></div><canvas id="tSig" class="tmsSig" width="700" height="300"></canvas><div style="margin-top:8px"><button class="arcButton tmsBtn tmsLight" id="tSigClear" data-gi=d50a3d446835>Borrar</button> <button class="arcButton tmsBtn tmsPrimary" id="tSigSave" data-gi=4133223d0626>Validar entrega</button></div></div></div><div class="arcPanel tmsCard"><div class="tmsTitle"><b data-gi=14f2e157ec34>Información de entrega</b></div><div class="tmsForm"><div><label data-gi=d740ee3e7961>Hora real de llegada</label><input value="${d.actualArrival?new Date(d.actualArrival).toLocaleString('es-ES'):'Se registrará al validar'}" disabled></div><div><label data-gi=756ac0b9183a>Hora de entrega</label><input value="${d.deliveredAt?new Date(d.deliveredAt).toLocaleString('es-ES'):'Por confirmar'}" disabled></div><div class="full"><label data-gi=59a5e76017bb>Notas del conductor</label><textarea id="tNotes" rows="3" data-gi-placeholder=f1a7364d9867 placeholder="Reserva, ausencia, observación…">${esc(d.notes||'')}</textarea></div></div><button class="arcButton tmsBtn tmsLight" id="tNotesSave" data-gi=8ef3a65da8e0>Guardar notas</button></div></div>`);
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
