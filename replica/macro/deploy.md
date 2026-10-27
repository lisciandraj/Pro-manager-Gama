# Livraison — documents collaboratifs dans Coco ERP

Vérification du 28 octobre 2026 à 00 h 47, heure de Bruxelles.

La deuxième tranche est publiée dans [Coco ERP](https://lisciandraj.github.io/Pro-manager-Gama/).
Parcours : **Espace de travail → Documents → Nouveau document partagé**.
Les documents privés des canaux proposent la coédition de texte Markdown,
les versions, l’export, l’archivage et la lecture autorisée par Agent Coco.
La synchronisation visible utilise un intervalle de deux secondes ; les
brouillons restent en mémoire dans l’onglet et peuvent être exportés.

## Publication vérifiée

- PR [#260](https://github.com/lisciandraj/Pro-manager-Gama/pull/260) et
  [#262](https://github.com/lisciandraj/Pro-manager-Gama/pull/262) fusionnées.
- Révision publique : `559886e049936addd7913375047325d289b46901`.
- [Publication 40602198031](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40602198031)
  terminée avec succès ; les 19 vérifications de la révision passent.
- 716 tests serveur et unitaires : 714 réussis, aucun échec, deux ignorés.
- 223 tests navigateur réussis dans le job principal, dont les parcours de
  l’espace de travail et des documents.
- Marqueur public, HTML et manifeste relus ; les sept fichiers liés au module
  correspondent octet pour octet à la distribution locale testée.

Les fonctions `coco-workhub-documents` v1 et `gama-assistant-ia` v8 sont actives,
avec vérification JWT et fichiers identiques aux sources testées. La migration
documentaire est inscrite sous `20261027225549`. Les quatre tables privées ont
RLS activé, l’exécution anonyme est interdite et le navigateur ne peut pas
préparer de reçu serveur. L’OID et la politique d’accès de l’historique sont
conservés. Aucun document fictif n’a été créé dans les données de production.

## Périmètre livré

Les modules métier et l’identité visuelle Coco sont conservés. Cette tranche
ajoute le texte partagé au noyau déjà livré : canaux privés, fils, tâches
natives, liens entre sources et contexte de lecture Agent Coco.

La messagerie email complète, les appels et leur transcription, le calendrier
connecté et les réservations, les feuilles collaboratives et le canvas,
l’édition riche, les agents de code/MCP et l’écriture documentaire par Agent
Coco restent à développer. Cette livraison ne constitue pas une parité complète
avec Macro. La présence en direct et la reprise hors ligne durable ne sont pas
implémentées.

Preuves et limites : [données de publication](deployment.json),
[conception documentaire](collaborative-documents.md),
[journal de construction](build-log.md), [défauts corrigés](bugs.md),
[matrice des capacités](features.csv).
