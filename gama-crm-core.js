/* GAMA — CRM · núcleo del módulo.

   Aquí vive lo que comparten todas las pantallas del CRM: la capa de datos,
   los permisos y los referenciales. Las pantallas se apoyan en esto y no
   hablan con la nube por su cuenta, para que la disciplina de columnas sea de
   un sitio y no de cada una.

   Dos reglas que este archivo hace cumplir:

   · Nunca se pide «*». products guarda la foto de cada artículo en base64 y
     customers acabará teniendo notas largas: una lista que pide todo se trae
     el catálogo entero de fotos para enseñar seis campos. Ya pasó en Compras.

   · Nunca se cuenta trayéndose las filas. Los KPIs se piden con count exacto y
     head:true —la nube devuelve el número y ni una fila—, porque el §35 habla
     de 50.000 oportunidades y 1.000.000 de líneas de historia.

   Lo que NO hay aquí, a propósito: ninguna copia de clientes, productos ni
   usuarios. El CRM lee las tablas que ya existen. */
(function(){
'use strict';
if(window.GamaCRM)return;

const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});

/* ---- piezas compartidas ----
   Cada pantalla del CRM pinta formularios, escribe fechas y compara textos.
   Escribirlo una vez aqui es lo que hace que la siguiente pantalla sea una
   pantalla y no otra copia de las mismas veinte lineas. */
const norm=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const terms=q=>norm(q).split(/\s+/).filter(Boolean);
/* Para comparar identificaciones y telefonos: «1790012345001» y
   «1790012345-001» son el mismo, y quien los teclea no siempre pone el guion
   en el mismo sitio. */
const clave=v=>norm(v).replace(/[^a-z0-9]/g,'');
const valor=id=>{const e=$(id);return e?String(e.value||'').trim():''};
const nulo=v=>v===''?null:v;

function fecha(iso){
 if(!iso)return '—';
 const d=new Date(iso);
 return isNaN(d.getTime())?'—':d.toLocaleDateString('es-EC',{day:'2-digit',month:'2-digit',year:'numeric'});
}
/* El navegador da y espera hora local en datetime-local; la base guarda UTC.
   La conversion va aqui, en un sitio, y no en cada campo. */
function paraInput(iso){
 if(!iso)return '';
 const d=new Date(iso);if(isNaN(d.getTime()))return '';
 const p=n=>String(n).padStart(2,'0');
 return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+'T'+p(d.getHours())+':'+p(d.getMinutes());
}
function desdeInput(v){if(!v)return null;const d=new Date(v);return isNaN(d.getTime())?null:d.toISOString()}

function campo(id,label,val,tipo){
 return '<div><label data-gi-live for="'+id+'">'+esc(label)+'</label><input id="'+id+'" type="'+(tipo||'text')+'" value="'+esc(val||'')+'"></div>';
}
function campoSelect(id,label,mapa,sel){
 return '<div><label data-gi-live for="'+id+'">'+esc(label)+'</label><select id="'+id+'" data-gama-nofind>'
  +Object.keys(mapa).map(k=>'<option value="'+k+'"'+(sel===k?' selected':'')+'>'+esc(mapa[k])+'</option>').join('')
  +'</select></div>';
}
function opciones(pares,sel,vacio){
 return '<option data-gi-live value="">'+esc(vacio||'— sin asignar —')+'</option>'
  +pares.map(p=>'<option value="'+esc(p[0])+'"'+(String(sel||'')===String(p[0])?' selected':'')+'>'+esc(p[1])+'</option>').join('');
}

/* Todas las pantallas del CRM escriben en el mismo sitio, #crmMsg, que cada
   una repinta con su contenido. */
function msg(t,tipo){const m=$('crmMsg');if(!m)return;m.className='crmMsg'+(tipo?' '+tipo:'');m.textContent=t||''}
function error(e,que,donde){
 console.warn('[GAMA CRM'+(donde?' '+donde:'')+']',que,e);
 msg(que+': '+((e&&(e.message||e.details))||e),'err');
}

/* Las columnas que pide cada tabla, escritas una vez. */
const COLS={
 stages:'id,name,sort_order,default_probability,is_won,is_lost,active',
 sources:'id,name,sort_order,active',
 lostReasons:'id,name,sort_order,active',
 leads:'id,kind,first_name,last_name,company,job_title,email,phone,city,industry,source_id,owner_id,status,priority,score,last_interaction_at,next_followup_at,converted_customer_id,active,created_at',
 opportunities:'id,reference,title,customer_id,lead_id,contact_id,owner_id,source_id,stage_id,amount,probability,weighted_amount,expected_close_date,priority,lost_reason_id,quote_invoice_id,won_at,lost_at,active,created_at',
 activities:'id,kind,subject,status,priority,owner_id,due_at,done_at,lead_id,customer_id,contact_id,opportunity_id,invoice_id,created_at',
 contacts:'id,customer_id,lead_id,first_name,last_name,job_title,email,phone,decision_role,is_primary,active',
};

