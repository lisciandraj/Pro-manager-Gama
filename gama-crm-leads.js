/* GAMA — CRM · Prospectos.

   Un prospecto es lo que TODAVÍA no es un cliente: alguien que llamó, una
   empresa que pidió precio, una tarjeta de una feria. Vive en crm_leads y no
   en customers a propósito — mezclarlos llenaría la ficha de Clientes de
   gente a la que nunca se le facturó nada, y las tarifas, los presupuestos y
   el catálogo trabajan sobre esa tabla.

   El puente entre las dos es la conversión: se crea el cliente de verdad y el
   prospecto guarda a cuál apunta. Así no se pierde de dónde salió ni cuánto
   costó ganarlo, y no hay dos fichas de la misma empresa.

   Tres cosas que esta pantalla hace cumplir porque la base las exige:

   · «Convertido» no se elige a mano. El CHECK crm_leads_convertido_coherente
     obliga a que venga con el cliente creado, así que el estado sale del
     desplegable y sólo se llega ahí por el botón de convertir.

   · Un prospecto necesita al menos empresa, nombre o apellidos
     (crm_leads_con_nombre). Se comprueba antes de enviar para que el usuario
     lea una frase y no un error de Postgres.

   · La puntuación va de 0 a 100 (crm_leads_score_check). */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] Prospectos necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=CRM.esc;
const val=id=>{const e=$(id);return e?String(e.value||'').trim():''};
const nulo=v=>v===''?null:v;
const norm=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const terms=q=>norm(q).split(/\s+/).filter(Boolean);
/* Para comparar identificaciones: «1790012345001» y «1790012345-001» son la
   misma, y quien las teclea no siempre pone el guion en el mismo sitio. */
const clave=v=>norm(v).replace(/[^a-z0-9]/g,'');

const LEAD='Prospectos: quien todavía no es cliente. Al convertirlo se crea su ficha en Clientes.';
/* La lista pide el juego estrecho del núcleo; la ficha, al abrir UNA fila,
   pide además lo que sólo hace falta en el formulario. Notas y direcciones no
   tienen por qué viajar por cada prospecto de una lista de mil. */
const FICHA=CRM.cols.leads+',phone2,address,country,website,company_size,notes,converted_at';
const CLIENTE_COLS='id,name,identification,email,active';

const ESTADOS={nuevo:'Nuevo',contactado:'Contactado',calificado:'Calificado',no_calificado:'No calificado',convertido:'Convertido',perdido:'Perdido'};
const ESTADOS_EDITABLES=['nuevo','contactado','calificado','no_calificado','perdido'];
const PRIORIDADES={baja:'Baja',media:'Media',alta:'Alta'};
const TIPOS={empresa:'Empresa',particular:'Particular'};
const CATEGORIAS=[['A','A — mayorista'],['B','B — minorista'],['C','C — precios negociados']];

let leads=[],clientes=[],gente=[],origenes=[];
let vista='lista',abierto=null,busca='',filtro='',cargando=false,forzar=false,borrador=null;

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
 const [l,c,r,g]=await Promise.all([
  api.list('crm_leads',{select:CRM.cols.leads,order:'created_at',ascending:false}),
  /* customers se pide con cuatro columnas: hace falta para enseñar a qué
     cliente apunta un prospecto convertido y para no crear un duplicado, no
     para nada más. */
  api.list('customers',{select:CLIENTE_COLS,order:'name',ascending:true}),
  CRM.referenciales(),
  CRM.comerciales(),
 ]);
 if(l.error)throw l.error;
 leads=l.data||[];
 clientes=c.error?[]:(c.data||[]);
 origenes=(r&&r.origenes)||[];
 gente=g||[];
 await quienSoy();
}

