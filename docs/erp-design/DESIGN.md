---
name: "Coco ERP — référence claire"
description: "Gestion quotidienne lisible, surfaces blanches et navigation violette partagée."
colors:
  petrol: "#6246CC"
  petrol-deep: "#5438BA"
  brand-blue: "#6246CC"
  action: "#6246CC"
  action-hover: "#5438BA"
  brand-orange: "#6246CC"
  ink: "#262331"
  muted: "#676473"
  surface: "#FFFFFF"
  inset: "#FAFAFC"
  canvas: "#FFFFFF"
  line: "#E9E9F0"
  row-line: "#E9E9F0"
  input-line: "#8E8A9C"
  selected: "#F0EBFC"
  hover: "#F8F6FE"
  success: "#16785D"
  success-bg: "#E8F8F2"
  warning: "#976015"
  warning-bg: "#FBF2E6"
  danger: "#BE3848"
  danger-bg: "#FFF0F1"
typography:
  headline:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: "44px"
    letterSpacing: "-0.025em"
  section:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.55
  table:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.55
  field-label:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.5
  field-value:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  value-mobile:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
  status:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.55
  button:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.55
  home-label:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.35
  compact-home-label:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.25
rounded:
  control: "8px"
  inset: "12px"
  panel: "16px"
  mobile-panel: "16px"
  badge: "6px"
  navigation: "8px"
  dialog: "16px"
spacing:
  s1: "4px"
  s2: "8px"
  s3: "12px"
  s4: "16px"
  s5: "20px"
  s6: "24px"
  s7: "32px"
  s8: "40px"
components:
  button-primary:
    backgroundColor: "{colors.action}"
    textColor: "{colors.surface}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  button-primary-hover:
    backgroundColor: "{colors.action-hover}"
    textColor: "{colors.surface}"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.petrol}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.field-value}"
    rounded: "{rounded.control}"
    padding: "10px 12px"
  panel:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.panel}"
    padding: "24px"
  mobile-card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.mobile-panel}"
    padding: "16px"
  status-success:
    backgroundColor: "{colors.success-bg}"
    textColor: "{colors.success}"
    typography: "{typography.status}"
    rounded: "{rounded.badge}"
    padding: "4px 9px"
  module-tab:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "10px 16px"
  module-tab-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.petrol-deep}"
  sidebar-link:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "10px 12px"
    height: "44px"
---

# Design System: Coco ERP — référence claire

## Overview

**Creative North Star: "Coco / GAMA — gestion sereine"**

Coco ERP privilégie un travail quotidien calme et lisible : choisir un module, repérer ou rechercher une information, puis agir dans les parcours existants. Une toile blanche, une navigation gris très clair, un accent violet et une hiérarchie compacte rendent les données utiles visibles plus tôt. Les formulaires séparent clairement libellés, valeurs et groupes de champs sans élargir les listes opérationnelles.

Ce contrat décrit l’application interne servie par `src/app/index.html`. Il applique la référence graphique fournie le 7 novembre 2026 à l’application réelle GitHub Pages ; l’aperçu privé Sites reste distinct. Les révisions GAMA et Geex antérieures restent historiques pour la finition visuelle. Les tokens viennent de `src/styles/tokens.css`, appliqués par `workbench.css`, `design.css`, les contrôles partagés et les feuilles différées. Les fonctions, identifiants, droits, langues FR/ES/EN, favoris, historiques et données métier sont conservés. Le site public possède son propre `DESIGN.md` à la racine.

**Key Characteristics:**

- Toile blanche, navigation gris clair et cartes à contour fin sans ombre.
- Inter pour les titres, les valeurs et les contrôles.
- Libellés proches de leur champ et groupes de formulaire espacés.
- Violet uni pour la commande principale et la destination active.
- Navigation et utilitaires compacts, structures métier conservées.

## Colors

### Primary

Le violet `#6246CC` porte les actions principales, liens et sélections ; le survol utilise `#5438BA`. La destination latérale active combine fond violet et texte/icône blancs. Les noms historiques `petrol`, `brand-blue` et `brand-orange` restent des alias compatibles et ne prescrivent plus leurs anciennes teintes.

### Reporting and semantic states

Les graphiques conservent leurs séries réelles et utilisent le bleu `#467CF5`, le violet `#6246CC`, la lavande `#C9BDF7` et le mauve `#B3A0D6`. Les statuts utilisent succès `#16785D` sur `#E8F8F2`, attention `#976015` sur `#FBF2E6` et erreur `#BE3848` sur `#FFF0F1`, avec un libellé explicite.

