---
version: 1
slug: "src-app-index-html"
primary_target: "src/app/index.html"
related_targets: ["src/styles/tokens.css", "src/styles/design.css", "src/styles/workbench.css", "src/styles/ui.css", "src/ui/components.css", "src/ui/tables.js", "src/styles/modules/", "src/features/"]
---

# Coco ERP — Coco Premium

MODE: Operate. Les équipes retrouvent leur travail, lisent les informations utiles et poursuivent une opération sous leurs droits existants.

SCOPE: Application interne servie par `src/app/index.html`, ses 27 modules actifs, les écrans internes de configuration et les vues métier associées. Le site public `src/storefront/`, ses API et sa publication sont hors de ce périmètre.

DESIGN AUTHORITY: Lire `docs/erp-design/DESIGN.md` et sa sidecar `docs/erp-design/.impeccable/design.json` pour les tokens et composants de l’ERP. Le `DESIGN.md`, le `PRODUCT.md` et la sidecar à la racine décrivent le storefront GAMA ; ils ne déterminent pas le thème de l’ERP. `docs/design-system.md` précise les contrats d’interface et les actifs de marque conservés.

DIRECTION: Coco Premium reprend la hiérarchie de gestion simple et propre approuvée : bandeau horizontal, espace blanc, tableaux lisibles sur PC, fiches de consultation sur téléphone et détails progressifs. Le pétrole, l’orange et les pictogrammes Coco portent l’identité. Les références couvrent l’accueil, les 27 modules actifs et 12 écrans internes ; les données, fonctions et autorisations viennent des modules réels.

FIRST VIEWPORT: Un retour au menu, un seul titre de module, ses onglets et les utilitaires existants. Le contenu commence par son action, sa recherche et ses résultats, son indicateur utile ou son espace de travail spécialisé. Les formulaires Produits, Employé et l’inspecteur Stock apparaissent à la demande. L’historique de module démarre replié sans rail vide ; son résumé occupe une ligne utilitaire dans le flux normal au-dessus du travail, compact sur PC et pleine largeur en haut sur téléphone.

VISUAL GRAMMAR: Références Geex du 29 octobre 2026 adaptées au pétrole/orange Coco. Toile porcelaine légèrement texturée, surfaces blanches satinées, ombres multicouches définies par tokens. Panneaux 16 px (14 px sur téléphone), contrôles 10 px, fenêtres 24 px. Une action principale orange à texte blanc, liens et sélections pétrole. Inter locale, chiffres tabulaires, statuts libellés. Mouvement limité au retour de pression, favori sélectionné et superpositions ; aucune chorégraphie de chargement, respect du mouvement réduit.

RESPONSIVE: Les onglets rejoignent le bandeau à partir de 1180 px et défilent dans le module sur les autres formats. Jusqu’à 760 px, les listes en lecture seule deviennent des fiches en l’absence de choix enregistré ; les grilles éditables et fenêtres conservent leurs tableaux. Les fiches mobiles ont une surface blanche et leurs noms de champ visibles. Les préférences explicites de vue, colonnes et ordre gardent priorité. L’accueil utilise neuf colonnes sur grand écran et trois sur téléphone, avec des favoris de 44 px. La navigation inférieure conserve sa place et les zones de sécurité.

SPECIALIZED WORKSPACES: TMS garde sa vraie carte et ses événements GPS ; arrêts et préparation à gauche, carte à droite sur PC, outils et étapes compacts puis carte tôt sur téléphone. Attribution, confidentialité, filtres et routage restent fonctionnels. Agent Coco conserve conversations récentes, message et historique central dans le flux. Les kanbans, articles, arbres, graphiques et éditeurs spécialisés gardent leurs structures métier. Un historique de dossier sélectionné reste ouvert sur PC ; le central Agent Coco reste ouvert dans sa page.

CONTENT AND CONSTRAINTS: Toutes les colonnes Produits restent disponibles, dont les 32 champs du sélecteur ; Produits et Contacts démarrent avec six champs métier en plus des éléments décoratifs et actions. Aucun choix compact initial n’est enregistré comme préférence. Retour masque la fiche produit en conservant le brouillon ; un enregistrement réussi la ferme. Retour dans Stock efface la sélection et rend le focus à la liste. Les vrais zéros, valeurs inconnues, erreurs et listes vides restent distincts. Garder les identifiants publics, clés de stockage, traductions, données, calculs, mutations et droits serveur compatibles.

IMPLEMENTATION: Modifier les sources canoniques sous `src/`. Les tokens et finitions communes sont partagés ; les finitions propres à un module suivent son chargement différé. `config/runtime-assets.json` conserve l’ordre CSS et les adresses publiées. Les fichiers racine générés ne sont pas des sources d’édition.

QUALITY BAR: Vérifier le rendu compilé sur PC et téléphone, les états vides et erreurs, les textes longs, les langues, les préférences existantes et le clavier. Les références visuelles guident la composition ; les modules conservent leurs données et particularités réelles. Les captures de fixtures ne prouvent ni une identité de chaque pixel, ni tous les états métier, ni le comportement du matériel physique.
