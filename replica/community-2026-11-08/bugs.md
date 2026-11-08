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

Les écarts fonctionnels de [features.csv](features.csv) restent ouverts ; ils ne
sont pas transformés en défauts corrigés par ces tests. Les services de signature,
banque, paiement et fiscalité ne sont pas simulés comme des intégrations réelles.
