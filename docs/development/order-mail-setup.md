# Configuration du mail par utilisateur

L’interface et le serveur peuvent être déployés avant la configuration des fournisseurs. Dans ce cas, l’ERP indique que la connexion doit être configurée et désactive les boutons OAuth correspondants. Aucun envoi réel ni récupération de boîte n’est possible sans les identifiants d’application et le consentement de l’utilisateur.

## Secrets serveur

Configurer dans les secrets Edge Functions du projet Supabase, jamais dans Git, dans le navigateur ou dans un fichier livré :

| Secret | Valeur attendue |
| --- | --- |
| `COCO_MAIL_ENCRYPTION_KEY` | Clé aléatoire de 32 octets encodée en base64 pour AES-GCM. La conserver pour déchiffrer les connexions existantes. |
| `COCO_GOOGLE_CLIENT_ID` | Identifiant de l’application web Google. |
| `COCO_GOOGLE_CLIENT_SECRET` | Secret de cette application. |
| `COCO_MICROSOFT_CLIENT_ID` | Identifiant de l’application Microsoft. |
| `COCO_MICROSOFT_CLIENT_SECRET` | Valeur du secret Microsoft, pas son identifiant. |

Les fournisseurs sont indépendants : configurer uniquement Gmail suffit pour les utilisateurs Gmail. L’Edge Function réutilise les secrets de plateforme `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` côté serveur.

URI de redirection exacte pour le projet actuel :

`https://mknsaibrewksgomuslev.supabase.co/functions/v1/coco-order-mail/callback`

Origine frontend autorisée : `https://lisciandraj.github.io`. Le retour OAuth est fixé à `https://lisciandraj.github.io/Pro-manager-Gama/`. Une autre origine nécessite une modification explicite du connecteur, pas un paramètre libre envoyé par le navigateur.

## Google

Activer Gmail API dans un projet Google Cloud, configurer l’écran de consentement et créer un client OAuth **Application Web** avec l’URI ci-dessus. Les permissions demandées sont `gmail.send` et `gmail.readonly`. Le flux utilise `access_type=offline`, consentement explicite, PKCE S256 et un état aléatoire à usage unique valable dix minutes. En mode test, ajouter les comptes autorisés ; respecter les règles Google de vérification et de durée des autorisations avant un usage durable ou plus large.

Références : [autorisation côté serveur](https://developers.google.com/workspace/gmail/api/auth/web-server), [envoi MIME](https://developers.google.com/workspace/gmail/api/guides/sending), [association des fils](https://developers.google.com/workspace/gmail/api/guides/threads).

## Microsoft

Créer une inscription d’application prenant en charge les comptes professionnels et personnels si les deux sont nécessaires, ajouter une plateforme **Web**, l’URI ci-dessus et un secret. Permissions déléguées demandées : `User.Read`, `Mail.ReadWrite`, `Mail.Send` et `offline_access`. Les règles du tenant peuvent demander le consentement d’un administrateur.

Le connecteur utilise le flux code avec PKCE, les identifiants immuables des messages, un brouillon enregistré avant l’envoi et `conversationId` pour importer les réponses. Un HTTP 202 est affiché comme accepté, pas comme livré. Les pages de résultats sont limitées au domaine Microsoft Graph et au chemin attendu.

Références : [flux d’autorisation](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow), [création de message](https://learn.microsoft.com/en-us/graph/api/user-post-messages?view=graph-rest-1.0), [envoi](https://learn.microsoft.com/en-us/graph/api/message-send?view=graph-rest-1.0), [lecture des messages](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0).

## Mise en service

1. Appliquer la migration additive `order_followup_mail`, puis déployer `coco-order-mail` avec ses deux dépendances locales et `_shared/http.mjs`. `verify_jwt=false` est nécessaire au callback OAuth ; tous les POST authentifient eux-mêmes l’utilisateur et ses droits. Le GET callback ne traite qu’un état serveur valide à usage unique.
2. Configurer les secrets, puis publier le frontend compilé et vérifié.
3. Depuis une commande, connecter la boîte correspondant à l’adresse du compte ERP. Une autre adresse est refusée ; les alias ne sont pas implicitement autorisés.
4. Pour un essai réel, utiliser des destinataires de test explicitement choisis. Vérifier l’envoi, sa présence dans le journal, la réponse, la déconnexion et les refus pour les profils non autorisés. Les tests automatiques n’envoient jamais de mail réel.

La rotation de la clé de chiffrement nécessite de rechiffrer les jetons ou de reconnecter les utilisateurs. La déconnexion ERP retire les jetons enregistrés ; l’utilisateur peut aussi révoquer l’autorisation dans son compte Google ou Microsoft.
