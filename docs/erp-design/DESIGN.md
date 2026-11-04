---
name: "Coco ERP — GAMA"
description: "Gestion quotidienne lisible, surfaces neutres et accents pétrole/orange GAMA."
colors:
  petrol: "#2F7180"
  petrol-deep: "#245C69"
  brand-blue: "#157F98"
  action: "#AF5C35"
  action-hover: "#974B2A"
  brand-orange: "#F87826"
  ink: "#283B42"
  muted: "#5F7178"
  surface: "#FFFFFF"
  inset: "#EEF3F4"
  canvas: "#F5F7F8"
  line: "#E1E8EA"
  row-line: "#E8EEF0"
  input-line: "#819298"
  selected: "#E5F0F2"
  hover: "#F1F7F8"
  success: "#28704E"
  success-bg: "#EDF6F0"
  warning: "#865D19"
  warning-bg: "#FAF4E7"
  danger: "#AD403B"
  danger-bg: "#FBEEEC"
typography:
  headline:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: "44px"
    letterSpacing: "-0.025em"
  section:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
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
  mobile-panel: "12px"
  badge: "6px"
  navigation: "8px"
  dialog: "20px"
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

# Design System: Coco ERP — GAMA

## Overview

**Creative North Star: "Coco / GAMA — gestion sereine"**

Coco ERP privilégie un travail quotidien calme et lisible : choisir un module, repérer ou rechercher une information, puis agir dans les parcours existants. Une toile neutre, des surfaces blanches, des accents GAMA atténués et une hiérarchie compacte rendent les données utiles visibles plus tôt. Les formulaires séparent clairement libellés, valeurs et groupes de champs sans élargir les listes opérationnelles.

Ce contrat décrit l’application interne servie par `src/app/index.html`. Il réconcilie la finition professionnelle du 4 novembre 2026 demandée par le propriétaire avec la structure ERP existante ; les références Geex restent historiques. Les tokens viennent de `src/styles/tokens.css`, appliqués par `workbench.css`, `design.css`, les contrôles partagés et les feuilles différées. Les fonctions, identifiants, droits, langues FR/ES/EN, favoris, historiques et données métier sont conservés. Le site public possède son propre `DESIGN.md` à la racine.

**Key Characteristics:**

- Toile neutre, surfaces blanches et ombres peu profondes.
- Inter pour le travail courant, Poppins pour les titres.
- Libellés proches de leur champ et groupes de formulaire espacés.
- Orange cuivré pour la commande principale, pétrole pour les liens et sélections.
- Navigation et utilitaires compacts, structures métier conservées.

## Colors

### Primary

Le pétrole atténué porte les liens, le focus et les sélections ; sa nuance profonde renforce les libellés actifs. Le bleu de marque reste inchangé dans les actifs et pictogrammes approuvés. Les icônes latérales emploient le texte secondaire au repos et retrouvent les accents de marque sur la destination courante.

### Secondary

L’orange cuivré d’action utilise un fond uni et un texte blanc ; son survol est plus sombre. L’orange brut GAMA reste réservé aux actifs, pictogrammes et usages décoratifs existants. Les graphiques conservent leurs séries, libellés et valeurs réels.

### Neutral

La toile est un gris froid très clair, sans texture ni satin. Les panneaux sont blancs et opaques ; le fond en retrait distingue les zones secondaires et les en-têtes de tableaux partagés. Les séparateurs de surface sont discrets, les champs possèdent un contour distinct. Succès, avertissement et erreur conservent leurs libellés explicites.

Les couples mesurés dans la finition courante donnent 4,74:1 pour texte secondaire/toile, 4,77:1 pour blanc/action et 5,53:1 pour blanc/pétrole. Ces mesures portent sur ces couples, pas sur chaque état métier.

**The Action Rule.** Réserver l’orange d’action à la commande principale ; employer le pétrole pour les liens et les sélections.

## Typography

Inter locale est la police du texte de travail, des valeurs et des contrôles ; elle est préchargée par l’application. Poppins locale reste réservée aux titres du bandeau et du contenu. Les polices système servent de repli. Les licences locales restent dans `fonts/` ; aucune police distante n’est requise au rendu.

Le titre unique du bandeau utilise `title`, puis passe à 23 px sous 1180 px et à 18 px jusqu’à 760 px. Sa description traduite utilise 12 px et disparaît sur téléphone. `headline` et `section` décrivent les titres de contenu ; certains panneaux emploient le titre compact de 16 px. Les cellules PC utilisent généralement `table`, les libellés de formulaire `field-label` et les valeurs `field-value`, explicitement à 14 px sur PC. Champs et valeurs de fiches passent à `value-mobile` sur téléphone. Les montants emploient des chiffres tabulaires et s’alignent à droite.

