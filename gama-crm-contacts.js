/* GAMA — CRM · Contactos.

   Las personas. Una empresa no compra: compra alguien de dentro, y casi nunca
   es quien contesta el teléfono. Por eso un contacto cuelga de UNA ficha —un
   cliente o un prospecto, nunca de los dos ni de ninguno (CHECK
   crm_contacts_uno_u_otro)— y lleva su papel en la decisión.

   Lo que esta pantalla hace cumplir porque la base lo exige:

   · Un solo contacto principal por ficha. Es un índice único parcial
     (is_primary AND active), así que marcar a otro sin quitar antes al de
     ahora lo rechazaría con un error de clave duplicada. Aquí se le quita
     primero, en el mismo gesto, y el usuario no se entera de que había un
     problema que resolver.

   · Un contacto necesita al menos nombre, apellidos o correo
     (crm_contacts_con_nombre).

   Archivar no libera al principal por casualidad: el índice sólo cuenta las
   filas activas, así que archivar al principal deja el puesto libre solo. */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] Contactos necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=CRM.esc;
const U=CRM.util;
const val=U.valor,nulo=U.nulo,norm=U.norm,terms=U.terms;
const campo=U.campo,opciones=U.opciones,msg=U.msg;
const fallo=(e,que)=>U.error(e,que,'Contactos');

const LEAD='Contactos: las personas de cada cliente y de cada prospecto, con su papel en la decisión.';
const LISTA=CRM.cols.contacts;
const FORM=LISTA+',linkedin,notes';
const CLIENTE_COLS='id,name,active';
const LEAD_COLS='id,company,first_name,last_name,active';

/* Los papeles del §7: quién decide, quién influye, quién lo va a usar y quién
   firma la orden de compra. Saber a quién se le habla es media venta. */
const PAPELES={decisor:'Decisor',prescriptor:'Prescriptor',usuario:'Usuario',comprador:'Comprador',otro:'Otro'};

let contactos=[],clientes=[],prospectos=[];
let vista='lista',abierto=null,busca='',filtro='',cargando=false;

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
 const [k,c,l]=await Promise.all([
  api.list('crm_contacts',{select:LISTA,order:'last_name',ascending:true}),
  api.list('customers',{select:CLIENTE_COLS,order:'name',ascending:true}),
  api.list('crm_leads',{select:LEAD_COLS,order:'company',ascending:true}),
 ]);
 if(k.error)throw k.error;
 contactos=k.data||[];
 clientes=c.error?[]:(c.data||[]);
 prospectos=l.error?[]:(l.data||[]);
 await quienSoy();
}

/* ---- presentación ---- */
function nombre(k){
 const n=[k.first_name,k.last_name].filter(Boolean).join(' ').trim();
 return n||String(k.email||'').trim()||'(sin nombre)';
}
function nombreLead(l){
 const p=[l.first_name,l.last_name].filter(Boolean).join(' ').trim();
 return String(l.company||'').trim()||p||'(sin nombre)';
}
/* De qué ficha cuelga. Una ficha archivada sigue teniendo sus contactos, así
   que se dice que está archivada en vez de dejar el hueco en blanco. */
function deQuien(k){
 if(k.customer_id){
  const x=clientes.find(c=>String(c.id)===String(k.customer_id));
  return {tipo:'cliente',etiqueta:'Cliente',nombre:x?x.name:'(cliente que ya no está)'};
 }
 const l=prospectos.find(p=>String(p.id)===String(k.lead_id));
 return {tipo:'prospecto',etiqueta:'Prospecto',nombre:l?nombreLead(l):'(prospecto que ya no está)'};
}
/* Sólo se ofrecen fichas activas para colgar un contacto nuevo; las archivadas
   conservan los suyos pero no reciben más. */
const clientesVivos=()=>clientes.filter(c=>c.active!==false);
const prospectosVivos=()=>prospectos.filter(p=>p.active!==false);

