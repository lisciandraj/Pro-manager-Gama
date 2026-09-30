# Architecture actuelle de Coco ERP

État : 30 septembre 2026. Application statique JavaScript, noyau ES modules compilé avec Vite, modules métier existants encapsulés, Supabase pour Auth/PostgreSQL/Storage/Realtime/Edge Functions. Le signataire fiscal Python reste un service privé distinct.

## Emplacements à modifier

| Besoin | Source faisant autorité |
| --- | --- |
| Menu, droits de navigation, alias, groupes | `src/app/registry.js` |
| Chargement différé et API disponibles | `src/app/lazy-modules.js`, `src/app/loader.js` |
| Navigation et cycle de vie | `src/app/router.js` |
| Structure HTML des pages | `src/app/index.html`, `src/app/gama-site.html` |
| Composants communs | `src/ui/components.js`, `src/ui/components.css` |
| Accueil et barre latérale | `src/ui/home-menu.js`, `src/ui/shell.js` |
| Modules métier | `src/features/<domaine>/` |
| Transport, cache de lecture et références | `src/data/` |
| Formulaires historiques encore utilisés | `src/legacy/` |
| Tokens, thème et styles par module | `src/styles/`, `src/styles/modules/` |
| Traductions | `locales/catalog.tsv`, `locales/server-messages.tsv` |
| Correspondance source → adresse publique | `config/runtime-assets.json` |
| Base et endpoints | `supabase/migrations/`, `supabase/functions/` |
| Signature SRI privée | `services/sri/` |

## Construction

`scripts/build.cjs` vérifie le manifeste, compile le catalogue de traductions sans réécrire les sources, copie les modules nommés, compile le noyau, assemble les 46 sections CSS dans l’ordre déclaré, calcule les versions par contenu, génère les pages et le service worker, puis prépare `dist/`.
`scripts/lib/assets.cjs` partage le manifeste et les règles de génération avec les contrôles.
La liste des scripts publiés est explicite : les configurations Playwright et les outils ne sont plus inclus par une recherche de tous les fichiers JS.

Les fichiers racine `gama-*` et `architect-*` restent des **sorties compatibles**, pas des sources à modifier. Les objets globaux Gama*/Architect*/Arc*, sélecteurs et clés de stockage restent stables. Une migration globale de ces contrats demanderait de migrer les clients, les tests et les données enregistrées ensemble.

## Chargement

Le noyau et les dépendances de base restent disponibles au démarrage. Comptabilité, flotte, retours, SAV/documents, diagnostics d’audit, site web, Knowledge, Coco Intelligence, Projets et TMS se chargent à la demande. SAV et Documents partagent un seul téléchargement. Un échec réseau peut être réessayé ; l’ouverture par recherche globale utilise les mêmes points d’entrée.

Le moteur jsPDF local est chargé par `GamaPdf.ready()` au premier export. Les constructeurs de documents restent synchrones après cette attente ; voir [exports PDF](development/pdf-exports.md). Le chargeur partage les téléchargements, conserve l’intégrité SRI et permet une nouvelle tentative après une erreur réseau.

Projets sépare l’intégration légère (`src/features/projects/integration.js`) du moteur de calcul et des écrans. Les alertes, liens de création et résumés clients restent disponibles à l’accueil ; `projects-core.js`, puis `projects.js`, sont chargés à l’ouverture. Les lectures simultanées d’alertes partagent une promesse sans conserver les résultats. Les réponses d’une ancienne session sont rejetées ; un renouvellement de jeton ne ferme pas l’éditeur.

CRM, les constructeurs PDF légers, les traductions Projets et certaines extensions restent chargés au démarrage. Le budget `npm run check:startup` limite les scripts déclarés à 93 et 1 900 000 octets non compressés ; il n’inclut pas les requêtes dynamiques, CSS, images ou données métier.

## Données et accès

Les droits réels restent contrôlés par la base et les fonctions serveur. Le menu n’est pas une frontière de sécurité. `ArcData` gère pagination, appels RPC, cache et invalidation ; `GamaCloud` reste le transport compatible des modules.
Les mutations de stock invalident aussi les quantités par emplacement et les réservations. Un ancien chargement en erreur ne peut plus évincer une nouvelle entrée de cache après invalidation.

La production et le dossier actif ont des historiques de migrations à rapprocher explicitement : les scripts de restauration et l’export de base documentés dans [Supabase](../supabase/README.md) restent nécessaires. Les migrations déjà appliquées ne sont ni renommées ni réécrites.

## Cache navigateur

Les URL JS/CSS comportant un hash de contenu peuvent être servies depuis le cache du service worker lorsqu’il est installé. Une nouvelle version possède une autre clé. Les pages HTML restent relues sur le réseau ; ERP et site de test ont chacun leur repli hors ligne. Les réponses métier, les écritures et les diagnostics caméra ne sont pas mis dans ce cache.

Le dépôt ne contient pas actuellement d’enregistrement automatique du service worker dans l’entrée ERP. Le correctif concerne les installations qui l’utilisent déjà ; il ne prouve pas un gain de chargement sur tous les appareils.

## Mise à jour et contrôles communs

`npm run update` reconstruit puis lance `npm run validate`. La CI de release utilise les mêmes contrôles. `config/performance-budget.json` centralise les plafonds du démarrage ; `npm run check:startup` contrôle aussi les CSS et les scripts dupliqués, et `node scripts/check-startup.cjs --json` détaille les tailles. Les requêtes dynamiques ne sont pas incluses.

Le manifeste `vendors` versionne par contenu les bibliothèques locales différées sans les ajouter au démarrage. Le chargeur valide la présence de jsPDF après téléchargement et permet une reprise si le SDK est absent.

Les lots de traduction scannent une seule fois chaque racine : un descendant est couvert par son parent lorsqu’ils figurent dans le même lot.

## Limites de cette simplification

Il reste des modules IIFE volumineux et des contrats globaux historiques. Les fichiers sont regroupés par domaine et contrôlés à la construction ; ils ne sont pas tous convertis en composants ES modules. Les avertissements SQL, les tests physiques iPhone/scanner et la validation fiscale restent des travaux distincts explicités dans l’audit.
