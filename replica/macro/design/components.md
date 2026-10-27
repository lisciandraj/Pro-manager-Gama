# Interface et composants

L'identité de référence est Coco : `src/styles/tokens.css`, ArcUI, Inter,
bleu pétrole et orange. Aucun actif Macro n'est livré. Le modèle collaboration
de UI/UX Pro Max recommande une présentation minimale, des surfaces calmes et
une hiérarchie lisible ; les tokens Coco restent prioritaires.

Réception : colonne de navigation compacte, liste lisible, détail latéral sur
grand écran et en dessous sur téléphone. Recherche commune à l'espace et accès
à la recherche ERP. Canaux : en-tête, messages, réponses regroupées sous leur
parent, formulaire avec labels. Boutons tactiles d'au moins 44 px ; focus visible,
alertes et progression annoncées, retours d'erreur conservant la saisie.

Les dialogues réutilisent ArcUI : focus, fermeture Échap, validation et bouton
occupé. Le contenu de source est échappé. L'affichage distingue classement
personnel et état métier : archiver une notification ne termine pas sa tâche.

Le chargement est différé : aucun téléchargement de données de discussion à
l'accueil. Les dimensions, espaces, couleurs, bordures et typographie dérivent
des propriétés CSS partagées ; les dimensions spécifiques sont des tokens locaux.
