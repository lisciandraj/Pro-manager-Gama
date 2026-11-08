# Bases de développement et de production

Les bases sont des **projets Supabase distincts** ; un onglet du navigateur ne suffit pas à isoler les données ou les droits.

| Environnement | Projet | Données |
| --- | --- | --- |
| Développement | `mknsaibrewksgomuslev` | Base actuelle conservée intégralement. |
| Production | `vhutzdfatijjpahsqkne` | Nouveau projet, initialisé à partir du schéma versionné, sans copie des utilisateurs, lignes métier, fichiers ou secrets existants. |

La production hérite des définitions de tables, RPC, droits et valeurs de configuration par défaut nécessaires au fonctionnement. Les exemples de flotte et autres lignes de démonstration créés par d'anciennes migrations sont retirés uniquement de la nouvelle base avant activation. Les intégrations privées demandent leur propre configuration ; copier un schéma ne copie pas les secrets de l'ancien projet.

## Contrat serveur

La migration `20261107195941_coco_environment_isolation.sql` crée un marqueur privé **`unassigned`**, sans modifier les lignes métier ni activer la restriction sur la base existante. Une application empaquetée doit vérifier l'identité attendue via `public.coco_environment_status()` avant d'ouvrir les modules. La réponse contient seulement `environment`, `release`, `allowed` et `admin`.

Après affectation à **`development`**, seul un profil actif dont le rôle enregistré en base est `administrador`, avec le niveau MFA requis, peut accéder aux données du développement. Les métadonnées utilisateur modifiables, le navigateur et les clés de stockage local ne donnent aucun droit.

Le contrôle cumule :

- Le hook PostgREST existant `public.coco_agent_request_guard`, renforcé sans retirer le contrôle OAuth d'Agent Coco. Il protège aussi les RPC privilégiées et les vues appelées par l'API.
- Une politique restrictive sur les tables RLS applicatives, Storage et Realtime, afin de couvrir leurs accès directs.
- Le contrôle central `private.current_user_role()` pour les opérations fondées sur le rôle et les Edge Functions qui vérifient d'abord le profil ou une RPC avec le jeton de l'appelant.

`environment_api` contient uniquement les helpers étroits de vérification ; ne pas ajouter ce schéma aux schémas exposés de la Data API. La fonction publique de statut est un invoker. Les fonctions d'affectation et d'installation des politiques ne sont exécutables ni par un navigateur ni par `service_role`. Les clés `service_role` conservent leur privilège de traitement machine existant ; elles ne doivent jamais être publiées côté client. Les buckets du développement doivent rester privés. Une URL signée déjà émise peut rester utilisable jusqu'à son expiration : planifier la bascule après expiration ou révocation des accès temporaires concernés.

## Affectation initiale explicite

Ne pas affecter l'ancienne base au développement avant que la production soit prête et que les intégrations publiques soient retargetées ou suspendues. Le site public/B2B utilise actuellement la même base : la restriction complète du développement refuse aussi ses accès anonymes et clients sur l'ancien projet. Une activation anticipée interromprait ces parcours.

Sur une connexion de maintenance au **projet sélectionné**, vérifier d'abord les migrations et les comptes. Ne jamais employer ces requêtes pour une remise à zéro ou une suppression :

```sql
select environment,release,assigned_at from private.coco_environment;
select count(*) from public.profiles where active and role='administrador';
select count(*) from auth.users;
select count(*) from storage.objects;
select id,public from storage.buckets;
```

La fonction d'affectation exige : le nom attendu, un SHA Git complet de la version de code retenue, le nombre exact de migrations et le nombre exact d'administrateurs actifs. Sur le nouveau projet, le nombre de migrations est celui des sources canoniques inscrites dans `private.coco_bootstrap_sources` par l'amorçage audité ; ailleurs, il est celui de `supabase_migrations.schema_migrations`.

```sql
-- Exemple de forme uniquement : remplacer le SHA et les nombres après lecture.
-- Exécuter dans le nouveau projet pour l'affectation initiale de production.
select private.coco_assign_environment('production', '<sha-git-complet>', <migrations>, <administrateurs>);

-- Exécuter séparément dans l'ancien projet uniquement lors de la bascule revue.
select private.coco_assign_environment('development', '<sha-git-complet>', <migrations>, <administrateurs>);
```

Les valeurs d'exemple ne sont pas exécutables. L'affectation est refusée si le marqueur a déjà été affecté, si les nombres divergent, si aucun administrateur actif n'existe en développement ou si un bucket est public. La première affectation de production refuse les lignes métier, fichiers et comptes hors administrateurs de bootstrap ; seule une liste explicite de configuration par défaut est admise. Aucun compte ni aucune donnée n'est supprimé automatiquement par cette fonction.

Après affectation, vérifier le statut avec un compte administrateur et un compte non administrateur. Confirmer le refus de l'API, des RPC, de Storage et de Realtime dans le développement ; confirmer que les droits normaux de production restent ceux de chaque module. Ne pas déduire cette vérification de la visibilité du menu.

## Évolutions et publication

Toutes les modifications de code et migrations se préparent en développement. Un changement ne doit rejoindre la production qu'avec la version précise testée et l'autorisation explicite du propriétaire ; les données de test ne sont jamais un artefact de promotion. La publication du frontend et le déploiement des migrations/Edge Functions sont des opérations distinctes. Une mise à jour de code ne remplace ni ne réinitialise la base de production.

Une nouvelle table exposée doit activer RLS et recevoir les politiques existantes du module ainsi que la politique d'environnement. Une nouvelle migration peut appeler `private.coco_install_environment_policies()` depuis la connexion de maintenance ; cette fonction ne confère aucun droit de table. Vérifier les RPC privilégiées, les services avec clé machine et les buckets ajoutés avant de promouvoir une version.

## Vérifications isolées

```sh
node --test tests/database-environment-db.test.cjs
npm run verify:migrations
```

Ces tests reconstruisent une base PGlite jetable, sans connexion aux projets réels. Ils vérifient le marqueur inactif, les accès admin/commercial/anon, le refus de rôles falsifiés dans les métadonnées utilisateur, MFA, les tables et Storage, les RPC et le hook, les privilèges machine explicites et les préconditions de l'affectation initiale. Les services hébergés (Auth, réseau, liens signés et Realtime) demandent aussi des contrôles sur les projets déployés.
