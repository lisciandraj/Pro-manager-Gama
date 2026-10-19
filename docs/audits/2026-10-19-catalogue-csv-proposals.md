# Suite de l’audit Coco ERP — catalogue public et CSV

État : **propositions préparées, aucune modification de production**. Base de comparaison : `main`, commit `6746cec99c5ed03449a8276560eee3081e2db09c`, vérifié le 19 octobre 2026. Les déploiements ERP GitHub Pages et GAMA Cloudflare Pages portent encore ce commit. La base cible observée utilise PostgreSQL 17.6 ; les tests ci-dessous utilisent PostgreSQL 17.5 dans PGlite 0.3.14, Node 24.19.0. Ils ne remplacent pas une recette PostgreSQL 17.6 avec deux comptes clients.

Le rapport initial du 18 octobre reste la référence pour les 13 constats et les accès manquants. Ce lot prépare SEC-02, PERF-01 et une partie de PERF-02. Il ne clôt aucun constat en production.

## Ce qui est préparé

| Proposition | Effet attendu | Limites |
| --- | --- | --- |
| `src/features/audit/audit.js` | Neutraliser les préfixes de formule dans les cellules textuelles CSV, tout en conservant les montants négatifs numériques et les guillemets CSV | Sérialisation testée ; ouverture Excel/LibreOffice à vérifier |
| `src/storefront/site.js` | Permettre l’utilisation des 30 premières cartes pendant le chargement des suivantes ; conserver les quantités saisies ; ignorer les anciennes réponses | Toujours quatre requêtes séquentielles pour 100 produits ; chargement complet des photos encore à optimiser |
| [Projection SQL proposée](proposals/coco-storefront-projection.sql) | Démarrage : calculer une seule fois les données publiques, au lieu de quatre fois. Liste : choisir la page avant de valider ses photos. Fiche : filtrer sur son identifiant avant projection | Non exécutée en production ; catalogue B2B avec prix négociés non optimisé par ce lot |
| [Retour arrière SQL](proposals/coco-storefront-projection-rollback.sql) | Rétablir la définition observée et supprimer la nouvelle vue, dans une transaction | Refuse de remplacer une fonction modifiée depuis ; à revoir si le code évolue |

La vue est privée, `security_invoker=true`, sans accès direct pour `anon` ou `authenticated`. La fonction privilégiée conserve son propriétaire, ses droits, son `search_path` vide, ses contrôles de publication, son secret serveur pour les soumissions et son calcul de prix. Le helper privé historique n’est pas modifié. Aucun cache de prix, index supplémentaire, service payant ou augmentation de timeout n’est introduit.

## Mesures de laboratoire

Base entièrement synthétique : 1 836 produits, 1 795 chaînes de photos, 34 275 525 caractères de photos. Trois appels séquentiels par action et variante, dans le même processus, avant puis après. Aucun réseau ni rendu navigateur dans ces durées. Le premier appel de chaque série peut inclure la préparation des plans ; ce protocole n’est pas un test de cache navigateur froid. CPU de l’hôte non maîtrisé, variabilité sensible ; aucun p95 ni gain de production ne peut en être déduit.

| Action SQL | Avant, trois essais en ms | Proposition, trois essais en ms | Médianes avant → après |
| --- | --- | --- | --- |
| `bootstrap` | 7 314,4 ; 5 815,1 ; 5 088,8 | 622,6 ; 554,5 ; 665,2 | 5 815,1 → 622,6 ms |
| `catalog`, 30 produits | 3 343,7 ; 1 465,6 ; 3 736,3 | 33,6 ; 25,2 ; 31,8 | 3 343,7 → 31,8 ms |
| `product`, une fiche | 1 215,3 ; 795,2 ; 1 372,7 | 4,3 ; 4,2 ; 5,1 | 1 215,3 → 4,3 ms |

Chaque réponse des 18 appels a été comparée à la réponse initiale correspondante. Les résultats sont identiques. Les [mesures individuelles](data/catalogue-proposal-benchmark-2026-10-19.json) sont conservées. Le plan joint est celui d’une lecture diagnostique de la projection, **pas** le plan complet de la RPC.

Reproduction locale, sans variable de connexion ni accès réseau :

```sh
node scripts/benchmark-storefront-proposal.cjs
```

Le script restaure une base PGlite vide, insère uniquement ses données fictives et ferme la base. Il s’arrête au premier échec ou après un appel dépassant 15 secondes ; aucun autre appel mesuré ne suit ce dépassement. Il réalise au maximum 18 appels mesurés et un plan diagnostique, hors restauration/préparation. Ce n’est pas un script de charge en production.

## Tests et critères d’acceptation

Les tests Node du CSV couvrent les préfixes `=`, `+`, `-`, `@`, les contrôles et espaces initiaux, les séparateurs, guillemets et caractères accentués ; le refus d’export intervient avant lecture ou téléchargement. Référence : OWASP ASVS **5.0.0, 1.2.10**. La réussite prouve le comportement de sérialisation, pas une certification ASVS.

Les tests Node du catalogue couvrent les premières cartes utilisables avant la suite, la conservation des cartes, les offsets 0/30/60/90, une limite serveur plus petite, les réponses obsolètes, le changement de compte et l’échec d’un lot intermédiaire. Les nouveaux tests Playwright aux largeurs 390 et 1 440 pixels contrôlent la modification de quantité et l’ajout au panier pendant l’attente. Les tests existants contrôlent les 100 produits, la pagination, les dix colonnes et les prix négociés.

