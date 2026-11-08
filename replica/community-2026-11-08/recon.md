# Ventes et facturation — référence Community

Demande : compléter les modules Ventes et Comptabilité de **Coco ERP**, dépôt
`lisciandraj/Pro-manager-Gama`. Revue du 8 novembre 2026. Référence fonctionnelle
explicite **Odoo 19.0 Community**, cohérente avec les comparaisons déjà présentes
dans le dépôt ; ce document ne présente pas 19.0 comme la dernière version.

## Sources et frontière de comparaison

| Source publique officielle | Utilisation |
| --- | --- |
| [Éditions](https://www.odoo.com/page/editions) | Distinguer facturation et comptabilité complète ; les pages du manuel peuvent décrire les deux éditions |
| [Ventes 19.0](https://www.odoo.com/documentation/19.0/applications/sales/sales.html) | Devis, produits, prix, commandes et facturation |
| [Pro forma](https://www.odoo.com/documentation/19.0/applications/sales/sales/invoicing/proforma.html) | Document commercial distinct de la facture |
| [Modèles de devis](https://www.odoo.com/documentation/19.0/applications/sales/sales/sales_quotations/quote_template.html) | Réutilisation de contenu commercial |
| [Remises](https://www.odoo.com/documentation/19.0/applications/sales/sales/products_prices/prices/discounts.html) | Trois modes distincts ; le lot livre le pourcentage sur toutes les lignes |
| [Taxes](https://www.odoo.com/documentation/19.0/applications/finance/accounting/taxes.html) | Configuration, activation et comptes de taxes |
| [Positions fiscales](https://www.odoo.com/documentation/19.0/applications/finance/accounting/taxes/fiscal_positions.html) | Substitutions de comptes et taxes ; reste à construire dans Coco |
| [Factures clients](https://www.odoo.com/documentation/19.0/applications/finance/accounting/customer_invoices.html) | Création et traitement des pièces clients |

La matrice [historique comptable](../accounting/features.csv) porte sur un
périmètre **Enterprise** beaucoup plus large. Son score historique de 67,1 %
n'est donc pas un score Community et n'est pas recalculé à partir de ce petit lot.
Les fonctions OCR, synchronisation bancaire, consolidation, abonnements et
signature dédiée nécessitent une vérification séparée d'édition et/ou de service.
Les accès clients ont été retirés explicitement de Coco : cette livraison ne les
réactive pas pour améliorer artificiellement un score.

La documentation officielle décrit également les [programmes promotionnels](https://www.odoo.com/documentation/19.0/applications/sales/sales/products_prices/loyalty_discount.html),
les [cartes cadeaux et portefeuilles](https://www.odoo.com/documentation/19.0/fr/applications/sales/sales/products_prices/ewallets_giftcards.html),
la [facturation du transport](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/shipping_receiving/setup_configuration/new_delivery_method.html),
la [refacturation des dépenses](https://www.odoo.com/documentation/19.0/applications/finance/expenses/reinvoice_expenses.html)
et les [devis PDF enrichis](https://www.odoo.com/documentation/19.0/applications/sales/sales/sales_quotations/pdf_quote_builder.html).
Leur [audit complémentaire dans les sources Coco](remaining-sales.md) confirme
les écarts de transport facturé, refacturation, programmes de récompenses,
suggestions et composition PDF. Elles ne sont ni déclarées livrées, ni éliminées
par une attribution Enterprise non démontrée.

## Inventaire des écrans étudiés

| ID | Écran Coco | Composants et états pertinents |
| --- | --- | --- |
| S01 | Ventes → Devis | Recherche, filtres, pagination, vide, erreur ; liste commune demandes/devis |
| S02 | Fiche du devis | Révision et conditions figées, PDF, copie, modèles, erreur d'export |
| S03 | Éditeur du devis | Client, lignes, tarifs, remises, TVA, brouillon et validation existante |
| S04 | Modèles de devis | Recherche, utilisation, archivage confirmé, vide et reprise après échec |
| S05 | Commandes et À facturer | Quantités, factures partielles/groupées, acomptes, crédit et annulations existants |
| S06 | Comptabilité → Impôts | Liste et formulaire de taxes, comptes, validité, archivage et permissions |
| S07 | Comptabilité → Configuration → Comptes des contacts | Clients/fournisseurs, recherche paginée, compte dédié ou général, lecture seule et erreurs |

## Parcours et invariants

- F01 : fiche du devis → télécharger pro forma → PDF commercial. Aucune création
  de facture, validation de commande, preuve de paiement ou émission SRI.
- F02 : liste → modèles → rechercher → utiliser ou archiver. Archiver conserve
  les documents existants ; un échec conserve le modèle à l'écran et autorise un nouvel essai.
- F03 : devis → copier → nouveau brouillon au tarif actuel. Un tarif recalculé
  ne conserve pas un marqueur de prix manuel appartenant au document source.
- F04 : brouillon → remise sur toutes les lignes → revue des totaux → sauvegarde
  via le moteur et les approbations existants. Une remise en pourcentage remplace
  les remises de ligne ; elle ne crée pas une ligne de montant négatif.
- F05 : liste des taxes → créer/modifier → enregistrer → archiver/réactiver.
  Les comptes et dates doivent être validés au serveur ; les pièces historiques
  restent intactes et les permissions de création et modification sont distinctes.
- F06 : comptes des contacts → choisir client/fournisseur → définir un compte
  dédié ou revenir au paramétrage général. Les futures pièces utilisent ce
  choix ; les paiements et corrections des anciennes factures gardent leur
  compte d'origine.

## Modèle réutilisé et limites structurelles

Les devis restent `invoices`/`invoice_lines`, les modèles
`private.sales_templates`, les factures `external_invoices` et les taxes
`accounting_taxes`. Les prix, remises et validations restent calculés par les
façades existantes. Aucun registre de factures parallèle et aucune donnée de
démonstration ne sont ajoutés à la production.

Une facture client autonome est un véritable écart : `external_invoices.order_id`
et ses lignes exigent actuellement une commande, et plusieurs consommateurs de
paiement, retours et SRI reposent sur ces liens. Créer une commande fictive ne
résoudrait pas cet écart. Il faut faire évoluer ces contrats et leurs tests
ensemble. Le moteur des taxes incluses/fixes/composées, les positions fiscales,
l'escompte et les comptes hérités des produits/catégories nécessitent aussi une
intégration comptable complète, distincte des taxes et des comptes tiers livrés ici.

Cette revue est un inventaire ciblé vérifié dans les sources, pas une preuve de
parité exhaustive. Les statuts et leurs preuves sont dans [features.csv](features.csv).
