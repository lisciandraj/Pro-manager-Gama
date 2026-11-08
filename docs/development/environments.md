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

Le code de séparation est versionné dans `development`. Le commit `d46a11bc16d306777d1e6fb166f8d073b24770be` conserve les modifications de `main` jusqu’à `18789706`. La branche `production` reste figée au candidat initial `20272ccbd040a5a00b32d6632ba8ad9eb1b72481` ; aucune mise à jour ultérieure de développement ne lui a été transmise.

La [validation complète de ce commit](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42480867415) réussit : 814 tests unitaires réussis, aucun échec et 2 ignorés. Les trois étapes de validation de [Pages](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42480867438) réussissent également. L’assemblage est volontairement arrêté par le contrôle de disponibilité : le RPC de production renvoie encore HTTP 404. Aucun déploiement n’a eu lieu.

Le projet Production distinct est créé au tarif annoncé de 0 $/mois. Ses 13 fonctions Edge sont déployées sans copier les secrets ni les comptes de développement. L’installation du schéma reste à **77 sources canoniques sur 362**. Le dernier contrôle confirme **0 compte Auth et 0 fichier Storage**. Les migrations restantes sont préparées avec vérification de l’identité du projet, des empreintes des sources et de l’absence de données métier avant chaque lot. Leur exécution via le connecteur Supabase renvoie une confirmation expirée, malgré l’autorisation explicite du propriétaire pour ces seules migrations de structure.

La préparation des [lots SQL gardés](https://github.com/lisciandraj/Pro-manager-Gama/tree/maintenance/coco-production-sql-20261108/maintenance/production-bootstrap) a [réussi](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42480220762). Cette tâche prépare et versionne uniquement les sources : elle n’a aucun accès à la base et n’effectue aucun déploiement. Ne pas réexécuter la préparation initiale ; reprendre au compteur réel et vérifier chaque empreinte.

La base actuelle n’a reçu aucune migration d’environnement et son verrou administrateur n’est pas activé. Le catalogue public et l’accès client utilisent encore son backend. La connexion Cloudflare relance l’authentification sans permettre la lecture du compte ; leur bascule autorisée vers la production vide reste donc bloquée. Ne pas restreindre l’ancienne base avant cette bascule vérifiée.

La publication Pages des deux instantanés et l’affectation des marqueurs restent à exécuter après installation et vérification du schéma. Les nouveaux onglets ne sont pas encore disponibles sur le site existant. Le premier compte administrateur Production reste à créer par un parcours sécurisé ; aucune invitation n’a été envoyée.

## Installation initiale

Le projet de production est créé séparément ; les données métier de la base actuelle restent en développement. Installer le schéma compatible, les règles d’accès, les comptes autorisés et les fonctions réellement nécessaires sur le nouveau projet. Les intégrations externes et leurs secrets restent des configurations indépendantes ; ne pas les copier à partir de la base de développement.

La mise en service nécessite aussi les branches `development` et `production`, une CI réussie pour le code retenu, la source Pages **GitHub Actions** et la vérification des marqueurs servis. Un commit ou une PR préparée ne suffit pas à rendre la séparation effective en ligne. Le résultat des migrations et les vérifications d’accès doivent être établis avant d’annoncer la production utilisable.

## Modifications suivantes

Modifier le développement, y compris les migrations et fonctions serveur. Conserver les données de chaque environnement dans leur base. Après les tests et l’autorisation explicite du propriétaire, promouvoir le SHA exact avec **Approve Coco production release**, puis vérifier la publication. Chaque promotion conserve sa version précédente et crée une nouvelle étiquette immuable.

La publication du site ne déploie aucune fonction Edge, n’exécute aucune migration distante et ne copie aucune donnée métier. Une évolution du schéma ou d’une intégration en production doit avoir sa propre préparation testée et son autorisation.

Voir [la publication et les contrôles de promotion](pages-publication.md) pour les étapes, les fichiers de version et les détails de l’assemblage. L’historique Git versionne le code ; il ne remplace pas une sauvegarde de base de données.