Les tests SQL de la proposition comparent les réponses avant/après avec les rôles `anon` et `authenticated`, testent les produits masqués/inactifs, les photos invalides, les prix cachés, le site en pause, le refus d’accès à la vue et de soumission sans secret. Ils vérifient les droits et le `search_path` inchangés, le retour arrière exact, ainsi que le refus d’application si la définition courante a changé. Les suites existantes du site et du portail testent également les règles de prix et de séparation des clients dans des fixtures isolées.

Le téléchargement de Chromium local a échoué (archive invalide). Les tests navigateur préparés doivent être exécutés par la CI avant fusion. Aucune validation Safari/iPhone, Android physique, PWA installée, ni mesure de Core Web Vitals de terrain n’est revendiquée.

Résultats locaux : **14 tests ciblés réussis**, puis **2 scénarios complets public/B2B réussis après application locale de la proposition** (16 exécutions, dont deux reprises avec la proposition). Compilation ERP et site, types, liens de documentation, reproductibilité des fichiers générés et budget de démarrage vérifiés. `verify:migrations` valide les empreintes locales ; il ne rapproche pas le registre distant et ne lève donc pas REL-01.

Commandes de recette ciblées (base isolée seulement) :

```sh
node --test --test-concurrency=2 tests/audit-csv.test.cjs tests/storefront-progressive.test.cjs tests/storefront-projection-db.test.cjs tests/storefront-db.test.cjs tests/b2b-storefront-db.test.cjs tests/storefront-server.test.mjs
node --require ./tests/helpers/storefront-proposal.cjs --test --test-concurrency=2 tests/storefront-db.test.cjs tests/b2b-storefront-db.test.cjs
npx playwright test tests/storefront.spec.js tests/b2b-portal.spec.js tests/audit-trail.spec.js --workers=2
```

La deuxième commande réutilise les scénarios complets du site public et des deux clients B2B **après application locale de la proposition**, via un préchargement réservé aux tests. Elle ne rejoue rien sur Supabase.

## Conditions avant mise en production

1. Examiner le diff de cette branche et obtenir l’autorisation d’implémentation. Ce lot reste une préparation d’audit.
2. Traiter **REL-01** : 313 migrations locales contre 312 entrées distantes ; les numéros divergent et deux anciens fichiers contiennent des remises à zéro. **Ne pas lancer un `db push` global, `--include-all`, ou une réparation automatique du registre.** Comparer noms, définitions et contenu ; faire approuver le rapprochement.
3. Préparer une recette PostgreSQL 17.6 isolée, avec deux entreprises et des comptes de test ; désactiver les notifications, paiements, SRI et tâches externes. Vérifier les mêmes scénarios avec les sessions ordinaires.
4. Conserver les définitions SQL et les réglages de publication, vérifier une restauration utilisable et tester le retour arrière. Les deux SQL proposés comparent l’empreinte des définitions attendues ; ils échouent en cas de divergence. Une divergence nécessite une nouvelle revue, pas la suppression du garde-fou.
5. Une fois autorisée, créer la migration ciblée avec `supabase migration new`, à partir du SQL approuvé. Aucun fichier de ce lot n’est dans `supabase/migrations/` et aucun historique existant n’est réécrit.
6. Appliquer la seule migration validée, puis publier les artefacts testés. L’ancienne interface reste compatible avec la nouvelle base, et la nouvelle interface accepte les anciens plafonds de RPC.
7. Vérifier le commit réellement servi, les trois lectures anonymes, les prix de deux clients de test et les compteurs d’erreurs. Sur recette : objectif proposé de médiane SQL `< 1 s` pour le démarrage, `< 250 ms` pour la page/fiches avec un volume comparable ; objectif UX `< 2,5 s` pour les premières cartes utilisables sur le contexte PC convenu. Ce sont des critères proposés, pas des résultats de terrain.

En cas de régression : revenir à l’artefact précédent et appliquer le retour arrière SQL revu. L’absence de modification de données évite une migration inverse de lignes métier. Une incompatibilité de l’empreinte ou une dépendance ajoutée depuis bloque le retour arrière et exige une revue.

## Risques restant ouverts

Le transfert de toutes les photos de la page, leur affichage tardif, le catalogue B2B trié par prix, les vérifications d’accès en conditions réelles, l’authentification, les sessions TMS, les validations d’Agent Coco, les sauvegardes et la restauration restent dans le plan initial. Ce lot ne change aucun de ces droits ou paramètres.

Effort restant pour ce lot : environ 0,5–1 jour de revue/recette, hors résolution du registre de migrations et disponibilité des comptes. Risque de régression modéré sur les lectures SQL et le chargement progressif ; faible sur la sérialisation CSV. Aucun coût récurrent nouveau.

Documentation technique consultée : [PostgreSQL 17 — CREATE VIEW](https://www.postgresql.org/docs/17/sql-createview.html), [Supabase — fonctions SQL](https://supabase.com/docs/guides/database/functions), [Supabase — RLS et vues](https://supabase.com/docs/guides/database/postgres/row-level-security), [OWASP ASVS 5.0.0](https://github.com/OWASP/ASVS/tree/v5.0.0).
