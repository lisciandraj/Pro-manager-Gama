# Charte graphique actuelle

Coco ERP applique la direction Geex / GAMA approuvée le 30 octobre 2026 : toile lavande claire, panneaux blancs, ombres discrètes, Poppins locale et navigation latérale flottante sur PC. L’orange et le bleu pétrole GAMA conservent l’identité du produit. Le contrat normatif est [Geex / GAMA ERP](erp-design/DESIGN.md), accompagné de `erp-design/.impeccable/design.json`. Les fichiers `DESIGN.md` et `.impeccable/design.json` à la racine concernent exclusivement le site public GAMA. La reconstruction est écrite depuis les captures fournies ; aucun fichier Figma ni source Geex n’a été importé.

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
| Fond / surfaces | Toile #F4F3F8 ; surface #FFFFFF ; fond en retrait #F0EFF5 ; sans texture ni satin |
| Texte / secondaire | #29283D / #686779 |
| Marque | Bleu pétrole #157F98, lien #10677D, orange #F87826 |
| Action principale | Dégradé #BD4E09 → #B54708, texte blanc #FFFFFF ; marque #F87826 conservée |
| Bordures | Lignes #E9E7F0 ; lignes de tableau #ECEAF2 ; saisie #7B8797 ; pas de quadrillage vertical ordinaire |
| Police | Poppins locale 400, 500, 600 ; Inter locale et polices système en repli ; licence `fonts/Poppins-OFL.txt` |
| Échelle | Métadonnées 12, cellules PC 13, corps 14, valeurs de fiche et saisie mobile 16, section 17, contenu 24, titre du bandeau 26/23/18 px selon largeur |
| Espacements | Base 4 px ; contenu PC haut 18, gauche 36, droite 42 px ; tablette côtés 24 px ; téléphone haut 16 et côtés 14 px (12 px jusqu’à 359 px), plus zones de sécurité ; panneaux 24/16 px |
| Rayons | Badge 9, bouton/champ 12, panneau 22 (14 sur téléphone), fenêtre et cadre latéral 28 px ; composants spécialisés selon leur contrat |
| Ombres | Surface très légère, survol interactif, superposition ; aucun reflet satiné ni ombre imbriquée |

Le [contrat Geex / GAMA ERP](erp-design/DESIGN.md) précise les tokens, composants, tableaux, formulaires progressifs et historiques actuels. Sa sidecar présente les contrôles sans dépendance de framework. `src/styles/tokens.css` reste la source runtime ; `design.css` applique le thème commun après les styles de disposition. Les adaptations CRM, Achats, RH et TMS restent dans leurs styles différés. Les contrats sous `replica/design/` et les captures datées documentent les étapes antérieures ; ils ne remplacent pas la charte courante. Les polices Poppins sont livrées localement ; aucune police distante n’est requise au rendu.

La refonte est exclusivement visuelle. Les modules, identifiants, données, calculs, droits, actions, filtres, onglets, liens, langues et préférences existantes sont conservés. Les graphiques utilisent leurs vraies séries existantes. Le menu conserve ses destinations, droits, favoris et langues ; il devient permanent sur PC à partir de 1180 px et reste un tiroir accessible en dessous. Les onglets natifs demeurent dans le contenu.

Les accents principaux sont `#157F98`, `#10677D`, `#238FA4` et `#F87826`. Les tokens de texte et fonds déterminent leur usage ; les noms historiques comme `--arc-coco-violet` sont des alias compatibles, pas une description de la couleur affichée.

**Référence d’identité du 20 octobre 2026.** Le paragraphe suivant décrit les actifs de marque approuvés ; sa mention d’une bordure de tuile appartient à cette révision. Les règles Geex / GAMA ci-dessus déterminent la présentation actuelle des tuiles.

