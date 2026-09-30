# Modifier Coco ERP

1. Chercher le module dans `config/runtime-assets.json` ; ouvrir son `source`.
2. Modifier le source nommé par domaine. Les anciennes URL dans les tests sont les sorties publiques compatibles.
3. Lancer `npm run build`, puis les contrôles et tests du parcours modifié.
4. Vérifier `npm run check:generated` avant publication : aucune copie racine ne doit diverger.
5. Mettre à jour le document courant du module.

## Commandes

| Commande | Vérification |
| --- | --- |
| `npm run build` | Compile le catalogue et génère les actifs racine et dist |
| `npm run check` | Syntaxe des sources et sorties, manifeste, liens des trois entrées HTML |
| `npm run check:docs` | Vérifie les liens locaux après déplacement des documents |
| `npm run typecheck` | Contrats TypeScript existants ; ne couvre pas tout le JavaScript |
| `npm run verify:migrations` | Historique du dépôt ; pas une migration automatique de production |
| `npm run test:architecture` | Propriété des sources, chargement partagé et ordonné, reprise après erreur, isolation de session, cache statique |
| `npm run check:startup` | Budget des scripts déclarés au démarrage après build : 93 scripts, 1 900 000 octets |
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
La CI vérifie la syntaxe, les contrats, les liens documentaires, les tests et la correspondance des sorties avec leurs sources. Les anciens workflows d’installation désactivés ont été retirés. GitHub Pages publie les sorties commises ; une modification de source seule n’actualise pas la production.

Ne jamais exécuter une fixture de test contre la base de production. Les tests SRI simulés ne remplacent pas l’autorisation réelle du SRI ni un essai de signature avec le service privé.

## Dépendances et exports

Vite est verrouillé en 6.4.3 dans `package.json` et `package-lock.json`. Après une mise à jour, lancer `npm audit`, reconstruire et vérifier les sorties ; l’audit npm ne couvre pas automatiquement les bibliothèques copiées dans `assets/vendor/`.

Pour ajouter un export, suivre le [contrat PDF](pdf-exports.md). Ne pas réintroduire le moteur PDF dans les scripts initiaux. Les notifications utilisent le badge créé par `src/ui/shell.js` ; ne pas observer tout le document pour recréer ce badge.
