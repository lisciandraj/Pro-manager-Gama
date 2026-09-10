/* GAMA — CRM · Informes.

   Las cifras que un gerente mira una vez a la semana. No es el cuadro de
   mando —ese dice cómo va HOY—, sino de dónde vienen las ventas, quién las
   cierra, cuánto se tarda y por qué se pierden.

   Dos cosas que este archivo se toma en serio:

   · Cada cifra dice sobre qué se calcula. «Ganado este mes» puede querer decir
     lo que ENTRÓ este mes o lo que se CERRÓ este mes, y son números distintos.
     Aquí el embudo es siempre AHORA —una foto del pipeline vivo— y lo ganado y
     lo perdido se cuenta por la fecha de cierre, que es lo que pregunta quien
     mira el informe. Está escrito en la pantalla, no sólo aquí.

   · El periodo se filtra en la NUBE y no en el navegador. El §35 habla de
     50.000 oportunidades: traérselas todas para quedarse con las de un mes
     sería descargar el histórico entero cada vez que alguien abre el informe.

   Sin biblioteca de gráficos: barras de CSS. Una dependencia externa por
   cuatro barras horizontales es tráfico y una cosa más que puede romperse. */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] Informes necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const $=id=>document.getElementById(id);
const esc=CRM.esc,money=CRM.money;

const LEAD='Informes: de dónde vienen las ventas, quién las cierra y por qué se pierden.';
const CERRADA_COLS='id,amount,source_id,owner_id,lost_reason_id,won_at,lost_at,created_at';
const ABIERTA_COLS='id,amount,weighted_amount,stage_id,owner_id,source_id,expected_close_date';

const PERIODOS={
 mes:'Este mes',
 trimestre:'Últimos 3 meses',
 anio:'Este año',
 doce:'Últimos 12 meses',
};
let periodo='anio';
let datos=null,cargando=false;

function desde(){
 const h=new Date();
 if(periodo==='mes')return new Date(h.getFullYear(),h.getMonth(),1).toISOString();
 if(periodo==='trimestre')return new Date(h.getFullYear(),h.getMonth()-2,1).toISOString();
 if(periodo==='doce')return new Date(h.getFullYear(),h.getMonth()-11,1).toISOString();
 return new Date(h.getFullYear(),0,1).toISOString();
}

async function cargar(){
 const api=C();
 if(!api)throw new Error('La conexión con la nube de GAMA no está disponible.');
 const ref=await CRM.referenciales();
 const gente=await CRM.comerciales();
 const d=desde();
 const abiertas=ref.etapas.filter(e=>!e.is_won&&!e.is_lost).map(e=>e.id);
 /* Tres consultas y no una: lo ganado se acota por won_at, lo perdido por
    lost_at, y el embudo no se acota porque es una foto de AHORA. Mezclarlas en
    una sola con created_at daría una cifra que no responde a la pregunta. */
 const [g,p,a,l]=await Promise.all([
  api.list('crm_opportunities',{select:CERRADA_COLS,gte:{won_at:d},order:'won_at',ascending:true}),
  api.list('crm_opportunities',{select:CERRADA_COLS,gte:{lost_at:d},order:'lost_at',ascending:true}),
  abiertas.length?api.list('crm_opportunities',{select:ABIERTA_COLS,eq:{active:true},in:{stage_id:abiertas}}):Promise.resolve({data:[]}),
  api.list('crm_leads',{select:'id,source_id,status,created_at',gte:{created_at:d}}),
 ]);
 if(g.error)throw g.error;
 datos={
  ref:ref,gente:gente,
  ganadas:(g.data||[]).filter(x=>x.won_at),
  perdidas:p.error?[]:(p.data||[]).filter(x=>x.lost_at),
  abiertas:a.error?[]:(a.data||[]),
  prospectos:l.error?[]:(l.data||[]),
 };
}

