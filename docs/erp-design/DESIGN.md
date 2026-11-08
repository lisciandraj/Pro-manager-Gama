---
name: "Coco ERP — espace CRM clair"
description: "Gestion quotidienne compacte, navigation blanche, actions charbon et créations vertes."
colors:
  petrol: "#263238"
  petrol-deep: "#1C252A"
  brand-blue: "#263238"
  action: "#263238"
  action-hover: "#1C252A"
  brand-orange: "#2F6F42"
  creation: "#2F6F42"
  creation-hover: "#265A36"
  creation-tint: "#E8F2EA"
  ink: "#263238"
  muted: "#5F6B72"
  surface: "#FFFFFF"
  sidebar: "#FFFFFF"
  inset: "#F7F8F9"
  canvas: "#F4F5F7"
  line: "#E2E6E9"
  row-line: "#E2E6E9"
  input-line: "#8A9499"
  selected: "#EEF0F2"
  hover: "#F2F7F3"
  phase-blue: "#A9BFF1"
  phase-orange: "#F7D7A4"
  phase-green: "#BAD8BF"
  phase-red: "#F2BABB"
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
    fontSize: "20px"
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
  control: "6px"
  inset: "8px"
  panel: "8px"
  mobile-panel: "12px"
  badge: "6px"
  navigation: "8px"
  dialog: "8px"
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
  button-create:
    backgroundColor: "{colors.creation}"
    textColor: "{colors.surface}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "10px 16px"
  button-create-hover:
    backgroundColor: "{colors.creation-hover}"
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
    padding: "20px"
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
  sidebar-link-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
  sidebar-link:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "10px 12px"
    height: "44px"
---

# Design System: Coco ERP — espace CRM clair

## Overview

**Creative North Star: "Coco — un bureau de gestion clair"**

Coco ERP privilégie un travail quotidien calme et lisible : choisir un module, repérer ou rechercher une information, puis agir dans les parcours existants. Une toile gris clair, une navigation blanche, des actions charbon et une création verte rendent les données utiles visibles plus tôt. La hiérarchie reprend la sobriété et la densité des références Nozti CRM fournies, en conservant l’identité Coco et les vrais contenus métier. Les formulaires séparent clairement libellés, valeurs et groupes de champs sans élargir les listes opérationnelles.

Ce contrat décrit l’application interne servie par `src/app/index.html`. Il applique la nouvelle direction issue des références Nozti CRM à l’application réelle GitHub Pages ; elle remplace la charte violette du 7 novembre 2026. L’aperçu privé Sites reste distinct. Les références inspirent les rôles visuels et la structure, sans reprendre leurs marques, logos, textes ni données. Les révisions GAMA, Geex et violette restent historiques pour la finition visuelle. Les tokens viennent de `src/styles/tokens.css`, appliqués par `workbench.css`, `design.css`, les contrôles partagés et les feuilles différées. Les fonctions, identifiants, droits, langues FR/ES/EN, favoris, historiques et données métier sont conservés. Le site public possède son propre `DESIGN.md` à la racine.

**Key Characteristics:**

- Toile gris clair, navigation blanche et panneaux blancs à contour fin sans ombre.
- Inter pour les titres, les valeurs et les contrôles.
- Libellés proches de leur champ et groupes de formulaire espacés.
- Actions charbon, créations vertes et destination active sur gris clair.
- Tableaux jointifs à grille fine, Kanban blanc à bandeaux pastel et structures métier conservées.

## Colors

### Primary

Les actions normales utilisent `action` charbon et leur survol `action-hover`. La création emploie `creation` vert, `creation-hover` au survol et `creation-tint` pour un fond discret. Le blanc reste le texte des boutons pleins. La destination latérale active combine `selected` gris clair avec texte et icône charbon ; elle ne devient pas un bouton plein. Les noms historiques `petrol`, `brand-blue` et `brand-orange` restent des alias compatibles, sans imposer leurs anciennes teintes.

### Reporting and semantic states

Les graphiques et KPI conservent leurs séries, légendes, calculs et valeurs réels ; aucune donnée de la référence n’est reproduite. Les bandes de phase Kanban utilisent `phase-blue`, `phase-orange`, `phase-green` et `phase-red`, avec texte charbon. Elles identifient les étapes existantes ; elles ne remplacent ni les libellés, ni les états métier. Les statuts succès, attention et erreur gardent strictement leurs couleurs et fonds antérieurs.

### Neutral

La toile et les retraits sont gris clair, la navigation et les panneaux blancs. Les bordures de surface et la grille des tableaux utilisent `line` ; les champs utilisent `input-line`, plus contrasté. Les panneaux restent sans ombre ni gradient ; la profondeur est réservée aux superpositions.

