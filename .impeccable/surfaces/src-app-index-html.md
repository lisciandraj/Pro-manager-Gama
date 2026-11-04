---
version: 1
slug: "src-app-index-html"
primary_target: "src/app/index.html"
related_targets: ["src/styles/tokens.css", "src/styles/design.css", "src/styles/workbench.css", "src/styles/order-followup.css", "src/styles/ui.css", "src/ui/components.css", "src/ui/tables.js", "src/styles/modules/", "src/features/"]
---

# Coco ERP — GAMA

MODE: Operate. Les équipes retrouvent leur travail, lisent les informations utiles et poursuivent une opération sous leurs droits existants.

SCOPE: Application interne servie par `src/app/index.html`, ses modules actifs, les écrans internes de configuration et les vues métier associées. Le site public `src/storefront/`, ses API et sa publication sont hors de ce périmètre.

DESIGN AUTHORITY: La demande de finition professionnelle du 4 novembre 2026 actualise la présentation ERP existante. Lire `docs/erp-design/DESIGN.md` et sa sidecar `docs/erp-design/.impeccable/design.json` pour les tokens et composants, puis `docs/design-system.md` pour les contrats d’interface et actifs approuvés. `DESIGN.md`, `PRODUCT.md` et la sidecar racine décrivent le storefront GAMA. La direction professionnelle a été fixée par le propriétaire ; il ne s’agit pas d’un nouveau seed ni d’une copie de marque tierce.

THESIS: Un espace de travail quotidien calme, lisible et efficace, où les informations utiles apparaissent plus tôt et où les champs sont visuellement groupés sans modifier les parcours métier.

OWN-WORLD: Toile neutre #F5F7F8, surfaces blanches, pétrole atténué #2F7180 et orange cuivré d’action #AF5C35 à texte blanc. Inter locale pour le travail, Poppins locale pour les titres. Rayons partagés de 8 / 12 / 16 / 20 px, ombres peu profondes, fond uni sans satin. Les couleurs brutes GAMA #157F98 / #F87826, logos, photographies et pictogrammes approuvés sont conservés.

STORY: Choisir un module, parcourir ou rechercher les données, puis agir avec les commandes existantes. Les formulaires séparent libellé et valeur, groupent les champs et gardent les détails progressifs. Les zéros, inconnus, erreurs et listes vides restent distincts.

FIRST VIEWPORT: Un retour au menu et un seul titre de module dans un bandeau de 88 px minimum sur PC, 80 px sur tablette et 72 px sur téléphone ; utilitaires natifs compacts, puis action principale, recherche et résultats ou espace spécialisé. L’historique de module démarre replié sans rail vide. Sur PC, historique fermé et Outils partagent une ligne lorsque l’en-tête le permet ; Dashboard réunit historique/filtres/outils à partir de 1280 px. Dans Devis à partir de 1180 px, l’historique fermé utilise l’extrémité droite réservée de la barre secondaire. Produits et Dashboard de 390 à 760 px partagent historique fermé et Outils, avec 140 px réservés aux traductions longues ; mois et profil Dashboard sont côte à côte, Personnaliser en dessous. Les téléphones plus étroits et historiques ouverts gardent le flux normal. Aucun contrôle n’est cloné ni déplacé dans le DOM.

FORM: Architecture ERP de gestion existante, adaptée à une direction professionnelle choisie par le propriétaire. Libellé/champ : 8 px ; rangées de formulaire : 24 px PC / 20 px téléphone ; colonnes : 24 / 16 px. Valeurs de saisie : 14 px PC / 16 px téléphone. Contrôles communs : au moins 44 px. Les listes gardent une densité distincte et les métriques spécialisées leurs dimensions dictées par le contenu.

RESPONSIVE: Barre latérale de 232 px à partir de 1180 px, tiroir accessible en dessous. Les onglets natifs restent dans leur module et défilent si nécessaire. Jusqu’à 760 px, les listes en lecture seule deviennent des fiches sans préférence enregistrée ; les grilles éditables et fenêtres gardent leurs tableaux. Préférences de vue, colonnes et ordre prioritaires. L’accueil garde neuf colonnes sur grand PC, trois sur téléphone, ses favoris et son ordre personnel. Le bandeau d’accueil téléphone ne contient pas de logo CO. La navigation basse et les zones de sécurité sont conservées.

SPECIALIZED WORKSPACES: TMS garde sa carte réelle, les événements GPS, l’attribution, la confidentialité et le routage ; outils et étapes compacts puis carte tôt sur téléphone. Agent Coco conserve conversations récentes, message et historique central dans le flux. Kanbans, articles, arbres, graphiques et éditeurs spécialisés gardent leurs structures métier. Les historiques de dossiers sélectionnés gardent leur comportement existant.

CONTENT AND CONSTRAINTS: Toutes les colonnes Produits restent disponibles, dont les 32 champs du sélecteur ; Produits et Contacts démarrent avec six champs métier, hors décorations et actions. Aucun choix compact initial n’est enregistré comme préférence. Retour masque la fiche produit sans effacer le brouillon ; un enregistrement réussi la ferme. Retour dans Stock efface la sélection et rend le focus à la liste. Garder identifiants publics, clés de stockage, traductions FR/ES/EN, données, calculs, mutations et droits serveur compatibles.

IMPLEMENTATION: Sources canoniques sous `src/`, tokens communs partagés et finitions spécialisées différées. `config/runtime-assets.json` conserve ordre CSS et adresses publiées. Les fichiers racine générés ne sont pas des sources d’édition. La composition d’historique reste dans `order-followup.css` ; le CSS initial mesuré reste à 298 874 / 300 000 octets.

QUALITY BAR: Groupement des formulaires inspiré des principes Carbon et rythme de 8 px Atlassian, avec l’identité GAMA conservée. Vérification du rendu compilé PC/téléphone, états vides et erreurs, textes longs, langues, préférences et clavier. Les captures de fixtures ne prouvent ni tous les états métier ni le comportement d’un appareil physique ; un mode sombre complet n’est pas livré.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance. La revue finale a couvert Accueil, Produits, fiche produit, Dashboard et Devis sur PC et téléphone. Les captures `.impeccable/review/` sont destinées à l’assurance qualité ; aucun raster du produit n’a été créé ni modifié par cette finition et tous les actifs sont préexistants et approuvés.
