/* GAMA — Gestión de flota: coches de empresa y camiones de transporte.

   La regla del módulo: el kilometraje se teclea una sola vez. Se captura al
   repostar o al pasar por el taller, y el vehículo lo sigue solo; nadie tiene
   que acordarse de actualizarlo aparte. Lo mismo con el consumo y el coste por
   kilómetro: no se escriben, salen de los repostajes.

   Los importes se formatean con GamaCurrency, nunca con un símbolo escrito a
   mano: la divisa es un dato de la empresa, no una constante del código. */
(function(){
'use strict';
if(window.GamaFleet)return;
const ID='fleet',$=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const money=v=>window.GamaCurrency.format(v);
const num=(v,d)=>window.GamaCurrency.number(v,d);
const allowed=()=>!!window.gamaAccessAllowed?.(ID);
const day=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const monthStart=()=>day().slice(0,8)+'01';

const SECTIONS=[['dashboard','Tablero'],['vehicles','Vehículos'],['drivers','Conductores'],['deadlines','Vencimientos']];
const KIND={car:'Coche',truck:'Camión'};
const STATUS={in_service:'En servicio',repair:'En reparación',out_of_service:'Fuera de servicio'};
const ENERGY={diesel:'Diésel',petrol:'Gasolina',electric:'Eléctrico',hybrid:'Híbrido',lpg:'GLP',cng:'GNC',other:'Otra'};
const DOCKIND={insurance:'Seguro',technical_inspection:'Inspección técnica',registration:'Permiso de circulación'};
const MAINTKIND={service:'Revisión',repair:'Reparación',tyres:'Neumáticos'};
/* Un vencimiento no dice lo mismo según de dónde venga: el permiso es de la
   persona, los papeles y la revisión son del vehículo. */
const DEADLINE={licence:'Permiso de conducir',document_insurance:'Seguro',
 document_technical_inspection:'Inspección técnica',document_registration:'Permiso de circulación',
 service_date:'Revisión prevista (fecha)',service_km:'Revisión prevista (kilometraje)'};
const ERRORS={ROLE_NOT_ALLOWED:'La flota es un módulo de administración: tu perfil no tiene acceso.',
 AUTH_REQUIRED:'Vuelve a iniciar sesión para continuar.',
 VEHICLE_NOT_FOUND:'Ese vehículo ya no existe. Actualiza la lista.',
 DRIVER_NOT_FOUND:'Ese conductor ya no existe. Actualiza la lista.',
 DOCUMENT_NOT_FOUND:'Ese documento ya no existe. Actualiza la ficha.',
 NO_ASSIGNMENT:'El vehículo no tiene ningún conductor asignado.',
 FILE_TOO_LARGE:'El archivo pesa demasiado. El máximo son 2,5 MB.',
 INVALID_PERIOD:'La fecha de fin es anterior a la de inicio.',
 INVALID_ACTION:'Esa operación no existe en este módulo.',
 NOT_FOUND:'El registro ya no existe. Actualiza la pantalla.'};
function err(e){
 const s=String(e?.message||e);
 for(const[k,v]of Object.entries(ERRORS)){if(s.includes(k))return v;if(s===v)return v}
 /* Dos índices únicos distintos, y decir «matrícula» ante los dos manda a
    corregir el campo equivocado. */
 if(/fleet_driver_employee/i.test(s))return 'Ese empleado ya tiene una ficha de conductor. Modifícala en vez de crear otra.';
 if(/duplicate key|unique/i.test(s))return 'Esa matrícula ya está registrada en otro vehículo.';
 if(/check constraint|violates check/i.test(s))return 'Revisa los datos: hay un valor fuera de lo admitido.';
 return 'No se pudo completar la operación. Inténtalo de nuevo.';
}

let section='dashboard',state={},generation=0,vehicleId=null,tab='info',filters={status:'',kind:'',search:''};

async function rpc(action,data={}){
 if(!allowed())throw Error('ROLE_NOT_ALLOWED');
 await window.GamaCloudReady;
 const c=await GamaCloud.db();
 const r=await c.rpc('gama_fleet_action',{p_action:action,p_data:data});
 if(r.error)throw Error(err(r.error));
 if(r.data==null)throw Error('EMPTY');
 return r.data;
}
async function mutate(action,data){const r=await rpc(action,data);
 window.dispatchEvent(new CustomEvent('gama:fleet-change'));return r}

function css(){
 if($('gfStyle'))return;const s=document.createElement('style');s.id='gfStyle';
 /* Mismos radios, mismos grises y el mismo verde azulado que el resto de GAMA.
    Los campos miden 16 px y 42 px de alto en todas partes: por debajo de eso el
    móvil hace zoom al tocarlos y el formulario deja de ser usable de pie, que
    es justo donde se rellena un repostaje. */
 s.textContent=`#fleet{display:none}#fleet.active{display:block}
.gfNav{display:flex;gap:6px;overflow:auto;margin:14px 0;padding-bottom:4px}
.gfNav button{border:1px solid #cbd8df;background:#fff;color:#18324a;border-radius:999px;padding:9px 14px;font-weight:800;white-space:nowrap;cursor:pointer;min-height:42px}
.gfNav button.on{background:#087c8b;border-color:#087c8b;color:#fff}
.gfCard{background:#fff;border:1px solid #cbd8df;border-radius:13px;padding:17px;margin:12px 0;overflow-wrap:anywhere}
.gfCard h3{margin:0 0 10px;font-size:16px;color:#18324a}
.gfKpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(165px,1fr));gap:12px;margin:14px 0}
.gfKpis .gfCard{margin:0}
.gfKpis small{display:block;color:#526975;font-size:12px;font-weight:700}
.gfKpis strong{display:block;font-size:24px;margin-top:7px;color:#18324a}
.gfKpis em{display:block;font-style:normal;font-size:12px;color:#526975;margin-top:5px}
.gfTools{display:flex;gap:10px;flex-wrap:wrap;align-items:end;margin:12px 0}
.gfTools label{flex:1;min-width:160px;font-size:13px;color:#18324a;font-weight:700}
.gfTools input,.gfTools select{width:100%;font-size:16px;min-height:42px;border:1px solid #cbd8df;border-radius:9px;padding:9px;background:#fff;color:#18324a}
.gfScroll{overflow:auto}
.gfTable{width:100%;border-collapse:collapse;min-width:620px}
.gfTable th,.gfTable td{text-align:left;padding:11px;border-bottom:1px solid #bacbd5;vertical-align:top;font-size:13px}
.gfTable th{font-size:12px;color:#37505f;font-weight:800}
.gfTable tbody tr:nth-child(even){background:#eef4f7}
.gfTable td.gfNum,.gfTable th.gfNum{text-align:right;white-space:nowrap}
.gfBadge{display:inline-block;border-radius:18px;padding:4px 10px;background:#edf2f6;color:#304c60;font-weight:700;font-size:12px}
.gfBadge[data-s=in_service]{background:#dcf4e7;color:#12633e}
.gfBadge[data-s=repair]{background:#fff0da;color:#914900}
.gfBadge[data-s=out_of_service]{background:#eceff1;color:#5c6b73}
.gfBadge[data-s=car]{background:#e7effa;color:#1d4171}
.gfBadge[data-s=truck]{background:#efe7fa;color:#4a2a7a}
.gfActions{display:flex;gap:9px;flex-wrap:wrap;margin-top:11px}
.gfActions button{min-height:42px}
.gfHint{font-size:13px;color:#526975;margin:7px 0}
.gfError{color:#a32318;font-weight:700}
.gfGrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:11px}
.gfGrid label,.gfField{font-size:13px;color:#18324a;font-weight:700;display:block}
.gfField{margin-top:11px}
.gfGrid input,.gfGrid select,.gfGrid textarea,.gfField input,.gfField select,.gfField textarea{width:100%;box-sizing:border-box;font-size:16px;min-height:42px;border:1px solid #cbd8df;border-radius:9px;padding:9px;background:#fff;color:#18324a}
.gfCards{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:12px}
.gfGrid[hidden],.gfCard[hidden]{display:none}
.gfVeh{border:1px solid #cbd8df;border-radius:13px;background:#fff;padding:0;overflow:hidden;text-align:left;cursor:pointer;font:inherit;color:inherit;display:flex;flex-direction:column}
.gfVeh:hover,.gfVeh:focus-visible{border-color:#087c8b;box-shadow:0 0 0 2px rgba(8,124,139,.16)}
.gfVeh figure{margin:0;height:120px;background:#eef4f7 center/cover no-repeat;display:flex;align-items:center;justify-content:center;font-size:38px}
.gfVeh .gfVehBody{padding:13px}
.gfVeh b{display:block;font-size:16px;color:#18324a}
.gfVeh span{display:block;font-size:13px;color:#526975;margin-top:3px}
.gfVeh .gfVehMeta{display:flex;gap:6px;flex-wrap:wrap;margin-top:9px}
.gfTabs{display:flex;gap:6px;overflow:auto;margin:14px 0;padding-bottom:4px}
.gfTabs button{border:1px solid #cbd8df;background:#fff;color:#18324a;border-radius:9px;padding:9px 14px;font-weight:800;white-space:nowrap;cursor:pointer;min-height:42px}
.gfTabs button.on{background:#18324a;border-color:#18324a;color:#fff}
.gfPhoto{width:100%;max-width:340px;border-radius:11px;border:1px solid #cbd8df;display:block}
.gfDl{display:grid;grid-template-columns:auto 1fr;gap:6px 14px;font-size:14px;margin:0}
.gfDl dt{color:#526975;font-weight:700}
.gfDl dd{margin:0;color:#18324a}
.gfDue{border-left:5px solid #cbd8df;padding-left:11px}
.gfDue[data-urgency=soon]{border-left-color:#e58b22}
.gfDue[data-urgency=now]{border-left-color:#a32318}
.gfDanger{border:1px solid #f0c8c4;background:#fff6f5;border-radius:9px;padding:11px;margin-top:11px}
.gfQuick{display:flex;gap:9px;flex-wrap:wrap;margin:12px 0}
.gfQuick button{flex:1;min-width:150px;min-height:48px;font-weight:800}
@media(max-width:700px){.gfKpis{grid-template-columns:1fr 1fr}.gfKpis strong{font-size:20px}
 .gfTable{min-width:520px}.gfTools label{min-width:130px}.gfCards{grid-template-columns:1fr}}
@media(max-width:430px){.gfKpis{grid-template-columns:1fr}.gfDl{grid-template-columns:1fr}
 .gfDl dd{margin-bottom:6px}}`;
 document.head.appendChild(s);
}
function shell(){
 css();let s=$(ID);
 if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 s.innerHTML=GamaUI.header({title:'🚚 Gestión de flota',lead:'Tus coches y camiones: papeles, consumos y revisiones.'})
  +'<nav class="gfNav" id="gfNav"></nav><div id="gfMain" aria-live="polite"></div>';
 GamaUI.bindBack(s);window.showTab?.(ID);
 return s;
}
function nav(){
 const host=$('gfNav');if(!host)return;
 host.innerHTML=SECTIONS.map(([k,label])=>`<button type="button" data-gi-live data-gf-section="${k}" class="${section===k&&!vehicleId?'on':''}" aria-current="${section===k&&!vehicleId?'page':'false'}">${esc(label)}</button>`).join('');
 host.querySelectorAll('[data-gf-section]').forEach(b=>b.onclick=()=>{vehicleId=null;go(b.dataset.gfSection)});
}
function busy(){$('gfMain').innerHTML=`<p class="gfCard">${tr('Cargando…')}</p>`}
function fail(e,retry){
 $('gfMain').innerHTML=`<div class="gfCard"><p class="gfError" role="alert">${esc(err(e))}</p>
 <button class="secondary" id="gfRetry">${tr('Actualizar')}</button></div>`;
 $('gfRetry').onclick=retry;
}
function badge(map,v){return `<span class="gfBadge" data-s="${esc(v)}">${tr(map[v]||v)}</span>`}
function kpi(label,value,hint){
 return `<div class="gfCard"><small>${tr(label)}</small><strong>${esc(value)}</strong>${hint?`<em>${hint}</em>`:''}</div>`;
}
/* «5 días» no se puede traducir de una pieza: el catálogo busca el texto
   entero y el número cambia en cada fila. Así el número queda fuera y lo que
   se traduce es la unidad, que en las tres lenguas va detrás de la cifra. */
function unit(n,word,decimals){return `${esc(num(n,decimals??0))} ${tr(word)}`}
/* Cuánto queda: en días si el vencimiento tiene fecha, en kilómetros si lo que
   marca la revisión es el cuentakilómetros. */
function remaining(d){
 if(d.days_remaining!=null)return{
  html:d.days_remaining<0?unit(-d.days_remaining,'días de retraso')
   :d.days_remaining===0?tr('Vence hoy'):unit(d.days_remaining,'días restantes'),
  urgency:d.days_remaining<=7?'now':d.days_remaining<=30?'soon':''};
 if(d.km_remaining!=null)return{
  html:d.km_remaining<0?unit(-d.km_remaining,'km de más'):unit(d.km_remaining,'km restantes'),
  urgency:d.km_remaining<=200?'now':d.km_remaining<=1000?'soon':''};
 return{html:'—',urgency:''};
}
function dueRow(d){
 const r=remaining(d);
 return `<div class="gfDue" data-urgency="${r.urgency}"><b>${tr(DEADLINE[d.kind]||d.kind)}</b> · ${esc(d.subject||'')}
 <div class="gfHint">${r.html}${d.due_on?' · '+esc(d.due_on):''}${d.reference?' · '+esc(d.reference):''}</div></div>`;
}
async function go(next){
 if(next)section=next;
 nav();
 const token=++generation;busy();
 try{
  const view=vehicleId?VIEWS.sheet:VIEWS[section];
  const data=await view.load();
  if(token!==generation||!allowed())return;
  $('gfMain').innerHTML=view.render(data);
  view.bind?.(data);
 }catch(e){if(token===generation)fail(e,()=>go())}
}
async function open(options={}){
 if(!allowed())return;
 state={};vehicleId=options.vehicleId||null;tab='info';
 section=options.section||(vehicleId?'vehicles':'dashboard');
 shell();
 try{const d=await rpc('overview');state.overview=d}
 catch(e){nav();fail(e,()=>open(options));return}
 return go(section);
}
/* El centro de acción abre la ficha del vehículo o la del conductor. */
function openVehicle(id){return open({section:'vehicles',vehicleId:id})}
function openDriver(){return open({section:'drivers'})}

/* ------------------------------------------------------------------ vistas */
const VIEWS={};

/* --------------------------------------------------------------- 1. tablero */
VIEWS.dashboard={
 async load(){return state.overview||(state.overview=await rpc('overview'))},
 render(d){
  const s=d.status||{},sp=d.spend||{},total=Number(sp.fuel||0)+Number(sp.maintenance||0);
  const due=d.deadlines||[],soon=due.filter(x=>remaining(x).urgency);
  return `<div class="gfKpis">
   ${kpi('En servicio',num(s.in_service||0,0),`${unit(s.cars||0,'coches')} · ${unit(s.trucks||0,'camiones')}`)}
   ${kpi('En reparación',num(s.repair||0,0),unit(s.out_of_service||0,'fuera de servicio'))}
   ${kpi('Gasto del periodo',money(total),`${tr('Carburante')} ${esc(money(sp.fuel))} · ${tr('Taller')} ${esc(money(sp.maintenance))}`)}
   ${kpi('Vencimientos a 30 días',num(due.length,0),soon.length?unit(soon.length,'urgentes'):tr('Ninguno urgente'))}
  </div>
  <div class="gfQuick">
   <button class="primary" id="gfQuickFuel" data-gi-live data-gi=5169e8fdef43>⛽ Registrar un repostaje</button>
   <button class="secondary" id="gfQuickMaint" data-gi-live data-gi=6b92080c35c7>🔧 Registrar un entretenimiento</button>
  </div>
  <div class="gfCard"><h3>${tr('Próximos vencimientos')}</h3>
   <p class="gfHint">${tr('Los 30 próximos días. El aviso llega también al Centro de acción.')}</p>
   ${due.length?due.slice(0,12).map(dueRow).join(''):`<p class="gfHint">${tr('Nada vence en los próximos 30 días.')}</p>`}</div>
  <div class="gfCard"><h3>${tr('Consumo medio por vehículo')}</h3>
   <p class="gfHint">${tr('Calculado de depósito lleno a depósito lleno, con los repostajes registrados.')}</p>
   <div class="gfScroll"><table class="gfTable"><thead><tr>
    <th>${tr('Vehículo')}</th><th>${tr('Tipo')}</th><th>${tr('Estado')}</th>
    <th class="gfNum">${tr('L/100 km')}</th><th class="gfNum">${tr('Coste por km')}</th>
    <th class="gfNum">${tr('Km medidos')}</th></tr></thead><tbody>
    ${(d.consumption||[]).map(c=>`<tr><td><b>${esc(c.plate)}</b><br>${esc(c.brand)} ${esc(c.model)}</td>
     <td>${badge(KIND,c.kind)}</td><td>${badge(STATUS,c.status)}</td>
     <td class="gfNum">${c.avg_litres_100km==null?'—':num(c.avg_litres_100km,2)}</td>
     <td class="gfNum">${c.cost_per_km==null?'—':money(c.cost_per_km)}</td>
     <td class="gfNum">${num(c.distance||0,0)}</td></tr>`).join('')
     ||`<tr><td colspan="6">${tr('Todavía no hay repostajes registrados.')}</td></tr>`}
   </tbody></table></div>
   <div class="gfActions">
    <button class="secondary" id="gfExport" data-gi-live data-gi=2bee4428f70d>Exportar a Excel</button>
    <button class="secondary" id="gfCheck" data-gi-live data-gi=0cbb9bfd6ecf>Comprobar vencimientos ahora</button>
   </div></div>`;
 },
 bind(){
  $('gfQuickFuel').onclick=()=>fuelForm();
  $('gfQuickMaint').onclick=()=>maintenanceForm();
  $('gfExport').onclick=()=>exportAll();
  /* La comprobación corre sola cada día; el botón existe para no tener que
     esperar a mañana cuando se acaba de cargar un documento. */
  $('gfCheck').onclick=async e=>{
   const el=e.currentTarget;el.disabled=true;
   try{await rpc('check_deadlines');
    window.gamaToast?.(GamaI18n?.t?.('Vencimientos comprobados.')||'Vencimientos comprobados.');
    state.overview=null;await go();
   }catch(x){window.gamaToast?.(err(x));el.disabled=false}
  };
 }
};

/* ------------------------------------------------------------- 2. vehículos */
VIEWS.vehicles={
 async load(){return rpc('vehicles',{status:filters.status||null,kind:filters.kind||null,search:filters.search})},
 render(d){
  const rows=d.rows||[];
  return `<div class="gfTools">
   <label data-gi-live data-gi=5f55edf90089>Buscar<input id="gfSearch" type="search" value="${esc(filters.search)}" data-gi-placeholder=a666a5eb56e8 placeholder="Matrícula, marca, modelo" data-gi-placeholder="live"></label>
   <label data-gi-live data-gi=3868d2843d59>Tipo<select id="gfKind">
    <option value="" data-gi-live data-gi=bd02b9a7d71d>Todos</option>
    ${Object.entries(KIND).map(([k,v])=>`<option value="${k}" ${filters.kind===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}
   </select></label>
   <label data-gi-live data-gi=98e5acddb6c4>Estado<select id="gfStatus">
    <option value="" data-gi-live data-gi=bd02b9a7d71d>Todos</option>
    ${Object.entries(STATUS).map(([k,v])=>`<option value="${k}" ${filters.status===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}
   </select></label>
   <label><button class="primary" id="gfNewVehicle" data-gi-live data-gi=f86ee15fd67d>Nuevo vehículo</button></label>
  </div>
  <p class="gfHint">${unit(rows.length,'vehículos')}</p>
  <div class="gfCards">${rows.map(v=>`
   <button type="button" class="gfVeh" data-gf-vehicle="${v.id}">
    <figure aria-hidden="true">${v.kind==='truck'?'🚛':'🚗'}</figure>
    <div class="gfVehBody">
     <b>${esc(v.plate)}</b><span>${esc(v.brand)} ${esc(v.model)}</span>
     <span>${num(v.odometer||0,0)} km${v.driver_name?' · '+esc(v.driver_name):''}</span>
     <span>${v.avg_litres_100km==null?tr('Sin consumo medido'):esc(num(v.avg_litres_100km,2)+' L/100 km')}</span>
     <div class="gfVehMeta">${badge(KIND,v.kind)}${badge(STATUS,v.status)}
      ${v.alerts>0?`<span class="gfBadge" data-s="repair">${unit(v.alerts,'vencimientos')}</span>`:''}</div>
    </div></button>`).join('')||`<p class="gfCard">${tr('Ningún vehículo con ese filtro.')}</p>`}</div>`;
 },
 bind(d){
  const reload=()=>{filters.search=$('gfSearch').value;filters.kind=$('gfKind').value;filters.status=$('gfStatus').value;go()};
  $('gfKind').onchange=reload;$('gfStatus').onchange=reload;
  let t=null;$('gfSearch').oninput=()=>{clearTimeout(t);t=setTimeout(reload,350)};
  $('gfNewVehicle').onclick=()=>vehicleForm(null);
  document.querySelectorAll('[data-gf-vehicle]').forEach(b=>b.onclick=()=>{vehicleId=b.dataset.gfVehicle;tab='info';go()});
 }
};

/* ----------------------------------------------- 3. ficha con sus pestañas */
const TABS=[['info','Información'],['documents','Documentos'],['fuel','Carburante'],['maintenance','Entretenimientos']];
VIEWS.sheet={
 async load(){const [v,drivers]=await Promise.all([rpc('vehicle',{id:vehicleId}),rpc('vehicles',{})]);
  return{v,drivers:drivers.drivers||[]}},
 render({v}){
  const tabs=`<div class="gfTabs">${TABS.map(([k,label])=>
   `<button type="button" data-gf-tab="${k}" class="${tab===k?'on':''}" aria-current="${tab===k?'page':'false'}" data-gi-live>${esc(label)}</button>`).join('')}</div>`;
  return `<div class="gfCard">
   <div class="gfActions" style="margin:0 0 11px"><button class="secondary" id="gfBackList" data-gi-live data-gi=2728babbb7ff>← Volver a la lista</button></div>
   <h3>${esc(v.plate)} · ${esc(v.brand)} ${esc(v.model)}</h3>
   <div class="gfVehMeta">${badge(KIND,v.kind)}${badge(STATUS,v.status)}
    <span class="gfBadge">${esc(v.reference)}</span>
    <span class="gfBadge">${esc(num(v.odometer||0,0))} km</span></div>
  </div>${tabs}<div id="gfTab">${TAB_VIEWS[tab](v)}</div>`;
 },
 bind(d){
  $('gfBackList').onclick=()=>{vehicleId=null;go('vehicles')};
  document.querySelectorAll('[data-gf-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.gfTab;go()});
  TAB_BINDS[tab]?.(d);
 }
};
const TAB_VIEWS={
 info(v){
  const c=v.consumption||{};
  return `<div class="gfCard">
   ${v.photo?`<img class="gfPhoto" src="${esc(v.photo)}" alt="${esc(v.plate)}">`:`<p class="gfHint">${tr('Sin foto del vehículo.')}</p>`}
   <dl class="gfDl" style="margin-top:12px">
    <dt>${tr('Matrícula')}</dt><dd>${esc(v.plate)}</dd>
    <dt>${tr('Energía')}</dt><dd>${tr(ENERGY[v.energy]||v.energy)}</dd>
    <dt>${tr('Primera matriculación')}</dt><dd>${esc(v.first_registration||'—')}</dd>
    <dt>${tr('Kilometraje')}</dt><dd>${esc(num(v.odometer||0,0))} km</dd>
    ${v.kind==='truck'?`<dt>${tr('PTAC')}</dt><dd>${v.gvwr_kg==null?'—':esc(num(v.gvwr_kg,0))+' kg'}</dd>
    <dt>${tr('Carga útil')}</dt><dd>${v.payload_kg==null?'—':esc(num(v.payload_kg,0))+' kg'}</dd>`:''}
    <dt>${tr('Consumo medio')}</dt><dd>${c.avg_litres_100km==null?'—':esc(num(c.avg_litres_100km,2))+' L/100 km'}</dd>
    <dt>${tr('Coste por km')}</dt><dd>${c.cost_per_km==null?'—':money(c.cost_per_km)}</dd>
    <dt>${tr('Conductor')}</dt><dd>${v.driver?esc(v.driver.name)+(v.driver.phone?' · '+esc(v.driver.phone):'')+(v.driver.since?' · '+tr('desde')+' '+esc(v.driver.since):''):'—'}</dd>
   </dl>
   ${v.notes?`<p class="gfHint">${esc(v.notes)}</p>`:''}
   <div class="gfActions">
    <button class="secondary" id="gfEditVehicle" data-gi-live data-gi=25cb6fc10242>Modificar</button>
    <button class="secondary" id="gfPhoto" data-gi-live data-gi=9149e7dc2fa4>Foto del vehículo</button>
    <button class="secondary" id="gfAssign" data-gi-live data-gi=940bdfbfa57d>Asignar un conductor</button>
    ${v.driver?`<button class="secondary" id="gfUnassign" data-gi-live data-gi=2efcde959ffe>Retirar el conductor</button>`:''}
    <button class="secondary" id="gfDeleteVehicle" data-gi-live data-gi=46af898b84fc>Dar de baja</button>
   </div></div>
  <div class="gfCard"><h3>${tr('Historial de conductores')}</h3>
   ${(v.assignments||[]).length?`<div class="gfScroll"><table class="gfTable"><thead><tr>
    <th>${tr('Conductor')}</th><th>${tr('Desde')}</th><th>${tr('Hasta')}</th><th></th></tr></thead><tbody>
    ${v.assignments.map(a=>`<tr><td>${esc(a.driver)}</td><td>${esc(a.started_on)}</td>
     <td>${a.ended_on?esc(a.ended_on):tr('En curso')}</td>
     <td><button class="secondary" data-gf-assign-del="${a.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join('')}
   </tbody></table></div>`:`<p class="gfHint">${tr('Ningún conductor ha llevado este vehículo todavía.')}</p>`}</div>`;
 },
 documents(v){
  return `<div class="gfCard"><h3>${tr('Documentos y vencimientos')}</h3>
   <p class="gfHint">${tr('Seguro, inspección técnica y permiso de circulación. El aviso salta 30 días antes.')}</p>
   ${(v.documents||[]).length?`<div class="gfScroll"><table class="gfTable"><thead><tr>
    <th>${tr('Documento')}</th><th>${tr('Referencia')}</th><th>${tr('Expedido')}</th>
    <th>${tr('Vence')}</th><th>${tr('Archivo')}</th><th></th></tr></thead><tbody>
    ${v.documents.map(x=>{const r=remaining(x);return `<tr><td>${tr(DOCKIND[x.kind]||x.kind)}</td>
     <td>${esc(x.reference||'—')}</td><td>${esc(x.issued_on||'—')}</td>
     <td>${x.expires_on?esc(x.expires_on)+`<br><small class="gfHint">${r.html}</small>`:tr('Sin caducidad')}</td>
     <td>${x.has_file?`<button class="secondary" data-gf-file="${x.id}" data-gi-live data-gi=ed3d9c907370>Descargar</button>`:'—'}</td>
     <td><button class="secondary" data-gf-doc-edit="${x.id}" data-gi-live data-gi=25cb6fc10242>Modificar</button>
      <button class="secondary" data-gf-doc-del="${x.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`}).join('')}
   </tbody></table></div>`:`<p class="gfHint">${tr('Ningún documento registrado.')}</p>`}
   <div class="gfActions"><button class="primary" id="gfNewDoc" data-gi-live data-gi=88fa2503185d>Añadir un documento</button></div></div>`;
 },
 fuel(v){
  const c=v.consumption||{};
  return `<div class="gfKpis">
   ${kpi('Consumo medio',c.avg_litres_100km==null?'—':num(c.avg_litres_100km,2)+' L/100 km',tr('Depósito lleno a depósito lleno'))}
   ${kpi('Coste por km',c.cost_per_km==null?'—':money(c.cost_per_km),unit(c.distance||0,'km medidos'))}
   ${kpi('Gasto en carburante',money(c.total_cost||0),unit(c.fills||0,'repostajes'))}
  </div>
  <div class="gfCard"><h3>${tr('Repostajes')}</h3>
   <p class="gfHint">${tr('El kilometraje del vehículo sigue el repostaje más reciente: no hace falta actualizarlo aparte.')}</p>
   ${(v.fuel||[]).length?`<div class="gfScroll"><table class="gfTable"><thead><tr>
    <th>${tr('Fecha')}</th><th>${tr('Conductor')}</th><th class="gfNum">${tr('Kilometraje')}</th>
    <th class="gfNum">${tr('Litros')}</th><th class="gfNum">${tr('Importe')}</th>
    <th>${tr('Estación')}</th><th></th></tr></thead><tbody>
    ${v.fuel.map(f=>`<tr><td>${esc(f.logged_on)}</td><td>${esc(f.driver_name||'—')}</td>
     <td class="gfNum">${num(f.odometer||0,0)}</td><td class="gfNum">${num(f.litres,2)}</td>
     <td class="gfNum">${money(f.amount)}</td><td>${esc(f.station||'—')}</td>
     <td><button class="secondary" data-gf-fuel-del="${f.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join('')}
   </tbody></table></div>`:`<p class="gfHint">${tr('Ningún repostaje registrado.')}</p>`}
   <div class="gfActions"><button class="primary" id="gfNewFuel" data-gi-live data-gi=4d231fdc447c>Registrar un repostaje</button></div></div>`;
 },
 maintenance(v){
  return `<div class="gfCard"><h3>${tr('Entretenimientos')}</h3>
   <p class="gfHint">${tr('La próxima revisión se avisa por fecha o por kilometraje, lo que llegue antes.')}</p>
   ${(v.maintenance||[]).length?`<div class="gfScroll"><table class="gfTable"><thead><tr>
    <th>${tr('Fecha')}</th><th>${tr('Tipo')}</th><th class="gfNum">${tr('Kilometraje')}</th>
    <th>${tr('Garaje')}</th><th class="gfNum">${tr('Coste')}</th>
    <th>${tr('Próxima revisión')}</th><th></th></tr></thead><tbody>
    ${v.maintenance.map(m=>`<tr><td>${esc(m.performed_on)}</td><td>${tr(MAINTKIND[m.kind]||m.kind)}</td>
     <td class="gfNum">${m.odometer==null?'—':num(m.odometer,0)}</td><td>${esc(m.garage||'—')}</td>
     <td class="gfNum">${money(m.cost)}</td>
     <td>${[m.next_service_on,m.next_service_odometer==null?'':num(m.next_service_odometer,0)+' km'].filter(Boolean).map(esc).join('<br>')||'—'}</td>
     <td><button class="secondary" data-gf-maint-del="${m.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join('')}
   </tbody></table></div>`:`<p class="gfHint">${tr('Ningún entretenimiento registrado.')}</p>`}
   <div class="gfActions"><button class="primary" id="gfNewMaint" data-gi-live data-gi=bf1c913a5662>Registrar un entretenimiento</button></div></div>`;
 }
};
const TAB_BINDS={
 info({v,drivers}){
  $('gfEditVehicle').onclick=()=>vehicleForm(v);
  $('gfPhoto').onclick=()=>photoForm(v);
  $('gfAssign').onclick=()=>assignForm(v,drivers);
  const un=$('gfUnassign');if(un)un.onclick=()=>confirmAction('Retirar el conductor',
   `${v.driver?.name||''} dejará de estar asignado a ${v.plate}. El historial se conserva.`,
   ()=>mutate('unassign',{vehicle_id:v.id}));
  document.querySelectorAll('[data-gf-assign-del]').forEach(b=>b.onclick=()=>
   confirmAction('Eliminar la línea del historial',
    'El vehículo deja de mostrar ese periodo con ese conductor.',
    ()=>mutate('assignment_delete',{id:b.dataset.gfAssignDel})));
  $('gfDeleteVehicle').onclick=()=>confirmDelete('Dar de baja el vehículo',
   'Si el vehículo tiene historial se archiva y deja de aparecer en la lista; si nunca se usó, se elimina.',
   'Borrarlo definitivamente con sus documentos, repostajes y entretenimientos',
   async purge=>{await mutate('vehicle_delete',{id:v.id,purge});vehicleId=null;section='vehicles'});
 },
 documents({v}){
  $('gfNewDoc').onclick=()=>documentForm(v,null);
  document.querySelectorAll('[data-gf-doc-edit]').forEach(b=>b.onclick=()=>
   documentForm(v,v.documents.find(x=>x.id===b.dataset.gfDocEdit)));
  document.querySelectorAll('[data-gf-doc-del]').forEach(b=>b.onclick=()=>
   confirmAction('Eliminar el documento','El documento y su archivo adjunto se borran.',
    ()=>mutate('document_delete',{id:b.dataset.gfDocDel})));
  document.querySelectorAll('[data-gf-file]').forEach(b=>b.onclick=async()=>{
   b.disabled=true;
   try{const f=await rpc('document_file',{id:b.dataset.gfFile});
    /* El adjunto se guarda como data URL. Sólo se abre si lo sigue siendo:
       una descarga no tiene por qué navegar a ningún otro esquema. */
    if(!/^data:[\w.+-]+\/[\w.+-]+;base64,/.test(f.data_url||''))throw Error('El archivo no se pudo leer.');
    const a=document.createElement('a');a.href=f.data_url;a.download=f.filename||'documento';
    document.body.appendChild(a);a.click();a.remove();
   }catch(e){window.gamaToast?.(err(e))}finally{b.disabled=false}
  });
 },
 fuel({v}){
  $('gfNewFuel').onclick=()=>fuelForm(v.id);
  document.querySelectorAll('[data-gf-fuel-del]').forEach(b=>b.onclick=()=>
   confirmAction('Eliminar el repostaje','El consumo medio se recalcula sin él.',
    ()=>mutate('fuel_delete',{id:b.dataset.gfFuelDel})));
 },
 maintenance({v}){
  $('gfNewMaint').onclick=()=>maintenanceForm(v.id);
  document.querySelectorAll('[data-gf-maint-del]').forEach(b=>b.onclick=()=>
   confirmAction('Eliminar el entretenimiento','La próxima revisión prevista se recalcula sin él.',
    ()=>mutate('maintenance_delete',{id:b.dataset.gfMaintDel})));
 }
};

/* ------------------------------------------------------------ 4. conductores */
VIEWS.drivers={
 async load(){return rpc('drivers',{search:filters.search})},
 render(d){
  const rows=d.rows||[];
  return `<div class="gfTools">
   <label data-gi-live data-gi=5f55edf90089>Buscar<input id="gfSearch" type="search" value="${esc(filters.search)}" data-gi-placeholder=139d71c70f85 placeholder="Nombre, teléfono, permiso" data-gi-placeholder="live"></label>
   <label><button class="primary" id="gfNewDriver" data-gi-live data-gi=bbb27df1ab94>Nuevo conductor</button></label>
  </div>
  <div class="gfCard"><div class="gfScroll"><table class="gfTable"><thead><tr>
   <th>${tr('Conductor')}</th><th>${tr('Teléfono')}</th><th>${tr('Permiso')}</th>
   <th>${tr('Caduca')}</th><th>${tr('Vehículo')}</th><th></th></tr></thead><tbody>
   ${rows.map(r=>{const rr=remaining(r);return `<tr>
    <td><b>${esc(r.name)}</b>${r.employee_name?`<br><small class="gfHint">${esc(r.employee_name)}</small>`:''}</td>
    <td>${esc(r.phone||'—')}</td>
    <td>${esc(r.licence_number||'—')}${(r.licence_categories||[]).length?'<br><small class="gfHint">'+esc(r.licence_categories.join(', '))+'</small>':''}</td>
    <td>${r.licence_expiry?esc(r.licence_expiry)+`<br><small class="gfHint">${rr.html}</small>`:tr('Sin fecha')}</td>
    <td>${(r.vehicles||[]).map(x=>esc(x.plate)).join('<br>')||'—'}</td>
    <td><button class="secondary" data-gf-driver-edit="${r.id}" data-gi-live data-gi=25cb6fc10242>Modificar</button>
     <button class="secondary" data-gf-driver-del="${r.id}" data-gi-live data-gi=46af898b84fc>Dar de baja</button></td></tr>`}).join('')
    ||`<tr><td colspan="6">${tr('Ningún conductor registrado.')}</td></tr>`}
  </tbody></table></div></div>`;
 },
 bind(d){
  let t=null;$('gfSearch').oninput=()=>{clearTimeout(t);t=setTimeout(()=>{filters.search=$('gfSearch').value;go()},350)};
  $('gfNewDriver').onclick=()=>driverForm(null,d.employees||[]);
  document.querySelectorAll('[data-gf-driver-edit]').forEach(b=>b.onclick=()=>
   driverForm(d.rows.find(x=>x.id===b.dataset.gfDriverEdit),d.employees||[]));
  document.querySelectorAll('[data-gf-driver-del]').forEach(b=>b.onclick=()=>
   confirmDelete('Dar de baja el conductor',
    'Si tiene historial se archiva y deja de aparecer en las listas; si nunca condujo, se elimina.',
    'Borrarlo definitivamente. Los repostajes se conservan y pierden a quién se atribuían',
    purge=>mutate('driver_delete',{id:b.dataset.gfDriverDel,purge})));
 }
};

/* ----------------------------------------------------------- 5. vencimientos */
VIEWS.deadlines={
 async load(){const [rows,log]=await Promise.all([rpc('deadlines',{days:60}),rpc('alert_log')]);return{rows,log}},
 render({rows,log}){
  return `<div class="gfCard"><h3>${tr('Vencimientos')}</h3>
   <p class="gfHint">${tr('Permisos de conducir, documentos del vehículo y revisiones previstas, a 60 días.')}</p>
   ${rows.length?rows.map(dueRow).join(''):`<p class="gfHint">${tr('Nada vence en los próximos 60 días.')}</p>`}</div>
  <div class="gfCard"><h3>${tr('Avisos ya enviados')}</h3>
   <p class="gfHint">${tr('La comprobación corre sola cada día. Cada vencimiento se avisa una sola vez.')}</p>
   ${log.length?`<div class="gfScroll"><table class="gfTable"><thead><tr>
    <th>${tr('Avisado el')}</th><th>${tr('Tipo')}</th><th>${tr('Detalle')}</th><th></th></tr></thead><tbody>
    ${log.map(a=>`<tr><td>${esc(new Date(a.notified_at).toLocaleString('es-EC'))}</td>
     <td>${tr(DEADLINE[a.kind]||a.kind)}</td><td>${esc(a.detail||'—')}</td>
     <td><button class="secondary" data-gf-alert-del="${a.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join('')}
   </tbody></table></div>
   <div class="gfActions"><button class="secondary" id="gfAlertClear" data-gi-live data-gi=815f78e0fc98>Vaciar el registro</button></div>`
   :`<p class="gfHint">${tr('Todavía no se ha enviado ningún aviso.')}</p>`}</div>`;
 },
 bind(){
  document.querySelectorAll('[data-gf-alert-del]').forEach(b=>b.onclick=()=>
   confirmAction('Eliminar el aviso','Si el vencimiento sigue vigente se volverá a avisar en la próxima comprobación.',
    ()=>mutate('alert_delete',{id:b.dataset.gfAlertDel})));
  if($('gfAlertClear'))$('gfAlertClear').onclick=()=>
   confirmAction('Vaciar el registro de avisos',
    'Se borran todos los avisos ya enviados. Lo que siga vencido se volverá a señalar en la próxima comprobación.',
    ()=>mutate('alert_clear',{}));
 }
};

/* ---------------------------------------------------------------- formularios */
/* Todos los formularios caben en una columna en el móvil y usan campos de 16 px
   para que el teclado del teléfono no haga zoom al entrar en ellos. */
const val=(el,id)=>el.querySelector('#'+id)?.value||'';
function options(map,selected){
 return Object.entries(map).map(([k,v])=>`<option value="${k}" ${selected===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('');
}
function confirmAction(title,text,run){
 window.GamaSales.modal(GamaI18n?.t?.(title)||title,`<p>${tr(text)}</p>`,GamaI18n?.t?.('Confirmar')||'Confirmar',
  async()=>{await run();state.overview=null;await go()});
}
/* Archivar y borrar no son lo mismo, así que no comparten botón: la casilla
   de borrado definitivo hay que marcarla a propósito. Lo que se borra no se
   recupera, pero sí queda en la auditoría quién lo borró y cuándo. */
function confirmDelete(title,text,purgeText,run){
 window.GamaSales.modal(GamaI18n?.t?.(title)||title,
  `<p>${tr(text)}</p>
   <label class="gfField gfDanger" style="font-weight:600"><input type="checkbox" id="gfPurge"> ${tr(purgeText)}</label>
   <p class="gfHint">${tr('Lo borrado no se recupera. La auditoría conserva quién lo borró y cuándo.')}</p>`,
  GamaI18n?.t?.('Confirmar')||'Confirmar',
  async el=>{await run(el.querySelector('#gfPurge').checked);state.overview=null;await go()});
}
function vehicleForm(v){
 const truck=v?.kind==='truck';
 const el=window.GamaSales.modal(GamaI18n?.t?.(v?'Modificar el vehículo':'Nuevo vehículo')||'',
 `<div class="gfGrid">
   <label data-gi-live data-gi=ae197ddc6091>Matrícula<input id="gfPlate" required maxlength="20" value="${esc(v?.plate||'')}" autocapitalize="characters"></label>
   <label data-gi-live data-gi=8e2ca9b0cc8a>Marca<input id="gfBrand" required maxlength="60" value="${esc(v?.brand||'')}"></label>
   <label data-gi-live data-gi=a5ab3212dad1>Modelo<input id="gfModel" required maxlength="60" value="${esc(v?.model||'')}"></label>
   <label data-gi-live data-gi=3868d2843d59>Tipo<select id="gfVKind">${options(KIND,v?.kind||'car')}</select></label>
   <label data-gi-live data-gi=34961a7f187b>Energía<select id="gfEnergy">${options(ENERGY,v?.energy||'diesel')}</select></label>
   <label data-gi-live data-gi=3d4efd97d4ee>Primera matriculación<input id="gfFirstReg" type="date" value="${esc(v?.first_registration||'')}"></label>
   <label data-gi-live data-gi=b3c3618d9228>Kilometraje<input id="gfOdo" type="number" inputmode="numeric" min="0" step="1" value="${esc(v?.odometer??0)}"></label>
   <label data-gi-live data-gi=98e5acddb6c4>Estado<select id="gfVStatus">${options(STATUS,v?.status||'in_service')}</select></label>
  </div>
  <div class="gfGrid" id="gfTruckBox" ${truck?'':'hidden'}>
   <label data-gi-live data-gi=10401a12d289>PTAC (kg)<input id="gfGvwr" type="number" inputmode="numeric" min="1" step="1" value="${esc(v?.gvwr_kg??'')}"></label>
   <label data-gi-live data-gi=6c3dba7e3c12>Carga útil (kg)<input id="gfPayload" type="number" inputmode="numeric" min="1" step="1" value="${esc(v?.payload_kg??'')}"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfNotes" maxlength="2000">${esc(v?.notes||'')}</textarea></label>
  <p class="gfHint">${tr('El PTAC y la carga útil sólo se piden para los camiones.')}</p>`,
 GamaI18n?.t?.('Guardar')||'Guardar',async form=>{
  await mutate('vehicle_save',{id:v?.id||null,plate:val(form,'gfPlate'),brand:val(form,'gfBrand'),
   model:val(form,'gfModel'),kind:val(form,'gfVKind'),energy:val(form,'gfEnergy'),
   first_registration:val(form,'gfFirstReg'),odometer:val(form,'gfOdo'),status:val(form,'gfVStatus'),
   gvwr_kg:val(form,'gfGvwr'),payload_kg:val(form,'gfPayload'),notes:val(form,'gfNotes')});
  state.overview=null;await go();
 });
 /* El bloque de camión aparece y desaparece al cambiar el tipo: un coche no
    tiene PTAC y pedirlo sólo confunde. */
 el.querySelector('#gfVKind').onchange=e=>{el.querySelector('#gfTruckBox').hidden=e.target.value!=='truck'};
}
/* La foto se reduce en el navegador antes de subirla: una foto de móvil pesa
   varios megas y lo que hace falta aquí es reconocer el vehículo. */
function shrink(file,max=1024){
 return new Promise((resolve,reject)=>{
  const img=new Image(),url=URL.createObjectURL(file);
  img.onload=()=>{
   URL.revokeObjectURL(url);
   const s=Math.min(1,max/Math.max(img.width,img.height));
   const cv=document.createElement('canvas');
   cv.width=Math.round(img.width*s);cv.height=Math.round(img.height*s);
   cv.getContext('2d').drawImage(img,0,0,cv.width,cv.height);
   resolve(cv.toDataURL('image/jpeg',0.75));
  };
  img.onerror=()=>{URL.revokeObjectURL(url);reject(Error('La imagen no se pudo leer.'))};
  img.src=url;
 });
}
function photoForm(v){
 window.GamaSales.modal(GamaI18n?.t?.('Foto del vehículo')||'Foto',
 `<label class="gfField" data-gi-live data-gi=58d6f29b0633>Imagen<input id="gfPhotoFile" type="file" accept="image/*" capture="environment"></label>
  <p class="gfHint">${tr('Se reduce sola antes de guardarse. Deja el campo vacío para quitar la foto actual.')}</p>`,
 GamaI18n?.t?.('Guardar')||'Guardar',async form=>{
  const f=form.querySelector('#gfPhotoFile').files[0];
  await mutate('vehicle_photo',{id:v.id,photo:f?await shrink(f):''});
  await go();
 });
}
function assignForm(v,drivers){
 window.GamaSales.modal(GamaI18n?.t?.('Asignar un conductor')||'',
 `<div class="gfGrid">
   <label data-gi-live data-gi=14116bf4372e>Conductor<select id="gfDriver" required><option value="" data-gi-live data-gi=3c41f9546e61>Seleccionar…</option>
    ${drivers.map(d=>`<option value="${d.id}" ${v.driver?.id===d.id?'selected':''}>${esc(d.name)}</option>`).join('')}</select></label>
   <label data-gi-live data-gi=8b4e93e928df>Desde<input id="gfFrom" type="date" value="${esc(day())}"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfANotes" maxlength="1000"></textarea></label>
  <p class="gfHint">${tr('Un vehículo tiene un conductor a la vez: el anterior se cierra solo y queda en el historial.')}</p>`,
 GamaI18n?.t?.('Asignar')||'Asignar',async form=>{
  if(!val(form,'gfDriver'))throw Error('Selecciona un conductor.');
  await mutate('assign',{vehicle_id:v.id,driver_id:val(form,'gfDriver'),
   started_on:val(form,'gfFrom'),notes:val(form,'gfANotes')});
  await go();
 });
}
function driverForm(d,employees){
 const cats=['A','B','C','D','E'];
 window.GamaSales.modal(GamaI18n?.t?.(d?'Modificar el conductor':'Nuevo conductor')||'',
 `<div class="gfGrid">
   <label data-gi-live data-gi=562bb15757a8>Nombre<input id="gfDName" required maxlength="120" value="${esc(d?.name||'')}"></label>
   <label data-gi-live data-gi=f1186abd0b8b>Teléfono<input id="gfDPhone" type="tel" inputmode="tel" maxlength="40" value="${esc(d?.phone||'')}"></label>
   <label data-gi-live data-gi=1b98753ff261>Número de permiso<input id="gfDLic" maxlength="60" value="${esc(d?.licence_number||'')}"></label>
   <label data-gi-live data-gi=b6115749e877>Caducidad del permiso<input id="gfDExp" type="date" value="${esc(d?.licence_expiry||'')}"></label>
   <label data-gi-live data-gi=6f0babb30673>Empleado<select id="gfDEmp"><option value="" data-gi-live data-gi=3c2b0b48e3a0>Sin vincular</option>
    ${employees.map(e=>`<option value="${e.id}" ${d?.employee_id===e.id?'selected':''}>${esc(e.name)}</option>`).join('')}</select></label>
  </div>
  <div class="gfField"><span data-gi-live data-gi=4d37c139ac37>Categorías del permiso</span>
   <div class="gfVehMeta">${cats.map(c=>`<label style="font-weight:600"><input type="checkbox" data-gf-cat value="${c}" ${(d?.licence_categories||[]).includes(c)?'checked':''}> ${c}</label>`).join('')}</div></div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfDNotes" maxlength="2000">${esc(d?.notes||'')}</textarea></label>
  <p class="gfHint">${tr('Vincular al empleado evita teclear dos veces la misma persona; no es obligatorio.')}</p>`,
 GamaI18n?.t?.('Guardar')||'Guardar',async form=>{
  await mutate('driver_save',{id:d?.id||null,name:val(form,'gfDName'),phone:val(form,'gfDPhone'),
   licence_number:val(form,'gfDLic'),licence_expiry:val(form,'gfDExp'),employee_id:val(form,'gfDEmp'),
   licence_categories:[...form.querySelectorAll('[data-gf-cat]:checked')].map(x=>x.value),
   notes:val(form,'gfDNotes')});
  state.overview=null;await go();
 });
}
function documentForm(v,x){
 window.GamaSales.modal(GamaI18n?.t?.(x?'Modificar el documento':'Añadir un documento')||'',
 `<div class="gfGrid">
   <label data-gi-live data-gi=cf4279e00d07>Documento<select id="gfDocKind">${options(DOCKIND,x?.kind||'insurance')}</select></label>
   <label data-gi-live data-gi=10ddff5fcc6f>Referencia<input id="gfDocRef" maxlength="120" value="${esc(x?.reference||'')}"></label>
   <label data-gi-live data-gi=b218a27cd772>Expedido el<input id="gfDocIssued" type="date" value="${esc(x?.issued_on||'')}"></label>
   <label data-gi-live data-gi=a2357698522d>Vence el<input id="gfDocExp" type="date" value="${esc(x?.expires_on||'')}"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=b8be96d00e42>Archivo adjunto<input id="gfDocFile" type="file" accept="image/*,application/pdf" capture="environment"></label>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfDocNotes" maxlength="1000">${esc(x?.notes||'')}</textarea></label>
  <p class="gfHint">${tr('Hasta 2,5 MB. Si dejas el archivo vacío se conserva el que ya estaba.')}</p>`,
 GamaI18n?.t?.('Guardar')||'Guardar',async form=>{
  const f=form.querySelector('#gfDocFile').files[0];let data_url='',filename='',mime_type='';
  if(f){
   if(f.size>2500000)throw Error('FILE_TOO_LARGE');
   filename=f.name;mime_type=f.type||'application/octet-stream';
   data_url=f.type.startsWith('image/')?await shrink(f,1600):await new Promise((ok,ko)=>{
    const r=new FileReader();r.onload=()=>ok(r.result);r.onerror=()=>ko(Error('El archivo no se pudo leer.'));r.readAsDataURL(f)});
  }
  await mutate('document_save',{id:x?.id||null,vehicle_id:v.id,kind:val(form,'gfDocKind'),
   reference:val(form,'gfDocRef'),issued_on:val(form,'gfDocIssued'),expires_on:val(form,'gfDocExp'),
   filename,mime_type,data_url,notes:val(form,'gfDocNotes')});
  await go();
 });
}
/* Repostaje y entretenimiento son lo que más se rellena, y casi siempre de pie
   junto al vehículo: si no llega un vehículo concreto, el formulario lo pide. */
async function pickVehicle(current){
 if(current)return{id:current,list:null};
 const d=await rpc('vehicles',{});
 return{id:null,list:d.rows||[]};
}
async function fuelForm(current){
 let ctx;try{ctx=await pickVehicle(current)}catch(e){return window.gamaToast?.(err(e))}
 const key=crypto.randomUUID();
 window.GamaSales.modal(GamaI18n?.t?.('Registrar un repostaje')||'',
 `<div class="gfGrid">
   ${ctx.list?`<label data-gi-live data-gi=e4579a8b1ea4>Vehículo<select id="gfFVeh" required><option value="" data-gi-live data-gi=3c41f9546e61>Seleccionar…</option>
    ${ctx.list.map(v=>`<option value="${v.id}">${esc(v.plate)} · ${esc(v.brand)} ${esc(v.model)}</option>`).join('')}</select></label>`:''}
   <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="gfFDate" type="date" value="${esc(day())}"></label>
   <label data-gi-live data-gi=b3c3618d9228>Kilometraje<input id="gfFOdo" type="number" inputmode="numeric" min="0" step="1" required></label>
   <label data-gi-live data-gi=4d6711f5e657>Litros<input id="gfFLitres" type="number" inputmode="decimal" min="0.01" step="0.01" required></label>
   <label data-gi-live data-gi=572a3acfd983>Importe<input id="gfFAmount" type="number" inputmode="decimal" min="0" step="0.01" required></label>
   <label data-gi-live data-gi=f328c354bbef>Estación<input id="gfFStation" maxlength="120"></label>
  </div>
  <label class="gfField" style="font-weight:600"><input type="checkbox" id="gfFFull" checked> ${tr('Depósito lleno')}</label>
  <p class="gfHint">${tr('El consumo medio se calcula de depósito lleno a depósito lleno. El kilometraje del vehículo se actualiza solo.')}</p>`,
 GamaI18n?.t?.('Guardar')||'Guardar',async form=>{
  const vid=ctx.id||val(form,'gfFVeh');
  if(!vid)throw Error('Selecciona un vehículo.');
  await mutate('fuel_save',{request_key:key,vehicle_id:vid,logged_on:val(form,'gfFDate'),
   odometer:val(form,'gfFOdo'),litres:val(form,'gfFLitres'),amount:val(form,'gfFAmount'),
   station:val(form,'gfFStation'),full_tank:form.querySelector('#gfFFull').checked});
  state.overview=null;await go();
 });
}
async function maintenanceForm(current){
 let ctx;try{ctx=await pickVehicle(current)}catch(e){return window.gamaToast?.(err(e))}
 const key=crypto.randomUUID();
 window.GamaSales.modal(GamaI18n?.t?.('Registrar un entretenimiento')||'',
 `<div class="gfGrid">
   ${ctx.list?`<label data-gi-live data-gi=e4579a8b1ea4>Vehículo<select id="gfMVeh" required><option value="" data-gi-live data-gi=3c41f9546e61>Seleccionar…</option>
    ${ctx.list.map(v=>`<option value="${v.id}">${esc(v.plate)} · ${esc(v.brand)} ${esc(v.model)}</option>`).join('')}</select></label>`:''}
   <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="gfMDate" type="date" value="${esc(day())}"></label>
   <label data-gi-live data-gi=3868d2843d59>Tipo<select id="gfMKind">${options(MAINTKIND,'service')}</select></label>
   <label data-gi-live data-gi=b3c3618d9228>Kilometraje<input id="gfMOdo" type="number" inputmode="numeric" min="0" step="1"></label>
   <label data-gi-live data-gi=bc1767d0530e>Garaje<input id="gfMGarage" maxlength="120"></label>
   <label data-gi-live data-gi=c940e0fbc42f>Coste<input id="gfMCost" type="number" inputmode="decimal" min="0" step="0.01" value="0"></label>
   <label data-gi-live data-gi=50c713c6250a>Próxima revisión (fecha)<input id="gfMNextOn" type="date"></label>
   <label data-gi-live data-gi=f736a163bd23>Próxima revisión (km)<input id="gfMNextKm" type="number" inputmode="numeric" min="0" step="1"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfMNotes" maxlength="2000"></textarea></label>
  <p class="gfHint">${tr('Se avisa por fecha o por kilometraje, lo que llegue antes. Puedes dejar los dos vacíos.')}</p>`,
 GamaI18n?.t?.('Guardar')||'Guardar',async form=>{
  const vid=ctx.id||val(form,'gfMVeh');
  if(!vid)throw Error('Selecciona un vehículo.');
  await mutate('maintenance_save',{request_key:key,vehicle_id:vid,performed_on:val(form,'gfMDate'),
   kind:val(form,'gfMKind'),odometer:val(form,'gfMOdo'),garage:val(form,'gfMGarage'),
   cost:val(form,'gfMCost'),next_service_on:val(form,'gfMNextOn'),
   next_service_odometer:val(form,'gfMNextKm'),notes:val(form,'gfMNotes')});
  state.overview=null;await go();
 });
}

/* ------------------------------------------------------------- exportación */
/* Un CSV con separador de punto y coma: Excel lo abre de doble clic en las tres
   lenguas y no hace falta ninguna librería. */
function download(rows,name){
 if(!rows||!rows.length){window.gamaToast?.(GamaI18n?.t?.('No hay nada que exportar.')||'No hay nada que exportar.');return}
 const keys=[...rows.reduce((s,r)=>{Object.keys(r).forEach(k=>typeof r[k]!=='object'&&s.add(k));return s},new Set())];
 const cell=v=>v==null?'':/[";\n]/.test(String(v))?'"'+String(v).replace(/"/g,'""')+'"':String(v);
 const csv='﻿'+[keys.join(';'),...rows.map(r=>keys.map(k=>cell(r[k])).join(';'))].join('\n');
 const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));
 const a=document.createElement('a');a.href=url;a.download=`GAMA-${name}-${day()}.csv`;
 document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),4000);
}
async function exportAll(){
 try{
  const d=await rpc('export',{from:monthStart(),to:day()});
  download(d.vehicles,'flota-vehiculos');
  download(d.expenses,'flota-gastos');
 }catch(e){window.gamaToast?.(err(e))}
}

window.addEventListener('gama:currency-change',()=>{if($(ID)?.classList.contains('active'))go()});
window.GamaFleet={open,openVehicle,openDriver,rpc,SECTIONS};
})();
