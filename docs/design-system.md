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
