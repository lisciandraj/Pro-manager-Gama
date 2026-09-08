/* GAMA — Recursos humanos: fichas de empleado y ausencias.

   Dos pestañas porque son dos cosas distintas: la plantilla, que cambia poco, y
   las ausencias, que se registran a diario.

   Sobre los días: la base guarda en hr_absences.days los días NATURALES del
   periodo (una columna generada, fin - inicio + 1). El saldo de vacaciones, en
   cambio, se cuenta en días LABORABLES, que es como se pactan los contratos.
   Son cifras distintas y mezclarlas daría un saldo equivocado, así que la
   lista enseña los naturales y el saldo se calcula aparte, aquí. */
(function(){
'use strict';
if(window.GamaHR)return;

const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const day=v=>{if(!v)return '—';try{return new Date(v+'T12:00:00').toLocaleDateString('es-EC')}catch(e){return String(v)}};
const today=()=>new Date().toISOString().slice(0,10);

const KINDS={vacaciones:'🏖️ Vacaciones',enfermedad:'🤒 Enfermedad',permiso:'📄 Permiso',formacion:'🎓 Formación',otro:'• Otro'};
const STATUS={pendiente:'Pendiente',aprobada:'Aprobada',rechazada:'Rechazada'};

let employees=[],absences=[],tab='empleados',editing=null,busy=false;

function msg(t,err){const m=$('hrMsg');if(!m)return;m.textContent=t||'';m.className='hrMsg'+(t?(err?' hrErr':' hrOk'):'')}
function fail(e,what){console.warn('[GAMA RRHH]',what,e);msg(what+': '+(e&&(e.message||e.details)||e),true)}

/* Días laborables (lunes a viernes) entre dos fechas, ambas incluidas. No
   descuenta festivos: eso pediría un calendario por país que aquí no existe, y
   más vale una cifra que se entiende que una que aparenta una precisión falsa. */
function workingDays(from,to){
 if(!from||!to)return 0;
 const a=new Date(from+'T12:00:00'),b=new Date(to+'T12:00:00');
 if(isNaN(a)||isNaN(b)||b<a)return 0;
 let n=0;
 for(const d=new Date(a);d<=b;d.setDate(d.getDate()+1)){const w=d.getDay();if(w!==0&&w!==6)n++}
 return n;
}
/* Vacaciones aprobadas que consumen saldo del año en curso. */
function usedLeave(employeeId,year){
 return absences
  .filter(a=>a.employee_id===employeeId&&a.kind==='vacaciones'&&a.status==='aprobada'&&String(a.start_date||'').slice(0,4)===String(year))
  .reduce((sum,a)=>sum+workingDays(a.start_date,a.end_date),0);
}
function employeeName(id){return (employees.find(e=>e.id===id)||{}).full_name||'Empleado'}
/* Una ausencia está en curso si hoy cae dentro de su periodo y está aprobada. */
function onLeaveToday(){
 const t=today();
 return absences.filter(a=>a.status==='aprobada'&&a.start_date<=t&&a.end_date>=t);
}

async function load(){
 const api=C();
 if(!api){msg('La conexión con la nube de GAMA no está disponible.',true);return}
 try{
  const [e,a]=await Promise.all([
   api.list('hr_employees',{order:'full_name',ascending:true}),
   api.list('hr_absences',{order:'start_date',ascending:false}),
  ]);
  if(e.error)throw e.error;
  if(a.error)throw a.error;
  employees=e.data||[];absences=a.data||[];
  render();
 }catch(err){fail(err,'No se pudieron cargar los datos de RRHH')}
}

/* ---- empleados ---- */
const FIELDS=['hrName','hrId','hrEmail','hrPhone','hrPosition','hrDept','hrContract','hrHire','hrEnd','hrSalary','hrLeaveDays','hrNotes'];
function clearEmployee(){editing=null;FIELDS.forEach(id=>{const el=$(id);if(el)el.value=id==='hrLeaveDays'?'15':''});const b=$('hrSave');if(b)b.textContent='＋ Guardar empleado';msg('')}

async function saveEmployee(){
 if(busy)return;
 const name=($('hrName').value||'').trim();
 if(!name)return msg('El nombre del empleado es obligatorio.',true);
 const num=v=>{const n=parseFloat(String(v).replace(',','.'));return Number.isFinite(n)?n:null};
 const row={
  full_name:name,
  identification:($('hrId').value||'').trim()||null,
  email:($('hrEmail').value||'').trim()||null,
  phone:($('hrPhone').value||'').trim()||null,
  position:($('hrPosition').value||'').trim()||null,
  department:($('hrDept').value||'').trim()||null,
  contract_type:$('hrContract').value||null,
  hire_date:$('hrHire').value||null,
  end_date:$('hrEnd').value||null,
  salary:num($('hrSalary').value),
  annual_leave_days:num($('hrLeaveDays').value)??15,
 };
 const notes=($('hrNotes').value||'').trim();row.notes=notes||null;
 busy=true;
 try{
  const r=editing?await C().update('hr_employees',editing,row):await C().insert('hr_employees',row);
  if(r.error)throw r.error;
  clearEmployee();msg(editing?'Ficha actualizada.':'Empleado añadido.');
  await load();
 }catch(e){fail(e,'No se pudo guardar el empleado')}
 finally{busy=false}
}
/* Primero se repinta —el formulario cambia de título y de botón al pasar a modo
   edición— y sólo después se rellenan los campos: al revés, el repintado los
   dejaría otra vez en blanco. */
function editEmployee(id){
 const p=employees.find(x=>x.id===id);if(!p)return;
 editing=id;tab='empleados';render();
 const set=(el,v)=>{const n=$(el);if(n)n.value=v};
 set('hrName',p.full_name||'');set('hrId',p.identification||'');
 set('hrEmail',p.email||'');set('hrPhone',p.phone||'');
 set('hrPosition',p.position||'');set('hrDept',p.department||'');
 set('hrContract',p.contract_type||'');
 set('hrHire',p.hire_date||'');set('hrEnd',p.end_date||'');
 set('hrSalary',p.salary??'');set('hrLeaveDays',p.annual_leave_days??15);
 set('hrNotes',p.notes||'');
 msg('Editando la ficha de '+p.full_name+'.');
 $('hrName')?.scrollIntoView({behavior:'smooth',block:'center'});
}
/* Se archiva, no se borra: las ausencias registradas son historial laboral y
   deben seguir explicándose por su ficha. */
async function archiveEmployee(id,on){
 try{
  const r=await C().update('hr_employees',id,{active:!!on});
  if(r.error)throw r.error;
  await load();
 }catch(e){fail(e,'No se pudo cambiar el estado del empleado')}
}

/* ---- ausencias ---- */
async function addAbsence(){
 if(busy)return;
 const employee_id=$('hrAbsEmployee').value;
 const start_date=$('hrAbsFrom').value,end_date=$('hrAbsTo').value;
 if(!employee_id)return msg('Elige un empleado.',true);
 if(!start_date||!end_date)return msg('Indica la fecha de inicio y la de fin.',true);
 if(end_date<start_date)return msg('La fecha de fin no puede ser anterior a la de inicio.',true);
 busy=true;
 try{
  const r=await C().insert('hr_absences',{
   employee_id,kind:$('hrAbsKind').value,start_date,end_date,
   status:$('hrAbsStatus').value,
   reason:($('hrAbsReason').value||'').trim()||null});
  if(r.error)throw r.error;
  $('hrAbsFrom').value='';$('hrAbsTo').value='';$('hrAbsReason').value='';
  msg('Ausencia registrada.');
  await load();
 }catch(e){fail(e,'No se pudo registrar la ausencia')}
 finally{busy=false}
}
async function setAbsenceStatus(id,status){
 try{
  const r=await C().update('hr_absences',id,{status});
  if(r.error)throw r.error;
  await load();
 }catch(e){fail(e,'No se pudo cambiar el estado de la ausencia')}
}
async function removeAbsence(id){
 const a=absences.find(x=>x.id===id);
 if(!confirm('¿Borrar esta ausencia de '+employeeName(a&&a.employee_id)+'?\n\nEsta acción no se puede deshacer.'))return;
 try{
  const r=await C().remove('hr_absences',id);
  if(r.error)throw r.error;
  await load();
 }catch(e){fail(e,'No se pudo borrar la ausencia')}
}

/* ---- pantalla ---- */
function section(){
 let s=$('hr');
 if(!s){s=document.createElement('section');s.id='hr';(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
function css(){
 if($('hrCss'))return;
 const s=document.createElement('style');s.id='hrCss';
 s.textContent=`#hr{display:none}
#hr .hrTabs{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:14px}
#hr .hrTabs button{background:#fff;border:1px solid #c9d6df;color:#18324a;border-radius:999px;padding:10px 16px;font-weight:800;cursor:pointer;width:auto}
#hr .hrTabs button.on{background:#087c8b;border-color:#087c8b;color:#fff}
#hr .hrKpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:14px}
#hr .hrKpi{background:#fff;border:1px solid #e2e8ec;border-radius:13px;padding:14px}
#hr .hrKpi span{display:block;color:#71808a;font-size:11px;font-weight:700}
#hr .hrKpi b{display:block;margin-top:6px;font-size:22px;color:#18324a}
#hr .hrGrid{display:grid;grid-template-columns:minmax(0,.85fr) minmax(0,1.15fr);gap:12px;align-items:start}
#hr .hrTable{width:100%;overflow:auto}
#hr .hrTable table{width:100%;border-collapse:collapse;min-width:560px}
#hr .hrTable th,#hr .hrTable td{padding:10px;border-bottom:1px solid #edf1f2;text-align:left;font-size:12px;vertical-align:top}
#hr .hrTable th{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:#71808a;background:#f8fafb}
#hr .hrTable small{display:block;color:#81909a}
#hr .hrBadge{display:inline-block;border-radius:999px;padding:4px 9px;font-size:10px;font-weight:800;background:#eef3f4;color:#60717b;white-space:nowrap}
#hr .hrBadge.ok{background:#e7f6f0;color:#138a69}
#hr .hrBadge.warn{background:#fff6e8;color:#b66a18}
#hr .hrBadge.red{background:#fff0ec;color:#c94f45}
#hr .hrBar{height:7px;border-radius:999px;background:#eef3f4;overflow:hidden;margin-top:5px;max-width:150px}
#hr .hrBar i{display:block;height:100%;background:#087c8b}
#hr .hrBar i.full{background:#c94f45}
#hr .hrMsg{margin:10px 0;font-size:13px}
#hr .hrMsg.hrOk{color:#138a69}#hr .hrMsg.hrErr{color:#c94f45;font-weight:700}
#hr .hrEmpty{padding:22px;text-align:center;color:#81909a}
#hr .hrActs{display:flex;gap:6px;flex-wrap:wrap}
#hr .hrActs button{padding:6px 9px;font-size:11px;width:auto}
#hr .hrOff td{opacity:.55}
@media(max-width:900px){#hr .hrGrid{grid-template-columns:1fr}#hr .hrKpis{grid-template-columns:1fr 1fr}}`;
 document.head.appendChild(s);
}

function kpis(){
 const activos=employees.filter(e=>e.active!==false).length;
 const fuera=onLeaveToday().length;
 const pend=absences.filter(a=>a.status==='pendiente').length;
 const year=new Date().getFullYear();
 const enfermos=absences.filter(a=>a.kind==='enfermedad'&&String(a.start_date||'').slice(0,4)===String(year)).length;
 return `<div class="hrKpis">
  <div class="hrKpi"><span>Empleados activos</span><b>${activos}</b></div>
  <div class="hrKpi"><span>Ausentes hoy</span><b>${fuera}</b></div>
  <div class="hrKpi"><span>Pendientes de aprobar</span><b>${pend}</b></div>
  <div class="hrKpi"><span>Bajas por enfermedad ${year}</span><b>${enfermos}</b></div>
 </div>`;
}

function employeesTab(){
 const year=new Date().getFullYear();
 const rows=employees.map(p=>{
  const total=Number(p.annual_leave_days||0);
  const used=usedLeave(p.id,year);
  const pct=total>0?Math.min(100,Math.round(used/total*100)):0;
  const off=p.active===false;
  return `<tr class="${off?'hrOff':''}">
   <td><b>${esc(p.full_name)}</b><small>${esc(p.position||'Sin puesto')}${p.department?' · '+esc(p.department):''}</small>
       <small>${esc(p.identification||'')}</small></td>
   <td>${esc(p.contract_type||'—')}<small>Alta: ${day(p.hire_date)}</small>${p.end_date?`<small>Baja: ${day(p.end_date)}</small>`:''}</td>
   <td>${p.salary==null?'—':money(p.salary)}</td>
   <td>${used} / ${total}<small>días laborables ${year}</small>
       <div class="hrBar"><i class="${pct>=100?'full':''}" style="width:${pct}%"></i></div></td>
   <td>${off?'<span class="hrBadge">Archivado</span>':'<span class="hrBadge ok">Activo</span>'}</td>
   <td><div class="hrActs">
    <button type="button" class="secondary" data-edit="${esc(p.id)}">✏️ Editar</button>
    <button type="button" class="${off?'secondary':'danger'}" data-arch="${esc(p.id)}" data-on="${off?'1':'0'}">${off?'♻️ Restaurar':'🗄️ Archivar'}</button>
   </div></td></tr>`;
 }).join('');

 return `<div class="hrGrid">
  <div class="card">
   <h3>${editing?'Editar empleado':'Nuevo empleado'}</h3>
   <label>Nombre y apellidos *</label><input id="hrName" placeholder="Ej. María Pérez">
   <div class="row">
    <div><label>Cédula / RUC</label><input id="hrId" placeholder="0912345678"></div>
    <div><label>Teléfono</label><input id="hrPhone" type="tel" placeholder="+593…"></div>
   </div>
   <label>Correo electrónico</label><input id="hrEmail" type="email" placeholder="correo@ejemplo.com">
   <div class="row">
    <div><label>Puesto</label><input id="hrPosition" placeholder="Ej. Almacenero"></div>
    <div><label>Departamento</label><input id="hrDept" placeholder="Ej. Bodega"></div>
   </div>
   <label>Tipo de contrato</label>
   <select id="hrContract">
    <option value="">Sin especificar</option>
    <option>Indefinido</option><option>Plazo fijo</option><option>Eventual</option>
    <option>Prueba</option><option>Prestación de servicios</option><option>Pasantía</option>
   </select>
   <div class="row">
    <div><label>Fecha de alta</label><input id="hrHire" type="date"></div>
    <div><label>Fecha de baja</label><input id="hrEnd" type="date"></div>
   </div>
   <div class="row">
    <div><label>Sueldo mensual (USD)</label><input id="hrSalary" type="number" min="0" step="0.01" placeholder="0.00"></div>
    <div><label>Vacaciones al año (días laborables)</label><input id="hrLeaveDays" type="number" min="0" step="0.5" value="15"></div>
   </div>
   <label>Observaciones</label><textarea id="hrNotes" placeholder="Formación, idiomas, licencia de conducir…"></textarea>
   <div class="actions">
    <button type="button" class="primary" id="hrSave">${editing?'💾 Guardar cambios':'＋ Guardar empleado'}</button>
    <button type="button" class="secondary" id="hrClear">↺ Limpiar</button>
   </div>
  </div>
  <div class="card">
   <h3>Plantilla <small class="muted">(${employees.length})</small></h3>
   ${employees.length?`<div class="hrTable"><table>
     <thead><tr><th>Empleado</th><th>Contrato</th><th>Sueldo</th><th>Vacaciones</th><th>Estado</th><th></th></tr></thead>
     <tbody>${rows}</tbody></table></div>`
    :'<div class="hrEmpty">Todavía no hay empleados. Añade el primero con el formulario de al lado.</div>'}
  </div>
 </div>`;
}

function absencesTab(){
 const vivos=employees.filter(e=>e.active!==false);
 const hoy=onLeaveToday();
 const rows=absences.map(a=>{
  const cls=a.status==='aprobada'?'ok':a.status==='rechazada'?'red':'warn';
  return `<tr>
   <td><b>${esc(employeeName(a.employee_id))}</b><small>${esc(KINDS[a.kind]||a.kind)}</small></td>
   <td>${day(a.start_date)} → ${day(a.end_date)}<small>${a.days} día${a.days>1?'s':''} naturales${a.kind==='vacaciones'?' · '+workingDays(a.start_date,a.end_date)+' laborables':''}</small></td>
   <td><span class="hrBadge ${cls}">${esc(STATUS[a.status]||a.status)}</span></td>
   <td>${esc(a.reason||'—')}</td>
   <td><div class="hrActs">
    ${a.status!=='aprobada'?`<button type="button" class="success" data-ok="${esc(a.id)}">✓ Aprobar</button>`:''}
    ${a.status!=='rechazada'?`<button type="button" class="secondary" data-no="${esc(a.id)}">✕ Rechazar</button>`:''}
    <button type="button" class="danger" data-del="${esc(a.id)}">🗑️</button>
   </div></td></tr>`;
 }).join('');

 return `<div class="hrGrid">
  <div class="card">
   <h3>Registrar una ausencia</h3>
   <label>Empleado *</label>
   <select id="hrAbsEmployee">${vivos.length?vivos.map(e=>`<option value="${esc(e.id)}">${esc(e.full_name)}</option>`).join(''):'<option value="">Añade primero un empleado</option>'}</select>
   <label>Motivo</label>
   <select id="hrAbsKind">${Object.keys(KINDS).map(k=>`<option value="${k}">${KINDS[k]}</option>`).join('')}</select>
   <div class="row">
    <div><label>Desde *</label><input id="hrAbsFrom" type="date" value="${today()}"></div>
    <div><label>Hasta *</label><input id="hrAbsTo" type="date" value="${today()}"></div>
   </div>
   <label>Estado</label>
   <select id="hrAbsStatus"><option value="pendiente">Pendiente</option><option value="aprobada">Aprobada</option></select>
   <label>Comentario</label><textarea id="hrAbsReason" placeholder="Certificado médico, asunto propio…"></textarea>
   <div class="actions"><button type="button" class="primary" id="hrAbsAdd">＋ Registrar ausencia</button></div>
  </div>
  <div class="card">
   <h3>Quién está fuera hoy</h3>
   ${hoy.length?hoy.map(a=>`<div class="hrBadge ok" style="margin:0 6px 6px 0">${esc(employeeName(a.employee_id))} · ${esc(KINDS[a.kind]||a.kind)} hasta ${day(a.end_date)}</div>`).join('')
    :'<div class="muted">Hoy no falta nadie.</div>'}
   <h3>Historial de ausencias <small class="muted">(${absences.length})</small></h3>
   ${absences.length?`<div class="hrTable"><table>
     <thead><tr><th>Empleado</th><th>Periodo</th><th>Estado</th><th>Comentario</th><th></th></tr></thead>
     <tbody>${rows}</tbody></table></div>`
    :'<div class="hrEmpty">Todavía no hay ausencias registradas.</div>'}
  </div>
 </div>`;
}

function render(){
 css();
 const s=section();
 s.innerHTML=window.GamaUI.header({
   title:'🧑‍💼 Recursos humanos',
   lead:'La ficha de cada empleado —puesto, contrato, sueldo y vacaciones pactadas— y el registro de sus ausencias: vacaciones, bajas por enfermedad, permisos y formación. El saldo de vacaciones de cada persona se descuenta solo a medida que apruebas sus días.',
   actions:'<button type="button" class="gamaStdAction" id="hrRefresh">↻ Actualizar</button>'
 })
 +`<div class="hrTabs">
   <button type="button" class="${tab==='empleados'?'on':''}" data-tab="empleados">👥 Empleados</button>
   <button type="button" class="${tab==='ausencias'?'on':''}" data-tab="ausencias">📅 Ausencias</button>
  </div>`
 +kpis()
 +'<div id="hrMsg" class="hrMsg"></div>'
 +(tab==='empleados'?employeesTab():absencesTab());
 bind();
}

function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
 const r=$('hrRefresh');if(r)r.onclick=load;
 s.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;render()});
 const save=$('hrSave');if(save)save.onclick=saveEmployee;
 const clr=$('hrClear');if(clr)clr.onclick=()=>{clearEmployee();render()};
 const add=$('hrAbsAdd');if(add)add.onclick=addAbsence;
 s.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editEmployee(b.dataset.edit));
 s.querySelectorAll('[data-arch]').forEach(b=>b.onclick=()=>archiveEmployee(b.dataset.arch,b.dataset.on==='1'));
 s.querySelectorAll('[data-ok]').forEach(b=>b.onclick=()=>setAbsenceStatus(b.dataset.ok,'aprobada'));
 s.querySelectorAll('[data-no]').forEach(b=>b.onclick=()=>setAbsenceStatus(b.dataset.no,'rechazada'));
 s.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>removeAbsence(b.dataset.del));
}

function open(){
 css();
 const s=section();
 if(!s.innerHTML)render();
 document.querySelectorAll('section').forEach(x=>{
  const on=x.id==='hr';
  x.classList.toggle('active',on);
  x.style.setProperty('display',on?'block':'none','important');
  if(on)x.removeAttribute('hidden');
 });
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
 load();
}

window.GamaHR={open,load};
window.GamaOpenHR=open;
})();
