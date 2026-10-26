# Parité fonctionnelle vérifiable

Référence : **Odoo 19.0 Enterprise**, sources officielles consultées les 24–26 octobre 2026. L’interface de référence reste Coco.

La matrice contient **108 lignes** : **54 testées, 29 partielles, 21 à développer, 0 à analyser, 3 bloquées et 1 exclusion SRI explicite**. Il reste donc **53 fonctions obligatoires incomplètes ou non démontrées** dans le périmètre de 107 lignes. Un score global ne compense aucun écart.

Le statut « testé » atteste les scénarios Coco et critères précis de la ligne, en base isolée, comparés aux règles Odoo documentées. Il ne démontre pas toute une famille Odoo ni une comparaison exhaustive sur instance Enterprise. La classification détaillée des éditions et la couverture de tous les écrans restent également limitées. Le périmètre complet n’est pas livré.

Le lot [moyens nommés et reliquats](partial-matching.md) termine les critères B14 et F06 : méthodes de même famille, préférences tiers, paiements figés, reliquats, plusieurs dates et annulation partielle. E05 reste partiel : les traitements et soldes réels sont vérifiés, tandis que la correspondance exhaustive des libellés/transitions avec Odoo reste à attester. Cette réserve est conservée malgré la réussite des tests.

Les 97 parcours comptables, dont neuf combinaisons ES/FR/EN × 390/768/1440 supplémentaires, et la concurrence PostgreSQL 17 réussissent dans le run 40387433781. Les derniers contrôles de liens d’historique et l’archive des migrations sont consignés dans [les résultats du lot](results-partial-matching.md). La comparaison de pixels avec Odoo est écartée : les composants, couleurs, montants et défilements sont évalués par rapport à Coco.

D05 (autofacturation) et L10 (rapports de localisation) ont été identifiés dans les sources officielles 19.0 et passent à « à développer », sans exclusion. Les priorités suivantes restent la valorisation 19 avec reprise, les taxes/positions fiscales, l’analytique et les budgets révisables, le multi-sociétés/consolidation, les méthodes d’amortissement et les services connectés. Le résultat reporté H13, les configurations et échéanciers déjà livrés sont conservés.

Le [diagnostic Replica](evidence/parity-tool.txt) conserve la liste des fonctions obligatoires manquantes. Il ne constitue pas une autorisation de présenter le module comme équivalent complet.

Le complément d’audit [journaux et compte d’attente](journal-dashboard-audit.md) ajoute F12 : la pièce banque/attente dès l’import est distincte du rapprochement partiel livré. Elle reste à développer avec sa reprise ; l’inventaire précédent de 107 points ne la couvrait pas explicitement.
