# Première installation de la base Production

Cette procédure concerne uniquement le nouveau projet `vhutzdfatijjpahsqkne`, avant son utilisation. Elle ne s’applique jamais au projet Développement `mknsaibrewksgomuslev` et ne sert ni à réinitialiser une base ni à promouvoir des données. Les programmes ci-dessous produisent des fichiers locaux ; ils n’ouvrent aucune connexion et n’exécutent aucun SQL distant.

## Sources et dérivation

Les 362 migrations canoniques restent inchangées. Chaque installation conserve leur SHA-256 original et le SHA-256 du SQL réellement appliqué dans `private.coco_bootstrap_sources`. L’empreinte de l’installation est calculée sur les originaux ; l’empreinte dérivée atteste les adaptations de première installation.

`scripts/production-bootstrap-sql.cjs` conserve l’adaptation existante de la réparation historique des produits pour un catalogue vide. Il ajoute les transformations suivantes, limitées à des sources dont le SHA-256 exact est vérifié :

| Source historique | Traitement de première installation |
| --- | --- |
| `knowledge_base` | Conserver le schéma et les RPC ; ne pas insérer l’article de démonstration. |
| `fleet_management_demo_data` | Conserver les colonnes `is_demo` ; ne pas insérer les 33 lignes d’exemple de flotte. |
| `project_management` | Conserver les six modèles de projet, sans créer de faux événements utilisateur lors de leur insertion initiale. |
| `p1_receipts_reconciliation_and_followup` | Conserver le compte système d’avances client `2090`, sans événement d’activité de bootstrap. |
| `coco_erp_brand` | Conserver le modèle d’invitation Coco ERP final, sans événement de modification fictif. |
| `hr_base_role_org_chart` | Conserver le rôle RH initial, sans événement de création fictif. |
| `accounting_audit_core` | Conserver la classification de trésorerie initiale du compte de capitaux propres, sans événement de modification fictif. |
| `business_modules_contracts_expenses_sourcing` | Conserver les modules Contrats et Dépenses activés par défaut, sans activité utilisateur fictive. |

Pour les seules écritures de configuration initiale ci-dessus, le déclencheur d’historique nommé est désactivé autour de l’instruction exacte puis immédiatement réactivé. Les contraintes, clés étrangères, politiques RLS et déclencheurs métier restent en place. Les fonctions d’historique finales ne sont pas réécrites. La vérification finale refuse un déclencheur de capture laissé désactivé.

Il n’y a aucun `DELETE`, `TRUNCATE`, copie d’utilisateurs, fichier, secret ni purge de lignes métier. Les exemples ne sont jamais insérés, et aucune fausse activité de suppression n’est inventée. Les opérations techniques et leurs empreintes restent dans les registres de migration et de bootstrap.

## Préparer et reprendre

Une installation entièrement neuve peut préparer son contrôle préalable et ses lots :

```sh
node scripts/bootstrap-production.cjs vhutzdfatijjpahsqkne
```

Après un arrêt, lire le nombre exact de sources déjà confirmées dans `private.coco_bootstrap_sources`, puis préparer les sources suivantes. Exemple de forme pour 77 sources confirmées et des lots de 100 Ko :

```sh
node scripts/bootstrap-production.cjs vhutzdfatijjpahsqkne 77 100000 production-bootstrap-derived
```

Les arguments sont, dans l’ordre : projet, nombre de sources déjà appliquées, taille cible d’un lot, nom de dossier sous `.build/`. Le manifeste indique les positions `start` et `end`, les sources et les empreintes de chaque lot. Une migration individuelle plus grande que la taille cible reste intacte ; elle n’est pas découpée au milieu d’une fonction SQL.

Chaque lot vérifie le projet et l’empreinte d’installation attendus, le nombre de sources déjà confirmé, l’absence de comptes et de fichiers, et l’absence de contenu dans les tables métier existantes. Seules les tables de configuration explicitement autorisées par la migration d’environnement peuvent contenir leurs valeurs par défaut. Un lot ne peut pas être rejoué ni exécuté dans un ordre différent sans échouer avant sa première modification.

Ne pas réexécuter le contrôle préalable d’une installation neuve sur une base partiellement préparée. Ne pas remplacer son empreinte pour masquer un écart : vérifier les sources et les traces d’installation avant toute reprise. Les anciens lots produits sans l’adaptateur de production ne doivent pas être utilisés à partir de la migration `knowledge_base`.

## Vérifier avant affectation

```sh
node scripts/prepare-production-verification.cjs vhutzdfatijjpahsqkne
```

Le fichier `.build/production-verification/verify.sql` est uniquement en lecture. Il exige :

- l’identité exacte du nouveau projet et une installation unique ;
- les 362 sources, leurs empreintes originales et dérivées intégrales ;
- un environnement encore `unassigned` ;
- aucun utilisateur Auth ni fichier Storage, et aucun bucket public ;
- aucune ligne métier, démonstration, référence de document ou activité de bootstrap ;
- RLS sur toutes les tables publiques et tous les déclencheurs de capture activés.

Le résultat est un reçu de vérification avec les empreintes et les nombres contrôlés. Il ne crée pas de compte administrateur, n’envoie aucune invitation et n’affecte aucun environnement. Conserver ce reçu avant une éventuelle création sécurisée du premier compte administrateur. Lire ensuite le nombre réel de comptes autorisés avant l’affectation initiale décrite dans [le guide des bases](../../supabase/ENVIRONMENTS.md).

La restriction du Développement ne doit être activée qu’après préparation de la Production et bascule des intégrations publiques. Une évolution ultérieure utilise une migration versionnée et une approbation de production ; elle ne réutilise jamais ce bootstrap de base vide.

## Vérification isolée

```sh
node tests/production-bootstrap.test.cjs
```

Ce test reconstruit une base PGlite jetable. Il vérifie les valeurs de configuration conservées, l’absence de lignes métier et d’historique fictif, les empreintes, les déclencheurs, les refus de projet erroné et de données imprévues, puis l’acceptation contrôlée de l’affectation initiale. Il ne contacte aucun projet hébergé.
