/* GAMA HR — employee records, leave requests and team absence calendar.
   HR P1 adds work calendars, audited workflows, documents and external payroll. */
(function(){
'use strict';
if(window.GamaHR)return;

const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const day=v=>{if(!v)return '—';try{return new Date(v+'T12:00:00').toLocaleDateString('es-EC')}catch(e){return String(v)}};
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());

const KINDS={vacaciones:'🏖️ Vacaciones',enfermedad:'🤒 Enfermedad',permiso:'📄 Permiso',formacion:'🎓 Formación',otro:'• Otro'};
/* El equipo ve el motivo de cada ausencia —vacaciones, enfermedad, permiso…—
   porque para organizarse hace falta saberlo. Lo que no sale de su tabla es el
   comentario escrito a mano, que puede llevar un detalle médico o personal. */
const STATUS={pendiente:'Pendiente',aprobada:'Aprobada',rechazada:'Rechazada',cancelada:'Cancelada'};

let employees=[],absences=[],tab='empleados',editing=null,busy=false,loadVersion=0;
/* Los datos sensibles —sueldo, cédula, contrato, y el comentario escrito a mano
   de una ausencia— viven en hr_employee_private y hr_absence_private, con su
   propia política. Las tablas base sólo guardan lo que el equipo necesita para
   el calendario: quién, qué puesto, qué motivo y qué días.

   Por eso aquí se piden las cuatro y se juntan por id: a un compañero la base
   le devuelve la mitad privada vacía, y la ficha le llega sin sueldo sin que
   este archivo tenga que decidir nada. */
let mine=null,perfiles=[],myUid=null;

const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(e){return ''}};
const isSystemAdmin=()=>role()==='admin'||role()==='administrador';
const isAdmin=()=>isSystemAdmin()||!!window.GamaHRP1?.isHR;
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
 if(window.GamaHRP1)return window.GamaHRP1.used(employeeId,year);
 return absences.filter(a=>a.employee_id===employeeId&&a.kind==='vacaciones'&&a.status==='aprobada').reduce((sum,a)=>sum+workingDays(a.start_date>year+'-01-01'?a.start_date:year+'-01-01',a.end_date<year+'-12-31'?a.end_date:year+'-12-31'),0);
}
function employeeName(id){return (employees.find(e=>e.id===id)||{}).full_name||'Empleado'}
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
 const version=++loadVersion;
 const api=C();
 if(!api){msg('La conexión con la nube de Architect ERP no está disponible.',true);return}
 try{
  const [e,a,ep,ap,ses]=await Promise.all([
   api.list('hr_employees',{order:'full_name',ascending:true}),
   api.list('hr_absences',{order:'start_date',ascending:false}),
   api.list('hr_employee_private',{}),
   api.list('hr_absence_private',{}),
   api.getSession(),
  ]);
  if(version!==loadVersion)return;
  if(e.error)throw e.error;
  if(a.error)throw a.error;
  if(ep.error)throw ep.error;
  if(ap.error)throw ap.error;
  myUid=ses?.data?.session?.user?.id||null;
  const priv=new Map((ep.error?[]:(ep.data||[])).map(r=>[r.employee_id,r]));
  const privA=new Map((ap.error?[]:(ap.data||[])).map(r=>[r.absence_id,r]));
  employees=(e.data||[]).map(x=>Object.assign({},x,priv.get(x.id)||{}));
  absences=(a.data||[]).map(x=>Object.assign({},x,privA.get(x.id)||{}));
  mine=employees.find(x=>x.profile_id&&x.profile_id===myUid)||null;
  if(window.GamaHRP1&&await window.GamaHRP1.load({employees,absences,myUid,admin:isSystemAdmin()})===false)return;
  if(version!==loadVersion)return;
  if(isAdmin())await loadProfiles();
  if(version!==loadVersion)return;
  render();
 }catch(err){fail(err,'No se pudieron cargar los datos de RRHH')}
}
/* Las cuentas de acceso, para poder ligar una ficha a un usuario. Sólo el
   administrador las lee. */
