/* Generated from src/features/hr/workspace.js. Edit the source and run npm run build. */
(function(){"use strict";if(window.GamaHR&&!window.GamaHR.__arcLazy)return;const C=()=>window.GamaCloud,$=id=>document.getElementById(id),esc=window.ArcUI.esc,money=v=>Number(v||0).toLocaleString("es-EC",{style:"currency",currency:"USD",minimumFractionDigits:2,maximumFractionDigits:2}),day=v=>{if(!v)return"\u2014";try{return new Date(v+"T12:00:00").toLocaleDateString("es-EC")}catch{return String(v)}},today=()=>new Intl.DateTimeFormat("en-CA",{timeZone:globalThis.window?.GamaCompany?.get()?.timezone||"America/Guayaquil",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date),KINDS={vacaciones:"Vacaciones",enfermedad:"Enfermedad",permiso:"Permiso",formacion:"Formaci\xF3n",otro:"Otro"},STATUS={pendiente:"Pendiente",aprobada:"Aprobada",rechazada:"Rechazada",cancelada:"Cancelada"};let employees=[],absences=[],tab="empleados",editing=null,busy=!1,loadVersion=0,mine=null,perfiles=[],myUid=null,employeePhoto="",photoChanged=!1,photoBusy=!1,photoVersion=0;const role=()=>{try{return JSON.parse(localStorage.getItem("gama_session_v1")||"null")?.role||""}catch{return""}},isSystemAdmin=()=>role()==="admin"||role()==="administrador",isHRRole=()=>["rh","rrhh"].includes(role()),isAdmin=()=>isSystemAdmin()||isHRRole();let planAnchor=new Date,planView="semana",planPick=null;function ymd(d){const p=n=>String(n).padStart(2,"0");return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate())}function fromYmd(s){const[y,m,d]=String(s||"").split("-").map(Number);return new Date(y,(m||1)-1,d||1)}const DIA_MS=864e5;function diffDays(a,b){return Math.round((fromYmd(ymd(b))-fromYmd(ymd(a)))/DIA_MS)}function msg(t,err){const m=$("hrMsg");m&&(m.textContent=t||"",m.className="hrMsg"+(t?err?" hrErr":" hrOk":""))}function fail(e,what){console.warn("[GAMA RRHH]",what,e),msg(what+": "+(e&&(e.message||e.details)||e),!0)}function workingDays(from,to){if(!from||!to)return 0;const a=new Date(from+"T12:00:00"),b=new Date(to+"T12:00:00");if(isNaN(a)||isNaN(b)||b<a)return 0;let n=0;for(const d=new Date(a);d<=b;d.setDate(d.getDate()+1)){const w=d.getDay();w!==0&&w!==6&&n++}return n}function usedLeave(employeeId,year){return window.GamaHRP1?window.GamaHRP1.used(employeeId,year):absences.filter(a=>a.employee_id===employeeId&&a.kind==="vacaciones"&&a.status==="aprobada").reduce((sum,a)=>sum+workingDays(a.start_date>year+"-01-01"?a.start_date:year+"-01-01",a.end_date<year+"-12-31"?a.end_date:year+"-12-31"),0)}function employeeName(id){return(employees.find(e=>e.id===id)||{}).full_name||"Empleado"}function onLeaveToday(){const t=today();return absences.filter(a=>a.status==="aprobada"&&a.start_date<=t&&a.end_date>=t)}async function load(){const version=++loadVersion,api=C();if(!api){msg("La conexi\xF3n con la nube de Coco ERP no est\xE1 disponible.",!0);return}try{const[e,a,ep,ap,ses]=await Promise.all([api.list("hr_employees",{order:"full_name",ascending:!0}),api.list("hr_absences",{order:"start_date",ascending:!1}),api.list("hr_employee_private",{}),api.list("hr_absence_private",{}),api.getSession()]);if(version!==loadVersion)return;if(e.error)throw e.error;if(a.error)throw a.error;if(ep.error)throw ep.error;if(ap.error)throw ap.error;myUid=ses?.data?.session?.user?.id||null;const priv=new Map((ep.error?[]:ep.data||[]).map(r=>[r.employee_id,r])),privA=new Map((ap.error?[]:ap.data||[]).map(r=>[r.absence_id,r]));if(employees=(e.data||[]).map(x=>Object.assign({},x,priv.get(x.id)||{})),absences=(a.data||[]).map(x=>Object.assign({},x,privA.get(x.id)||{})),mine=employees.find(x=>x.profile_id&&x.profile_id===myUid)||null,window.GamaHRP1&&await window.GamaHRP1.load({employees,absences,myUid,hr:isAdmin()})===!1||version!==loadVersion||(isAdmin()&&await loadProfiles(),version!==loadVersion))return;render()}catch(err){fail(err,"No se pudieron cargar los datos de RRHH")}}async function loadProfiles(){if(window.GamaHRP1?.directory.length){perfiles=window.GamaHRP1.directory;return}try{const r=await C().list("profiles",{select:"id,full_name,email,role,active",order:"full_name",ascending:!0});perfiles=r.error?[]:(r.data||[]).filter(p=>p.active!==!1&&p.role!=="cliente")}catch{perfiles=[]}}const FIELDS=["hrName","hrId","hrEmail","hrPhone","hrPosition","hrDept","hrManager","hrContract","hrHire","hrEnd","hrSalary","hrLeaveDays","hrNotes","hrAccount"];function clearEmployee(){editing=null,employeePhoto="",photoChanged=!1,photoBusy=!1,photoVersion++,FIELDS.forEach(id=>{const el=$(id);el&&(el.value=id==="hrLeaveDays"?"15":"")});const b=$("hrSave");b&&(b.textContent="Guardar empleado"),msg("")}async function saveEmployee(){if(busy||photoBusy)return;const name=($("hrName").value||"").trim();if(!name)return msg("El nombre del empleado es obligatorio.",!0);const num=v=>{const n=parseFloat(String(v).replace(",","."));return Number.isFinite(n)?n:null},row={full_name:name,position:($("hrPosition").value||"").trim()||null,department:($("hrDept").value||"").trim()||null,profile_id:$("hrAccount")?.value||null};photoChanged&&(row.photo_data=employeePhoto||null),$("hrManager")&&(row.manager_id=$("hrManager").value||null);const priv={identification:($("hrId").value||"").trim()||null,email:($("hrEmail").value||"").trim()||null,phone:($("hrPhone").value||"").trim()||null,contract_type:$("hrContract").value||null,hire_date:$("hrHire").value||null,end_date:$("hrEnd").value||null,salary:num($("hrSalary").value),annual_leave_days:num($("hrLeaveDays").value)??15,notes:($("hrNotes").value||"").trim()||null};busy=!0;try{const r=await window.ArcData.rawRpc("gama_hr_save_employee",{p_id:editing,p_employee:row,p_private:priv});if(r.error)throw r.error;window.dispatchEvent(new CustomEvent("gama:employee-photo-change")),clearEmployee(),msg(editing?"Ficha actualizada.":"Empleado a\xF1adido."),await load()}catch(e){fail(window.GamaHRP1?.managerError(e)||e,"No se pudo guardar el empleado")}finally{busy=!1}}function editEmployee(id){const p=employees.find(x=>x.id===id);if(!p)return;photoVersion++,photoBusy=!1,employeePhoto=window.GamaEmployeePhotos?.valid(p.photo_data)||"",photoChanged=!1,editing=id,tab="empleados",render();const set=(el,v)=>{const n=$(el);n&&(n.value=v)};set("hrName",p.full_name||""),set("hrId",p.identification||""),set("hrEmail",p.email||""),set("hrPhone",p.phone||""),set("hrPosition",p.position||""),set("hrDept",p.department||""),set("hrContract",p.contract_type||""),set("hrHire",p.hire_date||""),set("hrEnd",p.end_date||""),set("hrSalary",p.salary??""),set("hrLeaveDays",p.annual_leave_days??15),set("hrNotes",p.notes||""),set("hrAccount",p.profile_id||""),set("hrManager",p.manager_id||""),msg("Editando la ficha de "+p.full_name+"."),paintEmployeePhoto(),$("hrName")?.scrollIntoView({behavior:"smooth",block:"center"})}async function archiveEmployee(id,on){try{const r=await C().update("hr_employees",id,{active:!!on});if(r.error)throw r.error;window.dispatchEvent(new CustomEvent("gama:employee-photo-change")),await load()}catch(e){fail(e,"No se pudo cambiar el estado del empleado")}}async function addAbsence(){if(busy)return;const sel=$("hrAbsEmployee"),employee_id=sel?sel.value:mine&&mine.id||"",start_date=$("hrAbsFrom").value,end_date=$("hrAbsTo").value;if(!employee_id)return msg("Elige un empleado.",!0);if(!start_date||!end_date)return msg("Indica la fecha de inicio y la de fin.",!0);if(end_date<start_date)return msg("La fecha de fin no puede ser anterior a la de inicio.",!0);busy=!0;try{const r=await C().insert("hr_absences",{employee_id,kind:$("hrAbsKind").value,start_date,end_date,start_fraction:Number($("hpStartFraction")?.value||1),end_fraction:Number($("hpEndFraction")?.value||1),status:isAdmin()&&$("hrAbsStatus")?.value||"pendiente",decision_reason:["rechazada","cancelada"].includes($("hrAbsStatus")?.value)?$("hrAbsReason").value:null});if(r.error)throw r.error;const motivo=($("hrAbsReason").value||"").trim();if(motivo&&r.data?.id){const m=await C().insert("hr_absence_private",{absence_id:r.data.id,reason:motivo});m.error&&console.warn("[GAMA RRHH] no se guard\xF3 el comentario",m.error)}$("hrAbsFrom").value="",$("hrAbsTo").value="",$("hrAbsReason").value="",msg(isAdmin()?"Ausencia registrada.":"Solicitud enviada. Queda pendiente de aprobaci\xF3n."),await load()}catch(e){fail(e,"No se pudo registrar la ausencia")}finally{busy=!1}}async function setAbsenceStatus(id,status){try{const reason=status==="rechazada"?prompt(window.GamaI18n?.t("Motivo")||"Motivo"):null;if(status==="rechazada"&&!reason?.trim())return;const r=await C().update("hr_absences",id,{status,decision_reason:reason});if(r.error)throw r.error;await load()}catch(e){fail(e,"No se pudo cambiar el estado de la ausencia")}}async function removeAbsence(id){const reason=prompt(window.GamaI18n?.t("Motivo de anulaci\xF3n")||"Motivo de anulaci\xF3n");if(reason?.trim())try{const r=await C().update("hr_absences",id,{status:"cancelada",decision_reason:reason});if(r.error)throw r.error;await load()}catch(e){fail(e,"No se pudo anular la ausencia")}}function section(){let s=$("hr");return s||(s=document.createElement("section"),s.id="hr",(document.querySelector(".wrap")||document.body).appendChild(s)),s}function css(){}function duracion(a){const n=Number.isFinite(Number(a.days))&&a.days!==null&&a.days!==""?Number(a.days):Math.round((new Date(a.end_date)-new Date(a.start_date))/864e5)+1;let txt=n===1?"1 d\xEDa natural":n+" d\xEDas naturales";if(a.kind==="vacaciones"){const l=Number(window.GamaHRP1?window.GamaHRP1.days(a.employee_id,a.start_date,a.end_date,a.start_fraction??1,a.end_fraction??1):workingDays(a.start_date,a.end_date));txt+=" \xB7 "+(l===1?"1 d\xEDa laborable":l+" d\xEDas laborables")}return"<span data-gi-live>"+esc(txt)+"</span>"}function kpis(){const activos=employees.filter(e=>e.active!==!1).length,fuera=onLeaveToday().length,pend=absences.filter(a=>a.status==="pendiente").length,year=new Date().getFullYear(),enfermos=absences.filter(a=>a.kind==="enfermedad"&&String(a.start_date||"").slice(0,4)===String(year)).length;return`<div class="hrKpis">
  <div class="hrKpi"><span data-gi=e0a032ea89a6>Empleados activos</span><b>${activos}</b></div>
  <div class="hrKpi"><span data-gi=24635c11f693>Ausentes hoy</span><b>${fuera}</b></div>
  <div class="hrKpi"><span data-gi=8159fcc540c4>Pendientes de aprobar</span><b>${pend}</b></div>
  <div class="hrKpi"><span><span data-gi=d2e61c2d0c29>Bajas por enfermedad </span>${year}</span><b>${enfermos}</b></div>
 </div>`}function employeesTab(){const year=new Date().getFullYear(),rows=employees.map(p=>{const total=window.GamaHRP1?window.GamaHRP1.entitlement(p.id,year):Number(p.annual_leave_days||0),used=usedLeave(p.id,year),pct=total>0?Math.min(100,Math.round(used/total*100)):0,off=p.active===!1;return`<tr class="${off?"hrOff":""}">
   <td><div class="hrPerson"><span class="hrEmployeeAvatar" data-employee-avatar="${esc(p.id)}"></span><div><b>${esc(p.full_name)}</b><small>${p.position?esc(p.position):"<span data-gi-live data-gi=cb1226ba9d86>Sin puesto</span>"}${p.department?" \xB7 "+esc(p.department):""}</small>
       <small>${esc(p.identification||"")}</small></div></div></td>
   <td>${esc(p.contract_type||"\u2014")}<small><span data-gi=cdd3851b36eb>Alta: </span>${day(p.hire_date)}</small>${p.end_date?`<small><span data-gi=82a0a91a8205>Baja: </span>${day(p.end_date)}</small>`:""}</td>
   <td>${p.salary==null?"\u2014":money(p.salary)}</td>
   <td>${used} / ${total}<small><span data-gi=14a00985becf>d\xEDas laborables </span>${year}</small>
       <div class="hrBar"><i class="${pct>=100?"full":""}" style="width:${pct}%"></i></div></td>
   <td>${off?'<span class="hrBadge" data-gi=eac5386d4211>Archivado</span>':'<span class="hrBadge ok" data-gi=723858144bd5>Activo</span>'}${p.profile_id?'<br><span class="hrBadge ok" style="margin-top:4px" data-gi=dd4b9a1f56aa>Con cuenta</span>':'<br><span class="hrBadge" style="margin-top:4px" data-gi=b4c10bd2c2fc>Sin cuenta</span>'}</td>
   <td><div class="hrActs">
    <button type="button" class="arcButton secondary" data-edit="${esc(p.id)}" data-gi=2eba946b2e1e>Editar</button>
    <button type="button" class="arcButton ${off?"secondary":"danger"}" data-arch="${esc(p.id)}" data-on="${off?"1":"0"}" data-gi-live>${off?"Restaurar":"Archivar"}</button>
   </div></td></tr>`}).join("");return`<div class="hrGrid">
  <div class="arcPanel card">
   <h3 data-gi-live>${editing?"Editar empleado":"Nuevo empleado"}</h3>
   <div class="hrPhotoEditor"><span id="hrPhotoPreview" class="hrEmployeeAvatar" aria-hidden="true"></span><div>
    <label for="hrPhoto">${esc(window.GamaEmployeePhotos?.t("label")||"Foto del empleado")}</label>
    <input id="hrPhoto" type="file" accept="image/jpeg,image/png,image/webp" aria-describedby="hrPhotoHelp">
    <small id="hrPhotoHelp">${esc(window.GamaEmployeePhotos?.t("help")||"JPG, PNG o WebP.")}</small>
    <button type="button" id="hrPhotoRemove" class="arcButton secondary hrPhotoRemove">${esc(window.GamaEmployeePhotos?.t("remove")||"Quitar foto")}</button>
   </div></div>
   <label data-gi=0be48a5a67cc>Nombre y apellidos *</label><input id="hrName" data-gi-placeholder=d6730d8299a4 placeholder="Ej. Mar\xEDa P\xE9rez">
   <div class="row">
    <div><label data-gi=48fdf0f9d94c>C\xE9dula / RUC</label><input id="hrId" placeholder="0912345678"></div>
    <div><label data-gi=f1186abd0b8b>Tel\xE9fono</label><input id="hrPhone" type="tel" placeholder="+593\u2026"></div>
   </div>
   <label data-gi=ec64dc30a483>Correo electr\xF3nico</label><input id="hrEmail" type="email" data-gi-placeholder=19be3df30e22 placeholder="correo@ejemplo.com">
   <div class="row">
    <div><label data-gi=888f25ceee71>Puesto</label><input id="hrPosition" data-gi-placeholder=47f913f15782 placeholder="Ej. Almacenero"></div>
    <div><label data-gi=4695dca246f0>Departamento</label><input id="hrDept" data-gi-placeholder=749ad86d9ec3 placeholder="Ej. Bodega"></div>
   </div>
   ${window.GamaHRP1?.managerOptions?`<label data-gi-live data-gi=d49bc822266a>N+1 (responsable directo)</label><select id="hrManager">${window.GamaHRP1.managerOptions(editing)}</select>`:""}
   <label data-gi=d27403823536>Tipo de contrato</label>
   <select id="hrContract">
    <option value="" data-gi=e545b02d8dee>Sin especificar</option>
    <option data-gi=eddd72ca1009>Indefinido</option><option data-gi=d9460e0cb708>Plazo fijo</option><option data-gi=42413a38c5a9>Eventual</option>
    <option data-gi=ac3f091ca341>Prueba</option><option data-gi=817e41b7b714>Prestaci\xF3n de servicios</option><option data-gi=daa9133ba2c4>Pasant\xEDa</option>
   </select>
   <div class="row">
    <div><label data-gi=62956ad3a5c1>Fecha de alta</label><input id="hrHire" type="date"></div>
    <div><label data-gi=fb3e9da06db4>Fecha de baja</label><input id="hrEnd" type="date"></div>
   </div>
   <div class="row">
    <div><label data-gi=88ba39e35667>Sueldo mensual (USD)</label><input id="hrSalary" type="number" min="0" step="0.01" placeholder="0.00"></div>
    <div><label data-gi=2890d09262cb>Vacaciones al a\xF1o (d\xEDas laborables)</label><input id="hrLeaveDays" type="number" min="0" step="0.5" value="15"></div>
   </div>
   <label data-gi=f5500ac97424>Cuenta de acceso</label>
   <select id="hrAccount">
    <option value="" data-gi=1ca85c1d328a>Sin cuenta \u2014 no puede entrar en Coco ERP</option>
    ${perfiles.map(u=>`<option value="${esc(u.id)}">${esc(u.full_name||u.email||u.id)}${u.email?" \xB7 "+esc(u.email):""}</option>`).join("")}
   </select>
   <div class="muted" style="font-size:11.5px;margin-top:-2px" data-gi=3acee7e660f1>Al ligar la ficha a una cuenta, esa persona ve sus propios datos, pide sus d\xEDas y consulta el calendario del equipo. Sin cuenta, s\xF3lo la gestionas t\xFA.</div>
   <label data-gi=8ef60b6d94c0>Observaciones</label><textarea id="hrNotes" data-gi-placeholder=1dc4813dafd6 placeholder="Formaci\xF3n, idiomas, licencia de conducir\u2026"></textarea>
   <div class="actions">
    <button type="button" class="arcButton primary" id="hrSave" data-gi-live>${editing?"Guardar cambios":"Guardar empleado"}</button>
    <button type="button" class="arcButton secondary" id="hrClear" data-gi=08df229fa5ad>Limpiar</button>
   </div>
  </div>
  <div class="arcPanel card">
   <h3 data-gi=65ebd9bd0f84>Plantilla <small class="muted">(${employees.length})</small></h3>
   ${employees.length?`<div class="hrTable"><table class="arcTable">
     <thead><tr><th data-gi=6f0babb30673>Empleado</th><th data-gi=1951861239ed>Contrato</th><th data-gi=193df56cd57c>Sueldo</th><th data-gi=04c60d643e4c>Vacaciones</th><th data-gi=98e5acddb6c4>Estado</th><th></th></tr></thead>
     <tbody>${rows}</tbody></table></div>`:'<div class="hrEmpty" data-gi=bb5a96d44ddc>Todav\xEDa no hay empleados. A\xF1ade el primero con el formulario de al lado.</div>'}
  </div>
 </div>`}function absencesTab(){const vivos=employees.filter(e=>e.active!==!1),hoy=onLeaveToday(),rows=absences.map(a=>{const cls=a.status==="aprobada"?"ok":a.status==="rechazada"?"red":"warn";return`<tr>
   <td><b>${esc(employeeName(a.employee_id))}</b><small><span data-gi-live>${esc(KINDS[a.kind]||a.kind)}</span></small></td>
   <td>${day(a.start_date)} \u2192 ${day(a.end_date)}<small>${duracion(a)}</small></td>
   <td><span class="hrBadge ${cls}"><span data-gi-live>${esc(STATUS[a.status]||a.status)}</span></span>${a.decision_reason?"<small>"+esc(a.decision_reason)+"</small>":""}</td>
   <td>${esc(a.reason||"\u2014")}</td>
   <td><div class="hrActs">
    ${a.status!=="aprobada"&&a.status!=="cancelada"?`<button type="button" class="arcButton success" data-ok="${esc(a.id)}" data-gi=10a00fdf1a44>Aprobar</button>`:""}
    ${a.status!=="rechazada"&&a.status!=="cancelada"?`<button type="button" class="arcButton secondary" data-no="${esc(a.id)}" data-gi=2a0515602d31>Rechazar</button>`:""}
    ${a.status!=="cancelada"?`<button type="button" class="arcButton danger" data-del="${esc(a.id)}" data-gi-live data-gi=030a5cd7677c>Anular</button>`:""}
   </div></td></tr>`}).join("");return`<div class="hrGrid">
  <div class="arcPanel card">
   <h3 data-gi=72a86bcb4b1f>Registrar una ausencia</h3>
   <label data-gi=6020a9dd08e5>Empleado *</label>
   <select id="hrAbsEmployee">${vivos.length?vivos.map(e=>`<option value="${esc(e.id)}">${esc(e.full_name)}</option>`).join(""):'<option value="" data-gi=e918e93df678>A\xF1ade primero un empleado</option>'}</select>
   <label data-gi=c7b288b1c0bb>Motivo</label>
   <select id="hrAbsKind">${Object.keys(KINDS).map(k=>`<option value="${k}" data-gi-live>${KINDS[k]}</option>`).join("")}</select>
   <div class="row">
    <div><label data-gi=29ee9938a74c>Desde *</label><input id="hrAbsFrom" type="date" value="${today()}"></div>
    <div><label data-gi=66b3c7fb42f9>Hasta *</label><input id="hrAbsTo" type="date" value="${today()}"></div>
   </div>
   <label data-gi=98e5acddb6c4>Estado</label>
   <select id="hrAbsStatus"><option value="pendiente" data-gi=2ef68536d8e2>Pendiente</option><option value="aprobada" data-gi=80b504a3cd9c>Aprobada</option></select>
   <label data-gi=53c367898434>Comentario</label><textarea id="hrAbsReason" data-gi-placeholder=5c0130f03047 placeholder="Certificado m\xE9dico, asunto propio\u2026"></textarea>
   <div class="actions"><button type="button" class="arcButton primary" id="hrAbsAdd" data-gi=18f8ecb30787>Registrar ausencia</button></div>
  </div>
  <div class="arcPanel card">
   <h3 data-gi=38d61a2d5404>Qui\xE9n est\xE1 fuera hoy</h3>
   ${hoy.length?hoy.map(a=>`<div class="hrBadge ok" style="margin:0 6px 6px 0">${esc(employeeName(a.employee_id))} \xB7 <span data-gi-live>${esc(KINDS[a.kind]||a.kind)}</span> hasta ${day(a.end_date)}</div>`).join(""):'<div class="muted" data-gi=bf3e32312381>Hoy no falta nadie.</div>'}
   <h3 data-gi=f43b26519010>Historial de ausencias <small class="muted">(${absences.length})</small></h3>
   ${absences.length?`<div class="hrTable"><table class="arcTable">
     <thead><tr><th data-gi=6f0babb30673>Empleado</th><th data-gi=fb5065f3c8c1>Periodo</th><th data-gi=98e5acddb6c4>Estado</th><th data-gi=53c367898434>Comentario</th><th></th></tr></thead>
     <tbody>${rows}</tbody></table></div>`:'<div class="hrEmpty" data-gi=30887522852b>Todav\xEDa no hay ausencias registradas.</div>'}
  </div>
 </div>`}const PLAN_COLORES={vacaciones:"var(--arc-accent-600)",enfermedad:"var(--arc-danger)",permiso:"var(--arc-warning)",formacion:"var(--arc-fam-sales)",otro:"var(--arc-text-muted)"};function planRango(){const base=new Date(planAnchor);if(planView==="mes")return{desde:new Date(base.getFullYear(),base.getMonth(),1),hasta:new Date(base.getFullYear(),base.getMonth()+1,0)};const desde=new Date(base);desde.setDate(desde.getDate()-(desde.getDay()+6)%7);const hasta=new Date(desde);return hasta.setDate(hasta.getDate()+6),{desde,hasta}}function planDias(desde,hasta){const out=[];for(const d=new Date(desde);d<=hasta;d.setDate(d.getDate()+1))out.push(new Date(d));return out}function planCarriles(items){const finDeCarril=[];return items.forEach(a=>{let i=finDeCarril.findIndex(fin=>fin<a._d0);i<0?(finDeCarril.push(a._d1),i=finDeCarril.length-1):finDeCarril[i]=a._d1,a._carril=i+1}),Math.max(1,finDeCarril.length)}function planTab(){const{desde,hasta}=planRango(),dias=planDias(desde,hasta),cols=dias.length,hoy=today(),desdeY=ymd(desde),hastaY=ymd(hasta),titulo=planView==="mes"?desde.toLocaleDateString(window.GamaI18n?.locale||"es-EC",{month:"long",year:"numeric"}):desde.toLocaleDateString(window.GamaI18n?.locale||"es-EC",{day:"numeric",month:"short"})+" \u2013 "+hasta.toLocaleDateString(window.GamaI18n?.locale||"es-EC",{day:"numeric",month:"short",year:"numeric"}),gente=employees.filter(e=>e.active!==!1),cabecera=dias.map(d=>{const w=d.getDay(),esHoy=ymd(d)===hoy;return`<div class="hrPlanDia${w===0||w===6?" fin":""}${esHoy?" hoy":""}">
    <small>${d.toLocaleDateString(window.GamaI18n?.locale||"es-EC",{weekday:"short"})}</small><b>${d.getDate()}</b></div>`}).join(""),fondo=dias.map((d,i)=>{const w=d.getDay(),esHoy=ymd(d)===hoy;return`<div class="hrPlanCol${w===0||w===6?" fin":""}${esHoy?" hoy":""}" style="grid-column:${i+1}"></div>`}).join(""),filas=gente.map(p=>{const suyas=absences.filter(a=>a.employee_id===p.id&&a.status!=="rechazada"&&a.start_date<=hastaY&&a.end_date>=desdeY).sort((a,b)=>a.start_date.localeCompare(b.start_date)).map(a=>Object.assign({},a,{_d0:a.start_date,_d1:a.end_date})),carriles=planCarriles(suyas),barras=suyas.map(a=>{const ini=Math.max(0,diffDays(desde,fromYmd(a.start_date))),fin=Math.min(cols-1,diffDays(desde,fromYmd(a.end_date))),cortaIzq=a.start_date<desdeY,cortaDer=a.end_date>hastaY,color=PLAN_COLORES[a.kind]||PLAN_COLORES.otro,pend=a.status==="pendiente",etiqueta=KINDS[a.kind]||a.kind,tr=s=>window.GamaI18n?.t?.(s)||s,detalle=employeeName(a.employee_id)+" \xB7 "+tr(KINDS[a.kind]||a.kind)+" \xB7 "+day(a.start_date)+" \u2192 "+day(a.end_date)+" \xB7 "+tr(STATUS[a.status]||a.status);return`<button type="button" class="arcButton hrPlanBarra${pend?" pend":""}${cortaIzq?" cortaIzq":""}${cortaDer?" cortaDer":""}"
     data-plan="${esc(a.id)}" title="${esc(detalle)}"
     style="grid-column:${ini+1}/${fin+2};grid-row:${a._carril};--c:${color}">
     <span><span data-gi-live>${esc(etiqueta)}</span>${pend?" \xB7<span data-gi-live data-gi=b66292585132>pendiente</span>":""}</span></button>`}).join("");return`<div class="hrPlanFila">
    <div class="hrPlanNombre"><b>${esc(p.full_name)}</b><small>${esc(p.position||"")}</small></div>
    <div class="hrPlanCeldas" style="--cols:${cols};grid-template-rows:repeat(${carriles},22px)">
      ${fondo}${barras||""}
    </div>
  </div>`}).join(""),leyenda=Object.keys(PLAN_COLORES).map(k=>`<span class="hrPlanLeyenda" data-gi-live><i style="background:${PLAN_COLORES[k]}"></i>${esc(KINDS[k]||k)}</span>`).join("")+'<span class="hrPlanLeyenda" data-gi-live><i class="pend"></i>Pendiente de aprobar</span>',sel=planPick&&absences.find(a=>a.id===planPick);return`<div class="arcPanel card">
  <div class="hrPlanBarraSup">
   <div class="hrPlanNav">
    <button type="button" class="arcButton secondary" id="hrPlanHoy" data-gi=55133d4e6eb6>Hoy</button>
    <button type="button" class="arcButton secondary" id="hrPlanPrev" data-gi-aria-label=266784dff37a aria-label="Periodo anterior">\u2039</button>
    <button type="button" class="arcButton secondary" id="hrPlanNext" data-gi-aria-label=acdd18b1c536 aria-label="Periodo siguiente">\u203A</button>
    <b class="hrPlanTitulo">${esc(titulo)}</b>
   </div>
   <div class="hrPlanVistas">
    <button type="button" class="arcButton ${planView==="semana"?"on":""}" data-vista="semana" data-gi=51656a29fb46>Semana</button>
    <button type="button" class="arcButton ${planView==="mes"?"on":""}" data-vista="mes" data-gi=024261f9bfba>Mes</button>
   </div>
  </div>

  ${gente.length?`<div class="hrPlanScroll"><div class="hrPlan">
    <div class="hrPlanFila hrPlanCabecera">
     <div class="hrPlanNombre" data-gi=6f0babb30673>Empleado</div>
     <div class="hrPlanCeldas hrPlanDias" style="--cols:${cols}">${cabecera}</div>
    </div>
    ${filas}
   </div></div>`:'<div class="hrEmpty" data-gi=57ce01807e78>A\xF1ade empleados en la pesta\xF1a \xABEmpleados\xBB para verlos aqu\xED.</div>'}

  <div class="hrPlanPie">${leyenda}</div>

  ${sel?`<div class="hrPlanDetalle">
    <div><b>${esc(employeeName(sel.employee_id))}</b> \xB7 <span data-gi-live>${esc(KINDS[sel.kind]||sel.kind)}</span>
      <small>${day(sel.start_date)} \u2192 ${day(sel.end_date)} \xB7 ${duracion(sel)}</small>
      ${sel.reason?`<small>${esc(sel.reason)}</small>`:""}</div>
    <div class="hrActs">
      ${isAdmin()&&sel.status!=="aprobada"?`<button type="button" class="arcButton success" data-ok="${esc(sel.id)}" data-gi=10a00fdf1a44>Aprobar</button>`:""}
      ${isAdmin()&&sel.status!=="rechazada"?`<button type="button" class="arcButton secondary" data-no="${esc(sel.id)}" data-gi=2a0515602d31>Rechazar</button>`:""}
      <button type="button" class="arcButton secondary" id="hrPlanCerrar" data-gi=aeccae342e4b>Cerrar</button>
    </div>
   </div>`:""}
 </div>`}function planMover(n){const d=new Date(planAnchor);planView==="mes"?planAnchor=new Date(d.getFullYear(),d.getMonth()+n,1):(d.setDate(d.getDate()+7*n),planAnchor=d)}function myCardTab(){const yo=mine;if(!yo)return`<div class="arcPanel card"><div class="hrEmpty" data-gi=3bce45fcf14e>Tu cuenta todav\xEDa no est\xE1 ligada a una ficha de empleado.<br><span data-gi=b09ad5d3000c>
   P\xEDdele a un administrador que la enlace desde Recursos humanos \u2192 Empleados.</span></div></div>`;const year=new Date().getFullYear(),total=window.GamaHRP1?window.GamaHRP1.entitlement(yo.id,year):Number(yo.annual_leave_days||0),used=usedLeave(yo.id,year),quedan=Math.max(0,total-used),pct=total>0?Math.min(100,Math.round(used/total*100)):0,dato=(k,v)=>v?`<div class="hrDato"><span>${esc(k)}</span><b>${esc(v)}</b></div>`:"";return`<div class="hrGrid">
  <div class="arcPanel card">
   <h3 data-gi=b1c44421d26c>Mi ficha</h3>
   <div class="hrDatos">
    ${dato("Nombre",yo.full_name)}
    ${dato("Puesto",yo.position)}
    ${dato("Departamento",yo.department)}
    ${dato("Tipo de contrato",yo.contract_type)}
    ${yo.salary==null?"":dato("Sueldo mensual",money(yo.salary))}
    ${yo.hire_date?dato("Fecha de alta",day(yo.hire_date)):""}
    ${dato("C\xE9dula / RUC",yo.identification)}
    ${dato("Correo",yo.email)}
    ${dato("Tel\xE9fono",yo.phone)}
   </div>
   <div class="muted" style="font-size:11.5px;margin-top:12px" data-gi=f4655fc1977c>Si alg\xFAn dato no es correcto, avisa a un administrador: la ficha la mantiene recursos humanos.</div>
  </div>
  <div class="arcPanel card">
   <h3>Mis vacaciones ${year}</h3>
   <div class="hrSaldo">
    <div><span data-gi-live data-gi=54021b97e1a0>Derecho adquirido</span><b>${total}</b></div>
    <div><span data-gi=77c1b82cb1d7>Usados</span><b>${used}</b></div>
    <div class="hrSaldoLibre"><span data-gi=8fca1d80df6e>Te quedan</span><b>${quedan}</b></div>
   </div>
   <div class="hrBar" style="max-width:none"><i class="${pct>=100?"full":""}" style="width:${pct}%"></i></div>
   <div class="muted" style="font-size:11.5px;margin-top:8px" data-gi-live data-gi=2760b037a40d>El saldo considera el horario, los festivos y las vacaciones aprobadas.</div>
  </div>
 </div>`}function myRequestsTab(){const yo=mine,mias=yo?absences.filter(a=>a.employee_id===yo.id):[],filas=mias.map(a=>{const cls=a.status==="aprobada"?"ok":a.status==="rechazada"?"red":"warn";return`<tr>
   <td><b><span data-gi-live>${esc(KINDS[a.kind]||a.kind)}</span></b><small>${esc(a.reason||"")}</small></td>
   <td>${day(a.start_date)} \u2192 ${day(a.end_date)}<small>${duracion(a)}</small></td>
   <td><span class="hrBadge ${cls}"><span data-gi-live>${esc(STATUS[a.status]||a.status)}</span></span>${a.decision_reason?"<small>"+esc(a.decision_reason)+"</small>":""}</td>
   <td>${a.status==="pendiente"?`<button type="button" class="arcButton danger" data-del="${esc(a.id)}" data-gi=0eeac7f5e703>Retirar</button>`:""}</td>
  </tr>`}).join("");return`<div class="hrGrid">
  <div class="arcPanel card">
   <h3 data-gi=1fc7c7b3584e>Pedir d\xEDas</h3>
   ${yo?"":'<div class="hrEmpty" data-gi=26d051bd4f8d>Tu cuenta no est\xE1 ligada a una ficha de empleado, as\xED que todav\xEDa no puedes pedir d\xEDas.</div>'}
   ${yo?`<label data-gi=c7b288b1c0bb>Motivo</label>
   <select id="hrAbsKind">${Object.keys(KINDS).map(k=>`<option value="${k}" data-gi-live>${KINDS[k]}</option>`).join("")}</select>
   <div class="row">
    <div><label data-gi=29ee9938a74c>Desde *</label><input id="hrAbsFrom" type="date" value="${today()}"></div>
    <div><label data-gi=66b3c7fb42f9>Hasta *</label><input id="hrAbsTo" type="date" value="${today()}"></div>
   </div>
   <label data-gi=53c367898434>Comentario</label><textarea id="hrAbsReason" data-gi-placeholder=afe18510d3eb placeholder="Motivo o detalle para quien lo apruebe\u2026"></textarea>
   <div class="actions"><button type="button" class="arcButton primary" id="hrAbsAdd" data-gi=c9bb5c644aeb>Enviar solicitud</button></div>
   <div class="muted" style="font-size:11.5px;margin-top:8px" data-gi-live data-gi=66bbbee747ed>La solicitud queda pendiente hasta que RH o tu responsable la apruebe. Puedes retirarla mientras est\xE9 pendiente.</div>`:""}
  </div>
  <div class="arcPanel card">
   <h3 data-gi=12bc372ef7e7>Mis solicitudes <small class="muted">(${mias.length})</small></h3>
   ${mias.length?`<div class="hrTable"><table class="arcTable">
     <thead><tr><th data-gi=c7b288b1c0bb>Motivo</th><th data-gi=fb5065f3c8c1>Periodo</th><th data-gi=98e5acddb6c4>Estado</th><th></th></tr></thead>
     <tbody>${filas}</tbody></table></div>`:'<div class="hrEmpty" data-gi=52e9de7ee71f>Todav\xEDa no has pedido ning\xFAn d\xEDa.</div>'}
  </div>
 </div>`}function render(){const s=section(),admin=isAdmin();tab==="misDias"&&(tab="ausencias"),tab==="tiempo"&&(tab=admin?"empleados":"miFicha"),!admin&&tab==="empleados"&&(tab="miFicha");const pestanas=admin?[["empleados","Empleados"],["ausencias","Ausencias"],["planificacion","Planificaci\xF3n"]]:[["miFicha","Mi ficha"],["ausencias","Ausencias"],["planificacion","Planificaci\xF3n"]];window.GamaHRP1&&pestanas.push(...window.GamaHRP1.tabs()),window.ArcUI.render(s,window.GamaUI.header({title:"Recursos humanos",lead:admin?"Empleados, ausencias y calendario del equipo.":"Tus datos, tus d\xEDas y el calendario del equipo."})+`<div class="hrTabs">${pestanas.map(([id,txt])=>`<button type="button" class="arcButton ${tab===id?"on":""}" data-tab="${id}">${txt}</button>`).join("")}</div>`+(admin?kpis():"")+'<div id="hrMsg" class="hrMsg"></div>'+(tab==="empleados"?employeesTab():tab==="ausencias"?admin?absencesTab():myRequestsTab():tab==="miFicha"?myCardTab():tab==="planificacion"?planTab():window.GamaHRP1?.render(tab)||"")),window.GamaHRP1?.decorate(),bind(),window.GamaHRP1?.bind(tab,load)}function paintEmployeePhoto(){const photos=window.GamaEmployeePhotos;if(!photos)return;photos.paint($("hrPhotoPreview"),$("hrName")?.value||"",employeePhoto);const remove=$("hrPhotoRemove");remove&&(remove.disabled=!employeePhoto||photoBusy);const save=$("hrSave");save&&(save.disabled=photoBusy),document.querySelectorAll("[data-employee-avatar]").forEach(el=>{const person=employees.find(p=>p.id===el.dataset.employeeAvatar);person&&photos.paint(el,person.full_name,person.photo_data)})}async function selectEmployeePhoto(){const file=$("hrPhoto")?.files?.[0];if(!file)return;const version=++photoVersion;photoBusy=!0,paintEmployeePhoto();try{const value=await window.GamaEmployeePhotos.compress(file);if(version!==photoVersion)return;employeePhoto=value,photoChanged=!0,msg("")}catch(e){version===photoVersion&&msg(e.message,!0)}finally{version===photoVersion&&(photoBusy=!1,paintEmployeePhoto())}}function bind(){const s=section();window.GamaUI.bindBack(s),s.querySelectorAll("[data-tab]").forEach(b=>b.onclick=()=>{tab=b.dataset.tab,planPick=null,render()});const save=$("hrSave");save&&(save.onclick=saveEmployee);const photoInput=$("hrPhoto");photoInput&&(photoInput.onchange=selectEmployeePhoto);const photoRemove=$("hrPhotoRemove");photoRemove&&(photoRemove.onclick=()=>{photoVersion++,photoBusy=!1,employeePhoto="",photoChanged=!0,photoInput&&(photoInput.value=""),paintEmployeePhoto()}),$("hrName")?.addEventListener("input",paintEmployeePhoto),paintEmployeePhoto();const clr=$("hrClear");clr&&(clr.onclick=()=>{clearEmployee(),render()});const add=$("hrAbsAdd");add&&(add.onclick=addAbsence),s.querySelectorAll("[data-edit]").forEach(b=>b.onclick=()=>editEmployee(b.dataset.edit)),s.querySelectorAll("[data-arch]").forEach(b=>b.onclick=()=>archiveEmployee(b.dataset.arch,b.dataset.on==="1")),s.querySelectorAll("[data-ok]").forEach(b=>b.onclick=()=>setAbsenceStatus(b.dataset.ok,"aprobada")),s.querySelectorAll("[data-no]").forEach(b=>b.onclick=()=>setAbsenceStatus(b.dataset.no,"rechazada")),s.querySelectorAll("[data-del]").forEach(b=>b.onclick=()=>removeAbsence(b.dataset.del)),s.querySelectorAll("[data-vista]").forEach(b=>b.onclick=()=>{planView=b.dataset.vista,render()});const hoyBtn=$("hrPlanHoy");hoyBtn&&(hoyBtn.onclick=()=>{planAnchor=new Date,render()});const prev=$("hrPlanPrev");prev&&(prev.onclick=()=>{planMover(-1),render()});const next=$("hrPlanNext");next&&(next.onclick=()=>{planMover(1),render()}),s.querySelectorAll("[data-plan]").forEach(b=>b.onclick=()=>{planPick=planPick===b.dataset.plan?null:b.dataset.plan,render()});const cerrar=$("hrPlanCerrar");cerrar&&(cerrar.onclick=()=>{planPick=null,render()})}function open(requestedTab){typeof requestedTab=="string"&&(tab=requestedTab),section().innerHTML||render(),window.ArcRouter.show("hr"),document.querySelectorAll(".tab").forEach(t=>t.classList.remove("active")),window.scrollTo({top:0,behavior:"smooth"}),load()}window.addEventListener("gama:auth-change",ev=>{const nextUid=ev.detail?.session?.user?.id||null;ev.detail?.event!=="SIGNED_OUT"&&(!myUid||nextUid===myUid)||(loadVersion++,photoVersion++,employeePhoto="",photoChanged=!1,photoBusy=!1,employees=[],absences=[],mine=null,perfiles=[],myUid=null,editing=null,tab="empleados",$("hr")&&window.ArcUI.render($("hr"),""))}),window.GamaHR={open,load},window.GamaOpenHR=open})();