Depuis le 20 octobre 2026, le menu ouvrable et la connexion affichent le logo « COCO » en bleu pétrole avec des nuances satinées, une texture brossée discrète et un léger relief lumineux, avec le O et le C centraux partiellement fusionnés et « ERP » de la même couleur, davantage espacé sous le mot. L’icône PC/smartphone reprend uniquement le monogramme CO, avec le C à gauche, le O à droite et le même écart courbé que dans le logo principal, sur une tuile blanche, sans relief ni texte. Les originaux sont conservés intacts dans `assets/brand/coco-erp-logo-approved-20261020.png` et `assets/brand/coco-erp-icon-co-approved-20261018.png`, à côté des références précédentes. `scripts/export-brand-assets.py` (Python avec Pillow) recadre uniquement les marges blanches du logo principal et ajoute 3 % de marge blanche par bord à l’icône pour les masques d’application. Le logo web mesure 1200 × 435 px. Le logo principal utilise la révision `20261020-satin` ; le manifeste, le favicon et les icônes PC/smartphone utilisent `20261018-co`, y compris dans le menu et le cache hors connexion. Les anciennes adresses `coco-gama-*` et `icon-*.png` conservent des exports compatibles. Le point de lancement PWA et son identité existante restent inchangés. Les titres d’introduction de l’accueil ont été retirés ; la personnalisation des tuiles est conservée. Le traitement sans contour de la direction du 30 octobre remplace leur bordure fine antérieure. Une photo d’employé peut remplacer les initiales du profil.

Les rapports de contraste historiques ne doivent pas être réutilisés après une modification de couleurs : vérifier le couple texte/fond réellement calculé, y compris les surcharges du thème.

### Iconographie commune — 19 octobre 2026

La dernière référence du propriétaire, IMG_1313, remplace les pictogrammes pleins : chaque dessin présente un contour bleu pétrole #157F98, un détail orange #F87826 et un fond transparent. La grille commune mesure 24 px, avec un trait de 2 px et des jonctions légèrement adoucies. Aucune ombre, pastille ni carré décoratif n’entoure les icônes.

Le 20 octobre, les références IMG_1314 et IMG_1315 précisent deux exceptions : Agent Coco possède une tête de robot bleue compacte, deux yeux et une antenne orange ; les réglages suivent désormais IMG_1326 : deux roues simplifiées à six dents, une grande bleue et une petite orange, chacune avec un seul évidement central. Les silhouettes pleines aux angles adoucis remplacent les arcs et doubles contours pour rester lisibles à 21 px, sur la grille commune de 24 px. Ces dessins restent transparents et partagés entre les composants. La voiture de Gestion de flotte garde un toit simple, sans élément orange surélevé ; ses phares apportent la touche orange. Les étoiles de favoris sont exclusivement bleues : contour au repos, remplissage bleu lorsqu’elles sont sélectionnées. Les quatre commandes de navigation en bas du téléphone et le bouton d’ouverture du menu latéral reprennent leurs dessins monochromes d’origine, avec la grille de neuf points pour le menu.

Les 60 entrées du catalogue `src/ui/icons.js` servent à la fois aux tuiles, à la navigation latérale et mobile, aux favoris, aux indicateurs du Dashboard et des modules, aux en-têtes, aux raccourcis métier, aux paramètres, aux notifications, aux résultats de recherche et aux illustrations de remplacement des produits. `icons` fournit les deux couches SVG aux composants compacts existants ; `moduleIcon` fournit le SVG complet du même dessin. Les couches bleu/orange sont explicites, sans coloration arbitraire du dernier élément.

La direction du 30 octobre remplace le traitement latéral précédent : les icônes sont grises au repos et retrouvent le pétrole et l’orange sur la destination active. Les tuiles conservent les pictogrammes bicolores. Les emplacements décoratifs des KPI et des vues métier perdent leur bordure, fond, rayon et ombre ; leurs alignements et les zones de clic restent en place. Les icônes des KPI mesurent 28 px et celles du menu 21 px ; les tuiles gardent leurs tailles réactives existantes. Les favoris conservent leur remplissage de sélection. Les contrôles directionnels, symboles de fermeture, états métier, graphiques et codes-barres gardent leur sens fonctionnel. Le logo de marque COCO, l’icône PWA, les photographies et le site public restent distincts de ce catalogue.

Les libellés, calculs, destinations, autorisations, focus clavier et cibles tactiles restent ceux des composants existants. Les captures du 18 octobre ci-dessous documentent l’ancienne iconographie ; le code et cette section font autorité pour les icônes actuelles.

