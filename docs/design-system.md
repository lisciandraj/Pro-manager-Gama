# Charte graphique actuelle

Coco ERP utilise le thème bleu pétrole et orange inspiré de GAMA depuis le 29 septembre 2026. Les anciennes palettes violet/bleu robot sont conservées uniquement dans l’historique.

| Élément | Source actuelle |
| --- | --- |
| Tokens globaux | `src/styles/tokens.css` |
| Ajustements du thème et surfaces | `src/styles/design.css`, puis `src/styles/workspace.css` |
| Accueil | `src/styles/home.css`, `src/ui/home-menu.js` |
| Barre latérale et supérieure | `src/styles/shell.css`, `src/ui/shell.js` |
| Icônes vectorielles des modules | `src/ui/icons.js` |
| Logo de marque | `coco-gama-logo.jpg` |
| Icône C pour smartphone/PC | `coco-gama-icon-180/192/512.png`, variantes maskable, `favicon.ico` |
| Variantes d’export de marque | `assets/brand/` |

Les accents principaux sont `#157F98`, `#10677D`, `#238FA4` et `#F87826`. Les tokens de texte et fonds déterminent leur usage ; les noms historiques comme `--arc-coco-violet` sont des alias compatibles, pas une description de la couleur affichée.
La barre latérale et la barre supérieure restent blanches. Les titres d’introduction de l’accueil ont été retirés ; les tuiles gardent leur bordure fine et leur personnalisation. Une photo d’employé peut remplacer les initiales du profil.

Les rapports de contraste historiques ne doivent pas être réutilisés après une modification de couleurs : vérifier le couple texte/fond réellement calculé, y compris les surcharges du thème.

Les tableaux utilisent la vue tableau par défaut. Le stock ouvre des fiches sur téléphone (760 px ou moins) si le compte n’a pas déjà choisi une vue ; un choix enregistré reste prioritaire. Les cellules possèdent des bordures horizontales et verticales visibles (`--arc-table-grid` dans `src/ui/components.css`) ; les en-têtes et cellules vides gardent leur alignement. Les grands tableaux défilent dans leur propre zone. Le sélecteur permet toujours un choix explicite des cartes, conservé par compte et tableau (`src/ui/tables.js`).

En mode tuiles, les valeurs de détail affichent leur intitulé de colonne (`data-col`), à gauche de la valeur, sur téléphone comme sur ordinateur. La règle des cartes réactive explicitement ces intitulés, masqués en mode tableau. Le titre de la tuile, les photos et les boutons conservent leur présentation sans intitulé supplémentaire.

L’ordre des colonnes se modifie en glissant un en-tête (souris) ou sa poignée (tactile), ou avec Alt + flèche gauche/droite sur l’en-tête/la poignée. Le menu Colonnes propose la remise à l’ordre initial. L’ordre est enregistré dans le navigateur par compte et tableau, avec les préférences existantes de colonnes masquées ; il survit au rechargement et à la pagination mais n’est pas synchronisé entre appareils. Le tri reste attaché à la clé métier d’origine. Les cellules fusionnées restent groupées : un déplacement qui couperait un groupe est refusé ; les en-têtes à plusieurs niveaux et les tableaux avec fusion verticale conservent leur structure.

Les fenêtres de consultation partagées affichent une seule action « Retour » (« Volver » / « Back »), sans doublon « Fermer ». Les formulaires conservent leur action métier et leur bouton Retour. Une confirmation explicite conserve ses deux choix. `ArcUI.dialog` reconnaît les anciens libellés de fermeture FR/ES/EN ; `dismissOnly` permet de déclarer ce comportement explicitement.

Les maquettes approuvées sont implémentées dans `src/styles/workspace.css` : navigation blanche, tuiles bleu pastel/orange, titres visibles, favoris par compte, et navigation mobile Accueil/Recherche/Scanner/Plus. La première catégorie de la barre latérale est « Favoris » : les modules étoilés sur l’accueil y apparaissent immédiatement, dans l’ordre de leur ajout et selon les droits du compte. Retirer une étoile retire aussi son raccourci ; les changements sont synchronisés entre les onglets du navigateur. Sans favori, une indication explique comment en ajouter. Les favoris sont aussi accessibles dans le menu mobile. L’accès au scanner conserve les droits du module. Les favoris et l’ordre personnel des modules sont indépendants.

Le Dashboard présente les indicateurs du profil, le graphique, les actions du jour et cinq commandes récentes. Les vues favorites, indicateurs personnels et analyses détaillées restent accessibles dans des sections dépliables. Les commandes récentes sont une lecture limitée soumise aux mêmes droits, annulée visuellement lors d’un changement de compte ou de période.

Le stock conserve les calculs serveur : physique, réservé et disponible sont distincts. Six colonnes principales ouvrent un inspecteur avec les autres valeurs et emplacements. Les filtres avancés restent accessibles sans charger les onglets secondaires. La commande affiche huit étapes issues des données disponibles, ses lignes et une prochaine action réutilisant le bouton métier existant. Une preuve de livraison ne devient pas validée à partir du seul statut d’expédition.

Le SRI filtre les états fiscaux à la source avec pagination ; les onglets de traitement consultent les émissions liées à leurs factures. L’inspecteur distingue état interne et autorisation fiscale ; les contrôles ne deviennent verts qu’après la vérification API effective. XML/RIDE nécessitent une autorisation. Les envois groupés conservent les confirmations, droits et contrôles de non-réémission.

La réception mobile présente Quantités/Photo/Signature. Le bouton de sauvegarde attend les quantités cohérentes, le nom et la signature pour une réception acceptée, le motif d’incident, et la photo obligatoire si des unités manquent. La validation serveur et le fonctionnement hors connexion sont conservés.
