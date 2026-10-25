# Parité fonctionnelle vérifiable

Référence : Odoo 19.0 Enterprise, sources officielles du 24 octobre 2026.

107 lignes de couverture. Statuts : testé : 51, partiel : 31, à développer : 19, à analyser : 2, bloqué : 3, exclu avec justification : 1. La revue du 25 octobre isole en H13 le résultat reporté dynamique propre à Odoo 19 ; cet écart n'est pas couvert par la seule clôture annuelle native.

Le statut « testé » atteste un scénario Coco isolé conforme à la règle précisée dans cette ligne. Il ne démontre pas toute la famille Odoo ni une comparaison sur instance Enterprise. Les lignes partielles, à développer, à analyser ou bloquées interdisent de qualifier le module d’équivalent intégral. La concurrence PostgreSQL réelle et les parcours des échéanciers, de configuration et d'import mappé ont réussi en CI ; le contrôle multi-écrans du périmètre complet reste partiel. Seule la facturation électronique SRI est exclue sur instruction explicite.

Ne pas remplacer ces écarts par un score favorable. Le périmètre complet n’est pas livré. Les extensions testées peuvent être publiées comme améliorations additives du module existant, sans annonce d’équivalence.

Le [diagnostic du script Replica](evidence/parity-tool.txt), exécuté sur cette
matrice, conclut également que le périmètre complet n'est pas prêt : 55 fonctions
obligatoires restent incomplètes ou non démontrées. Sa pondération des fonctions
partielles ne remplace aucun critère d'acceptation. La comparaison de pixels avec
Odoo n'est pas retenue : la référence visuelle demandée est Coco, dont les
composants sont vérifiés dans les captures et parcours isolés.

Priorités de reprise : comptes d’attente et états des paiements ; résultat reporté et valorisation Odoo 19 avec transition ; moteur de taxes et positions fiscales ; analytique/budgets révisables ; séparation multi-sociétés puis consolidation ; méthodes d’immobilisations et services externes. Les séquences sont opérationnelles pour les nouvelles validations, mais B04 reste partiel pour l'inférence du format et la renumérotation de masse.

Le lot [paiements et comptes d’attente](results-payment-modes.md) étend B14/E05 sans les déclarer complets : paramètres, traitement figé, solde réellement comptabilisé, liquidation et annulation sont vérifiés ; méthodes personnalisées multiples et résiduels datés restent visibles.

Le moteur [de report et d’affectation du résultat](earnings-19.md) est implémenté avec neuf scénarios serveur chiffrés ; H13 reste partiel jusqu’à validation des parcours et du déploiement.