Les tableaux restent le défaut sur PC. Sur téléphone (760 px ou moins), les listes en lecture seule utilisent des fiches si le compte n’a pas choisi de vue. Les lignes éditables, grilles de formulaire, fenêtres et tableaux explicitement exclus gardent le tableau, sauf choix explicite ou adaptation propre au module. Un choix enregistré reste prioritaire. Les cellules ont des séparateurs horizontaux fins (`--coco-row-line`) ; `--coco-column-line` est transparent dans la charte ordinaire. Les en-têtes et cellules vides restent alignés. Les grands tableaux défilent dans leur propre zone. Le choix Tuiles / Tableau reste conservé par compte et tableau (`src/ui/tables.js`). Les fiches mobiles partagées sont des surfaces blanches de 14 px de rayon, espacées de 12 px, avec 16 px de marge intérieure.

Le sélecteur « Tuiles / Tableau » utilise les mêmes boutons partagés, y compris dans les tableaux historiques et les fenêtres de consultation. Leur largeur s’adapte à l’icône et au libellé traduit, sans compression ; leur hauteur minimale est de 44 px. Le contour ordinaire est discret ; le choix actif garde un fond clair et un contour pétrole. La présentation est définie dans `src/styles/ui.css` et la finition commune dans `src/styles/design.css` ; les styles de page ne redéfinissent pas ces boutons.

En mode tuiles, les valeurs de détail affichent leur intitulé de colonne (`data-col`), à gauche de la valeur, sur téléphone comme sur ordinateur. La règle des cartes réactive explicitement ces intitulés, masqués en mode tableau. Le titre de la tuile, les photos et les boutons conservent leur présentation sans intitulé supplémentaire.

L’ordre des colonnes se modifie en glissant un en-tête (souris) ou sa poignée (tactile), ou avec Alt + flèche gauche/droite sur l’en-tête/la poignée. Le menu Colonnes propose la remise à l’ordre initial. L’ordre est enregistré dans le navigateur par compte et tableau, avec les préférences existantes de colonnes masquées ; il survit au rechargement et à la pagination mais n’est pas synchronisé entre appareils. Le tri reste attaché à la clé métier d’origine. Les cellules fusionnées restent groupées : un déplacement qui couperait un groupe est refusé ; les en-têtes à plusieurs niveaux et les tableaux avec fusion verticale conservent leur structure.

Les fenêtres de consultation partagées affichent une seule action « Retour » (« Volver » / « Back »), sans doublon « Fermer ». Les formulaires conservent leur action métier et leur bouton Retour. Une confirmation explicite conserve ses deux choix. `ArcUI.dialog` reconnaît les anciens libellés de fermeture FR/ES/EN ; `dismissOnly` permet de déclarer ce comportement explicitement.

La charte commune est implémentée dans `src/styles/workspace.css`, `src/styles/workbench.css` puis `src/styles/design.css` : navigation blanche, tuiles blanches sans contour avec une ombre douce avec leurs icônes bleu/orange, titres visibles, favoris par compte et navigation mobile Accueil/Recherche/Scanner/Plus. Toutes les familles de modules utilisent ce même traitement ; le survol renforce légèrement la profondeur. La première catégorie du menu des applications est « Favoris » : les modules étoilés sur l’accueil y apparaissent immédiatement, dans l’ordre de leur ajout et selon les droits du compte. Retirer une étoile retire aussi son raccourci ; les changements sont synchronisés entre les onglets du navigateur. Sans favori, une indication explique comment en ajouter. Les favoris sont aussi accessibles dans le menu mobile. L’accès au scanner conserve les droits du module. Les favoris et l’ordre personnel des modules sont indépendants.

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

TMS utilise sa vraie carte quotidienne, les marqueurs GPS et les filtres de tournée. La préparation et les arrêts sont à gauche de la carte sur PC. Jusqu’à 900 px, les outils et la progression deviennent compacts et la carte précède les listes longues. Tracés, attribution, confidentialité, routage et actions métier sont conservés. Agent Coco conserve l’ordre conversations récentes, message et historique central ; les panneaux blancs et les contrôles suivent Geex / GAMA.

