---
name: Coco ERP — Coco Premium
description: Interface de gestion SaaS premium, satinée, lisible et progressive pour les modules internes de Coco ERP.
colors:
  petrol: "#10677d"
  petrol-deep: "#0c556b"
  brand-blue: "#157f98"
  action: "#b54708"
  action-top: "#bd4e09"
  action-hover: "#a83f07"
  brand-orange: "#f87826"
  ink: "#17243b"
  muted: "#5d6980"
  surface: "#ffffff"
  inset: "#edf2f4"
  canvas: "#f3f5f7"
  line: "#dfe6eb"
  input-line: "#7b8797"
  selected: "#e7f3f6"
  hover: "#f3f9fa"
  success: "#0d7446"
  success-bg: "#e4f5ec"
  warning: "#9a5b00"
  warning-bg: "#fdf1df"
  danger: "#b3261e"
  danger-bg: "#fce9e7"
typography:
  headline:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.3
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
  value-mobile:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  button:
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.55
rounded:
  control: "10px"
  panel: "16px"
  badge: "5px"
  dialog: "24px"
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
  status-success:
    backgroundColor: "{colors.success-bg}"
    textColor: "{colors.success}"
    typography: "{typography.label}"
    rounded: "{rounded.badge}"
    padding: "3px 8px"
  module-tab:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    padding: "10px 2px"
  module-tab-selected:
    backgroundColor: "transparent"
    textColor: "{colors.petrol}"
---

# Design System: Coco ERP — Coco Premium

## Overview

**Creative North Star: "Coco Premium"**

Une interface SaaS premium inspirée des cinq références Geex fournies le 29 octobre 2026 : toile porcelaine, panneaux blancs satinés, profondeur multicouche et formes adoucies. Le bandeau horizontal, les pictogrammes bicolores, les favoris pétrole et les détails progressifs conservent les repères opérationnels Coco. Les palettes violettes, les marques et les données des références ne sont pas reprises.

Ce contrat concerne les modules internes servis par `src/app/index.html`. Les sources d’exécution sont `src/styles/tokens.css`, `src/styles/design.css`, les composants communs et les styles différés des modules. Les valeurs ci-dessus décrivent cette implémentation ; les mises en page spécialisées gardent leurs besoins métier. Le site public possède son propre `DESIGN.md` à la racine du dépôt.

**Key Characteristics:**

- Une action principale identifiable, des détails ouverts à la demande.
- Une toile légèrement teintée, des surfaces satinées et des ombres douces à trois niveaux.
- Une navigation stable, des listes compactes sur PC et des fiches lisibles sur téléphone.
- Des données réelles, des états explicites et les droits métier existants.

## Colors

### Primary

Le pétrole porte les liens, les onglets actifs, les sélections et le focus. Le bleu de marque est conservé dans les dessins et actifs Coco. Le ton pétrole profond accompagne les états où le composant requiert davantage de contraste.

### Secondary

L’orange d’action reçoit du texte blanc sur un dégradé #BD4E09 → #B54708. Son survol #A83F07 est plus sombre ; le contraste est vérifié aux deux extrémités. L’orange de marque reste distinct, dans les pictogrammes et illustrations ; les graphiques conservent leurs séries et leurs libellés.

### Neutral

La toile porcelaine porte un dégradé très léger et un pointillé statique discret ; les surfaces de travail restent blanches et opaques. Le fond en retrait distingue les en-têtes de tableau, champs en lecture seule et zones secondaires. L’encre, le texte secondaire, les séparateurs et le contour de saisie ont chacun leur rôle ; un séparateur de panneau ne remplace pas le contour d’un champ.

Les statuts succès, avertissement et erreur conservent les couleurs sémantiques réellement utilisées par les composants. Chaque statut porte un libellé ; une valeur inconnue reste indiquée comme telle.

**The Action Rule.** Réserver l’orange d’action à la commande principale ; employer le pétrole pour les liens et les sélections.

## Typography

Inter variable est livrée localement et précède les polices système dans la pile. Les poids courants sont régulier, moyen et semi-gras. Le titre du bandeau et les titres de contenu ont des rôles distincts ; le nom du module n’est pas répété dans un second en-tête.

Les rôles du frontmatter sont ceux de la charte commune. Le bandeau utilise le titre sur grand écran, réduit à 18 px sous 1180 px ; le titre de contenu passe à 23 px sur téléphone. Les libellés secondaires restent plus petits que les valeurs. Les principales valeurs des fiches mobiles et les champs de saisie utilisent le rôle mobile. Les montants s’alignent à droite et utilisent des chiffres tabulaires. Les textes d’aide et états spécialisés conservent leurs tailles propres.

## Layout

