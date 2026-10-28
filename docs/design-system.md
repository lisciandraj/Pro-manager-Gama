# Charte graphique actuelle

Coco ERP applique la charte Coco Clair aux modules internes : espace de travail blanc, Inter locale, listes lisibles, détails progressifs et navigation horizontale. Le bleu pétrole, l’orange et les actifs Coco conservent l’identité du produit. Le contrat de tokens actuel est [Coco Clair ERP](erp-design/DESIGN.md), accompagné de sa sidecar `erp-design/.impeccable/design.json`. Les fichiers `DESIGN.md` et `.impeccable/design.json` à la racine concernent exclusivement le site public GAMA.

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
| Fond / surfaces | #FFFFFF ; fond en retrait #F7F9FA ; surfaces opaques et mates |
| Texte / secondaire | #17243B / #5D6980 |
| Marque | Bleu pétrole #157F98, lien #10677D, orange #F87826 |
| Action principale | Orange soutenu #BD4E09, texte blanc #FFFFFF ; marque #F87826 conservée |
| Bordures | Panneaux et lignes #DFE6EB ; tuiles d’accueil sans contour ; saisie #7B8797 ; pas de quadrillage vertical ordinaire |
| Police | Inter variable locale en premier, puis polices système ; poids courants 400, 500, 600 |
| Échelle | Métadonnées 12, corps et valeurs PC 14, principales valeurs de fiches et saisie téléphone 16, section 17, titre 22/24 px |
| Espacements | Base 4 px ; contenu grand PC 28 px en haut et 32 px sur les côtés ; sous 1180 px 24/20 px ; panneaux 24 px, 16 px sur téléphone |
| Rayons | Badge 5, bouton/champ 6, panneau 8, fenêtre partagée 12 px ; composants spécialisés selon leur contrat |
| Ombres | Aucune sur les surfaces de travail, contrôles et tuiles ; profondeur réservée aux superpositions |

Le [contrat Coco Clair ERP](erp-design/DESIGN.md) précise les tokens, composants, tableaux, formulaires progressifs et historiques actuels. Sa sidecar présente les contrôles sans dépendance de framework. `src/styles/tokens.css` reste la source runtime ; `design.css` applique le thème commun après les styles de disposition. Les adaptations CRM, Achats, RH et TMS restent dans leurs styles différés. Les contrats sous `replica/design/` et les captures datées documentent les étapes antérieures ; ils ne remplacent pas la charte courante. Aucun nouvel actif graphique ni police distante n’est téléchargé.

La refonte est exclusivement visuelle. Les modules, identifiants, données, calculs, droits, actions, filtres, onglets, liens, langues et préférences existantes sont conservés. Les graphiques utilisent leurs vraies séries existantes. La navigation horizontale et le lanceur gardent leur fonctionnement ; leurs couleurs, bordures, espacements et typographie suivent la charte.

Les accents principaux sont `#157F98`, `#10677D`, `#238FA4` et `#F87826`. Les tokens de texte et fonds déterminent leur usage ; les noms historiques comme `--arc-coco-violet` sont des alias compatibles, pas une description de la couleur affichée.

**Référence d’identité du 20 octobre 2026.** Le paragraphe suivant décrit les actifs de marque approuvés ; sa mention d’une bordure de tuile appartient à cette révision. Les règles Coco Clair ci-dessus déterminent la présentation actuelle des tuiles.

