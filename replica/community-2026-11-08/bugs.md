# Défauts reproduits et corrigés dans le lot

| ID | Gravité | Reproduction et effet | Correction et preuve |
| --- | --- | --- | --- |
| B01 | S3 | Copier un devis à prix manuel : le prix recalculé conservait le marqueur manuel et ne suivait plus les quantités | Provenance automatique réinitialisée ; test de copie et modification de quantité |
| B02 | S2 | Modifier les comptes d'une taxe dans l'ancien endpoint : les nouveaux comptes n'étaient pas conservés ; droits créer/modifier confondus | Écriture des comptes, droits distincts, révisions et reçus de commande ; tests SQL taxes |
| B03 | S3 | Première recherche locale des modèles : un modèle au-delà des 100 plus récents était introuvable | Recherche serveur avant limite ; cas avec 101 modèles et caractère `%` littéral |
| B04 | S2 | Archivage d'un modèle après réponse perdue : répétition en erreur, absence de contrôle d'action dédié et de capture de l'historique | Archivage idempotent, permission supprimer et historique expurgé ; tests SQL/UI modèles |
| B05 | S2 | Choisir une taxe avant de saisir la base, puis saisir 0,30 à 15 % : TVA périmée ou arrondie à 0,04 | Recalcul et arrondi entier à 0,05, montant validé au serveur ; tests trilingues et SQL |
| B06 | S2 | Taxe valable à la date de facture, date comptable décalée par verrouillage : refus injustifié | Contrôle de validité selon la date de pièce ; test 31 octobre comptabilisé le 1er novembre |
| B07 | S2 | Compte tiers aussi utilisé comme compte d'attente : risque de compensation sur un seul compte | Exclusion des usages incompatibles dans les deux sens ; tests SQL comptes tiers |
| B08 | S3 | Intégration de deux extensions d'historique : remplacement de chaîne devenu inopérant après le premier wrapper | Branche explicite des comptes tiers ; test sous rôle authentifié et lien vers l'onglet |
| B09 | S2 | Devise figée différente de celle courante : devis affiché avec un autre symbole que son export | Devise de l'instantané appliquée à l'affichage et au PDF ; assertion EUR du parcours pro forma |

## Corrections lors de la finalisation

| ID | Effet corrigé | Preuve |
| --- | --- | --- |
| B10 | Acompte avancé qui contournait la création des reports de revenu | tax-deposit-deferrals-integration |
| B11 | Avoir direct partiel qui retirait toute la base fiscale d’origine | direct-credit-tax-base-integration |
| B12 | Allocation fournisseur sur plusieurs comptes en conflit avec une clé de plan unique | direct-invoices-db, scénario fournisseur réparti |
| B13 | Prix taxes incluses de 0,04 perdant un centime | advanced-tax-engine-db |
| B14 | Acompte avec taxe fixe et TVA composée : escompte dû 29,32 au lieu de 29,33 | advanced-tax-deposits-db |
| B15 | Dernier centime déplacé lorsque deux retours sont traités dans l’ordre inverse | sales-commercial-db |
| B16 | Risque de double affectation des fonds entre paiement, portefeuille et virement | checkout-payments-db et sales-rewards-db |
| B17 | Avoir déjà payé sans remboursement canonique, ou double restitution argent/portefeuille | direct-paid-refunds-db et sales-rewards-db |
| B18 | Chiffre d’affaires sans les avoirs et retours pourtant comptabilisés | revenue-ledger-projection-db |
| B19 | Projections privées non lisibles par les fonctions invoker du tableau de bord | dashboard-db et p1-finance-db |
| B20 | Devise USD codée en dur dans le texte copié et affichage de facture lié à la société courante | internal-invoices et invoice-tools, document EUR face à société USD |
| B21 | Clic Enregistrer ignoré pendant le chargement ou le recalcul fiscal | request-quote, contexte et aperçu suspendus puis une seule sauvegarde |
| B22 | Réponse fiscale périmée qui effaçait la promesse courante ou empêchait le calcul de la dernière saisie | tax-preview-state, trois courses reproduites puis corrigées ; request-quote |

La [matrice actuelle](features.csv) distingue l’implémentation et la configuration
externe requise. Les événements Stripe de test ne créent aucun encaissement ; le
virement déclaré ne vaut pas preuve bancaire. Aucune activation externe ou de
production n’a été effectuée.
