# Résultat reporté et affectation — preuves

Règles et source officielle Odoo 19.0 : [earnings-19.md](earnings-19.md).
Livraison : [PR 247](https://github.com/lisciandraj/Pro-manager-Gama/pull/247).

## Vérifications

Treize tests serveur isolés réussissent : bénéfice 100, affectation partielle
60 puis complète 40, perte 30, plusieurs comptes d'affectation, contrepassation,
exercice de juillet, compte archivé, export cohérent et droits. Le report est
une valeur calculée : aucun test de consultation ne crée de pièce.

Les neuf parcours ES/FR/EN × 390/768/1440 passent au commit `19688a70`, avec
création réelle d'une OD d'affectation dans la base isolée, accès aux écritures,
export CSV, bilan à écart nul, axe et absence de débordement. Le job
`121213277179`, run `40208096096`, compte **88 tests navigateur réussis**.
La concurrence PostgreSQL existante passe dans le même workflow.

Une ouverture est agrégée une fois par compte dans le grand livre. Les lectures
d'un rapport partagent le même instantané PostgreSQL. L'export compare une
révision incluant le livre et les métadonnées ; un changement visible impose
de recommencer l'export.

## Migration et conservation

Migration installée : `20261025154847_accounting_earnings_19`, 13 511 octets,
SHA-256 `48caaa81d71c66f0bb7f97ab8cc2427b26bdf518d5c4669cc112932f787cbf7b`.
Archive immuable dans `supabase/sql/applied/` ; aucun rejeu des pièces.

Contrôle du 25 octobre 2026 à 15:50 UTC : **58 écritures, 138 lignes,
8 552,49 USD au débit et au crédit, zéro déséquilibre**. Les empreintes des
écritures, lignes et comptes sont identiques [avant](evidence/earnings-before-migration.json)
et [après](evidence/earnings-after-migration.json). Aucun compte existant n'a
été reclassé et aucune affectation de résultat réelle n'a été créée.
Le RPC anonyme est interdit ; le RPC authentifié conserve MFA, module,
périmètre et contrôle des exports.

## Publication

La PR consignera le commit effectivement publié et la vérification des actifs.
Commande de contrôle depuis le dépôt, sans opération métier :

```sh
python3 replica/accounting/verify-web.py --ref origin/main --commit COMMIT_PUBLIE
```

Conserver les fonctions et le garde-fou de type lors d'un retour de version
de l'interface ; ne pas reclasser un compte d'affectation déjà utilisé.
La navigation authentifiée en production reste non attestée avec la session
disponible. Ces preuves ne constituent pas une équivalence de tout le module
Comptabilité ni des sociétés/branches, stocks ou services encore ouverts.

La migration complémentaire `20261025161011_accounting_earnings_integration` (4 968 octets, SHA-256 `3ba7a364e2eba3b88cb52097e082dcd0697a367a58275cd4ca796fcf115632ba`) relie les rapports et la clôture existants. Les tests vérifient le refus d’une clôture après affectation partielle et la clôture complète sans doublon, avec douze mois verrouillés et résultat net conservé. La course entre deux clôtures est ajoutée au traitement PostgreSQL. **47 tests serveur ciblés sont réussis** avec les régressions Ecuador et échéanciers. La [preuve après intégration](evidence/earnings-integration-after-migration.json) confirme les mêmes comptes, écritures et lignes.
