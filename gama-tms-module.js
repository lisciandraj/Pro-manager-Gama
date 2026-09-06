/* GAMA TMS V4 — gestión de transporte: planificación, conductores, POD, historial.
   Los datos viven en Supabase (tms_*), no en el navegador: una prueba de entrega
   es un documento probatorio y debe sobrevivir a un borrado de caché. */
(function(){
'use strict';
const LOCAL_KEY='gama-tms-v1', MIGRATED_KEY='gama_tms_migrated_v1';
const HISTORY_LIMIT=200, ARCHIVE_LIMIT=200, PHOTO_MAX_PX=1280, PHOTO_QUALITY=0.72;
const C=()=>window.GamaCloud;
const readLocal=(k,f)=>{try{return JSON.parse(localStorage.getItem(k)||JSON.stringify(f))}catch(e){return f}};
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const today=()=>new Date().toISOString().slice(0,10),now=()=>new Date().toISOString();
let db={deliveries:[],drivers:[],routes:[],history:[],archive:[],settings:{}};
let editingDriverId=null,proofArchiveId=null,proofCache={},loaded=false,currentTab='planning';

/* ---- mapeo cloud → forma interna (se conserva la del V3 para no tocar la UI) ---- */
const drvFrom=r=>({id:r.id,name:r.name,phone:r.phone||'',vehicle:r.vehicle||'',maxWeight:Number(r.max_weight||0),maxVolume:Number(r.max_volume||0),enabled:r.enabled!==false});
const delFrom=r=>({id:r.id,customer:r.customer,address:r.address,date:r.delivery_date,timeWindow:r.time_window||'',priority:r.priority||'Normal',weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Pendiente de preparación',lat:r.lat,lng:r.lng,routeId:r.route_id,driverId:r.driver_id,actualArrival:r.actual_arrival,deliveredAt:r.delivered_at,notes:r.notes||''});
const rtFrom=r=>({id:r.id,date:r.route_date,driverId:r.driver_id,driver:r.driver_name||'',vehicle:r.vehicle||'',stops:Array.isArray(r.stops)?r.stops:[],distance:Number(r.distance||0),weight:Number(r.weight||0),volume:Number(r.volume||0),status:r.status||'Planificada',createdAt:r.created_at});
const evFrom=r=>({id:r.id,at:r.at,deliveryId:r.delivery_id,type:r.type,note:r.note||'',customer:r.customer||''});

function fail(e,what){const m=e&&(e.message||e.error_description||e.details)||'Error desconocido';console.warn('[GAMA TMS]',what,e);alert(what+' : '+m);}
function findDelivery(id){return db.deliveries.find(d=>d.id===id)||db.archive.find(d=>d.id===id)||null}

/* ---- carga ---- */
async function fetchAll(){
 const api=C();if(!api)return;
 const t=today();
 const [drv,rt,del,ev,st,pf]=await Promise.all([
  api.list('tms_drivers',{order:'created_at',ascending:true}),
  api.list('tms_routes',{eq:{route_date:t},order:'created_at',ascending:true}),
  api.list('tms_deliveries',{eq:{delivery_date:t},order:'created_at',ascending:true}),
  api.list('tms_events',{order:'at',ascending:false,limit:HISTORY_LIMIT}),
  api.list('tms_settings',{limit:1}),
  // Sólo el índice: las fotos y firmas no viajan hasta que se abre una prueba.
  api.list('tms_proofs',{select:'delivery_id,captured_at',order:'captured_at',ascending:false,limit:ARCHIVE_LIMIT}),
 ]);
 db.drivers=(drv.data||[]).map(drvFrom);
 db.routes=(rt.data||[]).map(rtFrom);
 db.deliveries=(del.data||[]).map(delFrom);
 db.history=(ev.data||[]).map(evFrom);
 const s=(st.data||[])[0]||{};
 db.settings={depot:s.depot||'',returnDepot:s.return_depot!==false,depotPoint:(s.depot_lat!=null&&s.depot_lng!=null)?{id:'__depot',isDepot:true,address:s.depot||'Depósito',lat:s.depot_lat,lng:s.depot_lng}:null};
 const ids=(pf.data||[]).map(p=>p.delivery_id).filter(Boolean);
 if(ids.length){
  const arch=await api.list('tms_deliveries',{in:{id:ids},order:'delivered_at',ascending:false});
  db.archive=(arch.data||[]).map(delFrom);
 }else db.archive=[];
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
 // entregas y eventos, nunca conductores: los dos conductores de ejemplo que
 // crea seedDrivers() en un puesto vacío harían creer que ya hay una
 // migración hecha y este histórico se perdería sin avisar.
 const [exDel,exEv]=await Promise.all([api.list('tms_deliveries',{limit:1}),api.list('tms_events',{limit:1})]);
 if((exDel.data||[]).length||(exEv.data||[]).length){
  localStorage.setItem(MIGRATED_KEY,'1');
  // Nunca se borra gama-tms-v1: los datos siguen en este navegador.
  alert('El transporte ya tiene datos en la nube, subidos desde otro equipo.\n\nEl histórico guardado en este navegador no se ha importado para no duplicarlo. Sigue disponible aquí; contacta con el administrador si hay que recuperarlo.');
  return;
 }
 const drvMap={},delMap={};
 for(const d of old.drivers||[]){
  const r=await api.insert('tms_drivers',{name:d.name||'Conductor',phone:d.phone||null,vehicle:d.vehicle||'Vehículo',max_weight:Number(d.maxWeight||1000),max_volume:Number(d.maxVolume||5),enabled:d.enabled!==false});
  if(r.data)drvMap[d.id]=r.data.id;
 }
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
async function seedDrivers(){
 if(db.drivers.length)return;
 const api=C();
 await api.insert('tms_drivers',{name:'Conductor 1',vehicle:'Camión 1',max_weight:3500,max_volume:18,enabled:true});
 await api.insert('tms_drivers',{name:'Conductor 2',vehicle:'Furgoneta 2',max_weight:1200,max_volume:8,enabled:true});
}
async function ready(){
 if(loaded)return true;
 if(!C()){alert('El módulo de transporte necesita la conexión con la nube. Recarga la aplicación.');return false}
 try{
  await migrateLocalOnce();
  await fetchAll();
  if(!db.drivers.length){await seedDrivers();await fetchAll()}
  loaded=true;return true;
 }catch(e){fail(e,'No se pudieron cargar los datos de transporte');return false}
}
async function reload(tab){try{await fetchAll()}catch(e){fail(e,'No se pudo actualizar')}render(tab||currentTab)}
async function log(delivery,type,note){
 try{await C().insert('tms_events',{delivery_id:delivery.id,at:now(),type,note:note||null,customer:delivery.customer||null})}
 catch(e){console.warn('[GAMA TMS] evento no registrado',e)}
}

function styles(){if(document.getElementById('gama-tms-style'))return;const s=document.createElement('style');s.id='gama-tms-style';s.textContent=`
.tms{max-width:1280px;margin:auto}.tmsHead{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;margin-bottom:14px}.tmsHead h2{margin:0;font-size:26px}.tmsHead p{margin:4px 0;color:#71808a;font-size:13px}.tmsActions{display:flex;gap:8px;flex-wrap:wrap}.tmsBtn{border:0;border-radius:9px;padding:10px 13px;font-weight:800;cursor:pointer}.tmsPrimary{background:#087C8B;color:#fff}.tmsOrange{background:#F47A2A;color:#fff}.tmsLight{background:#EEF3F4;color:#18324A}.tmsDanger{background:#C94F45;color:#fff}.tmsTabs{display:flex;gap:6px;overflow:auto;margin-bottom:12px}.tmsTab{border:1px solid #dbe5e8;background:#fff;border-radius:999px;padding:9px 13px;font-weight:800;white-space:nowrap}.tmsTab.active{background:#087C8B;color:#fff}.tmsKpis{display:grid;grid-template-columns:repeat(6,1fr);gap:8px;margin-bottom:12px}.tmsKpi{background:#fff;border:1px solid #e2e8ec;border-radius:12px;padding:11px}.tmsKpi span{display:block;color:#71808a;font-size:10px;font-weight:700}.tmsKpi strong{font-size:20px;display:block;margin-top:4px}.tmsGrid{display:grid;grid-template-columns:1.1fr .9fr;gap:12px}.tmsCard{background:#fff;border:1px solid #e2e8ec;border-radius:14px;padding:14px;margin-bottom:12px;box-shadow:0 3px 16px #18324a0d}.tmsCard summary{cursor:pointer;font-weight:800;list-style:none}.tmsCard summary::-webkit-details-marker{display:none}.tmsCard summary:before{content:'▸ ';color:#087C8B}.tmsCard[open] summary:before{content:'▾ '}.tmsTitle{display:flex;justify-content:space-between;align-items:center;margin-bottom:10px}.tmsTitle b{font-size:14px}.tmsTitle small{color:#81909a}.tmsTable{width:100%;border-collapse:collapse}.tmsTable th,.tmsTable td{padding:8px;border-bottom:1px solid #edf1f2;text-align:left;font-size:11px;vertical-align:middle}.tmsTable th{font-size:10px;color:#71808a}.tmsBadge{display:inline-block;border-radius:999px;padding:4px 8px;background:#eef3f4;color:#18324a;font-size:10px;font-weight:800}.tmsBadge.ok{background:#e7f6f0;color:#138a69}.tmsBadge.warn{background:#fff0e5;color:#c75e18}.tmsBadge.red{background:#fff0ec;color:#c94f45}.tmsForm{display:grid;grid-template-columns:1fr 1fr;gap:8px}.tmsForm .full{grid-column:1/-1}.tmsForm label{display:block!important;font-size:10px!important;color:#61717c!important;margin:3px 0!important}.tmsForm input,.tmsForm select,.tmsForm textarea{width:100%;box-sizing:border-box;padding:9px!important;border:1px solid #d4e0e4;border-radius:8px;font-size:13px!important}.tmsRoute{border:1px solid #e4ebee;border-radius:11px;padding:10px;margin-bottom:10px}.tmsRouteHead{display:flex;justify-content:space-between;align-items:center;gap:8px}.tmsRouteHead b{font-size:13px}.tmsRouteHead small{color:#71808a}.tmsStop{display:grid;grid-template-columns:28px 1fr auto;gap:8px;align-items:center;border-top:1px solid #edf1f2;padding:9px 0}.tmsNum{width:25px;height:25px;border-radius:50%;display:grid;place-items:center;background:#e8f5f6;color:#087C8B;font-weight:900}.tmsStop b{font-size:12px}.tmsStop small{display:block;color:#81909a;margin-top:2px}.tmsStop strong{font-size:10px;color:#F47A2A;text-align:right}.tmsTimeline{border-left:2px solid #dce7ea;margin-left:6px;padding-left:12px}.tmsEvent{position:relative;margin:0 0 12px}.tmsEvent:before{content:'';position:absolute;left:-19px;top:4px;width:9px;height:9px;border-radius:50%;background:#087C8B}.tmsEvent b{font-size:11px}.tmsEvent small{display:block;color:#81909a;font-size:10px;margin-top:2px}.tmsProof{display:grid;grid-template-columns:1fr 1fr;gap:10px}.tmsProof img{max-width:100%;border-radius:8px;border:1px solid #dbe5e8}.tmsSig{width:100%;height:160px;border:1px dashed #b9cbd0;border-radius:9px;background:#fff;touch-action:none}.tmsEmpty{padding:25px;text-align:center;color:#81909a}.tmsLive{display:inline-flex;align-items:center;gap:6px}.tmsLive i{width:8px;height:8px;border-radius:50%;background:#138a69;display:inline-block}.tmsPrint{display:none}@media print{.tmsPrint{display:block}.tmsNoPrint{display:none!important}.tmsCard{box-shadow:none}.tmsGrid{display:block}}@media(max-width:900px){.tmsGrid{grid-template-columns:1fr}.tmsKpis{grid-template-columns:repeat(3,1fr)}}@media(max-width:600px){.tmsHead{flex-direction:column}.tmsKpis{grid-template-columns:1fr 1fr}.tmsForm,.tmsProof{grid-template-columns:1fr}.tmsForm .full{grid-column:auto}.tmsTable{display:block;overflow:auto;white-space:nowrap}}
`;document.head.appendChild(s)}
function section(){let x=document.getElementById('gama-tms-section');if(x)return x;x=document.createElement('section');x.id='gama-tms-section';x.style.display='none';(document.querySelector('.wrap')||document.body).appendChild(x);return x}
function showSection(){document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.display='none'});const x=section();x.classList.add('active');x.style.display='block';document.getElementById('mainmenu')?.setAttribute('hidden','');return x}

async function open(tab){
 styles();
 const x=showSection();
 tab=tab||'planning';
 currentTab=tab;
 if(tab!=='fleet')editingDriverId=null;
 GamaPage.reset('tmsDeliveries');GamaPage.reset('tmsHistory');
 x.innerHTML='<div class="tms"><div class="tmsEmpty">Cargando datos de transporte…</div></div>';
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
 const pending=db.deliveries.filter(d=>d.date===today()&&!['Entregada','Cancelada'].includes(d.status));
 if(!pending.length){alert('No hay entregas para optimizar hoy.');return}
 const drivers=db.drivers.filter(x=>x.enabled!==false);
 if(!drivers.length){alert('Añada al menos un conductor/vehículo.');return}
 for(const d of pending)await geocode(d);
 try{
  // Se rehacen las rutas del día que aún no están terminadas.
  for(const r of db.routes.filter(r=>r.date===today()&&r.status!=='Terminada'))await api.remove('tms_routes',r.id);
  let rem=pending.slice(),created=0;
  for(const dr of drivers){
   if(!rem.length)break;
   const r=routeFor(rem,dr);
   const stops=r.stops.filter(x=>x.id&&!x.isDepot);
   if(!stops.length)continue;
   const route=await api.insert('tms_routes',{route_date:today(),driver_id:dr.id,driver_name:dr.name,vehicle:dr.vehicle,stops:r.stops.map(x=>x.isDepot?'__depot':x.id),distance:r.distance,weight:r.weight,volume:r.volume,status:'Planificada'});
   if(!route.data)continue;
   created++;
   for(const s of stops)await api.update('tms_deliveries',s.id,{route_id:route.data.id,driver_id:dr.id,status:'Planificada'});
   const used=new Set(stops.map(x=>x.id));
   rem=rem.filter(x=>!used.has(x.id));
  }
  for(const d of rem){await api.update('tms_deliveries',d.id,{status:'Excepción'});await log(d,'CAPACIDAD','No hay capacidad disponible para esta entrega')}
  await reload('planning');
  alert(created+' ruta(s) creada(s).'+(rem.length?' '+rem.length+' entrega(s) en excepción.':''));
 }catch(e){fail(e,'No se pudieron crear las rutas')}
}
async function addDelivery(){
 const f=id=>document.getElementById(id);
 const customer=f('tCustomer').value.trim(),address=f('tAddress').value.trim();
 if(!customer||!address){alert('El cliente y la dirección son obligatorios.');return}
 try{
  const r=await C().insert('tms_deliveries',{customer,address,delivery_date:f('tDate').value||today(),time_window:f('tWindow')?.value.trim()||null,priority:f('tPriority')?.value||'Normal',weight:+(f('tWeight')?.value)||0,volume:+(f('tVolume')?.value)||0,status:'Pendiente de preparación'});
  if(r.data)await log(delFrom(r.data),'Creada');
  await reload('planning');
 }catch(e){fail(e,'No se pudo crear la entrega')}
}
async function saveDriver(){
 const f=id=>document.getElementById(id);
 const row={name:f('dName').value.trim()||'Conductor',phone:f('dPhone').value.trim()||null,vehicle:f('dVehicle').value.trim()||'Vehículo',max_weight:+f('dWeight').value||1000,max_volume:+f('dVolume').value||5};
 try{
  if(editingDriverId){
   await C().update('tms_drivers',editingDriverId,row);
   for(const r of db.routes.filter(r=>r.driverId===editingDriverId))await C().update('tms_routes',r.id,{driver_name:row.name,vehicle:row.vehicle});
   editingDriverId=null;
  }else await C().insert('tms_drivers',Object.assign({enabled:true},row));
  await reload('fleet');
 }catch(e){fail(e,'No se pudo guardar el conductor')}
}
function editDriver(id){editingDriverId=id;render('fleet')}
function cancelDriverEdit(){editingDriverId=null;render('fleet')}
async function deleteDriver(id){
 if(db.routes.some(r=>r.driverId===id&&r.date===today()&&r.status!=='Terminada')){alert('Este conductor tiene una ruta activa hoy. Finaliza o cancela su ruta antes de eliminarlo.');return}
 const d=db.drivers.find(x=>x.id===id);
 if(!d||!confirm('¿Eliminar a '+d.name+' y su vehículo '+d.vehicle+'?'))return;
 try{await C().remove('tms_drivers',id);if(editingDriverId===id)editingDriverId=null;await reload('fleet')}
 catch(e){fail(e,'No se pudo eliminar el conductor')}
}
async function toggleDriver(id){
 const d=db.drivers.find(x=>x.id===id);if(!d)return;
 try{await C().update('tms_drivers',id,{enabled:d.enabled===false});await reload('fleet')}
 catch(e){fail(e,'No se pudo cambiar el estado')}
}

/* Las fotos de móvil pesan varios MB en base64. Se reducen antes de subirlas:
   una POD legible cabe de sobra en 1280 px, y así la tabla no se llena de
   payloads gigantes que habría que descargar en cada consulta. */
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
  const prev=await ensureProof(id);
  await C().upsert('tms_proofs',{delivery_id:id,photo,signature:prev?.signature||null,captured_at:now()},{onConflict:'delivery_id'});
  proofCache[id]={delivery_id:id,photo,signature:prev?.signature||null};
  renderProofDetail(id);
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
 document.getElementById('tSigSave').onclick=async()=>{
  const signature=c.toDataURL('image/png'),stamp=now();
  try{
   const prev=await ensureProof(d.id);
   await C().upsert('tms_proofs',{delivery_id:d.id,photo:prev?.photo||null,signature,captured_at:stamp},{onConflict:'delivery_id'});
   proofCache[d.id]={delivery_id:d.id,photo:prev?.photo||null,signature};
   await C().update('tms_deliveries',d.id,{status:'Entregada',actual_arrival:d.actualArrival||stamp,delivered_at:stamp});
   await log(d,'Entregada','Prueba de entrega registrada');
   proofArchiveId=d.id;
   await reload('tracking');
   alert('Prueba de entrega registrada.');
  }catch(e){fail(e,'No se pudo registrar la prueba de entrega')}
 };
}
async function viewProofArchive(id){proofArchiveId=id;await ensureProof(id);render('proof')}
async function saveDepot(){
 const x=section();
 try{
  await C().upsert('tms_settings',{id:true,depot:x.querySelector('#tDepot').value.trim()||null,return_depot:x.querySelector('#tReturn').value==='1',updated_at:now()},{onConflict:'id'});
  await fetchAll();
  alert('Parámetros guardados.');
 }catch(e){fail(e,'No se pudieron guardar los parámetros')}
}

function render(tab){
 currentTab=tab;
 const x=section(),ds=db.deliveries.filter(d=>d.date===today()),pending=ds.filter(d=>!['Entregada','Cancelada'].includes(d.status)).length,del=ds.filter(d=>d.status==='Entregada').length,exceptions=ds.filter(d=>d.status==='Excepción').length,planned=db.routes.filter(r=>r.date===today()&&r.status!=='Terminada').length;
 const tabs=[['planning','Planificación'],['tracking','Seguimiento del conductor'],['proof','Prueba de entrega'],['fleet','Conductores y vehículos'],['history','Historial']];
 let body='';
if(tab==='planning')body=`<div class="tmsGrid"><div><div class="tmsCard"><div class="tmsTitle"><b>Nueva entrega</b><small>Pedidos / preparación</small></div><div class="tmsForm"><div><label>Cliente</label><input id="tCustomer" placeholder="Nombre del cliente"></div><div><label>Fecha</label><input id="tDate" type="date" value="${today()}"></div><div class="full"><label>Dirección</label><input id="tAddress" placeholder="Calle, número, CP, ciudad, país"></div></div><details style="margin-top:8px"><summary>Detalles opcionales (franja horaria, prioridad, carga)</summary><div class="tmsForm" style="margin-top:8px"><div><label>Franja horaria</label><input id="tWindow" placeholder="08:00–10:00"></div><div><label>Prioridad</label><select id="tPriority"><option>Normal</option><option>Alta</option><option>Urgente</option></select></div><div><label>Peso (kg)</label><input id="tWeight" type="number" min="0"></div><div><label>Volumen (m³)</label><input id="tVolume" type="number" min="0" step="0.01"></div></div></details><button class="tmsBtn tmsPrimary" id="tAdd" style="margin-top:10px">Añadir entrega</button></div><div class="tmsCard"><div class="tmsTitle"><b>Entregas de hoy</b><small>${ds.length} en total</small></div>${ds.length?`<table class="tmsTable"><thead><tr><th>Cliente</th><th>Franja</th><th>Carga</th><th>Estado</th></tr></thead><tbody>${GamaPage.slice('tmsDeliveries',ds).map(d=>`<tr><td><b>${esc(d.customer)}</b><br><small>${esc(d.address)}</small></td><td>${esc(d.timeWindow||'—')}</td><td>${d.weight||0} kg / ${d.volume||0} m³</td><td><span class="tmsBadge ${d.status==='Entregada'?'ok':d.status==='Excepción'?'red':'warn'}">${esc(status(d))}</span></td></tr>`).join('')}</tbody></table>${GamaPage.controls('tmsDeliveries',ds.length)}`:'<div class="tmsEmpty">No hay entregas hoy.</div>'}</div></div><div><div class="tmsCard"><div class="tmsTitle"><b>Optimizar rutas de hoy</b><span class="tmsLive"><i></i> Sincronizado en la nube</span></div><p style="font-size:12px;color:#71808a">Reparte las entregas de hoy entre tus conductores según capacidad y cercanía, con un clic.</p><button class="tmsBtn tmsOrange" id="tOptimize">Optimizar todas las rutas</button><div style="margin-top:10px">${db.routes.filter(r=>r.date===today()).map(r=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(r.driver)} · ${esc(r.vehicle)}</b><small>${r.distance.toFixed(1)} km · ${r.weight||0} kg</small></div><p style="font-size:10px;color:#81909a">${routeStops(r).filter(s=>!s.isDepot).length} paradas · ${esc(r.status)}</p><button class="tmsBtn tmsLight" onclick="gamaTMS.open('tracking')">Ver ruta</button> <button class="tmsBtn tmsLight" onclick="window.open('${mapsUrl(r)}','_blank')">Google Maps</button></div>`).join('')||'<div class="tmsEmpty">No hay rutas planificadas.</div>'}</div></div><details class="tmsCard"><summary>⚙️ Configuración avanzada del depósito</summary><div class="tmsForm" style="margin-top:10px"><div class="full"><label>Dirección del depósito</label><input id="tDepot" value="${esc(db.settings?.depot||'')}" placeholder="Dirección de salida / regreso"></div><div><label>Regreso al depósito</label><select id="tReturn"><option value="1"${db.settings?.returnDepot!==false?' selected':''}>Sí</option><option value="0"${db.settings?.returnDepot===false?' selected':''}>No</option></select></div></div><button class="tmsBtn tmsLight" id="tSaveDepot" style="margin-top:8px">Guardar</button></details></div></div>`;
if(tab==='tracking')body=`<div class="tmsGrid"><div><div class="tmsCard"><div class="tmsTitle"><b>Seguimiento de las rutas</b><small>${planned} activa(s)</small></div>${db.routes.filter(r=>r.date===today()).map(r=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(r.driver)} · ${esc(r.vehicle)}</b><small>${r.distance.toFixed(1)} km · ${esc(r.status)}</small></div>${routeStops(r).filter(s=>!s.isDepot).map((d,i)=>`<div class="tmsStop"><span class="tmsNum">${i+1}</span><div><b>${esc(d.customer)}</b><small>${esc(d.address)}${d.timeWindow?' · '+esc(d.timeWindow):''}</small></div><strong>${esc(d.status)}<br>${d.actualArrival?new Date(d.actualArrival).toLocaleTimeString():''}</strong></div><div><button class="tmsBtn tmsPrimary" onclick="gamaTMS.openProof('${d.id}')">POD</button></div>`).join('')}</div>`).join('')||'<div class="tmsEmpty">No hay rutas hoy.</div>'}</div></div><div><div class="tmsCard"><div class="tmsTitle"><b>Eventos recientes</b><span class="tmsLive"><i></i> Sincronizado en la nube</span></div><div class="tmsTimeline">${db.history.slice(0,12).map(h=>`<div class="tmsEvent"><b>${esc(h.type)} · ${esc(h.customer)}</b><small>${new Date(h.at).toLocaleString()} ${esc(h.note)}</small></div>`).join('')||'<div class="tmsEmpty">No hay eventos.</div>'}</div></div></div></div>`;
if(tab==='proof'){
 const toCapture=ds.filter(d=>d.status!=='Entregada');
 const delivered=archiveList();
 const selId=defaultProofId();
 const sel=delivered.find(d=>d.id===selId);
 const pr=sel?proofCache[sel.id]:null;
 body=`<div class="tmsGrid"><div class="tmsCard"><div class="tmsTitle"><b>Entregas pendientes de prueba</b><small>${toCapture.length}</small></div>${toCapture.map(d=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(d.customer)}</b><small>${esc(d.address)}</small></div><button class="tmsBtn tmsPrimary" onclick="gamaTMS.openProof('${d.id}')">Abrir prueba de entrega</button></div>`).join('')||'<div class="tmsEmpty">Todas las entregas de hoy están terminadas.</div>'}</div><div class="tmsCard"><div class="tmsTitle"><b>Archivo de pruebas de entrega</b><small>${delivered.length}</small></div>${delivered.length?`<label>Selecciona una entrega</label><select id="tProofSelect">${delivered.map(d=>`<option value="${d.id}" ${d.id===selId?'selected':''}>${new Date(d.deliveredAt||d.date).toLocaleDateString('es-ES')} — ${esc(d.customer)}</option>`).join('')}</select>${sel?`<div class="tmsProof" style="margin-top:12px"><div>${pr?.photo?`<img src="${pr.photo}">`:'<div class="tmsEmpty">Sin foto</div>'}</div><div>${pr?.signature?`<img src="${pr.signature}">`:'<div class="tmsEmpty">Sin firma</div>'}</div></div><p style="font-size:12px;color:#71808a;margin-top:8px">Entregado: ${sel.deliveredAt?new Date(sel.deliveredAt).toLocaleString('es-ES'):'-'} · ${esc(sel.address)}${sel.notes?' · '+esc(sel.notes):''}</p>`:''}`:'<div class="tmsEmpty">Aún no hay pruebas de entrega archivadas.</div>'}</div></div>`;
}
if(tab==='fleet'){
 const editing=editingDriverId?db.drivers.find(x=>x.id===editingDriverId):null;
 body=`<div class="tmsGrid"><div class="tmsCard"><div class="tmsTitle"><b>Conductores y vehículos</b><small>${db.drivers.length}</small></div>${db.drivers.map(d=>`<div class="tmsRoute"><div class="tmsRouteHead"><b>${esc(d.name)}</b><small>${esc(d.vehicle)}</small></div><p style="font-size:11px">${d.maxWeight} kg · ${d.maxVolume} m³ ${d.phone?'· '+esc(d.phone):''}</p><div style="display:flex;gap:6px;flex-wrap:wrap"><button class="tmsBtn tmsLight" onclick="gamaTMS.toggleDriver('${d.id}')">${d.enabled===false?'Activar':'Desactivar'}</button><button class="tmsBtn tmsLight" onclick="gamaTMS.editDriver('${d.id}')">✏️ Editar</button><button class="tmsBtn tmsDanger" onclick="gamaTMS.deleteDriver('${d.id}')">🗑️ Eliminar</button></div></div>`).join('')||'<div class="tmsEmpty">Añade tu primer conductor y vehículo.</div>'}</div><div class="tmsCard"><div class="tmsTitle"><b>${editing?'Editar conductor':'Añadir un conductor'}</b></div><div class="tmsForm"><div><label>Nombre</label><input id="dName" value="${esc(editing?.name||'')}"></div><div><label>Teléfono</label><input id="dPhone" value="${esc(editing?.phone||'')}"></div><div><label>Vehículo</label><input id="dVehicle" placeholder="Camión 3" value="${esc(editing?.vehicle||'')}"></div><div><label>Capacidad kg</label><input id="dWeight" type="number" value="${editing?editing.maxWeight:1000}"></div><div><label>Capacidad m³</label><input id="dVolume" type="number" step="0.1" value="${editing?editing.maxVolume:5}"></div></div><div style="display:flex;gap:8px;margin-top:8px"><button class="tmsBtn tmsPrimary" id="dAdd">${editing?'Guardar cambios':'Añadir'}</button>${editing?'<button class="tmsBtn tmsLight" id="dCancelEdit">Cancelar</button>':''}</div></div></div>`;
}
if(tab==='history')body=`<div class="tmsCard"><div class="tmsTitle"><b>Historial de rutas y entregas</b><small>${db.history.length} eventos</small></div>${db.history.length?`<table class="tmsTable"><thead><tr><th>Fecha</th><th>Cliente</th><th>Evento</th><th>Detalle</th></tr></thead><tbody>${GamaPage.slice('tmsHistory',db.history).map(h=>`<tr><td>${new Date(h.at).toLocaleString('es-ES')}</td><td>${esc(h.customer)}</td><td><span class="tmsBadge">${esc(h.type)}</span></td><td>${esc(h.note)}</td></tr>`).join('')}</tbody></table>${GamaPage.controls('tmsHistory',db.history.length)}`:'<div class="tmsEmpty">No hay historial.</div>'}</div>`;
 x.innerHTML=`<div class="tms"><div class="tmsHead"><div><h2>🚚 GAMA TMS</h2><p>Planificación · rutas · seguimiento del conductor · prueba de entrega</p></div><div class="tmsActions tmsNoPrint"><button class="tmsBtn tmsLight" onclick="gamaStandardBackToMenu?gamaStandardBackToMenu():showTab('mainmenu',null)">← Menú</button><button class="tmsBtn tmsOrange" onclick="gamaTMS.open('planning')">Optimizar</button></div></div><div class="tmsKpis"><div class="tmsKpi"><span>Entregas</span><strong>${ds.length}</strong></div><div class="tmsKpi"><span>Pendientes</span><strong>${pending}</strong></div><div class="tmsKpi"><span>Entregadas</span><strong>${del}</strong></div><div class="tmsKpi"><span>Excepciones</span><strong>${exceptions}</strong></div><div class="tmsKpi"><span>Rutas</span><strong>${planned}</strong></div><div class="tmsKpi"><span>Estado</span><strong>CLOUD</strong></div></div><div class="tmsTabs">${tabs.map(t=>`<button class="tmsTab ${tab===t[0]?'active':''}" onclick="gamaTMS.open('${t[0]}')">${t[1]}</button>`).join('')}</div>${body}</div><div class="tmsPrint"><h2>GAMA TMS — hoja de ruta</h2>${db.routes.filter(r=>r.date===today()).map(r=>`<h3>${esc(r.driver)} · ${esc(r.vehicle)}</h3>${routeStops(r).filter(s=>!s.isDepot).map((d,i)=>`<p>${i+1}. <b>${esc(d.customer)}</b> — ${esc(d.address)}</p>`).join('')}`).join('')}</div>`;
 const add=x.querySelector('#tAdd');if(add)add.onclick=addDelivery;
 const opt=x.querySelector('#tOptimize');if(opt)opt.onclick=optimize;
 const da=x.querySelector('#dAdd');if(da)da.onclick=saveDriver;
 const dc=x.querySelector('#dCancelEdit');if(dc)dc.onclick=cancelDriverEdit;
 const ps=x.querySelector('#tProofSelect');if(ps)ps.onchange=()=>viewProofArchive(ps.value);
 const sd=x.querySelector('#tSaveDepot');if(sd)sd.onclick=saveDepot;
}
function mapsUrl(r){const s=routeStops(r),valid=s.filter(x=>!x.isDepot||x.address);if(valid.length<2)return '#';const o=encodeURIComponent(valid[0].address),dest=encodeURIComponent(valid[valid.length-1].address),wp=valid.slice(1,-1).map(x=>encodeURIComponent(x.address)).join('|');return'https://www.google.com/maps/dir/?api=1&origin='+o+'&destination='+dest+(wp?'&waypoints='+wp:'')+'&travelmode=driving'}
async function openProof(id){
 if(!await ready())return;
 const d=findDelivery(id);if(!d)return;
 await ensureProof(id);
 renderProofDetail(id);
}
function renderProofDetail(id){
 const d=findDelivery(id);if(!d)return;
 const pr=proofCache[id]||null;
 const x=section();
 x.innerHTML=`<div class="tms"><div class="tmsHead"><div><h2>📦 Prueba de entrega</h2><p>${esc(d.customer)} · ${esc(d.address)}</p></div><button class="tmsBtn tmsLight" onclick="gamaTMS.open('tracking')">← Volver</button></div><div class="tmsGrid"><div class="tmsCard"><div class="tmsTitle"><b>Foto de entrega</b><small>Cámara del teléfono</small></div><input id="tPhoto" type="file" accept="image/*" capture="environment"><p class="muted" style="font-size:11px;margin:6px 0 0">La foto se guarda automáticamente en la nube al tomarla o seleccionarla.</p>${pr?.photo?'<img src="'+pr.photo+'" style="display:block;max-width:100%;margin-top:10px;border-radius:8px">':''}</div><div class="tmsCard"><div class="tmsTitle"><b>Firma del cliente</b><small>Firma manuscrita</small></div><canvas id="tSig" class="tmsSig" width="700" height="300"></canvas><div style="margin-top:8px"><button class="tmsBtn tmsLight" id="tSigClear">Borrar</button> <button class="tmsBtn tmsPrimary" id="tSigSave">Validar entrega</button></div></div></div><div class="tmsCard"><div class="tmsTitle"><b>Información de entrega</b></div><div class="tmsForm"><div><label>Hora real de llegada</label><input value="${d.actualArrival?new Date(d.actualArrival).toLocaleString('es-ES'):'Se registrará al validar'}" disabled></div><div><label>Hora de entrega</label><input value="${d.deliveredAt?new Date(d.deliveredAt).toLocaleString('es-ES'):'Por confirmar'}" disabled></div><div class="full"><label>Notas del conductor</label><textarea id="tNotes" rows="3" placeholder="Reserva, ausencia, observación…">${esc(d.notes||'')}</textarea></div></div><button class="tmsBtn tmsLight" id="tNotesSave">Guardar notas</button></div></div>`;
 setupSignature(document.getElementById('tSig'),d);
 document.getElementById('tPhoto').onchange=()=>captureProof(id);
 document.getElementById('tNotesSave').onclick=async()=>{
  const notes=document.getElementById('tNotes').value;
  try{await C().update('tms_deliveries',id,{notes});d.notes=notes;alert('Notas guardadas.')}
  catch(e){fail(e,'No se pudieron guardar las notas')}
 };
}
GamaPage.register('tmsDeliveries',()=>render('planning'));GamaPage.register('tmsHistory',()=>render('history'));
window.gamaTMS={open,openProof,toggleDriver,editDriver,cancelDriverEdit,deleteDriver,viewProofArchive};
})();
