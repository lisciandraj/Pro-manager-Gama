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
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});

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
 const api=C();if(!api)throw new Error('La conexión con la nube de GAMA no está disponible.');
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

/* Los comerciales son los usuarios que ya existen. No hay tabla propia. */
let personas=null;
async function comerciales(){
 if(personas)return personas;
 const r=await C().list('profiles',{select:'id,full_name,email,role,active',order:'full_name',ascending:true});
 personas=r.error?[]:(r.data||[]).filter(p=>p.active!==false&&[...ADMIN,...COMERCIAL].includes(String(p.role||'')));
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

/* ---- pantalla ---- */
function section(){
 let s=$('crm');
 if(!s){s=document.createElement('section');s.id='crm';(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
function css(){
 if($('crmCss'))return;
 const s=document.createElement('style');s.id='crmCss';
 s.textContent=`#crm .crmKpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:14px}
#crm .crmKpi{background:#fff;border:1px solid #e2e8ec;border-radius:13px;padding:14px}
#crm .crmKpi span{display:block;color:#71808a;font-size:11px;font-weight:700}
#crm .crmKpi b{display:block;margin-top:6px;font-size:22px;color:#18324a}
#crm .crmKpi small{display:block;margin-top:3px;color:#81909a;font-size:11px}
#crm .card{background:#fff;border:1px solid var(--gama-line,#c9d6df);border-radius:14px;padding:16px;margin-bottom:12px}
#crm .crmEmbudo{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
#crm .crmCol{background:#f8fafb;border:1px solid #e4ebee;border-radius:11px;padding:11px}
#crm .crmCol b{display:block;font-size:12.5px;color:#18324a}
#crm .crmCol i{display:block;font-style:normal;font-size:19px;font-weight:800;color:#087c8b;margin-top:5px}
#crm .crmCol small{display:block;color:#71808a;font-size:11px;margin-top:2px}
#crm .crmCol.ganada{background:#e7f6f0;border-color:#bfe6d6}
#crm .crmCol.perdida{background:#fff0ec;border-color:#f2cfc7}
#crm .crmMsg{margin:10px 0;font-size:13px}
#crm .crmMsg.err{color:#c94f45;font-weight:700}
#crm .crmVacio{padding:20px;text-align:center;color:#81909a}
@media(max-width:900px){#crm .crmKpis{grid-template-columns:1fr 1fr}}`;
 document.head.appendChild(s);
}
function kpi(etiqueta,valor,pie){
 return `<div class="crmKpi"><span>${esc(etiqueta)}</span><b>${esc(valor)}</b>${pie?`<small>${esc(pie)}</small>`:''}</div>`;
}
function pintar(r,cols){
 const s=section();
 s.innerHTML=`${window.GamaUI.header({title:'🤝 CRM',lead:'Prospectos, oportunidades y actividad comercial.'})}
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
 <div class="card">
  <h3>Embudo comercial</h3>
  ${cols.length?`<div class="crmEmbudo">${cols.map(c=>`
   <div class="crmCol${c.etapa.is_won?' ganada':c.etapa.is_lost?' perdida':''}">
    <b>${esc(c.etapa.name)}</b><i>${c.n}</i>
    <small>${money(c.total)}</small>
    ${c.etapa.is_won||c.etapa.is_lost?'':`<small>ponderado ${money(c.ponderado)}</small>`}
   </div>`).join('')}</div>`
  :'<div class="crmVacio">Todavía no hay etapas configuradas.</div>'}
  ${r.oportunidades===0&&r.ganadas===0&&r.perdidas===0
   ? '<div class="crmVacio">Ninguna oportunidad todavía. En cuanto se cree la primera, el embudo se llena solo.</div>':''}
 </div>`;
 window.GamaUI.bindBack(s);
}
function fallo(e){
 const m=$('crmMsg');
 const texto='No se pudieron cargar los datos del CRM: '+((e&&(e.message||e.details))||e);
 console.warn('[GAMA CRM]',e);
 if(m){m.className='crmMsg err';m.textContent=texto}
 else section().innerHTML=`${window.GamaUI.header({title:'🤝 CRM',lead:'Prospectos, oportunidades y actividad comercial.'})}<div class="crmMsg err">${esc(texto)}</div>`;
 window.GamaUI.bindBack(section());
}

let cargando=false;
async function open(){
 css();
 const s=section();
 document.querySelectorAll('section').forEach(x=>{const on=x.id==='crm';x.classList.toggle('active',on);x.hidden=!on;x.style.display=on?'block':'none'});
 $('mainmenu')?.setAttribute('hidden','');
 if(!puedeUsar()){
  s.innerHTML=`${window.GamaUI.header({title:'🤝 CRM',lead:'Prospectos, oportunidades y actividad comercial.'})}
   <div class="card"><div class="crmVacio">Tu perfil no tiene acceso al CRM.</div></div>`;
  window.GamaUI.bindBack(s);return;
 }
 if(cargando)return;cargando=true;
 s.innerHTML='<div class="wrap"><div class="card"><div class="crmVacio">Cargando el CRM…</div></div></div>';
 try{
  const [r,cols]=await Promise.all([resumen(),embudo()]);
  pintar(r,cols);
 }catch(e){fallo(e)}
 finally{cargando=false}
 window.scrollTo({top:0,behavior:'smooth'});
}

window.GamaCRM={
 open,
 // La capa de datos, para las pantallas que vienen después.
 cols:COLS, referenciales, comerciales, nombreDe, resumen, embudo, cuantos, suma,
 puedeUsar, esAdmin, money, esc,
};
window.GamaOpenCRM=open;
})();
