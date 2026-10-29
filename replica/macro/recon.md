# Macro → Coco ERP : reconnaissance fonctionnelle

Date : 27 octobre 2026. Destination : Coco ERP web/PWA, ordinateur et téléphone,
pour l'équipe de distribution GAMA à Quito. Réalisation native ; modules et
identité Coco conservés. Analyse depuis les pages publiques uniquement.

## Sources

| Source | Observation |
| --- | --- |
| https://macro.com/ | Espace commun email, discussions, tâches, documents, CRM, agents ; liens bidirectionnels. |
| https://docs.macro.com/ | Blocs spécialisés, boîte commune, recherche et contexte d'équipe. |
| https://macro.com/channels/ | Canaux, fils de discussion, transformation d'un message en tâche. |
| https://macro.com/tasks/ | Responsable, priorité, état, tâche issue d'un message et conservation du contexte. |
| https://github.com/macro-inc/macro/blob/main/apps/docs/getting-started.mdx | Documentation publique : triage, raccourcis, travail côte à côte. Aucun code applicatif utilisé. |
| https://macro.com/terms | Restrictions d'utilisation du service : aucun compte Macro ouvert ni utilisé pour cette reconstruction. |

## Écrans et parcours

| ID | Écran Coco | Finalité et états |
| --- | --- | --- |
| S01 | Espace de travail / Réception | Éléments métier autorisés et nouveaux messages ; priorité, différer, archiver, recherche ; chargement, vide, erreur, pagination, accès refusé. |
| S02 | Canaux | Liste privée par appartenance, membres, discussion et réponses ; vide, erreur, texte long, mobile. |
| S03 | Message et contexte | Sources liées, tâche dérivée, références retour ; droit retiré, référence supprimée, nouvelle tentative. |
| S04 | Tâches | Tâches natives Projets et activités CRM ; ouverture du dossier existant et création native depuis un message. |
| S05 | Documents et clients | Articles Knowledge, documents et fiches clients existants ; liens sous les droits d'origine. |
| S06 | Contexte Agent Coco | Contexte du canal consultable et transmis comme brouillon de question à l'agent existant. |

F01 : S01 → ouvrir un élément → dossier existant → retour à l'espace.
F02 : S02 → créer un canal → choisir des collègues internes → envoyer un message → répondre.
F03 : S03 → créer une tâche → choisir un projet existant, responsable et échéance → tâche Projets liée au message.
F04 : S03 → lier une référence autorisée → ouvrir la référence → consulter ses conversations liées.
F05 : S01 → différer / archiver un élément → retrouver les éléments classés → restaurer.
F06 : S02 → contexte → S06 → brouillon Agent Coco → envoi volontaire dans l'agent.
F07 : rechercher un terme → résultats de discussion, tâches, documents et clients autorisés.

## Composants et modèle déduit

Liste commune, filtres typés, aperçu latéral, formulaire de message, réponse en
fil, sélecteur de source, formulaire de tâche, membres, bouton de contexte.
Toutes les valeurs saisies restent du texte, jamais du HTML interprété.

Macro associe équipe, canal, message, tâche, document et lien (confiance élevée,
documentation). Les détails internes de son schéma sont inconnus. Coco conserve
ses tables Projets, CRM, Knowledge et Documents ; seules les discussions, leurs
liens et le classement personnel nécessitent de nouvelles tables.

## Frontières et ampleur

Le noyau de travail commun est la première tranche, de taille M. La parité
intégrale Macro est XL : éditeur CRDT, appels enregistrés/transcrits, calendrier,
feuilles collaboratives, synchronisation Gmail complète, MCP et agents de code
sont des chantiers distincts. Le relais mail et les approbations Coco existants
sont conservés ; aucun nouvel OAuth mail, compte fournisseur ou abonnement.
Un lien dans un canal ne donne jamais accès à un dossier ERP autrement interdit.
Les API privées, logos, ressources et textes de Macro ne sont pas intégrés.

## Extension S07 — texte partagé

Documents privés par canal, création avec lien explicite, coédition de texte,
versions consultables, export, archivage et retrait des droits. Parcours F08,
F09 et F10 détaillés dans [la seconde tranche](collaborative-documents.md).
