# Tableau de bord de pilotage

Le tableau de bord rassemble les données autorisées de 18 sources métier dans une seule lecture. Il conserve les composants, les couleurs, les droits et les langues de l’ERP. Les quatre indicateurs personnalisables du menu principal restent indépendants.

## Lecture

- Période commune : mois courant, mois précédent, 30 derniers jours, année en cours ou dates personnalisées, jusqu’à 731 jours inclus. Comparaison avec la période précédente de même durée.
- En tête : facturation HT avant avoirs, encaissements TTC confirmés, reste à encaisser actuel, commandes confirmées créées pendant la période. Pour le magasinier : commandes, disponibilité et livraisons.
- Priorités du jour : impayés, retards, ruptures, SAV, projets, échéances, absences et retours. Six catégories visibles, avec accès à la liste complète et aux modules. Les catégories ne sont pas additionnées : elles peuvent concerner les mêmes dossiers.
- Factures et encaissements TTC sur le même graphique, avec tableau accessible des valeurs exactes. Pas de comparaison trompeuse entre HT et TTC.
- Trésorerie : soldes enregistrés par devise, dettes fournisseurs nettes d’avoirs et dépenses comptabilisées. Les devises ne sont pas converties ni additionnées. Les remboursements du module Retours n’ayant pas de compte financier associé sont exclus des soldes de comptes. Ces soldes ne représentent ni un solde bancaire rapproché ni le bénéfice.
- Activités : ventes, commandes, devis, CRM, clients, fournisseurs, produits, stocks, achats, TMS, Fleet, projets, RH, retours, SAV, Documents et Knowledge.

Les fonctions de paramétrage, d’import/export, de génération de codes et d’assistance ne créent pas de séries métier supplémentaires. Les modules de suivi ou de préparation s’appuient sur les commandes et les mouvements déjà comptabilisés.

## Sources et définitions

| Domaine | Source principale | Définition |
|---|---|---|
| Facturation | `external_invoices` | Registre commun des factures internes et externes ; exclusion des annulées et rejetées ; référence externe sans double compte |
| Encaissements | `external_invoice_payments` | Paiements confirmés des factures valides, selon `paid_at` |
| Créances | Factures, paiements, `return_credits` | Solde positif de chaque facture après paiements et avoirs ; échéance dépassée pour les impayés |
| Commandes | `sales_orders`, lignes et livraisons | Commandes confirmées ; quantités restantes à expédier |
| Stocks | `products`, `stock_quants` | Physique moins réservé ; sous le minimum et disponibilité nulle ou négative |
| Achats | `purchase_orders` | Commandes envoyées ou partielles ; date attendue dépassée |
| TMS | `tms_deliveries` | Livraisons terminées sur la période et retards actuels hors annulations |
| Fleet | Véhicules, documents, carburant, entretien | Parc actif, documents échus ou à échéance sous 30 jours, coûts enregistrés sur la période |
| Projets | `pm_projects`, `pm_items` | Projets actifs, projets et tâches non terminés en retard, dans le périmètre visible |
| RH | Employés et absences | Données globales réservées aux responsables RH autorisés ; pas de détail nominatif des absences |
| SAV / Documents | `service_tickets`, `business_documents` | Dossiers ouverts, échéances et documents visibles selon les RLS, y compris la confidentialité direction |
| Comptabilité | Factures fournisseurs, paiements, avoirs, dépenses et comptes | Périmètre comptable complet uniquement ; dépenses et soldes séparés par devise |

Les dates de métier sont calculées en `America/Guayaquil`, comme les autres agrégations de l’ERP. Les soldes, stocks et alertes sont actuels, même lorsqu’une période passée est sélectionnée. Une facture annulée ultérieurement est exclue : il ne s’agit pas d’une reconstitution comptable historique figée.

## Architecture et fiabilité

`architect-dashboard.js` appelle `gama_company_dashboard(from, to)`. La fonction est `SECURITY INVOKER`, avec un `search_path` vide et un droit d’exécution limité aux comptes authentifiés. Elle vérifie l’accès au tableau de bord, les modules activés, le rôle métier, le profil d’accès personnalisé et le périmètre comptable/RH. Les politiques RLS des tables continuent à s’appliquer.

Les agrégations sont exécutées dans la base, sans limite de pagination du navigateur et sans copie des données. Paiements et avoirs sont regroupés avant les jointures pour empêcher les multiplications de montants. Une source en erreur devient `null` et est signalée ; elle n’est jamais remplacée par zéro.

Le navigateur ignore les réponses devenues obsolètes, efface les données lors d’un changement d’accès ou de compte, et propose une nouvelle tentative en cas d’échec. Les chargements ne sont déclenchés que lorsque l’écran est actif ; les appels répétés du rendu historique sont regroupés. Revenir au tableau de bord recharge les données.

## Vérification

- `tests/dashboard-db.test.cjs` : restauration complète, montants, annulations, plusieurs paiements et avoirs, découpage mensuel, fuseau horaire, référence externe, monnaies distinctes, RLS Documents, profils personnalisés, accès refusés et source indisponible.
- `tests/dashboard-analysis.spec.js` : période partagée, graphiques, priorités, mobile/paysage, accès aux actions, erreurs et réponses obsolètes.
- Les tests du tableau de bord font partie du contrôle de publication de l’interface.
