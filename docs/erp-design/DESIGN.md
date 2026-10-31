---
name: Coco ERP — Geex / GAMA
description: Espace de gestion inspiré des captures Geex approuvées, avec identité pétrole et orange GAMA.
colors:
  petrol: "#10677D"
  petrol-deep: "#0C556B"
  brand-blue: "#157F98"
  action: "#B54708"
  action-top: "#BD4E09"
  action-hover: "#A83F07"
  brand-orange: "#F87826"
  ink: "#29283D"
  muted: "#686779"
  surface: "#FFFFFF"
  inset: "#F0EFF5"
  canvas: "#F4F3F8"
  line: "#E9E7F0"
  row-line: "#ECEAF2"
  input-line: "#7B8797"
  selected: "#E7F3F6"
  hover: "#F3F9FA"
  success: "#0D7446"
  success-bg: "#E4F5EC"
  warning: "#9A5B00"
  warning-bg: "#FDF1DF"
  danger: "#B3261E"
  danger-bg: "#FCE9E7"
typography:
  headline:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "26px"
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
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.55
  table:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.55
  value-mobile:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
  button:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.55
  home-label:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.35
  compact-home-label:
    fontFamily: "Poppins, Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.25
rounded:
  control: "12px"
  inset: "16px"
  panel: "22px"
  mobile-panel: "14px"
  badge: "9px"
  navigation: "14px"
  dialog: "28px"
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
    typography: "{typography.body}"
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
    typography: "{typography.label}"
    rounded: "{rounded.badge}"
    padding: "5px 10px"
  module-tab:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "11px 18px"
  module-tab-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.petrol-deep}"
  sidebar-link:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "12px 16px"
---

# Design System: Coco ERP — Geex / GAMA

## Overview

**Creative North Star: "Geex / GAMA"**

L’autorité visuelle est la direction demandée par le propriétaire le 30 octobre 2026 : reconstruire l’apparence des captures Geex fournies avec l’orange et le bleu pétrole GAMA. Elle remplace la précédente finition Coco Premium. La composition associe une navigation latérale flottante, un en-tête ample, une toile lavande très claire et des panneaux blancs aux angles doux. Les captures constituent la référence ; aucun fichier Figma ni code source Geex n’a été importé.

Ce contrat concerne les modules internes servis par `src/app/index.html`. Les tokens proviennent de `src/styles/tokens.css`, puis des dispositions `workbench.css`, de la finition `design.css` et des feuilles différées. Les fonctions, droits, langues, favoris, historiques et données métier restent ceux de Coco. Le site public possède un `DESIGN.md` distinct à la racine du dépôt.

**Key Characteristics:**

- Navigation latérale flottante sur PC, tiroir accessible sur tablette.
- Toile lavande claire, surfaces blanches et ombres discrètes.
- Poppins locale, titre unique et description traduite du module.
- Orange pour la commande principale, pétrole pour les liens et sélections.
- Contrôles et structures métier conservés dans leur module.

## Colors

### Primary

Le bleu de marque garde l’identité GAMA dans les actifs et pictogrammes. Le pétrole accessible porte les liens, le focus et les sélections ; sa nuance profonde accompagne les libellés actifs. Les icônes latérales sont grises au repos et retrouvent les accents de marque sur la destination courante.

### Secondary

L’orange de marque reste celui des dessins, indicateurs et graphiques. La commande principale conserve un dégradé d’orange plus sombre avec texte blanc ; sa variante de survol reste contrastée. Les séries de graphique gardent leurs libellés et valeurs.

### Neutral

La toile lavande claire est un aplat sans texture ni satin. Les panneaux sont blancs et opaques ; le fond en retrait distingue les contrôles secondaires. L’encre et le texte secondaire suivent les tokens normatifs. Les séparateurs de surface restent discrets ; les champs utilisent leur contour de saisie distinct. Chaque statut conserve un libellé explicite.

**The Action Rule.** Réserver l’orange d’action à la commande principale ; employer le pétrole pour les liens et les sélections.

## Typography

Poppins est livrée localement en régulier, moyen et semi-gras ; Inter locale et les polices système servent de repli. Les trois fichiers WOFF2 représentent 28 768 octets et sont accompagnés de `fonts/Poppins-OFL.txt` (SIL OFL 1.1, auteurs Poppins/itfoundry, distribution Google Fonts). Aucune police distante n’est requise au rendu.

Le titre du bandeau suit le rôle `title`, puis passe à 23 px sous 1180 px et à 18 px jusqu’à 760 px. Sa description utilise 12 px et disparaît sur téléphone. Les titres de contenu restent distincts des titres de section ; le nom du module ne se répète pas dans un second en-tête. Les cellules PC utilisent généralement le rôle `table`, les valeurs de fiche et les champs mobiles le rôle `value-mobile`. Les montants utilisent des chiffres tabulaires et s’alignent à droite. Les libellés d’accueil sur PC et téléphone ont le rôle `home-label` ; jusqu’à 359 px, ils utilisent `compact-home-label`. Les adaptations intermédiaires restent dans `workbench.css`.