La barre supérieure et le menu des applications restent blancs. Depuis le 20 octobre 2026, le menu ouvrable et la connexion affichent le logo « COCO » en bleu pétrole avec des nuances satinées, une texture brossée discrète et un léger relief lumineux, avec le O et le C centraux partiellement fusionnés et « ERP » de la même couleur, davantage espacé sous le mot. L’icône PC/smartphone reprend uniquement le monogramme CO, avec le C à gauche, le O à droite et le même écart courbé que dans le logo principal, sur une tuile blanche, sans relief ni texte. Les originaux sont conservés intacts dans `assets/brand/coco-erp-logo-approved-20261020.png` et `assets/brand/coco-erp-icon-co-approved-20261018.png`, à côté des références précédentes. `scripts/export-brand-assets.py` (Python avec Pillow) recadre uniquement les marges blanches du logo principal et ajoute 3 % de marge blanche par bord à l’icône pour les masques d’application. Le logo web mesure 1200 × 435 px. Le logo principal utilise la révision `20261020-satin` ; le manifeste, le favicon et les icônes PC/smartphone utilisent `20261018-co`, y compris dans le menu et le cache hors connexion. Les anciennes adresses `coco-gama-*` et `icon-*.png` conservent des exports compatibles. Le point de lancement PWA et son identité existante restent inchangés. Les titres d’introduction de l’accueil ont été retirés ; les tuiles gardent leur bordure fine et leur personnalisation. Une photo d’employé peut remplacer les initiales du profil.

Les rapports de contraste historiques ne doivent pas être réutilisés après une modification de couleurs : vérifier le couple texte/fond réellement calculé, y compris les surcharges du thème.

### Iconographie commune — 19 octobre 2026

La dernière référence du propriétaire, IMG_1313, remplace les pictogrammes pleins : chaque dessin présente un contour bleu pétrole #157F98, un détail orange #F87826 et un fond transparent. La grille commune mesure 24 px, avec un trait de 2 px et des jonctions légèrement adoucies. Aucune ombre, pastille ni carré décoratif n’entoure les icônes.

Le 20 octobre, les références IMG_1314 et IMG_1315 précisent deux exceptions : Agent Coco possède une tête de robot bleue compacte, deux yeux et une antenne orange ; les réglages suivent désormais IMG_1326 : deux roues simplifiées à six dents, une grande bleue et une petite orange, chacune avec un seul évidement central. Les silhouettes pleines aux angles adoucis remplacent les arcs et doubles contours pour rester lisibles à 21 px, sur la grille commune de 24 px. Ces dessins restent transparents et partagés entre les composants. La voiture de Gestion de flotte garde un toit simple, sans élément orange surélevé ; ses phares apportent la touche orange. Les étoiles de favoris sont exclusivement bleues : contour au repos, remplissage bleu lorsqu’elles sont sélectionnées. Les quatre commandes de navigation en bas du téléphone et le bouton d’ouverture du menu latéral reprennent leurs dessins monochromes d’origine, avec la grille de neuf points pour le menu.

Les 60 entrées du catalogue `src/ui/icons.js` servent à la fois aux tuiles, à la navigation latérale et mobile, aux favoris, aux indicateurs du Dashboard et des modules, aux en-têtes, aux raccourcis métier, aux paramètres, aux notifications, aux résultats de recherche et aux illustrations de remplacement des produits. `icons` fournit les deux couches SVG aux composants compacts existants ; `moduleIcon` fournit le SVG complet du même dessin. Les couches bleu/orange sont explicites, sans coloration arbitraire du dernier élément.

La barre latérale reprend désormais les deux couleurs, conformément à cette dernière demande, qui remplace la variante grise. Les emplacements décoratifs des KPI et des vues métier perdent leur bordure, fond, rayon et ombre ; leurs alignements et les zones de clic restent en place. Les icônes des KPI mesurent 28 px et celles du menu 21 px ; les tuiles gardent leurs tailles réactives existantes. Les favoris conservent leur remplissage de sélection. Les contrôles directionnels, symboles de fermeture, états métier, graphiques et codes-barres gardent leur sens fonctionnel. Le logo de marque COCO, l’icône PWA, les photographies et le site public restent distincts de ce catalogue.

Les libellés, calculs, destinations, autorisations, focus clavier et cibles tactiles restent ceux des composants existants. Les captures du 18 octobre ci-dessous documentent l’ancienne iconographie ; le code et cette section font autorité pour les icônes actuelles.

