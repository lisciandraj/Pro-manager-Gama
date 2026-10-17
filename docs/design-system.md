# Charte graphique actuelle

Coco ERP utilise le thème bleu pétrole et orange inspiré de GAMA depuis le 29 septembre 2026. Les anciennes palettes violet/bleu robot sont conservées uniquement dans l’historique.

| Élément | Source actuelle |
| --- | --- |
| Tokens globaux | `src/styles/tokens.css` |
| Ajustements du thème et surfaces | `src/styles/design.css`, `src/styles/workspace.css`, puis `src/styles/workbench.css` |
| Accueil | `src/styles/home.css`, `src/ui/home-menu.js` |
| Lanceur, menu des applications et barre supérieure | `src/styles/shell.css`, `src/ui/shell.js` |
| Icônes vectorielles des modules | `src/ui/icons.js` |
| Logo de marque | `coco-erp-logo.png` |
| Icône C pour smartphone/PC | `coco-erp-icon-180/192/512.png`, variantes maskable, `favicon.ico` |
| Variantes d’export de marque | `assets/brand/` |

Les accents principaux sont `#157F98`, `#10677D`, `#238FA4` et `#F87826`. Les tokens de texte et fonds déterminent leur usage ; les noms historiques comme `--arc-coco-violet` sont des alias compatibles, pas une description de la couleur affichée.
La barre supérieure et le menu des applications restent blancs. Depuis le 17 octobre 2026, le menu ouvrable et la connexion affichent le logo approuvé « COCO » bleu pétrole en relief et dégradé, avec le O et le C centraux partiellement fusionnés et « ERP » en bleu. L’original est conservé intact dans `assets/brand/coco-erp-logo-approved-20261017.png`, à côté des références précédentes du 16 octobre. `scripts/export-brand-assets.py` (Python avec Pillow) produit les formats web sans redessiner les images ; seul le blanc autour du logo principal est recadré. Le logo web mesure 1 132 × 427 px et porte la révision `20261017-relief-logo`, y compris dans le cache hors connexion. L’icône approuvée du 16 octobre reste un seul C bleu pétrole avec lumière et ombre sur une tuile blanche ; elle apparaît dans la barre supérieure à toutes les largeurs, le favicon et les installations PC/smartphone. Les anciennes adresses `coco-gama-*` et `icon-*.png` conservent des exports compatibles. Le point de lancement PWA existant reste inchangé pour conserver l’identité des installations. Les titres d’introduction de l’accueil ont été retirés ; les tuiles gardent leur bordure fine et leur personnalisation. Une photo d’employé peut remplacer les initiales du profil.

Les rapports de contraste historiques ne doivent pas être réutilisés après une modification de couleurs : vérifier le couple texte/fond réellement calculé, y compris les surcharges du thème.

Les tableaux utilisent la vue tableau par défaut. Le stock, la liste des devis et la file Ventes « À traiter » ouvrent des fiches sur téléphone (760 px ou moins) si le compte n’a pas déjà choisi une vue ; un choix enregistré reste prioritaire. Les cellules possèdent des bordures horizontales et verticales visibles (`--arc-table-grid` dans `src/ui/components.css`) ; les en-têtes et cellules vides gardent leur alignement. Les grands tableaux défilent dans leur propre zone. Le sélecteur permet toujours un choix explicite des cartes, conservé par compte et tableau (`src/ui/tables.js`).

Le sélecteur « Tuiles / Tableau » utilise partout les mêmes boutons à contour bleu, y compris dans les tableaux historiques et les fenêtres de consultation. Leur largeur s’adapte à l’icône et au libellé traduit, sans compression ; leur hauteur minimale est de 44 px. Le choix actif garde un fond bleu clair et un contour renforcé. La présentation partagée est définie dans `src/styles/ui.css` ; les styles de page ne redéfinissent pas ces boutons.