/* ---- presentación ---- */
function nombre(l){
 const p=[l.first_name,l.last_name].filter(Boolean).join(' ').trim();
 return String(l.company||'').trim()||p||'(sin nombre)';
}
function subtitulo(l){
 const p=[l.first_name,l.last_name].filter(Boolean).join(' ').trim();
 if(l.company&&p)return p+(l.job_title?' · '+l.job_title:'');
 return l.job_title||'';
}
function fecha(iso){
 if(!iso)return '—';
 const d=new Date(iso);
 return isNaN(d.getTime())?'—':d.toLocaleDateString('es-EC',{day:'2-digit',month:'2-digit',year:'numeric'});
}
function vencido(iso){const d=new Date(iso);return !isNaN(d.getTime())&&d.getTime()<Date.now()}
/* El navegador da y espera hora local en datetime-local; la base guarda UTC.
   La conversión va aquí, en un sitio, y no en cada campo. */
function paraInput(iso){
 if(!iso)return '';
 const d=new Date(iso);if(isNaN(d.getTime()))return '';
 const p=n=>String(n).padStart(2,'0');
 return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+'T'+p(d.getHours())+':'+p(d.getMinutes());
}
function desdeInput(v){if(!v)return null;const d=new Date(v);return isNaN(d.getTime())?null:d.toISOString()}
function clienteDe(l){return l.converted_customer_id?clientes.find(c=>String(c.id)===String(l.converted_customer_id))||null:null}

function msg(t,tipo){const m=$('crmMsg');if(!m)return;m.className='crmMsg'+(tipo?' '+tipo:'');m.textContent=t||''}
function fallo(e,que){console.warn('[GAMA CRM Prospectos]',que,e);msg(que+': '+((e&&(e.message||e.details))||e),'err')}

/* ---- lista ---- */
function visibles(){
 const arch=!!(window.GamaArchive&&window.GamaArchive.mode('crmLeads')==='archived');
 let r=leads.filter(l=>(l.active===false)===arch);
 if(filtro)r=r.filter(l=>String(l.status)===filtro);
 const t=terms(busca);
 if(t.length)r=r.filter(l=>{
  const h=norm([nombre(l),l.first_name,l.last_name,l.email,l.phone,l.city,l.industry].join(' '));
  return t.every(x=>h.includes(x));
 });
 return window.GamaSort?window.GamaSort.apply('crmLeads',r,{
  nombre:l=>nombre(l),
  estado:l=>ESTADOS[l.status]||l.status||'',
  prioridad:l=>({alta:3,media:2,baja:1})[l.priority]||0,
  puntos:l=>Number(l.score||0),
  responsable:l=>CRM.nombreDe(l.owner_id,gente),
  ciudad:l=>l.city||'',
  seguimiento:l=>l.next_followup_at||'',
 }):r;
}
function lista(){
 const nActivos=leads.filter(l=>l.active!==false).length;
 const nArch=leads.filter(l=>l.active===false).length;
 const filas=visibles();
 const pagina=window.GamaPage?window.GamaPage.slice('crmLeads',filas):filas;
 return '<div class="card">'
  +'<div class="crmBar">'
  +'<input id="crmLeadBusca" type="search" placeholder="Buscar por nombre, correo, teléfono o ciudad…" value="'+esc(busca)+'" aria-label="Buscar prospectos">'
  +'<select id="crmLeadFiltro" data-gama-nofind aria-label="Filtrar por estado"><option value="">Todos los estados</option>'
  +Object.keys(ESTADOS).map(k=>'<option value="'+k+'"'+(filtro===k?' selected':'')+'>'+esc(ESTADOS[k])+'</option>').join('')
  +'</select>'
  +'<button type="button" class="primary" id="crmLeadNuevo">+ Nuevo prospecto</button>'
  +'</div>'
  +(window.GamaArchive?window.GamaArchive.tabs('crmLeads',nActivos,nArch):'')
  +(filas.length?tabla(pagina):vacio(nActivos+nArch))
  +(window.GamaPage?window.GamaPage.controls('crmLeads',filas.length):'')
  +'</div>';
}
function vacio(total){
 return '<div class="crmVacio">'+(total
  ?'Ningún prospecto coincide con la búsqueda.'
  :'Todavía no hay prospectos. Crea el primero con «+ Nuevo prospecto».')+'</div>';
}
function tabla(rows){
 const th=(col,label,align)=>window.GamaSort?window.GamaSort.th('crmLeads',col,label,align):'<th>'+esc(label)+'</th>';
 return '<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
  +th('nombre','Prospecto')+th('estado','Estado')+th('prioridad','Prioridad')
  +th('puntos','Puntos','right')+th('responsable','Responsable')+th('ciudad','Ciudad')
  +th('seguimiento','Próximo paso')+'<th></th></tr></thead><tbody>'
  +rows.map(fila).join('')+'</tbody></table></div>';
}
function fila(l){
 const sub=subtitulo(l),cli=clienteDe(l);
 return '<tr>'
  +'<td><b>'+esc(nombre(l))+'</b>'
   +(sub?'<small class="crmSub">'+esc(sub)+'</small>':'')
   +(l.email?'<small class="crmSub">'+esc(l.email)+'</small>':'')
   +(cli?'<small class="crmSub crmLink">→ cliente '+esc(cli.name)+'</small>':'')
  +'</td>'
  +'<td><span class="crmEstado e-'+esc(l.status)+'">'+esc(ESTADOS[l.status]||l.status)+'</span></td>'
  +'<td><span class="crmPri p-'+esc(l.priority)+'">'+esc(PRIORIDADES[l.priority]||l.priority)+'</span></td>'
  +'<td class="r">'+Number(l.score||0)+'</td>'
  +'<td>'+esc(CRM.nombreDe(l.owner_id,gente))+'</td>'
  +'<td>'+esc(l.city||'—')+'</td>'
  +'<td>'+(l.next_followup_at?esc(fecha(l.next_followup_at))+(vencido(l.next_followup_at)?' <span class="crmTarde">vencido</span>':''):'—')+'</td>'
  +'<td class="crmAcc">'
   +'<button type="button" data-abrir="'+esc(l.id)+'">Abrir</button>'
   +(l.active!==false&&l.status!=='convertido'?'<button type="button" class="primary" data-convertir="'+esc(l.id)+'">Convertir</button>':'')
   +(l.active!==false
     ?'<button type="button" data-archivar="'+esc(l.id)+'" title="Archivar prospecto">🗄️</button>'
     :'<button type="button" data-restaurar="'+esc(l.id)+'" title="Restaurar prospecto">↩︎</button>')
  +'</td></tr>';
}

