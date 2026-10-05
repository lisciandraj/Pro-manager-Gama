/** Single registry consumed by home, sidebar, settings, access and router. */
const definitions=[
  {id:'surveys',label:'Encuestas',icon:'checklist',group:'Ventas',description:'Cuestionarios, respuestas y satisfacción',accent:'teal',order:7.2,menu:true,roles:['admin','commercial']},
  {id:'sri',label:'Facturación SRI',icon:'invoice',group:'Administración',description:'Facturas electrónicas, autorización SRI y archivo XML / RIDE',accent:'orange',order:15.1,menu:true,roles:['admin']},
  {id:'website',label:'Sitio web',icon:'globe',group:'Administración',description:'Catálogo web, presentación y solicitudes de prueba',accent:'teal',order:16.5,menu:true,roles:['admin']},
  {id:'sav',label:'Reclamaciones',icon:'headset',group:'Ventas',description:'Reclamaciones, garantías y seguimiento',accent:'violet',order:7.1,menu:false,tabOf:'returns',roles:['admin','commercial']},
  {id:'documents',label:'Documentos',icon:'documents',group:'Administración',description:'Archivos, contratos y versiones',accent:'blue',order:14.1,menu:true,roles:['admin','commercial','magasinier']},
  {
    "id": "tms",
    "label": "TMS",
    "icon": "truck",
    "group": "Logística",
    "description": "Preparación, rutas y pruebas de entrega",
    "accent": "teal",
    "order": 5,
    "menu": true,
    "configLabel": "TMS",
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
    "accent": "teal",
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
    "label": "Coco Intelligence",
    "icon": "cocoBot",
    "group": "Resumen",
    "description": "Recomendaciones inteligentes, análisis y asistente para tu empresa",
    "accent": "blue",
    "order": 1,
    "menu": true,
    "configLabel": "Coco Intelligence",
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
    "accent": "blue",
    "order": 0,
    "menu": true,
    "configLabel": "Panel de control y análisis",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ],
    "header": [
      "Panel de control",
      "Toda la analítica del negocio en una pantalla."
    ]
  },
  {
    "id": "notifications",
    "label": "Notificaciones",
    "icon": "bell",
    "group": "Resumen",
    "description": "Avisos y bloqueos pendientes",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "topbar": true,
    "configLabel": "Notificaciones y bloqueos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "knowledge",
    "label": "Base de conocimientos",
    "icon": "knowledge",
    "group": "Administración",
    "description": "Base de conocimientos",
    "accent": "blue",
    "order": 14,
    "menu": true,
    "configLabel": "Base de conocimientos",
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
    "accent": "teal",
    "order": 10,
    "menu": true,
    "configLabel": "Productos",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ],
    "header": [
      "Productos",
      "Crea tus productos y consulta el catálogo."
    ]
  },
  {
    "id": "warehouses",
    "label": "Almacenes y existencias",
    "icon": "warehouse",
    "group": "Inventario y compras",
    "description": "Existencias y ubicaciones",
    "accent": "teal",
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
    "accent": "teal",
    "order": 100,
    "menu": false,
    "retired": true,
    "configLabel": "Entradas / Salidas",
    "roles": [],
    "header": [
      "Movimientos",
      "Registra entradas y salidas de mercancía."
    ]
  },
  {
    "id": "gamaPurchasesV14",
    "label": "Compras",
    "icon": "cart",
    "group": "Inventario y compras",
    "description": "Pedidos de compra y recepciones",
    "accent": "teal",
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
    "tabOf": "quotes",
    "label": "Matriz comercial",
    "icon": "matrix",
    "group": "Ventas",
    "description": "Precios de compra y de venta",
    "accent": "teal",
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
    "accent": "teal",
    "order": 100,
    "menu": true,
    "configLabel": "Códigos de barras",
    "roles": [
      "admin",
      "magasinier"
    ],
    "header": [
      "Códigos de barras",
      "Genera códigos de barras para imprimir."
    ]
  },
  {
    "id": "quotes",
    "label": "Ventas",
    "icon": "sales",
    "group": "Ventas",
    "description": "Solicitudes, presupuestos, pedidos, facturas y tarifas",
    "accent": "violet",
    "order": 3,
    "menu": true,
    "configLabel": "Ventas",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "contacts",
    "label": "Contactos",
    "icon": "users",
    "group": "Administración",
    "description": "Clientes, proveedores y prospectos",
    "accent": "violet",
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
    "group": "Resumen",
    "description": "Ventas, compras y devoluciones de clientes y proveedores",
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
    "tabOf": "quotes",
    "label": "Pedidos de venta",
    "icon": "bag",
    "group": "Ventas",
    "description": "Gestión y seguimiento de pedidos",
    "accent": "violet",
    "order": 4,
    "menu": false,
    "configLabel": "Pedidos de venta",
    "roles": [
      "admin",
      "commercial",
      "magasinier"
    ]
  },
  {
    "id": "payments",
    "tabOf": "quotes",
    "label": "Facturas y cobros",
    "icon": "banknote",
    "group": "Ventas",
    "description": "Registro de facturas y cobros",
    "accent": "violet",
    "order": 6,
    "menu": false,
    "configLabel": "Pagos de clientes",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "returns",
    "label": "Devoluciones y posventa",
    "icon": "returnArrow",
    "group": "Logística",
    "description": "Devoluciones, abonos y reembolsos",
    "accent": "teal",
    "order": 7,
    "menu": true,
    "configLabel": "Devoluciones y posventa",
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
    "accent": "violet",
    "order": 2,
    "menu": true,
    "configLabel": "CRM",
    "roles": [
      "admin",
      "commercial"
    ]
  },
  {
    "id": "price-lists",
    "tabOf": "quotes",
    "label": "Tarifas",
    "icon": "tag",
    "group": "Ventas",
    "description": "Tarifas y precios especiales",
    "accent": "violet",
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
    "settingsTab": "reports",
    "label": "Importar datos",
    "icon": "spreadsheet",
    "group": "Administración",
    "description": "Importar datos desde Excel",
    "accent": "blue",
    "order": 100,
    "menu": false,
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
    "accent": "orange",
    "order": 13,
    "menu": true,
    "configLabel": "Recursos humanos",
    "roles": [
      "admin",
      "commercial",
      "magasinier",
      "rh"
    ]
  },
  {
    "id": "audit",
    "label": "Auditoría",
    "icon": "audit",
    "group": "Administración",
    "description": "Las acciones importantes, quién y cuándo",
    "accent": "orange",
    "order": 100,
    "menu": true,
    "configLabel": "Auditoría",
    "roles": [
      "admin"
    ],
    "header": [
      "Auditoría",
      "Stock, cobros y pagos, facturas, validaciones y accesos."
    ]
  },
  {
    "id": "users",
    "settingsTab": "users",
    "label": "Usuarios",
    "icon": "user",
    "group": "Administración",
    "description": "Cuentas y perfiles",
    "accent": "orange",
    "order": 100,
    "menu": false,
    "configLabel": "Usuarios y accesos",
    "roles": [
      "admin"
    ]
  },
  {
    "id": "access-settings",
    "settingsTab": "access-settings",
    "label": "Parámetros de acceso",
    "icon": "lock",
    "group": "Administración",
    "description": "Permisos por perfil",
    "accent": "orange",
    "order": 100,
    "menu": false,
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
    "accent": "orange",
    "order": 17,
    "menu": true,
    "topbar": true,
    "configLabel": "Configuración",
    "locked": true,
    "roles": [
      "admin",
      "commercial",
      "magasinier",
      "rh"
    ]
  },
  {
    "id": "backup",
    "settingsTab": "backup",
    "label": "Copias de seguridad",
    "icon": "cloud",
    "group": "Administración",
    "description": "Copias de seguridad de tus datos",
    "accent": "orange",
    "order": 100,
    "menu": false,
    "configLabel": "Copias de seguridad",
    "roles": [
      "admin"
    ],
    "header": [
      "Copias de seguridad",
      "Exporta tus datos y guarda copias de la base."
    ]
  },
  {
    "id": "billing",
    "label": "Formulario anterior de presupuestos",
    "description": "Presupuestos para tus clientes, en PDF.",
    "menu": false,
    "retired": true,
    "configLabel": "Formulario anterior de presupuestos",
    "roles": [
      "admin",
      "commercial"
    ],
    "header": [
      "Presupuestos",
      "Presupuestos para tus clientes, en PDF."
    ]
  }
];
export const groups=["Resumen","Inventario y compras","Ventas","Administración","Logística"];
export const aliases={menu:"mainmenu",inicio:"mainmenu",movements:"movement",operations:"dashboard","order-preparation":"tms",clients:"contacts",suppliers:"contacts",stock:"warehouses"};
export const roleAliases={administrador:"admin",comercial:"commercial",almacenero:"magasinier",rrhh:"rh"};
export const roles=Object.fromEntries([["admin","Administrador"],["commercial","Comercial"],["magasinier","Almacenero"],["rh","Responsable RH"]].map(([id,label])=>[id,{label,perms:id==="admin"?"*":definitions.filter(m=>m.roles.includes(id)).map(m=>m.id).concat(id==="commercial"?["customer-requests"]:[])}]));
/* Un módulo que es pestaña de otro (tabOf: los pedidos en Ventas) no tiene tarjeta ni
   línea en las listas de módulos; el módulo que lo contiene se abre para quien tiene al menos una de sus pestañas. */