Les tableaux restent le défaut sur PC. Sur téléphone (760 px ou moins), les listes en lecture seule utilisent des fiches si le compte n’a pas choisi de vue. Les lignes éditables, grilles de formulaire, fenêtres et tableaux explicitement exclus gardent le tableau, sauf choix explicite ou adaptation propre au module. Un choix enregistré reste prioritaire. Les cellules ont des séparateurs horizontaux fins (`--coco-row-line`) ; `--coco-column-line` est transparent dans la charte ordinaire. Les en-têtes et cellules vides restent alignés. Les grands tableaux défilent dans leur propre zone. Le choix Tuiles / Tableau reste conservé par compte et tableau (`src/ui/tables.js`). Les fiches mobiles partagées sont plates, séparées par une ligne horizontale.

Le sélecteur « Tuiles / Tableau » utilise les mêmes boutons partagés, y compris dans les tableaux historiques et les fenêtres de consultation. Leur largeur s’adapte à l’icône et au libellé traduit, sans compression ; leur hauteur minimale est de 44 px. Le contour ordinaire est discret ; le choix actif garde un fond clair et un contour pétrole. La présentation est définie dans `src/styles/ui.css` et la finition commune dans `src/styles/design.css` ; les styles de page ne redéfinissent pas ces boutons.

En mode tuiles, les valeurs de détail affichent leur intitulé de colonne (`data-col`), à gauche de la valeur, sur téléphone comme sur ordinateur. La règle des cartes réactive explicitement ces intitulés, masqués en mode tableau. Le titre de la tuile, les photos et les boutons conservent leur présentation sans intitulé supplémentaire.

L’ordre des colonnes se modifie en glissant un en-tête (souris) ou sa poignée (tactile), ou avec Alt + flèche gauche/droite sur l’en-tête/la poignée. Le menu Colonnes propose la remise à l’ordre initial. L’ordre est enregistré dans le navigateur par compte et tableau, avec les préférences existantes de colonnes masquées ; il survit au rechargement et à la pagination mais n’est pas synchronisé entre appareils. Le tri reste attaché à la clé métier d’origine. Les cellules fusionnées restent groupées : un déplacement qui couperait un groupe est refusé ; les en-têtes à plusieurs niveaux et les tableaux avec fusion verticale conservent leur structure.

Les fenêtres de consultation partagées affichent une seule action « Retour » (« Volver » / « Back »), sans doublon « Fermer ». Les formulaires conservent leur action métier et leur bouton Retour. Une confirmation explicite conserve ses deux choix. `ArcUI.dialog` reconnaît les anciens libellés de fermeture FR/ES/EN ; `dismissOnly` permet de déclarer ce comportement explicitement.

La charte commune est implémentée dans `src/styles/workspace.css`, `src/styles/workbench.css` puis `src/styles/design.css` : navigation blanche, tuiles blanches sans contour ni ombre avec leurs icônes bleu/orange, titres visibles, favoris par compte et navigation mobile Accueil/Recherche/Scanner/Plus. Toutes les familles de modules utilisent ce même traitement ; le survol emploie un fond en retrait. La première catégorie du menu des applications est « Favoris » : les modules étoilés sur l’accueil y apparaissent immédiatement, dans l’ordre de leur ajout et selon les droits du compte. Retirer une étoile retire aussi son raccourci ; les changements sont synchronisés entre les onglets du navigateur. Sans favori, une indication explique comment en ajouter. Les favoris sont aussi accessibles dans le menu mobile. L’accès au scanner conserve les droits du module. Les favoris et l’ordre personnel des modules sont indépendants.

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

Les historiques de module démarrent repliés : résumé dans une ligne utilitaire du flux normal au-dessus du travail, compact sur PC (270 px maximum) et pleine largeur sur téléphone. Un historique fermé ne réserve aucune colonne latérale. Les dossiers sélectionnés gardent leur historique ouvert sur PC ; l’historique central d’Agent Coco reste ouvert dans sa page. Les lectures, propositions, droits et commandes de focus restent ceux des composants existants.

TMS utilise sa vraie carte quotidienne, les marqueurs GPS et les filtres de tournée. La préparation et les arrêts sont à gauche de la carte sur PC. Jusqu’à 900 px, les outils et la progression deviennent compacts et la carte précède les listes longues. Tracés, attribution, confidentialité, routage et actions métier sont conservés. Agent Coco conserve l’ordre conversations récentes, message et historique central ; les cadres sont aplatis et les contrôles suivent Coco Clair.

