# Environnements de Coco ERP

## Organisation

| Environnement | Code | Base Supabase | Accès |
| --- | --- | --- | --- |
| Développement | Branche `development`, historique Git conservé | `mknsaibrewksgomuslev`, avec les données actuelles | Profil administrateur actif, vérifié par le serveur |
| Production | Instantané approuvé de la branche `production` et étiquette de version | `vhutzdfatijjpahsqkne`, projet distinct | Utilisateurs autorisés de production, selon leurs droits |

Le menu principal permet de passer d’un environnement à l’autre. Le lien Développement est réservé aux administrateurs vérifiés. Le serveur contrôle aussi l’accès aux données ; saisir manuellement une URL de développement ne donne aucun droit supplémentaire.

Les fichiers de production et de développement sont servis respectivement sous `/production/` et `/development/`. La racine ouvre la production. Chaque dossier conserve ses propres actifs et son cache. Les sauvegardes hors connexion de production sont séparées des anciens fichiers de développement. Les clés de compatibilité historiques sont conservées dans le développement.

Le démarrage attend `coco_environment_status` sur le backend sélectionné. Un environnement incorrect, une configuration absente ou un accès administrateur refusé bloque les lectures métier. Aucune URL de production manquante ne provoque de reprise automatique vers l’ancienne base.

## État de préparation — 8 novembre 2026

La première mise en service reste en attente. La branche `production` demeure figée à `20272ccbd040a5a00b32d6632ba8ad9eb1b72481` ; les évolutions suivantes restent en développement.

La correction MFA initiale est isolée dans le candidat `8c465ace2b042161eed8f2c25e080c736ce836c0`, examiné dans la [PR 291](https://github.com/lisciandraj/Pro-manager-Gama/pull/291). Seuls ses sept fichiers MFA diffèrent de la production initiale. Les cinq jobs de [validation de release](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42500077618) et les trois jobs de validation [Pages](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42500077596) réussissent pour ce candidat. Ces contrôles ne constituent ni une promotion ni un déploiement de production.

Le workflow manuel conserve la promotion normale d’un SHA exact, testé et appartenant à l’historique de développement, même si des travaux plus récents y sont présents. La promotion nécessite toujours l’autorisation explicite du propriétaire et conserve une version immuable. Le mode initial MFA est limité au candidat examiné et à sa base de production ; il ne permet pas de sélectionner une autre correction. Les évolutions Contacts, Openhub et de palette restent en développement.

La vérification des backends et de leurs droits, du catalogue public et de l’accès client, du parcours administrateur et des versions réellement servies doit être terminée avant la première mise en service. La préparation du code et la réussite des contrôles CI ne suffisent pas à annoncer les nouveaux environnements disponibles en ligne.

## Installation initiale

Le projet de production est créé séparément ; les données métier de la base actuelle restent en développement. Installer le schéma compatible, les règles d’accès, les comptes autorisés et les fonctions réellement nécessaires sur le nouveau projet. Les intégrations externes et leurs secrets restent des configurations indépendantes ; ne pas les copier à partir de la base de développement.

La mise en service nécessite aussi les branches `development` et `production`, une CI réussie pour le code retenu, la source Pages **GitHub Actions** et la vérification des marqueurs servis. Un commit ou une PR préparée ne suffit pas à rendre la séparation effective en ligne. Le résultat des migrations et les vérifications d’accès doivent être établis avant d’annoncer la production utilisable.

## Modifications suivantes

Modifier le développement, y compris les migrations et fonctions serveur. Conserver les données de chaque environnement dans leur base. Après les tests et l’autorisation explicite du propriétaire, promouvoir le SHA exact avec **Approve Coco production release**, puis vérifier la publication. Chaque promotion conserve sa version précédente et crée une nouvelle étiquette immuable.

La publication du site ne déploie aucune fonction Edge, n’exécute aucune migration distante et ne copie aucune donnée métier. Une évolution du schéma ou d’une intégration en production doit avoir sa propre préparation testée et son autorisation.

Voir [la publication et les contrôles de promotion](pages-publication.md) pour les étapes, les fichiers de version et les détails de l’assemblage. L’historique Git versionne le code ; il ne remplace pas une sauvegarde de base de données.
