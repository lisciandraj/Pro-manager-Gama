# Livraison du 8 novembre 2026

Les vérifications ciblées sont réalisées sur les actifs compilés et des bases
jetables ; elles ne modifient pas la production.

| Écran | Changement | État |
| --- | --- | --- |
| S02 | Pro forma distincte du devis et de la facture, devise figée | Implémenté ; exports 390/1440 et test du générateur PDF réussis |
| S03 | Remise de ligne en lot et provenance des prix copiés | Implémenté ; validations et document d'origine vérifiés |
| S04 | Recherche et archivage des modèles avec reprise | Implémenté ; droits, recherche au-delà de 100, idempotence et historique vérifiés |
| S06 | Comptes, validité et cycle des taxes | Implémenté ; 8 tests serveur et 3 parcours ES/FR/EN réussis |
| S07 | Comptes comptables des clients et fournisseurs | Implémenté ; 11 tests serveur et parcours FR/ES réussis ; extension EN en validation générale |

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
