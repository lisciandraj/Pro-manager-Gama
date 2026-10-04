/* Generated from src/features/transport/fleet.js. Edit the source and run npm run build. */
(function(){"use strict";if(window.GamaFleet&&!window.GamaFleet.__arcLazy)return;const ID="fleet",$=id=>document.getElementById(id),esc=window.ArcUI.esc,vehicleIcon=kind=>{const n=kind==="truck"?"truck":"car";return'<svg class="gfVehIcon" data-icon="'+n+'" viewBox="0 0 24 24" focusable="false">'+(window.ArcUI.icons?.[n]||"")+"</svg>"},tr=s=>`<span data-gi-live>${esc(s)}</span>`,money=v=>window.GamaCurrency.format(v),num=(v,d)=>window.GamaCurrency.number(v,d),allowed=()=>!!window.gamaAccessAllowed?.(ID),day=()=>new Intl.DateTimeFormat("en-CA",{timeZone:globalThis.window?.GamaCompany?.get()?.timezone||"America/Guayaquil",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date),monthStart=()=>day().slice(0,8)+"01",SECTIONS=[["dashboard","Tablero"],["vehicles","Veh\xEDculos"],["drivers","Conductores"],["deadlines","Vencimientos"]],KIND={car:"Coche",truck:"Cami\xF3n"},STATUS={in_service:"En servicio",repair:"En reparaci\xF3n",out_of_service:"Fuera de servicio"},ENERGY={diesel:"Di\xE9sel",petrol:"Gasolina",electric:"El\xE9ctrico",hybrid:"H\xEDbrido",lpg:"GLP",cng:"GNC",other:"Otra"},DOCKIND={insurance:"Seguro",technical_inspection:"Inspecci\xF3n t\xE9cnica",registration:"Permiso de circulaci\xF3n"},MAINTKIND={service:"Revisi\xF3n",repair:"Reparaci\xF3n",tyres:"Neum\xE1ticos"},DEADLINE={licence:"Permiso de conducir",document_insurance:"Seguro",document_technical_inspection:"Inspecci\xF3n t\xE9cnica",document_registration:"Permiso de circulaci\xF3n",service_date:"Revisi\xF3n prevista (fecha)",service_km:"Revisi\xF3n prevista (kilometraje)"},ERRORS={ROLE_NOT_ALLOWED:"La flota es un m\xF3dulo de administraci\xF3n: tu perfil no tiene acceso.",AUTH_REQUIRED:"Vuelve a iniciar sesi\xF3n para continuar.",VEHICLE_NOT_FOUND:"Ese veh\xEDculo ya no existe. Actualiza la lista.",DRIVER_NOT_FOUND:"Ese conductor ya no existe. Actualiza la lista.",DOCUMENT_NOT_FOUND:"Ese documento ya no existe. Actualiza la ficha.",NO_ASSIGNMENT:"El veh\xEDculo no tiene ning\xFAn conductor asignado.",FILE_TOO_LARGE:"El archivo pesa demasiado. El m\xE1ximo son 2,5 MB.",INVALID_PERIOD:"La fecha de fin es anterior a la de inicio.",INVALID_ACTION:"Esa operaci\xF3n no existe en este m\xF3dulo.",NOT_FOUND:"El registro ya no existe. Actualiza la pantalla."};function err(e){const s=String(e?.message||e);for(const[k,v]of Object.entries(ERRORS))if(s.includes(k)||s===v)return v;return/fleet_driver_employee/i.test(s)?"Ese empleado ya tiene una ficha de conductor. Modif\xEDcala en vez de crear otra.":/duplicate key|unique/i.test(s)?"Esa matr\xEDcula ya est\xE1 registrada en otro veh\xEDculo.":/check constraint|violates check/i.test(s)?"Revisa los datos: hay un valor fuera de lo admitido.":"No se pudo completar la operaci\xF3n. Int\xE9ntalo de nuevo."}let section="dashboard",state={},generation=0,vehicleId=null,tab="info",filters={status:"",kind:"",search:""};async function rpc(action,data={}){if(!allowed())throw Error("ROLE_NOT_ALLOWED");await window.GamaCloudReady;const c=await GamaCloud.db(),r=await window.ArcData.rawRpc("gama_fleet_action",{p_action:action,p_data:data});if(r.error)throw Error(err(r.error));if(r.data==null)throw Error("EMPTY");return r.data}async function mutate(action,data){const r=await rpc(action,data);return window.dispatchEvent(new CustomEvent("gama:fleet-change")),r}function css(){}function shell(){let s=$(ID);return s||(s=document.createElement("section"),s.id=ID,(document.querySelector(".wrap")||document.body).appendChild(s)),window.ArcUI.render(s,GamaUI.header({title:"Gesti\xF3n de flota",lead:"Tus coches y camiones: papeles, consumos y revisiones."})+'<nav class="gfNav" id="gfNav"></nav><div id="gfMain" aria-live="polite"></div>'),GamaUI.bindBack(s),window.showTab?.(ID),s}function nav(){const host=$("gfNav");host&&(window.ArcUI.render(host,SECTIONS.map(([k,label])=>`<button type="button" data-gi-live data-gf-section="${k}" class="arcButton ${section===k&&!vehicleId?"on":""}" aria-current="${section===k&&!vehicleId?"page":"false"}">${esc(label)}</button>`).join("")),host.querySelectorAll("[data-gf-section]").forEach(b=>b.onclick=()=>{vehicleId=null,go(b.dataset.gfSection)}))}function busy(){window.ArcUI.render($("gfMain"),`<p class="arcPanel gfCard">${tr("Cargando\u2026")}</p>`)}function fail(e,retry){window.ArcUI.render($("gfMain"),`<div class="arcPanel gfCard"><p class="gfError" role="alert">${esc(err(e))}</p>
 <button class="arcButton secondary" id="gfRetry">${tr("Actualizar")}</button></div>`),$("gfRetry").onclick=retry}function badge(map,v){return`<span class="arcStatusBadge gfBadge" data-s="${esc(v)}">${tr(map[v]||v)}</span>`}function kpi(label,value,hint){return`<div class="arcPanel gfCard"><small>${tr(label)}</small><strong>${esc(value)}</strong>${hint?`<em>${hint}</em>`:""}</div>`}function unit(n,word,decimals){return`${esc(num(n,decimals??0))} ${tr(word)}`}function remaining(d){return d.days_remaining!=null?{html:d.days_remaining<0?unit(-d.days_remaining,"d\xEDas de retraso"):d.days_remaining===0?tr("Vence hoy"):unit(d.days_remaining,"d\xEDas restantes"),urgency:d.days_remaining<=7?"now":d.days_remaining<=30?"soon":""}:d.km_remaining!=null?{html:d.km_remaining<0?unit(-d.km_remaining,"km de m\xE1s"):unit(d.km_remaining,"km restantes"),urgency:d.km_remaining<=200?"now":d.km_remaining<=1e3?"soon":""}:{html:"\u2014",urgency:""}}function dueRow(d){const r=remaining(d);return`<div class="gfDue" data-urgency="${r.urgency}"><b>${tr(DEADLINE[d.kind]||d.kind)}</b> \xB7 ${esc(d.subject||"")}
 <div class="gfHint">${r.html}${d.due_on?" \xB7 "+esc(d.due_on):""}${d.reference?" \xB7 "+esc(d.reference):""}</div></div>`}async function go(next){next&&(section=next),nav();const token=++generation;busy();try{const view=vehicleId?VIEWS.sheet:VIEWS[section],data=await view.load();if(token!==generation||!allowed())return;window.ArcUI.render($("gfMain"),view.render(data)),view.bind?.(data)}catch(e){token===generation&&fail(e,()=>go())}}async function open(options2={}){if(allowed()){state={},vehicleId=options2.vehicleId||null,tab="info",section=options2.section||(vehicleId?"vehicles":"dashboard"),shell();try{const d=await rpc("overview");state.overview=d}catch(e){nav(),fail(e,()=>open(options2));return}return go(section)}}function openVehicle(id){return open({section:"vehicles",vehicleId:id})}function openDriver(){return open({section:"drivers"})}const VIEWS={};VIEWS.dashboard={async load(){return state.overview||(state.overview=await rpc("overview"))},render(d){const s=d.status||{},sp=d.spend||{},total=Number(sp.fuel||0)+Number(sp.maintenance||0),due=d.deadlines||[],soon=due.filter(x=>remaining(x).urgency);return`<div class="gfKpis">
   ${kpi("En servicio",num(s.in_service||0,0),`${unit(s.cars||0,"coches")} \xB7 ${unit(s.trucks||0,"camiones")}`)}
   ${kpi("En reparaci\xF3n",num(s.repair||0,0),unit(s.out_of_service||0,"fuera de servicio"))}
   ${kpi("Gasto del periodo",money(total),`${tr("Carburante")} ${esc(money(sp.fuel))} \xB7 ${tr("Taller")} ${esc(money(sp.maintenance))}`)}
   ${kpi("Vencimientos a 30 d\xEDas",num(due.length,0),soon.length?unit(soon.length,"urgentes"):tr("Ninguno urgente"))}
  </div>
  <div class="gfQuick">
   <button class="arcButton primary" id="gfQuickFuel" data-gi-live data-gi=4d231fdc447c>Registrar un repostaje</button>
   <button class="arcButton secondary" id="gfQuickMaint" data-gi-live data-gi=bf1c913a5662>Registrar un entretenimiento</button>
  </div>
  <div class="arcPanel gfCard"><h3>${tr("Pr\xF3ximos vencimientos")}</h3>
   <p class="gfHint">${tr("Los 30 pr\xF3ximos d\xEDas. El aviso llega tambi\xE9n al Centro de acci\xF3n.")}</p>
   ${due.length?due.slice(0,12).map(dueRow).join(""):`<p class="gfHint">${tr("Nada vence en los pr\xF3ximos 30 d\xEDas.")}</p>`}</div>
  <div class="arcPanel gfCard"><h3>${tr("Consumo medio por veh\xEDculo")}</h3>
   <p class="gfHint">${tr("Calculado de dep\xF3sito lleno a dep\xF3sito lleno, con los repostajes registrados.")}</p>
   <div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
    <th>${tr("Veh\xEDculo")}</th><th>${tr("Tipo")}</th><th>${tr("Estado")}</th>
    <th class="gfNum">${tr("L/100 km")}</th><th class="gfNum">${tr("Coste por km")}</th>
    <th class="gfNum">${tr("Km medidos")}</th></tr></thead><tbody>
    ${(d.consumption||[]).map(c=>`<tr><td><b>${esc(c.plate)}</b><br>${esc(c.brand)} ${esc(c.model)}</td>
     <td>${badge(KIND,c.kind)}</td><td>${badge(STATUS,c.status)}</td>
     <td class="gfNum">${c.avg_litres_100km==null?"\u2014":num(c.avg_litres_100km,2)}</td>
     <td class="gfNum">${c.cost_per_km==null?"\u2014":money(c.cost_per_km)}</td>
     <td class="gfNum">${num(c.distance||0,0)}</td></tr>`).join("")||`<tr><td colspan="6">${tr("Todav\xEDa no hay repostajes registrados.")}</td></tr>`}
   </tbody></table></div>
   <div class="gfActions">
    <button class="arcButton secondary" id="gfExport" data-gi-live data-gi=2bee4428f70d>Exportar a Excel</button>
    <button class="arcButton secondary" id="gfCheck" data-gi-live data-gi=0cbb9bfd6ecf>Comprobar vencimientos ahora</button>
   </div></div>`},bind(){$("gfQuickFuel").onclick=()=>fuelForm(),$("gfQuickMaint").onclick=()=>maintenanceForm(),$("gfExport").onclick=()=>exportAll(),$("gfCheck").onclick=async e=>{const el=e.currentTarget;el.disabled=!0;try{await rpc("check_deadlines"),window.gamaToast?.(GamaI18n?.t?.("Vencimientos comprobados.")||"Vencimientos comprobados."),state.overview=null,await go()}catch(x){window.gamaToast?.(err(x)),el.disabled=!1}}}},VIEWS.vehicles={async load(){const d=await rpc("vehicles",{status:filters.status||null,kind:filters.kind||null,search:filters.search}),ids=(d.rows||[]).filter(v=>v.has_photo&&!v.photo).map(v=>v.id);if(ids.length)try{const photos=await window.ArcData.byIds("fleet_vehicles","id",ids,{select:"id,photo",order:"id"});if(photos.error)throw photos.error;const byId=new Map((photos.data||[]).map(v=>[v.id,v.photo]));d.rows=d.rows.map(v=>({...v,photo:v.photo||byId.get(v.id)||null}))}catch{console.warn("Fleet vehicle photos could not be loaded")}return d},render(d){const rows=d.rows||[];return`<div class="gfTools">
   <label data-gi-live data-gi=5f55edf90089>Buscar<input id="gfSearch" type="search" value="${esc(filters.search)}" data-gi-placeholder=a666a5eb56e8 placeholder="Matr\xEDcula, marca, modelo" data-gi-placeholder="live"></label>
   <label data-gi-live data-gi=3868d2843d59>Tipo<select id="gfKind">
    <option value="" data-gi-live data-gi=bd02b9a7d71d>Todos</option>
    ${Object.entries(KIND).map(([k,v])=>`<option value="${k}" ${filters.kind===k?"selected":""} data-gi-live>${esc(v)}</option>`).join("")}
   </select></label>
   <label data-gi-live data-gi=98e5acddb6c4>Estado<select id="gfStatus">
    <option value="" data-gi-live data-gi=bd02b9a7d71d>Todos</option>
    ${Object.entries(STATUS).map(([k,v])=>`<option value="${k}" ${filters.status===k?"selected":""} data-gi-live>${esc(v)}</option>`).join("")}
   </select></label>
   <label><button class="arcButton primary" id="gfNewVehicle" data-gi-live data-gi=f86ee15fd67d>Nuevo veh\xEDculo</button></label>
  </div>
  <p class="gfHint">${unit(rows.length,"veh\xEDculos")}</p>
  <div class="gfCards">${rows.map(v=>`
   <button type="button" class="arcButton gfVeh" data-gf-vehicle="${v.id}">
    <figure aria-hidden="true" data-gf-photo-fallback="${v.kind==="truck"?"truck":"car"}">${v.photo?`<img src="${esc(v.photo)}" alt="" loading="lazy" decoding="async">`:vehicleIcon(v.kind)}</figure>
    <div class="gfVehBody">
     <b>${esc(v.plate)}</b><span>${esc(v.brand)} ${esc(v.model)}</span>
     <span>${num(v.odometer||0,0)} km${v.driver_name?" \xB7 "+esc(v.driver_name):""}</span>
     <span>${v.avg_litres_100km==null?tr("Sin consumo medido"):esc(num(v.avg_litres_100km,2)+" L/100 km")}</span>
     <div class="gfVehMeta">${badge(KIND,v.kind)}${badge(STATUS,v.status)}
      ${v.alerts>0?`<span class="arcStatusBadge gfBadge" data-s="repair">${unit(v.alerts,"vencimientos")}</span>`:""}</div>
    </div></button>`).join("")||`<p class="arcPanel gfCard">${tr("Ning\xFAn veh\xEDculo con ese filtro.")}</p>`}</div>`},bind(d){const reload=()=>{filters.search=$("gfSearch").value,filters.kind=$("gfKind").value,filters.status=$("gfStatus").value,go()};$("gfKind").onchange=reload,$("gfStatus").onchange=reload;let t=null;$("gfSearch").oninput=()=>{clearTimeout(t),t=setTimeout(reload,350)},$("gfNewVehicle").onclick=()=>vehicleForm(null),document.querySelectorAll("[data-gf-photo-fallback] img").forEach(img=>{const fallback=()=>{img.parentElement.innerHTML=vehicleIcon(img.parentElement.dataset.gfPhotoFallback)};img.onerror=fallback,img.complete&&!img.naturalWidth&&fallback()}),document.querySelectorAll("[data-gf-vehicle]").forEach(b=>b.onclick=()=>{vehicleId=b.dataset.gfVehicle,tab="info",go()})}};const TABS=[["info","Informaci\xF3n"],["documents","Documentos"],["fuel","Carburante"],["maintenance","Entretenimientos"]];VIEWS.sheet={async load(){const[v,drivers]=await Promise.all([rpc("vehicle",{id:vehicleId}),rpc("vehicles",{})]);return{v,drivers:drivers.drivers||[]}},render({v}){const tabs=`<div class="gfTabs">${TABS.map(([k,label])=>`<button type="button" data-gf-tab="${k}" class="arcButton ${tab===k?"on":""}" aria-current="${tab===k?"page":"false"}" data-gi-live>${esc(label)}</button>`).join("")}</div>`;return`<div class="arcPanel gfCard">
   <div class="gfActions" style="margin:0 0 11px"><button class="arcButton secondary" id="gfBackList" data-gi-live data-gi=2728babbb7ff>\u2190 Volver a la lista</button></div>
   <h3>${esc(v.plate)} \xB7 ${esc(v.brand)} ${esc(v.model)}</h3>
   <div class="gfVehMeta">${badge(KIND,v.kind)}${badge(STATUS,v.status)}
    <span class="arcStatusBadge gfBadge">${esc(v.reference)}</span>
    <span class="arcStatusBadge gfBadge">${esc(num(v.odometer||0,0))} km</span></div>
  </div>${tabs}<div id="gfTab">${TAB_VIEWS[tab](v)}</div>`},bind(d){$("gfBackList").onclick=()=>{vehicleId=null,go("vehicles")},document.querySelectorAll("[data-gf-tab]").forEach(b=>b.onclick=()=>{tab=b.dataset.gfTab,go()}),TAB_BINDS[tab]?.(d)}};const TAB_VIEWS={info(v){const c=v.consumption||{};return`<div class="arcPanel gfCard">
   ${v.photo?`<img class="gfPhoto" src="${esc(v.photo)}" alt="${esc(v.plate)}">`:`<p class="gfHint">${tr("Sin foto del veh\xEDculo.")}</p>`}
   <dl class="gfDl" style="margin-top:12px">
    <dt>${tr("Matr\xEDcula")}</dt><dd>${esc(v.plate)}</dd>
    <dt>${tr("Energ\xEDa")}</dt><dd>${tr(ENERGY[v.energy]||v.energy)}</dd>
    <dt>${tr("Primera matriculaci\xF3n")}</dt><dd>${esc(v.first_registration||"\u2014")}</dd>
    <dt>${tr("Kilometraje")}</dt><dd>${esc(num(v.odometer||0,0))} km</dd>
    ${v.kind==="truck"?`<dt>${tr("PTAC")}</dt><dd>${v.gvwr_kg==null?"\u2014":esc(num(v.gvwr_kg,0))+" kg"}</dd>`:""}
    <dt>${tr("Carga \xFAtil")}</dt><dd>${v.payload_kg==null?"\u2014":esc(num(v.payload_kg,0))+" kg"}</dd>
    <dt>${tr("Volumen de carga")}</dt><dd>${v.cargo_volume_m3==null?"\u2014":esc(num(v.cargo_volume_m3,2))+" m\xB3"}</dd>
    <dt>${tr("Consumo medio")}</dt><dd>${c.avg_litres_100km==null?"\u2014":esc(num(c.avg_litres_100km,2))+" L/100 km"}</dd>
    <dt>${tr("Coste por km")}</dt><dd>${c.cost_per_km==null?"\u2014":money(c.cost_per_km)}</dd>
    <dt>${tr("Conductor")}</dt><dd>${v.driver?esc(v.driver.name)+(v.driver.phone?" \xB7 "+esc(v.driver.phone):"")+(v.driver.since?" \xB7 "+tr("desde")+" "+esc(v.driver.since):""):"\u2014"}</dd>
   </dl>
   ${v.notes?`<p class="gfHint">${esc(v.notes)}</p>`:""}
   <div class="gfActions">
    <button class="arcButton secondary" id="gfEditVehicle" data-gi-live data-gi=25cb6fc10242>Modificar</button>
    <button class="arcButton secondary" id="gfPhoto" data-gi-live data-gi=9149e7dc2fa4>Foto del veh\xEDculo</button>
    <button class="arcButton secondary" id="gfAssign" data-gi-live data-gi=940bdfbfa57d>Asignar un conductor</button>
    ${v.driver?'<button class="arcButton secondary" id="gfUnassign" data-gi-live data-gi=2efcde959ffe>Retirar el conductor</button>':""}
    <button class="arcButton secondary" id="gfDeleteVehicle" data-gi-live data-gi=46af898b84fc>Dar de baja</button>
   </div></div>
  <div class="arcPanel gfCard"><h3>${tr("Historial de conductores")}</h3>
   ${(v.assignments||[]).length?`<div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
    <th>${tr("Conductor")}</th><th>${tr("Desde")}</th><th>${tr("Hasta")}</th><th></th></tr></thead><tbody>
    ${v.assignments.map(a=>`<tr><td>${esc(a.driver)}</td><td>${esc(a.started_on)}</td>
     <td>${a.ended_on?esc(a.ended_on):tr("En curso")}</td>
     <td><button class="arcButton secondary" data-gf-assign-del="${a.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join("")}
   </tbody></table></div>`:`<p class="gfHint">${tr("Ning\xFAn conductor ha llevado este veh\xEDculo todav\xEDa.")}</p>`}</div>`},documents(v){return`<div class="arcPanel gfCard"><h3>${tr("Documentos y vencimientos")}</h3>
   <p class="gfHint">${tr("Seguro, inspecci\xF3n t\xE9cnica y permiso de circulaci\xF3n. El aviso salta 30 d\xEDas antes.")}</p>
   ${(v.documents||[]).length?`<div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
    <th>${tr("Documento")}</th><th>${tr("Referencia")}</th><th>${tr("Expedido")}</th>
    <th>${tr("Vence")}</th><th>${tr("Archivo")}</th><th></th></tr></thead><tbody>
    ${v.documents.map(x=>{const r=remaining(x);return`<tr><td>${tr(DOCKIND[x.kind]||x.kind)}</td>
     <td>${esc(x.reference||"\u2014")}</td><td>${esc(x.issued_on||"\u2014")}</td>
     <td>${x.expires_on?esc(x.expires_on)+`<br><small class="gfHint">${r.html}</small>`:tr("Sin caducidad")}</td>
     <td>${x.has_file?`<button class="arcButton secondary" data-gf-file="${x.id}" data-gi-live data-gi=ed3d9c907370>Descargar</button>`:"\u2014"}</td>
     <td><button class="arcButton secondary" data-gf-doc-edit="${x.id}" data-gi-live data-gi=25cb6fc10242>Modificar</button>
      <button class="arcButton secondary" data-gf-doc-del="${x.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`}).join("")}
   </tbody></table></div>`:`<p class="gfHint">${tr("Ning\xFAn documento registrado.")}</p>`}
   <div class="gfActions"><button class="arcButton primary" id="gfNewDoc" data-gi-live data-gi=88fa2503185d>A\xF1adir un documento</button></div></div>`},fuel(v){const c=v.consumption||{};return`<div class="gfKpis">
   ${kpi("Consumo medio",c.avg_litres_100km==null?"\u2014":num(c.avg_litres_100km,2)+" L/100 km",tr("Dep\xF3sito lleno a dep\xF3sito lleno"))}
   ${kpi("Coste por km",c.cost_per_km==null?"\u2014":money(c.cost_per_km),unit(c.distance||0,"km medidos"))}
   ${kpi("Gasto en carburante",money(c.total_cost||0),unit(c.fills||0,"repostajes"))}
  </div>
  <div class="arcPanel gfCard"><h3>${tr("Repostajes")}</h3>
   <p class="gfHint">${tr("El kilometraje del veh\xEDculo sigue el repostaje m\xE1s reciente: no hace falta actualizarlo aparte.")}</p>
   ${(v.fuel||[]).length?`<div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
    <th>${tr("Fecha")}</th><th>${tr("Conductor")}</th><th class="gfNum">${tr("Kilometraje")}</th>
    <th class="gfNum">${tr("Litros")}</th><th class="gfNum">${tr("Importe")}</th>
    <th>${tr("Estaci\xF3n")}</th><th></th></tr></thead><tbody>
    ${v.fuel.map(f=>`<tr><td>${esc(f.logged_on)}</td><td>${esc(f.driver_name||"\u2014")}</td>
     <td class="gfNum">${num(f.odometer||0,0)}</td><td class="gfNum">${num(f.litres,2)}</td>
     <td class="gfNum">${money(f.amount)}</td><td>${esc(f.station||"\u2014")}</td>
     <td><button class="arcButton secondary" data-gf-fuel-del="${f.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join("")}
   </tbody></table></div>`:`<p class="gfHint">${tr("Ning\xFAn repostaje registrado.")}</p>`}
   <div class="gfActions"><button class="arcButton primary" id="gfNewFuel" data-gi-live data-gi=4d231fdc447c>Registrar un repostaje</button></div></div>`},maintenance(v){return`<div class="arcPanel gfCard"><h3>${tr("Entretenimientos")}</h3>
   <p class="gfHint">${tr("La pr\xF3xima revisi\xF3n se avisa por fecha o por kilometraje, lo que llegue antes.")}</p>
   ${(v.maintenance||[]).length?`<div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
    <th>${tr("Fecha")}</th><th>${tr("Tipo")}</th><th class="gfNum">${tr("Kilometraje")}</th>
    <th>${tr("Garaje")}</th><th class="gfNum">${tr("Coste")}</th>
    <th>${tr("Pr\xF3xima revisi\xF3n")}</th><th></th></tr></thead><tbody>
    ${v.maintenance.map(m=>`<tr><td>${esc(m.performed_on)}</td><td>${tr(MAINTKIND[m.kind]||m.kind)}</td>
     <td class="gfNum">${m.odometer==null?"\u2014":num(m.odometer,0)}</td><td>${esc(m.garage||"\u2014")}</td>
     <td class="gfNum">${money(m.cost)}</td>
     <td>${[m.next_service_on,m.next_service_odometer==null?"":num(m.next_service_odometer,0)+" km"].filter(Boolean).map(esc).join("<br>")||"\u2014"}</td>
     <td><button class="arcButton secondary" data-gf-maint-del="${m.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join("")}
   </tbody></table></div>`:`<p class="gfHint">${tr("Ning\xFAn entretenimiento registrado.")}</p>`}
   <div class="gfActions"><button class="arcButton primary" id="gfNewMaint" data-gi-live data-gi=bf1c913a5662>Registrar un entretenimiento</button></div></div>`}},TAB_BINDS={info({v,drivers}){$("gfEditVehicle").onclick=()=>vehicleForm(v),$("gfPhoto").onclick=()=>photoForm(v),$("gfAssign").onclick=()=>assignForm(v,drivers);const un=$("gfUnassign");un&&(un.onclick=()=>confirmAction("Retirar el conductor",`${v.driver?.name||""} dejar\xE1 de estar asignado a ${v.plate}. El historial se conserva.`,()=>mutate("unassign",{vehicle_id:v.id}))),document.querySelectorAll("[data-gf-assign-del]").forEach(b=>b.onclick=()=>confirmAction("Eliminar la l\xEDnea del historial","El veh\xEDculo deja de mostrar ese periodo con ese conductor.",()=>mutate("assignment_delete",{id:b.dataset.gfAssignDel}))),$("gfDeleteVehicle").onclick=()=>confirmDelete("Dar de baja el veh\xEDculo","Si el veh\xEDculo tiene historial se archiva y deja de aparecer en la lista; si nunca se us\xF3, se elimina.","Borrarlo definitivamente con sus documentos, repostajes y entretenimientos",async purge=>{await mutate("vehicle_delete",{id:v.id,purge}),vehicleId=null,section="vehicles"})},documents({v}){$("gfNewDoc").onclick=()=>documentForm(v,null),document.querySelectorAll("[data-gf-doc-edit]").forEach(b=>b.onclick=()=>documentForm(v,v.documents.find(x=>x.id===b.dataset.gfDocEdit))),document.querySelectorAll("[data-gf-doc-del]").forEach(b=>b.onclick=()=>confirmAction("Eliminar el documento","El documento y su archivo adjunto se borran.",()=>mutate("document_delete",{id:b.dataset.gfDocDel}))),document.querySelectorAll("[data-gf-file]").forEach(b=>b.onclick=async()=>{b.disabled=!0;try{const f=await rpc("document_file",{id:b.dataset.gfFile});if(!/^data:[\w.+-]+\/[\w.+-]+;base64,/.test(f.data_url||""))throw Error("El archivo no se pudo leer.");const a=document.createElement("a");a.href=f.data_url,a.download=f.filename||"documento",document.body.appendChild(a),a.click(),a.remove()}catch(e){window.gamaToast?.(err(e))}finally{b.disabled=!1}})},fuel({v}){$("gfNewFuel").onclick=()=>fuelForm(v.id),document.querySelectorAll("[data-gf-fuel-del]").forEach(b=>b.onclick=()=>confirmAction("Eliminar el repostaje","El consumo medio se recalcula sin \xE9l.",()=>mutate("fuel_delete",{id:b.dataset.gfFuelDel})))},maintenance({v}){$("gfNewMaint").onclick=()=>maintenanceForm(v.id),document.querySelectorAll("[data-gf-maint-del]").forEach(b=>b.onclick=()=>confirmAction("Eliminar el entretenimiento","La pr\xF3xima revisi\xF3n prevista se recalcula sin \xE9l.",()=>mutate("maintenance_delete",{id:b.dataset.gfMaintDel})))}};VIEWS.drivers={async load(){return rpc("drivers",{search:filters.search})},render(d){const rows=d.rows||[];return`<div class="gfTools">
   <label data-gi-live data-gi=5f55edf90089>Buscar<input id="gfSearch" type="search" value="${esc(filters.search)}" data-gi-placeholder=139d71c70f85 placeholder="Nombre, tel\xE9fono, permiso" data-gi-placeholder="live"></label>
   <label><button class="arcButton primary" id="gfNewDriver" data-gi-live data-gi=bbb27df1ab94>Nuevo conductor</button></label>
  </div>
  <div class="arcPanel gfCard"><div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
   <th>${tr("Conductor")}</th><th>${tr("Tel\xE9fono")}</th><th>${tr("Permiso")}</th>
   <th>${tr("Caduca")}</th><th>${tr("Veh\xEDculo")}</th><th></th></tr></thead><tbody>
   ${rows.map(r=>{const rr=remaining(r);return`<tr>
    <td><b>${esc(r.name)}</b>${r.employee_name?`<br><small class="gfHint">${esc(r.employee_name)}</small>`:""}</td>
    <td>${esc(r.phone||"\u2014")}</td>
    <td>${esc(r.licence_number||"\u2014")}${(r.licence_categories||[]).length?'<br><small class="gfHint">'+esc(r.licence_categories.join(", "))+"</small>":""}</td>
    <td>${r.licence_expiry?esc(r.licence_expiry)+`<br><small class="gfHint">${rr.html}</small>`:tr("Sin fecha")}</td>
    <td>${(r.vehicles||[]).map(x=>esc(x.plate)).join("<br>")||"\u2014"}</td>
    <td><button class="arcButton secondary" data-gf-driver-edit="${r.id}" data-gi-live data-gi=25cb6fc10242>Modificar</button>
     <button class="arcButton secondary" data-gf-driver-del="${r.id}" data-gi-live data-gi=46af898b84fc>Dar de baja</button></td></tr>`}).join("")||`<tr><td colspan="6">${tr("Ning\xFAn conductor registrado.")}</td></tr>`}
  </tbody></table></div></div>`},bind(d){let t=null;$("gfSearch").oninput=()=>{clearTimeout(t),t=setTimeout(()=>{filters.search=$("gfSearch").value,go()},350)},$("gfNewDriver").onclick=()=>driverForm(null,d.employees||[]),document.querySelectorAll("[data-gf-driver-edit]").forEach(b=>b.onclick=()=>driverForm(d.rows.find(x=>x.id===b.dataset.gfDriverEdit),d.employees||[])),document.querySelectorAll("[data-gf-driver-del]").forEach(b=>b.onclick=()=>confirmDelete("Dar de baja el conductor","Si tiene historial se archiva y deja de aparecer en las listas; si nunca condujo, se elimina.","Borrarlo definitivamente. Los repostajes se conservan y pierden a qui\xE9n se atribu\xEDan",purge=>mutate("driver_delete",{id:b.dataset.gfDriverDel,purge})))}},VIEWS.deadlines={async load(){const[rows,log]=await Promise.all([rpc("deadlines",{days:60}),rpc("alert_log")]);return{rows,log}},render({rows,log}){return`<div class="arcPanel gfCard"><h3>${tr("Vencimientos")}</h3>
   <p class="gfHint">${tr("Permisos de conducir, documentos del veh\xEDculo y revisiones previstas, a 60 d\xEDas.")}</p>
   ${rows.length?rows.map(dueRow).join(""):`<p class="gfHint">${tr("Nada vence en los pr\xF3ximos 60 d\xEDas.")}</p>`}</div>
  <div class="arcPanel gfCard"><h3>${tr("Avisos ya enviados")}</h3>
   <p class="gfHint">${tr("La comprobaci\xF3n corre sola cada d\xEDa. Cada vencimiento se avisa una sola vez.")}</p>
   ${log.length?`<div class="gfScroll"><table class="arcTable gfTable"><thead><tr>
    <th>${tr("Avisado el")}</th><th>${tr("Tipo")}</th><th>${tr("Detalle")}</th><th></th></tr></thead><tbody>
    ${log.map(a=>`<tr><td>${esc(new Date(a.notified_at).toLocaleString("es-EC"))}</td>
     <td>${tr(DEADLINE[a.kind]||a.kind)}</td><td>${esc(a.detail||"\u2014")}</td>
     <td><button class="arcButton secondary" data-gf-alert-del="${a.id}" data-gi-live data-gi=c9894cf002f9>Eliminar</button></td></tr>`).join("")}
   </tbody></table></div>
   <div class="gfActions"><button class="arcButton secondary" id="gfAlertClear" data-gi-live data-gi=815f78e0fc98>Vaciar el registro</button></div>`:`<p class="gfHint">${tr("Todav\xEDa no se ha enviado ning\xFAn aviso.")}</p>`}</div>`},bind(){document.querySelectorAll("[data-gf-alert-del]").forEach(b=>b.onclick=()=>confirmAction("Eliminar el aviso","Si el vencimiento sigue vigente se volver\xE1 a avisar en la pr\xF3xima comprobaci\xF3n.",()=>mutate("alert_delete",{id:b.dataset.gfAlertDel}))),$("gfAlertClear")&&($("gfAlertClear").onclick=()=>confirmAction("Vaciar el registro de avisos","Se borran todos los avisos ya enviados. Lo que siga vencido se volver\xE1 a se\xF1alar en la pr\xF3xima comprobaci\xF3n.",()=>mutate("alert_clear",{})))}};const val=(el,id)=>el.querySelector("#"+id)?.value||"";function options(map,selected){return Object.entries(map).map(([k,v])=>`<option value="${k}" ${selected===k?"selected":""} data-gi-live>${esc(v)}</option>`).join("")}function confirmAction(title,text,run){window.GamaSales.modal(GamaI18n?.t?.(title)||title,`<p>${tr(text)}</p>`,GamaI18n?.t?.("Confirmar")||"Confirmar",async()=>{await run(),state.overview=null,await go()})}function confirmDelete(title,text,purgeText,run){window.GamaSales.modal(GamaI18n?.t?.(title)||title,`<p>${tr(text)}</p>
   <label class="gfField gfDanger" style="font-weight:600"><input type="checkbox" id="gfPurge"> ${tr(purgeText)}</label>
   <p class="gfHint">${tr("Lo borrado no se recupera. La auditor\xEDa conserva qui\xE9n lo borr\xF3 y cu\xE1ndo.")}</p>`,GamaI18n?.t?.("Confirmar")||"Confirmar",async el=>{await run(el.querySelector("#gfPurge").checked),state.overview=null,await go()})}function vehicleForm(v){const truck=v?.kind==="truck",el=window.GamaSales.modal(GamaI18n?.t?.(v?"Modificar el veh\xEDculo":"Nuevo veh\xEDculo")||"",`<div class="gfGrid">
   <label data-gi-live data-gi=ae197ddc6091>Matr\xEDcula<input id="gfPlate" required maxlength="20" value="${esc(v?.plate||"")}" autocapitalize="characters"></label>
   <label data-gi-live data-gi=8e2ca9b0cc8a>Marca<input id="gfBrand" required maxlength="60" value="${esc(v?.brand||"")}"></label>
   <label data-gi-live data-gi=a5ab3212dad1>Modelo<input id="gfModel" required maxlength="60" value="${esc(v?.model||"")}"></label>
   <label data-gi-live data-gi=3868d2843d59>Tipo<select id="gfVKind">${options(KIND,v?.kind||"car")}</select></label>
   <label data-gi-live data-gi=34961a7f187b>Energ\xEDa<select id="gfEnergy">${options(ENERGY,v?.energy||"diesel")}</select></label>
   <label data-gi-live data-gi=3d4efd97d4ee>Primera matriculaci\xF3n<input id="gfFirstReg" type="date" value="${esc(v?.first_registration||"")}"></label>
   <label data-gi-live data-gi=b3c3618d9228>Kilometraje<input id="gfOdo" type="number" inputmode="numeric" min="0" step="1" value="${esc(v?.odometer??0)}"></label>
   <label data-gi-live data-gi=98e5acddb6c4>Estado<select id="gfVStatus">${options(STATUS,v?.status||"in_service")}</select></label>
  </div>
  <div class="gfGrid" id="gfTruckBox" ${truck?"":"hidden"}>
   <label data-gi-live data-gi=10401a12d289>PTAC (kg)<input id="gfGvwr" type="number" inputmode="numeric" min="1" step="1" value="${esc(v?.gvwr_kg??"")}"></label>
  </div>
  <div class="gfGrid">
   <label data-gi-live data-gi=6c3dba7e3c12>Carga \xFAtil (kg)<input id="gfPayload" type="number" inputmode="numeric" min="1" step="1" value="${esc(v?.payload_kg??"")}"></label>
   <label data-gi-live data-gi=7a471aa837f5>Volumen de carga (m\xB3)<input id="gfVolume" type="number" inputmode="decimal" min="0.1" step="0.1" value="${esc(v?.cargo_volume_m3??"")}"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfNotes" maxlength="2000">${esc(v?.notes||"")}</textarea></label>
  <p class="gfHint">${tr("El PTAC s\xF3lo se pide para los camiones. La carga \xFAtil y el volumen los usa el TMS para repartir las entregas.")}</p>`,GamaI18n?.t?.("Guardar")||"Guardar",async form=>{await mutate("vehicle_save",{id:v?.id||null,plate:val(form,"gfPlate"),brand:val(form,"gfBrand"),model:val(form,"gfModel"),kind:val(form,"gfVKind"),energy:val(form,"gfEnergy"),first_registration:val(form,"gfFirstReg"),odometer:val(form,"gfOdo"),status:val(form,"gfVStatus"),gvwr_kg:val(form,"gfGvwr"),payload_kg:val(form,"gfPayload"),cargo_volume_m3:val(form,"gfVolume"),notes:val(form,"gfNotes")}),state.overview=null,await go()});el.querySelector("#gfVKind").onchange=e=>{el.querySelector("#gfTruckBox").hidden=e.target.value!=="truck"}}function shrink(file,max=1024){return new Promise((resolve,reject)=>{const img=new Image,url=URL.createObjectURL(file);img.onload=()=>{URL.revokeObjectURL(url);const s=Math.min(1,max/Math.max(img.width,img.height)),cv=document.createElement("canvas");cv.width=Math.round(img.width*s),cv.height=Math.round(img.height*s),cv.getContext("2d").drawImage(img,0,0,cv.width,cv.height),resolve(cv.toDataURL("image/jpeg",.75))},img.onerror=()=>{URL.revokeObjectURL(url),reject(Error("La imagen no se pudo leer."))},img.src=url})}function photoForm(v){window.GamaSales.modal(GamaI18n?.t?.("Foto del veh\xEDculo")||"Foto",`<label class="gfField" data-gi-live data-gi=58d6f29b0633>Imagen<input id="gfPhotoFile" type="file" accept="image/*" capture="environment"></label>
  <p class="gfHint">${tr("Se reduce sola antes de guardarse. Deja el campo vac\xEDo para quitar la foto actual.")}</p>`,GamaI18n?.t?.("Guardar")||"Guardar",async form=>{const f=form.querySelector("#gfPhotoFile").files[0];await mutate("vehicle_photo",{id:v.id,photo:f?await shrink(f):""}),await go()})}function assignForm(v,drivers){window.GamaSales.modal(GamaI18n?.t?.("Asignar un conductor")||"",`<div class="gfGrid">
   <label data-gi-live data-gi=14116bf4372e>Conductor<select id="gfDriver" required><option value="" data-gi-live data-gi=3c41f9546e61>Seleccionar\u2026</option>
    ${drivers.map(d=>`<option value="${d.id}" ${v.driver?.id===d.id?"selected":""}>${esc(d.name)}</option>`).join("")}</select></label>
   <label data-gi-live data-gi=8b4e93e928df>Desde<input id="gfFrom" type="date" value="${esc(day())}"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfANotes" maxlength="1000"></textarea></label>
  <p class="gfHint">${tr("Un veh\xEDculo tiene un conductor a la vez: el anterior se cierra solo y queda en el historial.")}</p>`,GamaI18n?.t?.("Asignar")||"Asignar",async form=>{if(!val(form,"gfDriver"))throw Error("Selecciona un conductor.");await mutate("assign",{vehicle_id:v.id,driver_id:val(form,"gfDriver"),started_on:val(form,"gfFrom"),notes:val(form,"gfANotes")}),await go()})}function driverForm(d,employees){const cats=["A","B","C","D","E"];window.GamaSales.modal(GamaI18n?.t?.(d?"Modificar el conductor":"Nuevo conductor")||"",`<div class="gfGrid">
   <label data-gi-live data-gi=562bb15757a8>Nombre<input id="gfDName" required maxlength="120" value="${esc(d?.name||"")}"></label>
   <label data-gi-live data-gi=f1186abd0b8b>Tel\xE9fono<input id="gfDPhone" type="tel" inputmode="tel" maxlength="40" value="${esc(d?.phone||"")}"></label>
   <label data-gi-live data-gi=1b98753ff261>N\xFAmero de permiso<input id="gfDLic" maxlength="60" value="${esc(d?.licence_number||"")}"></label>
   <label data-gi-live data-gi=b6115749e877>Caducidad del permiso<input id="gfDExp" type="date" value="${esc(d?.licence_expiry||"")}"></label>
   <label data-gi-live data-gi=6f0babb30673>Empleado<select id="gfDEmp"><option value="" data-gi-live data-gi=3c2b0b48e3a0>Sin vincular</option>
    ${employees.map(e=>`<option value="${e.id}" ${d?.employee_id===e.id?"selected":""}>${esc(e.name)}</option>`).join("")}</select></label>
  </div>
  <div class="gfField"><span data-gi-live data-gi=4d37c139ac37>Categor\xEDas del permiso</span>
   <div class="gfVehMeta">${cats.map(c=>`<label style="font-weight:600"><input type="checkbox" data-gf-cat value="${c}" ${(d?.licence_categories||[]).includes(c)?"checked":""}> ${c}</label>`).join("")}</div></div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfDNotes" maxlength="2000">${esc(d?.notes||"")}</textarea></label>
  <p class="gfHint">${tr("Vincular al empleado evita teclear dos veces la misma persona; no es obligatorio.")}</p>`,GamaI18n?.t?.("Guardar")||"Guardar",async form=>{await mutate("driver_save",{id:d?.id||null,name:val(form,"gfDName"),phone:val(form,"gfDPhone"),licence_number:val(form,"gfDLic"),licence_expiry:val(form,"gfDExp"),employee_id:val(form,"gfDEmp"),licence_categories:[...form.querySelectorAll("[data-gf-cat]:checked")].map(x=>x.value),notes:val(form,"gfDNotes")}),state.overview=null,await go()})}function documentForm(v,x){window.GamaSales.modal(GamaI18n?.t?.(x?"Modificar el documento":"A\xF1adir un documento")||"",`<div class="gfGrid">
   <label data-gi-live data-gi=cf4279e00d07>Documento<select id="gfDocKind">${options(DOCKIND,x?.kind||"insurance")}</select></label>
   <label data-gi-live data-gi=10ddff5fcc6f>Referencia<input id="gfDocRef" maxlength="120" value="${esc(x?.reference||"")}"></label>
   <label data-gi-live data-gi=b218a27cd772>Expedido el<input id="gfDocIssued" type="date" value="${esc(x?.issued_on||"")}"></label>
   <label data-gi-live data-gi=a2357698522d>Vence el<input id="gfDocExp" type="date" value="${esc(x?.expires_on||"")}"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=b8be96d00e42>Archivo adjunto<input id="gfDocFile" type="file" accept="image/*,application/pdf" capture="environment"></label>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfDocNotes" maxlength="1000">${esc(x?.notes||"")}</textarea></label>
  <p class="gfHint">${tr("Hasta 2,5 MB. Si dejas el archivo vac\xEDo se conserva el que ya estaba.")}</p>`,GamaI18n?.t?.("Guardar")||"Guardar",async form=>{const f=form.querySelector("#gfDocFile").files[0];let data_url="",filename="",mime_type="";if(f){if(f.size>25e5)throw Error("FILE_TOO_LARGE");filename=f.name,mime_type=f.type||"application/octet-stream",data_url=f.type.startsWith("image/")?await shrink(f,1600):await new Promise((ok,ko)=>{const r=new FileReader;r.onload=()=>ok(r.result),r.onerror=()=>ko(Error("El archivo no se pudo leer.")),r.readAsDataURL(f)})}await mutate("document_save",{id:x?.id||null,vehicle_id:v.id,kind:val(form,"gfDocKind"),reference:val(form,"gfDocRef"),issued_on:val(form,"gfDocIssued"),expires_on:val(form,"gfDocExp"),filename,mime_type,data_url,notes:val(form,"gfDocNotes")}),await go()})}async function pickVehicle(current){return current?{id:current,list:null}:{id:null,list:(await rpc("vehicles",{})).rows||[]}}async function fuelForm(current){let ctx;try{ctx=await pickVehicle(current)}catch(e){return window.gamaToast?.(err(e))}const key=crypto.randomUUID();window.GamaSales.modal(GamaI18n?.t?.("Registrar un repostaje")||"",`<div class="gfGrid">
   ${ctx.list?`<label data-gi-live data-gi=e4579a8b1ea4>Veh\xEDculo<select id="gfFVeh" required><option value="" data-gi-live data-gi=3c41f9546e61>Seleccionar\u2026</option>
    ${ctx.list.map(v=>`<option value="${v.id}">${esc(v.plate)} \xB7 ${esc(v.brand)} ${esc(v.model)}</option>`).join("")}</select></label>`:""}
   <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="gfFDate" type="date" value="${esc(day())}"></label>
   <label data-gi-live data-gi=b3c3618d9228>Kilometraje<input id="gfFOdo" type="number" inputmode="numeric" min="0" step="1" required></label>
   <label data-gi-live data-gi=4d6711f5e657>Litros<input id="gfFLitres" type="number" inputmode="decimal" min="0.01" step="0.01" required></label>
   <label data-gi-live data-gi=572a3acfd983>Importe<input id="gfFAmount" type="number" inputmode="decimal" min="0" step="0.01" required></label>
   <label data-gi-live data-gi=f328c354bbef>Estaci\xF3n<input id="gfFStation" maxlength="120"></label>
  </div>
  <label class="gfField" style="font-weight:600"><input type="checkbox" id="gfFFull" checked> ${tr("Dep\xF3sito lleno")}</label>
  <p class="gfHint">${tr("El consumo medio se calcula de dep\xF3sito lleno a dep\xF3sito lleno. El kilometraje del veh\xEDculo se actualiza solo.")}</p>`,GamaI18n?.t?.("Guardar")||"Guardar",async form=>{const vid=ctx.id||val(form,"gfFVeh");if(!vid)throw Error("Selecciona un veh\xEDculo.");await mutate("fuel_save",{request_key:key,vehicle_id:vid,logged_on:val(form,"gfFDate"),odometer:val(form,"gfFOdo"),litres:val(form,"gfFLitres"),amount:val(form,"gfFAmount"),station:val(form,"gfFStation"),full_tank:form.querySelector("#gfFFull").checked}),state.overview=null,await go()})}async function maintenanceForm(current){let ctx;try{ctx=await pickVehicle(current)}catch(e){return window.gamaToast?.(err(e))}const key=crypto.randomUUID();window.GamaSales.modal(GamaI18n?.t?.("Registrar un entretenimiento")||"",`<div class="gfGrid">
   ${ctx.list?`<label data-gi-live data-gi=e4579a8b1ea4>Veh\xEDculo<select id="gfMVeh" required><option value="" data-gi-live data-gi=3c41f9546e61>Seleccionar\u2026</option>
    ${ctx.list.map(v=>`<option value="${v.id}">${esc(v.plate)} \xB7 ${esc(v.brand)} ${esc(v.model)}</option>`).join("")}</select></label>`:""}
   <label data-gi-live data-gi=93b2a9ef782c>Fecha<input id="gfMDate" type="date" value="${esc(day())}"></label>
   <label data-gi-live data-gi=3868d2843d59>Tipo<select id="gfMKind">${options(MAINTKIND,"service")}</select></label>
   <label data-gi-live data-gi=b3c3618d9228>Kilometraje<input id="gfMOdo" type="number" inputmode="numeric" min="0" step="1"></label>
   <label data-gi-live data-gi=bc1767d0530e>Garaje<input id="gfMGarage" maxlength="120"></label>
   <label data-gi-live data-gi=c940e0fbc42f>Coste<input id="gfMCost" type="number" inputmode="decimal" min="0" step="0.01" value="0"></label>
   <label data-gi-live data-gi=50c713c6250a>Pr\xF3xima revisi\xF3n (fecha)<input id="gfMNextOn" type="date"></label>
   <label data-gi-live data-gi=f736a163bd23>Pr\xF3xima revisi\xF3n (km)<input id="gfMNextKm" type="number" inputmode="numeric" min="0" step="1"></label>
  </div>
  <label class="gfField" data-gi-live data-gi=53c367898434>Comentario<textarea id="gfMNotes" maxlength="2000"></textarea></label>
  <p class="gfHint">${tr("Se avisa por fecha o por kilometraje, lo que llegue antes. Puedes dejar los dos vac\xEDos.")}</p>`,GamaI18n?.t?.("Guardar")||"Guardar",async form=>{const vid=ctx.id||val(form,"gfMVeh");if(!vid)throw Error("Selecciona un veh\xEDculo.");await mutate("maintenance_save",{request_key:key,vehicle_id:vid,performed_on:val(form,"gfMDate"),kind:val(form,"gfMKind"),odometer:val(form,"gfMOdo"),garage:val(form,"gfMGarage"),cost:val(form,"gfMCost"),next_service_on:val(form,"gfMNextOn"),next_service_odometer:val(form,"gfMNextKm"),notes:val(form,"gfMNotes")}),state.overview=null,await go()})}function download(rows,name){if(!rows||!rows.length){window.gamaToast?.(GamaI18n?.t?.("No hay nada que exportar.")||"No hay nada que exportar.");return}const keys=[...rows.reduce((s,r)=>(Object.keys(r).forEach(k=>typeof r[k]!="object"&&s.add(k)),s),new Set)],cell=v=>v==null?"":/[";\n]/.test(String(v))?'"'+String(v).replace(/"/g,'""')+'"':String(v),csv="\uFEFF"+[keys.join(";"),...rows.map(r=>keys.map(k=>cell(r[k])).join(";"))].join(`
`),url=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"})),a=document.createElement("a");a.href=url,a.download=`Coco-ERP-${name}-${day()}.csv`,document.body.appendChild(a),a.click(),a.remove(),setTimeout(()=>URL.revokeObjectURL(url),4e3)}async function exportAll(){try{const d=await rpc("export",{from:monthStart(),to:day()});download(d.vehicles,"flota-vehiculos"),download(d.expenses,"flota-gastos")}catch(e){window.gamaToast?.(err(e))}}window.addEventListener("gama:currency-change",()=>{$(ID)?.classList.contains("active")&&go()}),window.GamaFleet={open,openVehicle,openDriver,rpc,SECTIONS}})();
