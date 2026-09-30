# Coco ERP

ERP de gestion pour PME, en français, espagnol et anglais. L’application conserve les données et identifiants historiques GAMA/Architect ; son nom affiché et sa documentation courante sont **Coco ERP**.

- [Application](https://lisciandraj.github.io/Pro-manager-Gama/)
- [Architecture et organisation des sources](docs/architecture.md)
- [Navigation et modules actuels](docs/modules/navigation.md)
- [Guide de développement](docs/development/README.md)
- [Charte graphique actuelle](docs/design-system.md)
- [Audit technique et organisation](docs/audits/2026-09-30.md)
- [Audit complémentaire : chargement, dépendances et maintenance](docs/audits/2026-09-30-runtime.md)
- [Revue de maintenance et contrôles communs](docs/audits/2026-09-30-maintenance.md)
- [Index de la documentation](docs/README.md)

## Démarrer

Prérequis : Node.js 22, npm et Python 3 (compilation des traductions et serveur des tests navigateur).

```sh
npm ci
npm run update
npm run dev
```

Les sources sont dans `src/`. Après une modification, exécuter `npm run build`.
Les scripts et styles à la racine ainsi que `index.html` sont des **copies générées** nécessaires à l’hébergement GitHub Pages actuel. Ne pas les modifier directement.

## Vérifier

`npm run update` reconstruit et lance les contrôles communs. `npm run validate` les relance ; les tests navigateur du parcours modifié restent nécessaires.

```sh
npm run check
npm run typecheck
npm run check:docs
npm run verify:migrations
npm run check:startup
npm run test:architecture
npm run test:unit
npx playwright install chromium
npm test
npm run check:generated
```

Les tests base utilisent des bases isolées ; ils ne sont pas des scripts à exécuter sur les données de production. Les parcours fiscaux SRI nécessitent en plus le signataire privé et leurs essais dédiés : voir [SRI](docs/modules/sri.md).

## Déploiement

GitHub Pages publie la branche principale et ses fichiers générés. `dist/` est également construit, avec uniquement les actifs web nécessaires. Le service SRI et les Edge Functions ont des déploiements distincts ; publier le site ne les déploie pas.
