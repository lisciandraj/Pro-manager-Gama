/* GAMA V10 - menú definitivo en español + Entregas/TMS */
(function(){
'use strict';
/* [rótulo, pantalla, icono, grupo]. El grupo es sólo para el menú: veinte
   módulos en una única rejilla se leen como un muro de iconos y encontrar
   «Matriz comercial» exigía recorrerlos todos. Agrupados —y con el buscador
   de aquí arriba— se llega a cualquiera de un vistazo o escribiendo tres
   letras.

   El orden importa, y no sólo por estética: un rótulo que es subcadena de
   otro se lleva por delante al que va después cuando algo elige la tarjeta
   por su texto —así es como la abren las pruebas de punta a punta—. Aquí
   hay dos casos, y los dos tienen que quedar en este orden:
     «Productos» antes que «Catálogo de productos»
     «Clientes»  antes que «Solicitudes de clientes»
   Por eso Inventario va antes que Ventas. Al mover un módulo de grupo, o
   al reordenar los grupos, hay que volver a comprobarlo. */
const ITEMS=[
 ['Panel de control','dashboard','chart','Resumen'],
 ['Productos','products','cube','Inventario y compras'],
 ['Almacenes y existencias','warehouses','warehouse','Inventario y compras'],
 ['Entradas / Salidas','movement','move','Inventario y compras'],
 ['Inventario','stock','stock','Inventario y compras'],
 ['Compras','gamaPurchasesV14','cart','Inventario y compras'],
 ['Proveedores','suppliers','truck','Inventario y compras'],
 ['Matriz comercial','matrix','matrix','Inventario y compras'],
 ['Códigos de barras','barcode','barcode','Inventario y compras'],
 ['Presupuestos','billing','invoice','Ventas'],
 ['Clientes','clients','users','Ventas'],
 ['Pedidos de venta','sales-orders','cart','Ventas'],
 ['CRM','crm','handshake','Ventas'],
 ['Solicitudes de clientes','customer-requests','request','Ventas'],
 ['Catálogo de productos','client-catalog','catalog','Ventas'],
 ['Tarifas','price-lists','tag','Ventas'],
 ['Importar Excel','reports','spreadsheet','Administración'],
 ['Recursos humanos','hr','badge','Administración'],
 ['Auditoría','audit','audit','Administración'],
 ['Usuarios','users','user','Administración'],
 ['Configuración','settings','gear','Administración'],
 ['Copias de seguridad','backup','cloud','Administración']
];
/* El orden en que se enseñan los grupos. «Logística» va la última y vacía a
   propósito: la tarjeta de Entregas/TMS la añade gama-role-spanish.js cuando
   el módulo termina de cargar, y al añadirla al final de la rejilla cae
   justo debajo de este rótulo. Si el módulo no carga —o el perfil no lo
   tiene— el rótulo se esconde solo (ver la regla :has del CSS). */
const GRUPOS=['Resumen','Inventario y compras','Ventas','Administración','Logística'];
const I={
 handshake:'<path d="M11 6.5 8.8 8.7a2 2 0 0 0 0 2.8l.3.3a2 2 0 0 0 2.8 0l1.2-1.2 3.4 3.4a1.6 1.6 0 0 1-2.3 2.3l-.5-.5"/><path d="M3 7.5 6 5l4 1 3.5-1.5L21 7.5"/><path d="M21 7.5v6M3 7.5v6"/>',
chart:'<path d="M4 19V10m5 9V6m5 13v-8m5 8V3"/><path d="m4 9 5-4 5 3 6-6"/>',
cube:'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
users:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
move:'<path d="M7 4v16M17 20V4M4 7l3-3 3 3M14 17l3 3 3-3"/>',
invoice:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
stock:'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
audit:'<path d="M12 3 20 6v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
truck:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
cart:'<path d="M3 4h2l2.2 10.2a2 2 0 0 0 2 1.6h7.4a2 2 0 0 0 1.9-1.4L20 8H6"/><circle cx="9" cy="19" r="1.5"/><circle cx="17" cy="19" r="1.5"/><path d="M9 11h8M12 8v6M15 8v6"/>',
spreadsheet:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18M15 3v18"/>',
gear:'<circle cx="12" cy="12" r="3"/><path d="M19 12h2M3 12h2M12 3v2M12 19v2M18 6l-2 2M8 16l-2 2M18 18l-2-2M8 8 6 6"/>',
cloud:'<path d="M7 18h11a4 4 0 0 0 .5-8 6 6 0 0 0-11.6 1A3.5 3.5 0 0 0 7 18Z"/><path d="M12 12v6m0 0-2-2m2 2 2-2"/>',
user:'<circle cx="12" cy="8" r="3.5"/><path d="M5 21c0-4 3-6 7-6s7 2 7 6"/>',
barcode:'<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
catalog:'<path d="M3.5 5.5h2l1.7 9.2a1.8 1.8 0 0 0 1.8 1.5h7.8a1.8 1.8 0 0 0 1.7-1.3L20.2 9H7"/><circle cx="9" cy="19" r="1.2"/><circle cx="17" cy="19" r="1.2"/>',
request:'<rect x="6" y="3.5" width="12" height="17" rx="1.8"/><path d="M9 3.5h6v2H9zM9 9h6M9 12.5h6M9 16h4"/>',
tag:'<path d="M3 12V5.5A2.5 2.5 0 0 1 5.5 3H12l9 9-9 9-9-9Z"/><circle cx="7.5" cy="7.5" r="1.4"/>',
matrix:'<path d="M4 19V5M4 19h16M8 16V9m4 7V6m4 10v-4"/>',
warehouse:'<path d="M3 10.5 12 4l9 6.5V20H3z"/><path d="M7 20v-6h10v6M7 14h10"/>',
badge:'<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M9 6V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V6"/><circle cx="12" cy="12" r="2"/><path d="M8.5 17c.4-1.6 1.8-2.5 3.5-2.5s3.1.9 3.5 2.5"/>'};
function ensureExcelModule(){let section=document.getElementById('reports');if(!section){section=document.createElement('section');section.id='reports';document.body.appendChild(section)}section.innerHTML='<div class="wrap"><div id="excel-import-module" data-module="excel"></div></div>';if(!document.getElementById('gamaExcelLoader')){const s=document.createElement('script');s.id='gamaExcelLoader';s.src='gama-excel-import-v1.js?v=20260910-tarifas2';s.onload=()=>window.GamaExcelImport&&window.GamaExcelImport.render();s.onerror=()=>{const h=document.getElementById('excel-import-module');if(h)h.innerHTML='<div class="card"><h2>Importar Excel</h2><p class="low">No se pudo cargar el módulo Excel. Recarga la aplicación.</p></div>'};document.head.appendChild(s)}else if(window.GamaExcelImport)window.GamaExcelImport.render()}
function openItem(x){if(x[1]==='sales-orders'){window.GamaSales?.open();return}if(window.GamaModules&&!window.GamaModules.enabled(x[1])){alert('Este módulo está desactivado en Configuración.');return}if(x[1]==='reports'){ensureExcelModule();window.showTab&&window.showTab('reports',null);return}if(x[1]==='gamaPurchasesV14'){if(window.gamaShowPurchases)window.gamaShowPurchases();else{window.showTab&&window.showTab('gamaPurchasesV14',null);setTimeout(()=>window.gamaShowPurchases&&window.gamaShowPurchases(),100)}return}if(x[1]==='crm'){if(window.showTab)window.showTab('crm',null);window.GamaOpenCRM?.();return}if(x[1]==='price-lists'){if(window.showTab)window.showTab('price-lists',null);window.GamaOpenPriceLists?.();return}if(x[1]==='client-catalog'){if(window.showTab)window.showTab('client-catalog',null);window.GamaOpenClientCatalog?.();return}if(x[1]==='customer-requests'){if(window.showTab)window.showTab('customer-requests',null);window.GamaOpenCustomerRequests?.();return}if(x[1]==='warehouses'){if(window.showTab)window.showTab('warehouses',null);window.GamaOpenWarehouses?.();return}if(x[1]==='hr'){window.GamaOpenHR?.();return}if(x[1]==='settings'){window.GamaOpenSettings?.();return}if(window.showTab)window.showTab(x[1],null)}

/* Un rótulo de grupo se esconde cuando no le queda ninguna tarjeta visible
   detrás: puede pasar porque el perfil no tenga acceso a ninguna —el control
   de acceso les pone .aclHidden— o porque el buscador las haya descartado.
   Se resuelve en CSS con :has() y el combinador de hermanos, sin observador:
   el guardarraíl de rendimiento del proyecto acota cuántos puede haber. */
function reglasDeGrupo(){
 return GRUPOS.map(g=>{
  const visible=g==='Logística'
   ?'.gamaF2Card[data-gama-tms-card]:not(.aclHidden):not(.gamaF2NoMatch)'
   :`.gamaF2Card[data-gama-grupo="${g}"]:not(.aclHidden):not(.gamaF2NoMatch)`;
  return `#mainmenu .gamaF2Section[data-gama-grupo="${g}"]:not(:has(~ ${visible})){display:none}`;
 }).join('');
}

function buscar(termino){
 const t=(termino||'').trim().toLowerCase();
 let visibles=0;
 document.querySelectorAll('#mainmenu .gamaF2Card').forEach(c=>{
  const rotulo=(c.querySelector('.gamaF2Title')?.textContent||'').toLowerCase();
  const coincide=!t||rotulo.includes(t);
  c.classList.toggle('gamaF2NoMatch',!coincide);
  if(coincide&&!c.classList.contains('aclHidden'))visibles++;
 });
 const vacio=document.getElementById('gamaF2Vacio');
 if(vacio)vacio.hidden=!(t&&!visibles);
}

function render(){const host=document.getElementById('mainmenu');if(!host)return;document.documentElement.lang='es';document.querySelectorAll('.gamaLanguage').forEach(e=>e.remove());const s=document.getElementById('gama-final2-css')||document.head.appendChild(document.createElement('style'));s.id='gama-final2-css';/* auto-fill en vez de cinco columnas fijas: al agrupar, un grupo de seis
   tarjetas dejaba una sola huérfana en la fila siguiente y un hueco enorme
   al lado. Dejando que la rejilla ajuste el número de columnas al ancho
   disponible —que además cambia cuando aparece la barra lateral— los grupos
   llenan sus filas. */
s.textContent='#mainmenu .gamaF2Grid{display:grid!important;grid-template-columns:repeat(auto-fill,minmax(196px,1fr))!important;gap:16px!important;padding:12px 18px 24px!important}#mainmenu .gamaF2Card{display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;min-height:155px!important;padding:18px 10px!important;margin:0!important;background:#fff!important;border:1px solid #C3D2DC!important;border-radius:18px!important;box-shadow:0 1px 2px rgba(23,50,70,.07),0 6px 18px rgba(23,50,70,.10)!important;color:#173246!important;cursor:pointer!important;transition:transform .12s ease,box-shadow .12s ease,border-color .12s ease}#mainmenu .gamaF2Card:hover{border-color:#087c8b!important;box-shadow:0 2px 4px rgba(23,50,70,.08),0 12px 26px rgba(23,50,70,.16)!important;transform:translateY(-2px)}#mainmenu .gamaF2Card:active{transform:translateY(-1px) scale(.99)}#mainmenu .gamaF2Card:focus-visible{outline:3px solid #087c8b!important;outline-offset:2px}#mainmenu .gamaF2Icon{display:flex!important;align-items:center!important;justify-content:center!important;width:64px!important;height:64px!important;min-width:64px!important;border-radius:18px!important;background:#e8f5f6!important;color:#087c8b!important;margin:0 0 12px!important}#mainmenu .gamaF2Icon.gamaF2Naranja{background:#fff0e5!important;color:#f47a2a!important}#mainmenu .gamaF2Icon svg{display:block!important;width:34px!important;height:34px!important;fill:none!important;stroke:currentColor!important;stroke-width:1.9!important;stroke-linecap:round!important;stroke-linejoin:round!important}#mainmenu .gamaF2Title{display:block!important;font-size:16px!important;font-weight:800!important;line-height:1.2!important;text-align:center!important}'
 +'#mainmenu .gamaF2Section{grid-column:1/-1;margin:10px 2px 0;font-size:11px;font-weight:850;letter-spacing:1.3px;text-transform:uppercase;color:#6d7d88}#mainmenu .gamaF2Section:first-child{margin-top:0}#mainmenu .gamaF2Card.gamaF2NoMatch{display:none!important}'
 +'#mainmenu .gamaF2Buscador{margin:0 18px 4px;position:relative;max-width:420px}#mainmenu .gamaF2Buscador input{width:100%;box-sizing:border-box;padding:12px 14px 12px 40px;border:1px solid #C3D2DC;border-radius:12px;background:#fff;font-size:15px;color:#173246}#mainmenu .gamaF2Buscador input:focus{outline:none;border-color:#087c8b;box-shadow:0 0 0 3px rgba(8,124,139,.18)}#mainmenu .gamaF2Buscador svg{position:absolute;left:13px;top:50%;transform:translateY(-50%);width:17px;height:17px;fill:none;stroke:#71808a;stroke-width:2;pointer-events:none}#mainmenu .gamaF2Buscador kbd{position:absolute;right:11px;top:50%;transform:translateY(-50%);padding:2px 7px;border:1px solid #C3D2DC;border-bottom-width:2px;border-radius:6px;background:#F4F7F9;color:#6D7D88;font:700 11px/1.5 inherit;pointer-events:none}#mainmenu .gamaF2Buscador input:focus~kbd{opacity:0}'
 +'#mainmenu .gamaF2Vacio{margin:14px 18px 0;padding:22px;text-align:center;color:#6d7d88;font-size:14px;background:#fff;border:1px dashed #C3D2DC;border-radius:14px}'
 +reglasDeGrupo()
 +'@media(max-width:900px){#mainmenu .gamaF2Grid{grid-template-columns:repeat(3,minmax(0,1fr))!important}}@media(max-width:600px){#mainmenu .gamaF2Grid{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:10px!important;padding:10px!important}#mainmenu .gamaF2Card{min-height:145px!important;padding:14px 7px!important}#mainmenu .gamaF2Icon{width:58px!important;height:58px!important;min-width:58px!important}#mainmenu .gamaF2Icon svg{width:30px!important;height:30px!important}.gamaF2Title{font-size:15px!important}#mainmenu .gamaF2Buscador{margin:0 10px 2px;max-width:none}#mainmenu .gamaF2Buscador kbd{display:none}#mainmenu .gamaF2Section{margin:8px 2px 0}#mainmenu .gamaF2Vacio{margin:12px 10px 0}}';
 host.replaceChildren();
 const h=document.createElement('h2');h.textContent='Menú principal';h.style.cssText='margin:22px 18px 8px;color:#173246;font-size:28px';
 const p=document.createElement('p');p.textContent='Accede rápidamente a todas las funciones de GAMA Enterprise Resource Planning.';p.style.cssText='margin:0 18px 14px;color:#7b8891;font-size:14px';
 const caja=document.createElement('div');caja.className='gamaF2Buscador';
 caja.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>';
 const input=document.createElement('input');input.type='search';input.id='gamaF2Buscar';input.placeholder='Buscar un módulo…';input.setAttribute('aria-label','Buscar un módulo');
 input.oninput=()=>buscar(input.value);
 input.onkeydown=e=>{if(e.key==='Escape'){input.value='';buscar('');input.blur()}};
 caja.appendChild(input);
 const tecla=document.createElement('kbd');tecla.textContent='/';tecla.setAttribute('aria-hidden','true');caja.appendChild(tecla);
 const grid=document.createElement('div');grid.className='gamaF2Grid';
 let n=0;
 GRUPOS.forEach(g=>{
  const rotulo=document.createElement('div');rotulo.className='gamaF2Section';rotulo.dataset.gamaGrupo=g;rotulo.textContent=g;
  grid.appendChild(rotulo);
  ITEMS.filter(x=>x[3]===g).forEach(x=>{
   const b=document.createElement('button');b.type='button';b.className='gamaF2Card';b.dataset.gamaGrupo=g;
   const icon=document.createElement('span');icon.className='gamaF2Icon'+(n++%2?' gamaF2Naranja':'');
   icon.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">'+I[x[2]]+'</svg>';
   const label=document.createElement('span');label.className='gamaF2Title';label.textContent=x[0];
   b.append(icon,label);b.onclick=()=>openItem(x);grid.appendChild(b);
  });
 });
 const vacio=document.createElement('div');vacio.className='gamaF2Vacio';vacio.id='gamaF2Vacio';vacio.hidden=true;vacio.textContent='Ningún módulo coincide con la búsqueda.';
 host.append(h,p,caja,grid,vacio);
}
/* Aquí vivía removeRedundantMainMenuBack(): un MutationObserver sobre todo el
   body que en cada cambio del DOM recorría cada a, button, div, p y span de la
   página para borrar los botones «‹ Menú principal» que index.html repetía en
   cada sección. Con una lista de productos larga eso es recorrer la página
   entera en cada repintado, en el móvil. Los botones ya no se escriben —cada
   pantalla lleva la cabecera común, con su único botón de volver— así que el
   barrido sobra. */
/* «/» lleva el foco al buscador, como en cualquier herramienta de uso
   diario. Sólo cuando el menú es la pantalla visible y no se está
   escribiendo ya en un campo: así no le quita la tecla a ningún módulo ni
   al lector de códigos de barras, que escribe en el campo que tenga el
   foco. */
document.addEventListener('keydown',function(e){
 if(e.key!=='/'||e.ctrlKey||e.metaKey||e.altKey)return;
 const menu=document.getElementById('mainmenu');
 if(!menu||!menu.classList.contains('active'))return;
 const t=e.target;
 if(t&&(t.isContentEditable||/^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName)))return;
 const input=document.getElementById('gamaF2Buscar');
 if(!input)return;
 e.preventDefault();input.focus();input.select();
});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});else render();
})();