L’accueil garde ses adaptations existantes : les libellés ont généralement 12 px sur grand PC et téléphone ; l’interligne devient 1,2 sur grand PC, et les largeurs intermédiaires conservent leurs ajustements de 13–14 px. Jusqu’à 359 px, `compact-home-label` conserve les noms complets dans trois colonnes.

**The Readability Rule.** Conserver les libellés complets, les traductions et le retour à la ligne sans comprimer la cible de commande.

## Layout

À partir de 1180 px, la barre latérale mesure 232 px, avec un retrait de 12 px sur trois côtés ; le contenu principal commence à 256 px. Le bandeau a une hauteur minimale de 88 px : retour et titre unique à gauche, recherche globale et utilitaires existants à droite. Le contenu reçoit 20 px en haut, 28 px sur les côtés et 32 px en bas, plus les zones de sécurité. La recherche globale mesure 44 px de haut.

Sous 1180 px, le menu devient un tiroir de largeur maximale 304 px, l’espace principal revient au bord de l’écran et le bandeau passe à 80 px minimum. Le contenu utilise 18 px en haut et 24 px sur les côtés. Jusqu’à 760 px, le bandeau passe à 72 px minimum, la recherche globale rejoint son accès mobile et la description est masquée. L’accueil téléphone conserve menu et compte sans logo CO dans le bandeau. Le contenu utilise 16 px en haut et 14 px sur les côtés, ramenés à 12 px jusqu’à 359 px, plus les zones de sécurité. La navigation basse Accueil / Recherche / Scanner / Plus reste disponible jusqu’à 860 px ; le contenu réserve sa place et les historiques ajoutent leur réserve de sécurité propre.

Ces minima ne bloquent pas une hauteur nécessaire au contenu. Les panneaux métier collants suivent la hauteur réellement peinte du bandeau, recalculée après redimensionnement, traduction et chargement des polices. Les onglets natifs restent dans le contenu de leur module, avec défilement horizontal lorsque nécessaire.

### Formulaires et listes

Le rythme partagé conserve un écart de 8 px entre libellé et champ. Les rangées de formulaire utilisent 24 px sur PC et 20 px sur téléphone ; les colonnes utilisent respectivement 24 et 16 px. Une section ou une rangée d’actions peut être séparée de 32 px. Les modules gardent leurs colonnes et leur ordre métier ; les champs s’empilent selon leur place disponible. Les panneaux génériques utilisent 24 px de marge intérieure sur PC et 16 px sur téléphone.

Les tableaux PC partagés utilisent 4 px verticalement et 16 px horizontalement dans les cellules. Le token de ligne vaut nominalement 52 px ; une ligne contenant une commande de 44 px mesure effectivement environ 53 px avec son séparateur. L’en-tête nominal de 44 px peut également grandir selon ses contrôles. Aucun de ces tokens ne fixe une hauteur exacte universelle : les tableaux spécialisés et les métriques Dashboard conservent leurs dimensions dictées par le contenu.

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

La profondeur repose d’abord sur l’espace et les fonds, puis sur des ombres peu profondes. Les contrôles et panneaux imbriqués n’empilent pas la profondeur. Les valeurs exactes des ombres et du mouvement figurent dans la sidecar.

| Rôle | Token runtime | Emploi |
| --- | --- | --- |
| En retrait | `--coco-inset` | Zones secondaires, sans ombre |
| Surface | `--arc-sh-1` / `--coco-surface-shadow` | Panneaux, KPI, fiches et tuiles |
| Élevé | `--arc-sh-2` | Survol interactif et menus |
| Superposition | `--arc-sh-3` / `--coco-dialog-shadow` | Fenêtres et tiroir ouvert |

La barre latérale PC et la commande principale sont plates. `--coco-surface-sheen` et `--coco-canvas-texture` valent `none`. Le voile des fenêtres reste sans flou permanent.

**The Surface Rule.** Un groupe de contenu porte une seule ombre ; ses tableaux et sous-panneaux restent plats.

Les retours de pression, d’état et de superposition durent 120, 180 et 240 ms, avec `cubic-bezier(.16,1,.3,1)`. Aucun chargement de page n’apparaît en cascade. La réduction du mouvement conserve les couleurs, focus, textes et états sans déplacement décoratif. Impression, contraste renforcé et couleurs forcées gardent leurs adaptations. Ce contrat décrit le thème clair livré ; un mode sombre complet n’est pas activé par cette finition.

## Shapes

Les commandes et champs partagés utilisent `control`, les fonds en retrait `inset`, les surfaces `panel`, et les fenêtres ainsi que le cadre latéral `dialog`. Jusqu’à 760 px, le rayon partagé des surfaces devient `mobile-panel`. Les onglets et liens latéraux utilisent `navigation`, les badges leur rayon compact. Avatars, repères GPS et autres formes métier gardent leur géométrie spécifique.

## Components

### Buttons

