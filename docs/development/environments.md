# Environnements de Coco ERP

## Organisation

| Environnement | Code | Base Supabase | Accès |
| --- | --- | --- | --- |
| Développement | Branche `development`, historique Git conservé | `mknsaibrewksgomuslev`, avec les données actuelles | Profil administrateur actif, vérifié par le serveur |
| Production | Instantané approuvé de la branche `production` et étiquette de version | `vhutzdfatijjpahsqkne`, projet distinct | Utilisateurs autorisés de production, selon leurs droits |

La barre latérale affiche l’environnement actif et propose un bouton pour ouvrir l’autre environnement. Sur mobile, ouvrir **Plus** pour y accéder. Depuis la production, seuls les administrateurs actifs vérifiés par le serveur voient le bouton vers le développement. Le navigateur ouvre la version de destination, qui applique ses propres droits d’accès.

Les fichiers de production et de développement sont servis respectivement sous `/production/` et `/development/`. La racine ouvre la production. Chaque dossier conserve ses propres actifs et son cache. Les sauvegardes hors connexion de production sont séparées des anciens fichiers de développement. Les clés de compatibilité historiques sont conservées dans le développement.

Le démarrage attend `coco_environment_status` sur le backend sélectionné. Un environnement incorrect, une configuration absente ou un accès administrateur refusé bloque les lectures métier. Aucune URL de production manquante ne provoque de reprise automatique vers l’ancienne base.

## Connexion commune

Le projet historique reste l’autorité d’identité. Les deux versions réutilisent sa session Supabase Auth quand leurs configurations approuvées activent `sharedIdentity`. La version Production utilise le jeton de cette session pour son API métier, sur son propre projet. Le stockage du jeton est commun à l’origine web de Coco. Préférences, brouillons, sauvegardes et caches restent rattachés à leur environnement.

L’activation nécessite la découverte OpenID Connect de l’autorité et sa clé de signature asymétrique, l’intégration Custom OIDC sur le projet Production et une correspondance entre les identités externes et les droits locaux. Le contrôle Pages exige que les deux réponses `coco_environment_status` attestent le même `identity_issuer`. Avant la publication, tester avec des sessions réelles la connexion, le MFA, la révocation, le refus des profils sans accès et les écritures métier. Les références de dossier vers les utilisateurs et les fonctions qui consultent Auth font partie de la validation serveur.

Les administrateurs existants gardent leur identifiant Auth. La Production enregistre leurs droits sur cet identifiant et exige le facteur MFA de l’autorité. Les comptes et les facteurs sont administrés dans le projet d’identité. Le schéma, le déroulement de la bascule et les contrôles sont décrits dans [le guide des bases Supabase](../../supabase/ENVIRONMENTS.md#identité-commune-et-autorisations-locales).

## État de préparation — 8 novembre 2026

La première mise en service reste en attente. La branche `production` demeure figée à `20272ccbd040a5a00b32d6632ba8ad9eb1b72481` ; les évolutions suivantes restent en développement.

La correction MFA initiale est isolée dans le candidat `8c465ace2b042161eed8f2c25e080c736ce836c0`, examiné dans la [PR 291](https://github.com/lisciandraj/Pro-manager-Gama/pull/291). Seuls ses sept fichiers MFA diffèrent de la production initiale. Les cinq jobs de [validation de release](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42500077618) et les trois jobs de validation [Pages](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/42500077596) réussissent pour ce candidat. Ces contrôles ne constituent ni une promotion ni un déploiement de production.

Le workflow manuel conserve la promotion normale d’un SHA exact, testé et appartenant à l’historique de développement, même si des travaux plus récents y sont présents. La promotion nécessite toujours l’autorisation explicite du propriétaire et conserve une version immuable. Le mode initial MFA est limité au candidat examiné et à sa base de production ; il ne permet pas de sélectionner une autre correction. Les évolutions Contacts, Openhub et de palette restent en développement.

La vérification des backends et de leurs droits, du catalogue public et de l’accès client, du parcours administrateur et des versions réellement servies doit être terminée avant la première mise en service. La préparation du code et la réussite des contrôles CI ne suffisent pas à annoncer les nouveaux environnements disponibles en ligne.

## Installation initiale

Le projet de production est créé séparément. Les données métier de la base actuelle restent en développement. Installer le schéma compatible, les règles d’accès, les profils d’autorisation et les fonctions réellement nécessaires sur le nouveau projet. Les intégrations externes et leurs secrets ont leur propre configuration.

La mise en service nécessite aussi les branches `development` et `production`, une CI réussie pour le code retenu, la source Pages **GitHub Actions** et la vérification des marqueurs servis. Un commit ou une PR préparée ne suffit pas à rendre la séparation effective en ligne. Le résultat des migrations et les vérifications d’accès doivent être établis avant d’annoncer la production utilisable.

## Modifications suivantes

Modifier le développement, y compris les migrations et fonctions serveur. Conserver les données de chaque environnement dans leur base. Après les tests et l’autorisation explicite du propriétaire, promouvoir le SHA exact avec **Approve Coco production release**, puis vérifier la publication. Chaque promotion conserve sa version précédente et crée une nouvelle étiquette immuable.

La publication du site ne déploie aucune fonction Edge, n’exécute aucune migration distante et ne copie aucune donnée métier. Une évolution du schéma ou d’une intégration en production doit avoir sa propre préparation testée et son autorisation.

Voir [la publication et les contrôles de promotion](pages-publication.md) pour les étapes, les fichiers de version et les détails de l’assemblage. L’historique Git versionne le code ; il ne remplace pas une sauvegarde de base de données.
