# Moyens de paiement et règlements en attente

Référence fonctionnelle : Odoo **19.0 Enterprise**, documentation consultée le
25 octobre 2026 : [paiements](https://www.odoo.com/documentation/19.0/applications/finance/accounting/payments/online.html)
et [journaux](https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/journals.html).
Implémentation originale dans la base et les composants existants de Coco.

## Contrat

- Un paramètre distingue compte financier, moyen et sens entrant/sortant.
- Trois traitements : banque directe, compte d'attente, sans écriture.
- Une configuration absente préserve le traitement Coco historique. Aucun
  paiement, compte ni solde existant n'est reclassé par la migration.
- Le traitement et les comptes sont figés à l'enregistrement du paiement.
  Modifier la configuration ne recalcule jamais une pièce antérieure.
- En attente : le tiers est soldé par l'écriture de paiement ; la trésorerie
  ne varie qu'au rapprochement. Sans écriture : le montant dû reste ouvert
  jusqu'au rapprochement. Un acompte sans écriture ne peut être affecté.
- Le rapprochement ne crée que le transfert restant à comptabiliser ; un
  règlement déjà comptabilisé en banque ne produit pas un second mouvement.
- L'annulation du rapprochement contre-passe son transfert et conserve le
  règlement. Annuler ensuite le règlement exige de défaire le rapprochement.
- Une proposition d'Agent Coco ne peut changer directement les paramètres.

## Architecture et preuves

Les tables privées de paramètres et de traitement figé complètent les tables
canoniques de paiements. Elles ne constituent pas un second registre de
factures. Les RPC existantes conservent leurs noms et droits. Partie double,
verrouillages, numérotation et historique passent par les contrôles communs.

`tests/accounting-payment-modes-db.test.cjs` vérifie les trois traitements,
paiements partiels, acomptes, réutilisation d'une intention lors d'un règlement
depuis la banque, annulation, isolation, historique et reprise idempotente.
Les montants attendus sont indépendants du code : facture 100, règlement 40,
acompte 150. `tests/accounting-payment-modes.spec.js` parcourt la configuration,
le règlement client, le rapprochement et son annulation sur une vraie base de
test, en ES/FR/EN à 390/768/1440 px. La CI PostgreSQL utilise deux sessions pour
la réservation concurrente d'une dette de 100 et le rapprochement d'un même
paiement de 60. Résultats de CI et publication à consigner après exécution.

## Écarts encore ouverts

- Les cinq moyens canoniques de Coco sont configurables par compte financier
  et sens. Plusieurs méthodes de même famille avec des noms libres, et la
  préférence d'une méthode personnalisée sur le contact, restent à ajouter.
- Un groupe qui liquide ces nouveaux traitements doit porter sur une même
  date bancaire. Le serveur refuse plusieurs dates au lieu de déplacer les
  mouvements vers une date commune. Le rapprochement avec résiduels et
  affectations datées distinctes demeure en F06.
- Fichiers de lots SEPA/NACHA, prélèvements et prestataires : E07/M03–M05.
- Les propositions de changement de paramètres passent encore par une personne
  dans l'interface ; leur raccordement à la file Agent Coco reste en N02.

B14 et E05 restent donc explicitement **partiels**, même lorsque les scénarios
de ce lot sont verts. Il ne s'agit pas d'une attestation de parité intégrale.
