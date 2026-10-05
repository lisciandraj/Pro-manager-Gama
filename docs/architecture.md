# Architecture actuelle de Coco ERP

État : 5 octobre 2026. Application statique JavaScript, noyau ES modules compilé avec Vite, modules métier existants encapsulés, Supabase pour Auth/PostgreSQL/Storage/Realtime/Edge Functions. La passerelle fiscale Python reste un service privé distinct ; elle peut utiliser le signataire historique ou le moteur externe Open API Facturación SRI.

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

`scripts/build.cjs` vérifie le manifeste, compile le catalogue de traductions sans réécrire les sources, compacte les scripts nommés sans renommer les identifiants publics, compile le noyau, assemble les deux lots de démarrage, assemble les sections CSS communes dans l’ordre déclaré et publie séparément les styles différés, calcule les versions par contenu, génère les pages et le service worker, puis prépare `dist/`.
`scripts/lib/assets.cjs` partage le manifeste et les règles de génération avec les contrôles.
La liste des scripts publiés est explicite : les configurations Playwright et les outils ne sont plus inclus par une recherche de tous les fichiers JS.

Les fichiers racine `gama-*` et `architect-*` restent des **sorties compatibles**, pas des sources à modifier. Les objets globaux Gama*/Architect*/Arc*, sélecteurs et clés de stockage restent stables. Une migration globale de ces contrats demanderait de migrer les clients, les tests et les données enregistrées ensemble.

## Chargement

Le noyau et les dépendances de base restent disponibles au démarrage. Dashboard/KPI, CRM, RH, Suivi de processus, Compras, Comptabilité, flotte, retours, SAV/documents, diagnostics d’audit, site web, Knowledge, Agent Coco, Projets, Stock et TMS se chargent à la demande. SAV et Documents partagent un seul téléchargement. Un échec réseau peut être réessayé ; l’ouverture par recherche globale utilise les mêmes points d’entrée.

Le menu et ses droits vivent dans le petit lot `coco-shell.js`, après le transport et le noyau. Les contrôles et les intégrations historiques sont réunis dans `coco-modules.js`, avec une priorité réseau basse. Ces deux lots conservent leur portée classique, leurs identifiants et leur ordre d’exécution. Une ouverture très précoce attend les contrôles partagés ; le fichier peut être réessayé après un échec réseau. La synchronisation centrale a un seul chargement déclaré, sans téléchargement de secours en double.

Les scripts déclarés dans l’entrée ERP utilisent `defer` : leurs téléchargements se chevauchent, avec un ordre d’exécution conservé après l’analyse du HTML. Identité et Supabase précèdent la validation du profil ; le menu peut fonctionner avant la fin du chargement des extensions finales. Les tuiles sont créées masquées puis affichées avec les droits vérifiés. Quand Auth restaure une session sans ancien enregistrement de compatibilité, `gama:profile-ready` réveille aussi le menu ; les changements de rôle sont comparés à l’état réellement appliqué, et les rafraîchissements identiques conservent le DOM.

Le moteur jsPDF local est chargé par `GamaPdf.ready()` au premier export. Les constructeurs de documents restent synchrones après cette attente ; voir [exports PDF](development/pdf-exports.md). Le chargeur partage les téléchargements, conserve l’intégrité SRI et permet une nouvelle tentative après une erreur réseau.

Projets sépare l’intégration légère (`src/features/projects/integration.js`) du moteur de calcul et des écrans. Les alertes, liens de création et résumés clients restent disponibles à l’accueil ; `projects-core.js`, puis `projects.js`, sont chargés à l’ouverture. Les lectures simultanées d’alertes partagent une promesse sans conserver les résultats. Les réponses d’une ancienne session sont rejetées ; un renouvellement de jeton ne ferme pas l’éditeur.

Stock garde son point d’entrée historique avec une intégration légère. Les existences se chargent en premier ; règles de reposición, fournisseurs, inventaires et étagères attendent leur onglet. Les vues opérationnelles agrègent les sorties côté serveur et créent uniquement des brouillons d’achat avec reçu idempotent ; voir [Stock](modules/stock.md).

