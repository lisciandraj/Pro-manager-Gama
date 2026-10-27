# Coût standard et clôture de stock native

Référence fonctionnelle inchangée : Odoo 19.0 Enterprise, documentation officielle consultée le 27 octobre 2026. [Valorisation comptable](https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/inventory_valuation.html) ; [aide-mémoire](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/inventory_valuation/cheat_sheet.html). La méthode périodique comptabilise la variation à la clôture ; la méthode de coût reste un choix distinct. Le parcours de référence passe par une revue à date, la génération d'un brouillon et sa validation.

## Parcours livré par ce lot

Comptabilité → **Valeur du stock et clôture**, trois vues natives Coco, FR/ES/EN :

- **Coûts et comptes** : recherche et pagination des produits ; reprise constatée FIFO, AVCO ou standard ; coût unitaire justifié, quantité existante conservée ; configuration explicite des comptes et du journal. Aucun taux, coût initial ou compte n'est choisi automatiquement.
- **Revue de clôture** : valeur physique, valeur au grand livre, variation proposée par compte et anomalies par produit, à une date civile. La génération crée de véritables pièces comptables en brouillon, sans affecter les rapports validés.
- **Clôtures préparées** : photographies de la revue, lignes comptables, validation humaine, abandon des brouillons périmés et correction motivée par contrepassation. Les liens ouvrent les pièces du livre et reviennent à la revue ; l'historique commun conserve auteurs et opérations.

Le coût standard est approuvé explicitement. Recevoir un produit à un autre prix ne modifie pas ce coût. Réviser le coût revalorise seulement la quantité restante, conserve les mouvements et ajoute une ligne de valorisation motivée. Les frais d'approche sur un coût standard sont refusés avec un message explicite en attendant leur traitement dédié.

Un correctif FIFO départage les couches de même horodatage par l'ordre enregistré des valorisations. PostgreSQL conserve le même `now()` pendant une transaction : l'ancien départage par UUID pouvait inverser deux réceptions successives. Aucune valorisation historique n'est recalculée.

## Garanties et intégration

La façade invocateur `gama_accounting_stock19` vérifie session, MFA, droit Comptabilité et périmètre complet. Les mutations privées utilisent les droits existants ; approbation et configuration sont refusées à une provenance Agent Coco non approuvée. Les nouvelles tables privées ont RLS et aucun accès direct pour les rôles API. Les calculs utilisent `numeric` PostgreSQL ; les soldes proviennent exclusivement du grand livre existant.

La clé de commande est liée à l'acteur, à l'action et au contenu. Un verrou commun avec le moteur comptable sérialise la capture du stock, la génération et la validation. La photographie complète est révisée avant pagination ; un changement de stock ou de livre invalide le brouillon. Les comptes partagés doivent avoir la même règle. Les dates verrouillées sont refusées sans déplacement silencieux.

Les produits configurés ne peuvent plus activer l'ancienne comptabilisation par mouvement ni appeler son écran de comptabilisation manuelle. Les contrôles de clôture attendent leur rapprochement global, sans exiger une écriture pour chaque mouvement physique.

La migration ne crée aucune politique, reprise ni écriture. Les anciennes dates sont conservées ; `effective_on` distingue les dates métier des nouveaux enregistrements de leur horodatage technique. Les anciennes lignes restent lisibles avec leur date historique dans le fuseau de la société.

## Preuves et limites

Scénarios indépendants : FIFO 10×10 + 10×20 − 12 → valeur restante 160 ; AVCO → 120 ; standard 12 → 96. Révision du standard de 12 à 15 pour cinq unités restantes → 75, avec variation de 15. Tests de brouillon, double requête, permissions, verrouillage, source modifiée, correction, 51 produits et coexistence interdite avec l'ancien moteur : `tests/accounting-stock19-db.test.cjs`. Régressions : `tests/audit-valuation-db.test.cjs`, `tests/accounting-audit-db.test.cjs`. Concurrence réelle : `tests/accounting-plans-concurrency.test.cjs`. Parcours navigateur : `tests/accounting-stock19.spec.js`, trois langues × trois largeurs, base isolée et axe.

**Ce lot n'établit pas la parité complète Odoo.** Restent notamment la valorisation perpétuelle à la facture, les quatre revues de régularisation, les comptes par catégorie/emplacement, les clôtures programmées, les écarts de prix et certains retours/frais d'approche. La sélection perpétuelle n'est pas exposée et le serveur la refuse. K02 et K03 restent partiels ; K04 et K05 conservent leurs écarts explicites.

Contrôle de production avant intervention, 27 octobre à 17:15 UTC : zéro sous-livre, zéro automatisation, zéro valorisation et zéro ancien lien de stock ; 58 écritures, 138 lignes, débit = crédit = 8 552,49 USD. La reprise des 1 756 produits à quantité positive exige leurs coûts constatés et leurs comptes approuvés ; ce lot ne les invente pas.

## Déploiement et retour arrière

Exécuter les tests isolés et les workflows existants, archiver la migration effectivement appliquée, comparer les empreintes des données et les soldes avant/après, puis publier le build GitHub Pages. La preuve d'une connexion utilisateur en production reste distincte des contrôles SQL/API et des essais isolés.

En cas de retour arrière, conserver les tables, photographies et pièces ; republier le build précédent pour retirer le point d'entrée. Ne pas supprimer les écritures après activation. Corriger une clôture via sa contrepassation ; une politique déjà utilisée nécessite une transition comptable explicitement préparée. La conversion des valeurs historiques reste suspendue à une sauvegarde complète et à un exercice de restauration, conformément au plan de reprise.

Preuves et migration effectivement appliquée : [résultats détaillés](results-stock19.md).