/* El rol de la sesión llega en dos vocabularios: el del navegador
   (admin/commercial) y el de la base (administrador/comercial). Es una
   divergencia vieja de GAMA que ya costó un fallo en producción, así que aquí
   se aceptan los dos en vez de fingir que sólo existe uno. */
const ADMIN=['admin','administrador'];
const COMERCIAL=['commercial','comercial'];
function rol(){try{return String(JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role||'')}catch(e){return ''}}
function esAdmin(){return ADMIN.includes(rol())}
function puedeUsar(){return esAdmin()||COMERCIAL.includes(rol())}

/* ---- referenciales ----
   Etapas, orígenes y motivos cambian una vez al año: se leen una vez por
   sesión y se guardan. Volver a pedirlos en cada pantalla sería tráfico por
   datos que no se mueven. */
let ref=null;
async function referenciales(recargar){
 if(ref&&!recargar)return ref;
 const api=C();if(!api)throw new Error('La conexión con la nube de Coco ERP no está disponible.');
 const [e,o,m]=await Promise.all([
  api.list('crm_pipeline_stages',{select:COLS.stages,order:'sort_order',ascending:true}),
  api.list('crm_sources',{select:COLS.sources,order:'sort_order',ascending:true}),
  api.list('crm_lost_reasons',{select:COLS.lostReasons,order:'sort_order',ascending:true}),
 ]);
 if(e.error)throw e.error;
 ref={
  etapas:(e.data||[]).filter(x=>x.active!==false),
  origenes:o.error?[]:(o.data||[]).filter(x=>x.active!==false),
  motivos:m.error?[]:(m.data||[]).filter(x=>x.active!==false),
 };
 return ref;
}

/* Los comerciales son los usuarios que ya existen. No hay tabla propia.

   Se leen de crm_team y NO de profiles: la politica profiles_self_read solo
   deja leer la fila propia salvo al administrador, asi que un comercial veia
   una lista de una sola persona —el mismo— y un guion en los prospectos de sus
   companeros. crm_team es una vista de solo lectura sobre profiles que expone
   id, nombre, correo y perfil de los usuarios comerciales activos, y solo a
   administrador y comercial. La politica de profiles sigue intacta.

   La vista ya filtra por activo y por perfil, asi que aqui no se vuelve a
   filtrar: la frontera esta en la base, que es donde no se puede saltar. */
let personas=null;
async function comerciales(){
 if(personas)return personas;
 const r=await C().list('crm_team',{select:'id,full_name,email,role',order:'full_name',ascending:true});
 personas=r.error?[]:(r.data||[]);
 return personas;
}
const nombreDe=(id,lista)=>{const p=(lista||[]).find(x=>String(x.id)===String(id));return p?(p.full_name||p.email||'—'):'—'};

/* ---- consultas ----
   count:'exact' con head:true pide a la nube el número sin traer ni una fila.
   Es la diferencia entre contar 50.000 oportunidades y descargarlas. */
async function cuantos(tabla,filtros){
 const r=await C().list(tabla,Object.assign({select:'id',count:'exact',head:true,limit:1},filtros||{}));
 if(r.error)throw r.error;
 return Number(r.count||0);
}
/* Sumar sí obliga a traer la columna, así que se pide SÓLO esa columna. */
async function suma(tabla,columna,filtros){
 const r=await C().list(tabla,Object.assign({select:columna},filtros||{}));
 if(r.error)throw r.error;
 return (r.data||[]).reduce((t,f)=>t+Number(f[columna]||0),0);
}

