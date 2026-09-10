/* GAMA — CRM · Oportunidades y embudo.

   Una oportunidad es una venta concreta en curso: de quién, por cuánto, en qué
   etapa y con qué probabilidad. Es lo que llena el cuadro de mando, así que lo
   que aquí se hace mal se ve mal en toda la pantalla de dirección.

   Reglas de la base que esta pantalla hace cumplir, y por qué importan:

   · La referencia OP-nnnnnn la pone una SECUENCIA de la base, no el navegador.
     El módulo de compras la calcula con max()+1 en el cliente y dos pestañas
     abiertas a la vez dan el mismo número. Aquí no se envía nunca: se deja que
     la ponga Postgres.

   · weighted_amount es una columna CALCULADA (amount × probability / 100).
     Enviarla sería un error de Postgres, así que no se toca: se cambia la
     probabilidad y la base recalcula.

   · Una oportunidad cuelga de un cliente O de un prospecto, nunca de los dos
     (crm_opp_uno_u_otro), y no puede estar ganada y perdida a la vez.

   · Una oportunidad perdida EXIGE motivo (crm_opp_perdida_con_motivo). Por eso
     mover una tarjeta a «Perdido» pregunta por qué antes de moverla, en vez de
     dejar que la base rechace el movimiento.

   El importe sale de los productos cuando los hay: sumar a mano lo que ya está
   en las líneas es la forma más fácil de que el embudo mienta. */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] Oportunidades necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=CRM.esc,money=CRM.money;
const U=CRM.util;
const val=U.valor,nulo=U.nulo,norm=U.norm,terms=U.terms;
const campo=U.campo,opciones=U.opciones,msg=U.msg,fecha=U.fecha;
const fallo=(e,que)=>U.error(e,que,'Oportunidades');

const LEAD='Oportunidades: las ventas en curso, etapa por etapa.';
const LISTA=CRM.cols.opportunities;
const FORM=LISTA+',description,competitors';
const PROD_COLS='id,name,reference,sale_price,active';
const CLIENTE_COLS='id,name,active';
const LEAD_COLS='id,company,first_name,last_name,active';

const PRIORIDADES={baja:'Baja',media:'Media',alta:'Alta'};

let opos=[],lineas=[],clientes=[],prospectos=[],contactos=[],productos=[],gente=[],ref={etapas:[],origenes:[],motivos:[]};
let vista='embudo',abierto=null,busca='',cargando=false,perdiendo=null;

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
 const [o,c,l,k,r,g]=await Promise.all([
  api.list('crm_opportunities',{select:LISTA,order:'created_at',ascending:false}),
  api.list('customers',{select:CLIENTE_COLS,order:'name',ascending:true}),
  api.list('crm_leads',{select:LEAD_COLS,order:'company',ascending:true}),
  api.list('crm_contacts',{select:'id,customer_id,lead_id,first_name,last_name,active'}),
  CRM.referenciales(),
  CRM.comerciales(),
 ]);
 if(o.error)throw o.error;
 opos=o.data||[];
 clientes=c.error?[]:(c.data||[]);
 prospectos=l.error?[]:(l.data||[]);
 contactos=k.error?[]:(k.data||[]);
 ref=r||{etapas:[],origenes:[],motivos:[]};
 gente=g||[];
 await quienSoy();
}
/* products guarda la foto de cada artículo en base64: pedirlo entero para
   enseñar nombre y precio se trae el catálogo de fotos. Ya pasó en Compras. */
async function cargarProductos(){
 if(productos.length)return productos;
 const r=await C().list('products',{select:PROD_COLS,order:'name',ascending:true});
 productos=r.error?[]:(r.data||[]).filter(p=>p.active!==false);
 return productos;
}
async function cargarLineas(id){
 lineas=[];
 if(!id)return;
 const r=await C().list('crm_opportunity_lines',{select:'id,opportunity_id,product_id,quantity,unit_price,discount,position',eq:{opportunity_id:id},order:'position',ascending:true});
 if(r.error)throw r.error;
 lineas=r.data||[];
}

