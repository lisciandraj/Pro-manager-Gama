# Récupération technique du bootstrap arrêté à 306 sources

Ce dossier est une proposition locale, limitée à l'installation neuve `vhutzdfatijjpahsqkne`. Il ne doit jamais être exécuté sur le Développement `mknsaibrewksgomuslev`, une installation déjà affectée, ou une production contenant des utilisateurs ou des données métier.

Le cron `coco-automation`, créé par le source 252, a fonctionné pendant la reconstruction longue. Les deux règles de contrôle activées par défaut ont créé trois reçus de contrôles sans résultat métier : `finance_checks` et `operating_checks` à `2026-11-08T15:18:00.122638+00`, puis `operating_checks` à `2026-11-08T15:20:00.04248+00`.

## Conditions et contenu du SQL

`cleanup.sql` vérifie l'identité et l'empreinte de la nouvelle installation, le nombre exact de 306 sources et les empreintes originales et dérivées de ce préfixe. La table d'environnement doit être absente ; Auth, les profils et Storage doivent être vides.

La pause de l'unique cron attendu doit être **déjà validée dans une transaction distincte** : même nom, base, commande et expression de planification, `active=false`. Le fichier ne suspend ni n'exécute de tâche. Il refuse un traitement encore actif, avant et après les verrous du planificateur et des tables concernées.

Les trois jobs doivent correspondre aux trois types et horodatages observés, aux versions 1 des règles inchangées, aux clés calculées de planification, au payload `{}`, sans acteur ni source, avec un seul succès sans erreur, sans bail, et avec un résultat limité à un compteur zéro et son horodatage. Chaque job doit avoir exactement sa tentative réussie correspondante. Tout autre enregistrement dans une table métier, historique, boîte d'envoi, exception, contexte ou lien fait échouer le SQL.

Après cette classification complète, les UUID sont figés sous verrou dans une table temporaire. Le SQL supprime uniquement les trois tentatives liées à ces UUID puis les trois jobs ; il exige trois suppressions pour chaque instruction. Le scan intégral habituel des tables métier est répété après les suppressions, sans exception pour les tables d'automatisation. Aucun UUID généré n'est inscrit dans le fichier.

Les tables de configuration conservent strictement la liste autorisée par la migration finale d'environnement. Le garde normal du bootstrap et les historiques métier restent inchangés. L'exécution distante éventuelle doit passer par une migration technique nommée, afin que son SQL et son résultat figurent dans le journal de migration. Il n'y a aucune mutation métier à attribuer artificiellement à un utilisateur.

## Recette d'exécution autorisée

1. Confirmer par lecture la pause déjà validée et l'absence d'exécution en cours. Conserver le relevé des trois signatures et les décomptes des autres tables.
2. Examiner `cleanup.sql` et `manifest.json`. Appliquer le fichier intégral via l'outil normal de migration, avec les contrôles habituels. En cas d'écart, arrêter et analyser ; ne pas modifier les compteurs ni élargir les exceptions pour forcer une reprise.
3. Confirmer le reçu retourné : trois jobs et trois tentatives supprimés, cron toujours suspendu, aucune donnée métier ou autre trace runtime.
4. Reprendre les sources 307 à 362 avec les gardes existants, puis exécuter la vérification finale uniquement en lecture.
5. Conserver le cron suspendu jusqu'à la vérification et l'affectation autorisée de l'environnement. Restaurer ensuite uniquement son état actif antérieur, en conservant sa commande et son horaire. Les automatismes métier avec délégation restent soumis à leur configuration et aux autorisations applicables.

Ce SQL n'est pas réutilisable : une nouvelle exécution échoue sur les compteurs. De nouveaux jobs, horodatages, résultats ou données imprévus exigent une nouvelle analyse bornée.

## Vérification locale isolée

```sh
node /workspace/scratch/coco-runtime-cleanup/prepare.cjs
node /workspace/scratch/coco-runtime-cleanup/recovery.test.cjs
```

Le programme de préparation ne fait que lire les sources canoniques et écrire ces artefacts locaux. Le test utilise uniquement PGlite et les services de plateforme simulés ; il ne contacte aucun serveur et n'envoie aucun message. Il reconstruit 306 sources, appelle le vrai planificateur local pour reproduire la création des reçus, puis associe explicitement les horodatages observés à ces fixtures. Il prouve que le garde normal bloque ces traces, vérifie les refus face aux écarts, exécute la récupération locale, reconstruit les 56 sources restantes et exige la vérification finale complète. Les anciennes migrations restent intactes.
