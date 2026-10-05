/** Public entry points for workspaces fetched on first use. */
export const lazyModules={
 "price-lists":{"global":"gamaPriceLists","file":"gama-price-lists.js","methods":["open"],"aliases":{"GamaOpenPriceLists":"open"}},
 "matrix":{"global":"GamaMatrix","file":"gama-proveedores-matriz.js","methods":["open","render"],"apis":{"GamaSuppliers":["migrate"]}},
 "workflow-tools":{"global":"CocoFlows","file":"coco-flow-tools.js","methods":["draftBills","projectTime","importSupplierXml","messages"]},
 "automation":{"global":"CocoAutomation","file":"coco-automation.js","methods":["mount"]},
 "dashboard":{"global":"ArchitectDashboard","file":"architect-dashboard.js","dependencies":["architect-kpi-catalog.js","architect-home-kpis.js"],"methods":["refresh"],"apis":{"ArchitectHomeKpis":["refresh"]}},
 "crm":{"styles":["coco-style-crm-core.css","coco-style-crm-activities.css","coco-style-crm-contacts.css","coco-style-crm-leads.css","coco-style-crm-opportunities.css","coco-style-crm-reports.css","coco-style-crm-targets.css"],"global":"GamaCRM","file":"gama-crm-core.js","extensions":["gama-crm-scoring.js","gama-crm-leads.js","gama-crm-opportunities.js","gama-crm-activities.js","gama-crm-contacts.js","gama-crm-reports.js","gama-crm-targets.js"],"methods":["open","ir"],"aliases":{"GamaOpenCRM":"open"},"apis":{"GamaCRMLeads":["open"],"GamaCRMOpportunities":["open","openRecord"],"GamaCRMActivities":["open"],"GamaCRMContacts":["open"],"GamaCRMReports":["open"]}},
 "hr-operations":{"styles":["coco-style-hr-operations.css"],"global":"GamaHRP1","file":"gama-hr-p1.js","methods":["mountFinance","load"]},
 "hr":{"styles":["coco-style-hr.css","coco-style-hr-operations.css"],"global":"GamaHR","file":"gama-hr.js","dependencies":["gama-hr-p1.js"],"methods":["open","load"],"aliases":{"GamaOpenHR":"open"}},
 "dossier-flow":{"styles":["coco-style-dossier-flow.css"],"global":"GamaDossierFlow","file":"gama-dossier-flow.js","methods":["open","attachHistory"]},
 "gamaPurchasesV14":{"styles":["coco-style-purchases.css"],"global":"GamaPurchases","file":"gama-purchases-v14.js","methods":["open","openOrder","openDossier","fromProject","prepareAction","prepareSupplierOffer"],"aliases":{"gamaShowPurchases":"open","gamaOpenPurchaseV14":"openOrder","gamaOpenPurchaseDossier":"openDossier","gamaCreateProjectPurchase":"fromProject","gamaPrepareActionPurchase":"prepareAction","gamaPrepareSupplierOffer":"prepareSupplierOffer"}},
 "warehouses":{"styles":["coco-style-inventory.css"],"global":"GamaInventoryV2","file":"gama-stock-workspace.js","methods":["abrir","openCount","openAdjustments","cargar"]},
 "surveys":{"global":"GamaSurveys","file":"gama-surveys.js","dependencies":["gama-survey-form.js"],"methods":["open"]},
  "website": {
    "global": "GamaWebsite",
    "file": "gama-website.js",
    "methods": [
      "open"
    ]
  },
  "audit-controls": {
    "global": "ArchitectStockAudit",
    "file": "architect-audit-controls.js",
    "methods": [
      "products",
      "valuation",
      "performance"
    ]
  },
  "sav": {
    "global": "GamaService",
    "file": "gama-service-documents.js",
    "methods": [
      "open",
      "openTicket"
    ]
  },
  "documents": {
    "global": "GamaDocuments",
    "file": "gama-service-documents.js",
    "methods": [
      "open"
    ]
  },
  "accounting": {"styles":["coco-style-accounting.css"],
    "global": "GamaAccounting",
    "file": "gama-accounting.js",
    "dependencies": ["gama-sri-documents.js"],
    "methods": [
      "openSri",
      "mountSriConfig",
      "open",
      "rpc"
    ]
  },
  "fleet": {"styles":["coco-style-fleet.css"],
    "global": "GamaFleet",
    "file": "gama-fleet.js",
    "methods": [
      "open",
      "openVehicle",
      "openDriver",
      "rpc"
    ]
  },
  "returns": {"styles":["coco-style-returns.css"],
    "global": "GamaReturns",
    "file": "gama-returns.js",
    "dependencies": ["gama-sri-documents.js"],
    "methods": [
      "open",
      "openReturn",
      "createFrom",
      "createFromService",
      "rpc",
      "mount"
    ]
  },
  "knowledge": {
    "global": "GamaKnowledge",
    "file": "gama-knowledge.js",
    "methods": [
      "open",
      "openArticle"
    ]
  },
  "assistant-ia": {
    "global": "GamaAssistant",
    "file": "gama-assistant-ia.js",
    "methods": [
      "open"
    ]
  },
  "tms": {"styles":["coco-style-tms-module.css"],
    "global": "gamaTMS",
    "file": "gama-tms-module.js",
    "dependencies": ["gama-tms-delivery-operations.js","gama-sri-documents.js"],
    "methods": [
      "open",
      "openDelivery",
      "openProof",
      "viewProofArchive",
      "downloadProofReport",
      "downloadProofCertificate"
    ]
  },
  "projects": {"global":"GamaProjects","file":"gama-projects.js","dependencies":["gama-projects-core.js"],"methods":["open","fromSource"]}
};
