# Dépendances et écarts non masqués

La matrice contient 108 points de contrôle ; elle n'est pas une preuve que l'inventaire des compléments et localisations Odoo est exhaustif.

| Dépendance | État vérifié | Accès et coût |
| --- | --- | --- |
| Instance Odoo 19 Enterprise | Documentation publique étudiée, pas d'instance licenciée inspectée | Instance autorisée nécessaire pour compléter les comportements non documentés et l'attribution fine des modules |
| Synchronisation bancaire Coco | Aucun prestataire natif raccordé ni banque équatorienne compatible attestée | Odoo utilise notamment Salt Edge, Plaid, Yodlee, Ponto, Enable Banking, Basiq selon pays ; son contrat ne donne pas une API réutilisable à Coco. Prestataire, consentement et tarif natif à sélectionner et vérifier |
| OCR | Outil de saisie fournisseur existant ; configuration opérationnelle non attestée par cet audit | Clé, prestataire, disponibilité et coût par document à vérifier ; l'interface ne vaut pas connexion |
| Paiement en ligne | Pas de preuve d'un compte marchand Coco actif et webhooks rapprochés | Compte marchand, contrat, clés et tarifs selon prestataire ; aucun abonnement ni dépense engagés |
| Taux de change automatiques | Registre manuel et règlements documentés présents | Source officielle/API et éventuel coût à choisir ; aucun taux inventé |
| Sauvegarde physique/PITR Supabase | Non attestée par les outils de cette intervention | Vérifier la politique de sauvegarde et exécuter un exercice de restauration avant une reprise destructive |

Écarts structurels : multi-sociétés et consolidation, valorisation Odoo 19 à la facture/clôture, moteur complet de taxes/positions fiscales, révisions budgétaires et engagements, modèles analytiques, dégressif d'immobilisations, formats bancaires supplémentaires, moteur complet de rapports et actions groupées. Ils restent à développer, pas exclus.

Seule l'émission fiscale électronique SRI est hors périmètre sur instruction explicite. Les outils fiscaux déjà présents restent distincts des pièces internes.

F12 : comptabilisation des transactions importées sur banque/attente avant rapprochement. La politique actuelle de Coco attend le traitement métier ; une transition vérifiée doit traiter séparément lignes non rapprochées, portions actives et paiements déjà comptabilisés. Le compte d’attente devra être configuré, avec comparaison avant/après sans écriture d’équilibrage arbitraire. Voir [complément d’audit](journal-dashboard-audit.md).
