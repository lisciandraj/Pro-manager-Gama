# Résultats vérifiés — configuration et relevés, 25 octobre 2026

Complément ultérieur : [19 types de comptes et contrôles hors bilan](off-balance.md).
Le présent point de contrôle conserve les résultats du premier lot de configuration.

Cette extension native complète la configuration de Coco et l'import CSV. Elle
ne livre pas toute la comptabilité Odoo. Référence inchangée : **Odoo 19.0
Enterprise**. La matrice contient maintenant 107 lignes : **51 testées, 30
partielles, 20 à développer, 2 à analyser, 3 bloquées et 1 exclusion SRI**.
Le résultat reporté dynamique spécifique à Odoo 19 est isolé en H13 ; il n'est
pas couvert par la clôture annuelle actuelle. Une réussite de scénario Coco ne
constitue pas une comparaison exhaustive sur une instance Enterprise.

## Fonctions et emplacements

**Comptabilité → Configuration → Types, groupes, numérotation et verrouillages** :

- Types et comptes : 18 types détaillés, famille cohérente, historique laissé
  « À classifier » sans sous-type inventé ; famille d'un compte utilisé protégée.
- Groupes : plages de codes, parents automatiques, rejet des chevauchements,
  balance avec ouverture/débit/crédit/clôture et accès au grand livre filtré.
- Séquences : activation par journal pour les prochaines validations,
  périodicité continue/annuelle/mensuelle/exercice, compteurs transactionnels et
  conservation de la référence ERP. La renumérotation de masse et l'inférence
  d'un format restent en B04.
- Verrouillages : dates inclusives globales/ventes/achats/taxes/définitives,
  exceptions personnelles ou globales motivées, expiration/révocation,
  auteur et dates demandée/effective. Le verrou définitif exige confirmation.

**Comptabilité → Banque et caisse → Importer CSV → Affecter les colonnes** :
correspondance par position, choix de première ligne/en-tête/séparateur/décimales,
aperçus original et interprété, erreurs compréhensibles bloquant tout le lot,
réimport sans doublon et sans nouvel encaissement. Les aperçus défilants sont
accessibles au clavier. Les trois langues et les composants Coco sont conservés.

## Code et tests

