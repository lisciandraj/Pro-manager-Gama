# Parité fonctionnelle vérifiable

Référence : Odoo 19.0 Enterprise, sources officielles du 24 octobre 2026.

106 lignes de couverture. Statuts : testé : 48, partiel : 32, à développer : 20, à analyser : 2, bloqué : 3, exclu avec justification : 1.

Le statut « testé » atteste un scénario Coco isolé conforme à la règle précisée dans cette ligne. Il ne démontre pas toute la famille Odoo ni une comparaison sur instance Enterprise. Les lignes partielles, à développer, à analyser ou bloquées interdisent de qualifier le module d’équivalent intégral. La concurrence PostgreSQL réelle et les neuf parcours des échéanciers ont réussi en CI ; le contrôle multi-écrans du périmètre complet reste partiel. Seule la facturation électronique SRI est exclue sur instruction explicite.

Ne pas remplacer ces écarts par un score favorable. Le périmètre complet n’est pas livré. Les extensions testées peuvent être publiées comme améliorations additives du module existant, sans annonce d’équivalence.

Priorités de reprise : comptes d’attente et états des paiements ; valorisation Odoo 19 et transition ; moteur de taxes et positions fiscales ; analytique/budgets révisables ; séparation multi-sociétés puis consolidation ; méthodes d’immobilisations et services externes.