La barre supérieure mesure 64 px sur PC et 60 px jusqu’à 760 px. Le contenu dispose de 28 px en haut et 32 px sur les côtés sur grand écran ; sous 1180 px, ses marges sont de 24 px en haut et 20 px sur les côtés, plus les zones de sécurité. Les onglets principaux rejoignent le bandeau à partir de 1180 px et défilent dans le module sur les formats plus étroits. Le lanceur remplace la navigation latérale permanente.

L’accueil garde des tuiles carrées sans contour avec une ombre douce, neuf colonnes à partir de 1180 px et trois sur téléphone jusqu’à 760 px. Les tailles intermédiaires suivent la place disponible. Les favoris et l’ordre personnel restent attachés au compte.

Les listes PC utilisent une barre de recherche, le choix des colonnes et les boutons Tuiles / Tableau partagés. Produits et Contacts démarrent avec six champs métier, en plus des éléments décoratifs et actions. Toutes les colonnes restent disponibles ; les préférences enregistrées ont priorité et le choix compact initial n’est pas enregistré comme préférence.

Jusqu’à 760 px, les listes en lecture seule ouvrent des fiches si aucune préférence explicite n’existe. Les lignes éditables, tableaux de formulaire, fenêtres et grilles déclarées sans cartes restent des tableaux, sauf choix explicite ou adaptation propre au module. Les grandes tables défilent dans leur zone. Les fiches mobiles partagées sont des surfaces blanches de 14 px de rayon, avec 16 px de marge intérieure, leurs libellés et leurs actions. Les ombres ne sont pas empilées sur leurs sous-contenus.

Le bas de page réserve la place de la navigation mobile et des zones de sécurité. Les conteneurs peuvent rétrécir sans élargir toute la page. Les dispositions doubles s’empilent selon le composant ; la carte TMS et l’historique utilisent un seuil de 900 px distinct du seuil des listes.

## Elevation & Depth

Les surfaces utilisent les tokens runtime, avec des ombres colorées par le pétrole et un reflet supérieur discret :

| Niveau | Token | Emploi |
| --- | --- | --- |
| En retrait | `--coco-inset` | Colonnes kanban, champs en lecture seule, zones secondaires ; aucune ombre |
| Surface | `--arc-sh-1` / `--coco-surface-shadow` | Panneaux, KPI, fiches, tuiles ; deux ombres douces et reflet interne |
| Élevé | `--arc-sh-2` | Survol d’un élément interactif, menus secondaires |
| Superposition | `--arc-sh-3` / `--coco-dialog-shadow` | Fenêtres et lanceur d’applications |

`--coco-surface-sheen` décrit le satin blanc. `--coco-action-fill` et `--coco-action-shadow` portent le relief orange. Les surfaces élevées n’ajoutent pas de contour décoratif ; les champs conservent leur contour contrasté. Le pointillé SVG intégré n’est présent que sur la toile, sans requête réseau. Aucun flou de fond permanent ni dépendance d’animation n’est ajouté.

**Règle de profondeur.** Un groupe de contenu porte une seule ombre ; ses tableaux et sous-panneaux restent plats. Les états erreur, retard et sélection gardent leur signification et leur libellé.

## Motion and feedback

- Retour immédiat : 120 ms ; changement d’état : 180 ms ; ouverture de fenêtre/lanceur : 240 ms.
- Courbe commune : `cubic-bezier(.16,1,.3,1)`.
- Le favori sélectionné se stabilise brièvement à sa place : l’utilisateur retrouve un raccourci personnel confirmé.
- La pression d’un bouton s’enfonce de 1 px ; les contrôles indisponibles ou occupés ne bougent pas.
- Aucun défilement animé ni apparition en cascade des pages. Les fenêtres apparaissent sur 4 px sans retarder leur contenu.
- `prefers-reduced-motion` supprime ces mouvements tout en conservant couleurs, états, focus et textes de retour.
- Contraste renforcé et couleurs forcées fournissent des séparateurs explicites ; impression sans toile texturée ni ombres.

## Shapes

Les boutons et champs partagent un angle discrètement adouci ; les panneaux ont un rayon légèrement plus large, selon le frontmatter. Les listes indépendantes portent une surface arrondie ; les listes intégrées à un panneau ne cumulent pas d’ombre. Les badges ont une forme compacte ; les avatars, repères GPS et numéros d’arrêt conservent leur géométrie propre. Les fenêtres partagées emploient le rayon de dialogue ; certains dialogues métier conservent leurs dimensions spécifiques.

## Components

### Buttons

La commande principale est orange, les commandes secondaires sont blanches bordées et les commandes discrètes utilisent le pétrole. Les contrôles communs gardent une hauteur minimale de 44 px ; les commandes métier spécialisées conservent leurs variantes. Le focus visible pétrole a un trait de 2 px décalé de 3 px. Les états indisponibles conservent leur sémantique et ne deviennent pas des actions actives par le seul thème.

### Inputs / Fields