Le catalogue complet des traductions attend le français ou l’anglais. En espagnol, seuls les messages serveur sont chargés et les scans de traduction inutiles sont évités. Un changement de langue charge une seule fois le catalogue puis retraduit les labels existants, sans changer les valeurs métier. Les liens de modules survolés ou sélectionnés au clavier préchargent leurs scripts sans exécuter de module ni lire de données. Les groupes de dépendances se téléchargent en parallèle avec un ordre d’exécution conservé ; CRM attend également toutes ses extensions avant de traiter un lien direct.

Les constructeurs PDF légers, les traductions Projets et certaines extensions restent chargés au démarrage. Le budget `npm run check:startup` limite désormais les scripts déclarés à 15 et 900 000 octets non compressés ; il n’inclut pas les requêtes dynamiques, CSS, images ou données métier.

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

## Fournisseur fiscal Open API

Le module `sri` partage le chargement différé de Comptabilité via `GamaAccounting.openSri`. La source canonique reste `src/features/finance/accounting.js`. `services/sri/openapi.py` adapte le contrat HTTP amont ; `gama-sri` conserve les droits, les revendications atomiques et les archives privées. Aucun secret amont ne passe par le navigateur. Voir [installation Open API](../services/sri/OPENAPI.md).

## Livres et contrôles équatoriens

`gama_accounting_ec` est la façade invocateur des extensions de livres, échéances, retenues, immobilisations et intégrations. Ses traitements privés vérifient le module, le périmètre et les droits, puis lient la clé idempotente à l’acteur et à la requête. La migration `20261003074945_accounting_ec_ledger.sql` ajoute des tables protégées par RLS, sans réécrire les migrations historiques ni rejouer les pièces existantes.

Le sous-ensemble de génération ATS, source `src/domain/accounting-ecuador.js`, devient `gama-accounting-ec.js` au build et se charge sur demande. Il ne s’ajoute pas au démarrage. Les contrôles, le périmètre et les écarts sont décrits dans [l’audit comptable équatorien](audits/2026-10-02-accounting-ecuador.md).

## Site public sur Cloudflare Pages

Le site GAMA est compilé séparément par `npm run build:storefront` dans `dist-storefront`. Ses sources sont dans `src/storefront/` et ses Pages Functions dans `src/storefront/server/`, avec des points d’entrée sous `functions/`. Il ne charge pas l’ERP. Le module Site web charge l’administration publique `gama-store-admin.js` à la demande. Les réglages sont définis par `config/storefront-schema.json` et validés dans SQL ; les lectures publiques utilisent la façade `gama_storefront` et une projection limitée. Les modifications administratives et les demandes sont distinctes de l’ancienne prévisualisation. Voir le [guide du site public](public-website.md).

### Sondages et contacts

Le module `surveys` utilise le chargeur différé et son rendu partagé `gama-survey-form.js`. Son formulaire public Cloudflare est indépendant de l’état du catalogue ; chaque questionnaire nécessite une publication explicite. Les RPC et données privées sont décrites dans [surveys.md](surveys.md).

`gama-contacts.js` conserve un adaptateur léger pour les routes historiques ; `gama-contacts-workspace.js` se charge à l’ouverture. Les personnes clientes utilisent `crm_contacts`, et leur enregistrement atomique respecte les droits CRM. Voir [contacts.md](contacts.md).

Le détail de Suivi de processus et des retours affiche l’historique de chaque étape via `gama_process_history`. La façade invoker appelle un helper privé protégé par authentification, MFA et droits du dossier/étape. Le serveur renvoie uniquement action, date, nom d’auteur, état et référence ; les données complètes des journaux ne sont pas exposées. Les étapes financières restreintes restent masquées. Les actions proviennent des journaux métier et de l’audit, sans attribuer une validation au propriétaire du dossier. Les actions historiques sans auteur sont signalées. L’historique se charge au détail seulement, par pages de 50 actions pour chaque étape. Les réceptions, traitements et clôtures futurs des retours sont audités.

Les onglets Importer des données, Sauvegarde, Utilisateurs et Paramètres d’accès vivent dans la fenêtre Configuration (`src/ui/settings.js`). Le registre conserve leurs identifiants et droits via `settingsTab`, tout en retirant les entrées du menu. Le routeur redirige les anciennes ouvertures vers l’onglet. Les écrans existants sont déplacés dans leurs panneaux puis replacés et masqués à la fermeture ; aucun formulaire ni gestionnaire de fichier n’est dupliqué. Utilisateurs reste réservé aux administrateurs et conserve les invitations, les rôles, l’approbation, la suppression et les mises à jour automatiques.

