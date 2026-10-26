# Complément d’audit : journaux et banque en attente

Référence figée : Odoo 19.0 Enterprise. [Rapprochement bancaire, section Transactions](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html), consultée le 26 octobre 2026. Ce complément étend l’inventaire ; il ne décrit pas une fonctionnalité déjà livrée.

## Écart explicite F12

La référence crée une écriture banque/compte d’attente pour chaque transaction bancaire, avant son rapprochement. Le rapprochement remplace ensuite sa contrepartie par le tiers, paiement ou compte choisi. Coco conserve actuellement les transactions importées dans `bank_transactions` et comptabilise leurs traitements métier ensuite. Les nouvelles portions datées de la PR 248 ne changent pas cette politique d’import. Le rapprochement partiel testé ne démontre donc pas cette autre capacité.

Preuves Coco : l’import de `gama_bank_invoice_action` délègue à `bank_import` et mémorise sa réponse. Les sources admissibles à la comptabilisation n’incluent pas les transactions bancaires brutes. La trésorerie comptable repose sur `gama_cash_ledger`, tandis que les transactions non rapprochées restent un contrôle séparé. Sources : migrations `20261005001842_ec_bank_statement_invoice_matching.sql` et `20261011211512_accounting_audit_core.sql` ; parcours existant `tests/bank-invoice-db.test.cjs`.

F12 reste **à développer**. L’activation exigera un compte d’attente configuré et une reprise qui distingue les lignes non rapprochées, les portions de groupes actifs, les paiements déjà comptabilisés directement en banque et les traitements attente/sans écriture. Aucun compte, taux ni ajustement historique ne doit être choisi implicitement. Chaque différence devra avoir une cause et une pièce traçables.

Critères chiffrés à tester indépendamment : importer 100 donne banque +100 et attente -100 ; affecter 40 laisse 60 en attente ; affecter le reliquat solde l’attente ; réimporter ne crée rien ; un paiement déjà passé en banque ne double pas le solde ; annuler un groupe libère seulement sa portion. Ajouter plusieurs dates, mouvements opposés, frais réels, verrouillages, permissions et concurrence. Comparer les écritures et les soldes avant/après sur une reprise isolée peuplée.

## Tableau de bord A02 : intégration préparée

Les résultats et la trésorerie actuels lisent déjà le grand livre ; les priorités ouvrent certaines listes filtrées. Les cartes par journal et toutes les activités restent partielles. Réutiliser les journaux, comptes financiers, listes, filtres et composants Coco, sans second agrégat persistant ni nouvelle navigation globale.

Prévoir par journal ses écritures et montants de période, brouillons et documents à traiter ; pour banque/caisse, le solde du livre, les transactions et leur reliquat non rapproché. Les liens doivent reprendre le journal, le compte financier, les dates et l’état exacts. Ne pas présenter les soldes avant rapprochement comme équivalents à Odoo tant que F12 manque. Les profils limités gardent leur périmètre ; aucune donnée de trésorerie ou fournisseur ne doit leur être révélée.

Cette préparation n’ajoute ni écran, ni calcul de production. La matrice contient maintenant 108 points : 54 testés, 29 partiels, 21 à développer, trois bloqués et une exclusion SRI explicite. L’inventaire reste à approfondir sur une instance Enterprise autorisée pour les comportements non documentés.
