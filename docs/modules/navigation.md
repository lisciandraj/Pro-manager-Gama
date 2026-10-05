# Navigation actuelle — Coco ERP

| Espace | Contenu et accès |
| --- | --- |
| Tableau de bord | Pilotage, priorités et KPI personnalisables |
| Agent Coco | Conversation et rapports PDF réservés aux administrateurs |
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
| Site web | Site public : publication, catalogue et présentation ; demandes reçues dans Ventes |
| Configuration (roue dentée) | Entreprise, identité, fiscalité/SRI, références, règles, Importer des données, Sauvegarde, Utilisateurs, Paramètres d’accès, langue et sécurité |
| Administration | Audit ; import, sauvegarde, utilisateurs et accès sont des onglets de Configuration |

## Compatibilité

`clients` et `suppliers` ouvrent Contacts ; `stock` ouvre Entrepôts et stocks ; `operations` ouvre le tableau de bord ; `order-preparation` ouvre TMS.
`sales-orders`, `payments`, `price-lists` et `matrix` restent les identifiants techniques des onglets Ventes.
`gamaPurchasesV14` est l’identifiant historique d’Achats ; le source porte maintenant un nom explicite.
Les modules `billing` et `movement` sont historiques/retirés du menu courant. Leur conservation n’accorde aucun accès supplémentaire.

## Ajustements de stock

Le motif utilise une liste native compacte. Choisir un produit limite les emplacements à ceux où sa quantité est positive. Le changement de produit efface l’ancienne sélection. « Stock initial » autorise un emplacement vide. Les réservations, seuils et validations restent vérifiés par les parcours existants.

## Références

Les processus et leurs étapes conservent une identité commune, avec préfixes paramétrables et huit chiffres. Les numéros fiscaux et références propres des documents restent séparés. Voir [références](document-references.md) et [retours](returns.md).

## Accès clients retirés

L’icône Ventes utilise une progression avec une flèche, distincte du document fiscal de Facturation SRI.

Le type d’accès Client et les modules Catalogue client et Mes livraisons sont retirés de Coco ERP. Les commandes publiques passent par le site internet, puis Ventes → Demandes clients. Les fiches commerciales, commandes, livraisons et documents existants restent gérés par les équipes internes. Les comptes de connexion de type client sont désactivés et ne peuvent plus être approuvés ni invités. Leurs identifiants historiques sont conservés pour les liens d’audit. Les anciens endpoints du portail sont fermés.

`reports`, `backup`, `users` et `access-settings` restent les identifiants des onglets Configuration. Ils n’ont plus de tuile ni de lien latéral. Les anciens appels ouvrent directement leur onglet. Les droits et l’activation de chaque fonctionnalité restent inchangés : import pour administrateurs/commerciaux autorisés ; sauvegarde, utilisateurs et paramètres d’accès pour administrateurs. Les formulaires existants sont conservés lors du passage entre onglets. Ces quatre écrans affichent directement leurs actions et formulaires, sans reprendre l’introduction de tuile « COCO ERP », le titre et la description du module.

L’import de produits accepte jusqu’à 3 000 lignes par fichier, pour la simulation et la confirmation. Chaque appel d’import dispose d’un délai serveur de 60 secondes, avec des recherches indexées sur le nom, la référence et le code-barres normalisés. Les doublons, erreurs par ligne et reprises conservent leurs contrôles existants. Les délais des autres opérations ne changent pas.