## Planification TMS quotidienne

La carte des livraisons est rendue localement par `src/features/transport/local-map.js` avec un fond Natural Earth livré dans l’application. Tous les points GPS se cadrent ensemble ; sans point, la vue est centrée sur Quito. Zoom, déplacement et filtres fonctionnent sans clé, serveur de tuiles ni géocodeur. Waze reste un lien de navigation. `gama_tms_plan_day` conserve sa façade invocateur et ses verrous transactionnels. `gama_tms_execution` ajoute les réceptions par ligne, l’historique de tentatives, les rôles TMS et la clôture. Voir [TMS](modules/tms.md).

## Vues personnelles du Dashboard

`src/features/dashboard/dashboard.js` utilise les agrégations autorisées existantes. Ses filtres, favorites, panneaux et outils de graphique sont décrits dans [Dashboard](modules/dashboard.md). Les préférences locales sont attachées au `user_id` vérifié du résultat serveur ; les CSV vérifient aussi les droits d’export.

Les titres et téléchargements de Documents remplacent les noms techniques contenant un UUID par leur référence ERP, par exemple `DOC-00000017` et `DOC-00000017.jpg`. Les titres et noms de fichiers choisis par les utilisateurs sont conservés. Les données et chemins de stockage restent identiques.

## Documents SRI liés aux opérations

`src/features/finance/sri-documents.js` est une dépendance différée de Comptabilité, Retours et TMS. Elle n'ajoute pas de script au démarrage. Les façades `gama_sri_documents`, `gama_sri_document_access` et `gama_tms_guide` contrôlent les droits dans des helpers privés ; le chauffeur ne peut ni préparer ni émettre. `gama-sri` choisit la table de documents par famille et lie aussi le type à la clé. Le service privé valide les XSD locaux et refuse toute divergence entre l'autorisation et la photographie fiscale. Sa tâche optionnelle de consultation utilise un compte de service uniquement pour reconsulter des documents déjà revendiqués, sans envoyer de nouveau document ni notification.

## Pilotage, réapprovisionnement et portail B2B

Les nouvelles lectures `gama_stock_sales_thresholds` et `gama_management_overview` s’ouvrent avec leurs écrans métier, sans dépendance au démarrage. Les validations des seuils utilisent des reçus de commande et ne touchent pas aux quantités physiques. SAV est un onglet de Retours dans le registre ; ses anciennes routes et contrôles serveur restent compatibles.

Le portail B2B est une page autonome produite depuis `src/storefront/`. Ses comptes utilisent une session Auth séparée dans `sessionStorage` et des associations explicites à une entreprise, vérifiées par les façades SQL. Les profils clients retirés de l’ERP restent inactifs ; les anciennes RLS demeurent fermées. La résolution de prix pure et privée est partagée avec le résolveur interne, dont les contrôles d’accès restent inchangés. Voir [site public](public-website.md), [Stock](modules/stock.md) et [pilotage](company-dashboard.md).

## Traitements durables et portail client

Les règles versionnées, traitements, tentatives et exceptions restent privés. Les façades invocateur filtrent par les droits courants du module. Les actions métier déléguées utilisent un contexte transactionnel fermé et temporaire, sans jeton fabriqué ni droit accordé par un GUC. La file d’envoi utilise pg_net et un secret Vault, une destination Resend fixe, des clés stables et une consultation des statuts réels. Les parcours, limites et paramètres sont dans [automatisations](automation.md). Les associations cloud sont accessibles depuis Contacts ; la rubrique Mes documents du portail reste contrôlée par entreprise à chaque téléchargement.

Le composant partagé de tableau utilise la vue tableau par défaut sur ordinateur et téléphone, avec quadrillage visible. Les préférences explicites de vue cartes restent disponibles. `tms-driver.html` est l’entrée mobile hors ligne ; les données de route et commandes en attente sont dans IndexedDB, séparées du cache statique du service worker.