/* ---- lista ---- */
function visibles(){
 const arch=!!(window.GamaArchive&&window.GamaArchive.mode('crmContactos')==='archived');
 let r=contactos.filter(k=>(k.active===false)===arch);
 if(filtro==='cliente')r=r.filter(k=>!!k.customer_id);
 else if(filtro==='prospecto')r=r.filter(k=>!!k.lead_id);
 else if(filtro==='principal')r=r.filter(k=>!!k.is_primary);
 const t=terms(busca);
 if(t.length)r=r.filter(k=>{
  const h=norm([nombre(k),k.job_title,k.email,k.phone,deQuien(k).nombre].join(' '));
  return t.every(x=>h.includes(x));
 });
 return window.GamaSort?window.GamaSort.apply('crmContactos',r,{
  nombre:k=>nombre(k),
  cargo:k=>k.job_title||'',
  ficha:k=>deQuien(k).nombre,
  papel:k=>PAPELES[k.decision_role]||'',
  correo:k=>k.email||'',
 }):r;
}
function lista(){
 const nActivos=contactos.filter(k=>k.active!==false).length;
 const nArch=contactos.filter(k=>k.active===false).length;
 const filas=visibles();
 const pagina=window.GamaPage?window.GamaPage.slice('crmContactos',filas):filas;
 const hayFichas=clientesVivos().length||prospectosVivos().length;
 return '<div class="card">'
  +'<div class="crmBar">'
  +'<input id="crmKBusca" type="search" placeholder="Buscar por nombre, cargo, correo o ficha…" value="'+esc(busca)+'" aria-label="Buscar contactos">'
  +'<select id="crmKFiltro" data-gama-nofind aria-label="Filtrar contactos">'
   +'<option value="">Todos</option>'
   +'<option value="cliente"'+(filtro==='cliente'?' selected':'')+'>Sólo de clientes</option>'
   +'<option value="prospecto"'+(filtro==='prospecto'?' selected':'')+'>Sólo de prospectos</option>'
   +'<option value="principal"'+(filtro==='principal'?' selected':'')+'>Sólo los principales</option>'
  +'</select>'
  +'<button type="button" class="primary" id="crmKNuevo"'+(hayFichas?'':' disabled title="Primero hace falta un cliente o un prospecto"')+'>+ Nuevo contacto</button>'
  +'</div>'
  +(window.GamaArchive?window.GamaArchive.tabs('crmContactos',nActivos,nArch):'')
  +(filas.length?tabla(pagina):vacio(nActivos+nArch,hayFichas))
  +(window.GamaPage?window.GamaPage.controls('crmContactos',filas.length):'')
  +'</div>';
}
function vacio(total,hayFichas){
 return '<div class="crmVacio">'+(total?'Ningún contacto coincide con la búsqueda.'
  :hayFichas?'Todavía no hay contactos. Crea el primero con «+ Nuevo contacto».'
  :'Todavía no hay ni clientes ni prospectos a los que colgar un contacto. Empieza por 🤝 Prospectos o por 👥 Clientes.')+'</div>';
}
function tabla(rows){
 const th=(col,label)=>window.GamaSort?window.GamaSort.th('crmContactos',col,label):'<th>'+esc(label)+'</th>';
 return '<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
  +th('nombre','Contacto')+th('ficha','Ficha')+th('cargo','Cargo')
  +th('papel','Papel')+th('correo','Contacto directo')+'<th></th></tr></thead><tbody>'
  +rows.map(fila).join('')+'</tbody></table></div>';
}
function fila(k){
 const q=deQuien(k);
 return '<tr>'
  +'<td><b>'+esc(nombre(k))+'</b>'
   +(k.is_primary?'<small class="crmSub crmPrin">★ Principal</small>':'')+'</td>'
  +'<td><span class="crmEstado e-'+esc(q.tipo)+'">'+esc(q.etiqueta)+'</span>'
   +'<small class="crmSub">'+esc(q.nombre)+'</small></td>'
  +'<td>'+esc(k.job_title||'—')+'</td>'
  +'<td>'+(k.decision_role?'<span class="crmPri p-'+esc(k.decision_role)+'">'+esc(PAPELES[k.decision_role]||k.decision_role)+'</span>':'—')+'</td>'
  +'<td>'+(k.email?esc(k.email):'')+(k.email&&k.phone?'<small class="crmSub">'+esc(k.phone)+'</small>':k.phone?esc(k.phone):'')
   +(!k.email&&!k.phone?'—':'')+'</td>'
  +'<td class="crmAcc">'
   +'<button type="button" data-abrir="'+esc(k.id)+'">Abrir</button>'
   +(k.active!==false?'<button type="button" data-principal="'+esc(k.id)+'" title="'
     +(k.is_primary?'Dejar de ser el contacto principal':'Marcar como contacto principal')+'">'
     +(k.is_primary?'★':'☆')+'</button>':'')
   +(k.active!==false
     ?'<button type="button" data-archivar="'+esc(k.id)+'" title="Archivar contacto">🗄️</button>'
     :'<button type="button" data-restaurar="'+esc(k.id)+'" title="Restaurar contacto">↩︎</button>')
  +'</td></tr>';
}

