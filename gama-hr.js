/* GAMA — Recursos humanos: fichas de empleado, ausencias y planificación.

   Tres pestañas porque son tres cosas distintas: la plantilla, que cambia poco;
   las ausencias, que se registran a diario; y la planificación, que es la misma
   información puesta en un calendario — una fila por empleado y una columna por
   día— para ver de un vistazo quién falta y cuándo se solapan dos personas, que
   es justo lo que no se puede leer en una lista ordenada por fecha.

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
/* «ausencia» no es un motivo que se pueda elegir: es lo que la vista compartida
   devuelve en lugar de «enfermedad» cuando quien mira es un compañero. Al
   equipo le basta con saber que ese día no está. */
const KIND_LABEL=Object.assign({ausencia:'🚫 Ausente'},KINDS);
const STATUS={pendiente:'Pendiente',aprobada:'Aprobada',rechazada:'Rechazada'};

let employees=[],absences=[],tab='empleados',editing=null,busy=false;
/* El calendario del equipo llega por dos vistas que enseñan MENOS columnas que
   las tablas: ni sueldos ni motivos escritos a mano. Las usan los dos perfiles
   —al administrador le dan lo mismo que la tabla— para que la planificación se
   dibuje con un solo camino. */
let directory=[],calendar=[],mine=null,perfiles=[];

const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(e){return ''}};
const isAdmin=()=>role()==='admin'||role()==='administrador';
/* Planificación: el día sobre el que se centra la vista y su amplitud. */
let planAnchor=new Date(),planView='semana',planPick=null;

/* Las fechas se manejan con las partes locales, nunca con toISOString(): al
   este de Greenwich un new Date('2026-09-07') se convierte en el día anterior
   por la noche, y una ausencia aparecería corrida un día en la rejilla. */
function ymd(d){const p=n=>String(n).padStart(2,'0');return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())}
function fromYmd(s){const [y,m,d]=String(s||'').split('-').map(Number);return new Date(y,(m||1)-1,d||1)}
const DIA_MS=86400000;
function diffDays(a,b){return Math.round((fromYmd(ymd(b))-fromYmd(ymd(a)))/DIA_MS)}

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
function employeeName(id){return (directory.find(e=>e.id===id)||employees.find(e=>e.id===id)||{}).full_name||'Empleado'}
/* Una ausencia está en curso si hoy cae dentro de su periodo y está aprobada. */
function onLeaveToday(){
 const t=today();
 return absences.filter(a=>a.status==='aprobada'&&a.start_date<=t&&a.end_date>=t);
}

/* Una sola consulta por tabla para los dos perfiles: lo que cambia no es la
   consulta sino lo que la base devuelve. Un empleado pide hr_employees y le
   llega SU ficha; el administrador pide lo mismo y le llegan todas. La
   diferencia la pone RLS, no este archivo — así no hay una rama del código que
   se pueda saltar desde la consola del navegador. */
async function load(){
 const api=C();
 if(!api){msg('La conexión con la nube de GAMA no está disponible.',true);return}
 try{
  const [e,a,d,c]=await Promise.all([
   api.list('hr_employees',{order:'full_name',ascending:true}),
   api.list('hr_absences',{order:'start_date',ascending:false}),
   api.list('hr_directory',{order:'full_name',ascending:true}),
   api.list('hr_calendar',{order:'start_date',ascending:false}),
  ]);
  if(e.error)throw e.error;
  if(a.error)throw a.error;
  employees=e.data||[];absences=a.data||[];
  directory=d.error?[]:(d.data||[]);
  calendar=c.error?[]:(c.data||[]);
  mine=directory.find(x=>x.is_me)||(!isAdmin()&&employees.length===1?employees[0]:null);
  if(isAdmin())await loadProfiles();
  render();
 }catch(err){fail(err,'No se pudieron cargar los datos de RRHH')}
}
/* Las cuentas de acceso, para poder ligar una ficha a un usuario. Sólo el
   administrador las lee. */
async function loadProfiles(){
 try{
  const r=await C().list('profiles',{select:'id,full_name,email,role,active',order:'full_name',ascending:true});
  perfiles=r.error?[]:(r.data||[]).filter(p=>p.active!==false&&p.role!=='cliente');
 }catch(e){perfiles=[]}
}

