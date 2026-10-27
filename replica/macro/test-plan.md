# Plan de vérification

| Cas | Vérification |
| --- | --- |
| F01-H1 | Réception vide puis tâche attribuée ; ouverture du dossier Projets exact. |
| F02-H1 | Créer canal avec collègue ; envoyer et répondre ; données relues par SQL réel. |
| F02-E1 | Texte long, accents, emoji, HTML inoffensif ; formulaire en erreur conserve le texte. |
| F02-E2 | Nouvelle tentative avec même clé = même message ; clé réutilisée avec autre contenu refusée. |
| F02-N1 | Autre administrateur et client exclus ; écriture directe refusée ; fil d'un autre canal refusé. |
| F03-H1 | Message → tâche native avec projet, auteur, responsable, échéance ; source et lien retour. |
| F03-E1 | Nouvelle tentative = une tâche et un lien ; erreur annule la transaction. |
| F04-H1 | Article lié → aperçu → discussions liées ; résultats de recherche issus des vraies tables. |
| F04-N1 | Référence inexistante refusée ; retrait d'un module masque le contenu déjà lié. |
| F05-H1 | Archiver/report personnel, restaurer, tâche métier intacte, changement fait réapparaître l'élément. |
| F06-H1 | Contexte du canal → brouillon Agent Coco ; aucune soumission automatique. |
| F07-H1 | Recherche texte commune ; résultats limités aux droits actuels. |
| S01-S06-E1 | 1440 px et 390 px ; champs nommés, clavier, axe, absence d'erreur console et HTTP 5xx. |
| S01-S06-E2 | FR/ES/EN ; déconnexion efface contenu, brouillons et dialogues ; module désactivé refusé. |

Les fournisseurs externes, le compte Gmail complet et les appels ne sont pas
simulés comme des fonctions terminées. Les essais de production seront limités
au schéma, à ses droits et à la publication, sans création d'objets métier.