async function resumen(){
 const {etapas}=await referenciales();
 const ganada=etapas.find(e=>e.is_won),perdida=etapas.find(e=>e.is_lost);
 const abiertas=etapas.filter(e=>!e.is_won&&!e.is_lost).map(e=>e.id);
 const hoy=new Date().toISOString();

 const [prospectos,porCalificar,oportunidades,ganadas,perdidas,tareas,vencidas,clientes]=await Promise.all([
  cuantos('crm_leads',{eq:{active:true}}),
  cuantos('crm_leads',{eq:{active:true,status:'nuevo'}}),
  abiertas.length?cuantos('crm_opportunities',{eq:{active:true},in:{stage_id:abiertas}}):0,
  ganada?cuantos('crm_opportunities',{eq:{stage_id:ganada.id}}):0,
  perdida?cuantos('crm_opportunities',{eq:{stage_id:perdida.id}}):0,
  cuantos('crm_activities',{in:{status:['pendiente','en_curso']}}),
  cuantos('crm_activities',{in:{status:['pendiente','en_curso']},lt:{due_at:hoy}}),
  cuantos('customers',{eq:{active:true}}),
 ]);

 /* El embudo sólo suma lo que sigue vivo: contar lo ganado y lo perdido dentro
    del «potencial» daría una cifra que no significa nada. */
 const [potencial,ponderado]=abiertas.length?await Promise.all([
  suma('crm_opportunities','amount',{eq:{active:true},in:{stage_id:abiertas}}),
  suma('crm_opportunities','weighted_amount',{eq:{active:true},in:{stage_id:abiertas}}),
 ]):[0,0];
 const ganado=ganada?await suma('crm_opportunities','amount',{eq:{stage_id:ganada.id}}):0;

 const cerradas=ganadas+perdidas;
 return {prospectos,porCalificar,clientes,oportunidades,ganadas,perdidas,tareas,vencidas,
  potencial,ponderado,ganado,
  conversion:cerradas?Math.round(ganadas/cerradas*100):null,
  medio:oportunidades?potencial/oportunidades:0};
}

/* Cuántas oportunidades hay en cada etapa y cuánto valen: la cabecera de cada
   columna del embudo (§6). Se pide una vez y se reparte, en vez de una
   consulta por etapa. */
async function embudo(){
 const {etapas}=await referenciales();
 const r=await C().list('crm_opportunities',{select:'id,stage_id,amount,weighted_amount',eq:{active:true}});
 if(r.error)throw r.error;
 const filas=r.data||[];
 return etapas.map(e=>{
  const suyas=filas.filter(f=>String(f.stage_id)===String(e.id));
  return {etapa:e,n:suyas.length,
   total:suyas.reduce((t,f)=>t+Number(f.amount||0),0),
   ponderado:suyas.reduce((t,f)=>t+Number(f.weighted_amount||0),0)};
 });
}

/* ---- pantalla ----

   El CRM es UN módulo con varias pantallas y UNA sola tarjeta en el menú: el
   control de acceso decide una vez, en la puerta, y a partir de ahí se navega
   por dentro sin pasar por el menú. Cada pantalla se apunta aquí con su
   nombre y su función de apertura —registrar()— y la barra de navegación se
   pinta sola, así que añadir la siguiente (contactos, oportunidades, agenda)
   es una línea y no otra barra escrita a mano que se olvide de actualizar. */