### Neutral

La toile et les panneaux sont blancs, la navigation `#F6F6F9` et les retraits `#FAFAFC`. Les bordures fines `#E9E9F0` organisent les cartes ; les champs utilisent `#8E8A9C`. Les cartes n’ont pas d’ombre ni de gradient ; la profondeur est réservée aux superpositions.

Couples de tokens calculés : texte secondaire/blanc 5,76:1 ; blanc/action 6,43:1 ; blanc/survol 7,92:1 ; états sémantiques au moins 4,74:1. Ces calculs ne certifient pas chaque état réellement peint.

**The Action Rule.** Réserver le violet plein à la commande principale et à la destination courante ; employer les surfaces claires pour les commandes secondaires.

## Typography

Inter locale est la police des titres, du texte de travail, des valeurs et des contrôles ; elle est préchargée par l’application. Les polices système servent de repli. Les licences locales restent dans `fonts/` ; aucune police distante n’est requise au rendu.

Le titre unique du bandeau utilise `title`, puis reste à 24 px sur PC/tablette et passe à 20 px jusqu’à 760 px. Sa description traduite utilise 12 px et disparaît sur téléphone. `headline` et `section` décrivent les titres de contenu ; certains panneaux emploient le titre compact de 16 px. Les cellules PC utilisent généralement `table`, les libellés de formulaire `field-label` et les valeurs `field-value`, explicitement à 14 px sur PC. Champs et valeurs de fiches passent à `value-mobile` sur téléphone. Les montants emploient des chiffres tabulaires et s’alignent à droite.

L’accueil garde ses adaptations existantes : les libellés ont généralement 12 px sur grand PC et téléphone ; l’interligne devient 1,2 sur grand PC, et les largeurs intermédiaires conservent leurs ajustements de 13–14 px. Jusqu’à 359 px, `compact-home-label` conserve les noms complets dans trois colonnes.

**The Readability Rule.** Conserver les libellés complets, les traductions et le retour à la ligne sans comprimer la cible de commande.

## Layout

À partir de 1180 px, la barre latérale droite mesure 256 px, sans retrait ni arrondi ; le contenu principal commence à 256 px. Le bandeau blanc a une hauteur minimale de 80 px : retour et titre unique à gauche, recherche globale et utilitaires existants à droite. Le contenu reçoit 20 px en haut, 28 px sur les côtés et 32 px en bas, plus les zones de sécurité. La recherche globale mesure 40 px de haut sur PC.

Sous 1180 px, le menu devient un tiroir de largeur maximale 304 px, l’espace principal revient au bord de l’écran et le bandeau passe à 80 px minimum. Le contenu utilise 18 px en haut et 24 px sur les côtés. Jusqu’à 760 px, le bandeau conserve son minimum de 80 px, la recherche globale rejoint son accès mobile et la description est masquée. L’accueil téléphone conserve menu et compte sans logo CO dans le bandeau. Le contenu utilise 16 px en haut et 14 px sur les côtés, ramenés à 12 px jusqu’à 359 px, plus les zones de sécurité. La navigation basse Accueil / Recherche / Scanner / Plus reste disponible jusqu’à 860 px ; le contenu réserve sa place et les historiques ajoutent leur réserve de sécurité propre.

Ces minima ne bloquent pas une hauteur nécessaire au contenu. Les panneaux métier collants suivent la hauteur réellement peinte du bandeau, recalculée après redimensionnement, traduction et chargement des polices. Les onglets natifs restent dans le contenu de leur module, avec défilement horizontal lorsque nécessaire.

### Formulaires et listes

Le rythme partagé conserve un écart de 8 px entre libellé et champ. Les rangées de formulaire utilisent 24 px sur PC et 20 px sur téléphone ; les colonnes utilisent respectivement 24 et 16 px. Une section ou une rangée d’actions peut être séparée de 32 px. Les modules gardent leurs colonnes et leur ordre métier ; les champs s’empilent selon leur place disponible. Les panneaux génériques utilisent 24 px de marge intérieure sur PC et 16 px sur téléphone.

Les listes de travail PC utilisent 12 px verticalement et 16 px horizontalement dans les cellules, un contour fin par ligne et 8 px de séparation entre lignes. Les actions de 44 px restent accessibles ; les lignes grandissent selon leur contenu. Les documents papier sont exclus de cette finition. Aucun de ces tokens ne fixe une hauteur exacte universelle : les tableaux spécialisés et les métriques Dashboard conservent leurs dimensions dictées par le contenu.

