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
| CI avant fusion | 13 contrôles GitHub réussis sur `4696f61`, dont Sales 251/251, interface partagée 405/405 et audit 171/171. Le job de mise en page reste bloqué pendant l'installation des navigateurs ; la même suite passe localement sur le code final : Chromium + WebKit, 18/18, 0 reprise, 69,7 secondes. Aucun contrôle ni aucune assertion supprimé. |
| Fusion | PR #165 fusionnée dans `main` : `54e70e986469dd63a3f27967d1e7763db731c718`. |
| Publication | Workflow de production [38927646633](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/38927646633) réussi, y compris le job de publication `117067303854`. Les 15 contrôles GitHub du commit fusionné sont verts. |

Le balayage a utilisé `sweep.py dist --avoid Odoo --domains odoo.com --colors '#714B67,#875A7B' --json`. Les mentions visibles concernent précisément l'import du plan comptable Odoo EC et l'attribution LGPL-3 Odoo / TRESCLOUD ; elles ne présentent pas Coco comme Odoo. Les sources de recherche et captures de comparaison restent dans `replica/`, hors de `dist/`.

Le commit de fusion conserve le complément d'archive Contacts `3b7f290`, ajouté à `main` après `c6a5f73`. Son arbre correspond exactement à l'arbre de fusion testé par la PR : `b6d7f29c787ea993011e949da5966b9b6cad6a2f`. Les cinq fichiers supplémentaires d'archive, documentation et test n'altèrent pas les fichiers runtime vérifiés localement. La publication conserve ses deux conditions : construction et tests des menus réussis sur le commit fusionné.

Le contrôle de mise en page sur le commit fusionné a ensuite réussi sur GitHub : [job 117063187767](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/38927646763/job/117063187767), 18 scénarios réussis en 1,4 minute, le 16 octobre à 15:56 UTC. L'attente d'installation observée sur la PR n'affecte donc plus la vérification du code déployé.

## Cible et vérification

- Application : <https://lisciandraj.github.io/Pro-manager-Gama/>.
- Publication : artefact `dist/` validé par GitHub Actions, environnement `github-pages`.
- Preuve attendue : workflow de publication réussi et `coco-build.json` servi par le site correspondant au commit fusionné.
- Retour arrière si nécessaire : rétablir le commit précédent par une nouvelle révision validée et republiée ; aucune restauration de données n'est impliquée.

## Publication vérifiée

Le 16 octobre 2026 à 16:04 UTC, le site répond en HTTPS et sert `coco-build.json` avec le commit `54e70e986469dd63a3f27967d1e7763db731c718`, le run `38927646633` et une construction datée `2026-10-16T16:02:57.737Z`. Le workflow a terminé avec succès à 16:03 UTC.

Les dix fichiers contrôlés sur le site répondent HTTP 200 et ont les mêmes empreintes SHA-256 que le build validé : page d'entrée, tokens, styles communs, CRM, Documents, Connaissances, contrôles, workspace et deux modules RH. Les réponses et empreintes sont conservées dans [la preuve de publication](tests/deployed-build.json).

Les parcours métier et les formats ordinateur/téléphone sont validés par les suites isolées ; la vérification de production est en lecture seule et ne crée aucune opération métier. Après ouverture du site, une actualisation permet de charger les nouveaux fichiers.

Ce compte rendu après publication est conservé dans la branche documentaire `docs/replica-design-deployment-20261016`. La version servie reste le commit de livraison ci-dessus.
