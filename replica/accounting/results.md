# Résultats vérifiés — 24 octobre 2026

Cette extension livre des échéanciers natifs ; elle ne réalise pas toute la comptabilité Odoo. Référence fonctionnelle : Odoo 19.0 Enterprise. La [matrice](features.csv) contient 106 lignes : 48 testées, 32 partielles, 20 à développer, 2 à analyser, 3 bloquées par des services non raccordés et 1 exclusion explicite (SRI). « Testé » désigne le scénario précis de la ligne, pas une comparaison exhaustive sur instance Enterprise.

## Code et intégration

Départ : `7dfa6b422dd7eeea5161be935c0dabfb273aeebc`. Les modifications récentes de main jusqu'à `74a261038bdd59d0233ff3a6a0c3bb47a735f5eb` sont intégrées. La [PR 243](https://github.com/lisciandraj/Pro-manager-Gama/pull/243) conserve les preuves finales de fusion, de publication et la révision effectivement servie ; un résultat de CI de branche ne prouve pas à lui seul la publication.

Les parcours ajoutés sont accessibles dans Comptabilité → Comptabilité → Différés, récurrences et emprunts : aperçu serveur, brouillon, approbation humaine, comptabilisation des échéances, exécution automatique facultative, annulation motivée, exports et liens plan/source/écriture/historique. Les composants, la navigation et les trois langues de Coco sont conservés. L'ancien traitement du stock n'est pas transformé en méthode Odoo 19 par cette extension.

## Tests

Code applicatif testé : `9d43d1f26ca20837a0417bd7c5ce7100679dfa91`.

| Contrôle | Résultat constaté | Preuve |
| --- | --- | --- |
| Suite serveur générale | 552 tests : 550 réussis, zéro échec, 2 SKIP pour services dédiés | [Publication de branche](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40108055343), job build |
| Non-régression interface partagée | 430 réussis | [Release](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40108055173) |
| Comptabilité, audit, historique et nouveaux échéanciers | 61 parcours navigateur réussis | [Échéanciers natifs](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40108055234) |
| Droits, calculs et historique des échéanciers | 18 tests serveur réussis | `tests/accounting-plans-db.test.cjs` |
| Concurrence réelle | Deux connexions PostgreSQL 17, réussite ; aucun SKIP dans ce job | Même workflow, job concurrency |
| Chaîne vente jusqu'aux rapports | Réussie en base isolée : facture 100 USD, paiement 100, banque 100, solde dû zéro ; rapprochement sans double trésorerie | `tests/accounting-sale-to-bank-db.test.cjs` |
| Calculs et intégrations ciblés | 70 tests réussis, zéro échec, zéro SKIP | Plans, livres, banque, valorisation existante, avances et contexte historique |
| Contrôles du dépôt | Sources, types, documentation, migrations, sorties générées, budget de démarrage et audit des dépendances réussis | Workflows du commit testé |

Les workflows Achats, Ventes, concurrence Ventes/Stock, Contacts, identité Produits, architecture, responsive, durcissement de l'audit et Agent Coco ont également réussi. Les suites se recouvrent : leurs nombres ne sont pas additionnés pour annoncer un total artificiel.

Les neuf combinaisons FR/ES/EN × 390/768/1440 utilisent les RPC réelles dans PGlite isolé. Les scans axe du formulaire et du détail ne rapportent aucune violation ciblée WCAG 2 A/AA. Les [captures conservées](evidence/README.md) ont été examinées. Elles ne certifient pas tous les écrans du périmètre complet.

Défaut découvert puis corrigé avant migration : renommer une fonction de visibilité conservait son ancienne liaison dans la politique RLS de l'historique. Le remplacement conserve désormais l'OID. Le test lit réellement l'historique sous authenticated, vérifie les liens exacts et refuse le périmètre commercial insuffisant. Aucun contrôle d'accès n'a été désactivé.

Le correctif d'arrondi a été ajouté après cette CI : 19 tests locaux échéanciers et chaîne complète réussis, zéro échec, zéro SKIP. Le cas 0,03 USD sur six mois révélait un reliquat négatif ; chaque montant est désormais plafonné au solde à répartir. Le cas de prêt à 0 % passe également. La CI du dernier commit de la PR reste la preuve de validation globale de ce correctif.

