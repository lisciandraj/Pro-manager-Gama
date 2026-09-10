/* GAMA — CRM · Puntuación de prospectos, y el enchufe para una IA futura.

   DOS COSAS DISTINTAS EN UN ARCHIVO, y conviene no confundirlas.

   1. LA PUNTUACIÓN es real y es determinista. Las reglas viven en
      crm_scoring_rules —evento, etiqueta, puntos— y se aplican contando lo que
      GAMA sabe de verdad de cada prospecto. No hay modelo, no hay estadística,
      no hay adivinanza: si un prospecto tiene 70 puntos, la pantalla enseña de
      dónde sale cada uno. Un número que nadie puede explicar no se usa para
      decidir a quién llamar.

      Tres de las cinco reglas sembradas se pueden calcular hoy:

        reunion               → reuniones mantenidas (actividades hechas)
        solicitud_presupuesto → oportunidades abiertas para ese prospecto, que
                                en GAMA es exactamente «nos pidió precio»
        pedido                → oportunidades suyas en la etapa ganadora

      Y DOS NO, y se dice en la pantalla en vez de inventarlas:

        correo_abierto, correo_click → GAMA envía los correos con el cliente de
        correo del usuario y un PDF adjunto. No hay píxel de seguimiento ni
        enlaces marcados, así que no hay forma honesta de saber si alguien
        abrió un correo. Cuando exista el envío con seguimiento, estas dos
        reglas empezarán a contar solas: ya están en la tabla y el cálculo las
        recogerá sin tocar nada aquí.

   2. EL ENCHUFE DE IA no hace nada, a propósito. El encargo dice: «NE PAS
      implémenter une IA fictive ou simulée. Préparer uniquement une
      architecture permettant son intégration future.» Así que aquí hay un
      registro vacío: mientras nadie registre un proveedor, GamaCRM.ia.hay() es
      false y ninguna pantalla enseña nada. No hay texto generado, no hay
      predicciones de mentira, no hay «probabilidad estimada por IA» calculada
      con una fórmula disfrazada. El día que haya un proveedor de verdad, se
      registra y las pantallas que quieran preguntarle ya saben cómo. */
