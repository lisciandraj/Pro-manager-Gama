# Livraison du noyau collaboratif

27 octobre 2026. Sources natives Coco, reconstruction depuis la documentation
publique de Macro ; aucune ressource propriétaire importée.

| Écran | État | Validation |
| --- | --- | --- |
| S01 Réception | Réalisé | Classement personnel et report ; tâches et propositions sous droits actuels. |
| S02 Canaux | Réalisé | Membres privés, fils, saisie conservée et synchronisation visible toutes les 20 s. |
| S03 Messages et sources | Réalisé | Liens résolus sous RLS et références retour, retrait des accès testé. |
| S04 Tâches | Réalisé | Une tâche native Projets par requête, source et responsabilité conservées. |
| S05 Documents et clients | Réalisé | Lectures natives et ouverture dans les modules existants. |
| S06 Agent Coco | Réalisé | Brouillon de contexte et outil serveur de lecture du travail commun, preuves citées et droits du demandeur. |

Corrections avant livraison : ordre sémantique des titres visible dans le shell
Coco, clés de requête, bonnes options des liens Projets/Documents/Contacts,
conservation des brouillons pendant l'arrivée de nouveaux messages et résolution
des devis avec le numéro canonique. Vérification SQL, tests du serveur Agent
Coco et parcours navigateur réels avec base isolée. Les capacités non réalisées
restent explicitement dans la matrice et dans la documentation du module.

Migration initiale installée sous la version 20261027192448. Correction additive
du périmètre de l’historique installée sous 20261027192816 ; les octets archivés
sont ceux du registre réel. Les migrations appliquées ne sont pas réécrites.
Agent Coco v7 est actif, JWT conservé, fichiers déployés identiques aux sources.

## S07 — documents collaboratifs

27 octobre 2026. Texte partagé par canal, liens et recherche, coédition Yjs
avec validation serveur et reçus sous le jeton original, versions et export,
archivage, mémoire des brouillons dans l’onglet. 17 contrôles serveur incluant
Agent Coco et documents, 19 contrôles des historiques existants et 32 parcours
navigateur réussis. Le contrôle visuel a corrigé les boutons comprimés sur
téléphone ; les deux parcours documentaires repassent après correction, avec
assertion de lisibilité et analyse axe. Captures S07 ordinateur et téléphone.

Les articles/fichiers métiers sont conservés. Synchronisation du texte toutes
les deux secondes, sans présence partagée ni hors-ligne durable. Éditeur riche,
écriture documentaire par Agent Coco, tableur/canvas et intégrations externes
restent hors de cette tranche.

La migration documentaire et les fonctions serveur sont installées. Les PR
[#260](https://github.com/lisciandraj/Pro-manager-Gama/pull/260) et
[#262](https://github.com/lisciandraj/Pro-manager-Gama/pull/262) sont fusionnées.
La publication de la révision `559886e049936addd7913375047325d289b46901`
est vérifiée le 28 octobre 2026 à 00 h 47, heure de Bruxelles : sept fichiers
publics correspondent octet pour octet aux fichiers construits localement.

Un contrôle supplémentaire reproduit l’archivage depuis une autre session
pendant qu’un brouillon reste en mémoire. Le statut conserve le brouillon et
permet sa restauration ; l’archivage local est bloqué tant que l’enregistrement
reste incomplet. Les deux parcours documentaires et les 24 contrôles
d’architecture passent après correction. Le pipeline final passe avec 714 tests
serveur et unitaires réussis, deux tests conditionnels ignorés, 223 tests
navigateur réussis et les 19 vérifications de la révision au vert.

Voir [le rapport de livraison](deploy.md) et [les preuves structurées](deployment.json).
