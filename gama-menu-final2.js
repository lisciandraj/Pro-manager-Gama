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
 ['Entregas / TMS','tms','truck','Logística'],
 ['Contabilidad','accounting','ledger','Administración'],
 ['Gestión de flota','fleet','truck','Administración'],
 ['Proyectos','projects','project','Administración'],
 ['Asistente IA','assistant-ia','sparkles','Resumen'],
 ['Panel de control','dashboard','chart','Resumen'],
 ['Control comercial y logístico','operations','gauge','Resumen'],
 ['Notificaciones','notifications','bell','Resumen'],
 ['Knowledge · Base de conocimientos','knowledge','knowledge','Administración'],
 ['Productos','products','cube','Inventario y compras'],
 ['Almacenes y existencias','warehouses','warehouse','Inventario y compras'],
 ['Entradas / Salidas','movement','move','Inventario y compras'],
 ['Inventario','stock','stock','Inventario y compras'],
 ['Compras','gamaPurchasesV14','cart','Inventario y compras'],
 ['Proveedores','suppliers','factory','Inventario y compras'],
 ['Matriz comercial','matrix','matrix','Inventario y compras'],
 ['Códigos de barras','barcode','barcode','Inventario y compras'],
 ['Presupuestos y facturas','quotes','invoice','Ventas'],
 ['Mis entregas','client-deliveries','pin','Cliente'],
 ['Clientes','clients','users','Ventas'],
 ['Seguimiento de expedientes','dossier-flow','folder','Ventas'],
 ['Pedidos de venta','sales-orders','bag','Ventas'],
 ['Facturas y cobros','payments','banknote','Ventas'],
 ['Preparación de pedidos','order-preparation','checklist','Logística'],
 ['Devoluciones','returns','returnArrow','Logística'],
 ['CRM','crm','handshake','Ventas'],
 ['Catálogo de productos','client-catalog','catalog','Cliente'],
 ['Tarifas','price-lists','tag','Ventas'],
 ['Importar datos','reports','spreadsheet','Administración'],
 ['Recursos humanos','hr','badge','Administración'],
 ['Auditoría','audit','audit','Administración'],
 ['Usuarios','users','user','Administración'],
 ['Parámetros de acceso','access-settings','lock','Administración'],
 ['Configuración','settings','gears','Administración'],
 ['Copias de seguridad','backup','cloud','Administración']
];
/* Categorías conservadas para los consumidores del registro; la portada usa una rejilla plana. */
const GRUPOS=['Resumen','Inventario y compras','Ventas','Cliente','Administración','Logística'];
const I={
sparkles:'<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3ZM20 2v4M18 4h4M3 18v4M1 20h4"/>',

ledger:'<path d="M5 3h12a2 2 0 0 1 2 2v16H7a2 2 0 0 1-2-2V3Z"/><path d="M5 7H3m2 5H3m2 5H3"/><path d="M9 8h6M9 12h6M9 16h3"/>',
 truck:'<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7z"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
returnArrow:'<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 6 6v5"/>',
project:'<path d="M4 3v18h17"/><rect x="7" y="5" width="6" height="3" rx=".5"/><rect x="11" y="10" width="8" height="3" rx=".5"/><rect x="15" y="15" width="6" height="3" rx=".5"/>',
knowledge:'<path d="M5 3h12a2 2 0 0 1 2 2v16H6a3 3 0 0 1-3-3V5a2 2 0 0 1 2-2ZM3 17h16M8 3v8l3-2 3 2V3"/>',
lock:'<rect x="5" y="10" width="14" height="12" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4M12 15v3"/>',
message:'<path d="M21 14a3 3 0 0 1-3 3H9l-6 4V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8Z"/><path d="M7 8h10M7 12h6"/>',
checklist:'<path d="M8 4H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-3"/><rect x="8" y="2" width="8" height="4" rx="1"/><path d="m6 11 1.5 1.5L10 10m-4 7 1.5 1.5L10 16M13 11h4M13 17h4"/>',
banknote:'<rect x="2" y="5" width="20" height="14" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M2 9a4 4 0 0 0 4-4M18 5a4 4 0 0 0 4 4M2 15a4 4 0 0 1 4 4M18 19a4 4 0 0 1 4-4"/>',
bag:'<path d="M5 7h14l2 14H3L5 7Z"/><path d="M9 8V5a3 3 0 0 1 6 0v3M8 14h8m-3-3 3 3-3 3"/>',
folder:'<path d="M3 7V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/><circle cx="7" cy="14" r="1"/><circle cx="12" cy="14" r="1"/><circle cx="17" cy="14" r="1"/><path d="M8 14h3M13 14h3"/>',
pin:'<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><path d="m8.5 10 2.2 2.2 4.8-4.8"/>',
factory:'<path d="M3 21V10l6 3V9l6 3V3h4l2 18H3Z"/><path d="M6 17h1M11 17h1M16 17h1"/>',
bell:'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
gauge:'<path d="M4.2 18a9 9 0 1 1 15.6 0Z"/><path d="M12 5v2M5.6 8l1.5 1.5M18.4 8l-1.5 1.5M12 14l3-4"/><circle cx="12" cy="14" r="1.5"/>',
 handshake:'<path d="M11 6.5 8.8 8.7a2 2 0 0 0 0 2.8l.3.3a2 2 0 0 0 2.8 0l1.2-1.2 3.4 3.4a1.6 1.6 0 0 1-2.3 2.3l-.5-.5"/><path d="M3 7.5 6 5l4 1 3.5-1.5L21 7.5"/><path d="M21 7.5v6M3 7.5v6"/>',
chart:'<path d="M4 19V10m5 9V6m5 13v-8m5 8V3"/><path d="m4 9 5-4 5 3 6-6"/>',
cube:'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
users:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
move:'<path d="M7 4v16M17 20V4M4 7l3-3 3 3M14 17l3 3 3-3"/>',
invoice:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
stock:'<path d="M3 3v18M21 3v18M3 11h18M3 20h18"/><rect x="6" y="4" width="5" height="7" rx=".5"/><rect x="13" y="6" width="5" height="5" rx=".5"/><rect x="6" y="14" width="12" height="6" rx=".5"/>',
audit:'<circle cx="10" cy="10" r="7"/><path d="m15 15 6 6M7 8h6M7 12h4"/>',
cart:'<path d="M3 4h2l2.2 10.2a2 2 0 0 0 2 1.6h7.4a2 2 0 0 0 1.9-1.4L20 8H6"/><circle cx="9" cy="19" r="1.5"/><circle cx="17" cy="19" r="1.5"/><path d="M9 11h8M12 8v6M15 8v6"/>',
spreadsheet:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18M15 3v18"/>',
gears:'<g stroke-width="1.4"><path d="M11.61 5.44L13.50 5.81L13.50 9.59L11.61 9.96L11.61 9.96L12.23 11.78L8.97 13.67L7.70 12.21L7.70 12.21L6.43 13.67L3.17 11.78L3.79 9.96L3.79 9.96L1.90 9.59L1.90 5.81L3.79 5.44L3.79 5.44L3.17 3.62L6.43 1.73L7.70 3.19L7.70 3.19L8.97 1.73L12.23 3.62L11.61 5.44Z"/><circle cx="7.7" cy="7.7" r="1.83"/><path d="M20.14 15.19L21.66 15.49L21.66 18.51L20.14 18.81L20.14 18.81L20.64 20.28L18.02 21.79L17.00 20.63L17.00 20.63L15.98 21.79L13.36 20.28L13.86 18.81L13.86 18.81L12.34 18.51L12.34 15.49L13.86 15.19L13.86 15.19L13.36 13.72L15.98 12.21L17.00 13.37L17.00 13.37L18.02 12.21L20.64 13.72L20.14 15.19Z"/><circle cx="17" cy="17" r="1.47"/></g>',
cloud:'<path d="M7 18h11a4 4 0 0 0 .5-8 6 6 0 0 0-11.6 1A3.5 3.5 0 0 0 7 18Z"/><path d="M12 12v6m0 0-2-2m2 2 2-2"/>',
user:'<rect x="4" y="3" width="16" height="14" rx="2"/><path d="m4 17-2 4h20l-2-4M8 14a4 4 0 0 1 8 0"/><circle cx="12" cy="8" r="2"/>',
barcode:'<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
catalog:'<path d="M12 5C9 3 5 3 2 4v15c3-1 7-1 10 1 3-2 7-2 10-1V4c-3-1-7-1-10 1ZM12 5v15M5 8h4M5 12h4M15 8h4M15 12h4"/>',
tag:'<path d="M3 12V5.5A2.5 2.5 0 0 1 5.5 3H12l9 9-9 9-9-9Z"/><circle cx="7.5" cy="7.5" r="1.4"/>',
matrix:'<rect x="3" y="3" width="6" height="6" rx="1"/><rect x="15" y="3" width="6" height="6" rx="1"/><rect x="3" y="15" width="6" height="6" rx="1"/><rect x="15" y="15" width="6" height="6" rx="1"/><path d="M9 6h6M6 9v6M18 9v6M9 18h6"/>',
warehouse:'<path d="M3 10.5 12 4l9 6.5V20H3z"/><path d="M7 20v-6h10v6M7 14h10"/>',
badge:'<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M9 6V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V6"/><circle cx="12" cy="12" r="2"/><path d="M8.5 17c.4-1.6 1.8-2.5 3.5-2.5s3.1.9 3.5 2.5"/>'};
function ensureExcelModule(){let section=document.getElementById('reports');if(!section){section=document.createElement('section');section.id='reports';(document.querySelector('.wrap')||document.body).appendChild(section)}section.innerHTML='<div class="wrap"><div id="excel-import-module" data-module="excel"></div></div>';if(!document.getElementById('gamaExcelLoader')){const s=document.createElement('script');s.id='gamaExcelLoader';s.src='gama-excel-import-v1.js?v=20260918-architect1';s.onload=()=>window.GamaExcelImport&&window.GamaExcelImport.render();s.onerror=()=>{const h=document.getElementById('excel-import-module');if(h)h.innerHTML='<div class="card"><h2 data-gi=63e31998d5d9>Importar datos</h2><p class="low" data-gi=2f9af44c4156>No se pudo cargar el módulo Excel. Recarga la aplicación.</p></div>'};document.head.appendChild(s)}else if(window.GamaExcelImport)window.GamaExcelImport.render()}
function openItem(x){if(window.gamaAccessAllowed&&!window.gamaAccessAllowed(x[1]))return;if(x[1]==='tms'){window.gamaTMS?.open('planning');return}if(x[1]==='accounting'){window.GamaAccounting?.open();return}if(x[1]==='fleet'){window.GamaFleet?.open();return}if(x[1]==='returns'){window.GamaReturns?.open();return}if(x[1]==='projects'){window.GamaProjects?.open();return}if(x[1]==='assistant-ia'){window.GamaAssistant?.open();return}if(x[1]==='knowledge'){window.GamaKnowledge?.open();return}if(x[1]==='payments'){window.GamaPayments?.open();return}if(x[1]==='order-preparation'){window.GamaPreparation?.open();return}if(x[1]==='dossier-flow'){window.GamaDossierFlow?.open();return}if(['operations','notifications'].includes(x[1])){window.GamaOperations?.open(x[1]);return}if(x[1]==='quotes'){window.GamaQuotes?.open();return}if(x[1]==='client-deliveries'){window.GamaQuotes?.deliveries();return}if(x[1]==='sales-orders'){window.GamaSales?.open();return}if(window.GamaModules&&!window.GamaModules.enabled(x[1])){alert('Este módulo está desactivado en Configuración.');return}if(x[1]==='reports'){ensureExcelModule();window.showTab&&window.showTab('reports',null);return}if(x[1]==='gamaPurchasesV14'){if(window.gamaShowPurchases)window.gamaShowPurchases();else{window.showTab&&window.showTab('gamaPurchasesV14',null);setTimeout(()=>window.gamaShowPurchases&&window.gamaShowPurchases(),100)}return}if(x[1]==='crm'){if(window.showTab)window.showTab('crm',null);window.GamaOpenCRM?.();return}if(x[1]==='price-lists'){if(window.showTab)window.showTab('price-lists',null);window.GamaOpenPriceLists?.();return}if(x[1]==='client-catalog'){if(window.showTab)window.showTab('client-catalog',null);window.GamaOpenClientCatalog?.();return}if(x[1]==='customer-requests'){if(window.showTab)window.showTab('customer-requests',null);window.GamaOpenCustomerRequests?.();return}if(x[1]==='warehouses'){if(window.showTab)window.showTab('warehouses',null);window.GamaOpenWarehouses?.();return}if(x[1]==='hr'){window.GamaOpenHR?.();return}if(x[1]==='access-settings'){window.GamaOpenAccessSettings?.();return}if(x[1]==='settings'){window.GamaOpenSettings?.();return}if(window.showTab)window.showTab(x[1],null)}