| Paire calculée (sRGB WCAG) | Rapport |
| --- | --- |
| Texte charbon / blanc | 13,16:1 |
| Texte secondaire / blanc, puis toile | 5,48:1 / 5,02:1 |
| Texte charbon / destination active grise | 11,52:1 |
| Blanc / action charbon, puis survol | 13,16:1 / 15,59:1 |
| Blanc / création verte, puis survol | 6,05:1 / 8,08:1 |
| Vert de création / teinte verte | 5,27:1 |
| Contour de champ / blanc | 3,10:1 |
| Succès, attention, erreur / leurs fonds | 4,93:1 / 4,74:1 / 4,93:1 |
| Texte charbon / bandes bleu, orange, vert, rouge | 7,15:1 / 9,53:1 / 8,56:1 / 7,84:1 |

Ces calculs de tokens satisfont 4,5:1 pour les textes cités et 3:1 pour le contour des champs. Les bordures légères de surface sont décoratives ; elles ne sont pas le seul repère d’un contrôle. Ce tableau ne certifie pas les styles calculés de chaque état métier ni leur rendu dans un navigateur.

**The Action Rule.** Distinguer l’action normale charbon de la création verte ; garder la destination courante sur une surface grise avec texte charbon.

## Typography

Inter locale est la police des titres, du texte de travail, des valeurs et des contrôles ; elle est préchargée par l’application. Les polices système servent de repli. Les licences locales restent dans `fonts/` ; aucune police distante n’est requise au rendu.

Le titre contextuel unique du bandeau (`title`, `.cocoModuleContext`) mesure 20 px à partir de 1180 px et jusqu’à 760 px ; la plage intermédiaire de 761 à 1179 px conserve 23 px. Son interligne et sa cible sont de 44 px. Le sous-titre est masqué à toutes les largeurs. Les titres `h2` de contenu utilisent `headline` à 24 px sur PC et 23 px sur téléphone : ce rôle est distinct du titre contextuel du bandeau, sans dupliquer le nom du module. `section` décrit les titres de section de 17 px ; les titres directs des panneaux standard utilisent 16 px. Les cellules PC utilisent généralement `table`, les libellés de formulaire `field-label` et les valeurs `field-value`, explicitement à 14 px sur PC. Champs et valeurs de fiches passent à `value-mobile` sur téléphone. Les montants emploient des chiffres tabulaires et s’alignent à droite.

L’accueil garde ses adaptations existantes : les libellés ont généralement 12 px sur grand PC et téléphone ; l’interligne devient 1,2 sur grand PC, et les largeurs intermédiaires conservent leurs ajustements de 13–14 px. Jusqu’à 359 px, `compact-home-label` conserve les noms complets dans trois colonnes.

**The Readability Rule.** Conserver les libellés complets, les traductions et le retour à la ligne sans comprimer la cible de commande.

## Layout

À partir de 1180 px, la barre latérale droite mesure 256 px, sans retrait ni arrondi ; le contenu principal commence à 256 px. Le bandeau blanc a une hauteur minimale de 64 px : retour et titre unique à gauche, recherche globale et utilitaires existants à droite. Le contenu reçoit 20 px en haut, 20 px sur les côtés et 32 px en bas, plus les zones de sécurité. La recherche globale mesure 40 px de haut sur PC.

Sous 1180 px, le menu devient un tiroir de largeur maximale 304 px, l’espace principal revient au bord de l’écran et le bandeau conserve un minimum de 64 px. Le contenu utilise 18 px en haut et 24 px sur les côtés. Jusqu’à 760 px, le bandeau conserve son minimum de 64 px, la recherche globale rejoint son accès mobile ; le sous-titre reste masqué, comme sur PC. L’accueil téléphone conserve menu et compte sans logo CO dans le bandeau. Le contenu utilise 16 px en haut et 14 px sur les côtés, ramenés à 12 px jusqu’à 359 px, plus les zones de sécurité. La navigation basse Accueil / Recherche / Scanner / Plus reste disponible jusqu’à 860 px ; le contenu réserve sa place et les historiques ajoutent leur réserve de sécurité propre.

Ces minima ne bloquent pas une hauteur nécessaire au contenu. Au zoom 200 %, le contenu revient à la ligne et le menu utilise le tiroir lorsque la largeur CSS passe sous 1180 px ; aucun élément métier ne doit être masqué ni recouvrir les commandes. Les panneaux métier collants suivent la hauteur réellement peinte du bandeau, recalculée après redimensionnement, traduction et chargement des polices. Les onglets natifs restent dans le contenu de leur module, avec défilement horizontal lorsque nécessaire.

### Formulaires et listes

