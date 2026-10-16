# Résultats de validation

15 octobre 2026 — branche `feat/replica-odoo-design`, base `e03de7b`.

## Résultats

| Contrôle | Résultat |
| --- | --- |
| `npm run build` | Réussi, 193 assets versionnés depuis les sources canoniques |
| `npm run validate` | Terminé avec code 0 ; sources, dépendances, types, docs, migrations, tests unitaires et contrôles de build |
| Architecture, chargement différé et performance de chargement | 18 tests réussis, réexécutés après extraction des styles spécifiques |
| Parcours navigateur | 84 scénarios distincts couverts dans les dix suites ci-dessous, corrections revérifiées |
| Responsive final | 5 scénarios réussis, dont parcours des modules à 320/360/390/768/844/1024/1440 px |
| Contraste | 17 couples de tokens conformes AA ; contrôle navigateur supplémentaire du bouton principal, badge et focus |
| Captures | Ordinateur, téléphone et composants isolés ; aucune erreur JavaScript remontée par le harnais de captures |
| Budget initial | 14 scripts / limite 15 ; JavaScript 848 152 / 850 000 octets ; CSS 298 964 / 300 000 octets |

Les dix suites navigateur sont `ux-workspace`, `product-identity`, `product-supplier`, `service-documents`, `knowledge`, `crm-opportunities`, `table-controls`, `sales-module-tabs`, `standardization` et `menu-contrast`.

La première passe de 82 scénarios a relevé deux échecs liés au libellé du nouveau bouton Produit. Ils ont été corrigés par « Nouveau produit » et revérifiés, avec les deux nouveaux scénarios de création/édition et de bibliothèque documentaire. Après extraction des styles, les 38 scénarios CRM, Documents et Connaissances ont été réexécutés : tous réussis. Les cinq scénarios responsive ont ensuite été réexécutés sur la version finale : tous réussis. Le total distinct est donc de 89 scénarios navigateur, sans additionner les répétitions.

## Commandes reproductibles

```sh
npm run build
npm run validate
node --test tests/architecture.test.cjs tests/lazy-loader.test.cjs tests/loading-performance.test.cjs
npx playwright test tests/ux-workspace.spec.js tests/product-identity.spec.js tests/product-supplier.spec.js tests/service-documents.spec.js tests/knowledge.spec.js tests/crm-opportunities.spec.js tests/table-controls.spec.js tests/sales-module-tabs.spec.js tests/standardization.spec.js tests/menu-contrast.spec.js --workers=2
npx playwright test --config=playwright.responsive.config.js --project=chromium tests/responsive-layout.spec.js --workers=2 --output=test-results-replica-responsive
npm run check:generated
npm run check:startup
```

Dans cet environnement, `PLAYWRIGHT_CHROMIUM_PATH=/tmp/chromium` sélectionne le navigateur disponible. Sur une autre machine, installer le Chromium de Playwright ou fournir son propre chemin. Employer des dossiers de résultats distincts si plusieurs commandes Playwright tournent simultanément.

## Limites et publication

Les tests utilisent les mocks et bases isolées du dépôt. Ils ne prouvent pas une exécution avec les données réelles ni une parité fonctionnelle avec Odoo. La passe du 15 octobre a été vérifiée sous Chromium ; le complément WebKit est décrit ci-dessous. Les appareils physiques et Safari sur macOS/iOS n’ont pas été exercés. Les langues FR/ES/EN sont parcourues dans les scénarios responsive et de validation partagée, pas dans chaque scénario métier.

Les images de recherche Odoo ne sont pas embarquées. Les aperçus Coco joints utilisent des données fictives et ne sont pas copiés dans `dist/`. Aucune migration métier ni modification de permission. Cette branche est proposée à la revue avant fusion et publication.

## Intégration de la version courante — 16 octobre 2026

La branche inclut maintenant `c6a5f73`, la version Contacts publiée sur `main` depuis la passe de design. La fusion des sources est sans conflit et conserve `GamaDocuments.openRecord` ainsi que les assets du dossier Contacts. Les fichiers générés ont été reconstruits depuis ces sources : 195 assets.

Les 45 scénarios de `contacts.spec.js` (dont les six parcours du dossier), `crm-leads.spec.js` et `service-documents.spec.js` passent sous Chromium. Les 18 tests d’architecture et de chargement passent aussi. Sources, types, liens documentaires, reproductibilité du build et budgets ont été revérifiés. Le binaire temporaire de la veille n’existait plus ; les scénarios ont été exécutés avec le Chromium conservé dans l’environnement, sans modifier les tests.

Budget après intégration : 14 scripts ; 848 280 octets JavaScript et 298 964 octets CSS, dans les limites existantes. Cette intégration ajoute une vérification ciblée ; la validation générale du 15 octobre ci-dessus reste distincte.

## Correction du contrôle CI responsive — 16 octobre 2026

La première CI de la PR #165 a validé 17 des 18 scénarios responsive/UX. Le contrôle du Dashboard échouait sous WebKit en anglais à 320 px. La reproduction locale a identifié un débordement de 8 px en anglais et de 6 px en espagnol : le texte des sélecteurs natifs à 16 px dépassait leurs colonnes de 140 px. Leur base flexible passe à 190 px, ce qui les empile aux petites largeurs. Le rendu reste à 320 px dans les trois langues après correction. Les budgets de démarrage restent identiques.

La fixture des suites `responsive-layout` et `ux-workspace` retire les préconnexions de la copie HTML servie aux tests et limite son `connect-src` à la même origine. Elle bloque aussi les requêtes HTTP externes, les WebSockets et les service workers. Les mocks métier et toutes les assertions de mise en page restent conservés. La page et la politique réseau de production ne sont pas modifiées par cette isolation.

Les 18 scénarios des deux suites ont ensuite terminé avec code 0 et l’état Playwright `passed` sans test échoué. Le scénario Dashboard a également été réexécuté seul sur les deux moteurs : 2 réussites en 11,2 secondes. WebKit 26.6 utilise des bibliothèques portables locales ; seule la sélection du binaire diffère de la configuration CI. Sources, documentation, build reproductible et budgets sont validés après le correctif.