async function loadProfiles(){
 if(window.GamaHRP1?.directory.length){perfiles=window.GamaHRP1.directory;return}
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
 // Lo que el equipo puede ver…
 const row={
  full_name:name,
  position:($('hrPosition').value||'').trim()||null,
  department:($('hrDept').value||'').trim()||null,
  profile_id:$('hrAccount')?.value||null,
 };
 // …y lo que sólo ven el interesado y recursos humanos.
 const priv={
  identification:($('hrId').value||'').trim()||null,
  email:($('hrEmail').value||'').trim()||null,
  phone:($('hrPhone').value||'').trim()||null,
  contract_type:$('hrContract').value||null,
  hire_date:$('hrHire').value||null,
  end_date:$('hrEnd').value||null,
  salary:num($('hrSalary').value),
  annual_leave_days:num($('hrLeaveDays').value)??15,
  notes:($('hrNotes').value||'').trim()||null,
 };
 busy=true;
 try{
  const r=await(await C().db()).rpc('gama_hr_save_employee',{p_id:editing,p_employee:row,p_private:priv});
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
   start_fraction:Number($('hpStartFraction')?.value||1),end_fraction:Number($('hpEndFraction')?.value||1),
   status:isAdmin()?($('hrAbsStatus')?.value||'pendiente'):'pendiente',
   decision_reason:['rechazada','cancelada'].includes($('hrAbsStatus')?.value)?$('hrAbsReason').value:null});
  if(r.error)throw r.error;
  const motivo=($('hrAbsReason').value||'').trim();
  if(motivo&&r.data?.id){
   const m=await C().insert('hr_absence_private',{absence_id:r.data.id,reason:motivo});
   // El comentario es un extra: si no se pudiera guardar, la ausencia ya está
   // pedida y perderla sería peor que quedarse sin la nota.
   if(m.error)console.warn('[GAMA RRHH] no se guardó el comentario',m.error);
  }
  $('hrAbsFrom').value='';$('hrAbsTo').value='';$('hrAbsReason').value='';
  msg(isAdmin()?'Ausencia registrada.':'Solicitud enviada. Queda pendiente de aprobación.');
  await load();
 }catch(e){fail(e,'No se pudo registrar la ausencia')}
 finally{busy=false}
}
async function setAbsenceStatus(id,status){
 try{
  const reason=status==='rechazada'?prompt(window.GamaI18n?.t('Motivo')||'Motivo'):null;
  if(status==='rechazada'&&!reason?.trim())return;
  const r=await C().update('hr_absences',id,{status,decision_reason:reason});
  if(r.error)throw r.error;
  await load();
 }catch(e){fail(e,'No se pudo cambiar el estado de la ausencia')}
}
async function removeAbsence(id){
 const reason=prompt(window.GamaI18n?.t('Motivo de anulación')||'Motivo de anulación');
 if(!reason?.trim())return;
 try{const r=await C().update('hr_absences',id,{status:'cancelada',decision_reason:reason});if(r.error)throw r.error;await load()}catch(e){fail(e,'No se pudo anular la ausencia')}
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
#hr .hrTabs button{background:#fff;border:1px solid var(--arc-line-strong);color:var(--arc-text);border-radius:999px;padding:10px 16px;font-weight:800;cursor:pointer;width:auto}
#hr .hrTabs button.on{background:var(--arc-accent-600);border-color:var(--arc-accent-600);color:#fff}
#hr .hrKpis{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:14px}
#hr .hrKpi{background:#fff;border:1px solid var(--arc-line);border-radius:13px;padding:14px}
#hr .hrKpi span{display:block;color:var(--arc-text-muted);font-size:11px;font-weight:700}
#hr .hrKpi b{display:block;margin-top:6px;font-size:22px;color:var(--arc-text)}
/* El reparto se inclina hacia la tabla. El formulario es una pila de campos y
   se lee igual de bien en 420 px; la tabla, en cambio, tiene seis columnas y
   cuando se queda corta hay que arrastrarla de lado para llegar a los botones
   de cada fila. El sitio se lo lleva quien lo necesita. */
#hr .hrGrid{display:grid;grid-template-columns:minmax(0,.72fr) minmax(0,1.28fr);gap:12px;align-items:start}
#hr .hrTable{width:100%;overflow-x:auto}
/* min-width:min-content y no los 560 px de antes. Con una anchura fija, si las
   columnas pedían más que la caja —un nombre largo, «Prestación de servicios»—
   la tabla se quedaba clavada al 100 % y las celdas se salían por su derecha:
   los botones de Editar y Archivar aparecían cortados y NO había forma de
   llegar a ellos, porque el contenedor no se enteraba de que sobraba nada que
   desplazar. Pidiéndole a la tabla su propio mínimo, crece lo que necesite y
   entonces sí es el contenedor el que se desplaza. */
#hr .hrTable table{width:100%;border-collapse:collapse;min-width:min-content}
#hr .hrTable th,#hr .hrTable td{padding:10px;border-bottom:1px solid var(--arc-surface-3);text-align:left;font-size:12px;vertical-align:top}
#hr .hrTable th{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--arc-text-muted);background:var(--arc-surface-2)}
#hr .hrTable small{display:block;color:var(--arc-text-subtle)}
#hr .hrBadge{display:inline-block;border-radius:999px;padding:4px 9px;font-size:10px;font-weight:800;background:var(--arc-surface-3);color:var(--arc-text-muted);white-space:nowrap}
#hr .hrBadge.ok{background:var(--arc-success-bg);color:var(--arc-success)}
#hr .hrBadge.warn{background:var(--arc-warning-bg);color:var(--arc-warning)}
#hr .hrBadge.red{background:var(--arc-danger-bg);color:var(--arc-danger)}
#hr .hrBar{height:7px;border-radius:999px;background:var(--arc-surface-3);overflow:hidden;margin-top:5px;max-width:150px}
#hr .hrBar i{display:block;height:100%;background:var(--arc-accent-600)}
#hr .hrBar i.full{background:var(--arc-danger)}
#hr .hrMsg{margin:10px 0;font-size:13px}
#hr .hrMsg.hrOk{color:var(--arc-success)}#hr .hrMsg.hrErr{color:var(--arc-danger);font-weight:700}
#hr .hrEmpty{padding:22px;text-align:center;color:var(--arc-text-subtle)}
#hr .hrActs{display:flex;gap:6px;flex-wrap:wrap}
#hr .hrActs button{padding:6px 9px;font-size:11px;width:auto}
#hr .hrOff td{opacity:.55}
#hr .hrDatos{display:grid;gap:1px;background:var(--arc-surface-3);border:1px solid var(--arc-surface-3);border-radius:10px;overflow:hidden}
#hr .hrDato{display:flex;justify-content:space-between;gap:12px;padding:11px 13px;background:#fff;font-size:13px}
#hr .hrDato span{color:var(--arc-text-muted)}
#hr .hrDato b{color:var(--arc-text);text-align:right}
#hr .hrSaldo{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:12px}
#hr .hrSaldo>div{background:var(--arc-surface-2);border:1px solid var(--arc-surface-3);border-radius:11px;padding:12px;text-align:center}
#hr .hrSaldo span{display:block;color:var(--arc-text-muted);font-size:11px;font-weight:700}
#hr .hrSaldo b{display:block;margin-top:5px;font-size:24px;color:var(--arc-text)}
#hr .hrSaldoLibre{background:var(--arc-accent-100)!important;border-color:var(--arc-accent-100)!important}
#hr .hrSaldoLibre b{color:var(--arc-accent-600)}

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
#hr .hrPlanTitulo{font-size:15px;color:var(--arc-text);margin-left:4px}
#hr .hrPlanTitulo::first-letter{text-transform:uppercase}
#hr .hrPlanVistas{display:flex;gap:6px}
#hr .hrPlanVistas button{background:#fff;border:1px solid var(--arc-line-strong);color:var(--arc-text);border-radius:999px;padding:8px 15px;font-weight:800;cursor:pointer;width:auto;font-size:13px}
#hr .hrPlanVistas button.on{background:var(--arc-accent-600);border-color:var(--arc-accent-600);color:#fff}
/* El calendario sí tiene que arrastrarse de lado —siete días, o treinta y uno,
   no caben en un teléfono y no hay forma de apilarlos—, así que aquí no se
   quita el desplazamiento: se arregla. overflow-y:hidden porque poner sólo
   overflow-x deja el otro eje en «visible», y el navegador lo asciende a
   «auto»: la caja se queda entonces con el gesto de subir la página y el dedo
   que cae dentro del calendario no la mueve. Y overscroll-behavior-x:contain
   porque el arrastre aquí es largo —306 px en la vista de semana, 926 en la
   de mes— y llegar al borde era de lo más fácil: allí se lo quedaba el
   navegador y disparaba su gesto de volver atrás. La columna de nombres se
   queda fija (position:sticky) para no perder de vista de quién es cada fila. */
#hr .hrPlanScroll{overflow-x:auto;overflow-y:hidden;overscroll-behavior-x:contain;-webkit-overflow-scrolling:touch;border:1px solid var(--arc-surface-3);border-radius:12px}
#hr .hrPlan{min-width:640px}
#hr .hrPlanFila{display:grid;grid-template-columns:170px 1fr;border-bottom:1px solid var(--arc-surface-3)}
#hr .hrPlanFila:last-child{border-bottom:0}
#hr .hrPlanNombre{padding:9px 11px;border-right:1px solid var(--arc-surface-3);background:#fff;position:sticky;left:0;z-index:3}
#hr .hrPlanNombre b{display:block;font-size:12.5px;color:var(--arc-text);line-height:1.25}
#hr .hrPlanNombre small{display:block;color:var(--arc-text-subtle);font-size:10.5px;margin-top:1px}
#hr .hrPlanCabecera{background:var(--arc-surface-2);border-bottom:1px solid var(--arc-surface-3)}
#hr .hrPlanCabecera .hrPlanNombre{background:var(--arc-surface-2);font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--arc-text-muted);font-weight:800;display:flex;align-items:flex-end}
#hr .hrPlanCeldas{display:grid;grid-template-columns:repeat(var(--cols),minmax(38px,1fr));grid-auto-rows:22px;align-content:center;gap:3px 0;padding:6px 0;position:relative}
#hr .hrPlanDias{grid-auto-rows:auto;padding:7px 0}
#hr .hrPlanDia{text-align:center;font-size:11px;color:var(--arc-text);border-right:1px solid var(--arc-surface-3)}
#hr .hrPlanDia:last-child{border-right:0}
#hr .hrPlanDia small{display:block;color:var(--arc-text-subtle);font-size:9.5px;text-transform:uppercase}
#hr .hrPlanDia b{display:block;font-size:13px}
#hr .hrPlanDia.fin{background:var(--arc-surface-2);color:var(--arc-text-subtle)}
#hr .hrPlanDia.hoy{background:var(--arc-warning-bg);box-shadow:inset 0 -3px 0 var(--arc-warning)}
#hr .hrPlanCol{grid-row:1/-1;border-right:1px solid var(--arc-surface-2)}
#hr .hrPlanCol:last-of-type{border-right:0}
#hr .hrPlanCol.fin{background:var(--arc-surface-2)}
#hr .hrPlanCol.hoy{background:var(--arc-warning-bg)}
#hr .hrPlanBarra{position:relative;z-index:2;display:flex;align-items:center;min-width:0;height:22px;margin:0 2px;padding:0 7px;border:0;border-radius:6px;cursor:pointer;background:var(--c);color:#fff;font-weight:700;font-size:10.5px;text-align:left;width:auto;overflow:hidden}
#hr .hrPlanBarra span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#hr .hrPlanBarra:hover{filter:brightness(1.08)}
#hr .hrPlanBarra:focus-visible{outline:3px solid var(--arc-text);outline-offset:1px}
/* Pendiente de aprobar: hueca y con el borde a rayas, para que no se confunda
   con lo ya concedido de un vistazo. */
#hr .hrPlanBarra.pend{background:#fff;color:var(--c);border:1.5px dashed var(--c)}
/* Una ausencia que empieza antes o acaba después del periodo se recorta: la
   punta plana avisa de que sigue fuera de la vista. */
#hr .hrPlanBarra.cortaIzq{border-top-left-radius:0;border-bottom-left-radius:0;margin-left:0}
#hr .hrPlanBarra.cortaDer{border-top-right-radius:0;border-bottom-right-radius:0;margin-right:0}
#hr .hrPlanPie{display:flex;gap:14px;flex-wrap:wrap;margin-top:12px;font-size:11px;color:var(--arc-text-muted)}
#hr .hrPlanLeyenda{display:inline-flex;align-items:center;gap:6px}
#hr .hrPlanLeyenda i{width:12px;height:12px;border-radius:3px;display:inline-block}
#hr .hrPlanLeyenda i.pend{background:#fff;border:1.5px dashed var(--arc-text-muted)}
#hr .hrPlanDetalle{display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap;margin-top:14px;padding:12px 14px;border:1px solid var(--arc-line);border-left:4px solid var(--arc-accent-600);border-radius:10px;background:var(--arc-surface-2)}
#hr .hrPlanDetalle small{display:block;color:var(--arc-text-muted);font-size:11.5px;margin-top:2px}
/* minmax(0,1fr) y no 1fr: «1fr» es «minmax(auto,1fr)», y ese mínimo automático
   es el del contenido. La tabla de empleados lleva min-width:560px a propósito
   —una tabla necesita sitio y por eso .hrTable tiene su propio scroll—, pero
   con «1fr» ese mínimo se escapaba a la columna y estiraba la rejilla, las dos
   tarjetas y el documento entero a 598 px en cualquier teléfono. El navegador
   respondía alejando el zoom para que cupiera: de ahí que la cabecera y las
   tarjetas salieran encogidas. Acotando la pista, la tabla vuelve a
   desplazarse dentro de su caja y la página mide lo que mide la pantalla. */
/* La rejilla se parte antes que el resto, y por su propia razón: en dos
   columnas la tabla necesita unos 690 px para enseñar sus seis columnas y los
   botones de cada fila, y por debajo de este ancho la mitad derecha ya no da
   para tanto. Puesta en una sola columna, la tabla ocupa la pantalla entera y
   deja de haber nada que arrastrar. Las tarjetas de arriba aguantan bien más
   estrechas, así que se parten por su cuenta más abajo. */
@media(max-width:1150px){#hr .hrGrid{grid-template-columns:minmax(0,1fr)}}
@media(max-width:900px){#hr .hrKpis{grid-template-columns:1fr 1fr}
 #hr .hrPlanFila{grid-template-columns:120px 1fr}#hr .hrPlanNombre b{font-size:11.5px}}
/* Las tres pestañas se partían en dos filas, con «Planificación» sola abajo.
   Repartidas a partes iguales entran en una; el icono sobra ahí, y sin él la
   palabra cabe entera. Este bloque va DESPUÉS de las reglas de base a
   propósito: una media query no añade especificidad, así que escrito antes se
   quedaba sin efecto contra un selector idéntico. */
@media(max-width:760px){#hr .hrTabs{display:flex;flex-wrap:nowrap;overflow-x:auto;gap:5px;padding-bottom:6px}
 #hr .hrTabs button{padding:10px 12px;font-size:12px;white-space:nowrap;flex:0 0 auto;min-height:44px}
 #hr .hrTabIco{display:none}}
/* Las fichas del teléfono las pone gama-tables.js para todas las tablas de la
   aplicación: copia de la cabecera el nombre de cada columna, apila cada fila
   y endurece el gesto. Aquí sólo queda lo que es de esta tabla y nada más. */
@media(max-width:760px){#hr .hrTable{--gamaCardsLabel:92px}
 #hr .hrTable .hrBar{max-width:none}}`;
 document.head.appendChild(s);
}

function kpis(){
 const activos=employees.filter(e=>e.active!==false).length;
 const fuera=onLeaveToday().length;
 const pend=absences.filter(a=>a.status==='pendiente').length;
 const year=new Date().getFullYear();
 const enfermos=absences.filter(a=>a.kind==='enfermedad'&&String(a.start_date||'').slice(0,4)===String(year)).length;
 return `<div class="hrKpis">
  <div class="hrKpi"><span data-gi=e0a032ea89a6>Empleados activos</span><b>${activos}</b></div>
  <div class="hrKpi"><span data-gi=24635c11f693>Ausentes hoy</span><b>${fuera}</b></div>
  <div class="hrKpi"><span data-gi=8159fcc540c4>Pendientes de aprobar</span><b>${pend}</b></div>
  <div class="hrKpi"><span>Bajas por enfermedad ${year}</span><b>${enfermos}</b></div>
 </div>`;
}

function employeesTab(){
 const year=new Date().getFullYear();
 const rows=employees.map(p=>{
  const total=window.GamaHRP1?window.GamaHRP1.entitlement(p.id,year):Number(p.annual_leave_days||0);
  const used=usedLeave(p.id,year);
  const pct=total>0?Math.min(100,Math.round(used/total*100)):0;
  const off=p.active===false;
  return `<tr class="${off?'hrOff':''}">
   <td><b>${esc(p.full_name)}</b><small>${esc(p.position||'Sin puesto')}${p.department?' · '+esc(p.department):''}</small>
       <small>${esc(p.identification||'')}</small></td>
   <td>${esc(p.contract_type||'—')}<small><span data-gi=cdd3851b36eb>Alta: </span>${day(p.hire_date)}</small>${p.end_date?`<small><span data-gi=82a0a91a8205>Baja: </span>${day(p.end_date)}</small>`:''}</td>
   <td>${p.salary==null?'—':money(p.salary)}</td>
   <td>${used} / ${total}<small>días laborables ${year}</small>
       <div class="hrBar"><i class="${pct>=100?'full':''}" style="width:${pct}%"></i></div></td>
   <td>${off?'<span class="hrBadge" data-gi=eac5386d4211>Archivado</span>':'<span class="hrBadge ok" data-gi=723858144bd5>Activo</span>'}${p.profile_id?'<br><span class="hrBadge ok" style="margin-top:4px" data-gi=19074913530e>🔑 Con cuenta</span>':'<br><span class="hrBadge" style="margin-top:4px" data-gi=b4c10bd2c2fc>Sin cuenta</span>'}</td>
   <td><div class="hrActs">
    <button type="button" class="secondary" data-edit="${esc(p.id)}" data-gi=e3bd2ee1d054>✏️ Editar</button>
    <button type="button" class="${off?'secondary':'danger'}" data-arch="${esc(p.id)}" data-on="${off?'1':'0'}" data-gi-live>${off?'♻️ Restaurar':'🗄️ Archivar'}</button>
   </div></td></tr>`;
 }).join('');

 return `<div class="hrGrid">
  <div class="card">
   <h3>${editing?'Editar empleado':'Nuevo empleado'}</h3>
   <label data-gi=0be48a5a67cc>Nombre y apellidos *</label><input id="hrName" data-gi-placeholder=d6730d8299a4 placeholder="Ej. María Pérez">
   <div class="row">
    <div><label data-gi=48fdf0f9d94c>Cédula / RUC</label><input id="hrId" placeholder="0912345678"></div>
    <div><label data-gi=f1186abd0b8b>Teléfono</label><input id="hrPhone" type="tel" placeholder="+593…"></div>
   </div>
   <label data-gi=ec64dc30a483>Correo electrónico</label><input id="hrEmail" type="email" placeholder="correo@ejemplo.com">
   <div class="row">
    <div><label data-gi=888f25ceee71>Puesto</label><input id="hrPosition" data-gi-placeholder=47f913f15782 placeholder="Ej. Almacenero"></div>
    <div><label data-gi=4695dca246f0>Departamento</label><input id="hrDept" data-gi-placeholder=749ad86d9ec3 placeholder="Ej. Bodega"></div>
   </div>
   <label data-gi=d27403823536>Tipo de contrato</label>
   <select id="hrContract">
    <option value="" data-gi=e545b02d8dee>Sin especificar</option>
    <option data-gi=eddd72ca1009>Indefinido</option><option data-gi=d9460e0cb708>Plazo fijo</option><option data-gi=42413a38c5a9>Eventual</option>
    <option data-gi=ac3f091ca341>Prueba</option><option data-gi=817e41b7b714>Prestación de servicios</option><option data-gi=daa9133ba2c4>Pasantía</option>
   </select>
   <div class="row">
    <div><label data-gi=62956ad3a5c1>Fecha de alta</label><input id="hrHire" type="date"></div>
    <div><label data-gi=fb3e9da06db4>Fecha de baja</label><input id="hrEnd" type="date"></div>
   </div>
   <div class="row">
    <div><label data-gi=88ba39e35667>Sueldo mensual (USD)</label><input id="hrSalary" type="number" min="0" step="0.01" placeholder="0.00"></div>
    <div><label data-gi=2890d09262cb>Vacaciones al año (días laborables)</label><input id="hrLeaveDays" type="number" min="0" step="0.5" value="15"></div>
   </div>
   <label data-gi=f5500ac97424>Cuenta de acceso</label>
   <select id="hrAccount">
    <option value="" data-gi=c202487fcbd6>Sin cuenta — no puede entrar en Architect</option>
    ${perfiles.map(u=>`<option value="${esc(u.id)}">${esc(u.full_name||u.email||u.id)}${u.email?' · '+esc(u.email):''}</option>`).join('')}
   </select>
   <div class="muted" style="font-size:11.5px;margin-top:-2px" data-gi=3acee7e660f1>Al ligar la ficha a una cuenta, esa persona ve sus propios datos, pide sus días y consulta el calendario del equipo. Sin cuenta, sólo la gestionas tú.</div>
   <label data-gi=8ef60b6d94c0>Observaciones</label><textarea id="hrNotes" data-gi-placeholder=1dc4813dafd6 placeholder="Formación, idiomas, licencia de conducir…"></textarea>
   <div class="actions">
    <button type="button" class="primary" id="hrSave" data-gi-live>${editing?'💾 Guardar cambios':'＋ Guardar empleado'}</button>
    <button type="button" class="secondary" id="hrClear" data-gi=681b0f02838a>↺ Limpiar</button>
   </div>
  </div>
  <div class="card">
   <h3 data-gi=65ebd9bd0f84>Plantilla <small class="muted">(${employees.length})</small></h3>
   ${employees.length?`<div class="hrTable"><table>
     <thead><tr><th data-gi=6f0babb30673>Empleado</th><th data-gi=1951861239ed>Contrato</th><th data-gi=193df56cd57c>Sueldo</th><th data-gi=04c60d643e4c>Vacaciones</th><th data-gi=98e5acddb6c4>Estado</th><th></th></tr></thead>
     <tbody>${rows}</tbody></table></div>`
    :'<div class="hrEmpty" data-gi=bb5a96d44ddc>Todavía no hay empleados. Añade el primero con el formulario de al lado.</div>'}
  </div>
 </div>`;
}

function absencesTab(){
 const vivos=employees.filter(e=>e.active!==false);
 const hoy=onLeaveToday();
 const rows=absences.map(a=>{
  const cls=a.status==='aprobada'?'ok':a.status==='rechazada'?'red':'warn';
  return `<tr>
   <td><b>${esc(employeeName(a.employee_id))}</b><small><span data-gi-live>${esc(KINDS[a.kind]||a.kind)}</span></small></td>
   <td>${day(a.start_date)} → ${day(a.end_date)}<small>${a.days} día${a.days>1?'s':''} naturales${a.kind==='vacaciones'?' · '+(window.GamaHRP1?window.GamaHRP1.days(a.employee_id,a.start_date,a.end_date,a.start_fraction??1,a.end_fraction??1):workingDays(a.start_date,a.end_date))+' laborables':''}</small></td>
   <td><span class="hrBadge ${cls}"><span data-gi-live>${esc(STATUS[a.status]||a.status)}</span></span>${a.decision_reason?'<small>'+esc(a.decision_reason)+'</small>':''}</td>
   <td>${esc(a.reason||'—')}</td>
   <td><div class="hrActs">
    ${a.status!=='aprobada'&&a.status!=='cancelada'?`<button type="button" class="success" data-ok="${esc(a.id)}" data-gi=28a14dff8662>✓ Aprobar</button>`:''}
    ${a.status!=='rechazada'&&a.status!=='cancelada'?`<button type="button" class="secondary" data-no="${esc(a.id)}" data-gi=c0f66b48fa6c>✕ Rechazar</button>`:''}
    ${a.status!=='cancelada'?`<button type="button" class="danger" data-del="${esc(a.id)}" data-gi-live data-gi=030a5cd7677c>Anular</button>`:''}
   </div></td></tr>`;
 }).join('');

 return `<div class="hrGrid">
  <div class="card">
   <h3 data-gi=72a86bcb4b1f>Registrar una ausencia</h3>
   <label data-gi=6020a9dd08e5>Empleado *</label>
   <select id="hrAbsEmployee">${vivos.length?vivos.map(e=>`<option value="${esc(e.id)}">${esc(e.full_name)}</option>`).join(''):'<option value="" data-gi=e918e93df678>Añade primero un empleado</option>'}</select>
   <label data-gi=c7b288b1c0bb>Motivo</label>
   <select id="hrAbsKind">${Object.keys(KINDS).map(k=>`<option value="${k}" data-gi-live>${KINDS[k]}</option>`).join('')}</select>
   <div class="row">
    <div><label data-gi=29ee9938a74c>Desde *</label><input id="hrAbsFrom" type="date" value="${today()}"></div>
    <div><label data-gi=66b3c7fb42f9>Hasta *</label><input id="hrAbsTo" type="date" value="${today()}"></div>
   </div>
   <label data-gi=98e5acddb6c4>Estado</label>
   <select id="hrAbsStatus"><option value="pendiente" data-gi=2ef68536d8e2>Pendiente</option><option value="aprobada" data-gi=80b504a3cd9c>Aprobada</option></select>
   <label data-gi=53c367898434>Comentario</label><textarea id="hrAbsReason" data-gi-placeholder=5c0130f03047 placeholder="Certificado médico, asunto propio…"></textarea>
   <div class="actions"><button type="button" class="primary" id="hrAbsAdd" data-gi=14ee9bb5d9a1>＋ Registrar ausencia</button></div>
  </div>
  <div class="card">
   <h3 data-gi=38d61a2d5404>Quién está fuera hoy</h3>
   ${hoy.length?hoy.map(a=>`<div class="hrBadge ok" style="margin:0 6px 6px 0">${esc(employeeName(a.employee_id))} · <span data-gi-live>${esc(KINDS[a.kind]||a.kind)}</span> hasta ${day(a.end_date)}</div>`).join('')
    :'<div class="muted" data-gi=bf3e32312381>Hoy no falta nadie.</div>'}
   <h3 data-gi=f43b26519010>Historial de ausencias <small class="muted">(${absences.length})</small></h3>
   ${absences.length?`<div class="hrTable"><table>
     <thead><tr><th data-gi=6f0babb30673>Empleado</th><th data-gi=fb5065f3c8c1>Periodo</th><th data-gi=98e5acddb6c4>Estado</th><th data-gi=53c367898434>Comentario</th><th></th></tr></thead>
     <tbody>${rows}</tbody></table></div>`
    :'<div class="hrEmpty" data-gi=30887522852b>Todavía no hay ausencias registradas.</div>'}
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
const PLAN_COLORES={vacaciones:'var(--arc-accent-600)',enfermedad:'var(--arc-danger)',permiso:'var(--arc-warning)',formacion:'var(--arc-fam-sales)',otro:'var(--arc-text-muted)'};

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
 const gente=employees.filter(e=>e.active!==false);

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
  const suyas=absences
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
   const etiqueta=(KINDS[a.kind]||a.kind).replace(/^\S+\s/,'');
   const detalle=employeeName(a.employee_id)+' · '+(KINDS[a.kind]||a.kind)+' · '
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

 const leyenda=Object.keys(PLAN_COLORES).map(k=>
   `<span class="hrPlanLeyenda"><i style="background:${PLAN_COLORES[k]}"></i>${esc((KINDS[k]||k).replace(/^\S+\s/,''))}</span>`).join('')
  +'<span class="hrPlanLeyenda"><i class="pend"></i>Pendiente de aprobar</span>';

 const sel=planPick&&absences.find(a=>a.id===planPick);

 return `<div class="card">
  <div class="hrPlanBarraSup">
   <div class="hrPlanNav">
    <button type="button" class="secondary" id="hrPlanHoy" data-gi=55133d4e6eb6>Hoy</button>
    <button type="button" class="secondary" id="hrPlanPrev" data-gi-aria-label=266784dff37a aria-label="Periodo anterior">‹</button>
    <button type="button" class="secondary" id="hrPlanNext" data-gi-aria-label=acdd18b1c536 aria-label="Periodo siguiente">›</button>
    <b class="hrPlanTitulo">${esc(titulo)}</b>
   </div>
   <div class="hrPlanVistas">
    <button type="button" class="${planView==='semana'?'on':''}" data-vista="semana" data-gi=51656a29fb46>Semana</button>
    <button type="button" class="${planView==='mes'?'on':''}" data-vista="mes" data-gi=024261f9bfba>Mes</button>
   </div>
  </div>

  ${gente.length?`<div class="hrPlanScroll"><div class="hrPlan">
    <div class="hrPlanFila hrPlanCabecera">
     <div class="hrPlanNombre" data-gi=6f0babb30673>Empleado</div>
     <div class="hrPlanCeldas hrPlanDias" style="--cols:${cols}">${cabecera}</div>
    </div>
    ${filas}
   </div></div>`
  :'<div class="hrEmpty" data-gi=57ce01807e78>Añade empleados en la pestaña «Empleados» para verlos aquí.</div>'}

  <div class="hrPlanPie">${leyenda}</div>

  ${sel?`<div class="hrPlanDetalle">
    <div><b>${esc(employeeName(sel.employee_id))}</b> · <span data-gi-live>${esc(KINDS[sel.kind]||sel.kind)}</span>
      <small>${day(sel.start_date)} → ${day(sel.end_date)} · ${sel.days} día${sel.days>1?'s':''} naturales${sel.kind==='vacaciones'?' · '+(window.GamaHRP1?window.GamaHRP1.days(sel.employee_id,sel.start_date,sel.end_date,sel.start_fraction??1,sel.end_fraction??1):workingDays(sel.start_date,sel.end_date))+' laborables':''}</small>
      ${sel.reason?`<small>${esc(sel.reason)}</small>`:''}</div>
    <div class="hrActs">
      ${isAdmin()&&sel.status!=='aprobada'?`<button type="button" class="success" data-ok="${esc(sel.id)}" data-gi=28a14dff8662>✓ Aprobar</button>`:''}
      ${isAdmin()&&sel.status!=='rechazada'?`<button type="button" class="secondary" data-no="${esc(sel.id)}" data-gi=c0f66b48fa6c>✕ Rechazar</button>`:''}
      <button type="button" class="secondary" id="hrPlanCerrar" data-gi=aeccae342e4b>Cerrar</button>
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
 const yo=mine;
 if(!yo){
  return `<div class="card"><div class="hrEmpty" data-gi=3bce45fcf14e>Tu cuenta todavía no está ligada a una ficha de empleado.<br data-gi=b09ad5d3000c>
   Pídele a un administrador que la enlace desde Recursos humanos → Empleados.</div></div>`;
 }
 const year=new Date().getFullYear();
 const total=window.GamaHRP1?window.GamaHRP1.entitlement(yo.id,year):Number(yo.annual_leave_days||0),used=usedLeave(yo.id,year),quedan=Math.max(0,total-used);
 const pct=total>0?Math.min(100,Math.round(used/total*100)):0;
 const dato=(k,v)=>v?`<div class="hrDato"><span>${esc(k)}</span><b>${esc(v)}</b></div>`:'';
 return `<div class="hrGrid">
  <div class="card">
   <h3 data-gi=b1c44421d26c>Mi ficha</h3>
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
   <div class="muted" style="font-size:11.5px;margin-top:12px" data-gi=f4655fc1977c>Si algún dato no es correcto, avisa a un administrador: la ficha la mantiene recursos humanos.</div>
  </div>
  <div class="card">
   <h3>Mis vacaciones ${year}</h3>
   <div class="hrSaldo">
    <div><span data-gi-live data-gi=54021b97e1a0>Derecho adquirido</span><b>${total}</b></div>
    <div><span data-gi=77c1b82cb1d7>Usados</span><b>${used}</b></div>
    <div class="hrSaldoLibre"><span data-gi=8fca1d80df6e>Te quedan</span><b>${quedan}</b></div>
   </div>
   <div class="hrBar" style="max-width:none"><i class="${pct>=100?'full':''}" style="width:${pct}%"></i></div>
   <div class="muted" style="font-size:11.5px;margin-top:8px" data-gi-live data-gi=2760b037a40d>El saldo considera el horario, los festivos y las vacaciones aprobadas.</div>
  </div>
 </div>`;
}

function myRequestsTab(){
 const yo=mine;
 // absences trae las de todo el equipo —hacen falta para el calendario—, así
 // que aquí se filtran las propias.
 const mias=yo?absences.filter(a=>a.employee_id===yo.id):[];
 const filas=mias.map(a=>{
  const cls=a.status==='aprobada'?'ok':a.status==='rechazada'?'red':'warn';
  return `<tr>
   <td><b><span data-gi-live>${esc(KINDS[a.kind]||a.kind)}</span></b><small>${esc(a.reason||'')}</small></td>
   <td>${day(a.start_date)} → ${day(a.end_date)}<small>${a.days} día${a.days>1?'s':''} naturales${a.kind==='vacaciones'?' · '+(window.GamaHRP1?window.GamaHRP1.days(a.employee_id,a.start_date,a.end_date,a.start_fraction??1,a.end_fraction??1):workingDays(a.start_date,a.end_date))+' laborables':''}</small></td>
   <td><span class="hrBadge ${cls}"><span data-gi-live>${esc(STATUS[a.status]||a.status)}</span></span>${a.decision_reason?'<small>'+esc(a.decision_reason)+'</small>':''}</td>
   <td>${a.status==='pendiente'?`<button type="button" class="danger" data-del="${esc(a.id)}" data-gi=0eeac7f5e703>Retirar</button>`:''}</td>
  </tr>`;
 }).join('');

 return `<div class="hrGrid">
  <div class="card">
   <h3 data-gi=1fc7c7b3584e>Pedir días</h3>
   ${yo?'':'<div class="hrEmpty" data-gi=26d051bd4f8d>Tu cuenta no está ligada a una ficha de empleado, así que todavía no puedes pedir días.</div>'}
   ${yo?`<label data-gi=c7b288b1c0bb>Motivo</label>
   <select id="hrAbsKind">${Object.keys(KINDS).map(k=>`<option value="${k}" data-gi-live>${KINDS[k]}</option>`).join('')}</select>
   <div class="row">
    <div><label data-gi=29ee9938a74c>Desde *</label><input id="hrAbsFrom" type="date" value="${today()}"></div>
    <div><label data-gi=66b3c7fb42f9>Hasta *</label><input id="hrAbsTo" type="date" value="${today()}"></div>
   </div>
   <label data-gi=53c367898434>Comentario</label><textarea id="hrAbsReason" data-gi-placeholder=afe18510d3eb placeholder="Motivo o detalle para quien lo apruebe…"></textarea>
   <div class="actions"><button type="button" class="primary" id="hrAbsAdd" data-gi=e3f27a649cc6>📩 Enviar solicitud</button></div>
   <div class="muted" style="font-size:11.5px;margin-top:8px" data-gi-live data-gi=66bbbee747ed>La solicitud queda pendiente hasta que RH o tu responsable la apruebe. Puedes retirarla mientras esté pendiente.</div>`:''}
  </div>
  <div class="card">
   <h3 data-gi=12bc372ef7e7>Mis solicitudes <small class="muted">(${mias.length})</small></h3>
   ${mias.length?`<div class="hrTable"><table>
     <thead><tr><th data-gi=c7b288b1c0bb>Motivo</th><th data-gi=fb5065f3c8c1>Periodo</th><th data-gi=98e5acddb6c4>Estado</th><th></th></tr></thead>
     <tbody>${filas}</tbody></table></div>`
    :'<div class="hrEmpty" data-gi=52e9de7ee71f>Todavía no has pedido ningún día.</div>'}
  </div>
 </div>`;
}

function render(){
 css();
 const s=section();
 const admin=isAdmin();
 // Un empleado que entra por primera vez cae en «Mi ficha», no en una
 // pestaña de administración que no va a poder usar.
 if(tab==='misDias')tab='ausencias';
 if(tab==='tiempo')tab=admin?'empleados':'miFicha';
 if(!admin&&tab==='empleados')tab='miFicha';


 // El icono va en su propio span: en el teléfono las tres pestañas se reparten
 // el ancho y «Planificación» no cabe con el emoji delante, así que allí se
 // esconde el icono en vez de cortar la palabra.
 const pestanas=admin
  ? [['empleados','👥','Empleados'],['ausencias','📅','Ausencias'],['planificacion','🗓️','Planificación']]
  : [['miFicha','🪪','Mi ficha'],['ausencias','📅','Ausencias'],['planificacion','🗓️','Planificación']];

 if(window.GamaHRP1)pestanas.push(...window.GamaHRP1.tabs());
 s.innerHTML=window.GamaUI.header({
   title:'🧑‍💼 Recursos humanos',
   lead:admin
     ? 'Empleados, ausencias y calendario del equipo.'
     : 'Tus datos, tus días y el calendario del equipo.'
 })
 +`<div class="hrTabs">${pestanas.map(([id,ico,txt])=>
    `<button type="button" class="${tab===id?'on':''}" data-tab="${id}"><span class="hrTabIco">${ico}</span> ${txt}</button>`).join('')}</div>`
 +(admin?kpis():'')
 +'<div id="hrMsg" class="hrMsg"></div>'
 +(tab==='empleados'?employeesTab()
  :tab==='ausencias'?(admin?absencesTab():myRequestsTab())
  :tab==='miFicha'?myCardTab()
  :tab==='planificacion'?planTab():window.GamaHRP1?.render(tab)||'');
 window.GamaHRP1?.decorate();
 bind();
 window.GamaHRP1?.bind(tab,load);
}

function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
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

function open(requestedTab){
 if(typeof requestedTab==='string')tab=requestedTab;
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

window.addEventListener('gama:auth-change',ev=>{const nextUid=ev.detail?.session?.user?.id||null;if(ev.detail?.event!=='SIGNED_OUT'&&(!myUid||nextUid===myUid))return;loadVersion++;employees=[];absences=[];mine=null;perfiles=[];myUid=null;editing=null;tab='empleados';if($('hr'))$('hr').innerHTML=''});
window.GamaHR={open,load};
window.GamaOpenHR=open;
})();
