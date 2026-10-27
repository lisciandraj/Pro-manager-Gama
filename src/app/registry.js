export const groups=["Resumen","Inventario y compras","Ventas","Administración","Logística"];
const adminRoles=['admin'],commercialRoles=['admin','commercial'],staffRoles=['admin','commercial','magasinier'],warehouseRoles=['admin','magasinier'];
/** Single registry consumed by home, sidebar, settings, access and router. */
const definitions=[
  {id:'workhub',label:'Espacio de trabajo',icon:'workhub',group:groups[0],description:'Conversaciones, tareas, documentos y contexto del equipo',accent:'blue',order:0.5,menu:true,roles:staffRoles},
  {id:'contracts',label:'Contratos',icon:'contract',group:groups[2],description:'Contratos y pedidos recurrentes',accent:'violet',order:4.1,menu:true,roles:commercialRoles},
  {id:'expenses',label:'Gastos y justificantes',icon:'expense',group:groups[3],description:'Justificantes, validación y reembolsos',accent:'orange',order:15.2,menu:true,roles:adminRoles},
  {id:'surveys',label:'Encuestas y marketing',icon:'checklist',group:groups[2],description:'Cuestionarios y campañas e-mail o WhatsApp',accent:'teal',order:7.2,menu:true,roles:commercialRoles},
  {id:'sri',label:'Facturación SRI',icon:'invoice',group:groups[3],description:'Facturas electrónicas, autorización SRI y archivo XML / RIDE',accent:'orange',order:15.1,menu:true,roles:adminRoles},
  {id:'website',label:'Sitio web',icon:'globe',group:groups[3],description:'Catálogo web, presentación y solicitudes de prueba',accent:'teal',order:16.5,menu:true,roles:adminRoles},
  {id:'sav',label:'Reclamaciones',icon:'headset',group:groups[2],description:'Reclamaciones, garantías y seguimiento',accent:'violet',order:7.1,menu:false,tabOf:'returns',roles:commercialRoles},
  {id:'documents',label:'Documentos',icon:'documents',group:groups[3],description:'Archivos, contratos y versiones',accent:'blue',order:14.1,menu:true,roles:staffRoles},
  {
    "id": "tms",
    "label": "TMS",
    "icon": "truck",
    "group": groups[4],
    "description": "Preparación, rutas y pruebas de entrega",
    "accent": "teal",
    "order": 5,
    "menu": true,
    "roles": warehouseRoles
  },
  {
    "id": "accounting",
    "label": "Contabilidad",
    "icon": "ledger",
    "group": groups[3],
    "description": "Seguimiento financiero y contabilidad",
    "accent": "orange",
    "order": 15,
    "menu": true,
    "roles": commercialRoles
  },
  {
    "id": "fleet",
    "label": "Gestión de flota",
    "icon": "car",
    "group": groups[3],
    "description": "Vehículos, papeles y consumos",
    "accent": "teal",
    "order": 100,
    "menu": true,
    "roles": adminRoles
  },
  {
    "id": "projects",
    "label": "Proyectos",
    "icon": "project",
    "group": groups[3],
    "description": "Gestión de proyectos",
    "accent": "blue",
    "order": 12,
    "menu": true,
    "roles": staffRoles
  },
  {
    "id": "assistant-ia",
    "label": "Agent Coco",
    "icon": "cocoBot",
    "group": groups[0],
    "description": "Conversación e informes de análisis semanales para tu empresa",
    "accent": "blue",
    "order": 1,
    "menu": true,
    "roles": adminRoles
  },
  {
    "id": "dashboard",
    "label": "Panel de control",
    "icon": "chart",
    "group": groups[0],
    "description": "Vista de conjunto de tu actividad",
    "accent": "blue",
    "order": 0,
    "menu": true,
    "configLabel": "Panel de control y análisis",
    "roles": staffRoles,
    "header": [
      "Panel de control",
      "Toda la analítica del negocio en una pantalla."
    ]
  },
  {
    "id": "notifications",
    "label": "Notificaciones",
    "icon": "bell",
    "group": groups[0],
    "description": "Avisos y bloqueos pendientes",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "topbar": true,
    "configLabel": "Notificaciones y bloqueos",
    "roles": staffRoles
  },
  {
    "id": "knowledge",
    "label": "Base de conocimientos",
    "icon": "knowledge",
    "group": groups[3],
    "description": "Base de conocimientos",
    "accent": "blue",
    "order": 14,
    "menu": true,
    "roles": staffRoles
  },
  {
    "id": "products",
    "label": "Productos",
    "icon": "cube",
    "group": groups[1],
    "description": "Catálogo y fichas de producto",
    "accent": "teal",
    "order": 10,
    "menu": true,
    "roles": staffRoles,
    "header": [
      "Productos",
      "Crea tus productos y consulta el catálogo."
    ]
  },
  {
    "id": "warehouses",
    "label": "Almacenes y existencias",
    "icon": "warehouse",
    "group": groups[1],
    "description": "Existencias y ubicaciones",
    "accent": "teal",
    "order": 11,
    "menu": true,
    "roles": staffRoles
  },
  {
    "id": "movement",
    "label": "Entradas / Salidas",
    "icon": "move",
    "group": groups[1],
    "description": "Entradas y salidas de mercancía",
    "accent": "teal",
    "order": 100,
    "menu": false,
    "retired": true,
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
    "group": groups[1],
    "description": "Pedidos de compra y recepciones",
    "accent": "teal",
    "order": 8,
    "menu": true,
    "roles": staffRoles
  },
  {
    "id": "matrix",
    "tabOf": "quotes",
    "label": "Matriz comercial",
    "icon": "matrix",
    "group": groups[2],
    "description": "Precios de compra y de venta",
    "accent": "teal",
    "order": 100,
    "menu": true,
    "roles": commercialRoles
  },
  {
    "id": "barcode",
    "label": "Códigos de barras",
    "icon": "barcode",
    "group": groups[1],
    "description": "Etiquetas y códigos de barras",
    "accent": "teal",
    "order": 100,
    "menu": true,
    "roles": warehouseRoles,
    "header": [
      "Códigos de barras",
      "Genera códigos de barras para imprimir."
    ]
  },
  {
    "id": "quotes",
    "label": "Ventas",
    "icon": "sales",
    "group": groups[2],
    "description": "Solicitudes, presupuestos, pedidos, facturas y tarifas",
    "accent": "violet",
    "order": 3,
    "menu": true,
    "roles": commercialRoles
  },
  {
    "id": "contacts",
    "label": "Contactos",
    "icon": "users",
    "group": groups[3],
    "description": "Clientes, proveedores y prospectos",
    "accent": "violet",
    "order": 16,
    "menu": true,
    "roles": commercialRoles
  },
  {
    "id": "dossier-flow",
    "label": "Seguimiento de procesos",
    "icon": "folder",
    "group": groups[0],
    "description": "Ventas, compras y devoluciones de clientes y proveedores",
    "accent": "blue",
    "order": 100,
    "menu": true,
    "roles": staffRoles
  },
  {
    "id": "sales-orders",
    "tabOf": "quotes",
    "label": "Pedidos de venta",
    "icon": "bag",
    "group": groups[2],
    "description": "Gestión y seguimiento de pedidos",
    "accent": "violet",
    "order": 4,
    "menu": false,
    "roles": staffRoles
  },
  {
    "id": "payments",
    "tabOf": "quotes",
    "label": "Facturas y cobros",
    "icon": "banknote",
    "group": groups[2],
    "description": "Registro de facturas y cobros",
    "accent": "violet",
    "order": 6,
    "menu": false,
    "configLabel": "Pagos de clientes",
    "roles": commercialRoles
  },
  {
    "id": "returns",
    "label": "Devolución",
    "icon": "returnArrow",
    "group": groups[4],
    "description": "Devoluciones, abonos y reembolsos",
    "accent": "teal",
    "order": 7,
    "menu": true,
    "roles": staffRoles
  },
  {
    "id": "crm",
    "label": "CRM",
    "icon": "handshake",
    "group": groups[2],
    "description": "Prospectos y oportunidades",
    "accent": "violet",
    "order": 2,
    "menu": true,
    "roles": commercialRoles
  },
  {
    "id": "price-lists",
    "tabOf": "quotes",
    "label": "Tarifas",
    "icon": "tag",
    "group": groups[2],
    "description": "Tarifas y precios especiales",
    "accent": "violet",
    "order": 100,
    "menu": true,
    "roles": commercialRoles
  },
  {
    "id": "reports",
    "settingsTab": "reports",
    "label": "Importar datos",
    "icon": "spreadsheet",
    "group": groups[3],
    "description": "Importar datos desde Excel",
    "accent": "blue",
    "order": 100,
    "menu": false,
    "roles": commercialRoles
  },
  {
    "id": "hr",
    "label": "Recursos humanos",
    "icon": "badge",
    "group": groups[3],
    "description": "Equipos, ausencias y nóminas",
    "accent": "orange",
    "order": 13,
    "menu": true,
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
    "group": groups[3],
    "description": "Las acciones importantes, quién y cuándo",
    "accent": "orange",
    "order": 100,
    "menu": true,
    "roles": adminRoles,
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
    "group": groups[3],
    "description": "Cuentas y perfiles",
    "accent": "orange",
    "order": 100,
    "menu": false,
    "configLabel": "Usuarios y accesos",
    "roles": adminRoles
  },
  {
    "id": "access-settings",
    "settingsTab": "access-settings",
    "label": "Parámetros de acceso",
    "icon": "lock",
    "group": groups[3],
    "description": "Permisos por perfil",
    "accent": "orange",
    "order": 100,
    "menu": false,
    "locked": true,
    "roles": adminRoles
  },
  {
    "id": "settings",
    "label": "Configuración",
    "icon": "gears",
    "group": groups[3],
    "description": "Configuración del ERP",
    "accent": "orange",
    "order": 17,
    "menu": true,
    "topbar": true,
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
    "group": groups[3],
    "description": "Copias de seguridad de tus datos",
    "accent": "orange",
    "order": 100,
    "menu": false,
    "roles": adminRoles,
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
    "roles": commercialRoles,
    "header": [
      "Presupuestos",
      "Presupuestos para tus clientes, en PDF."
    ]
  }
];
export const aliases={menu:"mainmenu",inicio:"mainmenu",movements:"movement",operations:"dashboard","order-preparation":"tms",clients:"contacts",suppliers:"contacts",stock:"warehouses"};
export const roleAliases={administrador:"admin",comercial:"commercial",almacenero:"magasinier",rrhh:"rh"};
export const roles=Object.fromEntries([["admin","Administrador"],["commercial","Comercial"],["magasinier","Almacenero"],["rh","Responsable RH"]].map(([id,label])=>[id,{label,perms:id==="admin"?"*":definitions.filter(m=>m.roles.includes(id)).map(m=>m.id).concat(id==="commercial"?["customer-requests"]:[])}]));
/* Un módulo que es pestaña de otro (tabOf: los pedidos en Ventas) no tiene tarjeta ni
   línea en las listas de módulos; el módulo que lo contiene se abre para quien tiene al menos una de sus pestañas. */
export const tabsOf=id=>definitions.filter(m=>m.tabOf===id).map(m=>m.id);
export const canOpen=id=>!!window.gamaAccessAllowed?.(id)||tabsOf(id).some(t=>window.gamaAccessAllowed?.(t));
/** Route adapters preserve public module IDs and existing cross-module links. */
const openers={
 workhub:()=>window.CocoWorkhub?.open(),
 contracts:()=>window.CocoBusiness?.contracts(),
 expenses:()=>window.CocoBusiness?.expenses(),
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

export const registry=definitions.map(m=>Object.freeze({configLabel:m.label,...m,open:from=>openModule(m.id,from)}));
