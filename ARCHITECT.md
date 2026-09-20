# ARCHITECT ERP — interface de référence

L’application reste le site statique `lisciandraj/Pro-manager-Gama`, avec ses modules JavaScript, son authentification et sa base Supabase existants. Aucun framework, route, identifiant de module, schéma ou workflow n’est remplacé.

## Référence visuelle et logo

La maquette fournie de 1145 × 1374 pixels est la référence : sidebar d’environ 192 px, barre supérieure de 70 px, grille principale de cartes blanches compactes de 12 px de rayon. La maquette en montrait quatre par ligne ; l’accueil en place six à partir de 1280 px, pour que tous les modules tiennent sans défiler, et retombe à quatre en dessous, puis trois et deux, là où un libellé de tuile cesserait de se lire d’un coup d’œil. Couleurs relevées dans les plages uniformes de l’image : sidebar `#122E46`, sélection `#245073`, fond gris très clair (environ `#F5F7FA`). Les tableaux et champs gardent des séparateurs plus soutenus pour la lisibilité.

`architect-logo.png` est le fichier officiel fourni, copié sans transformation. SHA-256 : `a6193809eb6efcc4cfa59119d0aba3b6176d53c3fa99047691d13218dd0ceb42`. Le slogan, les couleurs et le rapport carré sont conservés. Dans la sidebar, un masque CSS cache uniquement la marge blanche extérieure du fichier, sans retoucher le logo. Il apparaît dans la sidebar, la connexion, la fiche de devis et les métadonnées d’installation. `object-fit: contain` préserve ses proportions. Les anciens identifiants techniques GAMA et les informations légales de l’entreprise sur les documents restent inchangés.

La police Inter est hébergée localement dans `fonts/`, avec sa licence OFL, pour un rendu stable sans requête externe.

## Sources partagées

- `architect-tokens.css` : couleurs, espaces, rayons, ombres et typographie. Les alias publics `--color-*`, `--radius-*`, `--shadow-*` réutilisent ces tokens.
- `architect-ui.css` : cartes, tableaux, champs, boutons, états, dialogues et notifications communs aux modules existants.
- `architect-shell.css` : sidebar, barre supérieure, profil, navigation responsive.
- `architect-home.css` : accueil, KPI, grille, activité et personnalisation.
- `architect-shell.js` : navigation depuis `GamaMenu`, recherche globale existante, déplacement des contrôles de session existants dans le menu utilisateur, indicateur actif, droits et langues.
- `gama-menu-final2.js` : registre de tous les modules existants, cartes, KPI et activité. TMS utilise désormais ce même registre ; son chargeur reste unique.

Les feuilles de la sidebar et de l’accueil remplacent les anciennes chaînes CSS injectées. Les feuilles partagées habillent les classes déjà utilisées par les modules, y compris les composants chargés tardivement. Les nouvelles préférences d’affichage restent locales au navigateur et séparées des données métier.

## En-tête de module

Chaque écran s’ouvre sur l’en-tête standard produit par `ArcUI.header()`. Il porte l’icône de son propre module : le même dessin et le même accent que la tuile qui y mène depuis le menu, pour que l’on reconnaisse d’où l’on vient.

Les deux surfaces lisent la même source, `ArcModules.registry` pour `icon` et `accent`, et `ArcUI.icons` pour le tracé. Un module qui change d’icône change des deux côtés à la fois ; il n’y a rien à tenir à jour écran par écran, et aucun fichier de module n’a été modifié pour cette uniformité.

`header()` laisse une case vide, `<span class="gamaStdIcon" data-arc-icon-slot>`, que `ArcUI.headerIcon(racine, id)` remplit. Le module est identifié dans cet ordre : `data-arc-module`, posé quand l’appelant passe `module` ; l’`id` explicite ; enfin l’`id` de la `<section>` qui contient l’en-tête, que trente-cinq écrans sur trente-sept portent déjà. `gama-tms-section` est la seule exception, traitée par un alias ; le tableau de bord passe son identifiant explicitement parce qu’il peint son en-tête lui-même.