/* ---- formulario ---- */
function nuevo(){return {decision_role:'',is_primary:false,active:true}}
function formulario(){
 const k=abierto||{};
 const esNuevo=!k.id;
 const tipo=k.lead_id?'prospecto':'cliente';
 const q=esNuevo?null:deQuien(k);
 return '<div class="card">'
  +'<h3>'+(esNuevo?'Nuevo contacto':esc(nombre(k)))+'</h3>'
  +(q?'<div class="crmAviso">'+esc(q.etiqueta)+': <b>'+esc(q.nombre)+'</b>.</div>':'')
  +'<div class="crmForm">'
   +'<div><label for="crmKTipo">Pertenece a</label><select id="crmKTipo" data-gama-nofind>'
    +'<option value="cliente"'+(tipo==='cliente'?' selected':'')+'>Un cliente</option>'
    +'<option value="prospecto"'+(tipo==='prospecto'?' selected':'')+'>Un prospecto</option>'
   +'</select></div>'
   /* Los dos desplegables se pintan siempre y se enseña el que toca. Repintar
      al cambiar de tipo le borraría al usuario lo que acabara de escribir, y
      el buscador de listas largas se cuelga del padre del select, así que
      esconder el envoltorio esconde los dos a la vez. */
   +'<div id="crmKCajaCliente"'+(tipo==='cliente'?'':' hidden')+'>'
    +'<label for="crmKCliente">Cliente</label><select id="crmKCliente">'
    +opciones(clientesVivos().map(c=>[c.id,c.name]),k.customer_id,'— elige un cliente —')+'</select></div>'
   +'<div id="crmKCajaProspecto"'+(tipo==='prospecto'?'':' hidden')+'>'
    +'<label for="crmKProspecto">Prospecto</label><select id="crmKProspecto">'
    +opciones(prospectosVivos().map(p=>[p.id,nombreLead(p)]),k.lead_id,'— elige un prospecto —')+'</select></div>'
   +campo('crmKFirst','Nombre',k.first_name)
   +campo('crmKLast','Apellidos',k.last_name)
   +campo('crmKJob','Cargo',k.job_title)
   +campo('crmKEmail','Correo',k.email,'email')
   +campo('crmKPhone','Teléfono',k.phone,'tel')
   +campo('crmKLinkedin','LinkedIn',k.linkedin)
   +'<div><label for="crmKRol">Papel en la decisión</label><select id="crmKRol" data-gama-nofind>'
    +opciones(Object.keys(PAPELES).map(x=>[x,PAPELES[x]]),k.decision_role,'— sin definir —')+'</select></div>'
  +'</div>'
  +'<div class="crmCheck"><label><input type="checkbox" id="crmKPrincipal"'+(k.is_primary?' checked':'')+'> '
   +'Es el contacto principal de esta ficha</label>'
   +'<small>Sólo puede haber uno. Si ya hay otro, deja de serlo automáticamente.</small></div>'
  +'<div class="crmNotas"><label for="crmKNotes">Notas</label><textarea id="crmKNotes" rows="4">'+esc(k.notes||'')+'</textarea></div>'
  +'<div class="crmAcciones">'
   +'<button type="button" class="primary" id="crmKGuardar">Guardar</button>'
   +'<button type="button" id="crmKCancelar">Cancelar</button>'
  +'</div></div>';
}
function leerFormulario(){
 const tipo=val('crmKTipo')||'cliente';
 const quien=tipo==='cliente'?val('crmKCliente'):val('crmKProspecto');
 if(!quien){msg(tipo==='cliente'?'Elige el cliente al que pertenece el contacto.':'Elige el prospecto al que pertenece el contacto.','err');return null}
 const d={
  /* Uno u otro, nunca los dos: el que no toca se pone a null explícitamente,
     porque al cambiar de ficha hay que borrar el enlace anterior. */
  customer_id:tipo==='cliente'?quien:null,
  lead_id:tipo==='cliente'?null:quien,
  first_name:nulo(val('crmKFirst')),
  last_name:nulo(val('crmKLast')),
  job_title:nulo(val('crmKJob')),
  email:nulo(val('crmKEmail')),
  phone:nulo(val('crmKPhone')),
  linkedin:nulo(val('crmKLinkedin')),
  decision_role:nulo(val('crmKRol')),
  notes:nulo(val('crmKNotes')),
  is_primary:!!($('crmKPrincipal')&&$('crmKPrincipal').checked),
 };
 if(!(d.last_name||d.first_name||d.email)){
  msg('Un contacto necesita al menos un nombre, unos apellidos o un correo.','err');return null;
 }
 return d;
}

