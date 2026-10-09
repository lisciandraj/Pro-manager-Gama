# Agent Coco — mouvements de stock authentifiés

## Composants et état de publication

Le module conserve ses conversations et rapports. Il dispose désormais de **Stock et connexion** et du bouton **Préparer un mouvement depuis ce message**. La préparation en langage naturel est intégrée à `gama-assistant-ia` ; son modèle ne possède aucune fonction d'exécution. La confirmation appelle le moteur métier puis relit les mouvements et le stock.

La migration de production `20261009164509_agent_coco_gateway.sql` a été appliquée le 9 octobre 2026. Les accès personnels sont désactivés par défaut. `coco-agent-mcp` est déployé ; `gama-assistant-ia` a été mis à jour avec le planificateur de stock. Aucun compte partagé et aucun mouvement de stock de production ne sont créés par l'installation.

Le site doit publier le résultat de `npm run build` (`dist/`), pas des copies historiques à la racine. Le workflow `deploy-coco-pages.yml` compile, teste et publie ce résultat. Le propriétaire doit sélectionner **Settings > Pages > Build and deployment > Source > GitHub Actions**. Le workflow refuse de modifier lui-même les réglages administratifs. `dist/coco-build.json` identifie le commit réellement publié. Les Edge Functions et migrations sont déployées séparément.

## Activation personnelle

Dans l'ERP, se connecter avec un administrateur actif, satisfaire sa MFA puis ouvrir **Configuration > Agent Coco**, ou **Agent Coco > Stock et connexion**. Activer l'accès personnel et, séparément, les mouvements confirmés. Le bouton de révocation désactive immédiatement les appels suivants. Un changement d'autorisation invalide les propositions précédentes.

Pour ChatGPT, activer le serveur OAuth 2.1 dans Supabase, avec comme page de consentement l'adresse ERP `https://lisciandraj.github.io/Pro-manager-Gama/index.html`. Ajouter le connecteur privé avec l'URL MCP ci-dessous et se connecter au compte ERP. Autoriser le client affiché uniquement s'il correspond au connecteur créé. La case d'écriture est distincte pour chaque client : autoriser un nouveau client en écriture n'élève pas les anciens clients en lecture seule. L'ajout du connecteur dépend des fonctionnalités accessibles au compte ChatGPT.

- MCP : `https://mknsaibrewksgomuslev.supabase.co/functions/v1/coco-agent-mcp`
- Métadonnées : même URL suivie de `/.well-known/oauth-protected-resource`.
- Auth : `https://mknsaibrewksgomuslev.supabase.co/auth/v1`.

Ne transmettre aucun mot de passe, jeton ou clé privilégiée dans un chat ou un dépôt. La connexion MCP utilise le jeton du demandeur authentifié, jamais une clé administrateur partagée. La désactivation de la vérification JWT automatique sur la seule passerelle permet la découverte OAuth publique ; les appels métier vérifient toujours le jeton auprès de Supabase Auth puis appliquent les droits ERP.

## Contrat et garanties

Les six outils sont `coco_search_products`, `coco_get_stock`, `coco_prepare_stock`, `coco_execute_stock`, `coco_get_command` et `coco_stock_history`. La proposition expire après dix minutes et fige produit, unité, emplacement, réservations, quantité, justification et règles d'approbation. Sa confirmation porte sur une empreinte exacte. Les reprises réutilisent son identifiant ; elles ne créent pas un second mouvement.

L'exécution appelle `gama_adjustment_request` dans une transaction. Les validations, les réservations, les contrôles de lots et la MFA ne sont pas assouplis. `pending_approval` signifie qu'une validation ERP reste nécessaire ; ce n'est pas une preuve de mouvement effectué. `coco_get_command` relit les références réelles, la quantité et le stock actuel.

Les clients OAuth n'ont pas d'accès direct aux tables ni aux autres RPC. Cette frontière globale doit être revue avant d'ajouter d'autres applications OAuth au projet. Aucun client OAuth n'était enregistré au contrôle précédant l'installation. Un éventuel hook PostgREST antérieur provoque un arrêt explicite, pas un remplacement silencieux.

La première version n'automatise pas les validations indépendantes, les transferts, ni la sélection de lots. Les sorties par lot exigent un lot explicite par l'API ; l'interface dirige ces produits vers Stock. Les opérations multilocalisations dépassant un seuil global sont refusées pour ne pas fractionner une demande et contourner son approbation. Les entrées manuelles ne remplacent pas les réceptions fournisseur.

## Vérification

`npm run update` compile et lance les contrôles communs. Les tests `coco-agent-db.test.cjs`, `coco-agent-mcp.test.mjs`, `coco-agent-planner.test.mjs` et `coco-agent-ui.spec.js` couvrent le circuit et ses refus. Les fixtures, y compris la sortie de 65 unités vers zéro, sont **isolées**, jamais chargées dans la production. `node scripts/check-agent-live.mjs` vérifie seulement la santé publique et le refus des requêtes sans authentification ; il ne déplace aucun stock.

Pour prouver une sortie réelle de MED001, il faut une session ERP autorisée : lire le stock courant, préparer « tout le stock » avec le motif exact « consommation interne », confirmer, puis relire le mouvement, son numéro, son auteur et le stock. Les tests isolés et un déploiement ACTIVE ne remplacent pas cette preuve. Lors du contrôle de déploiement, le stock réel restait à 65 et aucun accès Agent Coco n'était activé.
