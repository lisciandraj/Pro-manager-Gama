/* GAMA — CRM · Actividades.

   Llamadas, correos, reuniones, tareas, notas, visitas, demostraciones y
   seguimientos: UNA tabla para todo. Por debajo son lo mismo —algo que pasó o
   que tiene que pasar, con fecha y con alguien—, y separarlas obligaría a unir
   cuatro tablas para pintar UNA línea de tiempo, que es el objeto central de un
   CRM: qué se ha hecho con este cliente y qué falta por hacer.

   Dos pantallas sobre los mismos datos, porque son dos preguntas distintas:

   · Agenda — lo que queda por hacer, ordenado por cuándo vence. Lo vencido
     arriba y en rojo. Es la pantalla de la mañana.
   · Historia — todo lo ocurrido, lo último primero, agrupado por día. Es la
     pantalla de «¿qué pasó con este cliente?».

   Reglas de la base que esta pantalla hace cumplir:

   · Una actividad cuelga de algo (crm_act_colgada_de_algo): de un cliente, un
     prospecto, una oportunidad o un contacto. Una nota que no cuelga de nadie
     no se puede volver a encontrar.

   · Una tarea PENDIENTE exige fecha (crm_act_pendiente_con_fecha). Sin fecha no
     es una tarea, es un deseo — y además no aparecería en la agenda ni contaría
     como vencida en el cuadro de mando.

   Aquí no se borra: se cancela. Una llamada que no se hizo es un dato, no un
   error que tapar. */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] Actividades necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=CRM.esc;
const U=CRM.util;
const val=U.valor,nulo=U.nulo,norm=U.norm,terms=U.terms;
const campo=U.campo,opciones=U.opciones,msg=U.msg;
const paraInput=U.paraInput,desdeInput=U.desdeInput;
const fallo=(e,que)=>U.error(e,que,'Actividades');

const LEAD='Actividades: lo que se ha hecho y lo que falta por hacer, con cada cliente y cada oportunidad.';
const LISTA=CRM.cols.activities;
const FORM=LISTA+',body,remind_at,customer_request_id';

const TIPOS={llamada:'Llamada',correo:'Correo',reunion:'Reunión',visita:'Visita',
 demostracion:'Demostración',tarea:'Tarea',seguimiento:'Seguimiento',nota:'Nota'};
const ICONO={llamada:'📞',correo:'✉️',reunion:'👥',visita:'🚗',demostracion:'🖥️',
 tarea:'✅',seguimiento:'🔁',nota:'📝'};
const ESTADOS={pendiente:'Pendiente',en_curso:'En curso',hecha:'Hecha',cancelada:'Cancelada'};
const ABIERTAS=['pendiente','en_curso'];
const PRIORIDADES={baja:'Baja',media:'Media',alta:'Alta'};
/* Una tarea o un seguimiento nacen por hacer; una llamada o una nota se
   apuntan porque ya ocurrieron. El estado por defecto sigue al tipo en vez de
   obligar a corregirlo cada vez. */
const PENDIENTE_POR_DEFECTO=['tarea','seguimiento'];

/* De qué puede colgar una actividad. invoice_id y customer_request_id existen
   en la tabla y los respeta el CHECK, pero no se ofrecen aquí: se rellenan
   desde Presupuestos y desde Solicitudes, que es donde el usuario está cuando
   tienen sentido. */
const ANCLAS={cliente:'Un cliente',prospecto:'Un prospecto',oportunidad:'Una oportunidad',contacto:'Un contacto'};

let actos=[],clientes=[],prospectos=[],oportunidades=[],contactos=[],gente=[];
let vista='agenda',abierto=null,busca='',filtroTipo='',soloMias=false,cargando=false;

let mi;
async function quienSoy(){
 if(mi!==undefined)return mi;
 try{const s=await C().getSession();mi=(s&&s.data&&s.data.session&&s.data.session.user&&s.data.session.user.id)||null}
 catch(e){mi=null}
 return mi;
}

