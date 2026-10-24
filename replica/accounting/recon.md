# Référence et audit comptable

Consultation : 24 octobre 2026. Référence unique : **Odoo 19.0 Enterprise, Comptabilité complète**, version majeure stable documentée. Les pages `master` et `saas-*` ne servent pas de règles de calcul. Pas d'accès à une instance Odoo Enterprise : les résultats indépendants ci-dessous proviennent des comportements documentés ; une comparaison sur instance reste à faire.

Sources officielles :

| ID | Source | Usage |
| --- | --- | --- |
| O01 | https://www.odoo.com/documentation/19.0/applications/finance/accounting.html | Périmètre, rapports, partie double |
| O02 | https://www.odoo.com/page/editions | Community : socle de facturation ; Enterprise : comptabilité complète. La page ne détaille pas chaque sous-fonction : édition individuelle à confirmer lorsqu'indiquée « attribution à vérifier ». |
| O03 | https://www.odoo.com/app/accounting | Présentation ; jamais preuve d'un résultat comptable |
| O04 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/inventory_valuation.html | Valorisation périodique à la clôture / perpétuelle à la facturation ; FIFO, AVCO, standard |
| O05 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/journals.html | Journaux et comptes d'attente des paiements |
| O06 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/payments/online.html | Enregistrement, affectation et rapprochement des paiements |
| O07 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html | Rapprochement multiple, partiel, écarts et modèles |
| O08 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/vendor_bills/deferred_expenses.html | Différés : jours, mois et mois complets ; reclassement puis reconnaissance |
| O09 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/customer_invoices/deferred_revenues.html | Produits différés |
| O10 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/loans.html | Échéancier ; principal, intérêts, reclassement à 12 mois puis extourne |
| O11 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/vendor_bills/assets.html | Linéaire, dégressif, dégressif puis linéaire, modèles et prorata |
| O12 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/reporting/budget.html | Révisions ; réalisé et engagé incluant les achats non facturés |
| O13 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/reporting/analytic_accounting.html | Plans, distributions et modèles |
| O14 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/reporting/year_end.html | Contrôles et clôture |
| O15 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started.html | Comptes produits/catégories/tiers, taxes et arrondis |
| O16 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/bank_synchronization.html | Prestataires et abonnement Odoo Enterprise requis pour sa synchronisation |
| O17 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/taxes/cash_basis.html | Taxes exigibles au rapprochement et comptes transitoires |
| O18 | https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/consolidation.html | Sociétés distinctes, correspondances et livres de consolidation |

Modules fonctionnels associés à inventorier : Facturation, Comptabilité complète, Banque, Immobilisations, Différés, Emprunts, Analytique/Budgets, Ventes, Achats, Stock et Documents. Les services OCR, synchronisation bancaire et paiement dépendent de prestataires et de leurs contrats. Aucun accès ou forfait prestataire n'est déduit de la présence d'un bouton.

Le socle Facturation est distinct de la Comptabilité complète Enterprise. La colonne édition indique la référence étudiée ; elle ne signifie pas que chaque opération est exclusivement Enterprise. L'attribution Community/Enterprise de chaque sous-opération et les identifiants techniques des compléments restent à valider sur une installation/licence 19.0. Ne pas présenter cette classification encore partielle comme un audit de licences achevé.

## Coco vérifié

Base de travail : `7dfa6b422dd7eeea5161be935c0dabfb273aeebc`. Application statique JS/Vite, composants ArcUI/GamaUI, Auth/PostgreSQL/Storage Supabase, GitHub Actions → Pages. Les travaux ouverts #232, #233 et #235 sont conservés ; aucune réécriture de branche.

Production identifiée : `mknsaibrewksgomuslev`, pays EC, monnaie USD. Lecture avant intervention : 58 écritures posted, débit = crédit = 8 552,49 ; 27 transactions bancaires rapprochées, 5 ignorées et 57 non rapprochées ; une période fermée. Ce contrôle global ne prouve pas à lui seul la justesse des 58 pièces.

