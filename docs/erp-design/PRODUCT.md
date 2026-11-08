# Coco ERP — contexte produit interne

Coco ERP est un ERP de gestion pour PME, disponible en français, espagnol et anglais. Cette fiche concerne l’application interne servie par `src/app/index.html` et publiée sur [GitHub Pages](https://lisciandraj.github.io/Pro-manager-Gama/). Le site public GAMA possède ses propres fichiers de contexte et de design à la racine.

Le travail quotidien consiste à retrouver une information, consulter ou modifier un dossier et réaliser les actions disponibles dans les modules autorisés. La [navigation actuelle](../modules/navigation.md) décrit les modules ; le [README](../../README.md) et l’[architecture](../architecture.md) restent les sources de vérité pour le produit et son exécution.

La refonte Openhub change la présentation de l’application existante. Elle conserve les contenus, données, calculs, droits, identifiants publics, actions, traductions, favoris et préférences. Les compteurs et graphiques présentent les données disponibles ; un état inconnu ou une erreur ne devient pas un zéro ou un succès.

Le travail doit rester possible sur ordinateur et téléphone, au clavier et avec les réglages de mouvement réduit. Les listes larges défilent dans leur conteneur. Les formulaires gardent leurs libellés, leur validation, les valeurs saisies lors d’un échec et leurs retours de focus. Le choix de vue et de colonnes déjà enregistré garde la priorité.

La direction visuelle est décrite dans [DESIGN.md](DESIGN.md) et sa sidecar `.impeccable/design.json`. La [référence Openhub CRM Dashboard](https://dribbble.com/shots/24822804-Openhub-CRM-Dashboard) guide la structure et les rôles visuels. L’identité, les actifs approuvés et les données métier restent ceux de Coco ERP.