## Parcours quotidiens — octobre 2026

La liste des devis place « Nouveau devis » et « Actualiser » près du titre et du nombre de résultats. La recherche, le statut et la vue restent visibles. Les dates, modèles et vues enregistrées sont regroupés dans « Filtres et vues enregistrées » ; un filtre de date actif ouvre ce panneau. Les modèles et l’ancien formulaire conservent leurs accès existants. Les totaux sont alignés à droite et les badges reprennent les couleurs de statut partagées, avec leur libellé.

Depuis « À traiter », ouvrir un devis ou une commande puis revenir conserve recherche, type de document, page, défilement et focus sur la ligne d’origine. Si la dernière page disparaît, la liste revient à la dernière page disponible. Cet état est en mémoire et disparaît au changement de compte. Le retour depuis la liste des devis conserve aussi le défilement et le focus ; les vues enregistrées gardent leur clé utilisateur existante.

Les barres de tableaux placent recherche, colonnes et choix de vue sur une ligne lorsque la largeur le permet ; sur téléphone, la recherche occupe toute la largeur. L’ouverture du sélecteur de colonnes conserve la place nécessaire à sa liste. L’ordre, le masquage et les préférences de vue restent gérés par le composant partagé.

Les formulaires montés par `ArcUI` conservent la validation HTML et leurs gestionnaires métier. `src/ui/form-validation.js` ajoute un message traduit près du champ invalide, conserve les indications `aria-describedby`, ouvre la section concernée et place le focus sur la première erreur. Les erreurs métier personnalisées restent celles du formulaire. Une saisie corrigée efface son erreur ; les valeurs restent en place lors d’un échec d’enregistrement.

La synthèse comptable commence par les factures clients échues, les factures fournisseurs échues et les mouvements bancaires non rapprochés. Chaque compteur ouvre la liste filtrée existante. Les droits commerciaux masquent les indicateurs non autorisés. Un compteur absent affiche « — » et n’ouvre aucune liste ; un vrai zéro reste affiché. Aucun calcul comptable ni appel supplémentaire n’est ajouté.


## Adaptation des références Odoo — 15 octobre 2026

Les références réunies pour Coco sont appliquées à la hiérarchie et à la densité des écrans, avec les couleurs et illustrations Coco. Les outils administratifs rejoignent l’en-tête partagé ; les listes gardent leurs grilles et leurs préférences. Le catalogue Produits précède désormais le formulaire : « Nouveau produit » prépare un brouillon vide et place le focus dans son nom ; modifier une ligne ouvre la même fiche préremplie.

Documents sépare les filtres dans un rail et la recherche/résultats dans une surface principale. La recherche doit rester dans `.sdLibraryContent`, car GamaTable normalise son emplacement. Les deux zones s’empilent sous 760 px. La base de connaissances réunit son arbre et l’article dans une surface de lecture. Les cartes d’opportunité, champs, en-têtes et pieds des dialogues partagés suivent les tokens harmonisés.

La spécification visuelle courante est [Coco Clair ERP](erp-design/DESIGN.md). Le [relevé Replica](../replica/recon.md) conserve les sources de référence historiques. Les sources runtime restent `src/styles/` et `src/ui/` ; les tokens documentaires ne sont pas une seconde feuille de thème à importer.

Les styles propres au pipeline CRM, à Documents et à la base de connaissances sont chargés avec leurs modules via le registre de chargement différé. Cela conserve le budget CSS de démarrage ; `config/runtime-assets.json` reste la source des assets publiés.

Sur mobile, les sélecteurs de période et de vue du Dashboard passent sur des lignes séparées lorsque leur largeur disponible devient insuffisante. Les libellés FR/ES/EN restent lisibles à 16 px, sans débordement des contrôles natifs WebKit à 320 px.

## Espace de travail horizontal — 16 octobre 2026

La maquette Ventes approuvée est adaptée à tous les modules par `src/styles/workbench.css` et `src/ui/shell.js`. Le contenu utilise toute la largeur. Le lanceur ouvre un menu de modules avec Favoris, droits et langue ; Échap et le bouton de fermeture rendent le focus au déclencheur. Le menu fermé est inerte ; ouvert, il retient le focus et rend le contenu derrière lui inerte.

