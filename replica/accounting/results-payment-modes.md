# Paiements — preuves du lot du 25 octobre 2026

Référence : Odoo 19.0 Enterprise, périmètre Comptabilité. Règles et écarts :
[payment-modes.md](payment-modes.md). Livraison :
[PR 246](https://github.com/lisciandraj/Pro-manager-Gama/pull/246).

## Tests observés

- Base isolée : **26 tests ciblés réussis** après correction, incluant 16
  des traitements, 8 de rapprochement depuis facture et 2 de compatibilité.
- CI `40204766828` : **79 parcours navigateur réussis**, dont neuf nouveaux
  ES/FR/EN × 390/768/1440. Axe et absence de débordement vérifiés.
- Même CI : PostgreSQL 17, deux sessions réelles. Une seule réservation de
  60 réussit sur une dette de 100 ; un seul rapprochement du même paiement
  réussit. Numérotation, verrouillage et plans existants passent également.
- La validation générale a trouvé deux ambiguïtés SQL et une différence de
  code d'erreur d'accès. Corrections faites et tests ciblés verts ; validation
  complète du dernier commit requise avant fusion.

Les captures [PC](evidence/accounting-payment-method-fr-1440.png) et
[téléphone](evidence/accounting-payment-method-fr-390.png) utilisent uniquement
des données fictives de CI. Elles montrent le haut de l'écran ; les tests
défilent ensuite et exécutent les formulaires.

## Migration installée

`20261025151430_accounting_payment_modes`, 41 442 octets UTF-8, SHA-256 :
`a4f8a4981acbce3ae5b7591e04c3c48e6d1b161d15b96aca67fef2a43ef43c68`.
Version attribuée par Supabase et archive dans `supabase/sql/applied/`.
Ces octets sont immuables.

Contrôle à 15:15 UTC : **58 écritures, 138 lignes, 8 552,49 USD au débit et
au crédit, zéro déséquilibre**. Empreintes identiques des neuf collections
historiques avant/après : écritures, lignes, comptes, paiements clients,
acomptes, paiements fournisseurs, transactions, groupes et sources bancaires.
Preuves : [avant](evidence/payment-modes-before-migration.json),
[après](evidence/payment-modes-after-migration.json).

Trois nouvelles tables vides : aucun paramètre activé et aucune opération
métier créée en production. RLS active, accès direct client refusé. Le RPC
anonyme renvoie HTTP 401/code 42501. Les deux avertissements de sécurité
existants sont inchangés.

## Publication et reprise

Le commit publié et les empreintes servies seront consignés dans la PR après
déploiement. La navigation authentifiée de production n'est pas attestée avec
la session disponible ; les parcours authentifiés ci-dessus utilisent les
RPC réels en base isolée.

Conserver le processus GitHub Pages. Un retour de version de l'interface ne
doit ni rejouer ni supprimer cette migration, les traitements figés ou les
contre-écritures. Après activation de paramètres, préférer une correction en
avant et conserver le moteur de liquidation. La sauvegarde ciblée précédente
ne constitue pas une sauvegarde physique/PITR ; N05 reste ouvert avant toute
reprise structurelle de l'historique.

B14/E05 restent partiels pour les méthodes personnalisées multiples de même
famille et les résiduels bancaires sur plusieurs dates. Ce lot ne prouve pas
une équivalence complète à Odoo 19.
