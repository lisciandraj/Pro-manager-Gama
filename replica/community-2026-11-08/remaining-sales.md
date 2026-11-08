# Finalisation des écarts Ventes

L’[audit initial](../../docs/history/odoo-community-sales-gaps-initial-2026-11-08.md)
constatait les absences du premier lot. Les parcours suivants sont désormais
implémentés dans les sources canoniques et vérifiés sur des bases jetables.

| Fonction | Implémentation et preuve |
| --- | --- |
| Remise globale fixe ou en pourcentage | Lignes négatives ventilées par taxe, factures partielles au centime ; `tests/sales-commercial-db.test.cjs` |
| Livraison facturée | Règles de prix, gratuité, ligne de service et facturation groupée ; même suite |
| Refacturation des dépenses | Dépenses approuvées, coût/prix de vente, lien source unique ; même suite |
| Suggestions automatiques d’options | Association produit/option ou alternative, sélection explicite ; `tests/sales-commercial.spec.js` |
| Coupons, promotions et fidélité | Règles, limites, points sur facture, avoirs et annulations ; `tests/sales-rewards-db.test.cjs` |
| Cartes cadeaux et portefeuilles | Financement par reçu réel, dette, consommation et contre-passation ; même suite |
| PDF enrichi | Import privé, champs associés, modèles, brochures et fusion réelle ; `tests/quote-document-compose.test.cjs`, `tests/quote-documents-db.test.cjs` |
| Signature commerciale distante | PDF figé et empreinte vérifiée, trois méthodes, confirmation native et reprise idempotente ; `tests/sales-checkout-db.test.cjs`, `tests/sales-checkout.spec.js` |

La couche de paiement prestataire et ses vérifications sont consignées dans le
[contrat courant](../../docs/modules/sales-accounting-community.md) et dans
`verification.json`. Une clé ou un compte marchand manquant est une configuration
à fournir avant activation, jamais un paiement à simuler.

La [matrice](features.csv) conserve le portail historique comme retrait produit
intentionnel. Les sources fonctionnelles Odoo sont listées dans [recon.md](recon.md).
Aucune migration hébergée, connexion marchande ou promotion de production n’est
effectuée par ces vérifications locales.
