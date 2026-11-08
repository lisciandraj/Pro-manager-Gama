# Exports PDF

Le moteur local `assets/vendor/jspdf-4.2.1.umd.min.js` est téléchargé au premier export, avec vérification d’intégrité. Les appels simultanés partagent le téléchargement et un échec ou un script téléchargé sans SDK peut être réessayé sans recharger l’application.

## Contrat d’appel

```js
await window.GamaCompany?.load(true);
await window.GamaPdf.ready();
const document = window.GamaQuotePdf.build(quote);
window.GamaPdf.save(document, window.GamaPdf.fileName('devis', quote.number));
```

`GamaQuotePdf.build`, `GamaPurchaseOrderPdf.build`, `GamaPdfTemplate.layout`, `GamaPdf.proofReport` et `GamaPdf.proofCertificate` restent synchrones. Leur appelant doit attendre `GamaPdf.ready()`. `GamaQuotePdf.send` et `GamaPurchaseOrderPdf.send` le font avant de préparer une pièce jointe dans le composeur de courriel.

Les exports de devis enrichis appellent `await GamaQuotePdf.compose(quote)` après `GamaPdf.ready()`. Cette API construit le corps avec `build`, puis assemble les documents privés de `quote.documentComposition`. Sans composition, elle retourne le corps existant. `send` utilise aussi cette composition et affiche une erreur si une pièce jointe sélectionnée manque.

## Documents commerciaux privés

Le bouton **Documents PDF** du devis ouvre une bibliothèque de PDF de 10 Mo maximum, des modèles de composition, les fiches associées aux produits et l’association aux modèles de devis. L’ordre est couverture, devis, fiches produits et documents supplémentaires, document de fin. La recherche paginée permet de choisir aussi les documents au-delà des 50 premiers résultats.

Les fichiers du bucket privé `quote-pdf-documents` sont téléchargés avec la session courante, sans URL publique. Un fichier enregistré ne se remplace ni ne se supprime depuis le navigateur ; il s’archive. Les devis finalisés conservent la liste, les versions et les associations de champs de leur révision. Une réouverture libère la sélection de travail et conserve l’historique des révisions précédentes. Les autorisations Ventes et les droits création, modification et suppression sont vérifiés côté serveur ; les modèles PDF appartiennent à leur créateur ou à l’administrateur.

L’inspection et l’assemblage utilisent `pdf-lib@1.17.1`, empaqueté localement avec son intégrité, chargé uniquement à la première opération qui en a besoin. Chaque champ AcroForm reçoit une source explicitement choisie parmi les données du devis, du client ou du produit. Les champs sans association sont vidés. Les quantités de fiches produit utilisent l’unité de base. Les champs sont ensuite aplatis ; actions, scripts et annotations interactives sont supprimés. Un PDF chiffré, XFA, invalide, ou un caractère non représentable dans la police du formulaire produit une erreur récupérable. La composition est limitée à 20 documents, 40 Mo et 300 pages ; les signatures électroniques du fichier importé ne sont pas conservées.

Les lignes commerciales et les composantes fiscales figées sont conservées dans le corps du devis, y compris les montants fixes et les taxes multiples. Aucune composition ne modifie le devis, la facture, les taxes ni le stock.

Conserver les contrôles d’accès du parcours et traiter les erreurs dans l’interface. Si le compte change pendant le chargement du moteur, `ready()` rejette avec `AUTH_CHANGED` ; un renouvellement normal du jeton n’annule pas l’export. Cette protection ne remplace pas les contrôles de session propres aux autres requêtes asynchrones du parcours.

## Où modifier

| Fonction | Source |
| --- | --- |
| Chargement, téléchargement, preuves de livraison | `src/features/documents/pdf.js` |
| Mise en page et identité visuelle commune | `src/features/documents/pdf-template.js` |
| Devis et factures internes | `src/features/sales/quote-pdf.js` |
| Bibliothèque privée, modèles PDF et associations | `src/features/sales/quote-documents.js` |
| Inspection, champs PDF et assemblage | `src/domain/quote-document-compose.js` |
| Commandes fournisseurs | `src/features/purchasing/purchase-order-pdf.js` |
| Étiquettes groupées | `src/features/inventory/barcode-controls.js` |
| Rapports Projets | `src/features/projects/projects.js` |

Les noms des fichiers téléchargés restent compatibles ; les nouvelles étiquettes groupées utilisent `GAMA-labels.pdf`. Les API globales et noms publics historiques sont conservés pour les clients existants.

## Vérification

`tests/pdf-loader.test.cjs` couvre les appels simultanés, les erreurs réseau et les changements de session. `tests/lazy-pdf.spec.js` construit de vrais PDF avec le moteur local. `tests/company-settings.spec.js` vérifie le logo, ses proportions et les documents multipages. Les suites PDF, Projets et TMS vérifient les données et les téléchargements de leurs parcours.

`tests/quote-document-compose.test.cjs` relit les pages et flux PDF réellement créés, vérifie leur ordre, les champs aplatis, les anciennes valeurs effacées et les erreurs. `tests/quote-documents-db.test.cjs` couvre l’accès privé, les doublons, versions concurrentes, modèles, recherche et révisions figées sur une base restaurée isolée. `tests/quote-documents.spec.js` vérifie import, association de champ et téléchargement réel en espagnol, français et anglais à 390, 768 et 1440 pixels.

## Marque des communications externes

Les mentions de marque du modèle PDF commun et des courriels commerciaux utilisent « GAMA Entreprise Resource Planning » (orthographe demandée). Cela couvre les devis, factures internes, commandes fournisseurs, preuves de livraison, étiquettes et pieds de page des rapports. Les anciennes mentions de marque dans les noms d’émetteur et les brouillons de courriel sont normalisées au rendu, sans modifier les enregistrements ni les instantanés acceptés. Les autres raisons sociales, le RUC, les coordonnées et les données des documents sont conservés. Les PDF déjà téléchargés ne sont pas réécrits. L’identité de l’application reste Coco ERP.
