# Charte graphique actuelle

Coco ERP applique la direction de la [référence Openhub CRM Dashboard](https://dribbble.com/shots/24822804-Openhub-CRM-Dashboard) : toile blanche, rail d’icônes ivoire, colonne de libellés blanche, destination active bleu pâle dans le rail et derrière le libellé bleu foncé, bandeau blanc compact, actions bleues et créations vertes à texte blanc et tableaux jointifs à grille fine. Cette structure remplace la finition Nozti du 8 novembre 2026 ; la demande du propriétaire d’harmoniser toutes les couleurs avec les icônes du menu fait désormais autorité pour sa palette. Inter sert aux titres, valeurs et contrôles. Le contrat normatif est [Coco ERP — espace Openhub](erp-design/DESIGN.md), accompagné de `erp-design/.impeccable/design.json` ; l’identité et les contenus métier Coco restent présents.

Cette charte vise l’application réelle [GitHub Pages](https://lisciandraj.github.io/Pro-manager-Gama/), compilée depuis `src/`. L’aperçu privé Sites reste une démonstration distincte et ne constitue pas sa publication. Les fichiers `DESIGN.md`, `PRODUCT.md` et `.impeccable/design.json` à la racine concernent exclusivement le site public GAMA. Les descriptions datées ci-dessous conservent l’historique des décisions ; la palette et les composants actuels de cette section prévalent sur leurs finitions antérieures.

| Élément | Source actuelle |
| --- | --- |
| Tokens globaux | `src/styles/tokens.css` |
| Ajustements du thème et surfaces | `src/styles/workspace.css`, `src/styles/workbench.css`, puis `src/styles/design.css` |
| Contrôles et listes partagés | `src/ui/components.css`, `src/styles/ui.css`, `src/ui/tables.js` |
| Accueil | `src/styles/home.css`, `src/ui/home-menu.js` |
| Lanceur, menu des applications et barre supérieure | `src/styles/shell.css`, `src/ui/shell.js` |
| Icônes vectorielles des modules | `src/ui/icons.js` |
| Logo de marque | `coco-erp-logo.png` |
| Icône C pour smartphone/PC | `coco-erp-icon-180/192/512.png`, variantes maskable, `favicon.ico` |
| Variantes d’export de marque | `assets/brand/` |

## Base visuelle commune

| Rôle | Standard |
| --- | --- |
| Fond / surfaces | Toile et surfaces #FFFFFF ; rail #FDFAF9 et libellés sur blanc ; retrait #F9F8F8 ; sans texture ni gradient décoratif |
| Texte / secondaire | #151515 / #6B6A69 |
| Cadre | Bandeau blanc : minimum 64 px ; sidebar PC 256 px à partir de 1180 px, tiroir en dessous ; adaptation au zoom 200 % |
| Palette partagée | Bleu #2176B8, vert #278344, rose #C7476A, corail #CC5139 ; variantes sombres et teintes claires communes ; sélection et rail actif bleu pâle #EAF3FB ; actifs de logo préservés |
| Actions | Action normale bleue #2176B8 / #1B659E ; création verte #278344 / #206B38 ; texte et icônes #FFFFFF |
| Bordures | Surface et grille de tableau #F1F0EF ; saisie #8F8B87 ; grille jointive de 1 px sans intervalle ni arrondi de ligne ; hauteur nominale 48 px |
| Police | Inter locale pour titres, texte et contrôles ; polices système en repli, licences locales dans `fonts/` |
| Échelle | Métadonnées 12, libellés de champ 13, cellules PC 13 et graisse 500, corps et valeurs de saisie PC 14, valeurs de fiche et saisie mobile 16, titres de panneau 16–17, contenu 24, titre contextuel du bandeau 22 px au-dessus de 760 px et 20 px sur téléphone ; aucun sous-titre |
| Espacements | Base 4 px ; libellé/champ 8 px ; rangées de formulaire 20/20 px et colonnes 20/16 px (PC/téléphone) ; contenu PC haut 20 et côtés 20 px, tablette côtés 24 px ; téléphone haut 16 et côtés 14 px (12 px jusqu’à 359 px), plus zones de sécurité ; panneaux 20/16 px ; écart de panneaux 20/16 px |
| Rayons | Badge 6, bouton/champ 6, onglets et recherche globale 8, liens latéraux 0, panneau PC/téléphone 8, fenêtre 8 px ; sidebar gauche sans arrondi ; composants spécialisés selon leur contrat |
| Ombres | Aucune sur les cartes, tuiles et boutons ; profondeur réservée aux menus et superpositions |

Le [contrat Coco ERP — espace Openhub](erp-design/DESIGN.md) précise les tokens, composants, tableaux, formulaires progressifs et historiques actuels. Sa sidecar présente les contrôles sans dépendance de framework. `src/styles/tokens.css` reste la source runtime ; `design.css` applique le thème commun après les styles de disposition. Les adaptations CRM, Achats, RH et TMS restent dans leurs styles différés. Les contrats sous `replica/design/` et les captures datées documentent les étapes antérieures ; ils ne remplacent pas la charte courante. Inter est livrée localement et préchargée ; aucune police distante n’est requise au rendu. Les fichiers Poppins existants restent disponibles pour compatibilité.

La refonte est exclusivement visuelle. Les modules, identifiants, données, calculs, droits, actions, filtres, onglets, liens, langues et préférences existantes sont conservés. Les graphiques utilisent leurs vraies séries existantes. Le menu conserve ses destinations, droits, favoris et langues ; il devient permanent sur PC à partir de 1180 px et reste un tiroir accessible en dessous. Les onglets natifs demeurent dans le contenu. Le bandeau d’accueil téléphone conserve menu et compte sans logo CO.

Les actions normales partagent le bleu `#2176B8` et les créations le vert `#278344`, avec texte et icônes blancs. Leurs survols sont `#1B659E` et `#206B38`. Le rose `#C7476A` et le corail `#CC5139` complètent la même palette, avec les variantes sombres `#AB3555` et `#AD402D`. Les teintes claires sont bleu `#EAF3FB`, vert `#EDF7F0`, rose `#FCEEF3` et corail `#FFF1EC`. La sélection et le rail actif utilisent le bleu pâle avec texte bleu foncé. Les fonds blancs, le rail ivoire et la structure Openhub restent en place.

Les six étapes du Kanban CRM conservent leurs noms et leur ordre ; leurs anciens alias de couleur sont remappés sur les quatre familles et leurs textes sombres. Le Kanban Projets conserve ses colonnes neutres et ses tâches blanches sans contour. Les graphiques utilisent dans l’ordre bleu, vert, rose, corail sombre, bleu sombre et rose sombre, avec leurs données et légendes réelles. Les statuts information, succès, erreur et attention emploient respectivement le bleu sombre `#1B659E`, le vert sombre `#206B38`, le rose sombre `#AB3555` et le corail sombre `#AD402D`, sur leurs teintes claires. Les libellés et pictogrammes portent toujours le sens des états. Les primitives `--coco-blue`, `--coco-green`, `--coco-rose`, `--coco-coral`, leurs suffixes `-hover` / `-tint` et les alias sémantiques sont centralisés dans `src/styles/tokens.css`. Les anciens noms restent compatibles avec les modules.

Cette harmonisation concerne l’ERP : les actifs de marque approuvés, le site public, les exports PDF et l’impression, les codes-barres et QR, les fonds de carte externes et les couleurs de données choisies par les utilisateurs restent distincts.

**Référence d’identité du 20 octobre 2026.** Le paragraphe suivant décrit les actifs de marque approuvés ; sa mention d’une bordure de tuile appartient à cette révision. Les règles actuelles ci-dessus déterminent la présentation actuelle des tuiles.

Depuis le 20 octobre 2026, le menu ouvrable et la connexion affichent le logo « COCO » en bleu pétrole avec des nuances satinées, une texture brossée discrète et un léger relief lumineux, avec le O et le C centraux partiellement fusionnés et « ERP » de la même couleur, davantage espacé sous le mot. L’icône PC/smartphone reprend uniquement le monogramme CO, avec le C à gauche, le O à droite et le même écart courbé que dans le logo principal, sur une tuile blanche, sans relief ni texte. Les originaux sont conservés intacts dans `assets/brand/coco-erp-logo-approved-20261020.png` et `assets/brand/coco-erp-icon-co-approved-20261018.png`, à côté des références précédentes. `scripts/export-brand-assets.py` (Python avec Pillow) recadre uniquement les marges blanches du logo principal et ajoute 3 % de marge blanche par bord à l’icône pour les masques d’application. Le logo web mesure 1200 × 435 px. Le logo principal utilise la révision `20261020-satin` ; le manifeste, le favicon et les icônes PC/smartphone utilisent `20261018-co`, y compris dans le menu et le cache hors connexion. Les anciennes adresses `coco-gama-*` et `icon-*.png` conservent des exports compatibles. Le point de lancement PWA et son identité existante restent inchangés. Les titres d’introduction de l’accueil ont été retirés ; la personnalisation des tuiles est conservée. Le traitement sans contour de la direction du 30 octobre remplace leur bordure fine antérieure. Une photo d’employé peut remplacer les initiales du profil.

Les rapports de contraste historiques ne doivent pas être réutilisés après une modification de couleurs. Les couples calculés en sRGB WCAG donnent 4,83:1 pour blanc/action bleue et 6,17:1 au survol ; 4,76:1 pour blanc/création verte et 6,52:1 au survol. Le bleu foncé sur la sélection bleu pâle atteint 5,50:1. Les textes d’information, succès, attention et erreur sur leurs fonds atteignent respectivement 5,50:1, 5,95:1, 5,37:1, 5,53:1. Les neutres texte/blanc et secondaire/blanc sont à 18,26:1 et 5,40:1 ; le contour des champs/blanc à 3,38:1. Le tableau complet est dans le contrat ERP. Ces calculs de tokens ne constituent pas un audit de chaque style calculé dans chaque état métier.

### Iconographie commune — 8 novembre 2026

La référence [Upview Icons](https://dribbble.com/shots/27554902-Upview-Icons) remplace le dessin au trait des révisions d’octobre : silhouettes pleines et compactes, coins généreusement arrondis, terminaisons en capsule et détails évidés. Les pictogrammes Coco sont redessinés pour leurs fonctions ERP ; aucun dessin ni actif de la référence n’est importé. Une seule couleur par pictogramme, sur fond transparent, sans dégradé, ombre ni pastille. La structure Openhub reste en place.

Le catalogue `src/ui/icons.js` conserve ses 61 entrées, alias compris, et les API `icons` / `moduleIcon`. La grille commune mesure 24 × 24, avec une emprise voisine de 20 × 20 et des détails ouverts pour les tailles compactes. Les groupes déclarent leur remplissage et neutralisent le trait hérité des anciens renderers. Les évidements sont transparents, sans blanc peint : le dessin fonctionne sur les surfaces et dans les commandes sélectionnées.

Les tuiles et emplacements d’en-tête partagent une couleur par famille : bleu #2176B8, vert #278344, rose #C7476A et corail #CC5139. Ces teintes adaptées au blanc de l’ERP ne sont pas les couleurs originales du visuel sur fond sombre. Les anciens noms de famille (`blue`, `teal`/`cyan`, `violet`, `orange`) restent compatibles. Le token `--coco-glyph-tone`, décliné par famille, est dans `src/styles/tokens.css` ; les glyphes de ces emplacements consomment ce rôle dans `src/styles/design.css` via `--coco-glyph-color`.

Navigation latérale, KPI, recherche, paramètres et commandes compactes partagent désormais les glyphes pleins arrondis. Le rail d’icônes est ivoire et la colonne de libellés blanche. Les icônes sont sombres au repos ; la destination active garde son icône et son repère bleus, sur un rail et un libellé bleu pâle, sans arrondi de ligne. Les commandes bleues et les créations vertes portent des icônes blanches lisibles. La navigation basse et l’ouverture du menu réutilisent le catalogue. Les favoris restent évidés au repos et pleins à la sélection. Contrats conserve une feuille avec signature/stylo et Dépenses un reçu avec pièce ; Agent Coco reste identifiable par sa tête de robot.

Les KPI gardent leurs pictogrammes de 28 px dans un emplacement de 34 px et la navigation latérale ses 21 px. Les tailles réactives des tuiles, les libellés FR/ES/EN, focus, cibles tactiles, droits, données et destinations restent ceux des composants existants. Le logo COCO, le monogramme CO, les icônes PWA, les photographies, les graphiques, les codes-barres et le site public restent distincts de cette famille.

Les tableaux restent le défaut sur PC. Sur téléphone (760 px ou moins), les listes en lecture seule utilisent des fiches si le compte n’a pas choisi de vue. Les lignes éditables, grilles de formulaire, fenêtres et tableaux explicitement exclus gardent le tableau, sauf choix explicite ou adaptation propre au module. Un choix enregistré reste prioritaire. Les listes de travail utilisent une grille jointive de 1 px et des lignes nominales de 48 px sans intervalle ; les exports papier et tableaux spécialisés restent exclus de ce traitement. Les préférences de vue et l’alignement des cellules restent conservés. Les en-têtes et cellules vides restent alignés. Les grands tableaux défilent dans leur propre zone. Le choix Tuiles / Tableau reste conservé par compte et tableau (`src/ui/tables.js`). Les fiches mobiles partagées sont des surfaces blanches de 8 px de rayon, espacées de 12 px, avec 16 px de marge intérieure.

Le sélecteur « Tuiles / Tableau » utilise les mêmes boutons partagés, y compris dans les tableaux historiques et les fenêtres de consultation. Leur largeur s’adapte à l’icône et au libellé traduit, sans compression ; leur hauteur minimale est de 44 px. Le choix actif utilise le bleu #2176B8 avec texte et icônes #FFFFFF ; les choix inactifs sont blancs. La présentation est définie dans `src/styles/ui.css` et la finition commune dans `src/styles/design.css` ; les styles de page ne redéfinissent pas ces boutons.

En mode tuiles, les valeurs de détail affichent leur intitulé de colonne (`data-col`), à gauche de la valeur, sur téléphone comme sur ordinateur. La règle des cartes réactive explicitement ces intitulés, masqués en mode tableau. Le titre de la tuile, les photos et les boutons conservent leur présentation sans intitulé supplémentaire.

L’ordre des colonnes se modifie en glissant un en-tête (souris) ou sa poignée (tactile), ou avec Alt + flèche gauche/droite sur l’en-tête/la poignée. Le menu Colonnes propose la remise à l’ordre initial. L’ordre est enregistré dans le navigateur par compte et tableau, avec les préférences existantes de colonnes masquées ; il survit au rechargement et à la pagination mais n’est pas synchronisé entre appareils. Le tri reste attaché à la clé métier d’origine. Les cellules fusionnées restent groupées : un déplacement qui couperait un groupe est refusé ; les en-têtes à plusieurs niveaux et les tableaux avec fusion verticale conservent leur structure.

Les fenêtres de consultation partagées affichent une seule action « Retour » (« Volver » / « Back »), sans doublon « Fermer ». Les formulaires conservent leur action métier et leur bouton Retour. Une confirmation explicite conserve ses deux choix. `ArcUI.dialog` reconnaît les anciens libellés de fermeture FR/ES/EN ; `dismissOnly` permet de déclarer ce comportement explicitement.

La charte commune est implémentée dans `src/styles/workspace.css`, `src/styles/workbench.css` puis `src/styles/design.css` : toile blanche, rail ivoire, libellés sur blanc, sélection bleu pâle dans le rail et derrière le libellé bleu foncé, tuiles blanches à bordure fine sans ombre, titres visibles, favoris par compte et navigation mobile Accueil/Recherche/Scanner/Plus. Toutes les familles partagent le même traitement ; le survol change la teinte et la bordure. La première catégorie du menu des applications est « Favoris » : les modules étoilés sur l’accueil y apparaissent immédiatement, dans l’ordre de leur ajout et selon les droits du compte. Retirer une étoile retire aussi son raccourci ; les changements sont synchronisés entre les onglets du navigateur. Sans favori, une indication explique comment en ajouter. Les favoris sont aussi accessibles dans le menu mobile. L’accès au scanner conserve les droits du module. Les favoris et l’ordre personnel des modules sont indépendants.

Le Dashboard présente les indicateurs du profil, le graphique, les actions du jour et cinq commandes récentes. Son en-tête conserve la flèche de retour au menu partagée avec les autres modules, sur ordinateur et téléphone. Les vues favorites, indicateurs personnels et analyses détaillées restent accessibles dans des sections dépliables. Les commandes récentes sont une lecture limitée soumise aux mêmes droits, annulée visuellement lors d’un changement de compte ou de période.

Le stock conserve les calculs serveur : physique, réservé et disponible sont distincts. Six colonnes principales ouvrent un inspecteur avec les autres valeurs et emplacements. Les filtres avancés restent accessibles sans charger les onglets secondaires. La commande affiche huit étapes issues des données disponibles, ses lignes et une prochaine action réutilisant le bouton métier existant. Dans Suivi de processus, l’encadré orange « Prochaine action » reprend l’illustration partagée du module de sa première action accessible, issue du registre et de `ArcUI.moduleIcon`, avec les mêmes couleurs bleu/orange. L’icône suit donc la destination du bouton, y compris les onglets Commandes et Factures/encaissements ; les demandes client reprennent Ventes, et le parcours des retours reprend Retours. Sans action accessible, le pictogramme de Suivi de processus sert de repère ; un processus terminé conserve sa coche verte. Une preuve de livraison ne devient pas validée à partir du seul statut d’expédition.

Le SRI filtre les états fiscaux à la source avec pagination ; les onglets de traitement consultent les émissions liées à leurs factures. L’inspecteur distingue état interne et autorisation fiscale ; les contrôles ne deviennent verts qu’après la vérification API effective. XML/RIDE nécessitent une autorisation. Les envois groupés conservent les confirmations, droits et contrôles de non-réémission.

La réception mobile présente Quantités/Photo/Signature. Le bouton de sauvegarde attend les quantités cohérentes, le nom et la signature pour une réception acceptée, le motif d’incident, et la photo obligatoire si des unités manquent. La validation serveur et le fonctionnement hors connexion sont conservés.

Les trois références du 11 octobre 2026 précisent ces écrans : Dashboard avec en-tête compact et cartes à icônes circulaires, commande en deux colonnes sous huit étapes, SRI avec cinq colonnes principales et contrôle avant envoi. La première catégorie Favoris est conservée ; le logo suit la sélection approuvée du 20 octobre décrite ci-dessus.

Le dossier de commande possède de vrais onglets Détails, Documents et Historique, utilisables au clavier. Le bandeau client regroupe livraison planifiée, emplacements réservés et paiement confirmé lorsqu’ils existent. Les valeurs absentes restent explicitement indisponibles. L’action métier principale est déplacée dans l’en-tête, avec son gestionnaire existant ; Télécharger produit un CSV de ses lignes après contrôle du droit d’export. La prochaine action et les trois événements récents sont à droite, l’historique complet dans son onglet. Les détails opérationnels restent dépliables. Sur téléphone, les étapes passent à deux colonnes et la prochaine action précède les lignes.

Les outils de tableau partagés acceptent un hôte de barre facultatif via `data-gama-toolbar-host`, limité à la même section. SRI l’utilise pour placer le sélecteur de colonnes dans la barre supérieure sans recopier ses gestionnaires ni ses préférences. Les aperçus courts du Dashboard et de la commande masquent la barre de recherche secondaire ; leurs tableaux et tris restent fonctionnels.


## Détails progressifs et espaces spécialisés

Produits et Contacts démarrent avec six champs métier visibles, en plus des photos, icônes et actions. Les 32 champs du tableau Produits restent dans le sélecteur Colonnes. Les préférences de masquage et d’ordre déjà enregistrées ont priorité ; cette présentation initiale ne crée pas de préférence persistante et « Tout afficher » reste disponible.

Le catalogue Produits apparaît avant le formulaire complet. Nouveau produit et Modifier affichent la fiche ; Retour la masque sans effacer le brouillon en mémoire, tandis qu’un enregistrement réussi la referme. L’éditeur Employé est un dépliant natif fermé au départ, ouvert à la création ou à l’édition, avec ses champs existants. Dans Stock, l’inspecteur n’apparaît qu’après sélection d’un produit ; Retour efface la sélection et rend le focus à la liste.

Les historiques de module démarrent repliés : résumé compact sur PC, jusqu’à 270 px selon l’espace disponible, dans une ligne utilitaire au-dessus du travail. Sur PC, le résumé partage cette ligne avec Outils lorsque l’en-tête le permet ; Dashboard partage historique, filtres et outils à partir de 1280 px, et Devis réserve l’extrémité droite de sa barre secondaire à partir de 1180 px. Entre 390 et 760 px, Produits et Dashboard partagent historique fermé et Outils avec 140 px réservés aux traductions longues ; mois et profil Dashboard sont côte à côte, puis Personnaliser en dessous. Les téléphones plus étroits et les historiques ouverts conservent le flux normal. Un historique fermé ne réserve aucune colonne latérale. Cette composition CSS ne déplace ni ne clone les contrôles métier. Les dossiers sélectionnés gardent leur historique ouvert sur PC ; l’historique central d’Agent Coco reste ouvert dans sa page. Les lectures, propositions, droits et commandes de focus restent ceux des composants existants.

TMS utilise sa vraie carte quotidienne, les marqueurs GPS et les filtres de tournée. La préparation et les arrêts sont à gauche de la carte sur PC. Jusqu’à 900 px, les outils et la progression deviennent compacts et la carte précède les listes longues. Tracés, attribution, confidentialité, routage et actions métier sont conservés. Agent Coco conserve l’ordre conversations récentes, message et historique central ; les panneaux blancs et les contrôles suivent les tokens ERP partagés.

## Parcours quotidiens — octobre 2026

La liste des devis place « Nouveau devis » et « Actualiser » près du titre et du nombre de résultats. La recherche, le statut et la vue restent visibles. Les dates, modèles et vues enregistrées sont regroupés dans « Filtres et vues enregistrées » ; un filtre de date actif ouvre ce panneau. Les modèles et l’ancien formulaire conservent leurs accès existants. Les totaux sont alignés à droite et les badges reprennent les couleurs de statut partagées, avec leur libellé.

Depuis « À traiter », ouvrir un devis ou une commande puis revenir conserve recherche, type de document, page, défilement et focus sur la ligne d’origine. Si la dernière page disparaît, la liste revient à la dernière page disponible. Cet état est en mémoire et disparaît au changement de compte. Le retour depuis la liste des devis conserve aussi le défilement et le focus ; les vues enregistrées gardent leur clé utilisateur existante.

Les barres de tableaux placent recherche, colonnes et choix de vue sur une ligne lorsque la largeur le permet ; sur téléphone, la recherche occupe toute la largeur. L’ouverture du sélecteur de colonnes conserve la place nécessaire à sa liste. L’ordre, le masquage et les préférences de vue restent gérés par le composant partagé.

Les formulaires montés par `ArcUI` conservent la validation HTML et leurs gestionnaires métier. `src/ui/form-validation.js` ajoute un message traduit près du champ invalide, conserve les indications `aria-describedby`, ouvre la section concernée et place le focus sur la première erreur. Les erreurs métier personnalisées restent celles du formulaire. Une saisie corrigée efface son erreur ; les valeurs restent en place lors d’un échec d’enregistrement.

La synthèse comptable commence par les factures clients échues, les factures fournisseurs échues et les mouvements bancaires non rapprochés. Chaque compteur ouvre la liste filtrée existante. Les droits commerciaux masquent les indicateurs non autorisés. Un compteur absent affiche « — » et n’ouvre aucune liste ; un vrai zéro reste affiché. Aucun calcul comptable ni appel supplémentaire n’est ajouté.


## Adaptation des références Odoo — 15 octobre 2026

Les références réunies pour Coco sont appliquées à la hiérarchie et à la densité des écrans, avec les couleurs et illustrations Coco. Les outils administratifs rejoignent l’en-tête partagé ; les listes gardent leurs grilles et leurs préférences. Le catalogue Produits précède désormais le formulaire : « Nouveau produit » prépare un brouillon vide et place le focus dans son nom ; modifier une ligne ouvre la même fiche préremplie.

Documents sépare les filtres dans un rail et la recherche/résultats dans une surface principale. La recherche doit rester dans `.sdLibraryContent`, car GamaTable normalise son emplacement. Les deux zones s’empilent sous 760 px. La base de connaissances sépare désormais son arbre et son article dans deux panneaux blancs, avec un rail de 230 px et un intervalle de 30 px sur PC ; les panneaux s’empilent sur téléphone. Les cartes d’opportunité, champs, en-têtes et pieds des dialogues partagés suivent les tokens harmonisés.

La spécification visuelle courante est [Coco ERP — espace Openhub](erp-design/DESIGN.md). Le [relevé Replica](../replica/recon.md) conserve les sources de référence historiques. Les sources runtime restent `src/styles/` et `src/ui/` ; les tokens documentaires ne sont pas une seconde feuille de thème à importer.

Les styles propres au pipeline CRM, à Documents et à la base de connaissances sont chargés avec leurs modules via le registre de chargement différé. Cela conserve le budget CSS de démarrage ; `config/runtime-assets.json` reste la source des assets publiés.

Entre 390 et 760 px, les sélecteurs de période et de profil du Dashboard partagent une rangée, et Personnaliser occupe la largeur suivante. Sur les téléphones plus étroits, les contrôles reviennent au flux normal lorsque la place manque. Les valeurs FR/ES/EN restent à 16 px sur téléphone, avec retour à la ligne des libellés et sans débordement des contrôles natifs WebKit à 320 px.

## Cadre professionnel Coco / GAMA — 4 novembre 2026 (historique visuel)

Cette révision du 4 novembre utilisait une sidebar de 232 px avec retrait de 12 px. La référence du 7 novembre remplace ce traitement par une sidebar droite de 256 px ; le seuil de 1180 px et le début du contenu à 256 px restent conservés. En dessous, le menu est un tiroir avec Échap, focus retenu, arrière-plan inerte et retour de focus à la fermeture. Les droits, favoris, groupes et langue restent ceux du menu existant.

Le bandeau mesure au moins 88 px sur PC, 80 px sous 1180 px et 72 px jusqu’à 760 px. Il affiche un titre unique et la description traduite existante du module. La recherche globale reste complète sur PC et tablette, puis rejoint son accès mobile. Les onglets natifs restent dans le contenu, dans leur DOM d’origine, avec défilement horizontal ; ils ne sont plus épinglés dans l’en-tête.

L’accueil utilise trois colonnes jusqu’à 760 px, quatre de 761 à 860 px, cinq de 861 à 1179 px, sept de 1180 à 1439 px et neuf à partir de 1440 px. Entre 861 et 1179 px avec une hauteur au plus 700 px, il utilise six colonnes. Jusqu’à 359 px, les trois colonnes utilisent un intervalle de 6 px, un retrait de page de 12 px plus les zones de sécurité, une marge intérieure de tuile de 6 px / 2 px, des icônes de 28 px et des titres de 11 px à interligne 1,25. Les tuiles restent carrées ; Flexbox et un espace carré dans le flux évitent le calcul cyclique de hauteur dans WebKit. Les écrans courts défilent sans aplatir les tuiles. Les libellés complets, favoris et ordre personnel sont conservés.

Les surfaces blanches emploient un rayon de 16 px, réduit à 12 px sur téléphone, et une ombre peu profonde. CRM et Projets placent les tâches sur des colonnes sans fond. Documents et Knowledge séparent le rail blanc de 230 px et le panneau principal par 30 px, puis s’empilent jusqu’à 760 px. Les contrôles partagés gardent leur cible de 44 px.

Ventes conserve sa barre de commande, ses filtres, sa pagination serveur, ses vues enregistrées et ses clés de préférence. Le site public et les documents imprimés ont leurs styles distincts. Les suites de navigation et de disposition utilisent uniquement des fixtures locales ; la [vérification du 30 octobre](erp-design/verification-2026-10-30.md) décrit la révision antérieure.

## Affinement UI/UX Pro Max — quatre références du 18 octobre 2026 (historique visuel)

Les fondations fonctionnelles de cette révision sont conservées. Sa finition historique employait Inter pour le travail, Poppins pour les titres, une toile neutre unie et des surfaces blanches sans satin ; le contrat actuel emploie Inter pour tous ces rôles. Le voile des fenêtres reste sans flou ; les préférences de réduction du mouvement et de transparence sont respectées.

`ArcUI.metricIcon(name)` fournit le pictogramme décoratif partagé des KPI. Les compteurs RH, CRM, Stock, Achats, Comptabilité, Flotte et Projets réutilisent la même composition : emplacement de 34 px pour un pictogramme de 28 px, libellé de 13 px, chiffre tabulaire de 22–28 px et détails de 12 px. Les valeurs, sources et calculs sont inchangés. Sur téléphone, icône et texte s’empilent sans réduire les champs sous 16 px.

Les tableaux gardent des séparateurs horizontaux fins : en-têtes communs de 12 px, cellules PC de 13 px et valeurs de fiches mobiles de 16 px. Les contrôles communs conservent une hauteur minimale de 44 px ; les tableaux spécialisés gardent leur densité propre. Les cellules de cette révision historique utilisaient 4 px / 16 px de marge intérieure. La finition actuelle utilise 10 px / 14 px, des lignes nominales de 48 px et des en-têtes nominaux de 42 px ; une ligne avec des actions de 44 px peut grandir pour accueillir marges et grille. La piste d’audit utilise 10 px horizontalement. Les métriques spécialisées du Dashboard restent dimensionnées par leur contenu. Les badges compacts conservent leur état écrit et leurs couleurs sémantiques. Kanban et progression réutilisent les mêmes surfaces ; retard et cible de dépôt restent distingués.

Les graphiques de cette révision historique utilisaient les dégradés pétrole/orange centralisés. Leurs axes, valeurs exactes, alternatives en tableau, exports et liens restent les mêmes, y compris dans la vue agrandie. Aucun indicateur fictif n’est ajouté.

Le texte blanc était conservé sur les boutons orange cuivré de cette révision historique. La nuance unie des actions est distincte de l’orange brut du logo ; son survol est plus sombre. Vérifier les couples calculés dans les composants actuels. Les rapports de contraste de `replica/design/` restent datés et ne constituent pas un audit de chaque état de l’interface.

Les CSS des KPI personnels et de Projets se chargent avec Dashboard et Projets via `src/app/lazy-modules.js`. Cela conserve le budget de démarrage sans augmenter son plafond. Les formulaires, droits, langues, navigation et préférences des modules sont conservés.

Périmètre : application ERP. Le site `src/storefront/`, les pages publiques, leurs API et leur déploiement Cloudflare ont une charte et une publication distinctes.

### Captures historiques

Captures locales d’une révision antérieure de l’application compilée, avec données de test : [accueil PC](design/erp-home-desktop.png), [accueil téléphone](design/erp-home-mobile.png), [fenêtre commune](design/erp-dialog.png). Elles documentent cette révision et ne font pas autorité sur les tokens actuels ni sur une publication en production.

### Contraste des surfaces sur PC

La toile est blanche et le rail de navigation ivoire. Les séparateurs restent fins, les cartes et KPI sans ombre. Les onglets actifs utilisent un fond bleu pâle et un libellé bleu foncé. Les contrôles du contenu et des fenêtres gardent un contour de focus bleu #2176B8 de 2 px décalé de 3 px ; les onglets le placent à l’intérieur. Le site public suit son propre contrat.

## Contrats de mise en page de l’ERP

La structure des cartes Dashboard appartient à `src/styles/workspace.css`. Le thème `src/styles/design.css` règle les couleurs, la typographie et les surfaces, sans imposer de grille à toutes les cartes. `adMetricStandard` contient une icône et un corps ; `adMetricExecutive` empile libellé, montant et action. Les indicateurs de direction passent sur une colonne lorsque le conteneur fait au plus 600 px. Les montants et libellés restent lisibles sans débordement.

Les sélecteurs recherchables (`src/ui/select-search.js`) gardent une hauteur naturelle dans les champs en colonne et conservent le nom accessible du champ. Le seuil de huit options ne doit pas modifier la hauteur de la barre de filtres de plus que la ligne d’aide. Le select natif conserve valeur, validation et événements ; seul le contrôle visible porte le focus et le libellé.

Les libellés `data-col` générés par `src/ui/tables.js` sont recalculés à chaque changement de langue. Les libellés explicitement définis par les modules sont préservés. Dans la piste d’audit, le détail revient à la ligne dans une largeur bornée, y compris pour une chaîne sans espaces ; le tableau conserve son défilement local et ses préférences de colonnes. Sur ordinateur, replier son historique déplace le résumé au-dessus du tableau et lui rend toute la largeur disponible ; rouvrir rétablit les deux colonnes.

Les métadonnées utilisent `--coco-muted`, avec un contraste minimal de 4,5:1 sur le fond de travail. Les commandes de dépliage, favoris et options de colonnes ont une cible tactile d’au moins 44 px sur téléphone et écran tactile. Sur téléphone, les étoiles restent visibles directement dans le coin supérieur droit de chaque tuile, avec une cible de 44 × 44 px ; les toucher change le favori sans ouvrir le module. Personnaliser conserve également un bouton dédié de 44 px par module. Le changement de favori est immédiat ; le bouton Enregistrer concerne les modules masqués. La grille d’accueil utilise sept colonnes de 1180 à 1439 px, neuf à partir de 1440 px et trois sur téléphone.

Le token `--arc-motion` est nul avec `prefers-reduced-motion: reduce`. Le thème supprime les transitions et réduit les animations décoratives ; les états d’attente restent signalés par un indicateur statique ou du texte. Les mouvements fonctionnels ne doivent pas être nécessaires pour comprendre un état.

La couverture automatisée est dans `tests/layout-audit-regressions.spec.js`, complétée par les suites responsive, formulaires, sélecteurs et espace de travail. Ces essais utilisent des données isolées, sans modifier les données de production.

### Listes opérationnelles — 20 octobre 2026

Les commandes partagées des tableaux conservent une recherche pleine largeur sur
petit écran, suivie des colonnes et du choix de vue. Le sélecteur de colonnes fermé
occupe une commande de 44 px minimum ; ses options ouvertes restent dans le flux.
Les listes Contrats et Notes de frais gardent leur recherche serveur et son bouton
ensemble, avec la création au-dessus sur téléphone. Les erreurs vides ne réservent
pas de ligne. Leur grille utilise une colonne `minmax(0,1fr)` pour contenir les
tables larges sans agrandir la page. Le site public conserve sa charte distincte.

Les modules Contrats et Dépenses et justificatifs ont chacun un dessin propre : `contract`, une feuille et un stylo orange avec une signature, et `expense`, un reçu dentelé avec une pièce orange. Ces deux icônes utilisent le même catalogue vectoriel 24 × 24 et sont partagées entre accueil, navigation et en-têtes.

Le module `returns` porte le libellé court « Retour » (FR), « Devolución » (ES), « Return » (EN), tout en conservant ses onglets de retours et de réclamations.

### Standard PC et smartphone — toutes les pages ERP

Ces règles s’appliquent aux modules, listes, dossiers, réglages et fenêtres ERP,
y compris Contrats et Dépenses. Le catalogue public conserve sa charte distincte.

| Élément | PC | Smartphone / tablette étroite |
| --- | --- | --- |
| Page | Dès 1180 px, contenu à 256 px avec retrait haut 20 et côtés 20 px ; sous 1180 px, haut 18 et côtés 24 px | Jusqu’à 760 px, haut 16 et côtés 14 px (12 px jusqu’à 359 px), plus zones de sécurité ; place de la navigation basse et zones de sécurité ; aucun défilement horizontal de la page |
| Hiérarchie | Titre dans la barre commune, action principale puis filtres et résultats | Même ordre ; commandes qui reviennent à la ligne, recherche et bouton associés |
| Tableaux | Grille jointive 1 px, texte 13 px et lignes nominales 48 px ; colonnes et vue conservées par compte | Fiches pour les listes en lecture seule sans préférence ; grilles éditables et fenêtres en tableau ; défilement local |
| Historique | Module replié dans une ligne utilitaire partagée quand la place le permet, sans rail vide ; colonne lorsqu’il est ouvert ; dossier sélectionné selon son comportement existant | Module replié dans le flux ; ligne partagée avec Outils pour Produits/Dashboard de 390 à 760 px ; ouverture en panneau avec fermeture et gestion du focus |
| Navigation basse | Absente | Espace réservé jusqu’à 860 px, avec zone de sécurité iOS ; aucun résumé d’historique par-dessus les boutons |
| Formulaires | Colonnes adaptées à la place disponible | Une colonne lorsque nécessaire, champs à 16 px et commandes tactiles d’au moins 44 px |
| Espacement | Échelle 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 px ; libellé/champ 8, rangées et colonnes de formulaire 20 px | Libellé/champ 8, rangées 20 et colonnes 16 px ; les messages d’erreur vides ne réservent pas de rangée |
| États | Chargement, erreur, vide et données réelles dans la même structure | Même comportement, textes longs et traductions avec retour à la ligne |

Les conteneurs de page utilisent `min-width:0` : un tableau large ne peut pas
agrandir la colonne ni décaler l’en-tête. Les règles de position de l’historique
sont dans sa feuille chargée à la demande ; le budget de démarrage reste inchangé.
L’historique central d’Agent Coco reste dans le flux de sa page. La dernière mesure historique du CSS initial était de 298 874 octets sur 300 000 ; le build courant doit être remesuré ; les compositions d’historique restent dans `order-followup.css`, chargé à la demande.

La suite `responsive-layout.spec.js` parcourt tous les modules visibles de la
fixture en 320, 360, 390, 768, 844, 1024, 1440 et 1920 px. Les suites formulaires,
fenêtres, listes métier et historiques complètent ce contrôle, notamment pour
les chevauchements avec la navigation. Les essais Chromium et WebKit émulent les
écrans ; ils ne remplacent pas un essai matériel sur iPhone ou Android.

## Accueil — tuiles des modules

Les tuiles restent carrées avec une surface blanche, une bordure fine et aucune ombre, séparées par l’espace. Elles affichent le pictogramme partagé et le nom du module. Les favoris et le réordonnancement restent disponibles. Le téléphone affiche trois tuiles par rangée, y compris à 320 px ; le PC utilise sept colonnes de 1180 à 1439 px et neuf à partir de 1440 px. La navigation clavier garde un indicateur de focus visible.


### Apple Design — 21 octobre 2026 (historique visuel)

Application des fondations HIG au web, sans imposer les conventions d’une application native :
- `layout.md › Best practices` : hiérarchie stable, navigation existante et espaces sûrs conservés.
- `typography.md › Best practices` : Inter locale pour le travail, Poppins pour les titres, chiffres tabulaires et champs mobiles de 16 px.
- `color.md › Inclusive color` : sélection identifiée par fond bleu clair, contour et graisse ; orange réservé aux actions principales. Les libellés de statuts restent présents.
- `accessibility.md` : focus visible, réduction du mouvement et contraste renforcé selon les préférences du système ; contrôles partagés de 44 px sur écran tactile.
- `lists-and-tables.md` : surfaces opaques, séparateurs horizontaux lisibles et défilement des grands tableaux dans leur conteneur.

Les tuiles carrées (sept ou neuf colonnes sur PC, trois sur téléphone), favoris et icônes restent en place. L’historique de module est progressif ; celui du dossier sélectionné reste ouvert sur PC et le central Agent Coco reste dans le flux. Le site B2B et les documents imprimés ont leurs propres styles. Le mode sombre complet n’est pas livré par cette évolution : les modules historiques nécessitent un audit dédié avant activation.

La création d’une commande fournisseur dans Achats utilise aussi une section fermée à l’arrivée. Les préparations issues du stock, d’un projet ou d’une offre fournisseur ouvrent cette section avec leurs lignes existantes ; la fermer conserve la saisie. Les erreurs de chargement de Contrats et Dépenses conservent une action Réessayer et ne deviennent pas une liste vide.

## Autorité visuelle et vérification

La structure Openhub et la palette des icônes du menu font autorité pour le thème actuel ; elle remplace la finition Nozti et conserve les décisions fonctionnelles des révisions antérieures. Le bandeau mesure au minimum 64 px et présente un seul titre contextuel, sans sous-titre, de 22 px au-dessus de 760 px et 20 px sur téléphone. Les titres de contenu `h2` restent distincts à 24 px sur PC et 23 px sur téléphone. La sidebar PC mesure 256 px à partir de 1180 px et devient un tiroir en dessous. La composition reste utilisable au zoom 200 %, avec retour à la ligne, défilement local des tableaux et actions accessibles. Les marques, contenus et données d’Openhub ne font pas partie du produit. La [fiche de surface ERP](../.impeccable/surfaces/src-app-index-html.md) enregistre le périmètre ; la [vérification du 30 octobre](erp-design/verification-2026-10-30.md) conserve les mesures historiques Geex. La [planche des composants](erp-design/components.html) et le [contrat de réutilisation](erp-design/DESIGN.md#reuse) suivent les sources runtime. Les captures finales de fixtures PC/téléphone Accueil, Produits, fiche produit, Dashboard et Devis servent à la revue. Les actifs approuvés préexistants gardent leur provenance décrite ci-dessus. Aucun nouveau moteur JavaScript n’est ajouté.
