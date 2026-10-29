# Différés depuis les factures — H14

Référence : Odoo 19.0 Enterprise, documentation des [produits différés](https://www.odoo.com/documentation/19.0/applications/finance/accounting/customer_invoices/deferred_revenues.html) et [charges différées](https://www.odoo.com/documentation/19.0/applications/finance/accounting/vendor_bills/deferred_expenses.html), consultation du 27 octobre 2026. Aucune source logicielle Odoo n'est utilisée.

Chaque ligne concernée porte une date de début et une date de fin. La configuration choisit séparément pour charges et produits un journal, un compte de report, un calcul par jours/mois/mois complets et un traitement individuel automatique ou groupé. À la validation d'une facture, Coco crée les échéanciers et leurs liens dans la même transaction. Le traitement individuel comptabilise le reclassement à la date comptable de la facture, puis utilise le planificateur existant. Le traitement groupé alimente la revue de clôture existante.

## Intégration native

- Ventes : dates facultatives dans la préparation de facturation, figées dans les lignes du document interne. Les montants proviennent du calcul serveur des quantités et prix ; les déductions d'acompte restent distinctes.
- Fournisseurs : ventilation facultative de la base hors taxes en lignes différées, dans la saisie directe et la revue des brouillons issus de réception. La base non ventilée reste immédiatement reconnue. Les quantités et le rapprochement des achats conservent leur moteur existant.
- Configuration → Différés de factures : aucun compte ou journal n'est choisi à la place du comptable. Sans dates, les parcours historiques restent identiques ; avec dates, une configuration absente provoque une erreur explicite.
- Facture → échéancier → facture/écriture : références natives conservées, sans deuxième registre de factures ou de paiements.

## Garanties et reprise

La création et la validation exigent les droits comptables et MFA existants. Une proposition IA ne valide pas de plan. Les paramètres nécessitent une approbation humaine ; ils sont figés dans chaque échéancier et ne modifient pas les plans précédents. Montants NUMERIC, verrous de source et unicité de ligne assurent l'atomicité et empêchent une seconde allocation. Une annulation de facture exige d'abord la correction des plans liés, selon les contrôles existants.

Les dates métier sont des DATE. Une facture tardive peut couvrir une période déjà commencée ; ses reconnaissances échues ne précèdent jamais sa date comptable. Les taxes ne sont pas différées. Les périodes verrouillées font échouer la transaction entière. Les échéanciers actifs restent protégés contre la modification des sources.

Migration additive : paramètres privés et références de facture sur les échéanciers ; ventilation vide sur les factures fournisseurs existantes. Aucun historique n'est rejoué, aucun compte ni montant inventé. Avant production : sauvegarde ciblée, restauration isolée, tests chiffrés, droits, concurrence et empreintes des données avant/après. Retour arrière web possible en conservant les nouvelles données ; une correction SQL passe par une migration supplémentaire.

## Recette indépendante

Une base de 1 200 USD sur douze mois produit 12 reconnaissances de 100 USD et un reclassement de 1 200 USD, sans différer la taxe. Deux lignes 1 200 + 600 d'une facture de 2 000 laissent 200 immédiatement reconnus. En mode groupé, elles produisent 1 650 à différer fin janvier. Les essais doivent couvrir reprise d'appel, validation simultanée, dates incomplètes, ventilation excédentaire, permissions, IA non approuvée, facture annulée, paramètres modifiés, période verrouillée, trois langues et trois largeurs.

Les dates sont actuellement reliées au compte de charge ou produit unique généré par le moteur natif de la facture. Une source comportant plusieurs comptes de résultat est refusée explicitement, sans choisir un compte arbitraire. Les avoirs ne disposent pas encore d'une ventilation de différés ; cette extension reste visible en H14. La correction complète d'une facture avec échéancier exige l'annulation motivée de ce dernier avant celle de la facture, en conservant les pièces originales et les contre-écritures.

État : implémentation et tests isolés réalisés ; contrôles CI et publication en cours. Voir [les résultats](results-invoice-deferrals.md). H14 reste **partiel** tant que les variantes ci-dessus ne sont pas démontrées.