La barre supérieure de 64 px sur PC et 60 px sur téléphone regroupe marque, module actif, recherche globale, notifications, configuration et compte. À partir de 1 180 px, les onglets principaux natifs se placent dans l’espace libre entre le titre et les utilitaires. Leur DOM reste dans le module : les gestionnaires, droits, sélecteurs et raccourcis restent ceux du module. Sur tablette/téléphone, les onglets défilent horizontalement dans le contenu. Les onglets secondaires, étapes TMS, kanban CRM, article Knowledge, documents, cartes et formulaires gardent leur structure métier.

L’accueil utilise une grille compacte de neuf colonnes sur ordinateur (à partir de 1180 px, y compris sur écran court), avec 24 px d’espacement horizontal et vertical, cinq sur tablette large, quatre sur tablette et trois sur téléphone jusqu’à 760 px. Les tuiles restent toujours carrées (un espace carré en flux normal, calculé par `::before` et `padding-top: 100 %`, évite les chevauchements de rangées sur Safari) : leur hauteur suit leur largeur, en portrait comme en paysage. Le bouton du module remplit ce carré en position absolue ; les libellés et icônes s’adaptent aux trois colonnes du téléphone. Les rangées utilisent Flexbox avec retour à la ligne et une largeur calculée par colonne pour éviter le calcul cyclique de hauteur de CSS Grid dans WebKit lors des redimensionnements ; sur un écran court, la page défile plutôt que d’aplatir les tuiles. Les icônes, marges et espaces conservent leurs adaptations par taille d’écran. Les libellés restent complets, et les favoris, l’ordre personnel et les droits restent identiques. Sur un écran très court ou avec un zoom important, le contenu conserve sa hauteur lisible et peut défiler, sans masquer de module.

Les surfaces de travail sont blanches et plates, avec des panneaux de 8 px de rayon et des listes sans cadre périphérique. Les lignes horizontales et les références restent lisibles ; les commandes communes conservent leur cible de 44 px. Les champs, états, focus et couleurs s’appuient sur les tokens Coco.

Ventes regroupe création, titre, recherche et pagination dans une barre de commande. Les destinations secondaires restent visibles ; les filtres, vues enregistrées et contrôles de tableau sont dépliables sur téléphone, ouverts sur ordinateur. Les filtres appliqués, la pagination serveur, le retour au devis, le choix tableau/tuiles et les clés de préférence restent compatibles. Le site public et les documents imprimés ne sont pas concernés.

Les contrôles de navigation et de mise en page vivent dans `tests/workbench-layout.spec.js`, `tests/architect-shell.spec.js`, `tests/responsive-layout.spec.js` et `tests/ux-workspace.spec.js`. Les tests utilisent uniquement les fixtures locales.


## Affinement UI/UX Pro Max — quatre références du 18 octobre 2026

Le modèle général est un espace de travail minimal : Inter locale, toile et surfaces blanches, bleu pétrole pour la navigation et les liens, orange pour les actions. Coco Clair emploie des surfaces plates et un voile de fenêtre sans flou. Aucun fond photographique ni bruit bitmap ne gêne la lecture. Les préférences de réduction du mouvement et de transparence sont respectées.

`ArcUI.metricIcon(name)` fournit le pictogramme décoratif partagé des KPI. Les compteurs RH, CRM, Stock, Achats, Comptabilité, Flotte et Projets réutilisent la même composition : icône de 34 px, libellé de 13 px, chiffre tabulaire de 22–28 px et détails de 12 px. Les valeurs, sources et calculs sont inchangés. Sur téléphone, icône et texte s’empilent sans réduire les champs sous 16 px.

Les tableaux gardent des séparateurs horizontaux fins : en-têtes communs de 12 px, principales valeurs PC de 14 px et valeurs de fiches mobiles de 16 px. Les contrôles communs conservent une hauteur minimale de 44 px ; les tableaux spécialisés gardent leur densité propre. Les badges compacts conservent leur état écrit et leurs couleurs sémantiques. Kanban et progression réutilisent les mêmes surfaces ; retard et cible de dépôt restent distingués.