/* ---- ficha ---- */
function campo(id,label,valor,tipo){
 return '<div><label for="'+id+'">'+esc(label)+'</label><input id="'+id+'" type="'+(tipo||'text')+'" value="'+esc(valor||'')+'"></div>';
}
function campoSelect(id,label,mapa,sel){
 return '<div><label for="'+id+'">'+esc(label)+'</label><select id="'+id+'" data-gama-nofind>'
  +Object.keys(mapa).map(k=>'<option value="'+k+'"'+(sel===k?' selected':'')+'>'+esc(mapa[k])+'</option>').join('')
  +'</select></div>';
}
function opciones(pares,sel){
 return '<option value="">— sin asignar —</option>'
  +pares.map(p=>'<option value="'+esc(p[0])+'"'+(String(sel||'')===String(p[0])?' selected':'')+'>'+esc(p[1])+'</option>').join('');
}
function nuevo(){return {kind:'empresa',status:'nuevo',priority:'media',score:0,active:true,owner_id:mi||null}}

function ficha(){
 const l=abierto||{},esNuevo=!l.id,cli=clienteDe(l);
 return '<div class="card">'
  +'<h3>'+(esNuevo?'Nuevo prospecto':esc(nombre(l)))+'</h3>'
  +(cli?'<div class="crmAviso">Ya convertido en el cliente <b>'+esc(cli.name)+'</b>'
    +(l.converted_at?' el '+esc(fecha(l.converted_at)):'')
    +'. Lo comercial se lleva desde su ficha de cliente; aquí queda el rastro de dónde salió.</div>':'')
  +'<div class="crmForm">'
   +campoSelect('crmLKind','Tipo',TIPOS,l.kind||'empresa')
   +campo('crmLCompany','Empresa',l.company)
   +campo('crmLFirst','Nombre',l.first_name)
   +campo('crmLLast','Apellidos',l.last_name)
   +campo('crmLJob','Cargo',l.job_title)
   +campo('crmLEmail','Correo',l.email,'email')
   +campo('crmLPhone','Teléfono',l.phone,'tel')
   +campo('crmLPhone2','Otro teléfono',l.phone2,'tel')
   +campo('crmLAddress','Dirección',l.address)
   +campo('crmLCity','Ciudad',l.city)
   +campo('crmLCountry','País',l.country)
   +campo('crmLWeb','Sitio web',l.website)
   +campo('crmLIndustry','Sector',l.industry)
   +campo('crmLSize','Tamaño',l.company_size)
   +'<div><label for="crmLSource">Origen</label><select id="crmLSource">'+opciones(origenes.map(o=>[o.id,o.name]),l.source_id)+'</select></div>'
   +'<div><label for="crmLOwner">Responsable</label><select id="crmLOwner">'+opciones(gente.map(p=>[p.id,p.full_name||p.email]),l.owner_id)+'</select></div>'
   /* Un prospecto ya convertido no enseña desplegable de estado: la base sólo
      acepta «convertido» acompañado del cliente creado, y ofrecerlo aquí sería
      ofrecer un guardado que va a fallar. */
   +(l.status==='convertido'
     ?'<div><label for="crmLStatusRO">Estado</label><input id="crmLStatusRO" value="Convertido" readonly aria-readonly="true"></div>'
     :'<div><label for="crmLStatus">Estado</label><select id="crmLStatus" data-gama-nofind>'
      +ESTADOS_EDITABLES.map(k=>'<option value="'+k+'"'+((l.status||'nuevo')===k?' selected':'')+'>'+esc(ESTADOS[k])+'</option>').join('')
      +'</select></div>')
   +'<div><label for="crmLPriority">Prioridad</label><select id="crmLPriority" data-gama-nofind>'
    +Object.keys(PRIORIDADES).map(k=>'<option value="'+k+'"'+((l.priority||'media')===k?' selected':'')+'>'+esc(PRIORIDADES[k])+'</option>').join('')
    +'</select></div>'
   +'<div><label for="crmLScore">Puntuación (0–100)</label><input id="crmLScore" type="number" min="0" max="100" step="1" value="'+Number(l.score||0)+'"></div>'
   +'<div><label for="crmLNext">Próximo seguimiento</label><input id="crmLNext" type="datetime-local" value="'+esc(paraInput(l.next_followup_at))+'"></div>'
  +'</div>'
  +'<div class="crmNotas"><label for="crmLNotes">Notas</label><textarea id="crmLNotes" rows="4">'+esc(l.notes||'')+'</textarea></div>'
  +'<div class="crmAcciones">'
   +'<button type="button" class="primary" id="crmLGuardar">Guardar</button>'
   +'<button type="button" id="crmLCancelar">Cancelar</button>'
   +(!esNuevo&&l.status!=='convertido'&&l.active!==false?'<button type="button" id="crmLConvertir">Convertir en cliente</button>':'')
  +'</div></div>';
}
function leerFicha(){
 const d={
  kind:val('crmLKind')||'empresa',
  company:nulo(val('crmLCompany')),
  first_name:nulo(val('crmLFirst')),
  last_name:nulo(val('crmLLast')),
  job_title:nulo(val('crmLJob')),
  email:nulo(val('crmLEmail')),
  phone:nulo(val('crmLPhone')),
  phone2:nulo(val('crmLPhone2')),
  address:nulo(val('crmLAddress')),
  city:nulo(val('crmLCity')),
  country:nulo(val('crmLCountry')),
  website:nulo(val('crmLWeb')),
  industry:nulo(val('crmLIndustry')),
  company_size:nulo(val('crmLSize')),
  source_id:nulo(val('crmLSource')),
  owner_id:nulo(val('crmLOwner')),
  priority:val('crmLPriority')||'media',
  next_followup_at:desdeInput(val('crmLNext')),
  notes:nulo(val('crmLNotes')),
 };
 /* El estado sólo se envía cuando se pudo elegir. Mandarlo a ciegas en una
    ficha convertida reescribiría el estado que la conversión dejó puesto. */
 if($('crmLStatus'))d.status=$('crmLStatus').value;
 const p=parseInt(val('crmLScore'),10);
 d.score=Number.isFinite(p)?Math.min(100,Math.max(0,p)):0;
 if(!(d.company||d.last_name||d.first_name)){msg('Un prospecto necesita al menos una empresa, un nombre o unos apellidos.','err');return null}
 return d;
}