## Migration et conservation des données

Migration appliquée : **20261024155142_accounting_plans**, projet `mknsaibrewksgomuslev`. Le SQL lu dans le registre Supabase contient exactement 33 281 octets ; son SHA-256 est `0c96babf4cd2be510008b4ba6286ce8bc7f2967ab6ae777a32c8ed9c67eba508`, identique au fichier du dépôt. Le nom initial de préparation a été aligné sur la version réellement attribuée ; les octets SQL ne sont pas modifiés. [Archive de contrôle](../../supabase/sql/applied/20261024155142_accounting_plans.json).

| Mesure | Avant | Après |
| --- | ---: | ---: |
| Écritures validées | 58 | 58 |
| Lignes comptables | 138 | 138 |
| Total débit USD | 8 552,49 | 8 552,49 |
| Total crédit USD | 8 552,49 | 8 552,49 |
| Écritures déséquilibrées | 0 | 0 |
| Transactions rapprochées / ignorées / non rapprochées | 27 / 5 / 57 | 27 / 5 / 57 |
| Factures clients / paiements clients | 17 / 20 | 17 / 20 |
| Factures fournisseurs / paiements fournisseurs | 6 / 7 | 6 / 7 |
| Encaissements | 3 | 3 |
| Périodes fermées / ouvertes | 1 / 1 | 1 / 1 |
| Échéanciers natifs | Absents | 0 |

Les trois tables privées ont RLS activé et aucun accès direct accordé à anon/authenticated/service_role. La façade publique est invoker, le moteur privé definer, avec search_path vide. Les triggers de protection de source et d'historique sont actifs. Le cron horaire est installé ; il n'exécute que les plans explicitement configurés comme automatiques et approuvés. Son invocation est refusée aux rôles clients. [Résultat de la lecture de contrôle](evidence/production-after-migration.json).

L'audit initial n'a trouvé aucun doublon de source comptable, numéro de facture client ou référence fournisseur normalisée ; aucun candidat bancaire dupliqué avec référence non vide ; aucun paiement actif sans pièce attendue ; aucun rapprochement déclaré sans lien ; aucun groupe de rapprochement déséquilibré. Base + taxe correspond aux totaux examinés. Ces contrôles ciblés ne certifient ni la conformité fiscale ni toutes les données.

La sauvegarde logique ciblée est conservée séparément du dépôt public : 378 144 octets, SHA-256 `2bef42f16df30ab0918449fb4f9cd96360defafd0d467fe23c1d4caa1cc744e3`. Aucun historique n'est rejoué et aucune écriture d'équilibrage n'est ajoutée. La sauvegarde intégrale/PITR et son exercice de restauration ne sont pas attestés ; ils restent requis avant une conversion structurelle de l'historique.

Correctif appliqué : **20261024160011_accounting_plan_rounding_guard**, 765 octets, SHA-256 `9ef5824b397dfc247322c4767532da7cb3dc349a16184c236e7f3dff4398a676`, vérifié par lecture du SQL enregistré dans Supabase. Il remplace uniquement le calcul de l'échéancier, conserve la fonction et ses droits et ne transforme aucun plan existant (aucun plan n'a été créé à ce point de contrôle). [Archive du correctif](../../supabase/sql/applied/20261024160011_accounting_plan_rounding_guard.json).

## Limites de vérification en production

L'application publique ouvre correctement la connexion Coco. Aucune session utilisateur authentifiée n'est disponible dans le navigateur de contrôle ; les parcours métier de production sous une identité humaine ne sont donc pas attestés. Les vérifications publiques, le registre des migrations, les droits serveur et les tests isolés restent distincts. Aucun document, paiement, rapprochement ou plan fictif n'est créé en production.

Les écarts fonctionnels et prestataires restent visibles dans [parity.md](parity.md) et [dependencies.md](dependencies.md). La publication de cette extension ne clôt pas la mission de parité intégrale.