function section(){
 let s=$('crm');
 if(!s){s=document.createElement('section');s.id='crm';(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
const PANTALLAS=[];
let actual='panel';
function registrar(id,label,abrir){if(!PANTALLAS.some(p=>p.id===id))PANTALLAS.push({id,label,abrir})}
function nav(){
 if(PANTALLAS.length<2)return '';
 return `<div class="crmNav">${PANTALLAS.map(p=>
  `<button type="button" class="arcButton ${p.id===actual?'on':''}" data-crm-ir="${esc(p.id)}" data-gi-live>${esc(p.label)}</button>`).join('')}</div>`;
}
/* La cabecera común de GAMA más la navegación del módulo. Todas las pantallas
   del CRM empiezan por aquí, para que el título y el botón de volver estén
   siempre en el mismo sitio. */
function cabecera(lead){
 return window.GamaUI.header({title:'🤝 CRM',lead:lead||'Prospectos, oportunidades y actividad comercial.'})+nav();
}
/* Conecta lo que la cabecera trae: el botón de volver y la navegación. Se
   llama después de cada innerHTML, que no arrastra los onclick. */
function bind(root){
 const r=root||section();
 window.GamaUI.bindBack(r);
 r.querySelectorAll('[data-crm-ir]').forEach(b=>{b.onclick=()=>ir(b.dataset.crmIr)});
}
function ir(id){
 const p=PANTALLAS.find(x=>x.id===id)||PANTALLAS[0];
 if(!p)return Promise.resolve();
 actual=p.id;
 return Promise.resolve(p.abrir());
}

function css(){ /* Styles are compiled in architect-components.css. */ }
function kpi(etiqueta,valor,pie){
 return `<div class="crmKpi"><span>${esc(etiqueta)}</span><b>${esc(valor)}</b>${pie?`<small>${esc(pie)}</small>`:''}</div>`;
}
function pintar(r,cols){
 const s=section();
 window.ArcUI.render(s,`${cabecera()}
 <div id="crmMsg" class="crmMsg"></div>
 <div class="crmKpis">
  ${kpi('Embudo abierto',money(r.potencial),r.oportunidades+' oportunidad(es)')}
  ${kpi('Valor ponderado',money(r.ponderado),'según la probabilidad de cada una')}
  ${kpi('Ganado',money(r.ganado),r.ganadas+' cerrada(s)')}
  ${kpi('Tasa de conversión',r.conversion===null?'—':r.conversion+'%',r.conversion===null?'sin nada cerrado todavía':r.ganadas+' de '+(r.ganadas+r.perdidas))}
 </div>
 <div class="crmKpis">
  ${kpi('Prospectos',r.prospectos,r.porCalificar+' sin contactar')}
  ${kpi('Clientes',r.clientes,'en la ficha de Clientes')}
  ${kpi('Tareas abiertas',r.tareas,r.vencidas?r.vencidas+' vencida(s)':'ninguna vencida')}
  ${kpi('Oportunidad media',money(r.medio),'sobre las abiertas')}
 </div>
 <div class="arcPanel card">
  <h3 data-gi=33bcdbcca6bc>Embudo comercial</h3>
  ${cols.length?`<div class="crmEmbudo">${cols.map(c=>`
   <div class="crmCol${c.etapa.is_won?' ganada':c.etapa.is_lost?' perdida':''}">
    <b>${esc(c.etapa.name)}</b><i>${c.n}</i>
    <small>${money(c.total)}</small>
    ${c.etapa.is_won||c.etapa.is_lost?'':`<small>ponderado ${money(c.ponderado)}</small>`}
   </div>`).join('')}</div>`
  :'<div class="crmVacio" data-gi=724149b9b88b>Todavía no hay etapas configuradas.</div>'}
  ${r.oportunidades===0&&r.ganadas===0&&r.perdidas===0
   ? '<div class="crmVacio" data-gi=4b416698f585>Ninguna oportunidad todavía. En cuanto se cree la primera, el embudo se llena solo.</div>':''}
 </div>`);
 bind(s);
}
function fallo(e){
 const m=$('crmMsg');
 const texto='No se pudieron cargar los datos del CRM: '+((e&&(e.message||e.details))||e);
 console.warn('[GAMA CRM]',e);
 if(m){m.className='crmMsg err';m.textContent=texto}
 else window.ArcUI.render(section(),`${cabecera()}<div class="crmMsg err">${esc(texto)}</div>`);
 bind(section());
}

let cargando=false;
async function panel(){
 css();
 const s=section();
 if(cargando)return;cargando=true;
 window.ArcUI.render(s,`${cabecera()}<div class="arcPanel card"><div class="crmVacio" data-gi=86bffaa6fba4>Cargando el CRM…</div></div>`);
 bind(s);
 try{
  const [r,cols]=await Promise.all([resumen(),embudo()]);
  pintar(r,cols);
 }catch(e){fallo(e)}
 finally{cargando=false}
 window.scrollTo({top:0,behavior:'smooth'});
}
registrar('panel','Cuadro de mando',panel);

/* Enciende la sección del CRM y apaga todo lo demás. Es lo que hace cualquier
   módulo de GAMA al abrirse; vive aquí para que las pantallas del CRM no lo
   repitan. */
function mostrar(){
 window.ArcRouter.show('crm');
 $('mainmenu')?.setAttribute('hidden','');
}
async function open(){
 css();
 const s=section();
 mostrar();
 if(!puedeUsar()){
  window.ArcUI.render(s,`${window.GamaUI.header({title:'🤝 CRM',lead:'Prospectos, oportunidades y actividad comercial.'})}
   <div class="arcPanel card"><div class="crmVacio" data-gi=0db875f7987c>Tu perfil no tiene acceso al CRM.</div></div>`);
  window.GamaUI.bindBack(s);return;
 }
 await ir(actual);
}

window.GamaCRM={
 open,
 // La capa de datos, para las pantallas que vienen después.
 cols:COLS, referenciales, comerciales, nombreDe, resumen, embudo, cuantos, suma,
 puedeUsar, esAdmin, money, esc,
 // El armazón de pantalla: registrarse, pintarse dentro y navegar.
 registrar, ir, cabecera, bind, section, mostrar, css,
 // Las piezas que repite cada pantalla: formularios, fechas, textos, avisos.
 util:{norm,terms,clave,valor,nulo,fecha,paraInput,desdeInput,campo,campoSelect,opciones,msg,error},
};
window.GamaOpenCRM=open;
})();