/* ---- conversión ---- */
/* Antes de crear una segunda ficha de la misma empresa se mira si ya está.
   Se compara por correo y por identificación, que son lo único que de verdad
   identifica: dos «Comercial Andina S.A.» pueden ser dos empresas distintas. */
function coincidencia(email,ident){
 const em=norm(email),id=clave(ident);
 return clientes.find(c=>c.active!==false&&(
  (!!em&&norm(c.email)===em)||(!!id&&clave(c.identification)===id)))||null;
}
/* Lo que el usuario ha tecleado en el formulario de conversión. Existe porque
   avisar de un duplicado obliga a repintar, y repintar desde el prospecto le
   borraría el RUC que acababa de escribir. */
function leerConversion(){
 return {name:val('crmCName'),identification:val('crmCId'),category:val('crmCCat')||'A',
  email:val('crmCEmail'),phone:val('crmCPhone'),address:val('crmCAddress'),
  city:val('crmCCity'),province:val('crmCProv'),notes:val('crmCNotes')};
}
function desdeProspecto(l){
 return {name:nombre(l),identification:'',category:'A',email:l.email||'',phone:l.phone||'',
  address:l.address||'',city:l.city||'',province:'',notes:l.notes||''};
}
function convertir(){
 const l=abierto||{},d=borrador||desdeProspecto(l);
 /* Una vez que el usuario ha dicho que sí quiere otra ficha, el aviso sobra:
    dejarlo puesto haría dudar de si el botón sirvió de algo. */
 const dup=forzar?null:coincidencia(d.email,d.identification);
 return '<div class="card">'
  +'<h3>Convertir «'+esc(nombre(l))+'» en cliente</h3>'
  +'<p class="muted">Se crea una ficha en 👥 Clientes con estos datos y el prospecto queda apuntando a ella. '
  +'A partir de ahí lo comercial vive en la ficha de cliente —presupuestos, tarifas, catálogo— y aquí queda de dónde salió.</p>'
  +(dup?'<div class="crmAviso crmDup">Ya hay un cliente que coincide: <b>'+esc(dup.name)+'</b>'
    +(dup.identification?' ('+esc(dup.identification)+')':'')+'. Enlázalo en vez de abrir otra ficha de la misma empresa.'
    +'<div class="crmAcciones"><button type="button" class="primary" data-enlazar="'+esc(dup.id)+'">Enlazar con este cliente</button>'
    +'<button type="button" id="crmCForzar">Crear otra ficha de todas formas</button></div></div>':'')
  +'<div class="crmForm">'
   +campo('crmCName','Nombre del cliente',d.name)
   +campo('crmCId','Identificación (RUC / cédula)',d.identification)
   +'<div><label for="crmCCat">Categoría</label><select id="crmCCat" data-gama-nofind>'
    +CATEGORIAS.map(c=>'<option value="'+c[0]+'"'+(d.category===c[0]?' selected':'')+'>'+esc(c[1])+'</option>').join('')+'</select></div>'
   +campo('crmCEmail','Correo',d.email,'email')
   +campo('crmCPhone','Teléfono',d.phone,'tel')
   +campo('crmCAddress','Dirección',d.address)
   +campo('crmCCity','Ciudad',d.city)
   +campo('crmCProv','Provincia',d.province)
  +'</div>'
  +'<div class="crmNotas"><label for="crmCNotes">Notas</label><textarea id="crmCNotes" rows="3">'+esc(d.notes||'')+'</textarea></div>'
  +'<div class="crmAcciones">'
   +'<button type="button" class="primary" id="crmCOk">Crear el cliente</button>'
   +'<button type="button" id="crmCCancel">Cancelar</button>'
  +'</div></div>';
}
async function convertirYa(existente){
 const l=abierto;
 if(!l||!l.id)return;
 try{
  let clienteId=existente||null;
  if(!clienteId){
   const nom=val('crmCName');
   if(!nom){msg('El cliente necesita un nombre.','err');return}
   const ident=nulo(val('crmCId')),correo=nulo(val('crmCEmail'));
   if(coincidencia(correo,ident)&&!forzar){
    borrador=leerConversion();
    pintar('Ya hay un cliente con esos datos. Enlázalo, o confirma que quieres otra ficha.','err');
    return;
   }
   /* owner_id, source_id y crm_score son las tres columnas que el CRM añadió a
      customers: el cliente nace sabiendo quién lo trajo y de dónde salió. */
   const r=await C().insert('customers',{
    name:nom,identification:ident,email:correo,
    phone:nulo(val('crmCPhone')),address:nulo(val('crmCAddress')),
    city:nulo(val('crmCCity')),province:nulo(val('crmCProv')),
    notes:nulo(val('crmCNotes')),category:val('crmCCat')||'A',active:true,
    owner_id:l.owner_id||null,source_id:l.source_id||null,crm_score:Number(l.score||0),
   });
   if(r.error)throw r.error;
   clienteId=r.data&&r.data.id;
   if(!clienteId)throw new Error('La nube no devolvió el cliente creado.');
  }
  const u=await C().update('crm_leads',l.id,{status:'convertido',converted_customer_id:clienteId,converted_at:new Date().toISOString()});
  /* Si el cliente se creó y el prospecto no se pudo marcar, hay que decirlo
     con esas palabras: repetir la conversión a ciegas abriría una segunda
     ficha del mismo cliente, que es justo lo que se quería evitar. */
  if(u.error)throw new Error('El cliente se creó, pero el prospecto no se pudo marcar como convertido ('+(u.error.message||u.error)+'). Enlázalo desde aquí en vez de convertirlo otra vez.');
  await cargar();
  vista='lista';abierto=null;forzar=false;borrador=null;
  pintar(existente?'Prospecto enlazado con el cliente.':'Cliente creado y prospecto convertido.','ok');
 }catch(e){fallo(e,'No se pudo convertir el prospecto')}
}

