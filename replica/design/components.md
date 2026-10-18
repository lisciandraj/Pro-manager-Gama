# Contrat des composants Coco — GAMA, 18 octobre 2026

Les trois modèles fournis (IMG_1295, IMG_1296, IMG_1297) définissent la nouvelle base visuelle. Le fond intérieur mesuré est #F3F4F6, les surfaces #FFFFFF. Leur cadre gris extérieur appartient à la présentation de la maquette. Coco conserve ses logos, ses icônes originales, les couleurs GAMA et Inter locale. Aucun nouveau framework, aucune copie des données ou images PeopleOS.

La source de vérité est `src/styles/tokens.css`. `src/styles/design.css`, chargé après les mises en page, applique les composants communs. Les styles de modules différés utilisent les mêmes variables. Les fichiers de ce dossier documentent le contrat et ne sont pas importés en plus dans l’application.

| Composant | Variantes, états et règles |
| --- | --- |
| Cadre | Fond gris froid mat, barre et menu blancs, séparateurs fins, texte pétrole. Structure existante : barre de 60 px, lanceur avec favoris, onglets natifs horizontaux. Padding 24/16/12 px selon largeur. Retour, menu modal, focus et droits conservés. |
| Carte / panneau | Blanc, bordure #DFE3EA 1 px, rayon 12 px, ombre nulle, padding 20 px / 16 px sur mobile. Titres 16 px/600 ; contenu 14 px/400. La hauteur dépend du contenu. États vide/chargement/erreur conservés. |
| Bouton | Primaire orange GAMA avec discret dégradé et texte blanc #FFFFFF, comme les références fournies ; secondaire blanc ; danger/succès sémantiques. Rayon 8 px, poids 500. Cible tactile 44 px ; action de ligne compacte sur PC. Survol, disabled natif, aria-busy et libellés existants conservés. Focus pétrole 2 px décalé de 3 px. |
| Champ | Inter, étiquette persistante, hauteur native ≥44 px, rayon 8 px, bordure #7B8797. Texte 16 px sur téléphone. Placeholder contrasté, lecture seule grisée, erreur textuelle avec aria-invalid. Aide, valeurs, validation et reprise inchangées. |
| Tableau | En-tête #F8F9FB, texte 12 px/500 ; lignes blanches et cellules 13 px. Padding 12 × 14 px, séparateurs horizontaux #E9ECF1, quadrillage vertical discret #F1F3F6. Survol et sélection pétrole clair. Montants tabulaires alignés à droite ; défilement local. Tri, colonnes, pagination, filtres et préférences inchangés. |
| Tableau en cartes | Blanc, rayon 12 px, bordure fine ; libellés de chaque valeur conservés dans toutes les langues. Les préférences enregistrées restent prioritaires. Aucun titre/cellule/contrôle masqué par le thème. |
| KPI | Carte blanche, petite icône dans un carré arrondi, libellé 13 px, valeur 28 px/600, chiffres tabulaires et sous-texte contrasté. Valeur absente et vrai zéro gardent leur distinction. Liens et calculs restent ceux du module. |
| Graphique | Séries orange/pétrole et nuances, barres adoucies, grille fine, légende lisible avec repère coloré et libellé. Progressions sur rail gris de 6 px. Les valeurs, échelles, dates, info-bulles, exports, accès clavier et liens détaillés sont conservés. Aucun graphique fictif ajouté. |
| Kanban | Colonnes légèrement grisées, bordure fine, rayon 12 px ; cartes blanches rayon 10 px, padding 14 px. Titre léger, séparateurs fins, repère d’étape discret. Retard, gagné/perdu, glisser-déposer, focus et contrôles de déplacement gardent leurs états. |
| Badge | Rayon 6 px, contour fin, fond sémantique léger, texte 12 px/400. État toujours écrit ; couleur jamais seule. |
| Historique | Même carte blanche, bulles gris très clair / pétrole clair, bordure fine. Avatars, auteurs, dates, regroupements, liens et validation des propositions existants conservés. |
| Fenêtre | Surface blanche, rayon 16 px, ombre légère réservée à la superposition, voile transparent. Taille, défilement, footer et retours restent adaptés aux formulaires existants. |
| Accueil | Tuiles blanches avec mêmes bordures et rayons, icônes bleu/orange conservées, texte 14 px/500. Grille compacte, noms complets, favoris et ordre personnel inchangés. |

Les paires de texte sont mesurées à 4,5:1, les bordures de saisie et le focus à 3:1. Le propriétaire demande explicitement le texte blanc sur les boutons orange le 18 octobre 2026, à l’identique des références : ces couples ne passent pas le seuil AA du texte courant et sont conservés comme tels dans `contrast.json`. Les autres résultats restent inchangés. Les séparateurs de surfaces sont décoratifs.

Les contrôles navigateur existants couvrent les modules, le responsive, les trois langues, les listes, les fenêtres et les actions Agent Coco avec des données locales. Les captures de vérification ne sont pas des données de production. Aucune migration SQL, API, route, permission ou fonction métier n’est modifiée.
