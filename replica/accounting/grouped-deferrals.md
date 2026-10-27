# Différés : mois complets et clôture groupée

Référence figée : Odoo 19.0 Enterprise, [charges différées](https://www.odoo.com/documentation/19.0/fr/applications/finance/accounting/vendor_bills/deferred_expenses.html) et [produits différés](https://www.odoo.com/documentation/19.0/applications/finance/accounting/customer_invoices/deferred_revenues.html), consultés le 27 octobre 2026.

Extension des échéanciers natifs existants. Le mode individuel conserve son comportement ; le mode groupé est choisi explicitement à la création, sans reprise automatique des plans historiques. Une même ligne source ne peut financer simultanément plusieurs plans au-delà de son montant disponible.

Les mois complets incluent le premier mois commencé. Un dernier mois incomplet distinct du premier est exclu ; la période minimale reste un mois. Le dernier centime est attribué au dernier mois retenu. Les dates et calculs restent côté PostgreSQL NUMERIC.

La revue groupée présente par plan le montant source, la fraction reconnue et le solde à différer à une fin de mois, puis agrège par compte et journal. Seules les pièces déjà comptabilisées à cette date participent. Un brouillon relie la clôture et son extourne du lendemain. La validation humaine contrôle de nouveau les sources et les verrouillages. L'extourne future reste en brouillon jusqu'à son échéance ; l'exécution déléguée revérifie les droits de la personne ayant approuvé.

Exemple de recette indépendant : deux charges annuelles de 1 200 et 600 USD, plus 600 USD débutant l'année suivante. Au 31 janvier : 150 USD reconnus et 2 250 USD différés. Au 28 février : 300 USD reconnus et 2 100 USD différés. Chaque clôture a son extourne le lendemain. Les écritures individuelles et groupées ne coexistent pas pour le même plan.

Les états vides, refus d'accès, erreurs, pagination, aperçu périmé, double validation et annulation contrôlée sont couverts par les tests isolés décrits dans [results-grouped-deferrals.md](results-grouped-deferrals.md). Les revues et leurs sources sont paginées par 50 ; les totaux restent calculés sur l'ensemble des sources. Aucune écriture d'équilibrage ni aucune opération réelle de test en production.

Accès : Comptabilité → Comptabilité → Échéanciers → Clôture groupée. Le formulaire d'échéancier propose les modes individuel/groupé et les calculs par jour, mois ou mois complet. Chaque revue donne accès aux sources, à l'échéancier et aux pièces générées, avec liens de retour et historique. La création automatique depuis les lignes de factures reste un écart séparé, H14.
