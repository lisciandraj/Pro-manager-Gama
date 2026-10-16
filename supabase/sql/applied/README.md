# Archives exactes des migrations déjà installées

Ce dossier conserve des copies de référence du SQL enregistré dans l'historique du projet Supabase. Il est distinct de `supabase/migrations/` et n'est pas parcouru par `scripts/restore-schema.cjs` ni `scripts/verify-migrations.cjs`. Il ne constitue pas une liste de migrations à déployer.

## Contacts

La migration [20261015202048_coco_contacts_hub.sql](20261015202048_coco_contacts_hub.sql) est la copie exacte de l'unique élément `statements[1]` associé à la version `20261015202048`, nom `coco_contacts_hub`, dans `supabase_migrations.schema_migrations`. La source a été relue le 16 octobre 2026. Le [manifeste de provenance et d'intégrité](20261015202048_coco_contacts_hub.json) enregistre le projet, les dimensions et les empreintes calculées sur les octets UTF-8.

L'archive ne contient pas d'export des fiches clients, fournisseurs, personnes, factures ou comptes Auth, ni de mot de passe ou clé API. Elle contient le code du schéma, ses règles de migration et ses fonctions. Elle est déjà appliquée dans le projet : **ne pas la rejouer en production, ne pas la renommer comme une nouvelle migration et ne pas l'ajouter automatiquement au déploiement**.

Le fichier `supabase/pending/coco_contacts_hub.sql` reste le brouillon historique utilisé par les tests de développement. Il n'est pas identique au SQL installé. L'archivage présent ne modifie pas ce brouillon ni le registre global `supabase/migration-history.json`. Une réconciliation du parcours de reconstruction nécessitera une intervention séparée avec ses tests ; la présence de cette archive ne signifie pas que cette réconciliation a été réalisée.

## Vérifier sans exécuter le SQL

Depuis la racine du dépôt :

```sh
node --test tests/contact-migration-archive.test.cjs
```

Ce test ne se connecte à aucune base et n'exécute aucun SQL. Il contrôle le nom/version, la taille, l'absence de saut de ligne final, MD5, SHA-256 et le SHA de l'objet Git. La copie a été vérifiée contre SHA-256 `7a13117770a7f57932f6e4c1d3dbde342c6c3d7e062175270d218e240dcb6d79`. Ne pas reformater ce fichier historique : toute modification doit produire une nouvelle migration distincte, pas réécrire cette preuve.
