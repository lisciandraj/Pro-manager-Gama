# Navigation actuelle — Coco ERP

| Espace | Contenu et accès |
| --- | --- |
| Tableau de bord | Pilotage, priorités et KPI personnalisables |
| Coco Intelligence | Diagnostics et assistant réservés aux administrateurs |
| Suivi de processus | PDV ventes, PDC achats, PRC retours clients, PRP retours fournisseurs |
| Ventes | Demandes, devis, commandes, factures/encaissements, tarifs, matrice commerciale, selon les droits |
| Achats | Commandes fournisseurs, réception, réapprovisionnement et contrôles |
| Produits | Catalogue, prix, photos, unités, lots et qualité des fiches |
| Contacts | Clients, fournisseurs et contacts de prospects ; catégorie Administration |
| Entrepôts et stocks | Quantités localisées, réservations, transferts, comptages, ajustements et valorisation |
| Codes-barres | Génération, scan, transferts et consommations |
| Retours | Tableau résumé des retours clients/fournisseurs et données financières ; le processus se suit dans Suivi de processus |
| SAV | Dossiers de service, garanties et création de retour lié |
| TMS | Préparation, planification, contrôle de chargement, livraisons et preuves |
| Flotte | Véhicules, conducteurs, documents, échéances et dépenses |
| Facturation SRI | Factures internes, moteur fiscal Open API, consultation SRI, XML/RIDE privés ; administrateurs et droits comptabilité |
| Comptabilité | Factures fournisseurs/clients, règlements, rapprochement et onglet SRI |
| CRM | Prospects, opportunités, activités, objectifs et rapports |
| Projets | Portefeuille et phases adaptées PME ; catégorie Administration |
| Ressources humaines | Employés, organigramme, absences, documents et paie |
| Knowledge | Articles, sous-articles et recherche |
| Documents | Catégories, employés, sources liées, versions et accès |
| Site web | Configuration de la vitrine de test et échanges autorisés avec l’ERP |
| Administration | Configuration entreprise, utilisateurs, accès, audit, import et sauvegardes |
| Portail client | Catalogue, demandes et livraisons autorisées au client connecté |

## Compatibilité

`clients` et `suppliers` ouvrent Contacts ; `stock` ouvre Entrepôts et stocks ; `operations` ouvre le tableau de bord ; `order-preparation` ouvre TMS.
`sales-orders`, `payments`, `price-lists` et `matrix` restent les identifiants techniques des onglets Ventes.
`gamaPurchasesV14` est l’identifiant historique d’Achats ; le source porte maintenant un nom explicite.
Les modules `billing` et `movement` sont historiques/retirés du menu courant. Leur conservation n’accorde aucun accès supplémentaire.

## Ajustements de stock

Le motif utilise une liste native compacte. Choisir un produit limite les emplacements à ceux où sa quantité est positive. Le changement de produit efface l’ancienne sélection. « Stock initial » autorise un emplacement vide. Les réservations, seuils et validations restent vérifiés par les parcours existants.

## Références

Les processus et leurs étapes conservent une identité commune, avec préfixes paramétrables et huit chiffres. Les numéros fiscaux et références propres des documents restent séparés. Voir [références](document-references.md) et [retours](returns.md).
