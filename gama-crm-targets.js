/* GAMA — CRM · Objetivos.

   Cuánto tiene que vender cada comercial en un mes, un trimestre o un año, y
   cuánto lleva. Sin esto el embudo dice cuánto hay, pero no si es suficiente,
   que es la pregunta de dirección.

   Un objetivo es de UNA persona o de LA EMPRESA (profile_id nulo), y hay uno
   solo por periodo: la base lo impone con dos índices únicos parciales
   —crm_targets_persona_idx y crm_targets_empresa_idx—, así que volver a fijar
   el objetivo de un mes ya fijado tiene que CORREGIR el que hay y no crear un
   segundo. Aquí se busca antes y se actualiza; si no, Postgres lo rechazaría
   con un error de clave duplicada.

   Lo conseguido se cuenta como en Informes: por fecha de CIERRE de la
   oportunidad ganada, no por cuándo nació. Es la misma definición en las dos
   pantallas a propósito — si difirieran, dirección y comercial acabarían
   discutiendo sobre dos números que se llaman igual.

   Sobre quién puede fijar objetivos: el formulario sólo se le enseña al
   administrador. Eso es una comodidad de pantalla, NO una frontera de
   seguridad: la política RLS de crm_targets admite escribir a los dos perfiles
   comerciales, igual que en el resto del CRM. Si los objetivos tienen que ser
   sólo del administrador de verdad, eso es una migración que cambia la
   política, no un if en el navegador. */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] Objetivos necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=CRM.esc,money=CRM.money;
const U=CRM.util;
const val=U.valor,nulo=U.nulo,opciones=U.opciones,msg=U.msg;
const fallo=(e,que)=>U.error(e,que,'Objetivos');

const LEAD='Objetivos: cuánto hay que vender, y cuánto se lleva.';
const COLS='id,profile_id,period_kind,period_start,amount_goal,notes';
const PERIODOS={mes:'Mensual',trimestre:'Trimestral',anio:'Anual'};
const TRIMESTRES={'1':'T1 · ene–mar','4':'T2 · abr–jun','7':'T3 · jul–sep','10':'T4 · oct–dic'};

let objetivos=[],ganadas=[],gente=[];
let tipo='mes',abierto=null,cargando=false;

let mi;
async function quienSoy(){
 if(mi!==undefined)return mi;
 try{const s=await C().getSession();mi=(s&&s.data&&s.data.session&&s.data.session.user&&s.data.session.user.id)||null}
 catch(e){mi=null}
 return mi;
}

/* ---- fechas del periodo ---- */
const dosDig=n=>String(n).padStart(2,'0');
function fin(inicio,kind){
 const [a,m]=String(inicio).split('-').map(Number);
 const meses=kind==='anio'?12:kind==='trimestre'?3:1;
 const d=new Date(Date.UTC(a,(m-1)+meses,1));
 return d.getUTCFullYear()+'-'+dosDig(d.getUTCMonth()+1)+'-01';
}
function etiqueta(inicio,kind){
 const [a,m]=String(inicio).split('-').map(Number);
 if(kind==='anio')return String(a);
 if(kind==='trimestre')return (TRIMESTRES[String(m)]||('mes '+m))+' · '+a;
 return new Date(Date.UTC(a,m-1,1)).toLocaleDateString('es-EC',{month:'long',year:'numeric',timeZone:'UTC'});
}
/* El periodo que corre ahora mismo, para proponerlo al crear uno nuevo. */
function periodoDeHoy(kind){
 const h=new Date();
 const a=h.getFullYear();
 if(kind==='anio')return a+'-01-01';
 if(kind==='trimestre')return a+'-'+dosDig(Math.floor(h.getMonth()/3)*3+1)+'-01';
 return a+'-'+dosDig(h.getMonth()+1)+'-01';
}

/* ---- datos ---- */
async function cargar(){
 const api=C();
 if(!api)throw new Error('La conexión con la nube de GAMA no está disponible.');
 const [o,g]=await Promise.all([
  api.list('crm_targets',{select:COLS,eq:{period_kind:tipo},order:'period_start',ascending:false}),
  CRM.comerciales(),
 ]);
 if(o.error)throw o.error;
 objetivos=o.data||[];
 gente=g||[];
 await quienSoy();
 await cargarGanadas();
}
/* UNA consulta para todos los objetivos de la pantalla, acotada al periodo más
   antiguo que se enseña. Una por objetivo serían doce consultas para ver un
   año, y el reparto se hace igual de bien aquí. */
