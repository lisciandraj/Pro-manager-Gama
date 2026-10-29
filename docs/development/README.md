# Modifier Coco ERP

1. Chercher le module dans `config/runtime-assets.json` ; ouvrir son `source`.
2. Modifier le source nommé par domaine. Les anciennes URL dans les tests sont les sorties publiques compatibles.
3. Lancer `npm run update` pour construire et valider, puis les tests navigateur du parcours modifié.
4. Vérifier `npm run check:generated` avant publication : aucune copie racine ne doit diverger.
5. Mettre à jour le document courant du module.

## Commandes

| Commande | Vérification |
| --- | --- |
| `npm run update` | Reconstruit toutes les sorties et lance la validation commune |
| `npm run validate` | Syntaxe, types, liens, migrations, tests Node, génération et budgets |
| `npm run build` | Compile le catalogue et génère les actifs racine et dist |
| `npm run check` | Syntaxe des sources et sorties, manifeste, liens des trois entrées HTML |
| `npm run check:docs` | Vérifie les liens locaux après déplacement des documents |
| `npm run typecheck` | Contrats TypeScript existants ; ne couvre pas tout le JavaScript |
| `npm run verify:migrations` | Historique du dépôt ; pas une migration automatique de production |
| `npm run test:architecture` | Propriété des sources, chargement partagé et ordonné, reprise après erreur, isolation de session, cache statique |
| `npm run check:startup` | Budget versionné dans `config/performance-budget.json` : 15 scripts, 850 000 octets JS et 300 000 octets CSS |
| `npm run test:unit` | Tests Node et fixtures SQL isolées |
| `npm test` | Parcours Playwright ; Chromium requis |
| `npm run check:generated` | Reconstruction reproductible et absence de dérive |
| `npm run build:i18n` | Annotations des sources et catalogue de traductions, puis reconstruction |

## Ajouter un module

Déclarer identité et accès dans `src/app/registry.js`, écrire son source sous `src/features/`, ajouter le couple source/output au manifeste.
S’il peut attendre son ouverture, déclarer ses méthodes publiques dans `src/app/lazy-modules.js`. Le module remplace la façade `__arcLazy` ; sa garde d’installation ne doit pas bloquer cette façade.
Déclarer les scripts prérequis dans `dependencies` : ils sont chargés dans l’ordre et partagés entre les appels simultanés. Les intégrations utilisées par plusieurs écrans doivent rester légères, comme `src/features/projects/integration.js`.
Garder les vérifications serveur, la gestion des changements de session et les appels croisés existants.

## Styles

Les tokens globaux sont dans `src/styles/tokens.css`; le thème GAMA courant ajoute ses valeurs dans `src/styles/design.css`.
Les sections CSS métier sont dans `src/styles/modules/` et assemblées dans l’ordre du manifeste. Changer cet ordre peut modifier la cascade, même sans changer une règle.

## Tests et publication

Privilégier les comportements observables : mêmes droits, mêmes documents, cache sans fuite de session, reprise après échec, mobile utilisable.
La CI vérifie la syntaxe, les contrats, les liens documentaires, les tests et la correspondance des sorties avec leurs sources. Les anciens workflows d’installation désactivés ont été retirés. GitHub Actions construit, teste puis publie l’artefact `dist/` sur GitHub Pages. Les migrations SQL, Edge Functions et le service SRI ont des déploiements distincts.

Ne jamais exécuter une fixture de test contre la base de production. Les tests SRI simulés ne remplacent pas l’autorisation réelle du SRI ni un essai de signature avec le service privé.

## Dépendances et exports

Vite est verrouillé en 6.4.3 dans `package.json` et `package-lock.json`. Après une mise à jour, lancer `npm audit`, reconstruire et vérifier les sorties ; l’audit npm ne couvre pas automatiquement les bibliothèques copiées dans `assets/vendor/`.

Les bibliothèques locales différées figurent dans `vendors` du manifeste pour recevoir une URL à hash de contenu. Après changement de jsPDF, actualiser aussi son chemin et son intégrité dans le chargeur. `node scripts/check-startup.cjs --json` détaille les tailles et leur gzip estimé ; expliquer une augmentation des plafonds avant de modifier le budget.

Pour ajouter un export, suivre le [contrat PDF](pdf-exports.md). Ne pas réintroduire le moteur PDF dans les scripts initiaux. Les notifications utilisent le badge créé par `src/ui/shell.js` ; ne pas observer tout le document pour recréer ce badge.

