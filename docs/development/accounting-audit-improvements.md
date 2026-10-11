# Améliorations comptables du 11 octobre 2026

Les actions de l’audit sont accessibles depuis **Administration → Comptabilité → Contrôles et préparation**. Les écrans sont chargés à la demande. Les migrations ajoutent des contrôles et des métadonnées ; elles ne réécrivent aucun montant validé et ne rouvrent aucune période.

| Action | Comportement livré |
| --- | --- |
| A01 | Inventaire des pièces et ouvertures sans écriture. Régularisation idempotente avec date de correction, date originale conservée et motif audité. |
| A02 | Solde de chaque banque issu du grand livre. Liaison explicite de la ligne au compte financier, apports, ajustements et virements entre comptes. |
| A03 | Indicateurs de produits, charges et résultat issus des écritures, rechargés à l’ouverture. Comparaison du mois précédent arrêtée au même jour. |
| A04 | Monnaie de base verrouillée côté serveur après la première écriture ; verrou partagé entre changement de monnaie et comptabilisation. |
| A05 | Banque paginée avec recherche, compte, import, dates et montants ; export de toutes les pages filtrées. |
| A06 | Revue de chaque relevé avec soldes initial/final, dates, justificatif, contrôle arithmétique et différence avec le livre à la date. |
| A07 | Correspondances groupées, encaissement de plusieurs factures d’un même client, règlements de plusieurs factures fournisseurs et écritures de frais/intérêts. |
| A08 | Valeur du stock calculée à la date. Activation explicite des coûts FIFO/coût moyen et des écritures réception/stock, consommation et compensation du reçu non facturé. Traitement des retours et verrouillage des comptes déjà utilisés. |
| A09 | Contrôles serveur communs à la clôture mensuelle et annuelle. Anomalies bloquantes, explication des différences bancaires et archivage de la revue conservé après réouverture. |
| A10 | Lecture de tout le livre indépendante de la création/validation. Droit de paiement distinct avec refus serveur. |
| A11 | Préparation fiscale, obligations et configuration SRI de test visibles ; enregistrement des preuves d’essais et du caractère applicable. Aucune autorisation SRI n’est simulée. |
| A12 | Dossier PDF/XLSX avec comparatif annuel, bilan, résultat, trésorerie classée, balance, grand livre, journal, tiers et contrôles. Livres entièrement paginés ; export interrompu si les données changent. Détail d’une écriture depuis les livres. |
| A13 | Accès direct aux outils existants OCR, relances, prévision sur 13 semaines et rentabilité ; revue d’acceptation avec preuve. |
| A14 | Centres de coûts, agences et familles de produits ; affectation des lignes sans modifier leurs montants, budgets mensuels, écarts, DSO et rotation du stock. |
| A15 | Montant étranger et taux historique liés à une facture en monnaie de base ; règlements partiels au taux réel, écart de change et arrondi final exact. |
| A16 | Plans mensuels avec prorata et centime final, dépréciation, vente/mise au rebut, sortie des amortissements et TVA. Une facture de cession existante est reclassée sans doubler sa TVA ou son encaissement. |

## Configuration et preuves

Les coûts, soldes d’un relevé, dimensions, budgets, taux de change et politiques d’amortissement demandent une donnée vérifiée. Leur présence dans l’interface n’active pas de valeur supposée. La couverture historique du stock est signalée comme incomplète avant l’ouverture constatée ou si des produits ne sont pas valorisés.

Le compte financier d’une ancienne ligne est déduit seulement de sa pièce source ou d’une correspondance unique avec le plan comptable. Les cas ambigus restent à affecter avec un motif ; les écritures validées ne sont pas modifiées.

Un remboursement direct reprend les produits et la taxe de la vente ; un remboursement précédé d’un avoir solde la créance correspondante. Les remboursements partiels répartissent ces montants sans doubler la reprise de la vente. Un avoir supplémentaire après une reprise directe déjà comptabilisée est refusé et demande une revue. La configuration du stock permet de rechercher tout le catalogue par nom ou référence, au-delà de la première page.

La préparation SRI demande le RUC, l’identité légale, les obligations confirmées, le prestataire privé et sa signature. Les essais réels de facture, avoir, retenue, guide et leurs XML/RIDE, ainsi que la revue ATS et 103/104, restent à effectuer avec ces éléments. Le panneau ne transmet ni déclaration, ni document fiscal, ni message client. Les préférences de relance restent gérées par l’outil existant.

Les soldes des tiers exportés sont la situation de gestion au moment de la génération, explicitement indiquée dans le dossier. Les états et livres utilisent la période sélectionnée. Les banques de règlement de devises restent dans la monnaie de base ; le registre conserve les montants étrangers et les deux taux, sans convertir le paramétrage global.

## Contrats et droits

Façade publique : `gama_accounting_audit(p_action, p_data)`, invocateur. Helpers et nouvelles tables restent dans `private`, avec RLS et sans accès direct `anon`/`authenticated`. Toute mutation vérifie Auth, MFA, module, périmètre, permission, puis lie `request_key` à l’acteur, l’action et le contenu. Les montants comptabilisés utilisent les mêmes livres et contrôles de période que les flux existants.

`accounting_permissions.can_read_all` élargit la consultation sans conférer de mutation. `can_pay` sépare les règlements ; une valeur héritée `NULL` conserve le comportement antérieur de `can_create`. L’activation comptable du stock nécessite modification et validation. La clôture requiert le droit de clôture ; les avertissements sont expliqués et archivés, les anomalies bloquantes doivent être corrigées.

Sources : `src/features/finance/accounting.js`, `src/features/finance/accounting-audit.js`, `src/domain/accounting-export.js`. Les deux derniers deviennent `coco-accounting-audit.js` et `coco-accounting-export.js` au build, sans ajout au démarrage.

## Validation

`tests/accounting-audit-db.test.cjs` exerce les soldes et contrepassations, virements avec compte comptable partagé, verrou de monnaie, reprise en période ouverte, relevés, rapprochements/règlements groupés, droits, budgets, devises, immobilisations et stock dans une base isolée. Il vérifie aussi les refus de clôture et la persistance des revues. `tests/accounting-export.test.cjs` ouvre le ZIP OOXML avec une bibliothèque indépendante et vérifie les dernières lignes du PDF. Les tests historiques et navigateur complètent ces contrôles.
