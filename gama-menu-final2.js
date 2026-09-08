/* GAMA V10 - menú definitivo en español + Entregas/TMS */
(function(){
'use strict';
const ITEMS=[
 ['Panel de control','dashboard','chart'],
 ['Productos','products','cube'],
 ['Clientes','clients','users'],
 ['Entradas / Salidas','movement','move'],
 ['Presupuestos','billing','invoice'],
 ['Inventario','stock','stock'],
 ['Auditoría','audit','audit'],
 ['Proveedores','suppliers','truck'],
 ['Compras','gamaPurchasesV14','cart'],
 ['Tarifas','price-lists','tag'],
 ['Importar Excel','reports','spreadsheet'],
 ['Matriz comercial','matrix','matrix'],
 ['Recursos humanos','hr','badge'],
 ['Configuración','settings','gear'],
 ['Copias de seguridad','backup','cloud'],
 ['Usuarios','users','user'],
 ['Códigos de barras','barcode','barcode'],
 ['Catálogo de productos','client-catalog','catalog'],
 ['Solicitudes de clientes','customer-requests','request']
];
const I={
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
badge:'<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M9 6V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V6"/><circle cx="12" cy="12" r="2"/><path d="M8.5 17c.4-1.6 1.8-2.5 3.5-2.5s3.1.9 3.5 2.5"/>'};
function ensureExcelModule(){let section=document.getElementById('reports');if(!section){section=document.createElement('section');section.id='reports';document.body.appendChild(section)}section.innerHTML='<div class="wrap"><div id="excel-import-module" data-module="excel"></div></div>';if(!document.getElementById('gamaExcelLoader')){const s=document.createElement('script');s.id='gamaExcelLoader';s.src='gama-excel-import-v1.js?v=20260908-ui1';s.onload=()=>window.GamaExcelImport&&window.GamaExcelImport.render();s.onerror=()=>{const h=document.getElementById('excel-import-module');if(h)h.innerHTML='<div class="card"><h2>Importar Excel</h2><p class="low">No se pudo cargar el módulo Excel. Recarga la aplicación.</p></div>'};document.head.appendChild(s)}else if(window.GamaExcelImport)window.GamaExcelImport.render()}
function openItem(x){if(window.GamaModules&&!window.GamaModules.enabled(x[1])){alert('Este módulo está desactivado en Configuración.');return}if(x[1]==='reports'){ensureExcelModule();window.showTab&&window.showTab('reports',null);return}if(x[1]==='gamaPurchasesV14'){if(window.gamaShowPurchases)window.gamaShowPurchases();else{window.showTab&&window.showTab('gamaPurchasesV14',null);setTimeout(()=>window.gamaShowPurchases&&window.gamaShowPurchases(),100)}return}if(x[1]==='price-lists'){if(window.showTab)window.showTab('price-lists',null);window.GamaOpenPriceLists?.();return}if(x[1]==='client-catalog'){if(window.showTab)window.showTab('client-catalog',null);window.GamaOpenClientCatalog?.();return}if(x[1]==='customer-requests'){if(window.showTab)window.showTab('customer-requests',null);window.GamaOpenCustomerRequests?.();return}if(x[1]==='hr'){window.GamaOpenHR?.();return}if(x[1]==='settings'){window.GamaOpenSettings?.();return}if(window.showTab)window.showTab(x[1],null)}
function render(){const host=document.getElementById('mainmenu');if(!host)return;document.documentElement.lang='es';document.querySelectorAll('.gamaLanguage').forEach(e=>e.remove());const s=document.getElementById('gama-final2-css')||document.head.appendChild(document.createElement('style'));s.id='gama-final2-css';s.textContent='#mainmenu .gamaF2Grid{display:grid!important;grid-template-columns:repeat(5,minmax(0,1fr))!important;gap:16px!important;padding:12px 18px 24px!important}#mainmenu .gamaF2Card{display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;min-height:155px!important;padding:18px 10px!important;margin:0!important;background:#fff!important;border:1px solid #C3D2DC!important;border-radius:18px!important;box-shadow:0 1px 2px rgba(23,50,70,.07),0 6px 18px rgba(23,50,70,.10)!important;color:#173246!important;cursor:pointer!important;transition:transform .12s ease,box-shadow .12s ease,border-color .12s ease}#mainmenu .gamaF2Card:hover{border-color:#087c8b!important;box-shadow:0 2px 4px rgba(23,50,70,.08),0 12px 26px rgba(23,50,70,.16)!important;transform:translateY(-2px)}#mainmenu .gamaF2Card:focus-visible{outline:3px solid #087c8b!important;outline-offset:2px}#mainmenu .gamaF2Icon{display:flex!important;align-items:center!important;justify-content:center!important;width:64px!important;height:64px!important;min-width:64px!important;border-radius:18px!important;background:#e8f5f6!important;color:#087c8b!important;margin:0 0 12px!important}#mainmenu .gamaF2Card:nth-child(5n+2) .gamaF2Icon,#mainmenu .gamaF2Card:nth-child(5n+5) .gamaF2Icon{background:#fff0e5!important;color:#f47a2a!important}#mainmenu .gamaF2Icon svg{display:block!important;width:34px!important;height:34px!important;fill:none!important;stroke:currentColor!important;stroke-width:1.9!important;stroke-linecap:round!important;stroke-linejoin:round!important}#mainmenu .gamaF2Title{display:block!important;font-size:16px!important;font-weight:800!important;line-height:1.2!important;text-align:center!important}@media(max-width:900px){#mainmenu .gamaF2Grid{grid-template-columns:repeat(3,minmax(0,1fr))!important}}@media(max-width:600px){#mainmenu .gamaF2Grid{grid-template-columns:repeat(2,minmax(0,1fr))!important;gap:10px!important;padding:10px!important}#mainmenu .gamaF2Card{min-height:145px!important;padding:14px 7px!important}#mainmenu .gamaF2Icon{width:58px!important;height:58px!important;min-width:58px!important}#mainmenu .gamaF2Icon svg{width:30px!important;height:30px!important}.gamaF2Title{font-size:15px!important}}';host.replaceChildren();const h=document.createElement('h2');h.textContent='Menú principal';h.style.cssText='margin:22px 18px 8px;color:#173246;font-size:28px';const p=document.createElement('p');p.textContent='Accede rápidamente a todas las funciones de GAMA Stock Manager.';p.style.cssText='margin:0 18px 14px;color:#7b8891;font-size:14px';const grid=document.createElement('div');grid.className='gamaF2Grid';ITEMS.forEach(x=>{const b=document.createElement('button');b.type='button';b.className='gamaF2Card';const icon=document.createElement('span');icon.className='gamaF2Icon';icon.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">'+I[x[2]]+'</svg>';const label=document.createElement('span');label.className='gamaF2Title';label.textContent=x[0];b.append(icon,label);b.onclick=()=>openItem(x);grid.appendChild(b)});host.append(h,p,grid)}
/* Aquí vivía removeRedundantMainMenuBack(): un MutationObserver sobre todo el
   body que en cada cambio del DOM recorría cada a, button, div, p y span de la
   página para borrar los botones «‹ Menú principal» que index.html repetía en
   cada sección. Con una lista de productos larga eso es recorrer la página
   entera en cada repintado, en el móvil. Los botones ya no se escriben —cada
   pantalla lleva la cabecera común, con su único botón de volver— así que el
   barrido sobra. */
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});else render();
})();