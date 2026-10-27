# Reprise des travaux Coco du 27 octobre 2026

La livraison rassemble les lots effectivement préparés dans les discussions
Comptabilité, TMS et espace de travail. Elle conserve la branche principale
`631b3ab67531421a6828dc7c151a6c57261bbcb8`, incluant la carte quotidienne #258,
les imports bancaires et les clôtures groupées #252 et leur preuve #257.

| Lot repris | Fonction livrée | Sources et limites |
| --- | --- | --- |
| Espace de travail | Texte partagé par canal, coédition Yjs, versions, export Markdown, accès Agent Coco en lecture | [Architecture documentaire](../macro/collaborative-documents.md) ; synchronisation toutes les deux secondes, brouillons en mémoire de l'onglet |
| TMS | Quatre dimensions de capacité supplémentaires, charges obligatoires, contrôles au déplacement et au départ, lieux de début/fin du conducteur | [Matrice](../optimoroute-pro/features.csv) ; carte routière facultative, GPS au premier plan et notifications manuelles |
| Comptabilité | Échéanciers natifs créés depuis les dates des lignes de factures clients/fournisseurs, réglages humains et liens retour | [Différés de factures](../accounting/invoice-deferrals.md) ; avoirs et ventilation sur plusieurs comptes de résultat encore ouverts |

Cette consolidation ne revendique ni la parité intégrale Odoo 19 Enterprise,
ni un algorithme identique à OptimoRoute, ni la totalité de Macro. Les matrices
de chaque chantier conservent les fonctions partielles, exclues ou absentes.
Les demandes de publication et de fusion après tests sont déjà autorisées par
le propriétaire ; les contrôles CI restent obligatoires.

## Préparation et intégration

- Ressources TMS : branche #259 conservée par fusion, y compris l'adaptation
  des trajets de la carte #258 aux lieux enregistrés.
- Factures : commit `79a440c` repris ; conflits limités aux sorties générées,
  reconstruites depuis les sources canoniques.
- Documents : changements et fichiers non encore commités récupérés sans
  modifier le répertoire d'origine, puis intégrés aux manifestes et au build.
- Les trois migrations sont additives. Aucun historique n'est rejoué et aucun
  réglage comptable, envoi externe ou capture GPS n'est activé automatiquement.
- Le libellé de quantité et montant manquants est retiré de l'historique,
  conformément à la demande du 20 octobre. Les valeurs réelles, y compris
  zéro et les variations, restent affichées. Régression reproduite avant
  correction dans le parcours des références historiques.

## Installation et vérification

1. Réussir la validation du dépôt, les parcours concernés et les contrôles CI.
2. Conserver les définitions des fonctions remplacées et la version active
   d'Agent Coco, hors dépôt public. Une sauvegarde logique ciblée n'est pas une
   preuve de restauration PITR complète.
3. Lire les empreintes avant installation conservées hors du dépôt public avec
   [la requête de comparaison](verify-snapshot.sql). Les seules colonnes exclues
   sont les ajouts des trois migrations ; les données historiques restent
   comparées, y compris celles du TMS et de l'espace partagé.
4. Appliquer documents, ressources TMS puis différés ; conserver le SQL exact
   enregistré par le service dans les archives de migrations.
5. Déployer `coco-workhub-documents` et la version compatible de
   `gama-assistant-ia`, avec leur vérification JWT conservée. Contrôler les
   permissions, les refus anonymes, les politiques d'historique et les soldes.
6. Fusionner après réussite des contrôles, publier l'artefact `dist/`, puis
   comparer le manifeste et les actifs réellement servis au commit publié.

Les tests métier s'exécutent sur des bases isolées. Aucune facture, écriture,
livraison, position GPS ni discussion fictive n'est créée en production.
Une recette authentifiée de production exige une session autorisée observée ;
les preuves HTTP et SQL ne sont pas présentées comme cette recette.

Retour arrière : rétablir les sources web précédentes par un nouveau commit
validé ; conserver les tables, les versions et les pièces utilisées. Une
correction du schéma utilise une migration additive. Ne pas restaurer un ancien
wrapper partagé en écrasant une extension plus récente d'un autre module.

## État

128 parcours distincts des lots ont été exercés avec succès, puis 17 contrôles
d'historique, regroupement et coédition après la correction du libellé. Les
29 tests serveur ciblés passent sans échec ni scénario ignoré, notamment la
migration peuplée, les montants de différés, les capacités TMS, la fusion réelle
CRDT et les droits du canal. Les captures ordinateur/téléphone ont été relues.

Sources, types, documentation, licences/empreintes des dépendances, génération
reproductible et budgets de démarrage passent. Le lancement local de la suite
complète n'a pas fourni de bilan terminal exploitable ; il n'est pas présenté
comme une preuve de validation intégrale. La CI complète reste obligatoire.
Le nettoyage du libellé a aussi exposé un ancien export de fonction dans le
harnais unitaire de l’historique : ce harnais est actualisé et ses cinq tests
repassent, y compris l’absence de mesures et la conservation d’un zéro chiffré.

La destination publique a été vérifiée via le connecteur GitHub : dépôt
`lisciandraj/Pro-manager-Gama`, même propriétaire, droits de poussée présents.
Les empreintes de données et les sauvegardes restent hors dépôt. La nouvelle
branche exclut leur historique ; l'analyse du diff ajouté ne détecte aucune clé
privée, clé OpenAI, jeton GitHub ou clé de service littérale.

## Serveur installé et interface en attente

Les trois migrations sont installées et leurs SQL enregistrés sont strictement
identiques aux sources testées :

| Fonction | Version installée |
| --- | --- |
| Documents collaboratifs | `20261027225549` |
| Capacités et lieux TMS | `20261027225653` |
| Différés depuis factures | `20261027225700` |

Les deux fonctions Edge sont actives : `coco-workhub-documents` version 1 et
`gama-assistant-ia` version 8. Tous leurs fichiers correspondent aux sources
testées et la vérification JWT reste activée. Les appels sans session sont
refusés avec HTTP 401 ; le contrôle CORS de l'éditeur accepte l'origine Coco.

La comparaison des 54 tables avant/après ne détecte aucun changement de leurs
valeurs historiques. Le livre reste équilibré, les politiques d'historique sont
identiques, les captures sont actives et les nouvelles configurations de
différés sont vides. Aucun document partagé ni plan de test n'a été créé.
Les avertissements de sécurité existants restent identiques ; les trois notices
INFO supplémentaires concernent les nouvelles tables privées sans accès direct.
Voir [les preuves sans données métier](production-verification.json).

La publication des changements dans le dépôt public a été explicitement
autorisée le 28 octobre 2026. La branche intègre maintenant `main` et la PR
TMS #259 déjà fusionnée, sans changement des sources applicatives testées.
La livraison attend les contrôles CI, sa fusion et la vérification HTTP du
commit réellement servi. Les preuves finales seront ajoutées après observation.