En mode tuiles, les valeurs de détail affichent leur intitulé de colonne (`data-col`), à gauche de la valeur, sur téléphone comme sur ordinateur. La règle des cartes réactive explicitement ces intitulés, masqués en mode tableau. Le titre de la tuile, les photos et les boutons conservent leur présentation sans intitulé supplémentaire.

L’ordre des colonnes se modifie en glissant un en-tête (souris) ou sa poignée (tactile), ou avec Alt + flèche gauche/droite sur l’en-tête/la poignée. Le menu Colonnes propose la remise à l’ordre initial. L’ordre est enregistré dans le navigateur par compte et tableau, avec les préférences existantes de colonnes masquées ; il survit au rechargement et à la pagination mais n’est pas synchronisé entre appareils. Le tri reste attaché à la clé métier d’origine. Les cellules fusionnées restent groupées : un déplacement qui couperait un groupe est refusé ; les en-têtes à plusieurs niveaux et les tableaux avec fusion verticale conservent leur structure.

Les fenêtres de consultation partagées affichent une seule action « Retour » (« Volver » / « Back »), sans doublon « Fermer ». Les formulaires conservent leur action métier et leur bouton Retour. Une confirmation explicite conserve ses deux choix. `ArcUI.dialog` reconnaît les anciens libellés de fermeture FR/ES/EN ; `dismissOnly` permet de déclarer ce comportement explicitement.

Les maquettes approuvées sont implémentées dans `src/styles/workspace.css` : navigation blanche, tuiles à fond blanc avec leurs icônes bleu/orange et une bordure fine bleue uniforme (`#B6DCE5`), titres visibles, favoris par compte, et navigation mobile Accueil/Recherche/Scanner/Plus. Toutes les familles de modules utilisent le même contour, y compris au survol (`#88BCC9`). La première catégorie du menu des applications est « Favoris » : les modules étoilés sur l’accueil y apparaissent immédiatement, dans l’ordre de leur ajout et selon les droits du compte. Retirer une étoile retire aussi son raccourci ; les changements sont synchronisés entre les onglets du navigateur. Sans favori, une indication explique comment en ajouter. Les favoris sont aussi accessibles dans le menu mobile. L’accès au scanner conserve les droits du module. Les favoris et l’ordre personnel des modules sont indépendants.

Le Dashboard présente les indicateurs du profil, le graphique, les actions du jour et cinq commandes récentes. Son en-tête conserve la flèche de retour au menu partagée avec les autres modules, sur ordinateur et téléphone. Les vues favorites, indicateurs personnels et analyses détaillées restent accessibles dans des sections dépliables. Les commandes récentes sont une lecture limitée soumise aux mêmes droits, annulée visuellement lors d’un changement de compte ou de période.

Le stock conserve les calculs serveur : physique, réservé et disponible sont distincts. Six colonnes principales ouvrent un inspecteur avec les autres valeurs et emplacements. Les filtres avancés restent accessibles sans charger les onglets secondaires. La commande affiche huit étapes issues des données disponibles, ses lignes et une prochaine action réutilisant le bouton métier existant. Dans Suivi de processus, l’encadré orange « Prochaine action » reprend l’illustration partagée du module de sa première action accessible, issue du registre et de `ArcUI.moduleIcon`, avec les mêmes couleurs bleu/orange. L’icône suit donc la destination du bouton, y compris les onglets Commandes et Factures/encaissements ; les demandes client reprennent Ventes, et le parcours des retours reprend Retours. Sans action accessible, le pictogramme de Suivi de processus sert de repère ; un processus terminé conserve sa coche verte. Une preuve de livraison ne devient pas validée à partir du seul statut d’expédition.

Le SRI filtre les états fiscaux à la source avec pagination ; les onglets de traitement consultent les émissions liées à leurs factures. L’inspecteur distingue état interne et autorisation fiscale ; les contrôles ne deviennent verts qu’après la vérification API effective. XML/RIDE nécessitent une autorisation. Les envois groupés conservent les confirmations, droits et contrôles de non-réémission.

