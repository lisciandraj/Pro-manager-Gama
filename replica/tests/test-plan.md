# Plan de validation de la passe Replica

Tests sur fixtures locales, sans accès aux données de production.

| Risque | Vérification |
| --- | --- |
| Déplacement du catalogue casse création/édition | `product-identity.spec.js` et `product-supplier.spec.js`, dont un parcours nouveau bouton → brouillon et édition → bon identifiant/focus. |
| Recherche commune déplace les résultats Documents | Nouveau scénario dans `service-documents.spec.js` : colonnes alignées à 1440/768 px, empilées à 320 px, puis recherche et filtrage catégorie. |
| Long formulaire, erreur ou sous-dialogue perd une action | Flux SAV et pièces jointes mobiles dans `service-documents.spec.js`, validation et reprise dans `ux-workspace.spec.js`. |
| Habillage de pipeline perturbe changement d’étape | Suite `crm-opportunities.spec.js`, succès/perte/reprise/drag and drop et annulation. |
| Styles communs changent navigation ou préférences | Suites `sales-module-tabs`, `table-controls`, `standardization` et `menu-contrast`. |
| Base de connaissances devient illisible ou perd un brouillon | `knowledge.spec.js` + capture d’un article de démonstration. |
| Débordement et chevauchement | `responsive-layout.spec.js` : modules à 320, 360, 390, 768, 844, 1024 et 1440 px, zoom/FR/ES/EN selon scénario. |
| Régression de build, schéma ou budget | `npm run validate`, sorties générées et contrôles de démarrage. |
| Contraste et cohérence visuelle | 17 couples de tokens, contrôle navigateur du focus/contraste, captures avant/après et primitives. |

Les résultats effectifs et limites d’environnement sont consignés dans `results.md` à la fin de la vérification. L’exécution navigateur locale utilise Chromium préinstallé ; Safari/WebKit doit être explicitement signalé s’il n’a pas été exécuté.