/* ---- acciones ---- */
/* El índice único parcial sólo deja un principal activo por ficha. Se le quita
   al de ahora ANTES de poner al nuevo; si no, Postgres rechaza el guardado con
   un mensaje de clave duplicada que no le dice nada a nadie. */
async function liberarPrincipal(donde,exceptoId){
 const filtro=donde.customer_id?{customer_id:donde.customer_id}:{lead_id:donde.lead_id};
 const r=await C().list('crm_contacts',{select:'id',eq:Object.assign({is_primary:true,active:true},filtro)});
 if(r.error)throw r.error;
 for(const fila of (r.data||[])){
  if(String(fila.id)===String(exceptoId||''))continue;
  const u=await C().update('crm_contacts',fila.id,{is_primary:false});
  if(u.error)throw u.error;
 }
}
async function abrir(id){
 try{
  const r=await C().list('crm_contacts',{select:FORM,eq:{id:id},limit:1});
  if(r.error)throw r.error;
  const k=(r.data||[])[0];
  if(!k){msg('Ese contacto ya no existe.','err');return}
  abierto=k;vista='ficha';pintar();
 }catch(e){fallo(e,'No se pudo abrir el contacto')}
}
async function guardar(){
 const d=leerFormulario();
 if(!d)return;
 try{
  if(d.is_primary)await liberarPrincipal(d,abierto&&abierto.id);
  let r;
  if(abierto&&abierto.id)r=await C().update('crm_contacts',abierto.id,d);
  else{d.created_by=await quienSoy();d.active=true;r=await C().insert('crm_contacts',d)}
  if(r.error)throw r.error;
  await cargar();
  vista='lista';abierto=null;
  pintar('Contacto guardado.','ok');
 }catch(e){fallo(e,'No se pudo guardar el contacto')}
}
async function alternarPrincipal(id){
 const k=contactos.find(x=>String(x.id)===String(id));
 if(!k)return;
 try{
  if(!k.is_primary)await liberarPrincipal(k,id);
  const r=await C().update('crm_contacts',id,{is_primary:!k.is_primary});
  if(r.error)throw r.error;
  await cargar();
  pintar(k.is_primary?'Ya no es el contacto principal.':'Marcado como contacto principal.','ok');
 }catch(e){fallo(e,'No se pudo cambiar el contacto principal')}
}
/* Archivar y no borrar, como en el resto de GAMA. Aquí además tiene un efecto
   útil: el índice del principal sólo cuenta filas activas, así que archivar al
   principal deja el puesto libre sin tener que desmarcarlo antes. */
async function archivar(id,activo){
 try{
  const r=await C().update('crm_contacts',id,{active:activo});
  if(r.error)throw r.error;
  await cargar();
  pintar(activo?'Contacto restaurado.':'Contacto archivado.','ok');
 }catch(e){fallo(e,'No se pudo archivar el contacto')}
}