/* ---- acciones ---- */
async function abrir(id,comoConversion){
 try{
  const r=await C().list('crm_leads',{select:FICHA,eq:{id:id},limit:1});
  if(r.error)throw r.error;
  const l=(r.data||[])[0];
  if(!l){msg('Ese prospecto ya no existe.','err');return}
  abierto=l;forzar=false;borrador=null;
  vista=comoConversion?'convertir':'ficha';
  pintar();
 }catch(e){fallo(e,'No se pudo abrir el prospecto')}
}
async function guardar(){
 const d=leerFicha();
 if(!d)return;
 try{
  let r;
  if(abierto&&abierto.id)r=await C().update('crm_leads',abierto.id,d);
  else{d.created_by=await quienSoy();d.active=true;r=await C().insert('crm_leads',d)}
  if(r.error)throw r.error;
  await cargar();
  vista='lista';abierto=null;
  pintar('Prospecto guardado.','ok');
 }catch(e){fallo(e,'No se pudo guardar el prospecto')}
}
/* Archivar y no borrar: un prospecto convertido cuelga de un cliente y borrarlo
   perdería de dónde salió. Es la misma regla que en el resto de GAMA. */
async function archivar(id,activo){
 try{
  const r=await C().update('crm_leads',id,{active:activo});
  if(r.error)throw r.error;
  await cargar();
  pintar(activo?'Prospecto restaurado.':'Prospecto archivado.','ok');
 }catch(e){fallo(e,'No se pudo archivar el prospecto')}
}