Le rythme partagé conserve un écart de 8 px entre libellé et champ. Les rangées de formulaire utilisent 20 px sur PC et téléphone ; les colonnes utilisent 20 px sur PC et 16 px sur téléphone. Les panneaux et leur grille utilisent un écart de 20 px sur PC, 16 px sur téléphone ; le token de séparation de section est de 24 px. Les modules gardent leurs colonnes et leur ordre métier ; les champs s’empilent selon leur place disponible. Les panneaux génériques utilisent 20 px de marge intérieure sur PC et 16 px sur téléphone.

Les listes de travail PC utilisent une grille jointive de 1 px, des cellules de 13 px et une hauteur nominale de ligne de 52 px, sans intervalle entre les lignes. Les cellules partagées utilisent 10 px verticalement et 14 px horizontalement de marge intérieure ; la piste d’audit réduit horizontalement à 10 px. Les en-têtes ont une hauteur nominale de 42 px et un texte de 12 px. Ces dimensions sont des minima : une ligne avec des boutons de 44 px peut grandir pour accueillir ses marges et sa bordure. Les actions de 44 px restent accessibles ; les lignes grandissent selon leur contenu. Les documents papier sont exclus de cette finition. Aucun de ces tokens ne fixe une hauteur exacte universelle : les tableaux spécialisés et les métriques Dashboard conservent leurs dimensions dictées par le contenu.

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

Les commandes et champs partagés utilisent `control`, les fonds en retrait `inset`, les surfaces `panel`, et les fenêtres `dialog`. Les surfaces de travail utilisent 8 px sur PC et 12 px sur téléphone ; les fenêtres conservent 8 px. Les boutons et champs génériques utilisent 6 px. Les onglets de module, les liens latéraux et la recherche globale gardent un rayon explicite de 8 px ; la barre latérale droite n’a pas d’arrondi. Les badges conservent leur rayon compact de 6 px. Avatars, repères GPS et autres formes métier gardent leur géométrie spécifique.

## Components

### Buttons

L’action normale est charbon unie avec texte blanc ; la création est verte avec texte blanc. Les actions secondaires sont blanches et les commandes discrètes utilisent le charbon. Les contrôles communs conservent une hauteur minimale de 44 px. Les barres métier spécialisées gardent leur densité propre. Le focus visible dans le contenu et les fenêtres utilise un trait vert de 2 px (`--arc-accent-600`, #2F6F42) décalé de 3 px. Les onglets conservent leur décalage intérieur de −3 px ; les menus compacts peuvent utiliser −2 px. Les contrôles généraux hors de ces conteneurs utilisent le vert plus sombre `--arc-accent-700` (#265A36). Les états indisponibles et occupés gardent leur sémantique et ne bougent pas à la pression.

### Inputs / Fields

Fond blanc, contour de saisie explicite, libellé persistant et rayon commun. Les champs standards conservent 44 px de hauteur minimale, des valeurs normales de 14 px sur PC et 16 px sur téléphone ; le libellé à 13 px et graisse 500 reste distinct de la valeur à graisse 400. Les erreurs restent près du champ ; les valeurs survivent à un échec et le premier champ invalide reçoit le focus. La recherche globale PC utilise une surface blanche compacte, une hauteur de 40 px et un rayon de 8 px.

### Navigation

La navigation latérale conserve groupes, favoris et liens autorisés. La destination courante combine fond gris clair et libellé/icône charbon sur une navigation blanche. Le tiroir fermé est inerte ; ouvert, il retient le focus, rend l’arrière-plan inerte, se ferme avec Échap et rend le focus au déclencheur. Les onglets natifs restent dans leur module avec fond gris clair et libellé charbon pour la sélection. Les favoris de l’accueil et la navigation basse gardent leur accès et leur cible tactile.

### Lists / Cards / Status

Les listes de travail utilisent des lignes blanches jointives, une grille fine de 1 px, des en-têtes discrets, une hauteur nominale de 52 px et des montants alignés à droite. Les exports papier et grilles spécialisées gardent leurs contrôles. Les fiches mobiles affichent les noms des colonnes avec leurs valeurs. Les statuts portent leur texte et leur couleur sémantique. Tableaux spécialisés, arbres et graphiques conservent leurs contrôles métier.

CRM et Projets placent leurs tâches sur des panneaux blancs bordés, coiffés d’une bande de phase pastel bleue, orange, verte ou rouge avec texte charbon. Les libellés, compteurs et états de glisser-déposer existants restent visibles. Documents et Knowledge séparent un rail blanc de 230 px et une surface principale blanche par 30 px ; les deux zones s’empilent jusqu’à 760 px. Ces finitions sont chargées avec leurs modules.

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
- **Don't** copier les données, textes, marques ou logos de Nozti CRM.
- **Don't** appliquer ce contrat au site public ni modifier son autorité visuelle racine.
