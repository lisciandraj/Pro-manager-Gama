/* GAMA V10 — main menu, single source of truth */
(function(){
'use strict';
const ITEMS=[
 ['Dashboard','dashboard','chart','teal','Ventas y KPIs'],['Inicio','home','home','orange','Escaneo rápido'],
 ['Productos','products','cube','teal','Fichas y precios'],['Clientes','clients','users','orange','Base de clientes'],
 ['IN / OUT','movement','move','teal','Entradas y salidas'],['Facturación','billing','invoice','orange','Ventas y facturas'],
 ['Inventario','stock','stock','teal','Stock actual'],['Audit Trail','audit','audit','orange','Trazabilidad'],
 ['Reportes','dashboard','pie','teal','Ventas y análisis'],['Códigos de barras','barcode','barcode','orange','Generar códigos'],
 ['Escáner','home','scan','teal','Escaneo cámara'],['Backup','backup','cloud','orange','Copias de seguridad'],
 ['Excel','excel','sheet','teal','Importar / exportar'],['Catálogo','products','catalog','orange','Productos disponibles'],
 ['Clientes frecuentes','clients','frequent','teal','Acceso a clientes'],['Movimientos','movement','move','orange','Historial IN / OUT'],
 ['Stock','stock','stock','teal','Consulta de stock'],['Facturas','billing','invoice','orange','Documentos emitidos'],
 ['Historial','audit','history','teal','Actividad registrada'],['Datos','backup','data','orange','Gestionar copias'],
 ['Proveedores','suppliers','truck','teal','Proveedores y compras'],['Compras','purchases','cart','orange','Pedidos y recepción']
];
const ICONS={
 chart:'<path d="M4 19V10m5 9V6m5 13v-8m5 8V3"/><path d="m4 9 5-4 5 3 6-6"/>',
 home:'<path d="m3 11 9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1v-9Z"/>',
 cube:'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
 users:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
 move:'<path d="M7 4v16M17 20V4M4 7l3-3 3 3M14 17l3 3 3-3"/>',
 invoice:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
 stock:'<path d="M4 7h16v13H4zM7 4h10v3H7zM8 11h8M8 15h5"/>',
 audit:'<path d="M12 3 20 6v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
 pie:'<path d="M12 3a9 9 0 1 0 9 9h-9V3Z"/><path d="M14 3a7 7 0 0 1 7 7h-7V3Z"/>',
 barcode:'<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
 scan:'<path d="M5 5h5M14 5h5M5 19h5M14 19h5"/><path d="M8 12h8"/>',
 cloud:'<path d="M7 18h11a4 4 0 0 0 .5-8 6 6 0 0 0-11.6 1A3.5 3.5 0 0 0 7 18Z"/><path d="M12 12v6m0 0-2-2m2 2 2-2"/>',
 sheet:'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
 catalog:'<path d="M4 7h16M7 12h10M10 17h4"/>',
 frequent:'<circle cx="12" cy="8" r="3"/><path d="M5 20c0-4 3-6 7-6s7 2 7 6"/><path d="M18 5v4M16 7h4"/>',
 history:'<circle cx="12" cy="12" r="8"/><path d="M12 8v5l3 2"/>',
 data:'<path d="M4 7h16v13H4z"/><path d="M8 7V4h8v3M8 11h8M8 15h5"/>',
 truck:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
 purchases:'<path d="M4 5h3l2 10h9l2-7H7"/><circle cx="10" cy="19" r="1.5"/><circle cx="17" cy="19" r="1.5"/>'
};
function setMainMenuState(active){document.body.classList.toggle('gamaMainMenuActive',!!active)}
function openItem(id){
 setMainMenuState(false);
 if(id==='purchases')return typeof window.gamaShowPurchases==='function'?window.gamaShowPurchases():alert('El módulo Compras todavía está cargando. Recarga la página.');
 if(id==='excel'){if(typeof window.showTab==='function')window.showTab('backup',null);setTimeout(()=>document.getElementById('excelImport')?.focus(),80);return}
 if(typeof window.showTab==='function')window.showTab(id,null);
}
function render(){
 const host=document.getElementById('mainmenu');if(!host)return;host.replaceChildren();setMainMenuState(true);
 const intro=document.createElement('div');intro.className='menuIntro';
 intro.innerHTML='<div><h2>Menú principal</h2><p>Accede rápidamente a todas las funciones de GAMA Stock Manager.</p></div><span class="onlineBadge"><i></i> En línea</span>';
 const grid=document.createElement('div');grid.className='appGrid';
 ITEMS.forEach(([label,id,icon,tone,sub])=>{const b=document.createElement('button');b.type='button';b.className='appTile';b.innerHTML='<span class="appIcon '+tone+'"><svg viewBox="0 0 24 24">'+ICONS[icon]+'</svg></span><b></b><small></small>';b.querySelector('b').textContent=label;b.querySelector('small').textContent=sub;b.addEventListener('click',()=>openItem(id));grid.appendChild(b)});
 const footer=document.createElement('div');footer.className='menuFooter';footer.innerHTML='<span><i></i> Sistema local activo</span><small>GAMA Stock Manager V10</small>';
 host.append(intro,grid,footer);
}
function installNavigationHook(){
 if(window.showTab&& !window.showTab.__gamaMenuState){const old=window.showTab;const wrapped=function(id,el){if(id==='mainmenu'){setMainMenuState(true);const r=old.apply(this,arguments);setTimeout(render,0);return r}setMainMenuState(false);return old.apply(this,arguments)};wrapped.__gamaMenuState=true;wrapped.__gamaOriginal=old;window.showTab=wrapped}
}
function boot(){render();installNavigationHook()}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.GAMA_MODULES={open:openItem,list:()=>ITEMS.map(x=>({label:x[0],id:x[1]}))};
})();