/* ---- pintar y conectar ---- */
function pintar(aviso,tipo){
 const s=CRM.section();
 s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>'
  +(vista==='ficha'?ficha():vista==='convertir'?convertir():lista());
 CRM.bind(s);
 conectar();
 if(aviso)msg(aviso,tipo);
}
function conectar(){
 const s=CRM.section();
 const b=$('crmLeadBusca');
 if(b)b.oninput=()=>{
  busca=b.value;
  if(window.GamaPage)window.GamaPage.reset('crmLeads');
  pintar();
  /* Repintar la lista se lleva por delante el campo donde se estaba
     escribiendo, así que se devuelve el foco y el cursor al final. */
  const n=$('crmLeadBusca');
  if(n){n.focus();try{n.setSelectionRange(n.value.length,n.value.length)}catch(e){}}
 };
 const f=$('crmLeadFiltro');
 if(f)f.onchange=()=>{filtro=f.value;if(window.GamaPage)window.GamaPage.reset('crmLeads');pintar()};
 const nv=$('crmLeadNuevo');
 if(nv)nv.onclick=()=>{abierto=nuevo();vista='ficha';pintar()};
 s.querySelectorAll('[data-abrir]').forEach(x=>{x.onclick=()=>abrir(x.dataset.abrir,false)});
 s.querySelectorAll('[data-convertir]').forEach(x=>{x.onclick=()=>abrir(x.dataset.convertir,true)});
 s.querySelectorAll('[data-archivar]').forEach(x=>{x.onclick=()=>archivar(x.dataset.archivar,false)});
 s.querySelectorAll('[data-restaurar]').forEach(x=>{x.onclick=()=>archivar(x.dataset.restaurar,true)});
 s.querySelectorAll('[data-enlazar]').forEach(x=>{x.onclick=()=>convertirYa(x.dataset.enlazar)});
 const g=$('crmLGuardar');if(g)g.onclick=guardar;
 const ca=$('crmLCancelar');if(ca)ca.onclick=()=>{vista='lista';abierto=null;pintar()};
 const cv=$('crmLConvertir');if(cv)cv.onclick=()=>{forzar=false;borrador=null;vista='convertir';pintar()};
 const ok=$('crmCOk');if(ok)ok.onclick=()=>convertirYa(null);
 const cc=$('crmCCancel');if(cc)cc.onclick=()=>{vista='lista';abierto=null;forzar=false;borrador=null;pintar()};
 const fz=$('crmCForzar');if(fz)fz.onclick=()=>{borrador=leerConversion();forzar=true;pintar('De acuerdo: se creará una ficha nueva con lo que has escrito.','ok')};
}
function css(){
 if($('crmLeadsCss'))return;
 const s=document.createElement('style');s.id='crmLeadsCss';
 s.textContent='#crm .crmBar{display:grid;grid-template-columns:minmax(0,1fr) 190px auto;gap:8px;align-items:center;margin-bottom:12px}'
 +'#crm .crmBar input,#crm .crmBar select{min-height:42px}'
 +'#crm .crmTablaWrap{width:100%;overflow-x:auto}'
 /* min-width:min-content y no una anchura fija: con un ancho clavado las
    celdas se salen por la derecha sin que el contenedor cuente ese sobrante
    como algo que desplazar, y los botones quedan fuera de alcance. */
 +'#crm .crmTabla{width:100%;min-width:min-content;border-collapse:collapse}'
 +'#crm .crmTabla th,#crm .crmTabla td{padding:9px;border-bottom:1px solid #edf1f2;text-align:left;font-size:12.5px;vertical-align:top}'
 +'#crm .crmTabla th{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:#71808a;background:#f8fafb}'
 +'#crm .crmTabla td.r,#crm .crmTabla th.r{text-align:right}'
 +'#crm .crmSub{display:block;color:#7b8992;font-size:11px}'
 +'#crm .crmLink{color:#087c8b;font-weight:700}'
 +'#crm .crmTarde{color:#c94f45;font-weight:800;font-size:11px}'
 +'#crm .crmEstado,#crm .crmPri{display:inline-block;padding:3px 9px;border-radius:999px;font-size:11px;font-weight:800;white-space:nowrap}'
 +'#crm .crmEstado{background:#eef3f4;color:#4c5c68}'
 +'#crm .crmEstado.e-calificado{background:#e4f1fb;color:#1b5f8c}'
 +'#crm .crmEstado.e-convertido{background:#e7f6f0;color:#12795c}'
 +'#crm .crmEstado.e-perdido,#crm .crmEstado.e-no_calificado{background:#fff0ec;color:#b4483c}'
 +'#crm .crmPri{background:#f2f5f6;color:#61717c}'
 +'#crm .crmPri.p-alta{background:#fdefe4;color:#9a5314}'
 +'#crm .crmPri.p-baja{background:#f4f6f7;color:#8a97a0}'
 +'#crm .crmAcc{white-space:nowrap}'
 +'#crm .crmAcc button{width:auto;margin:0 3px 3px 0;padding:7px 11px;font-size:12px;min-height:38px}'
 +'#crm .crmForm{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px}'
 +'#crm .crmForm label,#crm .crmNotas label{display:block;font-size:11px;font-weight:800;color:#61717c;margin-bottom:3px}'
 +'#crm .crmNotas{margin-top:10px}'
 +'#crm .crmNotas textarea{width:100%;padding:9px;border:1px solid #c9d6df;border-radius:9px;font:inherit;font-size:13px}'
 +'#crm .crmAcciones{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}'
 +'#crm .crmAcciones button{width:auto;min-height:44px}'
 +'#crm .crmAviso{background:#f8fbfb;border:1px solid #dbe6ea;border-left:4px solid #087c8b;border-radius:9px;padding:11px;font-size:13px;color:#4c5c68;margin-bottom:12px}'
 +'#crm .crmAviso.crmDup{background:#fff8f1;border-color:#f0dcc6;border-left-color:#d98324}'
 +'#crm .crmAviso .crmAcciones{margin-top:9px}'
 /* En el teléfono la barra se apila y la tabla la convierte en fichas
    gama-tables.js, como en el resto de la aplicación. */
 +'@media(max-width:760px){#crm .crmBar{grid-template-columns:minmax(0,1fr)}'
 +'#crm .crmBar button{width:100%}'
 +'#crm .crmTabla{--gamaCardsLabel:118px}'
 +'#crm .crmAcc button{margin:0 4px 4px 0}}';
 document.head.appendChild(s);
}

async function abrirPantalla(){
 CRM.css();css();
 const s=CRM.section();
 if(cargando)return;cargando=true;
 s.innerHTML=CRM.cabecera(LEAD)+'<div class="card"><div class="crmVacio">Cargando prospectos…</div></div>';
 CRM.bind(s);
 try{
  await cargar();
  vista='lista';abierto=null;forzar=false;borrador=null;
  pintar();
 }catch(e){
  s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>';
  CRM.bind(s);
  fallo(e,'No se pudieron cargar los prospectos');
 }finally{cargando=false}
 window.scrollTo({top:0,behavior:'smooth'});
}

if(window.GamaPage)window.GamaPage.register('crmLeads',()=>pintar());
if(window.GamaSort)window.GamaSort.register('crmLeads',()=>pintar());
if(window.GamaArchive)window.GamaArchive.register('crmLeads',()=>pintar());
CRM.registrar('prospectos','Prospectos',abrirPantalla);
window.GamaCRMLeads={open:abrirPantalla};
})();