(function(){
'use strict';
if(!window.GamaCRM){console.warn('[GAMA CRM] La puntuación necesita gama-crm-core.js');return}
const CRM=window.GamaCRM;
const C=()=>window.GamaCloud;
const esc=CRM.esc;

/* ---- 1. la puntuación ---- */

/* Qué sabe GAMA contar hoy, y con qué consulta. Añadir una regla nueva es
   añadir aquí su forma de contarse; las que no estén se quedan fuera del total
   y se enseñan aparte, dichas por su nombre. */
const CONTADORES={
 reunion:{
  explica:'reuniones mantenidas',
  contar:async lead=>{
   const r=await C().list('crm_activities',{select:'id',eq:{lead_id:lead.id,kind:'reunion',status:'hecha'}});
   if(r.error)throw r.error;
   return (r.data||[]).length;
  },
 },
 solicitud_presupuesto:{
  explica:'oportunidades abiertas a su nombre',
  contar:async lead=>{
   const r=await C().list('crm_opportunities',{select:'id',eq:{lead_id:lead.id,active:true}});
   if(r.error)throw r.error;
   return (r.data||[]).length;
  },
 },
 pedido:{
  explica:'oportunidades suyas ya ganadas',
  contar:async lead=>{
   const {etapas}=await CRM.referenciales();
   const ganada=etapas.find(e=>e.is_won);
   if(!ganada)return 0;
   const r=await C().list('crm_opportunities',{select:'id',eq:{lead_id:lead.id,stage_id:ganada.id}});
   if(r.error)throw r.error;
   return (r.data||[]).length;
  },
 },
};

let reglas=null;
async function cargarReglas(recargar){
 if(reglas&&!recargar)return reglas;
 const r=await C().list('crm_scoring_rules',{select:'id,event_key,label,points,active',order:'points',ascending:false});
 reglas=r.error?[]:(r.data||[]).filter(x=>x.active!==false);
 return reglas;
}

/* Devuelve el desglose completo, no sólo el total: el total sin el desglose es
   un número que nadie puede discutir, y por tanto en el que nadie confía. */
async function calcular(lead){
 const rs=await cargarReglas();
 const lineas=[],pendientes=[];
 for(const regla of rs){
  const c=CONTADORES[regla.event_key];
  if(!c){pendientes.push(regla);continue}
  let veces=0;
  try{veces=await c.contar(lead)}catch(e){console.warn('[GAMA CRM puntuación]',regla.event_key,e);continue}
  if(veces>0)lineas.push({regla:regla,veces:veces,puntos:veces*Number(regla.points||0),explica:c.explica});
 }
 const bruto=lineas.reduce((t,l)=>t+l.puntos,0);
 /* La base sólo admite de 0 a 100 (crm_leads_score_check), así que se corta
    aquí y se dice, en vez de mandar un 140 que Postgres rechazaría. */
 const total=Math.min(100,Math.max(0,bruto));
 return {total:total,bruto:bruto,recortado:bruto>100,lineas:lineas,pendientes:pendientes};
}

async function guardar(lead,total){
 const r=await C().update('crm_leads',lead.id,{score:total});
 if(r.error)throw r.error;
 return total;
}

/* El HTML del desglose. Lo pinta quien quiera —hoy la ficha de Prospectos—,
   porque la puntuación no es una pantalla: es una explicación. */
function panel(res){
 if(!res)return '';
 return '<div class="card crmPuntos"><h3>Puntuación: '+res.total+' / 100</h3>'
  +(res.recortado?'<p class="muted">Suman '+res.bruto+' puntos; la ficha guarda 100, que es el máximo.</p>':'')
  +(res.lineas.length
   ?'<table class="crmTabla"><thead><tr><th>Por qué</th><th class="r">Veces</th><th class="r">Puntos</th></tr></thead><tbody>'
    +res.lineas.map(l=>'<tr><td><b>'+esc(l.regla.label)+'</b><small class="crmSub">'+esc(l.explica)+'</small></td>'
      +'<td class="r">'+l.veces+'</td><td class="r"><b>'+l.puntos+'</b></td></tr>').join('')
    +'</tbody></table>'
   :'<div class="crmVacio">Todavía no ha pasado nada que puntúe: ni reuniones, ni oportunidades a su nombre.</div>')
  +(res.pendientes.length
   ?'<div class="crmAviso">Estas reglas están configuradas pero hoy no se pueden contar: <b>'
    +res.pendientes.map(r=>esc(r.label)).join('</b>, <b>')+'</b>. '
    +'GAMA envía los correos desde el programa de correo del usuario, sin seguimiento, '
    +'así que no hay forma honesta de saber si se abrieron. En cuanto el envío lleve seguimiento, contarán solas.</div>'
   :'')
  +'<div class="crmAcciones"><button type="button" class="primary" id="crmPtsAplicar">Guardar '+res.total+' en la ficha</button></div>'
  +'</div>';
}

/* ---- 2. el enchufe de IA ----

   Vacío a propósito. Ver la cabecera del archivo. */
const proveedores=[];
const ia={
 /* Un proveedor es {nombre, sugerir(peticion) -> Promise}. Nadie registra
    ninguno hoy, y por eso hay() devuelve false y las pantallas no enseñan
    nada relacionado con IA. */
 registrar(p){
  if(!p||typeof p.sugerir!=='function')throw new Error('Un proveedor de IA necesita una función sugerir().');
  proveedores.push(p);
 },
 hay(){return proveedores.length>0},
 nombres(){return proveedores.map(p=>p.nombre||'(sin nombre)')},
 /* Si nadie ha registrado nada, esto NO inventa una respuesta: falla. Devolver
    un texto plausible sería exactamente la IA de mentira que el encargo
    prohíbe. */
 async sugerir(peticion){
  if(!proveedores.length)throw new Error('No hay ningún proveedor de IA conectado.');
  return proveedores[0].sugerir(peticion);
 },
};

CRM.puntuacion={calcular,guardar,panel,reglas:cargarReglas,contadores:CONTADORES};
CRM.ia=ia;
window.GamaCRMScoring=CRM.puntuacion;
})();