Trois points de peinture couvrent tous les écrans : `ArcRouter.show()` pour les modules du registre, `bindBack()` dans `gama-ui.js` pour les écrans écrits à la main dans `index.html`, et l’appel propre au tableau de bord. Un en-tête relié avant d’être accroché à sa section ne sait pas encore de quel module il est : la peinture est alors relancée une fois au tick suivant.

Les titres qui commençaient par un emoji — 📦, 👥, 🚚 — le perdent dans `header()`, sinon l’écran afficherait deux icônes. Le catalogue de traduction indexe le texte sans ornement : `variant()` retire les caractères non alphanumériques de tête, donc « 📦 Productos » et « Productos » tombent sur la même ligne et aucune traduction n’est perdue.

Les teintes d’accent des tuiles du menu sont limitées à `#mainmenu`. L’en-tête a donc ses propres règles `.gamaStdIcon[data-arc-fam=…]` dans `src/ui/module-styles.css`, appuyées sur les mêmes jetons `--arc-icon-*`, sans toucher aux feuilles du menu ni à celles des réglages.

## Données de l’accueil

L’accueil ne contient aucune donnée de démonstration.

- Facturation du mois : `gama_operations_action(snapshot).metrics.invoiced`, lorsque `finance` est autorisé. Il s’agit de factures TTC, donc le libellé précise « Facturation » et « TVA incluse ».
- Commandes confirmées du mois : `metrics.orders`.
- Livraisons en retard : `metrics.late_deliveries`.
- Clients actifs : décompte exact des clients actifs, sous les droits existants.

`total` et `active_count` de cette RPC sont des compteurs d’alertes et ne doivent jamais être utilisés comme chiffre d’affaires ou commandes. Une donnée indisponible ne devient pas artificiellement zéro. Aucun taux d’évolution n’est inventé en l’absence d’une série de comparaison.

L’activité récente affiche les quatre derniers mouvements réels de l’audit de stock déjà synchronisé. Elle est réservée aux profils autorisés à consulter l’audit. Le lien ouvre l’audit complet. Il ne s’agit pas d’un journal universel de tous les modules.

## Navigation et droits

Desktop à partir de 1100 px : sidebar permanente. Tablette de 861 à 1099 px : rail d’icônes extensible. Jusqu’à 860 px : tiroir mobile, fermé hors de l’ordre de tabulation avec `inert`, ouvert au clavier avec focus maintenu dans la navigation. Échap ferme le tiroir et rend le focus au bouton.

La sidebar présente les destinations principales puis « Autres modules ». Tous les modules restent dans le registre et sur l’accueil. « Personnaliser » permet de masquer des cartes uniquement sur l’accueil ; les destinations restent accessibles dans la navigation. Les préférences sont propres au profil local et n’accordent jamais un droit d’accès.

`gama-fixed-header.js` reconnaît le conteneur Architect : il ne déplace plus les contrôles de session vers l’ancienne barre désormais invisible. Déconnexion et gestion des comptes conservent leurs événements et permissions.

Les libellés sont traduits avec le catalogue existant FR/EN/ES. Après modification, exécuter `python3 scripts/build-i18n.py`.

## Vérification

Site statique : pas de compilation, TypeScript ou lint configurés. Vérifier la syntaxe des scripts et des scripts intégrés, les assets locaux, puis les tests Node et Playwright existants. `tests/architect-reference.spec.js` couvre le logo exact, les vrais champs des KPI, les traductions, le profil, la personnalisation, les droits client et le tiroir. `tests/architect-shell.spec.js` contrôle les six largeurs demandées : 1920, 1440, 1024, 768, 430 et 390 px, dont plusieurs écrans de modules.

Les anciennes assertions imposant un fond gris foncé ont été alignées sur la nouvelle référence explicitement demandée. Les séparateurs de tableaux et les champs continuent à utiliser `--arc-line` et `--arc-line-strong` ; les bordures des cartes d’accueil utilisent le token distinct `--arc-card-border`.
