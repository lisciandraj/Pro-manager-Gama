# Preuves d'interface isolées

Captures du commit `9d43d1f26ca20837a0417bd7c5ce7100679dfa91`, [GitHub Actions 40108055234](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40108055234), le 24 octobre 2026. Les données visibles sont fictives et limitées à PGlite sur le runner de test. Ces images ne représentent pas des opérations effectuées en production.

- [Détail sur ordinateur](accounting19-fr-1440.png) : navigation Coco, tableau de montants et historique à droite.
- [Détail sur téléphone](accounting19-fr-390.png) : navigation défilante interne et historique replié.
- [Formulaire sur téléphone](accounting19-form-fr-390.png) : bouton primaire Coco et tableau de saisie avec défilement interne.

Les neuf combinaisons FR/ES/EN × 390/768/1440 ont passé le parcours complet des échéanciers et les contrôles axe WCAG 2 A/AA du formulaire et du détail. Le job comporte 61 tests navigateur au total. Il vérifie également, après rafraîchissement, le lien depuis l'historique réel vers le plan exact, puis l'aller-retour entre plan et écriture. Les captures sont prises avant ce rafraîchissement ; l'historique vide sur l'image n'est donc pas la preuve de ce dernier contrôle.

Cette couverture ne certifie pas l'accessibilité ou la fidélité fonctionnelle de chaque écran du périmètre Odoo. Le détail des écarts reste dans [la matrice](../features.csv).
