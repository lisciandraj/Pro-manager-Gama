# Charte graphique du site GAMA

État : 18 octobre 2026. Cette charte concerne le site public et son espace client commun, produits depuis `src/storefront/`. Elle ne remplace pas la charte des modules internes de Coco ERP.

## Direction visuelle

Les trois références fournies montrent une boutique sur fond blanc, de grandes photographies sur des surfaces gris clair, une typographie sobre, des filtres en pastilles, des actions arrondies et des fiches à deux colonnes. Le site reprend cette structure avec l'identité GAMA, sans reprendre le logo Shopcart, ses produits, ses avis ou ses promesses commerciales.

UI UX Pro Max a été consulté pour la composition, la hiérarchie des actions et les contrôles de lisibilité. Les résultats automatiques trop génériques ne sont pas la spécification : les références visuelles et les couleurs de la marque priment.

## Tokens partagés

Les variables sont définies dans `src/storefront/site.css`. `customer.css` les réutilise pour les écrans connectés. Les couleurs configurées dans Coco restent prioritaires.

| Rôle | Valeur par défaut | Utilisation |
| --- | --- | --- |
| Bleu pétrole | `#176072` | Identité, liens, navigation et filtres actifs |
| Orange GAMA | `#E4884F` | Accent de marque |
| Orange d'action | `#B65325` | Boutons principaux à texte blanc |
| Texte | `#182B30` | Titres et contenu principal |
| Texte secondaire | `#5E6B70` | Références, aides et informations secondaires |
| Surface | `#FFFFFF` | Page, cartes et fenêtres |
| Surface produit | `#F5F6F6` | Fonds des photos et contrôles secondaires |
| Bandeau d'accueil | `#FBF3EB` | Surface chaude discrète |
| Séparateur | `#E5E9EB` | Lignes et cadres légers |
| Typographie | Inter locale | Police variable sans téléchargement tiers |
| Arrondis | 12 px / pastille | Images et cartes / boutons et filtres |
| Espacement | 4, 8, 12, 16, 24, 32, 48, 64 px | Rythme de mise en page |
| Transition | 160 ms | Changement de couleur et de bordure |

`actionColor()` conserve les couleurs de marque et dérive séparément les fonds des contrôles à libellé blanc pour atteindre un contraste d'au moins 4,5:1. Les choix de couleurs administrés restent utilisables. Les animations sont désactivées avec `prefers-reduced-motion`.

## Composants

- En-tête blanc : logo, catégories, recherche permanente, accès entreprise et sélection de devis. Bandeau supérieur bleu pétrole.
- Accueil : catégories en premier, sur six colonnes au maximum et trois sur petit écran, sans bandeau de présentation ni section de produits mis en avant.
- Catalogue : dix colonnes à partir de 1024 px, trois sur tablette et deux sur téléphone ; surfaces photo carrées, cartes ouvertes, prix lisible et quantités existantes.
- Filtres : pastilles horizontales défilant dans leur propre conteneur. Le tri et les vues grille/liste restent disponibles.
- Fiche produit : fil de navigation descriptif, grande photo, titre, prix, quantité, caractéristiques et livraison à confirmer. Jusqu'à quatre suggestions issues des produits déjà publiés.
- Devis : produits et coordonnées à gauche, récapitulatif à droite ; une seule colonne sous 800 px. Les mentions de consentement et le comportement idempotent sont conservés.
- Espace client : même catalogue et mêmes tokens, onglets en pastilles, tableaux à séparateurs discrets et formulaires cohérents. Les favoris restent réservés aux clients connectés.
- Pages de crédits et questionnaires : chargement de la typographie et des tokens communs, contenu préservé.

## Contrats préservés

Les identifiants DOM, routes, clés de stockage, appels serveur, tarifs négociés, minimums et multiples, consentement et règles de publication restent compatibles. Le site conserve le parcours de demande de devis ; aucun paiement en ligne, avis produit ou engagement de livraison fictif n'est ajouté. Les réglages de publication dans Coco restent indépendants du déploiement des fichiers.

## Vérification

`npm run build`, `npm run build:storefront`, `npm run check:generated`, `npm run check`, `npm run typecheck`, `npm run check:docs` et `tests/storefront-server.test.mjs` vérifient la livraison. Le workflow `storefront-interface.yml` exécute les parcours existants `storefront.spec.js` et `b2b-portal.spec.js` avec leurs captures et contrôles de débordement entre 320 et 1440 px. Les données navigateur sont simulées et les tests ne créent aucune demande dans la production.

Le catalogue affiche 100 produits par page, en grille comme en liste, y compris dans la session entreprise. Quatre lots de 30 au maximum (30 + 30 + 30 + 10) respectent la limite actuelle du serveur. La navigation avance de 100 et les filtres reviennent à la première page.