/* ---- datos ---- */
async function cargar(){
 const api=C();
 if(!api)throw new Error('La conexión con la nube de GAMA no está disponible.');
 const [a,c,l,o,k,g]=await Promise.all([
  api.list('crm_activities',{select:LISTA,order:'created_at',ascending:false}),
  api.list('customers',{select:'id,name,active',order:'name',ascending:true}),
  api.list('crm_leads',{select:'id,company,first_name,last_name,active',order:'company',ascending:true}),
  api.list('crm_opportunities',{select:'id,reference,title,active',order:'created_at',ascending:false}),
  api.list('crm_contacts',{select:'id,first_name,last_name,customer_id,lead_id,active'}),
  CRM.comerciales(),
 ]);
 if(a.error)throw a.error;
 actos=a.data||[];
 clientes=c.error?[]:(c.data||[]);
 prospectos=l.error?[]:(l.data||[]);
 oportunidades=o.error?[]:(o.data||[]);
 contactos=k.error?[]:(k.data||[]);
 gente=g||[];
 await quienSoy();
}

/* ---- presentación ---- */
function nombreLead(l){
 const p=[l.first_name,l.last_name].filter(Boolean).join(' ').trim();
 return String(l.company||'').trim()||p||'(sin nombre)';
}
function nombreContacto(k){
 const n=[k.first_name,k.last_name].filter(Boolean).join(' ').trim();
 return n||'(sin nombre)';
}
/* De qué cuelga. Se mira en el orden en que un comercial lo entendería: la
   oportunidad manda sobre el cliente, porque decir «Estanterías bodega» dice
   más que decir «Ferretería Central». */