## Parcours quotidiens — octobre 2026

La liste des devis place « Nouveau devis » et « Actualiser » près du titre et du nombre de résultats. La recherche, le statut et la vue restent visibles. Les dates, modèles et vues enregistrées sont regroupés dans « Filtres et vues enregistrées » ; un filtre de date actif ouvre ce panneau. Les modèles et l’ancien formulaire conservent leurs accès existants. Les totaux sont alignés à droite et les badges reprennent les couleurs de statut partagées, avec leur libellé.

Depuis « À traiter », ouvrir un devis ou une commande puis revenir conserve recherche, type de document, page, défilement et focus sur la ligne d’origine. Si la dernière page disparaît, la liste revient à la dernière page disponible. Cet état est en mémoire et disparaît au changement de compte. Le retour depuis la liste des devis conserve aussi le défilement et le focus ; les vues enregistrées gardent leur clé utilisateur existante.

Les barres de tableaux placent recherche, colonnes et choix de vue sur une ligne lorsque la largeur le permet ; sur téléphone, la recherche occupe toute la largeur. L’ouverture du sélecteur de colonnes conserve la place nécessaire à sa liste. L’ordre, le masquage et les préférences de vue restent gérés par le composant partagé.

Les formulaires montés par `ArcUI` conservent la validation HTML et leurs gestionnaires métier. `src/ui/form-validation.js` ajoute un message traduit près du champ invalide, conserve les indications `aria-describedby`, ouvre la section concernée et place le focus sur la première erreur. Les erreurs métier personnalisées restent celles du formulaire. Une saisie corrigée efface son erreur ; les valeurs restent en place lors d’un échec d’enregistrement.

La synthèse comptable commence par les factures clients échues, les factures fournisseurs échues et les mouvements bancaires non rapprochés. Chaque compteur ouvre la liste filtrée existante. Les droits commerciaux masquent les indicateurs non autorisés. Un compteur absent affiche « — » et n’ouvre aucune liste ; un vrai zéro reste affiché. Aucun calcul comptable ni appel supplémentaire n’est ajouté.


## Adaptation des références Odoo — 15 octobre 2026

Les références réunies pour Coco sont appliquées à la hiérarchie et à la densité des écrans, avec les couleurs et illustrations Coco. Les outils administratifs rejoignent l’en-tête partagé ; les listes gardent leurs grilles et leurs préférences. Le catalogue Produits précède désormais le formulaire : « Nouveau produit » prépare un brouillon vide et place le focus dans son nom ; modifier une ligne ouvre la même fiche préremplie.

Documents sépare les filtres dans un rail et la recherche/résultats dans une surface principale. La recherche doit rester dans `.sdLibraryContent`, car GamaTable normalise son emplacement. Les deux zones s’empilent sous 760 px. La base de connaissances sépare désormais son arbre et son article dans deux panneaux blancs, avec un rail de 230 px et un intervalle de 30 px sur PC ; les panneaux s’empilent sur téléphone. Les cartes d’opportunité, champs, en-têtes et pieds des dialogues partagés suivent les tokens harmonisés.

La spécification visuelle courante est [Geex / GAMA ERP](erp-design/DESIGN.md). Le [relevé Replica](../replica/recon.md) conserve les sources de référence historiques. Les sources runtime restent `src/styles/` et `src/ui/` ; les tokens documentaires ne sont pas une seconde feuille de thème à importer.

Les styles propres au pipeline CRM, à Documents et à la base de connaissances sont chargés avec leurs modules via le registre de chargement différé. Cela conserve le budget CSS de démarrage ; `config/runtime-assets.json` reste la source des assets publiés.

Sur mobile, les sélecteurs de période et de vue du Dashboard passent sur des lignes séparées lorsque leur largeur disponible devient insuffisante. Les libellés FR/ES/EN restent lisibles à 16 px, sans débordement des contrôles natifs WebKit à 320 px.

## Cadre Geex / GAMA — 30 octobre 2026