/* ---- presentación ---- */
const etapaDe=id=>ref.etapas.find(e=>String(e.id)===String(id))||null;
const abiertas=()=>ref.etapas.filter(e=>!e.is_won&&!e.is_lost);
function deQuien(o){
 if(o.customer_id){
  const x=clientes.find(c=>String(c.id)===String(o.customer_id));
  return {tipo:'cliente',etiqueta:'Cliente',nombre:x?x.name:'(cliente que ya no está)'};
 }
 const l=prospectos.find(p=>String(p.id)===String(o.lead_id));
 return {tipo:'prospecto',etiqueta:'Prospecto',nombre:l?nombreLead(l):'(prospecto que ya no está)'};
}
function nombreLead(l){
 const p=[l.first_name,l.last_name].filter(Boolean).join(' ').trim();
 return String(l.company||'').trim()||p||'(sin nombre)';
}
function nombreContacto(k){
 const n=[k.first_name,k.last_name].filter(Boolean).join(' ').trim();
 return n||'(sin nombre)';
}
const clientesVivos=()=>clientes.filter(c=>c.active!==false);
const prospectosVivos=()=>prospectos.filter(p=>p.active!==false);
/* Sólo se ofrecen los contactos de la ficha elegida: un contacto de otra
   empresa en una oportunidad es un dato que no significa nada. */
function contactosDe(tipo,id){
 if(!id)return [];
 return contactos.filter(k=>k.active!==false&&(tipo==='cliente'
  ?String(k.customer_id||'')===String(id)
  :String(k.lead_id||'')===String(id)));
}
function tarde(o){
 if(!o.expected_close_date)return false;
 const e=etapaDe(o.stage_id);
 if(e&&(e.is_won||e.is_lost))return false;
 return new Date(o.expected_close_date+'T23:59:59').getTime()<Date.now();
}
const totalLinea=l=>Number(l.quantity||0)*Number(l.unit_price||0)*(1-Number(l.discount||0)/100);
const sumaLineas=()=>Math.round(lineas.reduce((t,l)=>t+totalLinea(l),0)*100)/100;

/* ---- embudo ---- */
function coincide(o){
 const t=terms(busca);
 if(!t.length)return true;
 const h=norm([o.title,o.reference,deQuien(o).nombre,CRM.nombreDe(o.owner_id,gente)].join(' '));
 return t.every(x=>h.includes(x));
}
function embudo(){
 const vivas=opos.filter(o=>o.active!==false&&coincide(o));
 return '<div class="crmBar">'
  +'<input id="crmOBusca" type="search" placeholder="Buscar por título, referencia, ficha o responsable…" value="'+esc(busca)+'" aria-label="Buscar oportunidades">'
  +'<span></span>'
  +'<button type="button" class="primary" id="crmONueva">+ Nueva oportunidad</button>'
  +'</div>'
  +(ref.etapas.length
   ?'<div class="crmTablero">'+ref.etapas.map(e=>columna(e,vivas.filter(o=>String(o.stage_id)===String(e.id)))).join('')+'</div>'
   :'<div class="card"><div class="crmVacio">Todavía no hay etapas configuradas.</div></div>')
  +(vivas.length?'':'<div class="card"><div class="crmVacio">'
   +(opos.length?'Ninguna oportunidad coincide con la búsqueda.':'Ninguna oportunidad todavía. La primera se crea con «+ Nueva oportunidad».')
   +'</div></div>');
}
function columna(e,suyas){
 const total=suyas.reduce((t,o)=>t+Number(o.amount||0),0);
 return '<div class="crmCol'+(e.is_won?' ganada':e.is_lost?' perdida':'')+'" data-etapa="'+esc(e.id)+'">'
  +'<div class="crmColCab"><b>'+esc(e.name)+'</b><i>'+suyas.length+'</i>'
   +'<small>'+esc(money(total))+'</small></div>'
  +(suyas.length?suyas.map(tarjeta).join(''):'<div class="crmColVacia">—</div>')
  +'</div>';
}
function tarjeta(o){
 const q=deQuien(o);
 return '<div class="crmTarjeta'+(tarde(o)?' tarde':'')+'" data-oportunidad="'+esc(o.id)+'">'
  +'<div class="crmTarjTit"><b>'+esc(o.title)+'</b>'
   +'<span class="crmPri p-'+esc(o.priority)+'">'+esc(PRIORIDADES[o.priority]||o.priority)+'</span></div>'
  +'<small class="crmSub">'+esc(q.nombre)+'</small>'
  +'<div class="crmTarjPie"><b>'+esc(money(o.amount))+'</b><span>'+Number(o.probability||0)+' %</span></div>'
  +'<small class="crmSub">'+esc(o.reference)+' · '+esc(CRM.nombreDe(o.owner_id,gente))+'</small>'
  +(o.expected_close_date?'<small class="crmSub'+(tarde(o)?' crmTarde':'')+'">Cierre previsto '+esc(fecha(o.expected_close_date))+'</small>':'')
  +'<select class="crmMover" data-mover="'+esc(o.id)+'" aria-label="Mover ' +esc(o.title)+' de etapa" data-gama-nofind>'
   +ref.etapas.map(e=>'<option value="'+esc(e.id)+'"'+(String(e.id)===String(o.stage_id)?' selected':'')+'>'+esc(e.name)+'</option>').join('')
  +'</select>'
  +'</div>';
}
/* La base exige motivo para dar algo por perdido, así que se pregunta antes de
   mover y no después de que Postgres rechace el movimiento. */