function ancla(a){
 if(a.opportunity_id){
  const o=oportunidades.find(x=>String(x.id)===String(a.opportunity_id));
  return {tipo:'oportunidad',etiqueta:'Oportunidad',nombre:o?(o.reference+' · '+o.title):'(oportunidad que ya no está)'};
 }
 if(a.customer_id){
  const c=clientes.find(x=>String(x.id)===String(a.customer_id));
  return {tipo:'cliente',etiqueta:'Cliente',nombre:c?c.name:'(cliente que ya no está)'};
 }
 if(a.lead_id){
  const l=prospectos.find(x=>String(x.id)===String(a.lead_id));
  return {tipo:'prospecto',etiqueta:'Prospecto',nombre:l?nombreLead(l):'(prospecto que ya no está)'};
 }
 if(a.contact_id){
  const k=contactos.find(x=>String(x.id)===String(a.contact_id));
  return {tipo:'contacto',etiqueta:'Contacto',nombre:k?nombreContacto(k):'(contacto que ya no está)'};
 }
 return {tipo:'',etiqueta:'Sin ficha',nombre:'—'};
}
const abierta=a=>ABIERTAS.includes(String(a.status));
function vencida(a){
 return abierta(a)&&!!a.due_at&&new Date(a.due_at).getTime()<Date.now();
}
function cuando(iso){
 if(!iso)return 'sin fecha';
 const d=new Date(iso);
 if(isNaN(d.getTime()))return 'sin fecha';
 return d.toLocaleString('es-EC',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'});
}
function dia(iso){
 const d=new Date(iso);
 if(isNaN(d.getTime()))return 'Sin fecha';
 const hoy=new Date(),ayer=new Date(Date.now()-86400000);
 const mismo=(a,b)=>a.getFullYear()===b.getFullYear()&&a.getMonth()===b.getMonth()&&a.getDate()===b.getDate();
 if(mismo(d,hoy))return 'Hoy';
 if(mismo(d,ayer))return 'Ayer';
 return d.toLocaleDateString('es-EC',{weekday:'long',day:'2-digit',month:'long',year:'numeric'});
}

/* ---- listas ---- */
function coincide(a){
 if(filtroTipo&&String(a.kind)!==filtroTipo)return false;
 if(soloMias&&String(a.owner_id||'')!==String(mi||''))return false;
 const t=terms(busca);
 if(!t.length)return true;
 const h=norm([a.subject,TIPOS[a.kind],ancla(a).nombre,CRM.nombreDe(a.owner_id,gente)].join(' '));
 return t.every(x=>h.includes(x));
}
function barra(){
 return '<div class="crmBar">'
  +'<input id="crmABusca" type="search" placeholder="Buscar por asunto, ficha o responsable…" value="'+esc(busca)+'" aria-label="Buscar actividades">'
  +'<select id="crmATipo" data-gama-nofind aria-label="Filtrar por tipo"><option value="">Todos los tipos</option>'
   +Object.keys(TIPOS).map(k=>'<option value="'+k+'"'+(filtroTipo===k?' selected':'')+'>'+esc(TIPOS[k])+'</option>').join('')
  +'</select>'
  +'<button type="button" class="primary" id="crmANueva">+ Nueva actividad</button>'
  +'</div>'
  +'<div class="crmNav crmSubNav">'
   +'<button type="button" class="'+(vista==='agenda'?'on':'')+'" data-vista="agenda">Agenda</button>'
   +'<button type="button" class="'+(vista==='historia'?'on':'')+'" data-vista="historia">Historia</button>'
   +'<button type="button" class="'+(soloMias?'on':'')+'" id="crmAMias">Sólo las mías</button>'
  +'</div>';
}
function agenda(){
 const filas=actos.filter(a=>abierta(a)&&coincide(a))
  .sort((x,y)=>String(x.due_at||'9999').localeCompare(String(y.due_at||'9999')));
 const tarde=filas.filter(vencida).length;
 return '<div class="card">'
  +(tarde?'<div class="crmAviso crmDup"><b>'+tarde+'</b> actividad(es) vencida(s). Son las de arriba.</div>':'')
  +(filas.length?'<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
    +'<th>Actividad</th><th>Ficha</th><th>Vence</th><th>Responsable</th><th></th></tr></thead><tbody>'
    +filas.map(filaAgenda).join('')+'</tbody></table></div>'
   :'<div class="crmVacio">'+(actos.length?'Nada pendiente que coincida con el filtro.':'Nada pendiente. Cuando haya una tarea o un seguimiento, aparecerá aquí ordenado por fecha.')+'</div>')
  +'</div>';
}
function filaAgenda(a){
 const q=ancla(a);
 return '<tr class="'+(vencida(a)?'crmFilaTarde':'')+'">'
  +'<td><b>'+esc((ICONO[a.kind]||'•')+' '+a.subject)+'</b>'
   +'<small class="crmSub">'+esc(TIPOS[a.kind]||a.kind)+' · '+esc(ESTADOS[a.status]||a.status)+'</small></td>'
  +'<td><span class="crmEstado e-'+esc(q.tipo)+'">'+esc(q.etiqueta)+'</span>'
   +'<small class="crmSub">'+esc(q.nombre)+'</small></td>'
  +'<td>'+esc(cuando(a.due_at))+(vencida(a)?' <span class="crmTarde">vencida</span>':'')+'</td>'
  +'<td>'+esc(CRM.nombreDe(a.owner_id,gente))+'</td>'
  +'<td class="crmAcc">'
   +'<button type="button" class="primary" data-hecha="'+esc(a.id)+'">Hecha</button>'
   +'<button type="button" data-abrir="'+esc(a.id)+'">Abrir</button>'
   +'<button type="button" data-cancelar="'+esc(a.id)+'" title="Cancelar la actividad">✕</button>'
  +'</td></tr>';
}
function historia(){
 const filas=actos.filter(coincide);
 if(!filas.length)return '<div class="card"><div class="crmVacio">'
  +(actos.length?'Ninguna actividad coincide con el filtro.':'Todavía no hay ninguna actividad apuntada.')+'</div></div>';
 /* Agrupada por día: una lista plana de trescientas líneas no se lee, y lo que
    se busca casi siempre es «qué pasó tal día». */
 const grupos=[];
 filas.forEach(a=>{
  const d=dia(a.created_at);
  const g=grupos.find(x=>x.dia===d);
  if(g)g.filas.push(a);else grupos.push({dia:d,filas:[a]});
 });
 return '<div class="card">'+grupos.map(g=>
  '<div class="crmDia"><h4>'+esc(g.dia)+'</h4>'
  +g.filas.map(hito).join('')+'</div>').join('')+'</div>';
}
function hito(a){
 const q=ancla(a);
 return '<div class="crmHito'+(a.status==='cancelada'?' cancelada':'')+'" data-abrir="'+esc(a.id)+'">'
  +'<div class="crmHitoIco" aria-hidden="true">'+(ICONO[a.kind]||'•')+'</div>'
  +'<div class="crmHitoCuerpo">'
   +'<b>'+esc(a.subject)+'</b>'
   +'<small class="crmSub">'+esc(TIPOS[a.kind]||a.kind)+' · '+esc(q.etiqueta)+' '+esc(q.nombre)+'</small>'
   +'<small class="crmSub">'+esc(CRM.nombreDe(a.owner_id,gente))+' · '+esc(cuando(a.created_at))+'</small>'
  +'</div>'
  +'<span class="crmEstado s-'+esc(a.status)+'">'+esc(ESTADOS[a.status]||a.status)+'</span>'
  +'</div>';
}

/* ---- ficha ---- */
function nueva(){
 return {kind:'llamada',status:'hecha',priority:'media',owner_id:mi||null};
}
function anclaDe(a){
 if(a.opportunity_id)return 'oportunidad';
 if(a.customer_id)return 'cliente';
 if(a.lead_id)return 'prospecto';
 if(a.contact_id)return 'contacto';
 return 'cliente';
}
function listaAncla(tipo){
 if(tipo==='oportunidad')return oportunidades.filter(o=>o.active!==false).map(o=>[o.id,o.reference+' · '+o.title]);
 if(tipo==='prospecto')return prospectos.filter(p=>p.active!==false).map(p=>[p.id,nombreLead(p)]);
 if(tipo==='contacto')return contactos.filter(k=>k.active!==false).map(k=>[k.id,nombreContacto(k)]);
 return clientes.filter(c=>c.active!==false).map(c=>[c.id,c.name]);
}
function idAncla(a,tipo){
 return tipo==='oportunidad'?a.opportunity_id:tipo==='prospecto'?a.lead_id
  :tipo==='contacto'?a.contact_id:a.customer_id;
}
function ficha(){
 const a=abierto||{};
 const esNueva=!a.id;
 const tipo=anclaDe(a);
 return '<div class="card">'
  +'<h3>'+(esNueva?'Nueva actividad':esc(a.subject||''))+'</h3>'
  +'<div class="crmForm">'
   +'<div><label for="crmAKind">Tipo</label><select id="crmAKind" data-gama-nofind>'
    +Object.keys(TIPOS).map(k=>'<option value="'+k+'"'+((a.kind||'llamada')===k?' selected':'')+'>'+esc(TIPOS[k])+'</option>').join('')
   +'</select></div>'
   +campo('crmASubject','Asunto',a.subject)
   +'<div><label for="crmAAncla">Cuelga de</label><select id="crmAAncla" data-gama-nofind>'
    +Object.keys(ANCLAS).map(k=>'<option value="'+k+'"'+(tipo===k?' selected':'')+'>'+esc(ANCLAS[k])+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmAQuien">Ficha</label><select id="crmAQuien">'
    +opciones(listaAncla(tipo),idAncla(a,tipo),'— elige una ficha —')+'</select></div>'
   +'<div><label for="crmAStatus">Estado</label><select id="crmAStatus" data-gama-nofind>'
    +Object.keys(ESTADOS).map(k=>'<option value="'+k+'"'+((a.status||'hecha')===k?' selected':'')+'>'+esc(ESTADOS[k])+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmAPri">Prioridad</label><select id="crmAPri" data-gama-nofind>'
    +Object.keys(PRIORIDADES).map(k=>'<option value="'+k+'"'+((a.priority||'media')===k?' selected':'')+'>'+esc(PRIORIDADES[k])+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmAResp">Responsable</label><select id="crmAResp">'
    +opciones(gente.map(p=>[p.id,p.full_name||p.email]),a.owner_id)+'</select></div>'
   +'<div><label for="crmADue">Vence</label><input id="crmADue" type="datetime-local" value="'+esc(paraInput(a.due_at))+'">'
    +'<small class="crmSub" id="crmADueNota"></small></div>'
   +'<div><label for="crmARemind">Recordar</label><input id="crmARemind" type="datetime-local" value="'+esc(paraInput(a.remind_at))+'"></div>'
  +'</div>'
  +'<div class="crmNotas"><label for="crmABody">Detalle</label><textarea id="crmABody" rows="4">'+esc(a.body||'')+'</textarea></div>'
  +'<div class="crmAcciones">'
   +'<button type="button" class="primary" id="crmAGuardar">Guardar</button>'
   +'<button type="button" id="crmACancelarF">Cancelar</button>'
   +(esNueva||!abierta(a)?'':'<button type="button" id="crmAHecha">Marcar como hecha</button>')
  +'</div></div>';
}
function leerFicha(){
 const asunto=val('crmASubject');
 if(!asunto){msg('La actividad necesita un asunto.','err');return null}
 const tipo=val('crmAAncla')||'cliente';
 const quien=val('crmAQuien');
 /* crm_act_colgada_de_algo: sin ficha no hay actividad. Una nota que no cuelga
    de nadie no se puede volver a encontrar. */
 if(!quien){msg('Elige la ficha de la que cuelga la actividad.','err');return null}
 const estado=val('crmAStatus')||'hecha';
 const vence=desdeInput(val('crmADue'));
 /* crm_act_pendiente_con_fecha: sin fecha no es una tarea, es un deseo — y no
    aparecería en la agenda ni contaría como vencida en el cuadro de mando. */
 if(estado==='pendiente'&&!vence){msg('Una actividad pendiente necesita una fecha de vencimiento.','err');return null}
 const d={
  kind:val('crmAKind')||'llamada',
  subject:asunto,
  body:nulo(val('crmABody')),
  status:estado,
  priority:val('crmAPri')||'media',
  owner_id:nulo(val('crmAResp')),
  due_at:vence,
  remind_at:desdeInput(val('crmARemind')),
  /* Uno solo: cambiar de ficha tiene que borrar el enlace anterior, o la
     actividad acabaría colgando de dos sitios a la vez. */
  customer_id:tipo==='cliente'?quien:null,
  lead_id:tipo==='prospecto'?quien:null,
  opportunity_id:tipo==='oportunidad'?quien:null,
  contact_id:tipo==='contacto'?quien:null,
  done_at:estado==='hecha'?((abierto&&abierto.done_at)||new Date().toISOString()):null,
 };
 return d;
}

/* ---- acciones ---- */
async function abrir(id){
 try{
  const r=await C().list('crm_activities',{select:FORM,eq:{id:id},limit:1});
  if(r.error)throw r.error;
  const a=(r.data||[])[0];
  if(!a){msg('Esa actividad ya no existe.','err');return}
  abierto=a;pintar();
 }catch(e){fallo(e,'No se pudo abrir la actividad')}
}
async function guardar(){
 const d=leerFicha();
 if(!d)return;
 try{
  let r;
  if(abierto&&abierto.id)r=await C().update('crm_activities',abierto.id,d);
  else{d.created_by=await quienSoy();r=await C().insert('crm_activities',d)}
  if(r.error)throw r.error;
  await cargar();
  abierto=null;
  pintar('Actividad guardada.','ok');
 }catch(e){fallo(e,'No se pudo guardar la actividad')}
}
async function marcarHecha(id){
 try{
  const r=await C().update('crm_activities',id,{status:'hecha',done_at:new Date().toISOString()});
  if(r.error)throw r.error;
  await cargar();
  abierto=null;
  pintar('Actividad marcada como hecha.','ok');
 }catch(e){fallo(e,'No se pudo marcar como hecha')}
}
/* Cancelar y no borrar: una llamada que no se hizo es un dato, no un error que
   tapar. Además el CHECK de pendiente exige fecha, y «cancelada» no. */
async function cancelar(id){
 try{
  const r=await C().update('crm_activities',id,{status:'cancelada',done_at:null});
  if(r.error)throw r.error;
  await cargar();
  pintar('Actividad cancelada. Sigue en la historia.','ok');
 }catch(e){fallo(e,'No se pudo cancelar la actividad')}
}

/* ---- pintar y conectar ---- */
function pintar(aviso,tipo){
 const s=CRM.section();
 s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>'
  +(abierto?ficha():barra()+(vista==='historia'?historia():agenda()));
 CRM.bind(s);
 conectar();
 if(aviso)msg(aviso,tipo);
}
function conectar(){
 const s=CRM.section();
 const b=$('crmABusca');
 if(b)b.oninput=()=>{
  busca=b.value;pintar();
  const n=$('crmABusca');
  if(n){n.focus();try{n.setSelectionRange(n.value.length,n.value.length)}catch(e){}}
 };
 const t=$('crmATipo');if(t)t.onchange=()=>{filtroTipo=t.value;pintar()};
 const m=$('crmAMias');if(m)m.onclick=()=>{soloMias=!soloMias;pintar()};
 s.querySelectorAll('[data-vista]').forEach(x=>{x.onclick=()=>{vista=x.dataset.vista;pintar()}});
 const nv=$('crmANueva');if(nv)nv.onclick=()=>{abierto=nueva();pintar()};
 /* Ningún elemento con data-abrir contiene otro botón —en la agenda ES el
    botón, y en la historia el hito no lleva ninguno—, así que no hace falta
    distinguir dónde se pulsó. */
 s.querySelectorAll('[data-abrir]').forEach(x=>{x.onclick=()=>abrir(x.dataset.abrir)});
 s.querySelectorAll('[data-hecha]').forEach(x=>{x.onclick=e=>{e.stopPropagation();marcarHecha(x.dataset.hecha)}});
 s.querySelectorAll('[data-cancelar]').forEach(x=>{x.onclick=e=>{e.stopPropagation();cancelar(x.dataset.cancelar)}});
 /* El desplegable de fichas depende del tipo de ancla, así que se rehace solo
    en vez de repintar y perder lo escrito. */
 const an=$('crmAAncla');
 if(an)an.onchange=()=>{
  const sel=$('crmAQuien');
  if(sel)sel.innerHTML=opciones(listaAncla(an.value),'','— elige una ficha —');
 };
 /* El tipo sugiere el estado: una tarea nace por hacer, una llamada se apunta
    porque ya ocurrió. Sigue pudiéndose cambiar a mano. */
 const kd=$('crmAKind');
 if(kd)kd.onchange=()=>{
  const st=$('crmAStatus');
  if(st&&(!abierto||!abierto.id))st.value=PENDIENTE_POR_DEFECTO.includes(kd.value)?'pendiente':'hecha';
  notaFecha();
 };
 const st=$('crmAStatus');if(st)st.onchange=notaFecha;
 const g=$('crmAGuardar');if(g)g.onclick=guardar;
 const c=$('crmACancelarF');if(c)c.onclick=()=>{abierto=null;pintar()};
 const h=$('crmAHecha');if(h)h.onclick=()=>marcarHecha(abierto.id);
 notaFecha();
}
function notaFecha(){
 const st=$('crmAStatus'),n=$('crmADueNota');
 if(!st||!n)return;
 n.textContent=st.value==='pendiente'?'Obligatoria mientras esté pendiente.':'';
}
function css(){
 if($('crmActCss'))return;
 const s=document.createElement('style');s.id='crmActCss';
 s.textContent='#crm .crmSubNav{margin:0 0 12px}'
 +'#crm .crmSubNav button{min-height:38px;padding:7px 14px;font-size:12.5px}'
 +'#crm .crmFilaTarde td{background:#fff7f5}'
 +'#crm .crmEstado.e-cliente{background:#e7f6f0;color:#12795c}'
 +'#crm .crmEstado.e-prospecto{background:#e4f1fb;color:#1b5f8c}'
 +'#crm .crmEstado.e-oportunidad{background:#fdefe4;color:#9a5314}'
 +'#crm .crmEstado.e-contacto{background:#f1eefb;color:#5b4a9a}'
 +'#crm .crmEstado.s-pendiente{background:#fdefe4;color:#9a5314}'
 +'#crm .crmEstado.s-en_curso{background:#e4f1fb;color:#1b5f8c}'
 +'#crm .crmEstado.s-hecha{background:#e7f6f0;color:#12795c}'
 +'#crm .crmEstado.s-cancelada{background:#f2f5f6;color:#8a97a0}'
 +'#crm .crmDia{margin-bottom:14px}'
 +'#crm .crmDia h4{margin:0 0 8px;font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:#71808a}'
 +'#crm .crmHito{display:flex;gap:10px;align-items:flex-start;padding:10px;border:1px solid #edf1f2;border-radius:10px;margin-bottom:7px;cursor:pointer;background:#fff}'
 +'#crm .crmHito:hover{border-color:#087c8b}'
 +'#crm .crmHito.cancelada{opacity:.6}'
 +'#crm .crmHito.cancelada b{text-decoration:line-through}'
 +'#crm .crmHitoIco{font-size:17px;line-height:1.2;flex:0 0 auto}'
 +'#crm .crmHitoCuerpo{flex:1 1 auto;min-width:0}'
 +'#crm .crmHitoCuerpo b{display:block;font-size:13px;color:#18324a}'
 +'@media(max-width:760px){#crm .crmHito{flex-wrap:wrap}}';
 document.head.appendChild(s);
}

async function abrirPantalla(){
 CRM.css();css();
 const s=CRM.section();
 if(cargando)return;cargando=true;
 s.innerHTML=CRM.cabecera(LEAD)+'<div class="card"><div class="crmVacio">Cargando la agenda…</div></div>';
 CRM.bind(s);
 try{
  await cargar();
  abierto=null;
  pintar();
 }catch(e){
  s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>';
  CRM.bind(s);
  fallo(e,'No se pudieron cargar las actividades');
 }finally{cargando=false}
 window.scrollTo({top:0,behavior:'smooth'});
}

CRM.registrar('actividades','Actividades',abrirPantalla);
window.GamaCRMActivities={open:abrirPantalla};
})();
