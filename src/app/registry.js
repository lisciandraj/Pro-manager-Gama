/** Single registry consumed by home, sidebar, settings, access and router. */
const definitions=[
  {id:'sav',label:'Servicio posventa',icon:'headset',group:'Ventas',description:'Reclamaciones, garantías y seguimiento',accent:'orange',order:7.1,menu:true,roles:['admin','commercial']},
  {id:'documents',label:'Documentos',icon:'documents',group:'Administración',description:'Archivos, contratos y versiones',accent:'blue',order:14.1,menu:true,roles:['admin','commercial','magasinier']},
  {
    "id": "tms",
    "label": "Entrega",
    "icon": "truck",
    "group": "Logística",
    "description": "Preparación, rutas y pruebas de entrega",
    "accent": "indigo",
    "order": 5,
    "menu": true,
    "configLabel": "Entrega",
    "roles": [
      "admin",
      "magasinier"
    ]
  },
  {
    "id": "accounting",
    "label": "Contabilidad",
    "icon": "ledger",
    "group": "Administración",
    "description": "Seguimiento financiero y contabilidad",
    "accent": "orange",
    "order": 15,
    "menu": true,
    "configLabel": "Contabilidad",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "fleet",
    "label": "Gestión de flota",
    "icon": "car",
    "group": "Administración",
    "description": "Vehículos, papeles y consumos",
    "accent": "indigo",
    "order": 100,
    "menu": true,
    "configLabel": "Gestión de flota",
    "roles": [
      "admin"
    ]
  },
  {
    "id": "projects",
    "label": "Proyectos",
    "icon": "project",
    "group": "Administración",
    "description": "Gestión de proyectos",
    "accent": "blue",
    "order": 12,
    "menu": true,
    "configLabel": "Proyectos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "assistant-ia",
    "label": "Asistente IA",
    "icon": "sparkles",
    "group": "Resumen",
    "description": "Analiza tus datos y obtén respuestas",
    "accent": "pink",
    "order": 1,
    "menu": true,
    "configLabel": "Asistente IA",
    "roles": [
      "admin"
    ]
  },
  {
    "id": "dashboard",
    "label": "Panel de control",
    "icon": "chart",
    "group": "Resumen",
    "description": "Vista de conjunto de tu actividad",
    "accent": "cyan",
    "order": 0,
    "menu": true,
    "configLabel": "Panel de control y análisis",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ],
    "header": [
      "📈 Panel de control",
      "Toda la analítica del negocio en una pantalla."
    ]
  },
  {
    "id": "notifications",
    "label": "Notificaciones",
    "icon": "bell",
    "group": "Resumen",
    "description": "Avisos y bloqueos pendientes",
    "accent": "orange",
    "order": 100,
    "menu": true,
    "configLabel": "Notificaciones y bloqueos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "knowledge",
    "label": "Knowledge · Base de conocimientos",
    "icon": "knowledge",
    "group": "Administración",
    "description": "Base de conocimientos",
    "accent": "violet",
    "order": 14,
    "menu": true,
    "configLabel": "Knowledge · Base de conocimientos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "products",
    "label": "Productos",
    "icon": "cube",
    "group": "Inventario y compras",
    "description": "Catálogo y fichas de producto",
    "accent": "green",
    "order": 10,
    "menu": true,
    "configLabel": "Productos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ],
    "header": [
      "📦 Productos",
      "Crea tus productos y consulta el catálogo."
    ]
  },
  {
    "id": "warehouses",
    "label": "Almacenes y existencias",
    "icon": "warehouse",
    "group": "Inventario y compras",
    "description": "Existencias y ubicaciones",
    "accent": "blue",
    "order": 11,
    "menu": true,
    "configLabel": "Almacenes y existencias",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "movement",
    "label": "Entradas / Salidas",
    "icon": "move",
    "group": "Inventario y compras",
    "description": "Entradas y salidas de mercancía",
    "accent": "cyan",
    "order": 100,
    "menu": true,
    "configLabel": "Entradas / Salidas",
    "roles": [
      "admin",
      "magasinier"
    ],
    "header": [
      "🔄 Movimientos",
      "Registra entradas y salidas de mercancía."
    ]
  },
  {
    "id": "stock",
    "label": "Inventario",
    "icon": "stock",
    "group": "Inventario y compras",
    "description": "Niveles de existencias disponibles",
    "accent": "green",
    "order": 100,
    "menu": true,
    "configLabel": "Inventario",
    "roles": [
      "admin",
      "magasinier"
    ],
    "header": [
      "📊 Inventario",
      "Las existencias de todos tus productos."
    ]
  },
  {
    "id": "gamaPurchasesV14",
    "label": "Compras",
    "icon": "cart",
    "group": "Inventario y compras",
    "description": "Pedidos de compra y recepciones",
    "accent": "cyan",
    "order": 8,
    "menu": true,
    "configLabel": "Compras",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "matrix",
    "label": "Matriz comercial",
    "icon": "matrix",
    "group": "Inventario y compras",
    "description": "Precios de compra y de venta",
    "accent": "violet",
    "order": 100,
    "menu": true,
    "configLabel": "Matriz comercial",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "barcode",
    "label": "Códigos de barras",
    "icon": "barcode",
    "group": "Inventario y compras",
    "description": "Etiquetas y códigos de barras",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "configLabel": "Códigos de barras",
    "roles": [
      "admin",
      "magasinier"
    ],
    "header": [
      "🏷️ Códigos de barras",
      "Genera códigos de barras para imprimir."
    ]
  },
  {
    "id": "quotes",
    "label": "Presupuestos y facturas",
    "icon": "invoice",
    "group": "Ventas",
    "description": "Crea y sigue tus presupuestos",
    "accent": "cyan",
    "order": 3,
    "menu": true,
    "configLabel": "Presupuestos y facturas",
    "roles": [
      "admin",
      "commercial",
      "client"
    ]
  },
  {
    "id": "client-deliveries",
    "label": "Mis entregas",
    "icon": "pin",
    "group": "Cliente",
    "description": "Tus entregas y sus pruebas",
    "accent": "indigo",
    "order": 100,
    "menu": true,
    "configLabel": "Mis entregas y pruebas",
    "roles": [
      "admin",
      "client"
    ]
  },
  {
    "id": "contacts",
    "label": "Contactos",
    "icon": "users",
    "group": "Ventas",
    "description": "Clientes, proveedores y prospectos",
    "accent": "cyan",
    "order": 16,
    "menu": true,
    "configLabel": "Contactos",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "dossier-flow",
    "label": "Seguimiento de procesos",
    "icon": "folder",
    "group": "Ventas",
    "description": "Venta (PDV) y compra (PDC), paso a paso",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "configLabel": "Seguimiento de procesos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "sales-orders",
    "label": "Pedidos de venta",
    "icon": "bag",
    "group": "Ventas",
    "description": "Gestión y seguimiento de pedidos",
    "accent": "red",
    "order": 4,
    "menu": true,
    "configLabel": "Pedidos de venta",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "payments",
    "label": "Facturas y cobros",
    "icon": "banknote",
    "group": "Ventas",
    "description": "Registro de facturas y cobros",
    "accent": "blue",
    "order": 6,
    "menu": true,
    "configLabel": "Pagos de clientes",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "returns",
    "label": "Devoluciones",
    "icon": "returnArrow",
    "group": "Logística",
    "description": "Devoluciones, abonos y reembolsos",
    "accent": "red",
    "order": 7,
    "menu": true,
    "configLabel": "Devoluciones",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "crm",
    "label": "CRM",
    "icon": "handshake",
    "group": "Ventas",
    "description": "Prospectos y oportunidades",
    "accent": "blue",
    "order": 2,
    "menu": true,
    "configLabel": "CRM",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "client-catalog",
    "label": "Catálogo de productos",
    "icon": "catalog",
    "group": "Cliente",
    "description": "Catálogo para tus clientes",
    "accent": "cyan",
    "order": 100,
    "menu": true,
    "configLabel": "Catálogo de productos",
    "roles": [
      "admin",
      "client"
    ]
  },
  {
    "id": "price-lists",
    "label": "Tarifas",
    "icon": "tag",
    "group": "Ventas",
    "description": "Tarifas y precios especiales",
    "accent": "orange",
    "order": 100,
    "menu": true,
    "configLabel": "Tarifas",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "reports",
    "label": "Importar datos",
    "icon": "spreadsheet",
    "group": "Administración",
    "description": "Importar datos desde Excel",
    "accent": "green",
    "order": 100,
    "menu": true,
    "configLabel": "Importar datos",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "hr",
    "label": "Recursos humanos",
    "icon": "badge",
    "group": "Administración",
    "description": "Equipos, ausencias y nóminas",
    "accent": "green",
    "order": 13,
    "menu": true,
    "configLabel": "Recursos humanos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "audit",
    "label": "Auditoría",
    "icon": "audit",
    "group": "Administración",
    "description": "Historial de todas las operaciones",
    "accent": "cyan",
    "order": 100,
    "menu": true,
    "configLabel": "Auditoría",
    "roles": [
      "admin"
    ],
    "header": [
      "🔎 Auditoría",
      "Historial de todas las entradas y salidas."
    ]
  },
  {
    "id": "users",
    "label": "Usuarios",
    "icon": "user",
    "group": "Administración",
    "description": "Cuentas y perfiles",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "configLabel": "Usuarios y accesos",
    "roles": [
      "admin"
    ]
  },
  {
    "id": "access-settings",
    "label": "Parámetros de acceso",
    "icon": "lock",
    "group": "Administración",
    "description": "Permisos por perfil",
    "accent": "violet",
    "order": 100,
    "menu": true,
    "configLabel": "Parámetros de acceso",
    "locked": true,
    "roles": [
      "admin"
    ]
  },
  {
    "id": "settings",
    "label": "Configuración",
    "icon": "gears",
    "group": "Administración",
    "description": "Configuración del ERP",
    "accent": "indigo",
    "order": 17,
    "menu": true,
    "configLabel": "Configuración",
    "locked": true,
    "roles": [
      "admin",
      "commercial",
      "magasinier",
      "client"
    ]
  },
  {
    "id": "backup",
    "label": "Copias de seguridad",
    "icon": "cloud",
    "group": "Administración",
    "description": "Copias de seguridad de tus datos",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "configLabel": "Copias de seguridad",
    "roles": [
      "admin"
    ],
    "header": [
      "💾 Copias de seguridad",
      "Exporta tus datos y guarda copias de la base."
    ]
  },
  {
    "id": "billing",
    "label": "Formulario anterior de presupuestos",
    "description": "Presupuestos para tus clientes, en PDF.",
    "menu": false,
    "configLabel": "Formulario anterior de presupuestos",
    "roles": [
      "admin",
      "commercial"
    ],
    "header": [
      "🧾 Presupuestos",
      "Presupuestos para tus clientes, en PDF."
    ]
  }
];
export const groups=["Resumen","Inventario y compras","Ventas","Cliente","Administración","Logística"];
export const aliases={menu:"mainmenu",inicio:"mainmenu",movements:"movement",operations:"dashboard","order-preparation":"tms",clients:"contacts",suppliers:"contacts"};
export const roleAliases={administrador:"admin",comercial:"commercial",almacenero:"magasinier",cliente:"client"};
export const roles=Object.fromEntries([["admin","Administrador"],["commercial","Comercial"],["magasinier","Almacenero"],["client","Cliente"]].map(([id,label])=>[id,{label,perms:id==="admin"?"*":definitions.filter(m=>m.roles.includes(id)).map(m=>m.id).concat(id==="commercial"?["customer-requests"]:[])}]));
function ensureExcelModule(){let section=document.getElementById('reports');if(!section){section=document.createElement('section');section.id='reports';(document.querySelector('.wrap')||document.body).appendChild(section)}section.innerHTML='<div class="wrap"><div id="excel-import-module" data-module="excel"></div></div>';if(!document.getElementById('gamaExcelLoader')){const s=document.createElement('script');s.id='gamaExcelLoader';s.src=window.ArcAssets?.['gama-excel-import-v1.js']||'gama-excel-import-v1.js';s.onload=()=>window.GamaExcelImport&&window.GamaExcelImport.render();s.onerror=()=>{const h=document.getElementById('excel-import-module');if(h)h.innerHTML='<div class="card"><h2 data-gi=63e31998d5d9>Importar datos</h2><p class="low" data-gi=2f9af44c4156>No se pudo cargar el módulo Excel. Recarga la aplicación.</p></div>'};document.head.appendChild(s)}else if(window.GamaExcelImport)window.GamaExcelImport.render()}
function openLegacy(x,from){if(window.gamaAccessAllowed&&!window.gamaAccessAllowed(x[1]))return;if(x[1]==='contacts'){return window.GamaContacts?.open(from)}if(x[1]==='sav'){return window.GamaService?.open()}if(x[1]==='documents'){return window.GamaDocuments?.open()}if(x[1]==='tms'){return window.gamaTMS?.open()}if(x[1]==='accounting'){return window.GamaAccounting?.open()}if(x[1]==='fleet'){return window.GamaFleet?.open()}if(x[1]==='returns'){return window.GamaReturns?.open()}if(x[1]==='projects'){return window.GamaProjects?.open()}if(x[1]==='assistant-ia'){return window.GamaAssistant?.open()}if(x[1]==='knowledge'){return window.GamaKnowledge?.open()}if(x[1]==='payments'){return window.GamaPayments?.open()}if(x[1]==='dossier-flow'){return window.GamaDossierFlow?.open()}if(['operations','notifications'].includes(x[1])){return window.GamaOperations?.open(x[1])}if(x[1]==='quotes'){return window.GamaQuotes?.open()}if(x[1]==='client-deliveries'){return window.GamaQuotes?.deliveries()}if(x[1]==='sales-orders'){return window.GamaSales?.open()}if(window.GamaModules&&!window.GamaModules.enabled(x[1])){alert('Este módulo está desactivado en Configuración.');return}if(x[1]==='reports'){ensureExcelModule();window.showTab&&window.showTab('reports',null);return}if(x[1]==='gamaPurchasesV14'){if(window.gamaShowPurchases)window.gamaShowPurchases();else{window.showTab&&window.showTab('gamaPurchasesV14',null);setTimeout(()=>window.gamaShowPurchases&&window.gamaShowPurchases(),100)}return}if(x[1]==='crm'){if(window.showTab)window.showTab('crm',null);window.GamaOpenCRM?.();return}if(x[1]==='price-lists'){if(window.showTab)window.showTab('price-lists',null);window.GamaOpenPriceLists?.();return}if(x[1]==='client-catalog'){if(window.showTab)window.showTab('client-catalog',null);window.GamaOpenClientCatalog?.();return}if(x[1]==='customer-requests'){if(window.showTab)window.showTab('customer-requests',null);window.GamaOpenCustomerRequests?.();return}if(x[1]==='warehouses'){if(window.showTab)window.showTab('warehouses',null);window.GamaOpenWarehouses?.();return}if(x[1]==='hr'){window.GamaOpenHR?.();return}if(x[1]==='access-settings'){window.GamaOpenAccessSettings?.();return}if(x[1]==='settings'){window.GamaOpenSettings?.();return}if(window.showTab)window.showTab(x[1],null)}
export const registry=definitions.map(m=>Object.freeze({...m,open:from=>openLegacy([m.label,m.id,m.icon,m.group],from)}));