La commande principale est orange cuivré avec texte blanc ; les actions secondaires sont blanches et les commandes discrètes utilisent le pétrole. Les contrôles communs conservent une hauteur minimale de 44 px. Les barres métier spécialisées gardent leur densité propre. Le focus visible utilise un trait pétrole de 2 px décalé de 3 px. Les états indisponibles et occupés gardent leur sémantique et ne bougent pas à la pression.

### Inputs / Fields

Fond blanc, contour de saisie explicite, libellé persistant et rayon commun. Les champs standards conservent 44 px de hauteur minimale, des valeurs normales de 14 px sur PC et 16 px sur téléphone ; le libellé à 13 px et graisse 500 reste distinct de la valeur à graisse 400. Les erreurs restent près du champ ; les valeurs survivent à un échec et le premier champ invalide reçoit le focus. La recherche globale PC utilise une surface blanche compacte.

### Navigation

La navigation latérale conserve groupes, favoris et liens autorisés. La destination courante combine fond pétrole clair, libellé plus sombre et icône de marque. Le tiroir fermé est inerte ; ouvert, il retient le focus, rend l’arrière-plan inerte, se ferme avec Échap et rend le focus au déclencheur. Les onglets natifs restent dans leur module avec fond et contour pétrole pour la sélection. Les favoris de l’accueil et la navigation basse gardent leur accès et leur cible tactile.

### Lists / Cards / Status

Les tableaux ont des séparateurs horizontaux fins, sans quadrillage vertical ordinaire, des en-têtes en retrait et des montants alignés à droite. Les fiches mobiles affichent les noms des colonnes avec leurs valeurs. Les statuts portent leur texte et leur couleur sémantique. Tableaux spécialisés, arbres et graphiques conservent leurs contrôles métier.

CRM et Projets placent leurs tâches blanches sur des colonnes sans surface de fond. Documents et Knowledge séparent un rail blanc de 230 px et une surface principale blanche par 30 px ; les deux zones s’empilent jusqu’à 760 px. Ces finitions sont chargées avec leurs modules.

### Progressive Editors / History

Produits et Contacts gardent six champs métier par défaut avec toutes les colonnes disponibles. Le catalogue Produits précède la fiche complète ; Retour conserve le brouillon en mémoire et un enregistrement réussi referme la fiche. Employé et la création de commande fournisseur restent progressifs. L’inspecteur Stock s’ouvre à la sélection.

L’historique de module démarre replié sans colonne vide. Sur PC, son résumé compact, de 270 px maximum, partage la ligne utilitaire avec Outils lorsque l’en-tête du module le permet. Dashboard réunit historique, filtres et outils à partir de 1280 px, avec une réserve limitée à 35 % de la largeur disponible pour permettre le retour à la ligne au zoom. Dans Devis, à partir de 1180 px, l’historique fermé occupe l’extrémité droite réservée de la barre secondaire. Les historiques ouverts reprennent leur disposition normale ; ceux des dossiers sélectionnés gardent leur comportement existant.

Entre 390 et 760 px, Produits et Dashboard placent l’historique fermé et Outils sur la même rangée en réservant 140 px aux traductions longues d’Outils. Dans Dashboard, mois et profil partagent la rangée suivante, puis Personnaliser occupe toute la largeur. Les téléphones plus étroits et les historiques ouverts conservent le flux normal. Cette composition est CSS : aucun contrôle n’est cloné ni déplacé dans le DOM. L’historique central d’Agent Coco reste dans sa page ; droits, propositions et retours de focus sont conservés. Ces dispositions se chargent avec `order-followup.css`.

### Reuse

Les composants `ArcUI`, classes métier et primitives `cocoSurface`, `cocoSurface--inset` et `cocoSurface--raised` consomment les mêmes tokens. Utiliser une seule variante de profondeur par groupe. Les anciens noms `arc-*` restent compatibles et ne décrivent pas nécessairement la couleur affichée. La [planche des composants](components.html) reste un outil de consultation des CSS compilés ; la [vérification du 30 octobre](verification-2026-10-30.md) décrit une révision historique.

La revue de finition du 4 novembre utilise les captures finales PC/téléphone des surfaces Accueil, Produits, fiche produit, Dashboard et Devis, sous `.impeccable/review/`. Il s’agit de captures de fixtures pour l’assurance qualité. Aucun raster destiné au produit n’a été créé ni modifié par cette finition : logos, icônes et autres actifs approuvés sont préexistants. Leur provenance reste décrite dans [la charte commune](../design-system.md). Le budget CSS initial mesuré reste de 298 874 octets sur un plafond de 300 000 ; la composition d’historique reste différée.

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
- **Don't** utiliser l’orange brut du logo pour une action à texte blanc.
- **Don't** forcer les lignes éditables ou les fenêtres en fiches sans préserver leurs contrôles.
- **Don't** transformer une valeur inconnue ou un échec de chargement en zéro ou succès.
- **Don't** appliquer ce contrat au site public ni modifier son autorité visuelle racine.