La réception mobile présente Quantités/Photo/Signature. Le bouton de sauvegarde attend les quantités cohérentes, le nom et la signature pour une réception acceptée, le motif d’incident, et la photo obligatoire si des unités manquent. La validation serveur et le fonctionnement hors connexion sont conservés.

Les trois références du 11 octobre 2026 précisent ces écrans : Dashboard avec en-tête compact et cartes à icônes circulaires, commande en deux colonnes sous huit étapes, SRI avec cinq colonnes principales et contrôle avant envoi. La première catégorie Favoris est conservée ; le logo suit la sélection approuvée du 17 octobre décrite ci-dessus.

Le dossier de commande possède de vrais onglets Détails, Documents et Historique, utilisables au clavier. Le bandeau client regroupe livraison planifiée, emplacements réservés et paiement confirmé lorsqu’ils existent. Les valeurs absentes restent explicitement indisponibles. L’action métier principale est déplacée dans l’en-tête, avec son gestionnaire existant ; Télécharger produit un CSV de ses lignes après contrôle du droit d’export. La prochaine action et les trois événements récents sont à droite, l’historique complet dans son onglet. Les détails opérationnels restent dépliables. Sur téléphone, les étapes passent à deux colonnes et la prochaine action précède les lignes.

Les outils de tableau partagés acceptent un hôte de barre facultatif via `data-gama-toolbar-host`, limité à la même section. SRI l’utilise pour placer le sélecteur de colonnes dans la barre supérieure sans recopier ses gestionnaires ni ses préférences. Les aperçus courts du Dashboard et de la commande masquent la barre de recherche secondaire ; leurs tableaux et tris restent fonctionnels.


## Parcours quotidiens — octobre 2026

La liste des devis place « Nouveau devis » et « Actualiser » près du titre et du nombre de résultats. La recherche, le statut et la vue restent visibles. Les dates, modèles et vues enregistrées sont regroupés dans « Filtres et vues enregistrées » ; un filtre de date actif ouvre ce panneau. Les modèles et l’ancien formulaire conservent leurs accès existants. Les totaux sont alignés à droite et les badges reprennent les couleurs de statut partagées, avec leur libellé.

Depuis « À traiter », ouvrir un devis ou une commande puis revenir conserve recherche, type de document, page, défilement et focus sur la ligne d’origine. Si la dernière page disparaît, la liste revient à la dernière page disponible. Cet état est en mémoire et disparaît au changement de compte. Le retour depuis la liste des devis conserve aussi le défilement et le focus ; les vues enregistrées gardent leur clé utilisateur existante.

Les barres de tableaux placent recherche, colonnes et choix de vue sur une ligne lorsque la largeur le permet ; sur téléphone, la recherche occupe toute la largeur. L’ouverture du sélecteur de colonnes conserve la place nécessaire à sa liste. L’ordre, le masquage et les préférences de vue restent gérés par le composant partagé.

Les formulaires montés par `ArcUI` conservent la validation HTML et leurs gestionnaires métier. `src/ui/form-validation.js` ajoute un message traduit près du champ invalide, conserve les indications `aria-describedby`, ouvre la section concernée et place le focus sur la première erreur. Les erreurs métier personnalisées restent celles du formulaire. Une saisie corrigée efface son erreur ; les valeurs restent en place lors d’un échec d’enregistrement.

La synthèse comptable commence par les factures clients échues, les factures fournisseurs échues et les mouvements bancaires non rapprochés. Chaque compteur ouvre la liste filtrée existante. Les droits commerciaux masquent les indicateurs non autorisés. Un compteur absent affiche « — » et n’ouvre aucune liste ; un vrai zéro reste affiché. Aucun calcul comptable ni appel supplémentaire n’est ajouté.


## Adaptation des références Odoo — 15 octobre 2026