La navigation latérale PC reste visible à partir de 1180 px : largeur 244 px, retrait de 16 px, rayon de 28 px et contenu principal à 276 px. En dessous, le menu est un tiroir avec Échap, focus retenu, arrière-plan inerte et retour de focus à la fermeture. Les droits, favoris, groupes et langue restent ceux du menu existant.

Le bandeau mesure au moins 112 px sur PC, 96 px sous 1180 px et 72 px jusqu’à 760 px. Il affiche un titre unique et la description traduite existante du module. La recherche globale reste complète sur PC et tablette, puis rejoint son accès mobile. Les onglets natifs restent dans le contenu, dans leur DOM d’origine, avec défilement horizontal ; ils ne sont plus épinglés dans l’en-tête.

L’accueil utilise trois colonnes jusqu’à 760 px, quatre de 761 à 860 px, cinq de 861 à 1179 px, sept de 1180 à 1439 px et neuf à partir de 1440 px. Entre 861 et 1179 px avec une hauteur au plus 700 px, il utilise six colonnes. Jusqu’à 359 px, les trois colonnes utilisent un intervalle de 6 px, un retrait de page de 12 px plus les zones de sécurité, une marge intérieure de tuile de 6 px / 2 px, des icônes de 28 px et des titres de 11 px à interligne 1,25. Les tuiles restent carrées ; Flexbox et un espace carré dans le flux évitent le calcul cyclique de hauteur dans WebKit. Les écrans courts défilent sans aplatir les tuiles. Les libellés complets, favoris et ordre personnel sont conservés.

Les surfaces blanches emploient un rayon de 22 px, réduit à 14 px sur téléphone, et une ombre très discrète. CRM et Projets placent les tâches sur des colonnes sans fond. Documents et Knowledge séparent le rail blanc de 230 px et le panneau principal par 30 px, puis s’empilent jusqu’à 760 px. Les contrôles partagés gardent leur cible de 44 px.

Ventes conserve sa barre de commande, ses filtres, sa pagination serveur, ses vues enregistrées et ses clés de préférence. Le site public et les documents imprimés ont leurs styles distincts. Les suites de navigation et de disposition utilisent uniquement des fixtures locales ; leur exécution pour cette révision est décrite dans la [vérification datée](erp-design/verification-2026-10-30.md).

## Affinement UI/UX Pro Max — quatre références du 18 octobre 2026

Les fondations fonctionnelles de cette révision sont conservées. La direction du 30 octobre remplace sa matière par Poppins locale, une toile lavande unie et des surfaces blanches sans satin. Le voile des fenêtres reste sans flou ; les préférences de réduction du mouvement et de transparence sont respectées.

`ArcUI.metricIcon(name)` fournit le pictogramme décoratif partagé des KPI. Les compteurs RH, CRM, Stock, Achats, Comptabilité, Flotte et Projets réutilisent la même composition : icône de 34 px, libellé de 13 px, chiffre tabulaire de 22–28 px et détails de 12 px. Les valeurs, sources et calculs sont inchangés. Sur téléphone, icône et texte s’empilent sans réduire les champs sous 16 px.

Les tableaux gardent des séparateurs horizontaux fins : en-têtes communs de 12 px, cellules PC de 13 px et valeurs de fiches mobiles de 16 px. Les contrôles communs conservent une hauteur minimale de 44 px ; les tableaux spécialisés gardent leur densité propre. Les badges compacts conservent leur état écrit et leurs couleurs sémantiques. Kanban et progression réutilisent les mêmes surfaces ; retard et cible de dépôt restent distingués.

Les graphiques existants utilisent les dégradés pétrole/orange centralisés. Leurs axes, valeurs exactes, alternatives en tableau, exports et liens restent les mêmes, y compris dans la vue agrandie. Aucun indicateur fictif n’est ajouté.

Le texte blanc est conservé sur les boutons orange. La nuance dégradée des actions est distincte de l’orange du logo ; son survol est plus sombre. Vérifier les couples calculés dans les composants actuels. Les rapports de contraste de `replica/design/` restent datés et ne constituent pas un audit de chaque état de l’interface.

