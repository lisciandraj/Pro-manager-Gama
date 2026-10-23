# Tests du lot

Toutes les écritures utilisent fixtures navigateur/bases isolées. Production : métadonnées et actifs en lecture seulement.

| Cas | Résultat attendu | Test |
| --- | --- | --- |
| F01-H1 | N articles à travers recherches, ajout unique, sauvegarde habituelle | sales-dossier.spec, nouveaux cas catalog |
| F01-E1 | Produit existant exclu, prix/motif négocié intacts | mêmes tests |
| F01-E2 | Retour/Échap, focus restauré, aucune sauvegarde | catalogue clavier |
| F01-E3 | Réponse tardive/session changée, aucun ajout | catalogue authentification |
| F01-N1 | Client absent, prix en panne, article désactivé : erreur sans ajout partiel | catalogue négatifs |
| F02-H1 | 2 cartons de 5 : quantité tarifaire 10, persistance facteur | catalogue + sales-workspace-db |
| F02-E1 | Facteur modifié : refus ; manque et service distincts | catalogue |
| F02-E2 | Vide, recherche/reprise, sélection conservée | catalogue |
| F02-E3 | 1440 ES, 390 FR/EN ; clavier, libellés, aucun débordement | catalogue et captures CI |
| F03 | Proposé rouvert/révision, accord obsolète refusé, accepté immuable | sales-dossier-db et tests existants |
| F04-H1 | Partiels, anti-double facturation, crédit et droits | sales-workspace-db, sales-dossier-db, autres unitaires |
| F04-E1 | Deux connexions sur stock limité, doubles confirmations | sales-concurrency PostgreSQL 17 |
| F04-N1 | Vendeur/magasinier/admin/client, périmètre et finances | sales-dossier-db, role-module-access, sales-workspace-db |

Contrôles communs : npm run update (sources, dépendances vendues, typage, docs, migrations, unitaires, reproductibilité et budgets), workflows de ventes, interfaces, release et déploiement. Résultats effectifs dans build-log.md. Les contrôles clavier/libellés/géométrie sont explicites ; aucun score d'audit axe n'est revendiqué.
