# Livraison de l’espace de travail Coco

27 octobre 2026. [PR #254](https://github.com/lisciandraj/Pro-manager-Gama/pull/254).
Fusion : `2278e6f380706ccd047cc28b2258a7c1f3960261`.

## Périmètre

Le noyau livré comprend réception personnelle, canaux privés, fils de discussion,
tâches natives Projets depuis un message, références dans les deux sens,
recherche et contexte de lecture pour Agent Coco. Les neuf exigences obligatoires
du périmètre sont réalisées. La matrice ne mesure pas une copie exhaustive de
Macro : messagerie externe complète, appels, calendrier connecté, édition CRDT,
tableur collaboratif et agents de code restent hors de cette tranche.

Identité, composants et traductions FR/ES/EN Coco conservés. Aucune ressource
propriétaire Macro importée. Les dernières corrections TMS présentes sur `main`
ont été conservées avant la fusion.

## Vérifications

- 30 parcours navigateur ordinateur/téléphone réussis sur l’espace, les
  historiques et Agent Coco ; analyse axe incluse dans les parcours de l’espace.
- 20 contrôles ciblés des historiques, propositions et canaux réussis après
  correction du périmètre RH ; 16 contrôles espace/serveur Agent réussis.
- Sources, types, documentation, registre des migrations, génération reproductible
  et budgets de démarrage vérifiés. Aucun budget relevé.
- La première suite complète a détecté une régression du filtrage RH ; corrigée
  par migration additive et retestée. La relance locale complète n’a pas fourni
  de résultat final exploitable et n’est pas comptée comme réussie.
- La validation complète GitHub sur la branche intégrée a ensuite réussi :
  671 tests serveur/unitaires, dont 669 réussis et deux conditionnels ignorés,
  aucun échec ; 211 tests navigateur réussis dans le job de construction,
  dont les trois parcours dédiés à l’espace. Preuve : job `122426786972` du
  [workflow de la branche](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40571508485).
- La publication conserve les contrôles `npm run update`, métier et navigateur
  du dépôt, avec le nouveau parcours de l’espace avant déploiement.

## Serveur en production

Projet Supabase existant : `mknsaibrewksgomuslev`.

| Élément | Preuve |
| --- | --- |
| Schéma de l’espace | Migration réelle `20261027192448`, source canonique `20261027190537_coco_unified_workspace.sql` |
| Correction de l’historique | Migration réelle `20261027192816`, source canonique `20261027192700_coco_workhub_preserve_history_scope.sql` |
| Accès | Six tables privées avec RLS ; façade SECURITY INVOKER ; exécution anonyme refusée |
| Agent Coco | `gama-assistant-ia` v7 ACTIVE, vérification JWT conservée ; fichiers relus identiques aux sources |
| Autorisation de lecture Agent | Jeton du demandeur ; canaux et sources sous leurs droits courants ; aucune écriture métier par `read_workspace` |
| Conseiller de sécurité | Aucune nouvelle alerte par rapport à la référence avant migration |

Les versions et octets réels sont archivés dans `supabase/sql/applied/`. Aucune
migration appliquée n’a été réécrite. Aucun faux message ou dossier n’a été ajouté
aux données de production ; les tests utilisent une base isolée.

## Publication de l’interface

Cible : <https://lisciandraj.github.io/Pro-manager-Gama/>.

Workflow : <https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40571513399>,
terminé avec succès. Les jobs construction, navigation, métier et publication
ont tous réussi. Les quinze contrôles complémentaires sur la révision fusionnée
ont également réussi.

Vérification publique le 27 octobre 2026 à 21 h 32, heure de Bruxelles :
`coco-build.json` sert exactement `2278e6f380706ccd047cc28b2258a7c1f3960261`.
Le JavaScript de l’espace (34 120 octets), sa feuille de style (6 259 octets) et
le cœur de navigation (81 496 octets) ont été téléchargés depuis les adresses
versionnées du manifeste public et comparés octet par octet aux fichiers validés.
Les trois comparaisons sont identiques. Empreintes et marqueur exacts dans
`deployment.json`.

La validation complète sur `main` confirme 669 tests serveur/unitaires réussis,
deux ignorés et aucun échec, puis 211 tests navigateur dans le job de
construction. L’écran **Espace de travail / Espacio de trabajo / Workspace** est
publié avec le noyau décrit ci-dessus. Ces preuves de publication ne changent
pas les limites fonctionnelles de la matrice.

Retour arrière : nouvelle révision validée de l’interface, en conservant les
migrations additives et les données de l’espace. Aucun effacement de données
n’est requis pour masquer le module.
