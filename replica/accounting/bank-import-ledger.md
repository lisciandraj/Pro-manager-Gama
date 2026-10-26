# Relevés bancaires au grand livre et cartes de journaux

Référence : Odoo 19.0 Enterprise, documentation officielle consultée le 26 octobre 2026 : [transactions](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/transactions.html), [rapprochement](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html) et [paiements](https://www.odoo.com/documentation/19.0/applications/finance/accounting/payments/online.html). Ces sources décrivent une pièce banque/attente par mouvement ; Coco conserve ses propres composants et des pièces immuables corrigées par contreparties traçables.

## Parcours livré par ce lot

Comptabilité → Configuration → Relevés au grand livre : sélectionner la banque, son journal actif, un compte transitoire non bancaire et la première date applicable. Aucune banque ni aucun compte d’attente n’est choisi par la migration. Seuls les nouveaux imports dans la période configurée sont comptabilisés automatiquement. Désactiver cette option n’altère aucune pièce déjà créée.

Un import de +100 produit banque débit 100 / compte transitoire crédit 100, à la date bancaire originale. Un rapprochement de 40 débite l’attente de 40 et crédite le compte du paiement ou du tiers ; 60 restent en attente. Le second rapprochement solde l’attente. L’annulation contre-passe seulement les affectations concernées et conserve la pièce bancaire d’origine. Les réimports, les clés réutilisées, les contrôles d’autorisation et les verrous de dates sont vérifiés côté serveur.

Les paiements déjà passés directement en banque sont un cas distinct : leur contrepartie de rapprochement crédite la banque, supprimant le doublon avec l’import. **Avant rapprochement**, le livre peut contenir le paiement direct et le mouvement importé. L’écran de configuration l’explique. Les méthodes avec attente ou sans écriture évitent ce double constat provisoire. Aucun rapprochement n’est inventé pour le cacher.

La liste Banque et caisse ouvre la pièce d’import ; le détail de celle-ci indique le mouvement d’origine et donne accès à son rapprochement. La Vue d’ensemble contient les cartes de journaux, débits/crédits, écritures et brouillons de la période. Chaque compte financier montre le solde du livre à la date de fin et le reliquat à rapprocher. Les boutons transmettent les filtres exacts à la liste. Celle-ci dispose de pagination, état, journal, dates, recherche et export de toutes les pages ; un changement pendant l’export annule celui-ci.

## Historique existant et limites de parité

La migration est additive : aucun paiement, relevé, compte, réglage existant ou montant historique n’est modifié. La revue des anciennes lignes distingue les lignes sans rapprochement, les lignes déjà rapprochées, les dates verrouillées et les lignes hors configuration. L’utilisateur peut sélectionner les lignes vérifiées sans aucun rapprochement antérieur pour une adoption explicite ; les dates restent inchangées et le traitement est atomique.

Les lignes ayant un rapprochement antérieur, même annulé, nécessitent une reprise spécifique avec comparaison des sources. Elles ne sont pas converties par cette action. L’historique 89 transactions / 26 groupes doit donc être analysé avant une bascule globale. Les paramètres de production restent désactivés tant que les comptes ne sont pas choisis dans Coco. F12 reste partiel pour cette raison ; un essai isolé réussi ne prouve pas une reprise intégrale de l’historique.

A02 reste partiel : les cartes et les listes sont réelles, mais le périmètre complet des activités de journaux Odoo n’est pas démontré. G04 reste partiel : la pagination et les filtres sont étendus, mais tous les regroupements et liens de l’ensemble du périmètre ne sont pas couverts. Aucun score n’est artificiellement augmenté.

## Architecture et vérification

`gama_accounting_bank_import` et `gama_accounting_journals` sont des façades invocateur. Leurs fonctions privées vérifient Auth, MFA, module, périmètre all et droits métier ; exports et écritures sont vérifiés séparément. Les deux tables privées ont RLS, aucun privilège direct client, des clés étrangères et des index. Les métadonnées de chaque import figent la banque, le compte et la pièce. Le verrou par banque est commun à l’import, l’adoption et au rapprochement. Les écritures utilisent les contraintes de partie double et de période existantes.

Les modifications métier sont capturées dans l’historique Coco. Les contrôles de lecture masquent les liens bancaires aux profils commerciaux limités. La migration reste uniquement dans le registre technique.

Tests : [base import](../../tests/accounting-bank-import-db.test.cjs), [cartes et listes](../../tests/accounting-journal-dashboard-db.test.cjs), [parcours trilingues](../../tests/accounting-bank-import.spec.js), [concurrence PostgreSQL](../../tests/accounting-plans-concurrency.test.cjs) et [reprise peuplée sans modification](../../tests/accounting-payment-upgrade-db.test.cjs). Résultats définitifs et publication à consigner après CI dans le fichier de résultats associé.

## Déploiement et retour arrière

Vérifier les empreintes de données et la sauvegarde privée avant les deux migrations additives. Appliquer d’abord le schéma et les fonctions, puis publier les sources compilées avec le processus GitHub Pages. Vérifier les deux nouvelles tables vides, les droits, les déclencheurs et les empreintes historiques inchangées. Les lectures en production ne créent aucune facture ou paiement fictif.

Avant activation de paramètres, un retour de l’interface vers la version antérieure conserve les tables et l’historique. Après utilisation, conserver les pièces d’import et leurs affectations : corriger en avant, par une migration testée. Ne pas supprimer les métadonnées ou annuler les écritures bancaires pour retrouver artificiellement un ancien solde. Une panne du nouvel import doit suspendre les nouveaux imports de la banque concernée jusqu’à correction ; ne pas changer de politique en silence.