Fond blanc, contour de saisie explicite, rayon commun et libellé persistant. Les champs standards ont une hauteur minimale de 44 px ; les textes multiligne gardent une hauteur naturelle. Sur téléphone, la saisie reste à 16 px. Les erreurs restent proches du champ, les valeurs survivent à un échec et le premier champ invalide reçoit le focus. Recherche et compositeur partagés rendent aussi visible le focus de leurs champs internes.

### Navigation

Un retour au menu et un seul titre de module dans le bandeau, un lanceur à neuf points, des onglets soulignés pétrole et les menus existants de recherche, notifications, configuration et compte. Les libellés traduits restent disponibles. Sur téléphone, Accueil / Recherche / Scanner / Plus occupent la barre inférieure. Le lanceur et les fenêtres conservent leur fermeture avec Échap et leur retour de focus.

### Lists / Cards / Status

Les tables utilisent des lignes horizontales, un en-tête en retrait et des montants alignés à droite. Les fiches mobiles partagées affichent les noms de colonnes et leurs valeurs sur une surface blanche, sans contour supplémentaire. Les badges gardent leur texte et leurs couleurs sémantiques. Les tableaux spécialisés, kanbans, arbres et graphiques conservent leur structure fonctionnelle.

### Progressive Editors

Produits ouvre d’abord le catalogue. Nouveau produit et Modifier affichent la fiche complète ; Retour conserve le brouillon en mémoire et un enregistrement réussi referme la fiche. Les 32 champs du tableau de produits restent disponibles dans Colonnes. L’éditeur Employé est un dépliant natif fermé au départ, ouvert par sa commande de création ou d’édition ; ses champs restent complets. L’inspecteur de stock apparaît à la sélection d’un produit ; Retour efface cette sélection et rend le focus à la liste.

### Module / Record History

L’historique de module démarre replié. Son résumé compact occupe une ligne utilitaire dans le flux normal, au-dessus de l’espace de travail : largeur maximale de 270 px sur PC, pleine largeur sur téléphone. Aucun rail vide ne réduit la liste quand il est fermé. Son ouverture conserve les lectures autorisées, les propositions et la gestion du focus. L’historique d’un dossier sélectionné reste ouvert sur PC ; l’historique central d’Agent Coco reste ouvert dans sa page, après les conversations récentes et le message.

### TMS / Agent Coco

TMS place les arrêts et la préparation à gauche de la vraie carte quotidienne sur PC ; sur téléphone, les outils et étapes sont compacts et la carte apparaît tôt. GPS, fonds, tracés, filtres de tournée, attribution, confidentialité et actions de livraison restent ceux du module. Agent Coco garde sa structure de conversations récentes, message et historique central ; les panneaux utilisent les surfaces communes et les conversations restent dans le flux.

## Do's and Don'ts

### Do:

- **Do** reprendre les tokens et composants communs avant d’ajouter une règle locale.
- **Do** conserver les pictogrammes Coco et une seule action principale identifiable.
- **Do** laisser accessibles les colonnes, détails et formulaires complets à la demande.
- **Do** respecter les préférences existantes, les langues, les droits et les états réels.
- **Do** vérifier ensemble les formats PC et téléphone, le focus et les textes longs.

### Don't:

- **Don't** empiler les ombres, ajouter des halos décoratifs ou remplacer le lanceur par une navigation permanente.
- **Don't** présenter l’orange de marque comme la couleur du texte blanc des actions principales.
- **Don't** forcer les lignes éditables ou les fenêtres en fiches sans préserver leurs contrôles.
- **Don't** transformer une valeur inconnue ou un échec de chargement en zéro ou succès.
- **Don't** appliquer ce contrat au site public ni modifier son autorité visuelle racine.

La création d’une commande fournisseur dans Achats utilise aussi une section fermée à l’arrivée. Les préparations issues du stock, d’un projet ou d’une offre fournisseur ouvrent cette section avec leurs lignes existantes ; la fermer conserve la saisie. Les erreurs de chargement de Contrats et Dépenses conservent une action Réessayer et ne deviennent pas une liste vide.


## Réutilisation

Les composants `ArcUI` et les classes métier existantes consomment les mêmes tokens. Pour une nouvelle zone :

```html
<section class="cocoSurface">
  <h2>Commandes</h2>
  <button class="arcButton primary" type="button">Créer une commande</button>
</section>
```

`cocoSurface--inset` donne une zone secondaire sans ombre, `cocoSurface--raised` un niveau élevé. Ne pas ajouter les trois variantes simultanément. Les nouveaux composants réutilisent les tokens de rayon, espacement et mouvement ; les anciens noms `arc-*` restent compatibles. Les styles spécialisés restent chargés avec leur module. La [planche des composants](components.html) utilise les vrais fichiers CSS compilés et expose les états de contrôle.
