# Agent Coco — passerelle de stock

## État de la livraison

Développement sur `feat/agent-coco-stock-gateway`, PR #143. Cette branche n'active aucun compte, aucun serveur OAuth et aucune opération de stock en production. Le fichier `plugins/agent-coco/mcp.json` déclare l'adresse prévue ; il ne prouve ni son déploiement ni son installation dans ChatGPT.

Les sources comprennent une passerelle MCP, une API métier transactionnelle, un écran structuré de préparation/confirmation, des autorisations personnelles, le consentement OAuth et des tests isolés. Le raccordement des demandes en langage naturel à l'intérieur de la conversation existante de l'ERP n'est pas encore implémenté : ce premier écran utilise un formulaire explicite. Le côté ChatGPT passe par les outils MCP après enregistrement du connecteur.

## Fonctionnement

Une préparation capture le produit, l'unité de base, les emplacements, les quantités, les réservations, le motif, les limites ERP et la révision des droits. La proposition expire après dix minutes. Une confirmation correspond à cette proposition précise. L'exécution réutilise `gama_adjustment_request('submit', ...)` ; elle ne remplace pas le moteur Stock.

Les entrées sont des ajustements manuels, pas des réceptions fournisseur. Le motif `internal_use` représente la consommation interne ; la justification textuelle exacte est conservée dans la demande d'ajustement. Le moteur historique ajoute son libellé métier au motif du mouvement.

L'exécution peut donner `executed`, `pending_approval` ou `rejected`. Une demande en attente de validation n'est pas présentée comme exécutée. Le reçu initial est conservé ; une validation ultérieure dans Stock n'actualise pas rétroactivement ce reçu de soumission. Un nouvel essai du même identifiant de commande renvoie le même résultat sans recréer de mouvement.

Les produits suivis par lot exigent un lot et un emplacement explicites via l'API. Le formulaire dirige ces produits vers le module Stock. La sortie globale ne traite pas les produits suivis par lot. Les commandes multi-emplacements dépassant une limite globale sont refusées plutôt que fractionnées pour éviter une approbation.

## Sources

| Composant | Fichier |
| --- | --- |
| SQL à intégrer | `supabase/sql/agent-coco.sql` |
| API MCP | `supabase/functions/coco-agent-mcp/handler.mjs` |
| Écran et consentement | `src/features/intelligence/agent-coco-stock.js` |
| Préparation des sources et de la migration | `scripts/prepare-agent-coco.cjs` |
| Tests métier isolés | `tests/coco-agent-db.test.cjs` |
| Tests HTTP/MCP | `tests/coco-agent-mcp.test.mjs` |
| Déclaration du plugin privé | `plugins/agent-coco/` |

## Préparation et vérification avant fusion

Sur une copie de la branche, avec Node.js 22 et Python 3 :

```sh
npm ci
node scripts/prepare-agent-coco.cjs
npm run build
node --test tests/coco-agent-mcp.test.mjs tests/coco-agent-db.test.cjs
npm run check
npm run typecheck
npm run check:generated
npm run check:startup
```

Le script d'intégration utilise Supabase CLI 2.120.0 pour générer le nom réel de la migration. Il ajoute le bouton au module Agent Coco et l'entrée dans Configuration, puis prépare le manifeste de chargement. Il n'appelle aucun projet Supabase distant et ne déploie rien. L'intégration doit être relue et les sources modifiées, la migration générée et tous les fichiers compilés doivent être enregistrés dans la branche avant fusion. Le contrôle CI en lecture seule effectue ces opérations dans un espace jetable et ne les enregistre pas dans le dépôt.

Les fixtures de test sont réservées à la base PGlite isolée. Ne pas exécuter les fichiers de tests sur la base de production. Les validations normales du dépôt et les tests navigateur des écrans/consentements restent nécessaires en plus des deux fichiers ciblés.

## Revue d'accès avant déploiement

La migration protège l'utilisation des jetons OAuth délégués au niveau PostgREST et des tables RLS. Elle concerne tous les clients OAuth : inventorier les clients existants avant application et vérifier que cette frontière correspond au périmètre de l'entreprise. Vérifier aussi tout hook PostgREST préexistant et les accès GraphQL, Realtime, Storage et Edge Functions. La migration refuse de remplacer un hook différent déclaré sur le rôle `authenticator` ; la configuration distante doit également être contrôlée.

La fonctionnalité reste désactivée par défaut pour chaque utilisateur. Il n'existe pas de compte administrateur partagé créé par cette livraison. Les droits effectifs restent limités par le compte ERP, les autorisations de l'intégration et les approbations métier.

## Activation par le propriétaire, après validation et déploiement

1. Déployer la migration validée, la fonction `coco-agent-mcp` et les actifs web correspondants. Vérifier les réponses publiques de découverte et le refus de toute demande métier non connectée, puis effectuer un essai autorisé sur un produit de test séparé du stock réel.
2. Activer le serveur OAuth Supabase et configurer son chemin de consentement pour atteindre l'ERP avec `authorization_id`. Vérifier l'URL finale construite à partir du Site URL existant et du chemin, sans modifier les redirections du site client GAMA. La compatibilité des clés de signature et le parcours MFA doivent être validés séparément.
3. Enregistrer un connecteur privé dans l'interface ChatGPT disponible pour le compte, avec l'adresse MCP déclarée dans `plugins/agent-coco/mcp.json`. L'enregistrement du package n'est pas automatique. Aucun identifiant technique ChatGPT n'est inventé dans ce dépôt.
4. Se connecter avec son compte Coco ERP, examiner l'application et les permissions, puis accorder ou refuser l'accès. Les droits d'écriture sont optionnels et désactivés par défaut à l'écran de consentement.
5. Dans Configuration > Agent Coco, contrôler les clients autorisés et la possibilité de révoquer l'accès. Vérifier que la révocation bloque aussi une proposition déjà préparée.

## Références techniques

Documentation consultée le 9 octobre 2026 :

- Supabase MCP Authentication : https://supabase.com/docs/guides/auth/oauth-server/mcp-authentication
- Supabase OAuth Token Security : https://supabase.com/docs/guides/auth/oauth-server/token-security
- OpenAI, packaging des plugins : https://developers.openai.com/plugins/build/plugins
- OpenAI, connexion de test : https://developers.openai.com/plugins/deploy/connect-chatgpt

L'installation réelle dépend de l'accès aux connecteurs personnalisés du compte ChatGPT et d'un test complet du consentement. Ces prérequis ne sont pas remplacés par la création des fichiers du plugin.
