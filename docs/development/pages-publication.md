# Publication compilée de Coco ERP

La publication cible est GitHub Pages avec **Source = GitHub Actions**, à configurer par le propriétaire dans les paramètres du dépôt. `deploy-coco-pages.yml` construit `dist/` à partir de `src/`, exécute `npm run update` et les parcours Agent Coco, puis publie un artefact Pages. Aucun workflow n'a besoin d'un jeton permettant de pousser du code, de clés Supabase ou de secrets ERP pour compiler.

Les jobs de construction disposent seulement de `contents: read`. Le job de publication, limité à `main` et à l'environnement `github-pages`, a `pages: write` et `id-token: write`. Il lit le mode de publication et refuse d'administrer le dépôt automatiquement. Une pull request construit et teste mais ne déploie pas.

Les scripts racine historiques ne sont plus la source de publication lorsque ce mode est activé. Ils sont des sorties locales/archives de compatibilité ; il faut reconstruire avant tout test. Le contrôle `check:generated` vérifie la reproductibilité du build, sans suppression de ses assertions. Ne jamais éditer manuellement un fichier compilé. Le manifeste conserve l'ordre et les adresses historiques des ressources.

Vérifier `coco-build.json` sur le site après déploiement pour comparer le commit réellement servi avec `main`. Tant que le réglage Pages reste sur la publication d'une branche, ces nouveaux écrans ne sont pas garantis en ligne. Ne pas annoncer le déploiement web sur la seule base d'un test de compilation.
