# Parité fonctionnelle vérifiable

Référence : Odoo 19.0 Enterprise, sources officielles du 24 octobre 2026.

107 lignes de couverture. Statuts intermédiaires au 26 octobre : testé : 52, implémenté : 3, partiel : 28, à développer : 20, à analyser : 0, bloqué : 3, exclu avec justification : 1. La revue du 25 octobre distingue le résultat reporté dynamique propre à Odoo 19 en H13, maintenant vérifié avec affectation et clôture sans double transfert.

Le statut « testé » atteste un scénario Coco isolé conforme à la règle précisée dans cette ligne. Il ne démontre pas toute la famille Odoo ni une comparaison sur instance Enterprise. Les lignes partielles, à développer, à analyser ou bloquées interdisent de qualifier le module d’équivalent intégral. La concurrence PostgreSQL réelle et les parcours des échéanciers, de configuration et d'import mappé ont réussi en CI ; le contrôle multi-écrans du périmètre complet reste partiel. Seule la facturation électronique SRI est exclue sur instruction explicite.

Ne pas remplacer ces écarts par un score favorable. Le périmètre complet n’est pas livré. Les extensions testées peuvent être publiées comme améliorations additives du module existant, sans annonce d’équivalence.

Le [diagnostic du script Replica](evidence/parity-tool.txt), exécuté sur cette
matrice, conclut également que le périmètre complet n'est pas prêt : 54 fonctions
obligatoires restent incomplètes ou non démontrées. Sa pondération des fonctions
partielles ne remplace aucun critère d'acceptation. La comparaison de pixels avec
Odoo n'est pas retenue : la référence visuelle demandée est Coco, dont les
composants sont vérifiés dans les captures et parcours isolés.

Priorités de reprise après validation du lot paiements : valorisation Odoo 19 avec transition ; moteur de taxes et positions fiscales ; analytique/budgets révisables ; séparation multi-sociétés puis consolidation ; méthodes d’immobilisations et services externes. Les séquences sont opérationnelles pour les nouvelles validations, mais B04 reste partiel pour l'inférence du format et la renumérotation de masse.

Le lot [paiements et comptes d’attente](results-payment-modes.md) étend B14/E05 sans les déclarer complets : paramètres, traitement figé, solde réellement comptabilisé, liquidation et annulation sont vérifiés ; méthodes personnalisées multiples et résiduels datés restent visibles.

Le moteur [de report et d’affectation du résultat](earnings-19.md) est vérifié par treize tests serveur chiffrés, neuf parcours multilingues et une course PostgreSQL de clôture. La PR 247 consigne la publication exacte ; la navigation authentifiée en production reste non attestée et N04 partiel.

Le lot [moyens nommés et rapprochements partiels](partial-matching.md) couvre B14/E05/F06. Les preuves serveur, la reprise sur base peuplée et la concurrence sont réussies ; le contrôle final navigateur du nouveau parcours reste en cours. Ces trois lignes restent donc « implémenté » dans ce relevé intermédiaire. D05 et L10 sont identifiés dans les sources officielles 19.0 et passent de l’analyse au développement, sans exclusion.