Base : `dd04ff4e5a2bbbb607f04b72c1d4d95ca631b2f5` (lot des échéanciers publié).
Code applicatif testé : `9671f5a48cd818d7c7f07df84ada13732132cc4b`.
La [PR 244](https://github.com/lisciandraj/Pro-manager-Gama/pull/244) porte les
preuves de fusion et de publication finales. Le commit réellement servi est
vérifié dans `coco-build.json` ; la seule CI de branche ne prouve pas le déploiement.

| Contrôle | Résultat | Preuve |
| --- | --- | --- |
| Suite serveur générale | 572 tests : 570 réussis, zéro échec, 2 SKIP de services dédiés | [Release 40183687020](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40183687020), job validate |
| Interface partagée et modules connectés | 430 réussis | Même workflow, job shared-interface |
| Comptabilité, audit, échéanciers, configuration, CSV et historique | 70 parcours navigateur réussis | [CI 40183687082](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40183687082), job browser |
| Concurrence réelle | PostgreSQL 17, deux connexions authenticated, aucun SKIP | Même workflow, job concurrency |
| Configuration serveur | 13 tests, types/groupes/numéros/dates/ACL/historique | `tests/accounting-configuration-db.test.cjs` |
| Parsing CSV | 8 tests, en-têtes inconnus ou absents, colonnes répétées, champs invalides, lignes physiques | `tests/bank-statement.test.cjs` |
| Chaîne vente → banque → rapports | Réussie en base isolée ; 100 USD de vente, paiement et banque ; zéro reste dû et aucun double cash | `tests/accounting-sale-to-bank-db.test.cjs`, inclus dans les suites |
| Contrôles du dépôt | Sources, dépendances, types, docs, migrations, sorties générées et budget de démarrage réussis | Workflows du commit testé |

Les SKIP de la suite générale concernent les services PostgreSQL comptabilité et
ventes ; leurs workflows dédiés ont réussi. Les suites se recouvrent : leurs
nombres ne sont pas additionnés. Les scans axe ciblés ne remontent aucune
violation WCAG 2 A/AA dans les nouveaux formulaires et la balance par groupes.
Les [captures isolées](evidence/README.md) ont été examinées. Cela ne certifie pas
tous les écrans ou toutes les fonctions Odoo.

Résultats indépendants : ouverture d'un groupe de produits -100, crédit de
période 30 → clôture -130 ; exercice débutant en juillet → juin 2026 relève de
2025 ; verrou au 31 mai → date comptable du 15 mai reportée au 1er juin ; import
mappé de 19,25 USD rejoué → un seul mouvement, aucune écriture de trésorerie.

La concurrence vérifie les créations/approbations/exécutions/annulations des
plans, les numéros de journaux potentiellement identiques et une course entre
modification du verrouillage et validation. Une opération se termine entièrement
avant ou après le changement de configuration.

Défauts corrigés : référence ERP qui rétablissait l'ancien numéro après
validation ; contrôle de permission de clôture ; régions CSV non focalisables
sur téléphone. Les attentes des tests de compatibilité ont été ajustées pour le
nouveau sous-type nullable et l'import désactivé en présence d'erreurs ; aucune
assertion de sécurité n'a été supprimée.

## Migration et conservation

Projet : `mknsaibrewksgomuslev`. Migration réellement appliquée :
**20261025102114_accounting_configuration_parity**. SQL enregistré : **32 547
octets**, SHA-256 `e84690a18d3ef6c4069f0e13b393c93ec9134c2ada4a098a390c61438a50bd78`,
identique au fichier renommé selon le registre Supabase.
[Archive immuable](../../supabase/sql/applied/20261025102114_accounting_configuration_parity.json).

| Mesure | Avant | Après |
| --- | ---: | ---: |
| Écritures | 58 | 58 |
| Lignes | 138 | 138 |
| Débit USD | 8 552,49 | 8 552,49 |
| Crédit USD | 8 552,49 | 8 552,49 |
| Écritures déséquilibrées | 0 | 0 |
| Comptes / journaux / périodes | 526 / 5 / 2 | 526 / 5 / 2 |
| Banque : rapprochées / ignorées / non rapprochées | 27 / 5 / 57 | 27 / 5 / 57 |
| Factures / paiements clients | 17 / 20 | 17 / 20 |
| Factures / paiements fournisseurs | 6 / 7 | 6 / 7 |
| Encaissements | 3 | 3 |
| Groupes / séquences / compteurs / verrous / exceptions / ajustements nouveaux | Absents | 0 / 0 / 0 / 0 / 0 / 0 |

Les données de la sauvegarde ciblée ont été comparées avant application et à
nouveau après : toutes les valeurs existantes des six ensembles sont identiques.
Seule la nouvelle clé nullable `account_type` est ignorée dans cette comparaison
des comptes ; ses 526 valeurs sont nulles. Aucun document historique n'est
recomptabilisé et aucune écriture d'équilibrage n'est créée.

La sauvegarde ciblée conservée séparément du dépôt public contient 378 144
octets, SHA-256 `2bef42f16df30ab0918449fb4f9cd96360defafd0d467fe23c1d4caa1cc744e3`.
Elle couvre comptes, journaux, périodes, écritures/lignes et transactions
bancaires ; elle ne constitue pas une sauvegarde intégrale/PITR attestée.
Cette limite reste explicite avant une future conversion structurelle.

Preuves agrégées : [avant](evidence/configuration-before-migration.json),
[après](evidence/configuration-after-migration.json),
[requête de vérification](verify-configuration-production.sql).

## Sécurité et limites de production

Les six nouvelles tables privées ont RLS et aucun accès direct pour anon,
authenticated ou service_role. La façade publique est invoker, le moteur privé
definer, tous deux avec search_path vide ; l'API impose Auth, MFA, rôle,
périmètre et permissions effectives. Cinq tables métier sont enregistrées dans
l'historique avec captures actives. Le trigger de validation est actif.

Les advisors n'ajoutent aucun WARN à la situation précédente. Les six notices
INFO de RLS sans politique correspondent au refus intentionnel d'accès direct
aux nouvelles tables privées ; l'accès métier passe par les fonctions contrôlées.
Les paramètres restent vides en production. Aucune facture, paiement, opération
bancaire ou configuration fictive n'a été créé pour la vérification.

Le contrôle public des actifs et le contrôle authentifié de l'interface restent
distincts des tests isolés. Si une session de production n'est pas disponible,
la navigation sous une identité humaine ne doit pas être annoncée comme vérifiée.

Les [55 fonctions encore incomplètes ou non démontrées](evidence/parity-tool.txt),
les [dépendances](dependencies.md) et les [écarts](parity.md) restent ouverts.
Les propositions Agent Coco pour ces nouveaux paramètres et échéanciers ne sont
pas raccordées à la file d'approbation ; les mutations nouvelles exigent un
auteur humain. Cette livraison n'annonce aucune équivalence intégrale.
