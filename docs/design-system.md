# Charte graphique actuelle

Coco ERP utilise le thème bleu pétrole et orange inspiré de GAMA depuis le 29 septembre 2026. Les anciennes palettes violet/bleu robot sont conservées uniquement dans l’historique.

| Élément | Source actuelle |
| --- | --- |
| Tokens globaux | `src/styles/tokens.css` |
| Ajustements du thème et surfaces | `src/styles/design.css` |
| Accueil | `src/styles/home.css`, `src/ui/home-menu.js` |
| Barre latérale et supérieure | `src/styles/shell.css`, `src/ui/shell.js` |
| Icônes vectorielles des modules | `src/ui/icons.js` |
| Logo de marque | `coco-gama-logo.jpg` |
| Icône C pour smartphone/PC | `coco-gama-icon-180/192/512.png`, variantes maskable, `favicon.ico` |
| Variantes d’export de marque | `assets/brand/` |

Les accents principaux sont `#157F98`, `#10677D`, `#238FA4` et `#F87826`. Les tokens de texte et fonds déterminent leur usage ; les noms historiques comme `--arc-coco-violet` sont des alias compatibles, pas une description de la couleur affichée.
La barre latérale et la barre supérieure restent blanches. Les titres d’introduction de l’accueil ont été retirés ; les tuiles gardent leur bordure fine et leur personnalisation. Une photo d’employé peut remplacer les initiales du profil.

Les rapports de contraste historiques ne doivent pas être réutilisés après une modification de couleurs : vérifier le couple texte/fond réellement calculé, y compris les surcharges du thème.

Les tableaux de tous les modules utilisent désormais la vue tableau par défaut, y compris en portrait sur téléphone. Les cellules possèdent des bordures horizontales et verticales visibles (`--arc-table-grid` dans `src/ui/components.css`) ; les en-têtes et cellules vides gardent leur alignement. Les grands tableaux défilent dans leur propre zone. Le sélecteur permet toujours un choix explicite des cartes, conservé par compte et tableau (`src/ui/tables.js`).

L’ordre des colonnes se modifie en glissant un en-tête (souris) ou sa poignée (tactile), ou avec Alt + flèche gauche/droite sur l’en-tête/la poignée. Le menu Colonnes propose la remise à l’ordre initial. L’ordre est enregistré dans le navigateur par compte et tableau, avec les préférences existantes de colonnes masquées ; il survit au rechargement et à la pagination mais n’est pas synchronisé entre appareils. Le tri reste attaché à la clé métier d’origine. Les cellules fusionnées restent groupées : un déplacement qui couperait un groupe est refusé ; les en-têtes à plusieurs niveaux et les tableaux avec fusion verticale conservent leur structure.

Les fenêtres de consultation partagées affichent une seule action « Retour » (« Volver » / « Back »), sans doublon « Fermer ». Les formulaires conservent leur action métier et leur bouton Retour. Une confirmation explicite conserve ses deux choix. `ArcUI.dialog` reconnaît les anciens libellés de fermeture FR/ES/EN ; `dismissOnly` permet de déclarer ce comportement explicitement.
