# Charte graphique du catalogue GAMA

État du code : 19 octobre 2026. Périmètre : [src/storefront](../src/storefront/), catalogue public et espace client commun. La charte des modules internes de Coco ERP reste distincte. Les tokens normatifs sont dans [DESIGN.md](../DESIGN.md), avec les composants et extensions dans [.impeccable/design.json](../.impeccable/design.json).

## Référence et identité

Le propriétaire a choisi [Grocery Website Design / Freshly, par Junaki](https://dribbble.com/shots/26664219-Grocery-Website-Design). L’adaptation reprend son en-tête compact, la recherche à extrémité orange, le ruban de catégories circulaires, les cartes blanches bordées, la photo de détail encadrée, le panneau éditorial orange pâle et le pied de page bleu pétrole. Le nom, le logo, le bleu et l’orange GAMA restent. Les photographies produits, textes espagnols et réglages administrés sont conservés.

La source visuelle actuelle est [site.css](../src/storefront/site.css), complétée par [customer.css](../src/storefront/customer.css). Inter est locale. Le bleu pétrole porte prix, actions principales et pied de page ; l’orange clair distingue la recherche et le compteur ; l’orange foncé sert notamment au focus. Les cartes sont plates, presque carrées, avec bordures fines et photos sur fond blanc. Boutons et filtres sont en pastilles. Les couleurs configurées dans Coco restent prioritaires ; `actionColor()` dérive séparément les fonds prévus pour des libellés blancs.

## Composition et adaptation

L’en-tête blanc conserve logo, catégories, recherche, accès entreprise et sélection de devis. Une seconde ligne porte les liens administrés et le téléphone lorsqu’il est renseigné. Sur téléphone, la recherche occupe sa propre ligne et le bloc téléphone disparaît.

Les catégories forment un ruban horizontal à illustrations circulaires, avec compteurs réels et flèches précédent/suivant. Le défilement reste contenu ; les flèches parcourent 90 % de la largeur visible. Les fournitures de bureau, fournitures scolaires, produits informatiques et équipements de bureau passent en tête. Cliquer filtre le catalogue. Le catalogue suit immédiatement : aucun hero ni section séparée de produits mis en avant.

| Largeur de fenêtre | Colonnes produits | Catégories visibles dans le ruban |
| --- | ---: | ---: |
| Jusqu’à 600 px | 2 | 2 |
| 601–800 px | 3 | 3 |
| 801–1000 px | 4 | 4 |
| 1001–1023 px | 5 | 5 |
| 1024–1200 px | 10 | 5 |
| Plus de 1200 px | 10 | 6 |

Les dix colonnes dès 1024 px sont un choix explicite du propriétaire. La page conserve 100 produits, en grille comme en liste et en session entreprise, livrés progressivement en lots de 30 + 30 + 30 + 10. Les filtres reviennent à la première page ; la pagination avance de 100. Les intitulés longs restent disponibles et reviennent à la ligne.

Les filtres en pastilles défilent dans leur propre conteneur. Recherche, marque, tri et vues grille/liste restent disponibles. Les cartes présentent catégorie, photo réelle, référence/marque, prix, nom complet, quantité et ajout. Les images signalées conservent « Foto ilustrativa » ; les images absentes affichent « Foto por confirmar ».

La fiche présente le titre, une photo unique encadrée de bleu pétrole et les informations à droite, puis les onglets Descripción / Información adicional et jusqu’à quatre suggestions publiées. Les onglets répondent aux flèches, à Début et à Fin. Le détail s’empile jusqu’à 600 px ; les suggestions passent de quatre à deux colonnes jusqu’à 800 px. Le formulaire de devis comporte un récapitulatif latéral et s’empile jusqu’à 800 px. L’espace client partage cette charte, avec onglets en pastilles et tableaux à défilement contenu.

Les transitions de couleur et bordure durent 180 ms ; le zoom discret d’une photo dure 300 ms. `prefers-reduced-motion` désactive les transitions et animations, et les flèches de catégories défilent immédiatement. Le focus clavier public est orange foncé ; les contrôles client utilisent le bleu pétrole. Les ombres sont réservées aux fenêtres et confirmations, pas aux cartes.

## Contrats et validation

La composition conserve les appels serveur, tarifs négociés, minimums et multiples, consentement, réessais idempotents, droits, périmètre client et règles de publication. Aucun paiement en ligne, avis, remise ou engagement de livraison n’est inventé. Les réglages de publication dans Coco restent indépendants du déploiement des fichiers.

Les sources canoniques sont [index.html](../src/storefront/index.html), [site.js](../src/storefront/site.js), [site.css](../src/storefront/site.css) et [customer.css](../src/storefront/customer.css). Les validations pertinentes restent `npm run build`, `npm run build:storefront`, `npm run check:generated`, `npm run check`, `npm run typecheck`, `npm run check:docs`, les tests du serveur storefront et les parcours navigateur storefront/B2B. Les fixtures ne créent aucune demande en production. Cette charte décrit le code ; elle ne constitue pas une attestation de déploiement.