export const tabsOf=id=>definitions.filter(m=>m.tabOf===id).map(m=>m.id);
export const canOpen=id=>!!window.gamaAccessAllowed?.(id)||tabsOf(id).some(t=>window.gamaAccessAllowed?.(t));
/** Route adapters preserve public module IDs and existing cross-module links. */
const openers={
 matrix:()=>window.GamaMatrix?.open(),
 surveys:()=>window.GamaSurveys?.open(),
 website:()=>window.GamaWebsite?.open(),
 contacts:from=>window.GamaContacts?.open(from),
 sav:()=>window.GamaService?.open(),
 documents:()=>window.GamaDocuments?.open(),
 tms:()=>window.gamaTMS?.open(),
 accounting:()=>window.GamaAccounting?.open(),
 sri:()=>window.GamaAccounting?.openSri(),
 fleet:()=>window.GamaFleet?.open(),
 returns:()=>window.gamaAccessAllowed?.('returns')?window.GamaReturns?.open():window.GamaService?.open(),
 projects:()=>window.GamaProjects?.open(),
 'assistant-ia':()=>window.GamaAssistant?.open(),
 knowledge:()=>window.GamaKnowledge?.open(),
 payments:()=>window.GamaPayments?.open(),
 'dossier-flow':()=>window.GamaDossierFlow?.open(),
 notifications:()=>window.GamaOperations?.open('notifications'),
 quotes:()=>window.GamaQuotes?.enter(),
 'sales-orders':()=>window.GamaSales?.open(),
 reports:()=>window.GamaSettings?.open('reports'),
 backup:()=>window.GamaSettings?.open('backup'),
 gamaPurchasesV14:()=>{if(window.gamaShowPurchases)return window.gamaShowPurchases();window.showTab?.('gamaPurchasesV14',null);setTimeout(()=>window.gamaShowPurchases?.(),100)},
 crm:()=>{window.showTab?.('crm',null);return window.GamaOpenCRM?.()},
 'price-lists':()=>{window.showTab?.('price-lists',null);return window.GamaOpenPriceLists?.()},
 warehouses:()=>{window.showTab?.('warehouses',null);return window.GamaOpenWarehouses?.()},
 hr:()=>window.GamaOpenHR?.(),
 'access-settings':()=>window.GamaOpenAccessSettings?.(),
 settings:()=>window.GamaOpenSettings?.()
};
function openModule(id,from){
 if(window.ArcRuntimeLoaded===false)return window.ArcEnsureRuntime().then(()=>openModule(id,from));
 if(window.gamaAccessAllowed&&!canOpen(id))return;
 if(window.GamaModules&&!window.GamaModules.enabled(id)){window.gamaToast?.(window.GamaI18n?.t('Este módulo está desactivado en Configuración.')||'Este módulo está desactivado en Configuración.');return}
 return openers[id]?openers[id](from):window.showTab?.(id,null);
}

export const registry=definitions.map(m=>Object.freeze({...m,open:from=>openModule(m.id,from)}));
