# Promotions, fidélité et soldes prépayés

Les programmes se configurent dans Ventes → Configuration → Programmes et soldes. Les devis enregistrés proposent Codes et fidélité. Les factures proposent le règlement par carte cadeau ou portefeuille. L’interface utilise les composants existants en français, espagnol et anglais.

## Programmes et devis

- Promotions automatiques à l’enregistrement du devis et lors d’un changement de livraison ou de remise globale.
- Coupons avec code, date de validité, client éventuel et limite d’utilisation. Les codes émis peuvent être suspendus, réactivés et prolongés avec motif. Seule la fin du code est relue ; son empreinte SHA-256 reste privée.
- Conditions de montant hors taxe, quantité, produit, catégorie et client. Dates de début/fin, plafond de réduction, limites globales et par client, cumul autorisé explicitement pour tous les programmes concernés.
- Récompenses en pourcentage, montant fixe, livraison offerte ou unités offertes d’un produit présent dans le devis. Les unités offertes font partie de la quantité réelle du produit : elles conservent la réserve et le suivi d’expédition. Leur réduction cible le produit concerné ; elle ne crée pas de marchandise sans origine.
- Chaque réduction devient une ligne commerciale du devis, du bon de commande et des factures partielles. Sa répartition fiscale et les centimes résiduels suivent le moteur commercial et fiscal commun.
- Un coupon ou une récompense devenu obsolète après modification du devis/programme bloque l’envoi ou l’acceptation jusqu’à sa révision. Les usages et les points ne sont consommés qu’à l’acceptation réussie, une seule fois.

Les points sont gagnés sur les factures réellement comptabilisées, selon le montant éligible hors taxe. Les acomptes ne génèrent pas de points. Les avoirs, remises comptables et extournes diminuent les points gagnés ; une dette de points peut subsister si ceux-ci ont déjà été utilisés. Les annulations de commande restituent les points dépensés. Les avoirs de retour les restituent proportionnellement aux montants facturés et retournés, y compris les factures partielles ou groupées.

## Cartes cadeaux et portefeuilles

L’émission crée un compte de solde, sans mouvement financier. Un portefeuille appartient à un client. Une carte cadeau peut être liée à un client ou au porteur ; le code complet est requis pour la dépenser. Plusieurs cartes du même programme peuvent être émises au même client. Le code affiché à l’émission doit être conservé : il n’est pas récupérable ensuite.

Pour charger le solde, sélectionner un encaissement client confirmé, comptabilisé et encore disponible. Le chargement reclasse le crédit réel de cet encaissement vers le compte de passif du solde. Le compte d’origine peut être un acompte historique ou le compte client figé par le mode d’encaissement. Un encaissement configuré sans écriture ne peut pas financer un solde. Un même montant ne peut plus être affecté à une facture ou à un autre solde. L’annulation de l’encaissement est bloquée tant que le chargement subsiste.

Le règlement débite le passif du solde et crédite le compte client de la facture d’origine. Le solde dû de la facture tient compte de cette écriture par le calcul canonique des encours. Aucun second encaissement bancaire ni revenu n’est enregistré. Les comptes et la devise du solde sont figés à son émission ; le compte client est lu dans l’écriture d’origine de la facture.

Les soldes exigent la devise de l’entreprise, un montant disponible à la date choisie et aujourd’hui, une date valide et un compte actif. L’expiration interdit la dépense et conserve le passif ; elle ne génère pas de produit exceptionnel automatique. La date peut être prolongée avec motif.

Une annulation produit une extourne comptable et un mouvement opposé du solde. Un chargement ou remboursement déjà dépensé ne peut être annulé sans solde suffisant. Une facture réglée par solde ne peut être annulée avant son règlement. Les verrous de périodes comptables restent applicables.

Après un avoir de retour ou un avoir financier comptabilisé sur une facture réglée, le règlement initial peut être remboursé sur le même solde. Les plafonds de l’avoir, du règlement et du crédit client réellement disponible sont contrôlés sous verrou. La partie de l’avoir qui éteint un impayé ne devient pas un nouveau solde. Pour un avoir financier, les remboursements bancaires et par solde partagent le même plafond et le même verrou de facture. Le même avoir ne peut pas être remboursé à la fois en espèces/banque et sur le solde. Il faut annuler les remboursements liés avant d’annuler le règlement d’origine.

## Accès, historique et API

La configuration de programmes exige un administrateur et les droits d’édition des ventes. Les récompenses de devis utilisent leurs droits de ligne existants. Les opérations de solde exigent une visibilité comptable complète et les droits d’édition et de paiement comptables. Le serveur vérifie le profil actif, l’authentification renforcée, les modules et l’environnement ; une session navigateur ne confère aucun droit.

`coco_sales_rewards(p_action, p_data)` expose les lectures `programs`, `quote_context`, `accounts`, `account_history`, `invoice_context` et les écritures `program_save`, `code_issue`, `code_update`, `account_issue`, `account_update`, `quote_apply`, `quote_remove`, `fund`, `redeem`, `refund`, `void`. Chaque écriture demande une clé UUID ; une répétition identique renvoie son résultat, une réutilisation avec autre acteur ou contenu est refusée. Les tables restent privées sans accès direct des clients ou du rôle de service.

Les programmes, codes, comptes, demandes de récompense, mouvements et règlements sont enregistrés dans l’historique commun avec acteur et provenance Agent Coco si fournie par la passerelle. Aucun code complet ni empreinte de code n’entre dans cet historique. Les mutations échouées ne créent ni écriture ni historique métier.

## Vérification et références

`tests/sales-rewards-db.test.cjs` utilise PostgreSQL jetable et les véritables RPC de devis, commandes, factures, encaissements et avoirs. `tests/sales-rewards.spec.js` teste configuration, émission et suspension de coupon, règlement avec récupération après code erroné, et annulation dans Chromium, avec vérification d’accessibilité et de débordement à 390, 768 et 1440 pixels.

Les comportements ont été conçus à partir de la documentation fonctionnelle publique, sans lecture ni reprise du code Odoo : [remises et fidélité](https://www.odoo.com/documentation/19.0/applications/sales/sales/products_prices/loyalty_discount.html), [cartes cadeaux et portefeuilles](https://www.odoo.com/documentation/19.0/applications/sales/sales/products_prices/ewallets_giftcards.html). Les opérations fiscales restent dans les parcours SRI existants. Cette migration ne contient aucune donnée métier d’exemple et ne constitue pas une autorisation de déploiement en production.