Les références réunies pour Coco sont appliquées à la hiérarchie et à la densité des écrans, avec les couleurs et illustrations Coco. Les outils administratifs rejoignent l’en-tête partagé ; les listes gardent leurs grilles et leurs préférences. Le catalogue Produits précède désormais le formulaire : « Nouveau produit » prépare un brouillon vide et place le focus dans son nom ; modifier une ligne ouvre la même fiche préremplie.

Documents sépare les filtres dans un rail et la recherche/résultats dans une surface principale. La recherche doit rester dans `.sdLibraryContent`, car GamaTable normalise son emplacement. Les deux zones s’empilent sous 760 px. La base de connaissances réunit son arbre et l’article dans une surface de lecture. Les cartes d’opportunité, champs, en-têtes et pieds des dialogues partagés suivent les tokens harmonisés.

Les spécifications, sources de référence et critères de vérification sont dans [le relevé Replica](../replica/recon.md) et [le contrat des composants](../replica/design/components.md). Les sources runtime restent `src/styles/` et `src/ui/` ; les tokens de référence ne sont pas une seconde feuille de thème à importer.

Les styles propres au pipeline CRM, à Documents et à la base de connaissances sont chargés avec leurs modules via le registre de chargement différé. Cela conserve le budget CSS de démarrage ; `config/runtime-assets.json` reste la source des assets publiés.

Sur mobile, les sélecteurs de période et de vue du Dashboard passent sur des lignes séparées lorsque leur largeur disponible devient insuffisante. Les libellés FR/ES/EN restent lisibles à 16 px, sans débordement des contrôles natifs WebKit à 320 px.

## Espace de travail horizontal — 16 octobre 2026

La maquette Ventes approuvée est adaptée à tous les modules par `src/styles/workbench.css` et `src/ui/shell.js`. Le contenu utilise toute la largeur. Le lanceur ouvre un menu de modules avec Favoris, droits et langue ; Échap et le bouton de fermeture rendent le focus au déclencheur. Le menu fermé est inerte ; ouvert, il retient le focus et rend le contenu derrière lui inerte.

La barre supérieure de 60 px regroupe marque, module actif, recherche globale, notifications, configuration et compte. À partir de 1 180 px, les onglets principaux natifs se placent dans l’espace libre entre le titre et les utilitaires. Leur DOM reste dans le module : les gestionnaires, droits, sélecteurs et raccourcis restent ceux du module. Sur tablette/téléphone, les onglets défilent horizontalement dans le contenu. Les onglets secondaires, étapes TMS, kanban CRM, article Knowledge, documents, cartes et formulaires gardent leur structure métier.

L’accueil utilise une grille compacte de six colonnes sur ordinateur, cinq sur tablette large, quatre sur tablette et trois sur téléphone. La hauteur des tuiles tient compte de la hauteur d’écran et des 24 modules du registre ; les icônes, marges et espaces sont réduits pour éviter le défilement aux dimensions usuelles. Les libellés restent complets, et les favoris, l’ordre personnel et les droits restent identiques. Sur un écran très court ou avec un zoom important, le contenu conserve sa hauteur lisible et peut défiler, sans masquer de module.

Les surfaces de travail sont blanches, sans ombre lourde, avec rayons de 6 px. Le quadrillage et les références restent lisibles ; les boutons de ligne sont compacts sur ordinateur, les cibles tactiles conservent 44 px. Les champs, états, focus et couleurs s’appuient sur les tokens Coco existants.

Ventes regroupe création, titre, recherche et pagination dans une barre de commande. Les destinations secondaires restent visibles ; les filtres, vues enregistrées et contrôles de tableau sont dépliables sur téléphone, ouverts sur ordinateur. Les filtres appliqués, la pagination serveur, le retour au devis, le choix tableau/tuiles et les clés de préférence restent compatibles. Le site public et les documents imprimés ne sont pas concernés.

Les contrôles de navigation et de mise en page vivent dans `tests/workbench-layout.spec.js`, `tests/architect-shell.spec.js`, `tests/responsive-layout.spec.js` et `tests/ux-workspace.spec.js`. Les tests utilisent uniquement les fixtures locales.
