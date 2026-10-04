/** Public entry points for workspaces fetched on first use. */
export const lazyModules={
 "dashboard":{"global":"ArchitectDashboard","file":"architect-dashboard.js","dependencies":["architect-kpi-catalog.js","architect-home-kpis.js"],"methods":["refresh"],"apis":{"ArchitectHomeKpis":["refresh"]}},
 "crm":{"global":"GamaCRM","file":"gama-crm-core.js","extensions":["gama-crm-scoring.js","gama-crm-leads.js","gama-crm-opportunities.js","gama-crm-activities.js","gama-crm-contacts.js","gama-crm-reports.js","gama-crm-targets.js"],"methods":["open","ir"],"aliases":{"GamaOpenCRM":"open"},"apis":{"GamaCRMLeads":["open"],"GamaCRMOpportunities":["open","openRecord"],"GamaCRMActivities":["open"],"GamaCRMContacts":["open"],"GamaCRMReports":["open"]}},
 "hr-operations":{"global":"GamaHRP1","file":"gama-hr-p1.js","methods":["mountFinance","load"]},
 "hr":{"global":"GamaHR","file":"gama-hr.js","dependencies":["gama-hr-p1.js"],"methods":["open","load"],"aliases":{"GamaOpenHR":"open"}},
 "dossier-flow":{"global":"GamaDossierFlow","file":"gama-dossier-flow.js","methods":["open","attachHistory"]},
 "gamaPurchasesV14":{"global":"GamaPurchases","file":"gama-purchases-v14.js","methods":["open","openOrder","openDossier","fromProject","prepareAction","prepareSupplierOffer"],"aliases":{"gamaShowPurchases":"open","gamaOpenPurchaseV14":"openOrder","gamaOpenPurchaseDossier":"openDossier","gamaCreateProjectPurchase":"fromProject","gamaPrepareActionPurchase":"prepareAction","gamaPrepareSupplierOffer":"prepareSupplierOffer"}},
 "warehouses":{"global":"GamaInventoryV2","file":"gama-stock-workspace.js","methods":["abrir","openCount","openAdjustments","cargar"]},
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
  "accounting": {
    "global": "GamaAccounting",
    "file": "gama-accounting.js",
    "methods": [
      "openSri",
      "mountSriConfig",
      "open",
      "rpc"
    ]
  },
  "fleet": {
    "global": "GamaFleet",
    "file": "gama-fleet.js",
    "methods": [
      "open",
      "openVehicle",
      "openDriver",
      "rpc"
    ]
  },
  "returns": {
    "global": "GamaReturns",
    "file": "gama-returns.js",
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
  "tms": {
    "global": "gamaTMS",
    "file": "gama-tms-module.js",
    "dependencies": ["gama-tms-delivery-operations.js"],
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
