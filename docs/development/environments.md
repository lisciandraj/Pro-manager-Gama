# Environnements de Coco ERP

## Organisation

| Environnement | Code | Base Supabase | Accès |
| --- | --- | --- | --- |
| Développement | Branche `development`, historique Git conservé | `mknsaibrewksgomuslev`, avec les données actuelles | Profil administrateur actif, vérifié par le serveur |
| Production | Instantané approuvé de la branche `production` et étiquette de version | `vhutzdfatijjpahsqkne`, projet distinct | Utilisateurs autorisés de production, selon leurs droits |

Le menu principal permet de passer d’un environnement à l’autre. Le lien Développement est réservé aux administrateurs vérifiés. Le serveur contrôle aussi l’accès aux données ; saisir manuellement une URL de développement ne donne aucun droit supplémentaire.

Les fichiers de production et de développement sont servis respectivement sous `/production/` et `/development/`. La racine ouvre la production. Chaque dossier conserve ses propres actifs et son cache. Les sauvegardes hors connexion de production sont séparées des anciens fichiers de développement. Les clés de compatibilité historiques sont conservées dans le développement.

Le démarrage attend `coco_environment_status` sur le backend sélectionné. Un environnement incorrect, une configuration absente ou un accès administrateur refusé bloque les lectures métier. Aucune URL de production manquante ne provoque de reprise automatique vers l’ancienne base.

## État de préparation — 7 novembre 2026

Le code de séparation et les contrôles ciblés sont prêts. Le projet Production est créé au tarif annoncé de 0 $/mois, et ses 13 fonctions Edge sont déployées sans copier les secrets ni les comptes de développement. L’installation SQL hébergée reste incomplète : les appels d’import volumineux restent en attente avant exécution ; seule la préparation technique initiale a été confirmée. La base actuelle n’a reçu aucune migration d’environnement et son verrou administrateur n’est pas activé.

La publication Pages des deux instantanés, la bascule du catalogue public vers la production vide (autorisée par le propriétaire) et l’affectation des marqueurs restent à exécuter après installation et vérification du schéma. Ne pas présenter les nouveaux onglets comme déjà disponibles sur le site existant. Le premier compte administrateur Production reste à créer par un parcours sécurisé ; aucune invitation n’a été envoyée.

Les builds, les contrôles de sources, types, dépendances locales, migrations et budgets ainsi que les tests ciblés de navigation, connexion, portail, catalogue, stockage et droits passent. La suite unitaire complète locale a été interrompue après le blocage de deux helpers Python préexistants (`accounting-export`, `marketing-mail`) ; elle n’est pas annoncée réussie. Les contrôles complets de CI restent requis avant publication.

## Installation initiale

Le projet de production est créé séparément ; les données métier de la base actuelle restent en développement. Installer le schéma compatible, les règles d’accès, les comptes autorisés et les fonctions réellement nécessaires sur le nouveau projet. Les intégrations externes et leurs secrets restent des configurations indépendantes ; ne pas les copier à partir de la base de développement.

La mise en service nécessite aussi les branches `development` et `production`, une CI réussie pour le code retenu, la source Pages **GitHub Actions** et la vérification des marqueurs servis. Un commit ou une PR préparée ne suffit pas à rendre la séparation effective en ligne. Le résultat des migrations et les vérifications d’accès doivent être établis avant d’annoncer la production utilisable.

## Modifications suivantes

Modifier le développement, y compris les migrations et fonctions serveur. Conserver les données de chaque environnement dans leur base. Après les tests et l’autorisation explicite du propriétaire, promouvoir le SHA exact avec **Approve Coco production release**, puis vérifier la publication. Chaque promotion conserve sa version précédente et crée une nouvelle étiquette immuable.

La publication du site ne déploie aucune fonction Edge, n’exécute aucune migration distante et ne copie aucune donnée métier. Une évolution du schéma ou d’une intégration en production doit avoir sa propre préparation testée et son autorisation.

Voir [la publication et les contrôles de promotion](pages-publication.md) pour les étapes, les fichiers de version et les détails de l’assemblage. L’historique Git versionne le code ; il ne remplace pas une sauvegarde de base de données.
