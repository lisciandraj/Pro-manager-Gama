# Exports PDF

Le moteur local `assets/vendor/jspdf-2.5.2.umd.min.js` est téléchargé au premier export, avec vérification d’intégrité. Les appels simultanés partagent le téléchargement et un échec peut être réessayé sans recharger l’application.

## Contrat d’appel

```js
await window.GamaCompany?.load(true);
await window.GamaPdf.ready();
const document = window.GamaQuotePdf.build(quote);
window.GamaPdf.save(document, window.GamaPdf.fileName('devis', quote.number));
```

`GamaQuotePdf.build`, `GamaPurchaseOrderPdf.build`, `GamaPdfTemplate.layout`, `GamaPdf.proofReport` et `GamaPdf.proofCertificate` restent synchrones. Leur appelant doit attendre `GamaPdf.ready()`. `GamaQuotePdf.send` et `GamaPurchaseOrderPdf.send` le font avant de préparer une pièce jointe dans le composeur de courriel.

Conserver les contrôles d’accès du parcours et traiter les erreurs dans l’interface. Si le compte change pendant le chargement du moteur, `ready()` rejette avec `AUTH_CHANGED` ; un renouvellement normal du jeton n’annule pas l’export. Cette protection ne remplace pas les contrôles de session propres aux autres requêtes asynchrones du parcours.

## Où modifier

| Fonction | Source |
| --- | --- |
| Chargement, téléchargement, preuves de livraison | `src/features/documents/pdf.js` |
| Mise en page et identité visuelle commune | `src/features/documents/pdf-template.js` |
| Devis et factures internes | `src/features/sales/quote-pdf.js` |
| Commandes fournisseurs | `src/features/purchasing/purchase-order-pdf.js` |
| Étiquettes groupées | `src/features/inventory/barcode-controls.js` |
| Rapports Projets | `src/features/projects/projects.js` |

Les noms des fichiers téléchargés restent compatibles ; les nouvelles étiquettes groupées utilisent `Coco-ERP-labels.pdf`. Les API globales et noms publics historiques sont conservés pour les clients existants.

## Vérification

`tests/pdf-loader.test.cjs` couvre les appels simultanés, les erreurs réseau et les changements de session. `tests/lazy-pdf.spec.js` construit de vrais PDF avec le moteur local. `tests/company-settings.spec.js` vérifie le logo, ses proportions et les documents multipages. Les suites PDF, Projets et TMS vérifient les données et les téléchargements de leurs parcours.