Les graphiques existants utilisent les dégradés pétrole/orange centralisés. Leurs axes, valeurs exactes, alternatives en tableau, exports et liens restent les mêmes, y compris dans la vue agrandie. Aucun indicateur fictif n’est ajouté.

Le texte blanc est conservé sur les boutons orange. La nuance unie des actions est distincte de l’orange du logo ; son survol est plus sombre. Vérifier les couples calculés dans les composants actuels. Les rapports de contraste de `replica/design/` restent datés et ne constituent pas un audit de chaque état de l’interface.

Les CSS des KPI personnels et de Projets se chargent avec Dashboard et Projets via `src/app/lazy-modules.js`. Cela conserve le budget de démarrage sans augmenter son plafond. Les formulaires, droits, langues, navigation et préférences des modules sont conservés.

Périmètre : application ERP. Le site `src/storefront/`, les pages publiques, leurs API et leur déploiement Cloudflare ont une charte et une publication distinctes.

### Captures historiques

Captures locales d’une révision antérieure de l’application compilée, avec données de test : [accueil PC](design/erp-home-desktop.png), [accueil téléphone](design/erp-home-mobile.png), [fenêtre commune](design/erp-dialog.png). Elles documentent cette révision et ne font pas autorité sur les tokens actuels ni sur une publication en production.

### Contraste des surfaces sur PC

La toile et les surfaces sont blanches. Les zones secondaires et en-têtes de tableau utilisent le fond en retrait ; les séparateurs restent fins. Les tuiles et KPI sont plats. Les onglets actifs utilisent un texte et un soulignement pétrole, sans fond sombre. Les contrôles gardent un contour de focus visible. Le site public suit son propre contrat.

## Contrats de mise en page de l’ERP

La structure des cartes Dashboard appartient à `src/styles/workspace.css`. Le thème `src/styles/design.css` règle les couleurs, la typographie et les surfaces, sans imposer de grille à toutes les cartes. `adMetricStandard` contient une icône et un corps ; `adMetricExecutive` empile libellé, montant et action. Les indicateurs de direction passent sur une colonne lorsque le conteneur fait au plus 600 px. Les montants et libellés restent lisibles sans débordement.

Les sélecteurs recherchables (`src/ui/select-search.js`) gardent une hauteur naturelle dans les champs en colonne et conservent le nom accessible du champ. Le seuil de huit options ne doit pas modifier la hauteur de la barre de filtres de plus que la ligne d’aide. Le select natif conserve valeur, validation et événements ; seul le contrôle visible porte le focus et le libellé.

Les libellés `data-col` générés par `src/ui/tables.js` sont recalculés à chaque changement de langue. Les libellés explicitement définis par les modules sont préservés. Dans la piste d’audit, le détail revient à la ligne dans une largeur bornée, y compris pour une chaîne sans espaces ; le tableau conserve son défilement local et ses préférences de colonnes. Sur ordinateur, replier son historique déplace le résumé au-dessus du tableau et lui rend toute la largeur disponible ; rouvrir rétablit les deux colonnes.

