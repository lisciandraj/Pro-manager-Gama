# Vérification des différés issus de factures

Référence : Odoo 19.0 Enterprise. Documentation officielle des charges et produits différés consultée le 27 octobre 2026 ; la documentation anglaise des charges a également été lue dans la branche officielle `odoo/documentation` **19.0**. Aucun code Odoo n'est repris.

## Tests isolés

- **14 tests serveur réussis** après correction : 11 tests du parcours, une migration peuplée et deux contrôles de compatibilité des actions natives. Montant net de 1 200 USD réparti en douze échéances de 100, taxe de 180 exclue, 400 restant au 31 août ; ventilation de 1 200 + 600 sur 2 000, donc 200 immédiatement reconnus et 1 650 différés fin janvier en mode groupé. Les montants des ventes restent calculés côté serveur depuis les quantités et prix natifs.
- Intégrations : saisie fournisseur, facture issue des ventes, édition puis validation d'un brouillon fournisseur, liens bidirectionnels, planificateur existant. Dates tardives reconnues au plus tôt à la date comptable de la facture.
- Garanties : refus des dates incomplètes, centimes fractionnaires, doublons, ventilation excessive, absence de configuration, compte désactivé et période fermée. Reprise identique sans doublon ; requête modifiée refusée ; réglage figé dans le plan ; refus anonyme, droits insuffisants et proposition IA non approuvée.
- Correction complète : une facture avec plan actif ne peut pas être annulée avant ses différés. L'annulation motivée de huit reconnaissances et du reclassement conserve leurs pièces et remet le compte de report à zéro avant correction de la facture.
- Migration peuplée : quatorze empreintes historiques identiques, aucun plan créé pour une facture passée, aucune configuration choisie, poursuite correcte des reconnaissances et de l'automatisation déjà approuvée ; historique TMS conservé.
- **12 parcours navigateur réussis** : neuf combinaisons ES/FR/EN × 390/768/1440 sur configuration → facture fournisseur → échéancier → facture ; conservation de saisie après erreur ; vente → facture datée → produit différé → facture ; brouillon fournisseur → modification → validation → clôture groupée. Vérification axe dans les panneaux testés et absence de débordement général ; capture mobile française examinée.

Un test de compatibilité a détecté le remplacement du message d'erreur historique lors d'une saisie fournisseur incomplète sans différé. Le normalisateur laisse désormais les lignes vides aux contrôles existants ; la régression dédiée passe. Les scénarios de concurrence PostgreSQL 17 (deux créations identiques et deux modifications de configuration) sont ajoutés au job comptable dédié ; résultats CI à consigner avant publication.

## Reprise et production

Une sauvegarde logique ciblée et les définitions des fonctions sont conservées hors du dépôt public. Elle ne constitue pas une preuve de restauration PITR complète. Les fonctions partagées ne doivent pas être restaurées aveuglément si TMS ou Workhub les ont enrichies depuis.

Le contrôle préalable de production vérifie les empreintes historiques et l’équilibre du livre, avec résultats détaillés conservés hors du dépôt public. [Requête de comparaison](verify-invoice-deferrals-snapshot.sql) : seules les quatre colonnes additives sont exclues des empreintes, toutes les colonnes historiques restent contrôlées.

Migration `20261027225700` installée le 27 octobre 2026 et archivée avec son SQL exact ; données historiques inchangées et configuration vide vérifiées. La publication du nouveau code dans le dépôt public est autorisée le 28 octobre 2026 ; l'interface attend les contrôles CI, la fusion et la vérification du commit servi. Voir [la reprise commune](../integration-2026-10-27/README.md). Aucun test métier n'est réalisé en production et la nouvelle interface n'est pas déclarée disponible.

## Écarts visibles

H14 demeure partiel : différés sur avoirs et ventilation sur plusieurs comptes de résultat encore ouverts. La navigation authentifiée de production n'est pas attestée faute de compte désigné autorisé par la revue automatique. Les preuves isolées ne remplacent pas cette vérification. L'ensemble de la comptabilité n'est pas présenté comme équivalent à Odoo.