**The Readability Rule.** Conserver les libellés complets, les traductions et le retour à la ligne sans comprimer la cible de commande.

## Layout

À partir de 1180 px, la barre latérale mesure 244 px, avec un retrait de 16 px sur trois côtés ; le contenu principal commence à 276 px. L’en-tête a une hauteur minimale de 112 px : titre et description à gauche, recherche globale complète, notifications, configuration et compte à droite. Le contenu dispose de 18 px en haut, 36 px à gauche et 42 px à droite, en plus des zones de sécurité applicables. Les onglets natifs restent dans le contenu du module à toutes les tailles ; ils défilent horizontalement si nécessaire.

Les minima d’en-tête sont définis sans surcharge de hauteur sur le cadre interne. Les panneaux métier collants suivent la hauteur réellement peinte du bandeau, recalculée après redimensionnement, traduction et chargement des polices. Les retraits horizontaux du bandeau ajoutent les zones de sécurité : 36/42 px sur PC, 24/24 px sur tablette et 10/10 px sur téléphone.

Sous 1180 px, la navigation devient un tiroir de largeur maximale 304 px, l’espace principal revient au bord de l’écran et l’en-tête passe à 96 px minimum. Jusqu’à 760 px, l’en-tête passe à 72 px minimum, la recherche globale rejoint son accès mobile et la description est masquée. Sur l’accueil téléphone, le bandeau affiche le bouton du menu à gauche et les commandes de compte à droite, sans logo CO. Le contenu utilise 16 px en haut et 14 px sur les côtés, ramenés à 12 px plus les zones de sécurité jusqu’à 359 px. La navigation basse Accueil / Recherche / Scanner / Plus reste disponible jusqu’à 860 px ; le contenu réserve 96 px plus la zone de sécurité en bas.

L’accueil conserve des tuiles carrées dont la hauteur suit leur largeur. Des rangées Flexbox avec un espace carré dans le flux évitent les calculs cycliques de hauteur de WebKit ; les écrans courts défilent.

| Largeur de la fenêtre | Colonnes d’accueil | Espacement |
| --- | --- | --- |
| Jusqu’à 359 px | 3 | 6 px |
| 360–760 px | 3 | 8 px |
| 761–860 px | 4 | 10 px |
| 861–1179 px | 5 | 12 px |
| 1180–1439 px | 7 | 18 px |
| À partir de 1440 px | 9 | 16 px |

Jusqu’à 359 px, les tuiles conservent trois colonnes avec une marge intérieure de 6 px verticalement et 2 px horizontalement, un intervalle de 6 px entre icône et libellé, des icônes de 28 px et le rôle `compact-home-label`. Les titres complets restent à l’intérieur de leur carré.

Entre 861 et 1179 px avec une hauteur au plus 700 px, la règle d’écran court utilise six colonnes. Les règles PC suivantes conservent sept ou neuf colonnes. Les favoris, l’ordre personnel et les modules autorisés restent attachés au compte.

Dans Ventes sur PC, le menu Outils partage la rangée des onglets. Les tableaux PC gardent leurs outils de recherche, colonnes et choix Tuiles / Tableau. Les préférences enregistrées sont prioritaires. Jusqu’à 760 px, les listes en lecture seule sans préférence s’ouvrent en fiches ; les grilles éditables, fenêtres et tableaux exclus conservent leur structure et leur défilement local. Les conteneurs peuvent rétrécir sans élargir toute la page.

## Elevation & Depth

La séparation repose d’abord sur l’espace entre surfaces. Les ombres sont légères, sans reflet satiné ; les contrôles et panneaux imbriqués n’empilent pas la profondeur.

| Rôle | Token runtime | Emploi |
| --- | --- | --- |
| En retrait | `--coco-inset` | Zones secondaires, sans ombre |
| Surface | `--arc-sh-1` / `--coco-surface-shadow` | Panneaux, KPI, fiches et tuiles |
| Élevé | `--arc-sh-2` | Survol interactif et menus |
| Superposition | `--arc-sh-3` / `--coco-dialog-shadow` | Fenêtres et tiroir ouvert |

Les valeurs exactes des ombres et du mouvement figurent dans la sidecar. `--coco-surface-sheen` et `--coco-canvas-texture` valent `none`. La barre latérale PC n’a pas d’ombre ; son léger dégradé blanc est composé sur un fond blanc opaque et conserve sa séparation de la toile. Le voile des fenêtres reste sans flou permanent.

**The Surface Rule.** Un groupe de contenu porte une seule ombre ; ses tableaux et sous-panneaux restent plats.

