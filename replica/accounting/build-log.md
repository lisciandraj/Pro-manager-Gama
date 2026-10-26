# Construction

24 octobre 2026 — audit de main et de production ; référence Odoo 19.0 Enterprise ; matrice de 106 points, toutes les lacunes conservées explicitement.

S12 — nouveaux échéanciers de charges/produits différés, OD récurrentes et emprunts, prévisualisation serveur, brouillon, approbation humaine, exécution manuelle/planifiée, annulation conservant les pièces. Les calculs sont PostgreSQL numeric et les dates sont civiles. Les contrôles de capacité et les liens entre plan/source/écriture sont natifs.

S01–S07 — navigation en familles et maintien des raccourcis compatibles. S05/S12/historique — liens vers le dossier ou l'écriture précis. Pas de modification des politiques de stock, du schéma de sociétés, des taxes réelles ou des paramètres SRI.

Tests : scénarios serveur isolés, neuf parcours navigateur avec axe, concurrence sur deux sessions PostgreSQL et suites existantes. Les modalités comptables non couvertes sont listées dans la matrice, jamais remplacées par des écrans simulés.

26 octobre 2026 — F12/A02/G04 : import bancaire configurable dans le grand livre, adoption explicite des lignes sans rapprochement antérieur, contreparties de rapprochement, cartes de journaux et pagination/export. Tests isolés en cours ; limites détaillées dans [le lot bancaire](bank-import-ledger.md).

La revue de reprise est paginée à 50 lignes, garde la sélection entre pages (200 par opération) et a été vérifiée sur 205 mouvements historiques isolés. Les 15 contrôles ciblés import/journaux passent. Aucun mouvement de production utilisé pour ces tests.