Jusqu’à 760 px, les listes en lecture seule sans préférence enregistrée s’ouvrent en fiches ; les grilles éditables, fenêtres et tableaux exclus conservent leur structure et leur défilement local. Les choix explicites de vue, colonnes et ordre restent prioritaires. Les conteneurs peuvent rétrécir sans élargir toute la page.

### Accueil

Les tuiles restent carrées ; leur hauteur suit leur largeur. Des rangées Flexbox et un espace carré dans le flux évitent les calculs cycliques de hauteur WebKit. Les écrans courts défilent. Favoris, ordre personnel et modules autorisés restent attachés au compte.

| Largeur de la fenêtre | Colonnes d’accueil | Espacement |
| --- | --- | --- |
| Jusqu’à 359 px | 3 | 6 px |
| 360–760 px | 3 | 8 px |
| 761–860 px | 4 | 10 px |
| 861–1179 px | 5 | 12 px |
| 1180–1439 px | 7 | 18 px |
| À partir de 1440 px | 9 | 16 px |

Entre 861 et 1179 px avec une hauteur au plus 700 px, l’accueil utilise six colonnes. Jusqu’à 359 px, les tuiles gardent 6 px / 2 px de marge intérieure, 6 px entre icône et libellé, et des icônes de 28 px.

## Elevation & Depth

L’espace, les fonds et les bordures organisent les surfaces de travail. Cartes, tuiles, KPI et commandes sont sans ombre ; seule une superposition reçoit de la profondeur. Les valeurs exactes des ombres et du mouvement figurent dans la sidecar.

| Rôle | Token runtime | Emploi |
| --- | --- | --- |
| En retrait | `--coco-inset` | Zones secondaires, sans ombre |
| Surface | `--arc-sh-1` / `--coco-surface-shadow` = `none` | Panneaux, KPI, fiches et tuiles plats |
| Élevé | `--arc-sh-2` | Menus et superpositions légères |
| Superposition | `--arc-sh-3` / `--coco-dialog-shadow` | Fenêtres et tiroir ouvert |

La barre latérale PC et la commande principale sont plates. `--coco-surface-sheen` et `--coco-canvas-texture` valent `none`. Le voile des fenêtres reste sans flou permanent.

**The Surface Rule.** Utiliser une bordure fine sans ombre pour les cartes, et réserver la profondeur aux superpositions.

Les retours de pression, d’état et de superposition durent 120, 180 et 240 ms, avec `cubic-bezier(.16,1,.3,1)`. Aucun chargement de page n’apparaît en cascade. La réduction du mouvement conserve les couleurs, focus, textes et états sans déplacement décoratif. Impression, contraste renforcé et couleurs forcées gardent leurs adaptations. Ce contrat décrit le thème clair livré ; un mode sombre complet n’est pas activé par cette finition.

## Shapes

Les commandes et champs partagés utilisent `control`, les fonds en retrait `inset`, les surfaces `panel`, et les fenêtres `dialog`. Les surfaces de travail et fenêtres utilisent 16 px, y compris sur téléphone ; la barre latérale droite n’a pas d’arrondi. Les onglets et liens latéraux utilisent `navigation`, les badges leur rayon compact. Avatars, repères GPS et autres formes métier gardent leur géométrie spécifique.

## Components

### Buttons

La commande principale est violette unie avec texte blanc ; les actions secondaires sont blanches et les commandes discrètes utilisent le violet. Les contrôles communs conservent une hauteur minimale de 44 px. Les barres métier spécialisées gardent leur densité propre. Le focus visible utilise un trait violet de 2 px décalé de 3 px. Les états indisponibles et occupés gardent leur sémantique et ne bougent pas à la pression.

### Inputs / Fields

Fond blanc, contour de saisie explicite, libellé persistant et rayon commun. Les champs standards conservent 44 px de hauteur minimale, des valeurs normales de 14 px sur PC et 16 px sur téléphone ; le libellé à 13 px et graisse 500 reste distinct de la valeur à graisse 400. Les erreurs restent près du champ ; les valeurs survivent à un échec et le premier champ invalide reçoit le focus. La recherche globale PC utilise une surface blanche compacte.

### Navigation

La navigation latérale conserve groupes, favoris et liens autorisés. La destination courante combine fond violet plein et libellé/icône blancs. Le tiroir fermé est inerte ; ouvert, il retient le focus, rend l’arrière-plan inerte, se ferme avec Échap et rend le focus au déclencheur. Les onglets natifs restent dans leur module avec fond violet clair et contour violet pour la sélection. Les favoris de l’accueil et la navigation basse gardent leur accès et leur cible tactile.

### Lists / Cards / Status