## Historique des migrations déployées

Les treize migrations Ecuador de cette livraison et les fonctions `gama-sri`, `gama-sri-received` et `architect-user-admin` sont déployées sur le projet de production. `supabase/migration-history.json` associe les versions effectives renvoyées par Supabase aux fichiers canoniques et à leurs empreintes SHA-256. Les noms de fichiers créés par le CLI sont conservés : la version attribuée par le connecteur au déploiement peut différer. Le contrôle des migrations interdit de réécrire un fichier déjà appliqué.

Les anciennes migrations absentes du relevé de 2026-10-03 comprennent des alias historiques déjà déployés et deux réinitialisations contrôlées du catalogue. Leur présence dans le répertoire ne constitue pas une instruction de les réappliquer en production. Comparer les noms et versions de la base avec le relevé avant une nouvelle livraison ; appliquer seulement les migrations réellement nouvelles.

La revue du 5 octobre complète la préparation 07 à la validation fournisseur/revue fiscale/politique fournisseur, et le rapport TMS de coûts par client. Leurs versions de production sont `20261005070632` et `20261005070644`. Voir [la revue des demandes](../audits/2026-10-05-erp-completion.md).

## Traductions de l’interface

Les libellés de l’ERP sont disponibles en espagnol, français et anglais. Ajouter les textes espagnols et leurs traductions relues dans `locales/catalog.tsv`, puis exécuter `npm run build:i18n`. Le compilateur annote les textes statiques des sources et les attributs de présentation (placeholder, titre, aria-label, alt). Isoler les libellés dynamiques avec `data-gi-live` ou `data-gi-source` ; ne jamais marquer un conteneur de noms de produits, clients ou de saisies utilisateur. Les composants partagés conservent la source des titres, champs et colonnes pour changer de langue sans reconstruire le formulaire. Les statuts se traduisent à l’affichage ; leurs valeurs métier ne changent pas.

Le mode chauffeur charge aussi le moteur de langue et met le catalogue en cache lors du téléchargement de la tournée. Vérifier les tests `i18n.spec.js`, `i18n-coverage.spec.js` et `i18n-hr.spec.js` après toute évolution des fenêtres ; ils couvrent les langues, les modules et onglets, les fenêtres TMS et la conservation des valeurs saisies.

## Maintenance des frontières d'autorisation (29 octobre 2026)

Les migrations `20261029233001` à `20261029233004` alignent les chemins historiques avec les contrôles courants : compte interne actif, identité non bannie des automatisations, droits d'action comptables et de réception d'achat, périmètre financier des lectures, accès aux preuves TMS, approbation des ajustements de stock, catalogue et consentement B2B, quota commun du formulaire public et coordonnées provenant du géocodeur. Les coordonnées manuelles restent propres au contact ; seul le cache vérifié par le fournisseur peut alimenter un autre contact.

Les contrats récurrents conservent leur auteur d'origine, mais toute sauvegarde ou reprise d'une préparation automatique engage les droits de son dernier responsable (`scheduled_by`). Elle exige le droit de créer une commande. Le traitement horaire revérifie les droits de ce responsable ; une modification ne peut donc pas utiliser implicitement les droits supérieurs d'un ancien auteur. Les contrats historiques non modifiés conservent leur responsable initial.

Le budget d'une acquisition est verrouillé avant la création d'une immobilisation. Les écritures directes des seuils de réapprovisionnement respectent les modules, actions et validation exigés par leur interface. Une substitution conserve les quantités de services déjà effectuées ; lorsqu'elle rejoint une ligne existante, sa revue de marge utilise le coût mémorisé de cette ligne, comme la commande résultante.

Les photos en cache échappent leurs attributs HTML. Le visualiseur de justificatifs utilise des propriétés DOM avec des URL de données PDF/image autorisées. Les exports CSV traitent les textes commençant comme des formules sans convertir les montants numériques négatifs en texte.

Le workflow `audit-hardening.yml` exécute les fixtures ciblées avant ses parcours navigateur. Les contrôles de publication habituels restent requis. Les tests de concurrence utilisent exclusivement la base PostgreSQL jetable prévue par `validate-sales-concurrency.yml`. Aucun test métier ne doit viser une base connectée de production.
