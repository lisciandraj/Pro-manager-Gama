# Méthodes de paiement et rapprochements partiels — résultats

Livraison suivie dans la [PR 248](https://github.com/lisciandraj/Pro-manager-Gama/pull/248). Référence **Odoo 19.0 Enterprise** ; interface et architecture Coco. Règles et emplacements : [partial-matching.md](partial-matching.md).

## Résultats métier et tests

100 USD rapprochés en 40 puis 60 conservent le bon reliquat. Une ligne bancaire de 150 peut être utilisée en 100 puis 50. Deux dates produisent deux transferts aux dates bancaires réelles. Une facture sans écriture reste due pour 60 après rapprochement de 40. Un encaissement de 100 avec frais réels de 3 conserve un montant bancaire net de 97. Annuler le premier groupe préserve le second. Une avance sans écriture ne peut affecter que son crédit réellement rapproché ; le dérapprochement de ce crédit est refusé tant que l’affectation dépendante subsiste.

La révision finale `62b9d8f` a réussi les **97 parcours comptables** et la course réelle à deux sessions PostgreSQL 17 (run `40393139578`). La validation générale compte **622 tests réussis**, aucun échec, deux tests de concurrence ignorés dans cette suite mais réussis dans leurs workflows PostgreSQL réels (run `40393138867` pour la validation générale ; `40393138936` et `40393139578` pour les services de concurrence). Les douze workflows de la PR sont au vert. La révision est intégrée dans main sous `273c54a497fcbffc9bce069cba8f609eaf7b57b9`.

**31 tests ciblés** comprenant historique, reprise et contrats ont ensuite réussi. Les **23 tests** de la dernière validation ciblée couvrent les méthodes, rapprochements, reprise et vente → rapports, y compris deux flux bancaires opposés de 100 le même jour dans les modes attente et sans écriture. Ce dernier scénario échouait avant le correctif : aucun mouvement bancaire brut n’était enregistré pour un net nul. Il vérifie désormais débit bancaire = 100 et crédit bancaire = 100, puis l’annulation et les restes dus. Les neuf parcours supplémentaires couvrent ES/FR/EN × 390/768/1440, axe et absence de débordement. Les captures mobile et ordinateur ont été examinées. Le parcours inclut l’ouverture de l’écriture réelle depuis le groupe.

La base de reprise est peuplée avant les migrations : les empreintes des écritures, lignes, paiements, banques, groupes, traitements et paramètres sont identiques après. Un rapprochement antérieur reste rejouable et annulable sans deuxième contrepassation.

## Migrations réellement appliquées

| Version | Nom | Octets SQL | SHA-256 |
| --- | --- | --- | --- |
| 20261026193150 | accounting_custom_payment_methods | 18 821 | 8dba6a71261f5aef19bfee39b0689cbb830bf28b6cb8c274b5f25a67781898bc |
| 20261026193151 | accounting_partial_bank_matching | 30 343 | c80659301e45f5c58f0a151b68e6af2879386c3eeb087193bfa5d294998ef118 |
| 20261026193755 | accounting_bank_history_links | 3 187 | 7369f819c5d73c9f9033864b06f0c37c42f65838adfbac5a9d9080ab939bb06d |
| 20261026200744 | accounting_bank_gross_flows | 1 683 | 2144c9f8e8e8c84e6ea988dc913f9994cd623783c0eb342705ea5c2014815412 |

Les fichiers de la PR ont été alignés sur les versions attribuées par Supabase avant intégration. Les octets des quatre migrations appliquées sont archivés sans réécriture dans `supabase/sql/applied/`. Aucune ancienne migration déjà présente sur main ni version du registre de production n’est renommée ou rejouée. Le correctif des flux bruts est une migration supplémentaire ; il ne réécrit aucune pièce historique.

## Conservation et accès

**58 écritures, 138 lignes ; débit = crédit = 8 552,49 USD ; zéro déséquilibre.** Les empreintes des **20 tables historiques** sont identiques [avant](evidence/partial-matching-before.json) et [après](evidence/partial-matching-after.json). Aucune facture, écriture, banque ou paiement de test n’est créé en production. Les trois nouvelles tables sont vides ; aucune préférence ou méthode n’a été activée sur les données réelles.

La [vérification des accès](evidence/partial-matching-access.json) confirme RLS, capture active d’historique, absence d’accès direct aux tables et façades publiques invocatrices. Les [deux appels HTTP anonymes](evidence/partial-matching-anonymous.json) sont refusés par HTTP 401 / 42501. L’historique renvoie un lien vers l’écriture de règlement effective et masque ces informations aux périmètres restreints. La revue Supabase ne signale aucune nouvelle alerte par rapport aux deux avertissements préexistants.

Sauvegarde logique privée ciblée de 20 tables : 1 049 128 octets, SHA-256 `eda73a0cfedd1937136c2bbaa55e7c2379dd3488efd8f7eb52b1ba67eaa8c44f`. Elle ne remplace pas une sauvegarde physique/PITR, non attestée pour les reprises structurelles futures.

## Publication et limites

Publication GitHub Pages réussie, run `40396126941`. Le [contrôle en lecture seule](evidence/partial-matching-web.json) confirme le commit réellement servi `273c54a497fcbffc9bce069cba8f609eaf7b57b9` et les octets des **dix actifs comptables**, y compris rapprochement, bundle commun et traductions serveur. URL vérifiée : https://lisciandraj.github.io/Pro-manager-Gama/. La session navigateur de production est à l’écran de connexion : aucune validation connectée sur les données réelles n’est annoncée. Les calculs et parcours authentifiés utilisent les RPC réelles dans les environnements isolés.

La [matrice](features.csv) conserve 54 lignes testées, 53 fonctions obligatoires incomplètes ou non démontrées et SRI exclu. E05 reste partiel pour les états Odoo exhaustifs. Stock 19, taxes avancées, analytique/budgets, multi-sociétés, immobilisations avancées et services externes restent ouverts. Cette livraison ne démontre pas une équivalence complète au module Odoo.

Retour arrière : conserver toutes les tables, affectations, traitements figés et écritures. Une correction de paiement ou de rapprochement passe par l’annulation motivée, ses contrôles de crédit et ses contrepassations. Un retour de l’interface nécessite une reconstruction et les contrôles habituels ; les méthodes nommées déjà utilisées et les portions de rapprochement ne doivent pas être supprimées. Privilégier une correction vers l’avant si ces nouvelles fonctions sont utilisées.
