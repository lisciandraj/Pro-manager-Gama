# Contrat des composants Coco — GAMA, 18 octobre 2026

Les quatre modèles fournis (IMG_1295, IMG_1296, IMG_1297 et IMG_1298) définissent la nouvelle base visuelle. Le fond intérieur mesuré est #F3F4F6, les surfaces #FFFFFF. Leur cadre gris extérieur appartient à la présentation de la maquette. Coco conserve ses logos, ses icônes originales, les couleurs GAMA et Inter locale. Aucun nouveau framework, aucune copie des données ou images PeopleOS.

La source de vérité est `src/styles/tokens.css`. `src/styles/design.css`, chargé après les mises en page, applique les composants communs. Les styles de modules différés utilisent les mêmes variables. Les fichiers de ce dossier documentent le contrat et ne sont pas importés en plus dans l’application.

| Composant | Variantes, états et règles |
| --- | --- |
| Cadre | Fond gris froid mat, barre et menu blancs, séparateurs fins, texte pétrole. Structure existante : barre de 60 px, lanceur avec favoris, onglets natifs horizontaux. Padding 24/16/12 px selon largeur. Retour, menu modal, focus et droits conservés. |
| Carte / panneau | Blanc, bordure #B5C5D0 1 px, rayon 12 px, reflet satiné et ombre douce de 2–5 px, padding 20 px / 16 px sur mobile. Titres 16 px/600 ; contenu 14 px/400. La hauteur dépend du contenu. États vide/chargement/erreur conservés. |
| Bouton | Primaire orange soutenu #BD4E09 → #C45310 avec discret dégradé et texte blanc #FFFFFF, comme les références fournies ; secondaire blanc ; danger/succès sémantiques. Rayon 8 px, poids 500. Cible tactile 44 px ; action de ligne compacte sur PC. Survol, disabled natif, aria-busy et libellés existants conservés. Focus pétrole 2 px décalé de 3 px. |
| Champ | Inter, étiquette persistante, hauteur native ≥44 px, rayon 8 px, bordure #7B8797. Texte 16 px sur téléphone. Placeholder contrasté, lecture seule grisée, erreur textuelle avec aria-invalid. Aide, valeurs, validation et reprise inchangées. |
| Tableau | En-tête #F8F9FB, texte 13 px/500 ; lignes blanches et cellules 13 px. Padding 10 × 14 px, séparateurs horizontaux #E9ECF1, quadrillage vertical discret #F1F3F6. Survol et sélection pétrole clair. Montants tabulaires alignés à droite ; défilement local. Tri, colonnes, pagination, filtres et préférences inchangés. |
| Tableau en cartes | Blanc, rayon 12 px, bordure fine ; libellés de chaque valeur conservés dans toutes les langues. Les préférences enregistrées restent prioritaires. Aucun titre/cellule/contrôle masqué par le thème. |
| KPI | Carte blanche, petite icône dans un carré arrondi, libellé 13 px, valeur 28 px/600, chiffres tabulaires et sous-texte contrasté. Valeur absente et vrai zéro gardent leur distinction. Liens et calculs restent ceux du module. |
| Graphique | Séries orange/pétrole et nuances, barres adoucies, grille fine, légende lisible avec repère coloré et libellé. Progressions sur rail gris de 6 px. Les valeurs, échelles, dates, info-bulles, exports, accès clavier et liens détaillés sont conservés. Aucun graphique fictif ajouté. |
| Kanban | Colonnes légèrement grisées, bordure fine, rayon 12 px ; cartes blanches rayon 10 px, padding 14 px. Titre léger, séparateurs fins, repère d’étape discret. Retard, gagné/perdu, glisser-déposer, focus et contrôles de déplacement gardent leurs états. |
| Badge | Rayon 6 px, contour fin, fond sémantique léger, texte 12 px/400. État toujours écrit ; couleur jamais seule. |
| Historique | Même carte blanche, bulles gris très clair / pétrole clair, bordure fine. Avatars, auteurs, dates, regroupements, liens et validation des propositions existants conservés. |
| Fenêtre | Cadre satiné opaque, rayon 16 px, ombre réservée à la superposition, voile flouté de 8 px. Taille, défilement, footer et retours restent adaptés aux formulaires existants. |
| Accueil | Tuiles blanches avec mêmes bordures et rayons, pictogrammes pleins bleu pétrole avec un détail orange, sans carré, fond, bordure ni padding autour de l’icône (référence du 19 octobre 2026), texte 14 px/500. Grille compacte, noms complets, favoris et ordre personnel inchangés. |

Les paires de texte sont mesurées à 4,5:1, les bordures de saisie et le focus à 3:1. Le texte blanc demandé sur les actions est conservé avec une nuance orange soutenue, distincte de l’orange décoratif GAMA. Le point le plus clair du dégradé atteint 4,57:1 ; les résultats recalculés sont dans `contrast.json`. Les séparateurs de surfaces sont décoratifs.

Les contrôles navigateur existants couvrent les modules, le responsive, les trois langues, les listes, les fenêtres et les actions Agent Coco avec des données locales. Les captures de vérification ne sont pas des données de production. Aucune migration SQL, API, route, permission ou fonction métier n’est modifiée.

Correction de lisibilité PC : le fond runtime devient #E4EBF0, les tuiles blanches ont un contour #708897. Les onglets actifs sont bleu pétrole #0C556B avec texte blanc et soulignement orange soutenu. Les mesures historiques des images de référence ci-dessus restent inchangées.
