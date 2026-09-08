/* GAMA — Interruptor de módulos.

   Configuración permite apagar un módulo que no se usa. Un módulo apagado
   desaparece del menú y de las pestañas para todo el mundo, y no se puede
   abrir por ninguna vía: el guardián de showTab también lo rechaza.

   Dos decisiones que conviene tener presentes:

   - El estado vive en app_modules, en la nube, para que apagar un módulo valga
     para todos los usuarios y no sólo para el navegador de quien lo apagó.
   - Una clave sin fila está ENCENDIDA. Así, añadir un módulo nuevo a la
     aplicación no obliga a insertar nada en la base, y si la consulta falla
     —sin conexión, por ejemplo— se ve la aplicación entera en vez de una
     pantalla vacía. Esto no es una barrera de seguridad: lo que protege los
     datos de cada módulo son las políticas RLS de sus tablas, no este
     interruptor. */
(function(){
'use strict';
if(window.GamaModules)return;

/* Catálogo de lo que se puede apagar. Es la lista que enseña Configuración,
   así que lleva el nombre con el que el usuario conoce cada módulo.

   `locked` marca lo que no se puede apagar: Configuración es la pantalla desde
   la que se vuelve a encender lo demás — apagarla dejaría la aplicación sin
   forma de recuperarse. */
const CATALOG=[
 {id:'dashboard',          label:'Panel de control y análisis'},
 {id:'products',           label:'Productos'},
 {id:'clients',            label:'Clientes'},
 {id:'movement',           label:'Entradas / Salidas'},
 {id:'billing',            label:'Presupuestos'},
 {id:'stock',              label:'Inventario'},
 {id:'audit',              label:'Auditoría'},
 {id:'suppliers',          label:'Proveedores'},
 {id:'matrix',             label:'Matriz comercial'},
 {id:'gamaPurchasesV14',   label:'Compras'},
 {id:'price-lists',        label:'Tarifas'},
 {id:'reports',            label:'Importar Excel'},
 {id:'backup',             label:'Copias de seguridad'},
 {id:'barcode',            label:'Códigos de barras'},
 {id:'client-catalog',     label:'Catálogo de productos'},
 {id:'customer-requests',  label:'Solicitudes de clientes'},
 {id:'tms',                label:'Transporte y entregas'},
 {id:'hr',                 label:'Recursos humanos'},
 {id:'users',              label:'Usuarios y accesos'},
 {id:'settings',           label:'Configuración', locked:true},
];
const LOCKED=new Set(CATALOG.filter(m=>m.locked).map(m=>m.id));
const CACHE_KEY='gama_modules_v1';

/* Sólo se guardan los módulos APAGADOS. Una lista corta, y encaja con la regla
   de que lo que no aparece está encendido. */
let off=read();
let loaded=false;

function read(){
 try{const v=JSON.parse(localStorage.getItem(CACHE_KEY)||'[]');return new Set(Array.isArray(v)?v:[])}
 catch(e){return new Set()}
}
function write(){
 try{localStorage.setItem(CACHE_KEY,JSON.stringify([...off]))}catch(e){}
}

function enabled(id){
 if(!id||LOCKED.has(id))return true;
 return !off.has(id);
}
function list(){
 return CATALOG.map(m=>({id:m.id,label:m.label,locked:!!m.locked,enabled:enabled(m.id)}));
}
function changed(){
 window.dispatchEvent(new CustomEvent('gama:modules-change',{detail:{off:[...off]}}));
}

/* Trae el estado de la nube. La caché local se usa mientras llega, para que al
   recargar no aparezca un módulo apagado durante medio segundo. */
async function load(){
 const api=window.GamaCloud;
 if(!api)return list();
 try{
  const r=await api.list('app_modules',{select:'id,enabled'});
  if(r.error)throw r.error;
  off=new Set((r.data||[]).filter(x=>x.enabled===false).map(x=>x.id));
  loaded=true;write();changed();
 }catch(e){
  // Sin respuesta se conserva lo último que se supo: apagar de más sería peor.
  console.warn('[GAMA Módulos] no se pudo leer el estado',e);
 }
 return list();
}

async function setEnabled(id,on){
 if(LOCKED.has(id))throw new Error('Este módulo no se puede desactivar.');
 const api=window.GamaCloud;
 if(!api)throw new Error('Sin conexión con GAMA Cloud.');
 const session=(await api.getSession()).data?.session;
 const r=await api.upsert('app_modules',
   {id,enabled:!!on,updated_at:new Date().toISOString(),updated_by:session?.user?.id||null},
   {onConflict:'id'});
 if(r.error)throw r.error;
 if(on)off.delete(id);else off.add(id);
 write();changed();
 return list();
}

window.GamaModules={CATALOG,list,enabled,load,setEnabled,isLoaded:()=>loaded};

/* En cuanto haya nube, se lee. El menú y el control de acceso escuchan
   gama:modules-change y se repintan solos. */
(function boot(){
 if(window.GamaCloudReady){window.GamaCloudReady.then(load).catch(()=>{});return}
 let n=0;const t=setInterval(()=>{
  if(window.GamaCloudReady){clearInterval(t);window.GamaCloudReady.then(load).catch(()=>{})}
  else if(++n>60)clearInterval(t);
 },250);
})();
})();