/* ---- pintar y conectar ---- */
function pintar(aviso,tipo){
 const s=CRM.section();
 s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>'
  +(vista==='ficha'?formulario():lista());
 CRM.bind(s);
 conectar();
 if(aviso)msg(aviso,tipo);
}
function conectar(){
 const s=CRM.section();
 const b=$('crmKBusca');
 if(b)b.oninput=()=>{
  busca=b.value;
  if(window.GamaPage)window.GamaPage.reset('crmContactos');
  pintar();
  const n=$('crmKBusca');
  if(n){n.focus();try{n.setSelectionRange(n.value.length,n.value.length)}catch(e){}}
 };
 const f=$('crmKFiltro');
 if(f)f.onchange=()=>{filtro=f.value;if(window.GamaPage)window.GamaPage.reset('crmContactos');pintar()};
 const nv=$('crmKNuevo');
 if(nv)nv.onclick=()=>{abierto=nuevo();vista='ficha';pintar()};
 const t=$('crmKTipo');
 if(t)t.onchange=()=>{
  const cli=t.value==='cliente';
  const a=$('crmKCajaCliente'),b2=$('crmKCajaProspecto');
  if(a)a.hidden=!cli;
  if(b2)b2.hidden=cli;
 };
 s.querySelectorAll('[data-abrir]').forEach(x=>{x.onclick=()=>abrir(x.dataset.abrir)});
 s.querySelectorAll('[data-principal]').forEach(x=>{x.onclick=()=>alternarPrincipal(x.dataset.principal)});
 s.querySelectorAll('[data-archivar]').forEach(x=>{x.onclick=()=>archivar(x.dataset.archivar,false)});
 s.querySelectorAll('[data-restaurar]').forEach(x=>{x.onclick=()=>archivar(x.dataset.restaurar,true)});
 const g=$('crmKGuardar');if(g)g.onclick=guardar;
 const c=$('crmKCancelar');if(c)c.onclick=()=>{vista='lista';abierto=null;pintar()};
}
function css(){
 if($('crmContactosCss'))return;
 const s=document.createElement('style');s.id='crmContactosCss';
 /* Casi todo lo visual lo pone ya la hoja de Prospectos, que es la misma
    lista con la misma barra. Aquí sólo va lo propio de esta pantalla. */
 s.textContent='#crm [hidden]{display:none!important}'
 +'#crm .crmPrin{color:#b8860b;font-weight:800}'
 +'#crm .crmEstado.e-cliente{background:#e7f6f0;color:#12795c}'
 +'#crm .crmEstado.e-prospecto{background:#e4f1fb;color:#1b5f8c}'
 +'#crm .crmPri.p-decisor{background:#fdefe4;color:#9a5314}'
 +'#crm .crmPri.p-comprador{background:#eef3f4;color:#4c5c68}'
 +'#crm .crmCheck{margin-top:12px;font-size:13px}'
 +'#crm .crmCheck input{width:auto;margin-right:7px;min-height:0}'
 +'#crm .crmCheck label{display:flex;align-items:center;font-weight:700;color:#18324a}'
 +'#crm .crmCheck small{display:block;color:#7b8992;font-size:11.5px;margin-top:3px}';
 document.head.appendChild(s);
}

async function abrirPantalla(){
 CRM.css();css();
 const s=CRM.section();
 if(cargando)return;cargando=true;
 s.innerHTML=CRM.cabecera(LEAD)+'<div class="card"><div class="crmVacio">Cargando contactos…</div></div>';
 CRM.bind(s);
 try{
  await cargar();
  vista='lista';abierto=null;
  pintar();
 }catch(e){
  s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>';
  CRM.bind(s);
  fallo(e,'No se pudieron cargar los contactos');
 }finally{cargando=false}
 window.scrollTo({top:0,behavior:'smooth'});
}

if(window.GamaPage)window.GamaPage.register('crmContactos',()=>pintar());
if(window.GamaSort)window.GamaSort.register('crmContactos',()=>pintar());
if(window.GamaArchive)window.GamaArchive.register('crmContactos',()=>pintar());
CRM.registrar('contactos','Contactos',abrirPantalla);
window.GamaCRMContacts={open:abrirPantalla};
})();
