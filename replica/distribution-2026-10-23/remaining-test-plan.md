
## Suite : accord B2B

- `b2b-distribution-db.test.cjs` : 7 tests isolés réussis (y compris le parent),
  entreprise/profil inactif ERP, refus, acceptation, exactitude, accès révoqué,
  répétition, obsolescence, crédit, marge et provenance Agent Coco.
- `distribution-commitments-db.test.cjs` : 13 tests isolés existants réussis.
- Portail autonome et préparation : 44 tests Playwright réussis.
- Catalogue public et portail intégré : 46 tests Playwright réussis.
- Réponse client ES/FR/EN ; largeurs 320/390/768/1440 ; revue visuelle téléphone
  et ordinateur. Axe-core WCAG2 A/AA et WCAG2.1 AA : zéro violation sur le contenu
  de la proposition en 390/1440 px (fixture locale, script de contrôle temporaire).
- `sales-concurrency.test.cjs` étendu : deux sessions clients enregistrent le même
  accord, puis deux sessions vendeurs l'appliquent ; une réponse/une substitution.
  Exécution PostgreSQL 17 dans le job CI dédié avant fusion.
- Validation globale et publication : résultats exacts conservés dans la PR et
  les exécutions GitHub/Cloudflare ; aucun test de mutation sur les données réelles.
