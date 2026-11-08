# Publication compilée de Coco ERP

GitHub Pages publie un artefact contenant deux instantanés indépendants :

- `/production/` sert la version approuvée de la branche `production`.
- `/development/` sert la version testée de la branche `development`.
- L’adresse historique de Coco ERP ouvre `/production/`.

L’activation de cette organisation nécessite la fusion de sa configuration initiale, une branche `development`, une branche `production` contenant le nouveau démarrage et **Source = GitHub Actions** dans les réglages Pages du dépôt. Une pull request prépare et teste les changements sans publier. La création d’un commit ou d’une PR ne prouve pas que le site a été actualisé.

## Construction et isolation

`deploy-coco-pages.yml` conserve les contrôles de construction, les tests SQL isolés et les parcours navigateur existants. Après leur réussite, il assemble les deux environnements avec `scripts/package-environments.cjs`. Les jobs de construction ont `contents: read`. Le job de publication possède seulement `pages: write` et `id-token: write`, dans l’environnement `github-pages`.

Chaque environnement conserve son HTML, ses scripts, ses styles, son manifeste, son démarrage public Supabase et son cache de service worker sous son propre chemin. Le service worker historique de la racine est retiré ; les caches des sous-environnements sont conservés. La configuration publique est préfixée au script existant `coco-environment.js`, sans requête de démarrage supplémentaire, et ses empreintes sont recalculées. `coco-environment-config.js` reste disponible pour les diagnostics et la préparation hors connexion. La CSP autorise uniquement le projet Supabase de l’environnement concerné.

Le code et la configuration de production viennent de la branche `production`, avec son propre verrouillage de dépendances. Son artefact est préparé avec le script de publication de cette version approuvée puis recopié sans modification ; les empreintes de `coco-release.json` sont revérifiées. Une modification du code, de la configuration ou du script de publication en développement ne réécrit donc pas l’instantané de production.

Avant tout assemblage, `scripts/check-environment-readiness.mjs` appelle uniquement la RPC publique `coco_environment_status`, sans session utilisateur, sur le backend de développement courant et celui de l’instantané de production approuvé. Le serveur de production doit annoncer `production` et autoriser l’accès anonyme ; le serveur de développement doit annoncer `development` et refuser cet accès. Une configuration absente, des bases identiques, un marqueur incorrect ou une RPC indisponible bloque la publication avant le téléversement. Ce contrôle ne migre ni n’active les bases ; leurs marqueurs doivent être affectés après leur préparation et les bascules des services publics.

`config/erp-environments.json` contient uniquement des URL et des clés publiques. La configuration `production: null` bloque toute connexion de production : elle ne peut jamais reprendre l’URL ou les données du développement. Il faut un projet de production distinct, son schéma et ses contrôles d’accès avant la mise en service. La publication web ne copie aucune ligne métier, aucun compte, fichier, secret ou fonction Edge et n’exécute aucune migration distante.

## Mises à jour et autorisation

Les changements suivants sont poussés sur `development`. Sa CI reconstruit `/development/` tout en conservant l’instantané approuvé de `/production/`. `main` reste accepté pour l’installation initiale et la compatibilité des contrôles ; il ne détermine pas la version de production.

Après ses tests, le propriétaire lance **Approve Coco production release** depuis la branche `development`, renseigne le SHA complet testé et saisit exactement `AUTORISER PRODUCTION`. Le workflow refuse :

- un nom de branche ou un SHA extérieur à l’historique de développement ;
- une révision sans validation de release réussie sur ce SHA exact ;
- une révision sans réussite des trois contrôles `build`, `topbar-menus` et `business-modules` ;
- une mise à jour qui réécrirait l’historique de la branche de production.

L’approbation crée une étiquette immuable `production/<date>-<sha>`, déplace la branche `production` puis demande une nouvelle publication Pages. La version précédente reste accessible dans Git et dans le résumé du workflow. L’étiquette atteste la version approuvée ; le résultat du workflow Pages atteste sa publication effective. L’environnement GitHub `production` peut en plus recevoir des réviseurs obligatoires dans les réglages du dépôt.

Le versionnement décrit ici porte sur le code et la configuration. Les sauvegardes, restaurations et migrations des bases restent des opérations séparées, à tester puis autoriser explicitement pour la production. Un retour arrière passe par un nouveau commit testé, sans effacer les anciennes versions.

### Préparation de la première correction MFA

Le mode normal `development` accepte un SHA exact, testé et appartenant à l’historique de développement ; il ne doit pas nécessairement être sa dernière révision. Le propriétaire peut ainsi conserver des travaux plus récents non approuvés en développement. Ses contrôles d’autorisation, de CI, de version et d’avance sans réécriture restent inchangés.

Le mode manuel distinct `initial-mfa-bootstrap` prépare une seule exception : le commit `8c465ace2b042161eed8f2c25e080c736ce836c0`, issu directement de la production initiale `20272ccbd040a5a00b32d6632ba8ad9eb1b72481`. Il contient uniquement les sept fichiers de la correction MFA examinée dans la PR 291, sans les évolutions Contacts, Openhub ou de palette conservées en développement. Le workflow exige le même propriétaire et la saisie `AUTORISER PRODUCTION`, puis vérifie les parents, l’arbre, les sept chemins et leurs empreintes, l’arbre de fusion réellement testé, et les cinq plus trois contrôles réussis des exécutions fixées `42500077618` et `42500077596`. Aucun SHA de remplacement n’est accepté.

Cette préparation ne constitue pas une autorisation de promouvoir ce code. Après les tests et l’autorisation explicite du propriétaire seulement, le workflow pourra créer l’étiquette immuable `production/initial-mfa-8c465ace2b042161eed8f2c25e080c736ce836c0`, puis avancer la production sans forcer. Une production déjà égale à ce candidat permet de reprendre une publication interrompue ; toute autre version que la base initiale ou ce candidat bloque le mode. GitHub ne permet pas de modifier ces deux références en une transaction : une interruption peut laisser l’étiquette créée avant l’avance de production. Une reprise vérifie et réutilise uniquement l’étiquette correspondant exactement au candidat, sans la déplacer et sans annuler une production ultérieure.

Ce mode ne modifie ni schéma, données, comptes Auth, configuration Cloudflare, ni préparation SQL figée à 362 sources. Il peut relancer la publication Pages existante ; la vérification des marqueurs réels des backends demeure obligatoire et peut encore bloquer le déploiement avant l’activation coordonnée.

## Vérifier la version servie

Après le déploiement, le workflow contrôle :

- `coco-build.json` à la racine : SHA du développement et SHA approuvé de production ;
- `production/coco-build.json` et `development/coco-build.json` : environnement et commit correspondant ;
- la configuration publique et les actifs commerciaux réellement servis.

Chaque dossier publie aussi `coco-release.json`, qui associe les actifs à leurs empreintes SHA-256. Ne pas annoncer une publication sur la seule base d’une compilation ou de fichiers générés présents dans le dépôt. Les scripts racine historiques restent des sorties compatibles ; les sources canoniques se trouvent dans `src/`.
