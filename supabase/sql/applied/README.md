# Manifestes et archives des migrations installées

Ce dossier conserve la provenance et les empreintes des migrations effectivement installées. Le SQL de référence n'est pas une file de déploiement. `scripts/verify-migrations.cjs` lit aussi ces manifestes lorsqu'un fichier portant le même nom existe dans `supabase/migrations`, et refuse toute différence d'empreinte.

La [migration Contacts du 15 octobre](20261015202048_coco_contacts_hub.sql) reste une archive exacte, sans modification de ses octets. Une copie byte-identique a été ajoutée au parcours de reconstruction. L'ancien fichier `supabase/pending/coco_contacts_hub.sql` reste un brouillon de test historique, pas la source installée. Le [manifeste d'alignement](20261016160823_coco_contact_alignment.json) protège la migration additionnelle du 16 octobre, dont le SQL se trouve dans `supabase/migrations`.

Aucun fichier de ce dossier ne contient d'export de clients, fournisseurs, factures ou comptes Auth. Ne jamais rejouer une migration déjà enregistrée dans l'historique de production et ne pas renommer un ancien SQL pour le présenter comme une nouvelle migration.

Contrôles locaux sans connexion à la production :

```sh
npm run verify:migrations
node --test tests/contact-migration-archive.test.cjs tests/contact-alignment.test.cjs
```

Le premier test vérifie l'intégrité de l'archive sans exécuter de SQL. Le second reconstruit un environnement PGlite isolé et vérifie les transactions d'alignement. Les fonctions de plateforme Supabase nécessitent toujours leurs propres essais d'intégration.
