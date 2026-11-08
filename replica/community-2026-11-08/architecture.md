# Architecture du complément Community

Le [recon](recon.md) et la [matrice](features.csv) distinguent existant,
implémentation à vérifier et écarts restants. Le périmètre étudié et les sources
Odoo sont explicites ; aucune ressource graphique ou implémentation Odoo n'est copiée.

## Décisions

1. Conserver la stack et les contrats Coco : JavaScript canonique sous `src/`,
   ArcUI, exports PDF différés, trois langues, façades PostgreSQL existantes.
2. Pro forma : option explicite de document dans le générateur PDF existant,
   même instantané commercial que le devis, titre et mention propres ; lecture seule.
3. Modèles : recherche locale sur la liste autorisée existante et archivage
   via `gama_sales_workspace('template_delete')`, sans suppression des devis.
4. Copie : prix relus au tarif de la date de copie et provenance redevenue
   automatique ; aucune mise à jour du devis d'origine.
5. Remise : appliquer un pourcentage borné aux lignes du brouillon ; les
   quantités, prix manuels, motifs et taux restent ceux de la saisie existante.
6. Taxes : migration additive locale et correction de la commande `tax_save`
   dans sa chaîne de contrôle existante. Aucune réécriture de migration appliquée,
   aucune modification des factures ou écritures historiques.
7. Comptes tiers : préférences privées clients/fournisseurs, intégrées au livre
   existant. Les règlements et corrections relisent le compte de la facture
   d'origine ; affecter une avance sur une autre créance requiert un transfert
   équilibré, sans second mouvement de trésorerie. Les comptes produits et
   catégories ne sont pas couverts par cette tranche.

## Vérification et publication

Tests métier serveur sur bases jetables restaurées par `scripts/restore-schema.cjs`.
Tests navigateur sur serveur local avec transport simulé et actifs compilés.
Les tests simulés ne sont pas une preuve d'émission fiscale, d'envoi d'email ou
de paiement réel. Compilation et contrôles communs du dépôt avant commit.

Livrer une branche de travail et une PR révisable ; conserver les gates CI
existants. Une migration locale n'est pas présentée comme appliquée à la base
hébergée et une branche poussée n'est pas présentée comme publiée en production.