/* ---- empleados ---- */
const FIELDS=['hrName','hrId','hrEmail','hrPhone','hrPosition','hrDept','hrContract','hrHire','hrEnd','hrSalary','hrLeaveDays','hrNotes','hrAccount'];
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
  profile_id:$('hrAccount')?.value||null,
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
 set('hrNotes',p.notes||'');set('hrAccount',p.profile_id||'');
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
/* Un empleado sólo puede pedir para sí mismo y siempre pendiente. Esto es
   comodidad de interfaz, no la barrera: la política de hr_absences rechaza en
   la base cualquier inserción con otro empleado o con un estado ya aprobado. */
async function addAbsence(){
 if(busy)return;
 const sel=$('hrAbsEmployee');
 const employee_id=sel?sel.value:(mine&&mine.id)||'';
 const start_date=$('hrAbsFrom').value,end_date=$('hrAbsTo').value;
 if(!employee_id)return msg('Elige un empleado.',true);
 if(!start_date||!end_date)return msg('Indica la fecha de inicio y la de fin.',true);
 if(end_date<start_date)return msg('La fecha de fin no puede ser anterior a la de inicio.',true);
 busy=true;
 try{
  const r=await C().insert('hr_absences',{
   employee_id,kind:$('hrAbsKind').value,start_date,end_date,
   status:isAdmin()?($('hrAbsStatus')?.value||'pendiente'):'pendiente',
   reason:($('hrAbsReason').value||'').trim()||null});
  if(r.error)throw r.error;
  $('hrAbsFrom').value='';$('hrAbsTo').value='';$('hrAbsReason').value='';
  msg(isAdmin()?'Ausencia registrada.':'Solicitud enviada. Queda pendiente de aprobación.');
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
#hr .hrDatos{display:grid;gap:1px;background:#edf1f2;border:1px solid #edf1f2;border-radius:10px;overflow:hidden}
#hr .hrDato{display:flex;justify-content:space-between;gap:12px;padding:11px 13px;background:#fff;font-size:13px}
#hr .hrDato span{color:#71808a}
#hr .hrDato b{color:#18324a;text-align:right}
#hr .hrSaldo{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:12px}
#hr .hrSaldo>div{background:#f8fafb;border:1px solid #e4ebee;border-radius:11px;padding:12px;text-align:center}
#hr .hrSaldo span{display:block;color:#71808a;font-size:11px;font-weight:700}
#hr .hrSaldo b{display:block;margin-top:5px;font-size:24px;color:#18324a}
#hr .hrSaldoLibre{background:#e8f5f6!important;border-color:#b9dde1!important}
#hr .hrSaldoLibre b{color:#087c8b}

/* ---- planificación ----
   La rejilla es una sola cuadrícula por fila: las columnas de fondo ocupan
   todos los carriles (grid-row 1/-1) y las barras se colocan encima en el
   suyo. Así el fondo, los fines de semana y el día de hoy se pintan una vez y
   las barras se superponen sin descuadrar nada. */
#hr .hrPlanBarraSup{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:14px}
#hr .hrPlanNav{display:flex;align-items:center;gap:7px;flex-wrap:wrap}
#hr .hrPlanNav button{width:auto;padding:8px 13px}
/* capitalize pondría mayúscula en cada palabra: «Septiembre De 2026». En
   español sólo la lleva la primera, y los meses abreviados van en minúscula. */
#hr .hrPlanTitulo{font-size:15px;color:#18324a;margin-left:4px}
#hr .hrPlanTitulo::first-letter{text-transform:uppercase}
#hr .hrPlanVistas{display:flex;gap:6px}
#hr .hrPlanVistas button{background:#fff;border:1px solid #c9d6df;color:#18324a;border-radius:999px;padding:8px 15px;font-weight:800;cursor:pointer;width:auto;font-size:13px}
#hr .hrPlanVistas button.on{background:#087c8b;border-color:#087c8b;color:#fff}
#hr .hrPlanScroll{overflow-x:auto;border:1px solid #e4ebee;border-radius:12px}
#hr .hrPlan{min-width:640px}
#hr .hrPlanFila{display:grid;grid-template-columns:170px 1fr;border-bottom:1px solid #edf1f2}
#hr .hrPlanFila:last-child{border-bottom:0}
#hr .hrPlanNombre{padding:9px 11px;border-right:1px solid #e4ebee;background:#fff;position:sticky;left:0;z-index:3}
#hr .hrPlanNombre b{display:block;font-size:12.5px;color:#18324a;line-height:1.25}
#hr .hrPlanNombre small{display:block;color:#81909a;font-size:10.5px;margin-top:1px}
#hr .hrPlanCabecera{background:#f8fafb;border-bottom:1px solid #e4ebee}
#hr .hrPlanCabecera .hrPlanNombre{background:#f8fafb;font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:#71808a;font-weight:800;display:flex;align-items:flex-end}
#hr .hrPlanCeldas{display:grid;grid-template-columns:repeat(var(--cols),minmax(38px,1fr));grid-auto-rows:22px;align-content:center;gap:3px 0;padding:6px 0;position:relative}
#hr .hrPlanDias{grid-auto-rows:auto;padding:7px 0}
#hr .hrPlanDia{text-align:center;font-size:11px;color:#18324a;border-right:1px solid #edf1f2}
#hr .hrPlanDia:last-child{border-right:0}
#hr .hrPlanDia small{display:block;color:#81909a;font-size:9.5px;text-transform:uppercase}
#hr .hrPlanDia b{display:block;font-size:13px}
#hr .hrPlanDia.fin{background:#f4f7f8;color:#8c99a3}
#hr .hrPlanDia.hoy{background:#fff6ef;box-shadow:inset 0 -3px 0 #f47a2a}
#hr .hrPlanCol{grid-row:1/-1;border-right:1px solid #f1f5f6}
#hr .hrPlanCol:last-of-type{border-right:0}
#hr .hrPlanCol.fin{background:#f7fafb}
#hr .hrPlanCol.hoy{background:#fff6ef}
#hr .hrPlanBarra{position:relative;z-index:2;display:flex;align-items:center;min-width:0;height:22px;margin:0 2px;padding:0 7px;border:0;border-radius:6px;cursor:pointer;background:var(--c);color:#fff;font-weight:700;font-size:10.5px;text-align:left;width:auto;overflow:hidden}
#hr .hrPlanBarra span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#hr .hrPlanBarra:hover{filter:brightness(1.08)}
#hr .hrPlanBarra:focus-visible{outline:3px solid #18324a;outline-offset:1px}
/* Pendiente de aprobar: hueca y con el borde a rayas, para que no se confunda
   con lo ya concedido de un vistazo. */
#hr .hrPlanBarra.pend{background:#fff;color:var(--c);border:1.5px dashed var(--c)}
/* Una ausencia que empieza antes o acaba después del periodo se recorta: la
   punta plana avisa de que sigue fuera de la vista. */
#hr .hrPlanBarra.cortaIzq{border-top-left-radius:0;border-bottom-left-radius:0;margin-left:0}
#hr .hrPlanBarra.cortaDer{border-top-right-radius:0;border-bottom-right-radius:0;margin-right:0}
#hr .hrPlanPie{display:flex;gap:14px;flex-wrap:wrap;margin-top:12px;font-size:11px;color:#61717c}
#hr .hrPlanLeyenda{display:inline-flex;align-items:center;gap:6px}
#hr .hrPlanLeyenda i{width:12px;height:12px;border-radius:3px;display:inline-block}
#hr .hrPlanLeyenda i.pend{background:#fff;border:1.5px dashed #71808a}
#hr .hrPlanDetalle{display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap;margin-top:14px;padding:12px 14px;border:1px solid #dbe6ea;border-left:4px solid #087c8b;border-radius:10px;background:#f8fbfb}
#hr .hrPlanDetalle small{display:block;color:#61717c;font-size:11.5px;margin-top:2px}
@media(max-width:900px){#hr .hrGrid{grid-template-columns:1fr}#hr .hrKpis{grid-template-columns:1fr 1fr}
 #hr .hrPlanFila{grid-template-columns:120px 1fr}#hr .hrPlanNombre b{font-size:11.5px}}`;
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
   <td>${off?'<span class="hrBadge">Archivado</span>':'<span class="hrBadge ok">Activo</span>'}${p.profile_id?'<br><span class="hrBadge ok" style="margin-top:4px">🔑 Con cuenta</span>':'<br><span class="hrBadge" style="margin-top:4px">Sin cuenta</span>'}</td>
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
   <label>Cuenta de acceso</label>
   <select id="hrAccount">
    <option value="">Sin cuenta — no puede entrar en GAMA</option>
    ${perfiles.map(u=>`<option value="${esc(u.id)}">${esc(u.full_name||u.email||u.id)}${u.email?' · '+esc(u.email):''}</option>`).join('')}
   </select>
   <div class="muted" style="font-size:11.5px;margin-top:-2px">Al ligar la ficha a una cuenta, esa persona ve sus propios datos, pide sus días y consulta el calendario del equipo. Sin cuenta, sólo la gestionas tú.</div>
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

/* ---- planificación ----
   Una fila por empleado y una columna por día, con las ausencias pintadas como
   barras que ocupan su periodo entero. De un vistazo se ve quién falta y
   cuándo se solapan dos personas, que es lo que no se puede leer en la lista.

   Dos ausencias de la misma persona que se pisan van en carriles distintos
   dentro de su fila; si no, la de arriba taparía a la de abajo y parecería que
   sólo hay una. */
const PLAN_COLORES={vacaciones:'#087c8b',enfermedad:'#c94f45',permiso:'#b66a18',formacion:'#5b62b5',otro:'#71808a',ausencia:'#8593a0'};

function planRango(){
 const base=new Date(planAnchor);
 if(planView==='mes'){
  return {desde:new Date(base.getFullYear(),base.getMonth(),1),
          hasta:new Date(base.getFullYear(),base.getMonth()+1,0)};
 }
 const desde=new Date(base);
 desde.setDate(desde.getDate()-((desde.getDay()+6)%7));   // la semana empieza el lunes
 const hasta=new Date(desde);hasta.setDate(hasta.getDate()+6);
 return {desde,hasta};
}
function planDias(desde,hasta){
 const out=[];
 for(const d=new Date(desde);d<=hasta;d.setDate(d.getDate()+1))out.push(new Date(d));
 return out;
}
/* Reparte en carriles las ausencias que se solapan: la primera que cabe en un
   carril libre se queda ahí, y si ninguno está libre se abre uno nuevo. */
function planCarriles(items){
 const finDeCarril=[];
 items.forEach(a=>{
  let i=finDeCarril.findIndex(fin=>fin<a._d0);
  if(i<0){finDeCarril.push(a._d1);i=finDeCarril.length-1}else finDeCarril[i]=a._d1;
  a._carril=i+1;
 });
 return Math.max(1,finDeCarril.length);
}

function planTab(){
 const {desde,hasta}=planRango();
 const dias=planDias(desde,hasta);
 const cols=dias.length;
 const hoy=today();
 const desdeY=ymd(desde),hastaY=ymd(hasta);

 const titulo=planView==='mes'
  ? desde.toLocaleDateString('es-EC',{month:'long',year:'numeric'})
  : desde.toLocaleDateString('es-EC',{day:'numeric',month:'short'})+' – '+hasta.toLocaleDateString('es-EC',{day:'numeric',month:'short',year:'numeric'});

 // Sólo la plantilla activa: un archivado no tiene por qué ocupar una fila.
 const gente=(directory.length?directory:employees).filter(e=>e.active!==false);

 const cabecera=dias.map(d=>{
  const w=d.getDay(),esHoy=ymd(d)===hoy;
  return `<div class="hrPlanDia${w===0||w===6?' fin':''}${esHoy?' hoy':''}">
    <small>${d.toLocaleDateString('es-EC',{weekday:'short'})}</small><b>${d.getDate()}</b></div>`;
 }).join('');

 const fondo=dias.map((d,i)=>{
  const w=d.getDay(),esHoy=ymd(d)===hoy;
  return `<div class="hrPlanCol${w===0||w===6?' fin':''}${esHoy?' hoy':''}" style="grid-column:${i+1}"></div>`;
 }).join('');

 const filas=gente.map(p=>{
  // Una ausencia entra si toca el periodo, aunque empiece antes o acabe después.
  const suyas=(calendar.length?calendar:absences)
   .filter(a=>a.employee_id===p.id&&a.status!=='rechazada'&&a.start_date<=hastaY&&a.end_date>=desdeY)
   .sort((a,b)=>a.start_date.localeCompare(b.start_date))
   .map(a=>Object.assign({},a,{_d0:a.start_date,_d1:a.end_date}));
  const carriles=planCarriles(suyas);

  const barras=suyas.map(a=>{
   // Se recorta a la ventana visible y se marca si se sale por algún lado.
   const ini=Math.max(0,diffDays(desde,fromYmd(a.start_date)));
   const fin=Math.min(cols-1,diffDays(desde,fromYmd(a.end_date)));
   const cortaIzq=a.start_date<desdeY,cortaDer=a.end_date>hastaY;
   const color=PLAN_COLORES[a.kind]||PLAN_COLORES.otro;
   const pend=a.status==='pendiente';
   const etiqueta=(KIND_LABEL[a.kind]||a.kind).replace(/^\S+\s/,'');
   const detalle=employeeName(a.employee_id)+' · '+(KIND_LABEL[a.kind]||a.kind)+' · '
     +day(a.start_date)+' → '+day(a.end_date)+' · '+(STATUS[a.status]||a.status);
   return `<button type="button" class="hrPlanBarra${pend?' pend':''}${cortaIzq?' cortaIzq':''}${cortaDer?' cortaDer':''}"
     data-plan="${esc(a.id)}" title="${esc(detalle)}"
     style="grid-column:${ini+1}/${fin+2};grid-row:${a._carril};--c:${color}">
     <span>${esc(etiqueta)}${pend?' ·pendiente':''}</span></button>`;
  }).join('');

  return `<div class="hrPlanFila">
    <div class="hrPlanNombre"><b>${esc(p.full_name)}</b><small>${esc(p.position||'')}</small></div>
    <div class="hrPlanCeldas" style="--cols:${cols};grid-template-rows:repeat(${carriles},22px)">
      ${fondo}${barras||''}
    </div>
  </div>`;
 }).join('');

 const leyenda=Object.keys(PLAN_COLORES).filter(k=>isAdmin()?k!=='ausencia':k!=='enfermedad').map(k=>
   `<span class="hrPlanLeyenda"><i style="background:${PLAN_COLORES[k]}"></i>${esc((KIND_LABEL[k]||k).replace(/^\S+\s/,''))}</span>`).join('')
  +'<span class="hrPlanLeyenda"><i class="pend"></i>Pendiente de aprobar</span>';

 const sel=planPick&&(calendar.length?calendar:absences).find(a=>a.id===planPick);

 return `<div class="card">
  <div class="hrPlanBarraSup">
   <div class="hrPlanNav">
    <button type="button" class="secondary" id="hrPlanHoy">Hoy</button>
    <button type="button" class="secondary" id="hrPlanPrev" aria-label="Periodo anterior">‹</button>
    <button type="button" class="secondary" id="hrPlanNext" aria-label="Periodo siguiente">›</button>
    <b class="hrPlanTitulo">${esc(titulo)}</b>
   </div>
   <div class="hrPlanVistas">
    <button type="button" class="${planView==='semana'?'on':''}" data-vista="semana">Semana</button>
    <button type="button" class="${planView==='mes'?'on':''}" data-vista="mes">Mes</button>
   </div>
  </div>

  ${gente.length?`<div class="hrPlanScroll"><div class="hrPlan">
    <div class="hrPlanFila hrPlanCabecera">
     <div class="hrPlanNombre">Empleado</div>
     <div class="hrPlanCeldas hrPlanDias" style="--cols:${cols}">${cabecera}</div>
    </div>
    ${filas}
   </div></div>`
  :'<div class="hrEmpty">Añade empleados en la pestaña «Empleados» para verlos aquí.</div>'}

  <div class="hrPlanPie">${leyenda}</div>

  ${sel?`<div class="hrPlanDetalle">
    <div><b>${esc(employeeName(sel.employee_id))}</b> · ${esc(KIND_LABEL[sel.kind]||sel.kind)}
      <small>${day(sel.start_date)} → ${day(sel.end_date)} · ${sel.days} día${sel.days>1?'s':''} naturales${sel.kind==='vacaciones'?' · '+workingDays(sel.start_date,sel.end_date)+' laborables':''}</small>
      ${sel.reason?`<small>${esc(sel.reason)}</small>`:''}</div>
    <div class="hrActs">
      ${isAdmin()&&sel.status!=='aprobada'?`<button type="button" class="success" data-ok="${esc(sel.id)}">✓ Aprobar</button>`:''}
      ${isAdmin()&&sel.status!=='rechazada'?`<button type="button" class="secondary" data-no="${esc(sel.id)}">✕ Rechazar</button>`:''}
      <button type="button" class="secondary" id="hrPlanCerrar">Cerrar</button>
    </div>
   </div>`:''}
 </div>`;
}

/* Un mes se avanza por su día 1: sumar 30 días desde un 31 se saltaría un mes. */
function planMover(n){
 const d=new Date(planAnchor);
 if(planView==='mes')planAnchor=new Date(d.getFullYear(),d.getMonth()+n,1);
 else{d.setDate(d.getDate()+7*n);planAnchor=d}
}

/* ---- lo que ve un empleado ---- */
function myCardTab(){
 const yo=employees.find(e=>e.profile_id)||employees[0]||null;
 if(!yo){
  return `<div class="card"><div class="hrEmpty">Tu cuenta todavía no está ligada a una ficha de empleado.<br>
   Pídele a un administrador que la enlace desde Recursos humanos → Empleados.</div></div>`;
 }
 const year=new Date().getFullYear();
 const total=Number(yo.annual_leave_days||0),used=usedLeave(yo.id,year),quedan=Math.max(0,total-used);
 const pct=total>0?Math.min(100,Math.round(used/total*100)):0;
 const dato=(k,v)=>v?`<div class="hrDato"><span>${esc(k)}</span><b>${esc(v)}</b></div>`:'';
 return `<div class="hrGrid">
  <div class="card">
   <h3>Mi ficha</h3>
   <div class="hrDatos">
    ${dato('Nombre',yo.full_name)}
    ${dato('Puesto',yo.position)}
    ${dato('Departamento',yo.department)}
    ${dato('Tipo de contrato',yo.contract_type)}
    ${yo.salary==null?'':dato('Sueldo mensual',money(yo.salary))}
    ${yo.hire_date?dato('Fecha de alta',day(yo.hire_date)):''}
    ${dato('Cédula / RUC',yo.identification)}
    ${dato('Correo',yo.email)}
    ${dato('Teléfono',yo.phone)}
   </div>
   <div class="muted" style="font-size:11.5px;margin-top:12px">Si algún dato no es correcto, avisa a un administrador: la ficha la mantiene recursos humanos.</div>
  </div>
  <div class="card">
   <h3>Mis vacaciones ${year}</h3>
   <div class="hrSaldo">
    <div><span>Días pactados</span><b>${total}</b></div>
    <div><span>Usados</span><b>${used}</b></div>
    <div class="hrSaldoLibre"><span>Te quedan</span><b>${quedan}</b></div>
   </div>
   <div class="hrBar" style="max-width:none"><i class="${pct>=100?'full':''}" style="width:${pct}%"></i></div>
   <div class="muted" style="font-size:11.5px;margin-top:8px">Se cuentan días laborables, de lunes a viernes. Sólo descuentan los días ya aprobados.</div>
  </div>
 </div>`;
}

function myRequestsTab(){
 const yo=employees.find(e=>e.profile_id)||employees[0]||null;
 const filas=absences.map(a=>{
  const cls=a.status==='aprobada'?'ok':a.status==='rechazada'?'red':'warn';
  return `<tr>
   <td><b>${esc(KINDS[a.kind]||a.kind)}</b><small>${esc(a.reason||'')}</small></td>
   <td>${day(a.start_date)} → ${day(a.end_date)}<small>${a.days} día${a.days>1?'s':''} naturales${a.kind==='vacaciones'?' · '+workingDays(a.start_date,a.end_date)+' laborables':''}</small></td>
   <td><span class="hrBadge ${cls}">${esc(STATUS[a.status]||a.status)}</span></td>
   <td>${a.status==='pendiente'?`<button type="button" class="danger" data-del="${esc(a.id)}">Retirar</button>`:''}</td>
  </tr>`;
 }).join('');

 return `<div class="hrGrid">
  <div class="card">
   <h3>Pedir días</h3>
   ${yo?'':'<div class="hrEmpty">Tu cuenta no está ligada a una ficha de empleado, así que todavía no puedes pedir días.</div>'}
   ${yo?`<label>Motivo</label>
   <select id="hrAbsKind">${Object.keys(KINDS).map(k=>`<option value="${k}">${KINDS[k]}</option>`).join('')}</select>
   <div class="row">
    <div><label>Desde *</label><input id="hrAbsFrom" type="date" value="${today()}"></div>
    <div><label>Hasta *</label><input id="hrAbsTo" type="date" value="${today()}"></div>
   </div>
   <label>Comentario</label><textarea id="hrAbsReason" placeholder="Motivo o detalle para quien lo apruebe…"></textarea>
   <div class="actions"><button type="button" class="primary" id="hrAbsAdd">📩 Enviar solicitud</button></div>
   <div class="muted" style="font-size:11.5px;margin-top:8px">La solicitud queda <b>pendiente</b> hasta que un administrador la apruebe. Mientras lo esté, puedes retirarla.</div>`:''}
  </div>
  <div class="card">
   <h3>Mis solicitudes <small class="muted">(${absences.length})</small></h3>
   ${absences.length?`<div class="hrTable"><table>
     <thead><tr><th>Motivo</th><th>Periodo</th><th>Estado</th><th></th></tr></thead>
     <tbody>${filas}</tbody></table></div>`
    :'<div class="hrEmpty">Todavía no has pedido ningún día.</div>'}
  </div>
 </div>`;
}

function render(){
 css();
 const s=section();
 const admin=isAdmin();
 // Un empleado que entra por primera vez cae en «Mi ficha», no en una
 // pestaña de administración que no va a poder usar.
 if(!admin&&(tab==='empleados'||tab==='ausencias'))tab=tab==='empleados'?'miFicha':'misDias';
 if(admin&&(tab==='miFicha'||tab==='misDias'))tab=tab==='miFicha'?'empleados':'ausencias';

 const pestanas=admin
  ? [['empleados','👥 Empleados'],['ausencias','📅 Ausencias'],['planificacion','🗓️ Planificación']]
  : [['miFicha','🪪 Mi ficha'],['misDias','📩 Mis días'],['planificacion','🗓️ Planificación']];

 s.innerHTML=window.GamaUI.header({
   title:'🧑‍💼 Recursos humanos',
   lead:admin
     ? 'La ficha de cada empleado —puesto, contrato, sueldo y vacaciones pactadas— y el registro de sus ausencias: vacaciones, bajas por enfermedad, permisos y formación. El saldo de vacaciones se descuenta solo a medida que apruebas los días, y en la ficha puedes ligar a cada persona con su cuenta de acceso para que pida sus días ella misma.'
     : 'Tus datos de empleado, tus vacaciones y el calendario del equipo. Pide tus días desde aquí: la solicitud queda pendiente hasta que un administrador la apruebe. Del resto de tus compañeros sólo ves cuándo están fuera, nunca sus datos ni el motivo.',
   actions:'<button type="button" class="gamaStdAction" id="hrRefresh">↻ Actualizar</button>'
 })
 +`<div class="hrTabs">${pestanas.map(([id,txt])=>
    `<button type="button" class="${tab===id?'on':''}" data-tab="${id}">${txt}</button>`).join('')}</div>`
 +(admin?kpis():'')
 +'<div id="hrMsg" class="hrMsg"></div>'
 +(tab==='empleados'?employeesTab()
  :tab==='ausencias'?absencesTab()
  :tab==='miFicha'?myCardTab()
  :tab==='misDias'?myRequestsTab()
  :planTab());
 bind();
}

function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
 const r=$('hrRefresh');if(r)r.onclick=load;
 s.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.tab;planPick=null;render()});
 const save=$('hrSave');if(save)save.onclick=saveEmployee;
 const clr=$('hrClear');if(clr)clr.onclick=()=>{clearEmployee();render()};
 const add=$('hrAbsAdd');if(add)add.onclick=addAbsence;
 s.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editEmployee(b.dataset.edit));
 s.querySelectorAll('[data-arch]').forEach(b=>b.onclick=()=>archiveEmployee(b.dataset.arch,b.dataset.on==='1'));
 s.querySelectorAll('[data-ok]').forEach(b=>b.onclick=()=>setAbsenceStatus(b.dataset.ok,'aprobada'));
 s.querySelectorAll('[data-no]').forEach(b=>b.onclick=()=>setAbsenceStatus(b.dataset.no,'rechazada'));
 s.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>removeAbsence(b.dataset.del));
 // Planificación
 s.querySelectorAll('[data-vista]').forEach(b=>b.onclick=()=>{planView=b.dataset.vista;render()});
 const hoyBtn=$('hrPlanHoy');if(hoyBtn)hoyBtn.onclick=()=>{planAnchor=new Date();render()};
 const prev=$('hrPlanPrev');if(prev)prev.onclick=()=>{planMover(-1);render()};
 const next=$('hrPlanNext');if(next)next.onclick=()=>{planMover(1);render()};
 s.querySelectorAll('[data-plan]').forEach(b=>b.onclick=()=>{planPick=planPick===b.dataset.plan?null:b.dataset.plan;render()});
 const cerrar=$('hrPlanCerrar');if(cerrar)cerrar.onclick=()=>{planPick=null;render()};
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