Les listes de travail utilisent des lignes blanches à contour fin et une séparation verticale de 8 px, des en-têtes discrets et des montants alignés à droite. Les exports papier et grilles spécialisées gardent leurs contrôles. Les fiches mobiles affichent les noms des colonnes avec leurs valeurs. Les statuts portent leur texte et leur couleur sémantique. Tableaux spécialisés, arbres et graphiques conservent leurs contrôles métier.

CRM et Projets placent leurs tâches blanches sur des colonnes sans surface de fond. Documents et Knowledge séparent un rail blanc de 230 px et une surface principale blanche par 30 px ; les deux zones s’empilent jusqu’à 760 px. Ces finitions sont chargées avec leurs modules.

### Progressive Editors / History

Produits et Contacts gardent six champs métier par défaut avec toutes les colonnes disponibles. Le catalogue Produits précède la fiche complète ; Retour conserve le brouillon en mémoire et un enregistrement réussi referme la fiche. Employé et la création de commande fournisseur restent progressifs. L’inspecteur Stock s’ouvre à la sélection.

L’historique de module démarre replié sans colonne vide. Sur PC, son résumé compact, de 270 px maximum, partage la ligne utilitaire avec Outils lorsque l’en-tête du module le permet. Dashboard réunit historique, filtres et outils à partir de 1280 px, avec une réserve limitée à 35 % de la largeur disponible pour permettre le retour à la ligne au zoom. Dans Devis, à partir de 1180 px, l’historique fermé occupe l’extrémité droite réservée de la barre secondaire. Les historiques ouverts reprennent leur disposition normale ; ceux des dossiers sélectionnés gardent leur comportement existant.

Entre 390 et 760 px, Produits et Dashboard placent l’historique fermé et Outils sur la même rangée en réservant 140 px aux traductions longues d’Outils. Dans Dashboard, mois et profil partagent la rangée suivante, puis Personnaliser occupe toute la largeur. Les téléphones plus étroits et les historiques ouverts conservent le flux normal. Cette composition est CSS : aucun contrôle n’est cloné ni déplacé dans le DOM. L’historique central d’Agent Coco reste dans sa page ; droits, propositions et retours de focus sont conservés. Ces dispositions se chargent avec `order-followup.css`.

### Reuse

Les composants `ArcUI`, classes métier et primitives `cocoSurface`, `cocoSurface--inset` et `cocoSurface--raised` consomment les mêmes tokens. Utiliser une bordure fine sans ombre pour les cartes ; réserver la profondeur aux superpositions. Les anciens noms `arc-*` restent compatibles et ne décrivent pas nécessairement la couleur affichée. La [planche des composants](components.html) reste un outil de consultation des CSS compilés ; la [vérification du 30 octobre](verification-2026-10-30.md) décrit une révision historique.

La revue de finition historique du 4 novembre utilisait les captures PC/téléphone des surfaces Accueil, Produits, fiche produit, Dashboard et Devis, sous `.impeccable/review/`. Il s’agit de captures de fixtures pour l’assurance qualité. Aucun raster destiné au produit n’a été créé ni modifié par cette finition : logos, icônes et autres actifs approuvés sont préexistants. Leur provenance reste décrite dans [la charte commune](../design-system.md). Le budget CSS initial doit être remesuré après la refonte ; son plafond de 300 000 octets et le chargement différé restent contrôlés par les scripts du projet.

## Do's and Don'ts

### Do:

- **Do** reprendre les tokens et composants communs avant d’ajouter une règle locale.
- **Do** distinguer l’espace d’un formulaire de la densité d’une liste opérationnelle.
- **Do** conserver les pictogrammes Coco, les favoris et une action principale identifiable.
- **Do** laisser accessibles les colonnes, détails et formulaires complets à la demande.
- **Do** respecter les préférences existantes, les langues, les droits et les états réels.
- **Do** vérifier ensemble PC, téléphone, clavier et traductions longues.

### Don't:

- **Don't** remettre une seconde occurrence du titre de module dans le contenu.
- **Don't** déplacer ni cloner les contrôles métier pour composer une barre utilitaire.
- **Don't** empiler les ombres ni ajouter des halos ou textures décoratifs.
- **Don't** réintroduire des couleurs d’action locales ni des gradients sur les cartes.
- **Don't** forcer les lignes éditables ou les fenêtres en fiches sans préserver leurs contrôles.
- **Don't** transformer une valeur inconnue ou un échec de chargement en zéro ou succès.
- **Don't** appliquer ce contrat au site public ni modifier son autorité visuelle racine.
