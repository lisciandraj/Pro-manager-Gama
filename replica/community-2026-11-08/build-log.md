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

## Suite complète et correction du contrat historique

La suite Node complète a exécuté **790 tests** : 787 réussites, une attente de
compatibilité obsolète et deux tests de concurrence ignorés sans serveur
PostgreSQL local. L’unique écart était la comparaison de `tax_save` avec son
ancienne erreur SQL brute et l’absence historique des nouveaux champs de taxe.
Le test conserve ses assertions sur l’ancien comportement, puis attend
explicitement `TAX_NAME_INVALID`, `valid_to` et `version`. Le fichier complet
`standardization-db.test.cjs` a ensuite réussi **3/3**, sans changement serveur.

Les deux scénarios de concurrence ont été exécutés sur PostgreSQL par GitHub :
[job ventes](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42496954621)
et [job comptabilité](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42496954535/job/128781239671)
réussis. Le contrôle général GitHub est relancé avec l’attente corrigée ; son
résultat doit rester une condition de fusion. Aucune fusion ni publication
n’est effectuée par cette livraison.

La suite complète utilise l’arbre métier `e161896`. Les sources Ventes,
Comptabilité et migrations de l’intégration sont identiques hors lignes blanches ;
les modifications de thème de `8569f2e` ont leurs contrôles communs et les 27 tests
navigateur distincts de l’intégration. Voir [verification.json](verification.json)
pour les limites et empreintes des migrations.