/* ---- cálculos ---- */
const suma=(filas,col)=>filas.reduce((t,f)=>t+Number(f[col]||0),0);
const nombreRef=(id,lista,vacio)=>{
 const x=(lista||[]).find(y=>String(y.id)===String(id));
 return x?x.name:(vacio||'Sin indicar');
};
/* Días entre que nace una oportunidad y se cierra. La media es la respuesta a
   «¿cuánto tardamos en vender?», que decide cuánto pipeline hace falta. */
function ciclo(filas){
 const dias=filas.map(f=>{
  const ini=new Date(f.created_at).getTime(),fin=new Date(f.won_at||f.lost_at).getTime();
  return (isNaN(ini)||isNaN(fin))?null:Math.max(0,Math.round((fin-ini)/86400000));
 }).filter(x=>x!==null);
 if(!dias.length)return null;
 return Math.round(dias.reduce((t,x)=>t+x,0)/dias.length);
}
/* Agrupa por una columna y devuelve las filas ordenadas de más a menos. */
function agrupa(filas,col,etiqueta){
 const m=new Map();
 filas.forEach(f=>{
  const k=String(f[col]||'');
  if(!m.has(k))m.set(k,{clave:k,n:0,importe:0});
  const g=m.get(k);g.n++;g.importe+=Number(f.amount||0);
 });
 return Array.from(m.values())
  .map(g=>Object.assign(g,{nombre:etiqueta(g.clave)}))
  .sort((x,y)=>y.importe-x.importe||y.n-x.n);
}
/* Ganadas y perdidas por mes, para ver la tendencia. */
function porMes(){
 const m=new Map();
 const mete=(f,campo,clave)=>{
  const d=new Date(f[campo]);
  if(isNaN(d.getTime()))return;
  const k=d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0');
  if(!m.has(k))m.set(k,{mes:k,ganadas:0,perdidas:0,importe:0});
  const g=m.get(k);g[clave]++;
  if(clave==='ganadas')g.importe+=Number(f.amount||0);
 };
 datos.ganadas.forEach(f=>mete(f,'won_at','ganadas'));
 datos.perdidas.forEach(f=>mete(f,'lost_at','perdidas'));
 return Array.from(m.values()).sort((a,b)=>a.mes.localeCompare(b.mes));
}
function etiquetaMes(k){
 const [a,m]=k.split('-');
 const d=new Date(Number(a),Number(m)-1,1);
 return d.toLocaleDateString('es-EC',{month:'short',year:'2-digit'});
}