Les retours de pression, d’état et de superposition durent respectivement 120, 180 et 240 ms, avec `cubic-bezier(.16,1,.3,1)`. Aucun chargement de page n’apparaît en cascade. La réduction du mouvement conserve les couleurs, focus, textes et états sans déplacement décoratif. L’impression, le contraste renforcé et les couleurs forcées conservent leurs adaptations.

## Shapes

Les contrôles partagés emploient le rayon `control`, les surfaces le rayon `panel`, et les fenêtres ainsi que le cadre latéral le rayon `dialog`. Jusqu’à 760 px, le rayon partagé des surfaces devient `mobile-panel`. Les onglets ont leur rayon `navigation` et les badges leur rayon compact. Les avatars, repères GPS et autres formes métier gardent leur géométrie spécifique.

## Components

### Buttons

La commande principale est orange avec texte blanc ; les actions secondaires sont blanches et les commandes discrètes utilisent le pétrole. Les contrôles communs conservent une hauteur minimale de 44 px. Le focus visible utilise un trait pétrole de 2 px décalé de 3 px. Les états indisponibles et occupés gardent leur sémantique et ne bougent pas à la pression.

### Inputs / Fields

Fond blanc, contour de saisie explicite, libellé persistant et rayon commun. Les champs standards conservent 44 px de hauteur minimale et 16 px de texte sur téléphone. Les erreurs restent près du champ ; les valeurs survivent à un échec et le premier champ invalide reçoit le focus. La recherche globale PC est une zone de 58 px sur fond lavande en retrait, avec un focus explicite.

### Navigation

La navigation latérale PC conserve groupes, favoris et liens autorisés. La destination courante combine fond pétrole clair, libellé plus sombre et icône de marque. Le tiroir tablette/téléphone est inerte lorsqu’il est fermé ; ouvert, il retient le focus, rend l’arrière-plan inerte, se ferme avec Échap et rend le focus au déclencheur. Les onglets natifs du module restent des commandes arrondies dans le contenu, avec fond et contour pétrole pour la sélection ; ils ne sont ni épinglés dans le bandeau ni clonés.

### Lists / Cards / Status

Les tableaux utilisent des séparateurs horizontaux fins, sans quadrillage vertical ordinaire, des en-têtes blancs et des montants alignés à droite. Les fiches mobiles affichent les noms de colonnes avec leurs valeurs. Les statuts portent leur texte et leur couleur sémantique. Les tableaux spécialisés, arbres et graphiques conservent leurs contrôles métier.

CRM et Projets placent les tâches blanches individuelles sur des colonnes sans surface de fond. Documents et Knowledge séparent un rail blanc de 230 px et une surface principale blanche par un intervalle de 30 px ; les deux zones s’empilent jusqu’à 760 px. Ces finitions sont chargées avec leurs modules.

### Progressive Editors / History

Produits et Contacts gardent six champs métier par défaut avec toutes les colonnes disponibles. Le catalogue Produits précède la fiche complète ; Retour conserve le brouillon en mémoire et un enregistrement réussi referme la fiche. Employé et la création de commande fournisseur restent progressifs. L’inspecteur Stock s’ouvre à la sélection.

L’historique de module démarre replié dans le flux, au-dessus du travail : résumé compact de 270 px maximum sur PC et pleine largeur sur téléphone, sans colonne vide. Les dossiers sélectionnés gardent leur historique ouvert sur PC ; l’historique central d’Agent Coco reste dans sa page. Les droits, propositions et retours de focus sont conservés.

### Reuse

Les composants `ArcUI`, les classes métier et les primitives `cocoSurface`, `cocoSurface--inset` et `cocoSurface--raised` consomment les mêmes tokens. Utiliser une seule variante de profondeur par groupe. Les anciens noms `arc-*` restent compatibles. La [planche des composants](components.html) réutilise les CSS compilés ; la [vérification du 30 octobre](verification-2026-10-30.md) décrit la couverture et ses limites.

## Do's and Don'ts

### Do:

- **Do** reprendre les tokens et composants communs avant d’ajouter une règle locale.
- **Do** conserver les pictogrammes Coco et une seule action principale identifiable.
- **Do** laisser accessibles les colonnes, détails et formulaires complets à la demande.
- **Do** respecter les préférences existantes, les langues, les droits et les états réels.
- **Do** vérifier ensemble les formats PC et téléphone, le focus et les textes longs.

### Don't:

- **Don't** rétablir le bandeau d’onglets épinglés, le satin ou la texture de toile de la révision précédente.
- **Don't** empiler les ombres ni ajouter des halos décoratifs.
- **Don't** présenter l’orange de marque comme la couleur du texte blanc des actions principales.
- **Don't** forcer les lignes éditables ou les fenêtres en fiches sans préserver leurs contrôles.
- **Don't** transformer une valeur inconnue ou un échec de chargement en zéro ou succès.
- **Don't** appliquer ce contrat au site public ni modifier son autorité visuelle racine.
