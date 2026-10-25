# Autres charges et séparation du hors bilan

Le premier lot de configuration exposait 18 types, d'après le tableau du guide
fonctionnel. La relecture du **25 octobre 2026** confirme le dix-neuvième type
`expense_other` dans la [référence technique officielle Odoo 19.0](https://www.odoo.com/documentation/19.0/nl/developer/reference/standard_modules/account/account_account.html).
Il est disponible dans Coco comme « Autres charges », « Otros gastos » et
« Other expenses », avec la famille charge existante. Les rapports calculés par
famille l'incluent dans les charges sans modifier le résultat d'autres comptes.

Métadonnées publiques Community consultées, branche 19.0 :
[types de comptes](https://github.com/odoo/odoo/blob/19.0/addons/account/models/account_account.py)
(blob `d5e602da66e5e6d48a88af9fcf726af385a0668f`) et
[contrôles des lignes](https://github.com/odoo/odoo/blob/19.0/addons/account/models/account_move_line.py).
Seuls les identifiants de types et les règles observables sont retenus ; aucun
code Odoo n'est intégré à Coco. Les contrôles SQL sont une implémentation native.

## Règles serveur

Une écriture utilisant un compte hors bilan doit utiliser exclusivement des
comptes hors bilan. Elle ne comporte ni taxe ni affectation de trésorerie.
Les liaisons bancaires et les deux registres de rapprochement existants refusent
une telle pièce. Cela empêche qu'une partie de l'écriture apparaisse dans le
bilan ou le résultat alors que sa contrepartie est exclue.

Les contrôles d'écriture sont différés à la fin de transaction, pour permettre
l'enregistrement atomique de toutes les lignes. Ils couvrent l'écriture, ses
lignes et les changements de famille de compte. Les contrôles d'affectation et
de rapprochement s'exécutent avant la liaison. Les droits existants restent en
place et les deux nouvelles fonctions privées ne sont pas exécutables par les
rôles clients. Les erreurs disposent de messages FR/ES/EN.

La migration remplace la fonction native de classification en conservant son
OID, ajoute les contrôles et ne transforme aucune donnée. Le SQL de la migration
déjà appliquée `20261025102114_accounting_configuration_parity` reste immuable.
Avant application, vérifier qu'aucun compte hors bilan ni donnée invalide n'a
été créé depuis le point de contrôle précédent ; sinon analyser les pièces et
conserver leurs causes explicites, sans écriture d'équilibrage arbitraire.

## Vérification

`tests/accounting-configuration-db.test.cjs` vérifie désormais 19 types et refuse
un mélange de 20 USD hors bilan/produit : aucune pièce n'est conservée après
l'échec. Il vérifie aussi le refus des taxes, de l'affectation de cash, d'une
liaison bancaire et des rapprochements dans les deux registres, puis les droits
des fonctions privées. Les écritures exclusivement hors bilan restent possibles
et sont exclues du bilan et du résultat. Les 14 tests ciblés réussissent en base
isolée.

Les neuf parcours navigateur utilisent maintenant le type « Autres charges »
pour l'écriture de 100 USD. La CI doit confirmer les trois langues, trois
largeurs, la concurrence et les suites de régression avant publication du
correctif. La suite ciblée de régression compte 78 réussites, zéro échec et aucun
SKIP, incluant la chaîne vente → banque, immobilisations, devises, clôture et
échéanciers. Le scénario « Autres charges » de 37 USD est inclus dans les
charges et compensé par 37 USD de produit ; son rollback conserve les autres
soldes indépendants de la suite.

Migration appliquée : **20261025105418_accounting_off_balance_guards**,
4 810 octets, SHA-256 `5f4de037f47e2c58aa2e534c6b3658b0545584dd04d57880ee2f966ba4eda62c`,
identique au SQL enregistré dans Supabase. Les six triggers sont actifs ; les
fonctions privées ont search_path vide et restent inaccessibles aux rôles
clients. Le contrôle en lecture seule des 58 écritures existantes réussit.
Débit = crédit = 8 552,49 USD, 138 lignes et aucun compte hors bilan existant :
la migration n'a créé ni modifié de pièce métier.
[Résultat agrégé](evidence/off-balance-after-migration.json),
[archive immuable](../../supabase/sql/applied/20261025105418_accounting_off_balance_guards.json).

Ce correctif conserve les 107 lignes de couverture et ne ferme pas H13 :
l'affectation du résultat reporté propre à Odoo 19 reste à développer.