/* Una línea por módulo que diga para qué sirve. El menú deja de ser una
   rejilla de iconos a adivinar: se lee y se entra al que toca. */
const DESC={
 tms:'Transporte y pruebas de entrega',
 dashboard:'Vista de conjunto de tu actividad',
 'assistant-ia':'Analiza tus datos y obtén respuestas',
 operations:'Alertas comerciales y logísticas',
 notifications:'Avisos y bloqueos pendientes',
 crm:'Prospectos y oportunidades',
 quotes:'Crea y sigue tus presupuestos',
 'sales-orders':'Gestión y seguimiento de pedidos',
 'order-preparation':'Preparación y pruebas de entrega',
 payments:'Registro de facturas y cobros',
 returns:'Devoluciones, abonos y reembolsos',
 gamaPurchasesV14:'Pedidos de compra y recepciones',
 suppliers:'Gestión de los proveedores',
 products:'Catálogo y fichas de producto',
 warehouses:'Existencias y ubicaciones',
 stock:'Niveles de existencias disponibles',
 movement:'Entradas y salidas de mercancía',
 matrix:'Precios de compra y de venta',
 barcode:'Etiquetas y códigos de barras',
 'dossier-flow':'Seguimiento de expedientes',
 'price-lists':'Tarifas y precios especiales',
 clients:'Base de clientes',
 'client-catalog':'Catálogo para tus clientes',
 'client-deliveries':'Tus entregas y sus pruebas',
 projects:'Gestión de proyectos',
 hr:'Equipos, ausencias y nóminas',
 accounting:'Seguimiento financiero y contabilidad',
 fleet:'Vehículos, papeles y consumos',
 knowledge:'Base de conocimientos',
 audit:'Historial de todas las operaciones',
 users:'Cuentas y perfiles',
 'access-settings':'Permisos por perfil',
 settings:'Configuración del ERP',
 backup:'Copias de seguridad de tus datos',
 reports:'Importar datos desde Excel',
};
const T=s=>window.GamaI18n?.t?.(s)||s;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const can=id=>!!window.gamaAccessAllowed?.(id);
const ORDER=['dashboard','assistant-ia','crm','quotes','sales-orders','tms','payments','returns','gamaPurchasesV14','suppliers','products','warehouses','projects','hr','knowledge','accounting','clients','settings'];
const ACCENT={dashboard:'cyan','assistant-ia':'pink',crm:'blue',quotes:'cyan','sales-orders':'red',tms:'indigo',payments:'blue',returns:'red',gamaPurchasesV14:'cyan',suppliers:'indigo',products:'green',warehouses:'blue',projects:'blue',hr:'green',knowledge:'violet',accounting:'orange',clients:'cyan',settings:'indigo',
 fleet:'indigo',operations:'cyan',notifications:'orange',movement:'cyan',stock:'green',matrix:'violet',barcode:'blue',
 'client-deliveries':'indigo','dossier-flow':'blue','order-preparation':'green','client-catalog':'cyan','price-lists':'orange',
 reports:'green',audit:'cyan',users:'blue','access-settings':'violet',backup:'blue','customer-requests':'blue'};