Le module existant comprend livres, paiements canoniques, rapprochements, imports CSV, échéances, avoirs, taxes, immobilisations, dimensions, budgets mensuels, registre de change, clôtures et contrôles de reprise. Les migrations de référence sont présentes en production, y compris les développements distribution du 23 octobre. Aucun historique n'est rejoué automatiquement par cette extension.

Écart majeur : `gama_stock_accounting_post` suit encore les mouvements physiques. Il ne démontre pas la méthode Odoo 19 à la facturation et à la clôture. Ne pas transformer ce paramètre sans inventaire des valeurs et validation de la transition.

## Écrans et parcours

S01 Vue d'ensemble ; S02 clients/factures ; S03 fournisseurs ; S04 banque/caisse ; S05 écritures/livres ; S06 rapports ; S07 configuration ; S08 contrôles/reprise ; S09 immobilisations ; S10 analytique/budgets ; S11 devises ; S12 échéanciers (différés, récurrences, emprunts).

F01 vente → facture interne → écriture → paiement → banque → balance. F02 achat → réception partielle → facture → paiement. F03 avoir/remboursement. F04 relevé CSV → rapprochement/dérapprochement. F05 acquisition → amortissement → sortie. F06 différé → validation humaine → reconnaissance → rapport. F07 modèle récurrent → échéance → pièce. F08 dette constatée → emprunt → principal/intérêts/reclassement/extourne → banque. F09 revue → clôture/verrouillage. F10 proposition Agent Coco → approbation/refus → exécution/historique.

États requis pour S01–S12 : chargement, vide, erreur avec reprise, refus serveur, liste paginée, détail, clavier, 390 px / tablette / PC, FR/ES/EN. L'interface conserve la charte Coco ; aucune comparaison de pixels avec Odoo n'est une condition de parité.

La matrice `features.csv` distingue présence du code, tests Coco et preuve d'équivalence Odoo. Une fonction partielle reste un écart, même si ses tests Coco passent. L'objectif complet représente plusieurs domaines comptables ; cette livraison ne doit pas être annoncée comme 100 % équivalente.

## Attribution des éditions : preuves supplémentaires

Les manifestes officiels de la branche **19.0** ont été consultés le 24 octobre 2026 par le connecteur GitHub, uniquement pour leurs métadonnées. Aucun fichier Odoo n'est intégré au dépôt Coco.

| Module | Métadonnée constatée | Limite de la preuve |
| --- | --- | --- |
| [account](https://github.com/odoo/odoo/blob/19.0/addons/account/__manifest__.py) | Facturation et paiements, licence LGPL-3 ; dépend d'analytic | Présence du socle Community ; ne prouve pas tous les menus ou rapports Enterprise |
| [analytic](https://github.com/odoo/odoo/blob/19.0/addons/analytic/__manifest__.py) | Comptabilité analytique, licence LGPL-3 | Les budgets et autres compléments restent distincts |
| [stock_account](https://github.com/odoo/odoo/blob/19.0/addons/stock_account/__manifest__.py) | Intégration stock/comptabilité, LGPL-3 ; dépend de stock et account | Ne prouve pas la concordance des traitements actuels de Coco avec les règles 19.0 |
| [account_accountant / account_reports](https://www.odoo.com/documentation/19.0/fr/developer/howtos/accounting_localization.html) | La documentation distingue les rapports fiscaux accessibles via Comptabilité Enterprise | Les identifiants et licences de tous les compléments avancés n'ont pas été inspectés sur une instance licenciée |

La matrice précise les socles Community documentés tout en conservant Enterprise comme référence fonctionnelle. Une dépendance partagée n'est pas une preuve d'exclusivité d'édition. Les développements récents `cf03d88` et `74a2610` ont été intégrés avant la CI.
