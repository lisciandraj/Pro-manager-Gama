# Historique et reconstruction de la base

`migrations/` est l'historique SQL réellement appliqué au projet, suivi des nouvelles migrations du dépôt. `migration-history.json` conserve les versions, noms et empreintes SHA-256 de la capture. `npm run verify:migrations` refuse la modification d'une migration déjà appliquée.

`legacy-migrations/` archive les anciens fichiers incomplets ou portant des horodatages différents. Ils restent utiles aux tests historiques ciblés ; **ce dossier n'est jamais une source de déploiement**. Les changements futurs se font par une nouvelle migration dans `migrations/`.

## Vérification locale sans accès à la production

```sh
npm ci
npm run verify:migrations
npm run test:restore
npm run test:unit
```

La reconstruction PGlite fournit les primitives de plateforme Auth, Storage et Cron décrites dans `tests/platform-bootstrap.sql`, puis rejoue l'historique applicatif. Elle vérifie les tables publiques et leur activation RLS selon les assertions de la suite `npm run test:restore`. Les nombres de tables évoluent avec les migrations. Elle ne remplace pas un test d'intégration sur Supabase pour les services de plateforme, le réseau ou Realtime.

Une réparation de données historique, `20260912081917_deduplicate_products_keep_most_complete.sql`, exige exactement 312 doublons dans 165 groupes de production. Elle ne peut pas être rejouée telle quelle sur une base vide. Le SQL canonique demeure inchangé. `scripts/fresh-migration.cjs` conserve sa création de table d'archive, exige un catalogue vide et exclut seulement la réparation de ces anciennes données lors d'une reconstruction neuve.

## Préparer une instance Supabase locale neuve

```sh
npx supabase init --workdir .build/fresh-database
node scripts/prepare-fresh-database.cjs
npx supabase start --workdir .build/fresh-database
npx supabase db reset --local --workdir .build/fresh-database
```

Ces commandes ciblent uniquement l'instance locale jetable. Ne pas lier ce répertoire dérivé au projet de production et ne pas pousser ses migrations avec `db push`. L'historique dérivé contient une adaptation réservée au démarrage à vide. Son exécution avec Docker/Supabase CLI est distincte du test PGlite automatisé.

La table temporaire `products_photo_backup_20260907`, présente dans l'historique mais déjà absente en production, est réconciliée par une migration qui refuse de supprimer une sauvegarde non vide.

## Contrats d'écriture

- Les RPC publiques et leurs contrôles de rôles restent les frontières serveur.
- Comptabilité, flotte et retours délèguent à des fonctions privées nommées par responsabilité ; les anciennes chaînes `action2/3/4` sont retirées.
- `gama_legacy_quote_save` crée l'en-tête et les lignes dans une transaction, recalcule les montants et protège les nouvelles tentatives par `request_key` et acteur.
- Les reçus d'idempotence restent dans `private.command_receipts`, sans lecture directe par le navigateur.
- Les nouveaux contrats TypeScript proviennent du schéma public réel : `src/data/database.types.ts`. Les adaptateurs applicatifs se trouvent dans `src/domain/`.

Les tests `standardization-db.test.cjs` comparent les résultats et refus des actions avant et après réorganisation, et vérifient annulation transactionnelle, permissions et idempotence des devis.

## Lecture des avis Supabase

Le relevé du 30 septembre 2026 signale 16 tables privées avec RLS sans politique (refus par défaut), la protection des mots de passe compromis désactivée et des pistes de performance. Ces constats, leurs volumes et les vérifications nécessaires sont détaillés dans [l’audit courant](../docs/audits/2026-09-30.md). Une alerte historique sur une vue ou une fonction ne doit pas être présentée comme toujours active sans un nouveau relevé. Ne pas supprimer une politique ou changer SECURITY DEFINER/INVOKER sans tests des accès correspondants.

## Modèle d'e-mail d'invitation (Supabase Auth)

L'e-mail de création d'accès est personnalisable dans **Utilisateurs → E-mail d'invitation** (objet et message avec `{nombre}`, `{empresa}`, `{rol}`, `{correo}`, table `access_invitation_template`) et retouchable à chaque invitation. La fonction `architect-user-admin` transmet le texte final à Supabase Auth dans les métadonnées de l'invité (`invite_subject`, `invite_message`, `company_name`).

Supabase n'affiche ces champs que si son modèle « Invite user » les utilise. Réglage à faire une fois dans le tableau de bord du projet (Authentication → Emails → Invite user) :

- **Subject** : `{{ if .Data.invite_subject }}{{ .Data.invite_subject }}{{ else }}Tu acceso a Coco ERP{{ end }}`
- **Body** : le contenu de [`templates/invite.html`](templates/invite.html).

Sans ce réglage, les invitations partent toujours, avec le modèle Supabase par défaut.
