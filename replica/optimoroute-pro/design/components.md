# Intégration aux composants Coco

Réutiliser les tokens architect-tokens.css et coco-style-tms-module.css. Les couleurs, typographie, arrondis, ombres, espacements et boutons restent ceux du module existant. Aucun logo, actif ou texte commercial OptimoRoute n’est publié dans l’interface.

Les commandes additionnelles s’ouvrent depuis une action « Planning et suivi » et des onglets à l’intérieur du même espace TMS. Conserver les étapes Préparer, Planifier, Charger, Livrer. Les formulaires s’appuient sur ArcUI.dialog, les données sur ArcUI.table ; boutons réels, labels explicites, focus visible, fermeture Échap et erreur dans role=alert. Les positions anciennes sont accompagnées de leur heure ; une absence de GPS reste un état vide.

Ordinateur : tables et carte existantes ; téléphone 390 px : barre d’onglets défilante et formulaires sur une colonne, tables dans un conteneur défilant sans débordement de page. Langues ES/FR/EN via la fonction de traduction du module. Aucun nouveau lot au démarrage de Coco.


### Éditeurs de ressources et lieux

Réutiliser les champs/fieldset/dialogues et tokens Coco. L’éditeur des capacités groupe clé stable, nom et unité ; l’éditeur véhicule reprend les mêmes noms/unités. La livraison exige une valeur explicite, dont zéro. L’éditeur conducteur masque et désactive les coordonnées du départ général et des fins non personnalisées ; les champs affichés ont un label et des limites natives. Le tableau Ressources récapitule les lieux et les capacités. Sur téléphone, formulaire sur une colonne et défilement du tableau dans son conteneur. Un changement de configuration affiche un conflit de version, sans remplacer une autre modification.