Les CSS des KPI personnels et de Projets se chargent avec Dashboard et Projets via `src/app/lazy-modules.js`. Cela conserve le budget de démarrage sans augmenter son plafond. Les formulaires, droits, langues, navigation et préférences des modules sont conservés.

Périmètre : application ERP. Le site `src/storefront/`, les pages publiques, leurs API et leur déploiement Cloudflare ont une charte et une publication distinctes.

### Captures historiques

Captures locales d’une révision antérieure de l’application compilée, avec données de test : [accueil PC](design/erp-home-desktop.png), [accueil téléphone](design/erp-home-mobile.png), [fenêtre commune](design/erp-dialog.png). Elles documentent cette révision et ne font pas autorité sur les tokens actuels ni sur une publication en production.

### Contraste des surfaces sur PC

La toile est lavande claire et les surfaces sont blanches. Les zones secondaires utilisent le fond en retrait ; les en-têtes de tableau restent blancs et les séparateurs fins. Les tuiles et KPI portent une ombre douce. Les onglets actifs utilisent un fond clair, un contour et un libellé pétrole. Les contrôles gardent un contour de focus visible. Le site public suit son propre contrat.

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
| Page | Dès 1180 px, contenu à 276 px avec retrait haut 18, gauche 36 et droite 42 px ; sous 1180 px côtés 24 px | Jusqu’à 760 px, haut 16 et côtés 14 px (12 px jusqu’à 359 px), plus zones de sécurité ; place de la navigation basse et zones de sécurité ; aucun défilement horizontal de la page |
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

Les tuiles restent carrées avec une surface blanche, sans contour et avec une ombre douce, séparées par l’espace. Elles affichent uniquement le pictogramme bleu pétrole/orange existant et le nom du module. Les favoris et le réordonnancement restent disponibles. Le téléphone affiche trois tuiles par rangée, y compris à 320 px ; le PC utilise sept colonnes de 1180 à 1439 px et neuf à partir de 1440 px. La navigation clavier garde un indicateur de focus visible.


### Apple Design — 21 octobre 2026

Application des fondations HIG au web, sans imposer les conventions d’une application native :
- `layout.md › Best practices` : hiérarchie stable, navigation existante et espaces sûrs conservés.
- `typography.md › Best practices` : Poppins locale en premier, Inter en repli, titres différenciés, chiffres tabulaires et champs mobiles de 16 px.
- `color.md › Inclusive color` : sélection identifiée par fond bleu clair, contour et graisse ; orange réservé aux actions principales. Les libellés de statuts restent présents.
- `accessibility.md` : focus visible, réduction du mouvement et contraste renforcé selon les préférences du système ; contrôles partagés de 44 px sur écran tactile.
- `lists-and-tables.md` : surfaces opaques, séparateurs horizontaux lisibles et défilement des grands tableaux dans leur conteneur.

Les tuiles carrées (sept ou neuf colonnes sur PC, trois sur téléphone), favoris et icônes restent en place. L’historique de module est progressif ; celui du dossier sélectionné reste ouvert sur PC et le central Agent Coco reste dans le flux. Le site B2B et les documents imprimés ont leurs propres styles. Le mode sombre complet n’est pas livré par cette évolution : les modules historiques nécessitent un audit dédié avant activation.

La création d’une commande fournisseur dans Achats utilise aussi une section fermée à l’arrivée. Les préparations issues du stock, d’un projet ou d’une offre fournisseur ouvrent cette section avec leurs lignes existantes ; la fermer conserve la saisie. Les erreurs de chargement de Contrats et Dépenses conservent une action Réessayer et ne deviennent pas une liste vide.

## Autorité visuelle et vérification

Les captures Geex fournies et la demande de les reconstruire avec les couleurs GAMA font autorité pour la refonte du 30 octobre. La [fiche de surface](erp-design/.impeccable/surfaces/coco-erp.md) enregistre ce périmètre ; la [vérification du 30 octobre](erp-design/verification-2026-10-30.md) distingue les captures, mesures et contrôles exécutés. La [planche des composants](erp-design/components.html) et le [contrat de réutilisation](erp-design/DESIGN.md#reuse) suivent les sources runtime. Aucun nouveau moteur JavaScript n’est ajouté.