function panelPerdida(){
 const o=opos.find(x=>String(x.id)===String(perdiendo.id));
 return '<div class="card crmPerdida"><h3>¿Por qué se perdió «'+esc(o?o.title:'')+'»?</h3>'
  +'<p class="muted">La base no admite una oportunidad perdida sin motivo, y con razón: un embudo que no dice por qué se pierde no sirve para corregir nada.</p>'
  +'<div class="crmForm"><div><label for="crmOMotivo">Motivo</label><select id="crmOMotivo">'
   +opciones(ref.motivos.map(m=>[m.id,m.name]),'','— elige un motivo —')+'</select></div></div>'
  +'<div class="crmAcciones"><button type="button" class="primary" id="crmOPerder">Darla por perdida</button>'
  +'<button type="button" id="crmOPerderNo">Cancelar</button></div></div>';
}

/* ---- ficha ---- */
function nueva(){
 const e=abiertas()[0]||ref.etapas[0]||null;
 return {title:'',priority:'media',amount:0,active:true,owner_id:mi||null,
  stage_id:e?e.id:null,probability:e?Number(e.default_probability||0):0};
}
function ficha(){
 const o=abierto||{};
 const esNueva=!o.id;
 const tipo=o.lead_id?'prospecto':'cliente';
 const quien=tipo==='cliente'?o.customer_id:o.lead_id;
 const e=etapaDe(o.stage_id);
 const conLineas=lineas.length>0;
 return '<div class="card">'
  +'<h3>'+(esNueva?'Nueva oportunidad':esc(o.reference+' · '+o.title))+'</h3>'
  +(e&&e.is_lost?'<div class="crmAviso crmDup">Perdida'+(o.lost_at?' el '+esc(fecha(o.lost_at)):'')+'. Motivo: '
    +esc((ref.motivos.find(m=>String(m.id)===String(o.lost_reason_id))||{}).name||'sin indicar')+'.</div>':'')
  +(e&&e.is_won?'<div class="crmAviso">Ganada'+(o.won_at?' el '+esc(fecha(o.won_at)):'')+'.</div>':'')
  +'<div class="crmForm">'
   +campo('crmOTitulo','Título',o.title)
   +'<div><label for="crmOTipo">Es de</label><select id="crmOTipo" data-gama-nofind>'
    +'<option value="cliente"'+(tipo==='cliente'?' selected':'')+'>Un cliente</option>'
    +'<option value="prospecto"'+(tipo==='prospecto'?' selected':'')+'>Un prospecto</option></select></div>'
   +'<div id="crmOCajaCliente"'+(tipo==='cliente'?'':' hidden')+'>'
    +'<label for="crmOCliente">Cliente</label><select id="crmOCliente">'
    +opciones(clientesVivos().map(c=>[c.id,c.name]),o.customer_id,'— elige un cliente —')+'</select></div>'
   +'<div id="crmOCajaProspecto"'+(tipo==='prospecto'?'':' hidden')+'>'
    +'<label for="crmOProspecto">Prospecto</label><select id="crmOProspecto">'
    +opciones(prospectosVivos().map(p=>[p.id,nombreLead(p)]),o.lead_id,'— elige un prospecto —')+'</select></div>'
   +'<div><label for="crmOContacto">Contacto</label><select id="crmOContacto">'
    +opciones(contactosDe(tipo,quien).map(k=>[k.id,nombreContacto(k)]),o.contact_id,'— sin contacto —')+'</select></div>'
   +'<div><label for="crmOEtapa">Etapa</label><select id="crmOEtapa" data-gama-nofind>'
    +ref.etapas.map(x=>'<option value="'+esc(x.id)+'"'+(String(x.id)===String(o.stage_id)?' selected':'')+'>'+esc(x.name)+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmOProb">Probabilidad (%)</label><input id="crmOProb" type="number" min="0" max="100" step="1" value="'+Number(o.probability||0)+'"></div>'
   /* Con líneas, el importe lo mandan los productos: dejarlo escribir a mano
      sería dejar que el embudo diga una cifra que no cuadra con lo que se
      está vendiendo. */
   +'<div><label for="crmOImporte">Importe</label><input id="crmOImporte" type="number" min="0" step="0.01" value="'
    +Number(conLineas?sumaLineas():(o.amount||0))+'"'+(conLineas?' readonly aria-readonly="true"':'')+'>'
    +(conLineas?'<small class="crmSub">Lo suman los productos de abajo.</small>':'')+'</div>'
   +'<div><label for="crmOCierre">Cierre previsto</label><input id="crmOCierre" type="date" value="'+esc(o.expected_close_date||'')+'"></div>'
   +'<div><label for="crmOPri">Prioridad</label><select id="crmOPri" data-gama-nofind>'
    +Object.keys(PRIORIDADES).map(k=>'<option value="'+k+'"'+((o.priority||'media')===k?' selected':'')+'>'+esc(PRIORIDADES[k])+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmOResp">Responsable</label><select id="crmOResp">'
    +opciones(gente.map(p=>[p.id,p.full_name||p.email]),o.owner_id)+'</select></div>'
   +'<div><label for="crmOOrigen">Origen</label><select id="crmOOrigen">'
    +opciones(ref.origenes.map(x=>[x.id,x.name]),o.source_id)+'</select></div>'
   +'<div><label for="crmOMotivoF">Motivo de pérdida</label><select id="crmOMotivoF">'
    +opciones(ref.motivos.map(m=>[m.id,m.name]),o.lost_reason_id,'— sólo si se pierde —')+'</select></div>'
   +campo('crmOCompe','Competencia',o.competitors)
  +'</div>'
  +'<div class="crmNotas"><label for="crmODesc">Descripción</label><textarea id="crmODesc" rows="3">'+esc(o.description||'')+'</textarea></div>'
  +'<div class="crmAcciones">'
   +'<button type="button" class="primary" id="crmOGuardar">Guardar</button>'
   +'<button type="button" id="crmOCancelar">Cancelar</button>'
  +'</div></div>'
  +(esNueva
    ?'<div class="card"><div class="crmVacio">Los productos se añaden en cuanto la oportunidad está guardada: hasta entonces no hay a qué colgarlos.</div></div>'
    :bloqueLineas());
}
function bloqueLineas(){
 const libres=productos.filter(p=>!lineas.some(l=>String(l.product_id)===String(p.id)));
 return '<div class="card"><h3>Productos</h3>'
  +'<p class="muted">Lo que se está vendiendo. En cuanto hay una línea, el importe de la oportunidad lo suman ellas.</p>'
  +'<div class="crmForm">'
   +'<div><label for="crmLProd">Producto</label><select id="crmLProd">'
    +opciones(libres.map(p=>[p.id,p.name+(p.reference?' · '+p.reference:'')]),'','— elige un producto —')+'</select></div>'
   +'<div><label for="crmLCant">Cantidad</label><input id="crmLCant" type="number" min="0.001" step="0.001" value="1"></div>'
   +'<div><label for="crmLPrecio">Precio unitario</label><input id="crmLPrecio" type="number" min="0" step="0.01" value="0"></div>'
   +'<div><label for="crmLDto">Descuento (%)</label><input id="crmLDto" type="number" min="0" max="100" step="0.1" value="0"></div>'
   +'<div><label>&nbsp;</label><button type="button" class="primary" id="crmLAdd">Añadir</button></div>'
  +'</div>'
  +(lineas.length?'<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
   +'<th>Producto</th><th class="r">Cantidad</th><th class="r">Precio</th><th class="r">Dto.</th><th class="r">Total</th><th></th>'
   +'</tr></thead><tbody>'
   +lineas.map(l=>{
     const p=productos.find(x=>String(x.id)===String(l.product_id));
     return '<tr><td>'+esc(p?p.name:'(producto archivado)')+'</td>'
      +'<td class="r">'+Number(l.quantity)+'</td>'
      +'<td class="r">'+esc(money(l.unit_price))+'</td>'
      +'<td class="r">'+Number(l.discount||0)+' %</td>'
      +'<td class="r"><b>'+esc(money(totalLinea(l)))+'</b></td>'
      +'<td class="crmAcc"><button type="button" class="danger" data-quitar="'+esc(l.id)+'" title="Quitar la línea">×</button></td></tr>';
    }).join('')
   +'</tbody><tfoot><tr><td colspan="4"><b>Total</b></td><td class="r"><b>'+esc(money(sumaLineas()))+'</b></td><td></td></tr></tfoot>'
   +'</table></div>'
   :'<div class="crmVacio">Ninguna línea todavía: el importe es el que se haya escrito arriba.</div>')
  +'</div>';
}

/* ---- guardar ---- */
/* Lo que NUNCA se envía: reference (la pone una secuencia de la base, y dos
   pestañas calculándola en el navegador darían el mismo número) y
   weighted_amount (columna calculada). */
function leerFicha(){
 const titulo=val('crmOTitulo');
 if(!titulo){msg('La oportunidad necesita un título.','err');return null}
 const tipo=val('crmOTipo')||'cliente';
 const quien=tipo==='cliente'?val('crmOCliente'):val('crmOProspecto');
 if(!quien){msg(tipo==='cliente'?'Elige el cliente de la oportunidad.':'Elige el prospecto de la oportunidad.','err');return null}
 const etapa=val('crmOEtapa');
 const e=etapaDe(etapa);
 if(!e){msg('Elige una etapa.','err');return null}
 const motivo=nulo(val('crmOMotivoF'));
 if(e.is_lost&&!motivo){msg('Una oportunidad perdida necesita un motivo.','err');return null}
 const prob=parseInt(val('crmOProb'),10);
 const imp=parseFloat(String(val('crmOImporte')).replace(',','.'));
 const d={
  title:titulo,
  customer_id:tipo==='cliente'?quien:null,
  lead_id:tipo==='cliente'?null:quien,
  contact_id:nulo(val('crmOContacto')),
  stage_id:etapa,
  probability:Number.isFinite(prob)?Math.min(100,Math.max(0,prob)):0,
  amount:lineas.length?sumaLineas():(Number.isFinite(imp)&&imp>=0?imp:0),
  expected_close_date:nulo(val('crmOCierre')),
  priority:val('crmOPri')||'media',
  owner_id:nulo(val('crmOResp')),
  source_id:nulo(val('crmOOrigen')),
  description:nulo(val('crmODesc')),
  competitors:nulo(val('crmOCompe')),
 };
 Object.assign(d,sellos(e,motivo));
 return d;
}
/* Ganada, perdida o en curso: los tres sellos van juntos y son excluyentes.
   Dejar un lost_at viejo al reabrir una oportunidad la dejaría ganada y
   perdida a la vez, que es justo lo que prohíbe crm_opp_no_ganada_y_perdida. */
function sellos(e,motivo){
 const ahora=new Date().toISOString();
 if(e.is_won)return {won_at:ahora,lost_at:null,lost_reason_id:null};
 if(e.is_lost)return {lost_at:ahora,won_at:null,lost_reason_id:motivo||null};
 return {won_at:null,lost_at:null,lost_reason_id:null};
}
async function guardar(){
 const d=leerFicha();
 if(!d)return;
 try{
  let r;
  if(abierto&&abierto.id)r=await C().update('crm_opportunities',abierto.id,d);
  else{d.created_by=await quienSoy();d.active=true;r=await C().insert('crm_opportunities',d)}
  if(r.error)throw r.error;
  await cargar();
  vista='embudo';abierto=null;lineas=[];
  pintar('Oportunidad guardada.','ok');
 }catch(e){fallo(e,'No se pudo guardar la oportunidad')}
}
async function mover(id,etapaId){
 const o=opos.find(x=>String(x.id)===String(id));
 const e=etapaDe(etapaId);
 if(!o||!e)return;
 if(String(o.stage_id)===String(e.id))return;
 if(e.is_lost){perdiendo={id:id,etapa:etapaId};pintar();return}
 try{
  const d=Object.assign({stage_id:e.id,probability:e.is_won?100:Number(e.default_probability||0)},sellos(e,null));
  const r=await C().update('crm_opportunities',id,d);
  if(r.error)throw r.error;
  await cargar();
  pintar('«'+o.title+'» pasa a '+e.name+'.','ok');
 }catch(err){fallo(err,'No se pudo mover la oportunidad')}
}
async function darPorPerdida(){
 if(!perdiendo)return;
 const motivo=val('crmOMotivo');
 if(!motivo){msg('Elige un motivo.','err');return}
 const e=etapaDe(perdiendo.etapa);
 try{
  const d=Object.assign({stage_id:perdiendo.etapa,probability:0},sellos(e,motivo));
  const r=await C().update('crm_opportunities',perdiendo.id,d);
  if(r.error)throw r.error;
  perdiendo=null;
  await cargar();
  pintar('Oportunidad dada por perdida, con su motivo.','ok');
 }catch(err){fallo(err,'No se pudo dar por perdida')}
}
async function abrir(id){
 try{
  await cargarProductos();
  const r=await C().list('crm_opportunities',{select:FORM,eq:{id:id},limit:1});
  if(r.error)throw r.error;
  const o=(r.data||[])[0];
  if(!o){msg('Esa oportunidad ya no existe.','err');return}
  await cargarLineas(id);
  abierto=o;vista='ficha';pintar();
 }catch(e){fallo(e,'No se pudo abrir la oportunidad')}
}

/* ---- líneas ---- */
/* El importe de la oportunidad se recalcula en cuanto cambian las líneas: si
   no, el embudo enseñaría una cifra vieja y nadie sabría cuál es la buena. */
async function sincronizarImporte(){
 if(!abierto||!abierto.id)return;
 const total=sumaLineas();
 const r=await C().update('crm_opportunities',abierto.id,{amount:total});
 if(r.error)throw r.error;
 abierto.amount=total;
}
async function anadirLinea(){
 if(!abierto||!abierto.id)return;
 const pid=val('crmLProd');
 if(!pid){msg('Elige un producto.','err');return}
 const cant=parseFloat(String(val('crmLCant')).replace(',','.'));
 const precio=parseFloat(String(val('crmLPrecio')).replace(',','.'));
 const dto=parseFloat(String(val('crmLDto')).replace(',','.'))||0;
 if(!(cant>0)){msg('La cantidad tiene que ser mayor que cero.','err');return}
 /* Un precio vacío se convertiría en 0 con Number(''), y eso es regalar el
    producto. Se exige que esté escrito; un 0 explícito sí vale. */
 if(!Number.isFinite(precio)||precio<0){msg('Escribe un precio unitario.','err');return}
 if(dto<0||dto>100){msg('El descuento va de 0 a 100.','err');return}
 try{
  const r=await C().insert('crm_opportunity_lines',{opportunity_id:abierto.id,product_id:pid,
   quantity:cant,unit_price:precio,discount:dto,position:lineas.length});
  if(r.error)throw r.error;
  await cargarLineas(abierto.id);
  await sincronizarImporte();
  pintar('Producto añadido.','ok');
 }catch(e){fallo(e,'No se pudo añadir el producto')}
}
async function quitarLinea(id){
 try{
  const r=await C().remove('crm_opportunity_lines',id);
  if(r.error)throw r.error;
  await cargarLineas(abierto.id);
  await sincronizarImporte();
  pintar('Producto quitado.','ok');
 }catch(e){fallo(e,'No se pudo quitar el producto')}
}

/* ---- pintar y conectar ---- */
function pintar(aviso,tipo){
 const s=CRM.section();
 s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>'
  +(perdiendo?panelPerdida():vista==='ficha'?ficha():embudo());
 CRM.bind(s);
 conectar();
 if(aviso)msg(aviso,tipo);
}
function conectar(){
 const s=CRM.section();
 const b=$('crmOBusca');
 if(b)b.oninput=()=>{
  busca=b.value;pintar();
  const n=$('crmOBusca');
  if(n){n.focus();try{n.setSelectionRange(n.value.length,n.value.length)}catch(e){}}
 };
 const nv=$('crmONueva');
 if(nv)nv.onclick=()=>{abierto=nueva();lineas=[];vista='ficha';pintar()};
 s.querySelectorAll('[data-mover]').forEach(x=>{x.onchange=()=>mover(x.dataset.mover,x.value)});
 s.querySelectorAll('[data-oportunidad]').forEach(x=>{x.onclick=e=>{
  if(e.target.closest('select'))return;
  abrir(x.dataset.oportunidad);
 }});
 const t=$('crmOTipo');
 if(t)t.onchange=()=>{
  const cli=t.value==='cliente';
  const a=$('crmOCajaCliente'),p=$('crmOCajaProspecto');
  if(a)a.hidden=!cli;
  if(p)p.hidden=cli;
  refrescarContactos();
 };
 const sc=$('crmOCliente');if(sc)sc.onchange=refrescarContactos;
 const sp=$('crmOProspecto');if(sp)sp.onchange=refrescarContactos;
 /* Cambiar de etapa pone la probabilidad de esa etapa, que es para lo que
    existe default_probability. Sigue pudiéndose corregir a mano después. */
 const se=$('crmOEtapa');
 if(se)se.onchange=()=>{
  const e=etapaDe(se.value);
  const p=$('crmOProb');
  if(e&&p)p.value=e.is_won?100:e.is_lost?0:Number(e.default_probability||0);
 };
 const g=$('crmOGuardar');if(g)g.onclick=guardar;
 const c=$('crmOCancelar');if(c)c.onclick=()=>{vista='embudo';abierto=null;lineas=[];pintar()};
 const add=$('crmLAdd');if(add)add.onclick=anadirLinea;
 const pr=$('crmLProd');
 if(pr)pr.onchange=()=>{
  const p=productos.find(x=>String(x.id)===String(pr.value));
  const campoPrecio=$('crmLPrecio');
  if(p&&campoPrecio)campoPrecio.value=Number(p.sale_price||0);
 };
 s.querySelectorAll('[data-quitar]').forEach(x=>{x.onclick=()=>quitarLinea(x.dataset.quitar)});
 const ok=$('crmOPerder');if(ok)ok.onclick=darPorPerdida;
 const no=$('crmOPerderNo');if(no)no.onclick=()=>{perdiendo=null;pintar()};
}
/* El desplegable de contactos depende de la ficha elegida, así que se rehace
   solo en vez de repintar la pantalla y perder lo escrito. */
function refrescarContactos(){
 const t=$('crmOTipo'),sel=$('crmOContacto');
 if(!t||!sel)return;
 const tipo=t.value==='prospecto'?'prospecto':'cliente';
 const quien=tipo==='cliente'?val('crmOCliente'):val('crmOProspecto');
 sel.innerHTML=opciones(contactosDe(tipo,quien).map(k=>[k.id,nombreContacto(k)]),'','— sin contacto —');
}
function css(){
 if($('crmOpoCss'))return;
 const s=document.createElement('style');s.id='crmOpoCss';
 s.textContent='#crm [hidden]{display:none!important}'
 +'#crm .crmTablero{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(228px,1fr);gap:10px;overflow-x:auto;padding-bottom:8px;align-items:start}'
 +'#crm .crmTablero .crmCol{background:#f8fafb;border:1px solid #e4ebee;border-radius:11px;padding:9px;min-width:0}'
 +'#crm .crmColCab{display:flex;align-items:baseline;gap:7px;flex-wrap:wrap;padding:2px 3px 9px;border-bottom:1px solid #e4ebee;margin-bottom:9px}'
 +'#crm .crmColCab b{font-size:12.5px;color:#18324a;flex:1 1 auto;min-width:0}'
 +'#crm .crmColCab i{font-style:normal;font-weight:800;color:#087c8b;font-size:15px}'
 +'#crm .crmColCab small{width:100%;color:#71808a;font-size:11px}'
 +'#crm .crmColVacia{text-align:center;color:#b3c0c7;padding:10px 0}'
 +'#crm .crmTarjeta{background:#fff;border:1px solid #e2e8ec;border-radius:10px;padding:9px;margin-bottom:8px;cursor:pointer}'
 +'#crm .crmTarjeta:hover{border-color:#087c8b}'
 +'#crm .crmTarjeta.tarde{border-left:3px solid #c94f45}'
 +'#crm .crmTarjTit{display:flex;gap:6px;align-items:flex-start;justify-content:space-between}'
 +'#crm .crmTarjTit b{font-size:12.5px;color:#18324a;min-width:0}'
 +'#crm .crmTarjPie{display:flex;justify-content:space-between;align-items:baseline;margin-top:6px}'
 +'#crm .crmTarjPie b{color:#087c8b;font-size:14px}'
 +'#crm .crmTarjPie span{color:#71808a;font-size:11px;font-weight:700}'
 +'#crm .crmMover{margin-top:8px;font-size:12px;min-height:38px;padding:6px}'
 +'#crm .crmPerdida .crmForm{max-width:420px}'
 /* En el teléfono el tablero se apila: ocho columnas de arrastre lateral son
    inservibles con el pulgar. Cada etapa queda una debajo de otra. */
 +'@media(max-width:760px){#crm .crmTablero{grid-auto-flow:row;grid-auto-columns:auto;overflow-x:visible}}';
 document.head.appendChild(s);
}

async function abrirPantalla(){
 CRM.css();css();
 const s=CRM.section();
 if(cargando)return;cargando=true;
 s.innerHTML=CRM.cabecera(LEAD)+'<div class="card"><div class="crmVacio">Cargando el embudo…</div></div>';
 CRM.bind(s);
 try{
  await cargar();
  vista='embudo';abierto=null;lineas=[];perdiendo=null;
  pintar();
 }catch(e){
  s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>';
  CRM.bind(s);
  fallo(e,'No se pudo cargar el embudo');
 }finally{cargando=false}
 window.scrollTo({top:0,behavior:'smooth'});
}

CRM.registrar('oportunidades','Oportunidades',abrirPantalla);
window.GamaCRMOpportunities={open:abrirPantalla};
})();