/* ---- pintar ---- */
function barra(valor,maximo,clase){
 const pc=maximo>0?Math.round(valor/maximo*100):0;
 return '<div class="crmBarra"><i class="'+(clase||'')+'" style="width:'+pc+'%"></i></div>';
}
function tabla(titulo,pie,filas,maximo){
 return '<div class="card"><h3>'+esc(titulo)+'</h3>'
  +'<p class="muted">'+esc(pie)+'</p>'
  +(filas.length?'<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
   +'<th>Concepto</th><th class="r">Cuántas</th><th class="r">Importe</th><th>Peso</th>'
   +'</tr></thead><tbody>'
   +filas.map(f=>'<tr><td><b>'+esc(f.nombre)+'</b></td>'
     +'<td class="r">'+f.n+'</td>'
     +'<td class="r">'+esc(money(f.importe))+'</td>'
     +'<td>'+barra(f.importe,maximo)+'</td></tr>').join('')
   +'</tbody></table></div>'
  :'<div class="crmVacio">Nada que contar en este periodo.</div>')
  +'</div>';
}
function kpi(etiqueta,valor,pie){
 return '<div class="crmKpi"><span>'+esc(etiqueta)+'</span><b>'+esc(valor)+'</b>'
  +(pie?'<small>'+esc(pie)+'</small>':'')+'</div>';
}
function pintar(){
 const s=CRM.section();
 const d=datos;
 const nG=d.ganadas.length,nP=d.perdidas.length,cerradas=nG+nP;
 const impG=suma(d.ganadas,'amount'),impP=suma(d.perdidas,'amount');
 const dias=ciclo(d.ganadas.concat(d.perdidas));
 const porOrigen=agrupa(d.ganadas,'source_id',k=>nombreRef(k,d.ref.origenes,'Sin origen'));
 const porComercial=agrupa(d.ganadas,'owner_id',k=>CRM.nombreDe(k,d.gente));
 const porMotivo=agrupa(d.perdidas,'lost_reason_id',k=>nombreRef(k,d.ref.motivos,'Sin motivo'));
 const embudoAhora=d.ref.etapas.filter(e=>!e.is_won&&!e.is_lost).map(e=>{
  const suyas=d.abiertas.filter(o=>String(o.stage_id)===String(e.id));
  return {nombre:e.name,n:suyas.length,importe:suma(suyas,'amount'),
   ponderado:suma(suyas,'weighted_amount')};
 });
 const maxEmbudo=Math.max.apply(null,[0].concat(embudoAhora.map(x=>x.importe)));

 s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>'
  +'<div class="crmBar">'
   +'<select id="crmRPeriodo" data-gama-nofind aria-label="Periodo del informe">'
    +Object.keys(PERIODOS).map(k=>'<option value="'+k+'"'+(periodo===k?' selected':'')+'>'+esc(PERIODOS[k])+'</option>').join('')
   +'</select><span></span><span></span>'
  +'</div>'
  +'<div class="crmKpis">'
   +kpi('Ganado',money(impG),nG+' cerrada(s) en el periodo')
   +kpi('Perdido',money(impP),nP+' cerrada(s) en el periodo')
   +kpi('Tasa de conversión',cerradas?Math.round(nG/cerradas*100)+' %':'—',cerradas?nG+' de '+cerradas:'nada cerrado todavía')
   +kpi('Ciclo medio',dias===null?'—':dias+' días',dias===null?'sin cierres que medir':'de la creación al cierre')
  +'</div>'
  /* El embudo es AHORA y no del periodo, y se dice: un pipeline «de enero» no
     significa nada, porque el pipeline es lo que hay vivo hoy. */
  +'<div class="card"><h3>Embudo vivo, hoy</h3>'
   +'<p class="muted">Una foto del pipeline abierto en este momento. No depende del periodo elegido: lo que está en curso está en curso.</p>'
   +(embudoAhora.length?'<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
     +'<th>Etapa</th><th class="r">Cuántas</th><th class="r">Importe</th><th class="r">Ponderado</th><th>Peso</th>'
     +'</tr></thead><tbody>'
     +embudoAhora.map(x=>'<tr><td><b>'+esc(x.nombre)+'</b></td><td class="r">'+x.n+'</td>'
       +'<td class="r">'+esc(money(x.importe))+'</td><td class="r">'+esc(money(x.ponderado))+'</td>'
       +'<td>'+barra(x.importe,maxEmbudo)+'</td></tr>').join('')
     +'</tbody></table></div>'
    :'<div class="crmVacio">Ninguna oportunidad abierta.</div>')
  +'</div>'
  +mesAMes()
  +tabla('De dónde vino lo ganado','Por origen del prospecto. Dice en qué vale la pena gastar el esfuerzo comercial.',
     porOrigen,Math.max.apply(null,[0].concat(porOrigen.map(x=>x.importe))))
  +tabla('Quién lo cerró','Por comercial responsable, sobre lo ganado en el periodo.',
     porComercial,Math.max.apply(null,[0].concat(porComercial.map(x=>x.importe))))
  +tabla('Por qué se perdió','El motivo de cada oportunidad perdida, con lo que costó. Es la lista de lo que hay que corregir.',
     porMotivo,Math.max.apply(null,[0].concat(porMotivo.map(x=>x.importe))))
  +'<div class="card"><h3>Prospectos entrados</h3>'
   +'<p class="muted">Los que nacieron en el periodo, por origen. Comparado con la tabla de arriba dice qué origen trae volumen y cuál trae dinero.</p>'
   +cuerpoProspectos()
  +'</div>';
 CRM.bind(s);
 const p=$('crmRPeriodo');
 if(p)p.onchange=()=>{periodo=p.value;abrirPantalla(true)};
}
function mesAMes(){
 const filas=porMes();
 const max=Math.max.apply(null,[0].concat(filas.map(f=>f.ganadas+f.perdidas)));
 return '<div class="card"><h3>Mes a mes</h3>'
  +'<p class="muted">Cerradas por mes, contadas por su fecha de cierre. Verde ganadas, rojo perdidas.</p>'
  +(filas.length?'<div class="crmMeses">'+filas.map(f=>
    '<div class="crmMes"><b>'+esc(etiquetaMes(f.mes))+'</b>'
    +'<div class="crmMesBarras">'
     +barra(f.ganadas,max,'ok')+barra(f.perdidas,max,'ko')
    +'</div>'
    +'<small>'+f.ganadas+' ganada(s) · '+f.perdidas+' perdida(s)</small>'
    +'<small>'+esc(money(f.importe))+'</small></div>').join('')+'</div>'
   :'<div class="crmVacio">Nada cerrado en este periodo.</div>')
  +'</div>';
}
function cuerpoProspectos(){
 const filas=agrupa(datos.prospectos.map(p=>({source_id:p.source_id,amount:0})),'source_id',
  k=>nombreRef(k,datos.ref.origenes,'Sin origen'));
 if(!filas.length)return '<div class="crmVacio">Ningún prospecto nuevo en este periodo.</div>';
 const max=Math.max.apply(null,[0].concat(filas.map(f=>f.n)));
 return '<div class="crmTablaWrap"><table class="crmTabla"><thead><tr>'
  +'<th>Origen</th><th class="r">Prospectos</th><th>Peso</th></tr></thead><tbody>'
  +filas.map(f=>'<tr><td><b>'+esc(f.nombre)+'</b></td><td class="r">'+f.n+'</td>'
    +'<td>'+barra(f.n,max)+'</td></tr>').join('')
  +'</tbody></table></div>';
}
function css(){
 if($('crmRepCss'))return;
 const s=document.createElement('style');s.id='crmRepCss';
 s.textContent='#crm .crmBarra{background:#eef3f4;border-radius:999px;height:9px;overflow:hidden;min-width:70px}'
 +'#crm .crmBarra i{display:block;height:100%;background:#087c8b;border-radius:999px}'
 +'#crm .crmBarra i.ok{background:#138a69}'
 +'#crm .crmBarra i.ko{background:#c94f45}'
 +'#crm .crmMeses{display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:10px}'
 +'#crm .crmMes{background:#f8fafb;border:1px solid #e4ebee;border-radius:10px;padding:10px}'
 +'#crm .crmMes b{display:block;font-size:12px;color:#18324a;text-transform:capitalize}'
 +'#crm .crmMesBarras{display:grid;gap:4px;margin:7px 0}'
 +'#crm .crmMes small{display:block;color:#71808a;font-size:11px}';
 document.head.appendChild(s);
}

async function abrirPantalla(recarga){
 CRM.css();css();
 const s=CRM.section();
 if(cargando)return;cargando=true;
 if(!recarga)s.innerHTML=CRM.cabecera(LEAD)+'<div class="card"><div class="crmVacio">Calculando…</div></div>';
 CRM.bind(s);
 try{
  await cargar();
  pintar();
 }catch(e){
  s.innerHTML=CRM.cabecera(LEAD)+'<div id="crmMsg" class="crmMsg"></div>';
  CRM.bind(s);
  CRM.util.error(e,'No se pudieron calcular los informes','Informes');
 }finally{cargando=false}
 if(!recarga)window.scrollTo({top:0,behavior:'smooth'});
}

CRM.registrar('informes','Informes',abrirPantalla);
window.GamaCRMReports={open:abrirPantalla};
})();
