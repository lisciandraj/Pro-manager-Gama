# Plan de vérification

Les tests portent sur Coco local et ses bases jetables, jamais sur Odoo ni sur
des factures réelles.

| Cas | Résultat attendu | Preuve prévue |
| --- | --- | --- |
| F01-H1 | Pro forma téléchargée avec les conditions figées ; aucun document aval créé | Playwright ventes, 390 et 1440 px |
| F01-N1 | Titre et pied PDF distincts des factures/devis | Test Node du générateur PDF |
| F02-H1 | Recherche d'un modèle puis archivage ; devis issus conservés | Playwright et SQL modèles |
| F02-E1 | Modèle ancien au-delà des 100 premiers retrouvé par recherche | SQL modèles |
| F02-E2 | Erreur réseau : reprise sans disparition prématurée ; réponse perdue : état récupérable | Playwright et SQL modèles |
| F02-N1 | Auteur non propriétaire ou permission supprimer absente : refus serveur | SQL modèles |
| F02-H2 | Mutation visible dans l'historique expurgé du module | SQL modèles |
| F03-H1 | Copie au tarif actuel ; quantité suivante relance le moteur ; source conservée | Playwright ventes |
| F04-H1 | Remise 10 % sur lignes taxées/exonérées ; prix manuels et motifs conservés | Playwright ventes |
| F04-N1 | Pourcentage hors bornes refusé ; validation serveur existante utilisée | Playwright ventes |
| F05-H1 | Créer/modifier taxe avec dates, comptes et archivage/réactivation | SQL taxes et Playwright |
| F05-N1 | Droits créer/modifier distincts ; anonymes et profils hors périmètre refusés | SQL taxes |
| F05-E1 | Double soumission et révision obsolète ; document historique et contrepassation conservés | SQL taxes |
| F05-H2 | Taxe choisie sur achat/dépense affecte le compte réel ; montant et dates contrôlés | SQL taxes et Playwright |
| F06-H1 | Compte tiers appliqué aux nouvelles factures ; paiement après changement garde le compte initial | SQL comptes tiers |
| F06-E1 | Affectation d'avance entre deux comptes : transfert équilibré et aucun second mouvement bancaire | SQL comptes tiers |
| F06-N1 | Compte bancaire ou d'attente refusé comme créance/dette ; permissions et historique protégés | SQL comptes tiers |
| F06-H2 | Recherche paginée et formulaire dans les trois langues sur téléphone et ordinateur | Playwright comptes tiers |

Régressions prioritaires : ventes et dossiers commerciaux, factures internes,
fournisseurs/dépenses, écritures et rapports de taxes, parcours vente → banque,
contrats SRI, historique de module. Les tests trilingues et captures utilisent
des noms et montants de fixtures. Les limites et résultats réellement exécutés
sont consignés dans [build-log.md](build-log.md).