async function cargarGanadas(){
 ganadas=[];
 if(!objetivos.length)return;
 const inicios=objetivos.map(o=>o.period_start).sort();
 const desde=inicios[0];
 const hasta=fin(inicios[inicios.length-1],tipo);
 const r=await C().list('crm_opportunities',
  {select:'id,amount,owner_id,won_at',gte:{won_at:desde},lt:{won_at:hasta}});
 if(r.error)throw r.error;
 ganadas=(r.data||[]).filter(x=>x.won_at);
}
/* Un objetivo sin profile_id es de la empresa: cuenta lo ganado por todos. */
function conseguido(o){
 const desde=o.period_start,hasta=fin(o.period_start,o.period_kind);
 return ganadas.filter(g=>{
  const d=String(g.won_at).slice(0,10);
  if(d<desde||d>=hasta)return false;
  return o.profile_id?String(g.owner_id||'')===String(o.profile_id):true;
 }).reduce((t,g)=>t+Number(g.amount||0),0);
}
const deQuien=o=>o.profile_id?CRM.nombreDe(o.profile_id,gente):'Toda la empresa';

/* ---- pantalla ---- */
function barra(pc){
 const clase=pc>=100?'ok':pc>=70?'':'ko';
 return '<div class="crmBarra"><i class="'+clase+'" style="width:'+Math.min(100,pc)+'%"></i></div>';
}
function lista(){
 const filas=objetivos.slice().sort((a,b)=>
  String(b.period_start).localeCompare(String(a.period_start))
  ||String(deQuien(a)).localeCompare(String(deQuien(b)),'es'));
 return '<div class="card">'
  +'<div class="crmBar">'
   +'<select id="crmTTipo" data-gama-nofind aria-label="Tipo de periodo">'
    +Object.keys(PERIODOS).map(k=>'<option value="'+k+'"'+(tipo===k?' selected':'')+'>'+esc(PERIODOS[k])+'</option>').join('')
   +'</select><span></span>'
   +(CRM.esAdmin()?'<button type="button" class="primary" id="crmTNuevo">+ Fijar un objetivo</button>':'<span></span>')
  +'</div>'
  +(filas.length?'<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
    +'<th>Periodo</th><th>Quién</th><th class="r">Objetivo</th><th class="r">Conseguido</th>'
    +'<th class="r">Avance</th><th>Peso</th>'+(CRM.esAdmin()?'<th></th>':'')+'</tr></thead><tbody>'
    +filas.map(fila).join('')+'</tbody></table></div>'
   :'<div class="crmVacio">'
    +(CRM.esAdmin()
      ?'Ningún objetivo '+PERIODOS[tipo].toLowerCase()+' todavía. Se fija con «+ Fijar un objetivo».'
      :'Ningún objetivo '+PERIODOS[tipo].toLowerCase()+' fijado todavía.')
    +'</div>')
  +'</div>';
}
function fila(o){
 const hecho=conseguido(o),meta=Number(o.amount_goal||0);
 const pc=meta>0?Math.round(hecho/meta*100):0;
 const falta=Math.max(0,meta-hecho);
 return '<tr>'
  +'<td><b>'+esc(etiqueta(o.period_start,o.period_kind))+'</b></td>'
  +'<td>'+esc(deQuien(o))+(o.profile_id?'':'<small class="crmSub">suma de todo el equipo</small>')+'</td>'
  +'<td class="r">'+esc(money(meta))+'</td>'
  +'<td class="r"><b>'+esc(money(hecho))+'</b></td>'
  +'<td class="r"><b class="'+(pc>=100?'crmVerde':'')+'">'+pc+' %</b>'
   +(falta>0?'<small class="crmSub">faltan '+esc(money(falta))+'</small>':'<small class="crmSub">cumplido</small>')+'</td>'
  +'<td>'+barra(pc)+'</td>'
  +(CRM.esAdmin()?'<td class="crmAcc">'
    +'<button type="button" data-abrir="'+esc(o.id)+'">Cambiar</button>'
    +'<button type="button" class="danger" data-quitar="'+esc(o.id)+'" title="Quitar el objetivo">×</button>'
   +'</td>':'')
  +'</tr>';
}
function nuevo(){return {period_kind:tipo,period_start:periodoDeHoy(tipo),amount_goal:0,profile_id:''}}
function ficha(){
 const o=abierto||{};
 const kind=o.period_kind||tipo;
 const [a,m]=String(o.period_start||periodoDeHoy(kind)).split('-').map(Number);
 const anios=[];
 for(let y=new Date().getFullYear()-1;y<=new Date().getFullYear()+2;y++)anios.push([String(y),String(y)]);
 return '<div class="card">'
  +'<h3>'+(o.id?'Cambiar el objetivo':'Fijar un objetivo')+'</h3>'
  +'<div class="crmForm">'
   +'<div><label for="crmTQuien">Para quién</label><select id="crmTQuien">'
    +opciones(gente.map(p=>[p.id,p.full_name||p.email]),o.profile_id,'Toda la empresa')+'</select></div>'
   +'<div><label for="crmTKind">Periodo</label><select id="crmTKind" data-gama-nofind>'
    +Object.keys(PERIODOS).map(k=>'<option value="'+k+'"'+(kind===k?' selected':'')+'>'+esc(PERIODOS[k])+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmTAnio">Año</label><select id="crmTAnio" data-gama-nofind>'
    +anios.map(x=>'<option value="'+x[0]+'"'+(String(a)===x[0]?' selected':'')+'>'+x[1]+'</option>').join('')
   +'</select></div>'
   +'<div id="crmTCajaMes"'+(kind==='mes'?'':' hidden')+'><label for="crmTMes">Mes</label><select id="crmTMes" data-gama-nofind>'
    +Array.from({length:12},(_,i)=>i+1).map(x=>'<option value="'+x+'"'+(kind==='mes'&&m===x?' selected':'')+'>'
      +esc(new Date(Date.UTC(2000,x-1,1)).toLocaleDateString('es-EC',{month:'long',timeZone:'UTC'}))+'</option>').join('')
   +'</select></div>'
   +'<div id="crmTCajaTri"'+(kind==='trimestre'?'':' hidden')+'><label for="crmTTri">Trimestre</label><select id="crmTTri" data-gama-nofind>'
    +Object.keys(TRIMESTRES).map(k=>'<option value="'+k+'"'+(kind==='trimestre'&&String(m)===k?' selected':'')+'>'+esc(TRIMESTRES[k])+'</option>').join('')
   +'</select></div>'
   +'<div><label for="crmTMeta">Objetivo en USD</label><input id="crmTMeta" type="number" min="0" step="0.01" value="'+Number(o.amount_goal||0)+'"></div>'
  +'</div>'
  +'<div class="crmNotas"><label for="crmTNotas">Notas</label><textarea id="crmTNotas" rows="3">'+esc(o.notes||'')+'</textarea></div>'
  +'<div class="crmAcciones">'
   +'<button type="button" class="primary" id="crmTGuardar">Guardar</button>'
   +'<button type="button" id="crmTCancelar">Cancelar</button>'
  +'</div></div>';
}
function leerFicha(){
 const kind=val('crmTKind')||'mes';
 const anio=parseInt(val('crmTAnio'),10);
 if(!Number.isFinite(anio)){msg('Elige un año.','err');return null}
 const mes=kind==='anio'?1:kind==='trimestre'?parseInt(val('crmTTri'),10):parseInt(val('crmTMes'),10);
 const meta=parseFloat(String(val('crmTMeta')).replace(',','.'));
 /* Un objetivo vacío se convertiría en 0 con Number(''), y un objetivo de cero
    dice que ya está cumplido antes de empezar. */
 if(!Number.isFinite(meta)||meta<0){msg('Escribe el objetivo en USD.','err');return null}
 return {
  profile_id:nulo(val('crmTQuien')),
  period_kind:kind,
  period_start:anio+'-'+dosDig(mes||1)+'-01',
  amount_goal:meta,
  notes:nulo(val('crmTNotas')),
 };
}

/* ---- acciones ---- */
/* Los índices únicos parciales sólo admiten UN objetivo por (quién, tipo,
   periodo). Se busca el que haya antes de insertar: volver a fijar el objetivo
   de un mes ya fijado tiene que corregirlo, no chocar contra Postgres. */
async function existente(d){
 const filtro={period_kind:d.period_kind,period_start:d.period_start};
 if(d.profile_id)filtro.profile_id=d.profile_id;
 const r=await C().list('crm_targets',{select:'id,profile_id',eq:filtro});
 if(r.error)throw r.error;
 return (r.data||[]).find(x=>String(x.profile_id||'')===String(d.profile_id||''))||null;
}
async function guardar(){
 const d=leerFicha();
 if(!d)return;
 try{
  const ya=abierto&&abierto.id?{id:abierto.id}:await existente(d);
  let r;
  if(ya)r=await C().update('crm_targets',ya.id,d);
  else{d.created_by=await quienSoy();r=await C().insert('crm_targets',d)}
  if(r.error)throw r.error;
  tipo=d.period_kind;
  await cargar();
  abierto=null;
  pintar(ya?'Objetivo corregido.':'Objetivo fijado.','ok');
 }catch(e){fallo(e,'No se pudo guardar el objetivo')}
}
/* Aquí sí se borra, y es lo correcto: un objetivo no es un hecho ocurrido sino
   una decisión, y una decisión se puede retirar sin perder trazabilidad de
   nada. Lo vendido sigue en las oportunidades. */
async function quitar(id){
 try{
  const r=await C().remove('crm_targets',id);
  if(r.error)throw r.error;
  await cargar();
  pintar('Objetivo retirado.','ok');
 }catch(e){fallo(e,'No se pudo retirar el objetivo')}
}
async function abrir(id){
 const o=objetivos.find(x=>String(x.id)===String(id));
 if(!o){msg('Ese objetivo ya no existe.','err');return}
 abierto=Object.assign({},o);
 pintar();
}

/* ---- pintar y conectar ---- */
function pintar(aviso,clase){
 const s=CRM.section();
 s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>'
  +(abierto?ficha():lista());
 CRM.bind(s);
 conectar();
 if(aviso)msg(aviso,clase);
}
function conectar(){
 const s=CRM.section();
 const t=$('crmTTipo');
 if(t)t.onchange=()=>{tipo=t.value;abrirPantalla(true)};
 const nv=$('crmTNuevo');
 if(nv)nv.onclick=()=>{abierto=nuevo();pintar()};
 s.querySelectorAll('[data-abrir]').forEach(x=>{x.onclick=()=>abrir(x.dataset.abrir)});
 s.querySelectorAll('[data-quitar]').forEach(x=>{x.onclick=()=>quitar(x.dataset.quitar)});
 /* Mes y trimestre se enseñan según el tipo, sin repintar: repintar borraría
    el importe que se acabara de escribir. */
 const k=$('crmTKind');
 if(k)k.onchange=()=>{
  const cm=$('crmTCajaMes'),ct=$('crmTCajaTri');
  if(cm)cm.hidden=k.value!=='mes';
  if(ct)ct.hidden=k.value!=='trimestre';
 };
 const g=$('crmTGuardar');if(g)g.onclick=guardar;
 const c=$('crmTCancelar');if(c)c.onclick=()=>{abierto=null;pintar()};
}
function css(){
 if($('crmTgtCss'))return;
 const s=document.createElement('style');s.id='crmTgtCss';
 s.textContent='#crm [hidden]{display:none!important}'
 +'#crm .crmBarra{background:#eef3f4;border-radius:999px;height:9px;overflow:hidden;min-width:70px}'
 +'#crm .crmBarra i{display:block;height:100%;background:#087c8b;border-radius:999px}'
 +'#crm .crmBarra i.ok{background:#138a69}'
 +'#crm .crmBarra i.ko{background:#c94f45}'
 +'#crm .crmVerde{color:#138a69}';
 document.head.appendChild(s);
}

async function abrirPantalla(recarga){
 CRM.css();css();
 const s=CRM.section();
 if(cargando)return;cargando=true;
 if(!recarga)s.innerHTML=CRM.cabecera(LEAD)+'<div class="card"><div class="crmVacio">Cargando objetivos…</div></div>';
 CRM.bind(s);
 try{
  await cargar();
  abierto=null;
  pintar();
 }catch(e){
  s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>';
  CRM.bind(s);
  fallo(e,'No se pudieron cargar los objetivos');
 }finally{cargando=false}
 if(!recarga)window.scrollTo({top:0,behavior:'smooth'});
}

CRM.registrar('objetivos','Objetivos',abrirPantalla);
window.GamaCRMTargets={open:abrirPantalla};
})();
