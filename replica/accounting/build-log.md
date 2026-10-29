# Construction

27 octobre 2026 — H14 : dates sur lignes des factures clients, ventilation nette fournisseur et revue de brouillon, configuration des différés, génération atomique et liens aux échéanciers. 14 tests serveur et 12 parcours navigateur réussis ; migration peuplée sans reprise historique. Les avoirs et sources à plusieurs comptes de résultat restent explicites dans la matrice. [Architecture et limites](invoice-deferrals.md), [preuves](results-invoice-deferrals.md).

24 octobre 2026 — audit de main et de production ; référence Odoo 19.0 Enterprise ; matrice de 106 points, toutes les lacunes conservées explicitement.

S12 — nouveaux échéanciers de charges/produits différés, OD récurrentes et emprunts, prévisualisation serveur, brouillon, approbation humaine, exécution manuelle/planifiée, annulation conservant les pièces. Les calculs sont PostgreSQL numeric et les dates sont civiles. Les contrôles de capacité et les liens entre plan/source/écriture sont natifs.

S01–S07 — navigation en familles et maintien des raccourcis compatibles. S05/S12/historique — liens vers le dossier ou l'écriture précis. Pas de modification des politiques de stock, du schéma de sociétés, des taxes réelles ou des paramètres SRI.

Tests : scénarios serveur isolés, neuf parcours navigateur avec axe, concurrence sur deux sessions PostgreSQL et suites existantes. Les modalités comptables non couvertes sont listées dans la matrice, jamais remplacées par des écrans simulés.

26–27 octobre 2026 — F12/A02/G04 : import bancaire configurable dans le grand livre, adoption explicite des lignes sans rapprochement antérieur, contreparties de rapprochement, cartes de journaux et pagination/export. 106 parcours navigateur et concurrence PostgreSQL réussis ; limites détaillées dans [le lot bancaire](bank-import-ledger.md).

La revue de reprise est paginée à 50 lignes, garde la sélection entre pages (200 par opération) et a été vérifiée sur 205 mouvements historiques isolés. Les 16 contrôles ciblés import/journaux passent. Aucun mouvement de production utilisé pour ces tests. Les deux migrations sont installées ; 23 empreintes historiques et les totaux sont inchangés. [Preuves et prérequis de configuration](results-bank-import.md).

28 octobre — H03 : dégressif et dégressif puis linéaire mensuels, facteur explicite, prorata, solde final exact et paramètres conservés sur l’actif. Le plan reste humain, non comptabilisé à l’enregistrement et verrouillé après sa première comptabilisation. Voir [la reprise commune](../continuation-2026-10-28/README.md).
