# Déploiement du design Coco ERP

Date : 16 octobre 2026. PR : [#165](https://github.com/lisciandraj/Pro-manager-Gama/pull/165).
Autorisation de fusion et de publication : demande explicite de l'utilisateur « Déploie stp ».
Skill appliqué : Replica Deploy, adapté à la mise à jour visuelle de l'application existante décrite dans `recon.md`.

## Contrôles avant publication

| Contrôle | Résultat |
| --- | --- |
| Exigences du périmètre | Les 9 exigences obligatoires de `features.csv` sont implémentées, préservées ou vérifiées ; les 2 souhaitables sont implémentées. Aucune parité fonctionnelle complète avec Odoo n'est revendiquée. |
| Identité Coco | Logo, palette, accueil et favoris conservés ; aucune image de référence Odoo livrée dans l'application. |
| Recherche de marques | Analyse de `dist/` : 20 correspondances textuelles, toutes classées en commentaires de source, attribution et provenance des localisations comptables existantes, ou traductions de l'import de ces localisations. Aucun logo ni couleur de marque Odoo détecté. Ce résultat n'est pas un balayage à zéro correspondance ; les mentions de provenance et de licence sont conservées. |
| Tests locaux | Résultats et limites dans `tests/results.md` ; correction du clic de paie reproduite puis validée par 22 tests RH. |
| Build et budgets | Build canonique, sources, types, reproductibilité et budgets vérifiés après correction. |
| Défauts bloquants connus | Aucun restant dans les parcours exercés ; voir `tests/bugs.md`. |
| Données et intégrations | Pas de migration, nouvelle permission, nouveau fournisseur, secret, paiement ni changement de domaine. Configuration existante conservée. |
| Pages légales et boutiques | Aucune nouvelle collecte ou distribution en boutique dans cette mise à jour ; notices des composants et données conservées. |
| CI avant fusion | En attente du contrôle sur le commit contenant la correction de chargement RH. |
| Publication | En attente de la fusion, puis du workflow `deploy-coco-pages.yml` sur `main`. |

Le balayage a utilisé `sweep.py dist --avoid Odoo --domains odoo.com --colors '#714B67,#875A7B' --json`. Les mentions visibles concernent précisément l'import du plan comptable Odoo EC et l'attribution LGPL-3 Odoo / TRESCLOUD ; elles ne présentent pas Coco comme Odoo. Les sources de recherche et captures de comparaison restent dans `replica/`, hors de `dist/`.

## Cible et vérification

- Application : <https://lisciandraj.github.io/Pro-manager-Gama/>.
- Publication : artefact `dist/` validé par GitHub Actions, environnement `github-pages`.
- Preuve attendue : workflow de publication réussi et `coco-build.json` servi par le site correspondant au commit fusionné.
- Retour arrière si nécessaire : rétablir le commit précédent par une nouvelle révision validée et republiée ; aucune restauration de données n'est impliquée.

Le résultat de publication sera ajouté après vérification du marqueur en ligne. Cette préparation ne constitue pas encore une preuve de déploiement.

## Refonte horizontale des modules — 16 octobre 2026

Cette livraison applique la maquette approuvée aux composants partagés des 22 modules activés : lanceur d’applications, navigation horizontale native, espace de travail pleine largeur, tableaux compacts et filtres repliables sur mobile. Le logo et les couleurs Coco sont conservés. Aucun changement de données, de permissions, d’intégration ou de domaine.

- Point de restauration : `54e70e986469dd63a3f27967d1e7763db731c718`.
- Tests locaux et limites : [rapport de validation](tests/workbench-results.md).
- Demande de fusion : [#167](https://github.com/lisciandraj/Pro-manager-Gama/pull/167).
- Autorisation de publication : demande de déploiement déjà donnée dans la conversation, suivie de la demande d’implémentation de la maquette dans tous les modules.
- Publication par le workflow existant `deploy-coco-pages.yml`, avec ses contrôles intégrés avant mise en ligne. L’utilisateur a confirmé « Publie en ligne direct stp » pendant le suivi de la livraison.
- État de préparation : implémentation et vérifications locales terminées ; CI et preuve du commit servi à vérifier après publication.
