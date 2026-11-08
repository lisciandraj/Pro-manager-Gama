# Livraison du 8 novembre 2026

Les vérifications ciblées sont réalisées sur les actifs compilés et des bases
jetables ; elles ne modifient pas la production.

| Écran | Changement | État |
| --- | --- | --- |
| S02 | Pro forma distincte du devis et de la facture, devise figée | Implémenté ; exports 390/1440 et test du générateur PDF réussis |
| S03 | Remise de ligne en lot et provenance des prix copiés | Implémenté ; validations et document d'origine vérifiés |
| S04 | Recherche et archivage des modèles avec reprise | Implémenté ; droits, recherche au-delà de 100, idempotence et historique vérifiés |
| S06 | Comptes, validité et cycle des taxes | Implémenté ; 8 tests serveur et 3 parcours ES/FR/EN réussis |
| S07 | Comptes comptables des clients et fournisseurs | Implémenté ; 11 tests serveur et parcours FR/ES/EN réussis |

Le lot Ventes compte huit nouveaux parcours navigateur et deux tests Node.
Les 89 régressions serveur prioritaires passent : ventes/dossier, comptabilité,
configuration, paiements, chaîne vente → banque et instantanés SRI. La validation
commune complète et les régressions navigateur complémentaires sont consignées
ci-dessous après leur fin.

La revue indépendante a conduit à corriger les problèmes décrits dans
[bugs.md](bugs.md). Trois migrations sont ajoutées ; aucune n'est présentée
comme appliquée à la base hébergée.

Écarts structurels restant ouverts dans [features.csv](features.csv), sans
revendication de parité totale ni score artificiel.

Régression navigateur complémentaire : 58 tests réussis, dont les trois parcours de comptes tiers et les vues comptables existantes. Avec les huit parcours Ventes et trois parcours Taxes, 69 cas distincts ont été vérifiés avant intégration du thème récent. La branche intègre `8569f2e` ; syntaxe, types, documentation, migrations, actifs reproductibles et budgets y sont vérifiés. Les parcours concernés par cette intégration sont revérifiés séparément.

Après intégration de `8569f2e` : **27/27 tests navigateur réussis**, couvrant les 14 nouveaux parcours, les onglets et vues modifiés par main. Les captures S02, S06 et S07 sont actualisées dans `clone-screens/`. Aucune violation Axe ni erreur de console n’a été constatée dans les parcours comptables contrôlés.
