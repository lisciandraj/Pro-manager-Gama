# Coco Premium — vérification du 29 octobre 2026

La direction reprend les surfaces claires, les arrondis et la profondeur des cinq références Geex fournies, dans les couleurs pétrole et orange de Coco. Les captures montrent le vrai code compilé avec des données de test isolées ; elles ne représentent pas les comptes réels de GAMA.

## Vérifications

- 31 tests navigateur Chromium réussis : `workbench-layout`, `responsive-layout`, `layout-audit-regressions`, `coco-clair` et `premium-design`.
- Toutes les routes visibles du profil de test sont ouvertes à 390, 768 et 1440 px ; aucun débordement horizontal, titre dupliqué ou navigation perdue. Le [rapport des modules](module-layout-coverage.json) conserve les observations.
- Les parcours de listes, formulaires, recherche, préférences, favoris, historique et retour au menu restent fonctionnels. Vérifications complémentaires à 320, 1024 px et dans les trois langues FR/ES/EN.
- Texte des actions à contraste supérieur ou égal à 4,5:1 aux extrémités du dégradé ; focus clavier, cibles de 44 px et réduction des animations vérifiés.
- Compilation reproductible ; budget initial conservé : 299 945 octets CSS sur 300 000, 14 scripts sur 15, aucune dépendance JavaScript ajoutée. Les poids ne constituent pas une mesure du temps de chargement réseau.
- Après le contrôle de publication : 35 tests Notifications, Paramètres et Coco Premium réussis. Les fenêtres apparaissent par fondu sans translation, ce qui garde leurs bords alignés pendant l'ouverture, notamment en plein écran sur téléphone.
- Vérification finale regroupée : 68 tests d'interface réussis, y compris la restauration de la liste après consultation d'un devis et le fond orange opaque sous le dégradé des actions. La position de lecture est rétablie après la mise en place de la navigation.
- Fond opaque partagé : 17 tests Surfaces/RH, Coco Premium, Coco Clair et Ventes réussis après centralisation du satin et de son fond blanc dans `--coco-surface-fill`.

Le détecteur Impeccable a été exécuté une fois. Ses avis de palette, rayon et taille comparent par défaut le `DESIGN.md` racine du storefront ; l’autorité ERP est `docs/erp-design/DESIGN.md`. Inter locale est conservée pour l’interface de gestion. Les anciens rails de statut signalés sont des règles historiques, supprimées lorsqu’elles étaient redondantes ou remplacées dans les styles CRM différés. Les états métier gardent leurs libellés.

## Captures

| Surface | Ordinateur | Téléphone |
| --- | --- | --- |
| Accueil | [1440 px](screens/mainmenu-1440.png) | [390 px](screens/mainmenu-390.png) |
| Dashboard | [1440 px](screens/dashboard-1440.png) | [390 px](screens/dashboard-390.png) |
| Documents / Ventes | [Documents](screens/documents-1440.png) | [Ventes](screens/quotes-390.png) |

La [planche de composants](components.html) utilise les CSS compilés du dépôt. Les vérifications locales couvrent Chromium et des dimensions de smartphone, sans test physique d’iPhone. La CI responsive est également configurée pour WebKit. Les fixtures générales couvrent certains modules en état vide ou erreur/réessai, sans prétendre couvrir toutes leurs données métier.