const ordered=()=>[...ITEMS].sort((a,b)=>(ORDER.includes(a[1])?ORDER.indexOf(a[1]):100)-(ORDER.includes(b[1])?ORDER.indexOf(b[1]):100));
const preferenceKey=()=>{try{const u=JSON.parse(localStorage.getItem('gama_session_v1')||'{}');return 'architect_home_modules_v1:'+String(u.id||u.email||u.username||u.name||u.role||'')}catch(_){return 'architect_home_modules_v1'}};
function hiddenModules(){try{return new Set(JSON.parse(localStorage.getItem(preferenceKey())||'[]'))}catch(_){return new Set()}}
function applyPreferences(){const hidden=hiddenModules();document.querySelectorAll('#mainmenu .gamaF2Card').forEach(c=>c.classList.toggle('arcPreferenceHidden',hidden.has(c.dataset.gamaModule)))}
function personalize(){
 const old=document.getElementById('arcCustomize');if(old)old.remove();
 const d=document.createElement('dialog');d.id='arcCustomize';d.className='arcCustomize';d.setAttribute('aria-labelledby','arcCustomizeTitle');
 const hidden=hiddenModules();
 d.innerHTML='<form method="dialog"><div class="arcSectionHead"><h2 id="arcCustomizeTitle">'+esc(T('Personalizar módulos'))+'</h2><button class="ghost" value="cancel" aria-label="'+esc(T('Cerrar'))+'">×</button></div><p>'+esc(T('Elige los módulos que se muestran en tu inicio.'))+'</p><div class="arcCustomizeList">'+ordered().filter(x=>can(x[1])).map(x=>'<label><input type="checkbox" value="'+esc(x[1])+'" '+(!hidden.has(x[1])?'checked':'')+'><span>'+esc(T(x[0]))+'</span></label>').join('')+'</div><div class="gsActions"><button class="secondary" value="reset">'+esc(T('Mostrar todos'))+'</button><button class="primary" value="save">'+esc(T('Guardar'))+'</button></div></form>';
 document.body.appendChild(d);
 d.addEventListener('close',()=>{if(d.returnValue==='save'){const invisible=[...d.querySelectorAll('input:not(:checked)')].map(n=>n.value);try{localStorage.setItem(preferenceKey(),JSON.stringify(invisible))}catch(_){}applyPreferences()}else if(d.returnValue==='reset'){try{localStorage.removeItem(preferenceKey())}catch(_){}applyPreferences()}d.remove()},{once:true});d.showModal();
}