Les métadonnées utilisent `--coco-muted`, avec un contraste minimal de 4,5:1 sur le fond de travail. Les commandes de dépliage, favoris et options de colonnes ont une cible tactile d’au moins 44 px sur téléphone et écran tactile. Sur téléphone, les étoiles restent visibles directement dans le coin supérieur droit de chaque tuile, avec une cible de 44 × 44 px ; les toucher change le favori sans ouvrir le module. Personnaliser conserve également un bouton dédié de 44 px par module. Le changement de favori est immédiat ; le bouton Enregistrer concerne les modules masqués. La grille d’accueil reste à neuf colonnes sur grand écran et trois sur téléphone.

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
| Page | Haut 28 px et côtés 32 px ; sous 1180 px haut 24 px et côtés 20 px ; contenu réductible dans sa colonne | Sous 760 px, règle commune haut 24 px et côtés 20 px, plus les zones de sécurité et la place de la navigation ; aucun défilement horizontal de la page |
| Hiérarchie | Titre dans la barre commune, action principale puis filtres et résultats | Même ordre ; commandes qui reviennent à la ligne, recherche et bouton associés |
| Tableaux | Séparateurs horizontaux, colonnes et vue conservées par compte | Fiches pour les listes en lecture seule sans préférence ; grilles éditables et fenêtres en tableau ; défilement local |
| Historique | Module replié dans une ligne utilitaire au-dessus du travail, sans rail vide ; colonne lorsqu’il est ouvert ; dossier sélectionné ouvert | Module replié dans le flux en haut ; ouverture en panneau avec fermeture et gestion du focus |
| Navigation basse | Absente | Espace réservé jusqu’à 860 px, avec zone de sécurité iOS ; aucun résumé d’historique par-dessus les boutons |
| Formulaires | Colonnes adaptées à la place disponible | Une colonne lorsque nécessaire, champs à 16 px et commandes tactiles d’au moins 44 px |
| Espacement | Échelle existante de 4 / 8 / 12 / 16 / 24 px | Même échelle ; les messages d’erreur vides ne réservent pas de rangée |
| États | Chargement, erreur, vide et données réelles dans la même structure | Même comportement, textes longs et traductions avec retour à la ligne |

Les conteneurs de page utilisent `min-width:0` : un tableau large ne peut pas
agrandir la colonne ni décaler l’en-tête. Les règles de position de l’historique
sont dans sa feuille chargée à la demande ; le budget de démarrage reste inchangé.
L’historique central d’Agent Coco reste dans le flux de sa page.

La suite `responsive-layout.spec.js` parcourt tous les modules visibles de la
fixture en 320, 360, 390, 768, 844, 1024, 1440 et 1920 px. Les suites formulaires,
fenêtres, listes métier et historiques complètent ce contrôle, notamment pour
les chevauchements avec la navigation. Les essais Chromium et WebKit émulent les
écrans ; ils ne remplacent pas un essai matériel sur iPhone ou Android.

## Accueil — tuiles inspirées du visuel GAMA

Les tuiles restent carrées avec une surface blanche unie, sans contour ni ombre, séparées par l’espace. Elles affichent uniquement le pictogramme bleu pétrole/orange existant et le nom du module. Les favoris et le réordonnancement restent disponibles. Le téléphone affiche trois tuiles par rangée, y compris à 320 px ; le grand écran conserve neuf colonnes. La navigation clavier garde un indicateur de focus visible.


### Apple Design — 21 octobre 2026

Application des fondations HIG au web, sans imposer les conventions d’une application native :
- `layout.md › Best practices` : hiérarchie stable, navigation existante et espaces sûrs conservés.
- `typography.md › Best practices` : Inter locale en premier, titres différenciés, chiffres tabulaires et champs mobiles de 16 px.
- `color.md › Inclusive color` : sélection identifiée par fond bleu clair, trait inférieur et graisse ; orange réservé aux actions principales. Les libellés de statuts restent présents.
- `accessibility.md` : focus visible, réduction du mouvement et contraste renforcé selon les préférences du système ; contrôles partagés de 44 px sur écran tactile.
- `lists-and-tables.md` : surfaces opaques, séparateurs horizontaux lisibles et défilement des grands tableaux dans leur conteneur.

Les tuiles carrées (neuf colonnes sur grand écran, trois sur téléphone), favoris et icônes restent en place. L’historique de module est progressif ; celui du dossier sélectionné reste ouvert sur PC et le central Agent Coco reste dans le flux. Le site B2B et les documents imprimés ont leurs propres styles. Le mode sombre complet n’est pas livré par cette évolution : les modules historiques nécessitent un audit dédié avant activation.

La création d’une commande fournisseur dans Achats utilise aussi une section fermée à l’arrivée. Les préparations issues du stock, d’un projet ou d’une offre fournisseur ouvrent cette section avec leurs lignes existantes ; la fermer conserve la saisie. Les erreurs de chargement de Contrats et Dépenses conservent une action Réessayer et ne deviennent pas une liste vide.
