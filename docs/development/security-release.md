# Livraison sécurisée et provenance

Le workflow Pages exige désormais les jobs `build`, `topbar-menus`, `business-modules`, `release-validation` et `secret-scan` de la **même exécution et révision**. `release-validation` appelle le workflow de validation existant : audit npm, contrôles unitaires, frontières navigateur/B2B, concurrence PostgreSQL et service fiscal sont conservés. La validation indépendante déjà déclenchée sur PR/main reste disponible pour les contrôles de branche existants.

Le job de promotion relit le manifeste produit par le job de construction et refuse une révision différente, un checkout marqué modifié, ou un résultat absent, ignoré, annulé ou en échec. Une PR ne déploie pas. Le contrôle HTTP du serveur déployé a été déplacé après la publication ; les tests d'une PR ne sondent donc plus le serveur de production.

`secret-scan` récupère l'historique complet disponible et exécute Gitleaks sur `--all`, y compris pour une publication manuelle. Le binaire officiel est versionné et son archive est vérifiée par une empreinte conservée dans Git ; les résultats sont masqués et aucun rapport contenant des secrets n'est envoyé comme artefact ou commentaire. Les seules exclusions concernent le préfixe public `sb_publishable_`, deux identifiants de stockage, un identifiant de module et un UUID de recette précisément identifiés ; aucune exclusion de chemin, de commit, de clé privée ou d’UUID générique. Le scanner est exercé avec deux canaris non réels pour vérifier qu’il distingue un identifiant public d’une clé privée synthétique et masque celle-ci. Tout autre résultat doit être traité avant une publication, sans ajouter d’exclusion générale ni réécrire l’historique automatiquement. Une clé exposée doit être révoquée chez son fournisseur ; la suppression du fichier ne suffit pas.

Les actions GitHub sont épinglées par SHA de commit vérifié. Les images PostgreSQL/Redis/Python existantes ont été résolues auprès du registre et épinglées par digest ; `config/release-dependency-pins.json` conserve la provenance de ces choix. Les dépendances Python du signataire sont verrouillées avec leurs empreintes dans `services/sri/requirements.lock`, et les outils de recette dans `test-requirements.lock`. Le conteneur n'accepte que l'installation `--require-hashes`. Sa liste de fichiers copiés et le `.dockerignore` excluent les configurations locales, caches et certificats.

Pour une mise à jour Python, modifier les exigences directes puis régénérer les deux verrous avec les commandes inscrites en en-tête. Vérifier les tests fiscaux et `pip-audit` avant revue. Dependabot prépare les mises à jour des écosystèmes ; il ne remplace pas cette validation ni l'examen des nouveaux digests.

## Manifeste de composants

Chaque construction ERP et site produit `coco-build.json` et `release-manifest.json` dans son dossier de publication. Le manifeste contient la révision source, l'état propre/modifié observé, les empreintes des actifs publics, de chaque migration et des sources de chaque fonction Edge, plus l'empreinte du service SRI. Il ne contient ni code serveur, ni configuration privée, ni valeur d'environnement. L'état `deployment_status` indique explicitement qu'une construction ne prouve pas un déploiement.

Vérifier les actifs compilés avec :

```sh
node scripts/verify-release-manifest.cjs dist
node scripts/verify-release-manifest.cjs dist-storefront
```

Les migrations historiques nécessitent les rapprochements décrits dans la procédure de reprise. Ne pas déduire leur équivalence de leurs seuls noms ou forcer une réparation de registre. Une observation de production doit conserver pour chaque fichier source la correspondance et l'empreinte réellement vérifiées.

`node scripts/check-release-alignment.cjs observations.json dist/release-manifest.json dist-storefront/release-manifest.json` compare un relevé **déjà constaté par l'exploitant** aux manifestes. Il ne contacte aucun service, n'applique aucune migration et signale les observations manquantes comme écarts, jamais comme réussites. Le relevé attend :

- `web.erp` et `web.storefront` : `observed: true`, `source_commit` lu dans le marqueur servi ;
- `edge_functions[]` : `name`, `observed: true`, `version` et `source_sha256` de la source effectivement déployée ;
- `migrations[]` : `file`, `observed: true`, `sha256` avec le rapprochement historique vérifié ;
- `sri` : `observed: true` et `source_sha256` du service privé réellement exécuté.

Un exemple rempli à la main n'est pas une preuve. La date, l'opérateur et les méthodes de collecte restent dans le compte rendu de livraison administré, sans secrets.

## En-têtes HTTP de l'ERP

`npm run build` génère désormais `dist/_headers` : CSP HTTP avec `frame-ancestors 'none'`, blocage de l'encadrement, `nosniff`, politique de référent, HSTS et restrictions de fonctionnalités. Les empreintes des scripts de bootstrap proviennent des pages réellement construites. La caméra et la géolocalisation de même origine restent possibles pour le scanner/TMS ; les images Blob validées et téléchargements PDF ne nécessitent pas d’élargir les permissions des frames. La CSP meta propre à chaque page est conservée et peut être plus restrictive.

**GitHub Pages n'applique pas `_headers`.** Le fichier est utilisable sur un hébergement contrôlé tel qu'un projet Cloudflare Pages ERP dédié, distinct du catalogue GAMA. `wrangler.erp.jsonc` décrit ce dossier de publication sans créer ni publier de projet. Aucun domaine, origine OAuth/CORS, audience ou service public n'est déplacé automatiquement. Avant activation d'une nouvelle origine ERP, adapter et vérifier les origines exactes autorisées, liens d'invitation/récupération, PWA et intégrations ; vérifier les en-têtes effectivement servis ainsi que caméra, impression et pièces jointes.

La règle proposée pour `main` conserve les contrôles existants et ajoute `secret-scan`. Son application réelle et les droits de contournement doivent être vérifiés avec les droits Administration. Le graphe de publication impose les validations même lorsque ce réglage distant n'est pas accessible ; il ne remplace pas une politique de revue du dépôt.