function render(){
 const host=document.getElementById('mainmenu');if(!host)return;
 document.documentElement.lang=window.GamaI18n?.language||'es';
 host.replaceChildren();
 const cabecera=document.createElement('div');cabecera.className='gamaF2Head';
 const h=document.createElement('h1');h.setAttribute('data-gi-live','');h.textContent='Menú principal';
 const p=document.createElement('p');p.setAttribute('data-gi-live','');p.textContent='Accede rápidamente a todas las funciones de Architect ERP.';
 cabecera.append(h,p);

 const fila=document.createElement('div');fila.className='gamaF2Kpis';fila.id='gamaF2Kpis';fila.hidden=true;

 const grid=document.createElement('div');grid.className='gamaF2Grid';
 ordered().forEach(x=>{
   const g=x[3];
   const b=document.createElement('button');b.type='button';b.className='gamaF2Card';
   b.dataset.gamaGrupo=g;b.dataset.gamaModule=x[1];
   const fam=ACCENT[x[1]]||'cyan';
   if(x[1]==='tms')b.dataset.gamaTmsCard='1';
   const icon=document.createElement('span');icon.className='gamaF2Icon';icon.dataset.arcFam=fam;
   icon.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">'+I[x[2]]+'</svg>';
   const cuerpo=document.createElement('span');cuerpo.className='gamaF2Body';
   const label=document.createElement('span');label.className='gamaF2Title';label.textContent=x[0];label.dataset.gamaSource=x[0];
   cuerpo.appendChild(label);
   if(DESC[x[1]]){
    const d=document.createElement('span');d.className='gamaF2Desc';d.textContent=DESC[x[1]];d.dataset.gamaSource=DESC[x[1]];d.setAttribute('data-gi-live','');
    cuerpo.appendChild(d);
   }
   const go=document.createElementNS('http://www.w3.org/2000/svg','svg');
   go.setAttribute('class','gamaF2Go');go.setAttribute('viewBox','0 0 24 24');go.setAttribute('aria-hidden','true');
   go.innerHTML='<path d="M5 12h14M13 6l6 6-6 6"/>';
   b.append(icon,cuerpo,go);
   if(x[1]==='notifications')b.dataset.goNav='notifications';
   b.onclick=()=>openItem(x);
   grid.appendChild(b);
 });
 const vacio=document.createElement('div');vacio.className='gamaF2Vacio';vacio.id='gamaF2Vacio';vacio.hidden=true;
 vacio.textContent='Ningún módulo coincide con la búsqueda.';
 grid.appendChild(vacio);

 const heading=document.createElement('div');heading.className='arcSectionHead';
 heading.innerHTML='<h2>'+esc(T('Tus módulos'))+'</h2><button type="button" class="ghost arcCustomizeButton" id="arcCustomizeOpen"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 3h6v6H3zM15 3h6v6h-6zM3 15h6v6H3zM15 15h6v6h-6z"/></svg><span>'+esc(T('Personalizar'))+'</span></button>';
 host.append(cabecera,fila,heading,grid);
 heading.querySelector('button').onclick=personalize;
 window.ArchitectHomeOrder?.mount(grid);applyPreferences();window.ArchitectHomeKpis?.mount(fila);window.GamaI18n?.scan?.(host);
}

window.addEventListener('gama:language-change',()=>{const h=document.querySelector('.arcSectionHead h2');if(h)h.textContent=T('Tus módulos');const b=document.querySelector('#arcCustomizeOpen span');if(b)b.textContent=T('Personalizar')});

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
 const input=document.getElementById('arcSearchInput');
 if(!input)return;
 e.preventDefault();input.focus();input.select();
});
/* La barra lateral y el menú de tarjetas enseñan lo mismo, así que leen la
   misma lista. Exponerla evita la copia que se desincroniza al añadir un
   módulo: se añade aquí y aparece en los dos sitios. */
window.GamaMenu={items:ITEMS,groups:GRUPOS,icons:I,open:openItem,render};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});else render();
})();
