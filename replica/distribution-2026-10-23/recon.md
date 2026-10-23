# Coco : distribution, comparaison de cinq ERP

Relevé du 23 octobre 2026. Base examinée : 5e91620d819b24ecdb55413a459c747bd9b4e7ab, identique au coco-build.json servi en production (run 39950208778). Refonte Apple Design et correctif DOMPurify inclus. Les PR ouvertes 232, 233 et 235 ne sont pas incorporées implicitement. SRI, nouveaux paiements et envois automatiques exclus.

## Portée des preuves

**D** : documentation officielle ; **C** : code/migration/test Coco inspecté ; **T** : comportement Coco exécuté (résultats dans build-log.md) ; **A** : adaptation proposée. Aucun compte concurrent n'a été utilisé. Leurs parcours sont documentaires, pas des comportements personnellement testés. Aucun code, actif graphique ou contenu privé concurrent repris. Pas de chronométrage humain.

## Sources, versions et parcours

| ID | Produit / version examinée | Source officielle et parcours utile | Modules et limites |
| --- | --- | --- | --- |
| BC1 | Business Central ; version 29.0 / vague 2 2026 confirmée par [notes de version](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/whatsnew/whatsnew-update-29-0) | [Promesse](https://learn.microsoft.com/en-us/dynamics365/business-central/sales-how-to-calculate-order-promising-dates) : commande → lignes → ATP/CTP → dates acceptées | [Essentials](https://www.microsoft.com/licensing/guidance/Dynamics-365-Business-Central) couvre ventes, achats, stocks, Order Promising, Workflow. Premium non requis pour cette tranche de distribution. Paramétrer préparation/transport. D |
| BC2 | Business Central, même périmètre | [Approbations](https://learn.microsoft.com/en-us/dynamics365/business-central/across-how-use-approval-workflows) : demande → attente → décision → libération ; changement puis nouvelle revue | Approbateurs et limites configurés. D |
| NS1 | NetSuite, [2026.2](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/article_72152418635.html) ; aide évolutive | [Dashboard commandes](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_161727869331.html) : indicateurs → alerte d'allocation → commande | [Supply Allocation](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_161221008116.html) à activer ; disponibilité commerciale selon contrat. Aucun forfait supposé inclus. D |
| NS2 | NetSuite, même réserve de version | [ATP](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2300269.html) : devis/commande → emplacement et quantité → disponibilité ; [Inventory Page](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_1121043715.html) : flux entrants/sortants, retards | ATP nécessite Demand Planning et Check Item Availability. Prix de licence non vérifié. D |
| SAP1 | SAP Business One Web Client 10.0, [fiche article SP 2608](https://help.sap.com/docs/SAP_BUSINESS_ONE_WEB_CLIENT/2554bf7e9aa347729b0547a737e123ac/79c99c58c2c54f3fa9f09f7b8d7fcf5c.html?version=10.0_SP_2608) | [Leçon avec démonstration publique](https://learning.sap.com/courses/discovering-sap-business-one-web-client-logistics/automating-quantities-check-in-a-sales-order-and-the-available-to-promise-report_dadc05d2-fffa-4727-a407-a22d6bd4100b) : ligne → alerte → quantité/emplacement/article alternatif | Ventes/stock ; contrôle automatique à activer. Physique, engagé et commandé distincts. Démonstration décrite dans la leçon, non exécutée. D |
| SAP2 | SAP Business One Web Client 10.0 FP 2105, source ancienne explicite | [Relationship Map](https://help.sap.com/docs/SAP_BUSINESS_ONE_WEB_CLIENT/2554bf7e9aa347729b0547a737e123ac/2fcdeeb2caa34beeae50a732e7513639.html?version=10.0+FP+2105) : document → bases, cibles, références | Source limitée aux documents de vente ; pas une preuve de toute la portée du client récent ou des licences utilisateur. D |
| OD1 | Odoo **19.0**, version étudiée, sans prétendre être la dernière | [Catalogue](https://www.odoo.com/documentation/19.0/ar/applications/essentials/product_catalog.html) : devis/RFQ → catalogue → plusieurs quantités → retour ; [Ventes](https://www.odoo.com/documentation/19.0/applications/sales.html) | Sales/Purchase/Inventory selon document. [Community/Enterprise](https://www.odoo.com/page/editions) existent ; l'article catalogue ne précise pas l'édition. Aucun avantage Enterprise présumé disponible en Community. D |
| OD2 | Odoo 19.0 | [Tarifs eCommerce](https://www.odoo.com/documentation/19.0/applications/websites/ecommerce/configuration/prices.html) : client → tarif affecté → panier | Website/eCommerce et tarifs. D |
| AC1 | Acumatica **2026 R2** | [DRP configuration](https://beacon.acumatica.com/r/Implementation-Guide/Implementing-Inventory-Planning/Configuring-Inventory-Planning/Inventory-Planning-Configuration-General-Information), [prérequis](https://beacon.acumatica.com/r/Order-Management-Guide/Performing-Inventory-Planning-with-DRP/Inventory-Planning-with-DRP-Implementation-Checklist), [documents](https://beacon.acumatica.com/r/Order-Management-Guide/Performing-Inventory-Planning-with-DRP/Inventory-Planning-with-DRP-Processing-of-Documents) : demande/offre datées → exceptions → achat/transfert | Distribution Requirements Planning activé ; Multiple Warehouses pour transferts. Coût contractuel non vérifié. D |
| AC2 | Acumatica **2026 R1**, documentation officielle versionnée | [Allocation IN402000](https://github.com/Acumatica/Acumatica-AI-Resources/blob/2026R1/Documentation/UserGuide/IN_40_20_00.md), [expédition partielle](https://github.com/Acumatica/Acumatica-AI-Resources/blob/2026R1/Documentation/UserGuide/SO__con_Partial_Shipments.md) : disponibilité → préparation partielle → reliquat | Inventory activé ; règles par commande/ligne. Prévision et stock expédiable distincts. D |

## Existant vérifié

Frontend JavaScript statique, noyau Vite, modules différés, ArcUI, ArcData et GamaCloud. Supabase actif, PostgreSQL 17.6.1.165. Façades publiques gama_sales_workspace, gama_quote_action, gama_sales_dossier, gama_stock_insights et gama_stock_replenish présentes en production, SECURITY INVOKER ; implémentations privées contrôlées. Migrations ventes du 13/15 octobre et stock du 4 octobre présentes dans le registre. Certains horodatages du registre diffèrent des noms historiques locaux : aucun rejeu automatique.

Les preuves suivantes sont C, pas une certification de tous les parcours de production. Une fonction difficile à trouver n'a pas été classée absente. Les écritures de test utilisent exclusivement des fixtures isolées.

## Matrice métier

S/M/L = effort relatif. Coût **0 ajouté** signifie aucun abonnement ou service supplémentaire ; consommation actuelle d'hébergement/Supabase inchangée dans son principe, pas un coût garanti.

| ID / problème | Référence | Coco / preuve | Proposition et bénéfice | Complexité / dépendances | Coût récurrent | Critère de validation | Priorité |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 Saisie répétitive de listes | OD1 | **Partielle** : sales/editor.js::chooseProduct, Ajouter et continuer ; sales-dossier.spec.js. Pas de sélection simultanée dans ce parcours | Catalogue multi-sélection conservée entre recherches ; moins d'allers-retours | S ; lookups bornés, dialogue, éditeur | 0 ajouté | N articles en une validation ; une ligne par produit ; pas d'écriture avant sauvegarde | P1 lot 1 |
| Q2 Erreur unité/carton et palier | OD1, SAP1 | **Présente**, moins exposée avant ajout : renderLines, migration 20261013191210_sales_workspace, sales-workspace-db | Exposer conditionnement, quantité stock et prix client avant ajout | S ; product_units, prices → erp_price | 0 ajouté | 2 cartons × 5 utilisent le palier 10 ; prix manuel antérieur inchangé | P1 lot 1 |
| Q3 Manque découvert après saisie | SAP1, AC2 | **Partielle** : lookups renvoie available, affiché après ajout ; ATP daté non prouvé | Disponible non réservé et avertissement ; services distincts | S ; stock_quants et réservations existants | 0 ajouté | Manque signalé ; zéro distinct d'inconnu ; aucun stock réservé | P1 lot 1 |
| Q4 Relances peu visibles en liste | NS1, BC2 | **Partielle** : queue next_action, activités du dossier, migrations dossier ; liste devis surtout état/date | Exposer activité datée et responsable existants dans liste commune | M ; projection paginée et droits | 0 ajouté | Prochaine activité non terminée correcte ; lien et périmètre exacts | P2 rapide retenu |
| Q5 Ligne peu rentable noyée dans total | OD1 | **Partielle** : finance/commercial-planning.js::quoteMargin agrège ; seuils existants | Détail des lignes à revoir via calcul serveur autorisé | M ; coûts autorisés et coûts absents distingués | 0 ajouté | Coût absent jamais zéro ; profil restreint sans détail financier | P2 rapide retenu |
| S1 Date de livraison difficile à promettre | BC1, NS2, AC1 | **Non vérifiée** pour ATP daté complet ; arrivages/reliquats présents (stock.md, migrations stock) | Projection datée unique des engagements/arrivages puis promesse acceptée et justifiée | L ; dates achats, calendrier préparation/TMS, allocation unique | 0 ajouté prévu | Deux commandes ne promettent pas le même stock ; retard amont visible | P2 structurant reporté |
| S2 Substitution après accord | SAP1 | **Partielle** : remplacement avant envoi, versions/instantané/accord existants ; substitution après confirmation non trouvée | Étendre dossier versionné pour proposition et accord explicite | L ; réservations, prix, reliquats et retours | 0 ajouté prévu | Pas de remplacement confirmé sans accord ; ancienne version conservée | P3 structurant reporté |
| S3 Alertes dispersées | NS1, AC1 | **Présente/partielle** : Operations, Stock Por tratar, queue Ventes, dashboard-priorities-db | Relier les vues dans une liste d'exceptions par rôle, sans autre registre | M ; agrégats et permissions existants | 0 ajouté prévu | Action utile par rôle ; chaque indicateur ouvre le bon dossier | P2 structurant reporté |
| P1 Achats en double | AC1 | **Présente** : stock.md, stock-workspace-db, automatic-minmax-purchases-db déduisent réservations, entrants et brouillons | Réutiliser le réapprovisionnement actuel | Aucun changement lot 1 | 0 ajouté | Propositions nettes et reçus idempotents conservés | Préserver |
| P2 Partiels et surfacturation | BC1, AC2 | **Présente** : sales-dossier-db, sales-workspace-db, sales-concurrency ; livré/facturé/restant distincts | Conserver allocations et dossier | Aucun changement lot 1 | 0 ajouté | 12+8 livrés et factures correspondantes ; double soumission refusée | Préserver |
| P3 Documents et historique | SAP2 | **Présente** : sales/dossier.js, processes/order-followup.js, sales_dossiers, sales_invoice_orders | Conserver compteurs/liens/historique | Aucun changement lot 1 | 0 ajouté | Dossier → livraison/facture → retour correct | Préserver |
| P4 Réachat et tarif B2B | OD2 | **Présente** : storefront/b2b.js, b2b-portal, b2b-storefront-db, produits habituels/favoris | Réutiliser portail, sans panier concurrent | Aucun changement lot 1 | 0 ajouté | Prix et produits du client autorisé | Préserver |

### Sélection

Cinq rapides Q1–Q5 et trois structurants S1–S3 maximum. Ordre : Q1, Q2, Q3, Q4, Q5, S3, S1, S2. Q1–Q3 forment le premier lot : usage fréquent, même écran/contrats, faible maintenance. Q4/Q5 demandent une projection serveur ; S1/S2 une validation plus large des engagements. Aucun gain chiffré en minutes n'est prétendu sans mesure réelle.

## Écrans, composants et états

| ID | Accès / composants | États |
| --- | --- | --- |
| S01 | Ventes → Devis, filtres et pagination | rempli, vide, refus |
| S02 | Nouveau / brouillon, client/date/lignes/conditions/total | brouillon, manuel, prix en vol, erreur |
| S03 | S02 → Catalogue, recherche/cartes/conditionnement/quantité/sélection | chargement, vide, panne/reprise, déjà ajouté, manque, service, sélection hors recherche, mobile |
| S04 | Dossier, états/documents/historique/activités | proposé, rouvert, accepté, partiel, droits |
| S05 | Stock → existences/réapprovisionnement | physique/réservé/disponible/entrant, proposition périmée |
| S06 | Dashboard / À traiter / À facturer | rôle, alerte, lien, partiel |

F01 : S01 → S02 → S03 → N articles → un ajout → S02 → sauvegarde → S04. Ancien parcours : N validations d'ajout ; nouveau : une, hors saisie des quantités. Comptage de gestes à valider par test, sans chronométrage humain.

F02 : S03 → unité/quantité → prix commun → manque éventuel → S02. Limites : recherche rapide, réponse tardive, prix indisponible, article désactivé, unité modifiée, fermeture/session.

F03 : S04 proposé → réouverture → révision → changement → nouvel accord ; devis accepté immuable.

F04 : commande → réservation concurrente → préparation → livraisons/factures partielles → paiement. Régression isolée.

F05 : S05 → besoins nets → brouillon fournisseur ; F06 : S06 → document autorisé. Reconnaissance hors changements du lot.

Données confirmées : customers → invoices (devis) → invoice_lines → products/product_units ; erp_price ; stock_quants moins réservations ; dossier lié à sales_orders, livraisons, external_invoices et paiements. Confiance élevée, migrations et code inspectés. Sélection du catalogue éphémère, aucune table ni identifiant métier supplémentaire.

Taille S, une fenêtre et un point d'entrée. Risques : asynchronisme, conversion d'unités, conservation des conditions négociées. [Architecture](architecture.md), [livraison](features.csv), [tests](test-plan.md).
