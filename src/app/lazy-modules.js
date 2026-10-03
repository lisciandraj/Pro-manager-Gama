/** Public entry points for workspaces fetched on first use. */
export const lazyModules={
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
